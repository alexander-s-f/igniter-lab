# LAB-RECORD-VM-P1: VM Record Construction and Serialization Proof — v0

**Track:** `lab-record-vm-construction-and-serialization-proof-v0`
**Status:** CLOSED / PROVED — 43/43 PASS
**Date:** 2026-06-09
**Depends on:** LAB-RACK-P13, LAB-SIDEKIQ-P4

---

## 1. Goal

Prove VM-level construction and observable serialization of typed record outputs,
using RackResponse (P13) and JobReceipt (Sidekiq P4) as pressure families — without
creating public/runtime/canon/stable authority.

---

## 2. Pre-Finding: Zero New Code Required

**The VM already fully supports record construction.** Research before implementation
found:

| Component | Status |
|---|---|
| `OP_PUSH_RECORD` (vm.rs) | Already present — constructs `Value::Record` from stack |
| `Value::Record(Arc<BTreeMap<String, Value>>)` (value.rs) | Already present — alphabetically sorted keys |
| `to_json()` for `Value::Record` (value.rs) | Already present — serializes to JSON object |
| `"record_literal"` in compiler (compiler.rs) | Already present — emits `OP_PUSH_RECORD` |

No VM changes, no compiler changes, no new opcodes. LAB-RACK-P13 and LAB-SIDEKIQ-P4
were TypeChecker/SemanticIR proofs only; the runtime path was already wired.

---

## 3. Explicit Answers to Card Questions

| Question | Answer |
|---|---|
| VM record construction proven for RackResponse? | **YES** — `OkHandler`, `DirectLiteralHandler`, `ComplexFieldHandler`, `StaticDispatcherP13`, `DynamicDispatcherP13` all execute end-to-end |
| VM record construction proven for JobReceipt? | **YES** — `ReceiptJob`, `ReceiptDispatcher`, `DynamicReceiptDispatcher` all execute end-to-end |
| Implementation is generic or domain-specific? | **GENERIC** — `OP_PUSH_RECORD` + `BTreeMap` works for any named record type; no Rack- or Sidekiq-specific code |
| Field names and values survive VM execution? | **YES** — all input fields, arithmetic fields, and literal fields preserved |
| Serialization is deterministic? | **YES** — `Value::Record` uses `BTreeMap`, so `to_json()` iterates in alphabetical key order unconditionally |
| Creates canon/runtime/public/stable authority? | **NO** — lab-only evidence |
| Rack P14 covered by this shared proof? | **YES** |
| Sidekiq P5 covered by this shared proof? | **YES** |
| Next route recommendation? | **P2** — nested record field access (prove `OP_FIELD_ACCESS` or equivalent on a record returned from `call_contract`) |

---

## 4. Mechanism Detail

### `OP_PUSH_RECORD` (vm.rs)

```rust
OP_PUSH_RECORD => {
    let key_count = inst.args.get(0)...as_integer()?;
    let mut map = std::collections::BTreeMap::new();
    for i in (0..key_count).rev() {
        let key_str = inst.args.get((i + 1) as usize)...as_str()?;
        let val = stack.pop()?;
        map.insert(key_str.to_string(), val);
    }
    stack.push(Value::Record(Arc::new(map)));
}
```

Keys are inserted into `BTreeMap` — always in sorted order regardless of insertion
sequence.

### `to_json()` for `Value::Record` (value.rs)

```rust
Value::Record(map) => {
    let mut obj = serde_json::Map::new();
    for (k, v) in map.iter() {  // BTreeMap::iter() → sorted order
        obj.insert(k.clone(), v.to_json());
    }
    serde_json::Value::Object(obj)
}
```

BTreeMap iterator is always sorted → JSON key order is always alphabetical.

### Compiler `"record_literal"` emission (compiler.rs)

```rust
"record" | "record_literal" => {
    let fields = node.get("fields").as_object()?;
    let mut sorted_keys: Vec<String> = fields.keys().cloned().collect();
    sorted_keys.sort();
    for key in &sorted_keys {
        self.compile_expr(fields.get(key).unwrap())?;  // push values in sorted order
    }
    let mut args = vec![Value::Integer(sorted_keys.len() as i64)];
    for key in sorted_keys {
        args.push(Value::String(Arc::from(key.as_str())));  // embed key names
    }
    self.emit(OP_PUSH_RECORD, args);
}
```

Compiler sorts keys before emission. Combined with `BTreeMap` in the VM, this
ensures a fully consistent alphabetical order.

---

## 5. Observed VM Output Examples

### RackResponse (`OkHandler`)

Input: `{ "method": "GET", "path": "/" }`

VM output: `{"status": "success", "result": {"body": "OK", "status": 200}}`

Fields in alphabetical order: `body` < `status`.

### JobReceipt (`ReceiptJob`)

Input: `{ "job_class": "SomeJob", "job_id": "j-001", "attempt": 2, "max_attempts": 5 }`

VM output: `{"status": "success", "result": {"attempt": 2, "budget_remaining": 3, "job_class": "SomeJob", "job_id": "j-001", "status": "ok"}}`

Fields in alphabetical order: `attempt` < `budget_remaining` < `job_class` < `job_id` < `status`.

`budget_remaining = max_attempts - attempt = 5 - 2 = 3` — arithmetic field preserved correctly.

### Tier 1 dispatcher (`ReceiptDispatcher`)

Calls `call_contract("ReceiptJob", ...)` — P11 Tier 1 resolves type at compile time.
VM executes the dispatch and receives the `Value::Record` as the callee's output.
The dispatcher's `receipt` compute node is populated with the full `JobReceipt` record.

### Tier 2 dispatcher (`DynamicReceiptDispatcher`)

Calls `call_contract(handler_name, ...)` — P11 Tier 2 stays Unknown at compile time.
VM executes the dispatch and receives the `Value::Record` at runtime. The record is
returned correctly even though the type was Unknown at compile time — runtime is fully
dynamic for record-valued outputs.

---

## 6. Check Inventory (43/43 PASS)

### RECORD-VM-COMPILE — 4 checks
P13 and P4 fixtures compile ok; no diagnostics.

### RECORD-VM-RACK — 10 checks

| Check | Scenario | Assertion |
|---|---|---|
| RACK-01..04 | `OkHandler` | Executes; result is Hash; status=200; body="OK" |
| RACK-05 | `DirectLiteralHandler` | status=200, body="Direct" |
| RACK-06 | `ComplexFieldHandler` (code=404) | status=404; BinaryOp field preserved |
| RACK-07..08 | `StaticDispatcherP13` (Tier 1) | Executes; status=200, body="OK" |
| RACK-09..10 | `DynamicDispatcherP13` (Tier 2) | Executes; returns record |

### RECORD-VM-SIDEKIQ — 9 checks

| Check | Scenario | Assertion |
|---|---|---|
| SIDEKIQ-01..05 | `ReceiptJob` | Executes; all 5 fields; job_class preserved; budget_remaining=3; status="ok" |
| SIDEKIQ-06..07 | `ReceiptDispatcher` (Tier 1) | Executes; all 5 fields; budget_remaining=2 |
| SIDEKIQ-08 | `DynamicReceiptDispatcher` (Tier 2) | Executes; budget_remaining=5 |
| SIDEKIQ-09 | Unknown handler | VM error "no contract named" |

### RECORD-VM-FIELDS — 5 checks
RackResponse is Hash with exactly 2 keys; keys alphabetical; JobReceipt has 5 keys;
keys alphabetical; computed `budget_remaining` survives across ReceiptJob + ReceiptDispatcher + DynamicReceiptDispatcher.

### RECORD-VM-REG — 5 checks
P9 `CallerDoubler(n=7)→15`; P3 `RetryPolicy(2,5)→3`; P2 `JobDispatcher→42`; P13 SemanticIR unchanged; P4 SemanticIR unchanged.

### RECORD-VM-CLOSED — 5 checks
No sockets; no Redis; no ServiceLoop; no clock access; no compatibility or production claims.

### RECORD-VM-GAP — 5 checks
Gap packet: `rack_response_vm_construction` and `jobreceipt_vm_construction` in `closed_by_p1`;
`implementation_finding = zero_new_vm_code_required`; `rack_p14_covered` and `sidekiq_p5_covered` true;
nested records and field access in `still_open`.

---

## 7. Fixtures Used (No New Fixtures Required)

| Fixture | Role |
|---|---|
| `igniter-view-engine/fixtures/rack_core/typed_response_record_checking.ig` | RackResponse VM proof (P13 fixture) |
| `igniter-view-engine/fixtures/sidekiq_core/jobreceipt_schema.ig` | JobReceipt VM proof (P4 fixture) |
| `igniter-view-engine/fixtures/rack_core/multi_contract_caller.ig` | P9 regression baseline |
| `igniter-view-engine/fixtures/sidekiq_core/retry_policy.ig` | P3 regression baseline |
| `igniter-view-engine/fixtures/sidekiq_core/job_dispatch_table.ig` | P2 regression baseline |

No new fixtures were required. P13 and P4 fixtures proved VM behavior directly.

---

## 8. Shared Proof Coverage

**Rack P14** (from LAB-RACK-P13 gap packet) and **Sidekiq P5** (from LAB-SIDEKIQ-P4
gap packet) both recommended VM record construction as the next step. LAB-RECORD-VM-P1
serves as a single shared proof covering both recommendations.

| Gap from | Recommendation | Covered by P1? |
|---|---|---|
| LAB-RACK-P13 | P14: VM record construction + field-order serialization | ✅ Yes |
| LAB-SIDEKIQ-P4 | P5: Execute ReceiptJob end-to-end through VM | ✅ Yes |

No separate LAB-RACK-P14 or LAB-SIDEKIQ-P5 cards are needed for this surface.

---

## 9. Gap Packet

```ruby
GAP_PACKET = {
  proof:        'lab-record-vm-p1-construction-and-serialization',
  version:      'v0',
  implementation_finding: 'zero_new_vm_code_required',
  closed_by_p1: %w[
    rack_response_vm_construction
    jobreceipt_vm_construction
    deterministic_alphabetical_field_serialization
    tier1_dispatched_record_output_preserved
    tier2_dispatched_record_output_preserved
  ],
  v0_policy: {
    field_order: 'alphabetical_btreemap',
    value_types_supported: %w[Integer String Bool],
    nested_record_fields: 'not_yet_proven',
    vm_authority: 'lab_only_no_runtime_gate'
  },
  still_open: %w[
    nested_record_types_as_field_values
    field_access_from_dispatched_record_output
    record_field_access_opcode
    multi_output_callee
    enum_status_type
  ],
  rack_p14_covered: true,
  sidekiq_p5_covered: true,
  sidekiq_compatibility: 'permanently_closed',
  rack_compatibility: 'permanently_closed',
  p2_recommendation: 'Nested record field access — prove OP_FIELD_ACCESS or equivalent on a record returned from call_contract'
}
```

---

## 10. Artifacts

| File | Role |
|---|---|
| `igniter-view-engine/proofs/verify_record_vm_construction.rb` | Proof — 43/43 |
| `lab-docs/lang/lab-record-vm-construction-and-serialization-proof-v0.md` | This document |
| `.agents/work/cards/lang/LAB-RECORD-VM-P1.md` | Card — CLOSED/PROVED |

No new fixtures needed. No VM or compiler code changes.

---

**Boundary:** Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim.
No canon grammar change. No production runtime authority. No public API stability.
`call_contract` is lab-only.
