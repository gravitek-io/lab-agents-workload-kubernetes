#!/usr/bin/env bash
# Helpers around `kagent sandbox` for the standalone probe sandbox
# (SandboxTemplate lab-probe). They give scripts a deterministic way to run a
# command inside a Substrate sandbox, without going through the model.
#
# exec_stdout and exec_exit_code are pure filters over the JSON event stream
# of `kagent sandbox exec -o json` and are unit-tested; the probe_* functions
# call the cluster.

# exec_stdout : read an exec event stream on stdin, print the decoded stdout.
exec_stdout() {
  jq -j 'select(.event == "output" and .source == "stdout") | .data | @base64d'
}

# exec_exit_code : read an exec event stream on stdin, print the exit code of
# the finished process, or nothing if the stream has no "finished" event.
exec_exit_code() {
  jq -r 'select(.event == "finished") | .exit_code'
}

# probe_sandbox_create NAME : create a probe sandbox, print its id. NAME makes
# the idempotency key unique per caller and run.
probe_sandbox_create() {
  kagent sandbox create lab-probe --request-id "lab-$1-$(date +%s)" --ttl 15m -o json \
    | jq -r '.id'
}

# probe_sandbox_run ID COMMAND... : run COMMAND in the sandbox, print its stdout.
# Returns the command's exit code.
probe_sandbox_run() {
  local id="$1" stream code
  shift
  stream="$(kagent sandbox exec "$id" -o json -- "$@" 2>/dev/null || true)"
  exec_stdout <<<"$stream"
  code="$(exec_exit_code <<<"$stream")"
  return "${code:-1}"
}

# probe_sandbox_delete ID : delete the sandbox, ignoring an already-gone one.
probe_sandbox_delete() {
  kagent sandbox delete "$1" >/dev/null 2>&1 || true
}
