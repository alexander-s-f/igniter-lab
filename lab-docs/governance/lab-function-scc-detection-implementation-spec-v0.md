# Lab: Function SCC Detection Implementation Spec

**Document ID:** lab-function-scc-detection-implementation-spec-v0.md
**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Lab work item:** LAB-FUNCTION-RECURSION-P3
**Route:** LAB PROOF + IMPLEMENTATION SPEC / NO PRODUCTION IMPLEMENTATION
**Date:** 2026-06-12
**Proof result:** 60/60 PASS
**Predecessor:** LAB-FUNCTION-RECURSION-P2 (42/42 PASS)

---

## 1. Primary Question

What exact SCC rule should replace direct self-call detection in the OOF-L4 gate for `def` functions?

**Answer:** Every function that belongs to a nontrivial SCC (self-loop or mutual cycle) in the per-module `def` function call graph must carry explicit `decreases fuel`. Missing members receive OOF-L4.

---

## 2. Toolchain Baseline

Both toolchains already implement OOF-L4 for `def` functions using self-only detection:

| Toolchain | Location | Method | Gap |
|-----------|---------|--------|-----|
| Rust lab | `typechecker.rs:357-369` | `is_recursive(body, fn_name)` | Pure mutual undetected |
| Ruby canon | `typechecker.rb:142-151` | `fn_self_recursive?(fn)` | Same gap as Rust |

P1 incorrectly reported "Ruby has no OOF-L4 for def functions." P3 corrects this: Ruby has OOF-L4 (line 147), but uses `fn_self_recursive?` — the same self-only pattern as Rust. The gap is symmetric.

---

## 3. Tarjan's SCC Algorithm

The proof-local model implements Tarjan's algorithm with three determinism guarantees:
1. Input nodes are sorted before traversal
2. Neighbors are sorted before traversal
3. SCC members are sorted alphabetically after extraction

This produces the same SCC decomposition for any given call graph regardless of definition order.

**Nontrivial SCC definition:**
- Kind `:self` — single node with a self-loop (`calls` contains own name)
- Kind `:mutual` — two or more nodes forming a cycle

Trivial SCCs (kind `:none`) require no evidence.

---

## 4. Full Case Matrix (10 patterns, all proved)

| Case | Pattern | Per-SCC result | Per-function (current) |
|------|---------|---------------|----------------------|
| Non-recursive | No edges | ACCEPT (trivial SCC) | ACCEPT |
| Non-recursive chain | A→B→C (DAG) | ACCEPT all | ACCEPT all |
| Non-recursive + spurious fuel | Annotation present | ACCEPT (harmless) | ACCEPT |
| Self-recursive, no evidence | `f(f)` | REJECT f (OOF-L4) | REJECT f |
| Self-recursive, fuel | `f(f) decreases fuel` | ACCEPT f | ACCEPT f |
| **Pure mutual, no evidence** | A→B, B→A | **REJECT both** | **ACCEPT (BUG)** |
| Pure mutual, one annotated | A fuel, B none | ACCEPT A, REJECT B | ACCEPT both |
| Pure mutual, all annotated | Both fuel | ACCEPT both | ACCEPT both |
| Mixed (self+mutual), partial | ax self+cross; bx cross-only | REJECT bx | ACCEPT bx |
| Three-way, partial | A→B→C→A; C missing | REJECT C | ACCEPT all |
| Disconnected SCCs | Two independent cycles | Independent check each SCC | Miss mutual in both |
| Helper call | Recursive f, non-recursive g | REJECT f, ACCEPT g | REJECT f, ACCEPT g |

**The critical difference** is the pure mutual row: per-SCC rejects both members; per-function accepts both (the correctness bug identified in P2).

---

## 5. OOF-L4 Trigger Definition

**Current (self-only):**
> OOF-L4 fires for function F if `is_recursive(F.body, F.name)` is true AND F lacks `decreases fuel`.

**Revised (per-SCC):**
> OOF-L4 fires for function F if F is a member of a nontrivial SCC in the def function call graph AND F lacks `decreases fuel`.

**Message template (UNCHANGED):**
> `"Recursive function '<name>' must specify 'decreases fuel'"`

No new OOF code is needed. The diagnostic code and message are identical — only the trigger condition expands.

**Diagnostic ordering:** alphabetical by function name within each SCC (determinism requirement).

---

## 6. Implementation Insertion Points

### 6.1 Rust typechecker (typechecker.rs)

**Current lines 357-369:**
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

**Replacement (spec, not code):**
```
// 1. Collect known def function names
let fn_names: HashSet<String> = functions.iter().map(|f| f.name.clone()).collect();

// 2. Build call graph: fn_name -> Vec<fn_name> (only calls to known def functions)
let fn_calls: HashMap<String, Vec<String>> = functions.iter()
    .map(|f| (f.name.clone(), extract_fn_calls(&f.body, &fn_names)))
    .collect();

// 3. Find SCCs via Tarjan's (sorted, deterministic)
let sccs: Vec<Vec<String>> = tarjan_sccs_sorted(&fn_names_sorted, &fn_calls);

// 4. Per-SCC gate: emit OOF-L4 for each missing member
for scc in &sccs {
    let is_nontrivial = scc.len() > 1
        || fn_calls.get(&scc[0]).map_or(false, |c| c.contains(&scc[0]));
    if !is_nontrivial { continue; }
    for fn_name in scc {          // scc members are already sorted
        let f = functions.iter().find(|f| &f.name == fn_name).unwrap();
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
```

**New functions required:**
- `fn extract_fn_calls(body: &BlockBody, fn_names: &HashSet<String>) -> Vec<String>`
  - Traverses `BlockBody` collecting all calls whose callee is in `fn_names`
  - Reuses the `expr_has_call` / `is_recursive` traversal pattern (same AST arms)
  - Collects names instead of matching one; returns deduplicated sorted Vec
- `fn tarjan_sccs_sorted(nodes: &[String], adj: &HashMap<String, Vec<String>>) -> Vec<Vec<String>>`
  - Standard iterative or recursive Tarjan's SCC
  - Sorts members within each SCC; input nodes pre-sorted before running

**Files touched:** `src/typechecker.rs` only. No parser changes. No new OOF code.

---

### 6.2 Ruby typechecker (typechecker.rb)

**Current lines 142-151:**
```ruby
function_errors = []
classified_program.fetch("functions", []).each do |fn|
  next unless fn_self_recursive?(fn)
  unless fn.fetch("decreases", nil) == "fuel"
    function_errors << oof("OOF-L4",
      "Recursive function '#{fn.fetch("name")}' must specify 'decreases fuel'",
      fn.fetch("name"))
  end
end
```

**Replacement (spec, not code):**
```ruby
function_errors = []
fns = classified_program.fetch("functions", [])
fn_names_set = fns.map { |f| f.fetch("name") }.to_set

# Build call graph
fn_adj = fns.to_h do |f|
  [f.fetch("name"), fn_extract_all_calls(f.fetch("body", {}), fn_names_set)]
end

# Tarjan's SCC (sorted, deterministic)
sccs = tarjan_sccs(fns.map { |f| f.fetch("name") }, fn_adj)
fn_map = fns.to_h { |f| [f.fetch("name"), f] }

sccs.each do |scc|
  is_nontrivial = scc.length > 1 || (fn_adj[scc.first] || []).include?(scc.first)
  next unless is_nontrivial
  scc.sort.each do |fn_name|        # alphabetical for determinism
    f = fn_map[fn_name]
    unless f.fetch("decreases", nil) == "fuel"
      function_errors << oof("OOF-L4",
        "Recursive function '#{fn_name}' must specify 'decreases fuel'",
        fn_name)
    end
  end
end
```

**New methods required:**
- `fn_extract_all_calls(body_hash, fn_names_set) -> Array[String]`
  - Traverses body Hash (Ruby parser AST format) collecting all called function names in `fn_names_set`
  - Call expression format: `{ "kind" => "call", "fn" => name, "args" => [...] }`
  - Mirrors `fn_body_has_call?` / `fn_expr_has_call?` traversal (same expr kinds)
  - Returns deduplicated sorted Array
- `tarjan_sccs(nodes, adj) -> Array[Array[String]]`
  - Same algorithm as Rust spec; same determinism properties
  - Can share implementation with Rust as a spec reference

**Files touched:** `lib/igniter_lang/typechecker.rb` only. No parser changes.

**Note:** `fn_self_recursive?` is NOT removed — it may have other callers or be used standalone. The OOF-L4 check loop replaces only the per-function iteration at lines 142-151.

---

## 7. Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Tarjan's correctness | 10 | Empty, single, self-loop, 2-cycle, 3-cycle, DAG, mixed, disconnected, sort determinism, self+mutual |
| B — Non-recursive cases | 4 | No evidence needed; DAG; harmless annotation |
| C — Self-recursive cases | 6 | OOF-L4 fires/passes; two independents; helper call; per-SCC regression check |
| D — Pure mutual recursion | 8 | No evidence → both reject; partial → missing reject; full → accept; three-way; diagnostic ordering |
| E — Mixed and complex | 8 | Mixed SCC; disconnected; helper; self+mutual subsumed |
| F — Per-SCC rule | 6 | Rule definition; nontrivial SCC; accept/reject; strictness vs current; no regression |
| G — OOF-L4 trigger + spreadsheet | 6 | Trigger definition; message template; SS-P02/P03 mapping |
| H — Implementation spec | 6 | Rust + Ruby insertion points; new functions |
| I — P4 readiness + comparison | 6 | Ready; no new syntax/OOF; current vs target; decision |

**Total: 60/60 PASS**

---

## 8. Spreadsheet Impact

| Fix level | Change | Addresses |
|-----------|--------|-----------|
| SS-P02 minimal | Add `decreases fuel` to `eval_expr` declaration | Removes OOF-L4 compile error (works today under self-only rule) |
| SS-P03 SCC-complete | Add `decreases fuel` to `eval_ref` declaration | SCC-complete coverage under per-SCC rule |

Both changes are source-level only (`decreases fuel` between return type and body brace). No new syntax. No parser changes.

---

## 9. Decision

**ACCEPT per-SCC rule. Route to P4.**

| Criteria | Assessment |
|----------|-----------|
| Evidence kind | `:fuel` only; structural = HOLD (from P1) |
| Scope | Per-module; cross-module SCC deferred |
| Diagnostic code | OOF-L4 (no change) |
| Message | Unchanged |
| Regression risk | Low — C-06 and F-06 prove no regression for self-recursive cases |
| New syntax | None required |
| New OOF code | None required |
| Implementation complexity | Bounded: two loops replaced, two helpers added per toolchain |

---

## 10. Next Route

**LAB-FUNCTION-RECURSION-P4** — Bounded Rust TypeChecker implementation

P4 scope:
- Implement `extract_fn_calls` and `tarjan_sccs_sorted` in Rust lab (`src/typechecker.rs`)
- Replace the `is_recursive` loop with the per-SCC gate (this spec, Section 6.1)
- Proof matrix: compile all P2 and P3 fixture cases; verify OOF-L4 fires where expected
- Confirm P2 case matrix: Case 3 now emits OOF-L4 (correctness bug fixed)
- No Ruby changes in P4

**LAB-RUBY-FUNCTION-RECURSION-P2** — Ruby SCC parity (after P4)

P2 scope:
- Implement `fn_extract_all_calls` and `tarjan_sccs` in Ruby canon (`typechecker.rb`)
- Replace the `fn_self_recursive?` loop with the per-SCC gate (this spec, Section 6.2)
- Proof matrix mirrors P4

**LAB-SPREADSHEET-RECURSION-FOLLOWUP-P1** — only after Ruby parity achieved
