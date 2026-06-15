# LAB-NUMERIC-DECIMAL-BOUNDARY-P1 — Readiness / Policy

**Status:** CLOSED — READINESS PROVED — DECISION: no implicit Float→Decimal v0; route = explicit `decimal(value, scale)` construction
**Route:** lab / numeric / Decimal boundary
**Date:** 2026-06-15
**Authority:** readiness and policy only — no numeric coercion implementation

---

## 0. TL;DR

The residual `bookkeeping` blocker is **`Output type mismatch: expected Decimal[2], got
Float`** (BK-P03), live dual-toolchain. It is **not** a homogeneous-numeric problem (that
cluster is done). It is a **heterogeneous numeric→Decimal** question.

**Decision (Q3):** implicit `Float → Decimal` (and `Integer → Decimal`) assignment is
**NOT** allowed for v0 — and it is **already correctly rejected today** (`OOF-TY1`,
dual-toolchain, via `structurally_assignable` name-equality). Keep rejecting it. Money is
exact fixed-point; an implicit coercion would silently round/truncate without a declared
rounding policy.

**Decision (Q4):** the real gap is not coercion but **Decimal construction**. There is
**no way to write a `Decimal[N]` constant in source today** — no `decimal()` constructor
and no Decimal literal (`0.00` types as `Float`). The route is an explicit
**`decimal(value, scale) -> Decimal[scale]`** stdlib constructor. `bookkeeping` migrates
its `Float` zero-seed `0.00` → `decimal(0, 2)`, keeping the whole fold in the `Decimal[2]`
family (matching scale), never crossing `Float`.

This is a **follow-up implementation card**, not part of P1.

---

## 1. Grounded current state (dual-toolchain, live)

| Probe | Ruby canon | Rust lab |
|---|---|---|
| `bookkeeping` full compile | `OOF-TY1` (+others) | **`OOF-TY1: expected Decimal[2], got Float`** |
| `0.00 → Decimal[2]` | `OOF-TY1` | `OOF-TY1` |
| `f:Float → Decimal[2]` | `OOF-TY1` | `OOF-TY1` |
| `n:Integer → Decimal[2]` | `OOF-TY1` | `OOF-TY1` |
| `decimal(0, 2) → Decimal[2]` | `OOF-TY0` Unknown function + `OOF-TY1` | same |
| `d:Decimal[2] → Decimal[2]` (sanity) | (Ruby crash, see §Q7) | clean |

So: implicit numeric→Decimal is **uniformly rejected** for every source numeric type, and
**no Decimal constructor exists**. The only ways to obtain a `Decimal[N]` value today are a
typed **input** (`input x : Decimal[2]`) or **Decimal arithmetic** on existing Decimals.
A pure contract cannot mint a Decimal **constant** — which is exactly what `bookkeeping`'s
fold seed needs.

## 2. The seven questions

**Q1 — Where does `Decimal[2]` exist?** First-class across all three layers, not an app
convention:
- **Syntax**: `Decimal[N]` (`parser.rs` `is_decimal`; ch3 `Decimal[N]` fixed-point, N places).
- **Typechecker**: scale-aware — `Decimal[A] + Decimal[B]` requires `A == B` (`OOF-TC5`),
  `Decimal[A] * Decimal[B] → Decimal[A+B]`; lowered to `stdlib.decimal.add` / `stdlib.decimal.mul`.
- **VM**: `Value::Decimal { value, scale }` backed by `igniter_stdlib::decimal::Decimal`;
  arithmetic computes the result scale.

**Q2 — Does the VM preserve scale?** **Yes.** `Value::Decimal { value, scale }` carries the
scale as runtime metadata; `add`/`sub`/`mul`/`div` go through `Decimal::new(value, scale)`
and return a scaled result. Decimal is **not** a scaleless numeric family at runtime.

**Q3 — Is `Float → Decimal` assignment safe without explicit conversion?** **No**, and it is
already rejected (`OOF-TY1`, dual). `Float` is binary floating-point (e.g. `0.1` is
inexact); `Decimal[2]` is exact base-10 fixed-point. An implicit bridge would have to pick a
rounding mode and silently lose precision — unacceptable for money. **Keep the rejection.**

**Q4 — Explicit `decimal()` / `round_decimal` rather than implicit assignability?** **Yes.**
- **v0 surface:** `decimal(value, scale) -> Decimal[scale]` — construct an exact Decimal
  constant from an `Integer` (and optionally a fractional-part form). `decimal(0, 2)` is the
  `bookkeeping` zero-seed. Keeps the value in the Decimal family from the start.
- **Deferred (separate card):** `round_decimal(x : Float, scale) -> Decimal[scale]` — the
  **only** sanctioned `Float → Decimal` bridge, carrying an explicit rounding choice. Not
  needed by `bookkeeping` (its money path never touches Float once the seed is Decimal).

**Q5 — Diagnostics for lossy / ambiguous conversion?** Keep `OOF-TY1` (output mismatch
rejecting implicit numeric→Decimal) and `OOF-TC5` (Decimal scale mismatch in add/sub). No
silent coercion is introduced. The explicit constructor is the sole sanctioned path; a
future `round_decimal` makes the rounding mode explicit at the call site.

**Q6 — Money semantics vs generic Decimal?** `bookkeeping` wants **generic `Decimal[2]`
fixed-point exactness** (debits/credits balance, exact sums) — which *serves* money — not a
dedicated `Money` type. `Decimal[N]` + explicit construction is sufficient. **No `Money`
type** (closed surface).

**Q7 — Canon-lang vs lab-runtime?**
- **Canon-lang:** the policy (no implicit Float/Integer→Decimal v0; explicit construction is
  the sanctioned route) and the `decimal(value, scale)` surface + ch3 wording.
- **Lab-runtime:** the substrate already exists (`Value::Decimal{value,scale}`,
  `igniter_stdlib::decimal`). Implementing `decimal()` is a TC arm + VM/stdlib lowering — a
  lab follow-up that the canon policy authorizes.
- **Canon parity gap (newly surfaced):** Ruby canon **crashes** on a `Decimal[N]` input
  annotation (`undefined method 'fetch' for 2:Integer` — the integer scale param), while Rust
  handles it. So `Decimal[N]` is currently **lab-leaning**; the canon Ruby Decimal[N]
  annotation path must be hardened alongside (or before) the `decimal()` constructor.

## 3. Boundary (crisp)

| Layer | Status |
|---|---|
| Homogeneous numeric (`Float+Float`, `Decimal[s]+Decimal[s]`) | DONE (`LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1`) |
| Heterogeneous numeric→Decimal **assignment/coercion** | **REJECTED today (correct); keep rejected** |
| Decimal **construction** from a constant | **MISSING — the real lever** → `decimal(value, scale)` |
| `Float → Decimal` **with rounding** | deferred → explicit `round_decimal(x, scale)` |

## 4. `bookkeeping` migration (follow-up, not P1)

`ComputeAccountBalance` currently seeds its fold with a `Float` literal
(`fold(txs, 0.00, (acc, tx) -> acc + 0.00)`, a placeholder) against an output
`Decimal[2]` → `OOF-TY1`. Target after the `decimal()` constructor lands:

```igniter
compute total : Decimal[2] =
  fold(txs, decimal(0, 2), (acc, tx) -> acc + <Decimal[2] sum of tx postings>)
```

Seed `decimal(0, 2)` is `Decimal[2]`; `acc + …` is `Decimal[2] + Decimal[2]` (matching
scale); output `Decimal[2]`. No `Float` in the money path.

## 5. Decision record

- **Implicit `Float→Decimal` (and `Integer→Decimal`) assignability for v0: NO.** Already
  rejected dual-toolchain; keep it.
- **Route: explicit `decimal(value, scale)` construction** (real gap = construction, not
  coercion). `round_decimal(Float, scale)` deferred as the explicit rounding bridge.
- **`bookkeeping` migrates to explicit Decimal construction** (a separate app-migration card,
  gated on the `decimal()` constructor).
- **No `Money` type, no rounding-policy change, no implicit coercion** — preserved.

## 6. Follow-up

Create `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` (implementation): `decimal(value, scale) ->
Decimal[scale]` TC arm + VM/stdlib lowering, dual-toolchain, plus the Ruby canon
`Decimal[N]` annotation-crash fix. Then a `bookkeeping` migration card.

## 7. Closed surfaces (this P1)

No implementation; no implicit coercion without explicit follow-up authorization; no `Money`
type; no rounding-policy change; no app source migration; no canon spec change beyond this
readiness proposal.
