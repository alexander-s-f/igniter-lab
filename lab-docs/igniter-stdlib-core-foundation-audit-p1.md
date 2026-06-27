# IGNITER-STDLIB-CORE-FOUNDATION-AUDIT-P1 - fresh verify-first audit of the stdlib runtime crate

Status: OPEN - findings (no code changed)
Lane: igniter-lab / lang / igniter-stdlib / foundation-hardening
Type: audit / fresh verify-first
Date: 2026-06-26
Skill: idd-agent-protocol

## Onboarding

Lab/frontier evidence, not authority. Code-first verify-first audit of
`igniter_stdlib` (Rust, **928 LOC src** — small). Read in full first-hand (no
subagents needed at this size). Do NOT lean on PROPs; the code is truth. Classify
BLOCKER / PROBLEM / INSIGHT; name high-leverage opportunities.

## Scope clarity (the first verify-first finding)

**This crate is NOT "the standard library."** The real stdlib is layered:
- the **contract surface** (String/Text/Integer/Float/Decimal/Collection
  signatures) is baked into the **compiler** (`typechecker/stdlib_calls.rs`, audited
  separately);
- the **`.ig` declarations** live in `igniter-stdlib/stdlib/*.ig`
  (`math.ig`, `random.ig`, `core/{string,option,result,datetime}.ig`, …);
- **execution** (incl. the determinism-critical `det_sin/det_cos/det_ln/det_exp/
  det_tan` and the SplitMix64 PRNG) lives in the **VM** (`igniter-vm`), NOT here
  (grep: `fn det_*` only in `igniter-vm/tests/`);
- production capability-IO lives in **`igniter-machine`**.

This Rust crate is a **small set of runtime helpers + FFI**: `io.rs` (capability
IO, 637), `decimal.rs` (fixed-point Decimal, 73), `lib.rs` (Decimal C-ABI, 97),
`temporal.rs`/`collections.rs` (small helper candidates). File headers call them
"candidate" / "experimental."

**LIVE confirmation (the gating question — answered):** the VM links this crate
(`igniter-vm/Cargo.toml:24`) and **actually calls** it on the execution path:
`use igniter_stdlib::decimal::Decimal` (`vm.rs:7` → all VM decimal arithmetic),
and `igniter_stdlib::io::stdlib_io_read_text`/`stdlib_io_write_text`
(`vm.rs:937, 1022` → `stdlib.IO.read_text`/`write_text`). So the blockers below
are **live in VM execution**, not dead candidates. (Note: the io FFI also exports
`read_json`/`write_json`/`exists`/`list_dir`, but the VM currently routes only
`read_text`/`write_text` — the rest is unwired surface.)

## Executive Decision

```text
decision=AUDIT - the .ig surface is determinism-disciplined and well-designed, but the LIVE Rust runtime helpers do not honor it: the money Decimal wraps/truncates/mis-orders, and the IO sandbox is symlink-escapable
severity=4 LIVE money-correctness BLOCKERS (decimal) + 2 LIVE sandbox-escape BLOCKERS (io)
root_cause=declared-vs-implemented gap - math.ig declares "checked, never wraps / total over finite"; decimal.rs uses unchecked i64 arithmetic, truncating division, and a derived Ord that compares raw fields
good_news=the .ig declarations (random.ig explicit-state SplitMix64 no-ambient-random; math.ig det_* "never NaN/Inf", checked integers, no implicit coercion) are genuinely excellent; the det math + PRNG impl live in the VM (separate audit)
keystone=make Decimal a real money type (i128 checked + explicit rounding + scale-normalized Eq/Ord) and replace the lexical+substring sandbox with canonical-parent containment + no-follow
next=IGNITER-STDLIB-DECIMAL-MONEY-SAFE-P2 + IGNITER-STDLIB-IO-SANDBOX-HARDEN-P2
architectural_decision_needed=no - these are correctness fixes to honor an already-declared contract
```

## Root cause (one)

**Declared-vs-implemented gap.** `math.ig` declares the money/numeric contract
("`Decimal[S] + Decimal[S] -> Decimal[S]`", integer basics "checked, never wraps",
transcendentals "total over finite values, never NaN/Inf"). The **`.ig` surface is
right**; the **live Rust runtime helper (`decimal.rs`) is not** — it wraps on
overflow, truncates on division, and derives a semantically-wrong ordering. Same
"aspirational-at-the-enforcement-layer" pattern as the TBackend and compiler
audits, here as a contract/impl mismatch.

## BLOCKERS

### Decimal (money type) — LIVE via `vm.rs:7`

**B-D1. `add`/`sub`/`mul` overflow silently (unchecked i64).**
`self.value + other.value` (`decimal.rs:38, 49`) and `self.value * other.value`
(`:54`) are plain i64 ops — panic in debug, **wrap silently in release**. A money
type that wraps a large sum to negative is a correctness blocker. No
`checked_add`/`checked_mul`/saturating path. (The runtime `add`/`sub` *do* re-check
scale equality — good defense-in-depth — but not magnitude.)

**B-D2. Derived `Ord`/`PartialOrd` compares raw `(value, scale)` → wrong numeric
order.** `#[derive(... PartialOrd, Ord)]` (`decimal.rs:6`) compares `value` then
`scale` lexicographically. `Decimal{value:10, scale:1}` (= 1.0) compares **greater
than** `Decimal{value:5, scale:0}` (= 5.0). Any sort / `min` / `max` / `<` over
Decimals of differing scale is wrong. Likewise derived `Eq`: `Decimal{1,1}` (0.1) ≠
`Decimal{10,2}` (0.10). *(Confirm whether the VM's comparison ops route through this
derive or via `value.rs::as_decimal`; the derive itself is unsound regardless.)*

**B-D3. `div` truncates and collapses scale → catastrophic precision loss.**
`self.value / other.value` (`decimal.rs:69`) is truncating i64 division; result
scale = `s1 - s2`. For equal scales (the common case) the result scale is **0** —
`10.00 / 3.00` → `Decimal{3, 0}` = `3`, not `3.33`. No rounding mode, no
precision preservation. Money division is effectively broken.

**B-D4. `mul` scale grows unbounded (`s1 + s2`), value overflows fast.** Repeated
multiplication grows scale (2,2→4→8…) while `value = v1*v2` overflows i64 within a
few multiplies (`decimal.rs:53-55`). No rescale/clamp. Compounds B-D1.

### IO capability sandbox — LIVE via `vm.rs:937, 1022`

**B-I1. Symlink escape on WRITE to a new file.** Path validation is lexical
(`clean_path`, `io.rs:21-42`, resolves `..` textually, never resolves symlinks),
then `starts_with(sandbox)`. The canonical filesystem re-check runs **only `if
resolved_path.exists()`** (`io.rs:122`). Writing a *new* file through a symlinked
directory inside the sandbox (`out/link -> /etc`, write `out/link/passwd`) passes
the lexical check, the target doesn't exist → canonical check skipped → `fs::write`
follows the symlink and **escapes the sandbox** (`io.rs:363`). Sandbox-escape
blocker for `stdlib.IO.write_text`.

**B-I2. The sandbox gate is a substring match on a hardcoded repo path.**
`if !abs_sandbox_str.contains("/igniter-stdlib/out")` (`io.rs:80`). (a) `contains`
matches `…/igniter-stdlib/outsider`, `…/output`, `…/out_evil` — substring, not a
path-component/prefix check. (b) It hardcodes the lab repo layout into the security
boundary, so the capability cannot be deployed anywhere else (fails closed
elsewhere — safe but unusable). The boundary should be a canonical-prefix check
against a capability-supplied root, not a substring of a fixed path.

## PROBLEMS

- **`stdlib_decimal_mul` returns `void`** (`lib.rs:59-74`) — no error code, so
  overflow (B-D1/D4) is invisible to the FFI caller, inconsistent with add/sub/div
  (which return i32). The unsafe out-param is written with the wrapped value.
- **`Decimal::from_f64` reintroduces lossy float into the money type**
  (`decimal.rs:21-28`): `(val * factor).round() as i64`; `as i64` saturates an
  out-of-range float to `i64::MAX` silently (NaN→0). A float→money path at all
  cuts against the language's "no implicit Float→Decimal" stance.
- **IO write receipts embed `SystemTime::now()`** (`io.rs:366, 521`) → ambient
  wall-clock in the stdlib write result, making IO non-reproducible. Same Law-6
  ("no ambient now()") violation pattern as TBackend — and directly at odds with
  `random.ig`'s own "NO ambient random()" discipline two files over.
- **App-domain logic baked into the language stdlib**: `temporal.rs`
  `compute_availability`/`build_snapshot` are technician-availability (SparkCRM)
  functions living in `igniter_stdlib` — the same drift the compiler audit found in
  `stdlib_calls.rs`, confirmed at the runtime layer.
- **`collections::range(start, end)` is unbounded** (`collections.rs:7`) →
  OOM on a large range (`range(0, 10_000_000_000)` allocates billions of `Value`s).
  No size cap.
- **`allowed_absolute_paths` fully bypasses the sandbox gate** (`io.rs:88-110`) —
  by design (explicit mapping, canonicalized match is correct), but worth stating:
  the sandbox boundary governs relative paths only; absolute access rests entirely
  on the capability's allowlist.

## INSIGHTS

- **I1. The `.ig` surface is the strong part and is genuinely excellent.**
  `random.ig`: explicit-state SplitMix64, **no ambient `random()`**, integer-only ⇒
  bit-identical cross-arch by construction; entropy/crypto is a host capability.
  `math.ig`: a clear two-tier model — fast platform `sin/cos/sqrt` (explicitly *not*
  a determinism claim) vs deterministic `det_*` (vendored libm, golden-bit lock,
  "total over finite values, never NaN/Inf"), integer roots "checked, never wraps,"
  no implicit coercion (`OOF-MATH3`). This is determinism-first design done well —
  the contract is right.
- **I2. The gap is the Rust helper, not the design.** The money/numeric contract is
  correctly *declared* (math.ig) and *type-checked* (compiler), but the live
  *runtime* (`decimal.rs`) silently violates it (B-D1..D4). The language promises
  money-safety at two layers and breaks it at the third.
- **I3. Scope honesty:** the determinism-critical surface (`det_*`, PRNG) is in the
  **VM**, not here — so the cross-arch bit-identity claims (STDLIB_VERSION 0.1.7)
  must be audited against `igniter-vm` (the vendored-libm golden-bit lock, the
  "never NaN/Inf" totality, the SplitMix64 step). That is a **separate, higher-value
  audit** this one does not cover.
- **I4. `io.rs` is a candidate IO surface; production capability-IO is in
  `igniter-machine`** (passport/sandbox/audit, per the machine-IO line). The two
  sandbox models should be reconciled — or the VM should route `stdlib.IO` through
  the hardened machine executor rather than this lexical-sandbox candidate.

## SUPER-COOL (high-leverage)

- **S1 (keystone-A). Make `Decimal` a real money type.** `i128` (or a bigint)
  with **checked** arithmetic (error, not wrap), an **explicit rounding mode** on
  `div` that preserves scale, and **scale-normalized `Eq`/`Ord`** (compare by
  rescaling to a common scale — drop the derive). Make `from_f64` explicitly
  fallible or remove it. One focused change makes the runtime finally honor
  `math.ig`'s declared contract. Closes B-D1..D4.
- **S2 (keystone-B). Robust, deployable sandbox.** Replace lexical `clean_path` +
  substring gate with: canonicalize the **parent** of the target, assert
  component-prefix containment under a **capability-supplied** root, and open with
  `O_NOFOLLOW` / check `symlink_metadata` — closing the write-through-symlink hole
  and the hardcoded-path coupling (B-I1/B-I2). Or route `stdlib.IO` through the
  `igniter-machine` executor (I4).
- **S3. Pin the declared `.ig` contracts to the impl with property/differential
  tests.** Turn math.ig's prose guarantees into executable invariants: "Decimal ops
  never wrap (checked) over a fuzz corpus", "`Ord` agrees with `to_f64` ordering",
  "det math never returns NaN/Inf over finite inputs", "SplitMix64 sequence is
  bit-identical across targets." The crate has `proofs/` (Ruby candidate proofs) —
  promote these to Rust property tests guarding the contract.
- **S4. Determinize the IO receipt** — drop `SystemTime::now()` from the write
  result (or move it behind an explicit clock capability), matching `random.ig`'s
  "no ambient" discipline, so IO results are reproducible/replayable.

## Keystone recommendation

- **IGNITER-STDLIB-DECIMAL-MONEY-SAFE-P2** — checked i128 + rounding + normalized
  Eq/Ord (S1). The single highest-value fix; money-safety is the crate's most
  load-bearing live surface.
- **IGNITER-STDLIB-IO-SANDBOX-HARDEN-P2** — canonical-parent containment + no-follow
  + capability-supplied root (S2), or converge on the `igniter-machine` executor.

The design (the `.ig` contracts) is sound; the work is making the **live runtime
honor it** — not a redesign.

## Boundary / not covered

Lab evidence only; no code changed. **Out of scope (separate, higher-value
audits):** the VM's `det_*`/libm golden-bit determinism + SplitMix64 PRNG impl
(`igniter-vm`), and the production capability-IO (`igniter-machine`). The `.ig`
files themselves are declarations (signatures), not implementations.
