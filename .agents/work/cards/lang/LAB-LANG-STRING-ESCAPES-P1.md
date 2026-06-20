# LAB-LANG-STRING-ESCAPES-P1 - Add basic escape handling to `.ig` string literals

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: implementation-proof
Delegation code: OPUS-LANG-STRING-ESCAPES-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

During the IgWeb render/ViewArtifact work, `.ig` could not inline JSON-like strings because the lexer closed
strings at the first `"`. The proof avoided the gap by sourcing artifact JSON from `req.body`, which was the
right proof move, but this should not become permanent application friction.

This is a language paper cut, not a graph-foundation problem. It should be fixed narrowly in the lexer/parser
surface and proven with real compiler tests.

## Goal

Support a minimal, conventional escape set in `.ig` string literals:

```text
\"  quote
\\  backslash
\n  newline
\t  tab
\r  carriage return
```

Optional: `\u{...}` only if the existing lexer/parser has a natural low-risk path. Do not expand scope just
because other languages support more escapes.

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/lexer.rs`
- `lang/igniter-compiler/src/parser.rs`
- `lang/igniter-compiler/tests`
- fixtures using strings with quotes / JSON / newlines, if any
- any docs/proposals found by `rg "escape|escaped|string literal|lexer"`
- latest render/ViewArtifact proof docs that mention the escape limitation

Confirm or correct:

- whether `read_string` still reads until the next raw `"`;
- whether parser/emitter/VM preserve string literal values unchanged after lexing;
- whether diagnostics can report unterminated strings and invalid escapes with line/column;
- whether existing tests assume backslash is literal inside strings.

Live code wins over this card.

## Required Shape

Prefer the narrowest lexer change:

1. Recognize the escape sequences listed in Goal.
2. Preserve existing string behavior for ordinary strings.
3. Invalid escape should be a clear lexer/compile diagnostic, not silent lossy output.
4. Unterminated strings should remain a clear diagnostic.
5. Do not add raw strings, heredocs, template strings, interpolation, JSON literals, or HTML strings.

If the current diagnostic plumbing cannot express invalid escape cleanly, implement the smallest consistent
error path and document the limitation.

## Required Tests

Add focused tests at the lowest useful layer and at least one compile-level proof:

- string with escaped quote: `"say \"hi\""` becomes `say "hi"`;
- escaped backslash: `"a\\b"` becomes `a\b`;
- escaped newline/tab/carriage return values are decoded correctly;
- JSON-shaped string can be represented: `"{\"body\":\"ok\"}"`;
- invalid escape such as `\q` fails clearly;
- trailing backslash / unterminated escape fails clearly;
- existing simple strings still compile and evaluate;
- no ViewArtifact / IgWeb route changes are required for this card.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test todo_view_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
git diff --check
```

If `cargo test` for the full compiler/VM has known pre-existing failures, isolate and report the focused
green tests plus the exact unrelated failure. Do not hide it.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-string-escapes-p1-v0.md
```

It must state:

- exact escape set implemented;
- exact invalid-escape behavior;
- whether existing string behavior changed;
- exact tests and counts;
- what remains deferred (raw strings, unicode escapes, interpolation, JSON literals, multiline/heredoc).

Update this card with a closing report.

## Closed Scope

- No interpolation.
- No raw strings.
- No heredocs/multiline string syntax beyond decoded `\n`.
- No JSON literal type.
- No HTML/template syntax.
- No ViewArtifact authoring change.
- No `.igweb` syntax.
- No VM semantic change except preserving decoded literal values.
- No canon/stable API claim.

## Suggested Next

If this lands cleanly, revisit the render/ViewArtifact examples only if inline strings are still useful. Do
not rewrite P17/P19/P22 just to use escapes; the proof history is valid.

---

## Closing Report (2026-06-20)

**Files:** `lang/igniter-compiler/src/lexer.rs` (`TokenType::Illegal` + escape-decoding `read_string`),
`src/parser.rs` (`Illegal` arm in `parse_primary` → `OOF-LEX1`), `tests/string_escapes_tests.rs` (+10).
Proof doc: `lab-docs/lang/lab-lang-string-escapes-p1-v0.md`.

**Implemented escape set:** `\"` `\\` `\n` `\t` `\r`. Inline JSON now lexes:
`"{\"body\":\"ok\"}"` → `{"body":"ok"}` (the exact P17–P22 detour, retired at the language level).

**Invalid escape / unterminated:** `read_string` returns an `Illegal` token (`value` = reason); the parser
surfaces it verbatim as a line-positioned **`OOF-LEX1`** and fails the compile (no silent lossy output).
`Illegal` is safe — both `match token_type` sites have `_` arms.

**Backward-compat (verified):** **no `.ig` string literal in the tree contains a backslash** (the only `\`
are in `decision_tree` comments, which the lexer skips; regexes use `[^/]+`). So every existing string
decodes byte-for-byte unchanged.

**Lane discipline (P0):** pure source-surface sugar — escapes change only the lexed string value; **no new
SIR node kind, no VM semantic change, no new runtime authority.**

**Proof — green:** `string_escapes` 10; igniter-compiler (lib 55 + igweb 11 + …); igniter-vm; igniter-web 17
default + 14 machine; `git diff --check` clean.

**Honest: the only red tests are PRE-EXISTING loop WIP** — `loop_conformance_tests` (4) +
`vm_candidate_proof_tests::test_proof_vmg13…` (1), all asserting loop-node SIR generation. **Confirmed
unrelated via `git stash` of my two files**: removed, the same loop tests fail identically (loops are pending
`PROP-039`; fixtures have no backslash strings). A one-off `--features machine` flake
(`product_todos_index_empty_returns_app_404`) was a parallel temp-dir race in the read harness, did not
reproduce clean.

**Deferred:** `\u{...}`, raw strings, heredocs, interpolation, JSON-literal type, HTML/template.
**Next:** `LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` → `LAB-LANG-RECORD-ERGONOMICS-READINESS-P1`.
