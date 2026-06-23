# LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-P31 - crystallize ReadThen and EffectHost surface

Status: CLOSED
Lane: IgWeb / implemented surface / runner hygiene
Type: documentation + evidence index
Delegation code: OPUS-WEB-IMPLEMENTED-SURFACE-P31
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The runner line moved fast:

- `ReadThen` exists in the IgWeb prelude and is intercepted by host-side dispatch.
- `MachineEffectHost` executes final `InvokeEffect` decisions in async machine mode.
- `igweb-serve --host-config` now wires real Postgres reads/writes under `postgres`.
- P28/P13/P29/P30 added operator example, smoke, diagnostics, and docs hygiene.

Agents still find old readiness/proof docs that say "ReadThen not implemented", "observed only",
"manual only", or "no live effect execution". Those files are often historically correct, but stale
as current status. We need a package-local front door.

## Goal

Create or update `server/igniter-web/IMPLEMENTED_SURFACE.md` as the code-anchored answer to:

```text
What does igniter-web actually implement today for ReadThen, EffectHost, host.toml, and igweb-serve?
```

This is not canon and not a public stability promise. It is a lab implemented-surface map for agents.

## Verify first

Read live code and tests before writing:

- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
- `server/igniter-web/tests/readthen_socket_runner_tests.rs`
- `server/igniter-web/tests/async_machine_runner_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/tests/igweb_serve_diagnostics_tests.rs`
- `server/igniter-web/README.md`
- `lab-docs/STATUS.md`

Do not trust old readiness docs without checking source.

## Required sections

Keep the document compact and scannable:

1. **Status header**: lab-only, not public/canon.
2. **Implemented today** table:
   - sync observed mode;
   - async machine mode;
   - `ReadThen`;
   - `StagedReadHost`;
   - `MachineEffectHost` / final `InvokeEffect`;
   - `host.toml` read/write/effects;
   - real Postgres under `postgres`;
   - `host.example.toml`;
   - `todo_postgres_smoke.sh`;
   - runner diagnostics.
3. **Not implemented / intentionally closed**:
   - public listener mode;
   - stable CLI promise;
   - pool/backpressure;
   - migration runner;
   - generic multi-source read config if still absent;
   - typed row destructuring if still absent;
   - production deployment story.
4. **Evidence commands**: exact commands that currently prove the surface.
5. **Historical docs rule**: old proof/readiness docs are evidence, not current backlog; this file + live source wins.

## Acceptance

- [x] `server/igniter-web/IMPLEMENTED_SURFACE.md` exists.
- [x] It explicitly states `ReadThen` implemented vs still-limited parts.
- [x] It explicitly states final `InvokeEffect` through `MachineEffectHost` implemented vs default observed mode.
- [x] It explicitly states real Postgres read/write wired only under `postgres` + `--host-config`.
- [x] It includes exact evidence commands and test names.
- [x] It keeps lab/prototype boundary clear.
- [x] It does not rewrite history in old proof docs.
- [x] README or `lab-docs/STATUS.md` points agents to this implemented surface.
- [x] `git diff --check` clean.

## Closed surfaces

- No code changes unless needed for a broken doc/test import.
- No behavior changes.
- No canon/public stability claim.
- No broad stale-doc sweep beyond a pointer to this file.

## Closing report

**Date:** 2026-06-23

### Files changed

- **NEW** `server/igniter-web/IMPLEMENTED_SURFACE.md` — the code-anchored front door. Sections:
  status header (lab/prototype, loopback-only, not canon); "Implemented today" table; "Not implemented
  / intentionally closed" table; "Evidence commands"; "Historical docs rule". Every row cites the
  live source location (`src/...:fn`) and the limited parts are called out inline.
- **M** `server/igniter-web/README.md` — one blockquote pointer near the top to IMPLEMENTED_SURFACE.md.

No code changed (doc-only card). `lab-docs/STATUS.md` already pointed agents at the package-local
`IMPLEMENTED_SURFACE.md` in its Operating Rule, so no STATUS edit was needed.

### Source-anchored facts captured (verified against live code this session)

- **ReadThen** — implemented in `src/lib.rs::IgWebLoadedApp::dispatch_with_read` (intercepts
  `ReadThen{plan,then}` before `map_decision`; Rows→continuation with `{req, rows_json}`, Denied→403,
  HostError→503). **Still limited:** continuation gets rows as a JSON **string** — no typed row
  destructuring.
- **Final `InvokeEffect`** — routes through `MachineEffectHost` only in **async machine mode**
  (`--host-config` + `machine`); executes for real only when a write host is wired; **default sync
  mode keeps `InvokeEffect` observed**.
- **Real Postgres** — `src/host_binding.rs` builders, wired only under `--features postgres` +
  `--host-config` with the matching sections (read needs `[postgres.read]`; write needs
  `[postgres.write]` + `[effects.*]` + `passport_env`).
- **host.toml** — exact `host_config.rs` keys + fail-closed rules; `*_env` resolved before bind.
- **Runner diagnostics (P29/P30)** — `src/runner_diag.rs` stable `DiagCode`s + distinct non-zero exit
  codes + DSN/passport redaction; process-exit only (per-request denials are HTTP responses).

### Evidence commands proven honest

Ran each cited command; all the named tests exist and pass:
- `cargo test --lib host_config` → `committed_host_example_toml_parses` + parser cases green (46 pass).
- `cargo test --features machine` → cited readthen / async / diagnostics test names all green; no failures.
- `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → 8 pass /
  skips cleanly without DSN (cited subprocess test included).

### Acceptance

- IMPLEMENTED_SURFACE.md exists; states ReadThen implemented vs still-limited; states final
  `InvokeEffect` via `MachineEffectHost` vs default observed mode; states real Postgres only under
  `postgres` + `--host-config`; includes exact evidence commands + test names; keeps the lab boundary
  clear; does not rewrite history (old proof docs untouched; explicit Historical docs rule).
- README points to it; STATUS.md Operating Rule already did.
- `git diff --check` clean. No code changed.

### Scope honored

No code/behavior changes, no canon/public claim, no broad stale-doc sweep beyond the front-door pointer.
