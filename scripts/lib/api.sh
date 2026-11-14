#!/usr/bin/env bash
# Access to the kagent controller gRPC API (SystemService) through a
# kubectl port-forward. Used by the measurement scripts to read Substrate
# state that the kagent CLI does not show.
#
# Usage: api_open; api_call kagent.api.v1.SystemService/GetSubstrateSummary
# (api_open installs an EXIT trap that closes the port-forward).

# Local port of the port-forward. 8083 is left to the kagent CLI, which
# opens its own port-forward there.
LAB_API_PORT="${LAB_API_PORT:-18083}"
API_PF_PID=""

# api_open : start the port-forward and wait until the API answers.
api_open() {
  kubectl port-forward -n kagent svc/kagent-controller "${LAB_API_PORT}:8083" >/dev/null 2>&1 &
  API_PF_PID=$!
  trap api_close EXIT
  local _
  for _ in $(seq 1 40); do
    grpcurl -plaintext "localhost:${LAB_API_PORT}" list >/dev/null 2>&1 && return 0
    sleep 0.25
  done
  die "kagent API not reachable on localhost:${LAB_API_PORT} (port busy? set LAB_API_PORT)"
}

# api_close : stop the port-forward.
api_close() {
  [[ -n "$API_PF_PID" ]] && kill "$API_PF_PID" 2>/dev/null || true
}

# api_call METHOD [JSON] : call a gRPC method, print the JSON response.
api_call() {
  local data="${2:-}"
  [[ -n "$data" ]] || data='{}'
  grpcurl -plaintext -d "$data" "localhost:${LAB_API_PORT}" "$1"
}
