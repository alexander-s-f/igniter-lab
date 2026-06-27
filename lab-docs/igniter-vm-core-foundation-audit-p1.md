# IGNITER-VM-CORE-FOUNDATION-AUDIT-P1 - fresh verify-first audit of the VM (determinism, numerics, termination, capability)

Status: OPEN - findings (no code changed)
Lane: igniter-lab / lang / igniter-vm / foundation-hardening
Type: audit / fresh verify-first
Date: 2026-06-26
Skill: idd-agent-protocol

## Onboarding

Lab/frontier evidence, not authority. Code-first verify-first audit of `igniter_vm`
(Rust, ~12.3k LOC src; `vm.rs` 6325 is the bulk). 5 parallel subsystem audits +
direct reads of `IMPLEMENTED_SURFACE.md` and `value.rs`. **Several crashes were
REPRODUCED** against the debug binary (overflow-checks on). Do NOT lean on PROPs;
the code is truth. Classify BLOCKER / PROBLEM / INSIGHT; name high-leverage levers.

## Executive Decision

```text
decision=AUDIT - the VM is the most mature of the four crates and the determinism THESIS holds on the headline surface; the blockers are concentrated in (a) reproduced crashes, (b) Decimal silently breaking the same determinism it elsewhere guarantees, (c) no real termination guarantee, (d) a forgeable capability root-of-trust
severity=9 BLOCKERS (5 reproduced crashes/OOM/SIGABRT, Decimal determinism-break + scale-naive eq, no global step budget, attacker-controlled grants, forgeable passport)
good_news=VERIFIED SOLID: det_sin/cos/ln/exp/tan total-over-finite (libm, never NaN/Inf), SplitMix64 PRNG integer-only golden-vector-correct, BTreeMap record ordering, deterministic float->text, robust Unicode, fail-closed SIR load, correct FFI lifecycle, checked ipow/mod/abs
root_cause=same pattern as the other 3 audits - the declared/model layer is right, ENFORCEMENT is thin/mislocated (math.ig "checked never wraps" but infix ops wrap; "authority is a typed value" but runtime uses a bare string + caller-declared map; termination declared but enforced by nobody)
keystone=three small sweeps: checked_* on the ~12 infix arithmetic sites; one global step counter + an eval_ast depth guard; i128-exact Decimal compare/eq
next=IGNITER-VM-CHECKED-ARITH-AND-DEPTH-P2 + IGNITER-VM-RUNTIME-TERMINATION-BUDGET-P2 + IGNITER-VM-DECIMAL-EXACT-P2 + IGNITER-VM-CAPABILITY-TOKEN-P2
architectural_decision_needed=yes - make termination a runtime property (global budget); make the capability an unforgeable value + sign the passport
```

## GOOD NEWS — verified solid (lead with it; this is load-bearing)

The determinism thesis is **real where it counts**, confirmed in code:
- **`det_sin/det_cos/det_ln/det_exp/det_tan`** route through vendored `libm` 0.2.16
  (pinned, never `std`), and guard non-finite **input AND result** → a deterministic
  error, **never NaN/Inf** (`vm.rs:3735/3747/3758/3772`). `det_sqrt` uses
  `f64::sqrt` — fine, IEEE-754 mandates sqrt correctly-rounded (cross-arch identical).
  **Totality claim holds.**
- **SplitMix64 PRNG** is integer-only with canonical constants (`vm.rs:3866`),
  golden seed-0 vector matches reference, `rng_uniform_int` uses multiply-high (no
  modulo bias, no overflow), `uniform01` always finite, **no OS randomness anywhere**.
- **No nondeterminism in the compute core:** `Value::Record` is a `BTreeMap`
  (`value.rs:15`) → deterministic output key order; no `HashMap`-into-output, no
  `SystemTime`/`Instant` in the deterministic path (only in harness/timing code);
  Float→text uses std `flt2dec` (correctly-rounded ties-even, `-0.0` normalized).
- **Robust elsewhere:** Unicode rune/byte/grapheme ops clamp (no panic); SIR load is
  fail-closed at the top level; the FFI lifecycle is correct (no leak/double-free);
  `ipow`/`mod`/`abs` use `checked_*`; conditions error on non-Bool (no truthiness
  footgun); mixed-type operators error (no silent cross-type coercion).

The VM is the strongest of the four crates. The blockers below are sharp but
localized — and several are the cruel irony that the *hard* part (transcendental
determinism) is right while an *easy* part (Decimal ordering) silently breaks it.

## Root cause (the recurring pattern, 4th audit running)

**The declared/model layer is right; enforcement is thin or mislocated.** `math.ig`
declares "checked, never wraps" → the infix `+ - *` operators wrap (B-A1). The
capability model says "authority is a typed value passed explicitly" → the runtime
passes a bare string and trusts a caller-declared map (B-D1). Termination is a
declared loop-class contract → it is enforced by neither compiler nor VM (B-C1).
Same shape as the TBackend, compiler, and stdlib audits — here at higher maturity.

## BLOCKERS

### A. Crashes / OOM (REPRODUCED)

**B-A1. Integer `+`/`-`/`*` overflow → panic (debug) / silent wrap (release).**
Plain `i64` ops, no `checked_*`, across all three dispatch tables: bytecode
`vm.rs:411/449/485`, eval_ast `:4108/4136/4162`, unified `:5909/5939/5967`.
REPRODUCED: `i64::MAX + 1` → `panicked at vm.rs:411: attempt to add with overflow`.
Release wraps silently → **wrong financial answer in a Decimal-exact VM**.
Contradicts `math.ig` "checked, never wraps" (which the named `ipow`/`mod` DO honor).

**B-A2. `i64::MIN / -1` and unary `-i64::MIN` panic.** The DIV guard only checks
`== 0` (`vm.rs:527`); NEG has no `checked_neg` (`vm.rs:2777, 4355`). REPRODUCED:
`panicked at vm.rs:527: attempt to divide with overflow`.

**B-A3. `eval_ast` native-stack recursion → SIGABRT (uncatchable).** `eval_ast`
(`vm.rs:3961`, `Box::pin`) and `Value::from_json`/`to_json` (`value.rs:51/101`)
recurse once per nesting level with **no depth guard**; `MAX_CALL_DEPTH=64` bounds
only contract/`def` calls, not expression depth. REPRODUCED: depth-200k nested `+`
in a lambda body (reachable via `map`/`filter`/`fold`) → `stack overflow, aborting
(SIGABRT)`; `catch_unwind` cannot recover. **Aborts the whole process**, not one
request — the most severe finding.

**B-A4. Unbounded `range(start, end)` → OOM.** `for i in start..end { push }` with
no size cap, program-controlled bounds (`vm.rs:1878, 4580`). Loop-fuel does not
protect it (eager vector build). REPRODUCED: `range(0, 50_000_000)` allocates 50M
`Value`s; a hostile bound is a guaranteed OOM.

### B. Decimal — determinism break + correctness

**B-B1. Decimal comparison routes through lossy, platform-dependent f64 — BREAKS
cross-arch determinism.** `>`/`<`/`>=`/`<=` and `min`/`max` do
`da.to_f64() > db.to_f64()` (`vm.rs:574` + `1823/1837/3181/5346/5360`), where
`to_f64 = value as f64 / 10f64.powi(scale)` — `value as f64` loses precision past
2^53 and `powi` is not guaranteed correctly-rounded/identical across architectures.
Proven: `Decimal{9007199254740993,0}` compares **equal** to `{…992,0}` and `a > b`
returns `false` when mathematically `true`. Two near-equal decimals can order
differently on x86_64 vs aarch64/riscv64 — **the exact cross-arch bit-identity the
thesis rests on.** The headline det math is solid; Decimal ordering silently breaks
the same guarantee. Fix: i128 scale-aligned integer compare, never f64.

**B-B2. Decimal equality is scale-naive + arithmetic inherits the stdlib bugs.**
`==`/`!=` use structural `PartialEq` (`vm.rs:550`), so `decimal(100,2)` (1.00) `!=`
`decimal(10,1)` (1.0) `!=` `decimal(1,0)` (1) — mathematically-equal decimals
compare unequal. And the `decimal(v,s)` builtin (`vm.rs:1086`) makes the stdlib
`Decimal` bugs reachable from `.ig`: `add`/`sub`/`mul` wrap, `mul` scale u32-overflow,
`div` truncates to scale 0 (`10.00/3.00 = 3`). (Per the stdlib audit.)

### C. Termination — declared but enforced by nobody

**B-C1. No global step/instruction budget in the bytecode VM.**
`execute_with_grants` (`vm.rs:321`) loops `while ip < total` with **no** step
counter; `OP_JMP` permits an unbounded backward jump (only bounds-checked,
`vm.rs:2817`). The only bounds are per-loop fuel (`LoopFrame.fuel`) and
`MAX_CALL_DEPTH=64`. Combined with the compiler audit (FuelBounded "runtime-trusted";
`decreases` shrinkage statically unverified), **termination is a compiler-only
convention, not a runtime guarantee**: compiler-trusts-runtime + runtime-trusts-
compiler = a gap. `decreases` shrinkage is checked NOWHERE. `max_steps==0` means
unbounded (`fuel=u64::MAX`, `vm.rs:3332`). ServiceLoop doesn't actually loop at
runtime (one step per process run; "stoppable" only by the absence of a scheduler).

### D. Capability / security — forgeable root of trust

**B-D1. The capability root-of-trust is attacker-controlled.** `active_grants` is
deserialized from the program's own `--inputs` JSON (`main.rs:767`) — the caller
declares its own authority. The capability "value" is a bare string name
(`vm.rs:346`); authority lives entirely in a host-side `resolved_grants` map
populated from untrusted input. The VM **never consults the effect/capability
declaration at runtime** — effects are not runtime-checked; a crafted SIR can grant
itself IO with `{read_allowed:true, write_allowed:true, …}`. (The no-passport path
*does* fail closed — `vm.rs:918` — but only because the map is empty.)

**B-D2. The passport is forgeable — no signature.** `passport.rs:186` compares
`passport.artifact_digest` to `manifest.artifact_hash`, both read from the same
attacker-controlled `igapp_dir`; edit both to agree → passes. No HMAC, signature,
expiry, nonce, issuer, or revocation anywhere (`passport.rs`). It enforces only
delegation monotonicity (sub-grant narrowing), and even that via lexical (non-
canonical) path containment (`passport.rs:61`, symlink-bypassable). Given B-D1, the
whole chain is a no-op.

## PROBLEMS

- **Float `+`/`*` overflow → Inf → silently `null` in output** (`value.rs:106`
  maps non-finite to JSON null); unlike `det_*` and Float `DIV` (guarded), ADD/MUL
  (`vm.rs:412/486`) are not — a non-finite result vanishes instead of erroring.
- **Fast `sin`/`cos`/`sqrt` (non-`det_`) use platform `f64::sin/cos`**
  (`vm.rs:3707`) — not cross-arch, pass NaN/Inf to the null collapse; same dispatch
  namespace as `det_*` (footgun). Documented as the "P2 fast path."
- **Collection `min`/`max` over mixed/unhandled types silently picks wrong**
  (`_ => false`, `vm.rs:1842`) — returns first-seen element, no error (unlike the
  binary operators); also accept NaN/Inf (no `finite()` guard); `sum` wraps.
- **`avg` truncates** (integer division, drops remainder) (`vm.rs:1761/1765`).
- **Three duplicated binary-op dispatch tables** (bytecode / eval_ast / unified) —
  identical only by hand-sync; a parity hazard worth collapsing (~600 lines).
- **eval_ast missing `loop_node`/`service_loop_node` arms** (construct-coverage
  divergence vs bytecode; currently unreachable but a real asymmetry — and
  `IMPLEMENTED_SURFACE.md` confirms `batch_importer` is red because eval_ast lacks
  `variant_construct`).
- **`write_text` embeds `SystemTime::now()` + `Uuid::new_v4()` into the program-
  visible result** (`io.rs:366`, `vm.rs:970/1056`) → IO is nondeterministic, breaking
  replay; inconsistent with other obs IDs which use `sha256_hex`.
- **Only `read_text`/`write_text` are wired** in the VM; `read_json`/`write_json`/
  `exists`/`list_dir` stdlib FFI exports are dead (`vm.rs:908/990` only).
- **`tbackend.rs:127` allocates a server-controlled length** (`vec![0u8; resp_len]`,
  up to ~4 GiB) with no frame cap → OOM from a hostile/desynced ledger over plain TCP.

## INSIGHTS

- **I1. The VM is the crown jewel — the determinism thesis is real on the headline
  surface.** That makes B-B1 (Decimal compare via f64) the sharpest finding: the
  hard part (transcendentals) is right; an easy part (decimal ordering) silently
  breaks the same cross-arch guarantee.
- **I2. Same "aspirational-at-enforcement" pattern as all three prior audits**, at
  higher maturity: checked-never-wraps (declared) vs wrapping operators; typed-value
  authority (declared) vs bare-string + caller map; loop-class termination (declared)
  vs no runtime budget; passport trust (implied) vs forgeable.
- **I3. The bytecode VM is authoritative; `eval_ast` is a closure sub-interpreter**
  (not peers) — confirmed by `IMPLEMENTED_SURFACE.md` and the dispatch entrypoints.
  The codebase is already drifting toward structural unification
  (`call_contract_value` single-sourced; shared Tier-1 math fn) — leaning in makes
  "eval_ast↔bytecode parity" a fact, not a test obligation.
- **I4. A cross-arch golden-bit CI gate is latent in the tests.**
  `stdlib_math_det_tests.rs` pins `f64::to_bits`; `stdlib_random_tests.rs` pins the
  SplitMix64 stream. Running the SAME suite under qemu aarch64/riscv64 turns the
  determinism *claim* into a *proof* with almost no new code — directly serving the
  emergence line and the embedded-swarm (riscv64/ESP32) readiness.

## SUPER-COOL (high-leverage)

- **S1. One `checked_*` sweep (~12 infix sites) closes B-A1/B-A2 AND honors
  `math.ig`'s "checked, never wraps".** The exact pattern already exists
  (`num_abs`/`ipow`/`mod`). Highest safety-per-line; also kills the release-mode
  silent-wrong-answer in a money VM.
- **S2. One global `steps_executed` counter (~5 lines) makes termination a real
  RUNTIME property** independent of the compiler (B-C1) — subsumes per-loop fuel, the
  backward-jump guard, and any future service scheduler. The guarantee the system
  currently only pretends to have.
- **S3. A symmetric `EVAL_DEPTH` guard in `eval_ast` (+ depth in `from_json`) turns
  the uncatchable SIGABRT (B-A3) into a catchable `OOF-DEPTH` error** — one malformed
  SIR no longer aborts the host. Essential for the embedded-swarm (a flash-once
  micro-runtime must never abort on hostile peer input). Pair with a
  `MAX_COLLECTION_ELEMENTS` budget shared by `range`/`PUSH_ARRAY`/HOFs (B-A4).
- **S4. Exact i128 Decimal compare + scale-normalized equality** (one `decimal_cmp`/
  `decimal_eq`, 6 sites) — fixes B-B1 (determinism) + B-B2 (equality), makes
  `1.5 == 1.50`, gives a correct `Decimal` `Ord`, and removes the f64 precision
  ceiling. Turns a determinism liability into a showcase: "exact decimals,
  bit-identical everywhere."
- **S5. Capability as an unforgeable runtime token + a signed passport.** Replace
  `Value::String(name)` with `Value::Capability(Arc<Grant>)` minted only at boot from
  a *signed* (HMAC/ed25519) passport — closes B-D1+B-D2 and finally matches "authority
  is a typed value" in the runtime, not just on paper. Ties to the embedded-swarm
  "capability = bit-identity path."
- **S6. Cross-arch golden-bit CI under qemu** (I4) + **collapse the 3 dispatch
  tables to one** (parity by construction) + **determinize IO receipts** (content/seq
  IDs, not `now()`/`uuid`) — three independent wins that each harden the determinism
  story end-to-end.

## Keystone recommendation

- **IGNITER-VM-CHECKED-ARITH-AND-DEPTH-P2** — `checked_*` sweep (S1) + `eval_ast`
  depth guard + collection budget (S3). Closes the 5 reproduced crashes/OOM.
- **IGNITER-VM-RUNTIME-TERMINATION-BUDGET-P2** — global step counter (S2). Makes
  termination a runtime guarantee.
- **IGNITER-VM-DECIMAL-EXACT-P2** — i128 compare/eq (S4). Closes the determinism
  break + fixes equality.
- **IGNITER-VM-CAPABILITY-TOKEN-P2** — capability value + signed passport (S5).

The determinism core is sound; the work is **hardening the edges to the same
standard the det-math already meets** — not a redesign.

## Boundary / not covered

Lab evidence only; no code changed. The determinism *claims* are verified in code
but the **cross-arch bit-identity proof** (running the golden-bit suite under qemu
aarch64/riscv64) is latent, not yet executed — that is the natural follow-up that
would upgrade "claim" to "proof." The compiler/stdlib that feed this VM were audited
separately (see the sibling `igniter-compiler-` and `igniter-stdlib-` audit docs in
`lab-docs/`).
