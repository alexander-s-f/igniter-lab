# LAB-IGNITER-PACKAGE-INTROSPECTION-READINESS-P17 — CLI shape for graph/status/explain

Status: CLOSED
Lane: standard / package DX
Type: readiness / design
Delegation code: OPUS-IGNITER-PACKAGE-INTROSPECTION-READINESS-P17
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P1-P15 produced a local-first package model: local dependencies, content/toolchain/stdlib lock, frozen/strict CI,
module exports, closed default, transitive graph, graph-aware drift. The next pain is not package semantics but
operability: users and agents need to see what the workspace graph is, why an import is allowed/denied, and what
CI is checking.

P15 explicitly deferred small DX polish: `igc package` introspection.

## Goal

Design the smallest useful `igc package ...` CLI surface for local package introspection. This is readiness only:
no code changes unless the card discovers a tiny documentation typo. The result should dispatch a later
implementation card with exact commands, JSON shape, and tests.

## Verify first

- `lang/igniter-compiler/src/main.rs` for current CLI style and JSON output conventions.
- `lang/igniter-compiler/src/project.rs` for graph/integrity data currently public/private.
- P4/P8/P11/P14/P15 package docs for lock/verify/strict shape.
- Existing CLI tests in `package_lockfile_cli_tests.rs`.

## Questions to answer

1. Is one command enough (`igc package graph`) or do we need `graph`, `status`, and `explain` separately?
2. Should v0 output be JSON-only, text + `--json`, or follow existing command defaults?
3. What exact fields should graph output include?
   - package label/name
   - root-relative path
   - source_roots
   - exports mode/surface
   - dependencies by label/path
   - digest?
4. Should graph output include the root node, or only dependencies?
5. How should diamond dedup be represented without implying version solving?
6. Should cycles/missing paths produce partial graph output plus diagnostic, or just fail?
7. Does `igc verify --strict` already answer `status`, or is `igc package status` still valuable?
8. What is the minimal import-debug story: `igc package explain-import <module> <import>` vs a later card?
9. What should be private/internal and not stabilize yet?
10. Which implementation card should come first?

## Bias

Prefer one boring command first: `igc package graph --project-root <dir> --json`, because it directly exposes
P14 truth and helps agents inspect workspaces. Avoid a broad package manager UX while registry/semver are closed.

## Required deliverable

- Readiness packet: `lab-docs/lang/lab-igniter-package-introspection-readiness-p17-v0.md`
- Closing report in this card.
- A concrete next implementation card name and acceptance matrix.

## Acceptance

- [x] Live CLI/project surfaces verified.
- [x] At least three command shapes compared.
- [x] Recommended v0 command(s) and exact JSON schema drafted.
- [x] Error/diagnostic behavior for OOF-IMP6/7/8/9 addressed.
- [x] Implementation card proposed with bounded tests.
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-package-introspection-readiness-p17-v0.md` — readiness packet, no
production code (`git diff --check` clean).

**Verify-first:** dispatch is `match command.as_str()` (compile/lock/verify); all commands emit pretty JSON
by default; `collect_package_graph`/`PackageGraph`/`PackageNode`/`PackageId` are **private** → introspection
needs one new public JSON accessor (internal structs stay private; JSON schema = the contract). Assembly
errors already render structurally (`error: d.to_value()`, P16).

**Decision:** ship **one** command — `igc package graph --project-root <dir>`, **structural** JSON-only view
(over shapes B three-subcommands / C top-level `igc graph` / D `verify --graph`). Fields: label, root-relative
path, source_roots, exports{mode: open|sealed|allowlist, modules?}, dependencies[{label,path}], root
`exports_default`, `faults`. **Root included** (`<root>`, `.`); **no digest** (lock's job); **diamond = one
node** (no version field). Error split: OOF-IMP9 → structured error+exit1; cycle → full graph + `faults`
exit0; OOF-IMP6/7 NOT shown (import-level, that's `verify --strict`). **Q7:** `verify --strict` IS status →
no `status` command. **Q8:** `explain-import` deferred to a later card. **Q9:** keep graph types private.

**Next:** `LAB-IGNITER-PACKAGE-GRAPH-CLI-P18` (implement `igc package graph` via
`project::workspace_graph_value(root) -> Result<Value,ProjectError>`) — 8-point acceptance matrix enumerated
in §7. Later: `LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-P19+`. Registry/semver far later.

## Closed scope

- No implementation.
- No registry/remote/semver.
- No publishing/package install UX.
- No changes to lock format unless explicitly deferred as a future card.
