# LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING-P8

Status: CLOSED (2026-06-28)
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

- [x] Live `call_contract` arg validation characterized before editing.
- [x] Wrong arity and wrong argument type are either rejected already with tests
      or fixed with tests.
- [x] Valid literal pure target calls still compile.
- [x] IgWeb lowering tests remain green.
- [x] Dynamic/non-literal target policy is explicitly unchanged.
- [x] Proof packet states implementation vs regression-lock decision.
- [x] `git diff --check` passes.
- [x] Card is closed with a concise report.

## Report (2026-06-28)

Decision: **IMPLEMENT** (real, small gap). Verify-first: `call_contract`
(`typechecker/stdlib_calls.rs:2488`) already checked literal-callee / pure-only / unknown /
self-recursion / **arity**, but NOT per-argument type — weaker than P6's user-`def` check. The
registry entry already carried `input_types` + `input_names`, so the fix only had to use them.

Added (in the valid-callee arm) a per-positional-argument structural check mirroring P6
`check_user_fn_call_signature`: `structurally_assignable(actual, type_ir(input_types[i]))` with
the SAME `IgType` boundary, Unknown / Unknown-bearing skipped (deferred, never a false reject),
diagnostic `OOF-TY0` naming `callee '<C>' parameter '<p>' expects <E>, got <A>`.

Answers: Q1 arity already checked (`expects N input(s), got M`), preserved. Q2 per-arg type
now checked structurally (was the gap). Q3 Unknown-bearing args skipped (same as P6). Q4 IgWeb
generated forms unchanged (lowering 11/11 + full suite green). Q5 dynamic/non-literal callees
stay `Unknown` + VM fail-closed, untouched.

Files: `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (the arg-type loop),
`lang/igniter-compiler/tests/call_contract_arg_typing_tests.rs` (4 new regression-lock tests),
board A19, packet `lab-docs/lang/lab-igniter-compiler-call-contract-arg-typing-p8-v0.md`.

Verification: `call_contract_arg_typing_tests` 4 PASS; `effect_summary_call_contract_tests` 3
PASS; `igweb_lowering_tests` 11 PASS; full compiler suite 0 failures; `git diff --check` PASS.

## P8a follow-up (2026-06-28)

P1's verify-first ran the **machine fleet sweep** (not in P8's verification list) and caught a
regression: this P8 check rejected `erp_logistics` ("expects Text, got String") because the
shared `IgType::structurally_assignable` treated `String`≠`Text`, though they are the same
scalar. Fixed in `type_ir.rs` with `canonical_scalar_name` (`String`≡`Text`) — general
(strengthens P6/P7 too). Re-verified: fleet 13/13, P8 tests still pass (real `String` vs `Float`
still rejected), compiler 0 failures, VM 167/0, machine 362/0. Detail in the P8 packet "P8a
follow-up" section + board A19 + `lab-igniter-vm-source-run-repl-readiness-p1-v0.md` §6.

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
