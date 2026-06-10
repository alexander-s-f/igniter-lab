# Lab: Static Trace Viewer Source Drilldown v0

**Track:** LAB-IDE-TRACE-VIEW-P3
**Status:** Complete
**Authority:** lab_only — evidence only; not canon, not public API

---

## Purpose

LAB-IDE-TRACE-VIEW-P2 proved a read-only static HTML trace viewer from existing `source_trace.json` and source text. P3 keeps the same static/no-debugger boundary and improves readability:

```text
igniter-view-engine/out/trace_view_p3/source_trace_view.html
```

The viewer remains explanatory only. It does not execute the VM, open a live session, mutate trace artifacts, define trace schema authority, or create debugger semantics.

---

## Proof Runner

`igniter-view-engine/proofs/verify_lab_ide_trace_view_p3.rb`

The runner regenerates the same fixture set used by P2/P3 trace coverage:

- loop trace
- nested branch trace
- fail-closed error trace
- basic successful trace

The renderer reads:

- existing `source_trace.json`
- original `.ig` source text
- `vm_trace.json` / `bytecode_map.json` only as supporting data for displayed error facts

It writes only `source_trace_view.html`.

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

## UX Improvements

P3 adds:

- source context windows around traced source lines
- highlighted active traced line
- context-only labels for nearby source lines
- node index / table of contents per trace case
- infrastructure entries separate from source nodes
- source-to-trace and trace-to-source anchors
- compact offset ranges
- raw offsets retained beside compact ranges
- explicit executed-vs-skipped branch explanation
- loop repetition summary
- error prefix summary
- inline CSS polish only

No JavaScript or external assets are required.

---

## Source Drilldown

Every traced source node renders a context window around the active line. The active line is highlighted and labeled as executed. Neighboring lines are labeled `context only`.

The proof checks that context line numbers are preserved and that context-only lines are not claimed as executed attribution.

---

## Node Index

Each trace case includes a node index:

- source nodes link to their trace sections
- source jump links point into source context windows
- infrastructure groups appear separately
- error trace entries carry an error-path marker

This improves scanability without introducing stateful navigation or session behavior.

---

## Offset Grouping

The viewer renders compact offset ranges for readability and keeps raw offsets visible for trace fidelity.

For the nested branch fixture, the rendered compact path is:

```text
0-6, 9-22, 31, 40
```

The skipped in-between offsets remain visible:

```text
7-8, 23-30, 32-39
```

The branch explanation states that skipped offsets are explained by branch/jump control flow, not missing trace data.

---

## Loop Summary

The loop trace shows repeated execution of `loop:LoopContract.Accumulate`.

The summary states that repeated execution is trace evidence and is not collapsed as duplicate data. Raw offsets remain visible, preserving the repeated source-node events proven by LAB-VMTRACE-P3.

---

## Error Summary

The fail-closed trace shows an error prefix summary:

- prefix execution only is shown
- no successful output node is inferred
- unsupported/fail-closed offset facts are surfaced from supporting bytecode map data when available

The proof confirms the HTML does not invent `output:VmNestedMatch.message`.

---

## Determinism

The proof renders the same trace set twice and confirms:

- returned HTML strings are identical
- `source_trace_view.html` digest is identical
- on-disk HTML matches the returned string
- `source_trace.json` schema remains `source-trace-v0`
- `source_trace.json`, `vm_trace.json`, and `bytecode_map.json` digests are unchanged by rendering

---

## Closed Surfaces

- No debugger
- No stepper
- No breakpoints
- No watch expressions
- No pause/resume
- No live execution
- No server
- No JavaScript execution requirement
- No websocket
- No Tauri IPC
- No VM/compiler changes
- No schema mutation
- No public/stable IDE API
- No public/stable trace API

The closed vocabulary appears only in explicit boundary text.

---

## Next Route

**A. LAB-IDE-TRACE-VIEW-P4 — static multi-file/session comparison may open.**

LAB-IDE-STEP-P1 remains closed. Any stepper/readiness work requires a separate readiness-only review card before implementation.
