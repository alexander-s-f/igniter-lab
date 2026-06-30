# LAB-IGNITER-COMPILER-TYPE-IR-ENUM-READINESS-P4

Status: CLOSED
Route: standard / main-audit / compiler / type IR soundness readiness
Skill: idd-agent-protocol

## Goal

Design the smallest safe replacement path for stringly typed compiler type IR
where it still creates soundness, drift, or diagnostic risks.

This is a readiness/design card unless the live code reveals a very small
mechanical patch. Do not rewrite the compiler.

## Current Authority

Live compiler code wins. Read first:

- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-compiler-core-foundation-audit-p1.md`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/src/emitter.rs`
- `lang/igniter-compiler/src/ast.rs`
- `lang/igniter-compiler/tests`

Known audit direction:

- parser depth and float literal crash-safety are closed;
- remaining compiler foundation gaps include type-IR soundness;
- the codebase has both AST `TypeRef`-like structures and string/type-name
  surfaces.

## Scope

Allowed:

- Inventory current type representations and conversion points.
- Identify concrete drift/soundness hazards with file/line evidence.
- Compare at least three implementation strategies:
  - local enum around primitive/builtin/user/generic forms;
  - typed wrapper at typechecker boundary only;
  - full AST/typechecker IR migration;
  - no-op with targeted guards if evidence is weak.
- Recommend one narrow implementation card.

Closed:

- No broad compiler rewrite.
- No syntax changes.
- No VM bytecode changes unless proven unavoidable.
- No canon `igniter-lang` change.

## Questions To Answer

1. Which type strings are trusted as semantic facts today?
2. Where can malformed or misspelled type names cross phase boundaries?
3. What diagnostics depend on string matching?
4. What is the smallest IR enum that would remove real risk without freezing
   future generics?
5. Which tests/specimens would prove parity?

## Acceptance

- [x] A type-representation inventory is included with source anchors.
- [x] At least one concrete risk or a justified "no current risk" conclusion is
      stated.
- [x] Three alternatives are compared.
- [x] A recommended next implementation card is named with scoped acceptance.
- [x] No production code changes unless truly mechanical and separately
      justified.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rg -n "String|TypeRef|type_name|type_tag|Collection\\[|Decimal\\[" lang/igniter-compiler/src
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test typechecker_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-type-ir-enum-readiness-p4-v0.md
```

Include the inventory, risk ranking, chosen direction, and the smallest next
implementation slice.

## Closure

Closed by:

- `lab-docs/lang/lab-igniter-compiler-type-ir-enum-readiness-p4-v0.md`

Verification:

- `rg -n "String|TypeRef|type_name|type_tag|Collection\\[|Decimal\\[" lang/igniter-compiler/src`
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test typechecker_tests` attempted; stale target, Cargo reports no such test target.
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --lib` passed: 57 passed.
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests` passed: 11 passed.
- `git diff --check` passed.
