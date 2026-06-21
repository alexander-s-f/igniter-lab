# LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2 — deterministic PRNG without language bitops

Status: CLOSED
Lane: standard / stdlib science / randomness
Type: implementation proof
Delegation code: OPUS-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on `LAB-STDLIB-RANDOM-PROBABILITY-READINESS-P1` if already closed; otherwise this card may proceed only
with the core boundary agreed in chat:

- no ambient `random()`;
- pure deterministic PRNG is explicit state-in/state-out;
- true entropy/crypto randomness is a host capability/effect, not stdlib pure math;
- `.ig` currently has **no bitwise/shift operators** (`^`, `&`, `|`, `<<`, `>>`) in the lexer/parser.

The bitops finding must not force a rushed language-syntax change. v0 PRNG can hide bit-twiddling inside a VM
stdlib builtin while preserving explicit deterministic state at the language boundary.

## Goal

Implement the smallest replay-safe deterministic PRNG surface **without adding language bit operators**.

Candidate v0 surface:

```ig
type Rng { state : Integer }
type RngInt { rng : Rng  value : Integer }
type RngFloat { rng : Rng  value : Float }

def rng_seed(seed: Integer) -> Rng
def rng_next_int(rng: Rng) -> RngInt
def rng_uniform01(rng: Rng) -> RngFloat
```

Exact spelling may change after verify-first, but the shape must remain explicit state threading.

## Verify first

- `lang/igniter-stdlib/stdlib/*` surface patterns.
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` record/stdlib-call support.
- `lang/igniter-vm/src/vm.rs` OP_CALL and eval_ast parity patterns after P10.
- Live ability to return records from stdlib calls / VM builtins; if no direct helper exists, choose the
  smallest existing shape and document it.
- Lexer/parser absence of bitwise/shift operators, to document why this card avoids syntax work.

## Algorithm requirement

Choose a simple deterministic integer PRNG implementable in Rust VM code without exposing bitops to `.ig`:

- splitmix64, PCG32, xorshift64*, or similar.
- Prefer an algorithm with tiny implementation, stable integer semantics, and no crypto claim.
- Document exact constants and state transition in the proof doc.

If full u64 semantics are awkward because `Integer` is signed i64, choose and document a bounded mapping. Do not
silently rely on platform undefined behavior; use Rust wrapping arithmetic explicitly.

## Semantics

- `rng_seed(seed)` normalizes the seed deterministically into internal state.
- `rng_next_int(rng)` returns a new state and an integer sample.
- `rng_uniform01(rng)` returns a new state and a Float in `[0, 1)`.
- Same seed -> identical sequence across runs.
- No hidden mutable/global state.
- No crypto/security claim.
- No true entropy.
- No language bitops.

## Acceptance

- [x] Surface is explicit state-in/state-out; no ambient RNG.
- [x] No lexer/parser bitwise/shift syntax is added.
- [x] `rng_seed`, `rng_next_int`, and `rng_uniform01` compile/typecheck. (scalar split `rng_next`+`rng_value` for the sample; authored `.ig` → status ok.)
- [x] VM returns deterministic records or documented equivalent values. (scalar values — record deviation documented.)
- [x] Golden sequence test pins at least 5 outputs for a fixed seed. (seed 0; +canonical `0xE220A8397B1DCDAF`.)
- [x] Repeated run with same seed yields identical sequence.
- [x] Different seeds yield different first outputs in a small sanity test.
- [x] `uniform01` stays in `[0,1)` and is deterministic.
- [x] OP_CALL and eval_ast/HOF parity (shared `eval_math_call`; compiler→VM test).
- [x] Wrong arity/type errors are deterministic. (`OOF-RAND1`/`OOF-RAND2` + VM-level.)
- [x] `STDLIB_VERSION` / `igniter-stdlib` bumped 0.1.2→0.1.3 (guard `stdlib_version_mirrors_crate` green).
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-random-prng-without-bitops-p2-v0.md`.
- [x] Relevant tests green; `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implemented native SplitMix64** as a pure, deterministic, **scalar state-threaded** stdlib surface —
`rng_seed`/`rng_next`/`rng_value`/`rng_uniform01` — with **no language bitops** and **no record returns**.
The bit-twiddling lives in the VM builtin (`eval_math_call` + `splitmix64_mix`, wrapping arithmetic explicit);
the `.ig` boundary stays explicit-state. SplitMix64 splits naturally into an additive `rng_next` + a stateless
`rng_value`, which is *why* the record return (`RngInt{rng,value}`) was unnecessary — and there is no
record-returning stdlib builtin precedent anyway (verified). Integer is `i64` carrying `u64` bits
(reinterpreted, opaque); `uniform01` = top-53-bits / 2^53 ∈ [0,1), always finite.

**Single-source dispatch** (`eval_math_call`) gives OP_CALL + eval_ast/HOF parity for free; OP_CALL mirror list
extended; typecheck arm returns Integer/Float with `OOF-RAND1` (arity) / `OOF-RAND2` (non-Integer).
`STDLIB_VERSION`+`igniter-stdlib` bumped 0.1.2→0.1.3.

**Proof:** `stdlib_random_tests` 6 passed — golden seed-0 stream (first u64 = canonical SplitMix64
`0xE220A8397B1DCDAF`), same-seed-identical, different-seeds-differ, uniform01∈[0,1) finite+deterministic,
arity/type errors, and `first_sample_through_compiler_vm` (real `Compiler`→`VM::execute`). Math parity intact
(math/hof/det/nbody 6/7/5/5); version guard green; authored `.ig` compiles (status ok), bad-arg → OOF-RAND2;
`git diff --check` clean. Proof doc: `lab-docs/lang/lab-stdlib-random-prng-without-bitops-p2-v0.md`.

**Authority boundary held:** no ambient `random()`, no crypto/entropy claim; seed is data → replay-safe;
algorithm lock-pinned via `STDLIB_VERSION`. True entropy stays a host capability (deferred). **Next:**
`LAB-STDLIB-RANDOM-PROBABILITY-HELPERS-P3` (`uniform_int`/`bernoulli`/`categorical`) +
`LAB-STDLIB-INTEGER-BITOPS-READINESS-P1`. Emergence: Kuramoto loop (P12) can now seed ω deterministically.

## Proof doc requirements

Include:

- live bitops absence and why it is not solved here;
- algorithm choice and constants;
- signed/unsigned mapping policy;
- JSON/value shape of returned RNG records;
- golden sequence;
- replay/authority boundary;
- host entropy deferred path;
- exact commands/counts.

## Closed scope

- No bitwise/shift operators in the language.
- No crypto RNG, UUID, nonce, token generation.
- No distribution helpers (`bernoulli`, `normal`, `categorical`) unless a tiny `uniform_int` falls out naturally
  and is explicitly justified.
- No Monte Carlo engine.
- No qemu cross-arch proof unless already trivial.
- No canon claim.

## Next

- `LAB-STDLIB-RANDOM-PROBABILITY-HELPERS-P3` — `bernoulli`, `uniform_int`, maybe weighted categorical over the
  explicit PRNG.
- `LAB-STDLIB-INTEGER-BITOPS-READINESS-P1` — bitwise functions/operators as a separate language/stdlib topic.
