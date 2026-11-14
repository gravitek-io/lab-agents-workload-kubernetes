#!/usr/bin/env bash
# Suspend/resume demo: send a message to five sleeping sessions. Each one is
# restored from its snapshot, answers, then goes back to sleep at the end of
# the turn. Restore times (read from the worker's own timing record, not the
# whole call, which includes the model) go to results/resume.csv, rewritten on
# each run. Finally prints where the last snapshot is stored.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/api.sh
source "${LAB_ROOT}/scripts/lib/api.sh"
# shellcheck source=lib/metrics.sh
source "${LAB_ROOT}/scripts/lib/metrics.sh"

readonly CSV="${LAB_ROOT}/results/resume.csv"
readonly SAMPLES=5

require_cmd kubectl kagent grpcurl jq

# actor_state SESSION_ID : current Substrate state of the session's actor.
actor_state() {
  kubectl ate get actors "session-$1" --atespace kagent 2>/dev/null | awk 'NR == 2 { print $4 }'
}

# wait_suspended SESSION_ID : wait for the actor to fall asleep again.
wait_suspended() {
  local _
  for _ in $(seq 1 60); do
    [[ "$(actor_state "$1")" == "ACTOR_STATE_SUSPENDED" ]] && return 0
    sleep 1
  done
  die "session $1 did not suspend after its turn"
}

# Plain read loop rather than mapfile: macOS ships bash 3.2.
sessions=()
while IFS= read -r id; do
  sessions+=("$id")
done < <(kagent agent session list --page-size 100 -o json \
  | jq -r '.sessions[] | select(.agent.ref.name | startswith("lab-agent-")) | .id' | head -n "$SAMPLES")
(( ${#sessions[@]} > 0 )) || die "no session to wake up: run 'mise run density' first"

mkdir -p "$(dirname "$CSV")"
echo "$RESUME_CSV_HEADER" > "$CSV"

for session in "${sessions[@]}"; do
  wait_suspended "$session"
  log "session ${session}: $(actor_state "$session"), no worker pod"
  reply="$(kagent agent invoke --session "$session" --task "Réponds juste : réveillé." 2>&1)" \
    || die "invoke failed: ${reply}"
  printf '    reply: %s\n' "$reply" >&2
  wait_suspended "$session"
  ms="$(kubectl logs -n kagent deploy/kagent-default --since=5m 2>/dev/null \
    | restore_duration_ms "session-${session}")" \
    || die "no restore record for session ${session} in the worker logs"
  row="$(date -u +%Y-%m-%dT%H:%M:%SZ),${session},${ms}"
  echo "$row" >> "$CSV"
  log "restored in ${ms} ms, back to $(actor_state "$session")"
done

api_open
log "snapshot of the last session (only the /data volume, no process memory):"
api_call kagent.api.v1.SystemService/ListSubstrateActors \
  | jq -r --arg name "session-${session}" '
      .actors[] | select(.metadata.name == $name) | .status.snapshots[-1]
      | "\(.fidelity)  \(.durableSnapshot.object.snapshotUri)"'
