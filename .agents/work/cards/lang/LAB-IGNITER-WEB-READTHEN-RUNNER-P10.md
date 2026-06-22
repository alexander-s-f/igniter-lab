# LAB-IGNITER-WEB-READTHEN-RUNNER-P10 - staged read continuation runner readiness

Status: CLOSED
Lane: IgWeb / read host / runner
Type: readiness / design
Delegation code: OPUS-IGNITER-WEB-READTHEN-RUNNER-P10
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- read-host harness proved `QueryPlan -> host read executor -> rows_json -> continuation`.
- write/effect-host runner contour is closed separately.
- Todo local Postgres e2e proved the real adapter path.

The missing web runner seam is staged read: the app needs data before returning the final `Decision`, so a pure guard cannot perform IO.

## Goal

Design the smallest staged read/continuation runner seam that can be implemented safely.

Expected shape from prior readiness:

```text
Decision::ReadThen { plan, then }
  -> host validates and executes QueryPlan
  -> host dispatches continuation with rows
  -> continuation returns final Decision
```

But live code wins; verify whether a different shape is now smaller.

## Verify first

Read:

- `lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md`
- `server/igniter-web/tests/todo_postgres_read_host_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_read_tests.rs`
- `server/igniter-web/src/lib.rs`
- `lang/igniter-compiler/src/igweb.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- runner/bin code in `server/igniter-web`.

Confirm:

- whether a `ReadThen` arm exists already;
- how `Decision` is represented in the injected IgWeb prelude today;
- whether continuation dispatch can be done without nested `block_on`;
- how read failures map to app vs host errors;
- how rows should travel in v0 (`String` JSON vs typed row values).

## Required design answers

- Exact `Decision` arm shape, or an alternative if live code suggests one.
- Continuation signature and argument order.
- Host error mapping: denied/permanent/retry/unknown.
- Runner config shape and authority boundary.
- Interaction with render/write effects after continuation.
- Tests required for found, empty/app-404, denied-before-adapter, clamp, raw SQL refusal.

## Acceptance

- [x] A single next implementation card is named with acceptance tests.
- [x] The design preserves app/domain ownership of not-found decisions.
- [x] The host owns source/field policy, clamp, adapter, DSN, and infra failures.
- [x] No hidden DB authority enters `via` or pure guards.
- [x] No implementation code unless explicitly justified as doc-only correction.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-22)

**Deliverable:** `lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md` — readiness packet,
**no code** (`git diff` clean; only the packet + this card). Caught up on the post-break state first.

**Verify-first (live, post-break):** no `ReadThen` arm yet; `Decision` now has 5 arms + a generic
**`Unknown`** payload type (`InvokeEffect.input : Unknown`); `IgWebServerApp::call` is **sync** with an
internal per-instance `block_on` (`lib.rs:106,119`); staged read works **only in `#[cfg(feature="machine")]`
harnesses** (one outer runtime, two `machine.dispatch().await`, no nesting, bypassing `call`); read executor
`PostgresReadResult{Rows/Unavailable/Transient/QueryError}`→succeeded/unknown/retryable/permanent; the
runner (`igweb-serve serve_loop`) drives neither reads nor effects.

**Design answers:**
- **Arm (smaller than P5):** `ReadThen { plan : Unknown, then : String }` — reuse `Unknown` for the
  app-built QueryPlan JSON (no new prelude QueryPlan type), `then` = continuation contract name literal.
- **Continuation:** `Cont(req : Request, rows_json : String) -> Decision` (req first; rows = JSON string in
  v0; typed-row destructuring deferred).
- **Errors:** infra = host (Denied→403, Permanent→400/500, Retryable/Unknown→503); **not-found = app**
  (empty rows → continuation → app 404).
- **Authority:** host owns policy/clamp/adapter/DSN/target-binding; app owns plan + continuation +
  not-found. `.ig(web)` names no capability/DSN/SQL.
- **Block_on resolution (core finding):** the staged read **cannot** nest inside `call`'s sync `block_on`;
  it must run in an **async host driver** that owns the await chain (`dispatch(entry).await → read.await →
  dispatch(then).await`) and bypasses `call` — exactly as the write effect-host does. Full async socket
  runner stays deferred.
- **Composition:** continuation returns any final `Decision` (Respond/RespondView/Render/RenderView, or
  `InvokeEffect` → read-then-write via the effect host) — one generic arm, uniform mapping.

**Next card:** **`LAB-IGNITER-WEB-READTHEN-DISPATCH-P11`** — `machine`-gated impl of the `ReadThen` arm + an
async `run_read_then` host driver + the named harness tests (found / empty-app-404 / denied-before-adapter /
forbidden-field / clamp / raw-SQL refusal / no-nested-block_on / read→render). The full async socket runner
(`…-ASYNC-RUNNER-P*`) and the `read …` `.igweb` sugar (`…-READ-SYNTAX-P*`) follow.

## Closed scope

No live Postgres implementation, no new syntax, no effect write changes, no server-core domain logic.

## Next

Implementation card: `LAB-IGNITER-WEB-READTHEN-RUNNER-P11` or a corrected name chosen by this readiness.
