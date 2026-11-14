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

# Shape of an OpenRouter API key: "sk-or-v1-" followed by 64 hex characters.
# Matching the full shape keeps text that merely mentions the prefix (docs,
# a command quoted by a model) from raising a false alarm.
readonly OPENROUTER_KEY_REGEX='sk-or-v1-[0-9a-f]{64}'

# contains_openrouter_key : success if the text on stdin holds an OpenRouter key.
contains_openrouter_key() {
  grep -qE -- "$OPENROUTER_KEY_REGEX"
}

# is_provider_rejection : success if the `kagent agent invoke` output on stdin
# reports an HTTP 4xx from the model provider. kagent hides the provider's
# detail and only reports "OpenAI API error: <status>".
is_provider_rejection() {
  grep -qE 'API error: 4[0-9]{2}'
}
