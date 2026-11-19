#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

CONTAINERS=(kafka schema-registry akhq ksqldb-server ksqldb-cli)
CURL_OPTS=(--silent --show-error --retry 10 --retry-delay 5 --retry-all-errors)

main() {
  run_test "Display help" test_help
  run_test "Start the local environment" test_start
  run_test "Wait for environment initialization" wait_for_initialization
  run_test "Verify Kafka broker is ready" test_kafka_broker_ready
  run_test "Verify Schema Registry is reachable" test_schema_registry_reachable
  run_test "Verify ksqlDB Server is healthy" test_ksqldb_server_healthy
  run_test "Verify AKHQ UI is reachable" test_akhq_ui_reachable
  run_test "Display container status" test_status
  run_test "Test seeding data" test_seed_data
  run_test "Open ksqlDB CLI" test_ksql_cli
  run_test "Tail logs" test_logs
  run_test "Stop the local environment" test_stop
  run_test "Test start failure when Docker is unavailable" test_start_without_docker
  run_test "Test seeding data without test-data.sql" test_seed_data_without_sql_file

  echo
  echo "All tests passed."
}

test_help() {
  local cmd
  for cmd in help unknown-command; do
    run bashcov -- ./local-env "$cmd"
    assert_success
    assert_output_contains "Local Environment Manager"
    assert_output_contains "Usage: ./local-env.sh [command]"
    for sub in start stop clean status logs ksql test-data; do
      assert_output_matches "^  $sub +- "
    done
  done
}

test_start() {
  run bashcov -- ./local-env start
  assert_success
  assert_output_contains "Environment is up!"
  assert_output_contains "- Kafka Broker: localhost:9092"

  run docker compose ps --status running --services
  local container
  for container in "${CONTAINERS[@]}"; do
    assert_output_matches "^$container$"
  done
}

wait_for_initialization() {
  sleep 30
}

test_kafka_broker_ready() {
  run docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
    --create --if-not-exists --topic test-topic --partitions 1 --replication-factor 1
  assert_success

  run docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list
  assert_success
  assert_output_matches "^test-topic$"
}

test_schema_registry_reachable() {
  run curl "${CURL_OPTS[@]}" --fail http://localhost:8081/subjects
  assert_success
  assert_output_matches '^\['
}

test_ksqldb_server_healthy() {
  run curl "${CURL_OPTS[@]}" --fail http://localhost:8088/healthcheck
  assert_success
  assert_output_contains '"isHealthy":true'
}

test_akhq_ui_reachable() {
  run curl "${CURL_OPTS[@]}" --location --output /dev/null --write-out '%{http_code}' http://localhost:8080
  assert_success
  assert_equals "200" "$OUTPUT" "AKHQ HTTP status"
}

test_status() {
  run bashcov -- ./local-env status
  assert_success
  assert_output_contains "Container Status:"
  local container
  for container in "${CONTAINERS[@]}"; do
    assert_output_contains "$container"
  done
}

test_seed_data() {
  run bashcov -- ./local-env test-data
  assert_success
  assert_output_contains "Test data seeded successfully!"

  run docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 \
    --topic items --from-beginning --max-messages 3 --timeout-ms 30000
  assert_success
  assert_output_contains "Item A"
  assert_output_contains "Item B"
  assert_output_contains "Item C"
}

test_ksql_cli() {
  run bash -c 'echo "exit" | timeout 120 script --quiet --return --command "bashcov -- ./local-env ksql" /dev/null'
  assert_success
  assert_output_contains "Opening ksqlDB CLI..."
}

test_logs() {
  bashcov -- ./local-env logs > "$TMP_DIR/logs.txt" 2>&1 &
  sleep 10
  pkill -f "compose logs -f" || true
  wait || true

  OUTPUT=$(cat "$TMP_DIR/logs.txt")
  echo "$OUTPUT"
  assert_output_contains "Tailing logs"
  assert_output_matches "kafka +\|"
}

test_stop() {
  run bashcov -- ./local-env stop
  assert_success
  assert_output_contains "Stopping local environment..."

  run docker compose ps --quiet
  assert_equals "" "$OUTPUT" "Running containers after stop"
}

test_start_without_docker() {
  run env DOCKER_HOST=unix:///nonexistent.sock bashcov --command-name "start without Docker" -- ./local-env start
  assert_failure
  assert_output_contains "Error: Failed to start the local environment."
}

test_seed_data_without_sql_file() {
  mv test-data.sql "$TMP_DIR/test-data.sql"
  run bashcov --command-name "test-data without test-data.sql" -- ./local-env test-data
  mv "$TMP_DIR/test-data.sql" test-data.sql
  assert_failure
  assert_output_contains "Error: test-data.sql not found in the current directory!"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Runs a command, capturing its combined output in OUTPUT and exit code in STATUS.
run() {
  STATUS=0
  OUTPUT=$("$@" 2>&1) || STATUS=$?
  echo "$OUTPUT"
}

assert_success() {
  [ "$STATUS" -eq 0 ] || fail "Expected exit code 0, got $STATUS"
}

assert_failure() {
  [ "$STATUS" -ne 0 ] || fail "Expected non-zero exit code, got 0"
}

assert_output_contains() {
  grep -qF -- "$1" <<< "$OUTPUT" || fail "Expected output to contain: $1"
}

assert_output_matches() {
  grep -qE -- "$1" <<< "$OUTPUT" || fail "Expected output to match: $1"
}

assert_equals() {
  [ "$1" = "$2" ] || fail "${3:-Values differ}: expected '$1', got '$2'"
}

run_test() {
  echo
  echo "==> $1"
  "$2"
}

main "$@"
