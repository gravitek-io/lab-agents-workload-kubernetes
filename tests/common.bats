#!/usr/bin/env bats
# Unit tests for scripts/lib/common.sh, the helpers every lab script sources.

setup() {
  # shellcheck source=../scripts/lib/common.sh
  source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
}

@test "require_env fails naming the variable" {
  unset FOO
  run require_env FOO
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing environment variable: FOO"* ]]
}

@test "require_env fails on an empty variable" {
  FOO=""
  run require_env FOO
  [ "$status" -eq 1 ]
  [[ "$output" == *"FOO"* ]]
}

@test "require_env never prints the value" {
  export FOO="sk-or-v1-secret"
  unset BAR
  run require_env FOO BAR
  [ "$status" -eq 1 ]
  [[ "$output" == *"BAR"* ]]
  [[ "$output" != *"sk-or-v1-secret"* ]]
}

@test "require_env passes when every variable is set" {
  export FOO="x" BAR="y"
  run require_env FOO BAR
  [ "$status" -eq 0 ]
}

@test "require_cmd fails naming the command" {
  run require_cmd bash definitely-not-a-cmd
  [ "$status" -eq 1 ]
  [[ "$output" == *"definitely-not-a-cmd"* ]]
}

@test "LAB_ROOT points at the repository root" {
  [ -f "${LAB_ROOT}/mise.toml" ]
}

@test "contains_openrouter_key ignores the prefix inside a quoted command" {
  run contains_openrouter_key <<<'case "$OPENAI_API_KEY" in sk-or-*) echo "VRAIE CLE PRESENTE";; esac'
  [ "$status" -eq 1 ]
}

@test "contains_openrouter_key detects a real-shaped key" {
  run contains_openrouter_key <<<"key=sk-or-v1-$(printf '0123456789abcdef%.0s' 1 2 3 4)"
  [ "$status" -eq 0 ]
}

@test "is_provider_rejection matches the provider error kagent reports" {
  run is_provider_rejection < "${BATS_TEST_DIRNAME}/fixtures/invoke-provider-error.txt"
  [ "$status" -eq 0 ]
}

@test "is_provider_rejection ignores numbers that are not HTTP statuses" {
  run is_provider_rejection <<<"inputTokens 4001, prompt 400 tokens"
  [ "$status" -eq 1 ]
}
