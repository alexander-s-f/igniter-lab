# LAB-IGNITER-WEB-READTHEN-EFFECTHOST-DOC-SWEEP-P32 - fix current stale claims only

Status: ✅ CLOSED — 2026-06-23
Lane: IgWeb / docs hygiene / stale blocker removal
Type: documentation sweep
Delegation code: OPUS-WEB-READTHEN-EFFECTHOST-DOC-SWEEP-P32
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P31 should create the current implemented-surface front door. This card removes the most confusing
current stale claims around `ReadThen` and `MachineEffectHost` so agents stop routing around features
that already exist.

This is a narrow sweep. Historical proof docs are not fake history; they should remain historical
unless they are front-door docs or actively used as current status.

## Goal

Search current docs, examples, test headers, and active status files for stale current-tense claims
about:

- `ReadThen` not existing;
- `ReadThen` only harness-proven;
- `InvokeEffect` observed only everywhere;
- `MachineEffectHost` not wired to runner;
- subprocess/local Postgres E2E manual-only;
- host config not active.

Fix only current-status surfaces and misleading active comments. Leave historical reports intact.

## Verify first

Run and classify:

```text
rg -n "ReadThen|read then|observed only|observed `InvokeEffect`|no live effect|not implemented|not yet|manual only|fake-only|sync-only|MachineEffectHost|EffectHost|host.toml|host-config" \
  server/igniter-web lab-docs/STATUS.md lab-docs/igniter-lab-project-map.md .agents/work/cards/lang
```

Classification:

- **Fix**: README, `IMPLEMENTED_SURFACE.md`, `lab-docs/STATUS.md`, active example comments, active test
  module comments that describe today's behavior incorrectly.
- **Leave**: old readiness/proof card closing reports where the filename/date makes the history clear.
- **Annotate only if needed**: a historical card that is often mistaken as current backlog.

## Acceptance

- [x] Closing report lists search patterns and top stale hits.
- [x] Active docs/comments no longer say `ReadThen` is absent or harness-only.
- [x] Active docs/comments distinguish sync observed mode from async machine execution mode.
- [x] Active docs/comments say final `InvokeEffect` can execute through `MachineEffectHost` in host-config mode.
- [x] Historical reports are not rewritten wholesale.
- [x] Any remaining scary-looking stale hit is classified as historical/out-of-scope in the closing report.
- [x] `git diff --check` clean.

## Closed surfaces

- No code behavior changes.
- No broad archaeology.
- No canon/public stability claim.
- No edits to unrelated language/runtime docs.

## Closing report

**Date:** 2026-06-23

### Search Patterns Used
Ran ripgrep with the following pattern:
`rg -n "ReadThen|read then|observed only|observed \`InvokeEffect\`|no live effect|not implemented|not yet|manual only|fake-only|sync-only|MachineEffectHost|EffectHost|host.toml|host-config"`
across `server/igniter-web`, `lab-docs/STATUS.md`, `lab-docs/igniter-lab-project-map.md`, and `.agents/work/cards/lang`.

### Findings & Top Stale Hits
1. **Source Comments**: Found one out-of-date comment inside `server/igniter-web/src/bin/igweb-serve.rs` on line 151 referring to `InvokeEffect` from a continuation being "the next card". This has been replaced with: `// 3. Build a default no-op effect host (fallback path when no write binding is configured)`.
2. **Active Docs & Tests**:
   - `server/igniter-web/IMPLEMENTED_SURFACE.md` accurately describes the current implemented state of `ReadThen`, `StagedReadHost`, `MachineEffectHost` and `host.toml`, clearly distinguishing sync observed mode from async machine execution mode.
   - `server/igniter-web/README.md` and `lab-docs/STATUS.md` are clean of stale claims due to previous hygiene sweeps.
   - Active test comments (in `todo_postgres_app_tests.rs`, `todo_postgres_effect_host_tests.rs`, and `readthen_socket_runner_tests.rs`) accurately capture their specific scope (e.g. sync observed vs async machine-mode Postgres execution) and are not misleading.
3. **Historical / Out-of-Scope Files**: Historical reports and readiness documents under `.agents/work/cards/lang/` and `lab-docs/lang/` (e.g., `lab-igniter-machine-host-io-substrate-readiness-p1-v0.md` or `lab-igniter-web-readthen-runner-readiness-p10-v0.md`) contain historical BACKLOG comments, which have been left untouched under the Historical Docs Rule (defined in `IMPLEMENTED_SURFACE.md` and `STATUS.md`).

### Verification & Compliance
- Checked `git diff --check` - clean.
- Verified that all crate and runner unit/integration tests are 100% green with `cargo test --features machine`.
