# lab-igniter-web-runner-p12-v0 — generic igweb-serve runner

**Card:** `LAB-IGNITER-WEB-RUNNER-P12` · **Delegation:** `OPUS-IGNITER-WEB-RUNNER-L`
**Status:** CLOSED (lab implementation) — a generic `igweb-serve <app_dir>` binary lets an Igniter-only
author run the P10 Todo app from **`routes.igweb` + `todo_handlers.ig` + `igweb.toml`** with **zero
authored Rust**. **No new dependency, loopback only, no public CLI promise, no source-map, no `.igwebpkg`,
no file watcher, no live effect execution, no canon claim.**
**Authority:** Lab. Implements the P11 v0 runner model (B `igweb.toml` + D directory convention).

## Final runner command + layout

```text
igniter-web/
  src/bin/igweb-serve.rs            # the generic lab runner binary
  src/lib.rs::runner               # IgwebManifest + parse_manifest + resolve_sources + build_app_from_dir
  examples/todo_app/
    routes.igweb                    # author
    todo_handlers.ig                # author (imports IgWebPrelude, injected by the builder)
    igweb.toml                      # author — the config.ru analogue
  tests/runner_tests.rs             # 8 tests

$ cd igniter-web && cargo run --bin igweb-serve -- examples/todo_app
igweb-serve: app_dir=examples/todo_app entry=Serve sources=2 listening http://127.0.0.1:PORT (loopback, bounded to 7 request(s))
```

## Manifest v0 (`igweb.toml`)

```toml
[app]
entry = "Serve"          # required
# sources = [...]        # optional; default = all *.ig + *.igweb in the dir, sorted (convention D)

[server]
mode = "loopback"        # only "loopback" accepted in v0
max_requests = 7

[middleware]
trace = true
body_limit_bytes = 65536
# auth_token_env = "VAR" # optional; token read from the env var — inline secrets are rejected
```
- Hand-rolled parser (no toml crate; mirrors `igniter-compiler/src/project.rs::parse_source_roots_toml`).
- **Rejected by the parser** (structured `RunnerError::Manifest`, not panic): missing `[app] entry`,
  an `[effects]` section, inline `auth_token`, a non-`loopback` `[server] mode`, any unknown key.
- The manifest can name **no** routes, bind address, secret, capability id/operation/scope, or passport.

## Runner behavior

`build_app_from_dir(app_dir)` (in `igniter_web::runner`): load `igweb.toml` → resolve sources (manifest
list, else dir `*.ig`/`*.igweb` sorted) → `igniter_web::build_igweb_app` → compose the P8 wrapper stack
from `[middleware]` (`BodyLimit → Auth → Trace → app`, only the configured layers; auth token from the
env var) → return the erased `Arc<dyn ServerApp + Send + Sync>`. The bin then holds it in
`ReloadableApp` and runs a bounded loopback `serve_loop(max_requests)`. The server owns transport, loop,
and reload; the app owns routing/domain; `build_igweb_app` stays the library primitive.

## Live trace (`igweb-serve examples/todo_app`, 7 loopback requests, exits)

```text
GET  /health          -> 200
GET  /todos/42        -> 200 {"body":"42"}                 (path param via generated regexp/capture)
POST /todos/42/done   -> 400                               (keyless)
POST /todos/42/done   -> 202 {"decision":"invoke_effect","target":"todo-done","idempotency_key":"evt-9",
                              "correlation_id":"corr-…"}    (keyed; correlation id added by the manifest's trace middleware)
GET  /missing         -> 404
POST /health          -> 405
served 7 request(s); exiting
```
The `correlation_id` is populated because `[middleware] trace = true` composed `TraceApp` from the
manifest — live proof that manifest middleware applies. No `capability_id`/`operation`/`scope` appears.

## Acceptance — met

1. ✓ P10 Todo runs from `routes.igweb + todo_handlers.ig + igweb.toml`, **no authored Rust** (live bin
   + `runner_serves_p10_todo_behavior`).
2. ✓ Runner uses `build_igweb_app` as the library primitive.
3. ✓ Manifest parser is tiny, deterministic, dependency-free (`parses_full_manifest`,
   `rejects_missing_entry_effects_inline_secret_and_bad_mode`).
4. ✓ Sources resolved relative to the app directory; default discovery deterministic + excludes
   `.toml` (`default_source_discovery_is_deterministic_and_excludes_toml`).
5. ✓ Middleware composes through existing P8 wrappers (`manifest_body_limit_rejects_oversized` → 413;
   `manifest_auth_env_short_circuits_then_passes` → 401/200; trace seen live).
6. ✓ Built stack held in `ReloadableApp`; bounded `serve_loop` (`runner_full_path_over_serve_loop`).
7. ✓ Loopback behavior matches P10 (health/param/keyless/keyed/404/405).
8. ✓ Manifest cannot name routes/public-bind/secrets/effect identity (parser rejects; effect identity
   structurally impossible in the decision).
9. ✓ `igniter-server` stays generic + serde-only by default (`cargo tree -e normal` = none).
10. ✓ Docs classify this as **lab v0**, not a stable CLI/canon.

## Test commands + pass counts

```text
$ cd igniter-web && cargo test                              → 20 passed; 0 failed (5 builder + 7 example + 8 runner)
$ cd igniter-web && cargo run --bin igweb-serve -- examples/todo_app  → serves 7 loopback requests, exit 0
$ cd igniter-server && cargo test                          → 49 passed; 0 failed
$ cd igniter-server && cargo test --features machine       → 0 failed
$ cd igniter-server && cargo tree -e normal | grep web|machine|compiler|regex|tokio → (none) serde-only
$ cd igniter-compiler && cargo test --test igweb_lowering_tests → 2 passed (P4 intact)
```
`runner_tests` (8): full manifest parse · 5 rejection cases · missing-manifest Io error · deterministic
source discovery · P10 behavior over loopback · body-limit 413 · auth env 401/200 · full
`serve_loop` path. `igniter-web` warning-clean (own code).

## What improved over `todo_server.rs`

`todo_server.rs` (P9) was hand-written Rust per app (paths + entry + a client loop). The P12 runner is
**generic**: it works for any app directory via a declarative `igweb.toml`, so an Igniter-only author
writes no Rust at all. Middleware is configured declaratively (`[middleware]`) instead of hand-composed
in Rust. The server boundary is unchanged — the runner is a thin manifest→`build_igweb_app`→middleware→
`ReloadableApp`→`serve_loop` layer.

## Dependency boundary

`igniter-server` normal tree stays **serde-only** (verified). The runner + manifest parser live in
`igniter-web` (which already carries compiler/machine). No new external dependency was added (toml is
hand-parsed). The `igweb-serve` bin is a target of the `igniter-web` package.

## Deferred (held)

Public CLI stability; `.igweb→.ig` source maps; assets/raw responses; live effect execution (observed
`202`); `[effects]` target binding (rejected in v0); package artifact (`.igwebpkg`); file-watch /
auto-reload; multi-app hosting; public bind. None block the runner.

---

*Lab implementation. Compiled 2026-06-18; igniter-web 20 tests green; `igweb-serve examples/todo_app`
serves the P10 Todo app from a manifest with zero authored Rust; `igniter-server` serde-only.*
