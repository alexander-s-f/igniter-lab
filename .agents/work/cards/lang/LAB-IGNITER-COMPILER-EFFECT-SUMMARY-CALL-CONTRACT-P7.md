# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7

Status: CLOSED (2026-06-28) — characterization + regression-lock; no propagation needed

## Closure Report

Verify-first finding: the inter-contract laundering vector is **already closed by
construction**, so no `call_contract` effect propagation is built (it would be
dead code). Packet:
`lab-docs/lang/lab-igniter-compiler-effect-summary-call-contract-p7-v0.md`.

**Why closed by construction:** `call_contract` (special form in
`infer_stdlib_call`, `stdlib_calls.rs:2488`) in v0 accepts only a **literal-String,
`pure`** callee — a non-pure callee is refused with `OOF-TY0`
(`stdlib_calls.rs:2536`). And a `pure` callee cannot do ambient I/O (classifier
`E-IO-AMBIENT-BLOCKED` for direct, P6 `OOF-M1` for transitive-via-def), checked
per pure contract. By induction the pure sub-language is closed under
`call_contract`; no contract-level `OOF-M1` propagation can find a laundering
path the purity gate does not reject first. Non-literal/dynamic callees resolve
`Unknown` + VM fail-closed (no constructible `.ig` case; out of scope).

**Deliverable:** 3 regression-lock tests
(`tests/effect_summary_call_contract_tests.rs`) that pin the invariant from both
sides, so the moment it could break (a future relaxation of the pure-only rule)
is caught.

Acceptance:
- [x] Live representation of `call_contract` characterized before editing.
- [x] Outcome documented: laundering closed by construction (purity gate), so
      propagation is not needed (stronger than "propagate" / "not-yet-safe").
- [x] Dynamic/non-literal targets explicitly deferred + fail-closed (`Unknown` +
      VM fail-closed); no dynamic-dispatch semantics introduced.
- [x] P6 direct/transitive `def` tests remain green (7/7).
- [x] Relevant compiler tests pass (full suite 318, 0 failed).
- [x] Packet names covered + deferred edges, static vs dynamic policy, tests.
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Tests: P7 3/3, P6 7/7, full suite 318/0-failed, `git diff --check` clean.
Follow-up (conditional): `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CONTRACT-GRAPH-P8`
— only if v0 later allows effectful `call_contract` callees. Board row A20 → CLOSED
(def + call_contract).

---

Status: CLOSED — original card below.
Route: standard / main-audit / compiler / effect system
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6`

## Goal

Extend the effect-summary audit slice to cover statically named
`call_contract("Name", ...)` edges when that can be done from live compiler
metadata without inventing dynamic dispatch semantics.

This is audit-control-board row A20 follow-up. P6 closed laundering through
app-local `def` call graph/SCCs and added `OOF-M1`. The next risk is a pure
surface calling a contract by literal name that reaches ambient IO, while
dynamic/non-literal contract calls remain out of scope.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-effect-summary-p6-v0.md`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- effect-summary tests under `lang/igniter-compiler/tests/`

Known facts to re-verify:

- P6 computes an interprocedural ambient-IO summary over app-local call graph
  using Tarjan SCCs;
- P6 added an `Expr::Try` call edge;
- `call_contract` may be represented as a stdlib call or special form rather
  than a normal `Expr::Call`;
- only literal callee names may be considered static authority for this card.

## Scope

Allowed:

- Characterize how `call_contract("Name", ...)` appears in AST/typechecker
  source.
- If small and static, add effect propagation for literal target contracts.
- Add a pure-contract negative test where a literal `call_contract` reaches
  ambient IO transitively.
- Add a positive test for a pure literal `call_contract` target.
- If live source shows this is not a small implementation slice, produce a
  readiness packet instead and name the implementation card.

Closed:

- No dynamic contract dispatch.
- No runtime/VM/web/machine changes.
- No broad SIR metadata export unless proven necessary and explicitly scoped.
- No public language syntax changes.
- No weakening of P6 `OOF-M1`.

## Questions To Answer

1. Is a literal `call_contract("Name", ...)` visible to the typechecker as a
   static contract edge?
2. Does contract purity/effect status live in the same summary graph as `def`
   summaries, or need a separate graph?
3. What should happen for non-literal/dynamic `call_contract` targets?
4. Can recursive contract edges be summarized with the existing SCC machinery?
5. Should any effect flags be persisted into SIR now, or remain compiler-only?

## Acceptance

- [ ] Live representation of `call_contract` is characterized before editing.
- [ ] Literal static contract edges either propagate ambient IO into `OOF-M1`,
      or a readiness packet explains why this is not yet safe to implement.
- [ ] Dynamic/non-literal targets are explicitly deferred or fail closed with a
      documented diagnostic; no dynamic-dispatch semantics are introduced.
- [ ] P6 direct/transitive `def` tests remain green.
- [ ] Relevant compiler tests pass.
- [ ] Proof/readiness packet names covered and deferred edges.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml effect_summary
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-effect-summary-call-contract-p7-v0.md
```

Packet must include:

- live shape of `call_contract`;
- implementation or readiness decision;
- static vs dynamic target policy;
- tests/proofs run.
