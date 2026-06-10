# LAB-VMTRACE-P1 — Agent Return Packet

Record-only VM execution trace substrate: every executed instruction is captured as a trace event and cross-referenced back through `bytecode_map.json → node_id → source_span`, emitted as a deterministic `vm_trace.json` sidecar.

---

## Status

**Complete.** P1 proof 66/66. LAB-SRCMAP-P2 proof 61/61 (still green).

---

## Changed Files

### VM (`igniter-lab/igniter-vm/src/`)

- **`vm.rs`** — Additive changes only:
  - Added `trace_collector: Option<Arc<Mutex<Vec<serde_json::Value>>>>` to `VM` struct; `None` by default in `VM::new()`
  - Added `take_trace_events(&self) -> Vec<serde_json::Value>` — drains collector via `std::mem::take`; returns `[]` when `None`
  - Added `trace_seq: usize` counter (incremented only in post-match block)
  - Captures `trace_pre_ip`, `trace_pre_depth`, `trace_pre_opcode` at top of while loop (trivial cost; guarded)
  - Post-match recording block: appends JSON event for all non-returning instructions; uses `opcode_mnemonic()`
  - `OP_RET` inline recording: records before `return Ok(val)` (only early-return instruction)

- **`main.rs`** — Added:
  - `trace` subcommand dispatch (before banner; stdout is clean JSON)
  - `async fn handle_vm_trace(igapp_path, entry, inputs_path)`:
    - Calls `handle_bytecode_map` to regenerate `bytecode_map.json`
    - Builds `offset_lookup: HashMap<usize, (node_id, sir_path, source_span)>`
    - Compiles entry contract; loads inputs; computes `inputs_digest`
    - Sets `vm.trace_collector = Some(...)`; calls `execute_with_grants()`
    - Drains via `take_trace_events()`; enriches events from `offset_lookup`
    - Computes `result_digest`; writes `vm_trace.json`; updates `manifest.json`
    - Prints JSON summary: `{status, igapp, vm_trace_file, contract_name, events_total, result_status}`

### Fixtures (`igniter-view-engine/fixtures/source_map/`)

- **`inputs_nested.json`** — `{"table_name":"users","schema_name":"public"}` for `BuildQueryPlan`
- **`inputs_variant.json`** — `{"current":{"__arm":"Active","__variant":"Status"},"message":"hello"}` for `CheckStatus`

### Proof Runners (`igniter-view-engine/proofs/`)

- **`verify_lab_vmtrace_p1.rb`** — 66-check proof runner across 10 sections.

### Lab Doc

- **`igniter-lab/lab-docs/ide/lab-vm-record-only-execution-trace-with-source-links-v0.md`**

---

## Proof Results

```
VMTRACE-P1: 66/66 PASS    0 FAIL

VMTRACE-COMPILE:      Compiler + VM binaries exist; 3 fixtures compile ok; bytecode-map steps succeed.
VMTRACE-RUN:          trace subcommand produces valid summary JSON; vm_trace.json created for all 3 fixtures.
VMTRACE-SCHEMA:       schema_version="vm-trace-v0"; seq 0-based monotonic; required + enrichment keys present; 16-char hex digests.
VMTRACE-OFFSETS:      Every ip_before valid offset in bytecode_map; events count = instruction count; last=RET; first=0.
VMTRACE-SOURCE:       Tagged events have non-null sir_path + source_span; start_line > 0; node_id matches bytecode_map at same offset.
VMTRACE-DETERMINISM:  Re-run produces identical events, opcodes, result_digest, inputs_digest.
VMTRACE-NONSEMANTIC:  Untraced run yields same result; result_digest matches sha256 of untraced value for all 3 fixtures.
VMTRACE-COVERAGE:     f1 contains RET, STORE_REG, MUL, SUB, GET_FIELD; f2/f3 contains PUSH_LIT.
VMTRACE-ERROR:        Empty inputs → status=error; events=[]; deterministic across re-runs.
VMTRACE-CLOSED:       No breakpoint/watch/step keys; OP_UNSUPPORTED=0x99; Value enum unchanged.
```

---

## Design Decisions

**opt-in via `Option<Arc<Mutex<...>>>` (not a flag):** An `Option` is cheaper than a boolean flag — `None` compiles to a single branch-not-taken and zero allocation. The `Arc<Mutex<...>>` wrapper allows the collector to be set before execution and drained after, without changing `execute_with_grants`'s return type.

**`take_trace_events()` via `std::mem::take`:** Drains the collector without cloning and leaves it empty for reuse. Does not change the `execute_with_grants` signature.

**OP_RET is the only special case:** It calls `return Ok(val)` inside the `match`, bypassing the post-match recording block. Inline recording before the `return` handles it. All other error paths (`return Err(...)`) skip recording — correct since execution has failed.

**Enrichment is post-execution in `handle_vm_trace`:** The `vm.rs` execution loop has no knowledge of `bytecode_map.json` or source spans. Enrichment is applied by `handle_vm_trace` after `take_trace_events()` returns the raw events. This keeps the VM semantics layer clean.

**Two stdout lines:** `handle_bytecode_map` prints its own JSON summary (line 1); `handle_vm_trace` prints the trace summary (line 2). Proof runners parse the last non-empty line.

---

## Closed Surfaces (Confirmed Untouched)

- `VM::execute_with_grants()` semantics (opcode behavior, stack, temporal context)
- `Instruction { opcode: u8, args: Vec<Value> }` struct
- `Value` enum
- Opcode constants (OP_UNSUPPORTED = 0x99, no new opcodes)
- Breakpoints / stepping / pause / resume / watch expressions
- IDE UI / Tauri / Svelte / public debugger API
- Ruby canon (`igniter-lang`)
- Language grammar
- Source-level operational semantics
