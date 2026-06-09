# LAB-RECORD-VM-P2: Dispatched Record Field Access

**Category:** lang
**Track:** `lab-record-vm-dispatched-record-field-access-proof-v0`
**Status:** CLOSED / PROVED — 42/42 PASS
**Date closed:** 2026-06-09
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Depends on

- LAB-RECORD-VM-P1 (VM record construction and serialization — 43/43)
- LAB-RACK-P13 (nominal record typechecking — 47/47)
- LAB-SIDEKIQ-P4 (JobReceipt schema — 46/46)

---

## Goal

Prove field access over records returned from `call_contract`, showing that a record
value produced by one contract can be consumed by another contract through static field
access expressions.

---

## Key Finding: New Code Required

P2 required targeted VM and compiler changes. Unlike P1 (zero new code), field extraction
from a dispatched record was a genuine gap in the bytecode path:

| Component | Change |
|---|---|
| `igniter-vm/src/instructions.rs` | `OP_GET_FIELD (0x22)` — new opcode |
| `igniter-vm/src/vm.rs` | `OP_GET_FIELD` handler: pop record → push field value |
| `igniter-vm/src/compiler.rs` | `"field_access"` fixed: emit `OP_LOAD_REG + OP_GET_FIELD` |

Root cause: the compiler's `"field_access"` branch emitted `OP_LOAD_REG(record_reg)`
when the record was in a register — loading the full record rather than extracting the
named field. No field extraction opcode existed. P2 adds the opcode and fixes the emit.

---

## Explicit Answers

| Question | Answer |
|---|---|
| Field access over RackResponse from `call_contract` proved | ✅ YES — `response.status = 200`, `response.body = "OK"` |
| Field access over JobReceipt from `call_contract` proved | ✅ YES — `receipt.status`, `receipt.budget_remaining`, `receipt.job_class` |
| Field values usable in downstream compute expressions | ✅ YES — `budget + budget = 6` |
| Missing-field behavior | ✅ SAFE — OOF-P1 at compile time |
| Tier 2 dynamic callee + field access | ✅ FAIL-CLOSED — OOF-P1 `Unknown.field` |
| Implementation required new code | ✅ YES — `OP_GET_FIELD` + compiler fix |
| Covers Rack/Sidekiq field-consumption pressure | ✅ YES |
| Creates canon/runtime/public authority | ❌ NO |

---

## Scope

### Proved in P2

- `RackStatusReader` reads `response.status` (Integer) from a dispatched `RackResponse`
- `RackBodyReader` reads `response.body` (String) from a dispatched `RackResponse`
- `FieldStatusReader` reads `receipt.status` (String) from a dispatched `JobReceipt`
- `FieldBudgetReader` reads `receipt.budget_remaining` (Integer) from a dispatched `JobReceipt`
- `FieldJobClassReader` reads `receipt.job_class` (String) from a dispatched `JobReceipt`
- `FieldComputeOnField` uses `receipt.budget_remaining` in arithmetic (`budget + budget`)
- Missing field name → OOF-P1 at compile time (with field name + record type in message)
- Tier 2 variable callee → field access fails OOF-P1 `Unknown.field` at compile time

### Not opened in P2

- Nested record types as field values
- Tier 2 dynamic callee + runtime field access (remains compile-time blocked)
- Multiple output fields from a single contract
- Enum/status type system
- Array-valued fields

---

## Deliverables

| File | Status |
|---|---|
| `igniter-view-engine/fixtures/rack_core/record_field_access.ig` | ✅ Written |
| `igniter-view-engine/proofs/verify_record_vm_field_access.rb` | ✅ 42/42 PASS |
| `igniter-vm/src/instructions.rs` | ✅ `OP_GET_FIELD` added |
| `igniter-vm/src/vm.rs` | ✅ `OP_GET_FIELD` handler added |
| `igniter-vm/src/compiler.rs` | ✅ `"field_access"` fixed |
| `lab-docs/lang/lab-record-vm-dispatched-record-field-access-proof-v0.md` | ✅ Written |
| `.agents/work/cards/lang/LAB-RECORD-VM-P2.md` | ✅ This file |
| `.agents/portfolio-index.md` updated | ✅ P2 row added |

---

## P3 Recommendation

**Nested record types as field values** — prove that a record field can hold another
record, and that field access chains like `outer.inner.field` work end-to-end. Currently
all field values are scalars (Integer, String). Nested records are a natural next step
for richer domain models.

---

## Boundary

Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim. No canon grammar
change. No production runtime authority. No public API stability. `call_contract` is
lab-only. `OP_GET_FIELD` is lab-only VM instrumentation with no public bytecode stability.
