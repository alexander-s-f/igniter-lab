# Lab Report: Igniter Debugger & Source-Mapping Feasibility — and the Interactive-Debugger Textbook

**Track:** lab-debugger-source-mapping-feasibility-and-teaching-instrument-v0 (out-of-track research)
**Card:** LAB-DEBUGGER-FEASIBILITY-P1
**Category:** ide / governance
**Date:** 2026-06-10
**Route:** REPORT / FEASIBILITY ANALYSIS / LAB-ONLY / NO IMPLEMENTATION AUTHORITY
**Status:** CLOSED — feasibility mapped; verdict FEASIBLE; phased route proposed; no implementation authorized

---

## Why this report exists

The goal is not "build another REPL." A classic REPL takes code, runs it, returns a value — and
stays a **black box**: it never explains *how* the result came to be. The vision here is the
opposite: an **interactive debugger** that makes Igniter execution *legible* — showing how code
runs, across **several dimensions and levels of abstraction** at once (source → typed contract →
semantic IR → bytecode → live machine state → observations/evidence) — and to build a **textbook
on top of that instrument**, where every lesson is something the learner can *watch execute*, not
just read about.

This report answers: **is that instrument feasible on the current Igniter lab platform, what
exists already, what is missing, and what is the safe route to build it?**

Authority: lab-only research report. `igniter-lang` is the language authority. PROPOSED Ch12 and
the Covenant are referenced as design context. **No code is changed; no implementation is
authorized by this report.** It informs future gate decisions; it does not make them.

---

## Verdict (read this first)

**FEASIBLE — and unusually well-matched to Igniter's design.** Confidence: **high** on the
instrument, **high** on the textbook concept, with **two foundational engineering gaps** that are
well-scoped and low-to-medium risk.

Three findings drive the verdict:

1. **Igniter is already an "honest", layered, inspectable system — the anti-black-box thesis is
   architectural, not aspirational.** The Covenant makes observation a *type*, evidence a *chain*,
   and uncertainty *non-discardable*; the compiler produces a concrete, readable artifact at every
   stage (AST → classified-with-fragment-class → typed → SemanticIR → bytecode), and the VM already
   emits an **observation stream** (`OP_EMIT_OBS`, temporal-read observations) and a result with
   `latency_us`. The multi-level abstraction the textbook wants to teach **already physically
   exists as separate artifacts.** Most languages would have to *invent* an IR to teach this;
   Igniter already exposes one at each layer.

2. **The host already exists.** `igniter-ide/` is a runnable Tauri 2 + SvelteKit 5 workbench with
   `monaco-editor`, `d3`, and `vis-network`, and it already ships the exact components a debugger
   textbook needs: `MonacoEditor`, `DebuggerPanel`, `ExecutionTracer` (frame-by-frame stepper),
   `TemporalTimeline` (D3 playback), `ContractDAG` (vis-network), `ObservationStream`,
   `ContractInspector`, `IntrospectionTreeInspectorNode`. The Rust backend bridge already exposes
   `load_contract`, `dispatch_traced`, `play_trace_playback`, `read_introspection_receipt`,
   `read_facts` (bitemporal). Cards `LAB-IDE-DEBUGGER-P1/P2`, `LAB-TAURI-IVF-P3..P20`,
   `LAB-IDE-VIEWER-P1` document this lineage. A "learning-by-contract" curriculum already exists in
   `lab-docs/tutorial/` (`LAB-TUTORIAL-P1..P5`).

3. **The two gaps are precise.** To turn "telemetry + trace playback" into a *synchronized,
   source-anchored, step-level* debugger, exactly two enabling capabilities are missing:
   - **(G-SRCMAP) Source-position provenance** — line/col is captured by the lexer but **dropped at
     parse time** and never reaches SIR or bytecode; the `Instruction` struct is `{opcode, args}`
     with no node/source reference. There is **no bytecode→source-line map today.**
   - **(G-TRACE) A per-instruction execution-trace recorder** — the VM runs to completion through a
     single central dispatch loop and exposes no step trace, no register/stack snapshots, no
     pause/step/breakpoint. (The files named `*_trace_receipt.json` are *result receipts* keyed by a
     transaction id — not execution traces.)

Both gaps are additive, well-isolated, and sit at single clean insertion points. Neither requires
touching `Result`/`Option`, the Covenant, the type system, or canon.

---

## 1. The conceptual core: why Igniter is the right substrate for this

A REPL teaches *what*. A debugger teaches *how*. Igniter can teach *how* across **layers of
abstraction simultaneously**, because each layer is a real, inspectable artifact that already
carries meaning the learner needs:

| Abstraction layer | Concrete artifact (exists today) | What it teaches the learner | Pedagogical lens |
|-------------------|----------------------------------|------------------------------|------------------|
| **Source** | `.ig` text (Monaco editor) | intent, syntax, contract shape | "what I wrote" |
| **Parse / AST** | parsed program (`contracts`, `compute` nodes, `Expr` tree) | structure, how syntax becomes a tree | "what the machine read" |
| **Classification** | classified nodes with **`fragment_class`** (CORE / STREAM / TEMPORAL / ESCAPE / EPISTEMIC) | *which world a computation lives in* — pure vs effectful vs temporal | "what kind of thing this is" |
| **Typecheck** | typed program, type env, OOF diagnostics | how types flow, why something is rejected | "why it's safe / why it failed" |
| **Semantic IR** | `semantic_ir_program.json` (deps, fragment, type, evidence/assumption refs) | the honest behavioral core, provenance, dependency DAG | "what it *means*, independent of syntax" |
| **Bytecode** | VM instructions (`OP_PUSH_RECORD`, `OP_GET_FIELD`, `OP_EQ`, `OP_JMP_UNLESS`, …) | how meaning becomes machine steps | "how it actually runs" |
| **Execution state** | stack + register file, per-step (not yet surfaced — G-TRACE) | data flowing through the machine | "watch the value move" |
| **Observations / evidence** | `observations[]` stream (`OP_EMIT_OBS`, temporal reads), `latency_us` | what the program *did to the world*, with provenance | "what it changed and how we know" |

This table is the textbook's spine. The same line of source can be illuminated from **eight
angles** — and Igniter is one of the very few languages where all eight are already first-class,
because the Covenant's honesty axioms *required* them to be. The "epistemic outcome" work in this
same governance track (LAB-EPISTEMIC-OUTCOME-P1..P4) is a live example: a learner could watch an
`unknown_external_state` envelope flow through routing in the VM and *see* that it never coerces to
success — honesty made visible.

**The differentiator vs every mainstream teaching tool:** Python Tutor / classic debuggers show
source + call stack + variables. Igniter can additionally show **fragment class** (this expression
is ESCAPE — it touches the world), **evidence/observation provenance** (this output is derived from
these inputs), and the **IR↔bytecode lowering** (this one `match`/`if` became these three
instructions). It teaches not just imperative state but *epistemic and effect honesty* — which is
the whole point of the language.

---

## 2. Current-state inventory (grounded)

### 2.1 The IDE host — exists and is purpose-built

`igniter-ide/` — **Tauri 2 + SvelteKit 5 + TypeScript**, deps incl. `monaco-editor@0.55`,
`d3@7.9`, `vis-network@10.1`. Components present in `igniter-ide/src/lib/components/`:

| Component | Role for a debugger-textbook |
|-----------|------------------------------|
| `MonacoEditor.svelte` | source pane (gutter/decoration API → breakpoints, line highlight) |
| `DebuggerPanel.svelte` | compile/run event log + artifact inspector (per `LAB-IDE-DEBUGGER-P1/P2`) |
| `ExecutionTracer.svelte` | frame-by-frame stepper UI — **the seat for step playback** |
| `TemporalTimeline.svelte` | D3 time-axis + trace playback / history buffer |
| `ContractDAG.svelte` | vis-network dependency graph of compute/input/output/loop nodes |
| `ObservationStream.svelte` | live observation/evidence event stream |
| `ContractInspector.svelte` | schema/structure inspector |
| `IntrospectionTreeInspectorNode.svelte` | recursive tree (GUI scene / structured artifact) |

Rust backend bridge (`src-tauri/src/commands.rs`) already exposes `load_contract`,
`dispatch_traced`, `play_trace_playback`, `simulate_trace_observation`,
`read_introspection_receipt`, `read_facts`. **The plumbing from compiler/VM to a Svelte UI already
exists.** (Note: I inventoried the repo; I did not boot the app in this report — "exists in repo
with passing cards", not "verified running here".)

### 2.2 VM observability — strong foundation, no step mode

- **Single central dispatch loop** (`igniter-vm/src/vm.rs`): one `while ip < n { match opcode }`.
  A per-instruction trace hook has exactly one clean insertion point.
- **Observation sink** already implemented: `OP_EMIT_OBS` pushes `{kind, observation_id, value}`;
  temporal reads (`OP_LOAD_AS_OF`) emit `temporal_live_read_observation` with `store/axis/as_of/
  result_value`. VM JSON output = `{status, result, latency_us, observations[]}`.
- **State exists but is not exposed:** `stack: Vec<Value>` + `registers: HashMap<i64,Value>` are
  method-local; no serialization, no snapshot, no inspection API.
- **No** `--trace`/`--step`/`--debug` flag, **no** breakpoint, **no** pause/resume.
- **Temporal reads** (`OP_LOAD_AS_OF`, `OP_LOAD_TICK`) → the observation log is effectively a
  time-stamped audit trail, which makes **replay / reverse-debugging reconstructible**.

### 2.3 Tutorial curriculum — exists as prose, not yet interactive

`lab-docs/tutorial/` ships a "learning-by-contract" path (`learning-contract-00-orientation`,
`-01-first-contract`, `-02-fail-closed`, `compiler-first-proof`, `forms-first-proof`,
`capability-passport-first-proof`, `igniter-learning-contracts.md`; cards `LAB-TUTORIAL-P1..P5`).
Model: **Intent → Contract → Evidence → Diagnostics → Reflection.** These are markdown today — the
debugger turns them into *executable, watchable* lessons.

---

## 3. Feasibility — Source Mapping (G-SRCMAP)

**Question:** can a running instruction be mapped back to a source line today? **No** — but the
raw material exists and the fix is well-scoped.

### Per-stage provenance (surveyed)

| Stage | Position carried? | Evidence |
|-------|-------------------|----------|
| Lexer (Ruby + Rust) | ✅ line/col on every token (`Token{type,value,line,col}`) | `igniter-lang/lib/.../parser.rb`; `igniter-compiler/src/lexer.rs` |
| Parser / AST | ❌ dropped — AST nodes carry no span (only **invariants** keep `source_span`) | `igniter-compiler/src/parser.rs` `Expr`/`Compute` have no line |
| Classifier / Typecheck | ❌ no span added; diagnostics emit `line: null` / `span: null` | `classifier.rb`; `semanticir_emitter.rb` `oof()` |
| Semantic IR | ❌ nodes have `deps/expr/fragment/kind/name/type` but **no line/span**; program has `source_hash`/`source_path` | sample `semantic_ir_program.json` |
| Bytecode | ❌ `Instruction { opcode, args }` — no node id, no source ref | `igniter-vm/src/instructions.rs:44` |
| Program identity | ✅ `program_id`, `source_hash`, `source_path`, stable node **names** | SIR program header |

**Conclusion:** position is captured at lex and **discarded at parse**; downstream identity is by
**node name**, not source location. A debugger can recover the *source text* (via `source_path`/
`source_hash`) and the *node name* of an instruction's origin (if register/name allocation is
surfaced), but **cannot point at a source line/column today.**

### Minimal path to a real source map

A clean, additive provenance thread — no semantics change:

1. **`node_id` + `span` at parse:** attach a stable `node_id` and the originating token's
   `{line, col, end}` to each AST node (the data is already in the token; today it is thrown away).
   Extend the existing `source_span` pattern (already done for invariants) to compute/input/output
   nodes.
2. **Propagate through SIR:** carry `node_id` + `span` on every SIR node (classifier/typechecker/
   emitter pass-through — the same way `fragment` and `type` already ride along).
3. **Attach to bytecode:** add an optional `node_id`/`span` to `Instruction` (or a parallel
   `Vec<SourceSpan>` indexed by instruction offset, to keep the hot struct lean), populated by the
   VM compiler's `emit()`.
4. **Emit a `.sourcemap` artifact** alongside `semantic_ir_program.json`: `instruction_offset →
   {node_id, contract, span}` and `node_id → span`. This is the single artifact the IDE consumes.

**Dual-toolchain caveat (important):** there are **two** compilers — Ruby canon (`igniter-lang`)
and Rust lab (`igniter-compiler`) — and the VM runs the Rust SIR. Source-map provenance must be
implemented where the **VM-executed** SIR is produced (Rust) for the debugger to work end-to-end,
and ideally mirrored in Ruby for parity. (This is the same Ruby↔Rust asymmetry surfaced in
PROP-044-P7-READINESS — worth tracking as one cross-cutting concern.)

**Effort: medium. Risk: low.** Additive metadata; deterministic; no behavior change. The chief
risk is *parity* (Ruby vs Rust spans agreeing) and *staleness* (source-map must be invalidated when
`source_hash` changes — already a stable key).

---

## 4. Feasibility — Execution Trace & Stepping (G-TRACE)

**Question:** can the debugger show step-by-step low-level execution? **Not today** — but the VM's
shape makes it cheap.

- **One insertion point.** The single `while`/`match` dispatch loop means a trace hook
  (`ip, opcode, args, node_id, stack-snapshot, register-delta`) added once captures *every* step.
- **State is in hand.** `stack` and `registers` are right there in the loop; snapshotting them per
  step (or recording deltas to bound volume) is straightforward.
- **Reuse the observation channel.** Observations already flow to a sink and to the IDE's
  `ObservationStream`; the step trace is a parallel, richer channel.

### Minimal path

1. **Trace-record mode** (`--trace` or a `VM::execute_traced`): emit a `TraceEvent` per instruction
   `{ip, opcode, node_id, span, stack_after, reg_delta, fragment}` to an in-memory log; serialize to
   a `.trace.json` artifact. **Post-mortem first** (record a full run, then scrub through it) — this
   is simpler and safer than live suspension and is exactly what a textbook needs (deterministic,
   replayable lessons).
2. **Feed the existing UI.** `ExecutionTracer.svelte` + `TemporalTimeline.svelte` already do
   frame-by-frame playback; point them at `.trace.json` joined with `.sourcemap` so each frame
   highlights the **source line**, the **SIR node**, the **bytecode instruction**, and the **live
   stack/registers** in synchronized panes.
3. **Interactive stepping later** (optional): pause/step/continue + breakpoints by source line
   (line → instruction offsets via the source map). Medium effort; only needed once post-mortem
   replay proves the model.
4. **Reverse / temporal debugging** (optional, high-value, low-mechanism): the observation log +
   `OP_LOAD_AS_OF` already record temporal reads; replaying the trace backward is "scrub the
   recorded log", not "rewind the live VM" — so reverse stepping is mostly a UI affordance over the
   recorded trace.

**Effort: low–medium (post-mortem) / medium (interactive). Risk: low.** Trace volume is the main
operational risk (snapshotting full stack per step on big programs) — mitigate with delta-recording
and per-contract scoping. Trace mode must be **opt-in** and must never alter execution semantics
(record-only).

---

## 5. The synchronized multi-pane debugger (the instrument)

With G-SRCMAP + G-TRACE, the existing IDE composes into the teaching instrument with little new UI:

```
┌─ Source (MonacoEditor) ────────────┐  ┌─ Semantic IR (Inspector/DAG) ──────┐
│ line highlighted for current step  │  │ active SIR node, fragment class,    │
│ breakpoints in the gutter          │  │ deps, evidence/assumption refs      │
└────────────────────────────────────┘  └─────────────────────────────────────┘
┌─ Bytecode (new small pane) ────────┐  ┌─ Machine state (TemporalTimeline) ─┐
│ instructions for the active node,  │  │ stack + registers at this step,     │
│ current instruction marked          │  │ scrub timeline (post-mortem replay) │
└────────────────────────────────────┘  └─────────────────────────────────────┘
┌─ Observations / Evidence (ObservationStream) ─────────────────────────────────┐
│ what the program did to the world at this step, with provenance + latency      │
└────────────────────────────────────────────────────────────────────────────────┘
        ▲ one "step" cursor drives ALL panes via (node_id ↔ span ↔ ip)
```

The unifying key is `node_id`: source span ↔ SIR node ↔ bytecode offset ↔ trace frame ↔
observations all join on it. That single thread is precisely what G-SRCMAP introduces.

---

## 6. The textbook: "dimensional learning"

The instrument enables a textbook genre that a REPL cannot:

- **Every concept is watchable.** "Pure vs effect" isn't a paragraph — the learner steps a contract
  and *sees* an expression light up CORE vs ESCAPE in the fragment pane. "Timeout is not failure"
  (Covenant P15) isn't a rule to memorize — they watch `unknown_external_state` route to
  `reconcile`, never to `accept`.
- **Zoom across abstraction.** The same lesson can be read at the "source" level (beginner), the
  "SIR/fragment" level (intermediate: what does this *mean*), or the "bytecode/state" level
  (advanced: how does it *run*). One artifact, three depths — the "several dimensions and levels"
  the brief asks for.
- **Honesty as curriculum.** Igniter's distinctive subjects — evidence chains, typed observation
  (real/model/human), the epistemic state machine, capability denial-as-data — are *exactly* the
  things a black-box REPL hides and this debugger reveals. The textbook's spine is the abstraction
  table in §1; each row is a lens, each lesson picks the lens(es) it needs.
- **Reproducible by construction.** A lesson is a `.ig` + recorded `.trace.json` + `.sourcemap`;
  it replays identically (deterministic post-mortem trace). Lessons become *assets*, not live demos
  that might drift.

This rides on the existing `lab-docs/tutorial/` "learning-by-contract" model — it makes
`Intent → Contract → Evidence → Diagnostics → Reflection` *executable*.

---

## 7. Risk & boundary map

| Risk / boundary | Severity | Mitigation |
|-----------------|----------|------------|
| Source-map parity Ruby↔Rust | medium | Implement where VM SIR is produced (Rust) first; parity-test against Ruby spans (cf. PROP-044-P7-READINESS asymmetry) |
| Source-map staleness | low | Key the `.sourcemap` to `source_hash`; invalidate on change |
| Trace volume on large programs | medium | Delta-record register/stack; per-contract scoping; opt-in only |
| Trace mode altering semantics | high if mishandled | Record-only hook; never branch execution on trace state; prove equivalence to untraced run |
| Lab-only artifact volatility | medium | All shapes (`.sourcemap`, `.trace.json`) are experimental; textbook must label "lab evidence, not canon" |
| Over-claiming canon | high | The debugger visualizes *lab* compiler/VM behavior; Ch12/Covenant referenced as proposed; never present lab output as canon authority |
| Dual-toolchain confusion in lessons | medium | Lessons must state which toolchain (Rust VM) produced the trace |

**Permanently out of scope here:** any code change; new opcodes; `Value` changes; canon spec /
Covenant edits; public/stable API; presenting lab behavior as canon.

---

## 8. Phased route (proposed IDD cards — none authorized here)

The instrument is the prerequisite for the textbook; build the enablers first, smallest viable
slice each.

| Card (proposed) | Scope | Gate / proof |
|-----------------|-------|--------------|
| **LAB-SRCMAP-P1** | `node_id` + `span` at parse → propagate to SIR; emit `node_id → span` map. **Rust `igniter-compiler` first** (VM-executed path), parity-anchored to Ruby. No bytecode change yet. | source spans present on SIR nodes; `.sourcemap` (node-level) emitted; round-trips to source text; non-position SIR byte-stable |
| **LAB-SRCMAP-P2** | Attach `node_id`/`span` to bytecode (parallel span table in VM compiler); extend `.sourcemap` to `instruction_offset → node_id`. | every instruction resolves to a source span; existing VM proofs green |
| **LAB-VMTRACE-P1** | Record-only `execute_traced` mode → `.trace.json` (`ip/opcode/node_id/stack/reg-delta`); **prove equivalence to untraced run** (same result/observations). Post-mortem only. | traced run ≡ untraced run; trace replays a known fixture (e.g. the P4 reconciliation routing) frame-by-frame |
| **LAB-IDE-STEP-P1** | Wire `ExecutionTracer`/`TemporalTimeline`/`Monaco` to `.trace.json` ⋈ `.sourcemap`: one step cursor drives synchronized source/SIR/bytecode/state/observation panes. | a recorded run scrubs with synchronized highlight across ≥4 panes |
| **LAB-TEXTBOOK-P1** | Lesson format = `.ig` + recorded trace + sourcemap + lens metadata; convert 1–2 existing `learning-contract-*` lessons into watchable form. | one lesson replays deterministically at 3 abstraction depths |
| **LAB-DEBUG-REVERSE-P1** *(optional)* | Reverse/temporal scrubbing over the recorded trace + observation log; breakpoints by source line. | backward step + line breakpoint on a recorded run |

Recommended first card: **LAB-SRCMAP-P1** — it is the keystone (`node_id` unifies every pane) and
the smallest piece that unblocks everything after it.

---

## Explicit answers

- **Is an Igniter debugger feasible?** **Yes** — the VM's single dispatch loop + observation sink +
  the existing Tauri/Svelte IDE make it a well-scoped build, not a green-field one.
- **Is source mapping feasible?** **Yes**, but it must be **built** — positions are captured by the
  lexer and dropped at parse; the fix is an additive `node_id`/`span` thread + a `.sourcemap`
  artifact. No source map exists today.
- **Does the platform already have what's needed?** Partially and substantially: IDE shell,
  telemetry bridge, trace-playback UI, observation stream, DAG, Monaco — yes. Source provenance and
  a per-instruction trace recorder — no (the two gaps).
- **Is the "anti-black-box / multi-dimensional teaching" vision sound?** **Yes, and it is the
  natural extension of Igniter's design** — the honest, layered IR is exactly what makes
  dimensional learning possible; few languages could do this without inventing the substrate first.
- **What blocks it / what's the route?** Two enablers (source-map provenance, trace recorder), then
  IDE synchronization, then the lesson format. See the phased route. **Keystone: LAB-SRCMAP-P1.**
- **Does any of this touch canon / require canon changes?** **No.** Lab tooling + additive
  metadata; canon language semantics untouched.

---

## Gap Packet

```
report:     igniter-debugger-and-source-mapping-feasibility / v0
status:     CLOSED — feasibility mapped; verdict FEASIBLE; phased route proposed
authority:  ide / governance / lab_only
date:       2026-06-10

verdict:    FEASIBLE (high confidence on instrument + textbook concept)
thesis:     Igniter is an honest layered IR by design → multi-level "dimensional learning"
            is architectural, not aspirational (anti-black-box vs REPL).

exists_today:
  ide_host:        igniter-ide Tauri2+Svelte5 (Monaco/d3/vis-network); DebuggerPanel,
                   ExecutionTracer, TemporalTimeline, ContractDAG, ObservationStream
  vm_observability: single dispatch loop; OP_EMIT_OBS + observation sink; latency_us;
                   temporal OP_LOAD_AS_OF audit trail
  curriculum:      lab-docs/tutorial learning-by-contract (LAB-TUTORIAL-P1..P5)
  abstraction_layers: source→AST→classified(fragment_class)→typed→SIR→bytecode→obs (all real artifacts)

gaps:
  G-SRCMAP:  source line/col dropped at parse; Instruction={opcode,args} no provenance;
             NO bytecode→source map today. Fix = node_id+span thread + .sourcemap artifact.
  G-TRACE:   VM runs to completion; no step/snapshot/breakpoint. "*_trace_receipt.json" are
             RESULT receipts, not execution traces. Fix = record-only execute_traced + .trace.json.

caveats:    dual toolchain (Ruby canon vs Rust lab VM) — implement source-map on Rust SIR path
            first, parity to Ruby (same asymmetry as PROP-044-P7-READINESS); trace must be
            record-only (no semantic change); lab-only artifacts; never present as canon.

route (proposed, none authorized):
  keystone:  LAB-SRCMAP-P1 (node_id+span parse→SIR, Rust-first, .sourcemap)
  then:      LAB-SRCMAP-P2 (bytecode spans) → LAB-VMTRACE-P1 (record-only trace, equivalence-proved)
             → LAB-IDE-STEP-P1 (synchronized panes) → LAB-TEXTBOOK-P1 (watchable lessons)
  optional:  LAB-DEBUG-REVERSE-P1 (reverse/temporal scrubbing + line breakpoints)

canon_touched: NO   implementation_authorized: NO
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Feasibility report + repo
inventory only (the IDE was inventoried in-repo, not booted in this report). No code changed; no
implementation authorized; no opcodes; no `Value` change; no source-map/trace code written. Canon
spec / Covenant untouched; Ch12 referenced as proposed, not accepted canon. `Result`/`Option`
untouched. Old Ruby framework surfaces not used as language authority. Lab behavior not accepted as
canon. This report informs future gate decisions; it does not make them.
