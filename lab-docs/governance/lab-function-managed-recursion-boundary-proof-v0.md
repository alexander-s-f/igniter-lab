# Lab: Function-Level Managed Recursion Boundary Proof

**Document ID:** lab-function-managed-recursion-boundary-proof-v0.md
**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Lab work item:** LAB-FUNCTION-RECURSION-P1
**Route:** LAB PROOF / DESIGN + FIXTURE PRESSURE / NO CANON IMPLEMENTATION
**Date:** 2026-06-11
**Proof result:** 66/66 PASS
**Predecessor governance:** PROP-039 (contract-level managed recursion), PROP-041 (T2 structural-size)
**Pressure source:** SS-P02, SS-P03 in igniter-lab/igniter-apps/spreadsheet/PRESSURE_REGISTRY.md

---

## 1. Research Question

What is the smallest safe model for managed recursion in `def` functions?
Specifically:
- Is `decreases fuel` sufficient termination evidence for self-recursive `def` functions?
- Does mutual recursion require SCC-level evidence coverage?
- What is the exact syntax, diagnostic code, and unblocking path for the spreadsheet?
- How does function-level recursion relate to contract-level `recur()`?

---

## 2. Evidence Base

| Source | Role |
|--------|------|
| `igniter-lab/igniter-compiler/src/typechecker.rs` L357-370 | OOF-L4 diagnostic, is_recursive() function |
| `igniter-lab/igniter-compiler/src/parser.rs` L420-430 | FunctionDecl struct, decreases field |
| `igniter-lab/igniter-apps/spreadsheet/engine.ig` | SS-P02/SS-P03 pressure source |
| `igniter-lab/igniter-apps/spreadsheet/PRESSURE_REGISTRY.md` | SS-P01..P07 registry |
| PROP-039 (contract-level recursion) | OOF-R1..R9 contract diagnostics |
| `igniter-lang/lib/igniter_lang/typechecker.rb` | Ruby parity audit |

---

## 3. Fixture Inventory

| Fixture | State | Purpose |
|---------|-------|---------|
| `function_recursion/non_recursive.ig` | Clean (no recursion) | Baseline; Section A/D |
| `function_recursion/self_recursive_fuel.ig` | Proposed (with annotation) | Accepted self-recursive |
| `function_recursion/mutual_recursive_fuel.ig` | Proposed (with annotation) | Accepted mutual pair |
| `function_recursion/spreadsheet_eval_pair.ig` | Current pressure (no annotation) | Exact SS-P02/SS-P03 |

---

## 4. Proof-Local Model

### 4.1 Data Structures

```ruby
FunctionDef = Struct.new(:name, :return_type, :calls, :evidence, keyword_init: true)
# evidence: nil | :fuel | :structural

RecursionGroup = Struct.new(:members, :kind, keyword_init: true)
# kind: :none | :self | :mutual

CheckReceipt = Struct.new(:group, :accepted, :diagnostic, :note, keyword_init: true)
```

### 4.2 SCC Detection

`RecursionGraph.classify(functions)` uses bidirectional BFS:
1. Build forward adjacency from `calls` sets
2. For each unvisited node, compute forward reachability and reverse reachability
3. SCC = intersection of forward and reverse reachability
4. Classify: single-node with self-loop = `:self`; multi-node = `:mutual`; single-node no self-loop = `:none`

### 4.3 Validation Rules

| Situation | Result |
|-----------|--------|
| `:none` group | accepted, no diagnostic |
| `:self` with `evidence: :fuel` | accepted |
| `:self` with `evidence: nil` | rejected, OOF-L4 |
| `:self` with `evidence: :structural` | rejected (HOLD — T2 extension needed) |
| `:mutual` all members have `:fuel` | accepted |
| `:mutual` any member missing `:fuel` | rejected, OOF-L4-MUTUAL |

### 4.4 Current Rust Model (simulated)

`CurrentRustModel.is_recursive?(fn_def)` = `fn_def.calls.include?(fn_def.name)` — self-only.
`CurrentRustModel.check(fn_def)` emits OOF-L4 for self-recursive functions without fuel evidence. Does NOT check mutual recursion partners.

---

## 5. Key Findings

### F-1: OOF-L4 is the actual canonical diagnostic code

The Rust typechecker already uses `rule: "OOF-L4"` (not a new code) for self-recursive `def` functions. The message is: `"Recursive function 'X' must specify 'decreases fuel'"`. The check appears at typechecker.rs:357-370.

### F-2: Syntax is already parseable

`def name(params) -> ReturnType decreases fuel { body }`

`decreases` appears between the return type and the opening brace. The Rust parser (parser.rs:2396-2415) already parses this: `FunctionDecl.decreases: Option<String>`. The validator checks `f.decreases.as_deref() != Some("fuel")`. No parser changes needed for the self-recursive fix.

### F-3: is_recursive() is self-only — mutual recursion is a gap

The Rust `is_recursive(body, fn_name)` function scans the body for calls to `fn_name`. For `eval_ref`, `is_recursive(eval_ref.body, "eval_ref")` returns `false` because `eval_ref` calls `eval_expr`, not itself. The mutual cycle is undetected.

**Consequence:** SS-P03 (eval_expr ↔ eval_ref mutual pair) is NOT currently flagged by OOF-L4. eval_ref compiles without evidence even though it participates in the cycle.

**Design recommendation:** Extend detection to SCC-level. All members of a mutual SCC should be required to declare `decreases fuel`.

### F-4: No max_steps requirement for def functions

Contract-level `fuel_bounded` requires `max_steps N` (a positive integer bound). `def` functions with `decreases fuel` have no such requirement. `FunctionDecl` has only `decreases: Option<String>`, no `max_steps` field.

**Design gap:** `decreases fuel` on a `def` function is a static acknowledgment without a bound. The behavior when "fuel runs out" is language-undefined in P1. P2 should decide whether to add a `max_steps` requirement for `def` functions.

### F-5: Ruby typechecker parity gap

The Ruby typechecker (`typechecker.rb`) has no OOF-L4 check for `def` functions. Contract-level recursion (OOF-R1..R10, `recur()` context) is implemented, but function-level recursion is not. Adding OOF-L4 to the Ruby pipeline is a separate authorized implementation task.

### F-6: Contract recur() and def self-call are distinct surfaces

| Dimension | contract recursion | def function recursion |
|-----------|-------------------|----------------------|
| Call form | `recur(args)` (special form) | `fn_name(args)` (direct call) |
| Modifier | `recursive`/`fuel_bounded` on contract | `decreases fuel` on def |
| Max steps | `max_steps N` required | Not required (gap) |
| Diagnostic | OOF-R1..R7 | OOF-L4 |
| Mutual detection | Not in PROP-039 (single contract) | Current: gap; safe model: SCC-level |
| Ruby implementation | OOF-R1..R10, T3 | None (parity gap) |

---

## 6. Proof Section Results

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 6 | SS-P02/SS-P03 pressure map; OOF-L4 confirmed; eval_expr vs eval_ref |
| B — Recursion Graph | 8 | SCC classification: :none/:self/:mutual; order-independence; 3-way SCC |
| C — Termination Evidence | 8 | fuel accepted; nil/structural rejected; no max_steps requirement (gap) |
| D — Positive Self-Recursion | 7 | count_depth, eval_simple accepted; non-recursive unaffected |
| E — Positive Mutual Recursion | 7 | eval_expr+eval_ref with fuel; 3-way; non-rec in mixed module |
| F — Negative Cases | 8 | OOF-L4/OOF-L4-MUTUAL for all missing-evidence patterns |
| G — Spreadsheet Mapping | 7 | SS-P02 exact blocker; minimal fix; full SCC fix; current gap |
| H — Contract recur() relation | 5 | Distinct syntax surfaces; shared conceptual fuel model; OOF-R vs OOF-L4 |
| I — Runtime/Authority Closed | 5 | No execution opened; no parser/TC changes; Ruby parity separate work |
| J — Decision | 5 | ACCEPT fuel; ACCEPT SCC model; HOLD structural; HOLD max_steps |

**Total: 66/66 PASS**

---

## 7. Unblocking Path for Spreadsheet

### SS-P02 (minimal fix — one line)

Add `decreases fuel` between the return type and the opening brace of `eval_expr`:

```igniter
-- Before (blocked):
def eval_expr(expr: Expr, grid: Grid) -> CellValue {

-- After (unblocked):
def eval_expr(expr: Expr, grid: Grid) -> CellValue decreases fuel {
```

This satisfies the Rust typechecker check `f.decreases.as_deref() != Some("fuel")` and removes OOF-L4 for eval_expr.

### SS-P03 (design recommendation — SCC completeness)

Add `decreases fuel` to `eval_ref` as well:

```igniter
def eval_ref(ref_id: Text, grid: Grid) -> CellValue decreases fuel {
```

This is NOT currently required by the Rust typechecker (because `is_recursive(eval_ref.body, "eval_ref")` returns false). However, `eval_ref` participates in the mutual SCC `{eval_expr, eval_ref}` and the safe model requires evidence from all SCC members.

The Rust `is_recursive()` function should be extended to SCC-level detection for full coverage. Until then, adding the annotation manually is the correct practice.

---

## 8. Authority Closed

| Surface | Status |
|---------|--------|
| Parser changes | CLOSED (syntax already parseable) |
| Rust typechecker OOF-L4 logic | CLOSED (already implemented for self-recursion) |
| Rust is_recursive() SCC extension | CLOSED in P1 (recommended for P2) |
| Ruby typechecker OOF-L4 implementation | CLOSED in P1 (separate authorized work) |
| max_steps requirement for def functions | CLOSED in P1 (HOLD for P2 decision) |
| T2 structural size relations for def | CLOSED (separate PROP-041 extension track) |
| VM runtime / actual fuel counting | CLOSED |
| New OOF diagnostic namespace | CLOSED (OOF-L4 is canonical; OOF-L4-MUTUAL is proof-local label) |
| Public API / package surface | CLOSED |

---

## 9. Open Questions for P2

1. **max_steps for def functions**: Should `decreases fuel` on a `def` function require an explicit `max_steps N` bound, aligning with `fuel_bounded contract`? Or is the acknowledgment-only form acceptable?

2. **is_recursive() SCC extension**: Should the Rust typechecker's `is_recursive()` be replaced with a full SCC detector that flags all mutual recursion participants? This is the safe model.

3. **OOF-L4-MUTUAL vs new code**: Should mutual recursion missing-evidence diagnostics reuse OOF-L4 (with different message) or get a new code? The proof uses OOF-L4-MUTUAL as a proof-local label; P2 canonizes the final code.

4. **Ruby parity**: Add OOF-L4 to the Ruby typechecker for def function recursion. This is a required implementation task, not a governance question.

---

## 10. Next Route

**Immediate:** Apply the minimal fix to `igniter-lab/igniter-apps/spreadsheet/engine.ig` — add `decreases fuel` to `eval_expr` and `eval_ref` declarations to unblock SS-P02 and establish SCC-complete annotations.

**Subsequent proposal:** Author a proposal for the SCC-level mutual recursion detection model and Ruby parity gap, gated on the recommendations in Section 9.
