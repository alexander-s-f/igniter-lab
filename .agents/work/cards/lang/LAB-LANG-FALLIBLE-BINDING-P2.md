# LAB-LANG-FALLIBLE-BINDING-P2 - Result-only postfix question propagation

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: implementation-proof
Delegation code: OPUS-LANG-FALLIBLE-BINDING-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-FALLIBLE-BINDING-READINESS-P1` recommends a Result-only postfix `?` over the now-landed
`MATCH-ARM-BINDINGS-P2` substrate.

Goal shape:

```ig
compute d : Decision = {
  let account = LoadAccount(account_id)?
  let todo = LoadTodo(account, todo_id)?
  Respond { status: 200, body: todo.title }
}
```

Desugar:

```ig
match LoadAccount(account_id) {
  Ok { value } => {
    let account = value
    match LoadTodo(account, todo_id) {
      Ok { value } => { let todo = value  Respond { status: 200, body: todo.title } }
      Err { error } => error
    }
  }
  Err { error } => error
}
```

This is pure syntax over `Result[T,E]`; no new effect semantics.

## Goal

Implement v0 postfix `?` for `Result[T, E]` at binding RHS positions inside output-producing blocks.

Rules:

- operand must type to `Result[T, E]`;
- success binds the name as `T`;
- `Err { error }` short-circuits to the enclosing contract output;
- `E` must be assignable/equal to the enclosing output type `O`;
- Option is explicitly unsupported in v0;
- `?` is pure when its operand is pure.

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/lexer.rs`
  - `TokenType::Question`;
- `lang/igniter-compiler/src/parser.rs`
  - `parse_postfix`;
  - `Expr`;
  - `BlockBody` / `Stmt::Let`;
  - match parsing;
- `lang/igniter-compiler/src/typechecker.rs`
  - `Result` / `Option` sealed generic definitions;
  - block typing from `MATCH-ARM-BINDINGS-P2`;
  - match typing;
  - output type resolution;
- `lang/igniter-compiler/src/emitter.rs`
  - block/match lowering;
- `lang/igniter-compiler/src/classifier.rs` / `form_resolver.rs`
  - expression exhaustiveness;
- readiness packet:
  - `lab-docs/lang/lab-lang-fallible-binding-readiness-p1-v0.md`;
- tests from `match_arm_bindings_tests`.

Confirm or correct:

- whether `?` can be represented as a temporary `Expr::Try` then desugared;
- where to run the desugar (parser, typechecker preprocessing, emitter preprocessing);
- how to get the enclosing contract output type for compatibility;
- whether v0 should require the `?` to appear exactly as a `let` RHS;
- whether signature-bound body bindings should support `x = Fallible()?` now or be deferred.

Live code wins over this card.

## Recommended Implementation Shape

Prefer the smallest safe slice:

- parse postfix `expr?` into a marker expression;
- accept it only in a block `let name = expr?`;
- desugar a block containing `?` lets into nested `match` / block / let AST before emission;
- typecheck that operand is `Result[T,E]` and `E` matches the enclosing output type;
- reject Option with a clear v0 diagnostic.

If signature-bound body bindings complicate output-context discovery, defer `x = Fallible()?` in signature
contracts and prove canonical `compute d = { let x = ...? ... }` first.

## Required Acceptance

- [x] Single `?` on `Result[T, Decision]` binds `T` and compiles.
- [x] Chained two-`?` block compiles and avoids `value` shadowing.
- [x] Hand-written nested match and `?` version produce **byte-identical** SIR.
- [x] `?` on non-Result is rejected (`OOF-Q1`).
- [x] `?` on Option is rejected with "not supported in v0" style diagnostic (`OOF-Q1`).
- [x] `Result[T,E]` where `E` is not compatible with output is rejected.
- [x] `?` outside a binding RHS is rejected (`OOF-Q3`).
- [x] Pure contract using pure fallible calls remains pure.
- [x] Existing match-arm bindings tests remain green (6).
- [x] Existing signature-bound contract tests remain green (5).
- [x] IgWeb-style `Result[T, Decision]` guard fixture compiles.
- [x] `lang/igniter-compiler cargo test` green (172/0).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Outcome:** Result-only postfix `?` works as pure parse-time sugar. Proof doc:
`lab-docs/lang/lab-lang-fallible-binding-p2-v0.md`.

**Model:** `let name = expr?` inside an output-producing block desugars (in `Parser::parse()`, guarded so only
`?`-bearing exprs change) to `match expr { Ok { value } => { let name = value  <rest…> }  Err { error } =>
error }` — reusing MATCH-ARM-BINDINGS-P2. Multiple `?` nest left-to-right. **No new SIR node kind**; the `?`
SIR is **byte-identical** to the hand-written nested match (proven).

**Two parser enablers:** postfix `?` (`Expr::Try`) in `parse_postfix` (type-position optional-field `?`
untouched); and a `{` starting with `let` now parses as a **block** in expression position (P2 only parsed
blocks in match arms) — required so `compute d = { let … }` can host `?`.

**Output rule (`E == O`) for free:** the desugared match's arms (`Ok`→O, `Err`→E) are unified by the existing
`unify_match_arm_types`, so `E ≠ O` is rejected with no bespoke check.

**Diagnostics:** `OOF-Q3` (misplaced `?`, from the surviving `Try`); `OOF-Q1` branded in `infer_match_expr`
on the `?`-desugar signature (exactly `Ok`/`Err` arms) — non-Result → "applies only to Result", Option →
"not supported on Option in v0". Hand-written Result matches are unaffected (regression-tested).

**Proof — all green:** fallible_binding_tests **10**; igniter-compiler **172/0**; match-arm 6; signature 5;
record-spread 9; escapes 10; loops 14; igweb 11; igniter-web 17. `git diff --check` clean. Files: parser,
typechecker, classifier, form_resolver + 1 new test file (emitter unchanged — rides P2).

**Deferred:** Option `?`, `? else`, route-level `via`, signature-bound `<-`; success-path record literal in a
`?` chain isn't nominally shape-checked against O (Unknown-compatible inside the arm — same v0 limit as
match-arm-bindings; the Err `E==O` path is fully enforced).

**Next:** app-pressure proof rewriting one composite guard / Todo context chain with `?` (no IgWeb `via`
syntax yet).

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-fallible-binding-p2-v0.md
```

It must include:

- exact syntax implemented;
- exact restrictions (Result-only, binding RHS only, Option deferred);
- desugar model;
- output compatibility rule;
- parser/typechecker/emitter/classifier changes;
- SIR parity evidence;
- diagnostics examples;
- exact test commands and counts;
- what remains deferred.

Update this card with a closing report.

## Closed Scope

- No Option `?`.
- No `? else`.
- No route-level IgWeb `via` syntax changes.
- No effect/capability semantics.
- No collection comprehensions.
- No signature-bound `<-` boundary syntax.
- No canon claim.

## Suggested Next

If P2 lands, open an app-pressure proof that rewrites one composite guard or Todo context chain with `?`,
without adding IgWeb `via` syntax yet.
