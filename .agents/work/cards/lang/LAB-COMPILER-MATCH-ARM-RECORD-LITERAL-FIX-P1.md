# LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1 - disambiguate match-arm record literals from blocks

Status: CLOSED (2026-06-24)
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

- [x] Focused parser/compiler test covers match arm returning a record literal beginning with `{`.
- [x] Existing match-arm block-body tests still pass.
- [x] `web_router` compiles through the machine multifile path.
- [x] `cargo test --test machine_tests test_machine_loads_multifile_app -- --nocapture` passes.
- [x] `cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture` improves; if `batch_importer` still fails, report exact remaining blocker.
- [x] `git diff --check` clean.

## Result (2026-06-24)

Root cause: `parse_match_arm_inner` (parser.rs ~L3956) forced **any** arm body starting with `{` to
`parse_block_body`, so a record literal `{ status: 201, body: body }` was parsed as a block and died on
the field `:` (`Unexpected token in expression: Colon`). The comment claiming "a `{` in expression
position is a record literal" was stale: FALLIBLE-BINDING-P2 later taught `parse_record_or_block` to
disambiguate `{ let … }` (block) from `{ field: value }` (record) in expression position.

Fix (parser.rs): the arm body is now parsed unconditionally via `self.parse_expr()`, which routes a
leading `{` through `parse_primary → parse_record_or_block`. That single disambiguation point keeps
`{ let … }` block arms (MATCH-ARM-BINDINGS-P2) lowering as blocks while record-literal arms parse as
records. No record-literal runtime semantics touched; `eval_ast variant_construct` untouched; fleet app
source unchanged (real parser repair, not a fixture patch).

Evidence:
- New focused test `match_arm_record_literal_body_compiles` in `tests/match_arm_bindings_tests.rs` (arm
  body record literal beginning with `{`) — **passes via the real compiler binary**.
- All 6 prior MATCH-ARM-BINDINGS-P2 tests still pass (7/7 in that file).
- Full `igniter-compiler` suite green (no regressions).
- `test_machine_loads_multifile_app` — passes.
- `test_machine_fleet_sweep` — **13/13 ok** (was HOLD 11/13). `web_router` recovered; `batch_importer`
  also clean — no remaining fleet blocker.
- `git diff --check` — clean.

Next route: none required. Fleet at full 13/13.

## Closed Surfaces

Do not change record literal runtime semantics. Do not fix `eval_ast variant_construct` in this card.
Do not rewrite fleet app source as the primary fix unless parser repair proves unsafe; if using the
parentheses workaround, document why it is a fixture patch rather than a language fix.
