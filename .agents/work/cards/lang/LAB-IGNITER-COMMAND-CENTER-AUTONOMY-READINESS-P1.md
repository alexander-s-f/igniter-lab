# LAB-IGNITER-COMMAND-CENTER-AUTONOMY-READINESS-P1 — `igniter` as autonomous command center across Dev / DX / DevOps

Status: CLOSED
Lane: distribution / command center / autonomy
Type: readiness / architecture
Delegation code: OPUS-IGNITER-COMMAND-CENTER-AUTONOMY-READINESS-P1
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

Igniter has crossed an important threshold:

- Core crates have been flattened in `igniter-lab` and mirrored into team-facing repos.
- `bin/igniter` already acts as the front door for `serve`, `check`, `doctor`, `toolchain`, `package`,
  `app bundle`, `agent`, `env`, and `stdlib` delegation.
- `bin/igniter-install` exists as a source-checkout bootstrap installer.
- TBackend distribution work proved that team DX improves dramatically when installation, smoke checks,
  Docker/systemd packaging, and release manifests are explicit.
- The mirror workflow proved that granular repos are good for review/onboarding, but bad DX if every user
  must remember the whole dependency graph manually.

The design pressure now is **autonomy**: a developer, app author, or operator should not need to know the
internal layout to get a working Igniter environment.

We need to decide whether the ecosystem should move toward:

1. a merged `igniter` / `igniter-core` repository, or
2. a convention + command-center repo/tool that knows how to clone/update/build/test/deploy the granular
   pieces.

The current hypothesis from curation is: **do not collapse the core crates into one code blob; keep granular
ownership, but promote `igniter` into the durable command center / toolchain supervisor.** This card must test
that hypothesis against live files, not assume it.

## Three axes to support

This packet must explicitly support all three axes below.

### 1. Dev — easy to develop Igniter itself

A core contributor should be able to work on compiler/stdlib/vm/machine/tbackend without remembering brittle
sibling paths or mirror details.

Desired posture:

```text
igniter workspace status
igniter workspace sync
igniter workspace build
igniter workspace test
igniter workspace doctor
```

Questions: what owns checkout layout, mirror remotes, branch drift, dependency graph checks, and the bounded
core test matrix?

### 2. DX — easy to install an environment and develop on Igniter

An app author should be able to install the toolchain, run `igniter doctor`, create/check/serve an app, inspect
stdlib docs, and package a local app without knowing which binary implements which verb.

Desired posture:

```text
igniter toolchain install/update/list
igniter doctor
igniter check <app>
igniter serve <app>
igniter stdlib search ...
igniter package lock/verify
```

Questions: what remains `bin/igniter-install` bootstrap-only, what becomes `igniter toolchain ...`, and when
should shell be replaced by a Rust CLI?

### 3. DevOps — easy to deploy/stage/prod

An operator should be able to produce a bundle, verify/admit it, check env, and hand it to systemd/Docker/AWS
without embedded secrets or unclear authority.

Desired posture:

```text
igniter app bundle
igniter app admit
igniter env template/check/doctor
igniter deploy plan        # if recommended; not necessarily v0
igniter doctor --json      # machine-readable for CI/MCP
```

Questions: what does command center own, and what must remain host/operator-owned: secrets, DSNs, public bind,
TLS, systemd units, Docker image publishing, AWS resources?

## Goal

Write a readiness packet that decides the next architecture of the Igniter command center.

This is **not** a code card. Do not implement the supervisor, do not rewrite shell scripts, and do not merge
repositories. Produce a grounded decision packet and name the next implementation cards.

## Verify first

Read live files, not stale docs:

- `bin/igniter`
- `bin/igniter-install`
- `bin/push-*-mirror`
- root `README.md`, `MAP.md`, `STATUS.md` if present
- `LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6`
- `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`
- `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`
- `LAB-DISTRIBUTION-DOCTOR-*`
- `LAB-DISTRIBUTION-APP-BUNDLE-*`
- `LAB-DISTRIBUTION-DEVOPS-DEPLOY-READINESS-P31`
- `LAB-IGNITER-MIRROR-CRATE-LINKING-READINESS-P1`
- `LAB-IGNITER-MONOREPO-FLATTEN-CORE-P2`
- `LAB-IGNITER-MIRROR-MACHINE-DEVDEP-RECONCILE-P3`
- Current `Cargo.toml` path topology for:
  - `igniter-stdlib`
  - `igniter-compiler`
  - `igniter-vm`
  - `igniter-machine`
  - `igniter-tbackend`
- Current mirror remotes and helper scripts.

Also verify the latest live fact from curation:

- Fresh mirror checkout works only with `igniter-lang` as canon sibling plus the five core mirrors.
- `igniter-machine` tests are now mirror-local for fleet fixtures.
- `igniter-compiler` still compile-time reads canon `igniter-lang/docs/spec/stdlib-inventory.json`.

If any of these facts drift, update the packet with live truth.

## Questions to answer

1. Should we merge the core crates into `igniter`/`igniter-core`, or keep granular repos with a command-center
   supervisor? Compare at least three options:
   - full repo merge;
   - granular repos + `igniter` command center;
   - separate `igniter-toolchain` / orchestration repo;
   - optional hybrid.
2. What is the exact desired checkout layout for contributor Dev?
   - one root with `igniter-lang` + `core/*`?
   - one flat core plane?
   - current `igniter-lab` monorepo as source of truth plus mirrors?
3. What commands should `igniter workspace ...` own in v0?
4. What commands should `igniter toolchain ...` own in v0 vs later?
5. What commands should `igniter app ...` and `igniter deploy ...` own, and what should stay outside?
6. What is the future of `bin/igniter-install`?
   - keep bootstrap-only;
   - subsume into `igniter toolchain install`;
   - replace with downloadable standalone `igniter` binary;
   - keep as source-checkout fallback.
7. Is shell still acceptable for v0, or has `bin/igniter` crossed the threshold where a Rust CLI is required?
8. What should be the stable machine-readable contract for agents/CI?
   - `--json` output shape;
   - structured error codes;
   - MCP tool responses.
9. How does command center avoid becoming a second package manager, second deploy system, or hidden authority
   layer?
10. What are the smallest next cards that give immediate value without overbuilding?

## Design constraints

- Preserve granular crate boundaries unless evidence strongly supports merging.
- Preserve owner authority:
  - `igweb-serve` owns loopback/public-bind/request-bound checks.
  - `igc` owns package lock/verify/admit and stdlib/canon provenance.
  - `igniter-machine` owns host capability execution and receipts.
  - host/operator owns secrets, DSN, TLS, public exposure, systemd/Docker/AWS resources.
- `igniter` command center may orchestrate and report, but must not silently grant authority.
- Do not introduce registry/semver/signing in this readiness card.
- Do not break current source checkout workflows.
- Keep Dev, DX, and DevOps separate in the packet; do not collapse them into one vague “install” story.
- Keep lab/canon/private/prod boundaries explicit.

## Expected packet shape

Write:

`lab-docs/lang/lab-igniter-command-center-autonomy-readiness-p1-v0.md`

Recommended structure:

1. Executive decision.
2. Live surface verified.
3. Three-axis requirements table: Dev / DX / DevOps.
4. Options compared.
5. Recommended architecture.
6. Proposed command taxonomy.
7. Bootstrap/update lifecycle.
8. JSON/MCP/CI contract.
9. Authority boundaries and non-goals.
10. Next implementation wave.

Include at least one table like:

| Axis | User | Success path | Command-center responsibility | Owner authority |
| --- | --- | --- | --- | --- |
| Dev | Igniter contributor | clone/sync/build/test core | workspace graph + checks | crates own build/tests |
| DX | app author | install/check/serve/package | toolchain + app front door | igweb/igc own enforcement |
| DevOps | operator | bundle/admit/env/deploy plan | manifests + checks + handoff | host owns secrets/exposure |

## Acceptance

- [x] Packet written under `lab-docs/lang/`.
- [x] Packet verifies live `bin/igniter` and `bin/igniter-install` behavior.
- [x] Packet explicitly compares merge vs command-center orchestration.
- [x] Packet covers all three axes: Dev, DX, DevOps.
- [x] Packet names a recommended architecture.
- [x] Packet names which commands belong under `igniter workspace`, `igniter toolchain`, `igniter app`, and optional `igniter deploy`.
- [x] Packet decides the v0 role of `igniter-install`.
- [x] Packet decides whether the next implementation should remain shell or start a Rust CLI.
- [x] Packet defines machine-readable output expectations for CI/MCP where relevant.
- [x] Packet lists explicit non-goals.
- [x] Packet names 2-4 concrete next cards with suggested order.
- [x] No production code changes.
- [x] No repo merge.
- [x] No `Cargo.toml` rewrites.
- [x] `git diff --check` clean.

## Suggested next-card names

Use or revise after evidence:

- `LAB-IGNITER-WORKSPACE-SUPERVISOR-READINESS-P2`
- `LAB-IGNITER-WORKSPACE-STATUS-SYNC-P3`
- `LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P4`
- `LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P5`
- `LAB-IGNITER-TOOLCHAIN-LIFECYCLE-P6`

## Closing report

**Date:** 2026-07-01 · Packet: `lab-docs/lang/lab-igniter-command-center-autonomy-readiness-p1-v0.md`

**Decision.** Keep granular core crates + mirrors; **do not merge** into `igniter-core`. Promote `igniter`
to the durable command center and close the one real gap: add an **`igniter workspace …` Dev lane**. DX and
DevOps lanes are already built in `bin/igniter` (shell) and verified live; Dev is the only axis with no
front-door command (its knowledge is scattered across six `bin/push-*-mirror` helpers). Options A (merge),
C (separate toolchain repo) rejected; B (command center) recommended on a Hybrid (D) trajectory.

**Live surface verified.** `bin/igniter` (1183 lines, shell): verbs serve/check/doctor/toolchain/package/app/
agent/env/stdlib/explain — **no `workspace`**, flatten-correct, `LANG_SIBLING=../igniter-lang`. `doctor
--json` already emits `{scope,check,severity,detail,suggest}` records (source-checkout vs installed-prefix
modes). `bin/igniter-install`: bootstrap-only, 5-binary fleet, flatten-correct, needs canon inventory. `agent`
exposes 8 non-mutating MCP tools. Prior wave P6/P7/P8/P10/P14/P27/P31 all CLOSED (P27 = MCP shape C).

**Curation facts re-verified (1 corrected).** (1) mirror checkout = `igniter-lang` canon + 5 core — CONFIRMED
by strict probe (renamed frame-ui AND apps away → machine `--no-default-features` = 366 pass / 1 known-flaky).
(2) machine fleet fixtures now **mirror-local** at `igniter-machine/tests/fixtures/fleet_apps/` — CONFIRMED,
**corrects** a stale note that still pointed at root `apps/igniter-apps`. (3) compiler compile-time reads canon
`stdlib-inventory.json` — CONFIRMED (the one hard cross-repo edge).

**Shell vs Rust.** Shell is fine for the immediate `workspace` addition (git+cargo orchestration; ~22 wrapper
tests protect the front door). It has crossed the threshold **only for structured output** (hand-rolled JSON
via `json_escape`/`doc_emit` + `grep -oE` JSON parsing) → Rust-CLI readiness opened in parallel, evidence-
gated, NOT a rewrite mandate.

**`igniter-install` v0 role.** Keep **bootstrap-only** (chicken-and-egg: can't `igniter toolchain install`
before `igniter` is on PATH). Standalone downloadable binary = a later channel tied to the Rust-CLI decision.

**Next cards (order P2 → P3 → P4 → P5, revised from the suggestions after evidence):**
`LAB-IGNITER-WORKSPACE-STATUS-DOCTOR-P2` (read-only status/doctor over flat core + mirrors), then
`LAB-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3` (bounded core test matrix; optional gated `sync`), then
`LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4` (unify diagnostic-record + shape-C + error codes), then
`LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P5` (Rust-CLI + standalone-binary evaluation).

**Scope honored:** no code, no repo merge, no `Cargo.toml` rewrites; authority unmoved; `git diff --check`
clean. (Temporarily renamed `frame-ui/` + `apps/` for the strict mirror probe; both restored intact.)
