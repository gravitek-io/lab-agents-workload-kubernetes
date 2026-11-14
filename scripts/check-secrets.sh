#!/usr/bin/env bash
# Fail if an OpenRouter API key appears in a file that could be published:
# any file tracked by git, any untracked file git does not ignore (the next
# `git add` would publish it), and any file under results/ (measurements are
# committed, so they must never carry a key). Prints file names only.
#
# Usage: scripts/check-secrets.sh [REPO_DIR]   (default: the lab root)
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

repo="${1:-$LAB_ROOT}"
cd "$repo"

leaks=()
while IFS= read -r -d '' file; do
  [[ -f "$file" ]] || continue
  if grep -qE -- "$OPENROUTER_KEY_REGEX" "$file"; then
    leaks+=("$file")
  fi
done < <(
  {
    git ls-files -z --cached --others --exclude-standard
    if [[ -d results ]]; then find results -type f -print0; fi
  }
)

if (( ${#leaks[@]} > 0 )); then
  printf 'possible OpenRouter key in: %s\n' "${leaks[@]}" >&2
  die "remove the key from these files before committing"
fi
log "no OpenRouter key found in tracked files or results/"
