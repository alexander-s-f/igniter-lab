# LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8 — frozen lock + strict verify (CI trust gate)

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P3–P6 gave reproducibility (content + toolchain provenance) and P7 gave import scoping (OOF-IMP6). This card
makes those guarantees **enforceable in CI without mutating the repo** — the applied "you can trust this
workspace" layer. After this, transitive package graph or module-level visibility/export are the logical
next slices, not before.

## Goal

- **`igc lock --frozen [--project-root ROOT]`** — never writes; compute the lock, compare byte-for-byte to
  the committed `igniter.lock`; exit 0 iff present and current; else exit 1 (`reason: missing`/`out-of-date`).
- **`igc verify --strict [--project-root ROOT]`** — existing drift check PLUS workspace assembly integrity
  (OOF-IMP4 duplicate, OOF-IMP6 phantom). Exit 1 on drift OR an integrity fault; JSON gains an `integrity`
  block. Plain `lock`/`verify` keep their P4 behavior.

## Closed scope

- No new lock/scope semantics — reuse P3 `workspace_lock` + P7 integrity rules (shared with compile path).
- No combined `igc ci` command (composition of the two suffices); no full type-check in strict mode.
- No registry/solver/semver, transitive graph, or module-level visibility.
- No `compile`-path behavior change; no server/web/machine change; no new crate; no canon claim.

## Verify first

- `src/main.rs` `run_lock`/`run_verify` (P4), `project_root_arg`, flag parsing.
- `src/project.rs` `resolve_entry_with_overlays` (OOF-IMP4 + OOF-IMP6 inline), `workspace_lock`/`verify_lock`.

## Required implementation

1. `project.rs`: extract OOF-IMP4 + OOF-IMP6 into a shared `index_integrity(&index,&config) ->
   Option<ProjectDiagnostic>`; add entry-free `pub fn check_workspace_integrity(root)`; keep
   `resolve_entry_with_overlays` byte-identical via the shared helper.
2. `main.rs`: `run_lock --frozen` (compute, compare on-disk byte-for-byte, never write); `run_verify
   --strict` (drift + `check_workspace_integrity`, add `integrity` JSON).

## Required tests

1. **frozen current** → exit 0, `up-to-date`, lockfile unchanged.
2. **frozen missing** → exit 1, `missing`, no lockfile created.
3. **frozen stale** → exit 1, `out-of-date`, lockfile untouched.
4. **strict catches phantom** → plain verify passes, strict fails with `integrity.diagnostic.rule=OOF-IMP6`.
5. **strict clean** → exit 0, `integrity.ok=true`.
6. **API**: `check_workspace_integrity` flags phantom (OOF-IMP6) / Ok on clean.
7. P2–P7 + full suite stay green.

## Required acceptance

- [x] `igc lock --frozen` never writes; exit 0 iff the committed lock is byte-current; else `missing`/`out-of-date`.
- [x] `igc verify --strict` = drift + workspace integrity (OOF-IMP4/OOF-IMP6); JSON `integrity` block.
- [x] Plain `lock`/`verify` keep P4 behavior (mutating / drift-only).
- [x] Integrity rules shared with the compile path (`index_integrity`); P2–P7 diagnostics byte-identical.
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change; no new crate.
- [x] `git diff --check` clean.

## Required proof doc

`lab-docs/lang/lab-igniter-package-lockfile-frozen-ci-p8-v0.md`.

---

## Closing Report (2026-06-21)

**Implementation:** `project.rs` extracted the OOF-IMP4 + OOF-IMP6 checks into `index_integrity` and added
entry-free `check_workspace_integrity` (compile path + CI gate now share one rule source; P2–P7 diagnostics
byte-identical). `main.rs`: `run_lock --frozen` (mutation-free byte-compare to the committed lock →
`up-to-date`/`out-of-date`/`missing`), `run_verify --strict` (drift + integrity, `integrity` JSON block).
Proof doc: `lab-docs/lang/lab-igniter-package-lockfile-frozen-ci-p8-v0.md`.

**Live smoke:** frozen current → ok/exit0 (no rewrite); frozen after a dep edit → `out-of-date`/exit1 (lock
untouched); `verify --strict` on a phantom workspace → `drift:[]` but `integrity:{rule:OOF-IMP6}`/exit1 while
plain `verify` passes — the strict flag is what ties P7 into CI trust.

**Proof — all green:** `package_lockfile_cli_tests` **11** (6 + 5 P8), `package_workspace_tests` **25**
(23 + 2 P8 integrity API), `project_mode` 9 intact (refactor preserved), full `igniter-compiler` suite green
(0 failed), `git diff --check` clean. CLI tests use tempdirs (no fixture pollution). Removed a now-unused
test const. No compile/server/web/machine change; no new crate.

**Deferred:** combined `igc ci`; full type-check in strict mode; registry/semver/solver; transitive graph;
module-level visibility. **Next:** module-level visibility/export OR transitive package graph (user's
sequencing) — registry/semver far later.
