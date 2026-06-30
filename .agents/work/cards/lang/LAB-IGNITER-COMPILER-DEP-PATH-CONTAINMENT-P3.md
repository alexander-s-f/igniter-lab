# LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3

Status: DONE
Route: standard / main-audit / compiler / package resolver containment
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`

## Goal

Close the remaining package resolver hardening gap: dependency paths must be
canonicalized and contained so `..`, symlinks, or surprising path shapes cannot
escape the intended workspace trust boundary.

P2 added explicit locked project compile. This card is about resolver path
authority, not lock semantics.

## Current Authority

Live compiler package code wins. Read first:

- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/lang/lab-igniter-compiler-lock-on-build-p2-v0.md`
- `lang/igniter-compiler/src/project.rs`
- `lang/igniter-compiler/src/main.rs`
- `lang/igniter-compiler/tests/package_workspace_tests.rs`
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`

Known live facts to verify:

- local package deps are supported;
- export/closed-default and transitive graph checks exist;
- compile `--locked` reuses lock and workspace integrity checks;
- path containment/canonicalization remains named as an open supply-chain gap.

## Scope

Allowed:

- Characterize current dependency path handling with targeted tests.
- Add resolver canonicalization/containment if the smallest safe rule is clear.
- Add diagnostics for escaped dependency roots if implemented.
- Update package proof docs / Implemented Surface if behavior changes.

Closed:

- No registry, semver solver, remote source, signing, or deploy.
- No default-on compile lock policy change.
- No package format changes unless unavoidable.
- No VM/server/machine/frame-ui changes.

## Design Boundary

Do not silently normalize unsafe inputs into surprising package identities.
Prefer explicit structured refusal over clever repair.

If implementation is not straightforward after live characterization, stop at a
readiness packet with exact failing/ambiguous cases and a recommended next card.

## Questions To Answer

1. What path forms are currently accepted in package manifests?
2. Can a dependency path escape the workspace through `..`?
3. Can a symlink dependency escape after apparent containment?
4. What is the intended trust root: project root, workspace root, or declared
   package root?
5. Should absolute local paths be allowed in lab-only workflows?

## Acceptance

- [x] Live behavior for relative, absolute, `..`, and symlink package paths is
      characterized by tests or a proof packet.
- [x] Unsafe path escape is either refused in code or explicitly marked as a
      follow-up with exact evidence.
- [x] Diagnostics are structured and stable if implementation is done.
- [x] Existing package graph, lock, verify, admit, and compile-locked tests stay
      green.
- [x] No unrelated package semantics change.
- [x] `git diff --check` passes.

## Result

Closed by `lab-docs/lang/lab-igniter-compiler-dep-path-containment-p3-v0.md`.
Dependency paths now resolve under the parent of the canonical initial project
root as the workspace trust root. Relative sibling deps such as `../lib` remain
accepted; absolute local dep paths, lexical `..` escapes above the trust root,
and symlink escapes outside the trust root are refused with structured
`OOF-IMP10`.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test project_mode_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-dep-path-containment-p3-v0.md
```

Include current path matrix, chosen trust root, implemented refusal or explicit
follow-up, and test results.
