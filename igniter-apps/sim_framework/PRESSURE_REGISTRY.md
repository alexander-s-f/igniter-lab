# Simulation Framework Pressure Registry

Updated: 2026-06-14 (APP-RECHECK-WAVE-P10 — DUAL-CLEAN)

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
| SIM-P10 | RESOLVED | String/Text naming mismatch | Wave P4: `record literal field 'rule_name': expected String, got Text` — `concat(String,String)` returned Text; `SimEvent.rule_name : String`. LANG-STRING-TEXT-ALIAS-P2: input-type-driven concat return — when both args are String, returns String (`stdlib.string.concat`); field check passes. | `LANG-STRING-TEXT-ALIAS-P2` CLOSED |
| SIM-P11 | RESOLVED | OOF-TY1 cascade from SIM-P10 | Wave P4: `Output type mismatch: expected SimEvent, got Unknown` — cascaded from SIM-P10 field error making record literal Unknown. Cleared by SIM-P10 resolution: concat(String,String)→String; record literal resolves to SimEvent; output boundary clean. | `LANG-STRING-TEXT-ALIAS-P2` CLOSED |
| SIM-P12 | RESOLVED | Unannotated record literal inference gap (pop_constraint) | Wave P4: `Unresolved symbol: pop_constraint` in `violations` contract; `compute pop_constraint = { ... }` is an unannotated record literal; Ruby TC `infer_record_literal` returns Unknown when no output_type_hint is set. Wave P6: LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved via structural candidate matching → `ConstraintViolation` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` CLOSED |
| SIM-P13 | RESOLVED | Unannotated record literal inference gap (wolves) | Wave P4: `Unresolved symbol: wolves` in `initial_state` contract; `compute wolves = { ... }` is an unannotated record literal; same root cause as SIM-P12. Wave P6: LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved via structural candidate matching | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` CLOSED |
| SIM-P14 | RESOLVED | Empty array field blocks SimState structural matching | Wave P7: `initial_state = { tick:0, entities:[...], events:[], proofs:[], violations:[] }` — three fields are `[]` → `Collection[Unknown]`; `structurally_assignable?(Collection[Unknown], Collection[SimEvent])` returns false at param depth → SimState rejected as candidate. Resolved: `empty_collection_assignable?` helper + or-clause in `infer_record_literal` structural filter. | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P5` CLOSED |

## Interpretation

The bounded claim is: a static simulation framework with temporal windows, relations, constraints, decisions, lens-style updates, and snapshots compiles today. The app does not authorize built-in `Temporal[T]`, `Snapshot[T]`, `Trajectory[T]`, tensor semantics, or relational algebra.

The strongest immediate compiler/typechecker signals are multi-output `call_contract` result shape and record literal typing inside conditional branches. The strongest stdlib signal is relational collection algebra beyond flat `map`/`filter`/`fold`.

## Wave P6 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: oof / 3 diagnostics (was 4, −1). LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved SIM-P12 (`pop_constraint` → `ConstraintViolation`) and SIM-P13 (`wolves` → inferred type via structural matching). Both ACTIVE_TRUE_INTERMEDIATE symbols RESOLVED. Remaining 3 Ruby diags: (1) `record literal field 'rule_name': expected String, got Text` (SIM-P10 — unchanged), (2) `Output type mismatch: expected SimEvent, got Unknown` (SIM-P11 cascade — unchanged), (3) `Unresolved symbol: initial_state` (SIM-P14 NEW). SIM-P14: `compute initial_state = { tick: 0, entities: [wolves, rabbits, deer, bears], events: [], proofs: [], violations: [] }` (example.ig:66) — P3 structural candidate matching finds `SimState` as the only field-name-set match, but excludes it because the empty array fields (`events: []`, `proofs: []`, `violations: []`) produce `Collection[Unknown]` which fails `structurally_assignable?(Collection[Unknown], Collection[SimEvent])` at param depth — `structurally_assignable?` line 1536 returns false when `actual` param is Unknown. This is correct-but-strict behavior; P3's bare-Unknown permissive only applies at the top field level. Route: LANG-RUBY-RECORD-LITERAL-INFERENCE-P4 (param-depth Collection[Unknown] permissive extension) or app annotation of empty-collection computes. No regressions.

| SIM-P14 | ACTIVE | `initial_state` structural match fails — `Collection[Unknown]` param-depth rejection | Wave P6: `Unresolved symbol: initial_state` — `compute initial_state = { ... events: [], proofs: [], violations: [] }` (example.ig:66); `SimState` is the unique field-name-set match but excluded because `structurally_assignable?(Collection[Unknown], Collection[SimEvent])` returns false at param depth (line 1536: actual=Unknown → false); P3 permissive only applies at top-field level; zero candidates → Unknown → downstream OOF-P1 | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` (param-depth permissive) or app: annotate empty-collection fields |

## Wave P5 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged from Wave P4. Ruby: oof / 4 diagnostics — unchanged from Wave P4. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: SIM-P10/P11 are String/Text alias (NOT_RECORD_LITERAL); SIM-P12/P13 (`pop_constraint`, `wolves`) are unannotated record literals (ACTIVE_TRUE_INTERMEDIATE) — none are annotated `compute name : Type = { ... }` forms. No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

**First Ruby TC check for this app.** Rust: CLEAN (ok / 0 diagnostics, unchanged). Ruby: oof / 4 diagnostics:
1. `record literal field 'rule_name': expected String, got Text` — SIM-P10; String/Text naming mismatch; `concat(...)` returns "Text" but type declares "String"
2. `Output type mismatch: expected SimEvent, got Unknown` — SIM-P11; cascade from SIM-P10 field mismatch → Unknown contract return → OOF-TY1
3. `Unresolved symbol: pop_constraint` — SIM-P12; unannotated record literal binding; `infer_record_literal` returns Unknown
4. `Unresolved symbol: wolves` — SIM-P13; unannotated record literal binding; same root cause

LANG-TYPED-COMPUTE-BINDING-P2 had zero effect (no annotated `compute name : Type = expr` bindings). New pressure count: 4 (SIM-P10 through SIM-P13).

## Wave P8 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: **ok / 0 diagnostics** — DUAL-CLEAN achieved. SIM-P10/P11 RESOLVED by LANG-STRING-TEXT-ALIAS-P2 (`concat(String,String)→String`). SIM-P14 RESOLVED by LANG-RUBY-RECORD-LITERAL-INFERENCE-P5 (`empty_collection_assignable?` + or-clause in structural matching). All 14 pressures SIM-P01 through SIM-P14 now resolved or documented. sim_framework is the **8th app to reach DUAL-CLEAN status**.

## Wave P7 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: oof / 3 diagnostics — unchanged from Wave P6. SIM-P10 ACTIVE (`record literal field 'rule_name': expected String, got Text` — String/Text alias). SIM-P11 ACTIVE (OOF-TY1 cascade from SIM-P10). SIM-P14 ACTIVE (`Unresolved symbol: initial_state` — `Collection[Unknown]` param-depth rejection in `structurally_assignable?`; route: `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4`). SIM-P12 and SIM-P13 RESOLVED (Wave P6). No new pressures. No regressions.

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

## Wave P9 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, LAB-VE-NEW-OBJ-INFERENCE-P1, LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1, LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2, and LAB-PARSER-RECORD-IN-HOF-P1 had no effect on this app. No new pressures. No regressions.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. No pressure ID changes this wave. No new pressures. No regressions.
