# LAB-IGNITER-WEB-RUNNER-DX-READINESS-P11 — config.ru-like runner model for IgWeb apps

Status: CLOSED (readiness packet)  
Lane: standard / readiness  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGNITER-WEB-RUNNER-DX-K  
Skill: idd-agent-protocol  

## Why This Card

P9 proved that a real IgWeb app can be authored as files and run with:

```text
routes.igweb + handlers.ig + tiny Rust runner
  -> build_igweb_app(...)
  -> igniter_server::host::serve_bounded(...)
```

That is a good proof harness, but it is probably **not** the target developer experience.

The intended user may know Igniter but not Rust. Forcing every app author to write a Rust
runner creates the same bad coupling we just removed from `igniter-server`: app-specific
boot code leaks into host mechanics.

Research the runner model. The analogy to test carefully is:

```text
Rack/Puma:
  config.ru declares the app
  puma owns process/socket/concurrency
  app owns routing/domain

IgWeb:
  ??? declares the IgWeb app
  igniter-server owns process/socket/concurrency/reload
  IgWeb app owns routing/domain
```

## Authority

Readiness/design only. No code. No new config format implementation. No public CLI promise.

Allowed:
- Produce a compact packet answering the research questions below.
- Compare candidate runner models using live P2-P10 surfaces.
- Recommend one v0 path and one implementation card.
- Add closing report to this card.
- Add thin pointers from P9/P10 docs only if useful.

Not allowed:
- No implementation.
- No new manifest/CLI/parser.
- No public listener/live server.
- No SparkCRM-specific server app.
- No server route table.
- No moving domain code into `igniter-server`.
- No canon claim for `.igweb` or any config format.

## Verify First

Read live code/docs before recommending:

- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-web/src/lib.rs`
- `igniter-web/examples/todo_server.rs`
- `igniter-web/examples/todo_app/routes.igweb`
- `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-app-boundary-p6-v0.md`
- `lab-docs/lang/lab-igniter-web-packaging-p6-v0.md`
- `lab-docs/lang/lab-igniter-web-example-app-p9-v0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`

Live code wins. Treat the Rust runner as evidence/proof harness, not authority.

## Research Questions

Answer all, compactly:

1. **What is the current runner contract?** Precisely describe what `todo_server.rs`
   does today and which parts are app-specific vs host mechanics.
2. **What is the desired non-Rust author contract?** What should a developer write if
   they only know Igniter? Candidate: `routes.igweb` + handlers + one app declaration file.
3. **What is the `config.ru` analogue?** Is it:
   - an `igweb.toml`;
   - an `.igapp` / `.igpkg` manifest;
   - an `.ig` contract that returns app config;
   - a directory convention;
   - or a generated artifact produced by `igniter web build`?
4. **What must stay in the server?** Process, socket, loop, concurrency, reload, middleware,
   effect-host binding, observability. Confirm against P2-P8.
5. **What must stay in the app?** Routing, handler contracts, domain types, logical targets,
   request validation, product meaning.
6. **How does `build_igweb_app(paths, entry)` fit?** Is it the library primitive behind the
   runner, or should it be hidden behind a higher-level package loader?
7. **How should middleware be configured?** Static host config, wrapper stack, env, or app
   declaration? Which pieces are safe for app authors and which require host authority?
8. **How should effect target binding be configured?** App emits logical target; host maps
   target -> `EffectBridgeConfig`. Where does that mapping live in a deployable app package?
9. **How does hot reload work?** What is the atomic reload unit: authored directory, generated
   package, compiled app, or `Arc<dyn ServerApp>`?
10. **What is the smallest practical v0?** It should let a non-Rust user run the P9 Todo app
    without writing Rust, while preserving all server/app authority boundaries.
11. **What is explicitly deferred?** Source maps, assets, public CLI stability, live effect
    execution, deployment topology, package signing, multi-app hosting, domain plugins.
12. **What should the next implementation card be?** Name it and define acceptance.

## Candidate Shapes To Evaluate

Evaluate these at minimum:

### A. Rust runner stays the only runner

Simple for framework developers, bad for Igniter-only authors. Probably not enough.

### B. `igweb.toml`

Example sketch:

```toml
[app]
entry = "Serve"
sources = ["web_types.ig", "todo_handlers.ig", "routes.igweb"]

[server]
bind = "127.0.0.1:3000"
mode = "loopback"

[middleware]
trace = true
body_limit_bytes = 65536
```

Risk: too much config too early; could recreate server-route coupling if careless.

### C. `config.ig` / app contract

Example sketch:

```text
module TodoApp

pure contract App {
  output app : WebApp = WebApp {
    entry: "Serve",
    sources: ["routes.igweb", "todo_handlers.ig"]
  }
}
```

Risk: bootstrapping problem; compiler needs sources before contract returns sources.

### D. Directory convention

Example:

```text
app/
  routes.igweb
  handlers.ig
  web.igniter.toml   # optional later
```

Good for P9-sized apps; may need manifest once multiple apps/assets/env enter.

### E. Build artifact first

```text
igniter web build ./todo_app -> todo_app.igwebpkg
igniter-server serve todo_app.igwebpkg
```

Good separation, but likely too much for v0 unless package builder is tiny.

## Desired Recommendation Bias

Prefer the shape that:

- lets an Igniter-only author run P9 Todo without Rust;
- keeps `igniter-server` generic, domain-free, route-table-free;
- uses `igniter-web` as the home for IgWeb packaging/building;
- keeps host authority explicit for bind address, middleware, secrets, effect target mapping;
- does not turn `.igweb` into a secret runtime language;
- can be implemented in one small follow-up card.

## Deliverables

- `lab-docs/lang/lab-igniter-web-runner-dx-readiness-p11-v0.md`
- Closing report in this card.
- Optional thin pointer from P9/P10 docs if helpful.

## Acceptance

1. Packet distinguishes proof runner vs target runner.
2. Packet names the app/server authority boundary.
3. Packet evaluates at least A-E above.
4. Packet recommends one v0 runner/package model.
5. Packet includes a non-Rust Todo app run sketch.
6. Packet says where middleware config belongs in v0.
7. Packet says where effect target binding belongs in v0.
8. Packet says how reload sees the built app.
9. Packet explicitly defers source-map/diagnostics unless needed for the runner.
10. Packet names the next implementation card with concrete acceptance.

## Closing Report Template

Report:

- chosen v0 runner model;
- rejected alternatives and why;
- proposed file layout;
- exact user command(s);
- authority boundary;
- how it composes with P8 middleware, P4 reload, P3 effect host, P9 IgWeb app;
- next implementation card.

