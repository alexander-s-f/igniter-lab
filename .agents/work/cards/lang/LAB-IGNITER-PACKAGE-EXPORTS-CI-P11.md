# LAB-IGNITER-PACKAGE-EXPORTS-CI-P11 — export boundary hardening and CI ergonomics

Status: CLOSED
Lane: standard / lab readiness
Type: readiness / follow-up
Delegation code: OPUS-IGNITER-PACKAGE-EXPORTS-CI-P11
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on P9/P10.

After module exports exist, the package trust story becomes:

1. direct dependency graph;
2. content + toolchain lock provenance;
3. package-level scoping (`OOF-IMP6`);
4. module-level exports (`OOF-IMP7`);
5. CI gate (`lock --frozen`, `verify --strict`).

P11 is not a broad feature card. It should harden the UX and CI behavior around exports after P10 lands,
without opening registry/semver.

## Goal

Decide and, if small, implement the next ergonomic slice around exports:

- better JSON shape for strict integrity diagnostics;
- optional machine-readable list of exported modules in `igc verify --strict`;
- `igc package check` / `igc verify --strict --explain` if justified;
- documentation/examples for CI use.

If the live P10 experience is already sufficient, close P11 as **NO-CODE readiness** with a clear "do not
add CLI surface yet" recommendation.

## Verify first

- P10 implementation and proof doc.
- `main.rs` `run_verify --strict` JSON shape.
- Existing P8 strict tests.
- Any newly added P10 CLI tests.

## Questions to answer

1. Is P10's `OOF-IMP7` JSON enough for CI and agents, or should strict output include package/import fields
   structurally instead of only inside `message`?
2. Should `ProjectDiagnostic` grow structured metadata for importer/imported package/module, or is that too
   broad for this slice?
3. Do we need a package introspection command, or is `verify --strict` enough?
4. Should `lock --frozen` detect export-only changes through dependency digest? Verify with a live fixture.
5. Should docs recommend:

   ```bash
   igc lock --frozen --project-root app
   igc verify --strict --project-root app
   igc compile --project-root app --entry App.Main --out /tmp/app.igapp
   ```

   or a different sequence?

## Bias

Prefer **no new command** unless P10 output is genuinely insufficient. The likely useful improvement is a
small structured integrity diagnostic JSON shape in `verify --strict`, but only if it does not spread
package-specific metadata through generic diagnostics.

## Closed scope

- No transitive graph.
- No registry/semver.
- No package publish format.
- No module wildcard exports.
- No typechecker/VM/server/web work.

## Required deliverable

Either:

1. readiness-only packet:
   `lab-docs/lang/lab-igniter-package-exports-ci-p11-v0.md`

or, if a tiny implementation is clearly justified:

2. implementation proof doc at the same path plus tests.

## Required acceptance

- [x] P10 live output reviewed.
- [x] Decision made: no-code vs small hardening.
- [x] CI sequence documented.
- [x] Export-only lock drift verified or explicitly delegated.
- [x] If code changes: P8/P10 tests + full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Decision: small hardening** (one-line `main.rs` change + 1 test + CI docs), per the card's bias — prefer no
new command; add structured integrity JSON only if it doesn't spread package metadata through generic
diagnostics.

**Verify-first:** P10's `verify --strict` built the integrity diagnostic by hand as `json!({rule,message})`,
discarding the structured fields `ProjectDiagnostic.to_value()` already serializes (`node`/`module_path`/
`source_paths`/`severity`) → CI/agents had to regex the message.

**Change:** `run_verify --strict` now emits `Some(d.to_value())` — the existing serializer. **No new field on
`ProjectDiagnostic`** (metadata not spread); `integrity.diagnostic` now carries `rule`+`node`+`module_path`+
`source_paths`+`severity`+`message`. Proof doc: `lab-docs/lang/lab-igniter-package-exports-ci-p11-v0.md`.

**Question answers:** (1) structural, not message-only; (2) no — don't grow `ProjectDiagnostic`; (3) no
introspection command; (4) export-only drift already covered by the P10 manifest-in-digest fold
(`cli_export_change_is_lock_drift` green); (5) CI = `lock --frozen` → `verify --strict` → optional `compile`.

**Live smoke:** `verify --strict` on a non-exported import → `integrity.diagnostic` =
`{rule:OOF-IMP7, node:"export:App.Main->Lib.Private", module_path:"App.Main", source_paths:[…/main.ig],
severity, message}`, exit 1.

**Proof — all green:** `package_lockfile_cli_tests` **14** (13 + 1 P11), `package_workspace_tests` 30 intact,
full `igniter-compiler` suite green (0 failed), `git diff --check` clean. No new command/metadata/crate.

**Deferred:** `igc package check`/`--explain` (not added); extra structured *package* fields (message+node
suffice); closed-default exports / transitive graph / registry-semver (unchanged from P10). **Next:**
closed-default exports OR transitive package graph (user's sequencing).

