# LAB-IDE-TRACE-VIEW-P4 — Static Multi-File / Session Trace Comparison

**Route:** LAB PROOF / STATIC TRACE COMPARISON / NO DEBUGGER
**Track:** ide-static-trace-viewer-multi-file-session-comparison-v0
**Authority:** lab-only evidence
**Status:** COMPLETE — 84/84 PASS

---

## Summary

P4 extends the static trace viewer line from one trace report to proof-local comparison across multiple existing trace artifacts.

Generated artifacts:

```text
igniter-view-engine/out/trace_view_p4/trace_comparison.html
igniter-view-engine/out/trace_view_p4/trace_comparison.json
```

Proof runner:

```text
igniter-view-engine/proofs/verify_lab_ide_trace_view_p4.rb
```

Lab doc:

```text
igniter-lab/lab-docs/ide/lab-static-trace-viewer-multi-file-session-comparison-v0.md
```

---

## Proof Result

```text
84 checks total: 84/84 PASS    0 FAIL

Sections:
P4-INPUT=8
P4-TRACE-SETUP=18
P4-RENDER=7
P4-METADATA=8
P4-DIFF-SUMMARY=12
P4-SAME-SOURCE=8
P4-CROSS-SOURCE=6
P4-IDENTICAL=5
P4-DETERMINISM=5
P4-CLOSED=7
```

Regression gates:

```text
LAB-IDE-TRACE-VIEW-P3: 80/80 PASS
LAB-VMTRACE-P3:        65/65 PASS
```

---

## Evidence

- HTML metadata table shows contract, status, input/result digests, source fixture id, event/instruction count, node count, and infrastructure count per trace.
- Diff summary compares status, result digest, node id sets, shared-node executed offsets, loop repetition counts, infrastructure, and error prefix vs success completion.
- Same-source nested success/error comparison is clear and truthful.
- Same-contract different-input branch comparison uses Green/Fast vs Red/Fast and proves changed executed offsets.
- Cross-source loop-vs-nested comparison is marked different-source and avoids false node equivalence.
- Identical trace comparison produces a no-diff baseline.
- Raw offsets remain visible in per-trace expandable details.
- Rendering leaves `source_trace.json`, `vm_trace.json`, and `bytecode_map.json` digest-identical.
- Provided trace order is preserved and documented.

---

## Boundary

The comparison report is a proof-local static artifact only.

Closed:

- debugger
- stepper
- breakpoints
- watch expressions
- live execution during render/compare
- server
- websocket
- Tauri IPC
- JavaScript requirement
- debugger session state
- schema mutation
- semantic-equivalence authority
- trace schema authority
- public/stable IDE API
- public/stable trace API

LAB-IDE-STEP-P1 remains closed.

---

## Next Route

**A. LAB-IDE-TRACE-VIEW-P5 — static trace packet export/share format may open.**

Stepper implementation remains unauthorized.
