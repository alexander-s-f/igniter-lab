# lab-stdlib-random-probability-readiness-p1-v0 — explicit randomness & probability boundary

**Card:** `LAB-STDLIB-RANDOM-PROBABILITY-READINESS-P1` · **Type:** readiness / design (NO code)
**Status:** CLOSED (readiness) — decides the randomness boundary before any RNG API exists. Authority: lab
readiness; canon randomness policy is governance-owned (this feeds it). Grounded in live governance + VM.

## Verify-first findings

- **Governance boundary is explicit and aligned.** `lab-stdlib-surface-inventory-and-entry-contract-v0`:
  *"Deterministic or explicitly capability-gated — no ambient clock (`now()` is OOF-L6 precedent), no ambient
  randomness, no ambient IO"*; and `"deterministic": true, // false requires an explicit entropy capability`.
  So the policy is already settled in principle: **no ambient `random()`; non-determinism requires an explicit
  entropy capability**, exactly like the ambient clock `now()` is OOF-L6 capability-gated.
- **Current app RNG pressure is LOW / incidental** (not a blocker today):
  - `bloom_filter/hash.ig` uses **fixed hash constants** (`a=31,b=17` / `37,53` / `61,7`), `hash=mod(a*key+b, size)`
    — deterministic fixed-seed hashing, **not RNG**.
  - `lead_router` injects clock/reads/rng as **host capabilities** (the injection pattern), not ambient stdlib.
  - The genuine future driver is the **scientific / simulation line** (Kuramoto ω from a distribution, Monte
    Carlo, stochastic CA) — forward-looking, as the card states.
- **THE technical blocker (decisive):** **`.ig` has no bitwise/shift operators** (lexer has no `^ & << >>`),
  and Integer arithmetic is **checked, not wrapping** (P7 `abs` uses `checked_abs` → overflow errors). Every
  serious integer PRNG (SplitMix64, xorshift, PCG, xoshiro) needs **xor + shifts + wrapping multiply**. So a
  **pure-`.ig` PRNG is not expressible today.** ⇒ the v0 PRNG must be **native** (Rust-implemented, exposed as
  stdlib `def`s), exactly like the transcendentals (`sin/det_sin`) are native. This is the key design pivot.

## Authority split (the boundary this card sets)

| Layer | What | Authority | Determinism |
|---|---|---|---|
| **Pure deterministic PRNG** | `rng_seed`, `rng_next`, `uniform_int`, `bernoulli`, … | **pure stdlib** (native impl, pure surface) | **deterministic** — seed is data; same seed → same stream; replay-safe |
| **True entropy / crypto** | secure token, UUID, nonce, password reset, *the initial sim seed* | **host capability / effect** (passport→effect→**receipt**), like `now()`/OOF-L6 | non-deterministic **by design** — lives at the effect edge, never in the pure graph |
| **Probability helpers** | distributions over explicit PRNG state | **pure stdlib** | deterministic; state-threaded |

**The reconciliation with replay (the important part):** a "random" simulation is made fully reproducible by
**capturing entropy once at the edge as a receipt** (the host draws a seed via the entropy capability → the
receipt records it), then running a **pure, deterministic PRNG** seeded by that value. Replay re-injects the
recorded seed → identical stream → identical run. The pure graph never touches ambient entropy. This is the
gold-standard pattern and the linchpin that lets the emergence line study stochastic models with **exact
reproducibility**.

## Surface options compared (≥3)

| # | Option | Verdict |
|---|---|---|
| 1 | **Pure state-threaded PRNG (native impl, pure surface)** | **core of the recommendation** — deterministic, replay-safe, version-pinned |
| 2 | Host capability only, no pure PRNG | **rejected** — sims need cheap deterministic replay; host-only is non-deterministic and can't replay without recording every draw |
| 3 | **Hybrid: pure PRNG for science + host entropy for security/seeding** | **RECOMMENDED overall** (the card's bias, endorsed) — matches the governance `now()`/capability precedent exactly |
| 4 | App-local PRNG helpers only, no stdlib | rejected as the destination (every app reinvents, no shared determinism/version guarantee) — *but note:* it is **currently the only option a user has**, and it is blocked too (no bitwise ops), which is itself why native stdlib is needed |

## Algorithm recommendation (v0)

**SplitMix64, implemented natively in Rust, exposed as stdlib `def`s.**
- **Why:** one `u64` of state; a fixed increment (`0x9E3779B97F4A7C15`) + one multiply + two xorshifts per step;
  excellent non-crypto statistical quality (it is Java's `SplittableRandom` core and the standard seeder for
  xoshiro). **Integer-only → cross-arch deterministic *by construction*** (the card's "argue determinism by
  integer arithmetic only" — Rust `u64` wrapping ops are identical on every target). Trivial to implement and
  document. **No crypto claim** (explicitly stated — SplitMix64 is not cryptographically secure).
- **Why native, not `.ig`:** the bitwise blocker above. The Rust impl uses `wrapping_mul`/`>>`/`^` internally;
  the `.ig` surface is a pure state-threaded API.
- Alternatives noted: `xoshiro256**`/`xoroshiro128**` (better quality, 2–4× `u64` state), `PCG` (excellent,
  more complex output permutation), `xorshift` (simplest, weaker statistics — rejected). SplitMix64 wins on
  simplicity × quality × minimal state for v0.

## State type & API schema (Q2/Q4)

`Rng { state : Integer }` — a single opaque `Integer` carrying the `u64` state (bit-reinterpreted internally;
opaque to the user). Minimal, no hidden state.

```
rng_seed(seed: Integer) -> Rng
rng_next(rng: Rng)       -> RngStep      { rng: Rng, value: Integer }   -- raw next u64-as-Integer + advanced state
uniform_int(lo, hi, rng) -> UniformIntStep { rng: Rng, value: Integer } -- integer-only: cross-arch clean
bernoulli(p, rng)        -> BernoulliStep  { rng: Rng, value: Bool }
```

Every step **returns the next `Rng`** alongside the value (state-threaded, never hidden) — the functional
idiom, fully compatible with the deterministic graph and the record returns the N-body proof (P11) showed work.

## Probability helper prioritization (Q5)

- **Tier 1 (integer-only, cross-arch clean, first impl card):** `uniform_int(lo, hi, rng)` (rejection-sampled
  to avoid modulo bias; composes with the now-landing integer `mod`), `bernoulli(p, rng)` (with `p` as an
  integer permille or `Decimal` to stay integer-deterministic; Float `p` deferred to the Float track).
- **Tier 2 (Float-valued → inherits the P3 Float-determinism caveat):** `uniform_float(rng) -> [0,1)`
  (the `u64 → [0,1)` division is where Float enters — deterministic only under the det-math discipline),
  `categorical(weights, rng)` (cumulative-sum selection; domain errors on empty/negative weights).
- **Deferred:** `normal(mean, stddev, rng)` (Box–Muller needs `sqrt`+`ln`+`cos`), and **Lorentzian** for
  Kuramoto ω (`γ·tan(π(u−½))` needs `uniform_float` + `tan`). Both depend on Tier-2 advanced transcendentals
  (P6-deferred) + Float determinism (P3). **Emergence note:** until then, the Kuramoto loop (P12) should seed
  ω from a precomputed deterministic stream or an integer sampling, not draw from a continuous distribution.

## Replay / provenance (Q7/Q8)

- **Seed is data** — an `Integer` input in the lineage. Same seed → identical stream (the PRNG is pure). A
  whole stochastic run is reproducible from a single recorded number.
- **Host-entropy-seeded runs:** the entropy capability's **receipt** records the drawn seed; replay
  re-injects it → deterministic re-run. Non-determinism is captured **once, at the edge**, never in the graph.
- **The PRNG algorithm is part of the stdlib surface → pinned by `STDLIB_VERSION`** (package P6). Changing the
  algorithm bumps the version → `igniter.lock` `toolchain.stdlib` drift catches it, so a locked workspace
  reproduces identical streams. Randomness becomes **versioned and lock-pinned**.

## Cross-arch determinism (design constraint)

- `rng_seed/rng_next/uniform_int/bernoulli(int p)` are **integer-only → bit-identical across architectures by
  construction** (the constraint satisfied without Float).
- `uniform_float` and Float-`p` helpers introduce Float → **deferred to / governed by the P3 det-math
  discipline** (don't claim cross-arch Float identity here).

## Diagnostics / domain errors (Q9)

A new **`OOF-RAND`** runtime domain-error class (parallel to the math domain errors):
- `bernoulli(p)` with `p < 0` or `p > 1` → domain error.
- `uniform_int(lo, hi)` with `lo > hi` → domain error.
- `categorical(weights)` with empty or negative weights → domain error.
Compile-time arity/type follow the existing `OOF-MATH1/2/3` pattern (or a parallel `OOF-RAND` arity/type).

## First implementation card + acceptance matrix (Q10)

**`LAB-STDLIB-RANDOM-PRNG-CORE-P2` — native SplitMix64 + integer surface.**

| Acceptance dimension | Target |
|---|---|
| Algorithm | SplitMix64, native Rust (`wrapping_mul` + xorshifts); documented; **no crypto claim** |
| State | `Rng { state: Integer }` (opaque u64) |
| Surface | `rng_seed`, `rng_next`, `uniform_int` (Tier-1), `bernoulli(int p)`; state-threaded record returns |
| Determinism | same seed → identical stream (golden-vector bit test); integer-only ⇒ cross-arch by construction (qemu CI later) |
| Replay/provenance | seed is data; algorithm pinned by `STDLIB_VERSION` (drift test) |
| Diagnostics | `OOF-RAND` domain errors (bad p / range); compile arity/type |
| Boundary | **no ambient `random()`**; entropy capability is a separate card |
| Scope | no Float draws, no crypto, no host entropy, no normal/categorical |

Follow-ons: `LAB-STDLIB-RANDOM-FLOAT-AND-DIST-Pn` (`uniform_float`/`categorical`, Float-caveated) and
`LAB-HOST-ENTROPY-CAPABILITY-READINESS-Pn` (the `now()`-style entropy effect + receipt).

## Acceptance (this card) — mapping

- [x] Live pressure inventory completed (governance boundary; bloom fixed-seed; lead_router injected; sim is the driver).
- [x] Ambient randomness boundary stated clearly (**none**; non-determinism = explicit entropy capability, `now()`/OOF-L6 precedent).
- [x] ≥3 surface options compared (4 in the table).
- [x] Pure PRNG algorithm recommendation made (**SplitMix64, native**, with the bitwise-blocker rationale).
- [x] Host entropy capability boundary defined (effect + receipt; seed captured once at the edge).
- [x] Probability helper ordering proposed (Tier-1 integer / Tier-2 Float-caveated / deferred normal+Lorentzian).
- [x] Replay/provenance + cross-arch determinism considered (seed-as-data, receipt re-injection, STDLIB_VERSION pin, integer-only argument).
- [x] First impl card named with acceptance matrix (`LAB-STDLIB-RANDOM-PRNG-CORE-P2`).
- [x] No production code changes.

## Closed scope

No implementation; no crypto RNG; no Monte Carlo engine; no normal distribution (deferred design only); no
package/registry work; no canon claim.

## Next

`LAB-STDLIB-RANDOM-PRNG-CORE-P2` (native SplitMix64 + integer surface), then Float/dist helpers and the host
entropy capability as separate cards. Emergence dependency: the Kuramoto loop (P12) seeds ω deterministically
until Tier-2 transcendentals + Float draws land.

---

*Lab readiness. 2026-06-21. Randomness boundary set: no ambient `random()`; a **pure deterministic
state-threaded PRNG** (native **SplitMix64**, integer-only → cross-arch by construction, because `.ig` has no
bitwise ops to author one) for science/simulation, with **true entropy as a host capability + receipt** (the
`now()`/OOF-L6 precedent) kept strictly at the effect edge. Seed-as-data + receipt re-injection +
`STDLIB_VERSION` pinning make stochastic runs exactly reproducible — the replay property the emergence line
needs. First impl card: `LAB-STDLIB-RANDOM-PRNG-CORE-P2`.*
