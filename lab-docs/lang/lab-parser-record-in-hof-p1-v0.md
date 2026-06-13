# lab-parser-record-in-hof-p1-v0

**Card:** LAB-PARSER-RECORD-IN-HOF-P1  
**Date:** 2026-06-13  
**Status:** CLOSED — 35/35 PASS  
**Route:** LAB PARSER / RECORD LITERAL IN HOF CONTEXTS / READINESS

---

## Problem Statement

Inline record literals inside HOF/lambda expression contexts fail to parse in both Ruby
and Rust parsers. `map(xs, i -> { pos: i, set: false })` fails because `{` after `->` is
unconditionally dispatched to `parse_lambda_block`, treating the brace as a block-body
opener. The record literal parser (`parse_record_or_block`) is bypassed entirely.

This gap has forced workarounds in at least two apps:
- `bloom_filter` — `MakeSlot` named helper contract instead of `i -> { pos: i, set: false }`
- `advanced_logistics` — avoids inline record in filter lambda; uses inline capacity check

---

## Root Cause

In both parsers, `parse_lambda` contains this dispatch:

```
# Ruby (parser.rb)
body = peek_type?(:lbrace) ? parse_lambda_block : parse_expr

# Rust (parser.rs)
if self.peek_type(TokenType::LBrace) {
    ExprOrBlock::Block(self.parse_lambda_block()?)
} else {
    ExprOrBlock::Expr(self.parse_expr()?)
}
```

When `{` follows `->`, both parsers call `parse_lambda_block` unconditionally — even
when the braces contain a record literal. `parse_record_or_block` is only reachable via
`parse_primary` when `{` appears in a general expression position (not the immediate
lambda-body position).

---

## Q1 — Reproduces in Ruby, Rust, or Both?

**Both parsers fail. Different failure modes:**

**Ruby:** Parse "succeeds" with a corrupt AST. Error recovery emits `{ "kind": "error",
"token": ":" }` nodes for unexpected colons. TypeChecker then emits:
- `OOF-P1 Unresolved symbol: {field_name}` — field name parsed as a ref
- `OOF-P1 Unsupported expression kind: error` — error node in AST

**Rust:** Hard parse failure. Status: `error`. Stage `parse`: `error`.
- `OOF-P0 Unexpected token in expression: Colon`
- `OOF-P0 Unexpected token in expression: Comma`
- `OOF-P0 Unexpected token in expression: Colon`

---

## Q2 — Which Contexts Fail?

### Fails (both parsers)

| Context | Ruby result | Rust result |
|---------|-------------|-------------|
| `map(xs, i -> { pos: i })` | PARSE "OK", TC OOF-P1 | PARSE ERROR OOF-P0 |
| `filter(xs, s -> { field: val })` | PARSE "OK", TC OOF-P1 | PARSE ERROR OOF-P0 |
| `fold(xs, init, (a, x) -> { field: val })` | PARSE "OK", TC OOF-P1 | PARSE ERROR OOF-P0 |

Any `-> {ident: val}` form — map, filter, fold, any lambda HOF.

### Works

| Context | Ruby | Rust |
|---------|------|------|
| `map(xs, i -> i)` — scalar expr | PARSE OK, TC CLEAN | OK |
| `map(xs, i -> if cond { a } else { b })` — if body | PARSE OK, TC CLEAN | OK |
| `compute r = { pos: 1 }` — record in compute | PARSE OK, TC works | OK (parse) |
| `map(xs, i -> call_contract("MakeSlot", i))` | PARSE OK, TC CLEAN | OK |
| `map(xs, i -> ({ pos: i }))` — paren workaround | PARSE OK, TC CLEAN | OK (parse); TC gap |
| `map(xs, i -> if cond { { pos: i } } else {{ pos: 0 }})` | PARSE OK, TC CLEAN | OK (parse); TC gap |

---

## Q3 — Parser-Only, or TC Also?

**Parser-only root cause.** Once the parser produces a correct `record_literal` AST node,
the existing TypeChecker record literal inference (LANG-RUBY-RECORD-LITERAL-INFERENCE P2/P3)
handles it correctly in Ruby.

**Secondary Rust TC gap:** Even with the parenthesized workaround `({ pos: i })`, Rust TC
infers the record as `Unknown` inside a HOF lambda body. The issue: `infer_record_literal`
in Rust has no type-context propagation from the surrounding `map` output annotation into
the lambda body. Result: `Collection[Unknown]` at the output boundary → OOF-TY1.

This secondary gap is separate from the parser ambiguity:
- Parser gap → **LAB-PARSER-RECORD-IN-HOF-P2** (fix)
- Rust HOF record TC gap → **LAB-RUST-HOF-RECORD-INFERENCE-P1** (successor)

---

## Q4 — Safe Grammar Route

### Option A — Lookahead disambiguation in `parse_lambda` (RECOMMENDED for P2)

After `->`, if `{` is next, peek 2 tokens:
- If `{ident:` or `{keyword:` pattern → call `parse_record_or_block`
- Otherwise → call `parse_lambda_block`

Both parsers already have `parse_record_or_block` implemented and correct. The fix is
~5–8 lines per parser, localized to `parse_lambda`.

Disambiguation logic: tokens[pos] = `{`, tokens[pos+1] = ident/keyword, tokens[pos+2] = `:` → record.

This covers all common record forms. Edge cases (empty record `{}`, nested braces) are handled
by the `}` check: an empty brace `{}` remains a block body.

### Option B — Parenthesized record `({ pos: i })`

Moves `{` out of the direct `->` lookahead. Ruby: PARSE OK, TC CLEAN (complete workaround).
Rust: PARSE OK, TC gap (secondary issue above — would need additional Rust TC fix).

Not recommended as canonical syntax — visually surprising.

### Option C — Named helper contract (CURRENT WORKAROUND — works in both TCs)

```igniter
contract MakeSlot {
  input pos : Integer
  compute slot = { pos: pos, set: false }
  output slot : BitSlot
}
-- Then use:
compute slots = map(range(0, 16), i -> call_contract("MakeSlot", i))
```

bloom_filter uses this pattern post-migration (50/50 PASS in LAB-BLOOM-FILTER-RANGE-MIGRATION-P1).
Reliable and working in both TCs today.

### Option D — If-expression wrapper (Ruby-only TC CLEAN)

```igniter
map(xs, i -> if true { { pos: i } } else { { pos: 0 } })
```

Ruby PARSE OK, TC CLEAN. Rust PARSE OK but TC gap (same secondary issue as option B).
Not recommended — semantically wrong (degenerate if) and Rust TC gap remains.

---

## Q5 — Apps Using Helper Contracts Due to This Gap

| App | Location | Gap evidence |
|-----|----------|-------------|
| `bloom_filter` | `ops.ig` — `MakeSlot` contract; `example.ig` — migration note | PRESSURE_REGISTRY: "inline record literal in lambda body (`i -> { pos: i, set: false }`) fails to parse" |
| `advanced_logistics` | `router.ig` — filter lambda avoids inline record | Comment: "We inline the capacity check to avoid lambda inline record parsing ambiguities." |

---

## Workaround Summary (P1 → P2 interim)

| Pattern | Ruby | Rust | Notes |
|---------|------|------|-------|
| Named helper contract | CLEAN ✓ | CLEAN ✓ | Best cross-toolchain option |
| `({ pos: i })` parenthesized | CLEAN ✓ | Parse OK; TC gap | Rust TC gap blocks |
| `if cond { { pos: i } } else { { pos: 0 } }` | CLEAN ✓ | Parse OK; TC gap | Ergonomically bad |
| `i -> { pos: i }` direct | TC fail | Parse fail | Not usable |

---

## Proof

**Runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_parser_record_in_hof_p1.rb`  
**Result:** 35/35 PASS

| Section | Topic | Checks |
|---------|-------|--------|
| A | Source census — apps affected | 5 |
| B | Ruby parser: lbrace dispatch, corrupt AST | 6 |
| C | Rust parser: hard OOF-P0 parse error | 5 |
| D | Contexts that work — empirical baseline | 5 |
| E | Disambiguation gap: parse_record_or_block unreachable | 5 |
| F | Workarounds: named helper, paren, if-wrapper | 5 |
| G | Route decision, P2 lookahead, no P1 changes | 4 |

---

## Non-Goals (P1)

- No parser changes
- No TC changes
- No app source changes
- No new syntax forms

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-PARSER-RECORD-IN-HOF-P2 | Lookahead disambiguation in parse_lambda (both parsers, ~5 lines each) |
| LAB-RUST-HOF-RECORD-INFERENCE-P1 | Rust TC: record literal type inference inside HOF lambda without output context |
