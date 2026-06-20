# lab-lang-record-ergonomics-readiness-p1-v0 — optional fields, spread, partial records

**Card:** `LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` · **Delegation:** `OPUS-LANG-RECORD-ERGONOMICS-P1`
**Status:** READINESS / DESIGN (v0) — decides what record ergonomics belong in the surface-ergonomics lane
vs canon vs app-local helpers. **No implementation; no canon claim.** P0 discipline: surface sugar lowers
to existing SIR, adds no authority.

## 1. Executive summary — split the two pains; one is canon-gated, one is a clean lab slice

There are **two distinct record pains**, and the right answer differs:

1. **All-fields-required / default-field noise** (P19/P23: flat `HtmlNode`, `OOF-TY0: required field
   'options' is missing`) → wants **optional fields with defaults**. **This is CANON-GATED:**
   `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1` *explicitly defers* implementation — "P1 must not implement
   partial record omission. Route a full language PROP" — because omission has **semantic authority**
   (what an absent field means for construction/access/serialization). The lab lane must **not** jump that
   gate; v0 stays **helper contracts** (canon's own "safe app pattern remains explicit defaults").
2. **Context accumulation** (`{ ...ctx, field: v }` — copy a record and add/override one field) → wants
   **record spread**. This is **semantically clean** (pure copy+override, *no* omission question),
   **not canon-tracked**, and has **strong real-app evidence** (lead_router has **six** `CtxWith*`
   contracts that are literally hand-written spreads). → **the recommended lab surface-sugar slice.**

**Recommendation:** open **`LAB-LANG-RECORD-SPREAD-P2`** (spread, desugars to an explicit field literal —
P0-clean). **Defer optional/default fields to the canon PROP** (feed P19/P23 evidence). **Keep helper
contracts as v0** for the default-field noise.

## 2. Live record behavior (verified)

| Fact | Evidence |
|---|---|
| **every record field is required** | P23: adding `HtmlNode.options` → `OOF-TY0: required field 'options' is missing` on every node until backfilled `options: []` |
| field **order does not matter** | `parse_record_or_block` builds `fields: HashMap`; VM serializes a record as a (sorted-key) object — keyed, not positional |
| records serialize **without variant tags** | P2 view test asserts no `__arm`/`__variant` in a record root (only *variants* carry discriminants) |
| field names validated against the declared schema | typechecker `check_record_literal_shape` (missing-required → `OOF-TY0`, proven) |
| `?` optional marker **parses but is erased** | canon `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1`: Rust keeps `FieldDecl.optional`, but `build_type_shapes` drops it before validation → partial literals still rejected, both toolchains |
| helper contracts already absorb the pain | P20 `MakeLabel`/`MakeButton`/`FormView`; lead_router `CtxWith{Trade,Vendor,Zip,Mode,Slots,Bid}` (6×) |

## 3. Proposal crosswalk (Q2)

| Need | Tracking | Verdict |
|---|---|---|
| optional fields / defaults / partial literals | **`LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1/P2`** — *implementation explicitly deferred pending a full semantic PROP* | **canon-gated**; lab does NOT implement; contributes evidence |
| record literal inference | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1/2/3/P5`, `LAB-NESTED-RECORD-LITERAL-TYPING-P1` | adjacent; not the ergonomics gap |
| **record spread `{ ...base, f: v }`** | **untracked** (registry "pressure" only) | **the clean lab slice (Q7)** |
| schema evolution / migration | `PROP-017` | separate lane |

## 4. Which pain is blocking vs verbose (Q1)

**Neither is a hard block** — helper contracts cover both (P20 nodes; lead_router `CtxWith*`). Both are
**verbosity**. Repetition counts:
- default-field noise: appeared in *every* view card (P19–P23) — most repeated, but the fix is canon-gated.
- accumulation: lead_router writes **6** `CtxWith*` spread-helpers in one app + the Todo via-chain need —
  a heavily repeated pattern with a *clean, non-gated* fix (spread).

## 5. Alternatives (Q-compare)

| # | Form | Verdict |
|---|---|---|
| A | optional fields with type-level defaults (`text? : String = ""`) | **defer to canon** — gated by `LANG-OPTIONAL-FIELD-PARTIAL-RECORD`; omission = semantic authority (not surface sugar) |
| B | partial record literals (typechecker fills defaults) | same as A (needs the default/omission story canon is gating) |
| **C** | **record spread / update `{ ...ctx, f: v }`** | **RECOMMEND (lab slice)** — pure copy+override; desugars to an explicit field literal; no omission semantics; 6× lead_router evidence |
| D | app-local helper contracts only | **blessed v0** for the default-field pain (canon agrees) until the optional-field PROP lands |
| E | specialized variant nodes | reject — reintroduces `__arm`/variant serialization mismatch with the renderer |

## 6. Record spread design (the recommended slice) (Q3, Q4, Q5)

**Syntax:** `compute enriched : Ctx = { ...ctx, todo_id: todo_id }` — copy all of `ctx`'s fields, then
add/override the listed fields.

**Lowering (Q4) — pure desugar, no new SIR node:** when `ctx`'s type is known at the spread site, the
compiler **desugars** `{ ...ctx, f: v }` to an explicit field-by-field record literal
`{ a: ctx.a, b: ctx.b, …, f: v }` (each non-overridden field read from `ctx`, overrides last-wins). This
lowers to an ordinary `RecordLiteral` → the **same SIR node kind**, byte-identical to the hand-written
form. `ctx` is immutable; the result is a **new** value (no mutation, no ordering, no effect) → determinism/
replay/receipts untouched (P0). This is exactly what lead_router's `CtxWith*` contracts do by hand.

**Defaults vs Option (Q3):** spread needs **neither** — it copies *present* fields from `ctx`, so there is
no absent-field/omission question. (That question is the optional-fields PROP's, deferred.)

**Diagnostics (Q5):** an override field must be a real field of the target type → reuse
`check_record_literal_shape` (unknown override = `OOF-TY0`); a spread source whose type lacks a target
field, or a target field neither in the source nor overridden, is a **missing-required** error (same
`OOF-TY0`). No new diagnostic machinery.

## 7. Scope of help (Q6)

Record spread helps **accumulation everywhere**: lead_router/via context threading, relational `WriteIntent`
(set `correlation_id` on a base), any "copy + tweak" record. Optional/default fields (deferred) would help
**ViewArtifact `HtmlNode` + relational optional policy fields** — but that is the canon PROP's scope.

## 8. Test matrix for the spread slice (Q8)

1. **parse:** `{ ...ctx, f: v }` parses (a spread element in a record literal).
2. **typecheck:** override `f` must be a field of the target type (`OOF-TY0` on unknown); a field absent
   from both source and overrides → `OOF-TY0` missing-required.
3. **desugar/SIR parity:** `{ ...ctx, f: v }` lowers to the **same SIR** as the explicit
   `{ a: ctx.a, …, f: v }` (byte-identical; no new node kind).
4. **VM serialization stable:** a contract building a record via spread serializes byte-identically to the
   hand-written full literal (the lead_router `CtxWithTrade` shape, spread vs `call_contract`).
5. **immutability:** the source `ctx` is unchanged; the result is a distinct value.
6. existing record/relational/view fixtures stay green; `git diff --check` clean.

## 9. What stays app-local / deferred (Q9)

- **Optional/default fields:** deferred to the canon `LANG-OPTIONAL-FIELD-PARTIAL-RECORD` PROP. Lab role:
  attach P19/P23 evidence (the `OOF-TY0` backfill cost) to that PROP. **Do not implement in the lab lane.**
- **Helper contracts:** remain the blessed v0 for default-field noise (and are an acceptable spread
  alternative) until the canon PROP lands / a spread slice ships.

## 10. Smallest follow-up card (Q10)

**`LAB-LANG-RECORD-SPREAD-P2`** (implementation-proof): record spread `{ ...base, f: v }` desugaring to an
explicit field literal, with §8 tests (incl. SIR-parity + the lead_router `CtxWith*` shape rewritten with
spread). Plus a **non-code action:** route the P19/P23 default-field evidence into the canon optional-field
PROP. Spread is the one record-ergonomics change that fits the surface-sugar lane (clean desugar, no
omission authority); optional fields wait for canon.

## Non-goals

No optional-field/partial-record implementation (canon-gated); no renderer/ViewArtifact schema change; no
relational schema/migration; no user-generic type design; no new SIR node kind; no canon claim.

---

*Readiness/design only. Compiled 2026-06-20; grounded in live record behavior (`parse_record_or_block`
HashMap fields, `check_record_literal_shape`, P23 `OOF-TY0`), the canon `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1`
deferral, and lead_router's 6 `CtxWith*` spread-by-hand helpers. Optional fields = canon-gated (semantic
authority); record spread = the clean lab surface-sugar slice. No code change.*
