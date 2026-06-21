# lab-igniter-package-transitive-graph-ci-p15-v0 — graph lock/strict hardening

**Card:** `LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15` · **Delegation:** `OPUS-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15`
**Status:** CLOSED (lab implementation-proof — **test-only hardening**, no production code) — P14's CI trust
gate already covers the transitive graph correctly; P15 **regression-locks** that with four CLI tests for the
gaps P14 only proved live. **No `project.rs`/`main.rs` change, no registry/semver, no new fixtures.**

## Decision: no production code — P14 is already correct; lock it in with tests

Verify-first live evidence showed every CI guarantee already holds against graph reality (P10's
manifest-in-digest fold + P14's full-graph lock + shared `index_integrity`). So **no production fix is
needed.** The honest hardening is to convert "proven live once" into "guarded forever" — four regression
tests for the behaviors P14 did not explicitly cover.

## Verify-first live evidence (P14 behavior)

| Q | Question | Result |
|---|---|---|
| 1 | Lock pins the full reachable graph? | **Yes** — `igniter.lock` for `workspace_transitive_ok` lists `mid` **and** `leaf` (transitive). |
| 2 | Leaf `.ig` change → drift? | **Yes** — P14 `cli_transitive_content_drift_detected`. |
| 3 | Leaf **manifest** (`igniter.toml`) change → drift? | **Yes** — editing `leaf/igniter.toml` `[exports]` → `verify` `changed` drift for `leaf` (the P10 manifest fold applies per-node across the graph). |
| 4 | `lock --frozen` catches leaf drift without writing? | **Yes** — after a leaf edit → `out-of-date`, `written:false`, lockfile byte-unchanged. |
| 5 | `verify --strict` reports transitive `OOF-IMP6`/`OOF-IMP7` structurally? | **Yes** — `integrity.diagnostic` carries `rule` + `node` + `module_path` + `source_paths` + `severity` (P11 shape) for transitive faults. |
| 6 | Cycle (`OOF-IMP8`) structured enough? | **Yes** — carries `node` (`cycle:a->b->a`), `message`, and `source_paths` (the cycle's canonical paths). |
| 7 | Should lock entries carry parent/path provenance for transitive packages? | **No (decided)** — the root-relative path uniquely identifies each node and shows its location; a parent field adds noise and would churn the lock format without improving drift detection. Deferred. |
| 8 | Duplicate canonical-path / name ambiguity needing a fix? | **No** — canonical-path identity dedups a diamond to one node (P14 `diamond_same_package_dedups`); `verify` matches by **path**, so colliding display names are harmless. No solver/identity card needed. |

## What changed (tests only)

Four CLI regression tests in `package_lockfile_cli_tests.rs`, all over **existing** P14 fixtures, no
production code:
- `cli_leaf_manifest_change_is_drift` — edit a transitive leaf's `igniter.toml` → `verify` `changed` drift
  for `leaf`.
- `cli_frozen_catches_leaf_drift` — after a leaf `.ig` edit, `lock --frozen` → `out-of-date`, lockfile
  unchanged.
- `cli_verify_strict_catches_transitive_phantom` — transitive `OOF-IMP6` with structured `module_path` +
  `source_paths`.
- `cli_verify_strict_catches_transitive_non_export` — transitive `OOF-IMP7` with structured `module_path`.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 21 passed (17 + 4 NEW P15)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests      → 41 passed (P14 intact)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

## Acceptance — mapping

- [x] P14 lock/frozen/strict behavior verified live (table above).
- [x] Leaf `.ig` and leaf manifest drift behavior proven (live + now regression-tested).
- [x] Decision made: **no production code; test-only hardening** (P14 already correct).
- [x] P14/P8/P11 tests + full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+4 P15 regression tests). No production code.

## Deferred (explicit)

- Lock parent/path provenance for transitive packages (Q7 — not needed; path suffices).
- `OOF-IMP9` (missing declared dependency path); per-consumer closed-default; glob exports.
- Remote/registry/semver/solver — the next major wave.

## Next

The **local** package model (direct + transitive graph, content+toolchain lock, scope, exports,
closed-default, CI gate) is feature-complete and regression-locked for v0. The next frontier is
**remote/registry** (semver, fetch, cache) — a large separate wave — or small DX polish (`OOF-IMP9`, `igc
package` introspection). Per the user's sequencing.

---

*Lab implementation-proof (test-only hardening). Compiled 2026-06-21; `package_lockfile_cli_tests` 21 green,
`package_workspace_tests` 41 intact, full `igniter-compiler` suite green, `git diff --check` clean. P14's CI
trust gate already covers the transitive graph (full-graph lock, leaf `.ig`+manifest drift, frozen, structured
strict diagnostics, cycle); P15 regression-locks it without touching production code.*
