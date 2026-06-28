# LAB-IGNITER-COMPILER-RECORD-LITERAL-NONINLINE-FIELD-TYPING-P7

Status: OPEN
Route: standard / main-audit / compiler / type soundness
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5`,
`LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6`

## Goal

Close the remaining A19 / B-U3 Rust-lab compiler tail: record-literal field
typing when the field value is not an inline literal/simple expression and the
old stringly path can miss structural generic mismatch.

P5 moved variant-field generic checks to the `IgType` structural boundary. P6
did the same for app-local user `def` call arguments. This card should apply the
same narrow model to record-literal field validation, without broad record
semantics redesign.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-type-ir-enum-p5-v0.md`
- `lab-docs/lang/lab-igniter-compiler-user-fn-signature-check-p6-v0.md`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/typechecker/type_ir.rs`
- `lang/igniter-compiler/tests/record_*`
- old Ruby-only record literal cards only as background, not authority for this
  Rust-lab slice.

Known facts to re-verify:

- P5 named "record-literal non-inline field = remaining B-U3 half";
- Rust and Ruby record-literal bugs are different ownership surfaces;
- public SIR/JSON shape must remain stable.

## Scope

Allowed:

- Characterize the current record-literal field comparison path.
- Add `IgType`-based structural assignability where record fields compare
  inferred value type against expected field type.
- Add tests where name-only typing would pass but `Collection[Integer]` into a
  `Collection[Text]` record field fails closed.
- Add valid controls for matching generic fields and ordinary record literals.
- Write proof packet and update the audit board/implemented surface if needed.

Closed:

- No optional fields.
- No broad record-literal redesign.
- No Ruby/canon `igniter-lang` edits.
- No VM/runtime/web changes.
- No public syntax changes.

## Questions To Answer

1. Which record-literal paths already use structural assignability, and which
   still compare only names?
2. What exactly makes a "non-inline" field value risky in current source?
3. Does the fix apply to all record literals or only typed/annotated contexts?
4. How should Unknown-bearing field values behave?
5. What record surfaces remain intentionally deferred?

## Acceptance

- [ ] Live record-literal field typing path characterized before editing.
- [ ] At least one previously accepted generic field mismatch now fails closed.
- [ ] Matching generic field values still compile.
- [ ] Existing record-spread/punning/relational tests remain green.
- [ ] Full or relevant compiler suite passes.
- [ ] Proof packet states covered vs deferred record surfaces.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml record
cargo test --manifest-path lang/igniter-compiler/Cargo.toml variant_field_generic_param_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml user_fn_signature_check_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-record-literal-noninline-field-typing-p7-v0.md
```

Packet must include:

- before-state;
- exact bug specimen;
- diagnostic behavior;
- tests/proofs run;
- remaining record-literal tails.
