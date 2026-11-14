#!/usr/bin/env bash
# Density demo: open 1, then 10, then 30 conversations (sessions) spread over
# the three lab agents, and measure after each step. Every session is its own
# Substrate actor, yet the number of worker pods stays that of the WorkerPool.
# Each run starts from zero: it deletes the lab agents' existing sessions
# (including those opened by the model and isolation steps), so the 1/10/30
# curve and results/density.csv are the same on every run.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

readonly STEPS=(1 10 30)
readonly AGENTS=(lab-agent-1 lab-agent-2 lab-agent-3)

require_cmd kubectl kagent jq

# lab_session_ids : ids of the lab agents' sessions, one per line.
lab_session_ids() {
  kagent agent session list --page-size 100 -o json \
    | jq -r '.sessions[] | select(.agent.ref.name | startswith("lab-agent-")) | .id'
}

count_sessions() {
  lab_session_ids | grep -c . || true
}

# Wait until no actor is running, resuming or suspending: a fresh session is
# created suspended, and a measurement must see the idle state.
wait_all_suspended() {
  local _ busy
  for _ in $(seq 1 120); do
    busy="$(kubectl ate get actors --atespace kagent 2>/dev/null \
      | awk 'NR > 1 && $4 != "ACTOR_STATE_SUSPENDED"' | wc -l | tr -d ' ')"
    [[ "$busy" == "0" ]] && return 0
    sleep 1
  done
  die "actors still busy after 2 minutes: kubectl ate get actors --atespace kagent"
}

kagent agent list >/dev/null 2>&1 || die "kagent is not reachable: run 'mise run up' and 'mise run model' first"
rm -f "${LAB_ROOT}/results/density.csv"

log "deleting the existing lab sessions"
lab_session_ids | while IFS= read -r id; do
  kagent agent session delete "$id" >/dev/null
done

for target in "${STEPS[@]}"; do
  current="$(count_sessions)"
  log "step ${target}: ${current} session(s) exist"
  i="$current"
  while (( i < target )); do
    agent="${AGENTS[$(( i % ${#AGENTS[@]} ))]}"
    kagent agent session create --agent "$agent" -o json >/dev/null
    i=$(( i + 1 ))
  done
  wait_all_suspended
  "${LAB_ROOT}/scripts/measure.sh"
done

log "actors now (first lines):"
kubectl ate get actors --atespace kagent 2>/dev/null | head -n 6
kubectl get pods -n kagent -l ate.dev/worker-pool=kagent-default
