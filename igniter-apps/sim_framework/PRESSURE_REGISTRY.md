# Simulation Framework Pressure Registry

This registry tracks language and stdlib pressure from the `sim_framework` app. The app is a large simulation fixture with temporal state, relation-like collections, proof/audit records, constraints, decision trees, lens-style updates, and snapshot/trajectory concepts.

## Baseline

Rust compilation currently succeeds for:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/sim_framework/types.ig ../igniter-apps/sim_framework/temporal.ig ../igniter-apps/sim_framework/relation.ig ../igniter-apps/sim_framework/constraints.ig ../igniter-apps/sim_framework/rules.ig ../igniter-apps/sim_framework/engine.ig ../igniter-apps/sim_framework/example.ig --out /tmp/sim_framework.igapp
```

Fresh observed result: all stages complete, 26 contracts emit, and diagnostics are empty. Current source hash: `sha256:d4f40bdd10ac8aada58b224d590ba1400188aa507196883832c50acd0f7dfd4f`. Liveness counters are small (`typechecker.infer_expr.max_depth=6`, `form_resolver.walk_expr.max_depth=6`).

## Pressures

| ID | Name | Evidence | Status | Next route |
|---|---|---|---|---|
| SIM-P01 | Simulation framework Rust baseline | Seven-source app compiles through Rust with 26 contracts and no diagnostics | Positive, needs frozen proof | `LAB-SIM-FRAMEWORK-BASELINE-P1` |
| SIM-P02 | Temporal sliding window | `TemporalInteger` with current/prev_t1/prev_t2/prev_t3 supports evolve, delta, trend, and rewind contracts | Positive app pattern | Keep as app evidence; no built-in `Temporal[T]` yet |
| SIM-P03 | Fold in real app | `SumPopulation` uses `fold(populations, 0, (acc, val) -> acc + val)` | Positive | Add to fold regression evidence |
| SIM-P04 | Multi-output call_contract shape | Multi-output contracts force ambiguity; proof values are embedded in wrapper records instead | Active | `LAB-CALL-CONTRACT-MULTI-OUTPUT-P1` |
| SIM-P05 | Inline records in if/else branches | `CheckConstraint` uses helper `MakeViolation` because inline branch records infer poorly | Active | `LAB-IF-ELSE-RECORD-LITERAL-TYPING-P1` |
| SIM-P06 | Lens update verbosity | Lens contracts manually copy unchanged fields to update one nested temporal field | Active design pressure | `LAB-RECORD-WITH-UPDATE-P1` later |
| SIM-P07 | Snapshot / Trajectory concepts | `TakeSnapshot`, time travel, and trend analysis reveal app-local state-slice and time-indexed-history concepts | Candidate concepts | `LAB-SIMULATION-SNAPSHOT-TRAJECTORY-P1` later |
| SIM-P08 | Proof wrapper pattern | `ProvenEntity`-style wrapping keeps proof/audit data inside a single returned value | Positive workaround | Keep as pattern pending multi-output call design |
| SIM-P09 | Relational collection algebra | Select works; group-by/join/order-by remain blocked or inefficient | Active | `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` |
| SIM-P10 | ACTIVE | String/Text naming mismatch | Wave P4 (first Ruby check): `record literal field 'rule_name': expected String, got Text` in `corrective_event`; Ruby TC `concat(...)` returns type "Text" but `types.ig` declares `rule_name : String`; the two names are treated as distinct types | `LANG-STRING-TEXT-ALIAS-P1` |
| SIM-P11 | ACTIVE | OOF-TY1 cascade from SIM-P10 | Wave P4: `Output type mismatch: expected SimEvent, got Unknown` on `corrective_event` output boundary; cascades from SIM-P10 String/Text mismatch making field resolution fail → Unknown contract return → OOF-TY1 at boundary | Clears when SIM-P10 resolves; route: `LANG-STRING-TEXT-ALIAS-P1` |
| SIM-P12 | ACTIVE | Unannotated record literal inference gap (pop_constraint) | Wave P4: `Unresolved symbol: pop_constraint` in `violations` contract; `compute pop_constraint = { ... }` is an unannotated record literal; Ruby TC `infer_record_literal` returns Unknown when no output_type_hint is set | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| SIM-P13 | ACTIVE | Unannotated record literal inference gap (wolves) | Wave P4: `Unresolved symbol: wolves` in `initial_state` contract; `compute wolves = { ... }` is an unannotated record literal; same root cause as SIM-P12 | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |

## Interpretation

The bounded claim is: a static simulation framework with temporal windows, relations, constraints, decisions, lens-style updates, and snapshots compiles today. The app does not authorize built-in `Temporal[T]`, `Snapshot[T]`, `Trajectory[T]`, tensor semantics, or relational algebra.

The strongest immediate compiler/typechecker signals are multi-output `call_contract` result shape and record literal typing inside conditional branches. The strongest stdlib signal is relational collection algebra beyond flat `map`/`filter`/`fold`.

## Wave P4 Recheck Summary (2026-06-13)

**First Ruby TC check for this app.** Rust: CLEAN (ok / 0 diagnostics, unchanged). Ruby: oof / 4 diagnostics:
1. `record literal field 'rule_name': expected String, got Text` — SIM-P10; String/Text naming mismatch; `concat(...)` returns "Text" but type declares "String"
2. `Output type mismatch: expected SimEvent, got Unknown` — SIM-P11; cascade from SIM-P10 field mismatch → Unknown contract return → OOF-TY1
3. `Unresolved symbol: pop_constraint` — SIM-P12; unannotated record literal binding; `infer_record_literal` returns Unknown
4. `Unresolved symbol: wolves` — SIM-P13; unannotated record literal binding; same root cause

LANG-TYPED-COMPUTE-BINDING-P2 had zero effect (no annotated `compute name : Type = expr` bindings). New pressure count: 4 (SIM-P10 through SIM-P13).

## Recommended Route

1. `LAB-SIM-FRAMEWORK-BASELINE-P1` to freeze the 26-contract positive baseline.
2. `LAB-CALL-CONTRACT-MULTI-OUTPUT-P1` to classify multi-output call semantics separately from literal call parity.
3. `LAB-IF-ELSE-RECORD-LITERAL-TYPING-P1` to isolate record literal branch typing.
4. `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` after existing collection stabilization work.
5. `LAB-SIMULATION-SNAPSHOT-TRAJECTORY-P1` only after more design evidence accumulates.

## Non-Goals

- No built-in temporal, snapshot, trajectory, tensor, or simulation package is authorized by this app.
- No compiler-managed history depth is authorized.
- No dynamic rule pipeline or plugin model is authorized.
- No relational collection primitives are accepted yet.
- No app source migration is authorized by this registry.
