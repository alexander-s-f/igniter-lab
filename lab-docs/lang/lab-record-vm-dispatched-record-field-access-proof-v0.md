# LAB-RECORD-VM-P2: Dispatched Record Field Access Proof — v0

**Track:** `lab-record-vm-dispatched-record-field-access-proof-v0`
**Status:** CLOSED / PROVED — 42/42 PASS
**Date:** 2026-06-09
**Depends on:** LAB-RECORD-VM-P1, LAB-RACK-P13, LAB-SIDEKIQ-P4

---

## 1. Goal

Prove field access over records returned from `call_contract`, showing that a record
value produced by one contract can be consumed by another contract through static field
access — without opening nested records, Map[K,V], JSON, runtime public authority, or
canon changes.

---

## 2. Finding: New Code Required

**One new opcode and one compiler fix were required.** The typechecker already correctly
resolved field types for Tier 1 dispatched records (confirmed in pre-research), but the
bytecode VM had no instruction for field extraction — `field_access` in the compiler
emitted `OP_LOAD_REG(record_reg)` which loaded the entire record rather than extracting
the named field.

| Component | Change |
|---|---|
| `igniter-vm/src/instructions.rs` | Added `OP_GET_FIELD (0x22)` constant |
| `igniter-vm/src/vm.rs` | Added `OP_GET_FIELD` handler |
| `igniter-vm/src/compiler.rs` | Fixed `"field_access"`: emit `OP_LOAD_REG + OP_GET_FIELD` |

All changes are inside `igniter-lab/igniter-vm/` — lab-only, no canon change.

---

## 3. Explicit Answers to Card Questions

| Question | Answer |
|---|---|
| Field access over RackResponse from `call_contract` proved? | **YES** — `response.status → 200`, `response.body → "OK"` |
| Field access over JobReceipt from `call_contract` proved? | **YES** — `receipt.status`, `receipt.budget_remaining`, `receipt.job_class` |
| Field values usable in downstream compute expressions? | **YES** — `budget + budget = 6` proved field value enters arithmetic |
| Missing-field behavior safe or blocker? | **SAFE** — OOF-P1 at compile time; not a runtime issue |
| Tier 2 (variable callee) + field access? | **FAIL-CLOSED** — OOF-P1 `Unknown.field` at compile time |
| Implementation required new code? | **YES** — `OP_GET_FIELD` opcode + compiler fix |
| Covers Rack/Sidekiq field-consumption pressure? | **YES** |
| Creates canon/runtime/public authority? | **NO** |

---

## 4. Mechanism Detail

### Pre-P2 State: Compiler Bug

For `compute status_out = receipt.status` where `receipt` is a register:

```rust
// OLD: compiler.rs "field_access" branch (BEFORE P2)
if let Some(&reg_idx) = self.compute_node_registers.get(name) {
    // BUG: just loaded the record without extracting the field
    self.emit(OP_LOAD_REG, vec![Value::Integer(reg_idx)]);
    return Ok(());
}
```

Result: `status_out` register got the entire `Value::Record` rather than the `status` field.

### Post-P2 Fix

```rust
// NEW: compiler.rs "field_access" branch (AFTER P2)
if let Some(&reg_idx) = self.compute_node_registers.get(name) {
    // Load the record register, then extract the named field
    self.emit(OP_LOAD_REG, vec![Value::Integer(reg_idx)]);
    self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(field))]);
    return Ok(());
}
```

### `OP_GET_FIELD` VM Handler

```rust
OP_GET_FIELD => {
    let field_name = inst.args.get(0)
        .ok_or("OP_GET_FIELD: missing field name argument")?
        .as_str()?;
    let record_val = stack.pop().ok_or("Stack underflow during OP_GET_FIELD")?;
    match record_val {
        Value::Record(ref map) => {
            let val = map.get(field_name)
                .ok_or_else(|| format!(
                    "OP_GET_FIELD: field '{}' not found in record (available: [{}])",
                    field_name,
                    map.keys().cloned().collect::<Vec<_>>().join(", ")
                ))?;
            stack.push(val.clone());
        }
        other => return Err(format!("OP_GET_FIELD: expected Record, got {:?}", other)),
    }
    ip += 1;
}
```

Opcode 0x22 in `instructions.rs`. Complements `OP_PUSH_RECORD (0x1F)`.

---

## 5. Fail-Closed Behaviors

### Missing field at compile time

```
compute no_such_out = response.no_such_field
output no_such_out : String
```

Produces at compile time:

```
OOF-P1: Unresolved field: RackResponse.no_such_field
```

The typechecker knows the record type (via P11 Tier 1 propagation) and validates the
field name against the `type_shapes` registry. Not a runtime error — caught early.

### Tier 2 (variable callee) + field access at compile time

```
compute receipt    = call_contract(handler_name, ...)  -- Tier 2: Unknown type
compute status_out = receipt.status
```

Produces at compile time:

```
OOF-P1: Unresolved field: Unknown.status
```

Tier 2 dynamic dispatch stays `Unknown`, so field access on a dynamically-dispatched
record is rejected at compile time. To access fields, the callee must be a Tier 1 literal.

---

## 6. Observed VM Outputs

### RackStatusReader (`response.status`)

Input: `{ "method": "GET", "path": "/" }`

VM output: `{"status": "success", "result": 200}`

Integer field correctly extracted from `Value::Record`.

### RackBodyReader (`response.body`)

VM output: `{"status": "success", "result": "OK"}`

String field correctly extracted.

### FieldBudgetReader (`receipt.budget_remaining`)

Input: `{ "job_class": "SomeJob", "job_id": "j-001", "attempt": 2, "max_attempts": 5 }`

VM output: `{"status": "success", "result": 3}`

`budget_remaining = max_attempts - attempt = 5 - 2 = 3`. Field value preserved through
`call_contract` dispatch + `OP_GET_FIELD` extraction.

### FieldComputeOnField (`budget + budget`)

Input: `{ ..., "attempt": 2, "max_attempts": 5 }`

VM output: `{"status": "success", "result": 6}`

`budget = receipt.budget_remaining = 3`; `doubled = budget + budget = 6`.
Field value enters arithmetic — usable as a normal integer.

---

## 7. Check Inventory (42/42 PASS)

### RECORD-FIELD-COMPILE — 5 checks
Fixture compiles OK; typechecker resolves `status_out → Integer`, `status_out → String`, `budget_out → Integer`.

### RECORD-FIELD-RACK — 6 checks

| Check | Contract | Assertion |
|---|---|---|
| RACK-01..02 | `RackStatusReader` | Executes; `response.status = 200` |
| RACK-03 | `RackStatusReader` | Result is Integer |
| RACK-04..05 | `RackBodyReader` | Executes; `response.body = "OK"` |
| RACK-06 | `RackBodyReader` | Result is String |

### RECORD-FIELD-SIDEKIQ — 9 checks

| Check | Contract | Assertion |
|---|---|---|
| SIDEKIQ-01..02 | `FieldStatusReader` | Executes; `receipt.status = "ok"` |
| SIDEKIQ-03..04 | `FieldBudgetReader` | Executes; `receipt.budget_remaining = 3` |
| SIDEKIQ-05..06 | `FieldJobClassReader` | Executes; `receipt.job_class = "SomeJob"` |
| SIDEKIQ-07..08 | `FieldComputeOnField` | Executes; `budget + budget = 6` |
| SIDEKIQ-09 | `FieldBudgetReader` | budget_remaining = 9 for attempt=1, max=10 |

### RECORD-FIELD-FAIL-CLOSED — 6 checks
Missing field → `OOF-P1`; diagnostic names the field and record type.
Tier 2 + field access → `OOF-P1`; diagnostic mentions `Unknown`.

### RECORD-FIELD-REG — 6 checks
P9 CallerDoubler, P3 RetryPolicy, P1 ReceiptJob all pass.
P13 SIR `OkHandler.response = RackResponse` unchanged.
P4 SIR `ReceiptJob.receipt = JobReceipt` unchanged.
No warnings on the P2 field access fixture.

### RECORD-FIELD-CLOSED — 5 checks
No sockets, no queue-store client, no event-loop framework, no compatibility claims,
no production/stability claims.

### RECORD-FIELD-GAP — 5 checks
Gap packet: `closed_by_p2` includes both Rack and Sidekiq field access;
`implementation_finding = new_opcode_required`; `still_open` includes nested records.

---

## 8. Fixture

New fixture: `igniter-view-engine/fixtures/rack_core/record_field_access.ig`

| Contract | Purpose |
|---|---|
| `OkHandler` | RackResponse source (passes through `call_contract`) |
| `RackStatusReader` | Reads `response.status : Integer` |
| `RackBodyReader` | Reads `response.body : String` |
| `ReceiptJob` | JobReceipt source (passes through `call_contract`) |
| `FieldStatusReader` | Reads `receipt.status : String` |
| `FieldBudgetReader` | Reads `receipt.budget_remaining : Integer` |
| `FieldJobClassReader` | Reads `receipt.job_class : String` |
| `FieldComputeOnField` | Uses `receipt.budget_remaining` in arithmetic |

---

## 9. Gap Packet

```ruby
GAP_PACKET = {
  proof:        'lab-record-vm-p2-dispatched-record-field-access',
  version:      'v0',
  implementation_finding: 'new_opcode_required',
  new_code: {
    'OP_GET_FIELD'            => 'instructions.rs: new opcode 0x22',
    'vm.rs OP_GET_FIELD'      => 'handler: pop record, push field value; missing-field error',
    'compiler.rs field_access' => 'fixed: OP_LOAD_REG(reg) + OP_GET_FIELD(field) when record in register'
  },
  closed_by_p2: %w[
    rack_response_dispatched_field_access
    jobreceipt_dispatched_field_access
    integer_field_extraction
    string_field_extraction
    field_value_usable_in_downstream_compute
    missing_field_fail_closed_compile_time
    tier2_dynamic_callee_field_access_fail_closed
  ],
  v0_policy: {
    field_access:             'tier1_only (literal callee resolves named type)',
    tier2_field_access:       'fail_closed_at_compile_time (Unknown.field → OOF-P1)',
    missing_field:            'fail_closed_at_compile_time (OOF-P1)',
    nested_record_fields:     'not_yet_proven',
    vm_authority:             'lab_only_no_runtime_gate'
  },
  still_open: %w[
    nested_record_types_as_field_values
    tier2_dynamic_callee_field_access_runtime
    multi_output_callee
    enum_status_type
    array_field_types
  ],
  rack_field_access_proved:    true,
  sidekiq_field_access_proved: true,
  rack_compatibility:          'permanently_closed',
  sidekiq_compatibility:       'permanently_closed',
  p3_recommendation: 'Nested record types as field values — prove field access on records that contain record-valued fields'
}
```

---

## 10. Artifacts

| File | Role |
|---|---|
| `igniter-view-engine/fixtures/rack_core/record_field_access.ig` | New fixture |
| `igniter-view-engine/proofs/verify_record_vm_field_access.rb` | Proof — 42/42 |
| `igniter-vm/src/instructions.rs` | Added `OP_GET_FIELD (0x22)` |
| `igniter-vm/src/vm.rs` | Added `OP_GET_FIELD` handler |
| `igniter-vm/src/compiler.rs` | Fixed `"field_access"` to emit `OP_GET_FIELD` |
| `lab-docs/lang/lab-record-vm-dispatched-record-field-access-proof-v0.md` | This document |
| `.agents/work/cards/lang/LAB-RECORD-VM-P2.md` | Card — CLOSED/PROVED |

---

**Boundary:** Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim.
No canon grammar change. No production runtime authority. No public API stability.
`call_contract` is lab-only. `OP_GET_FIELD` is lab-only VM instrumentation.
