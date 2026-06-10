# Lab: VM Trace Control-Flow and Error Coverage v0

**Track:** LAB-VMTRACE-P3
**Status:** Complete
**Authority:** lab_only — evidence only; not canon, not public API

---

## Purpose

LAB-VMTRACE-P1 proved opt-in instruction tracing. LAB-VMTRACE-P2 proved `source_trace.json` aggregation. LAB-IDE-TRACE-VIEW-P1 proved a deterministic readable static trace view.

P3 hardens the trace stack against deeper control-flow and fail-closed execution before any richer viewer or stepper work:

1. loop-shaped execution,
2. nested branch execution,
3. error / fail-closed execution,
4. non-contiguous instruction offsets caused by jumps,
5. infrastructure instructions with no source attribution.

No debugger, stepper, breakpoint, watch expression, UI, Tauri integration, runtime semantic change, or public/stable trace API is introduced.

---

## Artifacts

### Fixtures

Under `igniter-view-engine/fixtures/source_map/`:

- `vmtrace_p3_loop.ig`
- `vmtrace_p3_nested_branch.ig`
- `inputs_vmtrace_p3_loop.json`
- `inputs_vmtrace_p3_nested_green_fast.json`
- `inputs_vmtrace_p3_nested_unknown_signal.json`

### Proof Runner

`igniter-view-engine/proofs/verify_lab_vmtrace_p3.rb`

The runner compiles the fixtures, runs `bytecode-map`, runs `vm trace`, derives `source_trace.json`, renders a small deterministic `source_trace_view.md`, verifies deterministic digests, and compares traced versus untraced VM results.

### Proof Result

```
65 checks total: 65/65 PASS    0 FAIL

Sections:
P3-INPUT=10
P3-ARTIFACTS=9
P3-LOOP=8
P3-NESTED-BRANCH=7
P3-ERROR=9
P3-JUMPS-INFRA=6
P3-DETERMINISM=3
P3-NONSEMANTIC=9
P3-CLOSED=4
```

Regressions remain green:

```
LAB-VMTRACE-P1:          66/66 PASS
LAB-VMTRACE-P2:          60/60 PASS
LAB-IDE-TRACE-VIEW-P1:   50/50 PASS
```

---

## Findings

### 1. Loop Trace

`vmtrace_p3_loop.ig` executes `LoopContract` over input:

```json
{"items":[10,20,30]}
```

Observed VM trace:

- status: `ok`
- events: `30`
- result: `60`
- repeated `LOOP_STEP` global seq positions: `[4, 11, 18, 25]`
- repeated loop offsets include: `[4, 5, 6, 7, 8, 9, 10]`

The same loop source node is represented with repeated trace events. The source trace does not unique-collapse the repeated offsets: `instruction_offsets.length` equals the VM trace event count for the loop node, while `instruction_offsets.uniq.length` is smaller.

**Boundary note:** the current compiler emits a `loop_node` in SemanticIR but does not assign it a source node id in the compiled artifact. To test repeated source-node trace behavior without VM/compiler changes, the proof runner adds a proof-local loop node id and matching sourcemap entry to the `/tmp` compiled igapp before running `bytecode-map`. This is lab-only evidence. It is not canon authority and does not alter source, compiler, or VM semantics.

### 2. Nested Branch Trace

`vmtrace_p3_nested_branch.ig` executes `VmNestedMatch` with:

```json
{"signal":{"__arm":"Green"},"speed":{"__arm":"Fast"}}
```

Observed executed offsets for `compute:VmNestedMatch.message`:

```text
[0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 31, 40]
```

Skipped offsets:

```text
[7, 8, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 38, 39]
```

Only the executed Green/Fast path appears in `vm_trace.json`. Skipped alternatives do not receive synthetic source events. The readable narrative names the non-contiguous branch path as skipped branch alternatives, not as an error.

### 3. Error Trace

The same nested fixture executes fail-closed with:

```json
{"signal":{"__arm":"Blue"},"speed":{"__arm":"Fast"}}
```

Observed:

- `vm_trace.status = "error"`
- `source_trace.status = "error"`
- prefix events are emitted before fail-closed exit
- last recorded offset is `36`, the final `JMP_UNLESS` before the selected unsupported path
- `bytecode_map.json` identifies unsupported offsets `[30, 39]`
- failing unsupported offset `39` is not invented as a successful source event
- no infrastructure output/RET group is emitted
- no output node is invented

Current trace collection records non-returning instructions after successful instruction completion. Therefore an instruction that errors before completion is not itself recorded. P3 records this honestly as deterministic prefix evidence plus preserved error status; it does not claim a successful output path.

### 4. Jump / Offset Semantics

Nested branch execution proves non-contiguous offsets within a source node are expected when jumps are taken. The exact observed gap pattern is:

```text
[7, 8, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 38, 39]
```

These gaps are skipped bytecode from unexecuted branch alternatives, not missing trace data.

### 5. Infrastructure Boundary

Successful loop and nested branch traces each end with infrastructure instructions for output load and `RET`. These groups have offsets and mnemonics but no `node_id`, `sir_path`, or `source_span`.

This remains the honest boundary from P2: VM infrastructure must not be presented as source-origin code.

### 6. Determinism

For loop, nested branch, and error fixtures, repeated runs produce digest-identical trace artifacts for the same fixture/input:

- `bytecode_map.json`
- `vm_trace.json`
- `source_trace.json`
- proof-rendered `source_trace_view.md` where applicable

### 7. Non-Semantic Boundary

Successful traced and untraced VM results match:

- loop: `60`
- nested Green/Fast: `"go_fast"`

The traced `result_digest` matches the SHA-256 digest of the untraced result JSON. Trace reruns do not mutate `semantic_ir_program.json` or `sourcemap.json` after the proof-local loop annotation, and manifest semantics remain unchanged except additive trace refs.

---

## Closed Surfaces

- No debugger
- No interactive stepping
- No breakpoints
- No watch expressions
- No Tauri/IDE integration
- No HTML viewer
- No VM semantic changes
- No compiler/runtime implementation changes
- No public/stable trace API claim
- No canon language authority

---

## Next Route

**A. LAB-IDE-TRACE-VIEW-P2 static HTML viewer may open.**

P3 closes the immediate loop/nested/error coverage gap for static trace consumption. A P2 viewer may render the existing `source_trace.json` / `source_trace_view.md` material as static HTML with collapsible sections or syntax coloring, but it must remain non-interactive and must not introduce stepping, breakpoints, watch expressions, or debugger session authority.

LAB-IDE-STEP-P1 remains closed.
