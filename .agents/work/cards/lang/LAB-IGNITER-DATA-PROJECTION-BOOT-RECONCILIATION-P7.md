# LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILIATION-P7

Status: CLOSED (2026-06-25) — auto-routing + reconciliation `implemented` in the runner contour; reconciliation timing = request-time/first-dispatch (boot DiagCode = P8 follow-on)
Route: standard / implementation proof
Skill: idd-agent-protocol

## Goal

Lift the P6 typed-row crossing from a direct harness proof into the normal `ReadThen` runner contour:

```text
ReadThen { plan, then, carry }
  -> host inspects continuation input shape
  -> chooses typed `rows : Collection[AppRow]` + `meta : DatasetMeta`
     OR legacy `rows_json : String`
  -> reconciles host field policy against the app row type
  -> fails closed before continuation dispatch on schema drift
```

This is the mainline step after `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6`.

## Why This Card Exists

P6 proved the core crossing is real:

- fake Postgres rows can cross as `Collection[TodoRow]`, not only `rows_json : String`;
- String/Bool/Integer survive as typed values;
- HOF transforms over typed rows work;
- `DatasetMeta { source, count, truncated }` crosses;
- missing fields / wrong scalar kinds are refused before continuation dispatch;
- the old `rows_json` path remains green.

But P6 is still **harness-driven**: the test supplies the app row shape manually and calls
`StagedReadHost::execute_typed` directly. The normal runner path still always calls
`StagedReadHost::execute` and redispatches `{ req, rows_json, carry }`.

P7 should make the host select and reconcile the correct crossing from compiled app metadata, not from a test
fixture.

## Current Authority

Read these first:

- `lab-docs/lang/lab-igniter-data-projection-typed-row-crossing-p6-v0.md`
- `server/igniter-web/src/lib.rs` (`IgWebLoadedApp::dispatch_with_read`)
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/read_materialize.rs`
- `server/igniter-web/src/runner_diag.rs`
- `server/igniter-web/tests/typed_row_crossing_tests.rs`
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
- `server/igniter-web/tests/fixtures/typed_row_crossing/typed_row_crossing.ig`
- `lang/igniter-compiler` and/or `lang/igniter-vm` metadata surfaces that expose contract inputs/types.

Live code wins over packet prose. In particular, verify the current compiled contract metadata shape before
choosing an implementation.

## Verify-First Questions

Answer these in the proof doc before or alongside implementation:

1. Where can `igniter-web` read a continuation contract's declared inputs/types after `load_program`?
2. Can it distinguish:
   - `input rows_json : String`;
   - `input rows : Collection[TodoRow]`;
   - `input meta : DatasetMeta`;
   - malformed/mixed shapes?
3. Can it recover the concrete `TodoRow` record fields and scalar types without reparsing authored `.ig`
   source?
4. Can it tie a `ReadThen.plan.source` / projection to the host `PostgresReadPolicy` field kinds before
   continuation dispatch?
5. Is reconciliation truly boot-time, first-dispatch-time, or request-time in the smallest safe slice?
   Name it honestly.

If the live compiler/VM exposes no reliable input/type metadata, **stop and return a readiness/gap packet**.
Do not implement ad-hoc source parsing, regex over `.ig`, dynamic type guessing, or a sidecar schema DSL.

## Implementation Target

Add the smallest host-side reconciliation/routing layer that makes the normal `dispatch_with_read` path use
typed rows when the continuation asks for them.

Recommended shape:

1. Add a small `ReadContinuationShape` / `ContinuationReadBinding` helper:
   - `LegacyRowsJson { then }` for continuations taking `rows_json : String`;
   - `TypedRows { then, rows_input, row_type, meta_input }` for continuations taking
     `rows : Collection[<Record>]` and optionally/required `meta : DatasetMeta`;
   - `Invalid { reason }` for ambiguous or unsupported shapes.
2. Add a metadata extraction path from the compiled program / loaded machine:
   - no authored source parsing;
   - no stringly inference from contract names;
   - keep this internal to `server/igniter-web` if possible.
3. For typed continuations:
   - build `ProjectionSpec` from the host `PostgresReadPolicy` and the plan projection/source;
   - build app row shape from the continuation input type;
   - call `reconcile_projection` before dispatching the continuation;
   - execute via `StagedReadHost::execute_typed`;
   - redispatch continuation with `{ req, rows, meta, carry }` (or the exact declared input names if the
     implementation supports that safely).
4. For legacy continuations:
   - preserve the current `{ req, rows_json, carry }` behavior byte-for-byte where possible.
5. Map errors:
   - structural projection drift -> runner/startup/first-dispatch diagnostic (`ProjectionSchemaDrift` or
     closest honest name);
   - per-request materialization `SchemaMismatch` -> HTTP 502 JSON error, never app-owned 4xx;
   - host denial remains 403;
   - transient host error remains 503.

## Boundary

Allowed:

- Narrow edits in `server/igniter-web` read dispatch / loaded app / runner diagnostics.
- Small compiler/VM accessor if strictly needed to expose already-known contract input types.
- DB-free tests using fake Postgres/read executor.
- New focused `.ig` fixtures under `server/igniter-web/tests/fixtures`.
- Proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No live Postgres requirement.
- No `.igweb` syntax changes.
- No new `Decision` arm.
- No JSON parser in `.ig`.
- No `Map[String, Unknown]` product row boundary.
- No Todo HTML route/list implementation.
- No tbackend/facts second-source proof.
- No user-facing schema DSL or sidecar file.
- No ad-hoc parsing of authored `.ig` source to recover types.
- Do not remove or break existing `rows_json` continuations.

## Required Proof Doc

Create:

`lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md`

Include:

- live metadata source used to inspect continuation input types;
- exact shape classification rules;
- typed vs legacy routing behavior;
- reconciliation timing (boot, first-dispatch, or request) named honestly;
- error taxonomy and HTTP/status mapping;
- compatibility story for existing `rows_json` continuations;
- test matrix and exact commands/counts;
- next cards.

## Acceptance

- [x] Verify-first section names the live metadata source. — `input_ports.type_tag` (assembler:513) + persisted `type_env`→`type_defs` (P7 accessor); doc §"Verify-first"
- [x] No authored `.ig` source parsing or regex/schema sidecar is used. — only registry metadata
- [x] Existing `rows_json : String` continuation path remains green. — `legacy_lane_still_routes_to_rows_json` + readthen/todo_postgres suites
- [x] Typed continuation is auto-routed from normal `dispatch_with_read` without direct test-only `execute_typed` calls. — `typed_lane_auto_routes_and_crosses_rows_and_meta`
- [x] Typed continuation receives `rows : Collection[TodoRow]` and `meta : DatasetMeta`. — same test
- [x] Host reconciles `PostgresReadPolicy` field kinds against the app row type before continuation business logic runs. — `reconcile_projection` gated on `source_allowlisted`, before `execute_typed`
- [x] Drift test proves `TodoRow.done : Bool` vs host `done : Text` fails closed before dispatch. — `schema_drift_fails_closed_before_dispatch` (500, adapter query_count 0)
- [x] Per-request row shape mismatch maps to HTTP 502, not app 4xx and not partial. — `row_shape_mismatch_maps_to_502`
- [x] Denied source/field remains 403 before adapter; host transient remains 503. — `denied_source_stays_403`; executor gates unchanged
- [x] `ReadThen` hop bound remains intact. — `runaway_readthen_chain_is_bounded` green (loop bound untouched)
- [x] Regression `readthen_dispatch_tests` / `todo_postgres_read_host_tests` / `typed_row_crossing_tests` green.
- [x] Full `server/igniter-web cargo test --features machine` green. — no FAILED; igniter-machine suite also green
- [x] Proof doc exists. — `lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md`
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Files changed:**
- `runtime/igniter-machine/src/registry.rs` — `ContractRegistry.type_defs` + `register_type_def`/`type_def`.
- `runtime/igniter-machine/src/machine.rs` — persist `typed.type_env` at `load_contract_source` (additive).
- `server/igniter-web/src/read_continuation.rs` *(new)* — `classify_continuation` + `app_row_shape`.
- `server/igniter-web/src/read_dispatch.rs` — `with_read_policy` + `projection_spec_for` + `source_allowlisted`.
- `server/igniter-web/src/lib.rs` — `dispatch_with_read` typed/legacy routing + reconciliation + `respond_json`.
- `server/igniter-web/tests/fixtures/typed_readthen/typed_readthen.ig` *(new)* — typed + legacy lanes, one app.
- `server/igniter-web/tests/typed_readthen_tests.rs` *(new)* — 9 tests.
- `lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md` *(new)* — proof doc.

**Metadata source for type inspection:** compiled-program metadata only — continuation inputs from the
assembled contract JSON `input_ports[].{name,type_tag}` (`assembler.rs:513-520`) in `machine.registry`; row
field types from `TypedProgram.type_env` persisted into `ContractRegistry.type_defs` by the new P7 accessor
(`machine.rs` populates it; the typechecker already computed it — assembler previously discarded it). No
authored `.ig` parsing, no regex, no schema sidecar.

**Reconciliation timing:** **request-time / first-dispatch** (named honestly). Boot is infeasible for the full
`(source,continuation,row-type)` triple because `ReadThen` plans build `source` dynamically (P3 §3); the
host-kind ⇎ row-type check needs that runtime source, so it reconciles at first dispatch, fail-closed before
continuation business logic. A structural boot pass + `DiagCode::ProjectionSchemaDrift` (fail-before-bind) is
the named P8 follow-on — the metadata it needs now exists.

**Tests + counts (`--features machine`, DB-free):** `typed_readthen_tests` **9**; regression
`readthen_dispatch_tests` **10**, `typed_row_crossing_tests` **9**, `todo_postgres_read_host_tests` **4**,
`read_materialize` unit **8**; full igniter-web suite green; full igniter-machine suite green;
`git diff --check` clean.

**`rows_json` compatibility:** preserved — `LegacyRowsJson` continuations cross `{req, rows_json, carry}`
unchanged; "declares neither" defaults to legacy (the keystone that kept `LoopForever`/bound test green).

**Remaining gap before TodoApp HTML consumes typed rows:** none at the data boundary — the typed read →
`RespondView`/`View` join runs end to end through the runner. What's left is product/vocabulary (the HTML
expression / LINK-NODE arc), not boundary.

**Next recommended card:** `LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8` — structural boot pass over typed
continuations + promote drift to a runner `DiagCode` (fail-before-bind) where statically recoverable +
first-dispatch reconcile cache; then `…-DATASET-META-AND-HTML-P8` (read→HTML Todo list demo).

## Suggested Tests

Run from `server/igniter-web`:

```bash
cargo test --features machine --test typed_row_crossing_tests
cargo test --features machine --test readthen_dispatch_tests
cargo test --features machine --test todo_postgres_read_host_tests
cargo test --features machine
```

Add a new focused test target if that keeps the typed-vs-legacy routing proof clearer.

## Reporting

Close with:

- files changed;
- metadata source used for type inspection;
- whether reconciliation is `boot-time`, `first-dispatch-time`, or still `request-time`;
- exact tests and counts;
- compatibility status of `rows_json`;
- any remaining gap before TodoApp HTML can consume typed rows;
- next recommended card.

