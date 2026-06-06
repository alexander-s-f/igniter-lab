# LAB-IDE-DEBUGGER-P1 — Agent Return Packet

This return packet documents the implementation of the experimental compiler-to-workspace pipeline and Svelte Debugger Panel interface within the Igniter IDE sandbox to trace compilation stages, inspect artifact files, diagnose execution errors, and pin a regression case regarding loop collection expressions.

---

## Changed Files

The following files have been modified or introduced within the `igniter-lab/igniter-ide/` surface:

- **Tauri Backend (Rust)**:
  - `src-tauri/Cargo.toml` — Added dependencies on `igniter_compiler` and `sha2`.
  - `src-tauri/src/commands.rs` — Updated `load_contract` and `load_contract_from_file` commands to take `workspace_dir: Option<String>` and execute compiler stages sequentially while copying intermediate artifacts to the workspace directory.
- **Frontend Stores & API (TypeScript)**:
  - `src/lib/api.ts` — Updated method signatures of `loadContract` and `loadContractFromFile` to support workspaces.
  - `src/lib/stores/artifacts.ts` — Added `DebugEvent` schema and initialized `debuggerStore` Svelte store with `localStorage` persistence.
- **Frontend Components & Views (Svelte)**:
  - `src/lib/components/InlineRunPanel.svelte` — Log run success/failures with dynamic diagnostic failure stages to the store.
  - `src/lib/components/DispatchPanel.svelte` — Log run success/failures to the store.
  - `src/routes/+page.svelte` — Added `debugger` bottom tab, integrated new compilation return format, and wired telemetry listeners.
  - `src/lib/components/DebuggerPanel.svelte` (NEW) — Chronological event listing, filters, telemetry overview, export capabilities, artifact file inspector, and loop mismatch diagnostics.

---

## Feature Summary

1. **Stage-Wise Compiler Telemetry**:
   - The compile pipeline now tracks lex, parse, classify, typecheck, emit, and assemble phases.
   - On success or failure, structured report records containing hash, duration, error state, and paths are logged.
2. **Workspace Artifact Writing**:
   - Artifacts are saved to `{workspace_root}/.igniter/artifacts/{contract_name}_{ts}/`.
   - On compile failures, intermediate diagnostics and reports are written to the workspace to enable post-mortem analysis.
3. **Artifact File Explorer**:
   - A sub-panel allows users to browse and read JSON contents of raw artifacts (e.g. `manifest.json`, `semantic_ir_program.json`, `form_table.json`, `form_resolution_trace.json`) directly within the IDE's UI.
4. **Execution Logger & Replays**:
   - Records all contract executions dynamically, capturing exact input objects, outputs, durations, and allowing single-click input reloading into the dispatch panel for re-execution.
5. **Loop Mismatch Diagnostics (Regression Check)**:
   - Pins the regression of `"VM execution error: Missing loop collection expr"`.
   - Compares the `SemanticIR` node (which uses `expr` key) with the `CompiledIR` node (which renames `expr` to `expression`), highlighting the mismatch that causes `igniter-vm` compiler crashes.
   - Supports both a static pinned regression demo and dynamic analysis of workspace artifact folders.

---

## Command Matrix & Integration Points

| Command / Component | Target | Behavior |
| --- | --- | --- |
| `load_contract` | Rust API | Compiles source code, writes artifacts to `.igniter/artifacts/`, registers with VM registry. |
| `load_contract_from_file` | Rust API | Loads path content, compiles, writes artifacts, registers. |
| `debuggerStore` | Svelte Store | Chronological log list bounded at 200 items, persistent across app reloads. |
| `copyDebugBundle` | JS Clipboard | Exports a formatted JSON report containing event metadata, input/output payload, diagnostics, and loop node structures. |

---

## Known Limitations

- **Platform Invariant**: No changes were made to the mainline compiler assembler (`igniter-compiler/src/assembler.rs`) or VM executor (`igniter-vm/src/compiler.rs`). The loop mismatch diagnostics currently operates as an alert/diagnostics display inside the IDE.
- **JSON Viewer Scale**: Large semantic arrays or deeply nested structures may cause minor scroll lag in the simple artifact reader view.

---

## Handoff

Card: LAB-IDE-DEBUGGER-P1
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: igniter-lang/ide-debugger-p1
Status: done

[D] Decisions
- We introduced direct dependency reference to `igniter_compiler` path in the IDE backend crate rather than mocking diagnostics, permitting true stage-by-stage compilation telemetry inside the Tauri environment.
- We opted to write JSON diagnostic logs immediately to disk on compile failures to guarantee the frontend can read the diagnostics payload under any workspace condition.

[S] Shipped / Signals
- Stage telemetry & file inspection tools are fully operational.
- Loop Mismatch Diagnostics visualizes compiler key translation issues.

[T] Tests / Proofs
- verified `cargo check` warning-free on changed Tauri files.
- verified `npm run check` and `npm run build` are error-free.
- Pinned regression telemetry mock data loaded successfully on mount.

[R] Risks / Recommendations
- The assembler `expression` vs `expr` rename mismatch is a structural regression in the compiler/assembler. A separate card on the `igniter-compiler` repository should align the assembler emitter key naming to match what `igniter-vm` expects.
