# LAB-RECORD-VM-P1: VM Record Construction and Serialization

**Category:** lang
**Track:** `lab-record-vm-construction-and-serialization-proof-v0`
**Status:** CLOSED / PROVED — 43/43 PASS
**Date closed:** 2026-06-09
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Depends on

- LAB-RACK-P13 (nominal record typechecking — 47/47)
- LAB-SIDEKIQ-P4 (JobReceipt schema — 46/46)

---

## Goal

Prove VM-level construction and observable serialization of typed record outputs
using RackResponse (P13) and Sidekiq JobReceipt (P4) as pressure families — without
creating public/runtime/canon/stable authority.

---

## Key Finding: Zero New Code Required

**No VM changes, no compiler changes, no new opcodes were needed.**

The VM already had complete record support:
- `OP_PUSH_RECORD` — constructs `Value::Record(Arc<BTreeMap<String, Value>>)`
- `Value::Record` uses `BTreeMap` — alphabetical key order, deterministic iteration
- `to_json()` for `Value::Record` — serializes to JSON object preserving all fields
- Compiler's `"record_literal"` emission — already emits `OP_PUSH_RECORD`

LAB-RACK-P13 and LAB-SIDEKIQ-P4 were TypeChecker/SemanticIR-only proofs. The runtime
path was already wired and just needed to be exercised.

---

## Explicit Answers

| Question | Answer |
|---|---|
| VM record construction proven for RackResponse | ✅ YES |
| VM record construction proven for JobReceipt | ✅ YES |
| Implementation is generic (not domain-specific) | ✅ YES — OP_PUSH_RECORD + BTreeMap |
| Field names and values survive VM execution | ✅ YES |
| Serialization is deterministic | ✅ YES — BTreeMap alphabetical key order |
| Creates canon/runtime/public/stable authority | ❌ NO |
| Rack P14 covered by this shared proof | ✅ YES |
| Sidekiq P5 covered by this shared proof | ✅ YES |
| Next route | P2 — nested record field access |

---

## Scope

### Proved in P1

- `OkHandler` / `DirectLiteralHandler` / `ComplexFieldHandler` execute end-to-end returning `RackResponse`
- `StaticDispatcherP13` (P11 Tier 1 literal callee) executes returning `RackResponse`
- `DynamicDispatcherP13` (P11 Tier 2 variable callee) executes returning `RackResponse` at runtime
- `ReceiptJob` executes end-to-end returning `JobReceipt` with all 5 fields
- `ReceiptDispatcher` (Tier 1) executes returning `JobReceipt` via `call_contract` dispatch
- `DynamicReceiptDispatcher` (Tier 2) executes returning `JobReceipt` via dynamic dispatch
- Field serialization is deterministic: `BTreeMap` alphabetical order → consistent JSON key ordering
- Computed field values (e.g. `budget_remaining = max_attempts - attempt`) survive VM serialization

### Not opened in P1

- Nested record types as field values
- Field access on a record returned from `call_contract`
- `record_field_access` opcode / OP_FIELD_ACCESS
- Multi-output callee
- Enum/status type system

---

## Deliverables

| File | Status |
|---|---|
| `igniter-view-engine/proofs/verify_record_vm_construction.rb` | ✅ 43/43 PASS |
| `lab-docs/lang/lab-record-vm-construction-and-serialization-proof-v0.md` | ✅ Written |
| `.agents/work/cards/lang/LAB-RECORD-VM-P1.md` | ✅ This file |
| `.agents/portfolio-index.md` updated | ✅ P1 row added |

No new fixtures needed. No new VM or compiler code.

---

## Shared Coverage

| Prior gap | Recommendation | Covered? |
|---|---|---|
| LAB-RACK-P13 P14 | VM record construction + field serialization | ✅ Covered by P1 |
| LAB-SIDEKIQ-P4 P5 | Execute ReceiptJob end-to-end through VM | ✅ Covered by P1 |

**No separate LAB-RACK-P14 or LAB-SIDEKIQ-P5 cards are needed** for this surface.

---

## P2 Recommendation

**Nested record field access** — prove `OP_FIELD_ACCESS` or equivalent on a record
returned from `call_contract`. Currently the full record is returned as a single VM
value; field-level extraction from a dispatched record has not been exercised.

This is the next meaningful boundary for both the Rack and Sidekiq paths.

---

## Boundary

Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim. No canon grammar
change. No production runtime authority. No public API stability. `call_contract` is
lab-only.
