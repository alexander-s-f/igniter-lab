# LAB-DISTRIBUTION-DOC-GUARD-HYGIENE-P38

Status: CLOSED (2026-06-25) — tools/check_distribution_surface.sh guards the front-door's P33-P35 anchors against the live CLI; ALL GREEN (default + --with-tests); front-door points to it
Route: standard / guard hygiene
Skill: idd-agent-protocol

## Goal

Add a small anti-rot guard for the distribution/control-center docs, analogous to
`server/igniter-web/scripts/check_implemented_surface.sh`, so the new P33-P35 surfaces stay visible
and future agents stop routing around already-implemented DX.

## Current Authority

- Live command surface: `bin/igniter`.
- Current distribution front door: `lab-docs/lang/lab-distribution-implemented-surface-v0.md`.
- Existing guard pattern: `server/igniter-web/scripts/check_implemented_surface.sh` and
  `server/igniter-web/tests/implemented_surface_guard_tests.rs`.

## Design Target

Prefer the smallest useful guard. Recommended shape:

`tools/check_distribution_surface.sh`

or, if the repo already prefers script locality elsewhere, a clearly named script under `bin/` or
`tools/`.

The guard should be fast, DB-free, and source-backed:

1. Assert the distribution front-door doc exists.
2. Assert the doc names stable anchors:
   - `igniter env doctor`
   - `igniter env template`
   - `igniter env check`
   - `env_doctor`
   - `env_check`
   - `igniter app admit`
   - `igniter app bundle`
   - `igniter doctor`
   - `igniter toolchain`
3. Run lightweight command checks, without secrets:
   - `bin/igniter --help`
   - `bin/igniter env --help`
   - `bin/igniter app --help`
   - `bin/igniter doctor --json` if stable enough, otherwise leave as doc-only anchor.
4. Optionally run the already bounded smoke tests if runtime cost is acceptable:
   - `cargo test --test igniter_env_smoke_tests`
   - `cargo test --test igniter_agent_mcp_smoke_tests`
   - `cargo test --test igniter_app_bundle_smoke_tests`

## Boundary

Allowed:

- Add a shell guard script.
- Add one small Rust test or shell-invoked test only if it materially prevents drift.
- Add one pointer from the distribution implemented-surface doc to the guard.

Closed:

- No behavior changes to `bin/igniter`.
- No broad cargo suite.
- No live DB, no env secret requirements, no network.
- Do not make old historical proof docs fail the guard. Guard current front doors and live command
  anchors only.

## Verification / Evidence

Run:

```bash
bash -n <new-guard-script>
<new-guard-script>
git diff --check
```

If a Rust test is added, run only that test plus any affected existing guard test.

## Acceptance

- [x] Guard exists + executable: `tools/check_distribution_surface.sh` (`chmod +x`; `bash -n` clean).
- [x] DB-free and secret-free by default (doc-anchor grep + `--help`/`doctor --json`); the optional
      `--with-tests` runs only the bounded DB-free smoke suites — no live DB, no env secrets, no network.
- [x] Checks the P33/P34/P35 anchors: `igniter env doctor|template|check`, `env_doctor`, `env_check`,
      `igniter app admit`, `igniter app bundle`, `igniter doctor`, `igniter toolchain`; plus the live CLI
      advertises the env verbs (`env --help`).
- [x] Reads only the front-door doc + live commands — historical proof docs are never inspected, so old
      prose can never make it fail.
- [x] Front-door doc points to the guard (top-of-doc note).
- [x] `git diff --check` clean.

## Reporting

- **Guard path:** `tools/check_distribution_surface.sh` (run `tools/check_distribution_surface.sh`, or
  `… --with-tests` for the bounded smokes).
- **Command output:** default run → all anchors + live `--help`/`doctor --json` checks `ok` → `ALL GREEN`
  (exit 0); `--with-tests` → `bounded smoke suites ok (env / agent-mcp / app-bundle)` → `ALL GREEN`.
- **Anchors covered:** `igniter env doctor` / `igniter env template` / `igniter env check`, `env_doctor`,
  `env_check`, `igniter app admit`, `igniter app bundle`, `igniter doctor`, `igniter toolchain` (9), plus a
  live `env --help` verb check. (Making `igniter env template`/`check` literal in the doc surfaced a real
  anchor gap — the env bullets were prefixed with `igniter ` so each anchor is now unambiguous.)
- **What the guard intentionally does NOT prove:** real Postgres/DB behaviour, deploy/activation
  (current symlink / systemd / running the app), network/registry/signing, or any historical-doc accuracy.
  Default mode proves the front door + live CLI agree on the *anchors*; deeper LIVE behaviour is only the
  opt-in `--with-tests` bounded suites.

Changed files: `tools/check_distribution_surface.sh` (new), `lab-docs/lang/lab-distribution-implemented-surface-v0.md`
(guard pointer + made the three `igniter env <verb>` anchors literal). No `bin/igniter` behavior change, no
broad cargo suite.

## Reporting

Close with:

- guard path;
- exact command output;
- anchors covered;
- what the guard intentionally does not prove.
