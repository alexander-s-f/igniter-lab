# LAB-IGNITER-WEB-RUNNER-STATUS-HYGIENE-P27 - sync runner truth after P23-P26

Status: CLOSED — 2026-06-22
Lane: IgWeb / docs hygiene / implemented surface
Type: hygiene / documentation
Delegation code: GEMINI-WEB-RUNNER-STATUS-HYGIENE-P27
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

The runner line moved quickly:

- async machine mode;
- staged reads;
- host-config read/write policy;
- fake extracted-core Todo E2E;
- real Postgres read/write wiring.

Agents are starting to confuse:

- actual `igweb-serve` subprocess behavior;
- extracted binary core behavior;
- fake adapters;
- local Postgres adapters;
- stable CLI vs lab-only runner.

This card is a hygiene pass after P25/P26 or alongside them if drift is already obvious.

## Goal

Update the smallest set of docs/status files so future agents can answer:

1. What does `igweb-serve --host-config` actually do today?
2. Which parts are proven with fake adapters?
3. Which parts are proven with local Postgres?
4. Which parts are actual subprocess CLI vs extracted runner core?
5. What remains lab-only / not stable CLI?

## Verify first

Read live code and tests:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/todo_igweb_serve_e2e_tests.rs`
- any new P25/P26/P12 tests if they exist.

Then search docs for stale claims:

```text
rg -n "executor not yet wired|fake adapter|extracted binary core|actual igweb-serve|ReadThen|host-config|stable CLI|not stable" server/igniter-web lab-docs .agents/work/cards/lang
```

## Allowed

- Update README / lab docs / current status docs in `igniter-lab`.
- Update card closing reports only if they contain a factual stale claim.
- Add a compact status table if no current one exists.

## Closed

- No code changes.
- No test changes.
- No new runner behavior.
- No public stability claim.
- No rewriting old research docs wholesale; add supersession notes instead.

## Acceptance

- [x] Status table distinguishes actual binary, extracted core, fake adapters, local Postgres, and stable/public CLI.
- [x] Stale "not implemented" / "deferred" claims are either corrected or marked superseded with dates.
- [x] Docs do not overclaim subprocess E2E if only extracted core is proven.
- [x] Docs do not overclaim live DB if only fake adapters are proven.
- [x] `igweb-serve` remains marked lab-only / not stable CLI unless a separate authority card changed that.
- [x] `git diff --check` clean.

## Next

This is not a feature card. It should reduce agent uncertainty before the next implementation wave.

## Closing report

**Date:** 2026-06-22

Updated the compact runner truth tables in `lab-docs/STATUS.md` and `server/igniter-web/README.md`.
During curation, P12 superseded the first hygiene wording: subprocess CLI E2E is now **proven** under the
`postgres` feature with `IGNITER_TODO_PG_DSN`, not manual-only. Real Postgres read/write are now marked
**wired + proven** through `igweb-serve --host-config`, while the CLI remains lab-only / not stable public API.
