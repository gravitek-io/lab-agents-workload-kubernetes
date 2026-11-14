#!/usr/bin/env bash
# Resource checks run before the lab creates its cluster. The functions are
# pure (they compare numbers) so they can be unit-tested; up.sh feeds them the
# values it reads from Docker.

# Memory Docker must offer. The whole lab (kind node, Substrate, kagent,
# PostgreSQL, rustfs, one gVisor worker) used 2.1 GiB at rest in the first
# run; 6 GiB leaves room for 30 sessions and a running turn.
# shellcheck disable=SC2034 # used by up.sh, which sources this file
readonly LAB_MIN_DOCKER_MEMORY_BYTES=$((6 * 1024 * 1024 * 1024))

# Free disk the Docker VM must have. Images, the PostgreSQL volume and
# snapshots need a few GiB; a full disk makes PostgreSQL fail at initdb.
# shellcheck disable=SC2034 # used by up.sh, which sources this file
readonly LAB_MIN_DOCKER_DISK_FREE_BYTES=$((10 * 1024 * 1024 * 1024))

# docker_memory_ok AVAILABLE_BYTES REQUIRED_BYTES : success if enough memory.
docker_memory_ok() {
  (( $1 >= $2 ))
}

# docker_disk_ok FREE_BYTES REQUIRED_BYTES : success if enough free disk.
docker_disk_ok() {
  (( $1 >= $2 ))
}
