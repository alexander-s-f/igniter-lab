# LANG-STDLIB-NUMERIC-COMPARISON-P4 — Rust SIR Qualification Parity

**Track:** lang / stdlib / numeric / comparison
**Route:** IMPLEMENTATION
**Status:** CLOSED / PROVED — 44/44 PASS
**Date:** 2026-06-12
**Grounding:** LANG-STDLIB-NUMERIC-COMPARISON-P3 (46/46), SIR qualification gap deferred in P3

---

## Verdict: PROVED — 44/44 PASS

**Proof runner:** `igniter-lang/experiments/numeric_comparison_proof/verify_numeric_comparison_p4.rb`

---

## Scope

Close the SIR qualification gap deferred in P3: the Rust emitter was passing
`binary_op{op: ">/</<=/>="}` nodes through unchanged. This card adds a `binary_op`
handler in `semantic_expr` and a delegation in `semantic_expr_for_compute` so the
Rust SIR output matches the Ruby SIR — `call{fn: "stdlib.integer.*", resolved_type: Bool, args: [left, right]}`.

No new operator semantics. No Decimal/Float. No VM change. Rust emitter only.

---

## Changes

### `igniter-lab/igniter-compiler/src/emitter.rs`

1. **`semantic_expr`** — added `binary_op` comparison handler after the `unary_op` handler (line ~684):
   - Detects `kind: "binary_op"` with `op` in `{">", "<", "<=", ">="}`.
   - Maps `>` → `stdlib.integer.gt`, `<` → `stdlib.integer.lt`, `<=` → `stdlib.integer.lte`, `>=` → `stdlib.integer.gte`.
   - Returns `call{kind: "call", fn: ..., args: [lowered_left, lowered_right], resolved_type: {name: "Bool", params: []}}`.
   - Non-comparison binary_ops (`+`, `-`, etc.) fall through to existing behavior.

2. **`semantic_expr_for_compute`** — added delegation after `unary_op` delegation (line ~897):
   - Intercepts `binary_op` with comparison op and calls `self.semantic_expr(val)`.
   - Arithmetic and other binary_ops fall through to general recursion (unchanged).

### `igniter-lang/docs/spec/stdlib-inventory.json`

- Updated `proof_lineage` on all 4 entries (`gt`, `lt`, `lte`, `gte`) to add:
  `"LANG-STDLIB-NUMERIC-COMPARISON-P4 Rust SIR qualification parity 44/44 PASS"`
- Updated `compatibility_note` on all 4 entries: removed "SIR qualification gap — deferred",
  replaced with "Rust SIR emitter now emits qualified call{fn:..., resolved_type:Bool, args:[left,right]} — gap closed by P4".

### `igniter-lang/experiments/numeric_comparison_proof/verify_numeric_comparison_p3.rb`

- Updated G-03 and G-04: changed from checking `ops.include?("<=")` / `ops.include?(">=")` 
  (the old deferred-gap checks) to `collect_fns(sir).include?("stdlib.integer.lte/gte")`.
  P3 proof remains 46/46 PASS.

### `igniter-lang/experiments/numeric_comparison_proof/verify_numeric_comparison_p4.rb`

- New proof runner: 44 checks across 9 sections.

### `igniter-lang/experiments/numeric_comparison_proof/README.md`

- Added P4 entry and updated "Deferred" section (removed Rust qualification gap).

---

## Proof Matrix (44/44)

| Section | Checks | Topic |
|---------|--------|-------|
| A | 4 | Regression — all 4 ops still compile ok after emitter change |
| B | 8 | Rust qualification — each op emits correct qualified fn name |
| C | 4 | No raw binary_op — Rust SIR has no comparison op field |
| D | 8 | Call shape — resolved_type=Bool (4) + args.count=2 (4) |
| E | 4 | Ruby parity — Ruby and Rust emit identical fn names |
| F | 4 | Compute-context — all 4 ops qualify inside compute nodes |
| G | 4 | App fixtures — SigmoidApprox, Pipeline, BalanceCheck still ok |
| H | 4 | Emitter source — handler + delegation present in emitter.rs |
| I | 4 | Inventory — all 4 entries lab-implemented |

---

## Closed Surfaces

- No new operator semantics
- No Decimal/Float comparison
- No VM changes
- No arithmetic binary_op changes (`+`, `-`, `*`, `/` fall through unchanged)
- No Ruby emitter changes
- No typechecker changes (Ruby or Rust)
