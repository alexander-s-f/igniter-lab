# Lab: Ruby SCC OOF-L4 Parity for def Functions

**Document ID:** lab-ruby-function-recursion-scc-oof-l4-parity-proof-v0.md
**Track:** ruby-canon / recursion / SCC parity
**Lab work item:** LAB-RUBY-FUNCTION-RECURSION-P2
**Route:** BOUNDED RUBY IMPLEMENTATION / PROOF
**Date:** 2026-06-12
**Proof result:** 58/58 PASS
**Predecessor:** LAB-RUBY-FUNCTION-RECURSION-P1 (52/52), LAB-FUNCTION-RECURSION-P3 (60/60 — SCC spec)

---

## 1. Goal

Implement SCC-based OOF-L4 recursion checking for Ruby canon `def` functions, replacing
the self-only `fn_self_recursive?` loop proven in P1.

Rule (from LAB-FUNCTION-RECURSION-P3): every member of a nontrivial SCC in the per-module
`def` function call graph must declare `decreases fuel`. Missing members receive OOF-L4.

---

## 2. Changed File

**`igniter-lang/lib/igniter_lang/typechecker.rb` only.** No other files touched.

### 2.1 Replaced OOF-L4 loop (lines 142-151 → expanded block)

**Before (self-only):**
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

**After (per-SCC Tarjan gate):**
```ruby
function_errors = []
fns = classified_program.fetch("functions", [])
unless fns.empty?
  fn_names_set = fns.map { |f| f.fetch("name") }.to_set
  fn_adj = fns.to_h do |f|
    [f.fetch("name"), fn_extract_all_calls(f.fetch("body", {}), fn_names_set)]
  end
  sccs = tarjan_sccs(fns.map { |f| f.fetch("name") }, fn_adj)
  fn_map = fns.to_h { |f| [f.fetch("name"), f] }
  sccs.each do |scc|
    is_nontrivial = scc.length > 1 || (fn_adj[scc.first] || []).include?(scc.first)
    next unless is_nontrivial
    scc.sort.each do |fn_name|
      f = fn_map[fn_name]
      unless f.fetch("decreases", nil) == "fuel"
        function_errors << oof("OOF-L4",
          "Recursive function '#{fn_name}' must specify 'decreases fuel'",
          fn_name)
      end
    end
  end
end
```

### 2.2 New private methods added

**`fn_extract_all_calls(body_hash, fn_names_set) -> Array[String]`**
- Collects all calls to known def functions from a function body
- Returns sorted, deduplicated Array
- Delegates to `fn_collect_calls_body` (which handles the body Hash structure) then `fn_collect_calls_expr` (which handles call graph edge traversal)

**`fn_collect_calls_expr(expr, fn_names_set, found)`**
- Traverses expr Hash collecting call nodes whose callee is in `fn_names_set`
- Handles: call, binary_op, unary_op, field_access, index_access, if_expr
- Mirrors the `fn_expr_has_call?` traversal (same AST arms)

**`fn_collect_calls_body(body, fn_names_set, found)`**
- Traverses `stmts` + `return_expr` in a body Hash
- Mirrors `fn_body_has_call?`

**`tarjan_sccs(nodes, adj) -> Array[Array[String]]`**
- Standard Tarjan's SCC (O(V+E), single-pass)
- Three determinism guarantees:
  1. Input nodes sorted before traversal
  2. Neighbors sorted before traversal
  3. SCC members sorted alphabetically after extraction
- Implemented as a recursive lambda (avoids adding instance state)

### 2.3 Preserved methods

`fn_self_recursive?`, `fn_body_has_call?`, `fn_expr_has_call?` — all preserved as
private methods. `fn_self_recursive?` is no longer in the OOF-L4 hot path but is kept
for potential standalone use and to avoid breaking any external proofs that inspect the API.

---

## 3. P1 Proof Runner Update

Two checks in `verify_lab_ruby_function_recursion_p1.rb` documented the old gap behavior:

- **E-04**: "eval_ref not flagged — mutual detection deferred to P2"
- **G-05**: "b not flagged — mutual detection deferred to P2"

Both inverted to confirm the new correct behavior (mutual members without fuel ARE now
flagged). The update is annotated `"Updated by LAB-RUBY-FUNCTION-RECURSION-P2"`.

P1 post-update: 52/52 PASS.

---

## 4. Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Tarjan's correctness | 10 | Empty, single, self-loop, 2-cycle, 3-cycle, DAG, disconnected, determinism, mixed, sorted |
| B — Non-recursive | 4 | Trivial SCCs, DAG, spurious annotation accepted |
| C — Self-recursive | 6 | OOF-L4 fires, message, fuel accepted, two independents, helper not dragged |
| D — Pure mutual | 8 | No evidence→both reject; partial→missing reject; full→accept; 3-way; 3-way partial |
| E — Mixed/complex | 8 | Disconnected SCCs (4 errors), mixed self+mutual, caller not in cycle, SS-P03 |
| F — Per-SCC rule | 7 | Nontrivial kinds; trivial accepted; fuel accepted; strictness vs per-function; no regression; ordering |
| G — OOF-L4 trigger | 5 | Rule code; message template; node field; non-fuel decreases; empty module |
| H — Unknown call boundary | 3 | Unknown callee not in set; no spurious edges |
| I — P1 regression | 7 | All 4 P1 fixtures; OOF-R1; fn_self_recursive? preserved; helpers private |

**Total: 58/58 PASS**

---

## 5. Case Matrix

| Case | Per-SCC result | Per-function (P1) |
|------|---------------|------------------|
| Non-recursive | ACCEPT | ACCEPT |
| Self-recursive, no fuel | REJECT OOF-L4 | REJECT OOF-L4 |
| Self-recursive, fuel | ACCEPT | ACCEPT |
| **Pure mutual, no fuel** | **REJECT both** | **ACCEPT (bug — now fixed)** |
| Pure mutual, partial | ACCEPT annotated, REJECT missing | ACCEPT both (gap) |
| Pure mutual, all fuel | ACCEPT all | ACCEPT all |
| Three-way, partial | REJECT missing | ACCEPT all (gap) |
| Mixed self+mutual, partial | REJECT missing member | REJECT only self-caller |
| Disconnected SCCs | Check each independently | Miss mutual in all |
| Helper call | REJECT recursive; ACCEPT helper | Same |

---

## 6. Spreadsheet Impact

| Fix level | Change | Addresses |
|-----------|--------|-----------|
| SS-P02 minimal | `decreases fuel` on eval_expr | Removes OOF-L4 compile error (works under both rules) |
| SS-P03 SCC-complete | `decreases fuel` on eval_ref also | Required under per-SCC rule; eval_ref now in mutual SCC with eval_expr |

Proved in E-07 (eval_ref needs fuel under SCC rule) and E-08 (full fix accepted).

---

## 7. Authority Closed

No Rust implementation / No parser syntax changes / No VM/runtime / No spreadsheet app edits /
No new OOF codes / No new recursion keyword / No stdlib work / No new public methods on TypeChecker.

---

## 8. Artifacts

| Artefact | Path |
|----------|------|
| Typechecker changes | `igniter-lang/lib/igniter_lang/typechecker.rb` |
| P2 proof runner | `igniter-lang/experiments/function_recursion_proof/verify_lab_ruby_function_recursion_p2.rb` |
| P2 fixtures (4) | `igniter-lang/experiments/function_recursion_proof/p2_fixtures/*.ig` |
| P1 proof runner (updated) | `igniter-lang/experiments/function_recursion_proof/verify_lab_ruby_function_recursion_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/lang/lab-ruby-function-recursion-scc-oof-l4-parity-proof-v0.md` |
| Card | `igniter-lang/.agents/work/cards/lang/LAB-RUBY-FUNCTION-RECURSION-P2.md` |
