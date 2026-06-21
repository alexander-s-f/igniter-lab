# lab-igniter-package-missing-dep-diagnostic-p16-v0 — OOF-IMP9 for missing local dependency paths

**Card:** `LAB-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16` · **Delegation:** `OPUS-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16`
**Status:** CLOSED (lab implementation-proof) — a declared local dependency path that does not exist is now a
deterministic **`OOF-IMP9`** at graph-assembly time (compile, `lock`, `verify`), naming the declaring
package, the dependency edge, and the missing path — instead of a delayed `OOF-IMP2`. **`project.rs` +
`main.rs` (structured CLI error) + tests only — no registry/semver, no `.ig` syntax, no server/web/machine
change, no new crate.**

## Decisions (from the card's questions, settled live)

1. **What counts as "missing":** the resolved dependency path is **not a directory** (nonexistent, or a
   file). A directory **without an `igniter.toml`** is **allowed** — `ProjectConfig::load` returns defaults
   (`source_roots = ["."]`), so such a dir is a valid package with default config (existing P2 semantics).
   Verified live; gate = `!dep_canon.is_dir()`.
2. **Where emitted:** **`collect_package_graph`** — the single graph-assembly entry shared by
   `build_module_index` (→ `resolve_entry` / compile / `check_workspace_integrity` / `verify --strict`) **and**
   `workspace_lock` (→ `lock` / `lock --frozen`). One detection site → every consumer fails identically.
3. **`workspace_lock` fails on OOF-IMP9** even with no importing module — a lock over a broken graph is
   meaningless (tested).
4. **`verify --strict`** surfaces it: graph assembly returns the diagnostic *before* integrity checks; the
   CLI renders it structurally (below).
5. **Plain `verify` / `lock`** now surface a graph-assembly `Diagnostic` as **structured JSON** (`error`
   block) instead of a generic "could not assemble" stderr line (small `main.rs` enhancement).
6. **Diagnostic shape:** `rule: OOF-IMP9`; `message` names declaring package + dep name + **root-relative**
   missing path (stable across machines); `node: dependency:<declaring-label>-><dep-name>`; `module_path:
   null` (graph fault, not a module fault); `source_paths: [declaring root, missing path]`.

## What changed

**`project.rs` `collect_package_graph`:** while walking edges, a dep whose resolved canonical path is not a
directory is collected as a missing edge (and not folded as a phantom node). After traversal, if any exist,
the **deterministic-first** (sorted) missing edge is returned as `OOF-IMP9`. Determinism: sorted by
`(declaring path, dep name, missing path)`; the message uses `relative_to(root, missing)` so it is identical
across machines.

**`main.rs` `run_lock` / `run_verify`:** the assemble-error arm now matches `Err(ProjectError::Diagnostic(d))`
and prints `{ kind, ok:false, [written:false,] error: d.to_value() }` (structured) before exit 1; a non-
diagnostic `Io` error keeps the generic stderr path. Compile already rendered project diagnostics, so it
needed no change.

## Live behavior (smoke)

```text
$ igc compile … workspace_missing_root_dep/app
  { "rule": "OOF-IMP9",
    "message": "missing dependency: package '<root>' declares dependency 'ghost' at '../ghost',
                which does not exist" }

$ igc lock … workspace_missing_transitive_dep/app          # mid declares the missing dep
  { "kind": "igniter_lock_result", "ok": false, "written": false, "error": {
      "rule": "OOF-IMP9", "node": "dependency:mid->ghost",
      "message": "missing dependency: package 'mid' declares dependency 'ghost' at '../ghost', …",
      "source_paths": [".../mid", ".../ghost"] } }                                    # exit 1, no lock written
```

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 46 passed (41 + 5 NEW P16)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 23 passed (21 + 2 NEW P16)
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P16 tests: API (5) — `missing_root_dependency_is_oof_imp9` (node `dependency:<root>->ghost`,
`module_path` null, 2 source paths), `missing_transitive_dependency_is_oof_imp9` (node `dependency:mid->ghost`),
`check_workspace_integrity_reports_missing_dep`, `workspace_lock_fails_on_missing_dep`,
`existing_dir_without_manifest_is_not_missing` (a manifest-less dir loads with defaults — NOT OOF-IMP9). CLI
(2) — `cli_lock_reports_missing_dep_structurally` (no lockfile written), `cli_verify_strict_reports_missing_dep_structurally`.
Fixtures: `workspace_missing_root_dep`, `workspace_missing_transitive_dep`, `workspace_dep_no_manifest`.

## Acceptance — mapping

- [x] Missing root dependency path → `OOF-IMP9`, not delayed `OOF-IMP2`.
- [x] Missing transitive dependency path → `OOF-IMP9` naming the declaring package/edge (`mid->ghost`).
- [x] `check_workspace_integrity` / `verify --strict` surface `OOF-IMP9` (graph assembly returns it; the CLI
      renders it structurally in `error`).
- [x] `workspace_lock` / `lock --frozen` fail with `OOF-IMP9`, no lockfile written (tested).
- [x] Existing P14/P15 tests remain green; full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`collect_package_graph` missing-edge detection → `OOF-IMP9`).
- `lang/igniter-compiler/src/main.rs` (`run_lock`/`run_verify` structured assembly-error arm).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+5 P16 tests).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+2 P16 CLI tests).
- `tests/fixtures/project_mode/{workspace_missing_root_dep,workspace_missing_transitive_dep,workspace_dep_no_manifest}` (new).

## Deferred (explicit)

- Distinguishing "path is a file" vs "path absent" in the message (both = not-a-dir today; one message).
- Reporting **all** missing edges at once (only the deterministic-first is returned, like other integrity
  faults).
- Per-consumer closed-default, glob exports, remote/registry/semver — unchanged from prior deferrals.

## Next

The local package model is feature-complete + DX-polished for v0 (graph, lock, scope, exports,
closed-default, CI gate, missing-path diagnostic). The next frontier is the **remote/registry** wave
(semver, fetch, cache) — large and separate — or further DX (`igc package` introspection). Per the user's
sequencing.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 46 green, `package_lockfile_cli_tests`
23 green, full `igniter-compiler` suite green, `git diff --check` clean. A missing declared local dependency
path is now a deterministic `OOF-IMP9` at assembly time across compile / lock / verify, with structured CLI
output and a manifest-less-dir-is-valid carve-out.*
