# LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19 — actionable details for OOF-IMP6/OOF-IMP7

Status: CLOSED
Lane: standard / package DX
Type: implementation proof
Delegation code: OPUS-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on `LAB-IGNITER-PACKAGE-IMPORT-EXPLAIN-READINESS-P18`.

P18 selected **diagnostic enrichment** as the smallest useful import-explain step. Denied imports already emit
`OOF-IMP6` or `OOF-IMP7` during compile / `verify --strict`; what is missing is machine-actionable detail. The
current diagnostic message contains useful prose, but agents should not parse English to learn the importer
package, provider package, provider path, export surface, or suggested fix.

## Goal

Add a generic diagnostic `details` field and populate it for `OOF-IMP6` and `OOF-IMP7`.

## Verify first

- `lab-docs/lang/lab-igniter-package-import-explain-readiness-p18-v0.md`
- `ProjectDiagnostic` and `ProjectDiagnostic::to_value` in `project.rs`.
- `index_integrity` branches for:
  - `OOF-IMP6`
  - `OOF-IMP7`
- Existing compile and `verify --strict` tests around package scope/exports.

## Required implementation

- Add `details: Option<serde_json::Value>` to `ProjectDiagnostic`.
- Ensure `to_value` only emits `"details"` when present.
- Default all existing diagnostics to no details.
- Populate `details` for `OOF-IMP6` with:
  - `kind: "import_scope"`
  - importer `{ module, package, path }`
  - provider `{ module, package, path }`
  - `declared_edge: false`
  - static `fix` string advising a `[dependencies]` declaration on the importer package.
- Populate `details` for `OOF-IMP7` with:
  - `kind: "import_export"`
  - importer `{ module, package, path }`
  - provider `{ module, package, path }`
  - `declared_edge: true`
  - `provider_exports`
  - `exports_default`
  - static `fix` string advising `[exports]` or importing an exported module.
- For closed-default seal, make `provider_exports` and `fix` clearly distinguish the root policy from an
  explicit allowlist miss.

## Important constraints

- `details` is evidence, not authority.
- Do not add package-specific top-level fields to `ProjectDiagnostic`.
- Do not add auto-fix.
- Do not add a new CLI command in this card.
- Do not alter diagnostic rules or taxonomy.
- Diagnostics without details should be byte-shape compatible: no `"details"` key.

## Acceptance

- [x] `OOF-IMP6` compile diagnostic includes `details.kind = "import_scope"`.
- [x] `OOF-IMP6` details include importer/provider module/package/path and `declared_edge: false`.
- [x] `OOF-IMP6` fix mentions adding `[dependencies]` to the importer package.
- [x] `OOF-IMP7` allowlist miss includes `details.kind = "import_export"` and provider export modules.
- [x] `OOF-IMP7` closed-default seal includes `exports_default: "closed"` and a seal-specific fix.
- [x] Details surface through `verify --strict` under `integrity.diagnostic`.
- [x] `OOF-IMP4`, `OOF-IMP8`, `OOF-IMP9`, and non-package diagnostics do not emit `details`.
- [x] Existing P16/P17/P18 package tests remain green.
- [x] Full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests):** `ProjectDiagnostic.details: Option<Value>` (generic escape hatch,
P11-safe; `new`=None; `to_value` emits `"details"` only when present). `index_integrity` populates it for
`OOF-IMP6` (`kind:import_scope`, importer/provider{module,package,path}, `declared_edge:false`, `[dependencies]`
fix relative to the importer) and `OOF-IMP7` (`kind:import_export`, `declared_edge:true`, `provider_exports`,
`exports_default`, fix) — the closed-default seal is distinguished from an allowlist miss via `exports_default`
+ `provider_exports.mode` + a seal-specific fix. All data already lived in the graph; the `fix` is a static
per-rule template (evidence, not a solver). Proof doc: `lab-docs/lang/lab-igniter-package-diagnostic-details-p19-v0.md`.

**Live smoke:** IMP6 fix="declare 'leaf' in the [dependencies] of '<root>' (e.g. leaf = { path = "../leaf" })";
IMP7 allowlist provider_exports={mode:allowlist,modules:[Lib.Public]}; IMP7 seal exports_default:closed,
provider_exports.mode:open, seal-specific fix; **IMP8 cycle → no details**.

**Proof — all green:** `package_workspace_tests` **50** (46 + 4 P19), `package_lockfile_cli_tests` **31**
(30 + 1 P19), full `igniter-compiler` suite green (0 failed), `git diff --check` clean. Auto-surfaces through
compile + `verify --strict` (no CLI change). Non-package diagnostics byte-unchanged.

**Deferred:** `explain-import` CLI (allowed/hypothetical); OOF-IMP2 enrichment (no provider to describe);
details for IMP4/8/9. **Next:** optional `…-EXPLAIN-IMPORT-CLI-P20` OR remote/registry wave.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-igniter-package-diagnostic-details-p19-v0.md`
- Closing report in this card.

## Closed scope

- No `igc package explain-import` command.
- No allowed-import explanation.
- No unresolved-import (`OOF-IMP2`) enrichment unless needed by a tiny compatibility fix.
- No registry/remote/semver.
- No auto-fix or package edit tooling.
