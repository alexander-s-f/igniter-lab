# LAB-IGNITER-WEB-PRELUDE-P10 — shared web prelude + handler module convention

Status: CLOSED (lab implementation)  
Lane: standard / lab implementation  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGNITER-WEB-PRELUDE-J  
Skill: idd-agent-protocol  

## Why This Card

P9 proved the first real IgWeb app:

```text
routes.igweb + web_types.ig + todo_handlers.ig + tiny Rust runner
  -> build_igweb_app
  -> bounded loopback server
```

The DX is real, but the proof exposed two avoidable boilerplate seams:

1. Every app must author the same `Request`/`Decision` support types.
2. `lower_igweb` currently hardcodes `import WebTypes` and `import TodoHandlers`.

This card removes that boilerplate while keeping the server generic and keeping `.igweb`
as a Projection Dialect, not canon language syntax.

## Authority

Lab implementation. This may change `igniter-compiler` IgWeb lowering and `igniter-web`
builder/example/test surfaces. It is not canon `.ig`, not a public framework promise, and
not a source-map/manifest/CLI slice.

Allowed:
- Add an IgWeb-generated prelude/support module for common web request/decision shapes.
- Update `lower_igweb` to use the prelude instead of requiring app-authored `web_types.ig`.
- Add a small, explicit handler-module convention to `.igweb` if needed.
- Update `igniter-web` builder/tests/examples to prove the new DX.
- Keep backwards compatibility with the P9 shape if cheap; otherwise document the migration
  clearly and update all lab examples/tests.
- Add proof docs/card closure and thin pointers.

Not allowed:
- No `igweb.toml` manifest.
- No CLI/dialect registry.
- No `.igweb -> .ig` source-map work.
- No route table or domain code in `igniter-server/src`.
- No SparkCRM/domain-specific server app.
- No live/public listener; loopback/bounded only.
- No real effect execution; `InvokeEffect` may remain observed `202`.
- No new web framework abstraction beyond the prelude/convention.
- No canon claim for `.igweb`.

## Verify First

Read live code before editing:

- `igniter-compiler/src/igweb.rs`
- `igniter-web/src/lib.rs`
- `igniter-web/examples/todo_app/routes.igweb`
- `igniter-web/examples/todo_app/web_types.ig`
- `igniter-web/examples/todo_app/todo_handlers.ig`
- `igniter-web/tests/example_app_tests.rs`
- `igniter-web/tests/builder_tests.rs`
- `lab-docs/lang/lab-igniter-web-example-app-p9-v0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`

Live code wins. In particular, verify how `load_program` receives generated and authored
sources before deciding whether the prelude belongs in `lower_igweb`, `igniter-web`, or both.

## Target Shape

The P10 Todo app should no longer need `web_types.ig`.

Preferred authored shape:

```text
igniter-web/examples/todo_app/
  routes.igweb
  todo_handlers.ig
```

Preferred `.igweb` shape:

```text
app TodoWeb entry Serve {
  handlers TodoHandlers

  route GET  "/health"         -> Health
  route GET  "/todos"          -> TodoIndex
  route GET  "/todos/:id"      -> TodoShow
  route POST "/todos/:id/done" -> TodoDone requires idempotency
}
```

If a slightly different spelling is simpler, use it, but keep it boring and explicit. Do not
invent a broad web DSL here. The goal is only:

```text
common Request/Decision shape generated/provided by IgWeb
handler module named by app instead of hardcoded by lowerer
```

## Semantics

Generated/support prelude should provide the same logical surface P9 authored manually:

```text
type Request {
  method : String
  path : String
  body : String
  correlation_id : String
  idempotency_key : String
}

variant Decision {
  Respond { status: Integer, body: String }
  InvokeEffect { target: String, input: String, idempotency_key: String }
}
```

Use the exact live shape if it differs. Do not add headers, query params, cookies, assets, or
typed bodies in this card.

`handlers <ModuleName>` should affect only generated imports / handler resolution. It must not
grant new authority, add dynamic dispatch, or let the server own routes.

## Implementation Notes

Open design choice for the implementer:

1. `lower_igweb` emits/imports a generated support module, and `igniter-web` builder injects it.
2. `lower_igweb` emits one self-contained generated `.ig` module that includes support types.
3. `igniter-web` builder always prepends/provides a stable `IgWebPrelude` source.

Choose the smallest path that:
- compiles through existing project/load surfaces;
- keeps generated output inspectable;
- avoids module-name collisions or detects them clearly;
- does not make `igniter-server` depend on compiler/machine in normal builds.

Name the support module something explicit and lab-scoped, e.g. `IgWebPrelude`, unless live code
forces another safe name.

## Tests / Proofs

Required:

1. `lower_igweb` no longer hardcodes `TodoHandlers`; handler module comes from `.igweb`.
2. The common `Request`/`Decision` shape is no longer authored per example app.
3. The generated output remains deterministic / byte-stable.
4. Existing static `call_contract("...")` discipline remains: no dynamic dispatch from route data.
5. P9 Todo example runs from on-disk files with no `web_types.ig`.
6. `/todos/42` still proves path params through regexp/capture.
7. Keyless mutation still returns 400.
8. Keyed mutation still yields logical `InvokeEffect` with target/idempotency key and no privileged
   effect identity.
9. `igniter-server` normal dependency tree remains serde-only.
10. P4/P7/P8/P9 regressions remain green.

Suggested commands:

```bash
cd igniter-compiler && cargo test --test igweb_lowering_tests
cd igniter-web && cargo test
cd igniter-web && cargo run --example todo_server
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
cd igniter-server && cargo tree -e normal
```

Use exact updated test names/counts in the closing report.

## Deliverables

- Updated IgWeb lowering / builder as needed.
- Updated Todo example with less boilerplate.
- Tests proving prelude + handler-module convention.
- `lab-docs/lang/lab-igniter-web-prelude-p10-v0.md`
- Closing report in this card.
- Thin pointer from P9 proof doc to P10 result.

## Acceptance

1. `web_types.ig` is no longer required by the P10 Todo example.
2. Handler module is explicit in `.igweb` or otherwise clearly parameterized; no hidden
   `TodoHandlers` hardcode remains.
3. Generated/support `Request`/`Decision` are inspectable and documented.
4. No new server route table or domain code enters `igniter-server/src`.
5. No new privileged effect identity enters `.igweb` or app handlers.
6. Existing P9 behavior remains functionally identical on loopback.
7. Generated output remains deterministic.
8. Dependency boundary remains clean.
9. Docs state the exact new developer file layout and remaining pain points.
10. All listed regressions are green.

## Closing Report Template

Report:

- final authored file layout before/after;
- where the prelude lives and how it is injected/compiled;
- exact `.igweb` handler-module spelling;
- generated-output determinism evidence;
- request/response trace from `cargo run --example todo_server`;
- dependency boundary result;
- what this improves in DX;
- what remains deferred.

---

## Closing report — 2026-06-18

**Authored layout before→after:** P9 `{web_types.ig, todo_handlers.ig, routes.igweb}` → P10
`{todo_handlers.ig, routes.igweb}` (web_types.ig deleted). `.igweb` gains `handlers TodoHandlers`;
`todo_handlers.ig` imports `IgWebPrelude` instead of `WebTypes`.

**Where the prelude lives / injection:** `igniter_compiler::igweb::{PRELUDE_MODULE="IgWebPrelude",
PRELUDE_SOURCE}` (Request type + Decision variant) — co-located with the lowering that emits
`import IgWebPrelude`. `lower_igweb` generates `import IgWebPrelude` + `import <handlers_module>` (from
the directive). `igniter_web::build_igweb_app` writes PRELUDE_SOURCE to a file and adds it to
`load_program`. Chosen path = lowering imports prelude + builder injects it (generated `.ig` stays
inspectable; duplicate user prelude → clear OOF-IMP4 Load error).

**`.igweb` handler-module spelling:** `handlers <ModuleName>` (required line in the app block;
missing/dup/multi-token → structured IgwebError). Affects only generated imports + static
`call_contract` resolution — no authority, no dynamic dispatch.

**Determinism:** `lowers_deterministically` (lower twice → byte-equal) green.

**Trace (cargo run --example todo_server, now 2 authored files):** health 200, todos 200, todos/42
→"42" (regexp param), keyless 400, keyed 202 invoke_effect target "todo-done" idem evt-1 (no
capability_id/scope), missing 404, POST /health 405.

**Dependency boundary:** igniter-server normal tree serde-only (`cargo tree -e normal` none).

**Counts:** igweb lib 5 (+imports/missing-handlers) · P4 lowering 2 · igniter-web 12 (5 builder + 7
example) · igniter-server 49 default / 71 machine (0 failed). All warning-clean own code.

**DX improvement:** an app is now 2 authored files + a tiny runner; Request/Decision no longer
copy-pasted; handler module app-named, not a hidden lowerer constant.

**Deferred:** fixed `AppRoutes`/`IgWebPrelude` module names; no `.igweb→.ig` source map; InvokeEffect
observed-not-executed; one `.igweb` per build.

**Acceptance:** all 10 boxes met (see `lab-docs/lang/lab-igniter-web-prelude-p10-v0.md`). Thin pointer
added from the P9 proof doc.

