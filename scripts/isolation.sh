#!/usr/bin/env bash
# Isolation demo, in two parts.
#
# 1. Deterministic checks with the standalone probe sandbox (no model): the
#    sandbox runs under gVisor; egress is closed by default (an unknown host
#    does not even resolve); one EgressPolicy opens exactly one origin, and
#    the request then goes through Substrate's egress gateway.
# 2. Illustration with a real agent: it runs commands with its bash tool and
#    shows that it only holds a placeholder instead of the OpenRouter key. A
#    model may decline to use its tool, so this part never fails the script.
#
# Idempotent: the policy is detached and deleted on exit.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/sandbox.sh
source "${LAB_ROOT}/scripts/lib/sandbox.sh"

readonly NAMESPACE="kagent"
readonly ALLOWED_URL="https://example.com"
readonly DENIED_URL="https://www.google.com"

require_cmd kubectl kagent jq

sandboxes=()
cleanup() {
  local id
  for id in "${sandboxes[@]+"${sandboxes[@]}"}"; do probe_sandbox_delete "$id"; done
  kubectl patch sandboxtemplate lab-probe -n "$NAMESPACE" --type=merge \
    -p '{"spec":{"egressPolicyRefs":null}}' >/dev/null 2>&1 || true
  kubectl delete -f "${LAB_ROOT}/kagent/egress-policy.yaml" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

# http_status ID URL : HTTP status seen from the sandbox, or curl's error
# (curl prints a placeholder "000" status after an error; it is dropped).
http_status() {
  probe_sandbox_run "$1" sh -c "curl -sS -m 10 -o /dev/null -w '%{http_code}\n' '$2' 2>&1 | grep -v '^000\$'" || true
}

# new_probe NAME : create a fresh probe sandbox (a policy change applies to
# new ones) and set PROBE_ID. Not meant for $(...): the id must be recorded
# in this shell so that cleanup deletes the sandbox; a leaked sandbox keeps
# running and holds worker memory.
new_probe() {
  PROBE_ID="$(probe_sandbox_create "$1")"
  sandboxes+=("$PROBE_ID")
}

log "1/4 gVisor"
"${LAB_ROOT}/scripts/gvisor-check.sh"

log "2/4 egress closed by default"
cleanup
kubectl wait sandboxtemplate/lab-probe -n "$NAMESPACE" --for=condition=Ready --timeout=120s >/dev/null
new_probe egress-closed
denied="$(http_status "$PROBE_ID" "$ALLOWED_URL")"
printf '%s -> %s\n' "$ALLOWED_URL" "$denied"
[[ "$denied" == *"Could not resolve host"* ]] || die "expected ${ALLOWED_URL} to be unreachable, got: ${denied}"

log "3/4 one EgressPolicy opens one origin"
kubectl apply -f "${LAB_ROOT}/kagent/egress-policy.yaml" >/dev/null
kubectl patch sandboxtemplate lab-probe -n "$NAMESPACE" --type=merge \
  -p '{"spec":{"egressPolicyRefs":[{"name":"lab-allow-example"}]}}' >/dev/null
kubectl wait sandboxtemplate/lab-probe -n "$NAMESPACE" --for=condition=EgressPoliciesApplied --timeout=120s >/dev/null
new_probe egress-open
allowed="$(http_status "$PROBE_ID" "$ALLOWED_URL")"
other="$(http_status "$PROBE_ID" "$DENIED_URL")"
printf '%s -> %s\n%s -> %s\n' "$ALLOWED_URL" "$allowed" "$DENIED_URL" "$other"
[[ "$allowed" == "200" ]] || die "expected HTTP 200 from ${ALLOWED_URL}, got: ${allowed}"
[[ "$other" == *"Could not resolve host"* ]] || die "expected ${DENIED_URL} to stay closed, got: ${other}"
log "egress gateway log for the allowed request:"
kubectl logs -n ate-system deploy/atenet-egress -c agentgateway --since=2m 2>/dev/null \
  | grep 'http.host=example.com' | grep -v debug | tail -n 1 \
  | grep -oE 'endpoint=[^ ]+|http.host=[^ ]+|http.status=[0-9]+' | paste -sd ' ' -

log "4/4 an agent at work (illustration, depends on the model using its tool)"
session="$(kagent agent session create --agent lab-agent-1 -o json | jq -r '.session.id')"
# The variables belong to the agent's shell, hence the single quotes.
# shellcheck disable=SC2016
task='Exécute avec ton outil bash exactement cette commande et renvoie sa sortie brute : uname -r; case "$OPENAI_API_KEY" in sk-or-*) echo "VRAIE CLE PRESENTE";; *) echo "clé vue par l agent : $OPENAI_API_KEY";; esac'
for attempt in 1 2 3; do
  reply="$(kagent agent invoke --session "$session" --task "$task" 2>&1 || true)"
  # Only a real-shaped key or the sentinel on its own line count: the model
  # may quote the command, which contains the "sk-or-*" pattern.
  if contains_openrouter_key <<<"$reply" || grep -qx 'VRAIE CLE PRESENTE' <<<"$reply"; then
    die "the agent can read the OpenRouter key"
  fi
  if grep -q "gvisor" <<<"$reply"; then
    printf '%s\n' "$reply"
    echo "agent illustration: OK"
    exit 0
  fi
  log "attempt ${attempt}: the model did not run the tool, retrying"
done
echo "agent illustration: model did not run the tool (the checks above still hold)"
