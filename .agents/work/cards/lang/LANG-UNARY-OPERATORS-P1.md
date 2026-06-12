# Agent Card: LANG-UNARY-OPERATORS-P1

**Lane:** lang / parser + typechecker / unary operators  
**Mode:** PROPOSAL AUTHORING  
**Status:** CLOSED — AUTHORED  
**Date closed:** 2026-06-12  
**Proposal doc:** `igniter-lang/.agents/work/proposals/LANG-UNARY-OPERATORS-unary-operators-v0.md`  
**Evidence proof:** `igniter-lang/experiments/unary_minus_proof/verify_unary_minus_p1.rb` (34/34 PASS)

---

## Goal

Author the proposal for unary operators `!` and `-`. Define canonical contracts, SIR names, OOF behavior, parser forms, and current gap state across both toolchains. No implementation.

---

## Canonical Contracts Defined

### `!` — Logical Not
- Type: `Bool → Bool`
- SIR: `stdlib.primitive.not`
- Operand Unknown permissive → Bool
- Wrong operand → OOF-TY0

### `-` — Integer Negation
- Type: `Integer → Integer`
- SIR: `stdlib.integer.neg`
- Operand Unknown permissive → Integer
- Wrong operand → OOF-TY0
- Decimal / Float negation: **deferred**

---

## Current Gap State

| | Ruby | Rust |
|---|------|------|
| `!` parser | ✓ ok (`parse_unary` handles `:bang`) | ✓ ok (`TokenType::Bang`) |
| `-` parser | ✗ parse error ("Unexpected token: op(-)") | ✗ parse error |
| `!` TC | ✗ OOF-TY0 (no `when "unary_op"` in `infer_expr`) | ✗ OOF-TY0 (no `Expr::UnaryOp` arm) |
| `-` TC | n/a (blocked at parse) | n/a |

Key structural facts:
- `unary_op` IS handled in Ruby graph traversal helpers (`fn_expr_has_call?`, `fn_collect_calls_expr`) — just not in `infer_expr`
- Rust runtime confirmed: `!x` where x:Bool → parse=ok, then TC OOF-TY0 "Unsupported expression kind: \"unary_op\""
- LAB-UNARY-MINUS-P1 E-05: `infer_expr` has no `when "unary_op"` arm — structural source check PASS

---

## App Pressure (from LAB-UNARY-MINUS-P1)

| App | Site | Workaround |
|-----|------|------------|
| neural_net/network.ig | 6+ negative weights | `0 - X` |
| neural_net/activations.ig | SigmoidApprox threshold | `0 - 2500` |
| vector_math/vec2.ig | Vec2Negate | `0 - v.x` |
| vector_math/vec2.ig | Vec2Perp | `0 - v.y` |

---

## Design Decisions Made

| # | Decision |
|---|----------|
| D1 | `!: Bool → Bool`, SIR `stdlib.primitive.not` |
| D2 | `-: Integer → Integer`, SIR `stdlib.integer.neg` |
| D3 | No new OOF codes — OOF-TY0 reused with descriptive message |
| D4 | Unknown permissive on both operators |
| D5 | Decimal/Float deferred |
| D6 | Ruby `-` token is `:op` with value `"-"` (not `:minus`) — non-obvious parser detail |
| D7 | Ruby `parse_unary` change: add `:op` + value `"-"` case after `:bang` case |
| D8 | TC: new `when "unary_op"` arm in Ruby + `Expr::UnaryOp` arm in Rust |
| D9 | SIR fn name annotated on the `unary_op` node by TC |
| D10 | Operand chaining (`!!x`, `!-x`) not in scope |
| D11 | Inventory entries deferred to P3 (Ruby implementation) |

---

## Closed Surfaces

- No parser changes in this card
- No typechecker changes in this card
- No emitter changes in this card
- No VM / runtime / capability authority
- No binary operator parity
- No Decimal / Float negation
- No new OOF codes

---

## Related

- **LAB-UNARY-MINUS-P1**: 34/34 PASS readiness proof — parser gap, workaround, app pressure, TC downstream gap
- **LANG-STDLIB-IS-EMPTY-PROP-P1**: `non_empty` added because `!is_empty(x)` → OOF-TY0
- **LANG-STDLIB-IS-EMPTY-PROP-P3** J-04: `infer_expr` still has no `when "unary_op"` arm post-is_empty

---

## Next Route

**LANG-UNARY-OPERATORS-P2** — implementation planning:
- Parser change: `parse_unary` `-` case (Ruby `:op`+value, Rust token check)
- TC change: `infer_unary_op` helper shape + OOF-TY0 message text
- Decide Ruby P3 / Rust P4 split vs combined
- Proof matrix ≥60 checks / 9+ sections
