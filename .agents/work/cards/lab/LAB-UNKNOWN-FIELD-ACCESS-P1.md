# LAB-UNKNOWN-FIELD-ACCESS-P1 — Unknown Field Access Safety Boundary

**Track:** lab / safety / type-system
**Route:** EVIDENCE + SAFETY BOUNDARY CLASSIFICATION
**Status:** CLOSED — PROVED 35/35 — SAFETY POLICY ESTABLISHED + DIVERGENCE DOCUMENTED
**Date:** 2026-06-13
**Predecessors:** LAB-DYNAMIC-CONTRACT-DISPATCH-P1, LANG-OUTPUT-TYPE-ASSIGNABILITY-P4

---

## Goal

Classify field access on Unknown-typed objects: where it occurs, how Ruby and Rust TC
handle it, whether it bypasses output safety, what OOF code applies, and what route
(if any) would unblock rule_engine safely.

---

## Trigger

LAB-DYNAMIC-CONTRACT-DISPATCH-P1 classified dynamic callee + typed output as BLOCKED
and deferred `d.action` (field access on Unknown result inside HOF lambda) to this card.
Active pressure: RE-P03 (`Unresolved field: Unknown.action` in Ruby).

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/lang/lab-unknown-field-access-p1-safety-boundary-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_unknown_field_access_p1.rb` | 35/35 PASS |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-UNKNOWN-FIELD-ACCESS-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Key Finding: HOF Lambda Error Propagation Divergence

**Ruby TC (`typechecker.rb:2544`)**: lambda body errors pass the same `type_errors`
reference into `infer_lambda_body`. OOF-P1 from field access on Unknown propagates
to the contract's error list.

**Rust TC (`typechecker.rs:2975, 3075`)**: `filter` and `map` HOF create a local
`temp_errors = Vec::new()` for lambda body typecheck. Body errors are **never merged**
into `type_errors`. Only OOF-COL3 (predicate must return Bool) propagates.

This is the root cause of the rule_engine Wave P7 diagnostic divergence:
- Ruby: `Unresolved symbol: d` + `Unresolved field: Unknown.action` (OOF-P1 × 2)
- Rust: `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]`
        + `Output type mismatch: expected RuleDecision, got Unknown` (OOF-TY1 × 2)

---

## Findings (7 Questions Answered)

**Q1. Where does field access on Unknown occur in apps?**
One site: `rule_engine/engine.ig:27` — `d.action` inside `filter(raw_decisions, d -> ...)`,
where `d : Unknown` (element of `Collection[Unknown]` from Tier 2 dynamic callee).
No other app has Unknown field access.

**Q2. Does Ruby allow it, block it, or degrade it?**
Ruby **BLOCKS** in all contexts.
- Direct context: OOF-P1 "Unresolved field: Unknown.X" (typechecker.rb:966-967)
- HOF lambda context: OOF-P1 propagates from lambda body (same type_errors reference)
- Lambda param bound to Unknown also fires OOF-P1 "Unresolved symbol: {param}" (line 929)

**Q3. Does Rust allow it, block it, or degrade it?**
- Direct context: Rust **BLOCKS** — OOF-P1 fires (typechecker.rs:2419-2425)
- HOF lambda context: Rust **SILENCES** — lambda body errors go to `temp_errors` (discarded)
- Rust compensates via OOF-TY1 at the output boundary (D2 rule)

**Q4. Does Unknown field access bypass output safety?**
**No.** Different diagnostic paths, same safety outcome:
- Ruby: OOF-P1 upstream → `blocking_rule_present?("OOF-P1")` suppresses OOF-TY1. Still blocked.
- Rust: HOF lambda OOF-P1 silenced → OOF-TY1 fires at output boundary. Still blocked.

**Q5. Should it require explicit quarantine via output Unknown?**
**Partial quarantine only.** Declaring `output : Unknown` (D3 rule) removes OOF-TY1,
but Ruby still fires OOF-P1 for field access inside HOF lambda. No clean compile path
in Ruby without suppressing lambda body field access errors. Full quarantine not available.

**Q6. Should it produce OOF-P1, OOF-TY0, or a new code?**
**OOF-P1 is correct. No new code needed.**
"Unresolved field: Unknown.X" is semantically accurate. The divergence is in HOF lambda
error propagation, not in field access semantics. A separate card
(LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1) would address Rust silencing.

**Q7. What route would unblock rule_engine safely?**
**No safe route in current stage.** Requires one of:
- Validation receipt semantics (future canon work, not scoped)
- Tier 2 type narrowing / cast operator (not in language surface)
- Static rule-set typed dispatch table (architectural change)

Interim: `output : Unknown` removes OOF-TY1 but Ruby OOF-P1 remains. Not recommended.

---

## Verdict: PROVED 35/35 — SAFETY POLICY ESTABLISHED

```
Result: 35/35 PASS
VERDICT: PASS — LAB-UNKNOWN-FIELD-ACCESS-P1 PROVED

  Unknown field access sites:        1 (rule_engine/engine.ig:27)
  Other apps:                        0 (all concrete types)

  Ruby TC direct:                    BLOCKS — OOF-P1
  Ruby TC HOF lambda:                BLOCKS — OOF-P1 propagates
  Rust TC direct:                    BLOCKS — OOF-P1
  Rust TC HOF lambda:                SILENCES OOF-P1 (temp_errors), OOF-TY1 compensates

  Output safety bypassed?            NO (both toolchains block)
  New OOF code needed?               NO (OOF-P1 sufficient)
  Unblock route for rule_engine?     NONE in current stage
```

---

## Proof Matrix (35 checks / 7 sections)

| Section | Checks | Result |
|---------|--------|--------|
| A — Source census | 5 | 5/5 PASS |
| B — Ruby TC direct field access on Unknown | 6 | 6/6 PASS |
| C — Rust TC field access (direct + HOF divergence) | 5 | 5/5 PASS |
| D — Dynamic dispatch + field access chain | 5 | 5/5 PASS |
| E — Output boundary interaction | 5 | 5/5 PASS |
| F — Safety policy classification | 5 | 5/5 PASS |
| G — Closed surfaces | 4 | 4/4 PASS |

---

## Safety Policy Table

| Form | Status |
|------|--------|
| Field access on concrete record type | ACCEPTED |
| Direct field access on Unknown | BLOCKED (OOF-P1, both TCs) |
| HOF lambda field access on Unknown (Ruby) | BLOCKED (OOF-P1 propagates) |
| HOF lambda field access on Unknown (Rust) | SILENCED in lambda; BLOCKED at output (OOF-TY1) |
| Unknown field + Unknown output annotation | PARTIAL QUARANTINE (OOF-TY1 removed; OOF-P1 remains in Ruby) |

---

## New Divergence Documented

**LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1** (successor card):
Rust HOF `filter`/`map` use `temp_errors` (discarded) for lambda body typecheck.
Ruby propagates lambda body errors to parent `type_errors`.
This causes systematic Rust silencing of OOF-P1 inside HOF lambdas. The output
boundary (OOF-TY1) compensates for safety, but the divergence should be tracked.

---

## OOF Codes

| Code | Role in this card |
|------|-----------------|
| OOF-P1 | Correct code for Unknown field access (no change) |
| OOF-TY1 | Output boundary block for Unknown→T (D2 rule) |

No new OOF codes introduced.

---

## Authority Closed

- No changes to any compiler or TC source file
- No new OOF codes
- No HOF lambda error propagation changes
- No cast or type-narrowing operator
- No engine.ig source changes

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-RULE-ENGINE-BASELINE-P1 | Re-freeze rule_engine baseline post P-series |
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 | Rust HOF temp_errors vs Ruby propagation divergence |
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Parametric container assignability implementation planning |
