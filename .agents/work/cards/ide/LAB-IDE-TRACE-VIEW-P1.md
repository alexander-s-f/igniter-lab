# LAB-IDE-TRACE-VIEW-P1 — Agent Return Packet

Static source trace viewer: `source_trace.json` rendered into `source_trace_view.md`, a compact execution narrative with source locations, instruction counts, mnemonic summaries, source line snippets, and explicit branch/non-contiguous offset notes.

---

## Status

**Complete.** P1 proof 50/50. P2 proof 60/60 (still green).

---

## Changed Files

### Proof Runner (`igniter-view-engine/proofs/`)

- **`verify_lab_ide_trace_view_p1.rb`** — 50-check proof runner across 10 sections. Implements `render_source_trace_view()` and `write_source_trace_view()` in Ruby (proof-runner-only, no VM CLI change). Renders `source_trace_view.md` for all three source_map fixtures.

### Lab Doc

- **`igniter-lab/lab-docs/ide/lab-static-source-trace-view-readable-execution-narrative-v0.md`**

### No VM source changes

Zero changes to `vm.rs`, `main.rs`, `compiler.rs`, `instructions.rs`, `value.rs`.

---

## Proof Results

```
VIEW-P1: 50/50 PASS    0 FAIL

VIEW-INPUT:       prerequisites: VM binary + source_traces exist; f3 non-contiguous confirmed.
VIEW-RENDER:      view files emitted for f1/f2/f3; non-empty; f1 > 200 bytes.
VIEW-SCHEMA:      "# Trace:" header; "## Execution Timeline"; Status/Inputs/Result digest lines.
VIEW-READABLE:    contract name, node_id, source line, Instructions, Offsets, [node] marker, snippet.
VIEW-BRANCH:      f3 "Non-contiguous" note present; "branch" mentioned; note after label heading;
                  "skipped bytecode" confirms it's not an error; f1 (no branch) has no note.
VIEW-INFRA:       [infrastructure] label present; RET present; no **Source:** claim; "No source
                  location" note; Offsets line present.
VIEW-DRILLDOWN:   all f1 node_ids in view; offset 20 in f3 view; count matches; full label offset
                  list present; f2 contract name present.
VIEW-DETERMINISM: re-render f1 → identical; re-render f3 → identical; source_trace unchanged;
                  on-disk file matches in-memory render.
VIEW-NONSEMANTIC: result_digest and inputs_digest embedded from source_trace; f3 digest present;
                  vm_trace.json result_digest unchanged after render.
VIEW-CLOSED:      no breakpoint/step_counter/watch_expression; OP_UNSUPPORTED=0x99; schema_version
                  still "source-trace-v0" (no debugger-* upgrade).
```

---

## Answers to Required Questions

**Q1. Is `source_trace.json` readable enough for human/agent inspection?**

Yes. The rendered view provides: contract name, execution status, node-by-node timeline with source line/col, source snippet, instruction count, mnemonic summary, and offsets. Agents can read the markdown directly; JSON consumers can parse source_trace.json. Proved in VIEW-READABLE and VIEW-DRILLDOWN.

**Q2. Can the view explain branch jumps / non-contiguous offsets?**

Yes. When a node's `instruction_offsets` are not a contiguous integer range (i.e. `offsets != (min..max).to_a`), the renderer appends:
> **Note:** Non-contiguous offsets — control flow skipped bytecode (branch jump; unexecuted match arm not recorded).

Proved for f3's `compute:CheckStatus.label` node: offsets `[0,1,2,3,4,5,6,7,8,20]`, gap at 9–19 is the unexecuted Inactive arm. VIEW-BRANCH confirms the note appears after the label heading and is not present for f1 (no branches).

**Q3. Are infrastructure instructions clearly separated?**

Yes. Infrastructure entries render under `[infrastructure]` with no `**Source:**` line, no snippet, and an explicit `*(No source location — VM infrastructure instructions)*` note. Proved in VIEW-INFRA.

**Q4. Can a reader drill down to instruction offsets?**

Yes. Every entry has `**Offsets:**` and `**Instructions:**` lines. The offset list is the exact execution-order ip_before sequence from source_trace. Proved in VIEW-DRILLDOWN: all f1 node_ids present; f3 label offset list complete; instruction counts correct.

**Q5. Is rendering deterministic?**

Yes. Pure function of source_trace.json + source file lines. Re-render f1 and f3 produce identical strings. On-disk file matches in-memory render. Proved in VIEW-DETERMINISM.

**Q6. Does the renderer execute or affect VM behavior?**

**No.** The renderer reads source_trace.json and the .ig source file; writes only source_trace_view.md. It does not invoke the VM binary, does not modify vm_trace.json or source_trace.json. vm_trace.json result_digest is unchanged after rendering. Proved in VIEW-NONSEMANTIC.

**Q7. Does this authorize stepping or IDE UI?**

**No.** source_trace_view.md is a static artifact. No step counters, no breakpoint markers, no watch expressions, no interactive API. source_trace.json schema_version remains "source-trace-v0" after rendering. Proved in VIEW-CLOSED.

**Q8. What exact next route remains?**

- **LAB-VMTRACE-P3** (recommended first): expand fixture coverage to loops, nested matches, error paths. Proves grouping rule + non-contiguous detection hold under more complex patterns.
- **LAB-IDE-TRACE-VIEW-P2**: static HTML viewer with collapsible sections and syntax coloring.
- Do NOT authorize LAB-IDE-STEP-P1 until loop and nested-branch execution can be clearly explained.

---

## Design Decisions

**Non-contiguous check: `offsets != (min..max).to_a`:**
This is the natural test for "does the offset list have gaps?" It fails for single-element offsets (min==max, range has one element — correct) and correctly detects the f3 label gap. The note does not fire for f1 nodes (all consecutive) or for single-instruction nodes.

**Mnemonic truncation to first 6 + `...`:**
Long mnemonic lists (the label node has 10) are truncated to first 6 for readability. Full offsets are still shown — the reader can cross-reference with vm_trace.json if needed. This is a display choice, not a data loss.

**Source snippets via `source_lines[start_line-1].strip`:**
The start_line from source_span is 1-indexed. After stripping whitespace, the snippet fits on one line and is unambiguous. This works correctly for all three fixtures including the multi-line match expression (only the opening line is shown).

**Infrastructure heading is `[infrastructure]`, not `[infra]`:**
Matches the key chosen in source_trace.json ("infrastructure" array). Consistent naming across the two artifacts.

**Digests are passed through, not recomputed:**
The view embeds `inputs_digest` and `result_digest` verbatim from source_trace.json. This makes the provenance chain explicit: source_trace_view is a derived display, not an authoritative computation.

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

**LAB-VMTRACE-P3** — expand trace fixture coverage to loops, nested match expressions, and error paths. Verify:
1. Loop iterations produce multiple consecutive node entries for the same node_id (separate runs, not merged)
2. Nested match expressions produce correct non-contiguous offset notes
3. Error paths produce `status=error` with empty nodes/infrastructure

Or **LAB-IDE-TRACE-VIEW-P2** if a local HTML viewer is more immediately useful for human inspection.

Do not authorize LAB-IDE-STEP-P1 until loops and nested branches are covered.
