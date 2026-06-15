# Rule Engine Pressure Registry

Updated: 2026-06-14 — APP-RECHECK-WAVE-P11

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
| RE-P01 | Rule engine Rust baseline | Wave P2: Rust CLEAN (0 diagnostics). Wave P3: Rust oof / 2 diagnostics — LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 now fires OOF-TY1 for Collection[Unknown]→Collection[RuleDecision]; this is safety-positive, not a regression; P2 CLEAN baseline is superseded. Wave P8: baseline re-frozen by LAB-RULE-ENGINE-BASELINE-P1 (52/52 PASS) — Rust 2× OOF-TY1 + Ruby 2× OOF-P1 pinned; source hash frozen | FROZEN — LAB-RULE-ENGINE-BASELINE-P1 CLOSED |
| RE-P02 | Dynamic contract dispatch | Wave P3: `call_contract(r, tx)` where `r` is a variable now handled by P3 Tier 2 — returns Unknown (no "Unknown function" error); cascade: `Unresolved symbol: d`, `Unresolved field: Unknown.action`, `Unresolved symbol: tx1`; Rust: unchanged (already Unknown from LAB-RACK-P11) | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| RE-P03 | Unknown field access | Ruby wave recheck: `Unresolved field: Unknown.action` confirmed (1 diag); pipeline filters decisions using `d.action` on Unknown-typed result | Active, safety-high | `LAB-UNKNOWN-FIELD-ACCESS-P1` |
| RE-P04 | ACTIVE/CONFIRMED | Unknown output coercion | ACTIVE/CONFIRMED in both toolchains. Wave P3: Rust emits 2× OOF-TY1 (`Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]` + `expected RuleDecision, got Unknown`) — LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 landed; safety-positive. Ruby: OOF-TY1 masked by cascade errors from Tier 2 Unknown propagation. Route: LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 + LAB-DYNAMIC-CONTRACT-DISPATCH-P1 | `LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2`; `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| RE-P05 | Rule interface convention | Rule contracts follow an informal `Transaction -> RuleDecision` shape | Positive, informal | Typed contract-ref / forms route |
| RE-P06 | Plugin / middleware architecture | Dynamic rule-name lists suggest plugin-style pipelines | Promising, blocked on safety | After RE-P02..RE-P04 |
| RE-P07 | PARTIALLY-RESOLVED | Typed compute binding gap (split) | Wave P3: output variables from Tier 2 dynamic dispatch and unannotated record literal — `d`, `Unknown.action` cascade, `tx1`; 3 Ruby diags total. Wave P4: unchanged — LANG-TYPED-COMPUTE-BINDING-P2 had no effect. Root cause split: `d` and `Unknown.action` cascade = Tier 2 dynamic `call_contract(variable_callee, ...)` result unbound (route: `LAB-DYNAMIC-CONTRACT-DISPATCH-P1`); `tx1` = unannotated record literal (route: `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1`). Wave P6: `tx1` sub-pressure RESOLVED by LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 (structural match → `Transaction`); `d` and `Unknown.action` still ACTIVE | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` (d — ACTIVE) |

## Safety Interpretation

The app should not be described as having proven safe reflection or duck typing. The bounded interpretation is narrower:

- Dynamic call names currently compile to `Unknown`.
- `Unknown` currently permits field access.
- Concrete output annotations currently accept Unknown-derived values.

That combination may be desirable if backed by validation receipts, dynamic dispatch receipts, or explicit quarantine semantics. Without one of those, it risks violating the no-upward-coercion honesty rule.

## Wave Recheck Summary (2026-06-12 P1)

Ruby compile: 9 diagnostics (4× `Unknown function: call_contract`, 1× `Unresolved symbol: d`, 1× `Unresolved field: Unknown.action`, 3× `Type mismatch: expected Collection, got Unknown`). Rust: CLEAN (0 diagnostics). No changes to RE-P01 baseline. RE-P04 documented as HOLD/SAFETY-HIGH.

## Wave P2 Recheck Summary (2026-06-12)

Ruby: 9 diagnostics (4× `Unknown function: call_contract`, 1× `Unresolved symbol: d`, 1× `Unresolved field: Unknown.action`, 3× `Output type mismatch: expected Collection[RuleDecision], got Unknown`). Rust: CLEAN (0 diagnostics). RE-P04 ACTIVE/CONFIRMED — LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 landed; Ruby TC now emits specific output boundary error with full type info; coercion correctly rejected. No change in diagnostic count (9); message quality improved.

## Wave P6 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — unchanged (2× OOF-TY1). Ruby: oof / 2 diagnostics (was 3, −1). LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved RE-P07 partial: `tx1` (unannotated record literal) now infers its type (`Transaction`) via structural matching — `tx1` sub-pressure RESOLVED. Remaining Ruby diags: `Unresolved symbol: d` (Tier 2 dynamic dispatch result — RE-P02) + `Unresolved field: Unknown.action` (cascade from d being Unknown — RE-P03). Route for remaining: `LAB-DYNAMIC-CONTRACT-DISPATCH-P1`. No new pressures. No regressions.

## Wave P5 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — unchanged from Wave P4. Ruby: oof / 3 diagnostics — unchanged from Wave P4. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: RE-P07 root cause split confirmed — `tx1` is ACTIVE_TRUE_INTERMEDIATE (unannotated record literal); `d`/`Unknown.action` is NOT_RECORD_LITERAL (Tier 2 dynamic `call_contract(variable_callee, ...)` result). No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — unchanged from Wave P3. Ruby: oof / 3 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect. Root cause split confirmed for RE-P07: `d`/`Unknown.action` are from Tier 2 dynamic dispatch; `tx1` is an unannotated record literal. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]`, `Output type mismatch: expected RuleDecision, got Unknown`. Ruby: oof / 3 diagnostics — `Unresolved symbol: d`, `Unresolved field: Unknown.action`, `Unresolved symbol: tx1`. Resolutions since Wave P2: LAB-RUBY-CALL-CONTRACT-PARITY-P3 resolved 4 call_contract errors in Ruby (Ruby was 9 diags, now 3); Tier 2 dynamic callee now returns Unknown instead of "Unknown function" error. New: Rust RE-P01 baseline superseded — LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 now fires OOF-TY1 in Rust (safety-positive); RE-P04 CONFIRMED in both toolchains. Remaining blockers: Rust OOF-TY1 (RE-P04); Ruby typed compute binding gap for Tier 2 dynamic dispatch — `d`, `tx1` unbound, `Unknown.action` cascade (RE-P07).

## Wave P7 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — unchanged (2× OOF-TY1: `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]`; `Output type mismatch: expected RuleDecision, got Unknown`). Ruby: oof / 2 diagnostics — unchanged from Wave P6 (`Unresolved symbol: d`; `Unresolved field: Unknown.action`). RE-P04 ACTIVE/CONFIRMED (Rust OOF-TY1 safety-positive). RE-P07 PARTIALLY-RESOLVED: `tx1` sub-pressure RESOLVED by LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 (Wave P6; `tx1` → `Transaction`); remaining `d` (Tier 2 dynamic dispatch result — route: `LAB-DYNAMIC-CONTRACT-DISPATCH-P1`) and cascade `Unknown.action`. No new pressures.

## Wave P8 Baseline Freeze (2026-06-13)

LAB-RULE-ENGINE-BASELINE-P1 CLOSED 52/52 PASS. Baseline frozen. Rust: oof / 2× OOF-TY1 — `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]` (node: active_decisions); `Output type mismatch: expected RuleDecision, got Unknown` (node: decision). Ruby: oof / 2× OOF-P1 — `Unresolved symbol: d`; `Unresolved field: Unknown.action`. Source hash: `sha256:0cf7f61465246aedb46242c9c6c36add39f9d71956950461a7831e9bdc22486b`. Liveness: tc_infer=6 / fr_walk=6 / no breaches. RE-P01 re-frozen. No source changes. No implementation. Predecessors confirmed CLOSED: LAB-DYNAMIC-CONTRACT-DISPATCH-P1 / LAB-UNKNOWN-FIELD-ACCESS-P1 / LANG-OUTPUT-TYPE-ASSIGNABILITY-P4.

## Recommended Route

1. ~~`LAB-RULE-ENGINE-BASELINE-P1` to freeze the current app behavior.~~ **DONE**
2. `LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2` implementation planning for parametric container assignability (broader than Collection[Unknown] alone).
3. `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` to define receipt and fail-closed semantics for variable callees.
4. `LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1` to address Rust HOF temp_errors vs Ruby propagation divergence.
5. Rule/plugin architecture only after the safety cards close.

## Non-Goals

- No reflection feature is authorized by this app.
- No duck-typing surface is accepted as canon.
- No plugin/package/middleware model is authorized yet.
- No runtime VM behavior guarantee is inferred from compile success.

## Wave P8 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — **diagnostic content changed vs baseline freeze**. Prior (P7/baseline): 2× OOF-TY1 (`expected Collection[RuleDecision], got Collection[Unknown]`; `expected RuleDecision, got Unknown`). Now: 1× OOF-P1 (`Unresolved field: Unknown.action`) + 1× OOF-TY1 (`expected RuleDecision, got Unknown`). The collection-level OOF-TY1 is no longer emitted by Rust; OOF-P1 for Unknown.action now appears in Rust (was Ruby-only). Ruby: oof / 2 diagnostics — unchanged (`Unresolved symbol: d`; `Unresolved field: Unknown.action`). RE-P01 baseline source hash unchanged. Diagnostic count unchanged (2+2). Root cause unchanged: Tier 2 dynamic dispatch. Route unchanged: `LAB-DYNAMIC-CONTRACT-DISPATCH-P1`. No new pressures. No app regressions.

| RE-P04 | UPDATED-EVIDENCE | Unknown output coercion — Rust diagnostic changed | Wave P8: `Collection[RuleDecision]` vs `Collection[Unknown]` OOF-TY1 no longer emitted in Rust; `OOF-P1 Unresolved field: Unknown.action` now in Rust. Single-item `expected RuleDecision, got Unknown` OOF-TY1 remains. Safety signal still present; form changed. | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |

## Wave P9 Recheck Summary (2026-06-13)

Rust: oof / 2 diagnostics — unchanged from Wave P8 form (OOF-P1: "Unresolved field: Unknown.action" (node: active_decisions); OOF-TY1: "Output type mismatch: expected RuleDecision, got Unknown" (node: decision)). Ruby: oof / 2 diagnostics — unchanged (OOF-P1: "Unresolved symbol: d" (node: active_decisions); OOF-P1: "Unresolved field: Unknown.action" (node: active_decisions)). RE-P01 baseline source hash unchanged. Diagnostic form unchanged since Wave P8 (HOF-P2 Rust propagation change). Root cause unchanged: Tier 2 dynamic dispatch. Route unchanged: LAB-DYNAMIC-CONTRACT-DISPATCH-P1. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, LAB-VE-NEW-OBJ-INFERENCE-P1, LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1, LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2, and LAB-PARSER-RECORD-IN-HOF-P1 had no effect on rule_engine. No new pressures. No regressions.

## Wave P10 Recheck Summary (2026-06-14)

Rust: oof / 2 diagnostics (OOF-P1 Unknown.action + OOF-TY1 output type mismatch) — unchanged from Wave P9 form.
Ruby: oof / 2 diagnostics (OOF-P1 Unresolved symbol d + OOF-P1 Unknown.action) — unchanged from Wave P9 form.
BLOCKED status remains active as a deliberate safety-dispatch boundary under LAB-DYNAMIC-CONTRACT-DISPATCH-P2. No new pressures. No regressions.

## LAB-DYNAMIC-CONTRACT-DISPATCH-P2 Closure (2026-06-14)

CLOSED 47/47 PASS. Route selected: **DEFER (implementation) + NO-CHANGE (rule_engine source) + PRESERVE fail-closed**. The BLOCKED state is now a *selected safe route*, not an open gap — the dynamic Tier 2 callee (`map(rules, r -> call_contract(r, t))`) is retained as intentional fail-closed evidence and is **not** migrated to static dispatch (trade_robot already carries the positive static-dispatch baseline via TR-P06). RE-P02 (dynamic contract dispatch) route resolved to DEFER under a future canon-gated typed-union / typed-contract-reference design with an 8-part proof bar; no implementation authorized. RE-P03 (Unknown field access) and RE-P04 (Unknown output coercion) confirmed CLOSED-as-fail-closed (OOF-P1 + OOF-TY1, both toolchains). `output : Unknown` quarantine confirmed NOT a clean route for this app (Ruby OOF-P1 on `d.action` survives the D3 escape hatch). Diagnostics unchanged. No source edits. No compiler changes. No new OOF codes. Proof: `verify_dynamic_dispatch_p2.rb`; doc: `lab-docs/lang/lab-dynamic-contract-dispatch-p2-safe-route-v0.md`.

## Wave P11 Recheck Summary (2026-06-14)

Rust: oof / 2 diagnostics — unchanged from Wave P10 and `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` selected safe route.
Ruby: oof / 2 diagnostics — unchanged from Wave P10.

Diagnostics:

- Rust: `OOF-P1 Unresolved field: Unknown.action` (node `active_decisions`) + `OOF-TY1 Output type mismatch: expected RuleDecision, got Unknown` (node `decision`).
- Ruby: `OOF-P1 Unresolved symbol: d` + `OOF-P1 Unresolved field: Unknown.action` (node `active_decisions`).

BLOCKED status remains intentional fail-closed evidence for Tier 2 dynamic contract dispatch. No source changes. No new pressures. No regressions.

## Wave P12 Recheck Summary (2026-06-15)

Rust: oof / 2 diagnostics — unchanged from Wave P11 and `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` selected safe route.
Ruby: oof / 2 diagnostics — unchanged from Wave P11.

Diagnostics:

- Rust: `OOF-P1 Unresolved field: Unknown.action` (node `active_decisions`) + `OOF-TY1 Output type mismatch: expected RuleDecision, got Unknown` (node `decision`).
- Ruby: `OOF-P1 Unresolved symbol: d` (node `active_decisions`) + `OOF-P1 Unresolved field: Unknown.action` (node `active_decisions`).

BLOCKED status remains intentional fail-closed evidence for Tier 2 dynamic contract dispatch. No source changes. No new pressures. No regressions.

## Wave P13 Recheck Summary (2026-06-15)

Ruby: oof/2. Rust: oof/2. BLOCKED. Source files: 4. Source hash: `sha256:0cf7f61465246aedb46242c9c6c36add39f9d71956950461a7831e9bdc22486b`. Entrypoint: `none`. intentional fail-closed dynamic dispatch boundary.

Diagnostics preserved:

- Rust: `OOF-P1 Unresolved field: Unknown.action` (node `active_decisions`) + `OOF-TY1 Output type mismatch: expected RuleDecision, got Unknown` (node `decision`).
- Ruby: `OOF-P1 Unresolved symbol: d` (node `active_decisions`) + `OOF-P1 Unresolved field: Unknown.action` (node `active_decisions`).
No source changes in this wave. No new pressures. No regressions.

## VM RUN-OK Recheck P3 (2026-06-15)

Rust VM active-fleet recheck:

- Entrypoint selected by runtime fleet harness: `RunRuleEngine`.
- Status: COMPILE-NOT-OK, unchanged owner class.
- Diagnostics remain the intentional fail-closed dynamic dispatch boundary:
  `OOF-P1 Unresolved field: Unknown.action` and `OOF-TY1 Output type mismatch: expected
  RuleDecision, got Unknown`.
- Fleet context: `rule_engine` is now the only non-green app after `spreadsheet` moved to
  RUN-OK; overall RUN-OK is 24/25.

No source changes. No dynamic dispatch relaxation. Route remains the
`LAB-DYNAMIC-CONTRACT-DISPATCH-P2` selected safe route / ledger D-001.
