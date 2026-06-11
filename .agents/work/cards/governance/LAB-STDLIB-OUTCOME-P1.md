# LAB-STDLIB-OUTCOME-P1 — Outcome Helpers Stdlib Pressure Proof

**Track:** stdlib-outcome-helper-pressure-and-stringly-kind-reduction-v0
**Route:** LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION
**Status:** CLOSED — PASS 66/66
**Date:** 2026-06-11
**Predecessors:** PROP-047-P2, LAB-FAILURE-TAXONOMY-P4, LAB-EPISTEMIC-OUTCOME-P2/P4, LAB-OUTCOME-VARIANT-P1..P3, LANG-STDLIB-ENTRY-CONTRACT-P1, LAB-STDLIB-FOUNDATION-P1
**Successor:** LAB-STDLIB-OUTCOME-P2 (implementation planning — not yet authorized)

---

## Research Question

Can stdlib outcome helpers reduce stringly `kind` handling without collapsing
domain-specific outcomes or granting runtime authority?

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Fixtures (3 domains) | `igniter-lab/igniter-view-engine/fixtures/stdlib_outcome/*.ig` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_outcome_p1.rb` | 66/66 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-stdlib-outcome-helper-pressure-proof-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-OUTCOME-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Fixture Inventory (3 domains)

| File | Domain | Stable terms | Domain-local kinds |
|------|--------|--------------|--------------------|
| `http_client_outcome.ig` | Network/HTTP | denied, timed_out, unknown_external_state, system_error, query_error | ok, redirect, rate_limited |
| `storage_query_outcome.ig` | Storage/Query | denied, system_error, query_error, unknown_external_state, partial_success | rows, empty, found, created, conflict |
| `epistemic_reconciliation_outcome.ig` | Epistemic/Reconciliation | denied, timed_out, unknown_external_state, system_error, partial_success | confirmed_succeeded, confirmed_failed, still_unknown, reconciliation_denied, reconciliation_error |

All 6 PROP-047 stable terms appear in ≥2 domains. Domain-local kinds are domain-exclusive.

---

## Helper Verdicts

| Helper | Input → Output | Verdict | Notes |
|--------|---------------|---------|-------|
| `stdlib.outcome.is_denied` | `Map[String,String] → Bool` | ACCEPT | |
| `stdlib.outcome.is_unknown_external_state` | `Map[String,String] → Bool` | ACCEPT | |
| `stdlib.outcome.is_timed_out` | `Map[String,String] → Bool` | ACCEPT | |
| `stdlib.outcome.is_system_error` | `Map[String,String] → Bool` | ACCEPT | |
| `stdlib.outcome.is_query_error` | `Map[String,String] → Bool` | ACCEPT | |
| `stdlib.outcome.is_partial_success` | `Map[String,String] → Bool` | ACCEPT | |
| `stdlib.outcome.kind` | `Map[String,String] → String` | ACCEPT | Opaque passthrough |
| `stdlib.outcome.is_retryable` | `Map[String,String] → Bool` | CONDITIONAL ACCEPT | Axis-9 only; see below |
| `stdlib.outcome.route` | — | REJECT | Encodes policy = runtime authority |

---

## is_retryable Axis-9 Boundary

| Outcome kind | is_retryable | Rationale |
|-------------|-------------|-----------|
| `denied` | false | Deterministic refusal; PROP-047 FC-1 |
| `unknown_external_state` | false | Reconcile not retry; Covenant P15 |
| `system_error` | true | Retry with backoff |
| `timed_out` (dispatch_started=false) | true | Pre-dispatch; safe to retry |
| `timed_out` (dispatch_started=true) | false | Post-dispatch = unknown-state path |
| `query_error` | false | Malformed input; retry unhelpful |
| domain-local kinds | false | Generic helper cannot know domain semantics |

Entry contract `totality` field MUST document axis-9 boundary. Callers with
domain-specific retry logic MUST use direct kind comparison.

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 6 | 3 domains, ≥5/4/4 kinds, 6 stable terms ≥2 domains, domain-exclusive local kinds |
| B — Helper model | 6 | Hash input, no generic type, Bool return, kind passthrough, module-method-only, route() rejection |
| C — Positive stable terms | 8 | Each is_* correct per term; mutual exclusion; kind() exact |
| D — Domain-local preservation | 8 | No false collapse; kind() preserves domain-local strings exactly |
| E — Retry/routing safety | 7 | Axis-9 boundary: denied/unknown/post-dispatch/query_error → false; system_error → true |
| F — Stringly reduction | 5 | Shorter call site; centralized string; typo detection; domain-local passthrough; no fallback |
| G — KDR/variant boundary | 5 | Hash not variant; variant arms not stable terms; no exhaustiveness required |
| H — Authority closed | 8 | Idempotent; no scheduling; no state; frozen input; route() rejected; IO-free; side-effect-free |
| I — Entry contract pressure | 7 | LANG-STDLIB-ENTRY-CONTRACT schema: name, purity, authority, demand, determinism, totality, signature |
| J — Decision | 6 | ACCEPT 7, CONDITIONAL 1, REJECT 1, no domain-local helpers, P2 gate |

**Total: 66/66 PASS**

---

## Methodology

Proof-local Ruby model only. No compiler binary or VM binary invoked.
`OutcomeH` Ruby module defines proof-local predicates.
Fixture data is Ruby hash constants (KDR-like records).
`.ig` fixture files provide domain context; not compiled in P1.

---

## Domain-Local Preservation Rule

Generic helpers return `false` for any kind string not equal to their exact stable term.
There is no "fallback unknown" behavior. `kind()` always passes the string through unchanged.
Callers must use `kind()` directly for domain-local routing. This rule is non-negotiable:
if a helper absorbed domain-local kinds, it would erase domain-specific recovery semantics
and violate PROP-047 FC-rules (FC-4..FC-7 `partial_success`, FC-8..FC-10 validation/capability).

---

## Authority Closed

| Surface | Status |
|---------|--------|
| stdlib implementation | CLOSED |
| parser / typechecker / SemanticIR / assembler | CLOSED |
| VM / runtime | CLOSED |
| Canon outcome type | CLOSED |
| Generic `Outcome[T,E]` | CLOSED |
| Global `FailureKind` enum | CLOSED |
| Variant enforcement changes | CLOSED |
| Public API / package | CLOSED |
| New OOF diagnostic codes | CLOSED |

---

## Open Questions for P2

1. Implementation form: pattern-match dispatch vs stdlib-inventory dispatch table entries
2. `is_retryable` boundary documentation requirements in entry contract `totality` field
3. Input type precision: `Map[String, String]` vs `Map[String, Any]` for `dispatch_started`
4. `is_partial_success` proof_lineage must reference LAB-FAILURE-TAXONOMY-P4 explicitly

---

## Next Route

**LAB-STDLIB-OUTCOME-P2** — Implementation Planning

Gates satisfied:
- 66/66 PASS ✓
- 3-domain cross-domain demand established ✓
- 7 ACCEPT + 1 CONDITIONAL + 1 REJECT verdicts ✓
- Entry contract sketches for 3 representative helpers ✓
- Authority boundary fully documented ✓
- 4 open questions enumerated ✓

P2 scope: implementation form decision, input-type precision resolution,
entry contract records for `stdlib-inventory.json`, proof matrix (≥50 checks).
