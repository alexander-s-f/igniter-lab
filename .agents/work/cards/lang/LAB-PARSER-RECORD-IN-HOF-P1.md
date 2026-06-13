# LAB-PARSER-RECORD-IN-HOF-P1

**Status:** CLOSED — PROVED 35/35 PASS — FAILURE MATRIX + ROUTE DECIDED  
**Route:** LAB PARSER / RECORD LITERAL IN HOF CONTEXTS / READINESS  
**Date:** 2026-06-13  
**Authority:** evidence + route decision only; no parser implementation

## Goal

Classify the parser ambiguity for inline record literals inside HOF/lambda expression contexts.

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/lang/lab-parser-record-in-hof-p1-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_parser_record_in_hof_p1.rb` | 35/35 PASS |
| This card | `igniter-lab/.agents/work/cards/lang/LAB-PARSER-RECORD-IN-HOF-P1.md` | CLOSED |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

## Findings (5 Questions Answered)

**Q1. Ruby and Rust both fail. Different modes:**
- Ruby: parse "succeeds" with corrupt AST (error recovery nodes `{ "kind": "error", "token": ":" }`)
  → TC OOF-P1: "Unresolved symbol: {field}" + "Unsupported expression kind: error"
- Rust: hard parse failure OOF-P0 "Unexpected token in expression: Colon" (status: error, stages.parse: error)

**Q2. All `-> { field: val }` HOF contexts fail: map, filter, fold.
Works: if-expr body, scalar expr, call_contract, named helper contract.**

**Q3. Parser-only root cause.** TC is correct once AST has record_literal node.
Secondary Rust TC gap: HOF lambda record literal inferred as Unknown without output type context → OOF-TY1.
This is a separate issue from the parser ambiguity.

**Q4. Safe grammar route:**
- **P2 RECOMMENDED: Lookahead in parse_lambda** — peek 2 tokens after `{`; if `ident:` pattern → `parse_record_or_block`; else → `parse_lambda_block`. Both parsers have `parse_record_or_block` ready. ~5–8 lines per parser.
- Parenthesized `({ pos: i })` — Ruby CLEAN; Rust parse OK but TC gap remains
- Named helper contract — BOTH TCs CLEAN today (workaround)
- If-expression wrapper — Ruby CLEAN; Rust TC gap

**Q5. Apps affected:**
- `bloom_filter` — `MakeSlot` helper contract (BF-P10 via LAB-BLOOM-FILTER-RANGE-MIGRATION-P1)
- `advanced_logistics` — `router.ig` avoids inline record in filter lambda (AL-P05)

## Proof Matrix (35 checks / 7 sections)

| Section | Topic | Checks |
|---------|-------|--------|
| A | Source census — apps affected | 5 |
| B | Ruby parser: lbrace dispatch, corrupt AST | 6 |
| C | Rust parser: hard OOF-P0 parse error | 5 |
| D | Contexts that work — empirical baseline | 5 |
| E | Disambiguation gap: parse_record_or_block unreachable | 5 |
| F | Workarounds: named helper, paren, if-wrapper | 5 |
| G | Route decision, P2 lookahead, no P1 changes | 4 |

## Authority Closed

- No parser changes
- No TC changes
- No app source changes
- No new OOF codes

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-PARSER-RECORD-IN-HOF-P2 | Lookahead disambiguation in parse_lambda (both parsers, ~5 lines each) |
| LAB-RUST-HOF-RECORD-INFERENCE-P1 | Rust TC: record literal type inference inside HOF lambda without output type context |
