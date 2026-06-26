# lab-lang-float-to-text-readiness-p4-v0

Card: `LAB-LANG-FLOAT-TO-TEXT-READINESS-P4`
Route: standard / language stdlib readiness · Skill: idd-agent-protocol
Status: readiness packet (design only — no implementation; no canon claim)
Date: 2026-06-26
Wave: number→text — P1 `to_text(Integer)` (live) · P2 `to_text(Decimal)` (READY) · **P4 Float (this)**.

> **Authority boundary.** Lab language surface (igniter-lab `lang/` — the lab's own compiler/VM, NOT canon
> `igniter-lang`). Design only: no code, no implicit `to_text(Float)`, no locale/currency/grouping, no change
> to host-side experiment output, **no canon determinism-claim upgrade.** Cited against live source.

---

## Headline

**Float→text is the one number→text case that is *lossy*, so it must be a distinct function with a mandatory,
explicit precision + rounding contract — never an overload of the exact `to_text`.** Recommended v0:

```text
float_to_text(x : Float, decimals : Integer, rounding : String) -> String
```

with **one** accepted rounding mode `"half_even"`, **non-finite rejected** (NaN/±Inf → deterministic domain
error, never a `"NaN"` string), **no exponent notation**, and `decimals` **bounded** `0..=MAX` (MAX ≈ 17).
The principled extension — and the cleanest place for the rounding contract to *live* — is a sibling
`float_to_decimal(x, decimals, rounding) -> Decimal[decimals]` (the lossy step yields a reusable **exact**
Decimal; text then reuses P2's exact `to_text(Decimal)`). Recommend shipping `float_to_text` first; expose
`float_to_decimal` as a fast-follow sharing the same rounding core.

> **Review amendment.** `Decimal[decimals]` is only type-expressible when `decimals` is a literal/static
> scale. A dynamic `decimals` argument can still validate at runtime for `float_to_text`, but a future
> `float_to_decimal` must either require a literal scale (preferred for typed Decimal output) or return bare
> `Decimal`. Likewise, unknown `rounding` can be compile-rejected only when the mode is a literal string;
> dynamic strings need fail-closed runtime validation.

---

## 1. Why Float cannot reuse `to_text` (the live invariant)

`to_text` is, by construction, **total + exact + single-arg + no rounding**:

- `to_text(Integer)` → `i64::to_string()` — "Total + deterministic … base-10, no locale/grouping/padding …
  integer-only, no float/IEEE surface. Float/Decimal HELD" (`lang/igniter-vm/src/vm.rs:3704-3718`).
- `to_text(Decimal)` (P2, `READY`) — exact: "preserve exactly `scale` fractional digits; **no rounding**;
  never exponent; never locale … use integer/string arithmetic only. **Avoid `f64`**"
  (`.agents/work/cards/lang/LAB-LANG-DECIMAL-TO-TEXT-P2.md:48-66`).

Float breaks every one of those: an `f64` is binary, so most decimals are inexact; rendering to N decimals
**requires a precision argument** and **a rounding decision**, and `f64` carries **non-finite** values
(NaN/±Inf). Overloading `to_text(Float)` would silently void the "to_text is exact" invariant. So Float→text
is a **separate, contract-bearing function** — exactly the card's premise ("not a casual `f64.to_string()`").

The pressure is real and dual-ended: host science output already formats floats at fixed precision from
`{:.1}` to **`{:.16}`** (`lang/igniter-vm/src/experiment.rs`, the data CSVs vs human summaries) — so the
surface must serve both report-grade (2–3 decimals) and science-grade (≈16) fixed-point.

---

## 2. Surface alternatives (Q1) — ≥3 compared

| # | Surface | DX | Extensible | Verdict |
| --- | --- | --- | --- | --- |
| A | **`float_to_text(x:Float, decimals:Integer, rounding:String) -> String`** | explicit, positional; reads subject-first | adding a mode = new accepted string | **Recommended (deliverable).** Mandatory precision+rounding; total over finite floats; mirrors the `to_float`/`to_text` bare+namespaced style. |
| B | `to_text_float(x, decimals, mode)` | groups under `to_text` lexically | same | **Reject naming.** Awkward (`to_text_float` reads backwards); `float_to_text` is the natural verb order and keeps `to_text` reserved for the *exact* cases. |
| C | `float_to_text(x:Float, opts:FloatFormat{decimals,rounding})` | one options record; future-proof | add fields without arity change | **Defer.** Premature ceremony — needs a record type + still a `rounding` field; revisit only when a *second* option (grouping/exponent) lands, and those are held. |
| D | **`float_to_decimal(x, decimals, rounding) -> Decimal[decimals]` + reuse `to_text(Decimal)` (P2)** | two steps; the lossy step is a named, typed value | rounding contract attached where rounding happens | **Recommended primitive (fast-follow).** The quantization `Float → Decimal[N]` is the *real* lossy operation; its result is an **exact reusable Decimal** (arithmetic/compare/store), and text reuses P2 exactly — no second formatter. `float_to_text` becomes sugar = `to_text(float_to_decimal(…))`. |

**Recommendation:** ship **A** (`float_to_text`) first for the immediate need (render a float into a report /
HTML leaf / CSV cell). Add **D** (`float_to_decimal`) as a fast-follow so the rounding step is a first-class
typed value; both share one rounding core. Reject **B** (naming) and **C** (premature). This is the "smaller
or cleaner surface" the card asked to verify: D is *cleaner* (rounding lives at the float→fixed-point
boundary, exact text is reused), A is *smaller* (one call, self-contained).

**Static-scale caveat for D:** `Decimal[N]` needs a statically known `N` in today's type surface. If P5/P6
want typed `float_to_decimal`, require `decimals` to be an integer literal (mirroring `decimal(value, scale)`)
or explicitly accept bare `Decimal` as a weaker result. Do not imply dependent typing from a dynamic
`decimals` value.

---

## 3. Rounding policy (Q2) — v0 = one mode, `"half_even"`

**Recommend exactly one accepted string in v0: `"half_even"`** (round half to even / banker's rounding).
Three reasons, each load-bearing:

1. **Unbiased.** Reports and science round *many* values and then sum them; `half_up`/`half_away_from_zero`
   introduces a systematic upward drift, `half_even` does not. For the science pressure (`experiment.rs`
   aggregates), unbiasedness is correctness, not taste.
2. **Deterministic *and* cheapest to implement correctly.** Rust's std fixed-precision formatting
   (`format!("{:.*}", decimals, x)`) is **already correctly-rounded, ties-to-even, and integer-based**
   (`flt2dec`, no `libm`) — so `half_even` can lean on a proven cross-arch-deterministic algorithm. Any other
   mode (`half_up`, `floor`, `ceil`, `trunc`) needs a *custom* implementation, more surface + more
   determinism risk, for v0.
3. **Aligns with the platform + the det-math wave.** IEEE-754 round-to-nearest default is ties-to-even; the
   lab's deterministic math surface (`det_*`, `vm.rs:2061-2070`) is the determinism discipline this formatter
   plugs into.

Any other `rounding` string is an **`OOF-TY0`-class rejection** in v0 (unknown mode → compile/runtime error),
reserving `"half_up"` / `"floor"` / `"ceil"` / `"trunc"` for a future card. **Deterministic-implementation
requirement:** the rounding must be a correctly-rounded *integer/string* algorithm (std `{:.N}` or an explicit
equivalent), **never** `libm`, locale, or `Math.round`-style float ops.

If `rounding` is a string literal, the compiler should reject any value other than `"half_even"`. If it is
dynamic, the VM must reject unsupported values deterministically before producing output.

---

## 4. Non-finite policy (Q3) — reject as a deterministic domain error

**Recommend: NaN / +Inf / −Inf → a deterministic domain error, NOT a string.** Reasons:

- A `"NaN"` / `"Infinity"` cell in a report / table / CSV is a **silent data-quality failure** — the kind the
  science/replay discipline exists to catch, not launder into output.
- It aligns with the existing deterministic-error posture of the det-math surface (`vm.rs:3397-3421`: domain
  issues return *"a deterministic error"*, not a sentinel value). float_to_text should mirror that: non-finite
  in → deterministic error out, surfaced to the caller (who must guard the value upstream, e.g. via a finite
  check or a det op that cannot produce non-finite).
- It keeps `float_to_text` **total over the finite domain** and undefined-by-contract on non-finite — a clean,
  testable boundary. (And it is consistent with **D**: `Decimal` cannot represent non-finite, so
  `float_to_decimal` must reject them too — one rule, one place.)

Explicitly **not** chosen: emitting `"NaN"`/`"Infinity"` strings (hides bad numerics) or a locale/`±∞` glyph.

---

## 5. Exponent notation (Q4) — no, fixed-point only in v0

**No exponent / scientific notation in v0.** Reports, tables, money, and HTML leaves want fixed-point
(`123.45`, not `1.2345e2`). Scientific notation is a *separate, future* surface (science may want it for very
large/small magnitudes — note `experiment.rs` already uses fixed `{:.16}`, not `{:e}`), best as a later
`float_to_text_sci` or an added mode, **held** here. v0 `float_to_text` is fixed-point, `decimals` exact.

---

## 6. Determinism / replay boundary (Q5) — stated honestly

- **The formatter does not add nondeterminism.** Fixed-decimal formatting via a correctly-rounded
  *integer* algorithm (std `{:.N}` / `flt2dec`) is a pure function of the input `f64` bits + `decimals` +
  mode — no `libm`, no locale, no wall-clock. It is deterministic on a fixed toolchain and, because the
  algorithm is integer arithmetic, **byte-identical across architectures for the same `f64` bits**.
- **It inherits, it does not create, determinism.** The output is only as deterministic as the *input* `f64`.
  If that float came from a non-deterministic upstream op (e.g. raw `libm` `sin`), the nondeterminism is
  upstream — the det-math wave (`det_*`) is what guarantees bit-identical inputs; this card does not change
  that.
- **A public cross-arch science claim requires explicit evidence.** Reusing the determinism wave's discipline:
  if formatted float output is published as cross-arch-stable, it needs a test formatting the *same* `f64`
  on x86_64 + aarch64 and asserting byte-identical strings — not an assumed claim. **This card upgrades no
  canon determinism claim** (closed surface); it states the formatter is deterministic-by-construction and
  defers any public bit-identity claim to evidence under the existing det discipline.

---

## 7. Implementation card (Q6) — `LAB-LANG-FLOAT-TO-TEXT-P5`

> **Depends on:** P2 `to_text(Decimal)` should land first **iff** the `float_to_decimal` route (D) is taken;
> the self-contained `float_to_text` (A) via std `{:.N}` needs no P2. Recommend A first (no dependency), D
> after P2.

**Surface:** `float_to_text(x:Float, decimals:Integer, rounding:String) -> String`, bare + `stdlib.string.*`
namespaced, sharing the single `eval_math_call` arm (the P1/`to_text` pattern). Likely impl: non-finite check
→ bound `decimals` → `format!("{:.*}", decimals as usize, x)` (correctly-rounded, ties-to-even), with a test
that **verifies** std's rounding matches the `half_even` contract (else implement explicitly).

**Acceptance test matrix:**

*Typecheck (compiler `stdlib_to_text_tests.rs`):*
- accepts `float_to_text(1.5, 2, "half_even")` → `String`;
- rejects wrong arity, `x` not Float, `decimals` not Integer, `rounding` not String → `OOF-TY0`;
- rejects an **unknown rounding** string (`"half_up"`) → `OOF` (single-mode v0);
- `Integer`/`Decimal` `to_text` typing **unchanged** (regression).

*VM exact-value (`stdlib_to_text_tests.rs` VM crate):*
- basic + padding: `(1.5,2)→"1.50"`, `(0.0,2)→"0.00"`, `(1.0,3)→"1.000"`, `(3.7,0)→"4"`;
- **half-even ties (the proof it is not half-up):** `(0.5,0)→"0"`, `(1.5,0)→"2"`, `(2.5,0)→"2"`,
  `(3.5,0)→"4"`; negative `(-2.5,0)→"-2"`;
- **negative zero policy:** std formatting yields `"-0"` for some rounded negative values (for example
  `-0.5` at zero decimals on the current toolchain). P5 must either preserve that as faithful sign semantics
  or normalize it to `"0"` deliberately; do not let it be an accidental behavior.
- sign + small magnitude: `(-0.05,1)→"-0.1"` or document the representation-aware result;
- **non-finite rejected:** NaN and ±Inf inputs → deterministic domain error (no string emitted);
- **bound:** `decimals` above `MAX` (e.g. 18) → error; `decimals` negative → error;
- **no exponent:** a large magnitude (e.g. `1e9` at 2 decimals) renders fixed-point, no `e`.

*Compiler→VM end-to-end:* a compiled program calling `float_to_text(meta_ratio, 2, "half_even")` renders the
expected fixed-point string (mirrors P1's e2e test).

*Determinism (gated):* same `f64` → same string (trivial); a cross-arch byte-identity test **only if** a
public claim is made (else omit and state "deterministic-by-construction, cross-arch evidence deferred").

---

## Verification

```bash
rg -n "to_text|float_to_text|to_float|det_|rounding|Value::Float" \
  lang/igniter-vm/src/vm.rs lang/igniter-compiler/src/typechecker/stdlib_calls.rs

git diff --check    # clean (design-only; no code changed)
```

---

## Reporting

- **Recommended signature:** `float_to_text(x:Float, decimals:Integer, rounding:String) -> String` (bare +
  `stdlib.string.*`), **one** mode `"half_even"`, non-finite rejected, no exponent, `decimals` bounded
  `0..=≈17`. Principled fast-follow: `float_to_decimal(x, decimals, rounding) -> Decimal[decimals]` reusing
  P2's exact `to_text(Decimal)`.
- **Exact held surfaces:** implicit `to_text(Float)`; any rounding mode other than `half_even`; exponent /
  scientific notation; locale / currency / grouping; non-finite-as-string; options-record surface; any change
  to host-side `experiment.rs` output; any canon determinism-claim upgrade.
- **Test matrix:** §7 — typecheck (arity/type/unknown-mode reject, Integer/Decimal regression), VM exact
  values incl. **half-even tie cases**, non-finite rejection, decimals-bound, no-exponent, compiler→VM e2e,
  optional gated cross-arch determinism.
- **Next:** `LAB-LANG-FLOAT-TO-TEXT-P5` (implementation, surface A first; D after P2 Decimal→text lands).
