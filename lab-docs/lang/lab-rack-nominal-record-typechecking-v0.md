# LAB-RACK-P13: Nominal Record TypeChecking for Response Values

**Track:** `lab-rack-nominal-record-typechecking-for-response-values-v0`
**Card:** LAB-RACK-P13
**Status:** CLOSED / PROVED
**Date:** 2026-06-09
**Authority:** lab-only — no canon claim, no stable surface

---

## Background

P12 proved that literal `call_contract("Handler", ...)` dispatchers resolve their
compute node type to `RackResponse` using the P11 module contract registry. Handler
contracts themselves still had compute node type `Unknown` for their RecordLiteral
expressions — the nominal record type matching (structural → named) was left as an
open gap.

P13 closes that gap: a RecordLiteral assigned to an output declared as a named record
type is now validated against the declared field schema at compile time, and the compute
node type is upgraded from `Unknown` to the named record type.

---

## What was implemented

### Pre-scan: `output_type_hints`

In `typecheck_contract`, before the declaration loop, a pre-scan builds:

```rust
let output_type_hints: HashMap<String, String> = classified.declarations.iter()
    .filter(|d| d.kind == "output")
    .filter_map(|d| {
        let ann = d.type_annotation.as_ref()?;
        let type_name = self.type_name(&self.type_ir(ann));
        if local_type_shapes.contains_key(&type_name) {
            Some((d.name.clone(), type_name))
        } else { None }
    })
    .collect();
```

Only output annotations whose type name appears in `local_type_shapes` (i.e., named
user-declared record types) create hints. Primitive types (Integer, String, Bool, etc.)
are excluded — they're not in `type_shapes`.

### Post-infer check in compute phase

After `infer_expr` returns Unknown for a RecordLiteral, the compute phase checks:

```rust
if self.type_name(&typed_expr.resolved_type) == "Unknown" {
    if let Some(Expr::RecordLiteral { fields }) = decl.expr.as_ref() {
        if let Some(expected_type_name) = output_type_hints.get(&decl.name) {
            if let Some(shape) = local_type_shapes.get(expected_type_name.as_str()).cloned() {
                let errors_before = type_errors.len();
                self.check_record_literal_shape(fields, &shape, expected_type_name,
                    &decl.name, &symbol_types, &mut type_errors);
                if type_errors.len() == errors_before {
                    // Upgrade: Unknown → concrete named type
                    typed_expr.resolved_type = self.type_ir(
                        &serde_json::Value::String(expected_type_name.clone())
                    );
                }
            }
        }
    }
}
```

If all checks pass, the compute node type is upgraded from `Unknown` to `RackResponse`
(or whatever the named output type is). If any check fails, specific OOF-TY0 errors are
emitted for the field violations; the compute node stays `Unknown` (the Unknown-compat
rule at the output-check phase still applies, avoiding a duplicate generic error).

### `check_record_literal_shape`

Validates three invariants:

1. **Missing required fields**: every field name in the expected schema must appear in the literal.
2. **Unexpected fields**: every field in the literal must appear in the schema.
3. **Field value types**: for Ref and Literal field expressions, the inferred type must match the schema type (Unknown-compat: mismatched only if actual is neither Unknown nor correct).

### `infer_field_expr_type`

```rust
fn infer_field_expr_type(&self, expr: &Expr, symbol_types: &...) -> Option<String> {
    match expr {
        Expr::Ref { name } => symbol_types.get(name).map(|t| self.type_name(t)),
        Expr::Literal { type_tag, .. } => Some(type_tag.clone()),
        _ => None,  // Complex exprs → Unknown-compat: field type check skipped
    }
}
```

Complex field expressions (BinaryOp, function calls, etc.) return `None` — the field
type check is skipped in Unknown-compat style. This is intentionally permissive in v0.

---

## Semantic IR results

### P13 fixture (`typed_response_record_checking.ig`)

| Contract | `response` compute type | Path |
|---|---|---|
| `OkHandler` | `RackResponse` | RecordLiteral with ref fields — P13 upgrade |
| `DirectLiteralHandler` | `RackResponse` | RecordLiteral with literal fields — P13 upgrade |
| `ComplexFieldHandler` | `RackResponse` | RecordLiteral with BinaryOp field — type check skipped, upgrade |
| `StaticDispatcherP13` | `RackResponse` | P11 Tier 1 literal callee — unchanged |
| `DynamicDispatcherP13` | `Unknown` | P11 Tier 2 dynamic callee — unchanged |

### P12 fixture (`typed_response_dispatch.ig`) — updated by P13

| Contract | `response` compute type | Before P13 | After P13 |
|---|---|---|---|
| `GetRootHandler` | `RackResponse` | `Unknown` | upgraded |
| `NotFoundHandler` | `RackResponse` | `Unknown` | upgraded |
| `MethodNotAllowedHandler` | `RackResponse` | `Unknown` | upgraded |
| `StaticGetDispatcher` | `RackResponse` | `RackResponse` | unchanged |
| `StaticNotFoundDispatcher` | `RackResponse` | `RackResponse` | unchanged |
| `DynamicDispatcher` | `Unknown` | `Unknown` | unchanged |

---

## Fail-closed cases

| Case | Behavior |
|---|---|
| Missing required field | OOF-TY0: "required field '{}' is missing from literal at node '{}'" |
| Unexpected extra field | OOF-TY0: "unexpected field '{}' in literal at node '{}'" |
| Wrong field value type (Ref/Literal) | OOF-TY0: "field '{}' expects {}, got {} at node '{}'" |
| Complex field expression (BinaryOp etc.) | Field type check skipped (Unknown-compat) |
| Uncontextualized RecordLiteral (no named-type output) | Stays Unknown; no error |
| Dynamic call_contract (Tier 2) | Stays Unknown; no error (no RecordLiteral) |

---

## Design notes

### Uncontextualized RecordLiterals

A RecordLiteral with no `output_type_hints` entry (because the output annotation is a
primitive type like `Integer`, or there is no output with this name) stays `Unknown`.
This preserves Unknown-compat semantics for constructs not yet typed via this path.

### Why post-infer, not in infer_expr

`infer_expr` doesn't know the output context (the expected type). Adding an
`expected_type` parameter would require updating all ~29 call sites. The post-infer
approach in the compute phase avoids signature changes while having access to both
the RecordLiteral expression and the `output_type_hints` map.

### Ordering guarantee

The pre-scan reads output declarations; the compute phase processes compute declarations.
In Igniter source order, inputs come first, then computes, then outputs. All compute
nodes that contribute to an output will have been processed (and stored in `symbol_types`)
before `check_record_literal_shape` is called. This ensures Ref lookups work correctly.

---

## Sidekiq JobReceipt applicability

YES — the same path works for any named record type. A `type JobReceipt { job_id: String, status: String, error: String }` output annotation would:
1. Appear in `type_shapes` (built from `classified.type_declarations`)
2. Generate an entry in `output_type_hints` for the compute node name
3. Trigger `check_record_literal_shape` against the `JobReceipt` schema

No P13-specific code is needed for JobReceipt. This is the generic record-checking path.

---

## Still open (post-P13)

- **VM record construction**: runtime field serialization/deserialization — P14 candidate
- **Complex field expressions**: BinaryOp, function call fields — Unknown-compat skips check
- **Nested record types**: `type Address { city: String }` as a field type — deferred
- **Headers**: Map/Collection semantics for `RackResponse.headers` — deferred
- **Multi-output callee dispatch**: Unknown; dedicated card if needed

---

## Closed surfaces (carried forward)

```
CLOSED: igniter-lang canon grammar
CLOSED: ContractRef type semantics
CLOSED: multi-output callee dispatch (deferred, not blocked)
CLOSED: real TCP/socket usage
CLOSED: ServiceLoop / HTTP server / middleware
CLOSED: Rack-compatibility claim
CLOSED: stable/public surface claim
CLOSED: runtime execution, igc run, .igbin, certification
NOTE:   call_contract is lab-only; no canon claim, no stable API surface
```

---

## Files

- `igniter-compiler/src/typechecker.rs` — `output_type_hints` pre-scan, post-infer check,
  `check_record_literal_shape`, `infer_field_expr_type`
- `igniter-view-engine/fixtures/rack_core/typed_response_record_checking.ig` — P13 fixture
- `igniter-view-engine/proofs/verify_p13_nominal_record_typechecking.rb` — 47-check proof
- `igniter-view-engine/proofs/verify_p12_typed_response_dispatch.rb` — updated (P13 gap closed)

## Depends on

- LAB-RACK-P11 (module contract registry, two-tier dispatch)
- LAB-RACK-P12 (RecordLiteral support, RackResponse type, handler/dispatcher contracts)
