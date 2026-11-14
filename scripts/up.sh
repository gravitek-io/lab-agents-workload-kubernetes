#!/usr/bin/env bash
# Create the lab cluster and install kagent 1.0 with Agent Substrate.
# Idempotent: re-running converges to the same state without duplicates.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/preflight.sh
source "${LAB_ROOT}/scripts/lib/preflight.sh"

readonly CLUSTER_NAME="agents-lab"
readonly NODE_IMAGE="kindest/node:v1.37.0"
readonly METRICS_SERVER_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml"

require_cmd docker kind kubectl helm kagent jq

# --- Preflight: Docker must have enough memory and free disk -------------
docker info >/dev/null 2>&1 || die "Docker is not running"
mem_bytes="$(docker info --format '{{.MemTotal}}')"
docker_memory_ok "$mem_bytes" "$LAB_MIN_DOCKER_MEMORY_BYTES" \
  || die "Docker has $((mem_bytes / 1024 / 1024)) MiB of memory; the lab needs $((LAB_MIN_DOCKER_MEMORY_BYTES / 1024 / 1024)) MiB (Docker Desktop > Settings > Resources)"

# Free space inside the Docker VM, read from the node image the lab needs anyway.
free_kib="$(docker run --rm --entrypoint df "$NODE_IMAGE" -Pk / | awk 'NR == 2 { print $4 }')"
docker_disk_ok "$((free_kib * 1024))" "$LAB_MIN_DOCKER_DISK_FREE_BYTES" \
  || die "Docker has $((free_kib / 1024 / 1024)) GiB of free disk; the lab needs $((LAB_MIN_DOCKER_DISK_FREE_BYTES / 1024 / 1024 / 1024)) GiB (try 'docker builder prune')"

# --- Cluster ---------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster ${CLUSTER_NAME} already exists"
else
  log "creating kind cluster ${CLUSTER_NAME} (Kubernetes 1.37)"
  kind create cluster --config "${LAB_ROOT}/kind/cluster.yaml"
fi
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# --- metrics-server (kubectl top), with kind's self-signed kubelet certs ---
log "installing metrics-server"
kubectl apply -f "$METRICS_SERVER_URL" >/dev/null
# `kubectl apply` resets the args on each run, so the flag is re-added when missing.
if ! kubectl get deployment metrics-server -n kube-system -o json \
  | jq -e '.spec.template.spec.containers[0].args | index("--kubelet-insecure-tls")' >/dev/null; then
  kubectl patch deployment metrics-server -n kube-system --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
fi

# --- kagent + Agent Substrate --------------------------------------------
# `kagent install` insists on a provider key and creates a default OpenAI
# ModelConfig with it. The lab never uses that ModelConfig (agents reference
# the OpenRouter one created by `mise run model`), so it gets a dummy value:
# the OpenRouter key must never be sent to OpenAI.
log "installing kagent 1.0 and Agent Substrate (takes a few minutes)"
OPENAI_API_KEY="not-used" kagent --config "${LAB_ROOT}/kagent/kagent-config.yaml" \
  install --namespace kagent

log "waiting for the controller and the gVisor worker pool"
kubectl rollout status deployment/kagent-controller -n kagent --timeout=300s >/dev/null
kubectl rollout status deployment/metrics-server -n kube-system --timeout=300s >/dev/null
kubectl wait workerpool/kagent-default -n kagent \
  --for=jsonpath='{.status.readyReplicas}'=1 --timeout=600s >/dev/null

log "probe sandbox template (used by the isolation checks)"
kubectl apply -f "${LAB_ROOT}/kagent/sandbox-template.yaml" >/dev/null
kubectl wait sandboxtemplate/lab-probe -n kagent --for=condition=Ready --timeout=300s >/dev/null

kubectl get workerpools -n kagent
log "lab is up"
