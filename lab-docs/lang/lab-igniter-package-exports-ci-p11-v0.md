# lab-igniter-package-exports-ci-p11-v0 — export boundary hardening & CI ergonomics

**Card:** `LAB-IGNITER-PACKAGE-EXPORTS-CI-P11` · **Delegation:** `OPUS-IGNITER-PACKAGE-EXPORTS-CI-P11`
**Status:** CLOSED (lab implementation-proof — **small hardening**, not a broad feature) — `igc verify
--strict` now emits a **structured** integrity diagnostic so CI and agents read importer/imported/package/
path as fields instead of parsing `message`. **No new command, no new diagnostic metadata, no registry/
semver. One-line `main.rs` change (`d.to_value()`) + one CLI test + CI docs.**

## Decision: small hardening (not no-code, not a new command)

The card's bias: prefer **no new command** unless P10 output is genuinely insufficient; the one likely-useful
improvement is a **structured integrity JSON** *if it doesn't spread package-specific metadata through generic
diagnostics*. Verify-first showed P10's strict output discarded structure it already had — so the minimal,
bias-compliant fix is to **stop discarding it**, not to add anything.

## Verify-first finding

P10's `run_verify --strict` built the integrity diagnostic by hand as `json!({ "rule", "message" })` —
dropping the structured fields `ProjectDiagnostic` **already** serializes via `to_value()` (`node`,
`module_path`, `source_paths`, `severity`). So an agent/CI had to **regex the English `message`** to recover
the importer module, the imported module/package, and the source path. The fields existed; the strict path
threw them away.

## What changed (one line + a test)

`run_verify --strict` now returns the diagnostic's full structured form:
```rust
Err(project::ProjectError::Diagnostic(d)) => Some(d.to_value()),   // was json!({rule, message})
```
This **adds no field** to the generic `ProjectDiagnostic` (bias honored — no package-specific metadata
spread); it reuses the existing serializer. The `integrity.diagnostic` block now carries
`rule` + `node` + `module_path` + `source_paths` + `severity` + `message`.

### Before / after (`verify --strict` on a non-exported import)
```jsonc
// P10
"integrity": { "ok": false, "diagnostic": { "rule": "OOF-IMP7", "message": "non-exported import: …" } }

// P11
"integrity": { "ok": false, "diagnostic": {
  "rule": "OOF-IMP7",
  "node": "export:App.Main->Lib.Private",
  "module_path": "App.Main",
  "source_paths": ["…/app/src/main.ig"],
  "severity": "error",
  "message": "non-exported import: module 'App.Main' imports 'Lib.Private' (package lib), which package 'lib' does not export"
} }
```
Same structured shape applies to `OOF-IMP4` / `OOF-IMP6` integrity faults (one serializer for all).

## Card questions — answers

1. **Is OOF-IMP7 JSON enough, or structural fields?** Not enough as message-only → now **structural**
   (`node`/`module_path`/`source_paths`), via the existing serializer.
2. **Grow `ProjectDiagnostic` metadata?** **No** — too broad and unnecessary; the needed fields already
   exist. P11 only surfaces them.
3. **Package introspection command?** **No** — `verify --strict` (now structured) is sufficient; no
   `igc package check` / `--explain`.
4. **Export-only lock drift via digest?** **Yes, verified.** P10 folded the dependency `igniter.toml` into
   its digest; `cli_export_change_is_lock_drift` (re-run green) proves an `[exports]`-only edit is a `changed`
   drift caught by `igc verify` / `lock --frozen`. No new work needed.
5. **CI sequence?** Documented below.

## Recommended CI sequence

```bash
# 1. the committed lock is current (mutation-free; content + toolchain + manifest/exports drift)
igc lock   --project-root app --frozen
# 2. the workspace matches its lock AND assembles cleanly (scope OOF-IMP6 + exports OOF-IMP7, structured JSON)
igc verify --project-root app --strict
# 3. (optional) full build of the entry
igc compile --project-root app --entry App.Main --out /tmp/app.igapp
```
Steps 1–2 are the trust gate; step 3 is a full compile when CI also wants the artifact. `--frozen` never
writes; `--strict` exits non-zero with a structured `integrity.diagnostic` on any OOF-IMP4/6/7 fault.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 14 passed (13 + 1 NEW P11)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests      → 30 passed (P10 intact)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

New P11 test (1): `cli_verify_strict_integrity_is_structured` — strict verify on `workspace_exports_private`
→ `integrity.diagnostic` has `rule=OOF-IMP7`, `module_path="App.Main"`, `node="export:App.Main->Lib.Private"`,
a single `source_paths` entry, and the message still present. Existing P8/P10 strict tests
(`rule` access) stay green — `to_value()` keeps the `rule` field.

## Acceptance — mapping

- [x] P10 live output reviewed (message-only structure identified).
- [x] Decision made: **small hardening** (structured integrity JSON via existing `to_value()`).
- [x] CI sequence documented (`lock --frozen` → `verify --strict` → optional `compile`).
- [x] Export-only lock drift verified (P10 digest fold; `cli_export_change_is_lock_drift` green).
- [x] P8/P10 tests + full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/main.rs` (`run_verify --strict` integrity diagnostic → `d.to_value()`).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+1 structured-integrity test).

## Deferred (explicit)

- `igc package check` / `verify --strict --explain` — **not added** (sufficient without).
- Structured importer/imported *package* fields beyond `node`/`module_path` — message + node suffice; revisit
  only if an agent need is demonstrated.
- Closed-by-default exports, transitive graph, registry/semver — unchanged from P10's deferrals.

## Next

`LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P*` (global opt-in to closed exports) OR the transitive package
graph — per the user's sequencing. Registry/semver remain far later.

---

*Lab implementation-proof (small hardening). Compiled 2026-06-21; `package_lockfile_cli_tests` 14 green,
`package_workspace_tests` 30 intact, full `igniter-compiler` suite green, `git diff --check` clean. Strict
integrity diagnostics are now structured (no new metadata, existing serializer), and the CI trust sequence is
documented — export-only changes are already lock drift via the P10 manifest fold.*
