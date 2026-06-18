# lab-igniter-transpiling-research-dx-gemini-p1-v0 — Project DX for Dialect Lowering & Editor Overlays

**Card:** `LAB-IGNITER-TRANSPILING-RESEARCH-DX-GEMINI-P1`  
**Delegation-Code:** `GEMINI-20260618-TRANSPILING-C`  
**Status:** RESEARCH PACKET (v0; recommendations are backlog ideas, not authority)  
**Scope:** Developer experience (DX) and build pipeline design for projection dialects, generated files, watch/hot-reload, and editor overlays. **No code implementation, no compiler edits, no JetBrains plugin edits.**  
**Authority:** Lab research only. Grounded in `project.rs`, `main.rs`, and the `Projection Dialects (P0)` contract.

---

## 1. Executive Summary

This packet addresses the project-level developer experience for **Igniter Projection Dialects** (`.igv`, `.igweb`, etc.). As defined in `P0` (`lab-igniter-projection-dialects-p0-v0.md`), dialects are authoring syntax surfaces that lower to canonical inspectable targets and introduce no hidden runtime authority. 

To make this model practical in projects with multiple files, imports, and unsaved editor buffers, we recommend:
1.  A **project-config-driven build wrapper** (`igniter` CLI) rather than bloating the compiler with dialect-specific parser logic.
2.  Placing lowered files in **checked-in `generated/` directories** to ensure inspectability and compilation compatibility.
3.  Mapping unsaved editor buffers via a **two-stage overlay process** (IDE lowers unsaved dialect to a temp `.ig` buffer and passes it as an `--overlay` to `igc`).
4.  Implementing file watching via a **stateless watch wrapper** to avoid turning the compiler into a daemon.

---

## 2. DX Pipeline: Compiler Flag vs. Standalone Tool vs. Build Wrapper (Q1)

We analyze three primary architectures for driving dialect lowering:

| Architecture | Pipeline Flow | Pros | Cons |
|---|---|---|---|
| **Compiler Flag** | `igc compile --dialect-lower ...` | Single binary; no extra tool installations; direct integration. | Bloats the compiler core with dialect semantics; violates the `P0` boundary (compiler should remain canon-only). |
| **Standalone Tool** | `igniter-web-lower routes.igweb -o routes.ig` | Clean separation of concerns; compiler doesn't know about dialects. | Fragmentation; developers must manually run and chain multiple command-line utilities. |
| **Build Wrapper (Recommended)** | `igniter build` (reads config, runs lowerers, calls `igc`) | Cohesive DX; handles custom/app-local dialects; compiler remains stateless. | Requires maintaining a wrapper CLI and config parser. |

**Recommendation**: We recommend a **project-config-driven build wrapper** (e.g. `igniter` CLI). The core compiler (`igc`) should stay entirely unaware of dialect-specific syntax. The build wrapper orchestrates the build stages: it parses `igniter.toml`, runs the appropriate lowerer tools in parallel to generate canonical files, and then calls `igc` to assemble the module graph and compile the final `.igapp`.

---

## 3. Minimal `igniter.toml` Schema (Q2)

To drive the build wrapper, we target a minimal `igniter.toml` configuration format that integrates with the existing `ProjectConfig` source roots:

```toml
# igniter.toml

# Canonical source roots to scan for .ig files
source_roots = ["source"]

# Dialect Lowering Registry
[[dialects]]
id = "igweb"
extension = "igweb"
inputs = ["source/routes/**/*.igweb"]
target = "source/generated/routes.ig"
tool = "igniter-web-lower"

[[dialects]]
id = "igv"
extension = "igv"
inputs = ["source/views/**/*.igv"]
target = "source/generated/views.json"
tool = "igniter-view-lower"
```

This configuration explicitly defines the input globs, the target file where the lowered output is written, and the tool invoked to perform the translation.

---

## 4. Generated File Policy: Checked-in vs. Temp vs. Virtual (Q3)

We evaluate three placement strategies for generated artifacts:

1.  **Checked-in `generated/` directories** (e.g. `source/generated/routes.ig`):
    *   *Pros*: Standard and transparent. Humans can inspect the generated code directly to debug compiler errors; Git records changes; `igc` compiles them naturally without special search-path routing.
    *   *Cons*: Workspace noise; developers might accidentally edit generated files directly.
2.  **Temp Build Directory** (e.g. `target/lower/routes.ig`):
    *   *Pros*: Keeps the source roots clean of machine-generated code.
    *   *Cons*: Obscures the build outputs; requires the compiler or build wrapper to manage custom search paths for generated imports, increasing configuration surface.
3.  **IDE-only Virtual Files**:
    *   *Pros*: Ultra-fast; zero disk overhead.
    *   *Cons*: Breaks CLI and headless build compilation; requires tight coupling between the compiler and IDE language servers.

**Recommendation**: We recommend placing files in **checked-in `generated/` directories**, prepended with a clear warning comment (e.g., `// GENERATED CODE - DO NOT HAND-EDIT`). This satisfies the `P0` invariant of inspectability and keeps the compiler's entry resolution simple.

---

## 5. Editor Overlays and Unsaved Buffer Integration (Q4)

In `P2` (`lab-compiler-project-overlay-p2-v0.md`), we introduced the `--overlay` flag to pass unsaved editor buffers to `igc`. To handle unsaved dialect files (like an unsaved `routes.igweb` buffer), we recommend a **two-stage overlay translation** run by the IDE or build wrapper:

```
[Unsaved editor buffer: routes.igweb]
   │
   ▼ (IDE runs dialect lowerer on temp buffer)
[Temp lowered buffer: /tmp/unsaved_routes.ig]
   │
   ▼ (IDE invokes compiler with target redirection overlay)
igc compile --project-root . --entry App.Main \
  --overlay source/generated/routes.ig=/tmp/unsaved_routes.ig \
  --out target/app.igapp
```

### Steps:
1.  The developer edits `routes.igweb` in the editor.
2.  The IDE writes the unsaved buffer to a temporary file: `/tmp/buffer.igweb`.
3.  The IDE invokes the standalone lowerer: `igniter-web-lower --input /tmp/buffer.igweb --out /tmp/buffer_lowered.ig`.
4.  The IDE calls `igc` to compile, supplying the overlay mapping the *generated target path* to the *temporary lowered buffer*:
    `--overlay source/generated/routes.ig=/tmp/buffer_lowered.ig`.

*DX Payoff*: The core compiler never needs to parse or understand dialect syntax in memory. It continues to compile `.ig` buffers, yet the IDE successfully obtains real-time diagnostics on unsaved dialect files.

---

## 6. Watch and Hot-Reload Mechanics (Q5)

To support file watching and hot-reloads without turning the compiler into a persistent daemon:

1.  **Stateless Watch Wrapper**: Implement watch functionality in a separate CLI tool (e.g. `igniter watch`) using a filesystem notification library (`notify` in Rust). The watch process is the daemon; the compiler (`igc`) remains a stateless, one-shot binary.
2.  **Pipeline Sequence**:
    *   On a file modification event, the watcher checks the file extension.
    *   If a dialect file changes (e.g., `routes.igweb`), the watcher runs the mapped lowerer to regenerate the target `.ig`.
    *   The watcher then runs `igc compile` to rebuild the `.igapp`.
    *   If successful, the watcher notifies the running server stream or swaps the target file on disk to trigger host reload (`P4`/`P5`).

---

## 7. Makefile / Task Wrapper vs. Compiler Responsibilities (Q6)

To maintain a clean architectural boundary, we divide responsibilities:

*   **Compiler Responsibilities**:
    *   Scanning project source roots and parsing file modules (P1).
    *   Transitive import closure resolution and overlay substitution (P2).
    *   Typechecking, monomorphization, code emission, and formatting standardized diagnostic JSON payloads.
*   **Wrapper (Makefile / CLI wrapper) Responsibilities**:
    *   Reading `igniter.toml` configurations.
    *   Orchestrating the parallel execution of dialect lowerers before compilation.
    *   Filesystem watching and hot-swap notification.
    *   Clean, format, and package actions.

---

## 8. Dialect Composition and Ordering (Q7)

To prevent build fragility when using multiple dialects, we establish a strict **no-nested-dialect** rule:
*   Dialects must lower directly to canonical targets (`.ig` or JSON).
*   A dialect must **never** lower to another dialect (e.g. `.igweb` must not lower to `.igv`).

This makes the build pipeline a two-phase DAG:
1.  **Phase 1 (Lowering)**: Run all dialect lowerers in parallel to generate `.ig` and JSON targets.
2.  **Phase 2 (Compilation)**: Compile the canonical targets together using `igc`.

This guarantees that there are no hidden ordering dependencies between dialects.

---

## 9. Recommended CLI Sketch (Q8)

We propose a targeted CLI sketch for the `igniter` build wrapper:

```bash
# Compile the project based on igniter.toml
igniter build --entry App.Main --out build/app.igapp

# Start the file watcher to lower and compile on save
igniter watch --entry App.Main --out build/app.igapp
```

Internally, `igniter build` executes the steps:
1.  Parse `igniter.toml` to find all registered dialects.
2.  Scan files matching input globs and run their respective tools (e.g., `igniter-web-lower`).
3.  Execute `igc compile --project-root . --entry App.Main --out build/app.igapp` and print the result.

---

## 10. Future Card Backlog & Non-Goals

### Non-Goals for DX Phase 1
*   Do not implement dynamic code loaders in the compiler.
*   Do not write to the active JetBrains plugin code.
*   Do not allow dialect files to bypass the canonical `.ig` compilation stage.

### Future Card Ideas
1.  `LAB-IGNITER-BUILD-WRAPPER-P1`: Implement the minimal `igniter build` wrapper in Rust that parses `igniter.toml` and runs registered lowerer tools in parallel.
2.  `LAB-IGNITER-WATCH-WRAPPER-P2`: Implement filesystem watching (`igniter watch`) that triggers the lowering and compilation pipeline.
3.  `LAB-JETBRAINS-DIALECT-OVERLAY-P3`: Integrate the two-stage overlay process into the JetBrains plugin so unsaved dialect buffers map seamlessly to compiler overlays.
