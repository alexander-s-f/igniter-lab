# lab-igniter-package-exports-closed-default-p12-v0 — opt-in closed-by-default exports

**Card:** `LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12` · **Delegation:** `OPUS-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12`
**Status:** CLOSED (lab implementation-proof) — a workspace root can opt into **closed-by-default exports**
(`[package] exports = "closed"`): a dependency that declares no `[exports]` block is then **sealed** and
importing its modules is `OOF-IMP7`. **Default stays open** (P10 behavior, backward-compatible).
**`project.rs` + tests only — no full edition system, no `.ig` syntax, no registry/semver, no server/web/
machine change, no new crate.**

## Design: closed-default is a root *consumer* policy

Closed-by-default is a policy about how to interpret a dependency's **absence** of `[exports]`. A dependency
that wants to seal itself can already write `[exports] modules = []` (P10). The remaining question — *"what
does no declaration mean?"* — is answered by the **root** (the consumer): a team turns on strict export
hygiene for their workspace. Opt-in via a new root manifest section:

```toml
# root igniter.toml
[package]
exports = "closed"        # default "open"; "closed" ⇒ a dependency with NO [exports] block is sealed
```

- `exports = "open"` / absent ⇒ **P10 behavior** (no `[exports]` = open). Backward-compatible.
- `exports = "closed"` ⇒ a dependency with **no `[exports]` block** is sealed; any cross-package import of its
  modules → `OOF-IMP7`. A dependency that **does** declare `[exports]` keeps its allowlist. Same-package and
  `OOF-IMP6` (dependency→sibling/root) / `OOF-IMP4` edges are unchanged.
- **Only the root's policy is read** — a dependency's own `[package]` setting is irrelevant (the consumer
  decides). Verified: `index_integrity` reads `config.exports_default` where `config` is the root's.

This is the smallest honest opt-in — a one-key `[package]` section, **not** a full edition system (deferred).

## What changed (`project.rs` only)

1. `ExportsDefault { Open, Closed }` (default `Open`) + `ProjectConfig.exports_default`, parsed by
   section-scoped `parse_package_exports_default` (`[package] exports = "closed"`; any other value / absent =
   `Open`). Mirrors the existing hand-rolled parsers.
2. `index_integrity` applies the **root** policy in the existing OOF-IMP7 pass: a root→dependency edge whose
   dependency declared no exports (`dep_exports == Some(None)`) is a violation **iff** policy is `Closed`.
   `Some(Some(allow))` (a declared allowlist) is enforced exactly as in P10. Reuses `OOF-IMP7` — no new code
   path; the message distinguishes "sealed by closed policy" from "not in allowlist".

## Diagnostic (OOF-IMP7, two messages)

- **closed-default seal:** `non-exported import: module 'App.Main' imports 'Lib.A' (package lib), which
  declares no exports ([package] exports = "closed")`
- **allowlist miss (P10):** `… which package 'lib' does not export`

Both are `OOF-IMP7`, carry the P11 structured fields (`node`, `module_path`, `source_paths`, `severity`), and
flow through the same `index_integrity` (compile path + `verify --strict`).

## Live behavior (smoke)

```text
$ igc compile --project-root <ws>/workspace_closed_default/app --entry App.Main --out /tmp/x.igapp
  { "rule": "OOF-IMP7",
    "message": "non-exported import: module 'App.Main' imports 'Lib.A' (package lib),
                which declares no exports ([package] exports = \"closed\")" }

$ igc verify --project-root <ws>/workspace_closed_default/app --strict
  "integrity": { "ok": false, "diagnostic": {
     "rule": "OOF-IMP7", "node": "export:App.Main->Lib.A", "module_path": "App.Main",
     "source_paths": ["…/app/src/main.ig"], "severity": "error", "message": "…closed…" } }   # exit 1
# plain `igc verify` (drift-only) → exit 0
```

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 34 passed (30 + 4 NEW P12)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 15 passed (14 + 1 NEW P12)
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P12 tests (5) over two fixtures (`workspace_closed_default`, `workspace_closed_declared`):
- `closed_default_seals_undeclared_dependency` — closed root + lib with no `[exports]` → `OOF-IMP7`
  (message names the closed policy).
- `closed_default_honors_declared_exports_and_same_package` — closed root + lib declaring `[exports]` →
  exported import + same-package private import both resolve clean.
- `open_default_leaves_undeclared_open` — default policy unchanged (existing `workspace`).
- `check_workspace_integrity_flags_closed_default` — entry-free integrity sees the policy `OOF-IMP7`.
- CLI `cli_verify_strict_closed_default_seals` — `verify --strict` fails under closed policy; plain `verify`
  is drift-only and passes.

## Acceptance — mapping

- [x] `[package] exports = "closed"` opt-in parsed; default Open (backward-compatible; 30 P10 tests intact).
- [x] Closed policy seals an undeclared dependency → `OOF-IMP7`; declared allowlists still honored.
- [x] Same-package / OOF-IMP6 / OOF-IMP4 unchanged; open default unchanged.
- [x] Policy is the root's only; shared `index_integrity` (compile + `verify --strict`).
- [x] Full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`ExportsDefault` + `ProjectConfig.exports_default` +
  `parse_package_exports_default`; closed-policy branch in `index_integrity`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+4 P12 tests).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+1 P12 CLI test).
- `tests/fixtures/project_mode/{workspace_closed_default,workspace_closed_declared}/…` (new).

## Deferred (explicit)

- A full **`[package] edition`** mechanism (versioned language/policy bundles) — P12 ships only the single
  `[package] exports` key; an edition system is a separate, larger card.
- Per-workspace inheritance of the policy into transitive deps (none folded yet — direct-only).
- Glob exports, `.ig` `pub`, transitive graph, registry/semver — unchanged from prior deferrals.

## Next

A full `[package]`/edition story OR the transitive package graph — per the user's sequencing. Registry/semver
remain far later. The export trust model (open default, opt-in allowlists, opt-in closed-default) is now
complete for v0.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 34 green, `package_lockfile_cli_tests`
15 green, full `igniter-compiler` suite green, `git diff --check` clean. A root can opt into closed-by-default
exports via `[package] exports = "closed"`; absence stays open, declared allowlists are honored, and the
sealed case is a distinct `OOF-IMP7` enforced by the shared integrity gate.*
