# LAB-RACK-P7: VM Named Entrypoint Selector

**Track:** lab-rack-vm-named-entrypoint-selector-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 28/28 PASS
**Depends on:** LAB-RACK-P6 (TypeChecker == and <), LAB-RACK-P3 (ContractRef gap confirmed)

---

## Summary

Closes the VM entrypoint selector gap identified in LAB-RACK-P3. The VM
previously always executed `contracts[0]` from a multi-contract igapp; there
was no mechanism to select a different contract by name.

**Gap closed:** `--entry <contract_name>` CLI flag added to the `run` subcommand.
A named contract is found by searching the SemanticIR `contracts` array by
`contract_name` field. Unknown entries fail closed with a descriptive error
listing available contract names.

**Default behavior preserved:** `compile()` still calls `compile_entry(jv, None)`,
which selects `contracts[0]` — fully backward-compatible.

---

## Gap Closed

| Gap (from P3) | Status |
|--------------|--------|
| VM always executes contracts[0] — no named selection | ✅ CLOSED |

---

## Implementation Detail

### `igniter-vm/src/compiler.rs`

New method alongside the existing `compile`:

```rust
pub fn compile_entry(
    &mut self,
    contract_jv: &serde_json::Value,
    entry_name: Option<&str>,
) -> Result<Vec<Instruction>, String>
```

Contract selection logic (replaces the hardcoded `contracts_arr.get(0)`):

```rust
let contract_obj = if let Some(contracts_arr) = contract_jv.get("contracts").and_then(|c| c.as_array()) {
    if let Some(name) = entry_name {
        // LAB-RACK-P7: search by contract_name (SemanticIR field)
        contracts_arr.iter()
            .find(|c| {
                c.get("contract_name").and_then(|n| n.as_str()) == Some(name)
                    || c.get("name").and_then(|n| n.as_str()) == Some(name)
            })
            .ok_or_else(|| {
                let available: Vec<&str> = contracts_arr.iter()
                    .filter_map(|c| c.get("contract_name").and_then(|n| n.as_str())
                        .or_else(|| c.get("name").and_then(|n| n.as_str())))
                    .collect();
                format!(
                    "Entry '{}' not found in igapp (available: [{}])",
                    name,
                    if available.is_empty() { "none".to_string() } else { available.join(", ") }
                )
            })?
    } else {
        contracts_arr.get(0).ok_or("No contracts found in semantic_ir_program")?
    }
} else {
    contract_jv
};
```

The original `compile(&mut self, contract_jv)` is unchanged; it delegates:
```rust
pub fn compile(&mut self, contract_jv: &serde_json::Value) -> Result<Vec<Instruction>, String> {
    self.compile_entry(contract_jv, None)
}
```

### `igniter-vm/src/main.rs`

New flag added to the `run` subcommand argument parser:

```
--entry <contract_name>    Select named contract from multi-contract igapp
--entrypoint <name>        Alias for --entry
-e <name>                  Short form
```

The `entry_name: Option<String>` is passed as `entry_name.as_deref()` to
`compiler.compile_entry()`. The modifier reading was also updated to read
from the selected contract (not always contracts[0]).

### Error format (fail-closed)

When `--entry UnknownName` is used with `--json`:
```json
{
  "status": "error",
  "error": "Compilation Error: Entry 'UnknownName' not found in igapp (available: [Double, IsSmall, RouteGate])"
}
```

Exit code: 1. No silent fallback to contracts[0].

---

## New Fixture: `multi_contract_entrypoints.ig`

Three distinct pure contracts in one module, each with different signatures:

| # | Contract | Inputs | Output | Purpose |
|---|----------|--------|--------|---------|
| 0 | `Double` | `n: Integer` | `result: Integer` | Default selection test; n + n |
| 1 | `IsSmall` | `n: Integer` | `result: Bool` | Second-position selection; uses `<` (P6) |
| 2 | `RouteGate` | `method: String`, `path: String` | `status_code: Integer` | Third-position; uses `==` (P6) |

The `<` and `==` operators in IsSmall and RouteGate verify that P6 operators work
correctly after P7 entry selection — no regression.

---

## Entrypoint Selection Table

| CLI Flag | Contract Selected | Input | Expected Output | Verified |
|----------|-----------------|-------|-----------------|---------|
| (none) | `Double` (contracts[0]) | `n=5` | `result=10` | ✅ |
| `--entry Double` | `Double` | `n=21` | `result=42` | ✅ |
| `--entry IsSmall` | `IsSmall` | `n=50` | `result=true` | ✅ |
| `--entry IsSmall` | `IsSmall` | `n=150` | `result=false` | ✅ |
| `--entry RouteGate` | `RouteGate` | `GET /` | `status_code=200` | ✅ |
| `--entry RouteGate` | `RouteGate` | `GET /other` | `status_code=404` | ✅ |
| `--entry RouteGate` | `RouteGate` | `POST /other` | `status_code=405` | ✅ |
| `--entry UnknownContract` | — | any | `status=error, exit=1` | ✅ |
| `--entry Middleware` | — | any | `status=error, lists RouteGate` | ✅ |

---

## Proof Matrix Summary

| Section | Checks | Description |
|---------|--------|-------------|
| P7-COMPILE | 3 | Fixture compiles; 3 contracts in SemanticIR; names correct |
| P7-SOURCE | 3 | `compile_entry` defined; LAB-RACK-P7 annotation; `--entry` in main.rs |
| P7-DEFAULT | 2 | No flag → contracts[0] (Double); result=10 |
| P7-ENTRY | 7 | Double/IsSmall/RouteGate each selected + correct output |
| P7-FAIL | 3 | Unknown entries fail closed; error lists available names |
| P7-REG | 4 | P6 route_dispatch_exact.ig still green (4 routes) |
| P7-CLOSED | 4 | No socket/network/compiler-run/API-claim surfaces |
| P7-GAP | 2 | Gap packet: entrypoint closed; ContractRef still open |
| **Total** | **28** | **28/28 PASS** |

---

## Still Open

| Gap | Status | Path |
|-----|--------|------|
| ContractRef runtime dispatch | open | OP_CALL for user contracts in vm.rs |
| Middleware execution | deferred | No before/after hook model |
| Query/glob routing | deferred | Not in scope |

---

## Authority

- **Lab-only** — no canon grammar edits, no stable API surface
- **Closed:** ContractRef runtime dispatch, middleware, HTTP parser, network I/O,
  stable API, public runtime, production claims
- The `--entry` flag is a VM debugging aid. It does not imply a stable CLI
  contract or runtime dispatch protocol.

---

## Next Route

**LAB-RACK-P8**: ContractRef alignment — enable OP_CALL for user-defined contract
invocations so a dispatcher contract can call route-specific handler contracts
at runtime (the second pillar of multi-contract dispatch).
