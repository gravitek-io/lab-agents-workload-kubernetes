#!/usr/bin/env bash
# Pure helpers that turn lab outputs (Substrate summary, kubectl top) into CSV
# rows. No cluster access here: measure.sh collects the inputs, these
# functions only parse them, which keeps them unit-testable.

# shellcheck disable=SC2034 # used by measure.sh, which sources this file
readonly DENSITY_CSV_HEADER="timestamp,sessions,actors_total,actors_suspended,actors_running,worker_pods,worker_memory_mib"

# mem_to_mib QUANTITY : Kubernetes memory quantity (Ki, Mi, Gi) to whole MiB.
mem_to_mib() {
  local q="$1"
  case "$q" in
    *Ki) echo $(( ${q%Ki} / 1024 )) ;;
    *Mi) echo "${q%Mi}" ;;
    *Gi) echo $(( ${q%Gi} * 1024 )) ;;
    *) return 1 ;;
  esac
}

# worker_memory_mib : sum the MEMORY column of `kubectl top pods --no-headers`
# read on stdin (NAME CPU MEMORY), in MiB.
worker_memory_mib() {
  local _name _cpu mem total=0
  while read -r _name _cpu mem; do
    [[ -n "$mem" ]] || continue
    total=$(( total + $(mem_to_mib "$mem") ))
  done
  echo "$total"
}

# worker_pod_count : number of pods listed by `kubectl top pods --no-headers`.
worker_pod_count() {
  grep -c . || true
}

# density_row SUMMARY_JSON SESSIONS WORKER_PODS WORKER_MEMORY_MIB TIMESTAMP :
# one CSV line matching DENSITY_CSV_HEADER. SUMMARY_JSON is the output of
# SystemService/GetSubstrateSummary; its counts are strings and states with a
# zero count are omitted, hence the defaults.
density_row() {
  local summary="$1" sessions="$2" pods="$3" mem="$4" ts="$5"
  jq -r --arg ts "$ts" --arg sessions "$sessions" --arg pods "$pods" --arg mem "$mem" '
    def state($s): ([.actorStatusCounts[]? | select(.state == $s) | .count | tonumber] | add // 0);
    [$ts, $sessions, (.actorCount // "0" | tonumber),
     state("ACTOR_STATE_SUSPENDED"), state("ACTOR_STATE_RUNNING"), $pods, $mem]
    | map(tostring) | join(",")
  ' "$summary"
}
