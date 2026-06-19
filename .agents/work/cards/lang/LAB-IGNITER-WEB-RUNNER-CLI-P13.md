# LAB-IGNITER-WEB-RUNNER-CLI-P13 — igweb-serve CLI polish

Status: CLOSED
Date: 2026-06-19
Lane: standard

## Intent

Polish the generic IgWeb runner after P12 without widening authority. The runner should be easier to
use in hand smoke tests: explicit loopback bind, one-shot max request override, and help output.

## Scope

- Add CLI parsing in `igniter_web::runner`.
- Wire `src/bin/igweb-serve.rs` through that parser.
- Keep loopback-only guard structural.
- Keep `igweb.toml` unchanged.
- Keep server/core routing/effect boundaries unchanged.

## Closed Surfaces

- No public bind.
- No stable public CLI/canon claim.
- No watcher/hot reload automation.
- No source-map.
- No package manager.
- No live effects, credentials, or `[effects]`.
- No route table in `igniter-server`.

## Acceptance

- [x] `--help` prints usage without app dir/build.
- [x] default bind remains `127.0.0.1:0`.
- [x] `--addr 127.0.0.1:PORT` works.
- [x] non-loopback `--addr` is refused.
- [x] `--max-requests N` overrides manifest for the process.
- [x] malformed CLI args return `RunnerError::Cli`.
- [x] existing P12 runner behavior still passes.
- [x] live loopback smoke proves fixed port + one-shot exit.
- [x] `igniter-server --features machine` regression stays green.

## Closing Report

Implemented `RunnerCliOptions`, `RunnerCliCommand`, `parse_cli_args`, and `usage` in
`server/igniter-web/src/lib.rs::runner`. The `igweb-serve` binary now accepts:

```text
igweb-serve [--addr 127.0.0.1:PORT] [--max-requests N] <app_dir>
```

Verification:

- `server/igniter-web cargo test --test runner_tests` -> 12 passed.
- `server/igniter-web cargo test` -> 24 passed.
- live smoke: `--addr 127.0.0.1:18902 --max-requests 1 examples/todo_app` served `/health` with 200 and exited after one request.
- `server/igniter-server cargo test --features machine` -> 71 passed.

Proof doc: `lab-docs/lang/lab-igniter-web-runner-cli-p13-v0.md`.
