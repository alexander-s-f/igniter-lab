# Lab: Rust SCC-Based OOF-L4 Implementation for `def` Functions

**Document ID:** lab-function-recursion-rust-scc-oof-l4-implementation-v0.md
**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Lab work item:** LAB-FUNCTION-RECURSION-P4
**Route:** BOUNDED RUST IMPLEMENTATION / PROOF
**Date:** 2026-06-12
**Proof result:** 80/80 PASS
**Predecessor:** LAB-FUNCTION-RECURSION-P3 (60/60 PASS — implementation spec)

---

## 1. Summary

The Rust lab compiler now uses Tarjan's SCC algorithm to detect recursive `def` function groups, replacing the previous self-only `is_recursive()` check. The correctness bug identified in P2 (pure mutual recursion compiled silently) is fixed. All members of a nontrivial SCC must now carry `decreases fuel`.

---

## 2. Change Description

### 2.1 File Changed

`igniter-lab/igniter-compiler/src/typechecker.rs`

### 2.2 Old Gate (lines 357-369, self-only)

```rust
for f in functions {
    if is_recursive(&f.body, &f.name) {
        if f.decreases.as_deref() != Some("fuel") {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-L4".to_string(),
                message: format!("Recursive function '{}' must specify 'decreases fuel'", f.name),
                node: f.name.clone(),
                line: None,
            });
        }
    }
}
```

**Gap:** `is_recursive(body, fn_name)` only checks whether `fn_name` appears as a direct callee in `body`. Pure mutual recursion (A→B→A, where neither function calls itself directly) passed through with zero diagnostics.

### 2.3 New Gate (SCC-based)

```rust
let fn_names: HashSet<String> = functions.iter().map(|f| f.name.clone()).collect();
let mut fn_names_sorted: Vec<String> = fn_names.iter().cloned().collect();
fn_names_sorted.sort();
let fn_calls: HashMap<String, Vec<String>> = functions.iter()
    .map(|f| (f.name.clone(), collect_fn_calls(&f.body, &fn_names)))
    .collect();
let sccs = tarjan_sccs(&fn_names_sorted, &fn_calls);
let fn_map: HashMap<&str, &FunctionDecl> = functions.iter()
    .map(|f| (f.name.as_str(), f))
    .collect();
for scc in &sccs {
    let is_nontrivial = scc.len() > 1
        || fn_calls.get(scc[0].as_str()).map_or(false, |c| c.contains(&scc[0]));
    if !is_nontrivial { continue; }
    for fn_name in scc {
        if let Some(f) = fn_map.get(fn_name.as_str()) {
            if f.decreases.as_deref() != Some("fuel") {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-L4".to_string(),
                    message: format!("Recursive function '{}' must specify 'decreases fuel'", fn_name),
                    node: fn_name.clone(),
                    line: None,
                });
            }
        }
    }
}
```

### 2.4 New Helper Functions Added

| Function | Purpose |
|---------|---------|
| `collect_fn_calls(body, fn_names) -> Vec<String>` | Traverses a BlockBody collecting calls to known def functions; returns deduplicated sorted Vec |
| `block_collect_calls(body, fn_names, out)` | Block traversal writer into a mutable HashSet |
| `expr_collect_calls(expr, fn_names, out)` | Recursive expression traversal; handles all Expr variants including MatchExpr, VariantConstruct, Lambda |
| `tarjan_sccs(nodes, adj) -> Vec<Vec<String>>` | Tarjan's SCC with three determinism guarantees |
| `TarjanScc` struct | Tarjan's state: index_map, lowlink, on_stack, stack, counter, sccs |

---

## 3. Tarjan's SCC — Determinism Guarantees

1. Input nodes sorted before traversal (`fn_names_sorted`)
2. Neighbors sorted within each adjacency list (from `collect_fn_calls` which calls `.sort()`)
3. SCC members sorted alphabetically after extraction (`scc.sort()`)

This produces identical output regardless of definition order in the source file.

---

## 4. Nontrivial SCC Definition

```
Nontrivial SCC: a node v is in a nontrivial SCC if either:
  - scc.len() > 1  (mutual cycle — 2+ nodes)
  - scc.len() == 1 AND fn_calls[v] contains v  (self-loop)

Trivial SCCs (scc.len() == 1 AND no self-loop) require no decreases fuel.
```

---

## 5. Call Graph Filtering

`collect_fn_calls` only collects calls to names that are in `fn_names` (the set of all def function names in the module). Calls to stdlib, contracts, types, or unrecognized names are filtered out. This ensures:
- No false SCCs from external calls
- No false OOF-L4 from helper-to-stdlib patterns

---

## 6. Behavioral Change Summary

| Case | Pre-P4 | Post-P4 (P4) |
|------|--------|--------------|
| Non-recursive | ok, no OOF | ok, no OOF (unchanged) |
| Self-recursive, no fuel | oof, OOF-L4 | oof, OOF-L4 (unchanged) |
| Self-recursive, fuel | ok | ok (unchanged) |
| **Pure mutual, no fuel** | **ok (BUG)** | **oof, OOF-L4 on both (FIXED)** |
| Pure mutual, partial fuel | ok (gap) | oof, OOF-L4 on missing member (FIXED) |
| Pure mutual, all fuel | ok | ok (unchanged) |
| Three-way cycle, no fuel | ok (bug) | oof, OOF-L4 on all three (FIXED) |
| Four-way cycle, no fuel | ok (bug) | oof, OOF-L4 on all four (FIXED) |
| Mixed self+mutual, partial | oof on self-caller only | oof, OOF-L4 on all SCC members missing fuel |
| Disconnected SCCs | miss mutual SCCs | each SCC checked independently |
| DAG with helper | ok | ok (unchanged) |

---

## 7. Spreadsheet Impact

With P4 live in Rust:

| Fix level | Source change | Status under P4 |
|-----------|--------------|----------------|
| SS-P02 minimal | `decreases fuel` on `eval_expr` only | `eval_ref` still gets OOF-L4 (SCC-incomplete) |
| SS-P03 SCC-complete | `decreases fuel` on both `eval_expr` and `eval_ref` | ok — SCC-complete |

The SS-P02 minimal fix is no longer sufficient under P4. SS-P03 is required.

---

## 8. Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Non-recursive | 8 | No OOF-L4 for helpers, DAGs, unknown calls |
| B — Self-recursive | 8 | Gate fires without fuel; passes with fuel |
| C — Pure mutual | 10 | All annotation states; the P2 correctness bug fixed |
| D — Complex SCCs | 10 | Three-way, four-way, partial, mixed |
| E — Disconnected | 8 | Independent SCCs checked independently |
| F — Mixed (spreadsheet) | 6 | SS-P02/SS-P03 patterns verified |
| G — Determinism | 6 | Identical output on two runs; alphabetical ordering |
| H — P2 regression | 10 | All 5 P2 cases with updated expectations |
| I — P3 regression | 8 | All 4 P3 reference fixtures |
| J — Unknown calls | 6 | No false SCCs from non-def-function calls |

**Total: 80/80 PASS**

---

## 9. Regressions

- **P2 runner (42/42):** Updated 9 checks that documented the old buggy behavior to document the fixed behavior. The fix is symmetric: assertions now reflect the correct SCC-based outcome.
- **P3 runner (60/60):** Unchanged — P3 is proof-local and does not invoke the compiler.
- `cargo build --release`: PASS, zero errors.

---

## 10. Open Items

| Item | Status |
|------|--------|
| Ruby SCC parity | Deferred — LAB-RUBY-FUNCTION-RECURSION-P2 |
| Cross-module SCC detection | Deferred — per-module scope sufficient for v0 |
| Structural decrease evidence | HOLD from P1 — orthogonal T2 extension |
| max_steps for def functions | HOLD from P1 — orthogonal |
| `is_recursive` function | Preserved (may have other callers in the codebase) |

---

## 11. Next Route

**LAB-RUBY-FUNCTION-RECURSION-P2** — Ruby SCC parity
- Implement `fn_extract_all_calls` + `tarjan_sccs` in `lib/igniter_lang/typechecker.rb`
- Replace `fn_self_recursive?` loop with per-SCC gate (per P3 spec, Section 6.2)
- Proof matrix mirrors P4
