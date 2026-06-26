# LAB-TODOAPP-VIEW-DB-MONEY-REPORT-ROUTE-P25

Status: CLOSED (2026-06-26) — additive money-report HTML route in todo_postgres_app, DB-free proven; host.toml can't express Decimal → prod deploy gated on named host-config follow-on; host.example.toml untouched
Route: standard / product view payoff implementation
Skill: idd-agent-protocol

## Gate

Do **not** start until:

- `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23` is CLOSED.
- `LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24` is CLOSED.

If either is not closed, stop and report `blocked: waiting for Decimal money
proof`.

## Goal

Promote the P24 DB-backed Decimal money report from a standalone test fixture
into an additive `todo_postgres_app` product route, while keeping the scope
honest:

```text
GET /accounts/:account_id/report/money
  -> ReadThen
  -> typed Decimal[2] rows
  -> to_text + pad_left + Decimal fold total
  -> RenderView HTML
```

This should prove that the real app can host exact-money HTML reports through
the same `ReadThen` + `RenderView` seam. It is **not** a report engine, currency
formatter, invoice product, or schema migration.

## Current Authority

Read first:

- `lab-docs/lang/lab-todoapp-view-db-decimal-money-report-p24-v0.md`
- `server/igniter-web/tests/fixtures/db_money_report/db_money_report.ig`
- `server/igniter-web/tests/db_money_report_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/tests/todo_postgres_html_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/src/host_config.rs`

Live code wins. If product host config cannot express `Decimal { scale: 2 }`,
stop and write the exact host-config follow-up instead of faking a product
route.

## Task

1. Add an additive report route under account scope. Suggested path:

```igweb
route GET "/report/money" -> AccountMoneyReport
```

Place it before parameterized routes if necessary; IgWeb order is authored
order and static routes can be shadowed by earlier `:todo_id` patterns.

2. Add product `.ig` handlers by adapting the P24 fixture:

- query rows with `label : String`, `amount : Decimal[2]`;
- optionally filter by `account_id` if the product route is account-scoped;
- render exact cells with `pad_left(to_text(amount), 8, " ")`;
- compute exact Decimal total via `fold`;
- return `RenderView`.

3. Add host policy support in `host.example.toml` only if typed Decimal field
kinds are already expressible there. If not, keep the route DB-free/test-only
and close with a host-config card.

4. Add tests:

- DB-free fake adapter route proof;
- scale drift fail-closed;
- route-order proof if the route sits near `/:todo_id`;
- DSN-gated real Postgres `numeric` proof only if it can be done without
  schema/migration leakage.

## Closed Surfaces

- No schema migration runner.
- No currency/locale/grouping.
- No Float money.
- No app-local decimal parser.
- No PDF/XLSX/export.
- No streaming/file download.
- No broad report DSL.
- No production DB ownership claim.

## Acceptance

- [x] P23 and P24 verified CLOSED before implementation. — both CLOSED (gate check)
- [x] Additive product route exists, not shadowed by `/:todo_id`. — `/accounts/:account_id/report/money` (3rd seg `report`≠`todos`); `report_route_is_reached_not_shadowed`
- [x] Route returns `text/html` through `RenderView`, not JSON. — `money_report_route_renders_exact_cells_and_total`
- [x] Typed `Decimal[2]` rows cross through host materializer, not app parser. — `allow_source_typed(...,("amount",Decimal{2}))`; materialize reshapes digit-string→Value::Decimal (P23)
- [x] Rendered cells preserve trailing zeroes + padding. — `   12.50`/`    0.05`/` 1200.00`
- [x] Exact Decimal total computed in `.ig`. — `fold(rows, decimal(0,2), (acc,r)->acc+r.amount)` = `TOTAL 1212.55`
- [x] Label escaping renderer-owned. — `Coffee &lt;script&gt;`, no raw `<script>`
- [x] Scale drift fails closed before rendering. — `money_report_scale_drift_fails_before_render` (host Decimal{3} vs app Decimal[2] → 500, qc 0)
- [x] Existing Todo API routes unchanged. — additive; full suite + product-surface green
- [x] Docs mark the report as lab/product proof, not a report engine. — API.md "HTML view routes" section
- [x] `todo_postgres_html_tests` passes. — 4
- [x] `db_money_report_tests` passes. — 2
- [x] `cargo test --features machine` (igniter-web) passes. — 44 ok-blocks
- [x] Real Postgres test: not added (DB-free per host-config blocker; would need typed-Decimal host config). N/A
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Gate:** P23 + P24 both CLOSED → not blocked.

**Verify-first:** `host.toml` CANNOT express a typed `Decimal{scale}` field kind (`host_config.rs` `[postgres.read]
fields` = flat Text allowlist → `read_policy_binding` `allow_source` → all Text). Per Current Authority: did NOT
fake host-config support — `host.example.toml` untouched; route proven DB-free with a `Decimal`-typed harness
policy; production deploy gated on the named host-config follow-on. Seam open (P23 crossing/materializer/reconcile
real); only config syntax deferred.

**Route:** `GET /accounts/:account_id/report/money -> AccountMoneyReport` (top-level, 3rd seg `report` ≠ `todos`
→ no shadow). **Handlers** (product `.ig`, reuse P21 helpers): `MoneyLineRow{amount:Decimal[2]}` + `MoneyLineHtml`
+ `ListAccountMoney` + `AccountMoneyReport`→`ReadThen`→`AccountMoneyReportFromRows` (map cells + `fold`-Decimal-
total → `RenderView`).

**Rendered:** `12.50`/`0.05`/`1200.00` padded into an 8-col, exact `TOTAL 1212.55` (real Decimal fold); label
escaped; empty → app-owned `TOTAL 0.00`. Scale drift → 500 before render (qc 0).

**Files:** routes.igweb (+route), todo_handlers.ig (+5 contracts/type), API.md (+HTML-routes section), new
`tests/todo_postgres_money_report_tests.rs` (4). `host.example.toml` + `src/` NOT touched. No export/currency/
schema/Float/decimal-parser leaked.

**Counts:** money-report 4; db_money_report 2; todo_postgres_html 4; full igweb `--features machine` **44
ok-blocks**; product-surface guard **PASS**; `git diff --check` clean.

**Next card (shared with P53):** `LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS` — per-field decode-kind syntax
in `host.toml [postgres.read]` → `allow_source_typed`. Then this money route (and typed `Bool` `done`, P53)
deploy in production with NO `.ig` change.

## Reporting

Close with:

- route path and shadowing/order evidence;
- exact host typed Decimal policy shape, or exact blocker if host config cannot
  express it;
- rendered money examples and total;
- test counts;
- confirmation no export/currency/schema work leaked in.

