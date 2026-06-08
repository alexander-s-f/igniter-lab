# LAB-RACK-P7

**Card ID:** LAB-RACK-P7
**Category:** lang / web
**Track:** lab-rack-vm-named-entrypoint-selector-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 28/28 PASS

---

## D — Deliverables

- `igniter-vm/src/compiler.rs` — **`compile_entry` method added** (named entrypoint selection)
- `igniter-vm/src/main.rs` — **`--entry` / `--entrypoint` / `-e` flag added** to `run` subcommand
- `igniter-view-engine/fixtures/rack_core/multi_contract_entrypoints.ig` — 3-contract fixture
- `igniter-view-engine/proofs/verify_p7_vm_entrypoint_selector.rb` — **main deliverable, 28/28 PASS**
- `lab-docs/lang/lab-rack-vm-named-entrypoint-selector-proof-v0.md`
- `.agents/work/cards/lang/LAB-RACK-P7.md` (this receipt)

---

## S — Summary

Closes the VM entrypoint selector gap (P3 finding: VM always executed
`contracts[0]`). The `--entry <contract_name>` flag selects a named contract
from a multi-contract igapp. Unknown entries fail closed with a descriptive
error listing available contract names. Default behavior (no flag →
`contracts[0]`) is preserved.

**Key interface:**
```
igniter-vm run --contract multi.igapp --inputs inputs.json --entry Double
igniter-vm run --contract multi.igapp --inputs inputs.json --entry IsSmall
igniter-vm run --contract multi.igapp --inputs inputs.json --entry RouteGate
```

**Fail-closed error (JSON mode):**
```json
{"status": "error", "error": "Compilation Error: Entry 'X' not found in igapp (available: [Double, IsSmall, RouteGate])"}
```

**Implementation:** `Compiler::compile_entry(jv, Option<&str>)` in compiler.rs
searches the `contracts` array by `contract_name` SemanticIR field. The
existing `compile(jv)` remains unchanged — it calls `compile_entry(jv, None)`.

---

## Proof Matrix: 28/28 PASS

| Section | Checks | Coverage |
|---------|--------|----------|
| P7-COMPILE | 3 | Fixture compiles; 3 contracts with correct names |
| P7-SOURCE | 3 | `compile_entry` defined; LAB-RACK-P7 annotation; `--entry` in main.rs |
| P7-DEFAULT | 2 | No flag → contracts[0] = Double; n=5 → 10 |
| P7-ENTRY | 7 | Double (n=21→42), IsSmall (n=50→true, n=150→false), RouteGate (GET/→200, GET/other→404, POST/other→405) |
| P7-FAIL | 3 | Unknown entry fails closed; error lists available names |
| P7-REG | 4 | P6 route_dispatch_exact.ig still green |
| P7-CLOSED | 4 | No socket/network/compiler-run/API-claim surfaces |
| P7-GAP | 2 | Gap packet: entrypoint closed; ContractRef still open |

---

## Gap Closed

| Gap | Status |
|-----|--------|
| VM entrypoint selector (contracts[0] hardcoded) | ✅ CLOSED |
| Unknown entrypoint fails closed | ✅ CLOSED |
| Default behavior (no --entry) unchanged | ✅ CONFIRMED |

## Still Open

| Gap | Path |
|-----|------|
| ContractRef runtime dispatch (OP_CALL user contracts) | ContractRef alignment card |
| Middleware execution | Deferred |
| Query/glob routing | Deferred |

---

## Next Route

**LAB-RACK-P8**: ContractRef alignment — enable OP_CALL for user-defined
contract invocations so a dispatcher contract can call route-specific handlers
at runtime. P7 (entrypoint selection) is the prerequisite P8 needs.
