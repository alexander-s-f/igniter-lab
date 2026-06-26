# LAB-LANG-NUMBER-TO-TEXT-P1

Status: CLOSED (2026-06-25) — `to_text : (Integer)->String` implemented; Float/Decimal held
Route: standard / language DX proof
Skill: idd-agent-protocol

## Goal

Design and implement the smallest number-to-text surface needed by app/science pressure:

- `DatasetMeta.count` in Todo HTML;
- numeric badges / row counts;
- scientific/report labels;
- eventually export/report descriptors.

Do not turn this into general formatting/localization.

## Current Authority

Read first:

- `lab-docs/lang/lab-todoapp-view-typed-rows-html-p18-v0.md` (`meta.count` could not render)
- `lang/igniter-stdlib/stdlib`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src`
- tests for string/concat/numeric stdlib calls
- any current implemented-surface docs for stdlib math/string

## Questions

1. What numeric types exist today and cross the VM boundary (`Integer`, `Decimal`, `Float`)?
2. Which one is needed immediately? Bias: `Integer -> String` first for `DatasetMeta.count`.
3. Is there already a `to_string`, `format`, `int_to_string`, or equivalent?
4. Where should the function live: `stdlib.string.*`, `stdlib.number.*`, or a small compiler builtin?
5. What are deterministic/replay concerns for `Decimal`/`Float` formatting?

## Implementation Bias

Prefer a narrow, total function:

```text
to_text(n : Integer) -> String
```

or a namespaced equivalent if the current stdlib style demands it.

Hold:

- localization;
- padding/precision;
- Float formatting;
- Decimal formatting beyond exact string if not already deterministic.

## Boundary

Allowed:

- Narrow stdlib/compiler/VM support for integer-to-string.
- Focused tests and one Todo typed HTML use if low-risk.
- Proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No broad formatting library.
- No locale/timezone.
- No HTML-specific helper.
- No implicit numeric coercion.
- No change to Decimal semantics unless explicitly required by live code.

## Required Proof Doc

Create:

`lab-docs/lang/lab-lang-number-to-text-p1-v0.md`

Include:

- chosen name/signature;
- why Integer first;
- determinism story;
- rejected alternatives;
- tests/counts;
- next formatting candidates if any.

## Acceptance

- [x] `Integer -> String` works in `.ig`. — `to_text`/`stdlib.string.to_text`; `to_text_through_compiler_vm` = "42"
- [x] Typechecker rejects non-Integer inputs for the v0 function. — `non_integer_argument_is_rejected`, `float_argument_is_held` (OOF-TY0)
- [x] VM/runtime result is deterministic. — Rust `i64::to_string`, base-10, exact across full i64 range (`to_text_is_exact_across_i64_range`)
- [x] App proof can render `DatasetMeta.count` or a small fixture demonstrates the function. — `concat_to_text_count_renders` = "Count: 3"
- [x] Existing string/numeric tests remain green. — VM full 23 ok, compiler full 29 ok (incl. `stdlib_version_mirrors_crate`); igniter-web --features machine 39 ok
- [x] No Float/Decimal over-claim. — Float arg → OOF-TY0; held + documented
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Exact function + examples:** `to_text(n : Integer) -> String` (bare or `stdlib.string.to_text`).
`to_text(3)=="3"`, `to_text(-7)=="-7"`, `to_text(i64::MAX)=="9223372036854775807"` (exact, no rounding),
`concat("Count: ", to_text(3))=="Count: 3"` (the P18 `DatasetMeta.count` render unblocked).

**Files changed:**
- `lang/igniter-vm/src/vm.rs` — `to_text` arm in `eval_math_call` (single source for OP_CALL + eval_ast) + name in the OP_CALL gate list.
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` — `to_text` typecheck arm `(Integer)->String`, OOF-TY0.
- `lang/igniter-vm/tests/stdlib_to_text_tests.rs` *(new, 6)* + `lang/igniter-compiler/tests/stdlib_to_text_tests.rs` *(new, 4)*.
- `lab-docs/lang/lab-lang-number-to-text-p1-v0.md` *(new)* — proof doc.

`STDLIB_VERSION` deliberately NOT bumped (consistent with the precedent that `to_float`/`char_at`/`isqrt` and
other incremental P7/P8 builtins coexist at 0.1.7; version marks coarse milestones; `stdlib_version_mirrors_crate`
guard stays green). Implemented in lab `lang/` only — NOT canon igniter-lang.

**What remains held:** `Float`/`Decimal`→String, all formatting/locale/padding. Non-Integer args fail closed (OOF-TY0).

**Should Todo typed HTML adopt it?** Yes, low-risk — a `MakeLabel(concat("…", to_text(meta.count)))` count
badge drops into the P18/P19 continuation with no new primitive. Left to the next product card (kept this
language card narrow; did not cross-edit the P19-owned `typed_html.ig`).

**Next formatting candidates:** `to_text(Decimal)->String` (exact `{value,scale}` string — money/report labels);
bounded `pad_left` for table columns; `Float->String` only behind an explicit rounding mode (highest ambiguity, last).

## Reporting

Close with:

- exact function name and examples;
- what remains held;
- whether Todo typed HTML should immediately adopt it.
