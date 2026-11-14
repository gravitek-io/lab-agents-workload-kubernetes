#!/usr/bin/env bash
# Shared helpers for every lab script: logging, fatal errors and precondition
# checks. Sourcing this file has no side effect beyond defining LAB_ROOT and
# the functions below.

# Absolute path of the repository root (this file lives in scripts/lib/).
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LAB_ROOT

# log MESSAGE... : progress line on stderr, so stdout stays usable for data.
log() {
  printf '==> %s\n' "$*" >&2
}

# die MESSAGE... : print an error on stderr and stop the script.
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# require_cmd CMD... : stop at the first command missing from PATH.
require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 \
      || die "missing command: ${cmd} (run 'mise install')"
  done
}

# require_env VAR... : stop at the first unset or empty variable. Only the
# variable name is printed, never its value (values may be API keys).
require_env() {
  local var
  for var in "$@"; do
    [[ -n "${!var:-}" ]] \
      || die "missing environment variable: ${var} (see .env.example)"
  done
}
