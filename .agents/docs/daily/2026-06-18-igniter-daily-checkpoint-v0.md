# Igniter Daily Checkpoint — 2026-06-18

## Daily Summary

2026-06-18 was a high-throughput architecture-to-DX day. The main arc:

```text
igniter-server substrate
  -> IgWeb projection dialect
  -> igniter-web builder crate
  -> real Todo app from authored files
  -> shared IgWeb prelude
  -> generic manifest runner
  -> package/workspace research direction
```

The important shift: IgWeb crossed from "Rust proof harness" into a real authoring loop.
An Igniter-only author can now write `.igweb` + handler `.ig` + `igweb.toml` and run a
loopback server through a generic runner, without writing Rust app boot code.

SparkCRM work also continued in parallel outside this checkpoint's detailed evidence trail; do not
infer Spark live/deploy state from this lab daily note.

## Checkpoints Closed

### Igniter Server / App Boundary

- `igniter-server` remains a generic substrate:
  - owns wire/transport, loop, concurrency/lifecycle, reload, middleware, optional effect host;
  - does not own routing/domain/product meaning;
  - app implements `ServerApp`;
  - app returns `Respond` / `Invoke` / logical `InvokeEffect`.
- Server wave checkpoint P14 is in place as the navigation/front-door for the server line.

Core invariant retained:

```text
server owns wire / lifecycle / reload
app owns routing / product meaning
host owns effect authority
```

### Projection Dialects / IgWeb

- Projection dialects were named and governed:
  - `.ig` remains runtime/canon authority;
  - `.igweb` and `.igv` are lab projection dialects;
  - dialects must lower deterministically into inspectable artifacts and must not smuggle runtime
    authority.
- `.igweb` routing lowering is now real:
  - route lines lower to generated `.ig`;
  - path params use `stdlib.regexp.matches/capture`;
  - route handlers remain static `call_contract("...")`;
  - no dynamic dispatch or server route table.

### Standard Library Regexp

- Regex was promoted from deferred design pressure into a proven stdlib direction:
  - P1 readiness selected `matches` + positional `capture`;
  - P2 proved semantics with Rust `regex` in proof-local tests;
  - P3 wired `stdlib.regexp.{matches,capture}` into typechecker/VM.
- This unlocked clean IgWeb route params without split/nth gymnastics.

### igniter-web

The web line reached a usable lab loop:

- P5 proved server adapter path from `.igweb` generated app into `igniter-server`.
- P6 chose packaging seam: explicit source paths + entry, not manifest first.
- P7 extracted a reusable `build_igweb_app(paths, entry)` builder.
- P8 moved that builder into a new `igniter-web` crate, keeping `igniter-server` normal deps small.
- P9 added the first real Todo app from files:
  - `routes.igweb`
  - `todo_handlers.ig`
  - `todo_server.rs` proof runner.
- P10 added `IgWebPrelude` + `handlers <Module>`:
  - no more per-app `web_types.ig`;
  - no more hardcoded `TodoHandlers` in the lowerer.
- P11 decided runner DX:
  - Rust runner is proof harness, not target DX;
  - target is `igweb.toml` + directory convention + generic runner.
- P12 implemented the generic runner:
  - `igweb-serve <app_dir>`;
  - hand-rolled `igweb.toml`, no TOML dependency;
  - default source discovery for `*.ig` + `*.igweb`;
  - P8 middleware from manifest;
  - `ReloadableApp`;
  - loopback-only bounded serve loop.

Current authoring shape:

```text
todo_app/
  routes.igweb
  todo_handlers.ig
  igweb.toml

cargo run --bin igweb-serve -- examples/todo_app
```

Proven live route trace:

```text
GET  /health             -> 200
GET  /todos/42           -> 200 {"body":"42"}
POST /todos/42/done      -> 400 without idempotency key
POST /todos/42/done      -> 202 InvokeEffect target=todo-done idem=evt-9
GET  /missing            -> 404
POST /health             -> 405
```

### IgWeb Dependency Boundary

Boundary held:

```text
igniter-server normal deps: serde + serde_json only
igniter-web carries compiler/machine weight
igniter-server owns no domain routing table
```

Repeated checks confirmed:

```text
igniter-web cargo test                         -> 20 passed after P12
igniter-server cargo test                      -> 49 passed
igniter-server cargo test --features machine   -> 71 passed
igniter-compiler igweb_lowering_tests          -> 2 passed
```

Existing compiler/vm warnings remain pre-existing and unrelated.

### Runner DX

Major DX correction:

```text
Before: app author writes Rust runner.
After:  app author writes Igniter files + igweb.toml.
```

The generic runner is still lab v0:

- no stable CLI promise;
- no public bind;
- no source-map;
- no file watcher;
- no live effect execution;
- no package artifact format.

### Package / Workspace Research

Gemini and Opus package research converged on a useful direction:

- Gemini Round 1 favored local-first, no install scripts, capability declarations, registry later.
- Opus validation accepted most of that but revised lockfile timing.
- Opus independent research reframed the first slice:

```text
not package manager first
workspace/import ownership first
```

Current recommendation:

```text
LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3
  local workspace members
  module ownership
  no phantom imports
  no lockfile yet
  no registry / versions / install hooks
```

Lockfile/provenance should wait until remote or mutable inputs exist.

## Commits Landed Today

Recent relevant lab commits:

```text
bce347f Add package manager research validation
f50568e Add generic IgWeb runner
69a4ba7 Add Gemini package manager research round one
3547e10 Add IgWeb runner DX readiness packet
ce0a3b7 Add IgWeb runner and package research cards
ded25b6 Add IgWeb prelude and handler directive
d0b7182 Add IgWeb example todo app
fe86215 Extract IgWeb builder into igniter-web crate
7b34158 Add IgWeb package builder proof
f9ea412 Add IgWeb packaging seam readiness
14ab902 Add IgWeb server adapter proof
6473730 Add Gemini projection dialect research packets
```

## Current End-of-Day State

### Worktree

- `igniter-lab`: clean at checkpoint creation time.
- Package research cards/docs are committed.
- IgWeb runner P12 is committed.

### Igniter Web

- `igniter-web` exists as the lab home for IgWeb builder/runner.
- Todo example now runs without authored Rust.
- IgWeb authoring is real enough to stress next design questions.

### Server

- `igniter-server` remains generic and small.
- No public listener/live deployment claim.
- No domain route config in server core.

### Package/Workspace

- Package manager research is intentionally not implementation authority.
- Next action is local workspace/import ownership, not lockfile or registry.

## Rebalanced Backlog For Tomorrow

### P0 — Morning Hygiene

1. Start with a quick `git status` in `igniter-lab`.
2. Re-run only the narrow checks for whichever line resumes first.
3. Do not mix IgWeb implementation commits with package/workspace research commits.

### P0 — IgWeb Next Crest

Likely next practical implementation:

```text
LAB-IGNITER-WEB-RUNNER-P13 or equivalent:
  tighten runner ergonomics after P12
  decide whether `igweb-serve` stays bin or becomes example/tool command
  keep loopback-only / lab-v0 boundary
```

But before coding, discuss whether the next user-facing step is:

- runner ergonomics;
- source discovery/module naming;
- manifest minimalism;
- or source-map diagnostics.

Do **not** jump to source-map unless diagnostics pain becomes the active pressure.

### P0 — Package / Workspace Next Crest

Open:

```text
LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3
```

Target:

- extend project mode with local workspace/dependency roots;
- enforce module ownership;
- prevent phantom imports;
- preserve existing single-root projects;
- no lockfile;
- no registry;
- no versions;
- no install hooks.

### P1 — Projection Dialects

Keep P0 governance in force:

- `.igweb` and `.igv` are projection dialects, not canon;
- generated output must be inspectable;
- no hidden authority;
- app-local dialects should require explicit lowerer/registry thinking before broad use.

### P1 — SparkCRM

Spark work continued in parallel, but this checkpoint does not summarize its live state.

Do not infer:

- live SparkCRM readiness;
- vendor API status;
- credential availability;
- production deployment.

If tomorrow returns to Spark, start from Spark-specific live context/observability, not this lab note.

## Do Not Start First Tomorrow

- Do not open public bind for `igweb-serve`.
- Do not implement package lockfile before import ownership.
- Do not create registry/version solver.
- Do not push route tables into `igniter-server`.
- Do not make `.igweb` canon by accident.
- Do not start live SparkCRM traffic from lab momentum.

## Suggested Morning Entry Points

```text
1. Decide: IgWeb runner polish vs package workspace resolver.
2. If IgWeb: review P12 live DX and name the smallest next card.
3. If packages: open LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3.
4. If Spark: switch context deliberately and verify live Spark facts first.
```

## One-Line Carry Forward

```text
IgWeb now runs from Igniter files + igweb.toml with no authored Rust; next hard choice is whether to
polish runner DX or start workspace/import ownership before package-manager semantics grow.
```

