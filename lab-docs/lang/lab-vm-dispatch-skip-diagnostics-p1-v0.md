# LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1 Proof

**Date:** 2026-06-15  
**Card:** `LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1`  
**Runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_vm_dispatch_skip_diagnostics_p1.rb`  
**Result:** CLOSED - 90/90 PASS  
**Authority:** lab VM diagnostic behavior only

## Verdict

VM dispatch table construction is now fail-closed. If an emitted contract cannot
build a dispatch entry, the VM refuses to load/run the partial dispatch table
instead of silently skipping the contract.

This closes the false-green class where an app could appear green because a
callee contract failed bytecode compilation during dispatch table construction
and was omitted from `call_contract` runtime coverage.

## Implementation

Changed:

```text
igniter-lab/igniter-vm/src/main.rs
```

The VM still attempts to build every dispatch entry. Successful entries are kept
in the local dispatch table, while failures are accumulated as structured
diagnostics. If any failure exists, VM load stops before inputs are read and
before evaluator execution begins.

JSON mode returns a non-zero process status with:

```json
{
  "status": "error",
  "error": "Dispatch table construction failed for N contract(s)",
  "dispatch_built": 1,
  "dispatch_skipped": [
    {
      "contract_name": "BadDispatch",
      "error": "Unsupported AST expression kind: dispatch_skip_probe"
    }
  ]
}
```

Non-JSON mode prints the skipped contract names and underlying compile errors,
including the count of dispatch entries that did build.

## Proof Matrix

| Section | Topic | Checks |
|---|---|---:|
| A | Implementation shape | 12 |
| B | Gates and synthetic fixture shape | 14 |
| C | JSON failure diagnostics | 14 |
| D | Non-JSON failure diagnostics | 10 |
| E | Fully buildable synthetic app | 10 |
| F | Real app VM regressions | 18 |
| G | Closure artifacts | 12 |
| **Total** | | **90** |

## Evidence

The negative fixture is a synthetic `.igapp` with two emitted contracts:

- `RootOk`, a valid entry contract.
- `BadDispatch`, a contract whose expression kind is intentionally unbuildable.

The JSON VM run exits non-zero and includes `dispatch_skipped[0].contract_name =
"BadDispatch"` plus the underlying compile error. No `result`, `observations`,
or success status is emitted.

The text-mode VM run also exits non-zero and prints:

- dispatch table construction failure,
- refusal to perform a partial VM load,
- successful dispatch-entry count,
- skipped contract name,
- underlying compile error.

The positive synthetic `.igapp` still runs cross-contract dispatch through
`call_contract("GoodCallee")` and returns `42`.

## App Regressions

The proof recompiles and runs these app entrypoints through the VM with empty
inputs:

| App | Entrypoint | Result |
|---|---|---|
| `batch_importer` | `RunImport` | success |
| `lead_router` | `RunAccept` | success |
| `call_router` | `RunConnectedMatched` | success |

`batch_importer` remains green because `LAB-VM-EVALAST-MATCH-P1` is closed.
`lead_router` and `call_router` remain green after the earlier if-expression
dispatch fix.

## Closed Surfaces

- No typechecker changes.
- No compiler or app source changes.
- No dynamic dispatch relaxation.
- No Unknown permissiveness.
- No new language syntax.
- No canon language authority claim.
- No old Ruby framework surface used as language authority.

## Command

```text
cd /Users/alex/dev/projects/igniter-workspace
ruby igniter-lab/igniter-view-engine/proofs/verify_lab_vm_dispatch_skip_diagnostics_p1.rb
RESULT: 90/90 PASS
```
