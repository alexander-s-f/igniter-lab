# LAB-NUMERIC-DECIMAL-BOUNDARY-P1

**Status:** CLOSED — READINESS PROVED 62/62 — DECISION: no implicit Float→Decimal v0; route = explicit `decimal(value, scale)`
**Route:** lab / numeric / Decimal boundary
**Date:** 2026-06-15
**Authority:** readiness and policy only; no numeric coercion implementation

## Goal

Classify the residual numeric blocker exposed after homogeneous numeric ops were enabled
in `LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1`.

Known residual:

- `bookkeeping` executes Float/Decimal arithmetic but then fails `Output type mismatch: expected Decimal[2], got Float`.

This is not the same as homogeneous numeric ops. It asks whether Igniter should allow
Float -> Decimal assignment/coercion, and if so under what precision/rounding authority.

## Gate

Start after:

- `LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1` cluster 1 DONE.
- Current `bookkeeping` runtime/typecheck evidence available.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch3-type-system.md`
- Any Decimal/Money readiness docs or T3 numeric measure docs in gov/lang.

## Questions

1. Where does `Decimal[2]` exist today: syntax, typechecker only, VM value, or app convention?
2. Does the VM preserve Decimal scale, or does it treat Decimal as a numeric family without scale metadata?
3. Is Float -> Decimal assignment safe without an explicit conversion function?
4. Should the right route be explicit `decimal(value, scale)` / `round_decimal` stdlib rather than implicit assignability?
5. What diagnostics should remain for lossy or ambiguous numeric conversion?
6. Is bookkeeping asking for money semantics rather than generic Decimal semantics?
7. Which parts belong in canon-lang vs lab runtime only?

## Deliverables

- Readiness doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-numeric-decimal-boundary-p1-v0.md`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_numeric_decimal_boundary_p1.rb`, target at least 55 checks.
- Update this card and portfolio index.
- If accepted, create a follow-up implementation card with exact explicit conversion surface.

## Acceptance

- Clearly separates homogeneous numeric ops (already done) from heterogeneous conversion.
- Gives a yes/no decision on implicit Float -> Decimal assignability for v0.
- Identifies whether bookkeeping should migrate to explicit Decimal construction.
- Does not relax money/precision semantics by accident.

## Closed Surfaces

- No implementation.
- No implicit coercion without explicit follow-up authorization.
- No Money type.
- No rounding policy changes.
- No app source migration.
- No canon spec changes beyond readiness proposal.

## Closure Summary (2026-06-15)

**READINESS PROVED 62/62.** Boundary made crisp; decision recorded.

### Decision
- **Implicit `Float → Decimal` (and `Integer → Decimal`) assignability for v0: NO.** It is
  **already correctly rejected** today — `OOF-TY1`, dual-toolchain, via
  `structurally_assignable` (name-equality). Money is exact fixed-point; implicit coercion
  would silently round/lose precision. **Keep rejecting.**
- **The real gap is Decimal CONSTRUCTION, not coercion.** No `decimal()` constructor and no
  Decimal literal exist (`0.00` types as `Float`; `decimal(0,2)` → `OOF-TY0` Unknown
  function). A pure contract cannot mint a `Decimal[N]` constant — exactly what
  `bookkeeping`'s fold seed needs.
- **Route: explicit `decimal(value, scale) -> Decimal[scale]`** stdlib constructor.
  `round_decimal(Float, scale)` is deferred as the only sanctioned (explicit, rounding-bearing)
  `Float → Decimal` bridge. `bookkeeping` migrates `0.00` → `decimal(0, 2)` so the money path
  stays in the `Decimal[2]` family and never touches `Float`.

### Grounded findings (dual-toolchain, live)
- `Decimal[N]` is first-class across **syntax** (`Decimal[N]`), **typechecker** (scale-aware:
  `+/-` need equal scale → `OOF-TC5`, `*` → `Decimal[A+B]`, `stdlib.decimal.add/mul`), and
  **VM** (`Value::Decimal { value, scale }` on `igniter_stdlib::decimal` — scale preserved).
- Implicit `Float→Decimal`, `Integer→Decimal`, and bare-`0.00`→Decimal all `OOF-TY1` (dual);
  `bookkeeping` full compile is `OOF-TY1: expected Decimal[2], got Float` (BK-P03 live).
- **Canon parity gap:** Ruby canon **crashes** on a `Decimal[N]` input annotation
  (`undefined method 'fetch' for 2:Integer`), while Rust handles it — `Decimal[N]` is
  lab-leaning; the canon Ruby path must be hardened.

### Q&A
Q1 first-class (syntax/TC/VM, not app convention) · Q2 VM preserves scale · Q3 implicit
unsafe → already rejected, keep · Q4 yes, explicit `decimal()`/`round_decimal` · Q5 keep
`OOF-TY1`/`OOF-TC5`, no silent coercion · Q6 generic `Decimal[2]`, no `Money` type · Q7
policy+surface canon, runtime substrate lab, Ruby `Decimal[N]` annotation gap to fix.

### Deliverables
| Artefact | Status |
|---|---|
| `igniter-view-engine/proofs/verify_lab_numeric_decimal_boundary_p1.rb` | **62/62 PASS** (≥55) |
| `lab-docs/lang/lab-numeric-decimal-boundary-p1-v0.md` | Written |
| This card / portfolio index / follow-up card | Updated / created |

### Follow-up (created)
`LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` — implement `decimal(value, scale) -> Decimal[scale]`
(TC arm + VM/stdlib, dual-toolchain) + fix the Ruby `Decimal[N]` annotation crash. Then a
`bookkeeping` migration card (`0.00` → `decimal(0, 2)`).

## Agent Recommendation

Give this to **Claude Opus 4.8** if available, otherwise strong Codex. This is a policy/semantics card; implementation is easy only after the boundary is crisp.
