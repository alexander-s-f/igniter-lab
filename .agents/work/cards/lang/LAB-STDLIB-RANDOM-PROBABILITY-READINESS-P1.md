# LAB-STDLIB-RANDOM-PROBABILITY-READINESS-P1 — explicit randomness and probability boundary

Status: CLOSED
Lane: standard / stdlib science
Type: readiness / design
Delegation code: OPUS-STDLIB-RANDOM-PROBABILITY-READINESS-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Igniter is moving beyond web/app forms into scientific and simulation workloads. Randomness is a high-risk
surface because it can silently break replay, auditability, and deterministic graph execution.

Current signals:

- Governance inventory says no ambient randomness / no ambient IO.
- `bloom_filter` uses probabilistic semantics with fixed hash seeds, not RNG.
- `lead_router` mentions host `rng` as an injected production concern.
- Simulation / Monte Carlo / probabilistic models will eventually need random streams.

This card decides the boundary before any random API is implemented.

## Goal

Design the first randomness/probability surface for Igniter, separating:

1. **Pure deterministic PRNG** — explicit seed/state in, explicit value/state out; replay-safe.
2. **True entropy / crypto randomness** — host capability/effect, never ambient stdlib.
3. **Probability helpers** — distributions built over explicit PRNG state, not hidden global state.

No production code changes in this card.

## Verify first

- `lab-docs/governance/lab-stdlib-surface-inventory-and-entry-contract-v0.md` (ambient randomness boundary)
- `apps/igniter-apps/bloom_filter/*`
- `apps/igniter-apps/lead_router/*` (host rng mention)
- current `lang/igniter-stdlib/stdlib/*`
- current effect/capability docs for host authority and receipts
- math P5/P10 docs for deterministic/replay discipline

Search live tree for `random`, `rng`, `seed`, `probability`, `bernoulli`, `uniform`, `normal`, `monte` and
classify real pressure vs incidental words.

## Questions to answer

1. Should Igniter ever expose ambient `random()`? Bias: **no**.
2. What is the minimal pure PRNG state type?
   - `Rng { seed: Integer }`
   - `Rng { state_hi, state_lo }`
   - opaque String state
   - other
3. Which deterministic algorithm is appropriate for v0?
   - xorshift / splitmix64 / PCG / xoroshiro
   - criteria: simple, deterministic, portable, documented, no crypto claim
4. What should the API shape be?
   - `rng_seed(seed) -> Rng`
   - `rng_next(rng) -> RngStep { rng, value }`
   - `uniform_float(rng) -> UniformStep { rng, value }`
   - explicit tuple/record return, never hidden state
5. How do probability helpers compose with explicit RNG?
   - `bernoulli(p, rng)`
   - `uniform_int(lo, hi, rng)`
   - `categorical(weights, rng)`
   - `normal(mean, stddev, rng)` deferred?
6. What belongs to host entropy capability instead?
   - secure token, UUID, nonce, password reset, production sampling
7. How should replay/provenance record the seed/state?
8. How should deterministic PRNG interact with package lock / stdlib version?
9. What diagnostics/domain errors are needed?
   - invalid probability p < 0 or p > 1
   - invalid ranges
   - empty weights / negative weights
10. What is the first implementation card and acceptance matrix?

## Design constraints

- No ambient/global RNG.
- No cryptographic claims for pure PRNG.
- No host authority in pure stdlib.
- No hidden mutable state.
- Repeated run with same seed must produce identical values.
- Cross-arch behavior must be argued by integer arithmetic only, or deferred if Float conversion is involved.
- Probability helpers must preserve and return next RNG state.

## Candidate surfaces to compare

At least compare:

1. Pure state-threaded PRNG records.
2. Host capability only, no pure PRNG.
3. Hybrid: pure PRNG for simulations + host entropy for security.
4. App-local PRNG helpers only, no stdlib yet.

Bias: hybrid, with pure deterministic PRNG first for science/simulation and host entropy kept separate.

## Required deliverable

Write `lab-docs/lang/lab-stdlib-random-probability-readiness-p1-v0.md` with:

- pressure inventory;
- authority split (pure PRNG vs host entropy);
- algorithm recommendation;
- API schema;
- probability helper prioritization;
- replay/provenance story;
- exact next implementation card name + acceptance matrix.

Close this card with a report.

## Acceptance

- [x] Live pressure inventory completed. (governance boundary; bloom fixed-seed; lead_router injected; sim = driver.)
- [x] Ambient randomness boundary stated clearly. (none; non-determinism = explicit entropy capability, `now()`/OOF-L6.)
- [x] At least three surface options compared. (4 in the table.)
- [x] Pure PRNG algorithm recommendation made or explicitly deferred. (**SplitMix64, native** — bitwise blocker.)
- [x] Host entropy capability boundary defined. (effect + receipt; seed captured once at the edge.)
- [x] Probability helper ordering proposed. (Tier-1 integer / Tier-2 Float-caveated / deferred normal+Lorentzian.)
- [x] Replay/provenance and cross-arch determinism considered. (seed-as-data, receipt re-injection, STDLIB_VERSION, integer-only.)
- [x] First implementation card named with acceptance matrix. (`LAB-STDLIB-RANDOM-PRNG-CORE-P2`.)
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Decision (hybrid, governance-aligned):** **no ambient `random()`**. A **pure, deterministic, state-threaded
PRNG** for science/simulation (`rng_seed`/`rng_next`/`uniform_int`/`bernoulli`, every step returns the next
`Rng` — no hidden state), plus **true entropy as a host capability + receipt** kept strictly at the effect
edge. This maps onto the EXISTING governance precedent verbatim: the inventory already says *"no ambient
randomness; `false` deterministic requires an explicit entropy capability"* and `now()` is the OOF-L6
capability-gated precedent — entropy follows the same model.

**Decisive verify-first finding (reframed the algorithm path):** **`.ig` has no bitwise/shift operators**
(lexer has no `^ & << >>`) and Integer arithmetic is **checked, not wrapping** (P7 `abs`→`checked_abs`). Every
integer PRNG needs xor+shift+wrapping-mul → **a pure-`.ig` PRNG is impossible today**. So the PRNG must be
**native** (Rust, exposed as stdlib `def`s) exactly like the transcendentals. Recommended algorithm:
**SplitMix64** — one `u64` state, integer-only ⇒ **cross-arch deterministic by construction**, simple, good
non-crypto quality, explicit *no crypto claim*.

**Replay linchpin:** seed is **data** in the lineage (same seed → identical stream); host-entropy-seeded runs
capture the seed **once** as a receipt → replay re-injects it; the algorithm is pinned by `STDLIB_VERSION`
(package P6) so a locked workspace reproduces identical streams. This is what lets the emergence line study
stochastic models with exact reproducibility.

**Probability ordering:** Tier-1 integer (`uniform_int` rejection-sampled, `bernoulli` integer-p) is cross-arch
clean and first; Tier-2 Float (`uniform_float`, `categorical`) inherits the P3 Float-determinism caveat;
`normal` (Box–Muller) + **Lorentzian for Kuramoto ω** (`γ·tan(π(u−½))`) deferred behind Tier-2 transcendentals
— so the Kuramoto loop (P12) seeds ω deterministically until then. New `OOF-RAND` runtime domain-error class.

**Deliverables:** readiness packet `lab-docs/lang/lab-stdlib-random-probability-readiness-p1-v0.md`; first impl
card **`LAB-STDLIB-RANDOM-PRNG-CORE-P2`** named with an acceptance matrix (native SplitMix64 + integer surface,
golden-vector determinism, `OOF-RAND`, no ambient/crypto/host-entropy). Follow-ons: Float/dist helpers; host
entropy capability (the `now()`-style effect). No production code changed.

**Next:** `LAB-STDLIB-RANDOM-PRNG-CORE-P2`.

## Closed scope

- No implementation.
- No crypto RNG implementation.
- No Monte Carlo engine.
- No normal distribution unless only as deferred design.
- No package/registry work.
- No canon claim.
