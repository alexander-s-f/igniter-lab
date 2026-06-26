# lab-todoapp-view-db-decimal-money-report-p24-v0

Card: `LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24`
Route: standard / product view implementation · Skill: idd-agent-protocol
Status: implemented (DB-backed exact-money report HTML over typed `Decimal[2]` rows) · test-only, zero production change · no canon claim
Date: 2026-06-26
Builds on: **P23 Decimal crossing** (gate) · P20 authored-Decimal money render · P21 DB-backed Todo HTML · P7 typed runner crossing

> **Authority boundary.** Lab product evidence. Composes the P23 typed-Decimal read + the P20/P21 view
> surface; no language/renderer/server/schema change, **no canon claim.** A view-layer proof.

---

## Gate

P23 (`LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23`) is **CLOSED** and Decimal row crossing is live — so
this card proceeds (no `blocked`, no app-local string parser, no money-as-Float).

## Headline

A host `numeric` column now drives an **exact money report rendered as HTML, end to end through the normal
`ReadThen` runner** — `host numeric "12.50" → .ig Decimal[2] → to_text → pad_left → RenderView`, with a **real
Decimal `fold`-total**. No `rows_json`, no Float, no in-`.ig` decimal parser, no currency/locale, no renderer
change. Escaping stays renderer-owned. This is the product payoff of P23: DB-shaped rows carry **real Decimal**
values into `.ig`, are summed exactly, and render with trailing zeroes preserved.

## Fixture / route

`server/igniter-web/tests/fixtures/db_money_report/db_money_report.ig` (self-contained, DB-free):

```text
FetchMoneyReport(req) -> ReadThen { plan: ListMoney("lines"), then: "MoneyReportFromRows" }
MoneyReportFromRows(req, rows : Collection[LineRow], meta : DatasetMeta)
  lines      = map(rows, r -> MoneyRowLine(r))                         -- per-row money cell
  total      = fold(rows, decimal(0,2), (acc, r) -> acc + r.amount)    -- REAL Decimal sum
  total_node = MakeMoneyLabel(concat("TOTAL", pad_left(to_text(total), 8, " ")))
  body       = concat(lines, [total_node])
  -> MakeMoneyFormView(meta.source, body) -> RenderView 200

MoneyRowLine(row) -- cell = pad_left(to_text(row.amount), 8, " "); line = concat(row.label, cell)
type LineRow { label : String  amount : Decimal[2] }   -- amount scale matches host Decimal{scale:2}
```

The host read policy declares `amount` as the typed kind (P23): `allow_source_typed("lines", &[("label",
Text), ("amount", Decimal { scale: 2 })])`. The adapter returns `amount` as the exact decimal STRING
(`"12.50"`); the host materializer parses it to `Decimal[2]`. `to_text(r.amount)` only typechecks because
`amount` is a real Decimal — a String would be rejected — so the report compiling + rendering is itself proof.

## Crossed rows + rendered strings

| host `amount` (string) | `.ig Decimal[2]` | `to_text` | `pad_left(…, 8, " ")` cell |
| --- | --- | --- | --- |
| `"12.50"` | `1250@2` | `12.50` | `   12.50` (3 spaces) |
| `"0.05"` | `5@2` | `0.05` | `    0.05` (4 spaces) |
| `"1200.00"` | `120000@2` | `1200.00` | ` 1200.00` (1 space) |

**Decimal fold-total:** `12.50 + 0.05 + 1200.00 = 1212.55` → rendered `TOTAL 1212.55` (exact — a String could
not be summed). **Escaping:** the `"Coffee <script>"` label renders `Coffee &lt;script&gt;`, no raw markup.

The test asserts the **exact** padded substrings + the total + the escaped label in the `text/html` body.

## Behavior / error ownership

- **Scale drift** (host `Decimal{scale:3}` vs app `Decimal[2]`) → the P7/P23 reconciler fails closed **before
  the read** (HTTP 500 `projection_schema_drift`, adapter query_count 0) — no partial HTML.
- **No Float / no app-local parser** — `amount` crosses via the P23 host parse (`{value,scale}` →
  `Value::Decimal`); a Float value would be refused by `value_matches_kind` upstream (proven in P23).
- Denial/transient stay host-owned (403/503) as on every typed read.

## Files changed (test-only — zero production code)

| File | Change |
| --- | --- |
| `tests/fixtures/db_money_report/db_money_report.ig` *(new)* | `LineRow{amount:Decimal[2]}`, `MoneyRowLine`, `ListMoney`, `FetchMoneyReport`, `MoneyReportFromRows` + HTML helpers. |
| `tests/db_money_report_tests.rs` *(new, 2)* | the full DB-backed money report + scale-drift fail-closed. |

Reuses the P23 Decimal crossing + the existing renderer/runner verbatim — **no production source change**.

## Tests / counts

`tests/db_money_report_tests.rs` (**2**, `--features machine`, DB-free, full `dispatch_with_read`):
`db_decimal_rows_render_money_report_with_total`, `scale_drift_fails_before_render`.

**Regression (green):** `typed_html_tests` (7), `todo_postgres_html_tests` (9), `decimal_crossing_tests` (4),
`typed_row_crossing_tests` (6); full `igniter-web --features machine` green (**42 ok-blocks, 0 failures** — the
earlier in-flight P50 read-host wiring gap is resolved). `igniter-render-html` UNTOUCHED. `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test db_money_report_tests   # 2 passed
cargo test --features machine                                # full suite green (42 ok-blocks)
```

## Reporting

- **Route added:** `FetchMoneyReport` → `ReadThen` → `MoneyReportFromRows` (typed `Collection[LineRow]` +
  `DatasetMeta`) → `RenderView` HTML, in the new `db_money_report` fixture.
- **Crossed Decimal rows / rendered strings:** `"12.50"/"0.05"/"1200.00"` → `Decimal[2]` →
  `   12.50`/`    0.05`/` 1200.00` (padded to width 8); label escaped `Coffee &lt;script&gt;`.
- **Total:** `1212.55` (exact Decimal `fold`), rendered `TOTAL 1212.55`.
- **Counts:** db_money_report 2; full igniter-web `--features machine` green; render-html untouched; diff clean.
- **No Float/parser/currency/renderer/schema leaked:** confirmed — `amount` crosses via P23's host
  `Decimal{scale}` materializer; the only decimal parse is host-side (`parse_decimal`), never in `.ig`.
- **Next product card:** `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-ROUTE-P25` (optional) — promote this fixture into a
  real `examples/todo_postgres_app` route (`GET …/report.html`) with a `Decimal{2}` column in `host.example.toml`,
  mirroring P21; and an optional DSN-gated real-Postgres `numeric` proof. Presentation niceties (currency
  symbol, thousands grouping) stay view-layer, not new primitives.
