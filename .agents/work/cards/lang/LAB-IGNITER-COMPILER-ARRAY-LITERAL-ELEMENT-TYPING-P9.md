# LAB-IGNITER-COMPILER-ARRAY-LITERAL-ELEMENT-TYPING-P9

Status: TODO
Route: standard / igniter-lab / lang / igniter-compiler / type soundness
Skill: idd-agent-protocol

## Goal

Close the remaining A19 collection-element typing tail: `check_array_literal_shape` still compares
non-record array elements through name strings (`actual_type != elem_type_name`) instead of the
`IgType` structural assignability boundary introduced by P5-P8.

Implement structural element checks for `Collection[T]` array literals using the existing `IgType`
helpers. This should align collection literals with the record/user-function/call-contract typing
work already landed.

## Current Authority

Live source wins over this card if it has moved.

Read first:

- `lab-docs/lang/lab-igniter-compiler-type-ir-enum-p5-v0.md`
- `lab-docs/lang/lab-igniter-compiler-user-fn-signature-check-p6-v0.md`
- `lab-docs/lang/lab-igniter-compiler-record-literal-noninline-field-typing-p7-v0.md`
- `lab-docs/lang/lab-igniter-compiler-call-contract-arg-typing-p8-v0.md`
- `lang/igniter-compiler/src/type_ir.rs`
- `lang/igniter-compiler/src/typechecker.rs`
- existing array literal / collection tests in `lang/igniter-compiler/tests/`

Known live facts:

- P5 introduced `IgType` + structural assignability helpers.
- P6/P7/P8 use that boundary for user functions, record fields, and literal `call_contract` args.
- `check_array_literal_shape` still has a string-name comparison path for non-record items.
- Earlier P8a fixed `String`/`Text` canonicalization in `IgType::structurally_assignable`; array
  literals should inherit that fix instead of re-implementing scalar aliases.

## Requirements

- Replace the remaining non-record element name comparison with `IgType` structural assignability.
- Keep existing contextual typing behavior: empty arrays only type-check with a `Collection[T]` hint.
- Preserve Unknown-compatible behavior for complex expressions the compiler cannot yet infer.
- Preserve fail-closed behavior for record literals against non-record element types.
- Do not change parser, SIR format, Ruby/canon code, VM runtime, or collection stdlib semantics.

## Acceptance

- [ ] `Collection[Integer] = [1, 2]` type-checks.
- [ ] Mixed scalar literal elements fail closed, e.g. `Collection[Integer] = [1, "x"]`.
- [ ] `String`/`Text` scalar aliasing works through `IgType`, not a local string exception.
- [ ] Record element collections still check every record literal against the same element shape.
- [ ] A wrong record field type inside an array literal still emits `OOF-TY0`.
- [ ] Unknown-bearing complex elements remain deferred/permissive, matching existing v0 policy.
- [ ] Existing P6/P7/P8 regression tests remain green.
- [ ] `git diff --check` clean.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test -p igniter-compiler array
cargo test -p igniter-compiler type
cargo test -p igniter-compiler
git diff --check
```

If these filters do not match current test names, run the nearest focused compiler tests and record
the exact commands in the proof packet.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-array-literal-element-typing-p9-v0.md
```

Packet must include:

- exact code path changed in `check_array_literal_shape`,
- before/after typing examples,
- regression matrix,
- explicit deferrals: inference for arbitrary complex elements and stdlib arg typing.
