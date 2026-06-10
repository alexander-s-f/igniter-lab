# Lab: Static HTML Trace Viewer v0

**Track:** LAB-IDE-TRACE-VIEW-P2
**Status:** Complete
**Authority:** lab_only — evidence only; not canon, not public API

---

## Purpose

LAB-IDE-TRACE-VIEW-P1 proved a deterministic markdown trace narrative from `source_trace.json`. LAB-VMTRACE-P3 then closed the immediate coverage gap for loop repetition, nested branch jumps, fail-closed prefix traces, infrastructure boundaries, and non-contiguous offsets.

P2 proves that the same trace material can be rendered as a proof-local static HTML artifact:

```text
igniter-view-engine/out/trace_view_p2/source_trace_view.html
```

The viewer is read-only and explanatory. It does not execute the VM, open a live session, mutate trace artifacts, define a trace schema, or create debugger semantics.

---

## Proof Runner

`igniter-view-engine/proofs/verify_lab_ide_trace_view_p2.rb`

The proof runner regenerates P3 trace fixtures, derives `source_trace.json`, then calls a renderer that reads only:

- `source_trace.json`
- original `.ig` source text

The renderer may be used after trace artifacts exist. It writes only `source_trace_view.html`.

---

## Proof Result

```text
69 checks total: 69/69 PASS    0 FAIL

Sections:
HTML2-INPUT=8
HTML2-TRACE-SETUP=13
HTML2-RENDER=6
HTML2-METADATA=8
HTML2-STRUCTURE=8
HTML2-COVERAGE=9
HTML2-DETERMINISM=5
HTML2-NONSEMANTIC=6
HTML2-CLOSED=6
```

Regression gates:

```text
LAB-IDE-TRACE-VIEW-P1: 50/50 PASS
LAB-VMTRACE-P3:        65/65 PASS
```

---

## Viewer Contents

The generated HTML includes:

- contract name
- execution status
- inputs digest
- result digest
- execution timeline
- node groups
- infrastructure groups
- source line/snippet
- instruction count
- offsets
- mnemonics
- non-contiguous offset warning
- fail-closed error status panel

The UI is static HTML/CSS only. It uses:

- `<details>` / `<summary>` for collapsible sections
- badges for node / infrastructure / ok / error status
- line-highlighted source snippets
- anchor links to node ids
- inline CSS

It contains no `<script>` tag and no external asset URL.

---

## Coverage Findings

### Loop Trace

The HTML shows the P3 loop source node `loop:LoopContract.Accumulate` with repeated offsets. This makes repeated loop execution visible rather than collapsed into unique offsets.

The proof confirms the rendered offset list is present and that the source trace still has repeated offsets (`instruction_offsets.length > instruction_offsets.uniq.length`).

### Nested Branch Trace

The HTML shows `compute:VmNestedMatch.message` and its non-contiguous offset list for the Green/Fast path.

The viewer renders this warning:

```text
Non-contiguous offsets: control flow jumped over unexecuted bytecode. This is expected for branches and is not missing trace data.
```

This preserves the P3 interpretation: skipped offsets are branch alternatives, not missing data.

### Error Trace

The fail-closed trace renders an error badge and error panel:

```text
Fail-closed trace: prefix execution is shown up to the last recorded instruction. No successful output is inferred.
```

The proof confirms the error prefix offsets are visible and that the HTML does not invent an `output:VmNestedMatch.message` node.

### Infrastructure

Infrastructure groups render with a distinct badge and source-less note:

```text
No source attribution: output loading / return instructions are VM infrastructure.
```

This keeps VM output/RET instructions visually separate from source-origin nodes.

---

## Determinism

The proof renders the same trace set twice and confirms:

- returned HTML strings are identical
- `source_trace_view.html` digest is identical
- on-disk HTML matches the returned string
- `source_trace.json` schema remains `source-trace-v0`
- `source_trace.json`, `vm_trace.json`, and `bytecode_map.json` digests are unchanged by rendering

---

## Non-Semantic Boundary

The proof reruns untraced successful fixtures after rendering:

- loop result remains `60`
- nested branch result remains `"go_fast"`
- traced result digests still match untraced result JSON digests

Rendering is a pure display step over existing artifacts. It does not modify VM/compiler/runtime behavior.

---

## Closed Surfaces

- No debugger
- No stepper
- No breakpoints
- No watch expressions
- No live execution
- No server
- No JavaScript execution requirement
- No websocket
- No Tauri IPC
- No VM/compiler changes
- No schema changes
- No public/stable IDE API
- No public/stable trace API

---

## Next Route

**A. LAB-IDE-TRACE-VIEW-P3 static UX polish / source drilldown may open.**

P3 should stay static and proof-local: richer source drilldown, source-line context windows, better offset grouping, or visual polish are acceptable. LAB-IDE-STEP-P1 remains closed.
