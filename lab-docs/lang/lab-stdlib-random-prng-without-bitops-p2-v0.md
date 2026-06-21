# lab-stdlib-random-prng-without-bitops-p2-v0 — deterministic SplitMix64 PRNG without language bitops

**Card:** `LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2` · **Type:** implementation proof
**Status:** CLOSED — a pure, deterministic, **state-threaded** PRNG (SplitMix64) is live as a native stdlib
surface, with **no language bitwise/shift operators added** and **no record returns**. Same seed → identical
sequence; first sample is canonical SplitMix64. Builds on the P1 readiness boundary.

## Why no bitops are solved here (the constraint)

Verified live: the lexer has **no `^ & | << >>`** tokens, and Integer arithmetic is **checked, not wrapping**
(P7 `abs` uses `checked_abs`). Every integer PRNG needs xor + shifts + wrapping multiply, so a **pure-`.ig`
PRNG is impossible today.** Per P1, this card does **not** rush a syntax change: the bit-twiddling is hidden
inside a **native VM builtin** (Rust), while the `.ig` boundary stays explicit-state. A separate
`LAB-STDLIB-INTEGER-BITOPS-READINESS-P1` can decide language bitops later.

## Algorithm + constants

**SplitMix64** (no crypto claim). Wrapping arithmetic is explicit (`wrapping_add`/`wrapping_mul`); no platform
UB. Integer-only ⇒ **bit-identical across architectures by construction**.

```
GOLDEN = 0x9E3779B97F4A7C15
state' = state +w GOLDEN                         -- rng_next: the additive state step
mix(z):                                          -- rng_value: the stateless finalizer
  z = (z ^ (z >> 30)) *w 0xBF58476D1CE4E5B9
  z = (z ^ (z >> 27)) *w 0x94D049BB133111EB
  z =  z ^ (z >> 31)
```

**Key structural insight:** SplitMix64's state transition is a pure **add**, and its output is a **stateless
finalizer** of the state. So a "step" splits cleanly into two scalar functions — `rng_next` (advance) and
`rng_value` (sample) — which is exactly why **no record return is needed** (and no record-returning stdlib
builtin precedent exists — verified). This sidesteps both the bitops gap and the records-from-builtin gap.

## Signed/unsigned mapping policy

`Integer` is `i64`; SplitMix64 is `u64`. The state is **opaque** — the `Integer` carries the `u64` state
**bit-reinterpreted** (`i as u64` / `u as i64`, bit-preserving, no information loss). `rng_value` samples span
the full `i64` range (may be negative — it's a raw bit pattern, not a magnitude). `rng_uniform01` takes the
**top 53 bits** of the finalizer and scales by `2^-53` → a Float in `[0,1)`, always finite (never trips the
non-finite→JSON-null lineage hazard).

## Surface (scalar state-threaded; `Value` shape)

No records — every function takes/returns a scalar `Value::Integer`/`Value::Float`:

```ig
def rng_seed(seed: Integer) -> Integer        -- normalize seed → initial state (identity in v0; state opaque)
def rng_next(state: Integer) -> Integer       -- advance: SplitMix64 additive step
def rng_value(state: Integer) -> Integer      -- sample: SplitMix64 finalizer (full-range Integer)
def rng_uniform01(state: Integer) -> Float    -- sample mapped to [0,1) (always finite)
```

Usage threads state explicitly (no hidden/global state):
`s1 = rng_next(rng_seed(seed)); v1 = rng_value(s1); s2 = rng_next(s1); v2 = rng_value(s2); …`

**Deviation from the card's candidate `RngInt { rng, value }` record:** replaced by the scalar pair
`rng_next` + `rng_value` because (a) no stdlib builtin returns a record today and (b) SplitMix64 splits
naturally. The card explicitly permitted "choose the smallest existing shape and document it." Explicit state
threading — the load-bearing property — is preserved.

## Wiring (single-source dispatch, OP_CALL + eval_ast parity)

- VM: arms added to **`eval_math_call`** (the single semantic source shared by `OP_CALL` and the eval_ast/HOF
  path since P10) → the PRNG composes inside `map/fold/lambda` bodies with identical semantics, for free. The
  `OP_CALL` mirror name-list was extended to route the rng names to the same source.
- Typechecker (`stdlib_calls.rs`): `rng_seed/rng_next/rng_value` → `Integer`, `rng_uniform01` → `Float`;
  **`OOF-RAND1`** (arity), **`OOF-RAND2`** (non-Integer argument).
- Declarative `stdlib/random.ig` (module `stdlib.Random`); `STDLIB_VERSION` + `igniter-stdlib` version bumped
  `0.1.2 → 0.1.3` (surface changed; guard test `stdlib_version_mirrors_crate` green).

## Golden sequence (seed 0)

`rng_next` then `rng_value`, five samples:

```
i64:  [-2152535657050944081, 7960286522194355700, 487617019471545679, -537132696929009172, 1961750202426094747]
u64[0] = 16294208416658607535 = 0xE220A8397B1DCDAF   ← canonical SplitMix64(seed=0) first output
uniform01(first state) = 0.8833108082136426
```

The first `u64` matching `0xE220A8397B1DCDAF` confirms this is **reference SplitMix64**, not an ad-hoc variant.

## Replay / authority boundary

- **Seed is data** — an `Integer` in the lineage; same seed → identical stream (pure, no hidden state).
- The algorithm is pinned by **`STDLIB_VERSION`** (package P6) → a locked workspace reproduces identical
  streams; changing the algorithm is lock drift.
- **No ambient `random()`, no crypto/security claim, no true entropy.** True entropy (seeding from the
  outside world, tokens, UUIDs) is a **host capability + receipt** at the effect edge — deferred to a separate
  card; the pattern is: host draws a seed once → receipt records it → the pure PRNG (this card) makes the rest
  exactly reproducible.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_random_tests         → 6 passed; 0 failed
  (seed0_golden_sequence, same_seed_identical_sequence, different_seeds_differ,
   uniform01_in_unit_interval_and_deterministic, arity_and_type_errors, first_sample_through_compiler_vm)
$ cargo test --test stdlib_math_tests/hof/det/nbody                   → 6/7/5/5 passed (math parity intact)
$ cd lang/igniter-compiler && cargo test stdlib_version_mirrors_crate → 1 passed (0.1.3 mirror)
$ igc compile rng_proof.ig                                            → status: ok (all stages)
$ igc compile rng_bad.ig (Float→rng_next)                            → OOF-RAND2, status: oof
$ git diff --check                                                    → clean
```

`first_sample_through_compiler_vm` runs `rng_value(rng_next(rng_seed(0)))` through the **real `Compiler` →
`VM::execute`** (not just `eval_math_call`), proving OP_CALL/eval_ast dispatch parity.

## Acceptance — mapping

- [x] Surface is explicit state-in/state-out; no ambient RNG.
- [x] No lexer/parser bitwise/shift syntax added.
- [x] `rng_seed`, `rng_next`(+`rng_value` for the sample), `rng_uniform01` compile/typecheck (authored `.ig` → status ok).
- [x] VM returns deterministic scalar values (records replaced by the documented scalar split).
- [x] Golden sequence pins 5 outputs for seed 0 (+ canonical-SplitMix64 confirmation).
- [x] Repeated run, same seed → identical sequence.
- [x] Different seeds → different first outputs.
- [x] `uniform01` ∈ [0,1), finite, deterministic.
- [x] OP_CALL + eval_ast/HOF parity (shared `eval_math_call` source; compiler→VM test).
- [x] Wrong arity/type deterministic (`OOF-RAND1`/`OOF-RAND2`; VM-level errors).
- [x] `STDLIB_VERSION` + `igniter-stdlib` bumped 0.1.2→0.1.3 (guard green).
- [x] Tests green; `git diff --check` clean.

## Files

- `lang/igniter-vm/src/vm.rs` (`eval_math_call` rng arms + `splitmix64_mix`/`rng_unary_int`/`rng_uniform01` helpers; OP_CALL mirror).
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (rng typecheck arm; OOF-RAND1/2).
- `lang/igniter-stdlib/stdlib/random.ig` (new; module `stdlib.Random`).
- `lang/igniter-compiler/src/lib.rs` + `lang/igniter-stdlib/Cargo.toml` (`STDLIB_VERSION` 0.1.3).
- `lang/igniter-vm/tests/stdlib_random_tests.rs` (new; 6 tests).

## Closed scope (honored)

No bitwise/shift operators; no crypto/UUID/nonce/token; no distribution helpers (`bernoulli`/`normal`/
`categorical`); no Monte Carlo; no qemu cross-arch proof; no canon claim.

## Next

- `LAB-STDLIB-RANDOM-PROBABILITY-HELPERS-P3` — `uniform_int`, `bernoulli`, weighted `categorical` over the
  explicit PRNG (Tier-1 integer first; Float/dist caveated per P1/P3).
- `LAB-STDLIB-INTEGER-BITOPS-READINESS-P1` — bitwise functions/operators as a separate language topic.
- Emergence: the Kuramoto loop (P12) can now seed ω deterministically via this PRNG (Lorentzian `tan` still
  deferred behind Tier-2 transcendentals).

---

*Lab proof. 2026-06-21. Deterministic SplitMix64 PRNG, scalar state-threaded, native (because `.ig` has no
bitops and Integer is checked-not-wrapping), no records — same seed → identical stream, first sample is
canonical `0xE220A8397B1DCDAF`, [0,1) uniform finite, OP_CALL/eval_ast parity, `OOF-RAND1/2`, pinned by
`STDLIB_VERSION` 0.1.3. The replay-safe randomness the emergence line needs; true entropy stays a host
capability.*
