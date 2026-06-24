# LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1 - disambiguate match-arm record literals from blocks

Status: OPEN
Lane: compiler / fleet recovery
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Hygiene Gemini P5 and a live recheck found the current machine fleet is **HOLD 11/13**. One blocker is
`web_router`: match arm bodies like

```ig
Created { body } => { status: 201, body: body }
```

are parsed as block bodies when the arm expression starts with `{`, then fail on record-literal colons:

`Unexpected token in expression: Colon`

Parenthesizing the record literal is a workaround, but the compiler should parse this authored shape
unambiguously.

## Goal

Disambiguate match-arm bodies that start with `{` so record literals remain valid arm expressions while
block bodies still work. Recover `web_router` in the machine fleet sweep without weakening block support
added by match-arm binding work.

## Verify First

- Reproduce: `cd runtime/igniter-machine && cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture`.
- Inspect `apps/igniter-apps/web_router/serve.ig` lines around the failing arms.
- Inspect parser logic for match arms and block-vs-record parsing.
- Find tests from `LAB-LANG-MATCH-ARM-BINDINGS-P2` and preserve their accepted shapes.

## Acceptance

- [ ] Focused parser/compiler test covers match arm returning a record literal beginning with `{`.
- [ ] Existing match-arm block-body tests still pass.
- [ ] `web_router` compiles through the machine multifile path.
- [ ] `cargo test --test machine_tests test_machine_loads_multifile_app -- --nocapture` passes.
- [ ] `cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture` improves; if `batch_importer` still fails, report exact remaining blocker.
- [ ] `git diff --check` clean.

## Closed Surfaces

Do not change record literal runtime semantics. Do not fix `eval_ast variant_construct` in this card.
Do not rewrite fleet app source as the primary fix unless parser repair proves unsafe; if using the
parentheses workaround, document why it is a fixture patch rather than a language fix.
