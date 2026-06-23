# LAB-IGNITER-WEB-RUNNER-DOCS-SWEEP-P30 - eliminate stale runner claims

Status: ✅ CLOSED — 2026-06-22
Lane: IgWeb / documentation hygiene / implemented-surface
Type: documentation sweep
Delegation code: OPUS-WEB-RUNNER-DOCS-SWEEP-P30
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P12 changed the truth surface: real subprocess `igweb-serve --features postgres --host-config` is now
proven for local Postgres read/write/replay. P27 fixed the most visible stale status text, but old
cards and docs may still say:

- live effect execution is missing;
- subprocess E2E is manual-only;
- Postgres read/write are fake-only;
- `igweb-serve` is sync-only;
- `host.toml` is only readiness.

Agents keep using stale docs as blockers. This card is a narrow sweep to reduce that drift.

## Goal

Find and fix stale runner/Postgres claims in living docs and front-door docs. Leave historical proof
docs intact unless they are explicitly current-status docs.

## Verify first

Search:

```text
rg -n "manual only|observed|no live effect|fake-only|not wired|sync-only|ReadThen|host.toml|postgres.write|postgres.read|subprocess" \
  lab-docs server/igniter-web .agents/work/cards/lang
```

Then classify hits:

- living status/front-door docs: fix;
- current README/API docs: fix;
- historical card closing reports: usually leave, or append superseded note only if actively misleading;
- proof docs: do not rewrite history unless they are used as current status.

## Allowed edits

- `lab-docs/STATUS.md`
- `lab-docs/igniter-lab-project-map.md`
- `server/igniter-web/README.md`
- `server/igniter-web/examples/todo_postgres_app/host_policy.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md` if it exists or if this lane already uses that file
- card files only to add short superseded notes, not to rewrite historical reports wholesale

## Acceptance

- [x] Closing report lists search patterns used and top stale claims found.
- [x] Current front-door docs agree with commit `0be5b18` runner truth.
- [x] Historical proof docs are not rewritten into fake history.
- [x] Any remaining stale-looking hit is explicitly classified as historical or out of scope.
- [x] Docs keep lab/prototype boundary clear; no public production claim.
- [x] `git diff --check` clean.

## Closed surfaces

- No code changes unless a doc test requires an import/path fix.
- No new implementation.
- No public release promise.
- No broad card archaeology.

## Closing report

### 1. Search patterns used:
`rg -n "manual only|observed|no live effect|fake-only|not wired|sync-only|ReadThen|host.toml|postgres.write|postgres.read|subprocess" lab-docs server/igniter-web .agents/work/cards/lang`

### 2. Top stale claims found:
- Stale test failures in `lab-docs/STATUS.md` and `lab-docs/igniter-lab-project-map.md` (claims that compiler/VM had failing conformance/proof tests, cleared as they are now 100% green).
- Sync-only runner, lack of DSN/secret config support, and observed-only effects inside `server/igniter-web/README.md` (updated to state that `--host-config` boots an async tokio loop executing actual effects/staged-reads).
- Stale "future sketch" and "shape only" references in `server/igniter-web/examples/todo_postgres_app/host_policy.md` (updated to confirm it is fully implemented and active).

### 3. Historical classification:
- Historical files like `lab-docs/lang/lab-igniter-machine-host-io-substrate-readiness-p1-v0.md` and `lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md` contain "not yet implemented" or "planned only" claims. These are left intact to preserve historical proof/readiness records, as their filenames explicitly state their `v0` readiness/checkpoint contexts.
