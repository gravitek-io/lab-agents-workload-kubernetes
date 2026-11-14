#!/usr/bin/env bash
# Prove that Substrate sandboxes run under gVisor: start a standalone probe
# sandbox on the agents' worker pool, read its kernel from the inside and
# compare it with the host's. No model involved, so the result is
# deterministic. The probe sandbox is deleted on exit.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/sandbox.sh
source "${LAB_ROOT}/scripts/lib/sandbox.sh"

require_cmd kagent docker jq

sandbox_id="$(probe_sandbox_create gvisor-check)"
trap 'probe_sandbox_delete "$sandbox_id"' EXIT

host_kernel="$(docker exec agents-lab-control-plane uname -r)"
sandbox_kernel="$(probe_sandbox_run "$sandbox_id" uname -r)"
boot_line="$(probe_sandbox_run "$sandbox_id" dmesg | head -n 1)"

printf 'host kernel:     %s\n' "$host_kernel"
printf 'sandbox kernel:  %s\n' "$sandbox_kernel"
printf 'sandbox dmesg:   %s\n' "$boot_line"

[[ "$sandbox_kernel" == *gvisor* ]] || die "sandbox kernel is not gVisor: ${sandbox_kernel}"
[[ "$boot_line" == *"Starting gVisor"* ]] || die "unexpected sandbox boot log: ${boot_line}"
echo "gVisor: OK"
