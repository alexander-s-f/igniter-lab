# LAB-IGNITER-LANG-IO-RUNTIME-P4 — Runtime Wiring Proof

**Date:** 2026-06-13  
**Route:** LAB RUNTIME / RUNTIMEMACHINE EXECUTOR WIRING  
**Status:** CLOSED — PROOF COMPLETE (104/104)  
**Authority:** proof-local only; no real DB / no SQL / no ORM / no production runtime claim

---

## What this proves

A proof-local extension to `RuntimeMachineMemoryProof::RuntimeMachine` connects five previously isolated pieces into a runnable IO dispatch loop:

1. `effect_surface_v0_stub` evidence from a loaded `CompiledProgram` (LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3)
2. `CapabilityExecutorRegistry` (LAB-IGNITER-LANG-IO-RUNTIME-P3)
3. `CapabilityPassport` preflight (P3 executor substrate)
4. `StorageCapabilityExecutor` dispatch with G1–G6 gates (P3)
5. `EffectResult` envelope + `EffectReceipt` (P3 + Covenant P15)

---

## Gates satisfied

| Gate | Card | Score |
|------|------|-------|
| LAB-IGNITER-LANG-IO-RUNTIME-P3 | Executor substrate (CapabilityPassport, EffectReceipt, StorageCapabilityExecutor) | 129/129 |
| LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3 | SemanticIR emits `effect_surface_v0_stub` + `io_capability` escape boundaries | 65/65 |

---

## Implementation

**One new file:** `experiments/io_capability_executor/runtime_machine_io_extension.rb`

Reopens `RuntimeMachineMemoryProof::RuntimeMachine` (same pattern as `compiled_program.rb`) and adds one public method:

```ruby
def evaluate_effect(
  contract_id:,
  effect_name:,
  passport:,
  inputs:,
  authority_ref:,
  executor_registry:,
  now_iso8601:,
  idempotency_key: nil,
  deadline_ms: 30_000
)
```

### Pre-executor preflight gates (→ RuntimeRefusal, no receipt, no backend append)

| Check | Reason code |
|-------|-------------|
| contract_id not in loaded program | `effect.unknown_contract` |
| contract has no `effect_surface` | `effect.no_effect_surface` |
| no `capability_binding` for effect_name | `effect.unknown_effect_name` |
| capability_type not in executor_registry | `effect.no_executor` |
| passport is nil | `effect.missing_passport` |
| passport.revoked == true | `effect.passport_revoked` |
| passport.expired?(now_iso8601) | `effect.passport_expired` |
| passport.family != executor.family_id | `effect.passport_family_mismatch` |

All 8 return `{ status: "refused", refusal: RuntimeRefusal }` — no receipt, no backend packet.

### Executor dispatch (→ EffectResult, receipt always emitted by executor)

After all preflight gates pass, builds `ExecutionContext` from the loaded program and dispatches to `executor.execute(...)`. The executor runs G1–G6 and returns an `EffectResult` hash with a receipt on every path.

After dispatch, appends one `platform_observation` packet to the backend:
```json
{
  "kind": "platform_observation",
  "subject": "effect://<contract_id>/<effect_name>",
  "payload": {
    "effect_ref": "effect/<contract_id>/<effect_name>",
    "program_id": "...",
    "capability_type": "IO.StorageCapability",
    "capability_id": "...",
    "authority_ref": "...",
    "outcome": "succeeded | denied | failed | ..."
  }
}
```

Returns `{ status: "ok", effect_result: ..., effect_obs: ObsPacket }`.

---

## Dispatch flow diagram

```
CompiledProgram.contracts[contract_id]
  └─ effect_surface["capability_bindings"] → find binding by effect_name
       └─ binding["capability_type"] → executor_registry.fetch(...)
            ├─ nil → RuntimeRefusal (effect.no_executor)
            └─ StorageCapabilityExecutor
                 ├─ passport preflight (nil / revoked / expired / family)
                 │    └─ RuntimeRefusal — no receipt
                 └─ executor.execute(context, passport, inputs, ...)
                      ├─ G1: source_table in allowed_sources → denied(gate: "G1") + receipt
                      ├─ G2: "read" in allowed_ops          → denied(gate: "G2") + receipt
                      ├─ G3: read_allowed master gate        → denied(gate: "G3") + receipt
                      ├─ G4: row limit clamp (non-denial)
                      ├─ G5: include_all violation           → failed(query_error) + receipt
                      ├─ G6: error_trigger simulation        → failed(system_error) + receipt
                      └─ G6: mocked rows                     → succeeded + receipt
                           └─ effect_obs appended to backend
```

---

## Return value shapes

| Scenario | Return |
|----------|--------|
| Pre-executor gate failure | `{ status: "refused", refusal: RuntimeRefusal }` |
| Machine state guard failure | `{ status: "blocked", ... }` (existing failure method) |
| Executor dispatch (all outcomes) | `{ status: "ok", effect_result: EffectResult, effect_obs: ObsPacket }` |

The three-way distinction is explicit: `"refused"` has no receipt, `"ok"` has receipt inside `effect_result`.

---

## Covenant P15 compliance

P15: `timed_out` = UnknownExternalOutcome, not ObservedFailure.

```ruby
EffectResult.unknown_external_outcome?(timed_out_result)       # → true
EffectResult.unknown_external_outcome?(unknown_external_state) # → true
EffectResult.unknown_external_outcome?(succeeded)              # → false
EffectResult.unknown_external_outcome?(denied)                 # → false
```

The executor substrate from P3 carries this through; the P4 wiring proof verifies it at section K.

---

## PROP-035 upgrade-path guard

The `effect_surface_v0_stub` kind is consumed by `evaluate_effect` without checking the kind field — the field is load-bearing for consumers that need to distinguish bridge evidence from full PROP-035 evidence. When PROP-035 ships:
- `kind` changes to `"effect_surface_v0"` (no `_stub`)
- `evaluate_effect` continues to work unchanged (it reads `capability_bindings`, not the kind)
- Consumers that checked for `"effect_surface_v0_stub"` know to upgrade

---

## Proof runner section breakdown

**Path:** `igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p4.rb`  
**Score:** 104/104 PASS

| Section | Scope | Checks |
|---------|-------|--------|
| A | Extension + struct presence | 8 |
| B | CompiledProgram fixture validation | 8 |
| C | Boot + load_program | 8 |
| D | RuntimeRefusal — no executor | 6 |
| E | RuntimeRefusal — no effect_surface | 5 |
| F | RuntimeRefusal — passport gates (nil/revoked/expired/family) | 12 |
| G | Executor denial-as-data G1/G2/G3 | 9 |
| H | Executor success — mocked storage read | 8 |
| I | G4 row limit clamping (no-clamp + clamp) | 6 |
| J | G5 + G6 failure paths | 6 |
| K | Covenant P15 — timed_out / unknown_external_state | 6 |
| L | Receipt invariants across all executor paths | 8 |
| M | Backend observation packet isolation | 8 |
| N | Unknown contract / unknown effect_name | 6 |
| **Total** | | **104** |

---

## Boundary declarations

- No real DB / SQL / ORM / migrations / transactions.
- No network / file / process IO.
- No Rack or HTTP server.
- No public API claim.
- No Reference Runtime claim.
- No full PROP-035 Effect Surface.
- No storage write family.
- `evaluate_effect` is proof-local; it does not ship in `lib/igniter_lang`.

---

## Recommended next card

`LAB-IGNITER-LANG-MICROSERVICE-P3` — runs the ServiceRequest/ServiceResponse envelope over this actual Runtime P4 path.
