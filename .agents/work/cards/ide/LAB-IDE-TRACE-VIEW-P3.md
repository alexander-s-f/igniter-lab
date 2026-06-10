# LAB-IDE-TRACE-VIEW-P3 — Static UX Polish and Source Drilldown

**Route:** LAB PROOF / STATIC VIEWER POLISH / NO DEBUGGER
**Track:** ide-static-trace-viewer-source-drilldown-and-ux-polish-v0
**Authority:** lab-only evidence
**Status:** COMPLETE — 80/80 PASS

---

## Summary

P3 extends the P2 static HTML viewer with source drilldown and readability polish while preserving the static/no-debugger boundary.

Generated artifact:

```text
igniter-view-engine/out/trace_view_p3/source_trace_view.html
```

Proof runner:

```text
igniter-view-engine/proofs/verify_lab_ide_trace_view_p3.rb
```

Lab doc:

```text
igniter-lab/lab-docs/ide/lab-static-trace-viewer-source-drilldown-v0.md
```

---

## Proof Result

```text
80 checks total: 80/80 PASS    0 FAIL

Sections:
HTML3-INPUT=8
HTML3-TRACE-SETUP=13
HTML3-RENDER=6
HTML3-METADATA=8
HTML3-SOURCE-DRILLDOWN=8
HTML3-NODE-INDEX=9
HTML3-OFFSETS=8
HTML3-LOOP-ERROR=8
HTML3-DETERMINISM=5
HTML3-CLOSED=7
```

Regression gates:

```text
LAB-IDE-TRACE-VIEW-P2: 69/69 PASS
LAB-VMTRACE-P3:        65/65 PASS
```

---

## Evidence

- Source context windows render around traced nodes.
- Active traced line is highlighted.
- Context lines preserve line numbers and are marked context-only.
- Node index / TOC links to node sections.
- Infrastructure groups are indexed separately.
- Error trace carries an error-path marker.
- Source-to-trace and trace-to-source anchors are present.
- Compact offset ranges improve readability.
- Raw offsets remain visible.
- Nested branch skipped offsets remain explicit: `7-8, 23-30, 32-39`.
- Loop repetition summary preserves repeated execution evidence.
- Error prefix summary says prefix execution only and does not invent a successful output node.
- Rendering leaves `source_trace.json`, `vm_trace.json`, and `bytecode_map.json` digest-identical.

---

## Boundary

The viewer is a proof-local static artifact only.

Closed:

- debugger
- stepper
- breakpoints
- watch expressions
- pause/resume
- live VM execution
- server
- websocket
- Tauri IPC
- JavaScript requirement
- schema mutation
- VM/compiler changes
- public/stable IDE API
- public/stable trace API

The closed vocabulary appears only in explicit boundary text.

---

## Next Route

**A. LAB-IDE-TRACE-VIEW-P4 — static multi-file/session comparison may open.**

LAB-IDE-STEP-P1 remains closed. Stepper work is not authorized by this card.
