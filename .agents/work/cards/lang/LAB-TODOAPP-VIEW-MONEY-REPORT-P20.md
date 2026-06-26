# LAB-TODOAPP-VIEW-MONEY-REPORT-P20

Status: CLOSED (2026-06-26) — exact money cells in HTML via to_text(Decimal)+pad_left; test-only, zero production change
Route: standard / product-view proof
Skill: idd-agent-protocol

## Goal

Prove the immediate app payoff of the new exact formatting surface:

- `to_text(Decimal)` for money/report cells;
- `pad_left(to_text(...), width, pad)` for aligned table-ish labels;
- no local formatter helpers, no Float formatting, no renderer schema change.

This is a Todo/view-layer proof, not a new language feature.

## Current Authority

Read first:

- `.agents/work/cards/lang/LAB-LANG-DECIMAL-TO-TEXT-P2.md`
- `.agents/work/cards/lang/LAB-LANG-STRING-PAD-LEFT-P3.md`
- `lab-docs/lang/lab-lang-decimal-to-text-p2-v0.md`
- `lab-docs/lang/lab-lang-string-pad-left-p3-v0.md`
- `server/igniter-web/tests/fixtures/typed_html/typed_html.ig`
- `server/igniter-web/tests/typed_html_tests.rs`
- `server/igniter-web/examples/todo_view_app/` only if a product example is cleaner

Live code wins over card prose.

## Task

Add the smallest proof that `.ig` app code can render a tiny money/report view:

```ig
amount : Decimal[2] = decimal(12345, 2)
amount_text : String = to_text(amount)       -- "123.45"
cell : String = pad_left(amount_text, 8, " ")
```

Then feed that into existing `HtmlNode` helpers / `RenderView` so the HTML body contains
the exact string.

Preferred target: extend the existing `typed_html` fixture/tests if it is the smallest
place to prove the product-shaped flow. A separate fixture is acceptable if cleaner.

## Required Proofs

- Decimal value renders exact money text with trailing zeroes preserved (`12.00`
  or `123.45`).
- `pad_left` composes with `to_text(Decimal)` and produces visible alignment text.
- Escaping remains renderer-owned; no raw HTML.
- Float remains absent from the app proof.
- No `rows_json` boundary unless the chosen fixture already uses it for unrelated
  legacy coverage.

## Closed Surfaces

- No Float formatting.
- No currency symbols / locale / thousands grouping.
- No renderer schema change.
- No new ViewArtifact node kind unless already landed elsewhere.
- No server/runner/database changes.
- No broad report engine.

## Acceptance

- [x] An `.ig` route computes `Decimal[2]` via `decimal(value, 2)` and renders `to_text(decimal)` into HTML. — `MoneyReportHtml`/`MakeLineItem`
- [x] A visible string uses `pad_left(to_text(decimal), width, pad)`. — `MoneyRow.cell = pad_left(to_text(item.amount), 8, " ")`
- [x] Tests assert exact HTML content incl. preserved trailing zeroes. — `12.50`/`123.45`/`5.00` + exact padded cells
- [x] Tests assert no raw unsafe HTML leakage. — `Coffee &lt;script&gt;`, no raw `<script>`
- [x] Existing typed HTML / Todo view tests still pass. — typed_html 7, todo_view_app green
- [x] `cargo test --features machine --test typed_html_tests` passes. — **7 passed**
- [x] `igniter-render-html` — **renderer UNTOUCHED** (no source change); suite stays green.
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Files (test-only, ZERO production code):**
- `tests/fixtures/typed_html/typed_html.ig` — `+ type LineItem`, `MakeLineItem` (`decimal(cents,2)`), `MoneyRow`
  (`pad_left(to_text(item.amount), 8, " ")`), `MoneyReportHtml` (`map` over items → `FormView` → `RenderView`).
- `tests/typed_html_tests.rs` — `+ load_app_money` + `money_report_renders_exact_decimal_cells`.
- `lab-docs/lang/lab-todoapp-view-money-report-p20-v0.md` — proof doc.

**Rendered strings proven:** `decimal(1250,2)`→`12.50`, `decimal(12345,2)`→`123.45`, `decimal(500,2)`→`5.00`
(exact, trailing zeroes); right-aligned to width 8 (`   12.50` / `  123.45` / `    5.00`); user label escaped
(`Coffee &lt;script&gt;`), no raw markup. Money authored as Decimal in `.ig` (a host read would cross Decimal
as String — typed Decimal projection deferred).

**Counts:** `typed_html_tests` **7** (P18 4 / P19 2 / P20 1); full igniter-web `--features machine` green (26
ok-blocks); render-html untouched + green; `git diff --check` clean.

**Closed surfaces confirmed:** no Float, no currency/locale/grouping, no renderer schema/node change, no
server/runner/DB change, no report engine, no local formatter.

**Next slice:** host-Decimal lane (typed `Decimal` projection from a read via the deferred `value.rs:82-91`
`{value,scale}` bridge) → money FROM the DB as `Decimal`, the step toward a DB-backed report. Presentation
niceties (currency symbol, a Decimal-addition totals row) compose in view-layer, not new primitives.

## Reporting

Close with:

- exact app/fixture route or contract added;
- rendered strings proven;
- exact commands/counts;
- confirmation that Float/currency/locale/report-engine surfaces stayed closed.
