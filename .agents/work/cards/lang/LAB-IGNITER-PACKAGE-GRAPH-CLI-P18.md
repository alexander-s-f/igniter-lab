# LAB-IGNITER-PACKAGE-GRAPH-CLI-P18 — `igc package graph`

Status: CLOSED
Lane: standard / package DX
Type: implementation proof
Delegation code: OPUS-IGNITER-PACKAGE-GRAPH-CLI-P18
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on `LAB-IGNITER-PACKAGE-INTROSPECTION-READINESS-P17`.

P17 selected one boring first introspection command: `igc package graph --project-root <dir>`. It should expose
the assembled **local** package graph (P14 truth: nodes, edges, source roots, exports surface, root policy) as
JSON. This is a structural view, not a health gate; `verify --strict` remains the status/CI command.

## Goal

Implement `igc package graph --project-root <dir>` and a stable JSON projection of the private package graph.

## Verify first

- `lab-docs/lang/lab-igniter-package-introspection-readiness-p17-v0.md`
- `lang/igniter-compiler/src/main.rs` command dispatch / JSON conventions.
- `lang/igniter-compiler/src/project.rs`
  - `collect_package_graph`
  - `detect_cycle`
  - `relative_to`
  - lock/verify diagnostic JSON behavior from P16.
- Existing fixtures:
  - `workspace_transitive_ok`
  - `workspace_transitive_diamond`
  - `workspace_transitive_cycle`
  - `workspace_missing_root_dep`
  - closed-default / exports fixtures already used by package tests.

## Required implementation

- Add a public accessor returning a serializable graph view, e.g.
  `project::workspace_graph_value(root) -> Result<serde_json::Value, ProjectError>`.
- Keep `PackageGraph`, `PackageNode`, `PackageId`, and `collect_package_graph` private.
- Add `main.rs` support for:
  `igc package graph --project-root <dir>`
- Output JSON only. No `--json` flag needed.
- For `OOF-IMP9`, return structured error JSON and exit 1.
- For cycles, emit the full graph plus `faults` and exit 0. `verify --strict` remains the failing gate.

## Expected JSON

Shape should follow P17 exactly unless live code forces a small adjustment:

```json
{
  "kind": "igniter_package_graph",
  "root": ".",
  "exports_default": "open",
  "packages": [
    {
      "label": "<root>",
      "path": ".",
      "source_roots": ["src"],
      "exports": { "mode": "open" },
      "dependencies": [{ "label": "mid", "path": "../mid" }]
    }
  ],
  "faults": []
}
```

Rules:

- Include the root node.
- Sort packages by root-relative path.
- Sort dependency edges deterministically.
- Do not include digests; lock owns provenance.
- Diamond = one package node, multiple parent edges.
- Exports mode = `open` / `sealed` / `allowlist`.

## Acceptance

- [x] `igc package graph` on `workspace_transitive_ok` emits root + mid + leaf.
- [x] Edges include `<root> -> mid` and `mid -> leaf`.
- [x] Diamond fixture emits shared package once.
- [x] Closed-default fixture exposes `exports_default: "closed"`.
- [x] Sealed and allowlist exports render correctly.
- [x] Cycle fixture emits full graph plus `faults` containing `OOF-IMP8`, exit 0.
- [x] Missing dependency fixture emits structured `OOF-IMP9`, exit 1.
- [x] JSON is deterministic across runs.
- [x] Existing package tests remain green.
- [x] Full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation:** `project.rs` `pub fn workspace_graph_value(root) -> Result<Value, ProjectError>` — stable
JSON projection over the private `collect_package_graph` (graph structs stay private); `+ exports_mode_value`.
`main.rs` `package` dispatch + `run_package` → `igc package graph [--project-root ROOT]`, JSON-only.
`OOF-IMP9` → structured error JSON exit 1; cycle → full graph + `faults:[OOF-IMP8]` exit 0. Proof doc:
`lab-docs/lang/lab-igniter-package-graph-cli-p18-v0.md`.

**JSON:** `{kind, root:".", exports_default, packages:[{label,path,source_roots,exports{mode,modules?},
dependencies[{label,path}]}], faults}` — root included, packages sorted by root-relative path, edges sorted,
no digests, diamond=one node, exports mode open/sealed/allowlist. Deterministic (serde sorted keys).

**Live smoke (all ✓):** transitive_ok (root+mid+leaf, edges, faults:[]); diamond (`c` one node); closed_default
(`exports_default:"closed"`); `[exports] modules=[]`→sealed; cycle→`faults:[OOF-IMP8]` exit 0; missing→
`ok:false, error.rule:OOF-IMP9` exit 1.

**Proof — all green:** `package_lockfile_cli_tests` **30** (23 + 7 P18, read-only on fixtures — graph writes
nothing), `package_workspace_tests` intact, full `igniter-compiler` suite green (0 failed), `git diff --check`
clean. No lock-format/server/web/machine change; no new crate; internal structs unstabilized.

**Deferred:** `igc package status` (=`verify --strict`); `explain-import` (separate readiness); digests in the
view. **Next:** `…-DIAGNOSTIC-DETAILS-P19` (import-explain enrichment) OR remote/registry wave.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-igniter-package-graph-cli-p18-v0.md`
- Closing report in this card.

## Closed scope

- No graph health/status command.
- No explain-import command.
- No registry/remote/semver.
- No lock format change.
- No stabilization of internal Rust graph structs.
