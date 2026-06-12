# LAB-FUNCTION-RECURSION-P3 — SCC Detection Implementation Spec

**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Route:** LAB PROOF + IMPLEMENTATION SPEC / NO PRODUCTION IMPLEMENTATION
**Status:** CLOSED — PASS 60/60
**Date:** 2026-06-12
**Predecessors:** LAB-FUNCTION-RECURSION-P1 (66/66), LAB-FUNCTION-RECURSION-P2 (42/42)

---

## Primary Question

What exact SCC rule should replace direct self-call detection?

**Answer:** Every function in a nontrivial SCC (self-loop or mutual cycle) in the per-module def function call graph must carry `decreases fuel`. OOF-L4 fires for missing members.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Fixtures (4 reference) | `igniter-lab/igniter-view-engine/fixtures/function_recursion/p3_*.ig` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_function_recursion_p3.rb` | 60/60 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-function-scc-detection-implementation-spec-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-FUNCTION-RECURSION-P3.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Toolchain Baseline (P3 correction)

P1 incorrectly reported Ruby as having no OOF-L4 for def functions.

**Actual state:**
- **Rust** `typechecker.rs:357-369`: `is_recursive(body, fn_name)` self-only check → OOF-L4
- **Ruby** `typechecker.rb:142-151`: `fn_self_recursive?(fn)` self-only check → OOF-L4

Both implement OOF-L4 for def functions. Both have the same self-only detection gap. The fix is symmetric.

---

## OOF-L4 Trigger Definition (per-SCC)

```
OOF-L4 fires for function F if:
  F is a member of a nontrivial SCC in the def function call graph
  AND F lacks `decreases fuel` annotation

Nontrivial SCC:
  kind :self   — single node with self-loop
  kind :mutual — two or more nodes (mutual cycle)

Message template (UNCHANGED):
  "Recursive function '<name>' must specify 'decreases fuel'"

Diagnostic ordering: alphabetical by function name within SCC (determinism)
```

---

## Full Case Matrix

| Case | Per-SCC result | Per-function (current) |
|------|---------------|----------------------|
| Non-recursive | ACCEPT | ACCEPT |
| Self-recursive, no evidence | REJECT OOF-L4 | REJECT OOF-L4 |
| Self-recursive, fuel | ACCEPT | ACCEPT |
| **Pure mutual, no evidence** | **REJECT both** | **ACCEPT (bug)** |
| Pure mutual, partial | ACCEPT annotated, REJECT missing | ACCEPT all |
| Pure mutual, all annotated | ACCEPT all | ACCEPT all |
| Three-way cycle, partial | REJECT missing member | ACCEPT all |
| Mixed (self+mutual) | REJECT both if either missing | REJECT only self-caller |
| Disconnected SCCs | Check each SCC independently | Miss mutual in all SCCs |
| Helper call | REJECT recursive; ACCEPT helper | Same |

---

## Tarjan's SCC

Determinism guarantees:
1. Input nodes sorted before traversal
2. Neighbors sorted before traversal
3. SCC members sorted alphabetically

Algorithm: O(V+E), single-pass, standard Tarjan's.

---

## Implementation Insertion Points

### Rust (`src/typechecker.rs`)

**Replace** lines 357-369 (the `is_recursive` loop) with:
1. Build call graph from function bodies using new `extract_fn_calls(body, fn_names_set)`
2. Run `tarjan_sccs_sorted(fn_names, fn_call_graph)`
3. For each nontrivial SCC member lacking `decreases fuel`: emit OOF-L4

**New functions:**
- `fn extract_fn_calls(body: &BlockBody, fn_names: &HashSet<String>) -> Vec<String>`
- `fn tarjan_sccs_sorted(nodes: &[String], adj: &HashMap<String, Vec<String>>) -> Vec<Vec<String>>`

**Files:** `src/typechecker.rs` only. No parser changes.

### Ruby (`lib/igniter_lang/typechecker.rb`)

**Replace** lines 142-151 (the `fn_self_recursive?` loop) with:
1. Build call graph using new `fn_extract_all_calls(body, fn_names_set)`
2. Run `tarjan_sccs(nodes, adj)`
3. For each nontrivial SCC member lacking `decreases fuel`: emit OOF-L4

**New methods:**
- `fn_extract_all_calls(body_hash, fn_names_set) -> Array[String]`
- `tarjan_sccs(nodes, adj) -> Array[Array[String]]`

**Files:** `lib/igniter_lang/typechecker.rb` only. `fn_self_recursive?` preserved.

---

## Spreadsheet Impact

| Fix level | Change | Addresses |
|-----------|--------|-----------|
| SS-P02 minimal | `decreases fuel` on eval_expr | Removes current OOF-L4 compile error |
| SS-P03 SCC-complete | `decreases fuel` on eval_ref also | SCC-complete under per-SCC rule |

Both changes: source-level only, no new syntax, no parser changes.

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Tarjan's | 10 | Algorithm correctness, determinism, all topology cases |
| B — Non-recursive | 4 | Trivial SCCs, DAG, harmless annotation |
| C — Self-recursive | 6 | Gate fires, evidence accepted, helper call, no regression |
| D — Pure mutual | 8 | No evidence→reject; partial→reject missing; all→accept; three-way; ordering |
| E — Mixed/complex | 8 | Mixed SCC, disconnected, helper, self+mutual subsumed |
| F — Rule definition | 6 | Nontrivial; accept/reject; strictness vs current; no self-recursive regression |
| G — OOF-L4 + spreadsheet | 6 | Trigger; message; SS-P02/P03 |
| H — Insertion points | 6 | Rust + Ruby spec; new helpers |
| I — P4 readiness | 6 | Ready; no new syntax/OOF; current vs target; ACCEPT decision |

**Total: 60/60 PASS**

---

## Decision: ACCEPT

Per-SCC rule is **IMPLEMENTATION-READY for P4**.

| Criteria | Status |
|----------|--------|
| New syntax required | NO — `decreases fuel` already parsed |
| New OOF code required | NO — OOF-L4 unchanged |
| Regression risk | LOW — C-06/F-06 prove no self-recursive regression |
| Cross-module SCCs | DEFERRED to later; per-module scope sufficient for v0 |
| Structural decrease | HOLD from P1 — orthogonal |
| max_steps for def | HOLD from P1 — orthogonal |

---

## Authority Closed

No Rust/Ruby typechecker implementation in P3 / No parser syntax changes / No new keyword / No new OOF code / No VM/runtime / No spreadsheet app edits / No stdlib work / No broad compiler refactor.

---

## Next Route

1. **LAB-FUNCTION-RECURSION-P4** — bounded Rust typechecker implementation
   - Implement `extract_fn_calls` + `tarjan_sccs_sorted` in `src/typechecker.rs`
   - Replace `is_recursive` loop with per-SCC gate
   - Proof: compile P2/P3 case matrix; Case 3 must now emit OOF-L4

2. **LAB-RUBY-FUNCTION-RECURSION-P2** — Ruby SCC parity (after P4)
   - Implement `fn_extract_all_calls` + `tarjan_sccs` in `typechecker.rb`
   - Replace `fn_self_recursive?` loop

3. **LAB-SPREADSHEET-RECURSION-FOLLOWUP-P1** — only after Ruby parity achieved
