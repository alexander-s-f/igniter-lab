# LAB-LANG-STRING-PAD-LEFT-P3

Status: CLOSED (2026-06-25) — `pad_left : (String, Integer, String)->String` implemented (rune-counted table primitive)
Route: standard / language stdlib implementation
Skill: idd-agent-protocol

## Goal

Add a small string-table helper:

```ig
pad_left(text: String, width: Integer, pad: String) -> String
stdlib.string.pad_left(text, width, pad) -> String
```

This unblocks report/table columns without forcing app agents to hand-roll
padding or fake alignment through ViewArtifact nodes.

## Current Authority

Read first:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- existing string builtins/tests around `concat`, `char_at`, `to_text`
- `.agents/work/cards/lang/LAB-LANG-NUMBER-TO-TEXT-P1.md`

Live code wins over this card.

## Required Semantics

`pad_left(text, width, pad)`:

- if `len(text) >= width`, returns `text`;
- otherwise prefixes repetitions of `pad` until the result reaches `width`;
- if the last repetition would exceed width, truncate the final pad fragment;
- `width` counts Rust Unicode scalar chars, not bytes;
- `pad` must be non-empty;
- negative width is a runtime/domain error or compile/type error if the current
  stdlib pattern has an obvious convention. Pick one and document it.

Examples:

| Input | Output |
| --- | --- |
| `pad_left("7", 3, "0")` | `"007"` |
| `pad_left("abc", 2, "0")` | `"abc"` |
| `pad_left("x", 5, "ab")` | `"ababx"` |
| `pad_left("é", 3, " ")` | `"  é"` |

## Implementation Notes

Likely minimal path:

- typechecker: arity 3; `(String, Integer, String) -> String`; use the existing
  string-builtin diagnostic style (`OOF-TY0` unless a better local rule exists);
- VM: add one arm in the same stdlib call dispatch as string helpers;
- tests: direct VM helper + compiler -> VM path.

Do not introduce a general formatting mini-language. This is a table primitive,
not `printf`.

## Closed Surfaces

- No `pad_right` unless the card is explicitly expanded.
- No center-align.
- No width/display-cell/East Asian width policy.
- No numeric formatting; compose as `pad_left(to_text(x), width, "0")`.
- No Float formatting.

## Acceptance

- [x] Compiler accepts valid `(String, Integer, String)`. — `valid_pad_left_compiles_clean_as_string`
- [x] Compiler rejects wrong arity and wrong arg types. — `wrong_arity_is_rejected`, `wrong_arg_types_are_rejected` (arg1/2/3)
- [x] VM direct tests cover no-op, single-char, multi-char truncation, empty-pad rejection, negative width, Unicode scalar count. — 7 direct tests
- [x] Compiler→VM test proves `pad_left(to_text(7), 3, "0") == "007"`. — `pad_left_to_text_through_compiler_vm` (+ eval_ast fold parity)
- [x] No changes to web/render/server. — only `lang/` touched
- [x] `cargo test` focused string tests pass. — VM **9**, compiler **3**
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Final behavior:** width = Unicode-scalar (Rust `char`) count, not bytes (like `char_at`/`substring`).
`width <= len(text)` incl. **negative/zero width → total no-op** (returns text, no error — falls out of the
`width<=len` rule). **Empty pad → domain error ONLY when padding is needed** (`width>len`); harmless/unused
otherwise. Multi-char pad repeats L→R, truncating the final fragment (`"x",5,"ab"→"ababx"`).

**Implementation:** new `pub fn stdlib_string_pad_left` (vm.rs) next to char_at/substring (rune style, no f64),
wired into BOTH dispatch paths (OP_CALL + eval_ast → single source, byte-parity); typechecker arm
`(String,Integer,String)->String` (OOF-TY0). No web/render/server change. Not a formatter (numeric padding
composes as `pad_left(to_text(x), w, "0")`).

**Files:** `lang/igniter-vm/src/vm.rs`, `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (modified);
`lang/igniter-vm/tests/stdlib_pad_left_tests.rs` (9), `lang/igniter-compiler/tests/stdlib_pad_left_tests.rs` (3),
`lab-docs/lang/lab-lang-string-pad-left-p3-v0.md` (new). `STDLIB_VERSION` unchanged. Lab `lang/` only — NOT canon.

**Tests/counts:** VM `stdlib_pad_left_tests` **9**, compiler **3**; full VM **24 ok**, full compiler **30 ok**
(version guard incl.); igniter-web `--features machine` + igniter-render-html green; `git diff --check` clean.

**Next obvious sibling (only if justified):** `pad_right` (same helper, append vs prefix — symmetric, if
right-align pressure appears). NOT center-align, NOT display-width policy, NOT a broad formatter; grouping
separator stays view-layer (over `to_text`/`pad_left`), not a stdlib primitive.

## Reporting

Close with:

- final behavior for empty pad and negative width;
- whether width is scalar-char count or byte count;
- exact tests/counts;
- next obvious sibling only if justified (`pad_right`, not a broad formatter).
