# lab-todoapp-view-db-money-report-readiness-p22-v0

Card: `LAB-TODOAPP-VIEW-DB-MONEY-REPORT-READINESS-P22`
Route: standard / data-projection + product-view readiness · Skill: idd-agent-protocol
Status: readiness packet (design only — no implementation; no canon claim)
Date: 2026-06-26
Builds on: P20 authored-Decimal money report · P18 typed-rows→HTML · data-projection P1-P3/P6/P7.

> **Authority boundary.** Design only — no code, no Float money, no SQL/migration/renderer change, no
> currency/locale/grouping, no decoder framework. Cited against live source. The crossing question is decided;
> the next implementation card is named.

---

## Headline

**Typed `Decimal[N]` row-crossing does NOT exist today** — a host `numeric` column decodes to
`PostgresReadValueKind::DecimalString`, which the live materializer crosses as a `Value::String`
(`read_materialize.rs:95`), and the reconciler knows only `Text/Integer/Bool` app field types
(`read_continuation.rs:205-207`). So a `<AppRow> { amount : Decimal[2] }` field cannot reconcile today.

**Two exact paths already work; one principled path is the next card:**
- **v0 recommended — C (Integer minor units):** store/expose money as an **Integer cents** column; the app
  builds `decimal(cents, 2)` (literal scale) — *exactly the P20 pattern*, now sourced from a DB Integer column
  (Integer crossing proven by P18 `rank`). **Exact, supports arithmetic, zero new host code.**
- **v0 fallback — A (String display-only):** for an existing `numeric(p,s)` column you cannot reshape — cross
  as `String`, **display only** (`pad_left`/`concat`). **Tradeoff (named): no in-`.ig` arithmetic/sum/compare**,
  and **no in-`.ig` decimal parsing** (the one-off-decoder anti-pattern the card guards against).
- **Next implementation card — B (typed Decimal projection):** a host `Decimal{scale}` read-kind that turns
  the adapter's DecimalString into the `{value, scale}` shape the VM's `from_json` already materializes to
  `Value::Decimal` (`value.rs:82-97`, the live-but-unused landing pad), + a `Decimal[N]` reconciler case. This
  makes `numeric(p,s)` columns cross as exact `Decimal[N]` for full money arithmetic. **Reject D (full defer)**
  — C already gives a working exact path.

---

## 1. Current crossing surface (Q1–Q4, verified live)

| DB value | adapter (`postgres_read`) | host kind | materialize (`value_matches_kind`) | `from_json` → VM | app field type **today** |
| --- | --- | --- | --- | --- | --- |
| text | — | `Text` | requires JSON string | `Value::String` | `String` / `Text` |
| `integer` (e.g. cents `1250`) | i64 | `Integer` | requires i64 number (`read_materialize.rs:97`) | `Value::Integer` | `Integer` → app `decimal(1250,2)` → **`Decimal[2]`** |
| `boolean` | bool | `Boolean` | requires JSON bool | `Value::Bool` | `Bool` |
| **`numeric(10,2)`** (`"12.50"`) | **`DecimalString`** — exact digits as a String, *never f64* (`postgres_read.rs:309-310`) | `DecimalString` | **requires JSON string** (`read_materialize.rs:95`) | **`Value::String("12.50")`** | **`String`** (display-only) |
| date/time | string | `Timestamp` | requires JSON string | `Value::String` | `String` / `Text` |
| `{ "value":1250, "scale":2 }` *(no host kind emits this today)* | — | — | — | **`Value::Decimal{1250,2}`** (`value.rs:82-97`, live landing pad) | **`Decimal[2]`** *(B target — not wired)* |

**Q1 — typed scalar kinds `ReadThen` materializes today:** `Text/DecimalString/Timestamp → String`,
`Integer → Integer`, `Boolean → Bool`, `Json → Record/Array`, `Array → Array`
(`read_materialize.rs:91-98`). **DecimalString crosses as a String, not a Decimal.**

**Q2 — does typed row crossing support `.ig` `Decimal[N]` fields today? NO.** The materializer crosses a
decimal column as a String (`:95`), and the reconciler's app-field-type map is `Text/Integer/Bool` only
(`read_continuation.rs:205-207`) — there is **no `Decimal` case**, so a `Decimal[N]` field fails reconciliation
(it cannot be the assignability target of `DecimalString`). The P3 matrix already said this:
`DecimalString → String|Text`, "typed `Decimal[s]` deferred."

**Q3 — adapter for decimal/numeric:** `DecimalString` — "arbitrary-precision `numeric` kept as a String —
NEVER a lossy `f64`" (`postgres_read.rs:309-310`). The exact digits are preserved on the wire.

**Q4 — reusable VM Decimal crossing? YES (partial, unused by reads).** `from_json` materializes a JSON object
carrying numeric `value` + `scale` keys directly into `Value::Decimal{value, scale}`
(`lang/igniter-vm/src/value.rs:82-97`). This is the **landing pad** B uses — it exists and is live; the read
path simply never emits the `{value, scale}` shape for a decimal column (it crosses the bare string).

---

## 2. Alternatives (Q5) — four compared

| # | Crossing | Exact? | Arithmetic in `.ig`? | Works today? | New host code | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **A** | DB `numeric` → **String**, display-only | yes (digits preserved) | **no** (it's a String) | **yes** | none | **Fallback.** Only for a `numeric` column you can't reshape, and only for *display*. Name the no-arithmetic tradeoff; do **not** parse it in `.ig`. |
| **C** | DB **Integer cents** → app `decimal(cents, 2)` (literal scale) | **yes** | **yes** (real `Decimal`) | **yes** — composition of P18 Integer crossing + P20 authored Decimal | none | **Recommended v0.** Matches P20's `MakeLineItem(cents)` exactly; the only delta is `cents` comes from a DB Integer column. Money-as-minor-units is a standard convention. |
| **B** | DB `numeric(p,s)` → host `{value,scale}` → **`Decimal[N]`** | **yes** | **yes** | **no** | host `Decimal{scale}` read-kind + materializer emit + reconciler case | **Next implementation card.** The principled, general answer for *existing* `numeric` columns; reuses the live `from_json` landing pad. |
| **D** | Defer DB-money entirely until B | — | — | — | — | **Reject.** C already provides a working exact path; no need to block the product on B. |

**Why not app-local string parsing of the `DecimalString`:** there is **no in-`.ig` decimal parser** (and
building one would be a one-off money decoder — the exact anti-pattern this card exists to prevent). Money that
must be exact crosses as a real number (Integer cents → C, or `Decimal[N]` → B), never as a string the app
re-parses.

---

## 3. Recommendation

- **Use C (Integer minor units) as the v0 exact path.** Where the money column is — or can be — an Integer
  cents/minor-units column, cross it as `Integer` and build `decimal(cents, 2)` in `.ig` (literal scale,
  per the P4 amendment / P20). Exact, supports sum/compare, renders via the live `to_text(Decimal)` +
  `pad_left`. **No new host code** — it is the composition of two proven halves.
- **Use A (String, display-only) only for an unreshapeable `numeric` column,** and **only to display** — state
  the tradeoff (no `.ig` arithmetic) in the view; never parse the string.
- **Ship B (typed Decimal projection) as the next implementation card** to make `numeric(p,s)` columns cross as
  exact `Decimal[N]` (full arithmetic, no schema change required of the operator).

---

## 4. Safety rules for money (Q6)

| Rule | How it holds |
| --- | --- |
| **No Float money** | DecimalString explicitly avoids `f64` (`postgres_read.rs:310`); Integer-cents (C) is exact; `Decimal[N]` (B) is exact. Money never crosses as Float. |
| **No locale/currency/grouping (v0)** | `to_text(Decimal)` is plain base-10, no grouping/symbols (P2). |
| **Preserve scale / trailing zeroes** | `to_text(Decimal)` preserves exactly `scale` digits (`"12.00"`, not `"12"`) — P2. C uses a literal scale; B reconciles the host scale against the app `Decimal[N]` scale. |
| **Fail closed on schema drift** | Reconciliation → `ProjectionSchemaDrift` before any read (live, `read_continuation.rs`; proven by the `done`-as-Text drift test). For B: a host scale ≠ app `Decimal[N]` scale must also fail closed. |
| **Exact, never lossy** | Integer cents and `Decimal[N]` are exact; the String path (A) preserves digits but is display-only (no lossy parse). |

---

## 5. Relation to the P20 authored-Decimal proof

P20 proved the **render** half end-to-end over *authored* values: `decimal(cents, 2)` → `to_text` (exact,
trailing zeroes) → `pad_left` (right-aligned column) → `HtmlNode` → `RenderView`. P22's recommended **C** is
*that exact pattern with `cents` sourced from a DB Integer column* — and Integer row-crossing is already
proven (P18 `rank : Integer`). So C is **P20 + proven Integer crossing, with no new machinery**; the only thing
P20 leaves open for *DB* money is the `numeric`-column case, which is B.

---

## 6. Next implementation card — `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23`

**Goal:** make a host `numeric(p,s)` column cross as an exact `.ig` `Decimal[N]`.

**Shape (DB-free, fake adapter — mirrors the P18/typed_html harness):**
- Host: a `PostgresReadValueKind::Decimal { scale }` (or a `materialize_as_decimal` flag on the typed read
  policy). `materialize_rows` emits `{ "value": <i64 digits>, "scale": <s> }` for such a field (parsing the
  adapter's `DecimalString` "12.50" → value 1250, scale 2). The VM's `from_json` (`value.rs:82-97`) then yields
  `Value::Decimal{1250,2}` — **no VM change needed.**
- Reconciler: add an `AppFieldType::Decimal { scale }` case (`read_continuation.rs:205-207`), assignable from
  the host `Decimal{scale}` kind **iff the scales match** (static `N`, per the P4 amendment); scale mismatch →
  `ProjectionSchemaDrift`.
- App fixture: `type LineRow { label : String  amount : Decimal[2] }`, continuation
  `input rows : Collection[LineRow]`, then the P20 render (`to_text(r.amount)` + `pad_left`).

**Acceptance tests:**
- a fake `numeric`-kind column "12.50"/"0.05"/"1200.00" crosses → `r.amount : Decimal[2]` and
  `to_text(r.amount)` renders `"12.50"`/`"0.05"`/`"1200.00"` (exact, trailing zeroes);
- **arithmetic:** `fold(rows, decimal(0,2), (acc, r) -> acc + r.amount)` sums exactly (proves it's a real
  Decimal, not a String);
- **scale drift fails closed:** host `Decimal{scale:2}` vs app `Decimal[3]` → `ProjectionSchemaDrift`, query
  count 0;
- **no Float path:** a non-decimal/Float value for the field is refused by `value_matches_kind`;
- `Integer`/`Text`/`Bool` crossing + existing typed_html tests remain green; `git diff --check` clean.

---

## Reporting

- **Current crossing table:** §1 — Decimal columns cross as **String** today; Integer/Text/Bool are the
  reconcilable scalar app types; the `from_json` `{value,scale}` → `Value::Decimal` landing pad is live but
  unused by reads.
- **Recommendation:** **C (Integer minor units → `decimal(cents, 2)`)** as the v0 exact path (zero new code,
  the P20 pattern over a DB Integer column); **A (String display-only)** for unreshapeable `numeric` columns
  with the no-arithmetic tradeoff named; **reject D and app-local string parsing.**
- **Next implementation card:** `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23` (host `Decimal{scale}`
  read-kind → `{value,scale}` → `Value::Decimal`, + reconciler case, scale-drift fail-closed) with the §6
  test matrix.
