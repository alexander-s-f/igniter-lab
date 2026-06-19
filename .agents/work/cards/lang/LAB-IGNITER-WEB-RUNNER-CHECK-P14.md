# LAB-IGNITER-WEB-RUNNER-CHECK-P14 — dry-build check command

Status: CLOSED
Date: 2026-06-19
Lane: standard
Skill: idd-agent-protocol

## Intent

Add a preflight command for IgWeb authors:

```text
igweb-serve check <app_dir>
```

The command should prove that an app directory loads, lowers, and builds without starting a server
socket. This is runner DX only.

## Scope

- Extend runner CLI parsing with a `check` command.
- Add a dry-build primitive in `igniter_web::runner`.
- Wire `src/bin/igweb-serve.rs`.
- Add tests and proof doc.

## Closed Surfaces

- No public bind.
- No watcher.
- No source-map.
- No stable CLI/canon claim.
- No live effect execution.
- No `[effects]` binding or credentials.
- No server route table.

## Acceptance

- [x] `igweb-serve check <app_dir>` parses separately from serve mode.
- [x] `check` requires exactly one app dir.
- [x] `check_app_dir` loads manifest, resolves sources, and builds app.
- [x] `check` does not bind/listen/open a socket.
- [x] bad build returns structured `RunnerError::Build`.
- [x] `--help` includes `check <app_dir>`.
- [x] existing serve behavior remains green.
- [x] proof doc records commands/counts.

## Closing Report

Implemented:

- `RunnerCheckOptions`
- `RunnerCliCommand::Check`
- `check_app_dir(...) -> RunnerCheckReport`
- `igweb-serve check <app_dir>`

Verification:

- `server/igniter-web cargo test --test runner_tests` -> 16 passed.
- live `cargo run --quiet --bin igweb-serve -- check examples/todo_app` -> `check ok ... (no socket opened)`.
- help includes `usage: igweb-serve check <app_dir>`.

Proof doc: `lab-docs/lang/lab-igniter-web-runner-check-p14-v0.md`.
