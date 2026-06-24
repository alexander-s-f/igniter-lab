# LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-REFRESH-P42 - refresh IgWeb implemented surface after product hardening

Status: DRAFT
Lane: IgWeb / implemented surface / actualization
Type: documentation + evidence index
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`server/igniter-web/IMPLEMENTED_SURFACE.md` was created in P31 as the code-anchored answer for
ReadThen / EffectHost / `igweb-serve` / host config. Since then, the runner and TodoApp lines moved:

- `igweb-serve` read/write bindings are closed (`P25`/`P26`);
- local Postgres and Todo API product smoke are closed (`P12`/`P13` and follow-ups);
- Todo API request-body/id/account/error/product-surface cards (`P35`-`P41`) clarified the app-facing surface;
- hygiene cards (`P29`-`P33`) clarified diagnostics and implemented-surface guardrails.

Agents should not rediscover old "not implemented" claims from readiness docs. This card refreshes the front
door against live source and tests.

## Goal

Update the IgWeb implemented-surface front door so it accurately answers:

```text
What is implemented today in IgWeb runner / ReadThen / EffectHost / host-config / Todo API product path,
and what is still explicitly not implemented?
```

## Verify First

Read live source and tests before editing docs:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/tests/*read*`
- `server/igniter-web/tests/*postgres*`
- `server/igniter-web/tests/*diagnostics*`
- `examples/todo_postgres_app/` (or current Todo API example path)
- recent cards `P25`/`P26`/`P35`-`P41`

Live source wins over old proof docs. If a doc says "deferred" but code/tests prove it, update the doc surface,
not the plan.

## Required Output

- Refresh `server/igniter-web/IMPLEMENTED_SURFACE.md`.
- If needed, update only a short pointer in `server/igniter-web/README.md` or nearby status doc.
- Add a small proof doc only if the implemented surface needs a durable summary beyond the package-local file.

## Required Sections

Keep the front door compact:

1. Implemented today:
   - sync observed mode;
   - async machine mode;
   - `ReadThen` categories (`designed`, `harness-proven`, `implemented`, `runner-integrated`);
   - read bindings;
   - write/effect bindings;
   - host config schema and env interpolation rules;
   - Todo API local-Postgres / product-smoke status;
   - diagnostics / failure taxonomy.
2. Still closed / not production promise:
   - public listener deployment;
   - pool/backpressure;
   - migrations;
   - typed row destructuring if still absent;
   - stable public CLI contract if still lab-only.
3. Evidence commands:
   - exact test names and commands that prove the current surface.
4. Historical docs rule:
   - old readiness docs are evidence, not current backlog.

## Acceptance

- [ ] `IMPLEMENTED_SURFACE.md` matches live source after P25/P26/P35-P41.
- [ ] `ReadThen` status uses the exact categories and does not overclaim layers.
- [ ] Read/write binding status is source-backed and feature-gated accurately.
- [ ] Todo API product path status is summarized without copying app docs wholesale.
- [ ] Evidence commands are current and runnable or explicitly marked gated/skipped.
- [ ] No behavior changes.
- [ ] `git diff --check` clean.

## Closed Surfaces

- No production code changes unless a doc import/test name is broken.
- No canon/public stability promise.
- No broad stale-doc rewrite; make this front door authoritative for agents instead.

## Suggested Next

If stale claims are found in multiple docs, open a follow-up hygiene card. Do not fix the whole doc tree here.
