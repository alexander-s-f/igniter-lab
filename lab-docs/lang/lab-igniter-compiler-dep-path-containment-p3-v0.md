# lab-igniter-compiler-dep-path-containment-p3-v0

Status: DONE
Date: 2026-06-27
Lane: igniter-lab / lang / igniter-compiler / package resolver containment
Authority: lab implementation proof; `igniter-lang` canon unchanged.

## Decision

Local package dependency paths are now workspace-contained before a package node
is accepted into the graph.

Chosen trust root:

```text
workspace_root = parent(canonical initial project root)
```

This preserves the existing local workspace shape where an app package declares
a sibling dependency such as `../lib`. A stricter declaring-package-root rule
would break current tested package workflows without a new workspace manifest.

Absolute local dependency paths are refused in v0. Lab package manifests should
use relative paths that remain under the workspace trust root after lexical
normalization and filesystem canonicalization.

## Implemented Refusal

`lang/igniter-compiler/src/project.rs` now resolves each dependency root through
`resolve_dependency_root(...)` before graph insertion:

- absolute dependency paths return `OOF-IMP10`;
- relative paths that lexically climb above `workspace_root` return
  `OOF-IMP10`;
- existing directories are canonicalized, so symlink escapes outside
  `workspace_root` return `OOF-IMP10`;
- missing paths that stay inside the workspace still use the existing missing
  dependency path, `OOF-IMP9`.

`OOF-IMP10` is structured and stable:

- `details.declaring_package`;
- `details.dependency`;
- `details.declared_path`;
- `details.resolved_path`;
- `details.workspace_root`;
- `details.reason`.

## Path Matrix

| Manifest path shape | Result | Evidence |
|---|---|---|
| `../lib` sibling package under workspace root | accepted | Existing `cross_package_import_resolves` and `bare_string_dependency_path_resolves` stay green. |
| `../../outside` above workspace root | refused as `OOF-IMP10`, `details.reason = "lexical path escapes"` | `dependency_path_parent_escape_is_oof_imp10`. |
| absolute local path | refused as `OOF-IMP10`, `details.reason = "absolute paths are not allowed"` | `dependency_path_absolute_is_oof_imp10`. |
| symlink inside workspace pointing outside | refused as `OOF-IMP10`, `details.reason = "canonical path escapes"` | `dependency_path_symlink_escape_is_oof_imp10` on Unix. |
| missing relative path that stays inside workspace | unchanged `OOF-IMP9` missing dependency behavior | Existing package graph / verify strict tests stay green. |

## Out Of Scope

No registry, semver solver, signing, remote source, package execution from
admission, default-on compile-lock policy, or package format change was added.

## Verification

Commands run from `/Users/alex/dev/projects/igniter-workspace/igniter-lab`:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test project_mode_tests
git diff --check
```

Results:

- `package_workspace_tests`: 53 passed;
- `package_lockfile_cli_tests`: 55 passed;
- `project_mode_tests`: 9 passed.
- `git diff --check`: passed.
