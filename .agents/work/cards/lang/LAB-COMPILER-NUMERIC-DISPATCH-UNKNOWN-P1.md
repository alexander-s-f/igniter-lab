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
