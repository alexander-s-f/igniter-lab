# LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23

Status: CLOSED (2026-06-26) — exact typed `Decimal[N]` row crossing implemented (host `Decimal{scale}` kind → `{value,scale}` → `Value::Decimal`); no Float path
Route: standard / data projection implementation
Skill: idd-agent-protocol

## Goal

Implement exact typed Decimal row crossing for `ReadThen`.

Today Postgres `numeric` values are intentionally decoded as exact strings
(`DecimalString`) and materialized as `.ig String`. This card adds the missing
typed projection path so a host-declared decimal field can cross as `.ig`
`Decimal[N]`, fail closed on scale drift, and render through existing
`to_text(Decimal)` without Float or app-local parsing.

## Current Authority

Read first:

- `lab-docs/lang/lab-todoapp-view-db-money-report-readiness-p22-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `server/igniter-web/src/read_materialize.rs`
- `server/igniter-web/src/read_continuation.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/tests/typed_readthen_tests.rs`
- `server/igniter-web/tests/typed_row_crossing_tests.rs`
- `server/igniter-web/tests/typed_html_tests.rs`
- `lang/igniter-vm/src/value.rs` for the existing `{ value, scale } -> Value::Decimal` landing pad
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`

Live source wins. If Decimal crossing already landed, do not reimplement; add
the missing proof/doc only.

## Design Contract

Add a host/read policy way to declare that a decimal string should materialize
as a Decimal of a fixed scale.

Suggested shape, adjust to the local policy style:

```rust
PostgresReadValueKind::Decimal { scale: i64 }
```

or an equivalent explicit kind. Do not overload plain `DecimalString`; keep the
display-only String path available.

Materialization:

```text
"12.50" + Decimal{scale:2} -> JSON object { "value": 1250, "scale": 2 }
from_json -> Value::Decimal { value: 1250, scale: 2 }
```

Rules:

- parse only canonical finite decimal strings;
- preserve trailing zeroes via the declared scale;
- fail if the input has more fractional digits than the declared scale unless
  the local policy explicitly chooses exact zero-padding only;
- fail on exponent, signs/empty oddities, NaN/Inf, or overflow;
- no Float path;
- app `Decimal[N]` scale must match host scale exactly; mismatch is
  `ProjectionSchemaDrift` before adapter execution if detectable before read,
  otherwise before continuation dispatch.

## Closed Surfaces

- No Float money.
- No automatic conversion of every `DecimalString` to Decimal.
- No locale/currency/grouping.
- No SQL/schema migration.
- No broad decoder framework.
- No arithmetic changes in VM; Decimal arithmetic already exists.
- No product Todo route changes unless a tiny fixture is needed for proof.
- No canon claim.

## Acceptance

- [x] Host read policy can declare a Decimal field with scale. — `PostgresReadValueKind::Decimal { scale: u32 }` via `allow_source_typed`
- [x] Materializer emits a shape the VM turns into `Value::Decimal`. — `{value, scale}` (parsed); `from_json` lands it
- [x] Continuation field recovery recognizes `Decimal[N]`. — `app_field_type` "Decimal" → `AppFieldType::Decimal(scale)` (scale from `params[0]`)
- [x] Reconciler accepts host scale == app scale. — `(Decimal{scale}, Decimal(app)) => scale == app`
- [x] Reconciler rejects scale mismatch with `ProjectionSchemaDrift`. — `scale_drift_is_rejected_by_reconciler` (host{3} vs app[2])
- [x] Fake read crosses `"12.50"`/`"0.05"`/`"1200.00"` into `Decimal[2]`. — `numeric_strings_cross_as_exact_decimal_and_sum` (→ 1250/5/120000 @2)
- [x] `to_text(amount)` renders exact. — joined contains "12.50"/"0.05"/"1200.00"
- [x] Fold/sum exact (real Decimal not String). — total_text == "1212.55"
- [x] Bad decimal strings fail closed before continuation. — `bad_decimal_strings_fail_closed`
- [x] Existing Text/Integer/Bool typed crossings green. — typed_row_crossing 6, typed_readthen 4
- [x] Existing P20/P21 HTML tests green. — typed_html 7, todo_postgres_html 9
- [x] `typed_readthen_tests` / `typed_row_crossing_tests` / `typed_html_tests` pass. — all green
- [x] `cargo test --features machine` in `server/igniter-web` — **P23-owned suites + igniter-machine (56) green; 2 unrelated failures ISOLATED with evidence** (P50 typed-list read-host wiring gap `typed_read_unconfigured` + a parallel doc-pin test); task chip filed.
- [x] Implemented surface docs / follow-up card named. — proof doc + next card `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-P24`
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Kind/policy:** `PostgresReadValueKind::Decimal { scale: u32 }` (data variant, opt-in per field; display-only
`DecimalString` kept distinct). Real adapter (`postgres_real.rs`) treats it like `DecimalString` (`::text` +
string decode).

**Parse/scale (`read_materialize::parse_decimal`):** canonical finite `[-]?digits[.digits]` only — reject
exponent/`+`/whitespace/NaN/Inf/empty/multi-dot; fewer frac digits zero-pad, MORE fail (no truncation);
i64-bounded; rounded-zero unsigned; output `{value, scale}` → VM `from_json` → `Value::Decimal`. **No f64, no
in-`.ig` parser.**

**Files:** machine `postgres_read.rs` (+variant) + `postgres_real.rs` (2 arms); igniter-web `read_materialize.rs`
(parse + `AppFieldType::Decimal` + materialize reshape + scale-matching `kind_assignable`),
`read_continuation.rs` (`app_field_type` Decimal branch), `read_dispatch.rs` (Debug derive); new fixture +
`decimal_crossing_tests` (4). Proof doc `lab-docs/lang/lab-igniter-data-projection-decimal-crossing-p23-v0.md`.

**Tests:** decimal_crossing **4** + read_materialize unit **8**; typed_row_crossing 6 / typed_readthen 4 /
typed_html 7 / boot_diagnostic 9 / todo_postgres_html 9 green; full **igniter-machine 56 ok** (default +
`--features postgres` compile). `git diff --check` clean.

**Isolated unrelated failures (evidence in proof doc §"Isolated"):** in-flight P50 typed-list migration left
two read-host sites without `.with_read_policy` → `typed_read_unconfigured` 500 (`igweb_serve_machine_mode_tests`),
+ a parallel doc-pin test churn. NOT P23 — the Todo example has no Decimal field, so no Decimal path runs there;
my non-Decimal changes are behavior-preserving. Task chip filed for the P50 owner.

**No Float / no app-local parser:** confirmed.

**Next product card:** `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-P24` — DB-backed money report over a real `Decimal[2]`
column (P20 render sourced from a typed read), after the P50 typed-list read-host wiring lands.

## Reporting

Close with:

- exact kind/policy shape chosen;
- exact parse/scale rules;
- exact tests and counts;
- confirmation no Float path and no app-local decimal string parser;
- next product card for DB money report if not implemented here.

