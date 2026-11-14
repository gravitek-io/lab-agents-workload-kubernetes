#!/usr/bin/env bash
# Append one measurement to results/density.csv: sessions of the lab agents,
# Substrate actors by state, worker pods and their memory.
#
# Usage: scripts/measure.sh
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/api.sh
source "${LAB_ROOT}/scripts/lib/api.sh"
# shellcheck source=lib/metrics.sh
source "${LAB_ROOT}/scripts/lib/metrics.sh"

readonly CSV="${LAB_ROOT}/results/density.csv"

require_cmd kubectl kagent grpcurl jq

sessions="$(kagent agent session list --page-size 100 -o json \
  | jq '[.sessions[] | select(.agent.ref.name | startswith("lab-agent-"))] | length')"

api_open
summary="$(mktemp)"
trap 'rm -f "$summary"; api_close' EXIT
api_call kagent.api.v1.SystemService/GetSubstrateSummary > "$summary"

top="$(kubectl top pods -n kagent -l ate.dev/worker-pool=kagent-default --no-headers)"
pods="$(worker_pod_count <<<"$top")"
mem="$(worker_memory_mib <<<"$top")"

mkdir -p "$(dirname "$CSV")"
[[ -s "$CSV" ]] || echo "$DENSITY_CSV_HEADER" > "$CSV"
row="$(density_row "$summary" "$sessions" "$pods" "$mem" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
echo "$row" >> "$CSV"
echo "$row"
