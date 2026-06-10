# Lab: VM Record-Only Execution Trace With Source Links v0

**Track:** LAB-VMTRACE-P1  
**Status:** Complete  
**Authority:** lab_only — not canon, not production

---

## Purpose

This document records the design and implementation decisions for building a record-only VM execution trace substrate. The output is a deterministic `vm_trace.json` artifact that records every executed instruction offset, cross-referenced back through `bytecode_map.json → node_id → source_span`.

This is the third step on the debugger track:
`LAB-SRCMAP-P1 → LAB-SRCMAP-P2 → LAB-VMTRACE-P1 → LAB-IDE-STEP-P1 → LAB-TEXTBOOK-P1`

---

## Decision Questions

**Q1. Is record-only trace feasible without changing VM semantics?**

Yes. The trace collector is an opt-in field (`trace_collector: Option<Arc<Mutex<Vec<serde_json::Value>>>>`) on the `VM` struct. When `None` (the default), the `if let Some(ref collector) = self.trace_collector` guard is a zero-cost branch — the collector is never allocated and no recording happens. When `Some`, the collector receives one `push` per instruction after the match block. The execution path, opcode dispatch, and stack manipulation are identical in both modes. The `Instruction` struct and `Value` enum are untouched.

**Q2. How does the trace_collector avoid overhead when tracing is disabled?**

`trace_collector: Option<...>` is `None` by default. The two recording sites — pre-instruction capture of `(trace_pre_ip, trace_pre_depth, trace_pre_opcode)` and post-match `push` — are both guarded by `if let Some(ref collector) = self.trace_collector`. When `None`, Rust compiles the guard to a single branch-not-taken instruction. The three `trace_pre_*` variables are computed unconditionally but are trivially cheap register copies (ip is `usize`, depth is `stack.len()`, opcode is a `u8` copy). A production run with `trace_collector = None` incurs no allocation, no locking, and no JSON serialization.

**Q3. How is OP_RET handled? (The only early-return instruction)**

`OP_RET` calls `return Ok(val)` from inside the `match` block, bypassing the post-match recording code. It is the only instruction with this property. The solution: inline recording immediately before the `return`:

```rust
OP_RET => {
    let val = stack.pop().ok_or("Stack empty on RET instruction")?;
    if let Some(ref collector) = self.trace_collector {
        collector.lock().unwrap().push(serde_json::json!({
            "seq": trace_seq,
            "ip_before": trace_pre_ip,
            "opcode": format!("0x{:02X}", trace_pre_opcode),
            "mnemonic": "RET",
            "stack_depth_before": trace_pre_depth,
            "stack_depth_after": stack.len()
        }));
    }
    return Ok(val);
}
```

Error paths (`return Err(...)`) in other arms naturally skip recording — correct behavior since execution terminates before the trace can capture the event. The `status: "error"` field in `vm_trace.json` records this outcome.

**Q4. What is the vm_trace.json schema?**

Schema version: `vm-trace-v0`

```json
{
  "schema_version": "vm-trace-v0",
  "contract_name": "ComputeDistance",
  "inputs_digest": "bb455c58a2ce236c",
  "result_digest": "b7a56873cd771f2c",
  "status": "ok",
  "events": [
    {
      "seq": 0,
      "ip_before": 0,
      "opcode": "0x02",
      "mnemonic": "LOAD_REF",
      "stack_depth_before": 0,
      "stack_depth_after": 1,
      "node_id": "compute:ComputeDistance.dx",
      "sir_path": "$.contracts[?(@.contract_name=='ComputeDistance')].nodes[?(@.name=='dx')]",
      "source_span": { "start_line": 11, "start_col": 3 }
    },
    ...
    {
      "seq": 25,
      "ip_before": 25,
      "opcode": "0x0F",
      "mnemonic": "RET",
      "stack_depth_before": 1,
      "stack_depth_after": 0,
      "node_id": null,
      "sir_path": null,
      "source_span": null
    }
  ]
}
```

Fields:
- `seq`: monotonically increasing from 0; counts executed instructions
- `ip_before`: instruction offset at the start of this instruction (matches `bytecode_map.json` offset)
- `opcode`: hex string (e.g. `"0x0F"`) matching bytecode_map format
- `mnemonic`: human-readable string from `opcode_mnemonic()`
- `stack_depth_before` / `stack_depth_after`: stack size before and after the instruction
- `node_id`: SIR node identifier (null for infrastructure instructions: output LOAD_REG, RET)
- `sir_path`: JSONPath into `semantic_ir_program.json` (null when node_id is null)
- `source_span`: `{ start_line, start_col }` from sourcemap (null when node_id is null)
- `inputs_digest`: 16-char truncated SHA-256 of the JSON-serialized inputs
- `result_digest`: 16-char truncated SHA-256 of the JSON-serialized result value
- `status`: `"ok"` or `"error"`

**Q5. How are trace events cross-referenced to source spans?**

`handle_vm_trace` in `main.rs` builds an `offset_lookup: HashMap<usize, (Option<String>, Option<String>, JsonValue)>` by:

1. Calling `handle_bytecode_map(igapp_path)` to ensure `bytecode_map.json` is fresh
2. Loading `bytecode_map.json` and iterating its instructions
3. For each instruction: `offset → (node_id, sir_path, source_span)`

After `vm.execute_with_grants()` returns, `vm.take_trace_events()` drains the collected events. Each event is enriched by looking up `ip_before` in `offset_lookup` and adding `node_id`, `sir_path`, and `source_span` to the JSON object. The enrichment is done in `handle_vm_trace` (post-execution), keeping `vm.rs` free of any source-map awareness.

**Q6. How is determinism guaranteed?**

Determinism follows from three properties:
- The VM's execution is deterministic for fixed inputs (no randomness, no time-dependent opcodes in the tested fixtures)
- The trace collector records each instruction in execution order, producing the same sequence for identical execution paths
- `inputs_digest` and `result_digest` are SHA-256-based: same inputs and result produce identical digests across runs

The proof runner's VMTRACE-DETERMINISM section verifies this empirically: two sequential trace runs on the same inputs produce identical `events_total`, `seq` sequences, `opcode` sequences, `result_digest`, and `inputs_digest`.

**Q7. How is the non-semantic property proven?**

Two-part proof:
1. The traced VM run reports `result_status: "ok"` and `status: "ok"` in `vm_trace.json`
2. An untraced run via `igniter-vm run --contract <igapp> --inputs <inputs> -j` returns `{"result": 25, "status": "success"}`
3. The `result_digest` in `vm_trace.json` is computed as `sha256(JSON.generate(result_value))[0,16]` — the proof runner independently computes this digest from the untraced result and asserts equality

All three fixtures (ComputeDistance, BuildQueryPlan, CheckStatus) pass both traced and untraced. Stack depths, opcode dispatch, and the returned value are identical in both execution modes.

**Q8. What are the closed surfaces?**

The following surfaces were not touched and are verified by the VMTRACE-CLOSED section:

- `VM::execute_with_grants()` semantics (opcode behavior, stack manipulation, temporal context)
- `Instruction { opcode: u8, args: Vec<Value> }` struct — unchanged
- `Value` enum — no new variants (verified: no `SourceSpan` or `TraceEvent` variant)
- Opcode constants — `OP_UNSUPPORTED` is still `0x99`; no new opcodes added
- Breakpoints, stepping, pause/resume, watch expressions — not present in any artifact
- IDE UI, Tauri integration, Svelte, public debugger API
- Ruby canon (`igniter-lang`) — untouched
- Language grammar
- Source-level operational semantics

**Q9. How does the CLI plumbing work?**

The `trace` subcommand is intercepted in `main.rs` before the banner (so stdout is clean JSON):

```
igniter_vm trace <igapp_path> --entry <ContractName> --inputs <inputs.json>
```

The handler `handle_vm_trace(igapp_path, entry, inputs_path)`:
1. Calls `handle_bytecode_map(igapp_path)` → writes `bytecode_map.json`, prints bytecode-map summary to stdout
2. Loads `bytecode_map.json` → builds `offset_lookup`
3. Loads `semantic_ir_program.json` → finds entry contract → `Compiler::new().compile_entry(...)`
4. Loads `inputs.json` → computes `inputs_digest`
5. Sets `vm.trace_collector = Some(Arc::new(Mutex::new(Vec::new())))`
6. Calls `vm.execute_with_grants(instructions, temporal_context)`
7. Calls `vm.take_trace_events()` to drain the collector (leaves it empty for reuse)
8. Enriches each event with `node_id`, `sir_path`, `source_span` from `offset_lookup[ip_before]`
9. Computes `result_digest` from the execution result
10. Writes `vm_trace.json` with schema `vm-trace-v0`
11. Updates `manifest.json` with `vm_trace_ref: "vm_trace.json"`
12. Prints JSON summary to stdout: `{status, igapp, vm_trace_file, contract_name, events_total, result_status}`

Two JSON lines are emitted to stdout: the bytecode-map summary (step 1) and the trace summary (step 12). Proof runners parse the last non-empty line for the trace result.

---

## Implementation

### `igniter-lab/igniter-vm/src/vm.rs`

Additive changes only:

1. **`trace_collector: Option<Arc<Mutex<Vec<serde_json::Value>>>>`** — new field on `VM` struct; `None` by default in `VM::new()`
2. **`take_trace_events(&self) -> Vec<serde_json::Value>`** — drains collector via `std::mem::take`; returns empty vec when collector is `None`
3. **Pre-instruction capture** — `trace_pre_ip`, `trace_pre_depth`, `trace_pre_opcode` computed at top of while loop (zero-cost when `None`)
4. **`trace_seq: usize`** — monotonic counter; incremented only in the post-match block
5. **OP_RET inline recording** — records before `return Ok(val)`; the only special case
6. **Post-match recording** — all non-returning instructions recorded after the match block

### `igniter-lab/igniter-vm/src/main.rs`

1. **`trace` subcommand dispatch** — before banner; validates `--entry` and `--inputs` flags
2. **`async fn handle_vm_trace`** — full pipeline (compile → trace → enrich → write)

### `igniter-view-engine/fixtures/source_map/`

- `inputs_nested.json` — `{"table_name":"users","schema_name":"public"}` for `BuildQueryPlan`
- `inputs_variant.json` — `{"current":{"__arm":"Active","__variant":"Status"},"message":"hello"}` for `CheckStatus`

### `igniter-view-engine/proofs/verify_lab_vmtrace_p1.rb`

66-check proof runner across 10 sections (VMTRACE-COMPILE, VMTRACE-RUN, VMTRACE-SCHEMA, VMTRACE-OFFSETS, VMTRACE-SOURCE, VMTRACE-DETERMINISM, VMTRACE-NONSEMANTIC, VMTRACE-COVERAGE, VMTRACE-ERROR, VMTRACE-CLOSED).

---

## Closed Surfaces (Confirmed Untouched)

- `VM::execute_with_grants()` semantics
- `Instruction { opcode, args }` struct
- `Value` enum
- Opcode constants (OP_UNSUPPORTED = 0x99)
- Breakpoints / stepping / pause / resume / watch expressions
- IDE UI / Tauri / Svelte
- Ruby canon (`igniter-lang`)
- Language grammar
- Source-level operational semantics
