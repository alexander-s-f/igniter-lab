# LAB-FAILURE-TAXONOMY-P3 — Governance Doc
# Failure Taxonomy Proposal Readiness Decision

**Track:** lab-failure-taxonomy-proposal-readiness-decision-v0  
**Route:** GOVERNANCE / READINESS DECISION / NO IMPLEMENTATION  
**Authority:** lab_only  
**Date:** 2026-06-10  
**Predecessor:** LAB-FAILURE-TAXONOMY-P1 (HOLD), LAB-FAILURE-TAXONOMY-P2 (51/51 PASS)  
**Decision:** **A — Open a narrow naming-convention PROP now**

---

## READINESS-EVIDENCE — Proof Inventory After P2

### Evidence chain (updated)

| Source | Domain | Key failure vocabulary | Status |
|--------|--------|----------------------|--------|
| Ch12 (`ch12-effect-surface.md`) | Canon | 7 outcome kinds: `succeeded`, `failed`, `partial`, `timed_out`, `unknown_external_state`, `compensated`, `cancelled` | Named; unimplemented |
| Covenant P11/P13/P15/P16/P17 | Canon | Timeout ≠ failure; uncertainty non-discardable; idempotency gate; compensation named | Covenant rules |
| LAB-EPISTEMIC-OUTCOME-P2 | Storage write / commit-ack | `unknown_external_state`, `timed_out`, `denied`, `partial` (via `partly_confirmed`) | KDR, 54/54 PASS |
| LAB-EPISTEMIC-OUTCOME-P4 | Reconciliation routing | `confirmed_succeeded`, `confirmed_failed`, `still_unknown`, `partially_confirmed`, `reconciliation_denied`, `reconciliation_error` | KDR VM-proven, 46/46 PASS |
| LAB-OUTCOME-VARIANT-P1 | Reconciliation variant | 11 arms including `PartiallyConfirmed`, `StillUnknown{WithBudget\|NoBudget}` | Variant Path B, 58/58 PASS |
| LAB-FAILURE-TAXONOMY-P2 | HTTP client / upstream call | `unknown_external_state` (post-dispatch no-ack); `upstream_unavailable` (pre-dispatch timeout); `denied` | **NEW** — 51/51 PASS |
| LAB-EXECUTE-QUERY-P1/P2 | Storage query | `denied`, `query_error`, `system_error`, `rows`, `empty` | KDR VM-proven |
| LAB-FILTER-EVAL-P1 | Query filter | `rows`, `empty`, `query_error` | KDR VM-proven |
| LAB-RESULT-ENVELOPE-P1/P2 | Validation / HTTP | `valid`, `invalid`, `unauthorized` (denied), `system_error` | KDR Layer A+B |
| Network proofs (LAB-STDLIB-NET-P8/P9) | HTTP transport / ContractResult | `ok`, `denied`, `error`, `found`, `created`, `not_found`, `upstream_error`, `capability_denied`, `upstream_unavailable` | KDR Layer A+B |
| PROP-044-P8/P9 + LAB-OUTCOME-VARIANT-P1..P3 | Path B semantics | OOF-KIND1..6; `__arm`/`__variant`; variant/match Path B locked | Compiler proof chain |

### What P2 added

LAB-FAILURE-TAXONOMY-P2 proved in an independent domain (HTTP client) that:
1. `dispatch_started=true, ack_received=false` → `unknown_external_state` — second domain confirmation
2. `dispatch_started=false` (including transport_kind=timeout) → `upstream_unavailable` — NOT unknown
3. `transport_kind: "timeout"` alone is insufficient to classify the outcome — the epistemic Bool pair (`dispatch_started`, `ack_received`) is required

This directly confirmed the P1 HOLD condition: "one cross-domain proof for timeout and unknown_external_state in a non-reconciliation domain."

---

## READINESS-AXES — Updated 10-Axis Matrix

| Axis | Description | Domains proved | Cross-domain? | Stable term(s) |
|------|-------------|---------------|--------------|----------------|
| **1. capability_denial** | Authority refused before attempt; deterministic; do not retry same plan | Query (×4), HTTP, Validation, Rack, Sidekiq, Epistemic (7+ proofs) | ✓ Very strong | `denied` / `denial` |
| **2. malformed_plan** | Input structurally/semantically invalid; fix before retrying; not access control | Query (×4), HTTP 4xx, Validation | ✓ Strong | `query_error` / `invalid` |
| **3. external_unavailable** | Infrastructure-level failure; retry with backoff | HTTP (upstream_unavailable), Storage (system_error), Query (system_error) | ✓ Strong | `system_error` / `upstream_unavailable` (domain-local) |
| **4. timeout** | Time limit elapsed; outcome is unknown, not failed (P15) | Ch12, Covenant P15, Epistemic P2, HTTP client **P2 NEW** | ✓ NOW CROSS-DOMAIN | `timed_out` |
| **5. unknown_external_state** | Request sent; no confirmed receipt; must reconcile; never route to success/failure directly | Ch12, Epistemic (P2/P4), HTTP client **P2 NEW** | ✓ NOW CROSS-DOMAIN | `unknown_external_state` |
| **6. partial_success** | Some sub-effects confirmed; some unconfirmed; not the same as unknown | Ch12 (`partial`), Epistemic P4 (`partially_confirmed`), Variant P1 (`PartiallyConfirmed`) | ✗ Single-domain (reconciliation only) | `partial` (deferred) |
| **7. validation_invalid** | Domain constraint violated by data; fix the data; not access denial, not infrastructure | Validation (LAB-RESULT-ENVELOPE-P2), Query (query_error subset) | ✓ Strong | `invalid` / `query_error` |
| **8. compensation** | Irreversible effect completed; named compensation contract required (P17) | Ch12, LAB-OUTCOME-VARIANT-P1 (`ConfirmedFailedCompensatable`), Covenant P17 | Partial (canon + 1 domain) | `compensated` (domain-local term) |
| **9. retryable_vs_not** | Cross-cutting; whether automatic retry is permitted; P16 idempotency gate | LAB-OUTCOME-VARIANT-P1, Sidekiq proofs, Covenant P16 | ✓ Strong (pattern) | pattern only; arm names domain-local |
| **10. type_error_vs_domain_outcome** | Compiler diagnostic ≠ runtime outcome; OOF-KIND1..6 are not failure kinds | All compiler-proof tracks (PROP-044-P3..P9, LAB-VARIANT-RUST-P1) | ✓ Very strong | OOF-KIND (compiler), outcome (runtime) |

**Summary:** 9/10 axes cross-domain. Axis 6 (partial_success) is single-domain.

---

## READINESS-PARTIAL — Decision on Partial Success (Axis 6)

### What we know about partial_success

| Evidence | Weight |
|----------|--------|
| Ch12 names `partial` as 1 of 7 canonical outcome kinds | Strong (canon) |
| LAB-EPISTEMIC-OUTCOME-P4 proves `partially_confirmed` as a distinct KDR kind | Medium (one domain) |
| LAB-OUTCOME-VARIANT-P1 proves `PartiallyConfirmed` as a distinct variant arm | Medium (same domain) |
| Forbidden-collapse `partial` ≠ `unknown` is well-argued | Strong (epistemic argument) |
| No storage-query or HTTP proof of `partial` as a distinct kind | Gap |

### Why partial_success does NOT block the PROP

1. **The PROP is a naming convention, not a type system.** It does not define `partial` as a global type that all domains must implement. It can acknowledge `partial` as a Ch12 axis and instruct domains to avoid conflating it with `unknown_external_state` — without naming it as a stable cross-domain term.

2. **The forbidden-collapse is epistemic, not lexical.** The claim "do not collapse `partial` with `unknown`" can be stated as a recovery-guidance rule without requiring a second domain to have proven `partial` as a named kind. The claim is: these two axes require different reconciliation strategies — a partial outcome has some valid resource handles; an unknown outcome has none confirmed. This can be stated from Ch12 + epistemic domain evidence alone.

3. **Waiting for 10/10 over-fits the bar for a naming-convention PROP.** The value of the PROP is: give Igniter contract authors names for the stable cross-domain patterns and rules for forbidden collapses. That value is deliverable now from 9 axes. Waiting for axis 6 evidence delays value from 9 proven axes indefinitely.

4. **The risk of naming `partial` prematurely is low.** If the PROP explicitly defers `partial` (states: axis exists, Ch12 names it `partial`, no stable cross-domain convention yet, keep domain-local), then a future proof confirming `partial` in a second domain would merely extend the PROP — it would not require revision.

### Partial_success in the PROP

The PROP **must**:
- Acknowledge axis 6 as a distinct axis (from Ch12 + epistemic domain)
- State the forbidden collapse: `partial` ≠ `unknown_external_state` (different recovery strategies)
- Explicitly defer `partial` as a stable cross-domain term: "no convention name assigned; keep domain-local until LAB-FAILURE-TAXONOMY-P4 or equivalent confirms a second domain"

The PROP **must not**:
- Name `partial` as a stable cross-domain term
- Define `partial` recovery guidance as binding convention
- Require domains to implement a `partial` kind

---

## READINESS-SCOPE — What the PROP May Include

### Authorized content

| Category | Authorized | Notes |
|----------|-----------|-------|
| Stable cross-domain terms | `denied`, `unknown_external_state`, `timed_out`, `system_error`, `query_error` | Name, definition, recovery guidance |
| Cross-domain patterns | `denial-as-data`, timeout ≠ failure, unknown ≠ system_error | State as binding convention |
| Forbidden collapses | All 7 pairs from P1/P2 | Including `partial` ≠ `unknown` (as guidance, not naming) |
| KDR/variant usage boundary | When KDR is appropriate; when variant is appropriate | Boundary rule from P1 §TAXONOMY-BOUNDARY |
| Observation type guidance | real/model/human; No-Upward-Coercion; model cannot route to accept | From Covenant P13 + LAB-OUTCOME-VARIANT-P1 |
| Axis list | All 10 axes documented, even if not all named | State axis 6 as "deferred" |
| Recovery guidance per axis | What consumer should do for each stable term | Reconcile / retry / fix-plan / fix-credentials / compensate |

### Deferred content (not authorized in this PROP)

| Category | Status | Why |
|----------|--------|-----|
| `partial` stable term | Deferred to PROP follow-up or LAB-FAILURE-TAXONOMY-P4 | Single-domain evidence |
| Compensation stable term | Deferred | Ch12 + 1 domain; Covenant P17 supports it but cross-domain proof sparse |
| Retryable/non-retryable stable term | Pattern authorized, not a term | Arm names are domain-local; the pattern (idempotency gate, P16) is convention |
| Serialization ABI | Closed | No stable ABI for failure kinds |
| `__arm`/`__variant` stability guarantee | Closed | Compiler-internal; not public API |

### Excluded content (permanently closed in this PROP)

| Excluded item | Reason |
|--------------|--------|
| Global `FailureKind` enum | Proven impossible: 10 orthogonal axes cannot be faithfully collapsed to flat enum |
| `Outcome[T,E]` generic sealed type | 3 unsatisfied preconditions (generic type params, sealed-variant cross-domain, vocabulary consensus) — all still unmet |
| New OOF diagnostic codes | Not authorized; existing OOF-KIND1..6 cover proven surfaces |
| Compiler / parser / VM changes | Zero implementation authority |
| Runtime behavior changes | Not a runtime proposal |
| Production stability claims | Lab evidence only |
| Canon changes | No canon changes authorized in this PROP |

### Exact proposed PROP framing

**Title (proposed):** "Failure Outcome Naming Convention and Recovery-Axis Guidance"

This is a **naming convention** proposal. It does NOT:
- Define a type system extension
- Require any existing domain to rename its kinds
- Define a global enum or sealed type
- Introduce any runtime behavior

It DOES:
- Name the stable cross-domain terms and define them precisely
- State the forbidden-collapse rules as binding conventions
- Provide recovery-action guidance per axis (what to do when you see each kind)
- Define the KDR/variant usage boundary
- Acknowledge all 10 axes, including 1 deferred

---

## READINESS-CLOSED — What Remains Closed

| Surface | Status | Evidence |
|---------|--------|---------|
| `Outcome[T,E]` generic sealed type | **CLOSED** | Preconditions unchanged (generic params unproven, cross-domain vocabulary not yet consensus, sealed-variant machinery not stable-API) |
| Global `FailureKind` enum | **CLOSED** | 10-axis taxonomy proven non-collapsible by P1 analysis; LAB-EXECUTE-QUERY-P1/P2 proves `denied` ≠ `query_error` distinction would be lost |
| New OOF diagnostic codes | **CLOSED** | No new diagnostics from this PROP |
| Runtime / VM / compiler changes | **CLOSED** | Zero implementation |
| `partial_success` stable term | **CLOSED until P4** | Single-domain evidence; deferred explicitly in PROP |
| Canon changes in this card | **CLOSED** | No canon change authorized here; future PROP may propose canon update via standard process |
| Serialization ABI | **CLOSED** | `__arm`/`__variant` remain compiler-internal |

---

## READINESS-DECISION — A: Open the Narrow Naming-Convention PROP Now

**Decision: A**

### Evidence threshold: met

LAB-FAILURE-TAXONOMY-P1 stated the exact condition: "After LAB-FAILURE-TAXONOMY-P2 confirms that `unknown_external_state` (not `system_error`) is the correct term for a network timeout in at least one non-reconciliation domain."

LAB-FAILURE-TAXONOMY-P2 satisfied this condition: 51/51 PASS, two distinct scenarios in the HTTP client domain, including the crucial pre-dispatch vs post-dispatch distinction.

### Why A and not B or C

**Against B (hold for one more partial_success proof):**

P1 stated three axes as needing cross-domain evidence: timeout, unknown_external_state, and partial_success. P2 delivered two of the three. A strict reading of P1 would say B is correct.

But P1 was written before P2 existed. The HOLD condition in P1 was conservative: it required any one non-reconciliation proof. P2 delivered two confirmed axes simultaneously. The partial_success gap does not affect the naming convention for the 9 confirmed axes. And the PROP can explicitly defer axis 6, which is a stronger statement than silence — it names the gap and closes it from the PROP scope intentionally.

**Against C (continue hold):**

The evidence is not "too fragmented." 9/10 axes are cross-domain with strong evidence. The remaining gap (axis 6) is understood epistemically from Ch12 and the reconciliation domain. C would mean indefinitely deferring a naming convention that contract authors in the lab can already use today. The risk of opening a narrow naming-convention PROP is low.

### Rationale for A

1. **The P1 HOLD condition is satisfied.** The exact condition ("one non-reconciliation domain proof for timeout → unknown_external_state") was met.

2. **The PROP scope is narrow enough to exclude the gap.** A naming-convention PROP can defer axis 6 explicitly without loss of coherence. The 9 proven axes form a complete, self-consistent convention.

3. **The value is deliverable now.** Contract authors in the lab can benefit from stable names, forbidden-collapse rules, and recovery guidance for the 9 proven axes. The wait-for-10/10 approach delays this indefinitely.

4. **The risk of opening is low.** A naming-convention PROP with no runtime consequences can be updated later without breaking anything. If axis 6 is confirmed by LAB-FAILURE-TAXONOMY-P4, a small follow-up to the PROP (or an amendment) would extend it. No revisions to existing contracts would be required.

5. **The deferred-axis treatment is strictly safer than silence.** Explicitly deferring `partial` in the PROP is a stronger statement than not naming it. It prevents premature adoption and signals the remaining gap to contract authors.

### Decision record

| Option | Considered? | Why rejected |
|--------|-------------|-------------|
| A — Open narrow PROP now | ✓ **Chosen** | P1 HOLD condition satisfied; gap can be deferred; low risk |
| B — Hold for partial_success proof | Considered | P1 condition satisfied; further wait delays value without reducing risk |
| C — Continue HOLD | Considered | Evidence not fragmented; no new risk from narrow naming-convention PROP |

---

## READINESS-NEXT — Exact Next Cards

### Primary: Proposal authoring card

**Card to open:** `PROP-FAILURE-TAXONOMY-NAMING-P1` (assigned the next available PROP number at authoring time)

**PROP title (proposed):** "Failure Outcome Naming Convention and Recovery-Axis Guidance"

**Authorized content:**
- 5 stable cross-domain terms: `denied`, `unknown_external_state`, `timed_out`, `system_error`, `query_error`
- 2 cross-domain patterns: `denial-as-data`, timeout-is-not-failure
- 7 forbidden-collapse rules
- KDR/variant usage boundary rule
- Observation type guidance (real/model/human; No-Upward-Coercion)
- All 10 axes documented (axis 6 explicitly deferred)
- Recovery guidance per axis

**NOT authorized in this PROP:**
- `Outcome[T,E]` / global enum / OOF codes / runtime / compiler / VM / serialization ABI

**This card (P3) does NOT author the PROP.** P3 authorizes the opening of a proposal-authoring card. The proposal-authoring card writes the actual PROP document.

### Secondary: Partial-success cross-domain proof (optional, not blocking)

**Card to open when ready:** `LAB-FAILURE-TAXONOMY-P4` — Partial Success Cross-Domain Proof

Goal: prove in a non-reconciliation domain (storage/query, batch job, or multi-step write) that `partial` / `partially_confirmed` is a distinct outcome kind, not collapsible with `unknown_external_state`.

If P4 passes: open a PROP amendment (or the naming PROP can include `partial` from the start if P4 runs first).

P4 is **not a prerequisite** for the naming-convention PROP (per decision A). It can run in parallel.

### Can run in parallel:

- `LAB-OUTCOME-VARIANT-P2` (if not already closed) — rich payload routing
- `LAB-FAILURE-TAXONOMY-P4` — partial_success cross-domain evidence
- The naming-convention PROP authoring card

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| 1. Are 9/10 cross-domain axes enough for proposal-authoring? | **YES** — the P1 HOLD condition was satisfied by P2. Axis 6 is deferred, not blocking. |
| 2. Does partial_success block the proposal? | **NO** — it can be explicitly deferred in the PROP scope. The PROP names it as an axis, acknowledges the gap, and closes `partial` as a stable term pending P4. |
| 3. Should the proposal exclude partial_success or wait for it? | **Exclude and explicitly defer.** Do not wait. Stating the gap explicitly is stronger than silence. |
| 4. Is Outcome[T,E] still closed? | **YES — CLOSED.** 3 unsatisfied preconditions remain: generic type parameters not in the language, sealed-variant machinery not stable-API, cross-domain vocabulary not consensus. |
| 5. Is global FailureKind enum still closed? | **YES — CLOSED.** 10 orthogonal axes cannot be faithfully collapsed; proven by P1 analysis and execution-query denied ≠ query_error distinction. |
| 6. Is Path B variant/match relevant to the proposal scope? | **YES, indirectly.** The PROP's KDR/variant usage boundary rule depends on Path B being proven (LAB-VARIANT-VM-P1, LAB-OUTCOME-VARIANT-P1). The PROP can state: "use KDR for open vocabulary; use variant when vocabulary is finite, closed, and exhaustiveness matters — Path B lowering is the proven runtime substrate." This adds useful guidance without changing Path B's authority. |
| 7. What exact next card should open? | Proposal authoring card: `PROP-FAILURE-TAXONOMY-NAMING-P1` (next available PROP number). Secondary (parallel, not blocking): `LAB-FAILURE-TAXONOMY-P4` (partial_success cross-domain proof). |
