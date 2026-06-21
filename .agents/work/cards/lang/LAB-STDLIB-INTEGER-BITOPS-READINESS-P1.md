# LAB-STDLIB-INTEGER-BITOPS-READINESS-P1 — integer bit operations without rushing syntax

Status: CLOSED
Lane: standard / stdlib numeric / language surface
Type: readiness / design
Delegation code: OPUS-STDLIB-INTEGER-BITOPS-READINESS-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

The random/probability wave found a real surface gap: `.ig` has no bitwise/shift operators in the lexer/parser.
PRNG/hash/integer algorithms often need `xor`, `and`, shifts, and wrapping arithmetic.

This is not automatically a lexer emergency. Adding `^`, `&`, `|`, `<<`, `>>` as operators touches grammar,
precedence, typechecker, VM, diagnostics, and possible future `^`/power meaning. A stdlib-function surface may
be safer first.

## Goal

Decide the first bit-operations surface for Integer algorithms:

1. stdlib functions first (`bit_xor(a,b)`, `bit_and(a,b)`, `bit_or(a,b)`, `shl(a,n)`, `shr(a,n)`, maybe
   `rotl`/`rotr`), or
2. language operators now, or
3. defer because PRNG can hide bitops behind builtins.

No production code changes in this card.

## Verify first

- Lexer/parser/operator tables: confirm actual absence/presence of `^`, `&`, `|`, `<<`, `>>`.
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` numeric diagnostic conventions.
- `lang/igniter-vm/src/vm.rs` Integer representation and overflow behavior.
- `apps/igniter-apps/bloom_filter/*` hash pressure.
- random PRNG readiness/implementation cards.
- math P6/P7/P8 docs for integer numeric direction.

## Questions to answer

1. Is bitop pressure immediate outside PRNG internals?
2. Should v0 expose functions before operators?
3. What exact operations are needed first?
   - `bit_and`, `bit_or`, `bit_xor`, `bit_not`
   - `shl`, `shr`
   - `rotl`, `rotr`
   - wrapping add/mul?
4. What is the Integer domain?
   - signed i64 only
   - treat as u64 bit-pattern
   - reject negative inputs for shifts/bitops
5. What is right-shift semantics?
   - arithmetic shift
   - logical shift via u64 mapping
6. What are shift-count rules?
   - `0 <= n < 64`; otherwise runtime/domain error?
7. Should diagnostics use OOF-MATH* or new OOF-BIT* rules?
8. Should operators be deferred until function semantics are proven?
9. How does this interact with future `pow` / `^` spelling?
10. What implementation card should follow, if any?

## Candidate surfaces to compare

At least compare:

1. **Stdlib functions first** — boring, explicit, no precedence/parser risk.
2. **Language operators now** — ergonomic, but wider grammar/syntax commitment.
3. **No public bitops** — keep PRNG/hash as opaque builtins until app pressure appears.
4. **Separate `UInt64` type** — precise but likely too large for v0.

Bias: stdlib functions first, operators later only if repeated pressure proves ergonomics matter.

## Acceptance

- [x] Live lexer/parser absence confirmed with file references. (`lexer.rs`: no `^`/`<<`/`>>`; `&`/`|` logical only.)
- [x] At least three surface options compared. (4 in the table.)
- [x] Integer signed/unsigned semantics recommendation made. (`i64` as `u64` bit-pattern; total bitwise.)
- [x] Shift and overflow/domain policy proposed. (logical `shr`; `0≤n<64`→`OOF-BIT3`; wrapping via explicit `wrap_*`.)
- [x] Diagnostic taxonomy proposed. (`OOF-BIT1/2/3`.)
- [x] Operator-vs-function decision made. (**functions; operators deferred indefinitely**.)
- [x] Interaction with future `pow`/`^` addressed. (caret free; functions sidestep xor-vs-power.)
- [x] First implementation card named with acceptance matrix **+ explicit DEFER recommendation**. (`LAB-STDLIB-INTEGER-BITOPS-CORE-Pn`, gated on a consumer.)
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Decision: function surface DESIGNED, build DEFERRED — no public consumer today.** Verified live: `.ig` has
**no `^`/`<<`/`>>`** and `&`/`|` are logical-only (`lexer.rs`); the **caret `^` is entirely free**; Integer is
checked-not-wrapping. Pressure inventory found the random wave *surfaced* the gap but **nothing actually needs
public bitops**: the PRNG (P2) hid xor/shift/wrapping inside a native builtin, and `bloom_filter` — whose
header laments "no bitwise ops" — actually uses **multiplicative hashing + manual modulo** (needs `mod`, the
P8 work, not bitwise). Building now would be speculative generality.

**Shape when built = functions, not operators** (sidesteps grammar/precedence AND the free-`^` xor-vs-power
collision — `bit_xor` for xor, `ipow`/`powf` for power; never claim `^` prematurely). Designed surface:
`bit_and/or/xor/not`, `shl/shr` (**logical**, zero-fill; `shr` ≠ arithmetic ÷2^n), `wrap_add/wrap_mul`;
`i64`-as-`u64`-bit-pattern; shift count `0≤n<64` else `OOF-BIT3`; diagnostics `OOF-BIT1/2/3`. `rotl/rotr`
deferred within bitops.

**Deliverables:** readiness packet `lab-docs/lang/lab-stdlib-integer-bitops-readiness-p1-v0.md`; impl card
**`LAB-STDLIB-INTEGER-BITOPS-CORE-Pn`** named with acceptance matrix, **gated** on the first real consumer
(pure-`.ig` hash / bitset / checksum / flag-mask / user PRNG variant). No code. **Next:** hold the impl card
until that consumer appears; PRNG/hash bit-twiddling stays opaque in native builtins meanwhile.

## Required deliverable

Write `lab-docs/lang/lab-stdlib-integer-bitops-readiness-p1-v0.md` with:

- live parser/lexer evidence;
- pressure inventory;
- function-vs-operator decision;
- exact v0 operation list;
- integer/shift semantics;
- diagnostics;
- next implementation card if GO.

Close this card with a report.

## Closed scope

- No implementation.
- No parser/lexer changes.
- No PRNG implementation.
- No crypto.
- No broad numeric tower.
- No canon claim.
