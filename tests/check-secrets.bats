#!/usr/bin/env bats
# Unit tests for scripts/check-secrets.sh, run against a throwaway git repo.

# A realistic fake key: OpenRouter keys are "sk-or-v1-" + 64 hex characters.
FAKE_KEY="sk-or-v1-$(printf '0123456789abcdef%.0s' 1 2 3 4)"

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-secrets.sh"
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q
}

teardown() {
  rm -rf "$REPO"
}

@test "fails on a tracked file containing an OpenRouter key" {
  echo "OPENROUTER_API_KEY=${FAKE_KEY}" > "$REPO/notes.txt"
  git -C "$REPO" add notes.txt
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes.txt"* ]]
  [[ "$output" != *"${FAKE_KEY}"* ]]
}

@test "fails on an untracked file under results/" {
  mkdir -p "$REPO/results"
  echo "${FAKE_KEY}" > "$REPO/results/density.csv"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"results/density.csv"* ]]
}

@test "ignores a git-ignored .env outside results/" {
  echo ".env" > "$REPO/.gitignore"
  echo "OPENROUTER_API_KEY=${FAKE_KEY}" > "$REPO/.env"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "passes on a clean repo" {
  echo "hello" > "$REPO/README.md"
  git -C "$REPO" add README.md
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "ignores a documentation mention of the key prefix" {
  echo 'Keys look like sk-or-v1-...; never commit one.' > "$REPO/README.md"
  git -C "$REPO" add README.md
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "fails on an untracked, non-ignored file containing a key" {
  echo "${FAKE_KEY}" > "$REPO/notes-draft.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes-draft.md"* ]]
}
