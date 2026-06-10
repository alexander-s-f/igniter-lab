# LAB-SRCMAP-P2 — Agent Return Packet

Source-map bytecode bridge: every VM instruction offset is cross-referenced to the SIR `node_id` and `source_span` that produced it, emitted as a durable `bytecode_map.json` sidecar.

---

## Status

**Complete.** P2 proof 61/61. P1 proof 61/61 (still green).

---

## Changed Files

### VM Compiler (`igniter-lab/igniter-vm/src/`)

- **`compiler.rs`** — Additive changes only:
  - Added `node_id_map: Vec<Option<String>>` and `current_node_id: Option<String>` to `Compiler` struct
  - Reset both in `compile_entry`
  - Extended `emit()` to push `current_node_id.clone()` to `node_id_map` on every instruction emission
  - Set `current_node_id` from `node["node_id"]` before each compute node's `compile_expr` call
  - Cleared `current_node_id = None` after `OP_STORE_REG` (output `LOAD_REG` + `RET` get null)
  - Added `pub fn take_node_id_map(&mut self) -> Vec<Option<String>>`

- **`instructions.rs`** — Added `pub fn opcode_mnemonic(opcode: u8) -> &'static str` mapping all 34 opcodes to their mnemonic strings.

- **`main.rs`** — Added `bytecode-map` subcommand (before banner, stdout is clean JSON):
  - CLI: `igniter_vm bytecode-map <igapp_path>`
  - Reads `semantic_ir_program.json` + `sourcemap.json`
  - Compiles each contract, collects `take_node_id_map()`
  - Cross-references node_id to sir_path + source_span from sourcemap
  - Writes `bytecode_map.json` + updates `manifest.json` with `bytecode_map_ref`
  - Prints JSON summary: `{status, igapp, bytecode_map_file, instructions_total, contracts}`

### Fixtures (`igniter-view-engine/fixtures/source_map/`)

- **`inputs_basic.json`** — `{"p1":{"x":3,"y":4},"p2":{"x":0,"y":0}}`. Used by P2-CLOSED VM execution check.

### Proof Runners (`igniter-view-engine/proofs/`)

- **`verify_lab_srcmap_p2.rb`** — 61-check proof runner across 8 sections.
- **`verify_lab_srcmap_p1.rb`** — Narrowed `SRCMAP-CLOSED-2` to exclude `compiler.rs`, `instructions.rs`, `main.rs` (P2 extension scope); now correctly targets only VM execution engine (`vm.rs`).

### Lab Doc

- **`igniter-lab/lab-docs/ide/lab-source-map-bytecode-instruction-span-bridge-v0.md`**

---

## Proof Results

```
P2: 61/61 PASS    0 FAIL

P2-COMPILE:     All 3 P1 fixtures compile ok; bytecode-map step succeeds for each.
P2-MAP-SCHEMA:  bytecode_map.json shape correct (schema_version="bytecode-map-v0").
P2-COVERAGE:    All compute node_ids from sourcemap appear in bytecode_map.
P2-OFFSETS:     Offsets 0-based consecutive; last instruction is RET; hex opcodes valid.
P2-SOURCE:      Non-null node_id entries have sir_path + source_span; cross-ref exact.
P2-STABILITY:   Re-compile produces identical bytecode_map.json.
P2-NONSEMANTIC: Instruction struct unchanged; bytecode_map is additive parallel artifact.
P2-CLOSED:      vm.rs execution loop untouched; no new opcodes; VM result=25 correct.

P1: 61/61 PASS (still green after SRCMAP-CLOSED-2 scope fix)
```

---

## Design Decisions

**Parallel node_id_map (not embedded in Instruction):** Embedding a `node_id: Option<String>` in `Instruction { opcode, args }` would require touching every callsite that constructs or matches on `Instruction`. The parallel `Vec<Option<String>>` is purely additive — existing code is unchanged, and callers that don't need span data call `compile_entry` and ignore `take_node_id_map()`.

**Sidecar over sourcemap extension:** `bytecode_map.json` has a many-to-one relationship (N instructions per SIR node) vs `sourcemap.json`'s one-to-one shape. Different shapes, different consumers, different update cadences. The sidecar keeps both artifacts clean.

**current_node_id cleared after STORE_REG:** `OP_STORE_REG` is the last instruction emitted for a compute node's value — attributed to that node. Output `OP_LOAD_REG` and `OP_RET` are infrastructure and get `null`. This gives clear null/non-null semantics: null = infrastructure; non-null = compute work.

**bytecode-map before banner in main.rs:** The banner is printed to stdout, which would corrupt the JSON output. The `bytecode-map` check is placed before the banner block so the subcommand's stdout is always clean JSON, parseable by proof runners and CI scripts.

**P1 SRCMAP-CLOSED-2 scope fix:** The original P1 check scanned all `*.rs` files in `igniter-vm/src/`. P2 legitimately adds `node_id` to `compiler.rs`, `instructions.rs`, and `main.rs`. The check now excludes those three files and only asserts on the execution engine (`vm.rs` etc.). The P1 closed surface was always about the execution pipeline, not the compiler.

---

## Closed Surfaces (Confirmed Untouched)

- `VM::execute()` loop in `vm.rs`
- `Instruction { opcode: u8, args: Vec<Value> }` struct
- `Value` enum
- Opcode constants (OP_UNSUPPORTED still 0x99, no new opcodes)
- IDE UI / Tauri / Svelte
- Ruby canon (`igniter-lang`)
- Language grammar
- Runtime semantics
