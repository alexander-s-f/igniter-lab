# LAB-DISTRIBUTION-APP-BUNDLE-RUN-SMOKE-P16 - prove emitted app bundle runs

Status: CLOSED (2026-06-25) — emitted run/run-todo_app.sh serves GET /health 200 from inside the bundle; test green
Lane: distribution / app bundle
Type: implementation + proof
Date: 2026-06-25

## Context

P14 implemented `igniter app bundle` as assembly-only:

```text
<out>/<app>-<version>/
  bin/igweb-serve
  app/<app>/...
  run/run-<app>.sh
  checks/check.sh
  systemd/<app>.service.example
  manifest.json
```

P14 proves the layout, manifest, refusals, and `checks/check.sh`. It does not yet prove the emitted
`run/run-*.sh` can actually serve a request from inside the bundle. That is the next deployment-DX proof.

## Goal

Prove that a P14-produced bundle can run through its emitted runner script and answer HTTP on loopback.

This is still **not** a production deploy. It is a local/temp smoke of the emitted bundle.

## Verify First

- Read live `bin/igniter` `app_bundle`.
- Read `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`.
- Confirm `run/run-<app>.sh` reads:
  - `IGNITER_<APP>_PORT`
  - `IGNITER_<APP>_MAX_REQUESTS`
  - local `bin/igweb-serve`
- Confirm `igweb-serve` still enforces loopback / bounded request policy.

## Required Behavior

Add a focused smoke test that:

1. builds/bundles `server/igniter-web/examples/todo_app` into a temp dir;
2. runs the emitted `run/run-todo_app.sh`;
3. sets a deterministic temp loopback port and a bounded request count;
4. waits for readiness without sleeping blindly when possible;
5. sends a real HTTP request to the bundled app;
6. asserts a successful response from the bundled runner;
7. waits for the bounded process to exit, or terminates it cleanly on failure.

The test must use the bundled runner binary from `bundle/bin/igweb-serve`, not the repo target directly.

## Acceptance

- [x] New test `emitted_run_script_serves_from_bundle_on_loopback` runs the emitted `run/run-todo_app.sh`
      (which execs the BUNDLED `bin/igweb-serve` against `bundle/app/todo_app`) → `GET /health` → `HTTP/1.1 200`.
- [x] Response proves bundle-origin: the runner's `app_dir=` line is asserted to contain the versioned bundle
      dir (`todo_app-RUNV1/app/todo_app`), not the source `examples/todo_app` path.
- [x] Loopback-only enforced (addr asserted `127.0.0.1:`; igweb-serve still refuses non-loopback). PORT=0 →
      OS-chosen free port (no collisions, no public bind).
- [x] Bounded run: `IGNITER_TODO_APP_MAX_REQUESTS=1`; `child.wait()` asserts a clean self-exit; the test
      `kill()`s defensively on any failure path — no daemon/orphan.
- [x] Existing P14 bundle tests still pass (suite 6/6, incl. the 5 prior).
- [x] Wrapper / doctor / package smoke tests green: wrapper 16/16, doctor 6/6, package 9/9 (untouched by this card).
- [x] `git diff --check` clean.

## Result (2026-06-25)

Test-only card — **no production code changed**; the P14 emitted run script worked unmodified, so no
`igweb-serve` semantics bug surfaced (closed surface intact). Added one focused smoke to
`server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs` (mirrors the P2 serve-smoke readiness pattern:
spawn → parse the machine-readable `listening http://127.0.0.1:PORT` line → one real HTTP/1.1 request →
assert 200 → `wait()` the bounded process). Uses `PORT=0` for a deterministic-yet-collision-free bind and
the BUNDLED runner via the run script's own `exec "$here/bin/igweb-serve"`. This proves the
deployment-DX claim end-to-end: a P14 bundle is self-contained and serves from inside itself.

## Closed Surfaces

No systemd install. No `current` symlink. No public bind. No TLS/reverse proxy. No DB/host.toml/secrets. No
Docker. No production deploy. No change to `igweb-serve` semantics unless the smoke exposes a real bug.

