# LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING-P8

Status: OPEN
Route: standard / main-audit / compiler / type soundness
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7`,
`LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6`

## Goal

Close or regression-lock the A19 "call_contract arg-typing" tail.

P7 proved `call_contract` effect laundering is closed by construction because v0
allows only literal `pure` callees. This card is not about effects. It asks a
separate type-soundness question: does literal `call_contract("Name", ...)`
validate supplied argument types against the target contract inputs as strongly
as app-local `def` calls now do after P6?

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-effect-summary-call-contract-p7-v0.md`
- `lab-docs/lang/lab-igniter-compiler-user-fn-signature-check-p6-v0.md`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/tests/effect_summary_call_contract_tests.rs`
- IgWeb lowering tests, because generated routes heavily use literal
  `call_contract`.

Known facts to re-verify:

- `call_contract` is a special form in `infer_stdlib_call`;
- literal callees are registry-resolved and pure-only;
- arity may already be checked; parameter type checking may or may not be;
- non-literal/dynamic targets remain deferred/fail-closed.

## Scope

Allowed:

- Characterize existing literal `call_contract` arity/type checks.
- If missing and small, add structural argument type validation for literal
  target contract inputs using the same `IgType` boundary as P6.
- If already implemented, add regression-lock tests and close as
  characterization.
- Add valid IgWeb-style controls so generated route calls stay clean.
- Write proof packet.

Closed:

- No dynamic contract dispatch.
- No effect-summary changes.
- No public syntax changes.
- No VM/web/runtime behavior changes.
- No relaxation of pure-only callee rule.

## Questions To Answer

1. Does `call_contract` already check arity? If yes, what diagnostics?
2. Does it check each argument type structurally against callee inputs?
3. How are Unknown-bearing args handled today and after this slice?
4. Do generated IgWeb `call_contract` forms still pass unchanged?
5. What remains deferred for dynamic/non-literal callees?

## Acceptance

- [ ] Live `call_contract` arg validation characterized before editing.
- [ ] Wrong arity and wrong argument type are either rejected already with tests
      or fixed with tests.
- [ ] Valid literal pure target calls still compile.
- [ ] IgWeb lowering tests remain green.
- [ ] Dynamic/non-literal target policy is explicitly unchanged.
- [ ] Proof packet states implementation vs regression-lock decision.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test effect_summary_call_contract_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-call-contract-arg-typing-p8-v0.md
```

Packet must include:

- live before-state;
- arity/type policy;
- tests/proofs run;
- dynamic target non-goals.
