# LAB-RACK-P6: TypeChecker Equality and Comparison Alignment

**Track:** lab-rack-typechecker-equality-and-comparison-alignment-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 32/32 PASS
**Depends on:** LAB-RACK-P5, LAB-STR-CORE-P2

---

## Summary

Closes the TypeChecker `==` and `<` operator gap found in LAB-RACK-P4/P5.
Adds bounded support for equality and comparison in primitive types, enabling
idiomatic route/method dispatch without `starts_with` workarounds.

**Single file changed:** `igniter-compiler/src/typechecker.rs` — two new arms
added to the `operator_type` match:
- `"=="` arm: accepts compatible primitive pairs, rejects others with OOF-TY0
- `"<"` arm: Integer-only, rejects String/Text/Bool with OOF-TY0

No VM change needed. No emitter change needed. The VM's `binary_op` handler
already dispatches on `"=="` and `"<"` operator strings.

---

## Gap Closed

| Gap (from P4/P5) | Status |
|-----------------|--------|
| TypeChecker OOF-TY0 on `==` for all types | ✅ CLOSED — compatible primitive pairs accepted |
| TypeChecker OOF-TY0 on `<` for all types  | ✅ CLOSED — Integer-only accepted |

---

## TypeChecker Change Detail

### `==` operator (new arm in `operator_type`)

Compatible pairs (no OOF-TY0 emitted):
- `(String, String)` — used for `path == "/"`, `method == "GET"`, etc.
- `(Text, Text)`, `(String, Text)`, `(Text, String)` — Text/String cross-compat
- `(Integer, Integer)` — numeric equality
- `(Bool, Bool)` — boolean equality
- Any pair involving `Unknown` — pass-through (avoids spurious cascading errors)

Incompatible pairs (OOF-TY0: "Type mismatch for ==: cannot compare X with Y"):
- `(String, Integer)`, `(Integer, String)`, etc.

Emitted resolved_op: `"stdlib.primitive.eq"` (carried through but not used in
SemanticIR — the raw `"=="` op string passes through from parser to VM).

### `<` operator (new arm in `operator_type`)

Accepted:
- `(Integer, Integer)` — `n < 100`, `byte_length(path) < 10`, etc.

Rejected (OOF-TY0: "Type mismatch for <: expected Integer on both sides"):
- `(String, String)`, `(Text, Text)`, `(Bool, *)` — all rejected

Emitted resolved_op: `"stdlib.integer.lt"` (carried through but not used in IR).

---

## VM Compatibility

The VM's `binary_op` handler (vm.rs ~line 1870) already handles:
```rust
"==" => Ok(Value::Bool(left_val == right_val))  // Rust Value equality
"<"  => { /* Integer, Float, Decimal, String */ }
```

The emitter passes `BinaryOp { op: "==", .. }` through unchanged as
`{"kind": "binary_op", "op": "==", ...}`. The VM reads the `"op"` field.
**No VM change was needed for P6.**

---

## New Fixture: `route_dispatch_exact.ig`

Demonstrates idiomatic equality-based route dispatch:

```igniter
module Rack.P6.RouteDispatchExact

pure contract RouteDispatchExact {
  input method : String
  input path   : String

  compute status_code =
    if path == "/" {
      200
    } else {
      if starts_with(path, "/articles/") {
        if method == "GET" { 200 } else { 405 }
      } else {
        if path == "/articles" {
          if method == "POST" { 201 } else { 405 }
        } else {
          404
        }
      }
    }

  output status_code : Integer
}
```

Route table (same 5 routes as P5, now using idiomatic `==`):

| Method | Path            | Expected | VM Result |
|--------|-----------------|----------|-----------|
| GET    | /               | 200      | 200 ✅    |
| GET    | /articles/42    | 200      | 200 ✅    |
| POST   | /articles       | 201      | 201 ✅    |
| GET    | /missing        | 404      | 404 ✅    |
| POST   | /articles/42    | 405      | 405 ✅    |

---

## Negative Fixtures

Two fixtures prove TypeChecker rejection:

| Fixture | Op | Expected | Actual |
|---------|----|----------|--------|
| `eq_type_mismatch.ig` | `path == 42` (String==Integer) | OOF-TY0 | ✅ OOF-TY0 "cannot compare String with Integer" |
| `lt_string_reject.ig` | `s < t` (String<String) | OOF-TY0 | ✅ OOF-TY0 "expected Integer on both sides" |

---

## `<` Proof: `lt_integer_valid.ig`

```igniter
pure contract LtIntegerValid {
  input n : Integer
  compute is_small = n < 100
  output is_small : Bool
}
```

| n   | Expected | VM Result |
|-----|----------|-----------|
| 50  | true     | true ✅   |
| 100 | false    | false ✅  |
| 200 | false    | false ✅  |

---

## Proof Matrix Summary

| Section | Checks | Description |
|---------|--------|-------------|
| P6-TC   | 10     | TypeChecker accepts/rejects == and < correctly; source confirmed |
| P6-IR   | 3      | SemanticIR contains binary_op with op==\"==\" nodes |
| P6-VM   | 5      | 5 exact routes execute on VM with correct status codes |
| P6-LT   | 3      | Integer < Integer executes; boundary case correct |
| P6-REG  | 5      | P5 route_dispatch.ig and path_param_extract.ig still green |
| P6-CLOSED | 4    | No socket/network/igc-run/stable-api surfaces |
| P6-GAP  | 2      | Gap packet: eq/lt closed, vm_entrypoint + ContractRef still open |
| **Total** | **32** | **32/32 PASS** |

---

## Still Open

| Gap | Status | Path |
|-----|--------|------|
| VM entrypoint selector | open | contracts[0] hardcoded in compiler.rs:32 |
| ContractRef runtime dispatch | open | OP_CALL user-contract fallthrough in vm.rs |
| Middleware execution | deferred | No before/after hook model |
| Query/glob routing | deferred | Not in scope |

---

## Authority

- **Lab-only** — no canon grammar edits, no canon API surface
- **Closed:** ContractRef runtime dispatch, VM entrypoint selection, middleware,
  HTTP parser, network I/O, stable API, public runtime, production claims
- The TypeChecker change is lab-local. It does not imply canon operator semantics.

---

## Next Route

**LAB-RACK-P7**: VM entrypoint selector (unblock multi-contract dispatch) —
allow the VM to select a named contract from a multi-contract igapp,
enabling a dispatcher contract to invoke route-specific handler contracts.

Alternatively: ContractRef alignment (enable OP_CALL for user-defined contract
invocations), which is a prerequisite for dynamic dispatch.
