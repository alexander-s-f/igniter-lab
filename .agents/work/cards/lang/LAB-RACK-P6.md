# LAB-RACK-P6

**Card ID:** LAB-RACK-P6
**Category:** lang / web
**Track:** lab-rack-typechecker-equality-and-comparison-alignment-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 32/32 PASS

---

## D — Deliverables

- `igniter-compiler/src/typechecker.rs` — **2 new operator arms added** (`==` and `<`)
- `igniter-view-engine/fixtures/rack_core/route_dispatch_exact.ig` — exact route fixture using `==`
- `igniter-view-engine/fixtures/rack_core/lt_integer_valid.ig` — Integer < Integer positive fixture
- `igniter-view-engine/fixtures/rack_core/eq_type_mismatch.ig` — String==Integer rejection fixture
- `igniter-view-engine/fixtures/rack_core/lt_string_reject.ig` — String<String rejection fixture
- `igniter-view-engine/proofs/verify_p6_typechecker_eq_lt.rb` — **main deliverable, 32/32 PASS**
- `lab-docs/lang/lab-rack-typechecker-equality-and-comparison-alignment-v0.md`
- `.agents/work/cards/lang/LAB-RACK-P6.md` (this receipt)

---

## S — Summary

Closed the TypeChecker `==` and `<` operator gap (OOF-TY0 "Unsupported operator")
found in LAB-RACK-P4/P5. The fix is a two-arm addition to `operator_type` in
`igniter-compiler/src/typechecker.rs`. No VM change, no emitter change.

**TypeChecker change:**
```rust
// LAB-RACK-P6: equality for primitive types
"==" => {
    // accepts (String,String),(Text,Text),(String,Text),(Text,String),
    //         (Integer,Integer),(Bool,Bool),(Unknown,_),(_,Unknown)
    // rejects incompatible pairs with OOF-TY0
    ("stdlib.primitive.eq", Bool)
}
// LAB-RACK-P6: less-than for Integer only
"<" => {
    // accepts (Integer,Integer) only
    // rejects String/Text/Bool with OOF-TY0
    ("stdlib.integer.lt", Bool)
}
```

**VM compatibility:** Already handled. The VM's `binary_op` handler dispatches
`"=="` using Rust `Value` equality, and `"<"` for Integer/Float/Decimal/String.
No VM modification was needed.

**New fixture `route_dispatch_exact.ig`** uses idiomatic `path == "/"` and
`method == "GET"` instead of `starts_with` workarounds:

| Route | Expected | VM Result |
|-------|----------|-----------|
| GET / | 200 | 200 ✅ |
| GET /articles/42 | 200 | 200 ✅ |
| POST /articles | 201 | 201 ✅ |
| GET /missing | 404 | 404 ✅ |
| POST /articles/42 | 405 | 405 ✅ |

**`<` operator** proven via `lt_integer_valid.ig`: `n < 100` → `50→true`, `100→false`, `200→false`.

---

## Proof Matrix: 32/32 PASS

| Section | Checks | Coverage |
|---------|--------|----------|
| P6-TC   | 10     | TypeChecker accepts == for String/Integer/Bool; rejects incompatible; `<` Integer-only; source confirmed |
| P6-IR   | 3      | SemanticIR binary_op with op=="==" present in exact fixture |
| P6-VM   | 5      | 5 exact-route VM executions correct |
| P6-LT   | 3      | `<` VM executes; boundary n=100 correct |
| P6-REG  | 5      | P5 fixtures still compile and execute correctly |
| P6-CLOSED | 4    | No socket/network/igc-run/stable-api surfaces |
| P6-GAP  | 2      | Gap packet fields and closure confirmed |

---

## Gap Closed

| Gap | Status |
|-----|--------|
| TypeChecker `==` for String/Integer/Bool | ✅ CLOSED |
| TypeChecker `<` for Integer | ✅ CLOSED |
| TypeChecker `==` rejects incompatible types | ✅ CLOSED (OOF-TY0 confirmed) |
| TypeChecker `<` rejects String/Bool | ✅ CLOSED (OOF-TY0 confirmed) |

## Still Open

| Gap | Path |
|-----|------|
| VM entrypoint selector (contracts[0] hardcoded) | VM extension card |
| ContractRef runtime dispatch (OP_CALL fallthrough) | VM extension card |
| Middleware execution | Deferred |
| Query/glob routing | Deferred |

---

## Next Route

**LAB-RACK-P7**: VM entrypoint selector — unblock multi-contract dispatch.
Allow the VM to select a named contract from a multi-contract igapp,
enabling dispatcher contracts to call route-specific handlers.
