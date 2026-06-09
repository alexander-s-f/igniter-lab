# LAB-RACK-P12: Typed Response Single-Output Dispatch

**Track:** `lab-rack-typed-response-single-output-dispatch-proof-v0`
**Card:** LAB-RACK-P12
**Status:** CLOSED / PROVED
**Date:** 2026-06-09
**Authority:** lab-only — no canon claim, no stable surface

---

## Background

P11 proved that the TypeChecker resolves literal `call_contract("Name", ...)`
to the callee's declared single output type using a module contract registry
(`build_contract_registry`). The output type was resolved from the callee's
`output_decls[0].type_annotation`, so any named type could be resolved —
including user-defined record types like `RackResponse`.

P12 proves that this resolution works end-to-end for a Rack-like handler pattern:
handlers declare a structured response type, dispatchers call them by literal name,
and the TypeChecker resolves the dispatcher compute node to the structured type
rather than opaque `Unknown`.

---

## What was proved

### RackResponse type

```igniter
type RackResponse {
  status: Integer,
  body: String
}
```

Minimal structured response value. Headers are deferred — Map/Collection
semantics for header pairs require stronger type support (P13 work item).

### Handler contracts

Three handler contracts each take `method: String` + `path: String` and
return `response : RackResponse`:

```igniter
pure contract GetRootHandler {
  input  method : String
  input  path   : String
  compute status   = 200
  compute body_val = "OK"
  compute response = { status: status, body: body_val }
  output response : RackResponse
}
```

The `{ status: ..., body: ... }` RecordLiteral expression is typed as `Unknown`
by the TypeChecker (P12 added `Expr::RecordLiteral` support — returns Unknown;
field exprs still typed for dep collection). The OUTPUT DECLARATION drives the
module contract registry entry; the TypeChecker reads `output_decls[0].type_annotation`
(not the inferred compute type) when building `ContractRegistryEntry`.

### Dispatcher contracts (P11 Tier 1)

```igniter
pure contract StaticGetDispatcher {
  input  method : String
  input  path   : String
  compute response = call_contract("GetRootHandler", method, path)
  output response : RackResponse
}
```

P11 Tier 1 resolution: `"GetRootHandler"` is a literal string callee. The
TypeChecker looks up `GetRootHandler` in the module contract registry, finds
`single_output_type = RackResponse`, and resolves the `response` compute node
type to `RackResponse`. The Unknown-compat rule (P9) still applies for the
output check since declared annotation is `RackResponse` and inferred is
`RackResponse` — they match.

### Dynamic dispatcher (P11 Tier 2)

```igniter
pure contract DynamicDispatcher {
  input  handler_name : String
  ...
  compute response = call_contract(handler_name, method, path)
  output response : RackResponse
}
```

`handler_name` is a variable (Ref), not a literal string. Tier 2 path: compute
node type stays `Unknown`. Output declared as `RackResponse`. Unknown-compat
rule permits this (Unknown ≠ RackResponse but actual=Unknown skips the check).

---

## Semantic IR results

| Contract | `response` compute type | Path |
|---|---|---|
| `GetRootHandler` | `Unknown` | RecordLiteral — nominal type matching deferred |
| `NotFoundHandler` | `Unknown` | RecordLiteral |
| `MethodNotAllowedHandler` | `Unknown` | RecordLiteral |
| `StaticGetDispatcher` | `RackResponse` | P11 Tier 1 literal callee resolution |
| `StaticNotFoundDispatcher` | `RackResponse` | P11 Tier 1 |
| `DynamicDispatcher` | `Unknown` | P11 Tier 2 dynamic callee |

All 6 contracts declare `output response : RackResponse` — visible in
`contract_ir.outputs[0].type.name = "RackResponse"`.

---

## RecordLiteral TypeChecker support (P12 compiler change)

Before P12, `Expr::RecordLiteral { fields }` fell through to the catch-all arm
in `infer_expr`, emitting `OOF-TY0: Unsupported expression kind: record_literal`.

P12 added:

```rust
Expr::RecordLiteral { fields } => {
    // LAB-RACK-P12: RecordLiteral type inference.
    // Returns Unknown; field exprs typed for dep collection.
    // Declared output annotation drives the module contract registry.
    let mut deps = Vec::new();
    for expr in fields.values() {
        let typed = self.infer_expr(
            expr, symbol_types, olap_env, type_shapes,
            type_errors, type_warnings, node_name, functions,
            contract_registry, current_contract_name,
        );
        deps.extend(typed.deps);
    }
    TypedExpression {
        resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
        deps,
    }
}
```

Field expressions are fully typed (deps collected correctly for data-flow).
The compute node type is `Unknown` — nominal record type matching (structural →
named) is the P13 gap.

---

## Fail-closed cases (P12 preserves P11 Tier 1 guards)

| Case | Behavior |
|---|---|
| Literal callee not in module | OOF-TY0: unknown callee |
| Literal callee with arity mismatch | OOF-TY0: arity mismatch |
| Literal callee self-recursion | OOF-TY0: self-recursion closed in v0 |
| Dynamic (Tier 2) callee to unknown contract | Compiles OK; VM fail-closed at runtime |

---

## Design questions answered

**Q: Can call_contract("Handler", ...) resolve to RackResponse rather than Unknown?**
YES — P11 Tier 1 reads `output_decls[0].type_annotation` from the registry entry.
Even though the handler's RecordLiteral compute node is Unknown, the declared output
annotation is RackResponse, and that's what the registry stores.

**Q: Does RecordLiteral construction need nominal type checking?**
Not for P12 (TypeChecker proof). The gap (structural → named) is acknowledged.
For correctness, future work (P13) could verify that `{ status: ..., body: ... }`
matches the declared `RackResponse` field schema at compile time.

**Q: Does this apply to Sidekiq JobReceipt (P3a)?**
YES — `type JobReceipt { job_id: String, status: String, error: String }` follows
the exact same pattern. A `pure contract EnqueueJob` with `output receipt : JobReceipt`
would resolve to `JobReceipt` in a dispatcher via P11 Tier 1.

**Q: Is VM record construction verified in P12?**
NO. P12 is a TypeChecker-only proof. The runtime serialization and field-order
semantics of record-valued outputs are a P13+ work item.

**Q: Are headers deferred?**
YES. `RackResponse { status, body }` — no `headers` field. Map/Collection
semantics for header pairs require stronger type support.

---

## Open (post-P12)

- **Nominal record type checking**: structural `{ status: ..., body: ... }` vs
  declared `RackResponse` — field name/type matching at compile time (P13)
- **VM record construction**: runtime record serialization and field semantics
- **Multi-output callee**: returns Unknown; dedicated card if needed
- **Headers**: Map/Collection semantics; deferred past P12
- **Dynamic dispatch to record-returning contract**: Tier 2 stays Unknown; no
  TypeChecker resolution without literal callee name

---

## Closed surfaces

```
CLOSED: igniter-lang canon grammar
CLOSED: ContractRef type semantics (lab-only static name lookup, not ContractRef)
CLOSED: multi-output callee dispatch (deferred, not blocked)
CLOSED: non-pure callee dispatch (OOF-TY0 in Tier 1)
CLOSED: real TCP/socket usage
CLOSED: ServiceLoop / HTTP server / middleware
CLOSED: Rack-compatibility claim (no such claim made)
CLOSED: stable/public surface claim
CLOSED: runtime execution, igc run, .igbin, certification, portability
NOTE:   call_contract is lab-only; no canon claim, no stable API surface
```

---

## Files

- `igniter-compiler/src/typechecker.rs` — `Expr::RecordLiteral` arm added to `infer_expr`
- `igniter-view-engine/fixtures/rack_core/typed_response_dispatch.ig` — P12 fixture
- `igniter-view-engine/proofs/verify_p12_typed_response_dispatch.rb` — 45-check proof

## Depends on

- LAB-RACK-P9 (call_contract dispatch + Unknown output compat rule)
- LAB-RACK-P10 (design preflight — registry pattern, literal/dynamic distinction)
- LAB-RACK-P11 (TypeChecker module contract registry, two-tier policy)
