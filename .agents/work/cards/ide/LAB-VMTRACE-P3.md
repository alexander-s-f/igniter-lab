# LAB-VMTRACE-P3 — Agent Return Packet

Loop, nested-branch, and error trace coverage hardening for the VM trace stack.

---

## Status

**Complete.** P3 proof 65/65. Regressions green: VMTRACE-P1 66/66, VMTRACE-P2 60/60, IDE-TRACE-VIEW-P1 50/50.

---

## Changed Files

### Fixtures (`igniter-view-engine/fixtures/source_map/`)

- `vmtrace_p3_loop.ig`
- `vmtrace_p3_nested_branch.ig`
- `inputs_vmtrace_p3_loop.json`
- `inputs_vmtrace_p3_nested_green_fast.json`
- `inputs_vmtrace_p3_nested_unknown_signal.json`

### Proof Runner

- `igniter-view-engine/proofs/verify_lab_vmtrace_p3.rb`

### Lab Doc

- `igniter-lab/lab-docs/ide/lab-vmtrace-control-flow-and-error-coverage-v0.md`

### Portfolio

- `igniter-lab/.agents/portfolio-index.md`

### No VM/compiler source changes

Zero changes to VM/compiler implementation files. The loop source-node id used by P3 is proof-local annotation inside `/tmp` compiled igapps only.

---

## Proof Results

```
LAB-VMTRACE-P3: 65/65 PASS    0 FAIL

P3-INPUT:          10/10
P3-ARTIFACTS:       9/9
P3-LOOP:            8/8
P3-NESTED-BRANCH:   7/7
P3-ERROR:           9/9
P3-JUMPS-INFRA:     6/6
P3-DETERMINISM:     3/3
P3-NONSEMANTIC:     9/9
P3-CLOSED:          4/4
```

Regression gates:

```
LAB-VMTRACE-P1:          66/66 PASS
LAB-VMTRACE-P2:          60/60 PASS
LAB-IDE-TRACE-VIEW-P1:   50/50 PASS
```

---

## Key Findings

**Loop trace:** `LoopContract` over `[10,20,30]` returns `60`, emits 30 VM events, and repeats the same loop source node without unique-collapsing repeated offsets. `LOOP_STEP` appears at global seq `[4,11,18,25]`.

**Nested branch trace:** Green/Fast path executes exact source offsets `[0,1,2,3,4,5,6,9,10,11,12,13,14,15,16,17,18,19,20,21,22,31,40]`; skipped alternatives `[7,8,23..30,32..39]` are absent from `vm_trace.json`.

**Error trace:** Unknown signal arm fails closed with `vm_trace.status="error"` and `source_trace.status="error"`. Trace preserves prefix through offset `36`; bytecode_map identifies unsupported fail-closed offsets `[30,39]`; no successful output node or infra RET group is invented.

**Jump semantics:** Non-contiguous offsets are expected when branch jumps skip bytecode. P3 documents the exact nested branch gap pattern.

**Infra boundary:** output load/RET groups have offsets and mnemonics but no `node_id`, `sir_path`, or `source_span`.

**Determinism:** bytecode_map/vm_trace/source_trace/view digests are identical across reruns for same fixture/input.

**Non-semantic:** traced and untraced successful VM results match; result digests match untraced result JSON; SIR/source map/stripped manifest semantics unchanged.

---

## Closed Surfaces

- No debugger
- No stepper
- No breakpoints
- No watch expressions
- No Tauri/IDE integration
- No HTML viewer
- No VM/compiler semantic changes
- No public/stable trace API
- No canon language claim

---

## Recommended Next Route

**A. LAB-IDE-TRACE-VIEW-P2 static HTML viewer may open.**

Constraints for P2: static HTML only, derived from existing trace artifacts, no stepping, no breakpoints, no watch expressions, no debugger session authority.

LAB-IDE-STEP-P1 remains closed.
