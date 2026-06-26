# lab-todoapp-view-typed-bool-projection-p53-v0

Card: `LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION-P53`
Route: standard / product typed projection implementation · Skill: idd-agent-protocol
Status: implemented (DB-free **proof-only** lane) · shipped Todo API unchanged (stays `done : String`) · no canon claim
Date: 2026-06-26
Builds on: P6 typed-row-crossing (Boolean filter) · P7 reconciliation · P50 `RespondJson`

> **Authority boundary.** Lab proof. Validates the host `Boolean`→`.ig Bool` read lane in the test harness;
> **no production code change** (the shipped list/show API stays String-backed), **no canon claim.**

---

## Verify-first conclusion (the decisive question)

**`host.toml` CANNOT express per-field typed read kinds today.** The parser (`host_config.rs`) reads
`[postgres.read] fields = "id,account_id,title,done"` as a flat comma-list (`PostgresReadConfig.fields :
Vec<String>`), and `read_policy_binding` (`host_binding.rs`) maps it with `policy.allow_source(source,
&fields)` — which decodes **every field as `Text`**. There is no path from product host config to
`allow_source_typed` (per-field kinds). Per-field typed kinds are expressible **only** via the in-Rust
`allow_source_typed` API, used by tests.

**Therefore (as the card directs):** this card delivers a **DB-free proof-only lane** over
`allow_source_typed("todos", [("done", Boolean), …])`; it does **not** migrate the shipped Todo API (which
stays `done : String`, P50/P52) — `host.toml` could not carry the Boolean kind anyway. The missing piece is a
host-config typed-kind syntax → the named follow-on below.

## What the proof validates

Host `Boolean` decode-kind → `.ig Bool` field → real Bool branching → typed JSON summary via `RespondJson`,
through the normal `dispatch_with_read` runner contour (auto-routing + reconciliation + materialization, P7):

```text
type TodoBoolRow { id, account_id, title : String  done : Bool }

TodoBoolDigest(req, rows : Collection[TodoBoolRow], meta : DatasetMeta):
  pending_rows = filter(rows, t -> t.done == false)     -- REAL Bool, not a string compare
  done_rows    = filter(rows, t -> t.done == true)
  all_done     = if total == 0 { false } else { pending == 0 }   -- Bool computed from an Integer compare
  RespondJson { 200, body: { total, pending, done_count, all_done } }
```

The host policy supplies the kind: `allow_source_typed("todos", [("id",Text),("account_id",Text),
("title",Text),("done",Boolean)])` + `.with_read_policy`. Rows carry `done` as a **real JSON bool** (what a
`Boolean`-decoding adapter yields). The summary record serializes to the JSON body root via `RespondJson`.

## Drift — both directions, fail-closed before dispatch

| Direction | Where | Result |
| --- | --- | --- |
| host `Text` `done` vs app `Bool` | reconcile in `dispatch_with_read` (before the read) | **500 `projection_schema_drift`**, adapter `query_count == 0` |
| host `Boolean` `done` vs app `String` (matrix symmetry) | `reconcile_projection` (unit) | `Err("ProjectionSchemaDrift …`done`…")` — `Boolean` lands only in `Bool`, never `String` |
| matched `Boolean` → `Bool` | `reconcile_projection` | `Ok` |

This keeps the P2 silent-wrong hazard out of `.ig`: a `Bool`-typed `done` over a `Text` source (or vice
versa) never crosses.

## Row shape / policy shape

- **App row:** `TodoBoolRow { id : String, account_id : String, title : String, done : Bool }`.
- **Policy:** `allow_source_typed("todos", [("id",Text),("account_id",Text),("title",Text),("done",Boolean)])`
  (Rust-only; not `host.toml`-expressible).
- **Shipped API:** unchanged — `TodoListRow.done : String` over the Text host policy (P50/P52).

## Files changed (test-only — zero production code)

| File | Change |
| --- | --- |
| `tests/fixtures/typed_bool/typed_bool.ig` *(new)* | `TodoBoolRow {done : Bool}`, `TodoBoolSummary`, `FetchBoolTodos` → `ReadThen` → `TodoBoolDigest` (filter both directions → `RespondJson` summary). |
| `tests/typed_bool_projection_tests.rs` *(new, 5)* | the crossing + both drift directions. |
| `IMPLEMENTED_SURFACE.md`, `API.md` | state the lane is **proven DB-free (P53)** but not shipped (host-config syntax pending); also drop the now-stale "typed show route" deferral (done P52). |

## Tests / counts

`tests/typed_bool_projection_tests.rs` (**5**, `--features machine`, DB-free):
`boolean_kind_crosses_and_filters_both_directions` (pending 1 / done 2 / total 3 / all_done false),
`all_done_when_every_row_is_true`, `empty_is_all_done_false`, `text_host_vs_bool_app_drifts_before_dispatch`
(500, query_count 0), `boolean_host_vs_string_app_is_drift` (matrix symmetry + matched-ok).

**Regression (green):** `typed_row_crossing_tests` (9), `typed_html_tests` (7) — the acceptance-listed suites;
full `igniter-web --features machine` green (**43 ok-blocks**); product-surface CI guard **PASS**; the shipped
list/show API behavior unchanged; `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test typed_bool_projection_tests   # 5 passed
cargo test --features machine --test typed_row_crossing_tests      # 9 passed
cargo test --features machine --test typed_html_tests              # 7 passed
cargo test --features machine                                      # 43 ok-blocks
bash scripts/check_todo_product_surface.sh                         # PASS
```

## Reporting

- **Product-configurable today?** No — only test-harness configurable (`allow_source_typed`). `host.toml`'s
  `[postgres.read] fields` is a flat Text allowlist; no per-field kind syntax exists.
- **Row/policy shape:** `TodoBoolRow {…, done : Bool}` over `allow_source_typed("todos", […, ("done",
  Boolean)])`.
- **Drift behavior:** both directions fail closed — host `Text` vs app `Bool` → 500 before the read; host
  `Boolean` vs app `String` → reconciliation `Err` (matrix symmetry); matched `Boolean`→`Bool` reconciles ok.
- **Shipped list API:** **stayed String-backed** (unchanged) — deliberately not migrated (host config can't
  carry the Boolean kind, and the card forbids a silent migration).
- **Counts:** typed_bool 5; full igweb 43 ok-blocks; product-surface PASS; diff clean.

## Next card (the missing host-config syntax)

**`LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS`** — extend `host.toml [postgres.read]` (and
`[postgres.read.<name>]`) to express per-field decode kinds (e.g. `field_kinds = "done:boolean, rank:integer"`
or a typed `[postgres.read.fields]` table), parsed in `host_config.rs` and routed through `read_policy_binding`
→ `allow_source_typed`. Once that lands, the Todo `done` field (and money `Decimal` columns, P23) can be
adopted in the *shipped* API with no `.ig` change — the typed crossing + reconciliation are already proven.
Deferred siblings: typed `Timestamp`; nested `Json`→record.
