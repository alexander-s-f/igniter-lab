# lab-todoapp-view-money-report-p20-v0

Card: `LAB-TODOAPP-VIEW-MONEY-REPORT-P20`
Route: standard / product-view proof · Skill: idd-agent-protocol
Status: implemented (exact money cells in HTML via `to_text(Decimal)` + `pad_left`) · test-only, zero production change · no canon claim
Date: 2026-06-26
Builds on: P2 `to_text(Decimal)` · P3 `pad_left` · P18 typed-rows→HTML · the TodoView HTML helpers

> **Authority boundary.** Lab product evidence. Composes already-landed `.ig` builtins into a view; no
> language/renderer/server change, **no canon claim.** A view-layer proof, not a new feature.

---

## Headline

`.ig` app code now renders a **tiny money/report view with exact decimal cells and aligned columns**, using
only the formatting surface landed in P2/P3 plus the existing TodoView helpers:

```text
amount : Decimal[2] = decimal(1250, 2)            -- minor units (cents)
to_text(amount)                                   -- "12.50"  (exact, trailing zeroes preserved)
pad_left(to_text(amount), 8, " ")                 -- "   12.50"  (right-aligned, 8-wide column)
concat(label, cell) -> MakeLabel -> FormView -> RenderView -> escaped text/html
```

No local formatter, no Float, no currency/locale/grouping, no renderer schema change. The renderer still owns
escaping (a `<script>` in a label is neutralized).

## App route added (fixture)

Appended to `server/igniter-web/tests/fixtures/typed_html/typed_html.ig` (the smallest place — it already
holds `MakeLabel`/`FormView`/`RenderView`):

```text
type LineItem { label : String  amount : Decimal[2] }

MakeLineItem(label, cents)  -- amt : Decimal[2] = decimal(cents, 2); item = { label, amount: amt }
MoneyRow(item)              -- cell = pad_left(to_text(item.amount), 8, " "); line = concat(item.label, cell)
                            --   -> MakeLabel(line) : HtmlNode
MoneyReportHtml(req)        -- items = [Coffee <script> 1250, Books 12345, Gift 500]
                            --   body = map(items, it -> MoneyRow(it)); FormView("Report", body); RenderView 200
```

A `Decimal[2]` is built from **minor units** (`decimal(cents, 2)`) so the amount is a real `Decimal`, not a
String — which is what makes `to_text` the *exact* renderer (not stringly concatenation). Money arriving from a
host READ would cross as a String (typed Decimal projection is deferred, P2/P3), so the report authors the
Decimals in `.ig`.

## Rendered strings proven

| Authored | `to_text` | `pad_left(…, 8, " ")` | In HTML (label) |
| --- | --- | --- | --- |
| `decimal(1250, 2)` | `12.50` | `   12.50` (3 spaces) | `Coffee &lt;script&gt;   12.50` |
| `decimal(12345, 2)` | `123.45` | `  123.45` (2 spaces) | `Books  123.45` |
| `decimal(500, 2)` | `5.00` | `    5.00` (4 spaces) | `Gift    5.00` |

The test asserts the **exact** padded substrings (`"   12.50"`, `"  123.45"`, `"    5.00"`), which proves both
`to_text` exactness (incl. preserved trailing zeroes, `5.00`) and `pad_left` alignment in one shot. Escaping:
`Coffee &lt;script&gt;` present, raw `<script>` absent.

## Closed surfaces — confirmed stayed closed

- **No Float** in the app proof (only `Integer`→`decimal`→`Decimal[2]`→`to_text`).
- **No currency symbols / locale / thousands grouping** — the cells are bare decimal text.
- **No renderer schema change / no new ViewArtifact node kind** — reuses the flat `label` node + `FormView`.
- **No server/runner/database change** — a pure `RenderView` route, dispatched directly (no read host).
- **No broad report engine** — three authored line items + `map`, nothing more.
- **No local formatter helper** — `to_text`/`pad_left` are the stdlib surface; `MoneyRow` only composes them.

## Tests / counts

`server/igniter-web/tests/typed_html_tests.rs` — **+1** test `money_report_renders_exact_decimal_cells`
(`--features machine`): dispatches `MoneyReportHtml` (pure `RenderView`, no read host), asserts content-type
`text/html`, the three exact money texts, the three exact padded cells, and renderer-owned escaping.

**Regression (green):** `typed_html_tests` now **7** (P18 ×4, P19 ×2, P20 ×1); full `igniter-web
--features machine` green (26 ok-blocks). **`igniter-render-html` is UNTOUCHED** — no renderer source change;
its suite stays green (3 + 12, confirmed unchanged this session). `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test typed_html_tests   # 7 passed
cargo test --features machine                           # full suite green
```

## Files changed (test-only — zero production code)

| File | Change |
| --- | --- |
| `tests/fixtures/typed_html/typed_html.ig` | `+ type LineItem`, `MakeLineItem`, `MoneyRow`, `MoneyReportHtml`. |
| `tests/typed_html_tests.rs` | `+ load_app_money` + `money_report_renders_exact_decimal_cells`. |

## Reporting

- **Route/contract added:** `MoneyReportHtml` (+ `MakeLineItem`, `MoneyRow`, `type LineItem`) in the
  `typed_html` fixture.
- **Rendered strings proven:** `12.50` / `123.45` / `5.00` (exact, trailing zeroes), right-aligned to width 8
  (`   12.50` / `  123.45` / `    5.00`), label escaped (`Coffee &lt;script&gt;`), no raw markup.
- **Commands/counts:** `typed_html_tests` 7; full igniter-web `--features machine` green; render-html untouched
  + green; diff clean.
- **Float / currency / locale / report-engine surfaces:** all stayed closed (confirmed above).
- **Next product slice:** a host-Decimal lane (typed `Decimal` projection from a read, the P2/P3 deferred
  `value.rs:82-91` bridge) would let money come *from the DB* as `Decimal` rather than authored — the natural
  step toward a DB-backed report. Until then, presentation niceties (currency symbol, a totals row via Decimal
  addition) compose in `.ig`/view-layer, not as new primitives.
