# Lab Governance Doc: Stdlib Coverage & Numeric Core — Proposal Readiness

**Track:** lab-stdlib-numeric-coverage-proposal-readiness-v0 (out-of-track research)
**Card:** LAB-LANGFORM-RESEARCH-P1 (doc 1 of 3)
**Category:** governance / lang
**Date:** 2026-06-10
**Route:** PROPOSAL READINESS / RESEARCH / LAB-ONLY / NO CANON PROP AUTHORED
**Status:** CLOSED — gap mapped; numeric-core proposal route recommended; nothing authored

---

## Scope note

This is a **proposal-readiness research doc**, not a canon PROP. The canon governance gate owns
PROP authoring; this maps the gap, proposes the shape, names the precondition, and recommends the
route. One of three coordinated docs (stdlib / packaging / application-form); see the umbrella card
LAB-LANGFORM-RESEARCH-P1 for the dependency ordering.

---

## 1. Headline — stdlib is ~85% done; the gap is **numeric math**, and it is the embed blocker

A full survey of canon Ch8 vs the executable VM surface (vm.rs OP_CALL) shows the stdlib is, for a
*data/contract* language, surprisingly complete: **Text** (14 Unicode-correct ops, LAB-STR-UNICODE-P2
43/43), **Option/Result** (VM has *more* than canon — `try_catch`/`propagate`/`validate`),
**Collection** (fold/map/filter/find/any/all/sum/avg/min/max/take/zip/range), **DateTime** (6/6),
and **Map** read ops (`map_get`/`map_has_key`, LAB-VM-MAP-P1) are all present and executable.

The single sharp gap was discovered empirically by **LAB-PURSUIT-P1** (the quadcopter
pursuit/evasion guidance probe): there is **no numeric math beyond `+ − × ÷`**. No `abs`, `min`,
`max`, `clamp`, `compare`, `neg`(as fn), `isqrt`, `pow`, and no `sqrt`/`sin`/`cos`/`atan` of any
kind. That probe could only be built by forcing every algorithm to be arithmetic-only (scalar
Kalman with no matrix inverse, **sqrt-free** ZEM proportional navigation `t_go = r²/(−r·v)`). It
worked — and the integer fixed-point result is arguably *good* for embedded — but it was a
constraint worked *around*, not a sufficiency.

**This is the keystone gap for any embed in robotics / games / simulation / control / signal
processing** — exactly the (mild, classic) domains the user named.

---

## 2. The gap matrix (declared Ch8 vs executable VM)

| Area | Canon Ch8 | VM executable | Verdict |
|------|-----------|---------------|---------|
| Text (`stdlib.text.*`) | 14 ops | 14 ops | ✅ complete (promotion-ready) |
| Option | 6 | 8 | ✅ complete (VM superset) |
| Result | 5 | 9 | ✅ complete (VM superset) |
| Collection | 12 | 18 | ✅ near-complete (verify `sort_by`) |
| DateTime | 6 | 6 | ✅ complete (no Date-only ops) |
| Map | get/has_key/from_pairs/empty | **get/has_key only** | ⚠️ construction ops typecheck-only, no VM |
| **Numeric** | add/sub/mul/div/neg/**compare** | add/sub/mul/div/neg | ⚠️ **`compare` declared, not built; no math fns at all** |
| Date-only (`add_days`/`day_of_week`/…) | 5 ops | **none** | ❌ unimplemented (low priority) |
| Aggregate `aggregated_from` provenance | required (Ch8 §8.7) | not emitted by VM | ⚠️ compiler/SIR responsibility, unbuilt |

Existing PROPs in this space (build on, do not duplicate): **PROP-013** (stdlib kernel — fold/map/
filter/Option/Result, accepted), **PROP-043** (Map[String,V] — design-locked, get/has_key proved),
**PROP-042** (T3 numeric *measure* expressions — `count` for termination evidence only, NOT general
math).

---

## 3. The precondition nobody can skip — dual-toolchain operator parity

LAB-PURSUIT-P1 and the epistemic-outcome arc together surfaced a **load-bearing correctness
finding**: the two reference implementations *disagree on operator typing*.

| Construct | Rust compiler/VM | Ruby TypeChecker |
|-----------|------------------|------------------|
| `Float` arithmetic (`x*v`) | **rejected** (OOF-TY0, operators Integer-typed) | **rejected** |
| `Decimal` arithmetic | **accepted** | **rejected** |
| `==` / `<` on String, `\|\|` | **accepted / executed** | **rejected** ("Unsupported operator") |
| Integer arithmetic | accepted | accepted |

So today **only Integer arithmetic is dual-toolchain-safe.** Any stdlib *promotion to canon* is
gated on resolving this divergence — you cannot bless a numeric stdlib while the canonical Ruby
TC and the lab Rust VM disagree on which numeric types the operators even accept. This is the same
STAB-P4 operator-support-drift theme flagged in LAB-EPISTEMIC-OUTCOME-P4; it is **the** precondition
for this whole area.

**Recommendation: a STAB-P4 (or dedicated) decision must first pin the operator-type matrix**
(which of Integer/Float/Decimal each arithmetic + comparison + boolean operator accepts, in *both*
implementations) before any numeric-stdlib PROP lands. Stdlib coverage is downstream of operator
parity.

---

## 4. Proposed shape — a **Numeric Core** tier (integer-first, math-honest)

Smallest high-value addition, all *pure CORE*, no new types, no FFI:

**Tier N0 — comparison & selection (cheap, unblocks most ergonomics):**
```
abs(x: T) -> T                         -- T ∈ {Integer, Decimal[N]}  (Float pending §3)
min(a: T, b: T) -> T                    -- scalar (distinct from Collection.min over a field)
max(a: T, b: T) -> T
clamp(x: T, lo: T, hi: T) -> T          -- the guidance-clamp idiom (proved by hand in LAB-PURSUIT-P1)
compare(a: T, b: T) -> Integer          -- −1 / 0 / +1  (Ch8 already declares this; just unbuilt)
sign(x: T) -> Integer
```
*(Note: `clamp` and `abs` were hand-rolled with nested `if` in LAB-PURSUIT-P1's `ZemGuidance`/
`EvasionGuidance` — direct empirical demand.)*

**Tier N1 — integer math (embedded-grade, deterministic, FPU-free):**
```
isqrt(x: Integer) -> Integer            -- floor integer square root (Newton/binary; bounded loop)
ipow(base: Integer, exp: Integer) -> Integer   -- exp ≥ 0; bounded
imuldiv(a, b, d: Integer) -> Integer    -- (a*b)/d with wide intermediate — avoids overflow in fixed-point gains
```
`isqrt` alone lifts the "sqrt-free only" constraint that shaped LAB-PURSUIT-P1 — true range `|r|`,
magnitudes, RMS, distance thresholds become expressible without algebraic contortion.

**Tier N2 — trigonometry / real analysis (DEFERRED, decision required):**
`sin`/`cos`/`atan2`/`sqrt`(real) need a prior decision: **integer CORDIC** (fixed-point, FPU-free,
fits the embed philosophy and the determinism/replay property) vs **Float** (requires resolving
§3's Float-operator rejection first). Recommend **CORDIC-on-Integer** as the Igniter-idiomatic
path — deterministic, replayable, no FPU, no Float-divergence dependency — but this is a separate,
larger proof and is explicitly **out of scope** for the first numeric PROP.

**Also small & ready:** Map construction (`from_pairs`/`empty`) — declared in PROP-043, typecheck-
only, no VM handler. A bounded LAB card adds the two OP_CALL handlers (closes PROP-043 v0).

---

## 5. Forbidden / closed surfaces (for the eventual PROP)

- No Float math until §3's Float-operator decision (don't smuggle Float in via a stdlib fn).
- No FFI / libm binding — numeric core is pure, in-VM, deterministic (the whole point vs an FPU embed).
- No new numeric *types* (no `Rational`, no `Complex`, no `BigInt`) — Integer + Decimal only.
- No mutation, no ambient state, no `now()`.
- N2 (trig/real sqrt) is not authorized by this readiness doc — separate route.
- This doc authors no canon PROP and claims no stable API.

---

## 6. Recommended route

1. **STAB-P4-OPERATOR-PARITY (precondition)** — pin the dual-toolchain operator-type matrix
   (arith/compare/bool × Integer/Float/Decimal) in both Ruby TC and Rust VM. *Nothing numeric
   promotes to canon before this.*
2. **PROP-NUMERIC-CORE (N0 + N1)** — `abs/min/max/clamp/compare/sign` + `isqrt/ipow/imuldiv`,
   Integer + Decimal, pure CORE. Direct empirical demand from LAB-PURSUIT-P1. Smallest unlock for
   the robotics/games/sim/control embed class.
3. **LAB-MAP-CONSTRUCT (bounded)** — add `from_pairs`/`empty` VM handlers (closes PROP-043 v0).
4. **PROP-NUMERIC-TRIG (N2, deferred)** — CORDIC-on-Integer trig + integer/real `sqrt`; separate,
   larger, decision-gated.

Sequencing vs the other two docs: **independent of** packaging/structure and can proceed in
parallel — *except* that promoting any stdlib to canon shares the operator-parity precondition (§3)
and would itself become the first real consumer of import resolution (packaging doc §keystone): a
"numeric stdlib" you must re-declare per file is not a stdlib.

---

## Gap Packet

```
doc:       igniter-stdlib-numeric-coverage-proposal-readiness / v0  (1 of 3)
status:    CLOSED — readiness; no canon PROP authored
authority: governance / lang / lab_only
date:      2026-06-10

stdlib_state: ~85% complete (Text/Option/Result/Collection/DateTime done; Map read-only;
              numeric = +−×÷ only; NO abs/min/max/clamp/compare/isqrt/pow/sqrt/trig)
empirical:    LAB-PURSUIT-P1 forced sqrt-free integer fixed-point — the live evidence of the gap
precondition: dual-toolchain OPERATOR PARITY (Float rejected both; Decimal Rust-yes/Ruby-no;
              ==/< /|| Rust-yes/Ruby-no) — STAB-P4 family; gates ALL numeric canon promotion
proposed:     N0 abs/min/max/clamp/compare/sign | N1 isqrt/ipow/imuldiv (Integer+Decimal, pure CORE)
              N2 CORDIC-integer trig + sqrt = DEFERRED (decision-gated)
also:         Map from_pairs/empty VM handlers (closes PROP-043 v0)
route:        STAB-P4-OPERATOR-PARITY → PROP-NUMERIC-CORE → LAB-MAP-CONSTRUCT → PROP-NUMERIC-TRIG(deferred)
closed:       Float math (pending §3) | FFI/libm | new numeric types | N2 here | canon PROP authoring
canon_changed: NO   implementation_authorized: NO
```

---

## Authority

lab-only — proposal-readiness research; no canon claim, no stable surface, no PROP authored, no
code/VM/compiler changes. Ch8 referenced as canon-of-record; the operator divergence is flagged
(STAB-P4), not resolved here. Lab behavior not accepted as canon. Informs future gate decisions;
does not make them.
