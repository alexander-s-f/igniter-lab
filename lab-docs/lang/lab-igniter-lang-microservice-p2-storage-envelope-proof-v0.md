# Igniter Microservice P2 — Storage Envelope Proof v0

**Card:** LAB-IGNITER-LANG-MICROSERVICE-P2  
**Track:** LAB SERVICE ENVELOPE / MOCK EXECUTION INTEGRATION  
**Status:** OPEN — proof doc authored  
**Authority:** proof-only service envelope integration; no server implementation  
**Date:** 2026-06-13  
**Upstream:** LAB-IGNITER-LANG-MICROSERVICE-P1 (CLOSED 72/72), LAB-IGNITER-LANG-IO-RUNTIME-P2 (CLOSED 69/69)

---

## Scope

This document validates the `ServiceRequest` / `ServiceResponse` envelope from
P1 against the mocked `MockStorageCapabilityExecutor` path from IO Runtime P2.

**Three outcome scenarios are validated:**

1. **Succeeded** (`rows`): storage capability granted, G6 returns rows → ServiceResponse kind `"ok"`.
2. **Denied** (`denied`): G1–G3 gate fails → ServiceResponse kind `"denied"`, receipt carries gate.
3. **Unknown external state** (`unknown_external_state`): executor signals ambiguous outcome →
   ServiceResponse kind `"effect_failure"`, P15 enforced.

**Authority boundary:** This is a proof-local simulation. No real IO, no HTTP server, no Rack
middleware, no real DB/SQL/ORM, no production runtime, no public API claim.

---

## Upstream Dependency Chain

| Card | Result | What it contributes |
|---|---|---|
| LAB-IGNITER-LANG-IO-RUNTIME-P1 | CLOSED 85/85 | Route confirmed; CapabilityExecutor gap identified |
| LAB-IGNITER-LANG-IO-RUNTIME-P2 | CLOSED 69/69 | MockStorageCapabilityExecutor; G1–G6 gate sequence; QueryExecutionReceipt |
| LANG-IO-CAPABILITY-EXECUTOR-P1 | CLOSED 80/80 | Executor interface; CapabilityPassport; EffectResult; 14-field receipt shape |
| LAB-IGNITER-LANG-MICROSERVICE-P1 | CLOSED 72/72 | ServiceRequest; ServiceResponse; 8-gate allowlist; ResponseObservation |

---

## Envelope Integration Model

The `EnvelopeRunner` is a proof-local simulation that wraps the mocked executor
in the P1 envelope shapes. It is not a real microservice. It proves the shapes
are sufficient.

```
ServiceRequest
  ↓ 8-gate allowlist (EnvelopeRunner.validate_request)
  ↓ executor registry lookup → MockStorageCapabilityExecutor
  ↓ execute(effect_name, passport, inputs)
  ↓ [QueryResult, QueryExecutionReceipt]
  ↓ map to EffectReceipt (P1 shape)
  ↓ map QueryResult to ServiceResponse.kind
  ↓ build ResponseObservation (evidence_digest)
ServiceResponse
```

### ServiceRequest Shape (from P1)

```
ServiceRequest {
  correlation_id:      "req-001"
  contract_id:         "ExecuteQuery"
  effect_names:        ["read_file"]
  input:               { plan: QueryPlan }
  authority_ref:       "auth-token-read-v0"
  capability_passports: {
    "storage" => CapabilityPassport {
      passport_id:   "passport-storage-001"
      family:        "storage"
      capability_id: "storage-read-users-v0"
      authority_ref: "auth-token-read-v0"
      issued_at:     "2026-06-13T00:00:00Z"
      expires_at:    nil
      scope_ids:     ["read_file"]
      profile_ids:   []
      revoked:       false
    }
  }
  idempotency_key:     "idem-001" | nil
  ingress_substrate:   "http"
  ingress_timestamp:   "2026-06-13T00:00:00Z"
  artifact_digest:     "sha256:mock-artifact-001"
  profile_ids:         []
}
```

### ServiceResponse Kind Mapping

| Executor outcome | ServiceResponse.kind | EffectReceipt.outcome |
|---|---|---|
| `rows` / `empty` | `"ok"` | `"succeeded"` |
| `denied` (G1/G2/G3) | `"denied"` | `"denied"` |
| `query_error` (G5) | `"effect_failure"` | `"failed"` |
| `unknown_external_state` | `"effect_failure"` | `"unknown_external_state"` |
| `system_error` | `"effect_failure"` | `"failed"` |
| EvaluateRefusal (pre-executor) | `"runtime_refusal"` | (no receipt) |

**P15 constraint:** `unknown_external_state` must not be treated as `failed`. The
response carries `kind: "effect_failure"` but the receipt records `outcome: "unknown_external_state"`.
The consumer must branch explicitly on receipt outcome, not on response kind alone.

---

## Scenario 1 — Succeeded (rows)

**Setup:**
- `capability_passports["storage"]`: `allowed_sources: ["users"]`, `read_allowed: true`, `row_limit: 3`
- `input.plan`: `{ kind: "select", source: { table: "users" }, projection: { include_all: false }, limit: 10 }`
- G1–G3 pass; G4 clamp effective_limit=3; G6 returns 3 mocked rows

**ServiceRequest → EnvelopeRunner → ServiceResponse:**

```
correlation_id:    "req-001"
kind:              "ok"
output:            { rows: [...], count: 3, result_kind: "rows" }
receipts: [
  EffectReceipt {
    receipt_id:          "rcpt-sha256:..."
    effect_name:         "read_file"
    capability_id:       "storage-read-users-v0"
    family:              "storage"
    authority_ref:       "auth-token-read-v0"
    idempotency_key:     "idem-001"
    idempotency_key_used: true
    inputs_hash:         "sha256:..."   (canonical hash of plan)
    outcome:             "succeeded"
    substrate:           "storage"
    emitted_at:          "2026-06-13T00:00:00Z"
    evidence_refs:       []
  }
]
effect_outcomes:   { "read_file" => "succeeded" }
response_observation: {
  observation_id:  "obs-sha256:..."
  kind:            "response_observation"
  correlation_id:  "req-001"
  outcome_kind:    "ok"
  receipt_refs:    ["rcpt-sha256:..."]
  evidence_digest: "sha256:..."   (sha256 of receipts + output)
}
```

---

## Scenario 2 — Denied (G1 failure)

**Setup:**
- `capability_passports["storage"]`: `allowed_sources: []` (deny all sources)
- `input.plan`: `{ source: { table: "users" }, ... }`
- G1 fires → `QueryResult{kind:"denied"}` → `cap_granted: false`

**ServiceResponse:**

```
correlation_id:    "req-002"
kind:              "denied"
output:            nil
receipts: [
  EffectReceipt {
    effect_name:  "read_file"
    outcome:      "denied"
    inputs_hash:  "sha256:..."
    ...           (all 8 required replay fields present)
  }
]
effect_outcomes:   { "read_file" => "denied" }
```

**Rule:** denial-as-data. The consumer receives a typed response with receipts, not an exception.
The receipt carries `denial_gate: "G1"` and `deny_reason: "source-not-allowed"`.

---

## Scenario 3 — Unknown External State

**Setup:**
- `capability_passports["storage"]`: normal (G1–G3 pass)
- Executor simulates timeout → returns `EffectResult{kind:"unknown_external_state"}`
- No second attempt is made; the unknown state is recorded

**ServiceResponse:**

```
correlation_id:    "req-003"
kind:              "effect_failure"
output:            nil
receipts: [
  EffectReceipt {
    effect_name:  "read_file"
    outcome:      "unknown_external_state"
    inputs_hash:  "sha256:..."
    ...
  }
]
effect_outcomes:   { "read_file" => "unknown_external_state" }
```

**P15 enforcement:** the response mapper sees `outcome: "unknown_external_state"` and must
not convert it to `"failed"`. It maps to `kind: "effect_failure"` but the consumer is
required to branch on `receipts[0].outcome == "unknown_external_state"` before deciding
whether to reconcile or retry.

**Reconciliation rule:** the caller must reconcile at the substrate level before re-submitting
with the same `idempotency_key`. A re-submission without reconciliation may produce a duplicate
external effect (if the first attempt succeeded despite the timeout).

---

## Replay Evidence Sufficiency

All three scenarios produce receipts with the minimum 8 replay fields from P1 Q5:

| Field | Scenario 1 | Scenario 2 | Scenario 3 |
|---|---|---|---|
| `effect_name` | `"read_file"` | `"read_file"` | `"read_file"` |
| `capability_id` | `"storage-read-users-v0"` | `"storage-read-users-v0"` | `"storage-read-users-v0"` |
| `inputs_hash` | `sha256(plan)` | `sha256(plan)` | `sha256(plan)` |
| `outcome` | `"succeeded"` | `"denied"` | `"unknown_external_state"` |
| `substrate` | `"storage"` | `"storage"` | `"storage"` |
| `emitted_at` | `"2026-06-13T00:00:00Z"` | `"2026-06-13T00:00:00Z"` | `"2026-06-13T00:00:00Z"` |
| `idempotency_key` | `"idem-001"` | `nil` | `"idem-003"` |
| `authority_ref` | `"auth-token-read-v0"` | `"auth-token-read-v0"` | `"auth-token-read-v0"` |

**Invariant:** `inputs_hash` is computed from the canonical plan before executor dispatch. The same
plan + same `idempotency_key` + same `capability_id` must produce the same `inputs_hash` regardless
of when the request is submitted. This is the deterministic replay anchor.

The `QueryExecutionReceipt` 15-field shape (from IO Runtime P2) is used as the inner receipt and
carries additional storage-specific fields. It is embedded in the `EffectReceipt` as `evidence_refs`.

---

## Rack/HTTP Substrate Boundary

The `EnvelopeRunner` accepts a `ServiceRequest` and returns a `ServiceResponse`. It does not:

- Parse HTTP verb/path/headers
- Require a Rack `env` hash
- Depend on a running HTTP server
- Call `Net::HTTP` or any real network primitive

The `ingress_substrate: "http"` field in `ServiceRequest` records that the host
would deliver this request over HTTP/Rack. But the `EnvelopeRunner` does not use
this field for dispatch. A queue-substrate request with `ingress_substrate: "queue"`
would follow the same evaluate → dispatch → receipt path.

**Rule confirmed from P1:** Rack/HTTP is one substrate binding. The service envelope
is substrate-agnostic. The proof does not install or reference the Rack gem.

---

## Closed Surfaces

| Surface | Status |
|---|---|
| HTTP server / accept loop | CLOSED — no server implementation |
| Rack middleware chain | CLOSED — no Rack gem |
| Real DB / SQL / ORM | CLOSED — mock data only |
| Real network / file / queue | CLOSED |
| Production StorageCapabilityExecutor | CLOSED |
| PROP-035 full Effect Surface | CLOSED — experiment-pass subset only |
| Stage 2+ STORAGE fragment VM execution | CLOSED |
| Public runtime API | CLOSED |
| Production runtime claim | CLOSED |
| Reference Runtime claim | CLOSED |
