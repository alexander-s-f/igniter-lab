# LAB-IGNITER-WEB-RUNNER-FAILURE-TAXONOMY-P29 — proof

**Date:** 2026-06-22
**Lane:** IgWeb / runner production hygiene
**Status:** CLOSED — implemented (not readiness)

## What this proves

`igweb-serve --host-config` now maps every startup failure to a small, **stable, redacted**
operator diagnostic with a distinct non-zero exit code — and the one real secret-leak vector (a
Postgres connect error embedding the DSN) is closed.

## Verify-first: current failure modes

| Boundary | Source | Pre-P29 surface | Post-P29 |
|---|---|---|---|
| CLI parse / non-loopback bind | `parse_cli_args` → `RunnerError::Cli` | `Err` → Debug, exit 1 | `[CONFIG_PARSE]`, exit 2, before any socket |
| host.toml parse | `load_host_config` → `HostConfigError` | `?` → Debug, exit 1 | `[CONFIG_PARSE]`, exit 2, before bind |
| env-var resolve | `resolve_host_config` → `HostConfigError::EnvVar` | `?` → Debug, exit 1 | `[CONFIG_RESOLVE]`, exit 3, before bind, names the var |
| app build | `build_loaded_app_from_dir` → `RunnerError::Build` | `?` → Debug, exit 1 | `[APP_BUILD]`, exit 4 |
| loopback bind | `tokio::net::TcpListener::bind` | `?` io::Error, exit 1 | `[BIND_REFUSED]`, exit 5 |
| **Postgres connect** | `build_*_host_from_resolved` → `format!("…: {e}")` | **`{e}` could embed the DSN**, exit 1 | `[POSTGRES_CONNECT]`, exit 6, **DSN scrubbed** |
| tokio runtime / serve loop | `block_on` internals | `?` io::Error, exit 1 | `[RUNNER_INTERNAL]`, exit 11 |

Per-request denials (`READ_DENIED`/`WRITE_DENIED`/`EFFECT_UNBOUND`/`PASSPORT_DENIED`) stay
host-owned and are returned as HTTP responses by the policy gates — named in the taxonomy for
completeness but **not** emitted as process exits. The gate messages name fields/targets, never a
DSN/passport/raw SQL (verified by the existing `*_carries_no_forbidden_surface` tests).

## The leak that was closed

Before P29 the binary did `format!("postgres.read: {e}")` / `format!("postgres.write: {e}")` and
returned that as a process error. A `tokio-postgres` connect failure embeds the connection string
(`postgres://user:password@host/db`). P29 routes both through
`RunnerDiagnostic::postgres_connect(msg, &known_dsns)`, which:

1. exact-replaces every resolved DSN the runner holds (`postgres_read_dsn`, `postgres_write_dsn`)
   with `[redacted]` — the strongest guarantee, the runner knows its own secrets;
2. pattern-scrubs `postgres://…` / `postgresql://…` URLs and libpq `password=`/`dsn=` keyword forms
   as defence-in-depth for a secret nested in a cause it did not pass in.

## New code

- **`runner_diag.rs`** (new, default-built):
  - `DiagCode` — 10 stable codes (`as_str` SCREAMING_CASE, distinct non-zero `exit_code`, never `1`).
  - `RunnerDiagnostic { code, message }` — `Display` → `igweb-serve: [CODE] <message>`.
  - `RunnerDiagnostic::postgres_connect(msg, known)` — redacting constructor.
  - `classify_host_config_error` (EnvVar → RESOLVE, else PARSE), `classify_runner_error`.
  - `redact_secrets` (exact known-secret scrub + `postgres://`/`password=` pattern fallback).
  - 12 unit tests.
- **`bin/igweb-serve.rs`**: `fn fail(diag) -> !` prints the coded diagnostic to **stderr** and exits
  with `diag.exit_code()`; stdout stays reserved for the `listening http://…` line. CLI parse and
  `run_machine_mode` are routed through diagnostics; `run_machine_mode` now returns
  `Result<(), RunnerDiagnostic>`. Postgres connect, bind, runtime, and serve-loop errors are mapped
  to their codes.
- **`tests/igweb_serve_diagnostics_tests.rs`** (new, `--features machine`): 5 subprocess tests of the
  real binary — missing DSN env (`CONFIG_RESOLVE`, before bind), inline secret (`CONFIG_PARSE`, value
  never echoed), unknown section (`CONFIG_PARSE`), non-loopback `--addr` (fails closed, no socket),
  and the happy-path minimal `host.toml` (serves one request, exits 0).

## Results

- `cargo test` (default): all suites green (66 lib unit tests, incl. 12 `runner_diag`).
- `cargo test --features machine`: all suites green (68 lib unit tests + 5 subprocess diagnostics).
- `cargo build --features postgres --bin igweb-serve`: clean (redaction wiring compiles on the real
  adapter path).
- Default build remains Postgres-free.
- `git diff --check`: clean.

## Deferred

- No tracing/logging framework; no stable public CLI contract.
- Per-request denial codes are documented but not yet surfaced as structured response headers.
- A live `POSTGRES_CONNECT` redaction proof against a real bad DSN is left to the `postgres`-gated
  e2e lane (unit + constructor tests cover the redaction logic deterministically here).
