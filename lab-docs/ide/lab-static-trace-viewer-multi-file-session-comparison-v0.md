# Lab: Static Trace Viewer Multi-File Session Comparison v0

**Track:** LAB-IDE-TRACE-VIEW-P4
**Status:** Complete
**Authority:** lab_only — evidence only; not canon, not public API

---

## Purpose

LAB-IDE-TRACE-VIEW-P3 proved source drilldown and static UX polish for one static trace report. P4 extends the viewer line to compare multiple existing trace artifacts across source files, inputs, and sessions.

Generated artifacts:

```text
igniter-view-engine/out/trace_view_p4/trace_comparison.html
igniter-view-engine/out/trace_view_p4/trace_comparison.json
```

The comparison report is read-only and explanatory. It does not execute the VM during render/compare, open a live session, mutate trace artifacts, decide semantic equivalence, define trace schema authority, or create debugger semantics.

---

## Proof Runner

`igniter-view-engine/proofs/verify_lab_ide_trace_view_p4.rb`

The proof setup regenerates existing fixture trace artifacts for:

- nested branch Green/Fast success
- nested branch Red/Fast success using a temporary input file
- nested branch Blue/Fast fail-closed error
- loop trace
- basic successful trace

The comparison renderer reads:

- existing `source_trace.json`
- original `.ig` source text
- `vm_trace.json` / `bytecode_map.json` only as supporting data

It writes only `trace_comparison.html` and `trace_comparison.json`.

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

## Comparison Metadata

The HTML metadata table shows, per trace:

- contract name
- status
- inputs digest
- result digest
- source fixture id
- event / instruction count
- node count
- infrastructure count

The optional JSON summary records the same proof-local comparison facts under `schema_version = "trace-comparison-proof-v0"`.

---

## Diff Summary

P4 compares:

- status differences
- result digest differences
- node id set differences
- executed offset differences for shared node ids
- loop repetition count differences
- infrastructure differences
- error prefix vs success completion

The report keeps raw offsets visible in per-trace details while also showing compact comparison facts.

---

## Same-Source Cases

The nested success-vs-error comparison is marked same-source and exact node ids are treated as comparable only because the source fixture id matches.

The nested Green/Fast vs Red/Fast comparison proves same contract / different input branch behavior. The proof checks changed executed offsets for the shared `compute:VmNestedMatch.message` node.

The error-vs-success comparison explicitly says one side is a fail-closed prefix and the other reaches successful completion. It does not infer semantic equivalence.

---

## Cross-Source Case

The loop-vs-nested comparison is marked different-source. It groups by fixture/source first and does not pretend node ids are equivalent unless ids match exactly.

The proof confirms the heterogeneous loop/nested comparison has no shared node ids and displays the not-directly-comparable explanation.

---

## Identical Baseline

The identical nested trace comparison produces a no-diff baseline:

- no changed shared node offsets
- no added nodes
- no removed nodes
- no status/result/infrastructure/loop repetition differences

This proves the comparison renderer can distinguish no-diff from real comparison changes.

---

## Determinism

The proof renders the same comparison input set twice and confirms:

- returned HTML strings are identical
- HTML digest is identical
- JSON digest is identical
- `source_trace.json`, `vm_trace.json`, and `bytecode_map.json` digests are unchanged
- ordering policy is explicit: provided trace order is preserved

---

## Closed Surfaces

- No debugger
- No stepper
- No breakpoints
- No watch expressions
- No live execution during render/compare
- No server
- No JavaScript execution requirement
- No websocket
- No Tauri IPC
- No debugger session state
- No schema mutation
- No semantic-equivalence authority
- No public/stable IDE API
- No public/stable trace API

The closed vocabulary appears only in explicit boundary text.

---

## Next Route

**A. LAB-IDE-TRACE-VIEW-P5 — static trace packet export/share format may open.**

LAB-IDE-STEP-P1 remains closed. A readiness review may be considered separately, but this card does not authorize stepper implementation.
