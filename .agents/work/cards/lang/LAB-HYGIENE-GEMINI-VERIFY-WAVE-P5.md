# LAB-HYGIENE-GEMINI-VERIFY-WAVE-P5 - independent review of hygiene wave for contradictions

Status: CLOSED (2026-06-24) — independent review returned HOLD with two verified fleet blockers
Lane: hygiene / independent review
Type: Gemini review packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

After Codex agents refresh implemented surfaces, current waves, closed-card navigation, and stale claims,
run Gemini as a detective/reverse-engineer. The goal is not to produce more prose. The goal is to find
contradictions, ambiguous status, false blockers, and over-strong claims before we launch another feature
wave.

## Timing

Run this after at least P1 and P2 are complete. Prefer waiting for P3/P4 too if they are already close.

## Goal

Produce an independent review report that answers:

1. Which current docs contradict live code?
2. Which claims are over-strong for the evidence?
3. Which important implemented surfaces are still missing from front-door docs?
4. Which old cards still look like active backlog but are actually historical?
5. Which ambiguities would likely mislead a new agent?

## Inputs

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/current-waves-index.md` if present
- `lab-docs/lang/closed-card-index.md` if present
- key scripts/tests named by those docs
- recent `git log --oneline -30`

## Required Report

Write:

`lab-docs/lang/hygiene-gemini-verify-wave-p5-v0.md`

Report format:

- **Verdict:** pass / pass-with-followups / hold.
- **Findings:** ordered by severity, each with file path + live evidence.
- **False blockers removed:** list any old blockers that are no longer true.
- **Overclaims:** claims that need hedging or proof.
- **Recommended follow-up cards:** max 5, only if needed.

## Acceptance

- [x] Review checks live code/tests, not docs alone.
- [x] At least 3 major surfaces are sampled deeply: IgWeb/Todo, machine/Postgres, stdlib/VM/package.
- [x] Findings are actionable and path-specific.
- [x] No production code changes.
- [x] If verdict is `hold`, name the exact blocker before next feature wave.
- [x] `git diff --check` clean.

## Closed Surfaces

No implementation. No mass rewrite. No authority change. Gemini review is evidence; it does not become
truth until a human/Codex hygiene card patches the relevant front-door docs.

## Closing Report (2026-06-24)

Wrote `lab-docs/lang/hygiene-gemini-verify-wave-p5-v0.md`. Verdict: **HOLD**.

I verified the central claim locally:

`cd runtime/igniter-machine && cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture`

Result: `machine-fleet sweep: 11/13 ok`; failures:

- `batch_importer`: `Unsupported AST kind in VM evaluator: variant_construct`
- `web_router`: match-arm record literal starting with `{` parsed as block body, producing `Unexpected token in expression: Colon`

Patched the current front doors/index to reflect this live HOLD and created follow-up cards:
`LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5` and
`LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1`.
