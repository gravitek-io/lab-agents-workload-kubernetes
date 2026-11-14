# Lab « agents IA sur Kubernetes » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reproducible kind lab that shows kagent 1.0 on Agent Substrate: density (sessions vs pods), suspend/resume, gVisor isolation and closed egress, with measurements written to versioned CSV files.

**Architecture:** One `mise.toml` pins every tool and exposes one task per lab step; each task calls one idempotent bash script in `scripts/`. Pure parsing helpers (CSV rows, unit conversion, log durations) live in `scripts/lib/` and are unit-tested with bats against fixtures captured from the real cluster. Kubernetes manifests live in `kagent/`; measurements land in `results/`.

**Tech Stack:** mise, kind ≥ 0.32 with `kindest/node:v1.37.0`, kagent CLI v1.0.0, `kubectl-ate` v1.0.0, helm 3, kubectl, jq, grpcurl, metrics-server, bats-core, shellcheck, OpenRouter (OpenAI-compatible API).

**Spec:** `docs/superpowers/specs/2026-11-14-agents-workload-kubernetes-design.md`

**Scope:** this plan builds the lab only. The blog article (sources check, MDX draft, SVGs from the CSV files) gets its own plan once the lab has produced real numbers, in the `gravitek-website` repo, on a feature branch.

## Global Constraints

- Kubernetes ≥ 1.37: node image `kindest/node:v1.37.0`; kind ≥ v0.32.0.
- kagent CLI and charts pinned to `v1.0.0` / `1.0.0`; `kubectl-ate` pinned to `v1.0.0`. No floating versions anywhere (`mise.toml`, image tags, chart versions).
- Primary target: macOS arm64 + Docker Desktop; must also run on Linux amd64 (no macOS-only commands in scripts: no `sed -i ''`, no `date -j`, no BSD `stat`).
- Model: `ModelConfig` `api.kagent.dev/v1alpha3`, `provider: OpenAI`, `openAI.baseUrl: https://openrouter.ai/api/v1`, model from `OPENROUTER_MODEL`, which must support tool calling.
- Secrets: `OPENROUTER_API_KEY` only in `.env` (git-ignored, loaded by mise `[env] _.file`). Never echoed, never in `set -x` output, never in `results/`, never in a committed file. The OpenRouter key is never passed to an OpenAI endpoint.
- Code, comments, script output and commit messages in English; `README.md` in French.
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, sources `scripts/lib/common.sh`, checks its preconditions and fails with a message naming what is missing. Every script is idempotent (safe to re-run).
- Every script and helper starts with a header comment stating its purpose (documentation requirement).
- Conventional Commits; no reference to Claude, AI tools or automated generation in commit messages, and no `Co-Authored-By` trailer.
- Commit locally only. Creating the GitHub repo and pushing need Thomas's explicit approval.
- **Gate:** if Task 2 shows gVisor cannot run in kind on Docker Desktop arm64, stop and report to Thomas with the diagnostic; do not pick an alternative alone.

## Review Focus

1. `.env` missing or `OPENROUTER_API_KEY` empty → `mise run up` / `mise run model` stop before touching the cluster, naming the variable, never printing a value. (Task 1 test `require_env`.)
2. Re-running any step on an existing cluster → no error, no duplicate resources, same end state. (Each task's "re-run" verification step.)
3. Docker Desktop with too little memory → `up` warns before creating the cluster, with the measured requirement. (Task 2 test `docker_memory_ok`.)
4. `OPENROUTER_MODEL` without tool calling → the first invoke fails; the script prints a hint pointing at tool-calling support instead of a bare 400. (Task 3 verification.)
5. Key leak into the repo → `mise run check` fails if any tracked file or anything in `results/` contains an OpenRouter key pattern (`sk-or-`). (Task 1 test `check-secrets`.)

---

### Task 1: Repository scaffolding, tooling and shared helpers

**Files:**
- Create: `mise.toml`, `.gitignore`, `.env.example`, `LICENSE` (Apache 2.0, copyright Gravitek), `README.md` (French stub: title, one-paragraph purpose, "en construction")
- Create: `scripts/lib/common.sh`, `scripts/check-secrets.sh`
- Test: `tests/common.bats`, `tests/check-secrets.bats`

**Interfaces:**
- Produces (`scripts/lib/common.sh`, sourced, no side effects on load):
  - `log <message...>` → prints `==> message` to stderr
  - `die <message...>` → prints `ERROR: message` to stderr, exits 1
  - `require_cmd <cmd...>` → `die` naming the first missing command
  - `require_env <VAR...>` → `die "missing environment variable: VAR (see .env.example)"` for the first unset or empty one; never prints values
  - `LAB_ROOT` → absolute path of the repo root
- Produces mise tasks: `check` (shellcheck on `scripts/**/*.sh` + `bats tests/` + `scripts/check-secrets.sh`), `tools` (fallback downloader for kagent CLI and `kubectl-ate` if mise backends fail)

- [ ] **Step 1:** Write `mise.toml` with `[tools]` pinned exactly (kind ≥ 0.32 latest patch, kubectl 1.37.x, helm 3.x, jq, grpcurl, shellcheck, bats), plus kagent CLI and `kubectl-ate` through mise's GitHub backend if their release assets resolve (`github:kagent-dev/kagent`, `github:kagent-dev/substrate`); `[env] _.file = ".env"`. Run `mise install`. Expected: all tools install; `kind version` ≥ v0.32.0. If kagent/`kubectl-ate` do not resolve, remove them from `[tools]` and implement the `tools` task (downloads `v1.0.0` into `./bin`, added to `PATH` via `[env] _.path`).
- [ ] **Step 2:** `.gitignore` covers `.env`, `bin/`, `*.kubeconfig`; `.env.example` has `OPENROUTER_API_KEY=` and `OPENROUTER_MODEL=` with a French comment each (where to get the key, that the model must support tool calling).
- [ ] **Step 3: Write the failing tests** in `tests/common.bats`:
  - `require_env fails naming the variable`: with `FOO` unset, `run require_env FOO` → status 1, output contains `missing environment variable: FOO`.
  - `require_env never prints the value`: with `FOO=sk-or-v1-secret` and `BAR` unset, `run require_env FOO BAR` → output contains `BAR`, does not contain `sk-or-v1-secret`.
  - `require_cmd fails naming the command`: `run require_cmd definitely-not-a-cmd` → status 1, output contains `definitely-not-a-cmd`.
  and in `tests/check-secrets.bats` (run against a temp git repo fixture):
  - `fails on a tracked file containing sk-or-` → status 1, output names the file, not the key.
  - `fails on a file under results/ containing sk-or-` (even untracked) → status 1.
  - `passes on a clean repo` → status 0.
- [ ] **Step 4:** Run `mise exec -- bats tests/`. Expected: FAIL (functions not defined).
- [ ] **Step 5:** Implement `scripts/lib/common.sh` and `scripts/check-secrets.sh` (`git ls-files` + `results/`, grep `sk-or-`, print file names only).
- [ ] **Step 6:** Run `mise run check`. Expected: shellcheck clean, all bats tests PASS.
- [ ] **Step 7: Commit** `chore: scaffold lab tooling with mise and shared helpers`

### Task 2: Cluster and kagent/Substrate install, gVisor gate

**Files:**
- Create: `kind/cluster.yaml`, `kagent/kagent-values.yaml`, `kagent/kagent-config.yaml`, `scripts/up.sh`, `scripts/down.sh`, `scripts/lib/preflight.sh`
- Create: `kagent/sandbox-template.yaml`, `scripts/gvisor-check.sh`
- Test: `tests/preflight.bats`
- Modify: `mise.toml` (tasks `up`, `down`, `gvisor-check`), `README.md`

**Interfaces:**
- Consumes: `common.sh` (Task 1)
- Produces: cluster context `kind-agents-lab`; namespaces `kagent`, `ate-system`; WorkerPool `kagent-default` (1 replica, with requests/limits); metrics-server installed; standalone sandbox template `lab-probe` (gVisor)
- Produces (`scripts/lib/preflight.sh`): `docker_memory_ok <available_bytes> <required_bytes>` → status 0/1, pure; `LAB_MIN_DOCKER_MEMORY_BYTES` constant

- [ ] **Step 1: Spike first, throwaway.** By hand: `kind create cluster --name agents-lab --image kindest/node:v1.37.0`, `kagent install` (values below), then a standalone sandbox running `dmesg` and `uname -a`. Record the outcome, Docker Desktop memory in use (`docker stats --no-stream`), and the real output of `kubectl ate get actors`, `GetSubstrateSummary` (grpcurl) and worker logs into `tests/fixtures/` (redact nothing secret: there is no key yet).
- [ ] **Step 2: GATE.** gVisor kernel visible (dmesg shows gVisor's boot lines, not the host kernel) and WorkerPool `READY 1` → continue. Otherwise stop, write the diagnostic in `docs/gvisor-kind-spike.md`, commit it, and report to Thomas.
- [ ] **Step 3: Write the failing test** `tests/preflight.bats`: `docker_memory_ok 4294967296 8589934592` → status 1; `docker_memory_ok 12884901888 8589934592` → status 0. Run: FAIL.
- [ ] **Step 4:** Implement `preflight.sh`; set `LAB_MIN_DOCKER_MEMORY_BYTES` from the spike measurement plus a 2 GiB margin. Run: PASS.
- [ ] **Step 5:** Implement `scripts/up.sh`: preflight (commands, Docker memory via `docker info --format '{{.MemTotal}}'`), create the cluster only if absent, install metrics-server (pinned version, `--kubelet-insecure-tls` for kind), `kagent --config kagent/kagent-config.yaml install --namespace kagent` with `config.server.grpcReflection: true` and `substrateWorkerPool.template.resources` requests/limits, then wait for `kagent-controller` rollout and WorkerPool ready. Install-time `OPENAI_API_KEY` is set to the literal `not-used` (the default `ModelConfig` it creates is never referenced); document why in a comment. The OpenRouter key is not read by this script.
- [ ] **Step 6:** Implement `scripts/gvisor-check.sh` (creates the `lab-probe` sandbox, runs `dmesg | head` and `uname -a`, asserts gVisor markers, deletes the sandbox) and `scripts/down.sh` (deletes the kind cluster).
- [ ] **Step 7: Verify** from scratch: `mise run down && mise run up && mise run gvisor-check`. Expected: all pods `Running`/`Completed` in `kagent` and `ate-system`; WorkerPool `READY 1`; gvisor-check prints `gVisor: OK`. Re-run `mise run up`: no error, no change.
- [ ] **Step 8:** README: prerequisites (Docker Desktop memory from Step 4, mise), `mise install`, `mise run up`, `mise run gvisor-check`, `mise run down`.
- [ ] **Step 9: Commit** `feat: install kagent and Agent Substrate on kind with a gVisor check`

### Task 3: OpenRouter model and the lab agents

**Files:**
- Create: `kagent/harness.yaml`, `kagent/agent-template.yaml`, `kagent/agents.yaml`, `kagent/modelconfig.yaml`, `scripts/model.sh`
- Modify: `mise.toml` (task `model`), `README.md`

**Interfaces:**
- Consumes: cluster from Task 2; `require_env` (Task 1)
- Produces: Secret `openrouter` (key `OPENROUTER_API_KEY`) and `ModelConfig` `openrouter` in `kagent`; `Harness` `lab-harness` (`spec.kagent: {}`, image pinned by digest as in the kagent docs, `workerPoolRef.name: kagent-default`, `snapshotPolicy.location: s3://ate-snapshots/kagent/`); `AgentTemplate` `lab-assistant` (`modelConfig.name: openrouter`, short French system prompt); Agents `lab-agent-1` … `lab-agent-3`

- [ ] **Step 1:** Implement `scripts/model.sh`: `require_env OPENROUTER_API_KEY OPENROUTER_MODEL`; create/update the Secret with `kubectl create secret generic … --from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --dry-run=client -o yaml | kubectl apply -f - >/dev/null` (no output of the manifest); render the `ModelConfig` model name with `envsubst` limited to `$OPENROUTER_MODEL`; apply harness, template, agents; wait until each Agent reports `Ready`.
- [ ] **Step 2: Verify** `mise run model`, then `kagent agent session create --agent lab-agent-1 -o json` and `kagent agent invoke --session <id> --task "Réponds juste : prêt."`. Expected: a reply. If the provider returns 400, the script prints: model must support tool calling (see `.env.example`).
- [ ] **Step 3: Verify** missing key: `OPENROUTER_API_KEY= mise run model` → fails naming the variable, cluster untouched.
- [ ] **Step 4:** Run `mise run check`. Expected: PASS (no key anywhere).
- [ ] **Step 5:** README section « Brancher le modèle ».
- [ ] **Step 6: Commit** `feat: add OpenRouter model config and lab agents`

### Task 4: Measurement and density

**Files:**
- Create: `scripts/lib/metrics.sh`, `scripts/measure.sh`, `scripts/density.sh`, `tests/metrics.bats`, `tests/fixtures/substrate-summary.json` (from Task 2 spike or a fresh capture), `tests/fixtures/top-pods.txt`
- Modify: `mise.toml` (tasks `measure`, `density`), `README.md`
- Output: `results/density.csv`

**Interfaces:**
- Consumes: Agents from Task 3; grpc reflection on `svc/kagent-controller:8083`
- Produces (`scripts/lib/metrics.sh`, pure):
  - `DENSITY_CSV_HEADER="timestamp,sessions,actors_total,actors_suspended,actors_running,worker_pods,worker_memory_mib"`
  - `mem_to_mib <quantity>` → integer MiB (`512Mi`→512, `1Gi`→1024, `2048Ki`→2)
  - `density_row <summary_json_file> <sessions> <worker_pods> <worker_memory_mib> <timestamp>` → one CSV line; actor counts read from `actorCount` and `actorStatusCounts` (state keys as captured in the fixture)
- Produces: `scripts/measure.sh <sessions>` appends one row to `results/density.csv` (writes the header if the file is new)

- [ ] **Step 1: Write the failing tests** `tests/metrics.bats`: `mem_to_mib` on `512Mi`, `1Gi`, `2048Ki` → `512`, `1024`, `2`; `density_row tests/fixtures/substrate-summary.json 10 1 300 2026-11-14T10:00:00Z` → exactly the expected line built from the fixture's counts (write the literal expected line in the test).
- [ ] **Step 2:** Run `mise exec -- bats tests/metrics.bats`. Expected: FAIL.
- [ ] **Step 3:** Implement `metrics.sh` (jq for JSON, no bash arithmetic on floats).
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Implement `measure.sh` (port-forward in background with a trap that kills it, grpcurl `kagent.api.v1.SystemService/GetSubstrateSummary`, `kubectl top pods -n kagent -l <worker selector>`, append the row) and `density.sh` (for each step in `1 10 30`: create sessions round-robin across the three agents up to the target, wait until all actors are `SUSPENDED`, run `measure.sh`). Re-running continues from the existing session count.
- [ ] **Step 6: Verify** `mise run density`. Expected: three rows; `actors_total` follows 1/10/30 (+ golden actors if counted, note it in README); `worker_pods` stays 1. Also print `kubectl ate get actors --atespace kagent | head`.
- [ ] **Step 7:** README section « Densité » with the expected output shape.
- [ ] **Step 8: Commit** `feat: measure actors versus worker pods across session counts`

### Task 5: Suspend and resume

**Files:**
- Create: `scripts/resume.sh`, `tests/fixtures/worker-restore.log` (real capture), extend `scripts/lib/metrics.sh` and `tests/metrics.bats`
- Modify: `mise.toml` (task `resume`), `README.md`
- Output: `results/resume.csv`

**Interfaces:**
- Consumes: sessions from Task 4; `metrics.sh`
- Produces (`metrics.sh`): `RESUME_CSV_HEADER="timestamp,session,restore_ms"`; `restore_duration_ms <actor_name>` reading worker log lines on stdin → integer ms between `Actor restoring` and `Actor restored` for that actor (first pair)

- [ ] **Step 1:** Capture a real worker log around one invoke into `tests/fixtures/worker-restore.log`.
- [ ] **Step 2: Write the failing test**: `restore_duration_ms session-<id from fixture> < tests/fixtures/worker-restore.log` → the literal value computed by hand from the fixture timestamps; unknown actor → status 1.
- [ ] **Step 3:** Run: FAIL. Implement. Run: PASS.
- [ ] **Step 4:** Implement `resume.sh`: pick 5 suspended sessions, for each: show state (`SUSPENDED`, `WORKER POD <none>`), `kagent agent invoke` a short task, read worker logs since the invoke, append `restore_ms`, confirm the actor is back to `SUSPENDED`; then print the latest `snapshotUri` via `SystemService/ListSubstrateActors`.
- [ ] **Step 5: Verify** `mise run resume`. Expected: 5 rows in `results/resume.csv`, each actor back to `SUSPENDED`, one snapshot URI under `s3://ate-snapshots/kagent/atespaces/kagent/actors/`.
- [ ] **Step 6:** README section « Suspend/resume », stating that the snapshot holds `/data` only and containers restart on resume.
- [ ] **Step 7: Commit** `feat: show suspend/resume and record restore durations`

### Task 6: Isolation and egress

**Files:**
- Create: `scripts/isolation.sh`, `kagent/egress-policy.yaml`
- Modify: `mise.toml` (task `isolation`), `README.md`

**Interfaces:**
- Consumes: `lab-probe` sandbox template and `gvisor-check.sh` (Task 2); `lab-agent-1` (Task 3)
- Produces: `EgressPolicy` `lab-allow-example` (`spec.destinations[].origin: https://example.com`), referenced by `lab-agent-1` via `spec.egressPolicyRefs` only during the demo

- [ ] **Step 1:** Implement `isolation.sh`, deterministic part (all assertions must pass, exit 1 otherwise):
  1. gVisor: reuse `gvisor-check.sh`.
  2. Egress refused: from the `lab-probe` sandbox, `/dev/tcp` to `example.com:443` fails; `kubectl logs -n ate-system deploy/atenet-egress -c agentgateway --since=1m` contains `http.status=403` and `reason=Authorization`.
  3. Egress allowed: apply `lab-allow-example`. If a `SandboxTemplate` can reference an egress policy, attach it to `lab-probe` and assert the same probe now succeeds. Otherwise attach it to `lab-agent-1`, assert only the condition `EgressPoliciesApplied=True` here, and move the "probe succeeds" check to the agent-driven part (Step 2). Detach and delete the policy at the end (idempotent).
- [ ] **Step 2:** Agent-driven illustration (non-blocking, up to 3 attempts, prints the reply): ask `lab-agent-1` to run `uname -a` and `env | grep -i -E 'key|authorization' || echo none` with its bash tool. Script asserts the reply contains no `sk-or-` and reports `OK` / `model did not run the tool` without failing.
- [ ] **Step 3: Verify** `mise run isolation` twice in a row. Expected: both runs pass, no leftover `EgressPolicy`.
- [ ] **Step 4:** Run `mise run check`. Expected: PASS.
- [ ] **Step 5:** README section « Isolation ».
- [ ] **Step 6: Commit** `feat: demonstrate gVisor isolation, closed egress and credential injection`

### Task 7: End-to-end run and reader guide

**Files:**
- Modify: `README.md` (complete French guide), `mise.toml` (task `all` = up, model, density, resume, isolation)
- Output: committed `results/density.csv`, `results/resume.csv` from a clean run

- [ ] **Step 1:** From scratch: `mise run down && mise run all`. Expected: completes without manual step; note wall-clock time and peak Docker memory.
- [ ] **Step 2:** README final: purpose (link placeholder to the article), prerequisites with measured memory and time, outbound Internet access (nodes download the gVisor artefact), `.env` setup, one section per `mise run` step with expected output, troubleshooting (gVisor, memory, model without tool calling, port 8083 busy), cleanup, licence. No article copy (the article lives on the blog only).
- [ ] **Step 3:** `mise run check`. Expected: PASS.
- [ ] **Step 4: Commit** `docs: complete the lab guide and commit reference measurements`
- [ ] **Step 5:** Stop. Report to Thomas: results summary, the worker-capacity observation (many actors on one worker or not), and ask for approval to create `gravitek-io/lab-agents-workload-kubernetes` and push.
