# LAB-IGNITER-LANG-IO-RUNTIME-P3 — Storage Executor Proof

**Date:** 2026-06-13  
**Route:** LAB RUNTIME / MOCKED STORAGE EXECUTOR IMPLEMENTATION  
**Status:** CLOSED — PROOF COMPLETE (129/129)  
**Authority:** proof-local implementation; no real DB / no SQL / no ORM  
**No production runtime claim / no Reference Runtime claim / no public API**

---

## What this proves

This proof implements and exercises the first mocked IO runtime path: `StorageCapabilityExecutor` + `CapabilityExecutorRegistry` for storage-read effect dispatch.

The proof establishes:

1. All data structures from LANG-IO-CAPABILITY-EXECUTOR-P1/P2 are concretely instantiable.
2. `StorageCapabilityExecutor` correctly runs the 6-gate G1–G6 sequence from LAB-STORAGE-CAPABILITY-P1/P2.
3. Denial-as-data and RuntimeRefusal are separate, non-overlapping categories.
4. Receipts are emitted on all outcome paths (succeeded, denied, failed).
5. Covenant P15 outcome semantics: `timed_out` = UnknownExternalOutcome, not ObservedFailure.

---

## Implementation file

**Path:** `igniter-lang/experiments/io_capability_executor/capability_executor_runtime.rb`  
**Namespace:** `CapabilityExecutorRuntime`  
**Loaded via:** `require_relative` from proof runner only.  
**Not in lib/. Not a compiler component. Not a public API.**

### Classes and modules

| Symbol | Kind | Fields / Notes |
|--------|------|----------------|
| `CapabilityPassport` | Struct (7 fields, keyword_init) | capability_id, family, authority_ref, granted_at, expires_at, revoked, family_fields. `#expired?` / `#valid_family?` |
| `EffectReceipt` | Struct (14 fields, keyword_init) | receipt_id, effect_ref, program_id, contract_ref, capability_id, family, authority_ref, idempotency_key, idempotency_used, inputs_hash, outcome, substrate, emitted_at, evidence_refs. `#to_h` |
| `ExecutionContext` | Struct (4 fields) | program_id, contract_ref, effect_ref, session_id |
| `RuntimeRefusal` | Struct (4 fields) | reason_code, effect_ref, contract_ref, detail. `#to_h` |
| `EffectResult` | Module | 7 factory methods; `outcome_of` / `denied?` / `succeeded?` / `unknown_external_outcome?` |
| `CapabilityExecutor` | Module (interface) | `family_id` / `execute` (raise NotImplementedError) |
| `CapabilityExecutorRegistry` | Class | `register` / `fetch` / `supports?` / `registered_families` |
| `StorageCapabilityExecutor` | Class | includes CapabilityExecutor; G1–G6; MOCKED_ROWS |

---

## Gate sequence: G1–G6

| Gate | Name | Outcome on fail | Notes |
|------|------|-----------------|-------|
| G1 | source_table in allowed_sources | `denied` | Fail-closed: empty list = deny all |
| G2 | "read" in allowed_ops | `denied` | Must be present in passport family_fields |
| G3 | read_allowed master gate | `denied` | Boolean master switch |
| G4 | row limit clamp | *(non-denial)* | Reduces effective_limit; clamped flag set in value |
| G5 | include_all policy | `failed` (query_error) | NOT a denial; error_kind = "query_error" |
| G6 | mocked execution | `succeeded` / `failed` (system_error) | MOCKED_ROWS only; error_trigger plan → system_error |

---

## Outcome invariants

- Receipt emitted on **all** paths: succeeded / denied / failed / partial / timed_out / unknown_external_state / cancelled.
- `cap_checked` equivalent: receipt always carries `capability_id` regardless of gate outcome.
- G5 failure → `outcome=failed`, NOT `outcome=denied`. `error_kind=query_error`.
- G4 clamp → `outcome=succeeded` with `row_limit_clamped=true` and reduced `effective_limit`.
- P15: `timed_out` = UnknownExternalOutcome. `EffectResult.unknown_external_outcome?` returns true for both `timed_out` and `unknown_external_state`, never for `failed`.

---

## Denial-as-data vs RuntimeRefusal

| Concept | When | Receipt emitted | Exception raised |
|---------|------|-----------------|-----------------|
| `EffectResult.denied` | Inside executor (G1/G2/G3 gate failure) | Yes | No |
| `RuntimeRefusal` | Before executor (missing passport, expired, revoked, unsupported family) | No | No — caller raises separately |

This proof exercises the executor-side path. RuntimeRefusal is proven as a separate Struct that does not overlap with EffectResult.

---

## Proof runner

**Path:** `igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p3.rb`  
**Score:** 129/129 PASS

### Section breakdown

| Section | Topic | Checks |
|---------|-------|--------|
| A | Module + constants | 13 |
| B | CapabilityPassport (7 fields + methods) | 12 |
| C | EffectReceipt (14 fields + to_h) | 16 |
| D | RuntimeRefusal (4 fields + to_h) | 6 |
| E | EffectResult 7 factory methods + helpers | 16 |
| F | CapabilityExecutorRegistry | 8 |
| G | StorageCapabilityExecutor interface | 4 |
| H | Receipt generation (content-addressed) | 8 |
| I | G1 — source_table allowlist gate | 5 |
| J | G2 — allowed_ops gate | 4 |
| K | G3 — read_allowed master gate | 3 |
| L | G4 — row limit clamp | 5 |
| M | G5 — include_all policy gate | 5 |
| N | G6 — mocked execution | 8 |
| O | Denial-as-data vs RuntimeRefusal boundary | 6 |
| P | Covenant P15 + outcome semantics | 10 |
| **Total** | | **129** |

---

## Boundary declarations

- No SQL, no ORM, no migrations, no transactions, no persistence, no network, no file IO, no process IO.
- `StorageCapabilityExecutor` returns rows from `MOCKED_ROWS` only. No DB driver loaded.
- `IO.StorageCapability` authority is NOT conferred to this implementation. This proof demonstrates behavior under gate logic, not database access rights.
- `EffectReceipt.emitted_at` is a fixed proof-local timestamp (`PROOF_LOCAL_TIMESTAMP`).
- `receipt_id` and `inputs_hash` are content-addressed SHA256 — deterministic for same inputs, no ambient state.

---

## Prerequisite evidence chain

| Card | Score | Provides |
|------|-------|----------|
| LANG-IO-CAPABILITY-EXECUTOR-P1 | 80/80 | 7-arg execute interface; 7-outcome EffectResult |
| LANG-IO-CAPABILITY-EXECUTOR-P2 | 86/86 | Implementation plan; exact Ruby struct shapes |
| LAB-IGNITER-LANG-IO-RUNTIME-P2 | 69/69 | Storage read plan; gate sequence; denial-as-data boundary |
| LAB-STORAGE-CAPABILITY-P2 | 51/51 | G1–G6 gate design |
| LAB-EXECUTE-QUERY-P3 | 68/68 | QueryExecutionReceipt shape |

---

## Recommended next card

`LAB-IGNITER-LANG-IO-RUNTIME-P4` — wire executor dispatch into a minimal RuntimeMachine evaluate extension, proving full route: ESCAPE fragment → registry lookup → passport check → executor dispatch → EffectResult → RuntimeMachine result envelope.
