# lab-igniter-data-projection-decimal-crossing-p23-v0

Card: `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23`
Route: standard / data projection implementation · Skill: idd-agent-protocol
Status: implemented (typed `Decimal[N]` row crossing) · no Float path · no canon claim
Date: 2026-06-26
Builds on: P22 money-report readiness (chose path B) · P6/P7 typed crossing · P2 `to_text(Decimal)` · the live `from_json` `{value,scale}` landing pad

> **Authority boundary.** Lab data-projection surface (igniter-lab `lang/` + `server/igniter-web`). One new
> host read-kind + a host-side parse; no Float money, no in-`.ig` decimal parser, no SQL/schema change, no VM
> arithmetic change, **no canon claim.**

---

## Headline

A host `numeric(p,s)` column now crosses into an `.ig` continuation as an **exact typed `Decimal[N]`** (not a
display String). The adapter still reads the **lossless decimal digit string** (never `f64`); the host
materializer **parses** it against the host-declared scale into the `{ value, scale }` shape the VM's
`from_json` already turns into `Value::Decimal`. The continuation then does **real Decimal work** —
`to_text(r.amount)` (exact, trailing zeroes) and a `fold`-sum — proving the values are real Decimals, not
Strings. A host scale ≠ app `Decimal[N]` scale **fails closed** as `ProjectionSchemaDrift`; a Float or a
non-canonical string is refused **before continuation dispatch**. **No VM change** — the landing pad was
already live (P22 §4); only the host wiring was missing.

---

## Kind / policy shape chosen

A new **data-carrying** host read-kind, distinct from the display-only `DecimalString`:

```rust
// runtime/igniter-machine/src/postgres_read.rs
pub enum PostgresReadValueKind {
    …,
    DecimalString,          // display-only → crosses as `.ig String` (unchanged)
    Decimal { scale: u32 }, // P23: exact → crosses as `.ig Decimal[scale]`
    Array,
}
```

Declared per field via the existing `allow_source_typed("lines", &[("amount", Decimal { scale: 2 })])`. The
operator **opts in per column** — `DecimalString` stays available for a `numeric` column you only display.
The real adapter (`postgres_real.rs`) treats `Decimal { .. }` exactly like `DecimalString` (cast `::text`,
decode the exact digit String); only the host kind — and thus the materializer's reshape — differs.

## Parse / scale rules (host-side, `read_materialize::parse_decimal`)

Canonical finite decimal only — `[-]?digits[.digits]`:

- **canonical only:** reject exponent (`1e2`), `+`, whitespace, NaN/Inf, empty, `.`-oddities, multiple dots.
  The integer part must be present and all-digits; the fractional part all-digits.
- **scale:** fewer fractional digits than `scale` are **zero-padded** (`"12.5"`@2 → `1250`); **more**
  fractional digits than `scale` **fail** (no silent truncation/rounding). `"12"`@2 → `1200`; `"12."`@2 →
  `1200` (no fractional digits).
- **overflow:** the scaled integer must fit `i64`, else fail.
- **sign:** a leading `-` is kept; a rounded/zero magnitude is **unsigned** (`-0` → `0`).
- output: `{ "value": <i64>, "scale": <u32> }` — the shape `from_json` (`value.rs:82-99`) lands as
  `Value::Decimal { value, scale }`. **No `f64` anywhere; `.ig` never parses a money string.**

| input "s" @ scale 2 | value |
| --- | --- |
| `"12.50"` | `1250` |
| `"0.05"` | `5` |
| `"1200.00"` | `120000` |
| `"12.5"` | `1250` (zero-padded) |
| `"12.500"` | **error** (3 frac digits > scale 2) |
| `"1e2"` / `"abc"` / `"12.5.0"` | **error** (not canonical) |

## Reconciliation (scale must match)

`AppFieldType::Decimal(u32)` recovered from the compiled type_env: a `Decimal[2]` field's type_ir is
`{name:"Decimal", params:["2"]}` (the scale is the first param, a **bare string** — `app_field_type` parses
`params[0]` as a string-or-`{name}`). The assignability matrix gains:

```text
host Decimal{scale} ⇄ app Decimal(app_scale)   iff scale == app_scale
```

A scale mismatch (host `Decimal{3}` vs app `Decimal[2]`), or a display-only `DecimalString` against a typed
`Decimal[N]`, is **not assignable** → `ProjectionSchemaDrift` (the P7 first-dispatch reconciler, before any
read). Matched scales reconcile clean.

## Materialization gate (fail-closed, before continuation)

`value_matches_kind(Decimal{..})` requires a JSON **string** (the wire) — a Float/number/bool/object is the
wrong kind → `SchemaMismatch`. The string is then parsed in `materialize_rows`; a non-canonical/over-scale
string → `SchemaMismatch`. Both surface **before** the continuation is dispatched (no partial `.ig` response).

## Files changed

| File | Change |
| --- | --- |
| `runtime/igniter-machine/src/postgres_read.rs` | `PostgresReadValueKind::Decimal { scale: u32 }` (data variant). |
| `runtime/igniter-machine/src/postgres_real.rs` | `Decimal { .. }` arms in `projection_expr`/`decode_value` (mirror `DecimalString`: `::text` + string decode). |
| `server/igniter-web/src/read_materialize.rs` | `parse_decimal`; `AppFieldType::Decimal(u32)`; `value_matches_kind` + `materialize_rows` reshape; `kind_assignable` scale-matching (rewritten `matches!`→`match`). |
| `server/igniter-web/src/read_continuation.rs` | `app_field_type` `"Decimal"` branch (scale from `params[0]`). |
| `server/igniter-web/src/read_dispatch.rs` | `#[derive(Debug)]` on `TypedReadResult` (test ergonomics). |
| `tests/fixtures/decimal_crossing/decimal_crossing.ig` *(new)* | `LineRow { label, amount : Decimal[2] }`, `DecimalProbe` (to_text + fold-sum). |
| `tests/decimal_crossing_tests.rs` *(new, 4)* | the crossing + drift + no-Float + bad-strings. |

## Tests / counts

`server/igniter-web/tests/decimal_crossing_tests.rs` (**4**, `--features machine`, DB-free):
- `numeric_strings_cross_as_exact_decimal_and_sum` — `"12.50"/"0.05"/"1200.00"` reshape to
  `{value:1250/5/120000, scale:2}`; the continuation renders each exactly via `to_text` AND the `fold`-sum is
  `1212.55` (proves real Decimal arithmetic, not String concat).
- `scale_drift_is_rejected_by_reconciler` — `LineRow.amount` recovers as `Decimal(2)`; host `Decimal{2}`
  reconciles, host `Decimal{3}` → `ProjectionSchemaDrift`.
- `float_value_for_decimal_field_is_refused` — a JSON Float for the field → `SchemaMismatch` (no Float path).
- `bad_decimal_strings_fail_closed` — `"12.500"`/`"1e2"`/`"abc"` → `SchemaMismatch`; `"12."` is valid (→ 1200).

Plus `read_materialize` in-module unit tests (8) green.

**Regression (green, mine):** `typed_row_crossing_tests` (6), `typed_readthen_tests` (4), `typed_html_tests`
(7), `boot_diagnostic_tests` (9 — `Float` still un-projectable, Decimal now is), `todo_postgres_html_tests`
(9); full **`igniter-machine`** suite (56 ok-blocks — the new data variant compiles under default AND
`--features postgres`, all matches handled). `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test decimal_crossing_tests   # 4 passed
cargo test --features machine --test typed_row_crossing_tests # 6 passed
cargo test --features machine --test typed_html_tests         # 7 passed
# from runtime/igniter-machine
cargo test ; cargo check --features postgres                  # green
```

## Isolated unrelated failures (NOT P23)

A full `server/igniter-web cargo test --features machine` shows failures that **flap between runs** and are
**caused by the in-flight P50 (typed-list-envelope) parallel work**, not P23 — confirmed with evidence:

- `igweb_serve_machine_mode_tests::readthen_p23::*` → HTTP **500 `{"error":{"code":"typed_read_unconfigured"}}`**.
  P50 migrated the example's `AccountTodoIndexFromRows` from legacy `rows_json` to a **typed** `RespondJson`
  continuation, but the test helper `make_read_host` (`tests/igweb_serve_machine_mode_tests.rs:319`) and the
  `igweb-serve` non-postgres fallback build the `StagedReadHost` **without** `.with_read_policy(...)`, so the
  typed path cannot build a spec → 500. A task chip was filed for the P50 owner.
- `examples_doc_pins_current_api_contract_without_inline_secrets` → a markdown-pin test churning with the
  parallel API.md/EXAMPLES.md doc edits.

**Why these are not P23:** the Todo example has **no Decimal field** (all Text), so not one of my Decimal code
paths executes for those routes; my non-Decimal changes are behavior-preserving (`materialize_rows` `_ =>
v.clone()`, `kind_assignable` rewritten identically, `value_matches_kind`/`app_field_type` add only a Decimal
branch). All P23-owned suites + the full igniter-machine suite are green.

## Reporting

- **Kind/policy:** `PostgresReadValueKind::Decimal { scale: u32 }`, opt-in per field via `allow_source_typed`;
  `DecimalString` (display String) kept distinct.
- **Parse/scale:** canonical finite only; fewer frac digits zero-pad, more fail; i64-bounded; `{value,scale}`
  output; no `f64`; no in-`.ig` parser.
- **Tests:** decimal_crossing 4 + read_materialize unit 8; my typed suites + full igniter-machine green;
  `git diff --check` clean.
- **No Float / no app-local parser:** confirmed (Float refused by `value_matches_kind`; the only decimal parse
  is the host `parse_decimal`).
- **Next product card:** `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-P24` — a DB-backed money report route over a real
  `Decimal[2]` column (the P20 render now sourced from a typed read), once the P50 typed-list read-host wiring
  lands. (P22 §3's path **C** — Integer cents — remains the zero-code alternative where the column can be cents.)
