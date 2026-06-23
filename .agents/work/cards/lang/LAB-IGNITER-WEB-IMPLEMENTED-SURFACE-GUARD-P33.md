# LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-GUARD-P33 - lightweight guard against future stale blockers

Status: CLOSED
Lane: IgWeb / implemented surface / guardrail
Type: narrow test or script, with docs-only fallback
Delegation code: OPUS-WEB-IMPLEMENTED-SURFACE-GUARD-P33
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P31/P32 should make the current surface clear. The recurring failure mode is that a future agent greps
old docs, sees "deferred", and reinvents or blocks work that live code already supports.

We need a small guardrail, not a process machine.

## Goal

Add the smallest maintainable guard that helps future agents verify the implemented surface before
trusting stale docs.

Possible acceptable outcomes:

1. A small script, for example `server/igniter-web/scripts/check_implemented_surface.sh`, that runs
   the bounded evidence commands and prints a compact receipt.
2. A tiny Rust test that ensures `IMPLEMENTED_SURFACE.md` exists and references the current evidence
   anchors (`ReadThen`, `MachineEffectHost`, `host.example.toml`, `todo_postgres_smoke.sh`, diagnostics).
3. A docs-only fallback if a test/script would create more noise than clarity, with a strong closing
   rationale.

Prefer option 1 only if it is genuinely useful and fast. Prefer option 2 only if it avoids brittle prose
matching. Do not create a guard that fails every time wording changes.

## Verify first

Read:

- `server/igniter-web/IMPLEMENTED_SURFACE.md` (from P31)
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/tests/igweb_serve_diagnostics_tests.rs`
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
- `server/igniter-web/tests/readthen_socket_runner_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/README.md`

If P31 is not closed yet, stop with a dependency note rather than inventing a second surface file.

## Suggested evidence receipt

If implementing a script, it may print:

```text
implemented-surface: ReadThen dispatch tests ok
implemented-surface: socket runner tests ok
implemented-surface: diagnostics tests ok
implemented-surface: host example parses ok
implemented-surface: default tree postgres-free ok
```

Keep it bounded. Do not require a live DB by default.

## Acceptance

- [x] Closing report states which guard shape was chosen and why.
- [x] Guard starts from `IMPLEMENTED_SURFACE.md`, not old proof docs.
- [x] Guard is fast and does not require `IGNITER_TODO_PG_DSN`.
- [x] Guard verifies at least ReadThen, MachineEffectHost/effect path, host example parsing, and diagnostics.
- [x] Guard does not turn historical docs into failures.
- [x] README or `IMPLEMENTED_SURFACE.md` tells agents how to run it.
- [x] Existing `cargo test --features machine` remains green.
- [x] `git diff --check` clean.

## Closed surfaces

- No live DB requirement.
- No full repo CI policy.
- No public stability promise.
- No broad linter over all lab docs.

## Closing report

**Date:** 2026-06-23

### Chosen shape: option 1 (script) as headline + a tiny option-2 test for anti-rot

Both, kept minimal, because they cover different failure modes:

- **`server/igniter-web/scripts/check_implemented_surface.sh` (option 1, headline).** The genuinely
  useful guard: a future agent who finds a stale "deferred / observed only" doc runs ONE command and
  gets a `implemented-surface: … ok` receipt proving the surface is *live*. It starts from
  IMPLEMENTED_SURFACE.md (fails fast if the front door is missing), then runs the bounded evidence the
  doc cites. Fast (~1.3s on a warm build), no `IGNITER_TODO_PG_DSN`, no live DB. It reads/grades NO
  historical doc, so old prose can never make it fail.
- **`server/igniter-web/tests/implemented_surface_guard_tests.rs` (option 2, anti-rot).** Two tiny
  feature-free tests that run inside every `cargo test`: the front door exists and still names its
  STABLE anchors (code identifiers / file names: `ReadThen`, `dispatch_with_read`, `StagedReadHost`,
  `MachineEffectHost`, `host_config`, `host.example.toml`, `todo_postgres_smoke.sh`, `runner_diag`,
  `check_implemented_surface.sh`, `cargo test`), and the guard script exists. These are identifiers,
  not prose, so wording changes never fail the test — it only fires if the front door is deleted/gutted
  or the script disappears. This is the piece the script can't provide (the script isn't auto-run).

Rationale for both vs one: the script proves behavior on demand but is not run by CI/`cargo test`; the
test is auto-run but only proves the doc/script exist. Together they are still small and close the loop
(doc cites script → test guards both → script verifies behavior).

### What the script checks (receipt lines)

```
implemented-surface: front door IMPLEMENTED_SURFACE.md present ok
implemented-surface: ReadThen dispatch tests ok          # readthen_dispatch_tests
implemented-surface: socket runner tests ok              # readthen_socket_runner_tests
implemented-surface: effect path (MachineEffectHost) tests ok  # async_machine_runner_tests
implemented-surface: diagnostics tests ok                # igweb_serve_diagnostics_tests
implemented-surface: host example parses ok              # cargo test --lib host_config
implemented-surface: default tree postgres-free ok       # cargo tree -e normal has no tokio-postgres
implemented-surface: PASS
```

### Files changed

- **NEW** `server/igniter-web/scripts/check_implemented_surface.sh` (chmod +x).
- **NEW** `server/igniter-web/tests/implemented_surface_guard_tests.rs` (2 feature-free tests).
- **M** `server/igniter-web/IMPLEMENTED_SURFACE.md` — "Evidence commands" now leads with the
  one-command guard and how to run it.

No production code or behavior changed.

### Acceptance

- Guard shape chosen + rationale stated above.
- Guard starts from IMPLEMENTED_SURFACE.md (script step 0; test asserts it exists), not old proof docs.
- Fast; needs no `IGNITER_TODO_PG_DSN`; no live DB.
- Verifies ReadThen, MachineEffectHost/effect path, host example parsing, and diagnostics (plus the
  postgres-free default-tree boundary).
- Reads no historical doc → cannot turn old docs into failures.
- IMPLEMENTED_SURFACE.md tells agents how to run it (and points to the script).
- `cargo test --features machine` green (includes the new always-on guard tests); script PASS, exit 0.
- `git diff --check` clean.

### Scope honored

No live-DB requirement, no full-repo CI policy, no public stability promise, no broad lab-doc linter.
