# lab-lang-string-escapes-p1-v0 — basic escape handling in `.ig` string literals

**Card:** `LAB-LANG-STRING-ESCAPES-P1` · **Delegation:** `OPUS-LANG-STRING-ESCAPES-P1`
**Status:** CLOSED (lab implementation-proof) — `.ig` string literals now decode a minimal conventional
escape set; invalid escapes / unterminated strings fail with a line-positioned diagnostic. **First slice of
the parallel surface-ergonomics lane (P0): pure source-surface sugar, no SIR/VM semantic change.**
**Authority:** Lab tooling. Narrow `lexer.rs` + one `parser.rs` arm.

## What the lane discipline required (P0 §4) — met

- **Desugars to canonical:** escapes change only the *string value* a literal lexes to; the SIR `String`
  literal node is unchanged.
- **No new SIR node kind / no new runtime authority:** the only new token type is the lexer-internal
  `Illegal` (never reaches the AST); valid strings flow as ordinary `StringLit` → `Literal{String}`.
- **Source-positioned diagnostics:** invalid escape / unterminated → `OOF-LEX1` carrying the lexer reason.

## Escape set implemented

| sequence | decodes to |
|---|---|
| `\"` | `"` |
| `\\` | `\` |
| `\n` | newline (U+000A) |
| `\t` | tab (U+0009) |
| `\r` | carriage return (U+000D) |

This unblocks the exact case the IgWeb render proofs (P17–P22) routed around — an inline JSON literal:
`"{\"body\":\"ok\"}"` now lexes to `{"body":"ok"}`.

## Invalid-escape / unterminated behavior

`read_string` (`lexer.rs`) returns an **`Illegal` token** (new `TokenType::Illegal`, `value` = reason) on:
- an unsupported escape char → `invalid string escape: \<c>`;
- EOF before the closing `"` → `unterminated string literal`;
- a trailing `\` at EOF → `unterminated string literal (trailing backslash)`.

The parser's `parse_primary` has a `TokenType::Illegal` arm that surfaces the reason verbatim as a
line-positioned **`OOF-LEX1`** diagnostic (and returns `Expr::Error`, so compilation fails cleanly — no
silent lossy output). `Illegal` is safe to add: both `match tok.token_type` sites have `_` arms, and
`TokenType` is otherwise compared by `==`/`matches!`.

## Did existing string behavior change? — No (verified)

**No `.ig` string literal in the tree contains a backslash**, so every existing string decodes byte-for-byte
unchanged. Verified: `rg '\\' --glob '*.ig'` finds backslashes only in `decision_tree/example.ig` — and both
are inside **comments** (ASCII-art), which the lexer skips before `read_string`. Regex literals
(`"^/todos/([^/]+)$"`) use `[^/]+`, not backslash classes, so they are unaffected. The full compiler / VM /
igniter-web suites confirm no behavioral change (below).

## Files changed

- `lang/igniter-compiler/src/lexer.rs` — `TokenType::Illegal` + escape-decoding `read_string`.
- `lang/igniter-compiler/src/parser.rs` — `Illegal` arm in `parse_primary` → `OOF-LEX1`.
- `lang/igniter-compiler/tests/string_escapes_tests.rs` — 10 tests (new).

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test string_escapes_tests → 10 passed (escapes decode; invalid/
    unterminated → Illegal token + OOF-LEX1; ordinary + regex strings unchanged)
$ cd lang/igniter-compiler && cargo test → lib 55, igweb_lowering 11, string_escapes 10, effect-name-parity,
    main — all green; **loop_conformance 4 FAILED (PRE-EXISTING, see below)**
$ cd lang/igniter-vm && cargo test → all green EXCEPT vm_candidate_proof `test_proof_vmg13_local_loops_and_
    service_loops` 1 FAILED (PRE-EXISTING)
$ cd server/igniter-web && cargo test → 17 binaries green (FAILED 0)
$ cd server/igniter-web && cargo test --features machine → 14 binaries green (FAILED 0)
$ git diff --check → clean
```

## Honest report: the only failures are pre-existing loop WIP (not this change)

- `lang/igniter-compiler` `loop_conformance_tests` (4 fail) and `lang/igniter-vm`
  `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops` (1 fail) — all assert loop-node
  generation in SemanticIR (e.g. *"Expected at least one loop_node in SemanticIR"*).
- **Confirmed pre-existing via `git stash` of `lexer.rs` + `parser.rs`:** with my changes removed, the same
  loop tests fail identically (loop_conformance 10 passed / 4 failed; vmg13 1 failed). Loops are a known
  in-progress area (pending `PROP-039 managed-local-recursion-and-loop-classes` / `LANG-BUDGETED-LOCAL-LOOP`),
  unrelated to string lexing — the fixtures contain **no** backslash strings.
- A transient `--features machine` flake observed once (`product_todos_index_empty_returns_app_404`) did NOT
  reproduce on a clean run; it is a parallel-test race on a `process::id()`-keyed temp dir in the read
  harness (pre-existing harness shape), not a lexer regression.

## Deferred (out of scope, honest)

- `\u{...}` / unicode escapes (card-optional; skipped to keep the lexer change minimal/risk-free);
- raw strings, heredocs / multiline syntax (beyond decoded `\n`);
- string interpolation / templates;
- a JSON-literal type; HTML/template syntax.

None are needed for the unblock; revisit only under real pressure (P0 [R3]: wait for a 2nd app).

## Closed scope (honored)

No interpolation; no raw strings; no heredocs; no JSON literal type; no HTML/template syntax; no ViewArtifact
authoring change; no `.igweb` syntax; no VM semantic change beyond preserving decoded literal values; no
canon claim.

## Next (lane sequence)

`LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` (removes the multi-`via`/accumulation ceiling), then
`LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` (optional fields / spread). The render/ViewArtifact examples are
**not** rewritten to use escapes — the P17/P19/P22 proof history stays valid (card guidance).

---

*Lab implementation-proof. Compiled 2026-06-20; string_escapes 10 green; igniter-compiler (lib 55 + igweb 11
+ …) green; igniter-vm green; igniter-web 17 default + 14 machine green; `git diff --check` clean. The only
red tests are pre-existing loop-WIP failures, proven unrelated via `git stash`. `.ig` strings now carry
escapes — the P17–P22 inline-JSON detour is retired at the language level.*
