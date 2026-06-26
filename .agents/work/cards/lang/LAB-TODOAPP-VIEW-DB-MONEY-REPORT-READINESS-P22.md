# LAB-TODOAPP-VIEW-DB-MONEY-REPORT-READINESS-P22

Status: CLOSED (readiness packet delivered 2026-06-26)
Route: standard / data projection + product view readiness
Skill: idd-agent-protocol

## Closing report (2026-06-26)

Packet: `lab-docs/lang/lab-todoapp-view-db-money-report-readiness-p22-v0.md`.

**Current crossing (verified live):** typed `Decimal[N]` row-crossing is **NOT implemented.** A `numeric`
column → `PostgresReadValueKind::DecimalString` (exact digits as String, never f64, `postgres_read.rs:309`),
which the materializer crosses as a `Value::String` (`read_materialize.rs:95`); the reconciler's app-field-type
map is `Text/Integer/Bool` only (`read_continuation.rs:205-207`) — **no `Decimal` case**, so a `Decimal[N]`
field can't reconcile. The `from_json` `{value,scale}` → `Value::Decimal` landing pad is **live but unused**
(`value.rs:82-97`).

**Recommendation (4 alternatives compared):**
- **v0 = C (Integer minor units):** money as a DB **Integer cents** column → app `decimal(cents, 2)` (literal
  scale). **Exact, supports arithmetic, zero new host code** — the P20 pattern with `cents` from a DB Integer
  column (Integer crossing proven by P18 `rank`). C = P20 + proven Integer crossing.
- **A (String display-only):** for an unreshapeable `numeric` column — cross as String, **display only**;
  tradeoff named (no `.ig` arithmetic); **no in-`.ig` decimal parsing** (the one-off-decoder anti-pattern).
- **Reject D** (full defer — C already works) and **app-local string parsing**.

**Next implementation card — `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23`:** host `Decimal{scale}`
read-kind that parses DecimalString "12.50" → `{value:1250, scale:2}` (the VM `from_json` landing pad
materializes `Value::Decimal` — no VM change) + a reconciler `Decimal[N]` case (scale must match; mismatch →
`ProjectionSchemaDrift`). Makes `numeric(p,s)` cross as exact `Decimal[N]`. Test matrix in packet §6
(cross+render exact w/ trailing zeroes; `fold` sum proves real Decimal; scale-drift fail-closed; no-Float;
regression).

**Money safety (Q6):** no Float money; no locale/currency/grouping (v0); preserve scale/trailing zeroes
(`to_text(Decimal)`); fail-closed on schema drift (`ProjectionSchemaDrift`, live); exact never lossy.

**Relation to P20:** P20 proved the render half over *authored* `decimal(cents,2)`; C is that exact pattern
with `cents` from a DB Integer column; B (P23) extends it to `numeric` columns.

**Boundary honored.** Design only — no code, no Float money, no SQL/migration/renderer/locale change.
`git diff --check` clean; my only change is the packet doc.

> **Scope note:** the team is concurrently extending `typed_html.ig` (P20 money report); I added no fixture
> (avoids collision; C is the composition of already-proven P18+P20 halves, no new proof needed).

## Goal

Decide how a DB-backed money/report view should cross data into `.ig`.

P20 proved authored `Decimal[2]` values render cleanly:

```ig
to_text(decimal(1250, 2))        -- "12.50"
pad_left(to_text(amount), 8, " ")
```

The next real product question is different:

> If money comes from Postgres rows, does it cross as `Decimal`, `String`,
> `{ value, scale }`, or something else?

This card should prevent agents from inventing one-off money decoders in Todo
HTML. Produce the boundary decision and the next implementation card.

## Current Authority

Read first:

- `.agents/work/cards/lang/LAB-TODOAPP-VIEW-MONEY-REPORT-P20.md`
- `lab-docs/lang/lab-todoapp-view-money-report-p20-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/read_materialize.rs`
- `server/igniter-web/src/read_continuation.rs`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/src/value.rs`
- `lab-docs/lang/current-waves-index.md`

Live code wins. If Decimal typed-row crossing already exists, prove it. If it
does not, do not route around it with app-local string parsing without naming
the tradeoff.

## Questions To Answer

1. What typed scalar kinds can `ReadThen` materialize today?
2. Does typed row crossing support `.ig` `Decimal[N]` fields today?
3. What does the machine Postgres read adapter return for decimal/numeric-like
   DB values today?
4. Is there already a VM/value representation for Decimal crossing that can be
   reused?
5. Which v0 is best for a DB-backed money report?
   - A: DB stores money as text and app treats it as String (display-only);
   - B: host materializes `{ value, scale }` into `.ig Decimal[N]`;
   - C: app receives `{ value, scale }` record and constructs Decimal;
   - D: defer DB-money report until typed Decimal projection is implemented.
6. What are the exact safety rules for money?
   - no Float money;
   - no locale/currency/grouping in v0;
   - preserve scale/trailing zeroes;
   - fail closed on schema drift.

## Closed Surfaces

- No implementation unless the answer is already fully supported and only a
  tiny fixture proof is needed.
- No Float money.
- No SQL/raw query changes.
- No DB migrations.
- No renderer changes.
- No currency/locale/grouping.
- No broad decoder framework in this card.

## Acceptance

- [x] The packet states the current live typed-row scalar surface.
- [x] The packet states whether Decimal row crossing is implemented or not.
- [x] At least four alternatives are compared.
- [x] Recommendation names one concrete next implementation card.
- [x] The recommendation preserves exact money semantics and fail-closed drift.
- [x] The packet states how this relates to P20 authored Decimal proof.
- [x] No production code changes unless justified as a tiny proof.
- [x] `git diff --check` clean.

## Suggested Output

Create:

```text
lab-docs/lang/lab-todoapp-view-db-money-report-readiness-p22-v0.md
```

Close the card with:

- current crossing table;
- recommendation;
- next implementation card and tests.

