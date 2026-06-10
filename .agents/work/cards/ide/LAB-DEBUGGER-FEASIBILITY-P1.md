# Card: LAB-DEBUGGER-FEASIBILITY-P1
**Category:** ide / governance
**Track:** lab-debugger-source-mapping-feasibility-and-teaching-instrument-v0 (out-of-track research)
**Status:** CLOSED — REPORT COMPLETE
**Gate result:** N/A — feasibility report (no proof runner); verdict FEASIBLE
**Date closed:** 2026-06-10
**Route:** REPORT / FEASIBILITY ANALYSIS / LAB-ONLY / NO IMPLEMENTATION AUTHORITY

---

## Goal

Analyze the feasibility of an Igniter **interactive debugger + source mapping**, as the instrument
under a **textbook** that teaches by *showing how code executes across multiple abstraction levels*
(source → AST → fragment-classified → typed → SemanticIR → bytecode → live state → observations) —
the anti-black-box alternative to a classic REPL.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Feasibility report | `lab-docs/ide/igniter-debugger-and-source-mapping-feasibility-report-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/ide/LAB-DEBUGGER-FEASIBILITY-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Verdict

**FEASIBLE** — high confidence on both the instrument and the textbook concept. Igniter is unusually
well-matched: the Covenant's honesty axioms already force a real, inspectable artifact at **every**
abstraction layer, so "dimensional learning" is architectural, not aspirational. The IDE host
already exists.

---

## Findings (grounded)

**Exists today:**
- `igniter-ide/` — Tauri 2 + SvelteKit 5 (Monaco / d3 / vis-network); components `MonacoEditor`,
  `DebuggerPanel`, `ExecutionTracer` (frame stepper), `TemporalTimeline` (D3 playback), `ContractDAG`,
  `ObservationStream`, `ContractInspector`. Rust bridge: `load_contract`, `dispatch_traced`,
  `play_trace_playback`, `read_introspection_receipt`, `read_facts`. Cards `LAB-IDE-DEBUGGER-P1/P2`,
  `LAB-TAURI-IVF-P3..P20`, `LAB-IDE-VIEWER-P1`.
- VM observability: single central dispatch loop; `OP_EMIT_OBS` + observation sink; `latency_us`;
  temporal `OP_LOAD_AS_OF` audit trail.
- Curriculum: `lab-docs/tutorial/` learning-by-contract (`LAB-TUTORIAL-P1..P5`).
- All 8 abstraction layers are real artifacts (incl. `fragment_class` CORE/STREAM/TEMPORAL/ESCAPE).

**Two foundational gaps:**
- **G-SRCMAP** — source line/col captured by lexer, **dropped at parse**; `Instruction{opcode,args}`
  has no provenance; **no bytecode→source map today.** Fix: additive `node_id`+`span` thread parse→
  SIR→bytecode + a `.sourcemap` artifact.
- **G-TRACE** — VM runs to completion; no step/snapshot/breakpoint. `*_trace_receipt.json` are
  *result receipts*, not execution traces. Fix: record-only `execute_traced` → `.trace.json`.

**Caveat:** dual toolchain — Ruby canon vs Rust lab VM. Source-map must be built on the **Rust**
SIR path (VM-executed) first, parity-anchored to Ruby (same asymmetry as PROP-044-P7-READINESS).

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Debugger feasible? | **YES** — VM dispatch loop + observation sink + existing Tauri/Svelte IDE = scoped build |
| Source mapping feasible? | **YES, but must be built** — positions dropped at parse; no map today |
| Platform already has what's needed? | Substantially (IDE/telemetry/trace-UI/observations) + 2 gaps (provenance, trace recorder) |
| Anti-black-box / multi-dimensional vision sound? | **YES** — natural extension of Igniter's honest layered IR |
| Blocks / route? | 2 enablers → IDE sync → lesson format; keystone **LAB-SRCMAP-P1** |
| Touches canon? | **NO** — lab tooling + additive metadata |

---

## Proposed Route (none authorized here)

```
keystone:  LAB-SRCMAP-P1   node_id+span parse→SIR (Rust-first, parity to Ruby) + .sourcemap
then:      LAB-SRCMAP-P2   bytecode spans (instruction_offset→node_id)
           LAB-VMTRACE-P1  record-only execute_traced → .trace.json (PROVE equivalence to untraced)
           LAB-IDE-STEP-P1 synchronized panes (source⋈SIR⋈bytecode⋈state⋈observations, one cursor)
           LAB-TEXTBOOK-P1 watchable lesson = .ig + .trace.json + .sourcemap + lens metadata
optional:  LAB-DEBUG-REVERSE-P1  reverse/temporal scrubbing + source-line breakpoints
```

---

## Gap Packet

```
report:     igniter-debugger-and-source-mapping-feasibility / v0
status:     CLOSED — verdict FEASIBLE; phased route proposed
authority:  ide / governance / lab_only
date:       2026-06-10

verdict:    FEASIBLE (instrument + textbook)
exists:     igniter-ide (Tauri2/Svelte5, debugger+tracer+timeline+DAG+observation panes);
            VM single-loop + OP_EMIT_OBS observation sink; learning-by-contract curriculum;
            8 real abstraction-layer artifacts incl. fragment_class
gaps:       G-SRCMAP (no source provenance past lexer; no bytecode→source map);
            G-TRACE (no per-instruction trace/step/breakpoint; receipts ≠ traces)
caveat:     dual toolchain — build source-map on Rust VM SIR path first, parity to Ruby
keystone:   LAB-SRCMAP-P1
canon_touched: NO   implementation_authorized: NO
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Feasibility report + repo
inventory (IDE inventoried, not booted). No code changed; no implementation authorized; no
source-map/trace code; no opcodes; no `Value` change. Canon spec / Covenant untouched; Ch12
referenced as proposed. `Result`/`Option` untouched. Old Ruby framework surfaces not used as
language authority. Lab behavior not accepted as canon. This card informs future gate decisions; it
does not make them.
