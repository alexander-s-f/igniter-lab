# lab-lang-string-pad-left-p3-v0

Card: `LAB-LANG-STRING-PAD-LEFT-P3`
Route: standard / language stdlib implementation · Skill: idd-agent-protocol
Status: implemented (`pad_left : (String, Integer, String) -> String`) · table primitive, not a formatter · no canon claim
Date: 2026-06-25
Builds on: the string-builtin line (`char_at`/`substring`) · P1/P2 `to_text` (composes as `pad_left(to_text(x), w, "0")`)

> **Authority boundary.** Lab language surface (igniter-lab `lang/` — the lab's own compiler/VM, NOT canon
> igniter-lang). One rune-counted left-pad primitive mirroring `char_at`/`substring`; no formatting
> mini-language, no `pad_right`/center, no width/display-cell policy, no web/render/server change; **no canon claim.**

---

## Headline

`pad_left(text, width, pad)` left-pads `text` to `width` **Unicode scalar chars** by prefixing repetitions of
`pad` (truncating the final fragment), for report/table columns — so app agents stop hand-rolling alignment.
It mirrors the existing `char_at`/`substring` string builtins exactly: one shared free helper
`stdlib_string_pad_left`, wired into both VM dispatch paths (`OP_CALL` + `eval_ast`) and the typechecker
(`OOF-TY0`). Numeric padding composes — `pad_left(to_text(7), 3, "0") == "007"` — with no formatter primitive.

---

## Final behavior (the two edge-case decisions, documented)

- **Width is a Unicode-scalar (Rust `char`) count, not bytes** — consistent with `char_at`/`substring`'s
  rune-indexed policy. `pad_left("é", 3, " ") == "  é"` (é is one scalar); a multi-byte pad char (`"→"`)
  counts as one column.
- **`width <= len(text)` (including zero and negative width) → returns `text` unchanged** — a total no-op, no
  error. Negative width is *not* a separate error: it falls out of the `width <= len` rule directly (no
  positive `len` is ever `< 0`). Chosen for totality, matching the house style where string builtins never
  raise domain errors for out-of-range numeric args (they clamp / no-op).
- **`pad` must be non-empty — but only when padding is actually needed.** If `width > len(text)` and `pad` is
  empty, that's the one domain error (`"stdlib.string.pad_left: pad must be non-empty"`) — an empty pad cannot
  make progress. If no padding is needed, an empty `pad` is harmless (unused) and returns `text`.

| Input | Output | Shows |
| --- | --- | --- |
| `pad_left("7", 3, "0")` | `"007"` | single-char pad |
| `pad_left("abc", 2, "0")` | `"abc"` | no-op (width ≤ len) |
| `pad_left("x", 5, "ab")` | `"ababx"` | multi-char pad, final fragment truncated |
| `pad_left("é", 3, " ")` | `"  é"` | scalar-count width |
| `pad_left("abc", -5, "0")` | `"abc"` | negative width → no-op |
| `pad_left("x", 5, "")` | **error** | empty pad while padding needed |
| `pad_left("abc", 2, "")` | `"abc"` | empty pad harmless when unused |

## Implementation

- **VM** (`lang/igniter-vm/src/vm.rs`): a new shared helper `pub fn stdlib_string_pad_left(args) -> Result<Value, String>`
  next to `stdlib_string_char_at`/`stdlib_string_substring`, using the same `args[i].as_str()`/`as_integer()`
  + `.chars()` rune style. Integer/string arithmetic only — no `f64`. Wired into **both** dispatch arms that
  `char_at`/`substring` use (the bytecode `OP_CALL` path and the `eval_ast`/HOF path), so the two are
  byte-identical (single source).
- **Typechecker** (`lang/igniter-compiler/src/typechecker/stdlib_calls.rs`): a `pad_left`/`stdlib.string.pad_left`
  arm mirroring `substring` — arity 3, `(String, Integer, String) -> String`, each arg checked against its
  expected type (`OOF-TY0`, `Unknown` accepted), `String` returned on every path.

No web/render/server change. No general formatting mini-language (this is one primitive, not `printf`).

## Tests / counts

**`lang/igniter-vm/tests/stdlib_pad_left_tests.rs` (9):** the card examples; no-op/equal-width; multi-char
exact + partial repetition (`"x",4,"ab"→"abax"`, `"x",7,"ab"→"abababx"`); Unicode scalar count (`"naïve"`,
multi-byte pad char); negative/zero width no-ops; empty-pad rejected only when padding is needed; arity errors;
the required `pad_left(to_text(7), 3, "0") == "007"` through the real compiler→VM (`OP_CALL`); and an
`eval_ast` parity test (`pad_left` inside a `fold` lambda → `"007"`).

**`lang/igniter-compiler/tests/stdlib_pad_left_tests.rs` (3):** valid `(String, Integer, String)` (with
`to_text` composition) compiles clean; wrong arity → `OOF-TY0`; each of arg1/arg2/arg3 wrong type → `OOF-TY0`.

**Regression (green):** VM full suite (24 ok-blocks, incl. `char_at`/`substring`/`to_text`); compiler full
suite (30 ok-blocks, incl. **`stdlib_version_mirrors_crate`**); igniter-web `--features machine` and
`igniter-render-html` green (downstream path-dep recompile, no source change). `git diff --check` clean.

```bash
# from lang/igniter-vm
cargo test --test stdlib_pad_left_tests       # 9 passed
cargo test                                    # full VM suite green
# from lang/igniter-compiler
cargo test --test stdlib_pad_left_tests       # 3 passed
cargo test                                    # full compiler suite green (version guard incl.)
```

`STDLIB_VERSION` unchanged (same coarse-milestone precedent as P1/P2; the guard stays green).

## Files changed

| File | Change |
| --- | --- |
| `lang/igniter-vm/src/vm.rs` | `pub fn stdlib_string_pad_left` helper + `pad_left` arm in both string dispatch paths. |
| `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` | `pad_left` typecheck arm `(String, Integer, String)->String`. |
| `lang/igniter-vm/tests/stdlib_pad_left_tests.rs` *(new, 9)* | direct + OP_CALL + eval_ast tests. |
| `lang/igniter-compiler/tests/stdlib_pad_left_tests.rs` *(new, 3)* | typecheck accept/reject. |

## Reporting

- **Empty pad:** a domain error only when padding is actually needed (`width > len` + empty `pad`); harmless
  (returns `text`) when unused.
- **Negative width:** a total no-op (returns `text`) — falls out of the `width <= len` rule, no special error.
- **Width unit:** Unicode-scalar (Rust `char`) count, not bytes — consistent with `char_at`/`substring`.
- **Tests/counts:** VM 9, compiler 3; full VM 24 ok, full compiler 30 ok; downstream green; diff clean.
- **Next obvious sibling (only if justified):** `pad_right` (same helper, append instead of prefix) — a thin,
  symmetric follow-on if right-alignment pressure appears. NOT a broad formatter, NOT center-align, NOT a
  display-width/East-Asian policy. A thousands/grouping separator stays a view-layer presentation concern
  (composed over `to_text`/`pad_left`), not a stdlib numeric primitive.
