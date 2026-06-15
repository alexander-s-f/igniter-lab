# Card: LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1 — research + plan

**Status: RESEARCH DONE — plan for review.** Covers the 5 non-VM-execution blockers
(bookkeeping, erp_logistics, rule_engine, call_router, lead_router).

## Findings — three distinct clusters (not the two we expected)

### Cluster 1 — Numeric type strictness (front-end) · bookkeeping, erp_logistics

`typechecker.rs` (≈3458–3630) allows **only `Integer`** for arithmetic (`+ - * /`) and
comparison (`< <= >= > ==`). Errors: `Float < Float`, `Float+Float`, `Float*Float`,
`Decimal == Decimal`. There is a Decimal special case for `+ - *` (3420–3456) but none
for `/`, comparisons, or `==`; **Float is unsupported entirely**.

**The VM already executes Float/Decimal** (`vm.rs` binary ops have `(Float,Float)` and
the `add/sub/mul/div` stdlib arms handle Int/Float/Decimal). So this is a pure
**typechecker over-restriction** — relaxing it is low-risk; runtime already works.

### Cluster 2 — Dispatch-table completeness (VM, not front-end) · call_router, lead_router

`call_contract: no contract named 'FindTrade'`. **FindTrade IS defined** (`pure contract
FindTrade`, pipeline.ig) **and IS emitted** (lead_router: 31 contracts in the igapp).
But the VM dispatch reported only **24 available**. So the gap is **the VM building its
`dispatch_table` from only a subset of emitted contracts** (`igniter-vm/src/main.rs`),
NOT compiler emission. Investigation target: why 24/31 (entry-reachable only? a filter?
a per-file merge bug?).

### Cluster 3 — Unknown permissiveness / dynamic dispatch (GATED) · rule_engine

`compute raw = map(rules, r -> call_contract(r, t))` — **dynamic** `call_contract(r)`
with a `String` var → return type `Unknown` (by design). Then `d.action` on `Unknown`
→ `Unresolved field: Unknown.action`, and `Unknown` not assignable to the declared
`Collection[RuleDecision]` output. The app expects "Unknown is permissive" (field
access allowed, deferred to runtime).

**This is intentionally deferred** — `LAB-DYNAMIC-CONTRACT-DISPATCH` is route
`DEFER + NO-CHANGE + fail-closed`, with rule_engine recorded as the blocked evidence.
So **do NOT casually relax it**; it's governance-gated and tied to the epistemic
unknown-state model (ledger D-001). Out of scope for this pass.

## Cluster 1 — IMPLEMENTED 2026-06-15 (v0 homogeneous)

`typechecker.rs`: added a pre-check before the `match op` — when **both sides are the
SAME numeric type** (`Integer`/`Float`/`Decimal`), accept arithmetic (`+ - * /`),
comparison (`< <= >= >`), and `==`, returning the operand type (arith) or `Bool`
(cmp/==). ~20 lines; VM unchanged (binary opcodes already polymorphic — verified
`OP_LT` handles Int/Float/Decimal). Build clean, no regression (RUN-OK 15).

**Result:** erp_logistics + bookkeeping now compile past the numeric errors and execute
numeric ops. Neither is fully green yet, due to **non-numeric** residuals:
- **bookkeeping** → `Output type mismatch: expected Decimal[2], got Float` = **heterogeneous
  Float→Decimal** assignment — the deliberately-deferred case (v0 scope: homogeneous only).
- **erp_logistics** → contracts execute but need `routes`/`shipment` **inputs**; no zero-input
  demo/orchestrator entry → entry/UX cluster, not numeric.

So homogeneous numeric is done; the two apps need follow-ons (heterogeneous numeric;
demo-entry/inputs) to flip green.

## Cluster 2 — DONE 2026-06-15 (dispatch-table completeness)

Root: the VM builds `dispatch_table` by compiling each contract independently
(`main.rs`); failures are **silently skipped**. 7 lead_router contracts (FindTrade,
FindVendor, …) failed VM bytecode-compile, so call_contract couldn't find them.

Cause: the front-end emits **two `if_expr` shapes** — `condition/then_branch/else_branch`
AND `cond/then/else` (with branch **blocks** `{return_expr, stmts}`). Both VM readers
(`compiler.rs`, `eval_ast`) only knew the first.

Fix (igniter-vm): `compiler.rs` + `eval_ast` if_expr now accept both field shapes and
**unwrap a branch block to its `return_expr`** (stmts empty in practice). Also added
`stdlib.collection.filter_map` (map + drop None) — surfaced once the contracts compiled.

**Result: call_router + lead_router GREEN. RUN-OK 15 → 16.**

### Cascade exposed (honest): batch_importer

batch_importer's prior "green" was partly hollow — its `validate` contract (which does
`filter_map(rows, r -> match r {…})`) was a **skipped** dispatch entry, so the real
validation never ran. With the dispatch table now complete, batch_importer runs its
real path and hits **`Unsupported AST kind: match_expr` in `eval_ast`** — the
tree-walker lacks `match` (the bytecode path has it). Same class as the closures/if
gaps: a node kind eval_ast doesn't handle, needed inside a lambda body. → follow-up
**`LAB-VM-EVALAST-MATCH-P1`** (add `match_expr` to the tree-walker). Net RUN-OK still +1.

## Implementation plan

| # | cluster | change | repo/file | risk |
|---|---|---|---|---|
| 1 | **Numeric** (do first) | extend arithmetic + comparison + `==` to accept `Float` and `Decimal` (return Float/Decimal/Bool); keep emitting the same polymorphic ops (VM dispatches by value type) | `igniter-compiler/src/typechecker.rs` | **low** — VM already runs it |
| 2 | **Dispatch** (investigate→fix) | find why `dispatch_table` has 24/31; include all emitted (pure) contracts | `igniter-vm/src/main.rs` | medium — need root cause first |
| 3 | **Unknown** | HOLD — governance-gated (dynamic-dispatch DEFER) | — | — (decision, not code) |

## Sequencing

1. **Cluster 1 first** — clean, low-risk, unblocks 2 apps (bookkeeping, erp_logistics).
2. **Cluster 2** — short diagnostic spike on `main.rs` dispatch build, then fix; unblocks
   call_router, lead_router (and likely others that cross-call).
3. **Cluster 3** — leave gated; revisit only with the epistemic-outcome/dynamic-dispatch
   track and explicit governance.

Proof targets: bookkeeping, erp_logistics, call_router, lead_router → green
(rule_engine intentionally remains blocked). Fleet RUN-OK 15 → ~19.
