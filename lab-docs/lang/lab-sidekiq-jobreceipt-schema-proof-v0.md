# LAB-SIDEKIQ-P4: JobReceipt Schema Proof — v0

**Track:** `lab-sidekiq-jobreceipt-schema-proof-v0`
**Status:** CLOSED / PROVED — 46/46 PASS
**Date:** 2026-06-09
**Depends on:** LAB-SIDEKIQ-P2, LAB-SIDEKIQ-P3, LAB-RACK-P11, LAB-RACK-P13

---

## 1. Goal

Prove that a Sidekiq-like job execution surface can return a structured single-output
`JobReceipt` record using the same nominal record typechecking path proven in
LAB-RACK-P13, replacing raw Integer retry/job outputs with a typed receipt validated
at compile time — while keeping dispatch synchronous, pure, lab-only, and without
opening queues, Redis, workers, schedulers, effect-callee dispatch, VM record
construction authority, Sidekiq compatibility, or canon/stable API claims.

---

## 2. Fixture Design

**File:** `igniter-view-engine/fixtures/sidekiq_core/jobreceipt_schema.ig`
**Module:** `Sidekiq.Lab.JobReceipt`

### Type declaration

```igniter
type JobReceipt {
  job_class        : String,
  job_id           : String,
  attempt          : Integer,
  budget_remaining : Integer,
  status           : String
}
```

Five fields. No timestamps, no duration, no retry_at, no scheduled_at, no queue id.
No error object or stack trace. `status` is a String vocabulary in P4 (not an enum).

### Contracts

| Contract | Role | Mechanism | SemanticIR node type |
|---|---|---|---|
| `ReceiptJob` | Minimal pure job with RecordLiteral receipt output | P13 `check_record_literal_shape` | `JobReceipt` (upgraded from Unknown) |
| `ReceiptDispatcher` | Literal `call_contract("ReceiptJob", ...)` | P11 Tier 1 static resolution | `JobReceipt` |
| `DynamicReceiptDispatcher` | Variable `call_contract(handler_name, ...)` | P11 Tier 2 (no upgrade) | `Unknown` |

### ReceiptJob

```igniter
pure contract ReceiptJob {
  input  job_class        : String
  input  job_id           : String
  input  attempt          : Integer
  input  max_attempts     : Integer
  compute budget_remaining = max_attempts - attempt
  compute status_val       = "ok"
  compute receipt = {
    job_class:        job_class,
    job_id:           job_id,
    attempt:          attempt,
    budget_remaining: budget_remaining,
    status:           status_val
  }
  output receipt : JobReceipt
}
```

All 5 fields are ref expressions whose types are statically known:
- `job_class` → input (String) → ref → `String` ✓
- `job_id` → input (String) → ref → `String` ✓
- `attempt` → input (Integer) → ref → `Integer` ✓
- `budget_remaining` → compute (Integer, arithmetic) → ref → `Integer` ✓
- `status_val` → compute (String, literal) → ref → `String` ✓

P13 `check_record_literal_shape` validates all 5 fields and upgrades the `receipt`
compute node from `Unknown` to `JobReceipt`.

### ReceiptDispatcher

```igniter
pure contract ReceiptDispatcher {
  input  job_class    : String
  input  job_id       : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute receipt = call_contract("ReceiptJob", job_class, job_id, attempt, max_attempts)
  output receipt : JobReceipt
}
```

P11 Tier 1: `"ReceiptJob"` is a literal callee string. TypeChecker performs registry
lookup → `ReceiptJob.single_output_type = JobReceipt` → `receipt` compute node is
typed `JobReceipt` at compile time without a RecordLiteral in this contract.

### DynamicReceiptDispatcher

```igniter
pure contract DynamicReceiptDispatcher {
  input  handler_name     : String
  ...
  compute receipt = call_contract(handler_name, job_class, job_id, attempt, max_attempts)
  output receipt : JobReceipt
}
```

P11 Tier 2: `handler_name` is a variable — TypeChecker skips static resolution → `Unknown`.
P13 does NOT upgrade `call_contract` nodes (only `RecordLiteral` nodes). Node stays `Unknown`.
`output receipt : JobReceipt` annotation is Unknown-compat — no compile error.

---

## 3. Mechanism Reuse

| Mechanism | Source | Used in P4 |
|---|---|---|
| `check_record_literal_shape` | P13 TypeChecker | Validates all 5 JobReceipt fields in `ReceiptJob` |
| `output_type_hints` pre-scan | P13 TypeChecker | Maps `receipt → JobReceipt` hint for `ReceiptJob` |
| `build_contract_registry` | P11 TypeChecker | Tier 1 lookup: `"ReceiptJob"` → `JobReceipt` |
| `single_output_type` | P11 registry entry | Propagates `JobReceipt` to `ReceiptDispatcher.receipt` |
| `call_contract` dispatch | P9 VM | Runtime dispatch from `ReceiptDispatcher` |
| P13 Unknown-compat for outputs | P13 TypeChecker | `DynamicReceiptDispatcher` accepted with Unknown compute |

No new compiler or VM code required. P4 is zero-code — existing mechanisms compose
to prove the JobReceipt schema path.

---

## 4. Check Inventory (46/46 PASS)

### SJOB4-COMPILE — 6 checks
Fixture compiles ok; 3 contracts present; no diagnostics; all stages pass;
`ReceiptJob.receipt` → `JobReceipt` (P13); `ReceiptDispatcher.receipt` → `JobReceipt` (P11 Tier 1).

### SJOB4-SOURCE — 5 checks
Fixture source declares `type JobReceipt` with all 5 required fields;
`typechecker.rs` contains `check_record_literal_shape`, `output_type_hints`, `build_contract_registry`.

### SJOB4-TYPES — 6 checks

| Check | Contract | Node | Expected type |
|---|---|---|---|
| TYPES-01 | `ReceiptJob` | `receipt` | `JobReceipt` (P13 upgrade) |
| TYPES-02 | `ReceiptJob` | `budget_remaining` | `Integer` |
| TYPES-03 | `ReceiptJob` | `status_val` | `String` |
| TYPES-04 | `ReceiptDispatcher` | `receipt` | `JobReceipt` (P11 Tier 1) |
| TYPES-05 | `DynamicReceiptDispatcher` | `receipt` | `Unknown` (P11 Tier 2) |
| TYPES-06 | `ReceiptJob` | output `receipt` | `JobReceipt` (SemanticIR outputs array) |

### SJOB4-FC — 14 checks

| Scenario | Error | Evidence |
|---|---|---|
| Missing `status` field | OOF-TY0 | names `JobReceipt` type |
| Extra `queue_name` field | OOF-TY0 | names `queue_name` |
| `job_id` as Integer (should be String) | OOF-TY0 | names `job_id`, mentions `String` |
| `attempt` as String (should be Integer) | OOF-TY0 | names `attempt` |
| `status` as Integer (should be String) | OOF-TY0 | names `status` |
| Unknown literal callee `"GhostReceiptJob"` | OOF-TY0 | mentions `GhostReceiptJob` |

### SJOB4-REG — 5 checks
P3 `retry_policy.ig` compiles; `RetryPolicy(2,5)→3`; `RetrySimulator([1,2,3])→3`;
P2 `job_dispatch_table.ig` compiles; `JobDispatcher(ProcessOrderJob,21)→42`.

### SJOB4-CLOSED — 5 checks
No TCP/UDP socket; no Redis; no ServiceLoop; no clock/time access (OOF-L6 boundary);
no Sidekiq compatibility or production/canon claim.

### SJOB4-GAP — 5 checks
Gap packet: `job_receipt_schema_declaration` in `closed_by_p4`; `vm_record_construction`
and `enum_status_type` in `still_open`; `async_retry` in `still_open`;
`sidekiq_compatibility` is `permanently_closed`.

---

## 5. P11 Tier 1 Propagation of Named Record Types

P11 Tier 1 was originally proven for primitive output types (Integer, Bool). P4 proves
that P11 Tier 1 also propagates **named record types**: when `ReceiptJob`'s single
output type is `JobReceipt`, the `build_contract_registry` stores
`single_output_type = { "name": "JobReceipt", "params": [] }`, and the `call_contract`
callee resolution upgrades the dispatcher's compute node to `JobReceipt`.

This is a direct extension of P11 that requires no code change — the registry stores
`serde_json::Value` for `single_output_type`, which accommodates any named type.

---

## 6. P13 Record Literal Upgrade Path

The P13 `check_record_literal_shape` path is fully generic — driven by `type_shapes`
(populated from `type` declarations) and `output_type_hints` (pre-scan). Any contract
with `output X : SomeNamedType` where `SomeNamedType` is declared in `type_shapes` will
trigger validation of the `RecordLiteral` assigned to `X`. P4 confirms this works for
`JobReceipt` without any P4-specific code.

The `DynamicReceiptDispatcher` check (TYPES-05) confirms that P13 does NOT interfere
with Tier 2 dynamic callee behavior — `call_contract` nodes are not RecordLiterals, so
`check_record_literal_shape` is never invoked for them.

---

## 7. Sidekiq Analogy (Lab Only)

| Sidekiq concept | Lab analog | Notes |
|---|---|---|
| Job receipt / acknowledgement | `JobReceipt` record | Typed; compile-time validated |
| `performed_at` / `enqueued_at` | **CLOSED** | No timestamps in P4 |
| `jid` / job identifier | `job_id: String` | Caller-supplied; no UUID generation |
| `queue` identifier | **CLOSED** | No queue id in P4 |
| `retry_count` | `attempt: Integer` | From `RetryPolicy` context |
| Retries remaining | `budget_remaining: Integer` | Pure arithmetic from P3 |
| `status` / job outcome | `status: String` | Vocabulary only; no enum |
| Redis job receipt storage | **PERMANENTLY CLOSED** | No storage authority |

---

## 8. Gap Packet

```ruby
GAP_PACKET = {
  proof:        'lab-sidekiq-p4-jobreceipt-schema',
  version:      'v0',
  closed_by_p4: %w[
    job_receipt_schema_declaration
    record_literal_typechecking_for_receipt
    tier1_literal_callee_resolves_to_jobreceipt
    tier2_dynamic_callee_stays_unknown
    all_5_field_shape_violations_fail_closed
  ],
  v0_policy: {
    status_is_string_vocabulary: 'enforced',
    no_timestamps_or_queue_ids: 'enforced',
    typechecker_semir_only: 'enforced'
  },
  still_open: %w[
    vm_record_construction
    enum_status_type
    async_retry
    queue_storage
    effect_dispatch
    multi_output_callee
    nested_record_types
    job_receipt_field_order_serialization
  ],
  sidekiq_compatibility: 'permanently_closed',
  p5_recommendation: 'VM record construction — execute a contract with JobReceipt output end-to-end through the VM; prove field values are accessible at runtime'
}
```

### P5 Recommendation

**VM record construction** — execute `ReceiptJob` through the VM end-to-end. Prove that
the `JobReceipt` fields are accessible at runtime (field-by-field access or full record
output). This is the P14 recommendation from LAB-RACK-P13 applied to the Sidekiq path.

Prerequisite: at least one contract with RecordLiteral output must be executed end-to-end
through the VM. This has not yet been opened; see LAB-RACK-P13 gap packet.

---

## 9. Artifacts

| File | Role |
|---|---|
| `igniter-view-engine/fixtures/sidekiq_core/jobreceipt_schema.ig` | Fixture — type decl + 3 contracts |
| `igniter-view-engine/proofs/verify_sidekiq_p4_jobreceipt_schema.rb` | Proof — 46/46 |
| `lab-docs/lang/lab-sidekiq-jobreceipt-schema-proof-v0.md` | This document |
| `.agents/work/cards/lang/LAB-SIDEKIQ-P4.md` | Card — CLOSED/PROVED |

---

**Boundary:** Lab-only. No Sidekiq compatibility claim. No canon grammar change. No
production runtime. TypeChecker/SemanticIR proof only; VM record construction deferred.
`call_contract` is lab-only with no public API stability.
