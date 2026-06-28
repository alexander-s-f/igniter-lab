# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-READINESS-P5

Status: DONE
Route: standard / main-audit / compiler / purity and effect summary readiness
Skill: idd-agent-protocol

## Goal

Clarify whether the compiler needs an interprocedural purity/effect summary now,
and if yes, define the smallest enforceable surface.

Igniter already separates pure contracts from host-owned IO in architecture, but
recent web/machine work added staged reads, signed effects, and host runners.
This card prevents agents from guessing where purity is enforced.

## Current Authority

Live source and implemented surfaces win. Read first:

- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/classifier.rs`
- `lang/igniter-compiler/src/emitter.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/machine_runner.rs`

Known live facts to verify:

- `.ig` contracts remain pure/local in language intent;
- IgWeb `Decision` arms represent host-runner seams;
- `ReadThen` and `InvokeEffect` are runner semantics, not arbitrary in-language
  IO handles;
- compiler effect summary remains named as a foundation gap.

## Scope

Allowed:

- Inventory current purity/effect markers, if any.
- Characterize what the compiler can and cannot prove today.
- Compare whether effect summary belongs in compiler, IgWeb lowering, VM, or
  host runner metadata.
- Recommend the next small card if there is a live ambiguity.

Closed:

- No broad effect system implementation in this readiness card.
- No syntax changes.
- No change to `Decision` semantics.
- No runtime authority moves into `.ig`.

## Questions To Answer

1. What does `pure contract` enforce today, exactly?
2. Can a contract call another contract that returns host-effect decisions
   without any summary?
3. Is the risk semantic unsoundness, DX ambiguity, or only documentation drift?
4. What summary shape is sufficient: `pure`, `decision-producing`,
   `read-staged`, `effect-producing`, or something else?
5. Which existing tests would fail if the summary were wrong?

## Acceptance

- [x] Current enforcement is described with source anchors.
- [x] ReadThen/InvokeEffect/Render/RespondJson boundaries are classified.
- [x] At least three homes for the summary are compared.
- [x] Recommendation is one of: implement compiler summary, add lowering guard,
      update docs only, or defer with rationale.
- [x] A concrete next card is named if implementation is recommended.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rg -n "pure contract|InvokeEffect|ReadThen|RenderView|RespondJson|call_contract" lang server runtime -g '*.rs' -g '*.ig'
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-effect-summary-readiness-p5-v0.md
```

Include current enforcement, risk classification, alternatives, recommendation,
and next-card acceptance if needed.

## Closing Report

Closed in:

```text
lab-docs/lang/lab-igniter-compiler-effect-summary-readiness-p5-v0.md
```

Recommendation: implement a compiler summary next, narrowly. The next card is
`LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6`. It should compute transitive
function/contract summaries, reject `pure` contracts that reach ambient
`stdlib.IO.*` through `def`, classify `Decision` arms, and preserve current
IgWeb `pure -> Decision` host-intent patterns.

Verification:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
  11 passed; 0 failed

cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
  12 passed; 0 failed

git diff --check
  PASS
```
