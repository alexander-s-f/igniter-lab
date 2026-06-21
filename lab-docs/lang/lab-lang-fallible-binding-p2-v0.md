# lab-lang-fallible-binding-p2-v0 — Result-only postfix `?`

**Card:** `LAB-LANG-FALLIBLE-BINDING-P2` · **Delegation:** `OPUS-LANG-FALLIBLE-BINDING-P2`
**Status:** CLOSED (lab implementation-proof) — Result-only postfix `?` at `let`-binding positions inside
output-producing blocks. **Pure sugar**: desugars (at parse time) to a nested `match` over the now-CLOSED
`MATCH-ARM-BINDINGS-P2` substrate; the `?` SIR is **byte-identical** to the hand-written match. No new SIR
node kind, no effect/capability semantics, no canon claim. Option deferred.
**Authority:** Lab tooling. Implements `LAB-LANG-FALLIBLE-BINDING-READINESS-P1`.

## Exact syntax implemented

```ig
compute d : Decision = {
  let account = load_account?     -- load_account : Result[Acct, Decision]
  let todo    = load_todo?        -- load_todo    : Result[Todo, Decision]
  { code: todo.title }
}
```

- `?` is a **postfix** operator (`parse_postfix`); valid only as a **`let` binding RHS inside a block** whose
  value is the contract output.
- Two enabling parser additions: (a) `?` postfix in expression position (the type-position `?` for optional
  fields is unaffected — it's parsed in field decls); (b) a `{` whose first token is `let` now parses as a
  **block** (`compute d = { let … value }`), not a record literal (`{ let …` was never valid record syntax),
  so compute bodies can host `?` bindings. Match-arm blocks already parsed via P2; this extends blocks to
  expression position.

## Restrictions (v0)

- **Result only.** `?` on `Option` → `OOF-Q1: ? is not supported on Option in v0 (Result only)`.
- **Binding RHS only.** `?` anywhere else (e.g. `compute d = e?`) → `OOF-Q3: ? is only allowed as a `let`
  binding right-hand side inside an output-producing block`.
- **`E` must equal the output `O`.** Enforced for free by match arm-type unification (see below).
- Pure: `?` adds no effect; a `pure contract` using pure fallible inputs stays pure.

## Desugar model (parse-time, AST → AST)

A block's `let name = expr?` rewrites the **remainder of the block** into the Ok arm; Err short-circuits to
the output:

```
{ let name = e?   <rest…> }
   ⇩
match e {
  Ok  { value } => { let name = value   <rest…> }
  Err { error } => error
}
```

Multiple `?` nest left-to-right (the rest is recursively desugared). Implemented as a guarded pure AST
rewrite in `Parser::parse()` (`desugar_try_in_contracts`): **only `?`-bearing compute exprs are touched** —
every other tree is returned unchanged, so non-`?` programs are byte-identical. The rewrite emits ordinary
`Expr::MatchExpr` + `Expr::Block` + `Stmt::Let` (all from P2) — **no new node kind**; `Try` never reaches the
typechecker for valid uses, and never reaches the SIR.

## Output compatibility rule (`E == O`, for free)

The desugared match's `Ok` arm yields the continuation (eventually the output `O`); the `Err` arm yields
`error : E`. The existing `unify_match_arm_types` requires both arms to agree, so `E ≠ O` is rejected
(`Binding type mismatch: declared O, got E`). No bespoke compatibility check was needed — the match layer
already enforces it.

## Parser / typechecker / emitter / classifier changes

| File | Change |
|---|---|
| `parser.rs` | new `Expr::Try { expr }`; postfix `?` in `parse_postfix`; `{ let … }` parses as a block; parse-time `desugar_try_*` pass (guarded by `expr_contains_try`) |
| `typechecker.rs` | `infer_expr` `Try` arm → `OOF-Q3` (only fires for misplaced `?`, valid ones are desugared away); `expr_kind` += `try`; `infer_match_expr` brands the `?`-desugar signature (exactly `Ok`/`Err` arms) — non-Result subject → `OOF-Q1 "? applies only to Result"`, `Option` subject → `OOF-Q1 "not supported on Option in v0"` |
| `emitter.rs` | none — desugared `match`/`block` lower via the proven P2 path |
| `classifier.rs` | `expr_kind` += `try` |
| `form_resolver.rs` | `Expr::Try` added to the ignore group (exhaustiveness) |

## SIR parity (proof)

Compiling the `?` form and the hand-written

```ig
match r { Ok { value } => { let account = value  { code: account.id } }  Err { error } => error }
```

produces a **byte-identical `match_node`** in `semantic_ir_program.json`, and **no `try` node** survives into
the SIR. (Test `question_sir_identical_to_handwritten_match` asserts both. A redundant empty-block wrapper in
the continuation was removed so the desugar matches the hand-written shape exactly.)

## Diagnostics (live output)

```text
let x = n?   (n : Integer)          → OOF-Q1 ? applies only to Result[T, E], got 'Integer'
let x = o?   (o : Option[Integer])  → OOF-Q1 ? is not supported on Option in v0 (Result only)
let a = r?   (r : Result[A, Other], output Decision)
                                    → Binding type mismatch: declared Decision, got Other   (E ≠ O)
compute d : Decision = r?           → OOF-Q3 ? is only allowed as a `let` binding right-hand side …
```

The OOF-Q1 branding only triggers on the `?`-desugar signature (exactly `Ok`/`Err` arms over a
non-Result/Option subject) — a hand-written `match result { Ok … Err … }` over a real `Result` is unaffected
(regression test `handwritten_result_match_still_compiles`).

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test fallible_binding_tests → 10 passed
    (single ?; chained ?; IgWeb-style guard chain; pure contract; non-Result→Q1; Option→Q1; E≠O reject;
     misplaced→Q3; hand-written match regression; SIR parity vs nested match)
$ cd lang/igniter-compiler && cargo test                               → 172 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test match_arm_bindings_tests        → 6 passed
$ cd lang/igniter-compiler && cargo test --test signature_contract_surface_tests → 5 passed
$ cd lang/igniter-compiler && cargo test --test record_spread_tests             → 9 passed
$ cd lang/igniter-compiler && cargo test --test string_escapes_tests            → 10 passed
$ cd lang/igniter-compiler && cargo test --test loop_conformance_tests          → 14 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests            → 11 passed
$ cd server/igniter-web    && cargo test                               → 17 binaries green
$ git diff --check                                                     → clean
```

## Acceptance — mapping

- [x] Single `?` on `Result[T, Decision]` binds `T` and compiles.
- [x] Chained two-`?` block compiles and avoids `value` shadowing.
- [x] Hand-written nested match and `?` version produce **byte-identical** SIR.
- [x] `?` on non-Result is rejected (`OOF-Q1`).
- [x] `?` on Option is rejected with a v0 diagnostic (`OOF-Q1 "not supported on Option in v0"`).
- [x] `Result[T, E]` with `E` incompatible with output is rejected.
- [x] `?` outside a binding RHS is rejected (`OOF-Q3`).
- [x] Pure contract using pure fallible calls stays pure.
- [x] Existing match-arm bindings tests green (6).
- [x] Existing signature-bound contract tests green (5).
- [x] IgWeb-style `Result[T, Decision]` guard fixture compiles.
- [x] `lang/igniter-compiler cargo test` green (172/0).
- [x] `git diff --check` clean.

## Deferred / out of scope (honored)

No Option `?`; no `? else`/default; no route-level IgWeb `via` syntax; no effect/capability semantics; no
collection comprehensions; no signature-bound `<-`. The success-path record literal inside a `?` chain is not
nominally shape-checked against `O` (it types Unknown-compatible inside the match arm — same v0 limitation as
match-arm-bindings); the Err path's `E == O` is fully enforced.

## Next

App-pressure proof: rewrite one composite guard / Todo context chain with `?` (no IgWeb `via` syntax yet).

---

*Lab implementation-proof. Compiled 2026-06-21; igniter-compiler 172/0 (incl. 10 new), match-arm 6,
signature 5, record-spread 9, escapes 10, loops 14, igweb 11, igniter-web 17 green; `git diff --check`
clean. `?` is pure parse-time sugar to a nested match over MATCH-ARM-BINDINGS-P2 — byte-identical SIR, E=O
enforced free by arm unification, branded OOF-Q1/Q3 diagnostics, no new node kind, no authority.*
