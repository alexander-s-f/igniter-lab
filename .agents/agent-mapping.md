# Agent Slicing & Mapping Reference

This document maps codebase subprojects, task card prefixes, and documentation directories. All agents must follow this mapping when creating new cards or writing research documentation.

---

## 1. Symmetrical Category Mapping Matrix

Use this matrix to determine the correct target directory and naming prefix based on the codebase components you are working on:

| Subproject / Component | Card Prefix Pattern | Category Folder | Scope & Functional Area |
| :--- | :--- | :--- | :--- |
| `igniter-compiler/`<br>`igniter-vm/`<br>`igniter-runtime/`<br>`igniter-tbackend/`<br>`acts-as-tbackend/` | `LAB-FORMS-*`<br>`LAB-CORE-*`<br>`LAB-VM-*` | **`core`** | Compiler frontend/backend, Lexer/Parser, Typechecking, VM instruction set, bytecode execution, bitemporal ledger backends, fact lifecycle adapters. |
| `igniter-gui-engine/`<br>`igniter-design-system/`<br>`igniter-machine/` | `LAB-NATIVE-GUI-*`<br>`LAB-GUI-*`<br>`LAB-TAILMIX-*` | **`gui`** | Native layout constraint solver, scene tree rendering, headless event dispatchers, hit testing, design tokens, Tailmix applicability/GUI integration. |
| `igniter-ide/`<br>`igniter-jetbrains-plugin/` | `LAB-IDE-*`<br>`LAB-TAURI-IVF-*` | **`ide`** | Svelte/Tauri editor interface, temporal timeline widgets, Monaco integration, trace playback panel, Kotlin/JetBrains plugin skeleton. |
| `igniter-stdlib/`<br>`igniter-apps/` | `LAB-STDLIB-IO-*`<br>`LAB-APP-*` | **`stdlib`** | Stdlib candidates, decimal/collection SKUs, capability passport security, IO loader alignment, CLI utility apps. |
| `igniter-view-engine/` | `LAB-VIEW-DSL-*`<br>`LAB-IGNITER-VIEW-FRAMEWORK-*` | **`view`** | View DSL grammar, arbre-like boundaries, safe render policies, hot reloading preview renderer, isomorphic view framework. |

---

## 2. Directory Structure Conventions

Both task cards and research documentation are organized symmetrically into the five category folders:

### A. Task Cards (`.agents/work/cards/`)
*   **Path format**: `.agents/work/cards/<category>/<CARD-PREFIX>-P<N>.md`
*   *Example*: `.agents/work/cards/gui/LAB-TAILMIX-P1.md`
*   *Example*: `.agents/work/cards/stdlib/LAB-STDLIB-IO-P2.md`

### B. Durable Documentation (`lab-docs/`)
*   **Path format**: `lab-docs/<category>/lab-<descriptor>-v<version>.md`
*   *Example*: `lab-docs/gui/lab-tailmix-concept-applicability-to-igniter-gui-v0.md`
*   *Example*: `lab-docs/view/lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md`

---

## 3. Agent Rules for Slicing and Documenting

1.  **Card Creation**:
    Before starting a task, create a card in `.agents/work/cards/<category>/` using the correct category prefix and the next sequential phase number (`P1`, `P2`, etc.).
2.  **Documentation Creation**:
    When an experiment finishes or yields durable findings, document it in `lab-docs/<category>/`.
3.  **Link Alignment**:
    *   Symmetrical structure implies a standard offset of `../../lab-docs/<category>/<doc>.md` from a card file, and `../../.agents/work/cards/<category>/<card>.md` from a doc file.
    *   For external repositories (like `tailmix` or `igniter-lang`), use the `<project>/path/to/file` convention resolved via `repository-map.md`.
