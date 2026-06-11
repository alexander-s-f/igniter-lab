# LAB-FUNCTION-RECURSION-P1 — Managed Recursion for Functions

**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Route:** LAB PROOF / DESIGN + FIXTURE PRESSURE / NO CANON IMPLEMENTATION
**Status:** CLOSED — PASS 66/66
**Date:** 2026-06-11
**Pressure source:** SS-P02, SS-P03 (igniter-lab/igniter-apps/spreadsheet/engine.ig)
**Predecessor governance:** PROP-039 (contract-level recursion), PROP-041 (T2 structural-size)
**Successor:** Proposal authoring for SCC-level mutual recursion + Ruby parity (not yet authorized)

---

## Research Question

What is the smallest safe model for managed recursion in `def` functions:
self-recursive, mutual, explicit termination evidence, and fuel/budget behavior?

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Fixtures (4) | `igniter-lab/igniter-view-engine/fixtures/function_recursion/` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_function_recursion_p1.rb` | 66/66 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-function-managed-recursion-boundary-proof-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-FUNCTION-RECURSION-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Fixture Inventory

| File | State | Purpose |
|------|-------|---------|
| `non_recursive.ig` | Clean | Baseline: non-recursive def functions |
| `self_recursive_fuel.ig` | Proposed | Self-recursive with `decreases fuel` |
| `mutual_recursive_fuel.ig` | Proposed | Mutual pair, both with `decreases fuel` |
| `spreadsheet_eval_pair.ig` | Pressure (no evidence) | Exact SS-P02/SS-P03 pattern |

---

## Key Findings

### F-1: OOF-L4 is already the canonical diagnostic

Rust typechecker at typechecker.rs:357-370 emits `rule: "OOF-L4"` with message
`"Recursive function 'X' must specify 'decreases fuel'"`. This is NOT a new code.

### F-2: Syntax is already parseable

```igniter
def eval_expr(expr: Expr, grid: Grid) -> CellValue decreases fuel { ... }
```
`decreases` goes between the return type and `{`. `FunctionDecl.decreases: Option<String>`
already exists in the Rust parser. No parser changes needed.

### F-3: is_recursive() is self-only — mutual recursion is a gap (SS-P03)

Rust `is_recursive(body, fn_name)` scans body for direct calls to `fn_name`.
`eval_ref` calls `eval_expr` but NOT itself → `is_recursive(eval_ref.body, "eval_ref")` = false
→ eval_ref is NOT flagged today despite being in the `eval_expr ↔ eval_ref` SCC.
**Design recommendation:** Extend to SCC-level detection (all members must declare `decreases fuel`).

### F-4: No max_steps requirement for def functions (gap vs contracts)

`fuel_bounded contract` requires `max_steps N`. `def` functions with `decreases fuel`
have no max_steps gate (`FunctionDecl` has no `max_steps` field). P2 decision.

### F-5: Ruby typechecker parity gap

Ruby `typechecker.rb` has no OOF-L4 check for `def` functions. Only contract-level
recursion (OOF-R*, recur() context) is implemented. Ruby OOF-L4 = new authorized work.

---

## Evidence Model

### `decreases fuel` acceptance rule (per-function)

| Evidence | Verdict | Diagnostic |
|----------|---------|-----------|
| `:fuel` | ACCEPT | — |
| `nil` | REJECT | OOF-L4 |
| `:structural` | REJECT/HOLD | requires T2 size-relation extension |

### SCC-level rule (proof-local safe model)

| Group kind | Evidence coverage | Verdict | Diagnostic |
|-----------|------------------|---------|-----------|
| `:none` | any | ACCEPT | — |
| `:self` | `:fuel` on member | ACCEPT | — |
| `:self` | nil/structural | REJECT | OOF-L4 |
| `:mutual` | `:fuel` on ALL members | ACCEPT | — |
| `:mutual` | any member missing | REJECT | OOF-L4-MUTUAL (proof-local) |

---

## Spreadsheet Unblocking Path

### SS-P02 minimal fix (one line change)

```igniter
-- igniter-apps/spreadsheet/engine.ig, eval_expr declaration:
def eval_expr(expr: Expr, grid: Grid) -> CellValue decreases fuel {
```

This removes OOF-L4 from eval_expr. Satisfies Rust typechecker immediately.

### SS-P03 recommendation (SCC completeness)

```igniter
def eval_ref(ref_id: Text, grid: Grid) -> CellValue decreases fuel {
```

Not currently required by Rust (is_recursive returns false for eval_ref). Recommended
for SCC-completeness. The full safe model requires evidence on all SCC members.

---

## Contract recur() vs def Function Recursion

| | contract recursion | def function recursion |
|--|---|---|
| Call form | `recur(args)` | `fn_name(args)` (direct) |
| Modifier | `recursive`/`fuel_bounded` | `decreases fuel` on def |
| Max steps | Required | Not required (gap) |
| Diagnostic | OOF-R1..R7 | OOF-L4 |
| Mutual | Not in PROP-039 | Gap: SCC detection recommended |
| Ruby | Implemented | Parity gap |

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 6 | SS pressure map; OOF-L4 confirmed; eval_expr/eval_ref anatomy |
| B — Recursion Graph | 8 | SCC classification; order-independence; 3-way SCC |
| C — Termination Evidence | 8 | fuel accepted; nil/structural rejected; no max_steps gap |
| D — Positive Self-Recursion | 7 | count_depth, eval_simple; non-recursive unaffected |
| E — Positive Mutual Recursion | 7 | eval_expr+eval_ref; 3-way; mixed module |
| F — Negative Cases | 8 | OOF-L4/OOF-L4-MUTUAL for all missing-evidence patterns |
| G — Spreadsheet Mapping | 7 | SS-P02 exact blocker; minimal fix; SCC fix; gap |
| H — Contract recur() relation | 5 | Distinct surfaces; shared fuel concept; OOF-R vs OOF-L4 |
| I — Runtime/Authority Closed | 5 | No execution; no parser changes; Ruby parity separate |
| J — Decision | 5 | ACCEPT fuel; ACCEPT SCC model; HOLD structural/max_steps |

**Total: 66/66 PASS**

---

## Decisions

| Question | Answer |
|---------|--------|
| Is `decreases fuel` sufficient for self-recursive def functions? | YES — already in Rust (OOF-L4); ACCEPT |
| Does mutual recursion require SCC-level evidence? | YES — proof-local model confirms; ACCEPT as design recommendation |
| Does `decreases fuel` require `max_steps N` for def functions? | NO (current) — HOLD; P2 decides whether to require it |
| Are structural measures in scope? | HOLD — requires T2 size-relation extension for def functions |
| Does function recursion reuse OOF-L4? | YES — OOF-L4 is canonical in Rust for def functions |
| Does it need new diagnostics? | OOF-L4-MUTUAL is proof-local for mutual gap; P2 canonizes |
| Should function recursion be separate from contract recursive? | YES — different syntax forms, different diagnostic namespace |
| What exact change unblocks spreadsheet? | Add `decreases fuel` to eval_expr (SS-P02); eval_ref recommended (SS-P03) |

---

## Authority Closed

Parser changes / Rust typechecker OOF-L4 logic (already implemented for self-recursion) /
Rust is_recursive() SCC extension / Ruby typechecker OOF-L4 implementation /
max_steps requirement for def functions / T2 structural size relations for def /
VM runtime / new OOF diagnostic namespace / public API / package surface.

---

## Open Questions for P2

1. Should `decreases fuel` on `def` functions require an explicit `max_steps N`?
2. Should `is_recursive()` be replaced with SCC-level detection?
3. What canonical code for mutual recursion missing evidence: new OOF-L4-MUTUAL or extend OOF-L4?
4. Ruby parity: add OOF-L4 for `def` functions to Ruby typechecker.

---

## Next Route

**Immediate action:** Apply minimal fix to `igniter-lab/igniter-apps/spreadsheet/engine.ig`
(add `decreases fuel` to eval_expr and eval_ref to unblock SS-P02 and satisfy SCC model).

**Subsequent work (not yet authorized):**
- Proposal for SCC-level mutual recursion detection (Rust is_recursive() extension)
- Ruby typechecker OOF-L4 parity for def functions
- P2 governance: max_steps decision, canonical diagnostic code for mutual gap
