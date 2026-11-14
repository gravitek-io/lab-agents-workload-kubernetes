#!/usr/bin/env bats
# Unit tests for scripts/lib/metrics.sh, against outputs captured from the lab.

setup() {
  # shellcheck source=../scripts/lib/metrics.sh
  source "${BATS_TEST_DIRNAME}/../scripts/lib/metrics.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

@test "mem_to_mib converts Mi, Gi and Ki" {
  [ "$(mem_to_mib 512Mi)" = "512" ]
  [ "$(mem_to_mib 1Gi)" = "1024" ]
  [ "$(mem_to_mib 2048Ki)" = "2" ]
}

@test "mem_to_mib rejects an unknown unit" {
  run mem_to_mib 12Tb
  [ "$status" -eq 1 ]
}

@test "density_row reads suspended actors and defaults missing states to 0" {
  run density_row "$FIXTURES/substrate-summary.json" 10 1 300 2026-11-14T10:00:00Z
  [ "$status" -eq 0 ]
  [ "$output" = "2026-11-14T10:00:00Z,10,2,2,0,1,300" ]
}

@test "density_row reads running actors" {
  run density_row "$FIXTURES/substrate-summary-running.json" 1 1 17 2026-11-14T10:00:00Z
  [ "$output" = "2026-11-14T10:00:00Z,1,1,0,1,1,17" ]
}

@test "worker_memory_mib sums the worker pods from kubectl top" {
  run worker_memory_mib < "$FIXTURES/top-pods.txt"
  [ "$output" = "17" ]
}

@test "worker_pod_count counts the worker pods from kubectl top" {
  run worker_pod_count < "$FIXTURES/top-pods.txt"
  [ "$output" = "1" ]
}

@test "DENSITY_CSV_HEADER matches the row layout" {
  [ "$DENSITY_CSV_HEADER" = "timestamp,sessions,actors_total,actors_suspended,actors_running,worker_pods,worker_memory_mib" ]
}
