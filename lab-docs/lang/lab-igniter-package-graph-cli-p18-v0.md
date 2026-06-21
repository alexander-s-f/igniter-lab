# lab-igniter-package-graph-cli-p18-v0 — `igc package graph`

**Card:** `LAB-IGNITER-PACKAGE-GRAPH-CLI-P18` · **Delegation:** `OPUS-IGNITER-PACKAGE-GRAPH-CLI-P18`
**Status:** CLOSED (lab implementation-proof) — `igc package graph --project-root <dir>` emits the assembled
**local** package graph (P14 truth: nodes, edges, source roots, exports surface, root policy) as deterministic
JSON. Structural **view**, not a health gate — `verify --strict` remains the failing gate. **`project.rs`
public accessor + `main.rs` subcommand + tests — internal graph structs stay private; no lock-format change,
no registry/semver, no server/web/machine change, no new crate.**

## What changed

- **`project.rs`:** `pub fn workspace_graph_value(root) -> Result<Value, ProjectError>` — a stable JSON
  projection over the private `collect_package_graph`. `PackageGraph`/`PackageNode`/`PackageId` stay private;
  this function is the public contract. `+ exports_mode_value` helper.
- **`main.rs`:** `package` command dispatch + `run_package` → `igc package graph [--project-root ROOT]`.
  JSON only (no `--json` flag). `OOF-IMP9` (missing dep) → structured error JSON, **exit 1**. A **cycle** →
  full graph + `faults: [OOF-IMP8]`, **exit 0**.

## JSON shape (live)

```json
{
  "kind": "igniter_package_graph",
  "root": ".",
  "exports_default": "open",
  "packages": [
    { "label": "<root>", "path": ".",        "source_roots": ["src"], "exports": { "mode": "open" },
      "dependencies": [{ "label": "mid", "path": "../mid" }] },
    { "label": "leaf",   "path": "../leaf",  "source_roots": ["src"],
      "exports": { "mode": "allowlist", "modules": ["Leaf.Public"] }, "dependencies": [] },
    { "label": "mid",    "path": "../mid",   "source_roots": ["src"], "exports": { "mode": "open" },
      "dependencies": [{ "label": "leaf", "path": "../leaf" }] }
  ],
  "faults": []
}
```

Rules (all honored): root node **included**; packages sorted by **root-relative path**; dependency edges
sorted by path; **no digests** (the lock owns provenance); a diamond = **one** package node with multiple
parent edges; exports `mode` ∈ `open` / `sealed` (`modules = []`) / `allowlist` (with `modules`). Keys are
emitted in `serde_json`'s stable (sorted) order → deterministic across runs.

## Behavior matrix (live smoke)

| Fixture | Result |
|---|---|
| `workspace_transitive_ok` | root + mid + leaf; edges `<root>→mid`, `mid→leaf`; leaf `allowlist [Leaf.Public]`; `faults: []`; exit 0 |
| `workspace_transitive_diamond` | `c` is **one** package node (two parent edges `a→c`, `b→c`); exit 0 |
| `workspace_closed_default` | `exports_default: "closed"` |
| `[exports] modules = []` | `exports: { "mode": "sealed" }` |
| `workspace_transitive_cycle` | full graph + `faults: [{ "rule": "OOF-IMP8", … }]`, **exit 0** |
| `workspace_missing_root_dep` | `{ "kind": "igniter_package_graph", "ok": false, "error": { "rule": "OOF-IMP9", … } }`, **exit 1** |

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 30 passed (23 + 7 NEW P18)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests      → green (P16 intact)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

New P18 tests (7, read-only on existing fixtures — `package graph` writes nothing):
`cli_package_graph_emits_full_graph` (root+mid+leaf, edges, sorted, no faults),
`cli_package_graph_diamond_dedups` (shared `c` = one node), `cli_package_graph_exposes_closed_default`,
`cli_package_graph_renders_exports_modes` (allowlist), `cli_package_graph_cycle_emits_faults_exit_zero`
(OOF-IMP8 in faults, exit 0), `cli_package_graph_missing_dep_errors` (OOF-IMP9, exit 1),
`cli_package_graph_is_deterministic`.

## Acceptance — mapping

- [x] `igc package graph` on `workspace_transitive_ok` emits root + mid + leaf.
- [x] Edges include `<root> → mid` and `mid → leaf`.
- [x] Diamond fixture emits the shared package once.
- [x] Closed-default fixture exposes `exports_default: "closed"`.
- [x] Sealed and allowlist exports render correctly.
- [x] Cycle fixture emits the full graph plus `faults` with `OOF-IMP8`, exit 0.
- [x] Missing dependency fixture emits structured `OOF-IMP9`, exit 1.
- [x] JSON deterministic across runs.
- [x] Existing package tests green; full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`workspace_graph_value` + `exports_mode_value`).
- `lang/igniter-compiler/src/main.rs` (`package` dispatch + `run_package`).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+7 P18 tests).

## Deferred (explicit)

- `igc package status` / health command — `verify --strict` already is that (P17 decided).
- `igc package explain-import` — separate readiness (`…-IMPORT-EXPLAIN-READINESS-P18`); recommends diagnostic
  enrichment first.
- Digests / provenance in the graph view (the lock owns them); internal Rust struct stabilization.

## Next

`LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19` (import-explain enrichment) OR the remote/registry wave. The
local package model now has an introspection front door (`igc package graph`) alongside the CI gate.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_lockfile_cli_tests` 30 green, full `igniter-compiler`
suite green, `git diff --check` clean. `igc package graph` exposes the P14 graph as deterministic JSON —
nodes/edges/source-roots/exports/policy, diamond-deduped, cycle→faults (exit 0), missing→OOF-IMP9 (exit 1);
internal graph structs remain private behind `workspace_graph_value`.*
