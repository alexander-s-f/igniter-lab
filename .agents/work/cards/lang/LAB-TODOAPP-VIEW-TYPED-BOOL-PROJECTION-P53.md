# LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION-P53

Status: CLOSED (2026-06-26) — DB-free proof-only lane (host Boolean→.ig Bool→filter→summary); host.toml can't express typed kinds → shipped API stays String; follow-up named
Route: standard / product typed projection implementation
Skill: idd-agent-protocol

## Goal

Introduce a Todo product lane that reads `done` as a real `Bool` instead of a
Text/String field, then prove app logic can branch/filter on it in a Todo-facing
view or API proof.

This does **not** change the existing product list API unless the card proves
the migration is safe. The primary goal is to validate the host-policy lane:

```text
host Boolean kind -> .ig Bool field -> filter/branch/render
```

The motivating open claim is currently explicit:

- P50 kept `TodoListRow.done : String` because `host.example.toml` uses untyped
  field allowlists.
- `IMPLEMENTED_SURFACE.md` marks typed Bool `done` as deferred product work.

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `lab-docs/lang/lab-igniter-data-projection-typed-row-crossing-p6-v0.md`
- `lab-docs/lang/lab-todoapp-view-typed-rows-html-p18-v0.md`
- `lab-docs/lang/lab-todoapp-view-db-backed-todo-html-p21-v0.md`
- `server/igniter-web/tests/typed_row_crossing_tests.rs`
- `server/igniter-web/tests/typed_html_tests.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `runtime/igniter-machine/src/postgres_read.rs`

Live code wins. Verify whether `host.toml` can express per-field typed read
kinds for product config today. If not, stop and write the minimal readiness
delta instead of hardcoding a test-only shortcut into product code.

## Task

Preferred implementation if host config supports it:

1. Add an additive typed read source or source mode for `todos` where `done`
   is `Boolean`.
2. Add a Todo view/API proof route or test fixture whose app row declares:

```ig
type TodoBoolRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
}
```

3. Prove real Bool semantics in `.ig`:

```ig
pending = filter(rows, t -> t.done == false)
done    = filter(rows, t -> t.done == true)
```

4. Render or return a small typed JSON/ViewArtifact summary.

If product host config cannot yet express typed kinds, implement only a DB-free
proof over `allow_source_typed("todos", [("done", Boolean), ...])` and close
with the exact host-config follow-up card.

## Closed Surfaces

- No silent migration of the existing list API from String to Bool unless all
  product tests and docs are updated intentionally.
- No broad decoder DSL.
- No DB schema migration.
- No Boolean string parsing in `.ig`.
- No "truthy" coercion.
- No change to `done` write semantics (`"true"` string remains the v0 write
  value unless a separate write-shape card changes it).
- No global product API stability claim.

## Acceptance

- [x] Verify live host-config typed-kind expressiveness and state result. — **`host.toml` CANNOT** (flat `fields` → `allow_source` → all Text); doc §"Verify-first"
- [x] Host `Boolean` read kind lands in `.ig Bool` for a Todo row. — `boolean_kind_crosses_and_filters_both_directions`
- [x] App logic proves real Bool behavior with `filter`/`if`, not string compare. — `filter(t->t.done==false/true)` + `all_done` Bool
- [x] Kind drift (Text host vs Bool app; Boolean host vs String app) fails closed before dispatch. — `text_host_vs_bool_app_drifts_before_dispatch` (500, qc 0) + `boolean_host_vs_string_app_is_drift`
- [x] P50 list route behavior remains green (not migrated). — shipped API untouched; list tests green
- [x] Existing Todo HTML/API tests remain green. — full suite green
- [x] New focused tests pass. — `typed_bool_projection_tests` 5
- [x] Docs say exactly what is implemented: **proof-only lane** (not product route, not list migration). — IMPLEMENTED_SURFACE.md + API.md
- [x] `typed_row_crossing_tests` passes. — 9
- [x] `typed_html_tests` passes. — 7
- [x] `cargo test --features machine` (igniter-web) passes. — 43 ok-blocks
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Verify-first:** `host.toml` per-field typed kinds = **NOT expressible** today. `host_config.rs`
`PostgresReadConfig.fields : Vec<String>` (flat comma-list) → `read_policy_binding` `allow_source(...)` → all
Text. Only the Rust `allow_source_typed` carries per-field kinds (tests). So per the card: DB-free proof-only
lane; shipped API NOT migrated (host.toml couldn't carry Boolean anyway).

**Proof (test-only, zero production):** `TodoBoolRow { …, done : Bool }` over `allow_source_typed("todos", […,
("done", Boolean)])`; through `dispatch_with_read` → `filter(t->t.done==false)`=pending, `==true`=done,
`all_done` (Bool from Integer compare) → typed `RespondJson` summary `{total,pending,done_count,all_done}`.
Drift both directions fail closed (Text host vs Bool app → 500 before read, qc 0; Boolean host vs String app →
reconcile Err; matched Boolean→Bool ok).

**Files:** `tests/fixtures/typed_bool/typed_bool.ig` + `tests/typed_bool_projection_tests.rs` (5) [new];
`IMPLEMENTED_SURFACE.md` + `API.md` (lane proven DB-free, not shipped; dropped stale "typed show route"
deferral). **Shipped list/show API unchanged — `done : String`.**

**Counts:** typed_bool 5; typed_row_crossing 9; typed_html 7; full igweb `--features machine` **43 ok-blocks**;
product-surface guard **PASS**; `git diff --check` clean.

**Next card (named):** `LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS` — add per-field decode-kind syntax to
`host.toml [postgres.read]` (parse in `host_config.rs` → `read_policy_binding` → `allow_source_typed`). Once
landed, `done:Boolean` (and money `Decimal`, P23) adopt in the shipped API with NO `.ig` change (crossing +
reconciliation already proven). The host-config syntax is the ONLY missing piece.

## Reporting

Close with:

- whether typed Bool is product-configurable today or only test-harness
  configurable;
- exact row shape and policy shape;
- drift behavior;
- whether the shipped list API changed or stayed String-backed;
- next card if host-config typed kind syntax is still missing.

