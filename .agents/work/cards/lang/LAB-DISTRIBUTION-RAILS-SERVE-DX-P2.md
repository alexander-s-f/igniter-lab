# LAB-DISTRIBUTION-RAILS-SERVE-DX-P2 - smallest Rails-like `serve` DX proof

Status: CLOSED (2026-06-24) — bin/igniter serve wrapper + live smoke; packet at lab-docs/lang/lab-distribution-rails-serve-dx-p2-v0.md
Lane: distribution / server DX
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

The motivating DX target is "start an Igniter web app like `rails s`". Today `igweb-serve` exists inside
`server/igniter-web`, but the repo has package-local Cargo projects and the app runner is still more
lab-shaped than product-shaped. This card implements the smallest proof after P1 decides the exact shape.

Home-lab already has a useful loopback service shape:

- `deploy/pi5-lab/run-todo-loopback.sh` runs release-built `igweb-serve` against a Todo app with
  `--addr 127.0.0.1:${IGNITER_TODO_PORT}` and bounded `--max-requests`.
- `deploy/pi5-lab/igweb-todo-loopback.service` wraps it as a user-level loopback service.

Use this as precedent for command ergonomics and safety, not as a requirement to introduce systemd here.

If P1 has not landed, do not implement this card yet.

## Goal

Make one command start a local IgWeb app from an app directory with clear errors, loopback-safe defaults,
and no hidden authority.

Candidate shapes to evaluate from P1:

- keep `igweb-serve <app-dir>` but polish help/errors;
- add an `igniter` wrapper binary/subcommand: `igniter serve <app-dir>`;
- add a repo-local script as a temporary DX proof.

The preferred v0 is the smallest one that proves the Rails-like contour without forcing a root workspace.

## Verify First

- Read `server/igniter-web/src/bin/igweb-serve.rs`.
- Read runner tests in `server/igniter-web/tests/`.
- Verify current help output and default bind behavior.
- Verify host-config handling, DSN/env safety, and loopback-only/public-bind refusals.
- Use `examples/todo_postgres_app` or a smaller fixture app as the smoke target.
- Inspect the home-lab run script/unit above and extract what should become first-class CLI ergonomics
  (status line, default loopback bind, bounded smoke, log clarity).

## Required Behavior

The chosen command must:

- default to loopback;
- serve a known app with one short command;
- print useful listener/app/config status;
- support `--check` or equivalent dry build;
- keep host authority explicit (`--host-config` / env secrets);
- fail closed on public bind unless an existing explicit safety gate already exists;
- not require a live DB for the minimal smoke.
- be easy to wrap later in a release bundle/systemd unit without shell-specific hidden semantics.

## Acceptance

- [x] One documented command starts a local IgWeb app and returns a successful health request.
- [x] A dry-check command builds/verifies the app without binding a listener.
- [x] Help text names app dir, bind defaults, `--host-config`, and safety constraints.
- [x] Smoke test proves "serve app -> HTTP request -> response" without live DB.
- [x] Existing `igweb-serve` tests remain green.
- [x] No root workspace migration unless P1 explicitly recommended it.
- [x] `git diff --check` clean.

## Closed Surfaces

No Homebrew/Docker/systemd. No public listener. No implicit DSN or inline secrets. No production daemon.
No server route table. No app framework conventions beyond the current IgWeb app/manifest model.

## Closing Report

Proof doc: `lab-docs/lang/lab-distribution-rails-serve-dx-p2-v0.md`.

**Gate satisfied:** P1 (`LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1`) is CLOSED; its §5 decided the shape =
thin `igniter serve <app_dir>` over `igweb-serve`, loopback-default, bounded, **wrapper C, no root
workspace** (aligns with P5's defer-workspace recommendation).

**Verify-first result:** `igweb-serve` already owns every safety semantic — loopback default
(`DEFAULT_ADDR 127.0.0.1:0`), **public-bind refusal** (`parse_loopback_addr`), `check <app_dir>` dry build
(`no socket opened`), status `listening` line, request bound (`ServingPolicy::loopback_only`), explicit
`--host-config`. The only gap was the ergonomic front door → wrapper C adds **no authority**.

**Added (3 new files, no existing source changed):**
- `bin/igniter` — bash dispatcher; v0 verb `serve` → `igweb-serve` (pass-through), `serve --check` →
  `igweb-serve check`, `serve --help`/unknown-verb usage; binary via `IGNITER_IGWEB_SERVE_BIN` → target →
  `cargo build` (the only hidden plumbing).
- `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs` — 4 tests through the wrapper.
- the proof doc.

**Proof (executed):** live `igniter serve <todo_app> --addr 127.0.0.1:0 --max-requests 1` → real socket →
`GET /health` → **HTTP/1.1 200**, clean exit, **no DB, no machine feature**. `serve --check` → `no socket
opened`. `serve --addr 0.0.0.0:8080` → refused (`loopback-only`) end-to-end. Smoke 4 passed; regression
`runner_tests` 17 + `example_app_tests` 7 green. `git diff --check` clean.

**Deferred:** more verbs (`build`/`check`/`compile`), `igc`/`igniter_compiler` binary-name alignment,
release-bundle/systemd wrapping (Model B precedent) → P3/installer cards.
