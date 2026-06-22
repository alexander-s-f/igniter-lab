# LAB-IGNITER-WEB-READTHEN-DISPATCH-P11 - staged read decision and async continuation driver

Status: CLOSED
Lane: server / IgWeb / staged reads
Type: implementation
Delegation code: OPUS-WEB-READTHEN-DISPATCH-P11
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

`ReadThen` has been designed several times and proved by direct harnesses, but it is not yet a live runner
surface:

- P5 designed `ReadThen { plan, then }`;
- P6 hand-orchestrated query contract -> fake `PostgresReadExecutor` -> continuation contract;
- P10 readiness named `LAB-IGNITER-WEB-READTHEN-DISPATCH-P11`;
- P1 host IO substrate reconfirmed: `ReadThen` is `designed` + `harness-proven`, not `implemented` or
  `runner-integrated`.

This card should come after or alongside the async machine runner seam. If P2 has not landed, stop at a
compile/runtime feasibility packet and do not force staged reads into the sync runner.

## Goal

Implement the smallest honest staged-read surface:

```text
Serve(req) -> ReadThen { plan, then }
host executes plan through PostgresReadExecutor
host dispatches continuation `then` with rows
continuation returns final Decision
```

No new `.igweb` sugar in this card. Author `ReadThen` explicitly in `.ig` fixture/prelude first.

## Verify first

Read:

```text
lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md
lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md
lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md
lab-docs/lang/lab-igniter-machine-host-io-substrate-readiness-p1-v0.md
server/igniter-web/src/lib.rs
server/igniter-web/tests/todo_postgres_read_host_tests.rs
runtime/igniter-machine/src/postgres_read.rs
```

Confirm live absence/presence:

```text
rg -n "ReadThen|read then|staged read" lang/igniter-compiler/src server/igniter-web/src server/igniter-server/src lang/igniter-vm/src
```

## Implementation shape

Minimum expected pieces:

- Extend IgWeb prelude `Decision` with:

```ig
ReadThen { plan : Unknown, then : String }
```

- Add a host-side staged marker or async driver path. Do not map `ReadThen` to a normal final
  `ServerDecision::Respond`.
- The async runner/driver:
  1. dispatches entry;
  2. sees `ReadThen`;
  3. decodes `plan`;
  4. executes fake `PostgresReadExecutor` under host policy;
  5. serializes rows as the current v0 rows JSON string/value agreed by P6;
  6. dispatches continuation contract by name;
  7. maps the final Decision normally.

If P2 has not provided an async core dispatch seam, implement only direct async test harness extraction and
write the next P2 dependency in the closing report.

## Closed surfaces

- No `.igweb` `read ... as ...` syntax.
- No parser keyword for `read`.
- No live Postgres requirement; fake read executor is enough.
- No raw SQL.
- No typed row destructuring; rows JSON/string v0 is acceptable.
- No hidden DB authority in `.ig`.
- No background mailbox.

## Acceptance

- [x] Live source inventory is included in closing report.
- [x] `ReadThen` arm exists in the IgWeb prelude or the card stops with an exact blocker if P2 is missing.
- [x] A fixture app authors `ReadThen` explicitly, without new `.igweb` sugar.
- [x] Fake read executor is called through host policy; denied source/field fails before adapter.
- [x] Found rows -> continuation -> final `Respond` 200.
- [x] Empty rows -> continuation-owned 404 (not infra error).
- [x] Raw SQL refusal remains fail-closed.
- [x] No nested `block_on` in the new staged driver path.
- [x] Existing P6 direct-read tests remain green.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22
**Proof:** `lab-docs/lang/lab-igniter-web-readthen-dispatch-p11-v0.md`

### Live source inventory (verify-first)

`rg "ReadThen|read_then|staged.read"` → zero results in all source trees before this card.
`PRELUDE_SOURCE` had 5 `Decision` arms; `ReadThen` was absent.
P6 fixture (`read_harness.ig`) + `todo_postgres_read_host_tests.rs` existed as direct-dispatch proof, not runner-integrated.

### Deliverables

**1. Prelude — `lang/igniter-compiler/src/igweb.rs`**

Added `ReadThen { plan : Unknown, then : String }` to `variant Decision`. The `plan` field is
`Unknown` so any record value (e.g., `QueryPlan`) satisfies the type; the host decodes it via
`PostgresReadExecutor` without the app ever naming capability id, DSN, or SQL.

**2. Staged read module — `server/igniter-web/src/read_dispatch.rs`** (new)

- `StagedReadResult` enum: `Rows(String)` / `Denied(String)` / `HostError(String)`
- `StagedReadHost` struct: wraps `CapabilityExecutorRegistry` + `TBackend` + `authority_ref`
- `StagedReadHost::execute(&plan, &req) -> StagedReadResult` (async, no block_on)

**3. Async staged driver — `server/igniter-web/src/lib.rs`**

`IgWebLoadedApp::dispatch_with_read(req, &StagedReadHost)` (feature-gated `machine`):
1. Dispatches entry via `machine.dispatch`.
2. Intercepts `ReadThen` arm via `variant_of` before `map_decision`.
3. Calls `StagedReadHost::execute` → `Rows` / `Denied` / `HostError`.
4. On `Rows`: builds `{ req, rows_json }` and re-dispatches the continuation by name.
5. Maps continuation's final `Decision` via `map_decision`.
6. On `Denied`: 403. On `HostError`: 503.

No `block_on` anywhere; purely `async fn`.

**4. Fixture — `tests/fixtures/read_then_fixture/read_then_fixture.ig`** (new)

`FetchTodosEntry` emits `ReadThen { plan: {...}, then: "FetchTodosContinuation" }`.
`FetchTodosContinuation` receives `rows_json` and returns `Respond{200}` or `Respond{404}`.
No capability id, DSN, raw SQL, DB handle.

**5. Tests — `tests/readthen_dispatch_tests.rs`** (new, `--features machine`)

6 tests, all green:
- `found_rows_flow_to_continuation_200` — found rows → continuation → 200 + rows body
- `empty_rows_gives_continuation_owned_404` — empty result → continuation → 404 (not infra)
- `denied_source_gives_host_403_before_adapter` — source not in policy → 403, adapter query_count=0
- `raw_sql_key_in_plan_is_refused_before_adapter` — raw SQL key → Denied, adapter query_count=0
- `dispatch_with_read_has_no_nested_block_on` — runs inside tokio without panic
- `fixture_carries_no_authority_surface` — static text audit; no forbidden surface

**Full suite:** `cargo test` (33 host_config tests) + `cargo test --features machine` (all suites) — zero failures.

### Key design notes

- `authority_ref` is required by `run_effect_with_clock`; `StagedReadHost` carries a host-owned
  default `"host:read"` with `.with_authority()` override for tests.
- Idempotency key = `correlation_id` (reads are safe to replay with the same key).
- `ReadThen` is NOT added to `ServerDecision` in `igniter-server` — host intercepts before mapping.
- `map_decision` unchanged — `ReadThen` falls through the staged path only.
- P6 tests (`todo_postgres_read_host_tests.rs`) unmodified and green.
