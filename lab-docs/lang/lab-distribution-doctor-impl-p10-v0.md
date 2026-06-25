# lab-distribution-doctor-impl-p10-v0 — full v0 `igniter doctor`

**Card:** `LAB-DISTRIBUTION-DOCTOR-IMPL-P10` · **Type:** implementation + proof
**Status:** CLOSED — `igniter doctor` is now the full v0 P9 surface: local, non-mutating, **text + `--json`**,
**toolchain mode + `igniter doctor <app_dir>` app mode**, with **source-checkout vs installed-prefix** detection
and a strict no-secrets rule. Exits 0 always (a report). Proven by 6 focused doctor tests + the 16 wrapper
tests staying green.

## Gate

Depends on P9 (doctor readiness — CLOSED), P7 (skeleton — CLOSED), P8 (bootstrap install — CLOSED). All done.

## Verify-first findings

- **P9 packet** — the v0 check set, severity model (`ok`/`warn`/`fail`/`info`), text+`--json`, security rule.
- **P7's minimal doctor** (the seed) and **P8's manifest shape** (`<prefix>/igniter-manifest.json`).
- **host.toml secret contract** (`host_config.rs`): inline secret keys `dsn/password/secret/token/passport/
  api_key` fail closed; safe form is `*_env = "VAR_NAME"`; DSN/passport never logged — doctor mirrors this
  (key NAMES + env NAMES + booleans only).
- **`examples/todo_app`** — `igweb.toml` has `[app] entry = "Serve"`, no `host.toml` (observed/loopback).
- **P8 polish point reproduced:** a staged prefix has no crate tree, so the old doctor reported the missing
  `igniter-lang` sibling as a scary source-checkout failure. P10 distinguishes the two modes.

## What changed (`bin/igniter` only — `cmd_doctor` + render helpers; +1 test file)

- **Mode detection:** `source-checkout` (when `server/igniter-web/Cargo.toml` exists under the root) vs
  `installed-prefix` (a staged prefix). The `igniter-lang` sibling is a **`fail`** only in source-checkout
  mode (it's a *build* prereq); in installed-prefix mode it is **`info` — "not required (build-time only)"**.
- **Toolchain checks:** mode, rustc, cargo, igniter-lang sibling, `$PATH` (is the front door's bin dir on
  PATH?), install manifest, the 5-binary fleet (co-located staged → `IGNITER_IGWEB_SERVE_BIN` → repo build →
  `warn` not-built), and `igniter-repl` excluded (`info`).
- **App checks** (`igniter doctor <app_dir>`): app dir exists, `igweb.toml` present + `[app]`, `host.toml`
  secret-safety (inline secret keys flagged **by name only**), referenced `*_env` vars set/unset **by name
  only**, and a build pointer to `igniter check` (doctor never compiles).
- **Severity:** `ok`/`warn`/`fail`/`info`; **v0 always exits 0** (a report; `--strict` deferred per P9).
- **Output:** human text (grouped by `[env]`/`[toolchain]`/`[app]`) by default; **`--json`** emits a stable
  array `[{scope, check, severity, detail, suggest}]`. Both obey the no-secrets rule.
- **Bug fixed during impl:** under `set -e`, a render loop ending in `[[ -n "$suggest" ]] && printf …` made
  the function return non-zero when `suggest` was empty, aborting before `exit 0`. Switched to `if…fi` +
  explicit `return 0`. (This is why doctor must be tested for its *exit code*, which the suite now does.)

## Proof (executed)

```text
$ igniter doctor                       # source-checkout
  [env]  mode=source-checkout · rustc ok · cargo ok · igniter-lang sibling [ok] · PATH [warn]
  [toolchain] igc/igniter-vm/igweb-serve/igniter-mcp/tbackend [ok] · igniter-repl [info excluded]
  exit 0

$ <prefix>/bin/igniter doctor          # installed-prefix (staged by igniter-install)
  [env]  mode=installed-prefix · igniter-lang sibling [info] "not required in installed-prefix mode"
  [toolchain] all 5 [ok] "(staged)"
  exit 0

$ igniter doctor <todo_app>            # app mode
  [app] app-dir [ok] · igweb.toml [ok] present with [app] · host.toml [info] none · build [info]→igniter check
  exit 0

$ igniter doctor <missing>             # [fail] app-dir … ; exit 0
$ igniter doctor <app> --json          # valid JSON array, 15 entries, scopes {env,toolchain,app}
```

Secret-safety (live + tested): a `host.toml` with inline `password = "hunter2_topsecret"` →
`[fail] host.toml  inline secret key(s): password` — the value `hunter2_topsecret` is **never** printed;
`dsn_env = "MY_TEST_DSN_VAR"` with the var set → `[ok] env:MY_TEST_DSN_VAR set` — the value never printed.

Tests — `server/igniter-web/tests/igniter_doctor_tests.rs` (**6 passed**, through `bin/igniter`):

| test | proves |
|---|---|
| `doctor_json_has_min_checks_and_scopes` | `--json` is a valid-shaped array, ≥10 checks, env+toolchain+app scopes |
| `doctor_app_reports_app_shape` | `doctor <app>` names app-dir, igweb.toml, and the `igniter check` build pointer |
| `doctor_missing_dir_fails_entry_but_exits_zero` | missing dir → `[fail] app-dir`, **exit 0** |
| `doctor_host_toml_inline_secret_named_not_valued` | inline secret flagged by **key name**; value never printed |
| `doctor_env_var_reported_by_name_not_value` | env var reported by **name + set/unset**; value never printed |
| `doctor_staged_prefix_is_installed_mode_not_scary` | staged prefix → `installed-prefix`, sibling is `info` not `fail`, fleet `(staged)` |

Regression: the 16 `igniter_serve_wrapper_smoke_tests` (serve/check/skeleton/toolchain) stay green.
`git diff --check` clean.

## Acceptance — mapping

- [x] source-checkout `doctor` reports `igniter-lang` sibling as `ok` when present.
- [x] staged-prefix `doctor` no longer reports missing `igniter-lang` as a scary failure — explains installed mode.
- [x] `doctor --json` valid JSON, ≥10 checks (15).
- [x] `doctor <todo_app>` reports app dir + manifest checks.
- [x] host.toml inline secret reported by key name only, never value.
- [x] env-var checks report names + set/unset only.
- [x] `doctor <missing_dir>` → `fail` entry, exits 0.
- [x] existing wrapper tests green; focused doctor tests added.
- [x] `git diff --check` clean.

## Closed surfaces (honored)

No auto-fix. No network. No DB connection. No compile/build in doctor (build is a pointer to `igniter check`).
No mutation. No secret printing. No Rust CLI migration (still shell).

## Follow-ons

- `--strict` (non-zero exit on `fail`) for CI gating — P9 named it deferred.
- Deferred checks from P9: STDLIB_VERSION/lockfile skew, live Postgres connectivity (opt-in DB connect).
- Rust `igniter` CLI promotion later absorbs the JSON cleanly.

---

*Lab proof. 2026-06-25. `igniter doctor` v0: local non-mutating inspector, text + `--json`, toolchain +
`doctor <app_dir>` modes, source-checkout vs installed-prefix (the P8 polish), `ok/warn/fail/info`, exit 0.
Never prints secrets/DSNs (key/env NAMES + booleans only); build delegates to `igniter check`. 6 doctor tests
+ 16 wrapper tests green; `git diff --check` clean.*
