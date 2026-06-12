# LAB-FUNCTION-RECURSION-P4 — Rust SCC-Based OOF-L4 Implementation

**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Route:** BOUNDED RUST IMPLEMENTATION / PROOF
**Status:** CLOSED — PASS 80/80
**Date:** 2026-06-12
**Predecessors:** LAB-FUNCTION-RECURSION-P3 (60/60 PASS)

---

## Goal

Implement SCC-based OOF-L4 recursion checking for Rust `def` functions.

---

## Decision: IMPLEMENTED

The per-SCC OOF-L4 gate is live in `igniter-lab/igniter-compiler/src/typechecker.rs`.

The P2 correctness bug (pure mutual recursion compiling silently) is fixed.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Rust implementation | `igniter-lab/igniter-compiler/src/typechecker.rs` | Written |
| P4 fixtures (4) | `igniter-lab/igniter-view-engine/fixtures/function_recursion/p4_*.ig` | Written |
| P4 proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_function_recursion_p4.rb` | 80/80 PASS |
| P2 runner update | `proofs/verify_lab_function_recursion_p2.rb` | 42/42 PASS |
| P3 runner (unchanged) | `proofs/verify_lab_function_recursion_p3.rb` | 60/60 PASS |
| Lab doc | `lab-docs/governance/lab-function-recursion-rust-scc-oof-l4-implementation-v0.md` | Written |
| This card | `.agents/work/cards/governance/LAB-FUNCTION-RECURSION-P4.md` | Written |
| Portfolio update | `.agents/portfolio-index.md` | Updated |

---

## Implementation Summary

### Files Changed

- `igniter-lab/igniter-compiler/src/typechecker.rs` — only file changed

### Approach

Replaced the `is_recursive` self-only loop at lines 357-369 with an SCC-based gate:

1. Collect all known def function names
2. Build a call graph: `fn_name → Vec<fn_name>` (filtering to known def functions only)
3. Run Tarjan's SCC (deterministic: sorted input, sorted neighbors, sorted SCC members)
4. For each nontrivial SCC, emit OOF-L4 for each member lacking `decreases fuel`

### New Functions

| Function | Role |
|---------|------|
| `collect_fn_calls(body, fn_names)` | Body traversal → sorted Vec of known-def callees |
| `block_collect_calls(body, fn_names, out)` | Helper: block into HashSet |
| `expr_collect_calls(expr, fn_names, out)` | Recursive expr traversal (all variants) |
| `TarjanScc` struct + `visit` method | Tarjan's state machine |
| `tarjan_sccs(nodes, adj)` | Entry point — returns Vec<Vec<String>> of sorted SCCs |

### Nontrivial SCC

```
Nontrivial: scc.len() > 1  OR  (scc.len() == 1 AND fn_calls[v].contains(v))
```

---

## Behavioral Change

| Case | Pre-P4 | Post-P4 |
|------|--------|---------|
| Non-recursive | ok | ok |
| Self-recursive, no fuel | OOF-L4 | OOF-L4 |
| Self-recursive, fuel | ok | ok |
| **Pure mutual, no fuel** | **ok (BUG)** | **OOF-L4 (FIXED)** |
| Pure mutual, partial fuel | ok (gap) | OOF-L4 on missing |
| Pure mutual, all fuel | ok | ok |
| Three/four-way cycle, no fuel | ok (bug) | OOF-L4 on all |
| Disconnected SCCs | miss mutual | each SCC independent |

---

## P2 Runner Update

9 checks in `verify_lab_function_recursion_p2.rb` documented the old buggy behavior. Updated to document the new correct behavior with explicit P4 annotations. P2 runner: 42/42 PASS.

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Non-recursive | 8 | Helpers, DAGs, unknown calls — zero OOF-L4 |
| B — Self-recursive | 8 | Gate fires/passes correctly |
| C — Pure mutual | 10 | All annotation states; P2 bug fixed |
| D — Complex SCCs | 10 | Three-way, four-way, partial, mixed |
| E — Disconnected | 8 | Independent SCCs |
| F — Spreadsheet | 6 | SS-P02/SS-P03 patterns |
| G — Determinism | 6 | Reproducible, alphabetical ordering |
| H — P2 regression | 10 | All 5 P2 cases, updated expectations |
| I — P3 regression | 8 | All 4 P3 reference fixtures |
| J — Unknown calls | 6 | No false SCCs |

**Total: 80/80 PASS**

---

## Authority Closed

No Ruby implementation / No parser syntax changes / No new OOF codes / No VM/runtime / No spreadsheet app edits / No stdlib work / No broad Rust compiler refactor.

`is_recursive` function preserved (may have other callers).

---

## Next Route

1. **LAB-RUBY-FUNCTION-RECURSION-P2** — Ruby SCC parity
   - Implement `fn_extract_all_calls` + `tarjan_sccs` in `lib/igniter_lang/typechecker.rb`
   - Replace `fn_self_recursive?` loop with per-SCC gate (P3 spec Section 6.2)
   - Proof matrix mirrors P4

2. **LAB-SPREADSHEET-RECURSION-FOLLOWUP-P1** — after Ruby parity achieved
   - Requires SS-P03 SCC-complete fix (both `eval_expr` and `eval_ref` annotated)
