# lab-distribution-rails-serve-dx-p2-v0 — smallest Rails-like `serve` DX proof

**Card:** `LAB-DISTRIBUTION-RAILS-SERVE-DX-P2` · **Type:** implementation + proof
**Status:** CLOSED — a repo-local `bin/igniter serve <app_dir>` wrapper gives the Rails-`s` contour
(loopback-default, request-bounded, public-bind-refused, dry `--check`) over the existing `igweb-serve`
binary, **with no root workspace and no new authority**, proven by a live serve→HTTP→`200` smoke without a DB.

## Gate check (P1 landed) — this card was unblocked

The card says *"implement … after P1 decides the exact shape"* and *"if P1 has not landed, do not implement"*.
**P1 = `LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1` is CLOSED** (`lab-docs/lang/lab-distribution-ecosystem-readiness-p1-v0.md`),
and its §5 + next-card #1 decide the shape explicitly:

> a thin `igniter serve <app_dir>` over `igweb-serve`, **loopback-default**, machine-readable `listening`
> line, **request-bounded**, **no root workspace** (achieved via **wrapper C**, not a workspace migration).

This card implements exactly that smallest slice. (Aligns with `LAB-DISTRIBUTION-ROOT-WORKSPACE-READINESS-P5`,
which independently recommended **deferring** the root workspace and using a wrapper.)

## Verify-first findings (current `igweb-serve` already owns the semantics)

Read `server/igniter-web/src/bin/igweb-serve.rs` + `src/lib.rs` (CLI) + `tests/` + the home-lab
`deploy/pi5-lab/run-todo-loopback.sh`. The runner **already** satisfies almost every "required behavior":

| Behavior | Where it lives (verified) |
|---|---|
| Loopback default | `DEFAULT_ADDR = "127.0.0.1:0"` (`lib.rs:533`) |
| Public-bind **refused** | `parse_loopback_addr` → `--addr must be loopback-only` (`lib.rs:651-660`) |
| Dry build, no socket | `check <app_dir>` → `check ok … (no socket opened)` (`igweb-serve.rs:37-46`) |
| Status line | `app_dir=… entry=… sources=N listening http://127.0.0.1:PORT (loopback, bounded to N request(s))` |
| Request bound | `ServingPolicy::new(max).loopback_only()`; `max` from `--max-requests`/manifest/1024 |
| Explicit host authority | `--host-config host.toml` (env-expanded, secrets rejected; needs `--features machine`) |
| No live DB needed | sync `TcpListener`+`serve_loop` path (no `--host-config`) — `examples/todo_app` |

**Conclusion:** the missing piece is **not** runner behavior — it is the *ergonomic front door*. So the
smallest honest proof is **wrapper C** (hide the binary name / build path / target-dir plumbing), adding **no**
authority. Args-in-any-order and the `check` subcommand are already supported (`parse_run_args`/`parse_check_args`).

## What was added (3 new files, no code change to existing crates)

1. **`bin/igniter`** — a ~70-line bash dispatcher. v0 implements one verb, `serve`, forwarding to
   `igweb-serve`:
   - `igniter serve <app_dir> [--addr …] [--max-requests N] [--host-config PATH]` → `igweb-serve …` (pass-through)
   - `igniter serve --check <app_dir>` → `igweb-serve check <app_dir>`
   - `igniter serve --help` / `igniter --help` → wrapper usage; unknown verb → exit 2 + usage.
   - Resolves the binary via `IGNITER_IGWEB_SERVE_BIN` (prebuilt / release-bundle path) → existing
     `target/{release,debug}` → else `cargo build --release --bin igweb-serve` (the only "hidden plumbing").
   - **Adds no authority:** loopback-only, the public-bind refusal, and the request bound all stay in
     `igweb-serve`. No systemd/Docker/Homebrew, no public listener, no DSN/secrets, no daemon.
2. **`server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`** — 4 tests driving the wrapper end to
   end (binary chosen via `IGNITER_IGWEB_SERVE_BIN = CARGO_BIN_EXE_igweb-serve`, so no nested cargo).
3. **this doc.**

## Proof (real, executed)

`igweb-serve` release built (`cargo build --release --bin igweb-serve`). Through the wrapper:

```text
$ bin/igniter serve --check server/igniter-web/examples/todo_app
igweb-serve: check ok app_dir=…/examples/todo_app entry=Serve sources=2 (no socket opened)   # exit 0

$ bin/igniter serve server/igniter-web/examples/todo_app --addr 0.0.0.0:8080
igweb-serve: [CONFIG_PARSE] … --addr must be loopback-only, got `0.0.0.0:8080`                # exit 2
```

Automated smoke (`cargo test --test igniter_serve_wrapper_smoke_tests` → **4 passed**):

| test | proves |
|---|---|
| `igniter_serve_app_returns_health_200_no_db` | `igniter serve <app> --addr 127.0.0.1:0 --max-requests 1` binds loopback, serves one real HTTP/1.1 request, `GET /health` → **`HTTP/1.1 200`**, exits clean — **no DB, no machine feature** |
| `igniter_serve_check_opens_no_socket` | `igniter serve --check <app>` → `check ok … (no socket opened)` |
| `igniter_serve_refuses_public_bind` | `igniter serve <app> --addr 0.0.0.0:8080` fails, stderr `loopback-only` (gate preserved through the wrapper) |
| `igniter_serve_help_names_contract` | help names `<app_dir>`, `127.0.0.1:0`, `--host-config`, `loopback-only`, `--check` |

Regression: existing runner suites green — `runner_tests` (17), `example_app_tests` (7),
`igweb_serve_diagnostics_tests` (machine-gated, 0 on default build). No existing source changed.

```text
$ cd server/igniter-web && cargo test --test igniter_serve_wrapper_smoke_tests --test runner_tests \
      --test example_app_tests --test igweb_serve_diagnostics_tests
  → 4 + 17 + 4 + 0 passed, 0 failed
$ git diff --check  → clean
```

## Acceptance — mapping

- [x] One documented command starts a local IgWeb app and returns a successful health request →
      `igniter serve <app>` + GET /health = 200 (smoke test 1).
- [x] A dry-check command builds/verifies without binding → `igniter serve --check <app>` (smoke test 2).
- [x] Help names app dir, bind defaults, `--host-config`, safety constraints (smoke test 4).
- [x] Smoke proves serve→HTTP→response without live DB (`examples/todo_app`, sync path, no machine feature).
- [x] Existing `igweb-serve` tests remain green (runner/example/diagnostics).
- [x] No root workspace migration (wrapper C per P1; aligns with P5 defer).
- [x] `git diff --check` clean.

## Closed surfaces (honored)

No Homebrew/Docker/systemd. No public listener (non-loopback `--addr` refused end-to-end). No implicit DSN /
inline secrets. No production daemon (bounded run). No server route table. No app conventions beyond the
current IgWeb app/manifest model.

## Bundle-readiness note (for later, not implemented here)

The wrapper has **no shell-specific hidden semantics**: it forwards argv and reads one `IGNITER_IGWEB_SERVE_BIN`
env var. A future release bundle / systemd unit (home-lab Model B precedent: `run-todo-loopback.sh` +
`igweb-todo-loopback.service`) can set that env to the bundled binary and call `igniter serve <app> --addr
127.0.0.1:PORT --max-requests N` unchanged. Generalizing `igniter` to more verbs (`build`, `check`, `compile`)
and fixing the `igc`/`igniter_compiler` binary-name mismatch are P3/installer follow-ons.

---

*Lab proof. 2026-06-24. `bin/igniter serve <app>` — a thin Rails-`s` wrapper over `igweb-serve`: loopback
default, request-bounded, public-bind refused, `--check` dry build. Live serve→`GET /health`→`200` proven with
no DB and no machine feature; existing runner tests stay green; no root workspace, no new authority.*
