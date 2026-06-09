# LAB-RECORD-VM-P3: Nested Record Field Values Proof — v0

**Track:** `lab-record-vm-nested-record-field-values-proof-v0`
**Status:** CLOSED / PROVED — 49/49 PASS
**Date:** 2026-06-09
**Depends on:** LAB-RECORD-VM-P2, LAB-RECORD-VM-P1, LAB-RACK-P13, LAB-SIDEKIQ-P4

---

## 1. Goal

Prove that a record field can hold another record, and that chained field access
expressions like `outer.inner.field` work end-to-end through typechecking, SemanticIR,
bytecode compilation, and VM execution — without adding new opcodes, changing the
typechecker, or altering the canon grammar.

---

## 2. Finding: One Targeted Compiler Line

**A single change in one file was required.** The typechecker already handles chained
field access recursively. The VM already constructs and stores nested records correctly.
The only gap was the bytecode compiler's `"field_access"` branch: it returned an error
when the object was not a `"ref"` (i.e., when the object was itself a `"field_access"`
node for chaining).

| Component | Change |
|---|---|
| `igniter-vm/src/compiler.rs` | Replace `Err("Unsupported object type...")` with `compile_expr(object)? + OP_GET_FIELD(field)` in the `"field_access"` branch |

| Component | Change required? |
|---|---|
| `igniter-vm/src/instructions.rs` | **None** — `OP_GET_FIELD (0x22)` from P2 reused unchanged |
| `igniter-vm/src/vm.rs` | **None** — `OP_GET_FIELD` handler already handles nested records |
| `igniter-compiler/src/typechecker.rs` | **None** — already handles chaining recursively |

All changes are inside `igniter-lab/igniter-vm/` — lab-only, no canon change.

---

## 3. Explicit Answers to Card Questions

| Question | Answer |
|---|---|
| Nested record type as field value proved? | **YES** — `HeaderInfo` field in `ResponseEnvelope`; `JobMeta` field in `JobEnvelope` |
| `outer.inner.field` works end-to-end? | **YES** — `envelope.headers.content_type → "text/plain"`, `envelope.meta.priority → 5` |
| Typechecker handles chained access recursively? | **YES** — no changes needed; chain resolution already worked |
| VM record construction handles nested records? | **YES** — no changes needed; `OP_PUSH_RECORD` stores `Value::Record` as field value |
| Nested records serialize deterministically? | **YES** — `BTreeMap` sorts keys at every nesting level |
| Missing inner field safe? | **YES** — OOF-P1 at compile time naming the inner record type |
| Direct local nested access on Unknown-typed records? | **FAIL-CLOSED** — OOF-P1 `Unknown.content_type` at compile time |
| Non-record intermediate chain (`status.something`) safe? | **YES** — OOF-P1 `Integer.something` at compile time |
| Tier 2 + chained field access safe? | **YES** — OOF-P1 `Unknown.headers` at compile time |
| Implementation required new code? | **Minimal** — one line in compiler.rs |
| Creates canon/runtime/public authority? | **NO** |

---

## 4. Mechanism Detail

### Pre-P3 State: Compiler Dead End

For `compute content_type = envelope.headers.content_type`, the SIR emits:

```json
{
  "kind": "field_access",
  "field": "content_type",
  "object": {
    "kind": "field_access",
    "field": "headers",
    "object": { "kind": "ref", "name": "envelope" }
  }
}
```

The `"field_access"` branch in `compiler.rs` handled the `"ref"` case (load register +
`OP_GET_FIELD`) but fell through to an error for any other object kind:

```rust
// OLD: compiler.rs "field_access" branch (BEFORE P3)
if let Some(&reg_idx) = self.compute_node_registers.get(name) {
    self.emit(OP_LOAD_REG, vec![Value::Integer(reg_idx)]);
    self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(field))]);
    return Ok(());
}
// ... other cases ...
// ← REACHED HERE for chained access: object is another "field_access"
return Err(format!("Unsupported object type in field_access: {:?}", object));
```

### P3 Fix: One Recursive Call

The fallback now recursively compiles the object expression (whatever kind it is),
then appends `OP_GET_FIELD`:

```rust
// NEW: compiler.rs "field_access" branch (AFTER P3)
// LAB-RECORD-VM-P3: chained field access — object is itself an expression
// (e.g. another field_access). Recursively compile the object onto the stack,
// then extract the named field with OP_GET_FIELD.
// Handles: envelope.headers.content_type, receipt.meta.priority, etc.
self.compile_expr(object)?;
self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(field))]);
return Ok(());
```

This produces the correct bytecode sequence for `envelope.headers.content_type`:
1. `OP_LOAD_REG(envelope_idx)` — push the `ResponseEnvelope` record
2. `OP_GET_FIELD("headers")` — pop envelope, push `HeaderInfo` sub-record
3. `OP_GET_FIELD("content_type")` — pop HeaderInfo, push `"text/plain"`

### Why Typechecker Needed No Changes

The typechecker's `Expr::FieldAccess` arm calls `infer_expr(object)` recursively,
then looks up the result type in `type_shapes`:

```
infer_expr(envelope.headers.content_type):
  1. infer_expr(envelope.headers):
       infer_expr(envelope) → ResponseEnvelope     (Tier 1 propagation from P11)
       type_shapes["ResponseEnvelope"]["headers"]  → HeaderInfo
     result: HeaderInfo
  2. type_shapes["HeaderInfo"]["content_type"]     → String
  result: String
```

No OOF-P1 fires for intermediate steps because each resolved type (`HeaderInfo`, `String`)
is a known named type — not `Unknown`.

### The `Unknown` Wall

The `Unknown` wall appears when the outer record is NOT from a Tier 1 call_contract:

```igniter
-- This fails: headers is Unknown (local record literal, no type annotation)
compute headers = { content_type: "text/plain", cache_control: "no-cache" }
compute ct = headers.content_type  -- OOF-P1: Unknown.content_type
```

For `Unknown.content_type`: `type_shapes["Unknown"]["content_type"] = None → Unknown → OOF-P1`.

The fail-closed boundary is consistent with P2: Tier 1 literal callees give named types;
Tier 2 variable callees and anonymous local records give `Unknown`.

---

## 5. Observed VM Outputs

### EnvelopeBuilder (Rack — nested record construction)

Input: `{ "method": "GET" }`

```json
{
  "body": "OK",
  "headers": {
    "cache_control": "no-cache",
    "content_type": "text/plain"
  },
  "status": 200
}
```

Keys sorted alphabetically at both levels (`BTreeMap` guarantee).

### ContentTypeReader (Rack — chained field extraction)

Input: `{ "method": "GET" }` → `"text/plain"`

### CacheControlReader (Rack — chained field extraction)

Input: `{ "method": "GET" }` → `"no-cache"`

### JobEnvelopeBuilder (Sidekiq — nested record construction with arithmetic)

Input: `{ "job_class": "WorkerJob", "attempt": 2, "max_attempts": 5 }`

```json
{
  "budget_remaining": 3,
  "job_class": "WorkerJob",
  "meta": {
    "priority": 5,
    "queue": "default"
  },
  "status": "ok"
}
```

`budget_remaining = 5 - 2 = 3` computed before record construction.

### PriorityReader (Sidekiq — chained Integer field extraction)

Input: `{ "job_class": "WorkerJob", "attempt": 2, "max_attempts": 5 }` → `5`

### QueueReader (Sidekiq — chained String field extraction)

Input: `{ "job_class": "WorkerJob", "attempt": 2, "max_attempts": 5 }` → `"default"`

---

## 6. Fail-Closed Observations

| Scenario | Compile result | Diagnostic |
|---|---|---|
| Direct local nested access (`headers.content_type`, `headers` = Unknown) | `oof` | OOF-P1: `Unknown.content_type` |
| Missing inner field (`envelope.headers.no_such_inner`) | `oof` | OOF-P1: `HeaderInfo.no_such_inner` |
| Non-record intermediate chain (`envelope.status.something`, `status` = Integer) | `oof` | OOF-P1: `Integer.something` |
| Tier 2 callee + chained access (`call_contract(var,...).headers.content_type`) | `oof` | OOF-P1: `Unknown.headers` |

---

## 7. Check Inventory

| Section | Count | Description |
|---|---|---|
| NESTED-RECORD-COMPILE | 5 | Compile status; typechecker resolves chained field types |
| NESTED-RECORD-SIR | 4 | Tier 1 propagation; output type annotations; intermediate node types |
| NESTED-RECORD-VM | 10 | Nested record construction; scalar and nested fields; BTreeMap ordering |
| NESTED-RECORD-DISPATCH | 8 | Chained field access: 4 contracts × (success + value) |
| NESTED-RECORD-FAIL-CLOSED | 7 | 4 inline fail-closed fixtures; 3 diagnostic message checks |
| NESTED-RECORD-REG | 5 | P2/P1/P13/P4 regression baselines |
| NESTED-RECORD-CLOSED | 5 | Closed-surface scan |
| NESTED-RECORD-GAP | 5 | Gap packet; implementation finding; still-open; compat claims |
| **Total** | **49** | |

---

## 8. Gap Packet

```
proof:        lab-record-vm-p3-nested-record-field-values / v0
status:       CLOSED / PROVED — 49/49 PASS

implementation_finding: one_compiler_line_changed

unchanged:
  - instructions.rs: OP_GET_FIELD (0x22) reused from P2, no new opcode
  - vm.rs: OP_GET_FIELD handler unchanged, works for nested Value::Record
  - typechecker.rs: already handles chained access recursively, no changes
  - VM record construction: OP_PUSH_RECORD already handles Value::Record fields

closed_by_p3:
  - rack_nested_record_field_values
  - sidekiq_nested_record_field_values
  - chained_field_access_two_levels
  - chained_field_access_integer_field
  - chained_field_access_string_field
  - direct_local_nested_access_fail_closed
  - missing_inner_field_fail_closed
  - non_record_intermediate_chain_fail_closed
  - tier2_chained_field_access_fail_closed
  - deterministic_nested_record_serialization

still_open:
  - three_level_chained_field_access (a.b.c.d)
  - tier2_dynamic_callee_chained_field_access_runtime
  - local_record_literal_type_annotation (output: annotation enables local access)
  - enum_status_type
  - array_field_types
  - multi_output_callee
```

---

## 9. Boundary

Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim. No canon grammar
change. No production runtime authority. No public API stability.

`call_contract` is lab-only. `OP_GET_FIELD` is lab-only VM instrumentation with no
public bytecode stability. The compiler change is inside `igniter-lab/igniter-vm/`,
not in `igniter-lang` or `igniter-compiler` canon code.
