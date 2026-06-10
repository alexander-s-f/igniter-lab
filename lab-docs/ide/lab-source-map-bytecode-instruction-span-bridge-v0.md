# Lab: Source Map — Bytecode Instruction Span Bridge v0

**Track:** LAB-SRCMAP-P2  
**Status:** Complete  
**Authority:** lab_only — not canon, not production

---

## Purpose

This document records the design and implementation decisions for bridging the SIR-level source map (LAB-SRCMAP-P1) down to bytecode instruction level. The output is a durable `bytecode_map.json` artifact that maps each instruction offset to the source node that produced it.

This is the second step on the debugger track:
`LAB-SRCMAP-P1 → LAB-SRCMAP-P2 → LAB-VMTRACE-P1 → LAB-IDE-STEP-P1 → LAB-TEXTBOOK-P1`

---

## Decision Questions

**Q1. Is bytecode provenance feasible without VM semantic changes?**

Yes. The bytecode compiler (`compiler.rs`) is a pure build-time transformation with no runtime semantics. Adding a parallel `node_id_map: Vec<Option<String>>` to the `Compiler` struct is entirely additive. The `VM::execute()` loop in `vm.rs` is untouched. `Instruction { opcode, args }` is unchanged.

**Q2. Sidecar (`bytecode_map.json`) vs. sourcemap extension?**

Sidecar. The two artifacts have different shapes, different consumers, and different update cadences:

- `sourcemap.json`: `node_id → source_span` (1:1 per source declaration/expression). Produced by the Rust compiler at parse/emit time. Stable across re-compilation of the same source.
- `bytecode_map.json`: `offset → (node_id, source_span)` (many-to-1; each node produces multiple instructions). Produced by the VM compiler at lowering time. Changes if the VM compiler's lowering strategy changes even when source is unchanged.

Merging them would couple two independently-evolving artifacts. The sidecar is cleaner and independently readable.

**Q3. How are instruction ranges tracked?**

The compiler's `emit()` function is the single instruction emission point. It was extended to also push `self.current_node_id.clone()` onto a parallel `Vec<Option<String>>` (`node_id_map`). The `current_node_id` field on `Compiler` is set before each compute node's `compile_expr` call and cleared after the corresponding `OP_STORE_REG` is emitted. Infrastructure instructions (output `OP_LOAD_REG`, `OP_RET`) are emitted with `current_node_id = None`.

**Q4. What is the bytecode_map.json shape?**

```json
{
  "schema_version": "bytecode-map-v0",
  "source_file": "/path/to/source.ig",
  "contracts": [
    {
      "contract_name": "ComputeDistance",
      "instructions": [
        {
          "offset": 4,
          "opcode": "0x06",
          "mnemonic": "SUB",
          "node_id": "compute:ComputeDistance.dx",
          "sir_path": "$.contracts[?(@.contract_name=='ComputeDistance')].nodes[?(@.name=='dx')]",
          "source_span": { "start_line": 11, "start_col": 3 }
        },
        {
          "offset": 24,
          "opcode": "0x04",
          "mnemonic": "LOAD_REG",
          "node_id": null,
          "sir_path": null,
          "source_span": null
        }
      ]
    }
  ]
}
```

Instructions with `null` node_id are infrastructure (output register load, RET). `sir_path` and `source_span` are cross-referenced from `sourcemap.json` by node_id.

**Q5. What if a node has no node_id?**

It gets `null` node_id in the map. This happens for:
- Infrastructure instructions (output load, RET) — by design
- Loop nodes (`loop_node`, `service_loop_node`) that don't have a `node_id` field in the current SIR schema
- Compute nodes from pre-P1 SIR artifacts (no `node_id` in their JSON)

The null entries are valid and expected. The proof checks that null-node_id instructions also have null `sir_path` and null `source_span`.

**Q6. Forward path to runtime debugging?**

`bytecode_map.json` is the substrate for `LAB-VMTRACE-P1`. A future VM trace stream can annotate each executed instruction with its source span by doing a simple lookup: `offset → bytecode_map → node_id → sourcemap → source_span`. No VM execution changes are needed to produce the trace — only the post-execution reporting layer needs to read the sidecar.

---

## Architecture

### Compiler Changes (`igniter-vm/src/compiler.rs`)

Two new fields on `Compiler`:

```rust
node_id_map: Vec<Option<String>>,  // parallel to instructions; slot N = node_id at offset N
current_node_id: Option<String>,   // set during each compute node's compilation
```

`emit()` extended:
```rust
fn emit(&mut self, opcode: u8, args: Vec<Value>) -> usize {
    let inst = Instruction::new(opcode, args);
    self.instructions.push(inst);
    self.node_id_map.push(self.current_node_id.clone()); // <-- new
    self.instructions.len() - 1
}
```

Compute node loop extended to thread `current_node_id`:
```rust
for node in nodes_arr {
    self.current_node_id = node.get("node_id").and_then(|n| n.as_str()).map(String::from);
    // ... compile_expr call ...
    // ... OP_STORE_REG emit (tagged with current_node_id) ...
    self.current_node_id = None;  // cleared before output LOAD_REG + RET
}
```

New public method:
```rust
pub fn take_node_id_map(&mut self) -> Vec<Option<String>> {
    std::mem::take(&mut self.node_id_map)
}
```

### Instructions Changes (`igniter-vm/src/instructions.rs`)

New public function:
```rust
pub fn opcode_mnemonic(opcode: u8) -> &'static str { ... }
```

Maps all 34 opcodes (OP_PUSH_LIT through OP_UNSUPPORTED) to their mnemonic strings. Used by the `bytecode-map` CLI subcommand.

### CLI Changes (`igniter-vm/src/main.rs`)

New `bytecode-map` subcommand, added before the banner so stdout is clean JSON:

```
igniter_vm bytecode-map <igapp_path>
```

Reads `semantic_ir_program.json` and `sourcemap.json` from the igapp directory, compiles each contract, cross-references node_ids against the sourcemap, writes `bytecode_map.json`, updates `manifest.json` with `bytecode_map_ref`, and prints a JSON summary to stdout.

---

## v0 Provenance Accuracy

- **Compute node attribution**: every instruction emitted during a compute node's `compile_expr` is tagged with that node's `node_id`. This includes binary ops, field accesses, register loads, and the final `OP_STORE_REG`.
- **Infrastructure gap**: the output `OP_LOAD_REG` and `OP_RET` instructions have `null` node_id. They belong to the contract's output protocol, not to any specific source declaration.
- **Source span fidelity**: spans in `bytecode_map.json` are copied verbatim from `sourcemap.json` via node_id lookup. The fidelity is therefore the same as P1: declaration spans exact, expression spans best-effort.

---

## Proof Results

```
61/61 PASS    0 FAIL

P2-COMPILE:     All 3 fixtures compile; bytecode-map step succeeds for each.
P2-MAP-SCHEMA:  bytecode_map.json shape correct (bytecode-map-v0).
P2-COVERAGE:    All compute node_ids from sourcemap appear in bytecode_map.
P2-OFFSETS:     Offsets sequential, last instruction is RET, opcodes valid.
P2-SOURCE:      Non-null node_id entries have matching sir_path + source_span.
                Cross-reference matches sourcemap.json exactly.
P2-STABILITY:   Re-compile produces identical bytecode_map.
P2-NONSEMANTIC: Instruction struct unchanged; bytecode_map.json additive only.
P2-CLOSED:      vm.rs execution loop untouched; no new opcodes; VM output correct.
```

P1 proof also remains green: 61/61. The P1 SRCMAP-CLOSED check was narrowed to exclude compiler.rs, instructions.rs, and main.rs (which are the explicit P2 extension scope) and now correctly targets only the VM execution engine (vm.rs).

---

## Files Modified

**`igniter-vm/src/compiler.rs`** — Added `node_id_map`, `current_node_id` fields; extended `emit()`; added `take_node_id_map()`; threaded `current_node_id` through compute node compilation loop.

**`igniter-vm/src/instructions.rs`** — Added `pub fn opcode_mnemonic(opcode: u8) -> &'static str`.

**`igniter-vm/src/main.rs`** — Added `bytecode-map` subcommand check (before banner); added `fn handle_bytecode_map(igapp_path: &str)` function.

**`igniter-view-engine/fixtures/source_map/inputs_basic.json`** — Minimal inputs for VM execution check in P2-NONSEMANTIC.

**`igniter-view-engine/proofs/verify_lab_srcmap_p2.rb`** — 61-check proof runner.

**`igniter-view-engine/proofs/verify_lab_srcmap_p1.rb`** — Narrowed SRCMAP-CLOSED-2 to exclude compiler.rs, instructions.rs, main.rs.

**Closed surfaces (not modified):**

- VM execution loop (`vm.rs`) — untouched
- `Instruction` struct — unchanged (`{ opcode: u8, args: Vec<Value> }`)
- `Value` enum — unchanged
- Opcode constants — no new opcodes (OP_UNSUPPORTED still 0x99)
- IDE UI / Tauri / Svelte — untouched
- Ruby canon (`igniter-lang`) — untouched
- Language grammar — untouched
- Runtime semantics — unchanged
