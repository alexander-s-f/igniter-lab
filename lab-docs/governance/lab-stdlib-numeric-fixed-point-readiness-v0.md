# LAB-STDLIB-NUMERIC-FIXED-POINT-P1
## Readiness / Boundary Proof — Fixed-Point Integer Convention

**Lane:** governance / stdlib / numeric  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Status:** CLOSED — SPLIT  
**Date:** 2026-06-12  
**Card:** `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-NUMERIC-FIXED-POINT-P1.md`  
**Predecessors:** LAB-NEURAL-NET-BASELINE-P1 (85/85 PASS, NN-P03 documented), LAB-DSA-BASELINE-P1

---

## 1. Goal

Determine the boundary between:
- What the fixed-point integer convention IS (app-level working pattern)
- What belongs in stdlib (none yet, maybe later)
- What belongs in Decimal[N] work (separate toolchain track)
- What LAB-STDLIB-NUMERIC-P1 should cover (type-system question, not convention question)

---

## 2. App Evidence

Three apps use fixed-point Integer arithmetic. Their conventions are consistent but undeclared
at the type level.

### 2.1 neural_net — scale=1000 (documented)

**`neural_net/types.ig`:**
> "Since Igniter has no Float support, all values (weights, biases, inputs) are scaled by a
> factor of 1000. E.g., 0.5 is represented as 500."

**`neural_net/layers.ig`:**
> "Because our scale is 1000, multiplying two fixed-point numbers yields a scale of 1,000,000.
> So we divide by 1000 to normalize."

```
compute z1_raw = (x.x1 * w.w11) + (x.x2 * w.w12)
compute z1     = (z1_raw / 1000) + w.b1
```

**`neural_net/activations.ig` — SigmoidApprox:**
```
-- If scale is 1000:
-- x < -2500 => 0
-- x > 2500  => 1000
-- else => (x / 5) + 500
compute activated = if x < (0 - 2500) { 0 } else { if x > 2500 { 1000 } else { (x / 5) + 500 } }
```

### 2.2 vector_math — milli-units, scale=1000 (documented)

**`vector_math/types.ig`:**
> "All components use Integer (milli-units) since Igniter's typechecker does not support Float
> binary operators. Convention: 1000 = 1.0, 500 = 0.5, etc."

Multiply-normalize appears in every non-additive operation:
```
-- Vec2Scale:    (v.x * scalar) / 1000
-- Vec2Dot:      (a.x * b.x + a.y * b.y) / 1000
-- Vec2LengthSq: (v.x * v.x + v.y * v.y) / 1000
-- Vec2Lerp:     a.x + ((b.x - a.x) * t) / 1000
-- Vec2Cross:    (a.x * b.y - a.y * b.x) / 1000
-- Mat3MulVec3:  (m.r0.x * v.x + m.r0.y * v.y + m.r0.z * v.z) / 1000
```

Unary minus workaround (`0 - x`) in Vec2Negate, Vec3Negate (NN-P02 / unary_op gap):
```
compute result = { x: 0 - v.x, y: 0 - v.y }
```

### 2.3 bookkeeping — Decimal[2] (cents), NOT fixed-point Integer

`bookkeeping/types.ig`: `amount: Decimal[2]`

This is NOT fixed-point Integer — it uses the `Decimal[N]` type, which IS the semantic answer for
financial quantities. The bookkeeping app is blocked on:
- BK-P02: Decimal equality (`total_debits == total_credits` → OOF-TY0)
- BK-P03: Decimal literal typing (`0.00` inferred as Float, output expects Decimal[2])

**Critical distinction:** `Decimal[N]` is a first-class type with scale declared in the type
system. Fixed-point Integer is a convention where scale lives only in comments.

---

## 3. The Three Conventions Compared

| Convention | Type | Scale location | Who enforces | Arithmetic | In Igniter today |
|---|---|---|---|---|---|
| Fixed-point Integer (milli) | Integer | Comments only | Developer discipline | `(a * b) / 1000` | WORKS — all ops return Integer |
| Decimal[N] | Decimal[2] | Type param N | Type system (partially) | `a + b` (BLOCKED) | BLOCKED — BK-P02/P03 |
| Raw Integer (unitless) | Integer | N/A | N/A | `a + b` | WORKS |

---

## 4. The Multiply-Normalize Pattern

Every multiply of two fixed-point values must be followed by a divide to restore the scale.
This is a mechanical invariant with no type-level enforcement:

```
Scale = 1000 = 10^3

add(a, b):       a + b           — scale unchanged (1000 + 1000 = 1000) ✓
subtract(a, b):  a - b           — scale unchanged ✓
multiply(a, b):  (a * b) / 1000  — (1000 * 1000 = 1,000,000) / 1000 = 1000 ✓
scale(v, s):     (v * s) / 1000  — same as multiply ✓
dot(a, b):       (Σ aᵢ * bᵢ) / 1000  — multiply is inside the sum ✓
lerp(a, b, t):   a + ((b-a) * t) / 1000  — multiply by t is scaled ✓
```

**The invariant is expressible and verifiable at the expression level — but it is NOT checked by
the typechecker.** A developer who writes `a * b` (missing `/ 1000`) gets a result that is
1000× too large, silently.

---

## 5. Risk Catalog

### R1: Silent scale error (no OOF diagnostic)

`a * b` without `/ scale` compiles and runs without any error. The scale is wrong at runtime.
No compile-time protection is possible with current TC — there is no way to express that
an Integer has a particular scale.

**Severity:** High when mixing normalized and raw values at call boundaries.
**Current mitigation:** All three apps use consistent scale=1000 throughout; the boundary
risk only appears if different modules use different scales or if `call_contract` passes a
raw value where a normalized one is expected.

### R2: Integer overflow on multiply

With scale=1000, a value of 1.0 is represented as 1000. Two 1.0 values multiplied gives
1,000,000 before normalization. For a value near max representable magnitude M:

- Safe range before multiply: M < √(MAX_INT / scale)
- 64-bit max: ~9.2×10^18. Safe value range: < √(9.2×10^18 / 1000) ≈ 3×10^7 (milli-units → 3×10^4 real units)
- 32-bit max: ~2.1×10^9. Safe range: < √(2.1×10^9 / 1000) ≈ 1449 (real units)

**Neural net weights** stay in [-2.5, 2.5] real → [-2500, 2500] milli → safe.
**Vector math** inputs are user coordinates → depends on domain. For game-scale coords (0–10000 milli = 0–10 units), overflow is not a concern.

**Mat3 determinant** computes triple products (`a * b * c`) — each step must intermediate-divide:
```
compute cofactor_a = (m.r1.y * m.r2.z - m.r1.z * m.r2.y) / 1000
```
This is correct — each pair is divided before the next multiply. But it is fragile; reordering
the operations could cause overflow.

### R3: Truncation on division (floor toward zero)

Integer division in Igniter truncates toward zero. For `(5 * 1000) / 3`:
`5000 / 3 = 1666` (should be 1666.67). The error is ≤ 1/scale per operation.

Cumulative truncation is a known fixed-point hazard. For the current apps:
- Lerp with `t = 333` (≈0.333) introduces truncation per component
- Dot products and cross products introduce 1-unit error per term

**For neural networks:** Acceptable — these are approximations anyway.
**For vector math:** Acceptable for game-scale geometry; not for finance.
**For financial:** Decimal[N] is the correct type — integer division is wrong for accounting.

### R4: No round-trip to/from external representation

There is no `from_float(0.5) → 500` or `to_float(500) → 0.5` in stdlib. Fixed-point values
are entered as literals (e.g., weight `500` meaning 0.5) or computed from other fixed-point
values. External float inputs require the author to write the multiplication manually.

---

## 6. Relation to Decimal[N]

`Decimal[N]` is the TYPE-SYSTEM answer to fixed-scale quantities. It is a first-class type
that declares its scale in the type signature, enabling:
- Type-safe equality (`Decimal[2] == Decimal[2]` should work — blocked by BK-P02)
- Type-safe arithmetic (`Decimal[2] + Decimal[2] → Decimal[2]` — blocked by STAB-P4)
- Structural sum (`sum(postings, :amount) → Decimal[2]` — WORKS via field lookup)

**Fixed-point Integer is a workaround** for the absence of working Decimal arithmetic. The
two are NOT the same:

| Property | Fixed-point Integer | Decimal[N] |
|---|---|---|
| Scale in type signature | No | Yes (N) |
| TC enforcement | None | Partial (type param) |
| Cross-boundary safety | Convention only | Type system |
| Available today | YES | Blocked (BK-P02/P03) |
| Correct for finance | No (truncation) | Yes (designed for it) |
| Correct for ML/graphics | Yes (approximation OK) | Overkill |

**Route for Decimal:** BK-P02 + BK-P03 → LAB-STDLIB-DECIMAL-P1 → LANG-STDLIB-DECIMAL-OPERATOR-P1.
This is entirely separate from the fixed-point Integer question.

---

## 7. Relation to LAB-STDLIB-NUMERIC-P1

LAB-STDLIB-NUMERIC-P1 is about a **type system question**: what is a "numeric type" in Igniter?
Can type parameters be constrained to `{Integer, Decimal[N]}`? This gates:
- `sum(Collection[T]) → T` where T: Numeric (one-arg sum Split B)
- Any stdlib function whose return type depends on a numeric constraint

**This is orthogonal to the fixed-point convention.** Fixed-point Integer uses only:
- `Integer + Integer → Integer` (already works)
- `Integer - Integer → Integer` (already works)
- `Integer * Integer → Integer` (already works)
- `Integer / Integer → Integer` (already works)

LAB-STDLIB-NUMERIC-P1 does NOT unlock any missing arithmetic for fixed-point. Fixed-point
users need nothing from it.

---

## 8. stdlib vs. App Convention Boundary

### What is NOT stdlib material (now)

| Pattern | Why not stdlib |
|---|---|
| `(a * b) / 1000` normalize | Three-operation expression; no new function needed |
| Scale factor choice (1000, 100, etc.) | App-domain specific; stdlib cannot know |
| Overflow prevention | Author responsibility; varies by domain |
| Truncation rounding | No rounding mode in stdlib yet |

### What COULD be stdlib (later, demand-gated)

| Candidate | Prerequisite | Demand signal |
|---|---|---|
| `stdlib.math.fixed.mul(a, b, scale) → Integer` | At least 2 apps using different scales | Not yet — both apps use 1000 |
| `stdlib.math.fixed.div(a, b, scale) → Integer` | Same | Not yet |
| `Fixed[S]` type (Integer with scale param) | Type parameter support in record/stdlib system | Not yet |
| Scale-mismatch OOF (call boundary check) | `Fixed[S]` type first | Not yet |

**Current conclusion:** No stdlib helpers are warranted. The pattern is 2 operations
(`* b / scale`) and is transparent. Abstracting `fixed_mul(a, b)` would hide a 1000 constant
in stdlib when the app already documents it in comments.

### What belongs in a convention document

- Canonical scale declaration pattern (top-of-module comment)
- Normalize-after-multiply rule
- Overflow safe-range formula
- Truncation caveat for each operation type
- Unary minus workaround (`0 - x`) pending LANG-PARSER-UNARY-MINUS-P1

---

## 9. Verdict: SPLIT

**Split A — ACCEPT (app convention, no stdlib):**

Fixed-point Integer arithmetic is a working pattern for ML/graphics domains where Float is
unavailable and Decimal[N] arithmetic is blocked. The pattern is:
1. Declare scale at module top in a comment (e.g., `-- Convention: 1000 = 1.0`)
2. Add/subtract: no normalization needed
3. Multiply: always `(a * b) / scale`
4. Negate: `0 - x` (unary minus gap, see LANG-PARSER-UNARY-MINUS-P1)
5. Document overflow safe range

No new stdlib entries required. No implementation authorized. Convention document is sufficient.

**Split B — HOLD (stdlib.math.fixed.* helpers):**

No cross-scale demand yet. Both apps use scale=1000. A helper `fixed_mul(a, b)` with an
implicit 1000 would be less readable than `(a * b) / 1000`. Revisit when:
- A second scale value (100, 256, etc.) appears in fixtures
- A scale-mismatch bug is documented at a call boundary

**Split C — ROUTE TO LAB-STDLIB-DECIMAL-P1:**

`Decimal[N]` (bookkeeping) is NOT fixed-point Integer. Route:
- BK-P02 (Decimal equality) + BK-P03 (Decimal literal typing) → LAB-STDLIB-DECIMAL-P1
- LANG-STDLIB-DECIMAL-OPERATOR-P1 (arithmetic operators for Decimal[N])
- Blocked on STAB-P4 (dual-toolchain operator parity)

---

## 10. Next Routes

1. **LAB-STDLIB-NUMERIC-P1** — numeric type constraint for `T: Numeric` (gates one-arg sum,
   not gated on fixed-point; can proceed independently)

2. **LANG-STDLIB-DECIMAL-OPERATOR-P1** — Decimal[N] arithmetic (+, -, *, ==) with dual-toolchain
   parity (BK-P02/P03 active; gated on STAB-P4 clarification)

3. **LANG-PARSER-UNARY-MINUS-P1** — `parse_unary` for `-` token (fixes `0 - x` workaround
   in neural_net/vector_math; orthogonal to fixed-point convention but addresses NN-P02)

4. **LAB-FIXED-POINT-CONVENTION-P2** — (optional, demand-gated) stdlib.math.fixed helpers
   if a second scale appears in fixtures or cross-scale bugs are observed

---

## 11. Evidence Summary Table

| Evidence | Source | Pattern |
|---|---|---|
| scale=1000 declared | `neural_net/types.ig:7` | Comment-only declaration |
| multiply-normalize | `neural_net/layers.ig:10-11` | `(z1_raw / 1000) + w.b1` |
| SigmoidApprox boundaries | `neural_net/activations.ig:21-24` | `x > 2500 → 1000` |
| Vec2Scale normalize | `vector_math/vec2.ig:37` | `(v.x * scalar) / 1000` |
| Vec2Dot normalize | `vector_math/vec2.ig:62` | `/ 1000 to get milli-units` |
| Mat3 dot-per-row | `vector_math/mat3.ig:30-37` | `/ 1000` per row dot |
| unary minus workaround | `vector_math/vec2.ig:44-47` | `0 - v.x` |
| Decimal[2] blocked | `bookkeeping/types.ig:5` + BK-P02/P03 | separate track |
| `operator_type` always Integer | `typechecker.rb:1188-1199` | +/-/*// all return Integer |
| Decimal arithmetic gap | `typechecker.rb:1184-1216` | no Decimal in `operator_type` |
