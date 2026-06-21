# LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12 — opt-in closed-by-default exports

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P10 implemented module exports with **opt-in closure**: a dependency with no `[exports]` block is **open**
(every module importable). P9/P11 deferred **closed-by-default** to "a future `[package] edition`-style
global opt-in." This card adds that opt-in — minimally, without a full edition system.

## Verify-first

- No `[package]`/edition concept exists in `igniter-compiler` (`rg '\[package\]|edition'` → none).
- `project.rs`: `ProjectConfig.exports: Option<Vec<String>>`, `parse_exports_toml`, `ModuleIndex.dep_exports`
  (`None` = open, `Some(set)` = allowlist), `index_integrity` OOF-IMP7 pass, `dependency_digest` manifest fold.
- A dependency that wants to seal itself can already write `[exports] modules = []` (P10). The only gap is the
  *interpretation of absence*: today absence = open.

## Design decision (closed-default = root consumer policy)

Closed-by-default is a policy about how to interpret a dependency's **absence** of `[exports]`. The **root**
(consumer) owns it: a team turns on strict export hygiene for their workspace. Opt-in via a new root manifest
section:

```toml
# root igniter.toml
[package]
exports = "closed"     # default "open"; "closed" ⇒ a dependency with NO [exports] block exports nothing
```

- `exports = "open"` or absent ⇒ **P10 behavior** (no `[exports]` = open). Backward-compatible.
- `exports = "closed"` ⇒ a dependency with **no `[exports]` block** is treated as **sealed**; any cross-package
  import of its modules → `OOF-IMP7`. A dependency that **does** declare `[exports]` is unaffected (its
  allowlist still stands). Same-package and dependency→dependency (OOF-IMP6) edges are unchanged.
- Only the **root's** policy is read; a dependency's own `[package]` setting is irrelevant (consumer decides).
- Reuses `OOF-IMP7` (no new code); the policy only changes how `dep_exports == Some(None)` is interpreted.

## Closed scope

- No full edition system (just `[package] exports`), no semver/registry/transitive graph.
- No change to OOF-IMP6/OOF-IMP4; no `.ig` syntax; no server/web/machine; no new crate.
- Default stays **open** (opt-in only) — existing fixtures/tests unchanged.

## Required implementation (`project.rs`)

1. `ExportsDefault { Open, Closed }` + `ProjectConfig.exports_default` (default `Open`); section-scoped
   `parse_package_exports_default` on `[package] exports = "..."`.
2. In `index_integrity`, apply the **root** policy: for a root→dependency edge whose dependency declared no
   exports (`dep_exports == Some(None)`), if policy is `Closed` → `OOF-IMP7` (sealed-by-policy), with a
   message distinct from the allowlist-miss case.

## Required tests / fixtures

Fixtures under `tests/fixtures/project_mode/`:
1. `workspace_closed_default` — root `[package] exports="closed"`, `lib` has NO `[exports]`; `app` imports a
   lib module → `OOF-IMP7` (sealed by policy).
2. `workspace_closed_declared` — root closed, `lib` declares `[exports] modules=["Lib.Public"]`,
   `Lib.Public import Lib.Private`; `app` imports `Lib.Public` → resolves clean (declared export honored +
   same-package bypass under closed).

Tests (`package_workspace_tests.rs`):
- closed-default seals an undeclared dependency (`OOF-IMP7`, message names closed policy).
- closed-default honors a declared allowlist + same-package import (resolves clean).
- open default (existing `workspace`, no `[package]`) stays open.
- `check_workspace_integrity` reports the policy `OOF-IMP7` entry-free.
- CLI: `verify --strict` under closed policy → `OOF-IMP7`.
- P10 OOF-IMP7 (allowlist miss) + P7 OOF-IMP6 unaffected.

## Required acceptance

- [x] `[package] exports = "closed"` opt-in parsed; default Open (backward-compatible).
- [x] Closed policy seals an undeclared dependency → `OOF-IMP7`; declared allowlists still honored.
- [x] Same-package / OOF-IMP6 / OOF-IMP4 unchanged; open default unchanged.
- [x] Policy is the root's only; shared `index_integrity` (compile + `verify --strict`).
- [x] Full `igniter-compiler` suite green; `git diff --check` clean.

## Required proof doc

`lab-docs/lang/lab-igniter-package-exports-closed-default-p12-v0.md` — opt-in shape, why root-consumer
policy, message taxonomy, fixtures/tests/counts, deferred (full edition system), next card.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests):** `ExportsDefault {Open, Closed}` (default Open) +
`ProjectConfig.exports_default` + section-scoped `parse_package_exports_default` (`[package] exports =
"closed"`). `index_integrity` applies the **root** policy in the existing OOF-IMP7 pass: a root→dependency
edge whose dependency declared no exports (`Some(None)`) is a violation iff policy is `Closed`; declared
allowlists (`Some(Some)`) enforced as in P10. Distinct message for the sealed-by-policy case. Proof doc:
`lab-docs/lang/lab-igniter-package-exports-closed-default-p12-v0.md`.

**Design:** closed-default = root **consumer** policy (interprets a dependency's *absence* of `[exports]`);
only the root's setting is read; opt-in, backward-compatible (absent/open = P10). Single `[package] exports`
key — NOT a full edition system (deferred).

**Live smoke:** `compile` closed-default → `OOF-IMP7: …which declares no exports ([package] exports =
"closed")`; `verify --strict` → structured `integrity.diagnostic` (rule/node/module_path/source_paths), exit
1; plain `verify` drift-only passes.

**Proof — all green:** `package_workspace_tests` **34** (30 + 4 P12), `package_lockfile_cli_tests` **15**
(14 + 1 P12), full `igniter-compiler` suite green (0 failed), `git diff --check` clean. Default Open keeps all
30 P10 tests intact. Fixtures `workspace_closed_default` / `workspace_closed_declared`. No `.ig` syntax /
server / web / machine; no new crate.

**Deferred:** full `[package] edition` system; policy inheritance into transitive deps; glob exports; `.ig`
`pub`; transitive graph; registry/semver. **Next:** full edition story OR transitive package graph (user's
sequencing). The v0 export trust model (open default, opt-in allowlists, opt-in closed-default) is complete.
