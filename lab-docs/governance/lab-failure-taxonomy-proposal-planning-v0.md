# LAB-FAILURE-TAXONOMY-P1: Failure Taxonomy Proposal-Planning

**Card:** LAB-FAILURE-TAXONOMY-P1  
**Track:** lab-failure-taxonomy-proposal-planning-v0  
**Route:** GOVERNANCE / TAXONOMY RESEARCH / NO IMPLEMENTATION  
**Status:** CLOSED — proposal-planning complete  
**Authority:** lab_only — no runtime behavior, no compiler change, no Outcome[T,E]  
**Date:** 2026-06-10  
**Predecessor:** PROP-044-P8, PROP-044-P9, LAB-OUTCOME-VARIANT-P1

---

## TAXONOMY-EVIDENCE — Inventory of Proof Sources

### Evidence chain (9 sources)

| Source | Track | Outcome/Failure Vocabulary | KDR or Variant? |
|--------|-------|---------------------------|-----------------|
| Ch12 (`ch12-effect-surface.md`) | Canon | 7 outcome kinds: `succeeded`, `failed`, `partial`, `timed_out`, `unknown_external_state`, `compensated`, `cancelled` | Named but unimplemented |
| Covenant P11/P13/P15/P16/P17 | Canon | Uncertainty preservation, observation typing (real/model/human), timeout ≠ failure, idempotency required, compensation named | Covenant rules |
| LAB-EPISTEMIC-OUTCOME-P2 | KDR convention | `succeeded`, `denied`, `timed_out`, `unknown_external_state`, `partial`, `cancelled`, `compensated` as `kind:String` | KDR |
| LAB-EPISTEMIC-OUTCOME-P4 | KDR routing | `confirmed_succeeded`, `confirmed_failed`, `still_unknown`, `partially_confirmed`, `reconciliation_denied`, `reconciliation_error` | KDR (5 + terminal) |
| LAB-OUTCOME-VARIANT-P1 | Variant outcome | 11 arms: `ConfirmedSucceeded{Real\|Human\|Model}`, `ConfirmedFailed{Retryable\|Compensatable\|Terminal}`, `StillUnknown{WithBudget\|NoBudget}`, `PartiallyConfirmed`, `ReconciliationDenied`, `ReconciliationError` | Variant (Path B) |
| LAB-EXECUTE-QUERY-P1/P2 | Storage query | `rows`, `empty`, `denied`, `query_error`, `system_error` | KDR |
| LAB-FILTER-EVAL-P1 | Query filter | `rows`, `empty`, `query_error` (subset of query domain) | KDR |
| LAB-RESULT-ENVELOPE-P1/P2 | Validation/Web | `valid`, `invalid`, `unauthorized`, `system_error` (Validation); `ok`, `denied`, `error` (HTTP) | KDR |
| LAB-EXECUTE-QUERY-P1 + Network proofs | HTTP / ContractResult | `found`, `created`, `not_found`, `upstream_error`, `capability_denied`, `upstream_unavailable` (ContractResult); E-HTTP-* error codes | KDR + domain-local |

### Key finding from evidence inventory

No single domain uses identical vocabulary. The cross-domain patterns are **semantic** (denial-as-data, timeout ≠ failure, epistemic distinction) rather than **lexical** (shared string values). The KDR `kind: String` convention enables composition without requiring shared vocabulary. A global enum would impose false unification.

---

## TAXONOMY-AXES — Orthogonal Axes and Why One Enum Is Dangerous

### The 10 required axes

Each axis is orthogonal. Collapsing any two creates routing errors.

| Axis | Description | Evidence |
|------|-------------|---------|
| **1. Capability denial** | The authority surface refused the operation before it was attempted. Deterministic. Do not retry with same credentials/plan. | `denied` (Query), `capability_denied` (ContractResult), `unauthorized` (Validation), P15 guardrail |
| **2. Malformed plan/input** | The request is structurally invalid — fix it before retrying. Not an access control issue. | `query_error` (bad operator, bad limit), E-HTTP-CLIENT-ERROR (4xx), `invalid` (Validation) |
| **3. External system unavailable** | The upstream system could not be reached or returned a retriable infrastructure error. | `upstream_unavailable` (ContractResult/Sidekiq), E-HTTP-SERVER-ERROR (5xx), `system_error` |
| **4. Timeout** | Time limit exceeded. Outcome is **unknown**, not failed. P15: timeout is `UnknownExternalOutcome`, not `ObservedFailure`. Do not retry as a failure. Reconcile. | `timed_out` (Ch12), Covenant P15 |
| **5. Unknown external state / lost acknowledgement** | Request was sent; no confirmation received. State may be succeeded or failed. Must reconcile. Never route to success or failure branches directly. | `unknown_external_state` (Ch12/P2), `StillUnknown{WithBudget\|NoBudget}` (variant), Covenant P15 |
| **6. Partial success** | Some sub-effects confirmed; some unconfirmed. Not the same as unknown. Some resource handles may be valid. | `partial` (Ch12), `partially_confirmed` (P4), `PartiallyConfirmed` (variant) |
| **7. Validation invalid** | Domain constraint violated by input data. Not access denial, not infrastructure. Consumer fixes the data. | `invalid` (Validation), `query_error` when plan field semantically wrong |
| **8. Compensation required / compensation failed** | An irreversible operation completed but must be undone or logged. P17: compensation contract named or `no_compensation` declared. | `compensated` (Ch12), `ConfirmedFailedCompensatable` (variant) |
| **9. Retryable vs non-retryable** | Cross-cutting dimension. Whether a given failure kind permits automatic retry. P16: idempotency key required for retry-enabled operations. | `ConfirmedFailedRetryable` vs `ConfirmedFailedTerminal`, `non_retryable` (Sidekiq) |
| **10. Programmer/type error vs domain outcome** | A compile-time type violation (OOF diagnostic) is not a domain outcome. A mismatched arm type is not a domain failure. These must not appear in domain KDR or variant arms. | OOF-KIND1..6 (TypeChecker diagnostics); these are compiler diagnostics, not runtime outcomes |

### Why one global failure enum is dangerous

**Collapsing axis 1 with axis 2:**  
`denied` (capability) vs `query_error` (malformed plan) — proven distinct by LAB-EXECUTE-QUERY-P1/P2. G4 clamp is `cap_granted:true`; G1–G3 denial is `cap_granted:false`. Merging them forces consumers to inspect a second field to recover the original distinction.

**Collapsing axis 3 with axes 4 and 5:**  
`upstream_unavailable` (system down, retry later) vs `timed_out` (our clock expired, outcome unknown) vs `unknown_external_state` (request sent, no receipt) — three distinct recovery strategies. A single "unavailable/timeout/unknown" bucket erases them.

**Collapsing axis 5 with axis 3:**  
`unknown_external_state` requires reconciliation. `upstream_unavailable` requires retry with backoff. Covenant P15 explicitly forbids treating timeout as failure; collapsing unknown state with infrastructure failure violates the same principle.

**Collapsing axis 6 with axis 5:**  
`partially_confirmed` means some sub-effects succeeded — recovery strategy differs from "no confirmation at all." A reconciliation pass on `partial` should validate what succeeded, not start over.

**Collapsing axis 7 with axis 1:**  
`invalid` (data violates constraint) vs `unauthorized` (not permitted to submit) — LAB-RESULT-ENVELOPE-P2 proves these are distinct. "Fix your data" vs "Fix your credentials" are different consumer instructions.

**Collapsing axis 9 orthogonally:**  
Retryability is not a kind. `ConfirmedFailedRetryable` is not the same as "failure with retry=true flag." The arm name encodes the recovery path; a boolean collapses arms that differ in required payload (idempotency_key, compensation name).

**Conclusion:** A global `enum FailureKind` with 10–20 values would require consumers to maintain 10-axis mental models against a flat list. The KDR convention and variant/match surface are strictly more expressive because they compose domain-local vocabulary with the shared semantic axes as naming conventions, not as a single type.

---

## TAXONOMY-CANDIDATES — Candidate Reusable Names with Definitions

These terms appear in ≥2 proof tracks with stable, compatible meanings. They are candidates for a future cross-domain naming convention, not for a global enum.

| Term | Definition | Tracks with evidence | Stability |
|------|-----------|---------------------|----------|
| **`denied`** | Capability or authority surface refused the operation before it started. Deterministic — same request will be denied again. Consumer must change credentials, source, or plan structure. | Query (LAB-EXECUTE-QUERY-P2), HTTP (LAB-RESULT-ENVELOPE-P2), Validation (`unauthorized`), ContractResult (`capability_denied`) | High — 4+ proofs, no contradictions |
| **`unknown_external_state`** / `still_unknown` | Request was dispatched; no confirmed receipt. Outcome may be succeeded or failed. The correct response is reconciliation, not retry-as-failure. | Ch12, LAB-EPISTEMIC-OUTCOME-P2, P4, LAB-OUTCOME-VARIANT-P1 | High — Covenant P15; named in canon and proven in 3 proofs |
| **`partial`** / `partially_confirmed` | Some sub-effects succeeded; rest unconfirmed or unresolved. Not the same as unknown (some resource handles are valid). | Ch12 (`partial`), LAB-EPISTEMIC-OUTCOME-P4 (`partially_confirmed`), LAB-OUTCOME-VARIANT-P1 (`PartiallyConfirmed`) | Medium — reconciliation strategy differs from unknown |
| **`timed_out`** | Time limit elapsed without a response. Outcome unknown (not failed). | Ch12 (`timed_out`), Covenant P15 | High — explicitly named in canon, covenant principle |
| **`system_error`** | Infrastructure-level failure. Not a domain error, not access denial. Consumer retries with backoff. | LAB-RESULT-ENVELOPE-P2 (Validation), Query (LAB-EXECUTE-QUERY-P2) | Medium — present in 2 proofs; name stable |
| **`query_error`** / malformed plan | Input or plan is structurally or semantically invalid. Fix the plan before retrying. Not access control. | LAB-EXECUTE-QUERY-P1/P2, LAB-FILTER-EVAL-P1, LAB-QUERY-ORDER-LIMIT-P1 | High — proven distinct from denial in 4 proofs |
| **denial-as-data** (pattern) | Denial is a typed domain outcome, never an exception or side-channel error. | 7 independent proofs (Query, HTTP, Validation, Rack, Sidekiq, ContractResult, Epistemic) | Very high — strongest invariant across the entire proof base |
| **retryable / non-retryable** (pattern) | Whether a failure kind permits automatic retry. Idempotency key required (P16) for automatic retry. | LAB-OUTCOME-VARIANT-P1 (`ConfirmedFailedRetryable`), Sidekiq proofs (`non_retryable`), P16 | Medium — pattern stable; exact arm names are domain-local |
| **compensation / compensated** | An irreversible effect completed; a named compensation contract is required (P17). | Ch12 (`compensated`), LAB-OUTCOME-VARIANT-P1 (`ConfirmedFailedCompensatable`) | Medium — P17 is canon; variant arm name is domain-local |

### Observation types (cross-domain pattern, not failure taxonomy)

The evidence/observation types from Covenant P13 are distinct from failure taxonomy but constrain outcome vocabulary:

| Observation type | Definition | No-Upward-Coercion constraint |
|-----------------|-----------|-------------------------------|
| **real** | Directly witnessed from the world | Cannot be replaced by model without explicit conversion |
| **model** | From inference/model output | `ConfirmedSucceededModel` routes to `needs_human_review`, never to `accept` |
| **human** | From human judgment | Requires human review step in evidence chain |

These affect failure taxonomy because they split "succeeded" into three non-interchangeable outcomes (Real/Human/Model), enforced by distinct arm names.

---

## TAXONOMY-NONCANDIDATES — Domain-Specific Names That Should Stay Local

These terms are domain-local. Promoting them to cross-domain vocabulary would require false generalization or loss of precision.

| Term | Domain | Why it stays local |
|------|--------|-------------------|
| `ConfirmedSucceeded{Real\|Human\|Model}` | Epistemic reconciliation | Evidence-type split is specific to reconciliation + epistemic workflows. Generic "succeeded" loses the evidence distinction. |
| `ConfirmedFailed{Retryable\|Compensatable\|Terminal}` | Epistemic reconciliation | Recovery path is encoded in the arm name. Generic "failed" would require a second field (retryable: Boolean, compensation: String?) — collapsing evidence. |
| `StillUnknown{WithBudget\|NoBudget}` | Epistemic reconciliation | Budget-gated retry routing is reconciliation-domain-specific. Generic `unknown_external_state` loses the budget axis. |
| `ReconciliationDenied` / `ReconciliationError` | Epistemic reconciliation | "Denied by authority during reconciliation" vs "reconciliation machinery failed" — both local to the reconciliation workflow. |
| `rows` / `empty` | Query domain | Query-result success shape; no meaning outside data access. |
| `found` / `created` / `not_found` | HTTP ContractResult | HTTP-specific semantics (200/201/404). Not portable to job queues, validation, or reconciliation. |
| `upstream_unavailable` | HTTP/Sidekiq | Budget-exhausted retry state in async job context. Not meaningful in synchronous validation or query execution. |
| `non_retryable` | Sidekiq job | Job retry disposition; not a domain outcome — it's a job system classification. |
| `valid` / `invalid` | Validation domain | Data constraint results. "valid" has no meaning as a query or reconciliation outcome. |
| E-HTTP-* error codes | HTTP transport | Protocol-level codes. Not portable to storage or reconciliation. |

---

## TAXONOMY-BOUNDARY — What Remains KDR/Variant Convention

### KDR convention (`kind: String`) remains appropriate when:

1. **The vocabulary is open-ended or domain-specific** — new kinds may be added without a compiler change.
2. **Exhaustiveness is not required** — consumers route on known kinds and catch-all unknown kinds gracefully.
3. **Interoperability is the goal** — cross-language (Ruby↔Rust), serialization boundaries, API contracts.
4. **The domain is not yet proven** — not enough evidence to name an exhaustive set.

**Applicable now:** HTTP transport, ContractResult, QueryResult, ValidationResult, JobReceipt — all proven with KDR convention, no exhaustiveness enforcement needed.

### Variant/match is appropriate when:

1. **The vocabulary is finite and closed** — all arms are known at design time.
2. **Exhaustiveness matters** — unhandled arms should be a compile error, not a runtime miss.
3. **Recovery paths are arm-specific** — different arms require structurally different payloads.
4. **No-Upward-Coercion must be enforced** — distinct arm names prevent silent coercion between evidence types.

**Applicable now:** `ReconciliationOutcome` (proven by LAB-OUTCOME-VARIANT-P1), any future domain where a finite closed vocabulary of outcomes is defined.

### The boundary rule

A vocabulary crosses from KDR to variant when:
- **It gains exhaustiveness requirements** (OOF-KIND1 enforces this)
- **It splits an arm for evidence or recovery-path reasons** (model vs real, retryable vs compensatable)
- **Silent mismatches would produce incorrect routing** (ReconciliationDenied → retry would be wrong)

No existing domain other than epistemic reconciliation currently meets all three conditions.

---

## TAXONOMY-PROP — Whether a Formal PROP Should Open

### Recommendation: HOLD — gather one more domain proof before authoring

**Rationale:**

The evidence base is strong enough to **name** the cross-domain patterns (denial-as-data, timeout ≠ failure, unknown_external_state distinction). It is not yet strong enough to author a taxonomy PROP because:

1. **The 10 axes are not yet all proven across independent domains.** Axes 4 (timeout), 5 (unknown state), and 6 (partial) appear in the epistemic/reconciliation domain with high fidelity but have not yet been independently proven in the storage/query or HTTP domains at the same precision.

2. **A network failure-taxonomy proof is missing.** LAB-STDLIB-NET-P8/P9 prove HTTP transport and ContractResult kinds, but do not prove the timeout-vs-unknown-state distinction in the network domain specifically. Network timeout producing `unknown_external_state` (not `system_error`) is a Covenant P15 claim that needs a proof before it can be a taxonomy anchor.

3. **Partial success across domains is unproven.** `PartiallyConfirmed` exists in the epistemic variant, but no storage or HTTP proof shows `partial` as a distinct outcome kind. Without cross-domain confirmation, naming it as a shared convention is premature.

### If a PROP opens, its narrow scope is:

| Section | Content |
|---------|---------|
| Core invariants to adopt | denial-as-data (7 proofs); timeout ≠ failure (Covenant P15 + P2 proof); unknown_external_state ≠ system_error (P2 + P4 proofs) |
| Terms to name as conventions | `denied`/`denial`, `unknown_external_state`, `timed_out`, `system_error`, `query_error` — naming convention only, not a sum type |
| Terms to explicitly NOT adopt | A global `FailureKind` enum; `Outcome[T,E]` as a generic sealed type; any runtime behavior |
| Required precondition | Network domain proof confirming timeout → unknown_external_state (not system_error) in at least one non-reconciliation domain |
| Authority boundary | Naming convention PROP only — updates the lab docs taxonomy, does not touch compiler/parser/VM |

### What this PROP is NOT

A taxonomy naming-convention PROP is:
- **Not** a global error enum in the type system
- **Not** `Outcome[T,E]` (generic sealed outcome type — requires variant/match runtime and sealed type machinery not yet proven)
- **Not** a change to any domain's existing KDR vocabulary
- **Not** a runtime change
- **Not** a source of new OOF diagnostics

---

## TAXONOMY-CLOSED — No Implementation, No Outcome[T,E], No Runtime Behavior

### Explicit closures

| Surface | Status | Reason |
|---------|--------|--------|
| `Outcome[T,E]` generic sealed type | **CLOSED** | Requires generic type parameters (not yet in language), sealed variant machinery, and proven cross-domain vocabulary. None of these three preconditions are met simultaneously. |
| Global `FailureKind` enum | **CLOSED** | A 10-axis taxonomy cannot be faithfully represented in a flat enum without losing critical distinctions (denied vs query_error, timeout vs unknown state). Proven by the evidence inventory. |
| New OOF diagnostic codes | **CLOSED** | No new compiler diagnostics are authorized by this card. Existing OOF-KIND1..6 cover the proven surfaces. |
| Runtime failure taxonomy | **CLOSED** | This card produces no changes to VM opcodes, Value enum, or bytecode. All taxonomy work is at the naming/convention layer. |
| Parser/compiler changes | **CLOSED** | No keyword additions, no AST node changes, no typechecker changes. |
| Serialization policy | **CLOSED** | No stable ABI for failure kinds is defined here. `__arm`/`__variant` remain compiler-internal. |
| Production runtime claim | **CLOSED** | All evidence is lab-only. |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| **1. Is a shared failure taxonomy ready for proposal authoring?** | HOLD — not yet. The 10 semantic axes are clearly identified and 7 of them are proven across ≥2 domains. Axes 4 (timeout), 5 (unknown state), 6 (partial) still need a cross-domain proof beyond the reconciliation domain. |
| **2. Which terms are stable enough to name?** | `denied`, `unknown_external_state`, `timed_out`, `system_error`, `query_error` — these appear with stable, compatible definitions in ≥2 independent proof tracks. The `denial-as-data` pattern is the strongest invariant (7 proofs). |
| **3. Which terms must remain domain-local?** | All 11 ReconciliationOutcome arms; `rows`/`empty`; `found`/`created`/`not_found`; `upstream_unavailable`; `non_retryable`; `valid`/`invalid`; E-HTTP-* codes. Domain vocabulary should be defined by each domain, not by a shared enum. |
| **4. Is Outcome[T,E] required now?** | **NO.** KDR convention + variant/match per domain is sufficient for all proven use cases. Generic `Outcome[T,E]` requires: (a) generic type parameters in the language, (b) sealed variant machinery proven across domains, (c) cross-domain vocabulary consensus. None are proven simultaneously. |
| **5. Does Path B variant/match change the taxonomy decision?** | Yes, in one direction only: Path B proves that a finite closed vocabulary CAN be expressed as a variant with exhaustiveness enforcement, at compile time, with No-Upward-Coercion enforced by arm names. This is a precondition for any future domain adopting variant-based outcomes. It does not change the HOLD decision — it enables domain-specific adoption (as ReconciliationOutcome proves) without requiring a global taxonomy. |
| **6. What is the exact next route?** | **LAB-FAILURE-TAXONOMY-P2** (one targeted proof: network domain timeout → unknown_external_state distinction, not system_error) — then open the naming-convention PROP if P2 confirms. Can run in parallel with LAB-OUTCOME-VARIANT-P2. |

---

## Summary Evidence Table

| Domain | Proof count | Stable names | Local names |
|--------|------------|-------------|-------------|
| Epistemic reconciliation | 4 (P1–P4) | `unknown_external_state`, `denied`, `partial`, `timed_out` (via P15) | 11 variant arms |
| Storage / query | 3 (LAB-EXECUTE-QUERY-P1/P2, LAB-FILTER-EVAL-P1) | `denied`, `query_error`, `system_error` | `rows`, `empty` |
| HTTP / ContractResult | 2 (LAB-STDLIB-NET-P8/P9) | `denied` | `found`/`created`/`not_found`/`upstream_error`/`upstream_unavailable` |
| Rack / Sidekiq | 2 (LAB-RACK-P14, LAB-SIDEKIQ-P5) | `denied` (as `capability_denied`) | All domain-local |
| Validation | 1 (LAB-RESULT-ENVELOPE-P2) | `denied` (as `unauthorized`), `system_error`, `invalid` | `valid`/`invalid` |
| **Canon** | — | `succeeded`, `failed`, `partial`, `timed_out`, `unknown_external_state`, `compensated`, `cancelled` | — |

**Strongest cross-domain invariant:** `denial-as-data` — 7 independent proofs, zero contradictions.  
**Weakest cross-domain claim:** `partial` / partial success — named in Ch12, proven only in one domain (epistemic).  
**Not-yet-proven axis:** timeout → unknown_external_state in a domain other than epistemic.
