@echo off
SETLOCAL

CD /D "%~dp0.."

SET "TMP_DIR=%TEMP%\local-env-test-%RANDOM%"
SET "RAW=%TMP_DIR%\raw.txt"
SET "OUT=%TMP_DIR%\output.txt"
SET "CONTAINERS=kafka schema-registry akhq ksqldb-server ksqldb-cli"
SET "CURL_OPTS=--silent --show-error --retry 10 --retry-delay 5 --retry-all-errors"

MKDIR "%TMP_DIR%"
CALL :main
SET "RESULT=%ERRORLEVEL%"
RMDIR /S /Q "%TMP_DIR%"
EXIT /B %RESULT%

:main
    CALL :run_test "Display help" test_help || EXIT /B 1
    CALL :run_test "Start the local environment" test_start || EXIT /B 1
    CALL :run_test "Wait for environment initialization" wait_for_initialization || EXIT /B 1
    CALL :run_test "Verify Kafka broker is ready" test_kafka_broker_ready || EXIT /B 1
    CALL :run_test "Verify Schema Registry is reachable" test_schema_registry_reachable || EXIT /B 1
    CALL :run_test "Verify ksqlDB Server is healthy" test_ksqldb_server_healthy || EXIT /B 1
    CALL :run_test "Verify AKHQ UI is reachable" test_akhq_ui_reachable || EXIT /B 1
    CALL :run_test "Display container status" test_status || EXIT /B 1
    CALL :run_test "Test seeding data" test_seed_data || EXIT /B 1
    CALL :run_test "Open ksqlDB CLI" test_ksql_cli || EXIT /B 1
    CALL :run_test "Tail logs" test_logs || EXIT /B 1
    CALL :run_test "Stop the local environment" test_stop || EXIT /B 1
    CALL :run_test "Test start failure when Docker is unavailable" test_start_without_docker || EXIT /B 1
    CALL :run_test "Test seeding data without test-data.sql" test_seed_data_without_sql_file || EXIT /B 1

    echo.
    echo All tests passed.
    EXIT /B 0

:test_help
    FOR %%C IN (help unknown-command) DO (
        CALL :run .\local-env.bat %%C
        CALL :assert_success || EXIT /B 1
        CALL :assert_output_contains "Local Environment Manager" || EXIT /B 1
        CALL :assert_output_contains "Usage: local-env [command]" || EXIT /B 1
        FOR %%S IN (start stop clean status logs ksql test-data) DO (
            CALL :assert_output_matches "  %%S  *- " || EXIT /B 1
        )
    )
    EXIT /B 0

:test_start
    CALL :run .\local-env.bat start
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_contains "Environment is up!" || EXIT /B 1
    CALL :assert_output_contains "- Kafka Broker: localhost:9092" || EXIT /B 1

    CALL :run docker compose ps --status running --services
    FOR %%C IN (%CONTAINERS%) DO (
        CALL :assert_output_line "%%C" || EXIT /B 1
    )
    EXIT /B 0

:wait_for_initialization
    CALL :sleep 30
    EXIT /B 0

:test_kafka_broker_ready
    CALL :run docker exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic test-topic --partitions 1 --replication-factor 1
    CALL :assert_success || EXIT /B 1

    CALL :run docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_line "test-topic" || EXIT /B 1
    EXIT /B 0

:test_schema_registry_reachable
    CALL :run curl %CURL_OPTS% --fail http://localhost:8081/subjects
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_matches "\[.*\]" || EXIT /B 1
    EXIT /B 0

:test_ksqldb_server_healthy
    CALL :run curl %CURL_OPTS% --fail http://localhost:8088/healthcheck
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_matches "isHealthy.:true" || EXIT /B 1
    EXIT /B 0

:test_akhq_ui_reachable
    curl %CURL_OPTS% --location --output nul --write-out "%%{http_code}" http://localhost:8080 > "%RAW%" 2>&1
    SET "STATUS=%ERRORLEVEL%"
    MORE < "%RAW%" > "%OUT%"
    TYPE "%OUT%"
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_line "200" || EXIT /B 1
    EXIT /B 0

:test_status
    CALL :run .\local-env.bat status
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_contains "Container Status:" || EXIT /B 1
    FOR %%C IN (%CONTAINERS%) DO (
        CALL :assert_output_contains "%%C" || EXIT /B 1
    )
    EXIT /B 0

:test_seed_data
    CALL :run .\local-env.bat test-data
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_contains "Test data seeded successfully!" || EXIT /B 1

    CALL :run docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic items --from-beginning --max-messages 3 --timeout-ms 30000
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_contains "Item A" || EXIT /B 1
    CALL :assert_output_contains "Item B" || EXIT /B 1
    CALL :assert_output_contains "Item C" || EXIT /B 1
    EXIT /B 0

:test_ksql_cli
    :: cmd cannot provide a TTY for "docker exec -it", so only the launch message is checked
    (echo exit) | CALL .\local-env.bat ksql > "%OUT%" 2>&1
    TYPE "%OUT%"
    CALL :assert_output_contains "Opening ksqlDB CLI..." || EXIT /B 1
    EXIT /B 0

:test_logs
    START "" /B CMD /C ".\local-env.bat logs > "%OUT%" 2>&1"
    CALL :sleep 10
    powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*compose logs -f*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
    CALL :sleep 2

    MORE < "%OUT%" > "%RAW%"
    MOVE /Y "%RAW%" "%OUT%" >nul
    TYPE "%OUT%"
    CALL :assert_output_contains "Tailing logs" || EXIT /B 1
    CALL :assert_output_matches "kafka  *|" || EXIT /B 1
    EXIT /B 0

:test_stop
    CALL :run .\local-env.bat stop
    CALL :assert_success || EXIT /B 1
    CALL :assert_output_contains "Stopping local environment..." || EXIT /B 1

    docker compose ps --quiet > "%RAW%" 2>&1
    FOR %%F IN ("%RAW%") DO IF %%~zF GTR 0 (
        TYPE "%RAW%"
        CALL :fail "Expected no running containers after stop"
        EXIT /B 1
    )
    EXIT /B 0

:test_start_without_docker
    CMD /C "SET DOCKER_HOST=npipe:////./pipe/nonexistent&& .\local-env.bat start" > "%OUT%" 2>&1
    SET "STATUS=%ERRORLEVEL%"
    TYPE "%OUT%"
    CALL :assert_failure || EXIT /B 1
    CALL :assert_output_contains "Error: Failed to start the local environment." || EXIT /B 1
    EXIT /B 0

:test_seed_data_without_sql_file
    MOVE /Y test-data.sql "%TMP_DIR%\test-data.sql" >nul
    CALL :run .\local-env.bat test-data
    MOVE /Y "%TMP_DIR%\test-data.sql" test-data.sql >nul
    CALL :assert_failure || EXIT /B 1
    CALL :assert_output_contains "Error: test-data.sql not found in the current directory!" || EXIT /B 1
    EXIT /B 0

:fail
    SET "MESSAGE=%~1"
    SETLOCAL EnableDelayedExpansion
    echo FAIL: !MESSAGE! 1>&2
    ENDLOCAL
    EXIT /B 1

:: Runs a command, saving its combined output in OUT (with CRLF line endings) and exit code in STATUS.
:run
    CALL %* > "%RAW%" 2>&1
    SET "STATUS=%ERRORLEVEL%"
    MORE < "%RAW%" > "%OUT%"
    TYPE "%OUT%"
    EXIT /B 0

:assert_success
    IF NOT "%STATUS%"=="0" (
        CALL :fail "Expected exit code 0, got %STATUS%"
        EXIT /B 1
    )
    EXIT /B 0

:assert_failure
    IF "%STATUS%"=="0" (
        CALL :fail "Expected non-zero exit code, got 0"
        EXIT /B 1
    )
    EXIT /B 0

:assert_output_contains
    FINDSTR /L /C:"%~1" "%OUT%" >nul || (
        CALL :fail "Expected output to contain: %~1"
        EXIT /B 1
    )
    EXIT /B 0

:assert_output_matches
    FINDSTR /R /C:"%~1" "%OUT%" >nul || (
        CALL :fail "Expected output to match: %~1"
        EXIT /B 1
    )
    EXIT /B 0

:assert_output_line
    FINDSTR /X /L /C:"%~1" "%OUT%" >nul || (
        CALL :fail "Expected output to contain line: %~1"
        EXIT /B 1
    )
    EXIT /B 0

:run_test
    echo.
    echo ==^> %~1
    CALL :%~2
    EXIT /B %ERRORLEVEL%

:sleep
    powershell -NoProfile -Command "Start-Sleep -Seconds %~1"
    EXIT /B 0
