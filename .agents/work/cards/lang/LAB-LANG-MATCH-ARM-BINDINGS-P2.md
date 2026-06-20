# LAB-LANG-MATCH-ARM-BINDINGS-P2 - Bind local names inside block and match arms

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: implementation-proof
Delegation code: OPUS-LANG-MATCH-ARM-BINDINGS-P2
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` found that the real blockage is not graph semantics; it is a
half-built local binding surface:

- `BlockBody` and `let` parsing already exist;
- if/else branches already use block bodies;
- match arms currently accept only a single expression;
- `let` statements do not bind their name in typechecker scope, so `{ let a = x  a }` fails with `OOF-P1`;
- built-in `Result[T,E]` has fixed fields (`value` / `error`), and without branch-local names nested
  `match` arms shadow each other.

This card should turn the readiness result into the smallest implementation proof: local names must work in
blocks, and match arms must be allowed to use those blocks.

## Goal

Implement the minimum language slice:

```ig
match result {
  Ok { value } => {
    let account = value
    call_contract("Next", account)
  }
  Err { value } => value
}
```

The implementation should preserve pure graph lowering: no new effect semantics, no ordered runtime authority,
no new IgWeb syntax.

## Verify First

Read the live code before editing:

- `lang/igniter-compiler/src/parser.rs`
  - `BlockBody`
  - `parse_let_stmt`
  - `parse_if_expr`
  - `parse_match_expr`
  - `parse_match_arm_inner`
- `lang/igniter-compiler/src/typechecker.rs`
  - block typing / `Stmt::Let`
  - name resolution and scope handling
  - match arm typing
- `lang/igniter-compiler/src/emitter.rs`
  - `BlockBody` emission
  - match emission
- live fixtures/tests using `let`, `if`, `match`, `Result`, `Option`, and variants;
- `lab-docs/lang/lab-lang-match-arm-bindings-readiness-p1-v0.md`.

Confirm or correct:

- whether `let` is parsed in block bodies but not registered in scope;
- whether `if` blocks should begin working automatically once `let` scope is fixed;
- whether match arms can reuse the same `ExprOrBlock` / `BlockBody` path as if/else;
- whether emitter already handles block bodies for any expression position;
- whether the implementation needs parser changes only, typechecker changes only, or both.

Live code wins over this card.

## Recommended Implementation Shape

Prefer the narrowest path:

1. Fix `let` binding in `BlockBody` typing.
   - A `let name = expr` should typecheck `expr`, bind `name` in the block-local environment, and allow later
     statements / final expression to resolve it.
   - Keep block scoping local: names do not leak outside the block.
2. Allow match arm bodies to be blocks, not only expressions.
   - Reuse existing `ExprOrBlock` / `BlockBody` machinery if possible.
   - Do not add `where`, `let..in`, or pattern alias syntax in this card.
3. Add focused compiler tests.
   - Include one non-web arithmetic/block fixture.
   - Include one nested `Result` fixture proving outer `value` can be renamed with `let` before an inner match.
   - Include one match-arm block fixture with at least two local lets.

If a direct match-arm block is unexpectedly large, stop and document the blocker; do not invent a parallel
block grammar.

## Required Acceptance

- [x] `if` / block-local `let` binds and compiles: `{ let a = x  a }` no longer emits unresolved symbol.
- [x] `let` names are block-local and do not leak after the block.
- [x] match arms accept block bodies.
- [x] match-arm local lets are available to the arm final expression.
- [x] nested `Result` match can preserve an outer `value` by binding it to a new local name before an inner `match`.
- [x] existing match expression tests remain green.
- [x] existing if/block expression tests remain green.
- [x] no IgWeb syntax or lowering changes.
- [x] no new SIR node kind (block reuses the existing `let`-chain lowering / VM `let` handler).
- [x] diagnostics remain stable/improve (`OOF-P1` for out-of-scope locals).
- [x] `cargo test --test string_escapes_tests` green (10).
- [x] `cargo test --test loop_conformance_tests` green (14).
- [x] full `lang/igniter-compiler cargo test` green (143/0); one unrelated pre-existing VM red isolated below.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Outcome:** branch-local `let` now works in `if` blocks **and** `match` arm blocks — the readiness root
cause (half-built `let`) is fixed. Proof doc: `lab-docs/lang/lab-lang-match-arm-bindings-p2-v0.md`.

**Root cause:** the typechecker's `IfExpr` typed each branch's final expr with the **outer** scope, never
binding the block's `let` names (`OOF-P1: Unresolved symbol`); and match arms only accepted a single
expression. Fix: (1) typechecker `infer_block_scope` types a block's `let`s into a **child** scope (used by
`IfExpr` + a new `Expr::Block` arm); (2) parser parses a `{ … }` arm body into `Expr::Block`; (3) emitter
lowers a `block` node via the existing `emit_function_body` **`let`-chain** (VM `let` handler already runs
it — **no new SIR node kind**); (4) classifier `collect_block_refs` excludes `let` names from refs (mirrors
lambda `params`); form_resolver exhaustiveness.

**The unblock:** `let outer = value` renames `Result`'s fixed `value` so a nested `Ok { value }` no longer
shadows it — the multi-`via` ceiling P20 deferred is now liftable (separate card).

**Proof — all green:** match_arm_bindings_tests **6**; igniter-compiler **143/0**; string_escapes 10;
loop_conformance 14; igweb lowering 11; igniter-web 17. `git diff --check` clean. Files: parser,
typechecker, classifier, emitter, form_resolver + 1 new test file.

**Pre-existing unrelated red (isolated):** `igniter-vm`
`vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops` →
`OP_GET_FIELD: expected Record, got Integer(1710000000)` (a loops/`now()`/timestamp path). **Confirmed
pre-existing** — with this card's compiler changes `git stash`ed, it fails **identically**; structurally
unrelated to block/`let`/match (the real `loop_conformance` suite is 14/0 green).

**Next:** IgWeb composite-guard simplification using arm-block lets; `LAB-LANG-FALLIBLE-BINDING-READINESS-P1`
(`?` desugars onto this `let`+block substrate).

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-match-arm-bindings-p2-v0.md
```

It must include:

- live root cause of the old `let` failure;
- exact parser/typechecker/emitter files changed;
- examples of working if-block local let and match-arm block local let;
- nested `Result` shadowing proof;
- whether lowering reused existing block machinery or required a new representation;
- exact test commands and counts;
- what remains deferred.

Update this card with a closing report.

## Closed Scope

- No `where` syntax.
- No `let..in` syntax.
- No pattern alias / pattern rename unless it falls out as a trivial diagnostic-only helper; default is no.
- No multi-`via` IgWeb syntax.
- No context-composition IgWeb changes.
- No user-generic type changes.
- No new effect/capability semantics.
- No canon claim.

## Suggested Next

If P2 lands cleanly, open a small IgWeb pressure proof that uses match-arm block bindings to simplify a
composite guard or multi-step context fixture. Do not open syntax-chain `via` until this base language slice
is proven ergonomic in at least one app-shaped fixture.
