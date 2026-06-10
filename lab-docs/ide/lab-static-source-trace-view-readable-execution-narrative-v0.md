# Lab: Static Source Trace View — Readable Execution Narrative v0

**Track:** LAB-IDE-TRACE-VIEW-P1  
**Status:** Complete  
**Authority:** lab_only — not canon, not production

---

## Purpose

This document records the design and decisions for rendering `source_trace.json` (from LAB-VMTRACE-P2) into a compact, source-readable execution narrative (`source_trace_view.md`). The central question:

> Can a static rendered view explain execution clearly enough to support a future debugger/IDE, without any interactive behavior?

The answer is yes. `source_trace_view.md` answers "what source nodes ran, in what order, what source line each came from, how many instructions they executed, and whether a match branch was taken" — without running the VM, stepping through code, or adding any debugger authority.

This is the fifth step on the debugger track:
`LAB-SRCMAP-P1 → LAB-SRCMAP-P2 → LAB-VMTRACE-P1 → LAB-VMTRACE-P2 → LAB-IDE-TRACE-VIEW-P1 → LAB-VMTRACE-P3 or LAB-IDE-TRACE-VIEW-P2 (candidate)`

---

## Decision Questions

**Q1. Is `source_trace.json` readable enough for human/agent inspection?**

Yes. The source_trace groups instruction events into named compute nodes with `node_id`, `sir_path`, `source_span`, `instruction_offsets`, and `mnemonics`. A human can follow the execution timeline node-by-node. An agent can parse the JSON directly. `source_trace_view.md` makes this even more accessible: it adds source line snippets from the original `.ig` file, shows mnemonics in summary form, and calls out non-contiguous offsets explicitly. Proved in VIEW-READABLE and VIEW-DRILLDOWN.

**Q2. Can the view explain branch jumps / non-contiguous offsets?**

Yes. The renderer checks whether a node entry's `instruction_offsets` form a contiguous integer range. If not, it appends a blockquote note:

> **Note:** Non-contiguous offsets — control flow skipped bytecode (branch jump; unexecuted match arm not recorded).

For the `CheckStatus.label` node (f3 fixture), offsets are `[0,1,2,3,4,5,6,7,8,20]`. The gap at 9–19 is the unexecuted Inactive arm. The JMP at ip=8 jumps to STORE_REG at ip=20. The note appears immediately after the offsets line and is placed after the node_id heading (proved in VIEW-BRANCH: note_pos > label_pos). Nodes without branches (all f1 nodes) do not get the note.

**Q3. Are infrastructure instructions clearly separated?**

Yes. Infrastructure entries are rendered under a `[infrastructure]` heading (not `[node]`). They include instruction count, mnemonic summary, and offsets. They do not include `**Source:**` or `**Snippet:**` lines — these are VM infrastructure instructions (LOAD_REG, RET) with no source origin. A `*(No source location — VM infrastructure instructions)*` note is appended to make the distinction explicit. Proved in VIEW-INFRA: infrastructure sections contain no Source claim, and node sections have [node] markers.

**Q4. Can a reader drill down to instruction offsets?**

Yes. Every entry (node and infrastructure) carries `**Offsets:**` and `**Instructions:**` lines. The offsets are the exact `ip_before` values from the original vm_trace events. The mnemonic list (truncated to first 6 + `...` for longer sequences) provides the opcode names. The union of all offsets across all entries equals the full vm_trace ip_before set — lossless (inherited from source_trace, proved in LAB-VMTRACE-P2 VIEW-DRILLDOWN). Proved in VIEW-DRILLDOWN.

**Q5. Is rendering deterministic?**

Yes. The renderer is a pure function of `source_trace.json` and the original source file lines. Same inputs → same output. Proved in VIEW-DETERMINISM: re-render of f1 and f3 produces identical strings; the on-disk file matches the in-memory render.

**Q6. Does the renderer execute or affect VM behavior?**

No. The renderer calls only `load_source_trace` (JSON file read) and `File.write` (markdown file write). It does not invoke the VM binary, does not call `Open3.capture3`, does not modify `vm_trace.json` or `source_trace.json`. The `vm_trace.json` result_digest is unchanged after rendering. Proved in VIEW-NONSEMANTIC and VIEW-DETERMINISM.

**Q7. Does this authorize stepping or IDE UI?**

No. The rendered markdown is a static artifact. It contains no step counters, no breakpoint markers, no watch expressions, no session tokens, no interactive API surface. The source_trace.json schema_version remains `"source-trace-v0"` after rendering — no debugger-authority schema is emitted. Proved in VIEW-CLOSED.

**Q8. What exact next route remains?**

Two candidates, in order of recommended priority:

1. **LAB-VMTRACE-P3** — expand fixture coverage to loops, nested matches, and error paths. This proves the grouping rule and non-contiguous offset explanation hold under more complex execution patterns before building further viewer layers.

2. **LAB-IDE-TRACE-VIEW-P2** — a tiny local static HTML viewer: given `source_trace_view.md` or `source_trace.json`, produce a structured HTML page with syntax highlighting and collapsible entries. No interactive debugger, no stepping.

Do not authorize LAB-IDE-STEP-P1 until the trace receipt can clearly explain divergent execution paths, including loops and nested matches.

---

## Renderer Design

### Input

- `source_trace.json` — written by the P2 aggregation step (schema_version `"source-trace-v0"`)
- Original `.ig` source file — optional; provides line snippets via `source_span.start_line`

The renderer does not need `bytecode_map.json` or `vm_trace.json` — all information needed for the view is already in `source_trace.json`.

### Output

`source_trace_view.md` — written to the igapp directory alongside `source_trace.json`.

### Algorithm

```
load source_trace.json
sort all_groups = nodes + infrastructure by seq
emit header: "# Trace: <contract_name>"
emit metadata: Status / Inputs digest / Result digest
emit "## Execution Timeline"

for each group in execution order:
  human_pos = group.seq + 1

  if group is a node:
    emit "### {pos}. [node] {node_id}"
    emit "**Source:** line {start_line}, col {start_col}"
    if source_lines available:
      emit "**Snippet:** `{source_lines[start_line-1].strip}`"
    emit "**Instructions:** {count} ({first_6_mnemonics, ...})"
    emit "**Offsets:** {offsets.join(', ')}"
    if offsets != (min..max).to_a:
      emit "> **Note:** Non-contiguous offsets — control flow skipped bytecode ..."

  else (infrastructure):
    emit "### {pos}. [infrastructure]"
    emit "**Instructions:** {count} ({first_6_mnemonics, ...})"
    emit "**Offsets:** {offsets.join(', ')}"
    emit "*(No source location — VM infrastructure instructions)*"
```

The `min..max` contiguous check: offsets within a node may be non-contiguous when a branch jump skips unreachable arm instructions. This is expected behavior, not a defect — the note explains it explicitly.

---

## source_trace_view.md Format

### Example: CheckStatus (f3 — variant match with branch)

```markdown
# Trace: CheckStatus

**Status:** ok
**Inputs digest:** 90e9db3f333d5f5c
**Result digest:** 5aa762ae383fbb72

## Execution Timeline

### 1. [node] compute:CheckStatus.label
**Source:** line 12, col 3
**Snippet:** `compute label: String = match current {`
**Instructions:** 10 (LOAD_REF, STORE_REG, LOAD_REG, GET_FIELD, PUSH_LIT, EQ, ...)
**Offsets:** 0, 1, 2, 3, 4, 5, 6, 7, 8, 20
> **Note:** Non-contiguous offsets — control flow skipped bytecode (branch jump; unexecuted match arm not recorded).

### 2. [node] compute:CheckStatus.result
**Source:** line 17, col 3
**Snippet:** `compute result: Status = Active {}`
**Instructions:** 4 (PUSH_LIT, PUSH_LIT, PUSH_RECORD, STORE_REG)
**Offsets:** 21, 22, 23, 24

### 3. [infrastructure]
**Instructions:** 2 (LOAD_REG, RET)
**Offsets:** 25, 26
*(No source location — VM infrastructure instructions)*
```

The non-contiguous note on the label node tells a reader: "the match executed the Active arm; the Inactive arm instructions at ip=9-19 were never reached; execution jumped from ip=8 (JMP) directly to ip=20 (STORE_REG)."

---

## Implementation

### `igniter-view-engine/proofs/verify_lab_ide_trace_view_p1.rb`

Proof-runner-only renderer. The proof runner:
1. Compiles all three source_map fixtures fresh
2. Runs `vm trace` for each
3. Aggregates vm_trace → source_trace in memory (same logic as P2)
4. Writes `source_trace.json` for each igapp
5. Calls `render_source_trace_view(igapp_path, source_lines)` in memory
6. Writes `source_trace_view.md` to each igapp directory
7. Runs 50 checks across 10 sections

**Why proof-runner-only:** rendering is a pure transformation over existing trace artifacts. Adding a `trace-view` CLI subcommand to the VM binary would touch VM CLI with no additional proof value. If a CLI consumer needs `source_trace_view.md`, that belongs to a future card.

### No VM source changes

Zero changes to `vm.rs`, `main.rs`, `compiler.rs`, `instructions.rs`, `value.rs`.

---

## Fixtures

All three P1/P2 source_map fixtures:

| Fixture | Contract | Nodes | Infra | Branch note |
|---|---|---|---|---|
| srcmap_basic_contract.ig | ComputeDistance | 5 | 1 | None (all consecutive) |
| srcmap_nested_record.ig | BuildQueryPlan | 3 | 1 | None |
| srcmap_variant_match.ig | CheckStatus | 2 | 1 | label node: offsets `[0,1,2,3,4,5,6,7,8,20]` |

f3 CheckStatus is the key case: offset gap at 9–19 is the unexecuted Inactive arm, proved by the non-contiguous note appearing in the rendered view.

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

**LAB-VMTRACE-P3** — loop/nested-branch/error trace coverage: expand fixtures to include loops and recursive calls. Verify the grouping rule, non-contiguous detection, and view rendering hold under more complex execution shapes before building an HTML viewer.

Alternatively, **LAB-IDE-TRACE-VIEW-P2** — static HTML viewer with collapsible sections and syntax coloring.

Do not authorize **LAB-IDE-STEP-P1** until the receipt can explain loop iterations and nested branches clearly.
