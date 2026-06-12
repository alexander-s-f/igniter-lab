# LANG-UNARY-OPERATORS-P2 — Unary Operators Implementation Planning

**Track:** lang / stdlib  
**Route:** IMPLEMENTATION PLANNING / NO IMPLEMENTATION  
**Status:** CLOSED — PLANNING COMPLETE  
**Date:** 2026-06-12  
**Predecessor:** LANG-UNARY-OPERATORS-P1 (contracts frozen; gap confirmed)

---

## Goal

Produce a concrete, file-specific implementation plan for unary `!` and unary `-`:
parser + TC + emitter planning, Ruby-first or split decision, proof matrix for P3/P4.
No implementation.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Planning doc | `igniter-lang/.agents/work/proposals/LANG-UNARY-OPERATORS-P2-implementation-planning-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/lang/LANG-UNARY-OPERATORS-P2.md` | Written |
| Portfolio entry | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Decision: Ruby First (P3), Rust Parity (P4)

Ruby faster to iterate on inline proof fixtures. App pressure baselines already pass with `0-X` workarounds — no urgency for immediate Rust parity. P4 proof matrix is derived from P3's section structure.

---

## Authorized Files

| File | Phase |
|------|-------|
| `igniter-lang/lib/igniter_lang/parser.rb` | P3 |
| `igniter-lang/lib/igniter_lang/typechecker.rb` | P3 |
| `igniter-lang/lib/igniter_lang/semanticir_emitter.rb` | P3 (`lower_expr` pre-TC path only) |
| `igniter-lab/igniter-compiler/src/parser.rs` | P4 |
| `igniter-lab/igniter-compiler/src/typechecker.rs` | P4 |
| `igniter-lab/igniter-compiler/src/emitter.rs` | P4 |
| Stdlib inventory | P3 (ruby-only entries), P4 (→ dual-toolchain) |

---

## Key Findings

### Parser

Both parsers handle `!` today. Neither handles `-`. The lexer tokenizes `-` as `:op` / `TokenType::Op` — no dedicated minus token.

**Change in `parse_unary`**: after the `!` check, add:
```ruby
# Ruby
if peek_type?(:op) && peek&.value == "-"
  op = advance.value
  expr = parse_postfix          # NOT parse_unary — chaining out of scope
  return { "kind" => "unary_op", "op" => op, "operand" => expr }
end
```

```rust
// Rust — analogous: check TokenType::Op + value == "-"
```

**All 8 required forms parse correctly** from a single change: `-500`, `-x`, `{a:-300}`, `[-1,2]`, `else{-1}`, `-(x+1)`, `!flag`, `!(x==y)`. All consume `parse_expr` → `parse_binary_or` → `parse_unary` and the new `-` case activates naturally.

### TypeChecker

**Ruby:** Add `when "unary_op"` arm in `infer_expr` → delegates to new `infer_unary_op`. TC converts `unary_op` → `typed_expr("call", ...)` with qualified fn name (same pattern as `infer_binary`). `infer_unary_op` is ~20 lines.

**Rust:** Add `Expr::UnaryOp { op, operand }` arm in `infer_expr` before the `_ =>` wildcard. Returns `TypedExpression { resolved_type, deps, annotated_expr: None }` — same pattern as `BinaryOp` arm.

**Contracts (frozen in P1):**

| Op | Operand | Result | Fn name | Error |
|----|---------|--------|---------|-------|
| `!` | Bool | Bool | `stdlib.primitive.not` | OOF-TY0 |
| `-` | Integer | Integer | `stdlib.integer.neg` | OOF-TY0 |
| `!` / `-` | Unknown | Bool / Integer | — | no error |

Result type returned on all paths (no Unknown propagation on OOF-TY0).

### SIR Emitter

**Ruby typed path (`semantic_expr`):** NO CHANGE needed. TC converts `unary_op` → `call { fn: ... }` before the emitter sees it. `semantic_expr` passes through call nodes generically.

**Ruby pre-TC path (`lower_expr`):** Add `when "unary_op"` → new `lower_unary` and `unary_operator_for` helpers for completeness (~20 lines). Same OOF-TY0 / fn-name logic.

**Rust emitter:** `semantic_expr_for_compute` must delegate `unary_op` nodes to `semantic_expr` (a 3-line delegation). `semantic_expr` gets a `unary_op` → `call` conversion block (rewrite `{ kind: unary_op, op: "!", operand: X }` → `{ kind: call, fn: "stdlib.primitive.not", args: [X], resolved_type: Bool }`). This achieves Ruby/Rust SIR parity.

**SIR output (both toolchains):**
```json
{ "kind": "call", "fn": "stdlib.primitive.not",
  "args": [{ ... }], "resolved_type": { "name": "Bool", "params": [] } }
```

---

## Proof Matrix Summary

| Card | Target | Sections | Key topics |
|------|--------|---------|-----------|
| P3 Ruby | ≥ 50/50 | 10 | Parser forms (A), `!` TC (C), `-` TC (D), Unknown permissive (E), OOF-TY0 (F), SIR shape (G), app fixtures (H), regression (I) |
| P4 Rust | ≥ 45/45 | 9 | Same structure; Rust SIR parity checked in G; app baselines in H–I |

---

## Hash Note

Parser changes do NOT invalidate existing baseline hashes (LAB-DSA-BASELINE-P1, LAB-NEURAL-NET-BASELINE-P1). App source files still use `0-X` workarounds — not recompiled with new syntax until a future P5 migration card.

---

## Authority Closed

No parser changes. No TC changes. No emitter changes. No inventory entries. No new OOF codes.

---

## Next Routes

| Card | Scope |
|------|-------|
| **LANG-UNARY-OPERATORS-P3** | Ruby implementation + proof ≥ 50/50 PASS |
| **LANG-UNARY-OPERATORS-P4** | Rust implementation + proof ≥ 45/45 PASS |
