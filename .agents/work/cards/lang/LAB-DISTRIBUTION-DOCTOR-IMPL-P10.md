# LAB-DISTRIBUTION-DOCTOR-IMPL-P10 - full v0 `igniter doctor`

Status: CLOSED (2026-06-25) — full v0 igniter doctor (text + --json, toolchain + app modes); 6 doctor + 16 wrapper tests green; packet at lab-docs/lang/lab-distribution-doctor-impl-p10-v0.md
Lane: distribution / diagnostics DX
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-DOCTOR-READINESS-P9`
- `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`
- `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`

P7 shipped a minimal `igniter doctor`. P9 designed the full v0 shape: local, non-mutating, human text plus
`--json`, toolchain mode and app-specific mode. P8 revealed an important polish point: a staged installed
prefix is self-contained for running, but the current doctor reports the missing `igniter-lang` sibling as if
the user were still in a source checkout. v0 doctor must distinguish **source-checkout mode** from
**installed-prefix mode**.

## Goal

Implement the P9 v0 doctor surface:

```text
igniter doctor
igniter doctor --json
igniter doctor <app_dir>
igniter doctor <app_dir> --json
```

Keep it non-mutating. No network. No DB connection. No auto-fix.

## Verify First

- Read P9 packet.
- Read current `bin/igniter` doctor implementation.
- Read `bin/igniter-install` manifest shape.
- Verify host-config parsing / secret refusal surface:
  - `server/igniter-web/src/host_config.rs`
  - `server/igniter-web/src/bin/igweb-serve.rs`
  - `runner_diag.rs`
- Verify app manifest shape with `server/igniter-web/examples/todo_app`.
- Reproduce staged-prefix doctor behavior from P8: `<prefix>/bin/igniter doctor`.

## Required Behavior

- `igniter doctor` reports toolchain/environment checks:
  rustc, cargo, source-checkout or installed-prefix mode, `igniter-lang` sibling only when relevant,
  installed manifest if present, PATH hint, fleet binaries, `igc` alias, `igniter-repl` excluded.
- `igniter doctor <app_dir>` additionally reports app-shape checks:
  app dir exists, `igweb.toml` present/readable, entry/sources parse enough to give useful errors, host.toml
  if present uses env-var references and no inline secret keys, referenced env-var names are set/unset
  without printing values.
- `--json` emits stable JSON with entries like:
  `{ "scope": "toolchain", "check": "rustc", "severity": "ok", "detail": "...", "suggest": null }`
- Human output uses `ok`/`warn`/`fail`/`info`.
- v0 exits 0 even with failures; `--strict` remains deferred unless P9 explicitly authorized it.
- Build/entry resolution points to `igniter check <app_dir>`; doctor does not compile the app.
- No secret/DSN values printed in either text or JSON.

## Acceptance

- [x] `igniter doctor` in source checkout reports `igniter-lang` sibling as ok when present.
- [x] staged-prefix `igniter doctor` no longer reports missing `igniter-lang` as a scary source-checkout failure; it explains installed mode.
- [x] `igniter doctor --json` emits valid JSON and includes at least 10 checks.
- [x] `igniter doctor <todo_app>` reports app dir + manifest checks.
- [x] host.toml inline secret key is reported by key name only, never by value.
- [x] env-var checks report env var names + set/unset only.
- [x] `igniter doctor <missing_dir>` reports a fail entry but exits 0.
- [x] Existing wrapper tests remain green; add focused doctor tests.
- [x] `git diff --check` clean.

## Closed Surfaces

No auto-fix. No network. No DB connection. No compile/build in doctor. No mutation. No secret printing.
No Rust CLI migration.

## Closing Report

Proof doc: `lab-docs/lang/lab-distribution-doctor-impl-p10-v0.md`. Gate: P9/P7/P8 CLOSED.

**Implemented** in `bin/igniter` (`cmd_doctor` + render helpers): `igniter doctor [<app_dir>] [--json]`.
**Mode detection** — source-checkout vs installed-prefix (the P8 polish: missing `igniter-lang` sibling is a
`fail` only in source-checkout mode, `info` "not required" in installed-prefix). **Toolchain checks:** mode,
rustc, cargo, igniter-lang sibling, PATH, manifest, 5-binary fleet (co-located staged → env → repo → warn),
igniter-repl excluded. **App checks (`doctor <app_dir>`):** app dir, igweb.toml `[app]`, host.toml
secret-safety (inline secret keys flagged **by name only**), `*_env` vars set/unset **by name only**, build →
pointer to `igniter check` (never compiles). **Severity** ok/warn/fail/info; **v0 exits 0**. **`--json`**
stable array. **No secrets/DSNs printed** (mirrors runner_diag redaction).

**Bug fixed:** under `set -e`, a render loop ending in `[[ -n "$suggest" ]] && printf` returned non-zero on
empty suggest → aborted before `exit 0`; switched to `if…fi` + `return 0`.

**Proof:** `igniter_doctor_tests.rs` → **6 passed** (json≥10-checks, app-shape, missing-dir-fail-exit-0,
inline-secret-by-name, env-var-by-name, staged-prefix-installed-mode). Existing 16 wrapper tests green.
`git diff --check` clean.

**Deferred:** `--strict` (non-zero on fail), STDLIB_VERSION/lockfile skew, live DB connect, Rust-CLI.
