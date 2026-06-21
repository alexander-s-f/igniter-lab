-- stdlib/random.ig
-- LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2
--
-- Pure, deterministic, state-threaded PRNG (SplitMix64) for science/simulation. NO ambient random():
-- the state is an explicit Integer in and out; the same seed yields the same sequence on every run. True
-- entropy / crypto randomness is a HOST CAPABILITY (effect + receipt), never this pure stdlib surface.
--
-- The algorithm is implemented natively in the VM (SplitMix64; `.ig` has no bitwise/shift operators and
-- Integer arithmetic is checked-not-wrapping, so a pure-.ig PRNG is not expressible — the bit-twiddling is
-- hidden behind the builtin while the language boundary stays explicit-state). NO crypto/security claim.
--
-- The `Rng` state is a plain Integer carrying the u64 SplitMix64 state (bit-reinterpreted; opaque — do not
-- treat it as a meaningful number). SplitMix64 splits into an additive state step and a stateless finalizer,
-- so a step is exposed as two scalar functions rather than a record:
--
--   s0 = rng_seed(seed)
--   s1 = rng_next(s0)        v1 = rng_value(s1)        u1 = rng_uniform01(s1)
--   s2 = rng_next(s1)        v2 = rng_value(s2)        ...
--
-- Determinism is integer-only ⇒ bit-identical across architectures by construction; pinned by STDLIB_VERSION.
module stdlib.Random

-- Normalize a seed into the initial PRNG state (identity in v0; the state is opaque).
def rng_seed(seed: Integer) -> Integer

-- Advance the state: the SplitMix64 additive step. Returns the next state.
def rng_next(state: Integer) -> Integer

-- The sample for a state: the SplitMix64 finalizer. Full-range Integer (may be negative).
def rng_value(state: Integer) -> Integer

-- The sample for a state mapped to a Float in [0, 1) (top 53 bits / 2^53). Always finite.
def rng_uniform01(state: Integer) -> Float
