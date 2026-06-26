# LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24

Status: CLOSED (2026-06-26) — DB-backed exact-money report HTML over typed Decimal[2] rows; test-only, zero production change
Route: standard / product view implementation
Skill: idd-agent-protocol

## Gate

Do **not** start this card until
`LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23` is CLOSED and Decimal row
crossing is live.

If P23 is not closed, stop and report `blocked: waiting for Decimal crossing`.
Do not invent app-local string parsing or money-as-Float workaround.

## Goal

Turn the P20 authored Decimal money report into a DB-backed typed-row HTML proof:

```text
host row amount:numeric/Decimal -> .ig Decimal[2] -> to_text(amount)
  -> pad_left(...) -> RenderView HTML
```

This is product payoff for exact money crossing. It should prove that a DB-shaped
row can carry real Decimal values into `.ig`, be used in Decimal arithmetic, and
render with trailing zeroes preserved.

## Current Authority

Read first:

- `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23` card + closing report
- `lab-docs/lang/lab-todoapp-view-db-money-report-readiness-p22-v0.md`
- `lab-docs/lang/lab-todoapp-view-money-report-p20-v0.md`
- `server/igniter-web/tests/typed_html_tests.rs`
- `server/igniter-web/tests/fixtures/typed_html/typed_html.ig`
- `server/igniter-web/tests/todo_postgres_html_tests.rs`
- `server/igniter-web/src/read_materialize.rs`
- `server/igniter-web/src/read_continuation.rs`

Live code wins. Reuse the smallest existing fixture unless the product app is
cleaner after P23.

## Task

Add a DB-backed money/report fixture or product route that:

- reads rows with `label : String` and `amount : Decimal[2]`;
- renders each amount with `to_text(amount)` and `pad_left(..., 8, " ")`;
- computes a Decimal total with `fold`;
- renders the total with `to_text(total)`;
- proves escaping remains renderer-owned.

Prefer a DB-free fake-adapter test first. A real Postgres test is optional and
must be DSN-gated if added.

## Closed Surfaces

- No Float money.
- No app-local decimal string parser.
- No currency/locale/grouping.
- No DB migration runner.
- No renderer changes.
- No broad report engine.
- No product API behavior changes unless the route is explicitly additive.

## Acceptance

- [x] Card refuses to proceed if P23 is not closed. — P23 verified CLOSED before starting (gate satisfied)
- [x] Rows cross as real `.ig Decimal[2]`, not String. — `to_text(r.amount)` typechecks (String would be rejected) + fold-sum works
- [x] `to_text(amount)` preserves trailing zeroes. — `12.50`/`0.05`/`1200.00`
- [x] `pad_left(to_text(amount), 8, " ")` produces exact visible cells. — `   12.50`/`    0.05`/` 1200.00`
- [x] Decimal `fold` total is exact and rendered. — `TOTAL 1212.55` (12.50+0.05+1200.00)
- [x] Scale drift fails closed before rendering. — `scale_drift_fails_before_render` (500, query_count 0)
- [x] Unsafe label text escaped in HTML. — `Coffee &lt;script&gt;`, no raw `<script>`
- [x] Existing typed HTML / Todo HTML tests green. — typed_html 7, todo_postgres_html 9
- [x] New focused test passes. — `db_money_report_tests` 2
- [x] `cargo test --features machine` in `server/igniter-web` passes. — full suite green (42 ok-blocks, 0 failures)
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Gate:** P23 CLOSED → proceeded. Full chain proven end-to-end through `dispatch_with_read`: host `numeric`
column → `.ig Decimal[2]` (P23 materializer) → `to_text`+`pad_left` money cells + real Decimal `fold`-total →
`RenderView` escaped text/html.

**Fixture/route:** `db_money_report.ig` — `FetchMoneyReport`→`ReadThen`→`MoneyReportFromRows(rows :
Collection[LineRow{amount:Decimal[2]}], meta : DatasetMeta)`. Policy `allow_source_typed("lines",
[("amount", Decimal{scale:2})])`.

**Crossed rows / rendered:** `"12.50"/"0.05"/"1200.00"` → `Decimal[2]` → cells `   12.50`/`    0.05`/` 1200.00`;
**total `1212.55`** (`TOTAL 1212.55`); label escaped `Coffee &lt;script&gt;`. Scale drift (host{3} vs app[2]) →
500 `projection_schema_drift`, query_count 0.

**Files (test-only, ZERO production code):** `tests/fixtures/db_money_report/db_money_report.ig`,
`tests/db_money_report_tests.rs` (2), `lab-docs/lang/lab-todoapp-view-db-decimal-money-report-p24-v0.md`.

**Counts:** db_money_report **2**; typed_html 7 / todo_postgres_html 9 / decimal_crossing 4 / typed_row_crossing
6 green; full igniter-web `--features machine` **42 ok-blocks, 0 failures** (earlier P50 read-host gap resolved);
render-html untouched; `git diff --check` clean.

**No Float/parser/currency/renderer/schema leaked:** confirmed — `amount` crosses via P23 host `Decimal{scale}`
materializer; the only decimal parse is host-side.

**Next:** optional `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-ROUTE-P25` (promote into a real `todo_postgres_app` route +
`Decimal{2}` column in host.example.toml, mirroring P21; DSN-gated real-Postgres `numeric` proof).

## Reporting

Close with:

- exact fixture/route added;
- exact crossed Decimal rows and rendered strings;
- total calculation result;
- tests/counts;
- confirmation no Float/parser/currency/renderer/schema work leaked in.

