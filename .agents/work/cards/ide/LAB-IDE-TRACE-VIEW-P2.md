# LAB-IDE-TRACE-VIEW-P2 — Agent Return Packet

Static HTML trace viewer from existing `source_trace.json` and original `.ig` source text.

---

## Status

**Complete.** P2 proof 69/69. Regressions green: IDE-TRACE-VIEW-P1 50/50 and VMTRACE-P3 65/65.

---

## Changed Files

### Proof Runner

- `igniter-view-engine/proofs/verify_lab_ide_trace_view_p2.rb`

### Generated HTML Artifact

- `igniter-view-engine/out/trace_view_p2/source_trace_view.html`

### Lab Doc

- `igniter-lab/lab-docs/ide/lab-static-html-trace-viewer-v0.md`

### Portfolio

- `igniter-lab/.agents/portfolio-index.md`

### No VM/compiler source changes

Zero changes to VM/compiler implementation files.

---

## Proof Results

```text
LAB-IDE-TRACE-VIEW-P2: 69/69 PASS    0 FAIL

HTML2-INPUT:        8/8
HTML2-TRACE-SETUP: 13/13
HTML2-RENDER:       6/6
HTML2-METADATA:     8/8
HTML2-STRUCTURE:    8/8
HTML2-COVERAGE:     9/9
HTML2-DETERMINISM:  5/5
HTML2-NONSEMANTIC:  6/6
HTML2-CLOSED:       6/6
```

Regression gates:

```text
LAB-IDE-TRACE-VIEW-P1: 50/50 PASS
LAB-VMTRACE-P3:        65/65 PASS
```

---

## Key Findings

**Static viewer artifact:** `source_trace_view.html` is produced under `igniter-view-engine/out/trace_view_p2/`.

**Input model:** the renderer reads existing `source_trace.json` and original source text. The proof regenerates traces first, but rendering itself does not execute the VM.

**Output shape:** HTML includes contract/status/digests, execution timeline, node groups, infrastructure groups, source snippets, instruction counts, offsets, mnemonics, non-contiguous warnings, and fail-closed error panel.

**Static affordances:** uses `<details>/<summary>`, CSS styling, source-line highlighting, badges, and anchor links. No `<script>` tag. No external asset URL.

**Loop coverage:** repeated loop source-node offsets are visible in the HTML and are not collapsed.

**Nested branch coverage:** non-contiguous offsets are explained as jumped-over unexecuted bytecode, not missing data.

**Error coverage:** fail-closed trace displays error status and prefix execution; no successful output node is invented.

**Infrastructure boundary:** output/RET instructions are visually distinct and source-less.

**Determinism:** re-render is byte/digest identical; source_trace/vm_trace/bytecode_map digests unchanged.

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

---

## Recommended Next Route

**A. LAB-IDE-TRACE-VIEW-P3 static UX polish / source drilldown may open.**

LAB-IDE-STEP-P1 remains closed.
