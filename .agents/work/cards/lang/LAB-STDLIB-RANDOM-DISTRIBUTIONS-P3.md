# LAB-STDLIB-RANDOM-DISTRIBUTIONS-P3 - deterministic probability helpers over explicit PRNG state

Status: CLOSED
Lane: standard / stdlib science / randomness
Type: implementation proof
Delegation code: OPUS-STDLIB-RANDOM-DISTRIBUTIONS-P3
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

`LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2` closed the core replay-safe RNG without adding language bitops. The surface is explicit state-in/state-out and has no ambient randomness.

The next science pressure is probability helpers that keep the same determinism:

```text
Rng in -> value + Rng out
```

## Goal

Add the first bounded probability helpers over the existing deterministic PRNG:

- integer range sampling, preferably `rng_uniform_int(lo, hi, rng)`;
- Bernoulli sampling, preferably integer probability (`p_per_million` or another exact integer scale);
- golden tests and domain errors.

Live naming may differ; preserve the semantics over exact spelling.

## Verify first

Read:

- `LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2`
- `lab-docs/lang/lab-stdlib-random-probability-readiness-p1-v0.md`
- `lang/igniter-stdlib/stdlib/math.ig` or random stdlib declarations
- `lang/igniter-vm/src/vm.rs` random arms
- `lang/igniter-vm/tests/stdlib_random_tests.rs`
- compiler stdlib/typecheck tests for random if present.

Confirm the current names and record/scalar return shape before editing.

## Semantics

- No hidden state and no ambient `random()`.
- Same seed and same call sequence produce identical values.
- Range helper must reject invalid ranges.
- Bernoulli helper must reject probability outside the selected integer scale.
- No crypto claim.
- No host entropy.
- Float-valued distributions are out of scope unless already trivial from live code.

## Acceptance

- [x] Range sampling compiles/typechecks and runs through the real VM.
- [x] Bernoulli sampling compiles/typechecks and runs through the real VM.
- [x] Both helpers thread the RNG state explicitly. (P2 scalar shape: caller advances with `rng_next`, helper samples supplied state.)
- [x] Golden sequence tests pin deterministic outputs for at least one seed.
- [x] Domain errors are deterministic and tested.
- [x] Existing PRNG core tests remain green.
- [x] No lexer/parser bitops added.
- [x] No ambient entropy, host capability, normal/Lorentzian/categorical distribution.
- [x] `git diff --check` clean.

## Closed scope

No crypto RNG, no OS entropy, no normal distribution, no Lorentzian distribution, no Monte Carlo framework, no package work.

## Next

After this, design Float-valued distribution helpers and the host entropy capability separately.

## Closing report

Implemented deterministic distribution helpers over the existing SplitMix64 explicit-state surface:

- `rng_uniform_int(lo, hi, state) -> Integer`
- `rng_bernoulli_per_million(p_per_million, state) -> Bool`

**Live-design adjustment:** P2 landed a scalar RNG split, not record-return steps. P3 therefore samples from an
explicit state and leaves advancement visible to authored code:

```ig
s1 = rng_next(s0)
i1 = rng_uniform_int(10, 19, s1)
b1 = rng_bernoulli_per_million(500000, s1)
```

`rng_uniform_int` is integer-only multiply-high scaling over the SplitMix64 finalizer. It is deterministic and
Float-free, with deterministic domain errors (`lo > hi`). It does **not** hide rejection-sampling draws because
the scalar API has no returned state to expose variable draw consumption honestly.

Verification:

```text
lang/igniter-vm       cargo test --test stdlib_random_tests     -> 10 passed
lang/igniter-compiler cargo test --test stdlib_random_tests     -> 3 passed
git diff --check                                             -> clean
```

Golden values pinned:

```text
rng_uniform_int(10, 19, first 5 seed-0 states)     -> [18, 14, 10, 19, 11]
rng_bernoulli_per_million(500000, same states)     -> [false, true, true, false, true]
full i64 range first seed-0 state                  -> 7070836379803831727
```

Proof doc: `lab-docs/lang/lab-stdlib-random-distributions-p3-v0.md`.
