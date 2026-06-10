# Lab: VM Node-Level Trace Aggregation — Source Trace Receipt v0

**Track:** LAB-VMTRACE-P2  
**Status:** Complete  
**Authority:** lab_only — not canon, not production

---

## Purpose

This document records the design and implementation decisions for aggregating the instruction-level `vm_trace.json` (from LAB-VMTRACE-P1) into a compact, source-readable node-level trace receipt (`source_trace.json`). The central question:

> Can a human or agent understand execution as a timeline of source-origin nodes without reading every VM instruction?

The answer is yes. `source_trace.json` answers "what source nodes ran, in what order, and with what instruction footprint" — without re-running the VM or adding any debugger authority.

This is the fourth step on the debugger track:
`LAB-SRCMAP-P1 → LAB-SRCMAP-P2 → LAB-VMTRACE-P1 → LAB-VMTRACE-P2 → LAB-IDE-TRACE-VIEW-P1 (candidate)`

---

## Decision Questions

**Q1. What grouping rule is used?**

Group consecutive trace events (in execution order, i.e., by seq in vm_trace.json) that share the same non-null `node_id` into one node entry. Group consecutive events with `node_id == null` into one infrastructure entry.

"Consecutive" means consecutive in execution order — not consecutive in IP offset space. IP offsets within a node group may be non-consecutive when branch instructions skip unreachable arms (see Q2).

**Q2. Are same-node non-consecutive events merged or emitted separately?**

Emitted as separate node entries (one per consecutive run). In current fixtures, each node_id appears in exactly one consecutive run — empirically verified across all three fixtures (see VMT2-GROUP). This confirms the compiler emits each compute node as one contiguous block. If non-consecutive same-node events were to appear (e.g., in future recursive or loop constructs), they would produce multiple node entries for the same node_id, preserving timeline order.

**Key finding — non-consecutive IP offsets within a single node group:**

The `CheckStatus.label` node (a variant match) executes with IP offsets `[0,1,2,3,4,5,6,7,8,20]`. The Active arm is taken: after the Active arm body at ip=7, a JMP at ip=8 jumps over the Inactive arm (ip=9-19) to the STORE_REG at ip=20. The trace records only executed instructions, so the Inactive arm is absent, and ip=20 immediately follows ip=8 in the trace. This is correct behavior: the grouping is by execution-order adjacency, not IP-space adjacency. This finding is empirically proved in VMT2-GROUP.

**Q3. How are infrastructure instructions represented?**

Infrastructure instructions (those with `node_id == null` in the bytecode_map: output LOAD_REG, RET) are grouped into separate infrastructure entries. These entries have `instruction_offsets` and `mnemonics` but no `node_id`, `sir_path`, or `source_span` keys. This is honest: infrastructure instructions have no source-origin and must not be presented as if they do.

**Q4. Can each node event drill down to instruction offsets?**

Yes. Every node entry and infrastructure entry carries an `instruction_offsets` array and a `mnemonics` array. The union of all offsets across all entries exactly equals the set of `ip_before` values in `vm_trace.json`. The total instruction count across all entries equals `vm_trace.events_total`. Drill-down is lossless and reversible: the instruction-level trace can be fully reconstructed from source_trace + the original vm_trace.

**Q5. Is source_trace fully derived from vm_trace? Not runtime authority?**

Yes. The aggregation is a pure transformation over `vm_trace.json` events. No VM execution occurs. No compile step is needed. The `inputs_digest` and `result_digest` are copied verbatim from `vm_trace.json`. The `status` field mirrors the execution outcome. The derivation does not interpret or execute any contract semantics.

**Q6. Are outputs unchanged?**

Yes. VM execution semantics are unchanged. The source_trace is derived post-execution. `inputs_digest` and `result_digest` in source_trace match vm_trace exactly (proved in VMT2-NONSEMANTIC). The proof runner uses Option A (proof-runner aggregation, no VM CLI changes) — the VM binary is not modified.

**Q7. Is the receipt deterministic?**

Yes. The aggregation is a pure function of vm_trace.json content. Same vm_trace → same source_trace (proved in VMT2-DETERMINISM: same node count, same node_ids, same instruction_offsets, same result_digest).

**Q8. Does this authorize LAB-IDE-STEP-P1?**

**Not yet.** P2 proves a static, record-only source receipt is derivable and readable. It does not prove interactive stepping, breakpoints, or session-level pause/resume. Before authorizing LAB-IDE-STEP-P1, at minimum LAB-VMTRACE-P3 (branch/loop/error trace coverage) or LAB-IDE-TRACE-VIEW-P1 (static viewer) should demonstrate that the receipt can explain divergent execution paths.

---

## source_trace.json Schema

Schema version: `source-trace-v0`

```json
{
  "schema_version": "source-trace-v0",
  "contract_name": "ComputeDistance",
  "inputs_digest": "bb455c58a2ce236c",
  "result_digest": "b7a56873cd771f2c",
  "status": "ok",
  "nodes": [
    {
      "seq": 0,
      "node_id": "compute:ComputeDistance.dx",
      "sir_path": "$.contracts[?(@.contract_name=='ComputeDistance')].nodes[?(@.name=='dx')]",
      "source_span": { "start_line": 11, "start_col": 3 },
      "instruction_count": 6,
      "instruction_offsets": [0, 1, 2, 3, 4, 5],
      "mnemonics": ["LOAD_REF", "GET_FIELD", "LOAD_REF", "GET_FIELD", "SUB", "STORE_REG"],
      "stack_depth_entry": 0,
      "stack_depth_exit": 0
    }
  ],
  "infrastructure": [
    {
      "seq": 5,
      "instruction_count": 2,
      "instruction_offsets": [24, 25],
      "mnemonics": ["LOAD_REG", "RET"]
    }
  ]
}
```

Fields:
- `seq`: globally monotonic, 0-based, assigned in execution order across both `nodes` and `infrastructure`. Sort all entries by seq to reconstruct the full timeline.
- `node_id`: SIR compute node identifier (only present in node entries)
- `sir_path`: JSONPath into semantic_ir_program.json (only in node entries)
- `source_span`: `{ start_line, start_col }` (only in node entries)
- `instruction_count`: length of `instruction_offsets`
- `instruction_offsets`: list of `ip_before` values from corresponding vm_trace events
- `mnemonics`: list of mnemonic strings; same length as `instruction_offsets`
- `stack_depth_entry` / `stack_depth_exit`: stack size at first and last event in group (node entries only)

**Branch gap (f3 finding):** `instruction_offsets` for a variant match node will contain non-consecutive integers when branches are skipped. This is correct: the array represents executed instructions in execution order, not the contiguous bytecode block.

---

## Aggregation Algorithm

The aggregation is a pure transformation implemented in the proof runner:

```
for each event in vm_trace.events (in order):
  if event.node_id != current_group.node_id:
    flush current_group to all_groups
    start new group (node or infra based on node_id nil-ness)
  append event.ip_before to group.instruction_offsets
  append event.mnemonic to group.mnemonics
  update group.stack_depth_exit

for i, group in enumerate(all_groups):
  group.seq = i
  group.instruction_count = len(instruction_offsets)

split into nodes (g.key?('node_id')) and infrastructure (else)
```

Infrastructure entries omit `node_id`, `sir_path`, `source_span`, `stack_depth_entry`, `stack_depth_exit` entirely (key absent). This distinction is testable with `g.key?('node_id')`.

---

## Implementation

### `igniter-view-engine/proofs/verify_lab_vmtrace_p2.rb`

Option A (proof-runner-only aggregation): the proof runner:
1. Compiles all three fixtures fresh
2. Runs `vm trace` for each
3. Loads `vm_trace.json` for each
4. Calls `aggregate_source_trace(vt)` in memory
5. Writes `source_trace.json` to each igapp directory
6. Updates `manifest.json` with `source_trace_ref: "source_trace.json"`
7. Runs 60 checks across 11 sections

**Why Option A:** P2 is about proving the receipt shape and grouping rule, not adding product surface. The aggregation is a pure transformation (no VM execution, no CLI needed). Option B (CLI subcommand) would touch VM CLI for no additional proof value. If a consumer needs CLI access to source_trace, that can be LAB-VMTRACE-P3 work.

### No VM source changes

VM binary, `vm.rs`, `instructions.rs`, `value.rs`, `compiler.rs` are untouched. Zero new opcodes.

---

## Fixtures

All three P1 source_map fixtures used:

| Fixture | Contract | Node groups | Infra groups | Exec events |
|---|---|---|---|---|
| srcmap_basic_contract.ig | ComputeDistance | 5 | 1 | 26 |
| srcmap_nested_record.ig | BuildQueryPlan | 3 | 1 | 14 |
| srcmap_variant_match.ig | CheckStatus | 2 | 1 | 16 |

f3 (CheckStatus) is the key case: the `label` match expression produces a node group with non-consecutive IP offsets `[0,1,2,3,4,5,6,7,8,20]` — the gap at ip=9-19 is the unexecuted Inactive arm.

---

## Closed Surfaces (Confirmed Untouched)

- VM execution semantics
- `Instruction { opcode, args }` struct
- `Value` enum
- Opcode constants (OP_UNSUPPORTED = 0x99)
- Breakpoints / stepping / pause / resume / watch expressions
- IDE UI / Tauri / Svelte / public debugger API
- Ruby canon (`igniter-lang`)
- Language grammar
- Source-level operational semantics

---

## Recommended Next Route

**LAB-IDE-TRACE-VIEW-P1** — static trace viewer: given `source_trace.json`, produce a human-readable or agent-readable view that explains execution at the source level. This is still not a stepper, not breakpoints, not interactive. It proves the receipt is legible.

Alternatively, **LAB-VMTRACE-P3** — branch/loop/error trace coverage: expand fixture set to include loops, nested matches, error paths, and multi-contract execution. Verify the grouping rule holds under more complex execution patterns before building a viewer.

Do not authorize LAB-IDE-STEP-P1 until the receipt can explain branch paths (which arm was taken) and loop iterations clearly.
