# LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6

Status: CLOSED (2026-06-25) — host crossing `implemented`, boot reconciliation `harness-proven`
Route: standard / implementation proof
Skill: idd-agent-protocol

## Goal

Implement the smallest typed data-projection crossing:

```text
ReadThen / QueryPlan
  -> host read executor returns typed rows
  -> host materializer validates rows against continuation row type
  -> continuation receives rows : Collection[TodoRow] (+ meta : DatasetMeta)
  -> .ig uses typed field access + HOFs
```

This is the mainline step after the P1-P5 readiness series. It should prove that `rows_json : String` is
no longer the only possible read-continuation boundary.

## Why This Card Exists

P2 found the key fact: the VM can already materialize `serde_json::Array<Object>` as
`Value::Array(Value::Record)`. The gap is host-side: `read_dispatch.rs` stringifies typed rows into
`rows_json : String`.

P3 found the safety rule: do **not** just pass records through and hope the typechecker/VM catches drift.
The host must reconcile rows against its schema authority before `.ig` sees them.

## Current Authority

Read these first:

- `lab-docs/lang/lab-igniter-data-projection-boundary-readiness-p1-v0.md`
- `lab-docs/lang/lab-igniter-data-projection-materialization-readiness-p2-v0.md`
- `lab-docs/lang/lab-igniter-data-projection-contract-and-errors-p3-v0.md`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/lib.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `server/igniter-web/tests/todo_postgres_read_host_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `apps/igniter-apps/query_engine/`

Live code wins over packet prose if they disagree.

## Implementation Target

Add a **host-side typed row crossing** for the read harness path.

Recommended shape:

1. Preserve existing `rows_json` path for compatibility unless impossible.
2. Add a structured read result path that carries:
   - `rows` as `serde_json::Value::Array`;
   - `meta` as `{ source, count, truncated }`.
3. Add a tiny host materializer/reconciler:
   - input: typed rows from `PostgresReadExecutor`, projected fields, host field kinds, expected app row
     shape if accessible;
   - output: sanitized `rows` array and `DatasetMeta`;
   - fail before continuation dispatch on mismatch.
4. Add a DB-free fixture/continuation:
   - `type TodoRow { id : String, account_id : String, title : String, done : Bool, rank : Integer }`
     or equivalent String + Bool + Integer coverage;
   - continuation `input rows : Collection[TodoRow]`;
   - continuation `input meta : DatasetMeta`;
   - body uses typed access inside HOFs:
     - `filter(rows, r -> r.done == false)`;
     - `map(..., r -> r.title)` or `call_contract("TodoRowToLabel", r)`;
     - integer field used as Integer, not String.

## Important Safety Rule

Schema/type mismatch is **host-owned**, not app-owned.

Rows that reach `.ig` must be total and typed. The app should not need `map_get_string`, JSON parsing, or
decoder contracts for host-owned relational reads.

For this proof, a stable mismatch refusal may be implemented as a host error in the harness path if full
startup `DiagCode::ProjectionSchemaDrift` is too large. But the test must prove:

- missing required field is refused before continuation dispatch;
- wrong scalar kind is refused before continuation dispatch;
- no partial app response is produced.

Name any diagnostic/status shape honestly if it is not yet final runner diagnostic.

## Boundary

Allowed:

- Edit `server/igniter-web` read dispatch / runner harness code narrowly.
- Add a focused `.ig` fixture under `server/igniter-web/tests/fixtures` or examples if that is the local
  pattern.
- Add DB-free tests using fake Postgres/read executor.
- Add/update a proof doc in `lab-docs/lang/`.
- Update this card with a closing report.

Closed:

- No live Postgres requirement.
- No `.igweb` syntax changes.
- No JSON parser in `.ig`.
- No `Map[String, Unknown]` as the product row boundary.
- No Todo HTML route/list implementation.
- No tbackend/facts second-source proof.
- No decoder-contract lane.
- No canon claim.
- Do not remove existing `rows_json` behavior unless a test proves there is no compatibility need.

## Required Proof Doc

Create:

`lab-docs/lang/lab-igniter-data-projection-typed-row-crossing-p6-v0.md`

Include:

- what changed;
- exact crossing shape;
- compatibility story for `rows_json`;
- materializer/reconciliation behavior;
- mismatch/error behavior;
- test matrix;
- next cards.

## Acceptance

- [x] DB-free test proves fake read rows cross as `input rows : Collection[TodoRow]`. — `typed_rows_cross_as_collection_with_meta`
- [x] Test proves String field access (`r.title`) works. — titles fold + `TypedTodoIndex` item label
- [x] Test proves Bool field access in `filter(rows, r -> r.done == false)` works. — pending == 1
- [x] Test proves Integer field is preserved as Integer, not String. — `rank_sum == 30` (numeric fold)
- [x] Test proves HOF transform over typed rows works (`map` and/or `call_contract`). — `typed_continuation_maps_rows_to_view`
- [x] Test proves `DatasetMeta { source, count, truncated }` crosses. — meta asserts + `clamped_read_crosses_truncated_meta`
- [x] Missing required field is refused before continuation dispatch. — `missing_field_is_refused_before_dispatch`
- [x] Wrong scalar kind is refused before continuation dispatch. — `wrong_scalar_kind_is_refused_before_dispatch`
- [x] Existing `rows_json` path remains green or compatibility decision is explicit. — separate enum/method; `legacy_rows_json_path_still_works` + regression suites green
- [x] No live DB, no `.igweb` syntax change, no Todo HTML implementation. — fake adapter; no `.igweb`/VM/compiler edits
- [x] Proof doc exists. — `lab-docs/lang/lab-igniter-data-projection-typed-row-crossing-p6-v0.md`
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Files changed (all host-side `server/igniter-web`, narrow + additive):**
- `src/read_materialize.rs` *(new)* — `ProjectionSpec` (from host `PostgresReadPolicy`), `materialize_rows`
  (totality + scalar-kind gate), `reconcile_projection` + `AppFieldType` (P3 §3 drift), `build_dataset_meta`;
  8 in-module unit tests.
- `src/read_dispatch.rs` — `TypedReadResult` (separate enum) + `StagedReadHost::execute_typed`; shared
  `idem_key_for`. `execute`/`StagedReadResult` unchanged.
- `src/lib.rs` — registered `read_materialize` (machine-gated). `dispatch_with_read` untouched.
- `tests/fixtures/typed_row_crossing/typed_row_crossing.ig` *(new)* — `TodoRow`/`DatasetMeta`, `ListTypedTodos`,
  `TodoRowItem`, `TypedTodoProbe`, `TypedTodoIndex`.
- `tests/typed_row_crossing_tests.rs` *(new)* — 9 integration tests.
- `lab-docs/lang/lab-igniter-data-projection-typed-row-crossing-p6-v0.md` *(new)* — proof doc.

**Tests + counts (`--features machine`, DB-free):**
- `typed_row_crossing_tests`: **9 passed**.
- `read_materialize` unit: **8 passed**.
- Regression: `todo_postgres_read_host_tests` **4**, `readthen_dispatch_tests` **10**, `todo_view_app_tests`
  **14**; full `igniter-web --features machine` suite green. `git diff --check` clean.

**Verdict:** host crossing = **implemented** (real `execute_typed` + `materialize_rows`; typed rows + meta
cross into a live `.ig` continuation via VM `from_json`; String/Integer/Bool need no language change). Boot
schema reconciliation = **harness-proven** (`reconcile_projection` real + tested, but `<AppRow>` shape is
harness-supplied not yet IR-read, and `ProjectionSchemaDrift` is a stable string not yet a runner `DiagCode`).

**`rows_json` compatibility:** preserved unchanged (separate enum/method; original loop untouched); proven by
a dedicated test + the green regression suites.

**Next recommended card:** `LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILE-P7` — read the continuation `rows` type
from the compiled IR (`compiler.rs:213`), reconcile at boot, promote `ProjectionSchemaDrift` → runner
`DiagCode` (fail-closed before bind, P3 §5), auto-route typed vs stringly in `dispatch_with_read`, map
`SchemaMismatch` → HTTP 502. Then `LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P7` (read → typed
`Collection[HtmlNode]` view join) once the typed crossing is judged solid.

## Suggested Tests

Run from `server/igniter-web`:

```bash
cargo test --features machine --test todo_postgres_read_host_tests
cargo test --features machine --test readthen_dispatch_tests
cargo test --test todo_view_app_tests
```

Add the new typed-row tests to the smallest appropriate existing test target or a new focused target.

If you touch `runtime/igniter-machine`, also run the relevant fake Postgres read tests there.

## Reporting

Close with:

- files changed;
- exact tests and counts;
- whether verdict is `implemented` or still `harness-proven`;
- compatibility status of `rows_json`;
- next recommended card:
  - likely `LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P7` if typed crossing is solid;
  - or a narrower materializer follow-up if mismatch handling remains provisional.
