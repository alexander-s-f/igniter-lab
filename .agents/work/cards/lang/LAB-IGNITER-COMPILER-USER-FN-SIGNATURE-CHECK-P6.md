# LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6

Status: CLOSED (2026-06-28)
Route: standard / main-audit / compiler / type soundness
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5`

## Goal

Use the new `IgType` helper boundary from P5 to validate app-local user `def`
call signatures at `Expr::Call`.

This is audit-control-board row A19 follow-up B-U1. P5 proved that the typed
model can fail closed for generic mismatch at one high-risk boundary. This card
should close the next dangerous class: calls to app-local functions that are
accepted by name/return-type without checking argument arity and parameter
types.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-type-ir-enum-p5-v0.md`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/typechecker/type_ir.rs`
- `lang/igniter-compiler/tests/`

Known facts to re-verify:

- `IgType` exists but most typechecker paths may still be stringly at the edges;
- P5 intentionally left user-`def` call arity/param validation as the next
  slice;
- effect-summary P6 also touches call graph logic, so keep this card limited to
  type/signature diagnostics.

## Scope

Allowed:

- Add signature validation for app-local user `def` calls at `Expr::Call`.
- Use `IgType` helpers for parameter compatibility where practical.
- Add tests for wrong arity, wrong parameter type, and a valid call.
- Keep public SIR JSON and existing syntax stable.
- Write a proof packet and update implemented-surface docs only if current truth
  changes.

Closed:

- No new public language syntax.
- No broad typechecker rewrite.
- No effect-summary changes except preserving green tests.
- No VM/runtime/web changes.
- No canon `igniter-lang` edits.

## Questions To Answer

1. Where does `Expr::Call` resolve app-local user `def` signatures today?
2. Does the checker already evaluate all argument expression types before
   trusting `f.return_type`?
3. Which diagnostic code/message is consistent with existing type errors?
4. Are generic parameters structural enough for this slice, or should the card
   cover only concrete named types?
5. What remains unvalidated after this slice?

## Acceptance

- [ ] Live call/signature path characterized before editing.
- [ ] Wrong arity for an app-local `def` call fails with a clear diagnostic.
- [ ] Wrong parameter type for an app-local `def` call fails with a clear
      diagnostic.
- [ ] Valid app-local `def` calls still compile.
- [ ] P5 variant-field generic tests and P6 effect-summary tests remain green.
- [ ] Relevant compiler tests or full compiler suite pass.
- [ ] Proof packet states exactly what call surfaces are covered and deferred.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml variant_field_generic_param_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml effect_summary
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

Adapt exact filters after verify-first.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-user-fn-signature-check-p6-v0.md
```

Packet must include:

- live before-state;
- exact diagnostics added;
- tests proving before/after behavior;
- intentionally deferred call surfaces.

## Closing Report (2026-06-28)

Outcome: **implemented.** App-local user `def` calls are now signature-checked at
`Expr::Call` (`typechecker.rs` `infer_expr`). Previously the call was resolved by
name alone and `f.return_type` was trusted without checking argument arity or
types — a `def` could be called with the wrong arity/types and still compile.

Change (lab compiler only): one new private method
`check_user_fn_call_signature`, invoked at the user-fn resolution site. It emits
`OOF-TY0` for (a) arity mismatch and (b) parameter-type mismatch, the latter via
the P5 `IgType::structurally_assignable` boundary (so generics like
`Collection[Integer]` ≠ `Collection[Text]` are caught). Parameter checks fire
only when both declared and inferred types are concrete (no Unknown-bearing
false positives), mirroring P5's variant-field path and the typed-binding path.

Deliverable: `lab-docs/lang/lab-igniter-compiler-user-fn-signature-check-p6-v0.md`
(before-state, diagnostics table, tests, deferred surfaces, all 5 questions).

Acceptance:

- [x] Live call/signature path characterized before editing (`infer_expr` user-fn
      loop at the `f.return_type`-by-name site).
- [x] Wrong arity → `OOF-TY0` (`expected N arguments, got M`).
- [x] Wrong parameter type → `OOF-TY0` (named + generic, structural).
- [x] Valid calls still compile (named + generic controls, 0 `OOF-TY0`).
- [x] P5 `variant_field_generic_param_tests` (2) and P6
      `effect_summary_interprocedural_tests` (7) remain green.
- [x] Full compiler suite passes — all suites ok, 0 failed.
- [x] Proof packet states covered vs deferred call surfaces.
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Side update: audit-board A19 → "CLOSED (two slices)", B-U1 closed; remaining =
record-literal non-inline field (B-U3) + `call_contract`/stdlib arg-typing.

Verification:

```text
cargo test … --test user_fn_signature_check_tests          → 6 passed; 0 failed
cargo test … --test variant_field_generic_param_tests      → 2 passed; 0 failed
cargo test … --test effect_summary_interprocedural_tests   → 7 passed; 0 failed
cargo test … (full igniter-compiler suite)                 → all suites ok, 0 failed
git diff --check                                            → PASS
```
