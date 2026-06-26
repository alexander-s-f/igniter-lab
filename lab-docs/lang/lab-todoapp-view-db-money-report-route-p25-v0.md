# lab-todoapp-view-db-money-report-route-p25-v0

Card: `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-ROUTE-P25`
Route: standard / product view payoff implementation · Skill: idd-agent-protocol
Status: implemented (additive `todo_postgres_app` money-report HTML route, DB-free proven) · `host.toml` untouched · production deploy gated on the named host-config follow-on · no canon claim
Date: 2026-06-26
Gate: P23 (Decimal crossing) CLOSED · P24 (DB money report fixture) CLOSED — both verified before start
Builds on: P23 typed `Decimal[N]` crossing · P24 money report · P20 money surface · P21 DB-backed Todo HTML

> **Authority boundary.** Lab product evidence. Adds an additive HTML report route to the example app; no
> language/renderer/server/DB-schema change, **`host.toml` not modified**, **no canon claim.** Not a report
> engine / currency formatter / export surface.

---

## Gate check

- `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23` → **CLOSED** (host `Decimal{scale}` → `{value,scale}` →
  `Value::Decimal`; `app_field_type`/`kind_assignable`/`materialize_rows` all handle Decimal).
- `LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24` → **CLOSED** (`db_money_report.ig` + `db_money_report_tests.rs`
  prove the report DB-free with a fold-total + scale-drift).

Both closed → not blocked.

## Verify-first (the host-config gate the card flags)

**`host.toml` cannot express a typed `Decimal{scale}` field kind today** (same finding as P53's Boolean lane):
`host_config.rs` parses `[postgres.read] fields = "a,b,c"` into a flat `Vec<String>`, and `read_policy_binding`
maps it with `allow_source(...)` → **all Text**. There is no path to `allow_source_typed` (per-field kinds)
from product config. So per the card's Current Authority — **do not fake a product route by pretending
`host.toml` supports Decimal.** Instead: the route + handlers are real product `.ig`, proven **DB-free** with a
`Decimal`-typed harness policy; **`host.example.toml` is NOT modified**; production deploy awaits the named
host-config follow-on. The descriptor→bytes seam is fully open (P23 crossing + materializer + reconcile are
real); only the operator config syntax is deferred — not foreclosed.

## Route added

`server/igniter-web/examples/todo_postgres_app/routes.igweb`:

```igweb
route GET "/accounts/:account_id/report/money" -> AccountMoneyReport
```

A top-level route (the `:account_id` capture crosses as `input account_id : Option[String]`). **No shadowing:**
its 3rd path segment is `report`, distinct from `todos` (index) and `todos/:todo_id` (show) — the show pattern
`/accounts/:a/todos/:t` can never match `/accounts/:a/report/money`. Proven by
`report_route_is_reached_not_shadowed` (the report renders, so the route is reached).

## Handlers (product `.ig`, reusing P21 helpers)

```text
type MoneyLineRow { account_id : String  label : String  amount : Decimal[2] }

ListAccountMoney(account_id)  -- QueryPlan { source: "money_lines", projection: [account_id,label,amount],
                              --             filters: [account_id eq], order_by: [], limit: 50 }
AccountMoneyReport(req, account_id) -> ReadThen { plan, then: "AccountMoneyReportFromRows" }
MoneyLineHtml(row)            -- pad_left(to_text(row.amount), 8, " ") |> concat(label) -> MakeHtmlLabel
AccountMoneyReportFromRows(req, rows : Collection[MoneyLineRow], meta : DatasetMeta):
  lines = map(rows, r -> MoneyLineHtml(r))
  total : Decimal[2] = fold(rows, decimal(0, 2), (acc, r) -> acc + r.amount)   -- REAL Decimal arithmetic
  body  = concat(lines, [ MakeHtmlLabel(concat("TOTAL", pad_left(to_text(total), 8, " "))) ])
  RenderView { 200, MakeHtmlFormView("Money", body) }
```

`amount : Decimal[2]` is an EXACT host-materialized Decimal (a String would be rejected by `to_text` and `+`).
Reuses the P21 `MakeHtmlLabel`/`MakeHtmlFormView`/`DatasetMeta` (no duplicate helpers).

## Rendered money (proven)

| Row | `to_text` | `pad_left(…, 8, " ")` | HTML |
| --- | --- | --- | --- |
| `12.50` | `12.50` | `   12.50` | `Coffee &lt;script&gt;   12.50` |
| `0.05` | `0.05` | `    0.05` | `Books    0.05` |
| `1200.00` | `1200.00` | ` 1200.00` | `Gift 1200.00` |
| **fold-total** | `1212.55` | ` 1212.55` | `TOTAL 1212.55` |

`12.50 + 0.05 + 1200.00 = 1212.55` — exact Decimal arithmetic, not String concatenation. Label escaped
(`&lt;script&gt;`), no raw markup. Title `<h1>Money</h1>` (`meta.source` is the form title via `MakeHtmlFormView`).
Empty account → app-owned `200` with `TOTAL    0.00` (fold seed over zero rows).

## Behavior / drift

- **Scale drift** (host `Decimal{scale:3}` vs app `Decimal[2]`) → **500 `projection_schema_drift`** before the
  read; no HTML; adapter `query_count == 0` (`money_report_scale_drift_fails_before_render`). The scales must
  match exactly (P23 `kind_assignable`).
- **Denied source / transient** stay host-owned (403/503) — unchanged.
- **Empty** → app-owned 200 (a report of zero lines is valid), not an error.

## Files changed

| File | Change |
| --- | --- |
| `examples/todo_postgres_app/routes.igweb` | `+ route GET "/accounts/:account_id/report/money" -> AccountMoneyReport`. |
| `examples/todo_postgres_app/todo_handlers.ig` | `+ type MoneyLineRow`, `MoneyLineHtml`, `ListAccountMoney`, `AccountMoneyReport`, `AccountMoneyReportFromRows` (reuse P21 helpers). |
| `examples/todo_postgres_app/API.md` | new "HTML view routes" section documenting `todos.html` (P21) + `report/money` (P25) as lab/product proofs; the money route's host-config dependency named. |
| `tests/todo_postgres_money_report_tests.rs` *(new, 4)* | product route over the real example, fake adapter. |

**`host.example.toml` NOT modified** (it cannot express the `Decimal` kind). No `src/` production change — the
route + handlers are `.ig`; the typed crossing/materializer/reconcile already shipped (P23). No DB schema, no
export, no currency/locale.

## Tests / counts

`tests/todo_postgres_money_report_tests.rs` (**4**, `--features machine`, DB-free): exact cells + fold-total;
scale-drift fail-closed; route-order (report reached, not shadowed); empty → app-owned `TOTAL 0.00`.

**Regression (green):** `db_money_report_tests` (2, P24), `todo_postgres_html_tests` (4, P21); full
`igniter-web --features machine` green (**44 ok-blocks**); product-surface CI guard **PASS** (doc markers
intact); existing Todo API routes unchanged; `git diff --check` clean.

```bash
cargo test --features machine --test todo_postgres_money_report_tests   # 4 passed
cargo test --features machine --test db_money_report_tests              # 2 passed (P24)
cargo test --features machine --test todo_postgres_html_tests           # 4 passed (P21)
cargo test --features machine                                          # 44 ok-blocks
bash scripts/check_todo_product_surface.sh                             # PASS
```

## Reporting

- **Route + shadowing:** `GET /accounts/:account_id/report/money -> AccountMoneyReport`; 3rd segment `report`
  ≠ `todos`, so the `/todos/:todo_id` show pattern never shadows it (proven).
- **Host typed Decimal policy shape / blocker:** `allow_source_typed("money_lines", [("account_id",Text),
  ("label",Text),("amount",Decimal{scale:2})])` — **Rust-only; `host.toml` CANNOT express it.** Exact blocker:
  `host_config.rs` `[postgres.read] fields` is a flat Text allowlist. → host-config follow-on named.
- **Rendered money + total:** `12.50`/`0.05`/`1200.00` (padded), exact `TOTAL 1212.55`; empty → `TOTAL 0.00`.
- **Counts:** money-report 4; full igweb 44 ok-blocks; product-surface PASS; diff clean.
- **No leakage:** no export (PDF/XLSX), no currency/locale/grouping, no Float, no schema migration, no
  app-local decimal parser, no report DSL.

## Next card (the only missing piece)

**`LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS`** — per-field decode-kind syntax in `host.toml`
`[postgres.read]` (parse in `host_config.rs` → `read_policy_binding` → `allow_source_typed`). Once landed, the
money report route (and a typed-`Bool` Todo `done`, P53) deploy in production with **no `.ig` change** — the
typed crossing + reconciliation are already proven. This is the single shared blocker for P25 and P53.
