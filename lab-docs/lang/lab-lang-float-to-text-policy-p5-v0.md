# lab-lang-float-to-text-policy-p5-v0

Card: `LAB-LANG-FLOAT-TO-TEXT-POLICY-P5`
Route: standard / language stdlib policy · Skill: idd-agent-protocol
Status: policy/decision packet (no implementation; no canon claim)
Date: 2026-06-26
Builds on: P4 readiness (`lab-lang-float-to-text-readiness-p4-v0`). Wave: P1 Integer (live) · P2 Decimal (live) · P4 readiness · **P5 policy (this)** · P7 impl (named below; P6 is the formatting-surface refresh).

> **Authority boundary.** Lab language surface (igniter-lab `lang/`, NOT canon). Policy only — no code, no
> implicit `to_text(Float)`, no locale/currency/grouping/exponent, no canon determinism claim. The four
> decisions below close the last gaps before implementation. **All Rust-behavior claims are verified locally
> (rustc 1.95.0), not from memory** — facts in §6.

---

## Policy table (the four decisions)

| # | Question | Decision | Why (one line) |
| --- | --- | --- | --- |
| 1 | Negative zero | **Normalize: any output whose rounded magnitude is zero emits *unsigned* zero** (`-0.0`→`"0.00"`, `-0.001`→`"0.00"`, `-0.4`→`"0"`). | Std preserves `-0` (verified); `"-0.00"` is a report wart that breaks naive equality/diff. Display already discarded magnitude → the zero's sign is meaningless to a reader. |
| 2 | Dynamic vs literal rounding | **Literal ≠ `"half_even"` → compile-reject (`OOF-TY0`); dynamic `String` → deterministic runtime reject *before* output.** Same stable message family. | Catch at compile time when knowable; fail-closed + deterministic at runtime otherwise. |
| 3 | Decimal precision bound | **`decimals ∈ 0..=17`** (else deterministic error). | 17 = f64 round-trip digit guarantee; covers science `{:.16}` with headroom; beyond 17 = binary-expansion noise (verified: `0.1` at `.20` → `…0555`). |
| 4 | Implementation route | **Direct `format!("{:.*}", decimals, x)` + tiny post-processing**, in one helper. **Defer** the shared `float_to_decimal` quantization helper. | Std `{:.N}` is verified correctly-rounded half-even + integer-based (cross-arch deterministic); post-processing is two trivial string ops. `float_to_decimal` waits on literal-scale typed `Decimal[N]` (P4 amendment). |

---

## 1. Negative zero (Q1) — normalize rounded-zero to unsigned

**Verified std behavior (§6):** Rust `{:.N}` is **sign-faithful even when the magnitude rounds to zero** —
`-0.0`→`"-0.00"`, `-0.001` at 2dp →`"-0.00"`, `-0.4` at 0dp →`"-0"`, `-0.04` at 1dp →`"-0.0"`.

**Decision: normalize.** When the rounded result is all-zero digits, emit **unsigned** zero (`"0"`, `"0.00"`,
…), dropping any leading `-`. Applies to both literal `-0.0` and small negatives that round to zero.

**Report/science tradeoff (named):**
- *Report side (wins):* `"-0.00"` is a wart — it confuses readers and makes two display-equal zeros
  string-unequal (breaks naive table diff / equality / dedup). A balance that rounds to zero is zero.
- *Science side:* IEEE `-0.0` carries a sign bit (direction-of-approach in some contexts). But `float_to_text`
  is a **display** function that has *already* discarded magnitude to `decimals`; the sign of a zero magnitude
  is not recoverable information for a reader. Science that needs the IEEE sign operates at the **value** level
  (a `sign`/`signbit` predicate on the raw `f64`), not on the formatted string. So normalizing loses nothing
  the display could carry.

(Non-zero negatives keep their sign normally: `-1.25`→`"-1.2"`.)

---

## 2. Dynamic rounding validation (Q2) — compile + deterministic runtime reject

v0 supports exactly one mode, `"half_even"`. Two enforcement layers, one message family:

- **Literal `rounding`** (a string literal in source): the **compiler rejects** any value other than
  `"half_even"` — `OOF-TY0`-class. Expected diagnostic (stable wording):
  `float_to_text: unsupported rounding mode "<x>"; v0 supports only "half_even"`.
- **Dynamic `rounding : String`** (a runtime value — e.g. from a field/compute): the **VM rejects**
  unsupported modes **deterministically, before producing any output** — same message string, routed through
  the same deterministic domain-error channel as non-finite (P4 §4; `vm.rs` det-error posture). The error is a
  pure function of the mode value (no nondeterminism, no partial output).

Rationale: the contract is "only `half_even` in v0"; making the *unsupported-mode* path fail-closed and
deterministic (not a silent fallback to some default) preserves the explicit-contract premise of the wave. The
single stable message lets a future card widen the accepted set by extending the allow-list, not changing the
shape.

---

## 3. Decimal precision bound (Q3) — `0..=17`

**Decision: `decimals ∈ 0..=17`.** Out-of-range (`< 0` or `> 17`) → deterministic domain error before output.

Justification (empirically grounded, §6):
- **17 is the f64 round-trip guarantee.** `{:.17}` of `PI` → `3.14159265358979312` carries the full
  round-trippable value; this is the standard "17 significant digits round-trips an f64."
- **Covers the science pressure with headroom.** `experiment.rs` formats at most `{:.16}`; `0..=17` includes
  it + 1.
- **Beyond 17 is binary-expansion noise.** Verified: `0.1` at `{:.17}` → `0.10000000000000001`, at `{:.20}` →
  `0.10000000000000000555`, at `{:.30}` → `0.100000000000000005551115123126`. Past ~17 fractional digits you
  expose the exact binary→decimal expansion (the f64 isn't really `0.1`), which is **misleading in a
  fixed-decimal report**. An "exact expansion" surface (hundreds of digits) is a different, out-of-scope tool.

The bound is on **fractional digits** (flat), not magnitude-relative significance — the simple, honest v0
rule. (A value like `1e-9` at 2dp is `"0.00"`; the user chose the precision.)

---

## 4. Implementation route (Q4) — direct `format!` + post-processing; defer `float_to_decimal`

**Decision: direct `format!("{:.*}", decimals, x)` wrapped in one validating helper.** Pipeline:

```text
float_to_text(x, decimals, mode):
  1. mode == "half_even"          else → deterministic error (§2)
  2. x.is_finite()                else → deterministic error (non-finite, P4 §4)
  3. 0 <= decimals <= 17          else → deterministic error (§3)
  4. s = format!("{:.*}", decimals as usize, x)     -- std: correctly-rounded, ties-to-even (VERIFIED §6)
  5. if s with '-','.','0' removed is empty: drop a leading '-'   -- negative-zero normalize (§1)
  → s
```

Why this route over the alternatives:
- **vs a custom rounding helper:** std `{:.N}` is **verified** correctly-rounded half-even and integer-based
  (`flt2dec`, no `libm`) → cross-arch deterministic. Reimplementing correct decimal rounding of an f64 is
  error-prone (the `2.675`/`1.005` representation cases, §6) — lean on the proven std path. Post-processing is
  two trivial deterministic string ops.
- **vs the shared `float_to_decimal` quantization helper:** **deferred.** It needs literal-scale typed
  `Decimal[N]` (P4 amendment — `Decimal[N]` requires a static `N`), which is unA designed. When designed,
  `float_to_decimal` can be built *on top of* this (`float_to_text` → parse digits → `Decimal{value, scale:N}`),
  so `float_to_text` is the foundation, not a duplicate.

**Determinism note (honest, no canon upgrade):** std's fixed-precision formatting guarantees *correctly
rounded* output (a documented contract, not an implementation accident), so the value is stable across Rust
versions and architectures. The impl card must still **pin exact outputs in a regression test** so a
hypothetical std change is caught, and any *public* cross-arch claim needs explicit x86_64+aarch64 evidence
(P4 §6). This card upgrades no canon determinism claim.

---

## 5. Future implementation card — `LAB-LANG-FLOAT-TO-TEXT-IMPL-P7`

**Surface:** `float_to_text(x:Float, decimals:Integer, rounding:String) -> String`, bare + `stdlib.string.*`,
single `eval_math_call` arm (the P1 pattern). Route per §4. `Integer`/`Decimal` `to_text` unchanged.

**Acceptance matrix:**

*Typecheck (`stdlib_to_text_tests.rs`, compiler):*
- accepts `float_to_text(1.5, 2, "half_even")` → `String`;
- rejects wrong arity / `x` not Float / `decimals` not Integer / `rounding` not String → `OOF-TY0`;
- rejects a **literal** unknown mode (`"half_up"`) with the §2 message;
- `Integer`/`Decimal` `to_text` typing unchanged (regression).

*VM exact values (`stdlib_to_text_tests.rs`, VM):*
- basic/padding: `(1.5,2)→"1.50"`, `(1.0,3)→"1.000"`, `(3.7,0)→"4"`, `(3.14159,2)→"3.14"`;
- **half-even ties (pin §6):** `(0.5,0)→"0"`, `(1.5,0)→"2"`, `(2.5,0)→"2"`, `(3.5,0)→"4"`, `(-2.5,0)→"-2"`,
  `(0.125,2)→"0.12"`, `(0.375,2)→"0.38"`;
- **negative-zero normalized (§1):** `(-0.0,2)→"0.00"`, `(-0.001,2)→"0.00"`, `(-0.4,0)→"0"`, `(-0.04,1)→"0.0"`;
- **f64-reality (documented, not a bug):** `(2.675,2)→"2.67"`, `(1.005,2)→"1.00"`;
- **non-finite rejected:** NaN / +Inf / −Inf → deterministic error, no string;
- **dynamic unsupported mode:** a runtime `rounding` value `"half_up"` → deterministic error (§2), no output;
- **bound:** `decimals` `18` and `-1` → deterministic error; `(x,17)` works;
- **no exponent:** `(1e20,2)→"100000000000000000000.00"` (fixed-point).

*Compiler→VM e2e:* a compiled program calling `float_to_text(ratio, 2, "half_even")` renders the expected
string (mirrors P1 e2e).

*Determinism regression:* pin the exact strings above (guards a std change); gated cross-arch test only if a
public claim is made.

---

## 6. Exact local facts used (verified, not memory)

Probe `/tmp/fmt_probe.rs` compiled with **rustc 1.95.0**
(`rustc --edition 2021 -O fmt_probe.rs -o fmt_probe && ./fmt_probe`). Key results:

```text
half-even ties  {:.0}:  0.5→0  1.5→2  2.5→2  3.5→4  4.5→4   -0.5→-0  -1.5→-2  -2.5→-2  -3.5→-4
exact-f64 ties  {:.2}:  0.125→0.12  0.375→0.38  0.625→0.62  0.875→0.88     (ties-to-even, NOT half-up)
negative zero        :  -0.0 {:.0}→"-0"   -0.0 {:.2}→"-0.00"   0.0 {:.2}→"0.00"
round-to-zero (neg)  :  -0.4 {:.0}→"-0"   -0.001 {:.2}→"-0.00"   -0.04 {:.1}→"-0.0"    (std keeps the sign)
large, fixed-point   :  1e9 {:.2}→"1000000000.00"   1e20 {:.2}→"100000000000000000000.00"   (no exponent)
high precision       :  PI {:.17}→3.14159265358979312     0.1 {:.17}→0.10000000000000001
                        0.1 {:.20}→0.10000000000000000555  0.1 {:.30}→0.100000000000000005551115123126
f64 reality          :  3.14159 {:.2}→3.14   2.675 {:.2}→2.67   1.005 {:.2}→1.00   (f64 < the decimal literal)
```

**Conclusions:** (1) std `{:.N}` rounds **half-to-even** — confirmed on clean `.0` ties *and* exact-f64 `.2`
ties; (2) std **preserves the sign of zero/rounded-zero** → normalization is required, not free; (3) fixed
precision **never emits an exponent**; (4) beyond ~17 fractional digits exposes binary-expansion artifacts →
bound `0..=17`; (5) rounding operates on the **actual f64**, so `2.675→"2.67"` is correct (the f64 is below
2.675) — the honest "floats aren't decimals" behavior, and the reason the typed-`Decimal` route exists for
exact money. Probe kept under `/tmp` (uncommitted).

---

## Reporting

- **Policy table:** §top — (1) normalize rounded-zero to unsigned; (2) literal→compile-reject /
  dynamic→deterministic runtime-reject, one stable message; (3) `decimals ∈ 0..=17`; (4) direct
  `format!("{:.*}")` + post-processing, defer `float_to_decimal`.
- **Future implementation card:** `LAB-LANG-FLOAT-TO-TEXT-IMPL-P7` (surface + acceptance matrix in §5).
- **Exact local facts:** §6 (rustc 1.95.0 probe; half-even + negative-zero + bound + f64-reality verified).
- **Held surfaces:** implicit `to_text(Float)`; any mode but `half_even`; exponent/scientific; locale/
  currency/grouping; non-finite-as-string; the `float_to_decimal` quantization helper (until literal-scale
  `Decimal[N]` is designed); any canon determinism-claim upgrade; any change to `experiment.rs`.
