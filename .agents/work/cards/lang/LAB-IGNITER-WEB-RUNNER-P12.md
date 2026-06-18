# LAB-IGNITER-WEB-RUNNER-P12 — generic igweb-serve runner

Status: CLOSED (lab implementation)  
Lane: standard / lab implementation  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGNITER-WEB-RUNNER-L  
Skill: idd-agent-protocol  

## Why This Card

P11 decided the runner DX:

```text
Rust todo_server.rs = proof harness, not target DX.

Target v0:
  routes.igweb + handler .ig + igweb.toml
  -> generic runner in igniter-web
  -> build_igweb_app
  -> middleware
  -> ReloadableApp
  -> loopback serve_loop
```

This card implements the smallest generic runner so an Igniter-only author can run the P10 Todo app
with **zero authored Rust**.

## Authority

Lab implementation. This may add a binary/example runner and runner tests in `igniter-web`.
It does **not** create a stable public CLI, package spec, source-map system, or live deployment path.

Allowed:
- Add a generic `igweb-serve` binary or equivalent Cargo example in `igniter-web`.
- Add a tiny hand-rolled `igweb.toml` parser (no new dependency).
- Add `igweb.toml` to the Todo example fixture.
- Compose existing P8 middleware from manifest fields.
- Use `ReloadableApp` as the holder/swap unit, but no file watcher.
- Add tests/proof docs/card closure and thin pointers.

Not allowed:
- No new external dependency for TOML parsing.
- No public-bind support by default. Loopback only.
- No public CLI stability promise.
- No source-map/diagnostics expansion.
- No `.igwebpkg` or package artifact format.
- No file watcher / daemon / auto-reload.
- No live effect execution; `InvokeEffect` remains observed `202`.
- No SparkCRM/domain-specific app.
- No route table or domain code in `igniter-server/src`.
- No secrets inline in manifest.
- No canon claim.

## Verify First

Read live code/docs before editing:

- `lab-docs/lang/lab-igniter-web-runner-dx-readiness-p11-v0.md`
- `igniter-web/src/lib.rs`
- `igniter-web/examples/todo_server.rs`
- `igniter-web/examples/todo_app/routes.igweb`
- `igniter-web/examples/todo_app/todo_handlers.ig`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/src/host.rs`
- `igniter-compiler/src/project.rs` (`parse_source_roots_toml` precedent)

Live code wins. Keep the proof small.

## Implementation Target

Preferred layout:

```text
igniter-web/
  src/bin/igweb-serve.rs      # generic lab runner
  examples/todo_app/
    routes.igweb
    todo_handlers.ig
    igweb.toml                # new manifest/config.ru analogue
  tests/runner_tests.rs
```

If `src/bin` is awkward, an example is acceptable, but prefer a binary because P11 names a generic
runner. The binary may be lab-only; do not promise public CLI stability.

## Manifest v0

Hand-parse a tiny subset:

```toml
[app]
entry = "Serve"
# sources = ["todo_handlers.ig", "routes.igweb"]   # optional

[server]
mode = "loopback"
max_requests = 7

[middleware]
trace = true
body_limit_bytes = 65536
# auth_token_env = "TODO_TOKEN"    # optional; value read from env, never inline secret
```

Rules:

- Manifest file name: `igweb.toml`.
- Required: `[app] entry`.
- Optional: `[app] sources`. If omitted, default to all `*.ig` + `*.igweb` files in the app directory,
  sorted deterministically by filename/path.
- Optional: `[server] mode`; v0 accepts only `"loopback"` or omitted.
- Optional: `[server] max_requests`; default may be bounded and safe. For tests, use bounded.
- Optional: `[middleware] trace`, `body_limit_bytes`, `auth_token_env`.
- Reject inline auth secrets; only env variable names.
- Ignore/deny `[effects]` in v0. If present, either reject with a clear error or document as unsupported.

No routes, bind addresses, capability ids, operations, scopes, passports, or secrets in manifest v0.

## Runner Behavior

The runner should:

1. Accept an app directory path argument.
2. Read `<app_dir>/igweb.toml`.
3. Resolve sources relative to the app directory.
4. Call `igniter_web::build_igweb_app(IgWebBuildInput { sources, entry })`.
5. Compose middleware in a deterministic order using existing P8 wrappers.
6. Wrap the whole built stack in `ReloadableApp`.
7. Serve loopback only using existing server loop/host functions.
8. Print enough startup information for tests/users: app dir, entry, source count, loopback address.
9. Exit deterministically in tests when `max_requests` is bounded.

Prefer using existing `serve_loop` if its API is a clean fit; otherwise use `serve_bounded` for the
smallest proof, but document the choice. Do not invent a new server loop.

## Tests / Proofs

Required:

1. `igweb.toml` parser reads `[app] entry`, optional sources, server, middleware fields.
2. Missing manifest / missing entry / unsupported mode produce structured errors, not panics.
3. Default source discovery includes `todo_handlers.ig` and `routes.igweb`, excludes generated/temp files,
   and is deterministic.
4. Runner builds the P10 Todo app from `todo_app/igweb.toml` with no authored Rust and no `web_types.ig`.
5. Real loopback proof covers:
   - `GET /health` -> 200
   - `GET /todos/42` -> 200 body `"42"`
   - keyless `POST /todos/42/done` -> 400
   - keyed `POST /todos/42/done` -> observed `InvokeEffect` / 202 with target + idempotency key
   - `GET /missing` -> 404
   - `POST /health` -> 405
6. Middleware from manifest is applied:
   - `trace = true` decorates correlation/header as P8 does; and/or
   - `body_limit_bytes` rejects oversized body before app; and/or
   - `auth_token_env` short-circuits without env/token and passes with token.
7. Manifest cannot smuggle privileged effect identity (`capability_id`, `operation`, `scope`) into
   `InvokeEffect`.
8. Loopback only; no public bind in v0.
9. `igniter-server` normal dependency tree remains serde-only.
10. P10/P9/P8 regressions remain green.

Suggested commands:

```bash
cd igniter-web && cargo test
cd igniter-web && cargo run --bin igweb-serve -- examples/todo_app
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
cd igniter-server && cargo tree -e normal
cd igniter-compiler && cargo test --test igweb_lowering_tests
```

If the binary needs a bounded request count to exit, use the manifest's `max_requests` fixture or a
test-only flag. State the exact command in the proof doc.

## Deliverables

- Generic runner binary/example.
- Tiny manifest parser and typed config structs (in `igniter-web`, not `igniter-server`).
- `examples/todo_app/igweb.toml`.
- Runner tests.
- `lab-docs/lang/lab-igniter-web-runner-p12-v0.md`
- Closing report in this card.
- Thin pointer from P11 readiness doc to P12 result.

## Acceptance

1. P10 Todo app can be run from `routes.igweb + todo_handlers.ig + igweb.toml` with no authored Rust.
2. Runner uses `build_igweb_app` as the library primitive.
3. Manifest parser is tiny, deterministic, and dependency-free.
4. Sources are resolved relative to the app directory.
5. Middleware config composes through existing P8 wrappers.
6. Runner wraps the built stack in `ReloadableApp` or documents why the smallest proof uses a bounded
   host helper instead.
7. Real loopback behavior matches P10.
8. Manifest cannot name routes, bind public addresses, secrets, or privileged effect identities.
9. `igniter-server` remains generic and serde-only by default.
10. Docs explicitly classify the runner as lab v0, not stable CLI/canon.

## Closing Report Template

Report:

- final runner command;
- manifest shape implemented;
- file layout of Todo app;
- request/response trace;
- middleware proof;
- dependency boundary result;
- what improved over `todo_server.rs`;
- what remains deferred.

---

## Closing report — 2026-06-18

**Final runner command:** `cargo run --bin igweb-serve -- examples/todo_app` (a real loopback server,
bounded by manifest `max_requests`; verified live serving 7 requests then exiting).

**Manifest implemented (`igweb.toml`, hand-parsed, no dep):** `[app] entry` (required) + optional
`sources`; `[server] mode` (loopback only) + `max_requests`; `[middleware] trace` / `body_limit_bytes`
/ `auth_token_env`. Rejects (structured `RunnerError::Manifest`): missing entry, `[effects]`, inline
`auth_token`, non-loopback mode, unknown keys. No routes/bind/secret/effect-identity expressible.

**Todo app layout:** `examples/todo_app/{routes.igweb, todo_handlers.ig, igweb.toml}` — author writes
NO Rust.

**Request/response trace (live bin):** GET /health 200 · GET /todos/42 200 `{"body":"42"}` (regexp
param) · POST keyless 400 · POST keyed 202 invoke_effect target `todo-done` idem `evt-9` +
`correlation_id` added by the manifest's trace middleware · GET /missing 404 · POST /health 405.

**Middleware proof:** `manifest_body_limit_rejects_oversized` (413), `manifest_auth_env_short_circuits_
then_passes` (401→200), trace decoration seen live. Composed via existing P8 wrappers (`BodyLimit→Auth→
Trace→app`) over the erased built app (Arc<A> blanket impl).

**Dependency boundary:** `igniter-server` normal tree serde-only (`cargo tree -e normal` none); runner +
parser live in `igniter-web`; no new external dependency (toml hand-parsed).

**Improved over `todo_server.rs`:** P9's per-app Rust runner → a GENERIC manifest-driven runner; an
Igniter-only author writes zero Rust; middleware declarative; server boundary unchanged.

**Counts:** igniter-web 20 (5 builder + 7 example + 8 runner); igniter-server 49 default / machine
0-fail; P4 lowering 2. igniter-web warning-clean.

**Deferred:** public CLI stability; source maps; assets; live effect execution; `[effects]` binding;
`.igwebpkg`; file-watch/auto-reload; multi-app; public bind.

**Acceptance:** all 10 boxes met (see `lab-docs/lang/lab-igniter-web-runner-p12-v0.md`). Thin pointer
added from the P11 readiness doc.

