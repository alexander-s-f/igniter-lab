# lab-igniter-data-projection-boot-reconciliation-p7-v0

Card: `LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILIATION-P7`
Route: standard / implementation proof · Skill: idd-agent-protocol
Status: implemented (auto-routing + reconciliation in the runner contour) · reconciliation timing = **request-time / first-dispatch**, named honestly · no canon claim
Date: 2026-06-25
Builds on: P1 boundary · P2 materialization · P3 contract-and-errors · **P6 typed-row-crossing**
(`lab-docs/lang/lab-igniter-data-projection-typed-row-crossing-p6-v0.md`)

> **Authority boundary.** Lab evidence only. Host-side routing + a small machine accessor that exposes
> already-computed type metadata. No language/`.igweb`/Decision-grammar change; **no canon claim.** Live code
> wins over this prose.

---

## Headline

The P6 typed crossing now runs from the **normal `ReadThen` runner path** — no test-only `execute_typed`
call. When a contract returns `ReadThen { plan, then, carry }`, the host reads the named continuation's
**compiled inputs** and routes:

- `then` takes `rows : Collection[<AppRow>]` (+ `meta : DatasetMeta`) → **typed** crossing, after reconciling
  the host read policy against the recovered `<AppRow>` field types;
- `then` takes `rows_json : String` (or neither) → **legacy** stringly crossing, byte-for-byte as before.

Reconciliation is honest about its timing: it is **request-time (first dispatch of each `ReadThen`)**, not
boot. The metadata needed for a structural boot check now exists (P7 persists it), but the host-kind ⇎
row-type reconciliation depends on the *runtime* plan's `source`, which a `ReadThen` builds dynamically — so
the safe v0 reconciles at first dispatch, fail-closed before the continuation runs (P3 §3's named fallback).

---

## Verify-first: the live metadata source (no `.ig` source parsing)

The crux this card had to settle: can the host read a continuation's declared inputs/types after
`load_program`, **without re-parsing authored `.ig`**? Answer, from live code:

| Need | Live source | Reachable? |
| --- | --- | --- |
| Continuation input names + types | assembled contract JSON `input_ports[] = { name, type_tag }` (`assembler.rs:513-520`; `type_tag` is the stringified type via `type_name`, e.g. `"String"`, `"Collection[TodoRow]"`, `"DatasetMeta"`), held in `machine.registry` (`ContractRegistry.contracts`) | **YES** — already public |
| `<AppRow>` field names + scalar types | the typechecker's `TypedProgram.type_env` (`{ field: { "name", "params" } }`, `typechecker.rs:167,630-643`) | **was discarded** at assembly |

So input *shape* classification was already reachable; the **row-record field types were not** — `type_env`
is computed by the typechecker but the assembler never carried it into the registered contract JSON. Per the
card boundary ("Small compiler/VM accessor if strictly needed to expose already-known contract input types"),
P7 adds exactly that accessor — **no source parsing, no regex, no schema sidecar, no name-based guessing**:

- `ContractRegistry` gains `type_defs: HashMap<String, Value>` + `register_type_def` / `type_def`
  (`registry.rs`);
- `machine.rs::load_contract_source` persists `typed.type_env` into it after typechecking (purely additive
  metadata; no compile-semantics change).

`igniter-web` then reads both from the loaded machine: `input_ports` for shape, `type_def(<AppRow>)` for the
row's field types. Verified live: the P7 test `app_row_shape_recovers_field_types_from_type_defs` recovers
`TodoRow → {id:String, account_id:String, title:String, done:Bool, rank:Integer}` from a loaded machine with
no source access.

## Shape classification rules (`read_continuation::classify_continuation`)

Read `then`'s `input_ports` from the registry; decide from `(name, type_tag)` pairs:

| Declared inputs | Shape | Crossing |
| --- | --- | --- |
| `rows : Collection[<Record>]` (+ optional `meta : DatasetMeta`) | `TypedRows { row_type, declares_meta }` | `{ req, rows, meta, carry }` |
| `rows_json : String` | `LegacyRowsJson` | `{ req, rows_json, carry }` |
| **neither** `rows_json` nor `rows` | `LegacyRowsJson` (default) | `{ req, rows_json, carry }` |
| **both** `rows_json` and `rows` | `Invalid` (ambiguous) | 500, fail closed |
| `rows : Collection[<scalar>]` or `rows : <non-collection>` | `Invalid` | 500, fail closed |
| contract not found | `Invalid` | 500, fail closed |

The **"neither → legacy"** default is the back-compat keystone: the pre-P7 loop *always* crossed `rows_json`,
which a continuation could ignore (e.g. the staged-read bound test's `LoopForever`, which only re-issues a
`ReadThen` from `req`). Defaulting to legacy preserves that exactly. `<Record>` = any type name that is not a
known scalar; `app_row_shape` then validates it against `type_defs` (unknown type → fail closed).

## Typed vs legacy routing behavior (`dispatch_with_read`)

For each `ReadThen` hop the loop now classifies `then`, then:

**Legacy** → unchanged: `read_host.execute(plan, req)` → `{ req, rows_json, carry }` → redispatch. 403/503
exactly as before.

**Typed**:
1. derive `ProjectionSpec` from the host read policy + this plan (`read_host.projection_spec_for`); no policy
   attached → **500 `typed_read_unconfigured`** (never project blind);
2. **reconcile** — *only when the plan's `source` is allowlisted* (`read_host.source_allowlisted`): recover
   `<AppRow>` from `type_defs`, run `reconcile_projection(spec, approw)`; drift → **500
   `projection_schema_drift`**, before the read, adapter untouched. (An un-allowlisted source skips reconcile
   so the executor's denial — not a default-`Text` false-positive — is what surfaces.)
3. `read_host.execute_typed(plan, req, spec)` → materialize → `{ req, rows, meta, carry }` → redispatch.

The staged-read **hop bound is unchanged** (`MAX_READ_HOPS`), so a runaway typed/legacy chain still fails
closed to 500 (regression `runaway_readthen_chain_is_bounded` green).

## Reconciliation timing — named honestly

**Request-time, at the first dispatch of each `ReadThen` (no cross-request cache).** Not boot.

Why not boot: a `ReadThen` plan — and therefore its `source` and `projection` — is built *dynamically in a
contract body* (`FetchTypedTodos` calls `ListTypedTodos(req.path)`), so the `(source → continuation →
row-type)` triple is not statically enumerable at load (P3 §3's explicit nuance). The host-kind ⇎ row-type
check needs that runtime `source`. What boot *could* now do (and is the named follow-on) is a **structural**
pass: for every continuation declaring `rows : Collection[<AppRow>]`, confirm `<AppRow>` resolves in
`type_defs` and every field has a v0 landing — independent of source. P7 leaves that as a follow-on and
reconciles the source-bound part at first dispatch, fail-closed before continuation business logic.

A first-dispatch **cache** (reconcile once per `(source, continuation)`, memoize the verdict) is a noted
micro-optimization; v0 reconciles every dispatch (cheap: a handful of field comparisons).

## Error taxonomy + HTTP/status mapping

| Condition | Owner | Status | Code | Detected |
| --- | --- | --- | --- | --- |
| Host-kind ⇎ `<AppRow>` drift (allowlisted source) | Host/deploy | **500** | `projection_schema_drift` | before read |
| `<AppRow>` not recoverable / no v0 landing | Host/deploy | **500** | `projection_schema_unrecoverable` | before read |
| Typed continuation, no read policy attached | Host/config | **500** | `typed_read_unconfigured` | before read |
| Ambiguous/unsupported continuation shape | Host | **500** | `invalid_read_continuation` | classify |
| Row missing field / wrong scalar kind (post-reconcile) | Host (broke promise) | **502** | `projection_row_mismatch` | after read |
| Source/field/op denied; raw SQL | Host | **403** | (executor) | before adapter |
| Adapter transient / unknown | Host | **503** | (executor) | request |
| Empty result set / not-found | App | **200 `[]` / 404** | — | continuation |

This matches P3 §5: drift is a deploy fault (500 here at request-time; a boot `DiagCode` fail-before-bind is
the honest follow-on); a residual host-promise violation is **502** (not 4xx — host-owned rows are not client
input); denial 403; transient 503; product semantics stay app-owned. **Honest naming:** drift is a JSON 500
error `code`, **not** yet a `runner_diag.rs::DiagCode` with a non-zero exit before bind — that promotion is
P8.

## Compatibility story for `rows_json`

Preserved. `LegacyRowsJson` continuations cross `{ req, rows_json, carry }` exactly as before; the
"neither → legacy" default keeps even continuations that ignore rows working unchanged. Proven:

- `readthen_dispatch_tests` (10, incl. the runaway-bound test) — green;
- `todo_postgres_read_host_tests` (4) — green;
- a single loaded P7 app routes `FetchLegacyTodos → LegacyTodoIndexFromRows` to the stringly path and
  `FetchTypedTodos → TypedTodoIndexFromRows` to the typed path — same `dispatch_with_read` loop,
  metadata-selected (`legacy_lane_still_routes_to_rows_json`, `typed_lane_auto_routes_…`).

## Test matrix

`server/igniter-web` — `--features machine`, fake adapter, DB-free.

**`tests/typed_readthen_tests.rs` (9):**
- `classify_reads_compiled_input_shapes` — `TypedTodoIndexFromRows` → `TypedRows{row_type:"TodoRow", declares_meta}`; `LegacyTodoIndexFromRows` → `LegacyRowsJson`; unknown → `Invalid`. (verify-first: metadata, not source.)
- `app_row_shape_recovers_field_types_from_type_defs` — `TodoRow` field types recovered from `type_defs`; unknown type fails closed.
- `typed_lane_auto_routes_and_crosses_rows_and_meta` — entry `ReadThen` → host auto-routes typed → `RespondView 200`, `kind == meta.source`, pending item label `"Buy milk"` (map+call_contract over typed rows).
- `typed_lane_empty_is_app_not_found_404` — empty typed collection → app 404.
- `legacy_lane_still_routes_to_rows_json` — legacy entry → `rows_json` string body, 200.
- `schema_drift_fails_closed_before_dispatch` — host `done:Text` vs `TodoRow.done:Bool` → 500 `projection_schema_drift`, **adapter query_count 0** (before the read).
- `row_shape_mismatch_maps_to_502` — matched policy, row missing `done` → 502 `projection_row_mismatch`, query_count 1.
- `denied_source_stays_403` — policy allows only `orders`; `todos` read denied → 403, query_count 0.
- `typed_without_policy_fails_closed` — typed continuation, host has no read policy → 500 `typed_read_unconfigured`.

**Regression (green):** `typed_row_crossing_tests` (9), `readthen_dispatch_tests` (10),
`todo_postgres_read_host_tests` (4), `read_materialize` unit (8); full `igniter-web --features machine` green;
`igniter-machine` full suite green (registry/machine accessor change). `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test typed_readthen_tests          # 9 passed
cargo test --features machine --test readthen_dispatch_tests       # 10 passed
cargo test --features machine --test typed_row_crossing_tests      # 9 passed
cargo test --features machine --test todo_postgres_read_host_tests # 4 passed
cargo test --features machine                                      # full suite green
# from runtime/igniter-machine
cargo test                                                         # full suite green
```

## Files changed

| File | Change |
| --- | --- |
| `runtime/igniter-machine/src/registry.rs` | `ContractRegistry.type_defs` + `register_type_def` / `type_def`. |
| `runtime/igniter-machine/src/machine.rs` | Persist `typed.type_env` into the registry at `load_contract_source` (additive metadata). |
| `server/igniter-web/src/read_continuation.rs` *(new)* | `classify_continuation` (input-shape routing from `input_ports`) + `app_row_shape` (row field types from `type_defs`). |
| `server/igniter-web/src/read_dispatch.rs` | `StagedReadHost::with_read_policy` + `projection_spec_for` + `source_allowlisted`. |
| `server/igniter-web/src/lib.rs` | `dispatch_with_read` typed/legacy routing + reconciliation + `respond_json`; `read_continuation` module reg. |
| `server/igniter-web/tests/fixtures/typed_readthen/typed_readthen.ig` *(new)* | typed + legacy `ReadThen` lanes in one app. |
| `server/igniter-web/tests/typed_readthen_tests.rs` *(new)* | 9 routing/reconciliation tests. |

## Verdict

- **Auto-routing + request-time reconciliation: `implemented`** in the normal `dispatch_with_read` contour,
  driven by compiled metadata (no source parsing). Typed continuations receive `rows : Collection[TodoRow]` +
  `meta : DatasetMeta`; host reconciles policy ⇎ row type before business logic; drift/mismatch/denied/
  transient map to 500/502/403/503; `rows_json` untouched.
- **Boot-time reconciliation: not done (honest).** Reconciliation is request-time/first-dispatch; the
  structural-at-boot pass + a `DiagCode::ProjectionSchemaDrift` that fails the listener before bind is the
  named P8 follow-on (the metadata it needs now exists).

## Remaining gap before TodoApp HTML can consume typed rows

The typed read → typed `Collection[HtmlNode]` view join now works end to end through the runner
(`TypedTodoIndexFromRows` already returns a `RespondView`/`View`). What's left for a real Todo HTML list is
cosmetic/product, not boundary: a richer `View`/`ViewArtifact` vocabulary (the LINK-NODE / HTML-expression
arc) and the read→HTML demo wiring — none blocked by the data boundary.

## Next cards

- **`LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8`** — structural boot pass over typed continuations
  (`<AppRow>` resolvable + every field has a v0 landing) + promote drift to a `runner_diag.rs::DiagCode`
  (fail-before-bind, non-zero exit) where the `(source, continuation)` binding is statically recoverable;
  first-dispatch reconcile cache for the dynamic remainder.
- **`LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P8`** — read → typed `Collection[HtmlNode]` Todo list
  demo using `meta.truncated` for a "load more" affordance (pairs with the HTML-expression arc).
- **Deferred (named):** typed `Decimal`/`Timestamp` (`value.rs:82-91` bridge); nested `Json` → record;
  `Dataset[T]` generic envelope (needs user generics); cross-source facts/decoder lanes.
