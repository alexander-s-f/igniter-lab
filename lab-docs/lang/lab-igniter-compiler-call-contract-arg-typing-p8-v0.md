# LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING-P8

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / compiler / type soundness
Implements: audit-control-board row A19 (stringly/name-only type-IR soundness) — B-U2 slice
Depends-On: `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7`,
`LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6`

Lab evidence only. `igniter-compiler` (Rust lab compiler) scope. No dynamic contract dispatch,
no effect-summary changes, no public syntax changes, no VM/web/runtime behavior changes, no
relaxation of the `call_contract` pure-only callee rule. Decision: **IMPLEMENT** (the gap was
real and small), with regression-lock tests.

## Live before-state (verify-first)

`call_contract` is a special form in `infer_stdlib_call`
(`typechecker/stdlib_calls.rs:2488`). Before P8 it validated, for a literal-String callee
resolved against `contract_registry`:

- at least one argument (the callee name) — else `OOF-TY0`;
- first argument is `String` — else `OOF-TY0`;
- callee exists in this module — else `OOF-TY0`;
- callee is `pure` (P7 pure-only rule) — else `OOF-TY0`;
- not self-recursion — else `OOF-TY0`;
- **arity**: `positional_count == entry.input_count` — else `OOF-TY0`
  (`expects N input(s), got M`);
- on success: resolve to the callee's single output type (multi-output → `Unknown`).

**The gap:** arity was checked, but each supplied **argument type** was *not* compared against
the callee's declared input type. So `call_contract("Helper", "not-a-float")` against
`Helper { input n : Float }` passed the typechecker (correct count, wrong type) — weaker than
app-local `def` calls, which P6 (`check_user_fn_call_signature`) already type-check per
parameter via `structurally_assignable`.

The registry entry already carried everything needed:
`ContractRegistryEntry { input_count, input_names: Vec<String>, input_types: Vec<Value>, … }`
(`typechecker.rs:57`). The fix only had to *use* `input_types`/`input_names`.

## Arity / type policy (after P8)

In the valid-callee arm (`Some(entry) => …`), after resolving the output type, P8 adds a
per-argument structural check that mirrors P6 exactly:

```rust
for (i, expected_raw) in entry.input_types.iter().enumerate() {
    let Some(actual_arg) = typed_args.get(i + 1) else { break }; // [0] is the callee name
    let expected = self.type_ir(expected_raw);
    let actual = &actual_arg.resolved_type;
    if self.unknown_or_unknown_bearing(&expected) || self.unknown_or_unknown_bearing(actual) {
        continue;                       // deferred — never a false reject (same as P6)
    }
    if !self.structurally_assignable(actual, &expected) {
        // OOF-TY0: "call_contract: callee '<C>' parameter '<p>' expects <E>, got <A>"
    }
}
```

Policy summary:

| Aspect | Policy |
| --- | --- |
| Callee resolution | literal-String callee only; registry-resolved; pure-only (P7) — **unchanged** |
| Arity | `positional_count == input_count` else `OOF-TY0` — **unchanged** |
| Argument type | each positional arg vs `input_types[i]` via `structurally_assignable` (the **same `IgType` boundary** as P6) — **new** |
| Diagnostic | `OOF-TY0`, names the callee + parameter (`input_names[i]`, fallback `#<n>`) + expected/actual via `type_display` |
| Unknown handling | if either side is Unknown / Unknown-bearing → skipped (deferred), no diagnostic — same as P6 |
| Multi-output callee | result type still `Unknown` (deferred) — **unchanged**; arg typing still runs (inputs are known) |
| Non-literal / dynamic callee | never enters the valid arm → `Unknown`, VM fail-closed — **unchanged**, out of scope |

## Answers to the card questions

1. **Does `call_contract` already check arity?** Yes — `positional_count != entry.input_count`
   → `OOF-TY0` "expects N input(s), got M". Unchanged; regression-locked by
   `wrong_call_contract_arity_still_rejected`.
2. **Does it check each argument type structurally against callee inputs?** Before P8: **no**
   (the gap). After P8: **yes** — `structurally_assignable(actual, type_ir(input_types[i]))`
   per positional argument, the same boundary as P6's `def` check.
3. **How are Unknown-bearing args handled?** Skipped on either side (expected or actual), so a
   deferred/dynamic value never causes a false reject — identical to P6. Proven by
   `unknown_bearing_call_contract_arg_is_deferred` (a multi-output `call_contract` result,
   which resolves to `Unknown`, is accepted as an argument).
4. **Do generated IgWeb `call_contract` forms still pass unchanged?** Yes —
   `igweb_lowering_tests` 11/11 green and the full compiler suite is green. Generated route
   calls pass `req : Request`, guard outputs, and `capture(...) : Option[String]` against
   matching handler inputs; correctly-typed (or Unknown-bearing) args are unaffected.
5. **What remains deferred for dynamic/non-literal callees?** Everything: a non-literal first
   argument never resolves to a registry entry, stays `Unknown`, and is VM fail-closed. No
   dynamic dispatch is introduced or type-checked here (explicitly out of scope).

## Tests / proofs run

New regression-lock file `tests/call_contract_arg_typing_tests.rs` (4 tests):

- `wrong_call_contract_arg_type_is_rejected` — String arg vs `Float` input → `OOF-TY0`
  naming `callee 'Helper' parameter 'n'`.
- `correct_call_contract_arg_type_compiles_clean` — `Float` arg vs `Float` input → no
  `OOF-TY0`.
- `unknown_bearing_call_contract_arg_is_deferred` — `Unknown`-typed arg → no arg-type
  diagnostic (deferred).
- `wrong_call_contract_arity_still_rejected` — arity diagnostic preserved.

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test call_contract_arg_typing_tests
```
Result: PASS, 4 tests.

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test effect_summary_call_contract_tests
```
Result: PASS, 3 tests (P7 effect-laundering lock unchanged).

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
```
Result: PASS, 11 tests (generated route `call_contract` forms unaffected).

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
```
Result: PASS (full crate, 0 failures across all test binaries).

```text
git diff --check
```
Result: PASS.

## P8a follow-up (2026-06-28) — `String`/`Text` assignability fix

P8's verification (compiler suite + igweb lowering + 4 arg-typing tests) was green, but did not
run the **machine fleet sweep**, which compiles real app sources. During
`LAB-IGNITER-VM-SOURCE-RUN-REPL-READINESS-P1` verify-first, the sweep regressed to 12/13:
`erp_logistics` was newly rejected by this P8 check —

```
call_contract: callee 'MakeWarehouse' parameter 'id' expects Text, got String
```

Root cause was not in the P8 loop itself but in the shared `IgType::structurally_assignable`
(`type_ir.rs`): it compared scalar names raw, so a string-literal argument (tag `String`) was
not assignable to a `Text` declaration — though `String` and `Text` are the **same** scalar
(existing code already treats the literal tags interchangeably, `stdlib_calls.rs:2750`). The
gap was latent (P6/P7 also use `structurally_assignable`); P8's per-arg check at real
`call_contract` sites was the first to exercise it on app sources.

Fix: added `canonical_scalar_name` in `type_ir.rs` (`String` → `Text`) used by
`structurally_assignable`. General and correct — also strengthens P6 (`def` calls) and P7
(record-literal fields). Re-verified: machine fleet sweep **13/13**, the 4 P8 arg-typing tests
still pass (genuine `String` vs `Float` still rejected), compiler suite 0 failures, VM 167/0,
machine 362/0. Tracked on board A19; surfaced/recorded via
`lab-igniter-vm-source-run-repl-readiness-p1-v0.md` §6.

## Dynamic-target non-goals

- No dynamic / non-literal `call_contract` dispatch — a non-literal callee stays `Unknown` and
  is VM fail-closed; nothing about that path changed.
- No effect-summary changes (P7 owns the laundering invariant; this card is type soundness
  only).
- No relaxation of the pure-only callee rule, no public syntax change, no VM/web/runtime
  change.
- Remaining A19 tail (separate card if a live gap is shown): Collection-element literal typing
  (`check_array_literal_shape` name-only `_` arm) and stdlib builtin arg-typing.
