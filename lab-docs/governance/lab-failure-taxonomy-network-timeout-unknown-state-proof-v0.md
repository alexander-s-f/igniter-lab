# LAB-FAILURE-TAXONOMY-P2 — Governance Doc
# Network Timeout / Unknown External State Proof

**Track:** lab-failure-taxonomy-network-timeout-unknown-state-proof-v0  
**Route:** LAB PROOF / FAILURE TAXONOMY EVIDENCE / NO TAXONOMY PROP  
**Authority:** lab_only  
**Date:** 2026-06-10  
**Predecessor:** LAB-FAILURE-TAXONOMY-P1 (HOLD recommendation)  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_failure_taxonomy_p2.rb`  
**Result:** 51/51 PASS

---

## Purpose

LAB-FAILURE-TAXONOMY-P1 returned a **HOLD** recommendation for the failure taxonomy proposal, citing that three axes (timeout, unknown_external_state, partial success) had been proven only in the reconciliation domain. This card provides the missing second-domain evidence.

**Claim:** In the HTTP client / upstream-call domain, a timeout or lost acknowledgement **after** dispatch has started MUST route to `unknown_external_state`, not `system_error`, `upstream_error`, or `upstream_unavailable`. This is a direct consequence of Covenant P15 (Timeout Is Not Failure).

This proof:
- Does NOT open a formal taxonomy PROP
- Does NOT define a global FailureKind enum
- Does NOT implement Outcome[T,E]
- Does NOT import reconciliation arm names from the epistemic domain
- Claims no production authority; lab evidence only

---

## Domain

**HTTP client / upstream call domain** — the caller-side view of a network request to a remote upstream service. The signal carries what the transport layer observed; the outcome carries the epistemic classification.

This domain is distinct from the reconciliation domain (storage write/read) in:
- No persistent store is involved
- Acknowledgement is a network-layer event (response received), not a storage commit
- The retry gate (P16) requires a caller-supplied idempotency key, not an internal transaction ID

---

## Core Claim

```
dispatch_started == true  AND  ack_received == false
  => kind: "unknown_external_state"

dispatch_started == false
  => kind: "denied" | "upstream_unavailable"
  => NOT "unknown_external_state"
```

The key epistemic insight: `transport_kind == "timeout"` is **not sufficient** to determine the outcome kind. Two scenarios share the same `transport_kind` value but have different epistemic meanings:

| Scenario | dispatch_started | ack_received | Correct kind |
|----------|-----------------|--------------|-------------|
| Pre-dispatch timeout (connection pool stalled, DNS, TLS) | false | false | `upstream_unavailable` |
| Post-dispatch timeout (request in flight, no response) | true | false | `unknown_external_state` |

The `transport_kind` field is a transport-layer signal, not an epistemic outcome kind. The epistemic classification requires the `dispatch_started` / `ack_received` Bool pair.

---

## Fixture

**File:** `igniter-lab/igniter-view-engine/fixtures/failure_taxonomy/network_timeout_unknown_state.ig`  
**Module:** `Lab.FailureTaxonomy.NetworkTimeout`  
**Compile:** status=ok, 0 diagnostics

### Types

```igniter
type NetworkCallSignal {
  ack_received:     Bool,
  detail:           String,
  dispatch_started: Bool,
  host:             String,
  idempotency_key:  String,
  metadata:         Map[String, String],
  request_id:       String,
  status_code:      Integer,
  transport_kind:   String
}

type NetworkCallOutcome {
  ack_received:     Bool,
  detail:           String,
  dispatch_started: Bool,
  idempotency_key:  String,
  kind:             String,
  metadata:         Map[String, String],
  request_id:       String
}
```

Both types use the KDR (kind-discriminated record) convention. No `variant`/`match`. `kind: String` is the outcome discriminant. `dispatch_started` and `ack_received` are `Bool` — preserved in the outcome so consumers can inspect the epistemic basis without re-reading transport state.

### Contracts

| Contract | Scenario | kind |
|----------|----------|------|
| `CapabilityDenied` | Policy refused before dispatch | `"denied"` |
| `UpstreamServerError` | Dispatched + ack + 5xx | `"upstream_error"` |
| `UpstreamUnavailablePreDispatch` | Upstream unreachable, dispatch never started | `"upstream_unavailable"` |
| `TimeoutBeforeDispatch` | Timeout before dispatch started | `"upstream_unavailable"` |
| `DispatchedNoAck` | **POST-DISPATCH TIMEOUT (key case)** | `"unknown_external_state"` |
| `DispatchedLostResponseBody` | Dispatched + response body lost | `"unknown_external_state"` |
| `ConfirmedSuccess` | Dispatched + ack + 2xx | `"ok"` |
| `NetworkOutcomeClassifier` | Full if/else routing over Bool fields | (routes to all of the above) |
| `ReconciliationDataCheck` | Proves unknown_external_state carries reconciliation data | metadata passthrough |
| `MetadataPassthrough` | Proves Map[String,String] preserved end-to-end | map_get / or_else |

### Classifier routing

The `NetworkOutcomeClassifier` uses nested `if/else` (no `&&` operator) to encode the conjunction:

```igniter
compute kind =
  if is_dispatched {
    if has_ack {
      if is_ok { "ok" } else {
        if is_client_err { "not_found" } else { "upstream_error" }
      }
    } else {
      "unknown_external_state"
    }
  } else {
    if is_blocked { "denied" } else { "upstream_unavailable" }
  }
```

This structure makes Covenant P15 structurally enforced: the `"unknown_external_state"` branch is only reachable when `is_dispatched == true` AND `has_ack == false`.

---

## Proof Sections

### FTAX2-COMPILE (6 checks)
Fixture compiles clean. `NetworkCallSignal` and `NetworkCallOutcome` are referenced in the SIR via contract input/output type annotations. `NetworkOutcomeClassifier` and `DispatchedNoAck` contracts are present.

### FTAX2-SHAPE (7 checks)
Type fields verified via SIR node analysis:
- `dispatch_started: Bool` — via the `is_dispatched` compute node type in `NetworkOutcomeClassifier`
- `ack_received: Bool` — via the `has_ack` compute node type
- `transport_kind: String` — via the `is_blocked` binary_op node (left field_access, right String literal)
- `idempotency_key: String` — via `DispatchedNoAck` input type declaration + TypeChecker acceptance
- `NetworkCallOutcome.dispatch_started: Bool` — via `DispatchedNoAck` record literal `type_tag: 'Bool'`
- `NetworkCallOutcome.ack_received: Bool` — same
- `NetworkCallOutcome.kind: String` — via `DispatchedNoAck` record literal `type_tag: 'String'`

### FTAX2-CLASSIFY (8 checks)
Core routing verified for all 5 dispatch scenarios. **Key case**: `dispatch_started=true, ack_received=false, transport_kind='timeout' → kind='unknown_external_state'`. `dispatch_started=true` and `ack_received=false` are preserved in the output.

### FTAX2-NOT-UNKNOWN (6 checks)
Negative controls: capability denial, pre-dispatch timeout, confirmed success, upstream error do NOT produce `unknown_external_state`. Specifically: `dispatch_started=false + transport_kind='timeout' → 'upstream_unavailable'` (not unknown).

### FTAX2-METADATA (7 checks)
`request_id`, `idempotency_key`, and `metadata` (Map[String,String]) are preserved through `DispatchedNoAck` and `NetworkOutcomeClassifier`. The `idempotency_key` is available for post-reconciliation retry gating (Covenant P16).

### FTAX2-RECONCILE (5 checks)
An `unknown_external_state` outcome carries sufficient data for downstream reconciliation: `request_id` for correlation, `idempotency_key` for retry gating, `metadata` for context (resource path, sent_at, etc.). A `denied` outcome (no request in flight) has no resource metadata — the distinction is maintained.

### FTAX2-CROSSDOMAIN (6 checks)
Cross-domain comparison with the epistemic domain (storage / `lost_confirmation_kdr.ig`):
- Both domains independently use `kind: "unknown_external_state"` for the same epistemic situation
- Both use `dispatch_started=true/false` (or equivalent) as the discriminant
- Neither imports the other's arm names
- Both use KDR (no variant/match)

This confirms the same semantic distinction arises independently in at least two non-reconciliation domains.

### FTAX2-CLOSED (7 checks)
All SIR contracts have `effects: []` (pure contracts — no I/O). No retry scheduler. No `Outcome[T,E]`. No variant/match. `OP_MATCH` and `Value::Variant` absent from VM. No taxonomy PROP authority claimed.

---

## Cross-Domain Evidence

This proof + the epistemic domain (storage) proof from `LAB-EPISTEMIC-OUTCOME-P2/P4` provide the second independent domain for axes 4 (timeout) and 5 (unknown_external_state) requested by LAB-FAILURE-TAXONOMY-P1.

**From LAB-FAILURE-TAXONOMY-P1:**
> "Axes 4 (timeout), 5 (unknown external state), and 6 (partial success) are proven only in the reconciliation domain. One cross-domain proof is needed before a naming-convention PROP can open with confidence."

This proof addresses axes 4 and 5. Axis 6 (partial success) remains proven only in the reconciliation domain.

| Axis | P1 Status | P2 Status |
|------|-----------|-----------|
| timeout | reconciliation domain only | ✓ also: HTTP client domain (this proof) |
| unknown_external_state | reconciliation domain only | ✓ also: HTTP client domain (this proof) |
| partial_success | reconciliation domain only | still reconciliation domain only |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Does post-dispatch timeout route to `unknown_external_state`? | **YES** — proven via `DispatchedNoAck` and `NetworkOutcomeClassifier` |
| Does pre-dispatch timeout route to `unknown_external_state`? | **NO** — routes to `upstream_unavailable` (`dispatch_started=false`) |
| Can `transport_kind: "timeout"` alone determine the outcome kind? | **NO** — `dispatch_started` and `ack_received` are required to distinguish the two timeout cases |
| Does `unknown_external_state` carry reconciliation data? | **YES** — `request_id`, `idempotency_key`, metadata preserved |
| Is `unknown_external_state` the right term in the network domain (not `system_error`)? | **YES** — `system_error` implies a known infrastructure fault; unknown state is epistemically distinct |
| Does this open a formal taxonomy PROP? | **NO** — lab evidence only; HOLD recommendation extended to LAB-FAILURE-TAXONOMY-P3 |
| What remains before a PROP can open? | Axis 6 (partial_success) cross-domain evidence; or explicitly scope PROP to only axes 1–5 + 7–10 |

---

## Stable Cross-Domain Terms (updated from P1)

| Term | Domains proved | Notes |
|------|---------------|-------|
| `denied` | storage, query, network, HTTP client, Rack, Sidekiq (7 proofs) | Strongest invariant — zero contradictions |
| `unknown_external_state` | reconciliation (P2/P4), HTTP client **(this proof)** | Now cross-domain ✓ |
| `timed_out` | Ch12, Covenant P15, HTTP client **(this proof)** | `dispatch_started=true + ack_received=false` case |
| `system_error` | query (P2), validation (P2) | Not the same as `unknown_external_state` |
| `query_error` / malformed | query (P1/P2), filter, order/limit | Domain-local but stable pattern |

---

## Do Not Collapse (unchanged from P1)

| Pair | Why distinct |
|------|-------------|
| `timed_out` vs `unknown_external_state` | Clock expiry vs lost-ack — P15 names them separately |
| `unknown_external_state` vs `system_error` | Must reconcile vs retry later — different recovery paths |
| pre-dispatch timeout vs post-dispatch timeout | Same `transport_kind`; different epistemic meaning; different kind |

---

## Closed Surfaces (unchanged)

| Surface | Status |
|---------|--------|
| Formal taxonomy PROP | **CLOSED** — HOLD extended; axis 6 still single-domain |
| Global `FailureKind` enum | **CLOSED** |
| `Outcome[T,E]` generic sealed type | **CLOSED** — 3 unsatisfied preconditions unchanged |
| New OOF diagnostic codes | **CLOSED** |
| Runtime/compiler/parser changes | **CLOSED** |
| Real network I/O | **CLOSED** — all contracts pure; effects: [] |

---

## Next Route

**LAB-FAILURE-TAXONOMY-P3** — Proposal readiness decision.

Now that `unknown_external_state` and the post-dispatch timeout routing are proven cross-domain, the remaining question is whether to:
- (A) Open a narrowly-scoped naming-convention PROP for axes 1–5 + 7–10 (exclude partial_success for now)
- (B) Add one more domain proof for axis 6 (partial_success) then open a full PROP
- (C) Remain on HOLD; continue accumulating evidence

P3 should make that route decision with explicit answers.
