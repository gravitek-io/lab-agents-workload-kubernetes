#!/usr/bin/env bats
# Unit tests for scripts/lib/preflight.sh: pure resource checks run before
# the lab creates its cluster.

setup() {
  # shellcheck source=../scripts/lib/preflight.sh
  source "${BATS_TEST_DIRNAME}/../scripts/lib/preflight.sh"
}

@test "docker_memory_ok rejects 4 GiB when 8 GiB are required" {
  run docker_memory_ok 4294967296 8589934592
  [ "$status" -eq 1 ]
}

@test "docker_memory_ok accepts 12 GiB when 8 GiB are required" {
  run docker_memory_ok 12884901888 8589934592
  [ "$status" -eq 0 ]
}

@test "docker_disk_ok rejects 2 GiB free when 10 GiB are required" {
  run docker_disk_ok 2147483648 10737418240
  [ "$status" -eq 1 ]
}

@test "docker_disk_ok accepts 23 GiB free when 10 GiB are required" {
  run docker_disk_ok 24696061952 10737418240
  [ "$status" -eq 0 ]
}

@test "thresholds are defined and positive" {
  (( LAB_MIN_DOCKER_MEMORY_BYTES > 0 ))
  (( LAB_MIN_DOCKER_DISK_FREE_BYTES > 0 ))
}
