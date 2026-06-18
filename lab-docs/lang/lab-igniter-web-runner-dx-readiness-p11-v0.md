# lab-igniter-web-runner-dx-readiness-p11-v0 — config.ru-like runner model for IgWeb apps

**Card:** `LAB-IGNITER-WEB-RUNNER-DX-READINESS-P11` · **Delegation:** `OPUS-IGNITER-WEB-RUNNER-DX-K`
**Status:** READINESS / DESIGN (v0, recommended) — how an **Igniter-only author** (no Rust) runs an
IgWeb app, keeping `igniter-server` generic. **No code, no config-format implementation, no CLI promise,
no canon claim.**
**Authority:** Lab readiness. Grounded in the live P2–P10 surface (verified `todo_server.rs`,
`build_igweb_app`, `serve_loop`, `ReloadableApp`, the `project.rs` hand-rolled-toml precedent).

## Executive summary

Today the only runner is `igniter-web/examples/todo_server.rs` — a hand-written Rust file. That is a
fine **proof harness**, but the **target** author knows Igniter, not Rust. The Rack analogue: `config.ru`
declares the app; Puma owns process/socket/concurrency; the app owns routing/domain. For IgWeb the
honest minimum is a **tiny declarative `igweb.toml` manifest + a generic runner binary** (in
`igniter-web`) that reads it, calls `build_igweb_app`, composes P8 middleware, wraps in
`ReloadableApp`, and runs `serve_loop`. The author writes **`routes.igweb` + handler `.ig` +
`igweb.toml`** and runs a pre-built runner — **zero authored Rust**. The manifest is the seam: an
`[app]` section (author-owned: entry + sources) vs `[server]`/`[middleware]`/`[effects]` sections
(host/operator-owned policy). `build_igweb_app` stays the library primitive behind the runner.

## Proof runner vs target runner

- **Proof harness (today):** `todo_server.rs` — Rust: builds paths, `build_igweb_app`, binds a
  listener, drives client requests. App-specific bits = `{sources, entry}`; everything else is host
  mechanics + a demo driver. Evidence, not the target DX.
- **Target runner:** a **generic binary** the author never edits; it reads a manifest and serves. App
  authorship = files only.

## Authority boundary (confirmed against P1–P8)

| Concern | Owner | Evidence |
|---|---|---|
| process, socket bind, accept loop, concurrency, bounded budget | **server (host)** | `serving_loop::serve_loop`, `host::serve_*` |
| hot reload swap of the active app | **server (host)** | `reload::ReloadableApp` (P4) |
| middleware MECHANISM (wrap order, short-circuit) | **server (host)** | `middleware` P8 |
| effect-host binding (`target → EffectBridgeConfig`), passports, secrets, receipts | **host/operator** | `effect_host` P3 |
| routing, handler contracts, domain types, logical `target`, validation, product meaning | **app (`.igweb` + `.ig`)** | P4/P9/P10 |

The manifest co-locates app vs host *config* but must not blur *authority*: `.igweb` never names a
bind address, secret, or effect identity; the operator never edits routes.

## Research answers (compact)

1. **Current runner contract:** `todo_server.rs` does (app-specific) source paths + `entry:"Serve"` →
   `build_igweb_app`; (host) `TcpListener::bind` + `host::serve_bounded`; (demo) a client request loop.
   Only `{sources, entry}` is genuinely app-authored.
2. **Desired non-Rust author contract:** `routes.igweb` + handler `.ig` + one declarative app file
   naming `entry` + `sources`. No Rust.
3. **`config.ru` analogue:** a small **`igweb.toml`** manifest (declarative data), NOT an `.ig` contract
   (bootstrapping: the compiler needs sources before a contract could name them — reject C) and NOT a
   full `.igwebpkg` build artifact for v0 (too heavy — defer E). A directory convention (D) supplies the
   default `sources`; the manifest carries `entry` + host policy.
4. **Stays in the server:** process/socket/loop/concurrency/reload/middleware-mechanism/effect-host
   binding/observability (✓ P2–P8).
5. **Stays in the app:** routing, handler contracts, domain types, logical targets, request
   validation, product meaning (✓ P4/P9/P10).
6. **`build_igweb_app(paths, entry)` fit:** the **library primitive**. The runner is a thin layer that
   parses the manifest → calls `build_igweb_app` → composes middleware → `ReloadableApp` → `serve_loop`.
   Do NOT hide it behind a heavier loader; keep the seam.
7. **Middleware config:** host policy in a `[middleware]` manifest section (`trace`, `body_limit_bytes`
   — app-safe; `auth` token via an **env/secret reference**, never inline-committed, never from
   `.igweb`). The runner composes the P8 wrapper stack from it.
8. **Effect target binding:** app emits logical `target`; host maps `target → EffectBridgeConfig`.
   v0's runner is **machine-free** (InvokeEffect observed `202`), so no binding yet. When live, the
   mapping lives in a host-only `[effects]` section + secret provider — never `.igweb`/handlers.
9. **Hot reload unit:** the built **`Arc<dyn ServerApp + Send + Sync>`** (P4 `ReloadableApp::swap`).
   The runner rebuilds from sources and swaps the whole Arc. v0 reload is an **explicit operator
   action** (no file watcher — held closed since P4).
10. **Smallest v0:** a generic runner binary in `igniter-web` (e.g. `src/bin/igweb-serve.rs` or an
    example) that reads `igweb.toml`, builds, composes middleware, and runs a bounded loopback
    `serve_loop`. The author runs it against their app directory — no Rust authored.
11. **Deferred:** source maps, assets/raw responses, public CLI stability, live effect execution,
    deployment topology, package signing, multi-app hosting, domain plugins, file-watch reload.
12. **Next card:** `LAB-IGNITER-WEB-RUNNER-P12` (below).

## Candidate evaluation (A–E)

| Shape | Verdict |
|---|---|
| **A. Rust runner only** | REJECT as the target — fails the non-Rust author goal (good only as the proof harness, which exists). |
| **B. `igweb.toml`** | **WINNER (minimal form).** Declarative; carries `entry` + `sources` (app) + `[server]`/`[middleware]`/`[effects]` (host). Risk (over-config / route coupling) mitigated by keeping it tiny and forbidding routes/secrets/effect-identity in it. A hand-rolled parser (precedent: `project.rs::parse_source_roots_toml`) avoids a new dep. |
| **C. `config.ig` contract returning sources** | REJECT — bootstrapping paradox (need sources to compile the contract that lists sources); also drags runtime into config. |
| **D. directory convention** | **ADOPT as the default** under B — `sources` defaults to the app dir's `*.ig` + `*.igweb`, so a tiny manifest (just `entry`, + host policy) suffices. Pure-convention-only can't express entry/bind/middleware → needs B. |
| **E. `.igwebpkg` build artifact + `serve pkg`** | DEFER — clean separation but too much for v0 (package format + builder + serve subcommand). Named as a later route once a package format is justified. |

**Recommended v0 = B (tiny `igweb.toml`) + D (directory convention defaults) + a generic runner binary
in `igniter-web`.**

## Non-Rust Todo run sketch (v0)

```text
todo_app/
  routes.igweb        # app: handlers TodoHandlers + route lines (P10)
  todo_handlers.ig    # app: pure handler contracts (import IgWebPrelude — injected by the builder)
  igweb.toml          # the config.ru analogue
```
```toml
# todo_app/igweb.toml
[app]
entry   = "Serve"
# sources optional — defaults to all *.ig + *.igweb in this directory (convention D)

[server]
mode         = "loopback"     # host policy; bind to a public address stays a human/live gate
max_requests = 0              # 0 = unbounded loop (v0 may keep it bounded for safety)

[middleware]
trace            = true
body_limit_bytes = 65536
# auth_token_env = "TODO_TOKEN"   # secret via env reference, never inline, never from .igweb
```
```text
$ igniter-web run ./todo_app          # (v0: cargo run --bin igweb-serve -- ./todo_app)
todo_app on http://127.0.0.1:PORT (loopback)
# GET /todos/42 -> 200 {"body":"42"} ; POST /todos/42/done (keyed) -> InvokeEffect ; ...
```
The author wrote **no Rust**. The runner: parse manifest → `build_igweb_app(dir sources, entry)` →
compose P8 middleware from `[middleware]` → `ReloadableApp` → `serve_loop` with `[server]` policy.

## How it composes with the existing stack

- **P9 IgWeb app:** unchanged authored files; `build_igweb_app` is the primitive.
- **P10 prelude/handlers:** the builder still injects `IgWebPrelude`; `.igweb` still names `handlers`.
- **P8 middleware:** the runner composes `with_trace()/with_auth()/with_body_limit()` from
  `[middleware]` (the `Arc<A>` blanket impl, P7, lets it wrap the erased built app).
- **P4 reload:** the built `Arc` is held in `ReloadableApp`; an operator rebuild → `swap`.
- **P3 effect host:** out of v0's machine-free runner; the `[effects]` mapping + secrets are the
  host-side, gated extension when a live runner lands.

## Next implementation card

**`LAB-IGNITER-WEB-RUNNER-P12`** — implement a generic IgWeb runner in `igniter-web` (a
`src/bin/igweb-serve.rs` or example) that:
- reads a minimal `igweb.toml` (`[app] entry`, optional `sources`; optional `[server]
  mode/max_requests`; optional `[middleware] trace/body_limit_bytes`, `auth_token_env`) via a
  hand-rolled parser (no new dep, mirroring `project.rs`);
- defaults `sources` to the app dir's `*.ig` + `*.igweb` (convention D);
- calls `igniter_web::build_igweb_app`, composes P8 middleware, wraps in `ReloadableApp`, runs a bounded
  loopback `serve_loop`;
- ships a fixture `todo_app/` with an `igweb.toml`;
- **tests prove the P9 Todo app runs with ZERO authored Rust** (manifest + `.ig`/`.igweb` only), over
  real loopback (health 200, `/todos/42` param, keyless 400, keyed InvokeEffect, 404/405), with
  middleware composed from the manifest.
**Acceptance gates:** no `.igweb`-sourced bind/secret/effect-identity; loopback only; no live effect
execution; `igniter-server` normal dep tree unchanged (serde-only); no public CLI stability promise;
no source maps. **Closed:** public-bind, secrets-in-manifest, `.igwebpkg`, multi-app, file-watch.

## Closed surfaces (held)

No implementation · no new manifest/CLI/parser built here · no public listener · no SparkCRM server
app · no server route table · no domain code in `igniter-server` · no canon claim for `.igweb` or any
config format.

---

*Readiness/design only. Compiled 2026-06-18 against live P2–P10 surfaces. Recommended v0:
`igweb.toml` (B) + directory convention (D) + a generic `igniter-web` runner over `build_igweb_app`.*
