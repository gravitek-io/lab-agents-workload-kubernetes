#!/usr/bin/env bats
# Unit tests for the pure parts of scripts/lib/sandbox.sh.

setup() {
  # shellcheck source=../scripts/lib/sandbox.sh
  source "${BATS_TEST_DIRNAME}/../scripts/lib/sandbox.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/sandbox-exec-stream.jsonl"
}

@test "exec_stdout decodes stdout events only" {
  run exec_stdout < "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$output" = "4.19.0-gvisor" ]
}

@test "exec_exit_code reads the finished event" {
  run exec_exit_code < "$FIXTURE"
  [ "$output" = "0" ]
}

@test "exec_exit_code is empty when the process never finished" {
  run exec_exit_code < <(head -n 2 "$FIXTURE")
  [ -z "$output" ]
}
