# lab-stdlib-random-distributions-p3-v0

**Card:** `LAB-STDLIB-RANDOM-DISTRIBUTIONS-P3`  
**Status:** CLOSED (implementation proof)  
**Date:** 2026-06-22

## Summary

Added the first deterministic probability helpers over the existing SplitMix64 explicit-state PRNG:

- `rng_uniform_int(lo, hi, state) -> Integer`
- `rng_bernoulli_per_million(p_per_million, state) -> Bool`

They preserve the P2 scalar surface: callers advance state explicitly with `rng_next`, then sample from that
state. No ambient random source, no host entropy, no lexer/parser bitops, no record-return RNG shape.

## Live design adjustment

The older readiness sketch used a functional `Rng -> value + Rng out` shape. P2 deliberately landed a scalar
split instead:

```ig
s1 = rng_next(s0)
v1 = rng_value(s1)
```

P3 follows that live shape:

```ig
s1 = rng_next(s0)
i1 = rng_uniform_int(10, 19, s1)
b1 = rng_bernoulli_per_million(500000, s1)
```

This keeps state consumption visible in authored code and avoids hidden internal draws. `rng_uniform_int`
uses integer multiply-high scaling over the SplitMix64 finalizer; it is deterministic and Float-free, but it is
not a hidden rejection loop because this scalar API has no returned state to expose variable draw consumption.

## Implementation

- `lang/igniter-stdlib/stdlib/random.ig`
  - declares `rng_uniform_int`
  - declares `rng_bernoulli_per_million`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
  - typechecks arity and Integer-only arguments with `OOF-RAND1` / `OOF-RAND2`
  - return types: `Integer` for range, `Bool` for Bernoulli
- `lang/igniter-vm/src/vm.rs`
  - adds both helpers to the same `eval_math_call` single source used by OP_CALL and eval_ast/HOF paths
  - `rng_uniform_int`: rejects `lo > hi`, supports inclusive ranges including full `i64`
  - `rng_bernoulli_per_million`: rejects probabilities outside `[0, 1000000]`
- Tests:
  - `lang/igniter-vm/tests/stdlib_random_tests.rs`
  - `lang/igniter-compiler/tests/stdlib_random_tests.rs`

## Golden values

For seed `0`, after explicit `rng_next` states:

```text
rng_uniform_int(10, 19, state[0..5])       -> [18, 14, 10, 19, 11]
rng_bernoulli_per_million(500000, state)   -> [false, true, true, false, true]
```

The golden tests also pin full-range behavior:

```text
rng_uniform_int(i64::MIN, i64::MAX, first_state(seed=0)) -> 7070836379803831727
```

## Verification

```text
cd lang/igniter-vm
cargo test --test stdlib_random_tests
=> 10 passed

cd lang/igniter-compiler
cargo test --test stdlib_random_tests
=> 3 passed
```

Compiler test proves `.ig` typecheck behavior:

- valid distribution calls compile cleanly;
- wrong arity emits `OOF-RAND1`;
- non-Integer args emit `OOF-RAND2`.

VM test proves direct runtime + compiler-to-VM nested OP_CALL execution:

- range helper runs and returns golden values;
- Bernoulli helper runs and returns golden values;
- deterministic domain errors are returned, not panics;
- existing P2 PRNG golden sequence remains green.

Warnings seen during test runs are pre-existing crate warnings, not introduced by this slice.

## Closed Scope

No ambient entropy, no crypto RNG, no OS random, no normal/Lorentzian/categorical distribution, no Float
probability parameter, no language bitops, no package or host capability work.

## Next

Float-valued distributions should remain a separate design/implementation wave. If unbiased rejection-sampled
integer helpers become required, they should first revisit the RNG API shape so the returned state can expose
variable draw consumption honestly.
