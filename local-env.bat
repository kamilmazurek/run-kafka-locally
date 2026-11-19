@echo off
SETLOCAL

CALL :route "%~1"
EXIT /B %ERRORLEVEL%

:help
    echo.
    echo ========================================================
    echo   Local Environment Manager
    echo ========================================================
    echo Usage: local-env [command]
    echo.
    echo Commands:
    echo   start     - Starts the environment in the background
    echo   stop      - Stops the environment without deleting data
    echo   clean     - Stops the environment and deletes volumes
    echo   status    - Shows the status of the containers
    echo   logs      - Tails the logs for all services
    echo   ksql      - Opens the interactive ksqlDB CLI
    echo   test-data - Seeds the environment with test data
    echo.
    EXIT /B 0

:start
    echo Starting local environment...
    docker compose up -d

    IF %ERRORLEVEL% NEQ 0 (
        echo.
        echo Error: Failed to start the local environment.
        echo Please check if the Docker Desktop/daemon is running.
        EXIT /B 1
    )

    echo.
    echo Environment is up!
    echo - Kafka Broker: localhost:9092
    echo - Schema Registry: http://localhost:8081
    echo - AKHQ UI: http://localhost:8080
    echo - ksqlDB Server: http://localhost:8088
    echo.
    echo Type 'local-env help' to see available commands.
    EXIT /B 0

:stop
    echo Stopping local environment...
    docker compose down
    EXIT /B

:clean
    echo Stopping and deleting data volumes...
    docker compose down -v
    echo Environment cleaned up.
    EXIT /B

:status
    echo Container Status:
    docker compose ps
    EXIT /B

:logs
    echo Tailing logs (Press Ctrl+C to exit)...
    docker compose logs -f --tail=50
    EXIT /B

:ksql
    echo Opening ksqlDB CLI...
    docker exec -it ksqldb-cli ksql http://ksqldb-server:8088
    EXIT /B

:test-data
    echo Seeding items test data via ksqlDB...

    IF NOT EXIST test-data.sql (
        echo Error: test-data.sql not found in the current directory!
        EXIT /B 1
    )

    :: Pipe the file into the ksqldb container
    type test-data.sql | docker exec -i ksqldb-cli ksql http://ksqldb-server:8088

    echo.
    echo Test data seeded successfully!
    echo View it in AKHQ (http://localhost:8080) or run 'local-env ksql' and type: SELECT * FROM items EMIT CHANGES;
    EXIT /B 0

:route
    SET "COMMAND=%~1"

    IF /I "%COMMAND%"=="start" (
        CALL :start
    ) ELSE IF /I "%COMMAND%"=="stop" (
        CALL :stop
    ) ELSE IF /I "%COMMAND%"=="clean" (
        CALL :clean
    ) ELSE IF /I "%COMMAND%"=="status" (
        CALL :status
    ) ELSE IF /I "%COMMAND%"=="logs" (
        CALL :logs
    ) ELSE IF /I "%COMMAND%"=="ksql" (
        CALL :ksql
    ) ELSE IF /I "%COMMAND%"=="test-data" (
        CALL :test-data
    ) ELSE (
        CALL :help
    )

    EXIT /B %ERRORLEVEL%
