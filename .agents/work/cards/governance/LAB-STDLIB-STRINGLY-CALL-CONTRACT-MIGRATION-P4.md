# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4

**Status:** CLOSED — PROVED — 51/51  
**Route:** lab / app-pressure / source-migration  
**Date:** 2026-06-13  
**Scope:** igniter_parser final stdlib-form migration — 5 sites  
**Authority:** app source migration only; no compiler/stdlib/runtime changes

## Proof

- Proof runner: `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p4.rb` — **51/51 PASS**
- Lab doc: `igniter-lab/lab-docs/governance/lab-stdlib-stringly-call-contract-migration-p4-v0.md`
- IP-P06: **RESOLVED**
- igniter_parser: **DUAL-CLEAN** (Ruby ok/0, Rust ok/0, 3 contracts)

## Goal

Finish the stringly stdlib-form migration track for `igniter_parser` by replacing the remaining 5 `call_contract("empty"/"append")` sites with canonical collection forms.

Wave P8 exposed `IP-P06` after `stdlib.string`, `char_at`, and `substring` were resolved:

- 3x `call_contract("empty")`
- 2x `call_contract("append")`

Expected outcome: `igniter_parser` advances from `Rust oof/5`, `Ruby oof/7` to dual-toolchain clean, unless a deeper parser/state-machine blocker appears.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/igniter_parser/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p8-2026-06-13-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/igniter_parser/api.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/igniter_parser/parser.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/igniter_parser/lexer.ig`

## Known Sites

From Wave P8:

- `api.ig`: 2x `call_contract("empty")`
- `parser.ig`: 1x `call_contract("empty")`, 1x `call_contract("append")`
- `lexer.ig`: 1x `call_contract("append")`

Preserve user-contract calls:

- `call_contract("LexNextToken", ...)`
- `call_contract("ParseModuleDecl", ...)`

## Implementation Guidance

Use canonical collection forms only:

- `compute xs : Collection[T] = []` for typed empty collections.
- `append(xs, item)` for accumulating a known collection.

Do not introduce `empty()` stdlib. `LANG-STDLIB-COLLECTION-EMPTY-P1` rejected that route; typed `[]` is the canonical surface.

## Deliverables

- Source edits in `igniter_parser` only.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p4.rb`, target at least 45 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-stdlib-stringly-call-contract-migration-p4-v0.md`.
- Update `igniter_parser/PRESSURE_REGISTRY.md`: `IP-P06` resolved or reclassified with exact diagnostics.
- Card update and portfolio update after closure.

## Acceptance

- No `call_contract("empty")` or `call_contract("append")` remains in `igniter_parser`.
- Ruby and Rust compiles are run on all four app files: `types.ig`, `lexer.ig`, `parser.ig`, `api.ig`.
- If clean: mark `IP-P06 RESOLVED` and `igniter_parser DUAL-CLEAN`.
- If not clean: document the next blocker without widening the card.

## Closed Surfaces

- No compiler changes.
- No stdlib changes.
- No runtime/Rack/IO changes.
- No self-hosting claim.
- No parser loop/state-machine implementation.
- No special-casing `call_contract` stdlib names.
