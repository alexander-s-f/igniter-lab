# Agent Slicing & Mapping Reference

Status: tracked routing contract.

This document is the category authority for new Igniter Lab agent cards and
durable lab documentation. Agents must use it before creating cards, receipts,
or research/proof docs.

## 1. Category Contract

Every new lab card MUST declare exactly one primary category:

```text
Category: core | gui | ide | stdlib | view
```

The primary category decides both the card path and the durable doc path.

If a task touches multiple components, choose the category that owns the
primary write scope. Put secondary areas in `Related Categories:` only. Do not
split a single card across category folders.

If the category is unclear, do not invent a new category and do not write a
root-level card. Stop with a short blocker receipt asking for category routing.

## 2. Category Mapping Matrix

| Category | Components | Card prefixes | Scope |
| :--- | :--- | :--- | :--- |
| `core` | `igniter-compiler/`, `igniter-vm/`, `igniter-runtime/`, `igniter-tbackend/`, `acts-as-tbackend/` | `LAB-FORMS-*`, `LAB-CORE-*`, `LAB-VM-*` | Compiler frontend/backend, lexer/parser, typechecking, SemanticIR, VM instruction set, bytecode execution, bitemporal ledger backends, fact lifecycle adapters. |
| `gui` | `igniter-gui-engine/`, `igniter-design-system/`, `igniter-machine/` | `LAB-NATIVE-GUI-*`, `LAB-GUI-*`, `LAB-TAILMIX-*` | Native layout, scene tree rendering, headless event dispatchers, hit testing, design tokens, Tailmix applicability and GUI interaction IR. |
| `ide` | `igniter-ide/`, `igniter-jetbrains-plugin/` | `LAB-IDE-*`, `LAB-TAURI-IVF-*` | Svelte/Tauri IDE shell, temporal timeline widgets, Monaco integration, trace playback/control panels, JetBrains plugin skeleton. |
| `stdlib` | `igniter-stdlib/`, `igniter-apps/` | `LAB-STDLIB-IO-*`, `LAB-APP-*` | Stdlib candidates, decimal/collection utilities, capability passports, IO/effect surfaces, app fixtures and utility apps. |
| `view` | `igniter-view-engine/` | `LAB-VIEW-DSL-*`, `LAB-IGNITER-VIEW-FRAMEWORK-*` | View DSL grammar, arbre-like boundaries, safe render policy, hot reload preview renderer, isomorphic view artifact work. |

## 3. Path Contract

### Task Cards

New task cards go here:

```text
.agents/work/cards/<category>/<CARD-ID>.md
```

Examples:

```text
.agents/work/cards/ide/LAB-TAURI-IVF-P17.md
.agents/work/cards/gui/LAB-TAILMIX-P1.md
.agents/work/cards/stdlib/LAB-STDLIB-IO-P2.md
```

Root-level `.agents/LAB-*.md` files are legacy handoff artifacts only. Do not
create new root-level lab cards.

### Durable Lab Docs

Durable proof, research, design, and hardening docs go here:

```text
lab-docs/<category>/lab-<descriptor>-v<version>.md
```

Examples:

```text
lab-docs/ide/lab-tauri-ivf-telemetry-status-control-dashboard-v0.md
lab-docs/gui/lab-tailmix-concept-applicability-to-igniter-gui-v0.md
lab-docs/view/lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md
```

Root-level `lab-docs/lab-*.md` files are legacy/imported documents only. Do not
create new root-level durable lab docs.

## 4. Required Card Header

Use this header shape for new lab cards:

```text
Card: <CARD-ID>
Category: <core|gui|ide|stdlib|view>
Agent: [Igniter-Lang <Research|Implementation> Agent]
Role: <research-agent|implementation-agent>
Track: <track-slug-v0>
Route: EXPERIMENTAL / LAB-ONLY
Depends on:
- <previous card or doc>
```

Add `Related Categories:` only when the read scope crosses category boundaries:

```text
Related Categories:
- core
- view
```

Related categories do not change the card path or durable doc path.

## 5. Deliverable Contract

Every new card should name exact output paths:

```text
Deliver:
- Card receipt:
  .agents/work/cards/<category>/<CARD-ID>.md
- Durable doc:
  lab-docs/<category>/<track-slug-v0>.md
- D/S/T/R return packet
```

If no durable doc is needed, say so explicitly:

```text
- Durable doc: none; receipt-only task
```

## 6. Link Rules

Use repo-relative paths for same-repo links.

Use `<project>/path/to/file` for cross-repo links. Project tags are resolved by
the local-only `repository-map.md`.

Do not put absolute local paths or `file://` links in tracked docs or cards.

`repository-map.md` is intentionally ignored by git because it contains local
machine paths. Do not copy its absolute paths into tracked files.

## 7. Agent Rules

1. Read this mapping before creating or moving any card/doc.
2. Pick one primary category from the matrix.
3. Write cards only under `.agents/work/cards/<category>/`.
4. Write durable docs only under `lab-docs/<category>/`.
5. Do not create new categories without an explicit mapping update.
6. Do not create root-level `.agents/LAB-*.md` or root-level `lab-docs/lab-*.md`.
7. Do not widen scope because a category folder contains related history.
8. Do not treat lab evidence as canon or public product authority.
