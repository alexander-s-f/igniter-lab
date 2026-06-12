# Rule Engine Pressure Registry

This registry tracks language and safety pressure from the `rule_engine` app. The app demonstrates a dynamic rule pipeline built from contract names, and exposes a high-leverage but high-risk Unknown-flow path.

## Baseline

Rust compilation currently succeeds for:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/rule_engine/types.ig ../igniter-apps/rule_engine/rules.ig ../igniter-apps/rule_engine/engine.ig ../igniter-apps/rule_engine/example.ig --out /tmp/rule_engine.igapp
```

Fresh observed result: all stages complete, 5 contracts emit, and diagnostics are empty. Current source hash: `sha256:9aefca5ca90dc3ec11a73ff0bf05036a2eadfa00af9034dd3e017beb371b59e3`. Liveness counters are small (`typechecker.infer_expr.max_depth=6`, `form_resolver.walk_expr.max_depth=6`).

## Pressures

| ID | Name | Evidence | Status | Next route |
|---|---|---|---|---|
| RE-P01 | Rule engine Rust baseline | Wave recheck: Rust still CLEAN (0 diagnostics, 5 contracts); unchanged since prior baseline | Positive, needs frozen proof | `LAB-RULE-ENGINE-BASELINE-P1` |
| RE-P02 | Dynamic contract dispatch | `call_contract(r, tx)` where `r` is a variable compiles and produces `Unknown` flow | Active, safety-high | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| RE-P03 | Unknown field access | Ruby wave recheck: `Unresolved field: Unknown.action` confirmed (1 diag); pipeline filters decisions using `d.action` on Unknown-typed result | Active, safety-high | `LAB-UNKNOWN-FIELD-ACCESS-P1` |
| RE-P04 | HOLD/SAFETY-HIGH | Unknown output coercion | `Collection[Unknown]` flows into `output active_decisions : Collection[RuleDecision]` — gap documented and held; LAB-UNKNOWN-OUTPUT-COERCION-P1 CLOSED as HOLD; LAB-OUTPUT-TYPE-PARAMETER-CHECK-P1 CLOSED as READY FOR IMPLEMENTATION PLANNING | `LAB-UNKNOWN-OUTPUT-COERCION-P1` CLOSED/HOLD; `LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2` next |
| RE-P05 | Rule interface convention | Rule contracts follow an informal `Transaction -> RuleDecision` shape | Positive, informal | Typed contract-ref / forms route |
| RE-P06 | Plugin / middleware architecture | Dynamic rule-name lists suggest plugin-style pipelines | Promising, blocked on safety | After RE-P02..RE-P04 |

## Safety Interpretation

The app should not be described as having proven safe reflection or duck typing. The bounded interpretation is narrower:

- Dynamic call names currently compile to `Unknown`.
- `Unknown` currently permits field access.
- Concrete output annotations currently accept Unknown-derived values.

That combination may be desirable if backed by validation receipts, dynamic dispatch receipts, or explicit quarantine semantics. Without one of those, it risks violating the no-upward-coercion honesty rule.

## Wave Recheck Summary (2026-06-12)

Ruby compile: 9 diagnostics (4× `Unknown function: call_contract`, 1× `Unresolved symbol: d`, 1× `Unresolved field: Unknown.action`, 3× `Type mismatch: expected Collection, got Unknown`). Rust: CLEAN (0 diagnostics). No changes to RE-P01 baseline. RE-P04 now documented as HOLD/SAFETY-HIGH pending output-type-parameter implementation planning.

## Recommended Route

1. `LAB-RULE-ENGINE-BASELINE-P1` to freeze the current app behavior.
2. `LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2` implementation planning for parametric container assignability (broader than Collection[Unknown] alone).
3. `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` to define receipt and fail-closed semantics for variable callees.
4. `LAB-UNKNOWN-FIELD-ACCESS-P1` to decide whether field projection over Unknown requires trace, quarantine, or OOF.
5. Rule/plugin architecture only after the safety cards close.

## Non-Goals

- No reflection feature is authorized by this app.
- No duck-typing surface is accepted as canon.
- No plugin/package/middleware model is authorized yet.
- No runtime VM behavior guarantee is inferred from compile success.
