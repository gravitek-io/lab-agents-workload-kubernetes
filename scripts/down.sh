#!/usr/bin/env bash
# Delete the lab cluster and everything in it (agents, sessions, snapshots).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

readonly CLUSTER_NAME="agents-lab"

require_cmd kind
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "deleting kind cluster ${CLUSTER_NAME}"
  kind delete cluster --name "$CLUSTER_NAME"
else
  log "kind cluster ${CLUSTER_NAME} does not exist, nothing to delete"
fi
