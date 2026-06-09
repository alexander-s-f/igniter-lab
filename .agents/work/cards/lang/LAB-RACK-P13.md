# LAB-RACK-P13: Nominal Record TypeChecking for Response Values

**Status:** CLOSED / PROVED
**Track:** lab-rack-nominal-record-typechecking-for-response-values-v0
**Date:** 2026-06-09
**Result:** 47/47 PASS

---

## Summary

Implemented nominal record type checking for RecordLiteral expressions in declared
output contexts. A `RecordLiteral` assigned to an output declared as `RackResponse`
(or any named record type in `type_shapes`) is now validated at compile time and its
compute node type is upgraded from `Unknown` to the named type.

Closes the gap documented in P12: "RecordLiteral returns Unknown; nominal type matching
deferred."

Builds on:
- P11: module contract registry, two-tier dispatch policy
- P12: RecordLiteral support, `type RackResponse { ... }`, handler/dispatcher pattern

---

## Key implementation

### TypeChecker changes (typechecker.rs)

**Pre-scan** (`output_type_hints`): maps compute-node-name → expected named record type
for outputs whose type annotation appears in `type_shapes`. Built once before the
declaration loop in `typecheck_contract`.

**Post-infer check in compute phase**: after `infer_expr` returns Unknown for a
RecordLiteral, calls `check_record_literal_shape` if a hint exists. Upgrades compute
node type on success.

**`check_record_literal_shape`**: validates
1. Missing required fields → OOF-TY0
2. Unexpected extra fields → OOF-TY0
3. Field value types (Ref/Literal only) → OOF-TY0 on mismatch

**`infer_field_expr_type`**: Ref → symbol_types lookup, Literal → type_tag, complex → None (Unknown-compat skips check).

### No signature changes to infer_expr

The 29 `infer_expr` call sites are unchanged. P13 works via a post-infer pass in the
compute phase, using the pre-scanned `output_type_hints` map.

---

## Semantic IR changes

**Before P13** (P12 state):
- Handler RecordLiteral compute nodes: `Unknown`
- Dispatcher (Tier 1) compute nodes: `RackResponse` (via P11 registry)

**After P13**:
- Handler RecordLiteral compute nodes: `RackResponse` (P13 upgrade when valid)
- Dispatcher (Tier 1): `RackResponse` (P11 — unchanged)
- Dynamic (Tier 2): `Unknown` (unchanged)

---

## What was proved (47 checks)

```
P13-COMPILE  (5)  — fixture compiles; 5 contracts; no diagnostics
P13-TYPES    (8)  — OkHandler/Direct/Complex → RackResponse (P13);
                    StaticDispatcher → RackResponse (P11 Tier 1);
                    DynamicDispatcher → Unknown (Tier 2);
                    P12 handler nodes now RackResponse; P12 dispatcher unchanged
P13-FIELD    (4)  — field base types (Integer/String); inline literals ok;
                    BinaryOp field → skipped type check; RackResponse still upgrages
P13-FC      (16)  — missing status/body → OOF-TY0 (field named, type named);
                    extra field → OOF-TY0; wrong status/body type → OOF-TY0;
                    uncontextualized → Unknown (no error)
P13-COMPAT   (4)  — P12/P11/P9 regressions green
P13-CLOSED   (5)  — no sockets, no CR-type semantics, no compat/prod claim
P13-GAP      (5)  — complex-expr Unknown-compat acknowledged; VM deferred;
                    headers deferred; Sidekiq JobReceipt path confirmed; auth present
```

---

## Gap packet

| Gap | Status |
|---|---|
| RecordLiteral → Unknown | **CLOSED by P13** |
| Complex field expressions | Still Unknown-compat (BinaryOp, fn calls) |
| VM record construction | Still deferred — P14 candidate |
| Headers / Map type | Still deferred |
| Multi-output callee | Still deferred |
| Nested record types as field values | Not yet addressed |

**Sidekiq JobReceipt**: YES — same path applies. `type JobReceipt { job_id, status, error }` output
would trigger `check_record_literal_shape` against the JobReceipt schema. No P13-specific code needed.

**P14 recommendation**: VM record construction + field-order serialization. Prerequisite: at least one
contract with RecordLiteral output is executed end-to-end through the VM.

---

## Authority

lab-only — no canon claim, no stable surface.
`call_contract` is lab-only. No Rack-compatibility claim. Record checking is in the
lab Rust compiler; not in igniter-lang canon grammar.

---

## Files

- `igniter-compiler/src/typechecker.rs` — `output_type_hints`, post-infer check,
  `check_record_literal_shape`, `infer_field_expr_type`
- `igniter-view-engine/fixtures/rack_core/typed_response_record_checking.ig`
- `igniter-view-engine/proofs/verify_p13_nominal_record_typechecking.rb`
- `igniter-view-engine/proofs/verify_p12_typed_response_dispatch.rb` (updated)
- `lab-docs/lang/lab-rack-nominal-record-typechecking-v0.md`
