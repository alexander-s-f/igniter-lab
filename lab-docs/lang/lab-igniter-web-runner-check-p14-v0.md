# lab-igniter-web-runner-check-p14-v0 — igweb-serve dry build check

**Card:** `LAB-IGNITER-WEB-RUNNER-CHECK-P14`
**Status:** CLOSED (lab implementation)
**Date:** 2026-06-19

## Summary

P14 adds a dry-build command to the generic IgWeb runner:

```text
igweb-serve check <app_dir>
```

It loads `igweb.toml`, resolves sources, lowers `.igweb`, loads the generated app into
`IgniterMachine`, reports success or a structured build error, and exits without opening a socket.

This is author DX polish: check the app before serving it.

## What Changed

- `RunnerCliCommand::Check(RunnerCheckOptions)` added to `igniter_web::runner`.
- `check_app_dir(app_dir) -> Result<RunnerCheckReport, RunnerError>` added.
- `igweb-serve` now handles `check <app_dir>` before bind/listen.
- CLI usage now documents both forms:

```text
igweb-serve [--addr 127.0.0.1:PORT] [--max-requests N] <app_dir>
igweb-serve check <app_dir>
```

## What Did Not Change

- No server socket in `check`.
- No public bind.
- No source-map promise.
- No watcher.
- No package manager.
- No effect execution, credentials, or `[effects]` binding.
- No stable public CLI/canon claim.

## Proof

### Tests

```text
cd server/igniter-web
cargo test --test runner_tests
  16 passed; 0 failed
```

New assertions:

- `check <app_dir>` parses as a dry-build command.
- missing/extra check args are `RunnerError::Cli`.
- `check_app_dir(examples/todo_app)` returns `entry=Serve`, `source_count=2`.
- bad app build returns `RunnerError::Build`, not panic.
- help includes `check <app_dir>`.

### Live CLI

```text
cd server/igniter-web
cargo run --quiet --bin igweb-serve -- check examples/todo_app
```

Output:

```text
igweb-serve: check ok app_dir=examples/todo_app entry=Serve sources=2 (no socket opened)
```

And:

```text
cargo run --quiet --bin igweb-serve -- --help
```

includes:

```text
usage: igweb-serve check <app_dir>
```

## Interpretation

P12 made the runner generic. P13 made serving easier to operate. P14 adds the missing preflight:
authors can verify manifest/source/build shape before starting a loopback server. It deliberately
stops before diagnostics/source-map work; today it proves the command shape and the no-socket boundary.

## Next

Good next slices:

1. `LAB-IGNITER-WEB-RUNNER-ERRORS-P15` — polish human-readable error output, still no source-map.
2. `LAB-IGNITER-WEB-SOURCE-MAP-READINESS-P15` — design only, when real diagnostic pressure appears.
3. `LAB-IGNITER-WEB-WATCH-READINESS-P*` — later; file watching is explicitly not part of P14.
