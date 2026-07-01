# LAB-IGNITER-WORKSPACE-STATUS-DOCTOR-P2 — read-only `igniter workspace status/doctor`

Status: DONE
Lane: distribution / command center / workspace Dev lane
Type: implementation
Delegation code: OPUS-IGNITER-WORKSPACE-STATUS-DOCTOR-P2
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P1 (`LAB-IGNITER-COMMAND-CENTER-AUTONOMY-READINESS-P1`) decided:

- Do **not** merge core crates into one `igniter-core` code blob.
- Keep granular crates + mirrors.
- Promote `bin/igniter` into the durable command center.
- Add the missing **Dev lane**: `igniter workspace ...`.

Current live surface:

- `bin/igniter` has `serve/check/doctor/toolchain/package/app/agent/env/stdlib/explain`.
- `bin/igniter` has **no `workspace` verb**.
- `bin/igniter` already has text + `--json` doctor machinery using records:
  `{scope, check, severity, detail, suggest}`.
- Core has been flattened to repo root:
  `igniter-stdlib`, `igniter-compiler`, `igniter-vm`, `igniter-machine`, `igniter-tbackend`.
- Compiler still needs canon sibling:
  `../igniter-lang/docs/spec/stdlib-inventory.json`.
- Mirrors exist under `git.int.avenlance.com:222/Igniter/*`.
- `igniter-machine` fleet fixtures are now crate-local under
  `igniter-machine/tests/fixtures/fleet_apps`.

This card implements the first Dev-lane slice: **read-only diagnosis only**. No clone, fetch, pull, push,
build, test, or rewrite.

## Goal

Implement:

```text
igniter workspace status [--json]
igniter workspace doctor [--json]
igniter workspace --help
```

Both commands are read-only.

`workspace status` should report the core workspace layout and mirror state in a compact human-readable form.
`workspace doctor` should emit diagnostic records using the same schema as existing `doctor --json`.

## Verify first

Read live code before editing:

- `bin/igniter`
- `bin/igniter-install`
- `bin/push-*-mirror`
- `lab-docs/lang/lab-igniter-command-center-autonomy-readiness-p1-v0.md`
- current `Cargo.toml` files for the five core crates
- current `git remote -v` and `git ls-remote` facts where cheap

Do not rely on old distribution docs if live `bin/igniter` differs.

## Required behavior

### Workspace scope

The v0 workspace scope is the current source checkout:

```text
igniter-lab/
  igniter-stdlib/
  igniter-compiler/
  igniter-vm/
  igniter-machine/
  igniter-tbackend/
../igniter-lang/
```

Report these checks:

1. source checkout root present;
2. five core crate directories present;
3. five core `Cargo.toml` files present;
4. `../igniter-lang/docs/spec/stdlib-inventory.json` present;
5. mirror helper scripts present:
   - `bin/push-igniter-stdlib-mirror`
   - `bin/push-igniter-compiler-mirror`
   - `bin/push-igniter-vm-mirror`
   - `bin/push-igniter-machine-mirror`
   - `bin/push-tbackend-mirror`
6. current git branch and dirty status for `igniter-lab`;
7. best-effort mirror remote HEADs for the five core mirrors if network/SSH is available.

Network check must be **soft**:

- If `git ls-remote` works, report remote HEAD.
- If it fails, return a `warn`, not fatal.
- Do not prompt for credentials.
- Do not fetch/pull.

### Output

Text output should be concise and readable.

JSON output must use the existing doctor record shape:

```json
[
  {
    "scope": "workspace",
    "check": "igniter-lang sibling",
    "severity": "ok",
    "detail": "../igniter-lang/docs/spec/stdlib-inventory.json present",
    "suggest": ""
  }
]
```

Severity vocabulary must match existing doctor: `ok`, `warn`, `fail`, `info`.

### Exit codes

- `workspace status`: exits `0` unless usage error.
- `workspace doctor`: exits non-zero only if required local layout checks fail.
- Remote mirror lookup failures are `warn`, not non-zero.
- Usage error exits `2`, matching existing style.

## Design constraints

- Shell implementation is acceptable for this card.
- Reuse existing `json_escape` / doctor helpers where practical.
- Do not rewrite `bin/igniter` wholesale.
- Do not add a root Cargo workspace.
- Do not modify `Cargo.toml`.
- Do not implement `workspace sync`, `build`, or `test`.
- Do not call mirror push helpers.
- Do not mutate the filesystem.
- Do not print secrets or env values.

## Tests / verification

Add focused tests if there is an existing wrapper test harness for `bin/igniter`. If not, add the smallest
reasonable shell or Rust test used by nearby distribution cards.

At minimum run:

```text
bin/igniter workspace --help
bin/igniter workspace status
bin/igniter workspace doctor
bin/igniter workspace status --json
bin/igniter workspace doctor --json
bin/igniter doctor --json
git diff --check
```

Also verify that existing common commands still work:

```text
bin/igniter --help
bin/igniter doctor
```

## Acceptance

- [x] `igniter workspace --help` documents status/doctor.
- [x] `igniter workspace status` reports core layout + branch/dirty + mirror helper presence.
- [x] `igniter workspace doctor` reports diagnostic records for required local checks.
- [x] `--json` works for both status and doctor.
- [x] JSON uses the existing doctor record schema.
- [x] Missing `igniter-lang` sibling is a local `fail` with clear suggestion.
- [x] Remote mirror lookup failure is only `warn`.
- [x] No filesystem mutation.
- [x] No clone/fetch/pull/push.
- [x] Existing `igniter doctor --json` still works.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-07-01. Changes staged (not committed). No mirrors pushed.

**Implemented** in `bin/igniter` (shell, per P1's decision — no Rust CLI yet): a new top-level
`workspace` verb with `cmd_workspace` → `workspace_usage` + `ws_collect` + `ws_run`, wired into `main()`
and the front-door `usage()`. **Reuses the existing doctor machinery** (`doc_emit` / `doc_render_text` /
`doc_render_json` / `json_escape`), so `--json` shares one schema `[{scope,check,severity,detail,suggest}]`
with severity vocabulary `ok/warn/fail/info`.

**Behavior (all read-only — no clone/fetch/pull/push/build/test, no FS mutation, no secret/env values):**

- `workspace status [--json]` — emits `scope:"workspace"` records: mode (source-checkout vs
  installed-prefix), the five flattened core crates + `Cargo.toml` presence, the `igniter-lang` canon
  sibling, the five mirror push helpers, `igniter-lab` branch + dirty, and best-effort mirror remote
  HEADs. Always exit 0 (unless usage → 2).
- `workspace doctor [--json]` — same checks; exits **1** only on a required-LOCAL layout fail (missing
  core crate / `Cargo.toml` / canon sibling). Remote lookups stay `warn`.
- **Remote HEADs are SOFT**: `git ls-remote` under `GIT_TERMINAL_PROMPT=0` +
  `GIT_SSH_COMMAND='ssh -oBatchMode=yes -oConnectTimeout=5'` — never prompts, bounded, `warn` on failure.
  `IGNITER_WORKSPACE_NO_REMOTE=1` skips them (CI/offline/hermetic tests).
- Installed-prefix mode (no crate tree) is a graceful `info` ("targets a source checkout"), not a fail.

**Verification (this box):**

- `workspace --help | status | doctor | status --json | doctor --json` → exit 0; `doctor --json` (existing)
  → exit 0; `--help` / `doctor` → exit 0.
- Live `status` shows all 5 crates ok, canon sibling ok, 5 mirror helpers ok, branch `main`, and real
  mirror HEADs (`main @ <sha>` for stdlib/compiler/vm/machine/tbackend — SSH reachable).
- Fail path: with the canon inventory renamed away, `workspace doctor` → `[fail] igniter-lang sibling` +
  **exit 1**, while `workspace status` → **exit 0**; sibling restored.
- New `server/igniter-web/tests/igniter_workspace_tests.rs` → **6/6 pass** (help, layout+mirrors, JSON
  schema for both verbs, doctor-fails-without-sibling vs status-does-not on a synthetic checkout,
  installed-prefix info, unknown-subcommand→2). Tests run with `IGNITER_WORKSPACE_NO_REMOTE=1` (hermetic).
- Regression: existing `igniter_doctor_tests` → 6/6 pass. `git diff --check` clean; no trailing whitespace.

**Status of `igniter-machine` etc. unchanged.** No `Cargo.toml` touched, no root workspace, no authority
moved (the verb only reads git + the filesystem and reports). Next in the wave: P3 (`workspace build|test`
+ optional gated `sync`), then P4 (unify the JSON/MCP diagnostic contract).
