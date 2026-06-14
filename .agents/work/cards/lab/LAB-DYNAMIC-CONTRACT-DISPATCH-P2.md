# LAB-DYNAMIC-CONTRACT-DISPATCH-P2

**Status:** CLOSED — PROVED 47/47 — ROUTE SELECTED: DEFER + NO-CHANGE + PRESERVE FAIL-CLOSED  
**Route:** LAB SAFETY / DYNAMIC DISPATCH POLICY  
**Date:** 2026-06-14  
**Recommended agent:** Claude Opus or strongest reasoning agent  
**Authority:** policy/proof planning only — no implementation, no canon claim

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

---

## Closure Summary (2026-06-14)

**Route selected: DEFER (implementation) + NO-CHANGE (rule_engine source) + PRESERVE fail-closed.**

The current blocked state is intentional fail-closed evidence. The route keeps it
intact rather than spending it. No `rule_engine` source migration is selected —
the doc deliberately does **not** elect source-level static dispatch, because
`trade_robot` already carries the positive static-dispatch baseline (TR-P06,
dual-clean) and `rule_engine`'s value is precisely as the blocked Tier 2 witness.

### Baseline ground-truthed (live binary + Ruby TC)

| Toolchain | Status | Diagnostics |
|-----------|--------|-------------|
| Rust | `oof` / 2 | `OOF-P1 Unresolved field: Unknown.action` + `OOF-TY1 expected RuleDecision, got Unknown` |
| Ruby | `oof` / 2 | `OOF-P1 Unresolved symbol: d` + `OOF-P1 Unresolved field: Unknown.action` |

Matches Wave P9/P10; supersedes the P1 runner's `2× OOF-TY1` Rust form (changed by
LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2; safety outcome unchanged).

### Seven questions — answers

1. **Variable callees stay blocked** unless a *closed, declared, typed* set
   provides a statically-known result type. Open `Collection[String]` is not such
   a set.
2. **Declared strategy union is sufficient in principle** (trade_robot → `Signal`,
   rule_engine → `RuleDecision`) but only as a closed declared set, and the
   feature is not in canon. Open runtime string lists are not covered.
3. **Typed plugin registry = compile-time enumerable union of typed contract
   references**, selector is an enum tag, result type = join of members. Not a
   runtime `String → Contract` lookup. No reflection.
4. **Receipts narrowing `Unknown → RuleDecision` = authority creep** as a bare
   cast. Admissible only as fail-closed typed `Result[T]` combinators that the
   boundary still sees as typed. Out of scope; canon-gated.
5. **`output : Unknown` quarantine** = labeled lab-only escape hatch with no
   capability; for rule_engine it is **not even a clean compile** (Ruby OOF-P1 on
   `d.action` survives). rule_engine keeps its concrete annotation.
6. **Pre-implementation proof bar (8 parts)**: static resolution / member
   agreement / open-string regression guard / field-access safety / no reflection
   / OOF-TY0 fail-closed primitives / OOF-TY1 boundary preserved / canon authority
   landed first.
7. **Stays closed**: duck typing, field access on Unknown (OOF-P1), typed-output
   coercion (OOF-TY1/D2), runtime stringly authority. All asserted (Section G).

### Acceptance check

- ✅ Clear route produced: **defer + no-change** (with named, canon-gated forward design).
- ✅ No implementation route opened without explicit type evidence + fail-closed semantics.
- ✅ Preserves LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 and OOF-P1 field-access safety.
- ✅ `rule_engine` NOT marked resolved (still `oof`/`oof` dual-toolchain).
- ✅ Accounts for `trade_robot` avoiding dynamic strategy dispatch (static `CombinedStrategy`).

### Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/lang/lab-dynamic-contract-dispatch-p2-safe-route-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-apps/rule_engine/verify_dynamic_dispatch_p2.rb` | **47/47 PASS** (target ≥45) |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md` | CLOSED |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

### Authority closed

- No compiler / TC source changes. No app source changes. No new OOF codes.
- No dynamic dispatch implementation. No validation receipt implementation.
- No VM/runtime reflection. No plugin/middleware model.
