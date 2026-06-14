# LAB-DYNAMIC-CONTRACT-DISPATCH-P2

**Status:** OPEN — DISPATCH READY  
**Route:** LAB SAFETY / DYNAMIC DISPATCH POLICY  
**Date:** 2026-06-14  
**Recommended agent:** Claude Opus or strongest reasoning agent  
**Authority:** policy/proof planning only unless explicitly narrowed by findings

## Goal

Decide the safe route for `rule_engine` dynamic contract dispatch without weakening the safety model.

The key source form is:

```igniter
map(rules, r -> call_contract(r, tx))
```

The current state is intentional fail-closed evidence, not an accidental syntax gap. This card must not unblock by making `Unknown` permissive or by weakening output assignability.

## Current Baseline

From `APP-RECHECK-WAVE-P9`:

- Ruby: `oof/2` — OOF-P1 `Unresolved symbol: d` + OOF-P1 `Unresolved field: Unknown.action`.
- Rust: `oof/2` — OOF-P1 `Unresolved field: Unknown.action` + OOF-TY1 `expected RuleDecision, got Unknown`.
- `rule_engine` is the only blocked app in the 12-app fleet; with `trade_robot`, expected only blocked app in 13-app fleet.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-DYNAMIC-CONTRACT-DISPATCH-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-dynamic-contract-dispatch-p1-safety-boundary-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/rule_engine/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/rule_engine/engine.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-UNKNOWN-FIELD-ACCESS-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LANG-OUTPUT-TYPE-ASSIGNABILITY-P4.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-RULE-ENGINE-BASELINE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-TRADE-ROBOT-BASELINE-P1.md`

## Questions

1. Should variable callees remain compile-time blocked unless a typed registry is declared?
2. Is a declared strategy union sufficient for `rule_engine` and `trade_robot`-style pressure?
3. What would a typed plugin registry look like without runtime reflection authority?
4. Can validation receipts narrow `Unknown` to `RuleDecision` safely, or is that runtime authority creep?
5. Is `output : Unknown` quarantine acceptable only for lab demos, and how should it be labeled?
6. What exact proof would be required before any dynamic-dispatch implementation card?
7. What stays closed: duck typing, field access on Unknown, typed-output coercion, runtime stringly authority?

## Deliverables

- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-dynamic-contract-dispatch-p2-safe-route-v0.md`.
- Proof/policy runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/rule_engine/verify_dynamic_dispatch_p2.rb`, target at least 45 checks.
- Update this card with closure summary.
- Portfolio update after closure.

## Acceptance

- The card produces a clear route: implement, defer, quarantine, or no-change.
- Any implementation route has explicit type evidence and fail-closed semantics.
- The route preserves `LANG-OUTPUT-TYPE-ASSIGNABILITY-P4` and OOF-P1 field-access safety.
- `rule_engine` is not marked resolved unless both toolchains compile cleanly without weakening Unknown.
- The policy accounts for `trade_robot` avoiding dynamic strategy dispatch.

## Closed Surfaces

- No permissive `Unknown.action`.
- No `Collection[Unknown] -> Collection[T]` output coercion.
- No stringly runtime authority.
- No VM/runtime reflection implementation.
- No app source migration unless the doc explicitly selects source-level static strategy dispatch as the safe route.
