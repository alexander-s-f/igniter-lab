# lab-stdlib-integer-bitops-readiness-p1-v0 — integer bit operations without rushing syntax

**Card:** `LAB-STDLIB-INTEGER-BITOPS-READINESS-P1` · **Type:** readiness / design (NO code)
**Status:** CLOSED (readiness) — decides the bit-operations surface. **Conclusion: design the function
surface now, but DEFER the build — there is no public consumer today** (PRNG solved bit-twiddling natively;
the one app that laments "no bitwise ops" actually needs *modulo*, addressed by P8, not bitwise). No code.

## Live lexer/parser evidence (Q-verify)

`lang/igniter-compiler/src/lexer.rs`:
- **`^` (caret): completely absent** — no `'^'` arm, no `Caret`/`Power`/xor token. The caret is **unclaimed**.
- **`<<` / `>>` shift tokens: absent** — no `Shl`/`Shr`.
- `&` (line ~361) and `|` (line ~381) exist only as **logical** `&&` / `||` (and a `Pipe` token for non-bitwise
  use); there is **no bitwise `&`/`|`**.
- **No power operator** (`**` or `^`) in lexer or parser.

So: `.ig` has **no bitwise/shift operators and no power operator**, and the caret is free. Confirmed.

`lang/igniter-vm/src/vm.rs`: Integer arithmetic is **checked** (`abs`→`checked_abs`); wrapping is only used
inside native builtins (the P2 PRNG used explicit `wrapping_add`/`wrapping_mul`). Wrapping arithmetic is **not
exposed** to `.ig` today.

## Pressure inventory — the decisive part

| Would-be consumer | Reality | Needs public bitops? |
|---|---|---|
| **PRNG (SplitMix64, P2)** | xor/shift/wrapping **hidden inside the native builtin**; `.ig` surface is scalar state-threaded | **No** — solved natively |
| **bloom_filter** | header laments "no modulo, no bitwise ops"; **actual algorithm is multiplicative hashing** (`31*key+17`, manual `mod(a,b)=a-(a/b)*b`) — uses `*`/`+`/`mod`, **not** xor/shift | **No** — it needs **modulo** (landing in P8 integer `mod`), not bitwise |
| hashing / bitsets / checksums / flag-masks / pure-`.ig` PRNG variants | hypothetical / future | would, but **none exists today** |

**Verdict:** the random wave *surfaced* the gap, but the only thing that actually needed bit-twiddling (the
PRNG) hid it natively, and the one app that mentions "no bitwise ops" really needed modulo. **There is no
concrete public consumer of bitwise ops right now.** Building a public bitop surface today would be
speculative generality — exactly the trap the card warns against.

## Surface options compared (≥3)

| # | Option | Verdict |
|---|---|---|
| 1 | **Stdlib functions** (`bit_xor(a,b)`, `shl(a,n)`, …) | **the right SHAPE when built** — boring, explicit, zero parser/precedence risk, matches the bare-name stdlib idiom |
| 2 | Language operators now (`^ & \| << >>`) | **rejected** — touches grammar/precedence/typechecker/VM/diagnostics AND prematurely claims the free `^` (xor vs power, Q9); no pressure justifies it |
| 3 | **No public bitops — keep them opaque in builtins until app pressure appears** | **the right STATUS now** — PRNG is native; no public consumer exists |
| 4 | Separate `UInt64` type | rejected — too large for v0; `i64`-as-bit-pattern suffices |

**Decision: shape = functions (option 1); status = defer (option 3).** When a real public consumer appears,
build the function surface below; never operators until repeated ergonomic pressure proves it.

## The function surface (designed, ready to build on first consumer)

Integer domain: **`i64` treated as a `u64` bit-pattern** (reinterpret, like the PRNG state) — total for
bitwise, no negative-rejection, sign bit included.

- **Bitwise (total):** `bit_and(a,b)`, `bit_or(a,b)`, `bit_xor(a,b)`, `bit_not(a)` — `(Integer,Integer)->Integer`.
- **Shifts (logical / zero-fill, matching the u64 bit-pattern model):** `shl(a,n)`, `shr(a,n)`.
  - **Right shift = logical** (zero-fill via the u64 mapping) — this is what hash/PRNG algorithms need
    (SplitMix64's `>> 30` is logical). Arithmetic shift (÷2^n) is better served by integer `div`; an explicit
    `ashr` can be added only if a consumer needs it.
  - **Shift count rule:** `0 <= n < 64`; otherwise a **runtime domain error** (Rust `<<`/`>>` on `u64` with
    `n>=64` is UB/panics → must be guarded). Negative `n` → error.
- **Wrapping arithmetic (adjacent, same "bit-pattern" world):** `wrap_add(a,b)`, `wrap_mul(a,b)` — the *other*
  half of the PRNG/hash need (overflow-tolerant integer math, distinct from checked `+`/`*`). Recommend
  including these in the same card; they are arguably more broadly useful than bitwise.
- **Deferred even within bitops:** `rotl`/`rotr` (rotations) — add only for a consumer that needs them (PCG,
  some hashes).

## Integer / shift semantics summary (Q4/Q5/Q6)

- Bitwise ops operate on the **two's-complement 64-bit pattern** (`i64` ↔ `u64` reinterpret); total.
- `shr` is **logical** (zero-fill); `shl` is logical (identical direction). Document loudly that `shr` is NOT
  arithmetic (÷2^n) — use integer `div` for that.
- Shift count must be `Integer`, `0 ≤ n < 64`; else a runtime domain error.

## Diagnostics (Q7)

New **`OOF-BIT*`** class (parallel to `OOF-MATH*`/`OOF-RAND*`):
- `OOF-BIT1` — arity (compile).
- `OOF-BIT2` — non-Integer argument (compile).
- `OOF-BIT3` — shift count out of `[0,64)` / negative (runtime domain error).

## `^` / `pow` interaction (Q9) — a strong argument for functions

The caret is **free**, and there are two competing future meanings: **xor** (C/Rust) vs **power** (some math
DSLs). **Functions-first sidesteps the fight entirely** — `bit_xor` for xor, `ipow`(P8)/`powf` for power, no
`^` operator. Recommendation: **do not claim `^` as an operator** until a deliberate, separate decision; keep
both meanings as named functions. This keeps the grammar uncommitted and avoids a later breaking reinterpretation.

## Recommendation

**DEFER the implementation** (no public consumer today), with the function surface above **designed and ready**.
Operators are rejected for the foreseeable future. The impl card is named and ready to fire on the first real
consumer (a pure-`.ig` hash, bitset, checksum, flag-mask, or a user-authored PRNG variant).

## First implementation card (named, GATED on a consumer)

**`LAB-STDLIB-INTEGER-BITOPS-CORE-Pn` — native integer bitops + wrapping arithmetic (build when a consumer appears).**

| Acceptance dimension | Target |
|---|---|
| Functions | `bit_and/or/xor/not`, `shl/shr` (logical), `wrap_add/wrap_mul`; `rotl/rotr` only if needed |
| Domain | `i64` as `u64` bit-pattern; bitwise total; shifts logical |
| Shift count | `0≤n<64` else `OOF-BIT3` runtime error |
| Wiring | native `eval_math_call` arms (OP_CALL + eval_ast parity, like P2 PRNG); `stdlib/bits.ig` decl |
| Diagnostics | `OOF-BIT1` arity, `OOF-BIT2` non-Integer, `OOF-BIT3` shift range |
| Tests | golden values (xor/and/shl/shr known), shift-range errors, parity through compiler→VM |
| Provenance | bump `STDLIB_VERSION` (surface change) |
| Operators | **none** — functions only |
| Scope | no operators, no `UInt64` type, no crypto, no rotations unless consumer-driven |

## Acceptance (this card) — mapping

- [x] Live lexer/parser absence confirmed with file references (`lexer.rs`: no `^`/`<<`/`>>`, `&`/`|` logical only).
- [x] ≥3 surface options compared (4 in the table).
- [x] Integer signed/unsigned recommendation (`i64` as `u64` bit-pattern; total bitwise).
- [x] Shift + overflow/domain policy (logical `shr`; `0≤n<64` → `OOF-BIT3`; wrapping via explicit `wrap_*`).
- [x] Diagnostic taxonomy (`OOF-BIT1/2/3`).
- [x] Operator-vs-function decision (**functions; operators deferred indefinitely**).
- [x] Interaction with future `pow`/`^` addressed (caret free; functions sidestep xor-vs-power).
- [x] First impl card named with acceptance matrix **+ explicit DEFER recommendation** (gated on a consumer).
- [x] No production code changes.

## Closed scope

No implementation; no parser/lexer changes; no PRNG implementation; no crypto; no broad numeric tower; no
canon claim.

## Next

Hold `LAB-STDLIB-INTEGER-BITOPS-CORE-Pn` until a concrete public consumer appears (pure-`.ig` hash / bitset /
checksum / flag-mask / user PRNG variant). Until then, PRNG/hash bit-twiddling stays opaque in native builtins.

---

*Lab readiness. 2026-06-21. `.ig` has no bitwise/shift operators and a free `^` (verified). The random wave
surfaced the gap, but the PRNG hid it natively and bloom_filter actually needs modulo (P8), not bitwise — so
**no public consumer exists today**. Decision: function surface (`bit_and/or/xor/not`, `shl/shr` logical,
`wrap_add/wrap_mul`) is **designed and ready** but the build is **deferred** until a real consumer; operators
are rejected indefinitely (keeps the free `^` uncommitted, xor-vs-power as named functions). Impl card named:
`LAB-STDLIB-INTEGER-BITOPS-CORE-Pn`.*
