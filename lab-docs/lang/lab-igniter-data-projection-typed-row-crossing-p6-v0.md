# lab-igniter-data-projection-typed-row-crossing-p6-v0

Card: `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6`
Route: standard / implementation proof · Skill: idd-agent-protocol
Status: implemented (host crossing) + harness-proven (boot reconciliation deferred to P7) · no canon claim
Date: 2026-06-25
Builds on: P1 boundary · P2 materialization · P3 contract-and-errors readiness packets
(`lab-docs/lang/lab-igniter-data-projection-{boundary-readiness-p1,materialization-readiness-p2,contract-and-errors-p3}-v0.md`)

> **Authority boundary.** Lab evidence only. This proves a host-side typed-row crossing in `igniter-web`; it
> changes no language/VM/compiler/`.igweb`/Postgres surface and makes **no canon claim**. Live code wins over
> this prose if they disagree.

---

## Headline

`rows_json : String` is **no longer the only read-continuation boundary.** A fake-Postgres read now crosses
into an `.ig` continuation as a **total + typed `Collection[TodoRow]`** (native records, not a JSON string)
plus a sibling `DatasetMeta`, and the continuation does ordinary typed record work over them — `r.title`
(String), `r.done == false` (Bool filter), `r.rank` arithmetic (Integer fold), `map` + `call_contract` over a
row — with **no JSON parsing, no `map_get_string`, no decoder contract** in `.ig`. The crossing is gated by a
host materializer that refuses a row missing a field or carrying the wrong scalar kind **before** the
continuation is ever dispatched, so `.ig` never sees the P2 silent-wrong / path-dependent field-access hazard.

This confirms the P2 verdict (`small-gap`): the gap was entirely host-side and small. **No language / VM /
compiler / `.igweb` / Postgres change was needed** — exactly as predicted.

---

## What changed

All edits are host-side in `server/igniter-web`, narrow and additive.

| File | Change |
| --- | --- |
| `src/read_materialize.rs` *(new)* | The host materializer + reconciler: `ProjectionSpec` (built from the host `PostgresReadPolicy`), `materialize_rows` (totality + scalar-kind gate → stable error), `reconcile_projection` + `AppFieldType` (P3 §3 drift gate), `build_dataset_meta`. Pure functions, 8 unit tests in-module. |
| `src/read_dispatch.rs` | Added `TypedReadResult` (separate enum from `StagedReadResult`) and `StagedReadHost::execute_typed`, which runs the read then materializes instead of stringifying. Extracted the shared idempotency/freshness key into `idem_key_for` so the typed and stringly paths are byte-identical. The existing `execute` / `StagedReadResult` are unchanged. |
| `src/lib.rs` | Registered `pub mod read_materialize` under `#[cfg(feature = "machine")]`. `dispatch_with_read` (the `rows_json` loop) is **untouched**. |
| `tests/fixtures/typed_row_crossing/typed_row_crossing.ig` *(new)* | `type TodoRow { id, account_id, title : String, done : Bool, rank : Integer }`, `type DatasetMeta { source : String, count : Integer, truncated : Bool }`, an authored `ListTypedTodos -> QueryPlan`, a `TodoRowItem` helper, a `TypedTodoProbe` (asserts every typed dimension), and a realistic `TypedTodoIndex` Decision continuation. |
| `tests/typed_row_crossing_tests.rs` *(new)* | 9 integration tests (`--features machine`), fake adapter, DB-free. |

---

## Exact crossing shape

```text
ListTypedTodos(account_id) -> QueryPlan { source: "todos", projection: [id, account_id, title, done, rank], … }
  -> StagedReadHost::execute_typed(plan, req, spec)
       run_effect → PostgresReadExecutor (host gates + clamp, all pre-adapter, unchanged)
                  → FakePostgresAdapter returns typed serde rows (int/bool preserved)
       materialize_rows(rows, spec):                         ← the new host step
         for each row: keep projected fields (drop extras),
                       require every declared field present,  → else stable "missing required field" error
                       require each value's JSON kind == host decode-kind → else stable "wrong kind" error
       build_dataset_meta(source, count, row_limit_clamped)
  -> TypedReadResult::Rows { rows: Value::Array(records), meta: { source, count, truncated } }
  -> machine.dispatch("TypedTodoIndex", { req, rows, meta })
       VM from_json materializes rows : Collection[TodoRow], meta : DatasetMeta   ← type-erased, P2 §1.3
       continuation: filter(rows, r -> r.done == false); map(pending, r -> call_contract("TodoRowItem", r))
  -> RespondView { status: 200, view: { kind: meta.source, items: [ { key: "todo-1", label: "Buy milk" } ] } }
```

The rows array is crossed **structurally** under a `rows` input key; the VM's `from_json` does the
materialization to `Collection[Record]` with no extra machinery (the P2 §1.3 type-erased dispatch path). The
continuation declares `input rows : Collection[TodoRow]` and `input meta : DatasetMeta` — ordinary typed
contract inputs, the P3 §2 "single declaration point".

## Compatibility story for `rows_json`

**Kept, untouched, proven green side-by-side.** The typed path is a *separate* `TypedReadResult` enum and a
*separate* `execute_typed` method; the original `StagedReadResult::Rows(String)` / `execute` /
`dispatch_with_read` loop is byte-for-byte unchanged. Every pre-P6 continuation that takes
`input rows_json : String` (`AccountTodoIndexFromRows`, `CheckAccountThenList`, `FetchTodosContinuation`, …)
still works. The regression suites confirm it:

- `todo_postgres_read_host_tests` (4) + `readthen_dispatch_tests` (10) — green;
- a dedicated P6 test (`legacy_rows_json_path_still_works`) runs `execute` on the *same* plan and asserts it
  still returns a `Rows(String)` JSON array.

Selecting the typed vs stringly path *per continuation* (by reading the continuation's `rows` input type from
the compiled IR, so the generic `dispatch_with_read` loop auto-routes) is intentionally **out of scope** here
— it is the P7 boot-reconciliation lift (below). For P6 the typed path is driven directly through
`execute_typed`, the same harness posture as `todo_postgres_read_host_tests`.

## Materializer / reconciliation behavior

Two host-owned gates, both keeping schema concerns out of `.ig` business logic (P3 §1):

1. **`materialize_rows` (per-request totality + scalar-kind).** Drops extra host fields (cosmetic), requires
   every projected field present, and requires each value's JSON kind to equal its host decode-kind
   (`Text`/`Decimal`/`Timestamp` → string; `Integer` → integral `i64`; `Boolean` → bool; `Json` →
   object/string; `Array` → array). A SQL `NULL` never satisfies a non-nullable field — it is refused like a
   missing one. Any violation → `TypedReadResult::SchemaMismatch(stable string)` **before** continuation
   dispatch. This is the host honoring its own promise; per P3 §5 it maps to **502** (a gateway-level fault —
   the host's upstream returned something it could not honor as promised). *Status wiring into the HTTP
   contour is itself a follow-on; P6 surfaces the typed `SchemaMismatch` outcome and proves no partial app
   response is produced.*

2. **`reconcile_projection` (structural drift).** Checks the host decode-kinds are assignable to the declared
   `<AppRow>` field types (the P3 §3 matrix: `Text`→`String|Text`, `Integer`→`Integer`, `Boolean`→`Bool`, …)
   and that every app field is covered by a projected host field. A mismatch is `ProjectionSchemaDrift` — a
   **deploy-time** fact, not per-request. P6 proves the check; wiring it to fail the runner *before bind* with
   a `DiagCode::ProjectionSchemaDrift` (P3 §5) is the P7 follow-on. Named honestly: today it is a stable host
   error string, **not** yet a runner `DiagCode` (the `runner_diag.rs` set has no `ProjectionSchemaDrift`).

### Honest naming of provisional surfaces

- `TypedReadResult::SchemaMismatch` is a host outcome value, **not** yet an HTTP 502 in the serving contour.
- `reconcile_projection` returns a `ProjectionSchemaDrift: …` **string**, **not** yet a runner `DiagCode` /
  non-zero exit. P3 §3's *boot* reconciliation (statically recover `(source, continuation, row-type)` triples
  from the IR) is deferred; P6 supplies the `<AppRow>` shape from the harness, standing in for the IR read.
- The `<AppRow>` field types in `reconcile_projection` are harness-supplied (`AppFieldType`), representing the
  IR-derived shape P3 §2 reads from `compiler.rs:213` `inputs[].type`. → **verdict component: harness-proven.**

## Mismatch / error behavior

| Condition | Detected | Surfaced as | Test |
| --- | --- | --- | --- |
| Row missing a projected field | request (materializer) | `SchemaMismatch("… missing required field `done`")`, no dispatch | `missing_field_is_refused_before_dispatch` |
| Wrong scalar kind (string for a `Boolean`/`Integer` field) | request (materializer) | `SchemaMismatch("… `done` wrong kind …")`, no dispatch | `wrong_scalar_kind_is_refused_before_dispatch` |
| Host kind ⇎ `<AppRow>` type drift | (boot / first-touch) | `ProjectionSchemaDrift: …` | `reconciliation_catches_kind_drift` |
| Source/field/op denied; raw SQL | request (executor gate, unchanged) | `Denied` → 403 | covered by existing suites |
| Empty result set | request | **not an error** — app product decision (404 here) | `empty_typed_rows_are_app_not_found_404` |
| Truncated / clamped read | request | `meta.truncated = true` (data, not error) | `clamped_read_crosses_truncated_meta` |

## Test matrix

`server/igniter-web` — all `--features machine`, fake adapter, DB-free.

**`tests/typed_row_crossing_tests.rs` (9):**
- `typed_rows_cross_as_collection_with_meta` — rows cross as `Collection[TodoRow]` (total 2); `r.done == false`
  filter selects 1 pending (Bool); `fold(rows,0,(acc,r)->acc+r.rank)` = 30 (Integer preserved, not String);
  `fold` over `r.title` yields the titles (String); `DatasetMeta { source, count, truncated }` crosses.
- `typed_continuation_maps_rows_to_view` — `map(pending, r -> call_contract("TodoRowItem", r))` builds a typed
  `View`; item label `"Buy milk"` proves `r.title` through `map` + `call_contract`; `kind == meta.source`.
- `empty_typed_rows_are_app_not_found_404` — empty typed collection → app-owned 404.
- `clamped_read_crosses_truncated_meta` — cap 1 → `meta.truncated == true`, `meta.count == 1`.
- `missing_field_is_refused_before_dispatch` — host `SchemaMismatch`, no continuation dispatch.
- `wrong_scalar_kind_is_refused_before_dispatch` — host `SchemaMismatch` on a stringified Bool.
- `reconciliation_catches_kind_drift` — matched spec reconciles; `done : Text` vs `Bool` → `ProjectionSchemaDrift`.
- `legacy_rows_json_path_still_works` — original `execute` still returns `Rows(String)` for the same plan.
- `fixture_has_no_forbidden_surface` — authored `.ig` carries no SQL/capability id/scope/DSN.

**`src/read_materialize.rs` unit tests (8):** materialize drops extras + preserves Bool/Integer; missing
field refused; wrong scalar kind refused (Bool *and* Integer); null-for-non-nullable refused; reconcile
matches when assignable; reconcile detects kind drift; reconcile detects an uncovered app field; meta shape.

**Regression (unchanged, green):** `todo_postgres_read_host_tests` (4), `readthen_dispatch_tests` (10),
`todo_view_app_tests` (14); full `igniter-web --features machine` suite green. `git diff --check` clean.

```bash
cargo test --features machine --test typed_row_crossing_tests   # 9 passed
cargo test --features machine --lib read_materialize            # 8 passed
cargo test --features machine --test todo_postgres_read_host_tests --test readthen_dispatch_tests  # 4 + 10
cargo test --features machine                                   # full suite green
```

## Verdict

- **Host crossing: `implemented`.** `execute_typed` + `materialize_rows` are real host code on the read
  contour; the typed rows + `DatasetMeta` cross into a real `.ig` continuation via the live VM `from_json`
  path, and typed field access / HOFs run green. The String/Integer/Bool case needs no language change.
- **Boot schema reconciliation: `harness-proven`.** `reconcile_projection` is real and tested, but the
  `<AppRow>` shape is harness-supplied (not yet read from the IR at boot) and drift is a stable string (not
  yet a runner `DiagCode` that fails the listener before bind).

## Next cards

- **`LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILE-P7`** (the materializer follow-up): read the continuation's
  `rows` input type from the compiled IR (`compiler.rs:213`); reconcile at boot/first-dispatch; promote
  `ProjectionSchemaDrift` to a runner `DiagCode` (fail-closed before bind, P3 §5); route the typed vs stringly
  path automatically in `dispatch_with_read` by the continuation's input shape; map `SchemaMismatch` → HTTP 502.
- **`LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P7`** (if typed crossing is judged solid): the read →
  typed `Collection[HtmlNode]` view join (P1 §7 / pairs with this), using `meta.truncated` to drive a
  "load more" affordance.
- **Deferred (named):** typed `Decimal`/`Timestamp` via the `{value,scale}` `from_json` bridge
  (`value.rs:82-91`); nested `Json` → record; `Dataset[T]` generic envelope (needs user generics);
  nullability policy surface.
```
