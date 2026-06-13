# Igniter Microservice P3 — Runtime-Wired Envelope Proof v0

**Card:** LAB-IGNITER-LANG-MICROSERVICE-P3
**Track:** LAB SERVICE ENVELOPE / RUNTIME-WIRED STORAGE EXECUTION
**Status:** OPEN — proof doc authored
**Authority:** proof-only service integration; no HTTP server and no production API
**Date:** 2026-06-13
**Upstream:** LAB-IGNITER-LANG-MICROSERVICE-P2 (CLOSED 60/60), LAB-IGNITER-LANG-IO-RUNTIME-P4 (CLOSED 104/104)

---

## Scope

This document validates the `ServiceRequest` / `ServiceResponse` envelope from P1/P2
against the **runtime-wired** executor dispatch path from IO Runtime P4.

P2 proved the envelope over a proof-local `EnvelopeRunner` that embedded
a simplified `MockStorageCapabilityExecutor` (3-arg, inline). P3 replaces
that simulation layer with the actual `RuntimeMachine.evaluate_effect` path
from `runtime_machine_io_extension.rb`, which:

- Reads effect evidence from a loaded `CompiledProgram` (`effect_surface_v0_stub`).
- Runs 8 preflight gates before executor dispatch.
- Dispatches through a `CapabilityExecutorRegistry` to `StorageCapabilityExecutor` (7-arg canonical interface).
- Returns `EffectResult` (7-outcome) with `EffectReceipt` (14-field).
- Appends a `platform_observation` to the backend for each executor-side outcome.

The `RuntimeEnvelopeAdapter` is a proof-local module that wraps the machine in
P1 `ServiceRequest` / `ServiceResponse` shapes. It is not a real microservice.

**Five outcome scenarios are validated:**

1. **Succeeded** (`storage_read` G1–G6 pass): rows returned → ServiceResponse kind `"ok"`.
2. **Pre-executor RuntimeRefusal** (revoked/expired/wrong-family passport, unknown contract,
   artifact mismatch): machine returns `{ status: "refused", refusal: RuntimeRefusal }` →
   ServiceResponse kind `"runtime_refusal"`, no receipt.
3. **Executor denial-as-data** (G1/G2/G3 capability gate fail): executor returns
   `EffectResult.denied` with receipt → ServiceResponse kind `"denied"`.
4. **Unknown external state** (P15): proof-local `UnknownStateStorageExecutor` returns
   `EffectResult.unknown_external_state` → ServiceResponse kind `"effect_failure"`,
   receipt.outcome `"unknown_external_state"` (distinct from `"failed"`).
5. **Deterministic replay evidence**: same inputs → same `inputs_hash`, same
   `idempotency_key` + `correlation_id` → same `evidence_digest`.

**Authority boundary:** proof-local simulation. No real IO, no HTTP server,
no Rack middleware, no real DB/SQL/ORM, no production runtime, no public API claim.

---

## Upstream Dependency Chain

| Card | Result | What it contributes |
|---|---|---|
| LAB-IGNITER-LANG-IO-RUNTIME-P1 | CLOSED 85/85 | Route confirmed; CapabilityExecutor gap identified |
| LAB-IGNITER-LANG-IO-RUNTIME-P2 | CLOSED 69/69 | MockStorageCapabilityExecutor; G1–G6 gate sequence |
| LANG-IO-CAPABILITY-EXECUTOR-P1 | CLOSED 80/80 | CapabilityExecutor interface; 7-outcome EffectResult; 14-field EffectReceipt |
| LAB-IGNITER-LANG-IO-RUNTIME-P3 | CLOSED 129/129 | StorageCapabilityExecutor (7-arg); CapabilityExecutorRegistry; EffectResult shapes |
| LAB-IGNITER-LANG-IO-RUNTIME-P4 | CLOSED 104/104 | RuntimeMachine.evaluate_effect; 8 preflight gates; platform_observation per dispatch |
| LAB-IGNITER-LANG-MICROSERVICE-P1 | CLOSED 72/72 | ServiceRequest (11 fields); ServiceResponse; 8-gate allowlist; ResponseObservation |
| LAB-IGNITER-LANG-MICROSERVICE-P2 | CLOSED 60/60 | EnvelopeRunner proof-local; three scenarios; replay evidence determinism |

---

## Integration Model

The `RuntimeEnvelopeAdapter` (proof-local) wraps the `RuntimeMachine` from
IO Runtime P4 in P1 envelope shapes. It is not a production component.

```
ServiceRequest
  ↓ RuntimeEnvelopeAdapter.validate_envelope! (G1: contract_id, G2: artifact_digest)
  ↓ [PreEvaluateRefusal → ServiceResponse{kind:"runtime_refusal", receipts:[]}]
  ↓ machine.evaluate_effect(contract_id, effect_name, passport, inputs, authority_ref,
                              executor_registry, now_iso8601, idempotency_key)
    ↓ machine gate 1: contract_id in loaded program
    ↓ machine gate 2: contract has effect_surface (effect_surface_v0_stub)
    ↓ machine gate 3: capability_binding for effect_name exists
    ↓ machine gate 4: executor registered for capability_type
    ↓ machine gate 5: passport not nil
    ↓ machine gate 6: passport not revoked
    ↓ machine gate 7: passport not expired
    ↓ machine gate 8: passport family matches executor family_id
    ↓ [status:"refused", refusal:RuntimeRefusal → ServiceResponse{kind:"runtime_refusal"}]
    ↓ StorageCapabilityExecutor.execute(context, effect_name, passport, inputs, ...)
      ↓ G1: source_table in allowed_sources
      ↓ G2: "read" in allowed_ops
      ↓ G3: read_allowed master gate
      ↓ G4: row limit clamp (not a denial)
      ↓ G5: include_all policy gate (query_error if blocked)
      ↓ G6: mocked rows execution
    ↓ [EffectResult.denied|succeeded|failed|unknown_external_state with EffectReceipt]
    ↓ platform_observation appended to backend
  ↓ map EffectResult → EffectReceipt (P1 shape) + ServiceResponse kind
  ↓ build ResponseObservation (evidence_digest = sha256(receipt_refs + output + outcome_kind))
ServiceResponse
```

**Key difference from P2:** In P2, `EnvelopeRunner` called a simplified 3-arg
`MockStorageCapabilityExecutor.execute(effect_name, capability_hash, inputs)` directly.
In P3, `RuntimeEnvelopeAdapter` calls `machine.evaluate_effect(...)` which:
(a) resolves the executor from the registry, (b) runs 8 preflight gates on the
`CapabilityPassport` struct, (c) dispatches to the canonical 7-arg executor interface,
(d) emits a `platform_observation` per call.

---

## CompiledProgram Fixture

The `CompiledProgram` must carry an `effect_surface_v0_stub` in the contract IR
so that `evaluate_effect` can resolve the capability binding.

```ruby
P3_CONTRACT_ID = "contract/io-storage-read-v0"

P3_STORAGE_CONTRACT = {
  "contract_id"    => P3_CONTRACT_ID,
  "name"           => "io_storage_read",
  "fragment_class" => "escape",
  "escape_set"     => ["io_capability"],
  "lifecycle"      => "session",
  "type_signature" => {},
  "input_ports"    => [],
  "output_ports"   => [],
  "compute_nodes"  => [],
  "effect_surface" => {
    "kind" => "effect_surface_v0_stub",
    "capability_bindings" => [
      {
        "capability_name" => "store",
        "capability_type" => "IO.StorageCapability",
        "effect_name"     => "storage_read"
      }
    ]
  },
  "escape_boundaries" => [
    {
      "kind"            => "io_capability",
      "name"            => "storage_read",
      "required_caps"   => ["IO.StorageCapability"],
      "capability_name" => "store",
      "capability_type" => "IO.StorageCapability"
    }
  ]
}
```

The `effect_name` used in `ServiceRequest.effect_names` and in `evaluate_effect`
must match `capability_bindings[*].effect_name` in the effect_surface.
For P3: `"storage_read"`.

---

## CapabilityPassport Struct (P4 form)

P3 `ServiceRequest.capability_passports` carries proper
`CapabilityExecutorRuntime::CapabilityPassport` structs (7 fields), not plain hashes.
This is the canonical form that `RuntimeMachine.evaluate_effect` expects for
its preflight gates (revoked?, expired?, valid_family?).

```ruby
# Valid passport
P3_VALID_PASSPORT = CapabilityExecutorRuntime::CapabilityPassport.new(
  capability_id: "storage-read-users-v0",
  family:        "storage",
  authority_ref: "authority/proof-p3",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,      # no expiry
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 3,
    "allow_include_all" => false
  }
)
```

```ruby
# Revoked passport → machine gate 6 → RuntimeRefusal
P3_REVOKED_PASSPORT = CapabilityExecutorRuntime::CapabilityPassport.new(
  capability_id: "storage-read-revoked-v0",
  family:        "storage",
  authority_ref: "authority/proof-p3",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       true,
  family_fields: {}
)
```

```ruby
# Denial passport (G1: allowed_sources empty) → executor denial-as-data
P3_DENY_PASSPORT = CapabilityExecutorRuntime::CapabilityPassport.new(
  capability_id: "storage-read-deny-v0",
  family:        "storage",
  authority_ref: "authority/proof-p3",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => [],     # deny all sources
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 3,
    "allow_include_all" => false
  }
)
```

---

## ServiceRequest Shape (P3 form)

```
ServiceRequest {
  correlation_id:       "req-p3-001"
  contract_id:          "contract/io-storage-read-v0"    # must be in DECLARED_CONTRACTS
  effect_names:         ["storage_read"]                 # must match capability_binding
  input:                { plan: { kind: "select", source: { table: "users" }, limit: 2 } }
  authority_ref:        "authority/proof-p3"
  capability_passports: { storage: P3_VALID_PASSPORT }   # CapabilityPassport struct
  idempotency_key:      "idem-p3-001"                    # nil for non-idempotent
  ingress_substrate:    "http"                           # recorded, not used for dispatch
  ingress_timestamp:    "2026-06-13T00:00:00Z"           # clock binding
  artifact_digest:      "sha256:proof-p3-storage-effect-artifact"  # must match program
  profile_ids:          []
}
```

---

## Scenario 1 — Succeeded (rows)

**Setup:**
- `P3_VALID_PASSPORT`: `allowed_sources: ["users"]`, `read_allowed: true`, `row_limit: 3`
- `plan`: `{ kind: "select", source: { table: "users" }, limit: 2 }`
- Machine gates 1–8 pass; G4 effective_limit = min(2, 3) = 2; G6 returns 2 mocked rows

**Machine dispatch result:**
```
{ status: "ok",
  effect_result: { "outcome" => "succeeded", "value" => { "rows" => [...], "count" => 2, ... },
                   "receipt" => EffectReceipt{outcome:"succeeded", inputs_hash:"sha256:..."} },
  effect_obs: ObsPacket{kind:"platform_observation"} }
```

**ServiceResponse:**
```
{
  correlation_id:    "req-p3-ok"
  kind:              "ok"
  output:            { "rows" => [...], "count" => 2, "kind" => "rows" }
  receipts: [
    {
      receipt_id:          "receipt/sha256:..."   (from EffectReceipt)
      effect_name:         "storage_read"
      capability_id:       "storage-read-users-v0"
      family:              "storage"
      authority_ref:       "authority/proof-p3"
      idempotency_key:     "idem-p3-ok"
      idempotency_key_used: true
      inputs_hash:         "sha256:..."
      outcome:             "succeeded"
      substrate:           "storage"
      emitted_at:          "2026-06-13T00:00:00Z"
      evidence_refs:       []
      runtime_receipt:     { ... 14-field EffectReceipt ... }
    }
  ]
  effect_outcomes:   { "storage_read" => "succeeded" }
  response_observation: { kind: "response_observation", evidence_digest: "sha256:..." }
}
```

---

## Scenario 2 — Pre-Executor RuntimeRefusal

**Two sub-paths:**

**2a — Envelope refusal (before machine):**
- `contract_id` not in DECLARED_CONTRACTS → `PreEvaluateRefusal("effect.unknown_contract")`
- `artifact_digest` mismatch → `PreEvaluateRefusal("effect.artifact_digest_mismatch")`
- No call to `machine.evaluate_effect`; no backend observation; no receipt.

**2b — Machine preflight refusal (before executor):**
- `revoked: true` → `{ status: "refused", refusal: RuntimeRefusal{reason_code: "effect.passport_revoked"} }`
- `expired: true` (past `expires_at`) → `RuntimeRefusal{reason_code: "effect.passport_expired"}`
- `family: "file"` with storage executor → `RuntimeRefusal{reason_code: "effect.passport_family_mismatch"}`
- `passport: nil` → `RuntimeRefusal{reason_code: "effect.missing_passport"}`
- No executor registered → `RuntimeRefusal{reason_code: "effect.no_executor"}`

**ServiceResponse (both sub-paths):**
```
{
  correlation_id:  "req-p3-refused"
  kind:            "runtime_refusal"
  output:          nil
  diagnostics:     [{ reason_code: "effect.passport_revoked" }]
  receipts:        []                        # no receipt on RuntimeRefusal
  effect_outcomes: {}                        # no outcomes recorded
  response_observation: { outcome_kind: "runtime_refusal", receipt_refs: [], ... }
}
```

**Rule:** `receipts: []` is the invariant that distinguishes pre-executor RuntimeRefusal from
executor denial. The consumer must branch on `kind == "runtime_refusal"` before looking at receipts.

---

## Scenario 3 — Executor Denial-as-Data

**Setup:**
- `P3_DENY_PASSPORT`: `allowed_sources: []` (deny all sources)
- `plan`: `{ source: { table: "users" }, ... }`
- Machine gates 1–8 pass (passport not revoked/expired); G1 executor gate fires → `EffectResult.denied`

**Machine dispatch result:**
```
{ status: "ok",
  effect_result: { "outcome" => "denied", "gate" => "G1",
                   "reason" => "source-not-in-allowed-sources",
                   "receipt" => EffectReceipt{outcome:"denied"} },
  effect_obs: ObsPacket{...} }
```

**ServiceResponse:**
```
{
  kind:            "denied"
  receipts: [
    {
      outcome:     "denied"
      inputs_hash: "sha256:..."      (always present — denial is data)
      ...                            (all 8 P1 replay fields)
      runtime_receipt: { ... }       (gate:"G1", reason:"source-not-in-allowed-sources")
    }
  ]
  effect_outcomes: { "storage_read" => "denied" }
}
```

**Rule:** denial-as-data. The executor found, the capability was evaluated, a receipt was produced.
`kind == "denied"` with `receipts.length == 1` — not an empty receipts array.

---

## Scenario 4 — Unknown External State (P15)

**Setup:**
- A proof-local `UnknownStateStorageExecutor` registered in `P3_UNKNOWN_REGISTRY`
  under `"IO.StorageCapability"`.
- Machine gates 1–8 pass (same `P3_VALID_PASSPORT`); executor returns
  `EffectResult.unknown_external_state(receipt:, sent_at:, last_known: nil)`.

**Machine dispatch result:**
```
{ status: "ok",
  effect_result: { "outcome" => "unknown_external_state",
                   "receipt" => EffectReceipt{outcome:"unknown_external_state"} },
  effect_obs: ObsPacket{...} }
```

**ServiceResponse:**
```
{
  kind:            "effect_failure"             # response-level kind
  receipts: [
    {
      outcome:     "unknown_external_state"      # P15: NOT "failed"
      inputs_hash: "sha256:..."                  (evidence always emitted)
      ...
    }
  ]
  effect_outcomes: { "storage_read" => "unknown_external_state" }
}
```

**P15 enforcement:**
- `response.kind == "effect_failure"` — consumer sees effect_failure at the envelope level.
- `receipts[0].outcome == "unknown_external_state"` — consumer MUST branch on receipt
  outcome, not on response kind alone.
- `"unknown_external_state"` is NOT `"failed"` — it is an UnknownExternalOutcome per
  Covenant P15, not an ObservedFailure.
- Reconciliation required before re-dispatch with the same `idempotency_key`.
  Re-submission without reconciliation risks duplicate external effect if the first
  attempt succeeded despite the timeout.

---

## Scenario 5 — Deterministic Replay Evidence

All scenarios produce receipts where the 8 minimum replay fields from P1 Q5 are deterministic:

| Field | Source | Invariant |
|---|---|---|
| `receipt_id` | `sha256(capability_id + ":" + effect_name + ":" + inputs_hash)` | Same inputs → same receipt_id |
| `effect_name` | from ServiceRequest.effect_names | Constant per effect |
| `capability_id` | from CapabilityPassport.capability_id | Constant per passport |
| `inputs_hash` | `sha256(JSON.generate(inputs.transform_keys(&:to_s).sort.to_h))` | Same plan → same hash |
| `outcome` | from EffectResult.outcome | Deterministic per execution path |
| `idempotency_key` | from ServiceRequest.idempotency_key | Threaded from request |
| `authority_ref` | from CapabilityPassport.authority_ref | Threaded from passport |
| `emitted_at` | proof-local fixed timestamp | Deterministic in proof context |

**inputs_hash invariant:**
```ruby
inputs_str  = JSON.generate(inputs.transform_keys(&:to_s).sort.to_h)
inputs_hash = "sha256:" + Digest::SHA256.hexdigest(inputs_str)
# Same plan = same inputs_hash. Different plan = different inputs_hash.
```

**evidence_digest invariant (P26):**
```ruby
evidence_digest = "sha256:" + Digest::SHA256.hexdigest(
  JSON.generate({ receipts: receipt_refs, output: output, outcome_kind: response_kind })
)
# Same request + same executor path → same evidence_digest.
```

**P26 audit chain:** `ingress_timestamp` (ServiceRequest) → `emitted_at` (EffectReceipt) →
`observed_at` (ResponseObservation). The `evidence_digest` closes the chain by committing
over receipt content + output + outcome_kind.

---

## Rack/HTTP Substrate Boundary

The `RuntimeEnvelopeAdapter` accepts a `ServiceRequest` hash and returns a `ServiceResponse`.
It does not:

- Parse HTTP verb / path / headers
- Require a Rack `env` hash
- Depend on a running HTTP server
- Call `Net::HTTP`, `TCPSocket`, or any real network primitive

The `ingress_substrate: "http"` field in `ServiceRequest` records that the host would
deliver this request over HTTP/Rack. But `RuntimeEnvelopeAdapter` does not use this
field for dispatch. A queue-substrate request with `ingress_substrate: "queue"` follows
the same evaluate → dispatch → receipt path through the RuntimeMachine.

The `RuntimeMachine` itself is also substrate-agnostic: `evaluate_effect` takes typed
inputs and returns a typed `EffectResult`. It does not know or care whether the call
came from HTTP, AMQP, gRPC, or a test runner.

**Rule (from P1):** Rack/HTTP is one substrate binding, not the architecture.

---

## Closed Surfaces

| Surface | Status |
|---|---|
| HTTP server / accept loop | CLOSED — no server implementation |
| Rack middleware chain | CLOSED — no Rack gem |
| Real DB / SQL / ORM | CLOSED — mock data only (MOCKED_ROWS constant) |
| Real network / file / queue | CLOSED |
| Production StorageCapabilityExecutor | CLOSED |
| PROP-035 full Effect Surface | CLOSED — effect_surface_v0_stub only |
| Stage 2+ STORAGE fragment VM execution | CLOSED |
| Public runtime API | CLOSED |
| Production runtime claim | CLOSED |
| Reference Runtime claim | CLOSED |
