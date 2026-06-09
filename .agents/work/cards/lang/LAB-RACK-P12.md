# LAB-RACK-P12: Typed Response Single-Output Dispatch

**Status:** CLOSED / PROVED
**Track:** lab-rack-typed-response-single-output-dispatch-proof-v0
**Date:** 2026-06-09
**Result:** 45/45 PASS

---

## Summary

Proved that Rack-like handler contracts can return a structured single-output
response value (`RackResponse`) through literal `call_contract("Handler", ...)`,
using the P11 TypeChecker module contract registry to resolve the handler output
type statically — `RackResponse`, not `Unknown`.

Builds on:
- P9: call_contract dispatch + Unknown output compat rule
- P10: design preflight (registry pattern, literal/dynamic distinction)
- P11: TypeChecker module contract registry, two-tier policy

---

## Key design

### RackResponse type

```igniter
type RackResponse { status: Integer, body: String }
```

Headers deferred. Map/Collection semantics for header pairs require stronger
type support (P13 work item).

### Two-tier resolution in P12 context

| Tier | Callee | compute type | Output declared |
|---|---|---|---|
| Tier 1 — literal | `"GetRootHandler"` | `RackResponse` | `RackResponse` |
| Tier 2 — dynamic | `handler_name` (var) | `Unknown` | `RackResponse` |

Handler bodies use RecordLiteral `{ status: ..., body: ... }` — compute type
is `Unknown` (nominal type matching deferred). The P11 registry reads the
DECLARED output annotation (`output_decls[0].type_annotation`), so the
dispatcher sees `RackResponse` even though the handler's compute node is Unknown.

### RecordLiteral compiler fix (P12)

Added `Expr::RecordLiteral { fields }` arm to `infer_expr` in `typechecker.rs`.
Returns Unknown type; field exprs fully typed for dep collection.
Before P12: `{ status: 200, body: "OK" }` emitted `OOF-TY0: Unsupported expression kind: record_literal`.

---

## What was proved (45 checks)

```
P12-COMPILE  (5)  — fixture compiles; 6 contracts; no diagnostics
P12-STATIC   (8)  — StaticGetDispatcher/StaticNotFoundDispatcher → RackResponse;
                    handler response nodes → Unknown (RecordLiteral);
                    status/body_val nodes → Integer/String; record_literal expr kind
P12-TYPE     (4)  — RackResponse annotation in output declarations; all 6 contracts
P12-TIER2    (4)  — DynamicDispatcher.response → Unknown; no OOF-TY0; Tier 1 vs Tier 2 contrast
P12-FC       (8)  — unknown/arity/self-rec literal callees → OOF-TY0;
                    correct inline dispatch → SimpleResponse (not Unknown)
P12-REG      (6)  — P11 fixture (CallerDouble→Integer) green; P9 fixture + SelfRecurseDyn green
P12-CLOSED   (5)  — no sockets, no CR-type semantics, no compat/prod-runtime claim
P12-GAP      (5)  — RecordLiteral→Unknown gap acknowledged; VM construction deferred;
                    headers deferred; single-output only; authority disclaimer present
```

---

## Open gaps (post-P12)

- **Nominal record type checking** (P13): verify `{ status, body }` matches `RackResponse` fields at compile time
- **VM record construction**: runtime serialization, field-order semantics — TypeChecker proof only
- **Headers**: `Map[String, String]` type or similar — deferred
- **Multi-output callee**: Unknown; deferred
- **Dynamic dispatch resolution**: Tier 2 stays Unknown; only Tier 1 (literal) resolves

---

## Authority

lab-only — no canon claim, no stable surface.
`call_contract` is explicitly lab-only. No Rack-compatibility claim.
RecordLiteral support is in the lab Rust compiler; not in igniter-lang canon.

---

## Files

- `igniter-compiler/src/typechecker.rs` — `Expr::RecordLiteral` arm
- `igniter-view-engine/fixtures/rack_core/typed_response_dispatch.ig` — P12 fixture
- `igniter-view-engine/proofs/verify_p12_typed_response_dispatch.rb` — 45-check proof
- `lab-docs/lang/lab-rack-typed-response-dispatch-v0.md` — design doc
