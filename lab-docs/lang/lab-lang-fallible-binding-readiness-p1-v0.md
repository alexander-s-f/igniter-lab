# lab-lang-fallible-binding-readiness-p1-v0 — `?` propagation for Result / Option

**Card:** `LAB-LANG-FALLIBLE-BINDING-READINESS-P1` · **Delegation:** `OPUS-LANG-FALLIBLE-BINDING-P1`
**Status:** CLOSED (readiness/design — **no implementation**). Recommends a `Result`-only postfix `?` that
desugars to nested `match` over the now-CLOSED `MATCH-ARM-BINDINGS-P2` substrate. No new SIR node kind, no
runtime authority, no canon claim. Optional fields stay on the canon PROP track.
**Authority:** Lab tooling design.

## Live syntax / type findings (verified)

| Question | Live finding |
|---|---|
| Is `?` tokenized? | **Yes** — `TokenType::Question` (`lexer.rs:27`, emitted at 504-508). |
| Is `?` already consumed? | **Yes, but only in TYPE position** — `parser.rs:2768` reads `?` after a field's type annotation to set `FieldDecl.optional` (the optional-field surface, canon-gated by `LANG-OPTIONAL-FIELD-PARTIAL-RECORD`). |
| Conflict with `expr?`? | **None.** The existing `?` is in a **type-annotation** context (`field : Type?` inside `type X { … }`). A fallible `value?` is in **expression/postfix** context (`parse_postfix`, `parser.rs:3337`). Different grammar productions — no ambiguity. |
| Result arm fields | `Ok { value }`, `Err { error }` (`typechecker.rs:369-373`). |
| Option arm fields | `Some { value }`, **`None {}` — empty, no payload** (`typechecker.rs:364-365`). |
| Match typing | `infer_match_expr` (5667) + `sealed_arm_field_types` (383) already bind arm fields; `infer_sealed_construct` (5441) builds `ok()/err()/some()/none()`. |
| Postfix attach point | `parse_postfix` is a clean `loop` over `.field` / `[index]` / `(call)` — adding an `else if Question` arm is the natural, isolated hook. |

## Comparison to explicit `match` (the pain `?` removes)

The IgWeb guard / context-composition shape today (after P2) is:

```ig
compute d : Decision = match LoadAccount(account_id) {
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

The proposed `?` collapses the staircase:

```ig
compute d : Decision = {
  let account = LoadAccount(account_id)?
  let todo    = LoadTodo(account, todo_id)?
  Respond { status: 200, body: todo.title }
}
```

Both compile to the **same nested-match SIR**. `?` is pure presentation over P2.

## Answers to the 11 required questions

1. **Postfix or binding operator?** Syntactically a **postfix expression operator** (`e?`), but it is only
   *meaningful at a binding position inside a block whose value is the contract output* (`let x = e?`).
   Parse it as postfix (producing a `Try` marker), reject it elsewhere with a diagnostic.
2. **Result / Option / both?** **`Result` only in v0.** `Option`'s `None {}` carries **no payload**, so there
   is nothing to become the short-circuit output without an explicit default — deferred.
3. **Err output-compat rule?** `e : Result[T, E]`. The `Err` arm yields `error : E`, which **must be
   assignable to the contract's declared output type** (v0: `E` equals the output type, or `E` is
   `Unknown`-compatible per the existing P9/P11 output rule). The canonical guard shape
   `Result[T, Decision]` with `output : Decision` satisfies this exactly.
4. **None output-compat rule?** N/A in v0 (Option deferred). If added: `None` needs an explicit default form
   (`e ? else <value>`) because there is no payload to carry — out of scope here.
5. **Allowed in `pure contract`?** **Yes, iff the callee is pure.** `?` desugars to `match` (pure); it adds
   no effect, capability, or authority. `pure` does not forbid `?` — it forbids *effects*, and `?` has none.
6. **Desugar + graph node identity?** `?` lowers to ordinary `match` + block `let` nodes — the **same node
   kinds P2 already emits**. No new SIR node kind. Node identity is the match/let chain; source-map spans
   anchor to the `?` token for diagnostics/time-travel.
7. **Requires `MATCH-ARM-BINDINGS-P2`?** **Yes — it is the substrate.** The Ok arm must bind the unwrapped
   value and carry the *rest of the block* as its body (block arm + local `let` + nested match + outer
   rename). All of that is exactly what P2 (now CLOSED) delivers. `?` cannot lower cleanly without it.
8. **Interaction with signature-bound body bindings?** Orthogonal and composable: `?` is the **RHS postfix**;
   the binding arrow (`=` today, `<-` later) is the LHS. `account = LoadAccount(id)?` is binding(`=`) of
   postfix(`?`). No grammar overlap.
9. **Unblocks multi-`via` / route guards?** It unblocks **pure `.ig` guard-contract chains**
   (`Result[T, Decision]`) directly. Route-level `via` is host-side wiring (a separate lowering) and only
   benefits indirectly — `?` does not implement route `via`.
10. **Diagnostics needed?**
    - `?` on a non-`Result` value → `OOF-Q1: ? applies only to Result[T, E]` (Option → "not supported in
      v0").
    - `Err` payload `E` not assignable to the declared output type → `OOF-Q2: ? error type E not compatible
      with output O`.
    - `?` outside a binding inside an output-producing block (e.g. nested in an arbitrary subexpression) →
      `OOF-Q3: ? is only allowed as a binding right-hand side`.
11. **Smallest implementation card?** `LAB-LANG-FALLIBLE-BINDING-P2` (Result-only, below).

## Desugar sketch (block-level CPS over P2)

A `?`-binding rewrites the **remainder of its block** into the `Ok` arm; `Err` becomes the block value:

```
{ let x = e?   <rest…> }
   ⇩  (AST→AST, before/with typecheck)
match e {
  Ok  { value } => { let x = value   desugar(<rest…>) }
  Err { error } => error
}
```

- `<rest…>` = the block's remaining statements + return expression, recursively desugared (so multiple `?`
  in a row nest left-to-right).
- The innermost block value is the contract output; every `Err` short-circuits to `error`, which is why
  `E` must equal the output type.
- Pure AST→AST using P2's `Expr::Block` + `Expr::MatchExpr`; **no new node kind, no new lowering path** in
  the emitter or VM.

Suggested marker: a `Try`/postfix node in `parse_postfix` (`else if Question`), expanded by a small desugar
pass that walks `Expr::Block` statements and applies the CPS rewrite when a `let`'s RHS is a `Try`.

## Output compatibility rule (concrete)

`?` is well-typed iff: (a) the operand types to `Result[T, E]`; (b) the enclosing contract has a declared
output type `O`; (c) `E` is assignable to `O` (equal, or `Unknown`-compatible). On success the binding's name
has type `T`. This reuses the existing nominal output check — no new type machinery.

## Pure / impure rule

`?` is pure. A contract using `?` is `pure` iff every `?` operand (the callee producing the `Result`) is
pure. Effects come from the callee, never from `?` itself.

## Implementation test matrix (for P2)

| Case | Expectation |
|---|---|
| single `?` on `Result[T, O]`, Ok path | binds `T`, compiles |
| single `?`, Err path | yields `error : O` as the output |
| chained `?` (≥2) | nests left-to-right; first Err short-circuits |
| `?` on `Result[T, E]`, `E ≠ O` | `OOF-Q2` |
| `?` on non-Result (e.g. Integer) | `OOF-Q1` |
| `?` on `Option` | `OOF-Q1` ("not supported in v0") |
| `?` not at a binding RHS | `OOF-Q3` |
| `pure contract` + pure callee + `?` | compiles pure |
| serialization parity | `?` SIR byte-identical to hand-written nested match |
| IgWeb guard fixture (`Result[T, Decision]`) | guard chain compiles + lowers to nested match |

## Non-goals

No implementation; no Option `?`; no `else`/default form; no signature-bound `<-`; no collection
comprehensions; no route-level `via`; no new effect/capability; no optional-field semantics (canon PROP
track); no canon claim.

## Recommendation

**Proceed.** The shape is clean, conflict-free, and rides entirely on closed primitives (P2 block arms +
built-in `Result`). Open `LAB-LANG-FALLIBLE-BINDING-P2`: Result-only postfix `?` + block-CPS desugar to
nested `match`, the `E`-assignable-to-`O` rule, and the test matrix above with one non-web `Result` fixture
and one IgWeb-style `Result[T, Decision]` guard fixture.

---

*Readiness/design only — verified against live lexer/parser/typechecker (2026-06-20). `?` is tokenized and
used solely for type-position optional fields; expression-position `?` is conflict-free. v0 = Result-only,
pure sugar to nested match over MATCH-ARM-BINDINGS-P2, Err→output requires `E = O`. Next:
LAB-LANG-FALLIBLE-BINDING-P2.*
