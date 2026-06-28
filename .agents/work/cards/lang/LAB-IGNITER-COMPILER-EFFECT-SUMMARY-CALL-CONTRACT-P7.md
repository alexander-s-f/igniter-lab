# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7

Status: OPEN
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
