# lab-igniter-web-runner-cli-p13-v0 — igweb-serve CLI polish

**Card:** `LAB-IGNITER-WEB-RUNNER-CLI-P13`
**Status:** CLOSED (lab implementation)
**Date:** 2026-06-19

## Summary

`igweb-serve` is still the same generic lab runner from P12: it reads `igweb.toml`, builds an
IgWeb app, wraps it in `ReloadableApp`, and serves a bounded loopback `serve_loop`.

P13 only polishes the command-line seam:

```text
igweb-serve [--addr 127.0.0.1:PORT] [--max-requests N] <app_dir>
```

This makes the runner usable for hand smoke tests and scripts without changing the app/runtime
authority model.

## What Changed

- Added `runner::RunnerCliOptions`, `RunnerCliCommand`, `parse_cli_args`, and `usage`.
- `--help` prints usage and exits before build.
- `--addr` allows explicit loopback socket addresses; non-loopback addresses are structurally refused.
- `--max-requests` overrides manifest `[server] max_requests` for the current process.
- `src/bin/igweb-serve.rs` now delegates argument policy to `igniter_web::runner`.

## What Did Not Change

- No public bind. `--addr 0.0.0.0:...` is refused.
- No route table in the server.
- No effect identity in `.igweb` or `igweb.toml`.
- No `[effects]`, inline secrets, source-map, watcher, package manager, or stable public CLI promise.
- `igniter-server` remains independent of `igniter-web` in its normal dependency tree.

## Proof

### Unit / Integration

```text
cd server/igniter-web
cargo test --test runner_tests
  12 passed; 0 failed

cargo test
  24 passed; 0 failed
```

New assertions:

- `--help` works without app dir.
- default address is `127.0.0.1:0`.
- explicit loopback addr + max override parse.
- public addr, zero max, unknown option, and extra app dir are rejected.
- existing manifest, middleware, Todo route, and bounded loop tests still pass.

### Live Smoke

```text
cd server/igniter-web
cargo run --quiet --bin igweb-serve -- --addr 127.0.0.1:18902 --max-requests 1 examples/todo_app
```

Then:

```text
curl -i http://127.0.0.1:18902/health
HTTP/1.1 200 OK
{"body":"ok"}
```

The runner log shows:

```text
igweb-serve: app_dir=examples/todo_app entry=Serve sources=2 listening http://127.0.0.1:18902 (loopback, bounded to 1 request(s))
igweb-serve: served 1 request(s); exiting
```

### Regression

```text
cd server/igniter-server
cargo test --features machine
  71 passed; 0 failed
```

Known compiler/VM warnings remain pre-existing and unrelated.

## Interpretation

P12 proved "Igniter-only author, no Rust runner." P13 makes that proof less awkward to operate:
fixed loopback ports, one-shot smoke runs, and clear help are now first-class. This is still a lab
runner, not a public deployment interface.

## Next

Good next slices:

1. `LAB-IGNITER-WEB-RUNNER-CHECK-P14` — CLOSED; `igweb-serve check <app_dir>` dry-builds the app
   without opening a socket (`lab-igniter-web-runner-check-p14-v0.md`).
2. `LAB-IGNITER-WEB-SOURCE-MAP-READINESS-P14` — only if real diagnostics pressure appears.
3. `LAB-IGNITER-WEB-PACKAGE-READINESS-*` — package manager/workspace decisions, not runner polish.
