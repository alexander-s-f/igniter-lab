# lab-lang-match-arm-bindings-p2-v0 — local names in block and match arms

**Card:** `LAB-LANG-MATCH-ARM-BINDINGS-P2` · **Delegation:** `OPUS-LANG-MATCH-ARM-BINDINGS-P2`
**Status:** CLOSED (lab implementation-proof) — branch-local `let` bindings now work in `if` blocks **and**
`match` arm blocks. Pure-graph lowering preserved (block → `let`-chain, the existing function-body lowering;
**no new SIR node kind**, no ordered effects, no IgWeb change, no canon claim).
**Authority:** Lab tooling. Implements the P1 readiness (fix the half-built `let`, let arms be blocks).

## Root cause (from readiness, now confirmed in code)

The block/`let` surface was half-built:
- `BlockBody` + `parse_let_stmt` existed (if/else branches), and the emitter already lowered a `BlockBody`
  to a right-nested `let`-chain (`emit_function_body`) which the VM `let` handler runs.
- **But the typechecker never bound `let` names:** `infer_expr`'s `IfExpr` arm typed each branch's final
  expression with the **outer** `symbol_types`, so `if x==1 { let a = x  a } else { 0 }` reported
  `OOF-P1: Unresolved symbol: a` (the `a` Ref at `infer_expr` was looked up in a scope that never gained
  `a`).
- **And match arms only accepted a single expression** (`parse_match_arm_inner` → `parse_expr`), so a block
  arm was impossible; once a `block` reached the typechecker it hit `OOF-TY0: Unsupported expression kind:
  "block"`.

## What changed (parser + typechecker + classifier + emitter + form_resolver)

| File | Change |
|---|---|
| `parser.rs` | new `Expr::Block(BlockBody)` variant; `parse_match_arm_inner` parses a `{ … }` arm body into `Expr::Block` (a `{` in normal expr position stays a record literal, so blocks are recognized only at the arm-body position) |
| `typechecker.rs` | new `infer_block_scope` (types a block's `let`s left-to-right into a **child** scope); `IfExpr` arm now types each branch's final expr in that child scope; new `Expr::Block` arm; `expr_kind` += `block` |
| `classifier.rs` | new `collect_block_refs` (collects a block's refs **excluding** its `let`-bound names — mirrors the lambda-`params` exclusion); `IfExpr`/`Expr::Block` use it; `expr_kind` += `block` |
| `emitter.rs` | `semantic_expr` lowers a `block` node via `emit_function_body` (the existing right-nested `let`-chain) — **reuses block machinery, no new node kind** |
| `form_resolver.rs` | `Expr::Block(_)` added to the ignore group (exhaustiveness) |

**Scope rule:** `let` names are **block-local** — visible only within the block, after their declaration
(incl. the final expr and later `let`s); they do **not** leak past the block. The block body remains a DAG
(`let` = a named subexpression); no ordered effects, no authority — purity/determinism untouched.

## Working examples (all compile clean)

```ig
-- if-block local let (was OOF-P1)
compute r : Integer = if x == 1 { let a = x  a } else { 0 }

-- match-arm block with local lets
match r { Ok { value } => { let a = value  let b = a  b }  Err { error } => error }

-- nested Result: RENAME the outer value so the inner match's Ok{value} doesn't shadow it (the P20 unblock)
match r {
  Ok { value } => {
    let outer = value
    match r { Ok { value } => outer  Err { error } => error }   -- `outer` still in scope
  }
  Err { error } => error
}
```

## Lowering — reused, not new

A `block` lowers to the **same right-nested `let`-chain** `emit_function_body` already produces for `def`
function bodies; the VM `let` handler "already threads a continuation `body`, so no new node kind is needed"
(emitter comment, `emit_function_body`). So a match-arm block is lowered + evaluated by proven machinery.

## Diagnostics

- block-local `let` referenced outside its block → `OOF-P1: Unresolved symbol` (block-locality enforced).
- (unchanged) unresolved refs, type mismatches still produce their existing diagnostics.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test match_arm_bindings_tests → 6 passed
    (if-block let; block-local-no-leak; match-arm block w/ 2 lets; nested-Result rename; arithmetic
     let-chain; plain match arm unchanged)
$ cd lang/igniter-compiler && cargo test                                 → 143 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test string_escapes_tests     → 10 passed
$ cd lang/igniter-compiler && cargo test --test loop_conformance_tests   → 14 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests     → 11 passed
$ cd server/igniter-web    && cargo test                                 → 17 binaries green
$ git diff --check                                                       → clean
```

**Unrelated pre-existing red (isolated per card):** `igniter-vm` →
`vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops` fails with
`OP_GET_FIELD: expected Record, got Integer(1710000000)` — a **timestamp/field-access** error in the
loops/service-loops/`now()` path. **Confirmed pre-existing:** with this card's compiler changes `git stash`ed,
the test fails **identically**. It is structurally unrelated to block/`let`/match (no loops/time/OP_GET_FIELD
touched); the real loop suite (`loop_conformance_tests`) is 14/0 green.

## Acceptance — mapping

- [x] `if`/block-local `let` binds + compiles (`{ let a = x  a }` no longer unresolved).
- [x] `let` names are block-local; do not leak (proven by the leak test → `Unresolved symbol: a`).
- [x] match arms accept block bodies; arm-local lets available to the final expr.
- [x] nested `Result` preserves an outer `value` via a renamed `let` before an inner match.
- [x] existing match / if / block tests green; no IgWeb syntax/lowering change.
- [x] no new SIR node kind (block reuses the `let`-chain lowering).
- [x] diagnostics stable/improved (`OOF-P1` for out-of-scope locals).
- [x] `string_escapes_tests` (10) + `loop_conformance_tests` (14) green.
- [x] full `lang/igniter-compiler cargo test` green (143/0); the one VM red is pre-existing + unrelated (isolated above).
- [x] `git diff --check` clean.

## Out of scope / deferred (honored)

No `where`, no `let..in`, no pattern alias/rename; no multi-`via` IgWeb syntax (now **unblocked** by this
slice — a separate card); no context-composition change; no user-generic types; no new effect/capability
semantics; no canon claim.

## Next

The branch-local binding ceiling is gone, which **unblocks** two follow-ons:
1. a small IgWeb pressure proof rewriting a composite guard / multi-step context with match-arm block lets;
2. `LAB-LANG-FALLIBLE-BINDING-READINESS-P1` (`?` over Result/Option) — `let`+block is the substrate it
   desugars onto.

---

*Lab implementation-proof. Compiled 2026-06-20; igniter-compiler 143/0 (incl. 6 new), string_escapes 10,
loop_conformance 14, igweb lowering 11, igniter-web 17 green; one pre-existing unrelated VM red isolated
(fails identically with changes stashed); `git diff --check` clean. Branch-local `let` works in if + match
blocks via the existing `let`-chain lowering — no new SIR node kind, no authority, the multi-`via` ceiling
lifted.*
