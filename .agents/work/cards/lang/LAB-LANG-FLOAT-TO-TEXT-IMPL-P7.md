# LAB-LANG-FLOAT-TO-TEXT-IMPL-P7

Status: CLOSED (2026-06-26) — `float_to_text(Float, Integer, String)->String` implemented (fixed-point, half_even-only); no implicit to_text(Float)
Route: standard / language stdlib implementation
Skill: idd-agent-protocol

## Goal

Implement the explicit Float formatting surface:

```ig
float_to_text(x: Float, decimals: Integer, rounding: String) -> String
```

This closes the policy/readiness gap from P4/P5 without adding implicit
`to_text(Float)`.

The result must be boring and exact about its limits: fixed-point text only,
finite Float only, v0 rounding mode `"half_even"` only, decimals `0..=17`, and
negative rounded zero normalized to unsigned zero.

## Current Authority

Read first:

- `.agents/work/cards/lang/LAB-LANG-FLOAT-TO-TEXT-READINESS-P4.md`
- `.agents/work/cards/lang/LAB-LANG-FLOAT-TO-TEXT-POLICY-P5.md`
- `lab-docs/lang/lab-lang-float-to-text-readiness-p4-v0.md`
- `lab-docs/lang/lab-lang-float-to-text-policy-p5-v0.md`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- existing tests around `to_text(Integer)`, `to_text(Decimal)`, and `pad_left`

Live code wins over docs. If a doc says something is missing but source already
implements it, treat the doc as stale and update/report it.

## Semantics To Implement

Surface:

```text
float_to_text(Float, Integer, String) -> String
```

Rules:

1. `rounding == "half_even"` is the only supported mode.
2. Literal unsupported rounding should be compile-rejected when the typechecker
   can see the literal.
3. Dynamic unsupported rounding should deterministically fail at runtime before
   producing an output.
4. `decimals` must be in `0..=17`.
5. Non-finite inputs (`NaN`, `Infinity`, `-Infinity`) must fail
   deterministically; do not stringify them.
6. Formatting is fixed-point, never exponent/scientific.
7. Use Rust's fixed precision formatting plus tiny post-processing, as selected
   by P5:
   - validate mode / finite / bound;
   - `format!("{:.*}", decimals, x)`;
   - normalize a negative sign away if the rounded output is all zero
     (`-0.0`, `-0.001` at 2 decimals, `-0.4` at 0 decimals).
8. Preserve f64 reality. Examples like `2.675` at 2 decimals may produce
   `"2.67"` because the binary Float value is below the decimal-looking
   literal. Do not "fix" this by pretending Float is Decimal.

## Closed Surfaces

- No implicit `to_text(Float)`.
- No locale, currency, grouping, or exponent format.
- No rounding modes except `"half_even"`.
- No `float_to_decimal` or typed `Decimal[N]` conversion.
- No broad formatter API.
- No changes to `experiment.rs` unless live source proves the stdlib surface
  already routes there and the implementation cannot be placed elsewhere.
- No canon determinism claim.

## Acceptance

- [x] Typechecker accepts `float_to_text(Float,Integer,String) -> String`. — `valid_float_to_text_compiles_clean_as_string`
- [x] Typechecker rejects wrong arity and wrong argument types. — `wrong_arity_is_rejected`, `wrong_arg_types_are_rejected`
- [x] Literal unsupported rounding mode rejected at compile time. — **IMPLEMENTED** `literal_unsupported_rounding_mode_rejected` (checker inspects `Expr::Literal`, §2 message)
- [x] Dynamic unsupported rounding mode fails deterministically at runtime. — `dynamic_unsupported_mode_rejected`
- [x] VM exact-value tests (0.5→0, 2.5→2, 0.125→0.12, 0.375→0.38, 2.675→2.67, 1.005→1.00, 1e20 fixed-point, -0.0→0.00, -0.001→0.00, -0.4→0). — `half_even_ties`/`negative_zero_normalized`/`f64_reality_not_decimal`/`no_exponent_for_large_values`
- [x] Runtime rejects non-finite. — `non_finite_rejected` (NaN/±Inf)
- [x] Runtime rejects decimals `<0` and `>17`. — `precision_bound_edges`
- [x] Existing `to_text(Integer/Decimal)` + `pad_left` tests remain green. — full VM 25 / compiler 31 green
- [x] Compiler→VM e2e fixture. — `float_to_text_through_compiler_vm` (+ eval_ast fold parity); composition with `pad_left` already proven (P3) and via the trio
- [x] No implicit `to_text(Float)`; negative test. — `no_implicit_to_text_of_float` (to_text(Float)→OOF-TY0)
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Files:** `lang/igniter-vm/src/vm.rs` (free `fn float_to_text` next to `decimal_to_text` + arm in
`eval_math_call` + name in OP_CALL math gate; eval_ast auto-routes), `lang/igniter-compiler/src/typechecker/
stdlib_calls.rs` (`float_to_text` arm + literal-mode rejection); `lang/igniter-vm/tests/stdlib_float_to_text_tests.rs`
(11), `lang/igniter-compiler/tests/stdlib_float_to_text_tests.rs` (5); `lab-docs/lang/lab-lang-float-to-text-impl-p7-v0.md`.

**Accepted surface:** `float_to_text(Float, Integer, String) -> String` (bare + `stdlib.string.*`), single
`eval_math_call` source. **Held:** no implicit `to_text(Float)`, no locale/currency/grouping/exponent, only
`"half_even"`, no `float_to_decimal`/typed `Decimal[N]`, no broad formatter, no `experiment.rs` change, no
canon determinism claim. Semantics = P5 §4 exactly: validate mode/finite/`0..=17` → `format!("{:.*}")` →
negative-zero normalize.

**Local Rust facts:** NO deviation from the P5 §6 probe (rustc 1.95.0) — all pinned values matched std
`{:.N}` (ties-to-even, sign-preserved rounded-zero → normalize, fixed-point, f64-reality `2.675→2.67`).

**Literal-mode compile rejection:** IMPLEMENTED (not deferred) — checker inspects the `String` literal arg.

**Tests/counts:** VM 11, compiler 5; full VM 25 ok, full compiler 31 ok (version guards incl.); igniter-web
`--features machine` green (39 ok-blocks); `git diff --check` clean. `STDLIB_VERSION` unchanged.

**Next route:** `LAB-LANG-STDLIB-FORMATTING-COMPLETION-P8` (front-door docs — the trio
to_text(Integer)/to_text(Decimal)/float_to_text + pad_left now covers the formatting surface). Named follow-ons
gated on pressure: `float_to_decimal` quantizer, optional `pad_right`.

## Reporting

Close with:

- exact files changed;
- the accepted public surface and held surfaces;
- local Rust formatting facts if any values differ from the P5 packet;
- exact tests run and counts;
- whether literal-mode compile rejection was implemented or deferred because
  the current checker cannot inspect string literals there.

## Next Route

After this lands, run:

- `LAB-LANG-STDLIB-FORMATTING-COMPLETION-P8`

That card updates the front-door docs so future agents stop asking whether
Float formatting exists.
