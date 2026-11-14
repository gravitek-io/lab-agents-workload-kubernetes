#!/usr/bin/env bash
# Connect the lab to OpenRouter and create the lab agents, then check that an
# agent answers. Reads OPENROUTER_API_KEY and OPENROUTER_MODEL from .env
# (loaded by mise). Idempotent.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

readonly NAMESPACE="kagent"
readonly AGENTS=(lab-agent-1 lab-agent-2 lab-agent-3)

require_cmd kubectl kagent envsubst jq
# Checked before anything touches the cluster; values are never printed.
require_env OPENROUTER_API_KEY OPENROUTER_MODEL
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || die "kagent is not installed: run 'mise run up' first"

log "storing the OpenRouter key in Secret ${NAMESPACE}/openrouter"
# The key goes through a process substitution, never through a command-line
# argument (which `ps` would show), and the rendered Secret is not printed.
kubectl create secret generic openrouter -n "$NAMESPACE" \
  --from-file=OPENROUTER_API_KEY=<(printf '%s' "$OPENROUTER_API_KEY") \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log "ModelConfig openrouter -> ${OPENROUTER_MODEL}"
envsubst -no-unset -no-empty -i "${LAB_ROOT}/kagent/modelconfig.yaml" | kubectl apply -f - >/dev/null

log "harness, agent template and agents"
kubectl apply -f "${LAB_ROOT}/kagent/harness.yaml" \
  -f "${LAB_ROOT}/kagent/agent-template.yaml" \
  -f "${LAB_ROOT}/kagent/agents.yaml" >/dev/null

log "waiting for the agents (the first run builds their golden snapshot)"
for agent in "${AGENTS[@]}"; do
  kubectl wait "agent/${agent}" -n "$NAMESPACE" --for=condition=Ready --timeout=600s >/dev/null \
    || die "agent ${agent} is not Ready: kubectl describe agent ${agent} -n ${NAMESPACE}"
done

log "smoke test: one question to lab-agent-1"
session="$(kagent agent session create --agent lab-agent-1 -o json | jq -r '.session.id')"
if ! reply="$(kagent agent invoke --session "$session" --task "Réponds juste : prêt." 2>&1)"; then
  printf '%s\n' "$reply" >&2
  if grep -q "400" <<<"$reply"; then
    die "the provider rejected the request: OPENROUTER_MODEL must support tool calling (see .env.example)"
  fi
  die "the agent did not answer"
fi
printf '%s\n' "$reply"
log "model connected (session ${session})"
