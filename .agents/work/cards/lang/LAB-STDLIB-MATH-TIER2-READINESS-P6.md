# LAB-STDLIB-MATH-TIER2-READINESS-P6 — next numeric surface after Tier-1

Status: CLOSED
Lane: standard / stdlib math
Type: readiness / design
Delegation code: OPUS-STDLIB-MATH-TIER2-READINESS-P6
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P2 added Tier-1 fast f64 `sin/cos/sqrt/pi`; P3/P5 cover deterministic Tier-1. We should not wait for the next
app pressure to discover that the next obvious math primitives are missing. But we also should not dump a giant
numeric standard library into the language without taxonomy, semantics, and tests.

P1 suggested Tier-2 candidates: `tan`, `pow`, `exp`, `ln`, `abs`, `floor`, `ceil`, `round`, `mod`.

## Goal

Design the next math surface and split it into one or two bounded implementation cards. Decide which functions
belong in fast Float math, deterministic math, integer/decimal helpers, or should stay deferred.

No production code changes in this card.

## Verify first

- Current math implementation after P2/P5 if present.
- `lab-docs/lang/lab-stdlib-math-pressure-kuramoto-p1-v0.md`
- `lab-docs/lang/lab-stdlib-math-transcendentals-p2-v0.md`
- `lab-docs/lang/lab-stdlib-math-determinism-readiness-p3-v0.md`
- `lab-docs/governance/igniter-stdlib-numeric-coverage-proposal-readiness-v0.md`
- `lab-docs/governance/lab-stdlib-numeric-fixed-point-readiness-v0.md`
- Search app-pressure docs for missing math mentions: air combat, pursuit, vector, neural, emergence.

## Questions to answer

1. Which Tier-2 functions are genuinely next: `abs/min/max/clamp` vs `tan/pow/exp/ln` vs rounding/mod?
2. Which types should each support: Integer, Float, Decimal[N]?
3. Which functions are total and which need domain/runtime/type errors?
4. Should `pow` be split into `powf` and integer exponent variants?
5. Should `mod` be integer-only first?
6. Should `abs/min/max/clamp` be implemented before advanced transcendentals because they unlock control/physics?
7. Which functions need deterministic counterparts immediately?
8. How should non-finite Float behavior be handled consistently?
9. What diagnostic rules should be introduced beyond `OOF-MATH1/2`?
10. What exact implementation cards should follow?

## Bias

Prefer a practical split:

- **P7 Numeric basics:** `abs`, `min`, `max`, `clamp`, `mod`, maybe `floor/ceil/round`.
- **P8 Advanced Float:** `tan`, `pow`, `exp`, `ln`.

But let live pressure decide. If app docs show `sqrt/sin/cos/atan` pressure rather than `exp/ln`, adjust.

## Required deliverable

- Readiness packet: `lab-docs/lang/lab-stdlib-math-tier2-readiness-p6-v0.md`
- Closing report in this card.
- One or two concrete implementation cards with acceptance matrices.

## Acceptance

- [x] Existing live math surface summarized. (Decimal ×4 + Float sin/cos/sqrt/pi; OOF-MATH1/2.)
- [x] At least five candidate functions categorized by type/domain/determinism need. (12 in the table.)
- [x] App-pressure evidence cited from live docs or source search. (LAB-PURSUIT N0/N1, neural sigmoid, vector magnitude, Kuramoto mod.)
- [x] Recommended implementation split chosen. (P7 N0 → P8 N1+mod → deferred advanced Float; evidence-adjusted vs bias.)
- [x] Diagnostics/domain policy proposed. (`OOF-MATH3` type-mismatch; runtime domain-error convention; non-finite rule.)
- [x] No production code changes.

## Closed scope

- No implementation.
- No broad numeric tower.
- No Decimal transcendentals unless only as a recommendation.
- No registry/package work.

---

## Closing Report (2026-06-21)

**Method:** ranked Tier-2 by **live app-pressure**, not the tentative bias — raw substring counts were
noise-contaminated (`sign`→design, `log`→logic, `round`→around) and discarded in favor of the actual
app-pressure docs.

**Live surface note:** after harvest, P5 is closed: flat `det_sin/det_cos/det_sqrt` are in the stdlib surface
with local golden-bit lock and `STDLIB_VERSION`/`igniter-stdlib` bumped to `0.1.1`; cross-arch confirmation is
still deferred to qemu CI.

**Decision (evidence-adjusted):** the highest *proven* pressure is **numeric basics N0** (`abs/min/max/clamp/
sign` — hand-rolled with nested `if` in **LAB-PURSUIT-P1**'s `ZemGuidance`) and **integer roots/powers N1**
(`isqrt/ipow`, which lift the forced **sqrt-free** constraint), plus integer `mod` (CA/sandpile emergence are
integer). The card's bias `exp/ln` is **second-wave** (low real pressure; mostly noise). `atan2` (guidance) +
`exp` (real sigmoid) are deferred to a readiness card opened on real pressure.

**Key finding:** the high-pressure tier is **deterministic by construction** — comparisons, sign flips, and
integer arithmetic are bit-identical cross-arch with **no `det.*` variant needed**. Only the deferred Float
transcendentals inherit the P3 determinism fork. So Tier-2's most-wanted functions are also the cheapest to
make replay-safe. Non-finite handled by reusing P3's NaN→`null` rule (stay finite; runtime domain error
otherwise). New compile diagnostic `OOF-MATH3` = numeric type-mismatch/no-coercion.

**Deliverables:** readiness packet `lab-docs/lang/lab-stdlib-math-tier2-readiness-p6-v0.md`; two impl cards
named with acceptance matrices — **`LAB-STDLIB-MATH-NUMERIC-BASICS-P7`** (N0, total, no det) and
**`LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8`** (`isqrt/ipow/mod`, integer-deterministic, domain errors);
advanced Float transcendentals deferred. Aligned with governance **PROP-NUMERIC-CORE (N0+N1)** — canon PROP is
governance-owned, these lab cards feed it as executable evidence (authority boundary respected). No code.

**Next:** `LAB-STDLIB-MATH-NUMERIC-BASICS-P7`.
