# LAB-IGNITER-WEB-RUNNER-FAILURE-TAXONOMY-P29 - operator diagnostics and redaction

Status: CLOSED
Lane: IgWeb / runner production hygiene
Type: implementation, with readiness fallback
Delegation code: OPUS-WEB-RUNNER-FAILURE-TAXONOMY-P29
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

`igweb-serve --host-config` now crosses several host-owned boundaries:

- config parse;
- env-var resolution;
- loopback bind;
- app compile/load;
- read executor connect/policy;
- write executor connect/policy;
- bearer/passport routing;
- staged `ReadThen`;
- final effect dispatch and receipts.

The proof is real, but an operator failure can still look like an arbitrary Rust error. Production
hygiene needs a small, redacted, stable diagnostic taxonomy before we add more DB/app pressure.

## Goal

Inventory current `igweb-serve` failure modes, then improve the smallest useful surface so common
operator errors produce clear, redacted messages and non-zero exit codes without leaking secrets.

## Verify first

Read and characterize current errors:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/lib.rs` (`RunnerError`)
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`

Run or inspect tests for missing DSN env, bad bind addr, malformed host config, denied source/field,
unbound effect target, missing passport env, and Postgres connection failure.

## Implementation bias

Prefer narrow improvements:

- error messages name the config section/key, not secret values;
- DSN/passport values are never logged;
- failure happens before socket bind when host config cannot resolve;
- stdout remains machine-readable enough for tests that parse `listening http://...`;
- stderr carries diagnostics.

If the right answer is a readiness packet instead of code, write it and explain the split. Do not
start a broad logging framework.

## Suggested taxonomy

Use or revise after verify-first:

```text
CONFIG_PARSE
CONFIG_RESOLVE
APP_BUILD
BIND_REFUSED
POSTGRES_CONNECT
READ_DENIED
WRITE_DENIED
EFFECT_UNBOUND
PASSPORT_DENIED
RUNNER_INTERNAL
```

This is not canon; it is operator DX evidence.

## Acceptance

- [x] Closing report lists current failure modes and which were improved.
- [x] Missing DSN env fails before socket bind with section/key named.
- [x] Malformed host config fails before socket bind with line/section context when available.
- [x] Bad public bind still fails closed.
- [x] Denied read/write/effect remains host-owned and does not expose DSN/passport/raw SQL.
- [x] Subprocess tests or CLI tests cover at least 3 high-value operator failures.
- [x] Existing happy-path P12 test remains green or skips cleanly without DSN.
- [x] Default build remains Postgres-free.
- [x] `git diff --check` clean.

## Closed surfaces

- No tracing/logging framework.
- No stable public CLI contract.
- No change to `.ig`/`.igweb` semantics.
- No production deployment docs.
- No new authority in app files.

## Closing report

**Date:** 2026-06-22
**Proof:** `lab-docs/lang/lab-igniter-web-runner-failure-taxonomy-p29-v0.md`

Implemented (small surface — not readiness). All 9 acceptance checks pass.

### Failure modes found, and what improved

| Boundary | Before | After |
|---|---|---|
| CLI / non-loopback bind | Debug, exit 1 | `[CONFIG_PARSE]` exit 2, before socket |
| host.toml parse | Debug, exit 1 | `[CONFIG_PARSE]` exit 2, before bind, names section/key |
| env-var resolve | Debug, exit 1 | `[CONFIG_RESOLVE]` exit 3, before bind, names the var |
| app build | Debug, exit 1 | `[APP_BUILD]` exit 4 |
| loopback bind | io::Error, exit 1 | `[BIND_REFUSED]` exit 5 |
| **Postgres connect** | **`{e}` could embed DSN** | `[POSTGRES_CONNECT]` exit 6, **DSN scrubbed** |
| runtime / serve loop | io::Error, exit 1 | `[RUNNER_INTERNAL]` exit 11 |

The genuinely important fix: the binary previously returned `format!("postgres.read: {e}")` /
`postgres.write: {e}` as a process error, and a `tokio-postgres` connect failure embeds the
connection string. Now routed through `RunnerDiagnostic::postgres_connect(msg, &known_dsns)` —
exact known-DSN scrub + `postgres://`/`password=` pattern fallback.

### New code

- `runner_diag.rs` (default-built): `DiagCode` (10 stable codes, distinct non-`1` exit codes),
  `RunnerDiagnostic` (`Display` = `igweb-serve: [CODE] msg`), `classify_host_config_error` /
  `classify_runner_error`, `redact_secrets`; 12 unit tests.
- `bin/igweb-serve.rs`: `fail(diag) -> !` (coded diag to stderr, exit `diag.exit_code()`; stdout
  reserved for `listening http://`); `run_machine_mode` returns `Result<(), RunnerDiagnostic>`;
  bind/connect/runtime/serve errors mapped to codes.
- `tests/igweb_serve_diagnostics_tests.rs` (`--features machine`): 5 subprocess tests of the real
  binary — missing DSN env, inline secret (no value leak), unknown section, non-loopback addr,
  happy-path serve+exit-0.

### Verify-first notes

Read modes are gated by `PostgresReadPolicy` (source/field allowlist + row clamp); writes by
`PostgresWritePolicy` (target/op allowlist). `InvokeEffect.target` maps via
`effect_host.bind_target(target, route)` then `IngressRouter.route(route, pool)`. Config errors
already named env-var NAMES not values (structurally redaction-safe); the only value-bearing path was
the Postgres connect error, now scrubbed.

`cargo test` (default) and `cargo test --features machine`: all suites green.
`cargo build --features postgres --bin igweb-serve`: clean. Default build Postgres-free.
`git diff --check`: clean.
