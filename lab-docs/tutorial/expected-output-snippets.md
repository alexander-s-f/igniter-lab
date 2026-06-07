# Expected Output Snippets

This reference document compiles concrete, compact success signals and artifact shapes produced by the tutorial commands.

---

## Compact Success Signals

### 1. Compiler Result (`L1` and `L3`)
When compiling fixtures with the `igniter-compiler` CLI, the terminal prints a high-level JSON receipt. A successful compilation contains `"status": "ok"` and shows stages compiled successfully:

```json
{
  "status": "ok",
  "contracts": ["Add", "UseAdd"],
  "stages": {
    "parse": "ok",
    "classify": "ok",
    "typecheck": "ok",
    "emit": "ok",
    "assemble": "ok"
  }
}
```

### 2. VM Candidate Proof (`L2`)
Running the candidate virtual machine proof writes a telemetry result packet to `igniter-vm/out/vm_candidate_proof/summary.json` containing:

```json
{
  "kind": "vm_candidate_proof_summary",
  "overall": "PASS",
  "checks_total": 15,
  "checks_pass": 15,
  "evidence_class": "proof_local_vm_candidate_evidence"
}
```

### 3. Capability Passport Integration (`L4`)
Running the loader capability proof runner compiles test assets and runs security checks (`IOVM_1` to `IOVM_17`). Success is signaled by:

```text
===========================================================================
 Checks: 17 PASS / 0 FAIL
 Verification Completed. Status: PASS
===========================================================================
```

### 4. View SSR / GUI Scene Resolution (`L5`)
Running visual layout solving reports green statuses in terminal output:

```text
ALL PROOFS PASSED! View engine P1 is fully verified.
```
```text
ALL CHECKS PASS! (207/207)
```

---

## Core Artifact Filenames

When compilation finishes, the output `.igapp` directory contains the following JSON files:

| File | Role |
| --- | --- |
| `manifest.json` | General bundle identifier and list of contracts. |
| `semantic_ir_program.json` | Parsed and type-checked intermediate AST block representation. |
| `passport.json` | Security declaration file specifying permissions and bindings. |
| `form_table.json` | Compiled custom syntax mapping table. |
| `form_resolution_trace.json` | Diagnostic trace logging type-directed dispatch actions. |

---

## Ignored Output Policy

The workspace enforces a strict ignore policy. The following directories are configured in `.gitignore` and **must never** be checked into git:

- `out/` (e.g. `igniter-compiler/out/`, `igniter-vm/out/`, `igniter-view-engine/out/`)
- `target/` (compiled Rust cargo artifacts)
- `node_modules/` and `.svelte-kit/` (IDE web libraries)
