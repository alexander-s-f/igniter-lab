# LAB-VMTRACE-P2 — Agent Return Packet

Node-level trace aggregation: `vm_trace.json` instruction events are grouped into compact source-readable node entries (`source_trace.json`), preserving execution order, source linkage, and drill-down to instruction offsets.

---

## Status

**Complete.** P2 proof 60/60. P1 proof 66/66 (still green). SRCMAP-P2 proof 61/61 (still green).

---

## Changed Files

### Proof Runners (`igniter-view-engine/proofs/`)

- **`verify_lab_vmtrace_p2.rb`** — 60-check proof runner across 11 sections. Implements `aggregate_source_trace()` in Ruby (proof-runner-only aggregation, no VM CLI change). Writes `source_trace.json` + updates `manifest.json` with `source_trace_ref` for all three fixtures.

### Lab Doc

- **`igniter-lab/lab-docs/ide/lab-vm-node-level-trace-aggregation-source-receipt-v0.md`**

### No VM source changes

Zero changes to `vm.rs`, `main.rs`, `compiler.rs`, `instructions.rs`, `value.rs`.

---

## Proof Results

```
VMT2-P2: 60/60 PASS    0 FAIL

VMT2-INPUT:       VM binary + f1 trace prerequisites confirmed.
VMT2-SCHEMA:      source_trace.json schema valid; schema_version="source-trace-v0"; manifest updated.
VMT2-GROUP:       5 node entries (f1); 2 node entries (f3); non-consecutive ip offsets confirmed for f3 label branch.
VMT2-ORDER:       seq 0-based monotonic; timeline correct; f3 seq order = [label, result, infra].
VMT2-SOURCE:      all node entries have sir_path + source_span; start_line > 0; node_ids correct.
VMT2-INFRA:       1 infra entry (f1); last entry has RET; no sir_path/source_span in infra.
VMT2-DRILLDOWN:   all ip offsets covered; total count == events_total; mnemonics match execution order.
VMT2-DETERMINISM: re-aggregate → identical nodes/offsets/result_digest.
VMT2-NONSEMANTIC: result_digest + inputs_digest match vm_trace exactly; f2+f3 ok.
VMT2-ERROR:       error vm_trace → status=error; nodes=[]; infrastructure=[].
VMT2-CLOSED:      no breakpoint/watch/step keys; OP_UNSUPPORTED=0x99; schema_version≠debugger-*.
```

---

## Design Decisions

**Grouping rule — consecutive by execution order, not IP space:**
Group consecutive trace events (in execution seq order) with the same non-null `node_id`. "Consecutive" means execution-adjacent, not IP-adjacent. This handles branches correctly: when the Active arm of a match is taken, the Inactive arm instructions are not in the trace, and the STORE_REG at a non-adjacent IP appears immediately after the JMP in execution order. The same node_id appears as one contiguous block in all current fixtures.

**Key empirical finding — f3 label node non-consecutive IPs:**
The `CheckStatus.label` match expression executes IP offsets `[0,1,2,3,4,5,6,7,8,20]`. The gap at ip=9-19 is the unexecuted Inactive arm. This is proven in VMT2-GROUP and documents that `instruction_offsets` in node entries may not be a consecutive integer range when branches are taken.

**No non-consecutive same-node events in current fixtures:**
All three fixtures show each node_id in exactly one consecutive run. Consecutive-run grouping equals per-node grouping. If future fixtures (loops, recursion) produce same-node non-consecutive events, each run would produce a separate node entry (timeline order preserved), not merged.

**Infrastructure entries have no `node_id` key (not null, absent):**
This makes infra entries distinguishable from node entries via `g.key?('node_id')` — a clean structural distinction. Ruby and JSON consumers can separate node vs infrastructure without checking for null.

**Seq globally ordered across nodes + infrastructure:**
The `seq` field is assigned before splitting into `nodes` and `infrastructure` arrays. To reconstruct the full timeline, sort all entries from both arrays by `seq`. This design keeps the two categories structurally separate while preserving order recoverability.

**Option A (proof-runner-only):**
The aggregation is a pure function of vm_trace.json. No VM execution needed. No CLI change justified. The proof proves the receipt shape and grouping rule. A CLI subcommand belongs to a future card if consumer demand exists.

**result_digest / inputs_digest passthrough:**
source_trace copies these verbatim from vm_trace. This makes the provenance chain clear: source_trace is a derived view, not a re-execution. The origin of the digests is always vm_trace.

---

## Closed Surfaces (Confirmed Untouched)

- VM execution semantics
- `Instruction { opcode, args }` struct
- `Value` enum
- Opcode constants (OP_UNSUPPORTED = 0x99, no new opcodes)
- Breakpoints / stepping / pause / resume / watch expressions
- IDE UI / Tauri / Svelte / public debugger API
- Ruby canon (`igniter-lang`)
- Language grammar
- Source-level operational semantics

---

## Recommended Next Route

**LAB-IDE-TRACE-VIEW-P1** — static source trace viewer: given `source_trace.json`, produce a legible execution narrative (which nodes ran, in which order, which arm was taken in a match). Not stepping, not breakpoints.

Or **LAB-VMTRACE-P3** — expand fixture coverage to loops and nested matches before building the viewer.

Do not authorize LAB-IDE-STEP-P1 until the source receipt can clearly explain branch paths.
