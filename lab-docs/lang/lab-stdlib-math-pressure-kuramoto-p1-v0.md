# lab-stdlib-math-pressure-kuramoto-p1-v0 — stdlib.Math pressure from the emergence research workload

**Card:** `LAB-STDLIB-MATH-PRESSURE-KURAMOTO-P1` · **Type:** pressure / readiness (evidence, design-only)
**Status:** CLOSED (pressure finding) — a real research workload (Kuramoto synchronization, the first
emergence experiment) was run against the live toolchain and **pressured `stdlib.Math` to a hard wall**:
the math surface is four `Decimal` functions and nothing else. **No code change to the language in this card
— this is the evidence + prioritized recommendation.**
**Authority:** Lab evidence. The workload lives in the private `igniter-home-lab` emergence research line
(`LAB-IGNITER-EMERGENCE-RESEARCH-CHARTER-P1`); this packet is the language-side pressure it produced.

## Verify-first: the actual `stdlib.Math` surface (live)

`lang/igniter-stdlib/stdlib/math.ig` declares, in full:

```ig
module stdlib.Math
def add(a: Decimal[S],  b: Decimal[S])  -> Decimal[S]
def sub(a: Decimal[S],  b: Decimal[S])  -> Decimal[S]
def mul(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 + S2]
def div(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 - S2]
```

That is the **entire** math standard library: fixed-point `Decimal` add/sub/mul/div. Confirmed absent
(stdlib **and** native VM): `sin`, `cos`, `tan`, `sqrt`, `pow`, `exp`, `ln`, `pi`/`e` constants, `abs`,
`floor`/`ceil`/`round`, `mod`. The VM (`igniter-vm/src/vm.rs`) has **no** native trig/sqrt either — grep for
`.sin()`/`.sqrt()` returns nothing.

**What the substrate *does* have (also verified):**
- `Float` (`f64`) is a first-class type; the VM evaluates `+ − × ÷` and `> < ≤ ≥` on `Value::Float`
  (`vm.rs` match arms). The typechecker treats `Integer|Float|Decimal` as numeric, **but Integer×Float
  mixing is deliberately deferred** — Float expressions must keep all operands Float (`6.0`, not `6`).
- Collection `map` / `fold` / `sum` / `range` are accepted by the compiler.

So **algebra and iteration are present; transcendental/irrational math is entirely missing.**

## The pressure: what Kuramoto needs vs what exists

The Kuramoto micro-rule `dθ_i/dt = ω_i + (K/N)·Σ_j sin(θ_j − θ_i)` and order parameter
`r = |(1/N)Σ_j e^{iθ_j}|` require:

| Need | In stdlib.Math? | Severity |
|---|---|---|
| `sin` (the coupling term — unavoidable) | **no** | **blocker** |
| `sqrt` (order-parameter magnitude) | **no** | **blocker** |
| `cos` (order parameter via (Σcos, Σsin)) | **no** | high |
| `pi` constant (phase wrap, Kc = 2γ scaling) | **no** | high |
| `mod` / float remainder (phase wrap into [0,2π)) | **no** | medium |
| `abs` | **no** | low (derivable) |
| Float `+ − × ÷` | yes (operators) | — |

**Result:** the first emergence experiment cannot be written cleanly today — it hits the transcendental wall
immediately. This is the predicted pressure: the research line bears on `stdlib.Math`.

## Proof that transcendentals are the *only* blocker (live run)

To show the gap is precisely "no transcendentals in stdlib" and nothing deeper, `sin` was **hand-rolled in
pure `.ig`** (bounded Taylor `x − x³/6 + x⁵/120 − x⁷/5040`, all-Float) and run end-to-end on the live
toolchain:

```text
igniter_compiler compile sin.ig --out sin.igapp     → status: ok (parse/typecheck/classify/emit/assemble ok)
igniter-vm trace sin.igapp --entry SinApprox …      → result_status: ok (42 instructions executed)
```

The Taylor bytecode is numerically sound (standard IEEE `f64` opcodes): `x=0.5` → series `0.4794255` vs
exact `sin(0.5)=0.4794255`. So Kuramoto **is** expressible/runnable on the substrate **if** we hand-roll the
transcendentals — which is exactly the argument for putting them in `stdlib.Math` instead. (Source:
`igniter-home-lab/apps/emergence/kuramoto/sin.ig`.)

**Adjacent finding (minor, separate):** `igniter-vm trace` reports execution but not the returned value — a
small runner gap worth a follow-up (a `run`/`eval` that prints the output value would make numeric proofs
one-line).

## Recommended `stdlib.Math` additions (prioritized; design-only)

Tier 1 (unblocks Kuramoto and most numeric work):
- `sin(x: Float) -> Float`, `cos(x: Float) -> Float`, `sqrt(x: Float) -> Float`, and a `pi() -> Float`
  constant (or `Float` literal const).

Tier 2 (rounds out the surface):
- `tan`, `pow(base, exp)`, `exp`, `ln`, `abs`, `floor`/`ceil`/`round`, `mod`/`rem` (float remainder).

Tier 3 (numeric ergonomics, separate research):
- Integer↔Float coercion policy (the deferred mixing rule) so `2*pi` etc. don't force `2.0`.
- `Decimal`↔`Float` bridges (the current stdlib is Decimal-only; research math is Float-heavy).

## The determinism fork (this is the important design decision, ties to the swarm)

`sin`/`sqrt` can be provided two ways, and the choice is **load-bearing** for the emergence + embedded-swarm
lines:

- **(A) `f64` native (`libm`):** simplest, fastest. But `f64`+`libm` are **not guaranteed bit-identical
  across architectures** → byte-identical replay holds only on the same arch; sim↔ESP32 agreement becomes
  statistical. Weakens the "exact reproducibility" thesis on hardware.
- **(B) fixed-point / table-or-CORDIC `sin`, integer-domain:** designed for deterministic, bit-identical replay
  across architectures; physical swarm identity still needs a hardware proof before it becomes a recorded
  guarantee. Costs some speed/precision.

Recommendation: offer **both**, explicitly — a default `f64` `stdlib.Math.sin` for convenience, and a
deterministic `stdlib.Math.det.sin` (fixed-point/LUT) for reproducible/embedded use. The emergence research
line (`KURAMOTO-IMPL-P3`) and the swarm line (`LAB-IGNITER-EMBEDDED-VM-SWARM-READINESS-P1`) both depend on
this fork; deciding it once here keeps them coherent.

## Scope / boundaries

- Evidence + recommendation only; **no language/stdlib code changed in this card.**
- Float-only path documented; Integer×Float coercion stays deferred (separate research).
- The workload is the private emergence research line; this packet is its language-side pressure.

## Next card

`LAB-STDLIB-MATH-TRANSCENDENTALS-P2` — implement Tier-1 `stdlib.Math` (`sin`/`cos`/`sqrt`/`pi`), deciding the
determinism fork (A `f64` default + B `det.*` fixed-point), with conformance tests vs known values and a
cross-arch determinism check for the `det.*` variant. Unblocks Kuramoto's clean implementation.

---

*Lab pressure finding. 2026-06-21. The first emergence experiment (Kuramoto) pressured `stdlib.Math` to a
hard wall: four Decimal functions, no transcendentals. Proven (live compile+run of a hand-rolled Taylor
`sin`) that transcendentals are the sole blocker. Recommendation: Tier-1 `sin/cos/sqrt/pi`, with an explicit
`f64`-vs-deterministic fork that the emergence and swarm lines share.*
