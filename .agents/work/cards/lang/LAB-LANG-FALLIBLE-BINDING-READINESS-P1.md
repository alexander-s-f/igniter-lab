# LAB-LANG-FALLIBLE-BINDING-READINESS-P1 - Question-mark propagation for Result and Option

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: readiness / design
Delegation code: OPUS-LANG-FALLIBLE-BINDING-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

IgWeb `via` and context-composition work exposed a real ceiling: chaining fallible guards over
`Result[T, Decision]` creates nested `match` expressions and fixed `value` / `error` fields that shadow each
other. Composite guards work, but they are heavier than the common app shape.

During signature-bound surface discussion, a possible third glyph emerged:

```ig
account = LoadAccount(account_id)?
todo = LoadTodo(account, todo_id)?
d = Respond { status: 200, body: todo.title }
```

The `?` should **not** be mixed into the first signature-bound surface. This card should investigate it as a
separate fallible-dataflow surface.

## Goal

Design whether Igniter should support `?` propagation over `Result` and/or `Option`, and if so define the
smallest desugar that preserves graph semantics.

Candidate meaning:

- `expr?` unwraps `Ok` / `Some` into the current binding;
- `Err` / `None` short-circuits to a compatible contract output;
- desugars to explicit `match`, with no hidden runtime authority.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/src/lexer.rs` for existing `?` token;
- `lang/igniter-compiler/src/parser.rs` for postfix operators and optional-field parsing;
- `lang/igniter-compiler/src/typechecker.rs` for built-in `Result[T,E]`, `Option[T]`, and match typing;
- `lang/igniter-compiler/src/emitter.rs` for match lowering;
- fixtures/docs using `Result`, `Option`, `ok`, `err`, `some`, `none`;
- IgWeb docs/cards:
  - `lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md`;
  - `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md`;
  - `lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`;
  - context composition P25/P26 docs if present;
- `LAB-LANG-MATCH-ARM-BINDINGS-P2.md`;
- `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-READINESS-P1.md`.

Confirm or correct:

- whether `?` is already reserved by optional-field syntax and where conflicts appear;
- exact arm fields for built-in `Result` and `Option`;
- whether match desugar can be expressed today after match-arm bindings P2, or needs a separate lowering path;
- whether `?` can be pure; do not assume `pure` forbids `?`;
- what output compatibility rule is possible today.

## Required Questions

Answer directly:

1. Is `?` a postfix expression operator, a binding operator, or both?
2. Should v0 support `Result` only, `Option` only, or both?
3. What is the output compatibility rule for `Err`?
4. What is the output compatibility rule for `None`?
5. Is `?` allowed in `pure contract` when the callee is pure?
6. How does `?` desugar to `match` and preserve graph node identity?
7. Does `?` require `MATCH-ARM-BINDINGS-P2`, or can it lower independently?
8. How does it interact with signature-bound body bindings?
9. Does it unblock multi-`via` / route guards, or only pure `.ig` guard contracts?
10. What diagnostics are needed for `?` on non-fallible values or incompatible outputs?
11. What is the smallest implementation card after readiness?

## Required Deliverable

Create:

```text
lab-docs/lang/lab-lang-fallible-binding-readiness-p1-v0.md
```

It must include:

- live syntax/type findings;
- comparison to explicit `match`;
- Result vs Option decision;
- pure/impure rule;
- desugar sketch;
- output compatibility rule;
- implementation test matrix;
- non-goals.

Update this card with a closing report.

## Closed Scope

- No implementation.
- No signature-bound contract implementation.
- No collection comprehensions.
- No new effect/capability semantics.
- No IgWeb syntax-chain `via` implementation.
- No canon claim.

## Suggested Next

If readiness proves the shape, open `LAB-LANG-FALLIBLE-BINDING-P2` with one non-web `Result` fixture and
one IgWeb-style guard fixture.

---

## Closing Report (2026-06-20)

**Outcome: PROCEED.** Deliverable: `lab-docs/lang/lab-lang-fallible-binding-readiness-p1-v0.md` (all 11
required questions answered against live code).

**Headline findings (verified):**
- `?` is already tokenized (`TokenType::Question`) and **already consumed — but only in TYPE position**
  (`parser.rs:2768`, `field : Type?` → `FieldDecl.optional`, canon-gated by
  `LANG-OPTIONAL-FIELD-PARTIAL-RECORD`). A fallible **`value?` is expression/postfix context**
  (`parse_postfix`, 3337) → **no grammatical conflict**.
- Result = `Ok{value}`/`Err{error}`; Option = `Some{value}`/**`None{}` (empty, no payload)**.

**Design decisions:**
- **Result-only v0** (Option's `None` has no payload to become the short-circuit output; deferred to an
  explicit `else`/default form later).
- `?` is **pure sugar** desugaring (AST→AST, block-level CPS) to nested `match` over the now-CLOSED
  **MATCH-ARM-BINDINGS-P2** (block arms + local `let` + nested match + rename). **No new SIR node kind**, no
  new lowering path, no authority. P2 is a hard prerequisite (and is satisfied).
- **Output rule:** `e : Result[T, E]` requires the contract's declared output `O` with `E` assignable to `O`
  (the `Err` arm yields `error : E` as the output). The canonical guard `Result[T, Decision] → Decision`
  fits exactly.
- **Pure:** allowed in `pure contract` iff the callee is pure; `?` adds no effect.
- **Unblocks** pure `.ig` guard-contract chains directly; route-level `via` is host-side (separate), benefits
  indirectly only.
- **Diagnostics:** `OOF-Q1` (non-Result / Option), `OOF-Q2` (Err type ≠ output), `OOF-Q3` (`?` not at a
  binding RHS).

**No code changed** (readiness). **Next:** `LAB-LANG-FALLIBLE-BINDING-P2` — Result-only postfix `?` +
block-CPS desugar, the `E = O` rule, test matrix + one non-web `Result` fixture + one IgWeb `Result[T,
Decision]` guard fixture.
