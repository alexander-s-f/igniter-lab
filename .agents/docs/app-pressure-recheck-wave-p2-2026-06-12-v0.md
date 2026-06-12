# APP-RECHECK-WAVE-P2 — App Pressure Recheck Rollup

**Date:** 2026-06-12  
**Wave:** P2  
**Gate check:** All 8 prerequisite cards CLOSED before recheck was performed.  
**Scope:** dsa, vector_editor, decision_tree, arch_patterns, dataframes, rule_engine, neural_net  
**Mode:** compile/report only — no app source edits, no proposals, no implementations

---

## Prerequisite Gate Check

All 8 prerequisite cards confirmed CLOSED before recheck:

| Card | Status | Proof |
|------|--------|-------|
| LANG-EMITTER-ENCODING-P2 | CLOSED — PROVED 18/18 PASS | igniter-lab/.agents/work/cards/lang/ |
| LANG-STDLIB-NUMERIC-COMPARISON-P3 | CLOSED — PROVED 46/46 PASS | igniter-lang/.agents/work/cards/lang/ |
| LANG-UNARY-OPERATORS-P4 | CLOSED — PROVED 47/47 PASS | igniter-lab/.agents/work/cards/lang/ |
| LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 | CLOSED — PROVED 70/70 PASS | igniter-lang/.agents/work/cards/lang/ |
| LANG-STDLIB-COLLECTION-CONCAT-PROP-P4 | CLOSED — PROVED 32/32 PASS | igniter-lang/.agents/work/cards/lang/ |
| LANG-STDLIB-IS-EMPTY-PROP-P4 | CLOSED — PROVED 50/50 PASS | igniter-lang/.agents/work/cards/lang/ |
| LANG-STDLIB-COLLECTION-APPEND-PROP-P4 | CLOSED — PROVED 66/66 PASS | igniter-lab/.agents/work/cards/lang/ |
| LANG-STDLIB-TEXT-EQUALITY-P3 | CLOSED — PROVED 52/52 PASS | igniter-lang/.agents/work/cards/lang/ |

Gate status: **CLEAR** — full recheck authorized.

---

## Compile Results Summary

| App | Rust status | Rust diags | Ruby status | Ruby diags | First blocker |
|-----|-------------|------------|-------------|------------|---------------|
| dsa | ok | 0 | oof | 15 | call_contract parity (DSA-P08) |
| vector_editor | oof | 1 | oof | 7 | call_contract parity (VE-P02/P03) |
| decision_tree | oof | 4 | error | 1 | call_contract append Rust / keyword(label) Ruby |
| arch_patterns | oof | 7 | oof | 39 | call_contract parity (AP-P02) |
| dataframes | ok | 0 | oof | 8 | call_contract parity (DF-P08) |
| rule_engine | ok | 0 | oof | 9 | call_contract parity (RE-P02/P03/P04) |
| neural_net | ok | 0 | oof | 12 | call_contract parity (NN-P08) |

Rust CLEAN apps: **dsa, dataframes, rule_engine, neural_net** (same as Wave P1).

---

## Resolutions Since Wave P1

### DSA-P09 — Ruby emitter UTF-8 encoding → RESOLVED
- **Prerequisite:** LANG-EMITTER-ENCODING-P2 CLOSED (18/18 PASS, 6 sites fixed)
- **Evidence:** Wave P2 unstripped Ruby recheck produces 15 actual diagnostics without JSON crash. Previously `types.ig` box-drawing chars (U+2500) caused `JSON::GeneratorError: "\xE2" on US-ASCII`.
- **Impact:** Full diagnostic surface now visible for DSA; call_contract parity (DSA-P08) is the sole remaining Ruby blocker.

### AP-P09 — `<` operator gap (arch_patterns Ruby TC) → RESOLVED
- **Prerequisite:** LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED (46/46 PASS)
- **Evidence:** Wave P2 unstripped Ruby recheck: 39 total diagnostics (vs 41 in P1); 2 fewer = the two `Unsupported operator: <` errors from pipeline.ig lines 30, 108 are gone. `ctx.command.amount < 1` and `ctx.account.balance < ctx.command.amount` now type-check correctly.
- **Impact:** numeric comparisons resolved for arch_patterns Ruby.

### AP-P10 — Ruby emitter UTF-8 encoding (arch_patterns) → RESOLVED
- **Prerequisite:** LANG-EMITTER-ENCODING-P2 CLOSED
- **Evidence:** Wave P2 unstripped Ruby recheck produces 39 diagnostics without crashing. Previously required UTF-8-stripped source workaround.

### DF-P09 — Ruby emitter UTF-8 encoding (dataframes) → RESOLVED
- **Prerequisite:** LANG-EMITTER-ENCODING-P2 CLOSED
- **Evidence:** Wave P2 unstripped Ruby recheck: 8 diagnostics without crash. Previously required stripped source.

### NN-P02 — Unary minus parser gap → RESOLVED
- **Prerequisite:** LANG-UNARY-OPERATORS-P3 (Ruby) + LANG-UNARY-OPERATORS-P4 (Rust) CLOSED
- **Evidence:** Language capability exists: unary `-` dual-toolchain. App source `0 - 500` workaround is stale but no source edits in this wave. No new diagnostics related to unary operators appear in Wave P2 output.

### NN-P07 — `<` operator gap (neural_net Ruby TC) → RESOLVED
- **Prerequisite:** LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED
- **Evidence:** Wave P2 unstripped Ruby recheck: 12 total diagnostics (vs 13 in P1); 1 fewer = the `Unsupported operator: <` from activations.ig line 26 (`x < (0 - 2500)`) is gone. SigmoidApprox now compiles in Ruby.

### RE-P04 — Unknown output coercion (rule_engine) → ACTIVE/CONFIRMED (improved diagnostics)
- **Prerequisite:** LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 CLOSED (70/70 PASS)
- **Evidence:** Wave P2 Ruby: "Output type mismatch: expected Collection[RuleDecision], got Unknown" × 3 (vs generic "Type mismatch: expected Collection, got Unknown" × 3 in P1). Same diagnostic count (9 total); error message is now specific — includes expected type name and full parametric info. The coercion is correctly rejected.
- **Status change:** HOLD/SAFETY-HIGH → ACTIVE/CONFIRMED (P3 makes the error precise; next: LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 for full parametric container coverage).

---

## No-Change Apps (Wave P1 state unchanged)

### vector_editor
- Rust: 1 diag (`call_contract: unknown callee 'append'`) — VE-P02 ACTIVE
- Ruby: 7 diags (4× call_contract, 3× Unresolved symbol) — VE-P03 ACTIVE
- No new resolutions. Dominant blocker: call_contract parity both toolchains.

### decision_tree
- Rust: 4 diags (all `call_contract: unknown callee 'append'`) — DT-P03 ACTIVE
- Ruby: error (1 diag — `ParseError: Expected name, got keyword(label)`) — DT-P02 ACTIVE
- No new resolutions. DT-P02 blocks all Ruby TC output; parser contextual-keyword fix is prerequisite.

---

## Newly Exposed Blockers

None. All Wave P2 diagnostics were known from Wave P1 minus the resolved pressures. No new blocking diagnostics discovered.

---

## App-by-App Detail

### dsa

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | ok | 0 | — (CLEAN) |
| Ruby | oof | 15 | `Unknown function: call_contract` |

Resolved this wave: DSA-P09 (UTF-8 encoding crash).  
Still active: DSA-P08 (call_contract parity — 9 call_contract errors, 3 output type mismatches, 3 unresolved symbols).

### vector_editor

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | oof | 1 | `call_contract: unknown callee 'append'` |
| Ruby | oof | 7 | `Unknown function: call_contract` |

No new resolutions. VE-P02 (Rust) and VE-P03 (Ruby) remain active.

### decision_tree

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | oof | 4 | `call_contract: unknown callee 'append'` |
| Ruby | error | 1 | `ParseError: Expected name, got keyword(label)` |

No new resolutions. DT-P02 (keyword label) blocks all Ruby TC output; DT-P03 (append call_contract) is first Rust blocker. Next route: LANG-PARSER-CONTEXTUAL-KEYWORDS-P1 per LAB-PARSER-LABEL-IDENTIFIER-P1 readiness proof.

### arch_patterns

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | oof | 7 | `call_contract: unknown callee 'append'` |
| Ruby | oof | 39 | `Unknown function: call_contract` |

Resolved this wave: AP-P09 (`<` operator), AP-P10 (UTF-8 encoding crash).  
Still active: AP-P02 (call_contract append × 7 Rust), AP-P03 (fold/event-replay).

### dataframes

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | ok | 0 | — (CLEAN) |
| Ruby | oof | 8 | `Unknown function: call_contract` |

Resolved this wave: DF-P09 (UTF-8 encoding crash).  
Still active: DF-P08 (call_contract parity — 6 calls, 2 unresolved).

### rule_engine

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | ok | 0 | — (CLEAN) |
| Ruby | oof | 9 | `Unknown function: call_contract` |

RE-P04 diagnostic improved (LANG-OUTPUT-TYPE-ASSIGNABILITY-P3): error message now carries full type info.  
Still active: RE-P02 (dynamic dispatch), RE-P03 (Unknown field access), RE-P04 (output coercion, confirmed).

### neural_net

| Toolchain | Status | Diag count | First blocking diagnostic |
|-----------|--------|------------|--------------------------|
| Rust | ok | 0 | — (CLEAN) |
| Ruby | oof | 12 | `Unknown function: call_contract` |

Resolved this wave: NN-P02 (unary minus — language capability available), NN-P07 (`<` operator).  
Still active: NN-P08 (call_contract parity — 7 calls).

---

## Cross-App Pressure Clusters (Post Wave P2)

| Cluster | Status | Apps | Route |
|---------|--------|------|-------|
| call_contract Rust (append callee) | ACTIVE | vector_editor, decision_tree, arch_patterns | call_contract parity |
| call_contract Ruby (all forms) | ACTIVE | dsa, vector_editor, decision_tree, arch_patterns, dataframes, rule_engine, neural_net | LANG-RUBY-CALL-CONTRACT-PARITY-P2 |
| parser keyword hygiene | ACTIVE | decision_tree | LANG-PARSER-CONTEXTUAL-KEYWORDS-P1 |
| Unknown safety (output/field/dynamic) | ACTIVE/SAFETY | rule_engine | LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 / LAB-DYNAMIC-CONTRACT-DISPATCH-P1 |
| find-one / scalar extraction | ACTIVE | dsa, decision_tree | LAB-STDLIB-FIND-ONE-P1 |
| fold / reduction | ACTIVE | arch_patterns, neural_net | fold track |

UTF-8 encoding cluster fully closed across all apps.  
Numeric comparison (`<`, `<=`, `>=`) cluster fully closed.  
Unary minus cluster fully closed.

---

## Next Route (Post Wave P2)

The dominant cross-app blocker is **call_contract parity** — 7 apps affected in Ruby, 3 in Rust. This should be the priority for Wave P3 prerequisites:

1. **LANG-RUBY-CALL-CONTRACT-PARITY-P2** — Ruby TC call_contract dispatch implementation (Tier 1: literal module calls; deferred: stdlib-form calls).
2. **LANG-PARSER-CONTEXTUAL-KEYWORDS-P1** — unblock decision_tree Ruby; readiness proof complete (LAB-PARSER-LABEL-IDENTIFIER-P1).
3. **LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2** — implementation planning for parametric container assignability (rule_engine RE-P04 next step).
4. **LAB-STDLIB-FIND-ONE-P1** — scalar extraction for dsa/decision_tree.
