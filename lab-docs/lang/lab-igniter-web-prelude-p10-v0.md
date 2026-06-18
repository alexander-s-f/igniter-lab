# lab-igniter-web-prelude-p10-v0 — shared web prelude + handler-module convention

**Card:** `LAB-IGNITER-WEB-PRELUDE-P10` · **Delegation:** `OPUS-IGNITER-WEB-PRELUDE-J`
**Status:** CLOSED (lab implementation) — removed the two P9 boilerplate seams: apps no longer author
`web_types.ig` (a shared `IgWebPrelude` provides `Request`/`Decision`), and `lower_igweb` no longer
hardcodes `import TodoHandlers` (the handler module is named by a required `handlers <Module>`
directive). **No manifest, no CLI, no source-map, no server route table, no canon claim.**
**Authority:** Lab. Touched `igniter-compiler` lowering + `igniter-web` builder/example/tests.

## Authored file layout — before → after

```text
P9 (before):  examples/todo_app/{ web_types.ig, todo_handlers.ig, routes.igweb }
P10 (after):  examples/todo_app/{ todo_handlers.ig, routes.igweb }     ← web_types.ig GONE
```
`.igweb` before → after:
```text
P9:   app TodoWeb entry Serve { route GET "/health" -> Health ... }
P10:  app TodoWeb entry Serve {
        handlers TodoHandlers          ← app names its handler module (no hardcode)
        route GET "/health" -> Health ...
      }
```
`todo_handlers.ig`: `import WebTypes` → `import IgWebPrelude`.

## Where the prelude lives + how it's injected

- **Source of truth:** `igniter_compiler::igweb::PRELUDE_MODULE` (`"IgWebPrelude"`) +
  `PRELUDE_SOURCE` (the `Request` type + `Decision` variant) — co-located with the lowering that emits
  `import IgWebPrelude`, so the import name and the module can never drift.
- **Lowering (`lower_igweb`):** generated `AppRoutes` now emits `import IgWebPrelude` + `import
  <handlers_module>` (from the directive) instead of `import WebTypes` + `import TodoHandlers`.
- **Injection (`igniter_web::build_igweb_app`):** writes `PRELUDE_SOURCE` to one file per build and
  adds it to the `IgniterMachine::load_program` source set. So every app gets `Request`/`Decision`
  without authoring them; the handler module (authored) imports `IgWebPrelude`.

Chosen path = option 1 (lowering imports the prelude; builder injects it). The generated `.ig` stays
inspectable; a duplicate user-supplied `IgWebPrelude` would surface as a clear `OOF-IMP4` Load error.

## `handlers` directive semantics

`handlers <ModuleName>` is a required line inside the `app { ... }` block. It affects only the
generated `import <ModuleName>` and the static `call_contract("Handler", ...)` resolution — it grants
no authority, adds no dynamic dispatch (targets remain string literals), and never lets the server own
routes. Missing/duplicate/multi-token directives are structured `IgwebError`s.

## Acceptance — met

1. ✓ `web_types.ig` not required by the P10 Todo example (file deleted; not authored).
2. ✓ Handler module explicit via `handlers TodoHandlers`; no hardcoded `TodoHandlers` remains
   (`lower_igweb` reads the directive; `missing_handlers_directive_is_rejected` proves it's required).
3. ✓ `Request`/`Decision` are the inspectable, documented `PRELUDE_SOURCE` (`module IgWebPrelude`).
4. ✓ No server route table / domain code in `igniter-server/src`.
5. ✓ No privileged effect identity in `.igweb` / handlers (`InvokeEffect` names a logical target only).
6. ✓ P9 behavior identical on loopback (`cargo run --example todo_server` output unchanged).
7. ✓ Generated output deterministic (`lowers_deterministically`: lower twice → byte-equal).
8. ✓ Dependency boundary clean — `igniter-server` normal tree stays serde-only.
9. ✓ This doc states the new layout + remaining pain points.
10. ✓ P4/P7/P8/P9 regressions green.

## Test commands + pass counts

```text
$ cd igniter-compiler && cargo test --lib igweb                 → 5 passed (incl. imports + missing-handlers)
$ cd igniter-compiler && cargo test --test igweb_lowering_tests → 2 passed (prelude+handlers compile clean)
$ cd igniter-web && cargo test                                  → 12 passed (5 builder + 7 example)
$ cd igniter-web && cargo run --example todo_server             → 7 routes, exit 0 (no web_types.ig)
$ cd igniter-server && cargo test                               → 49 passed
$ cd igniter-server && cargo test --features machine            → 71 passed; 0 failed
$ cd igniter-server && cargo tree -e normal | grep web|machine|compiler|regex|tokio → (none) serde-only
```

Request/response trace (`cargo run --example todo_server`, now from 2 authored files):
```text
GET  /health        -> 200 {"body":"ok"}
GET  /todos         -> 200 {"body":"[]"}
GET  /todos/42      -> 200 {"body":"42"}        (path param via generated regexp/capture)
POST /todos/42/done -> 400 {"body":"missing idempotency-key"}       (keyless)
POST /todos/42/done -> 202 invoke_effect target "todo-done" idem "evt-1"   (keyed; no capability_id/scope)
GET  /missing       -> 404 ;  POST /health -> 405
```

## DX improvement + remaining pain

**Improved:** an app is now **2 authored files** — `todo_handlers.ig` + `routes.igweb` — plus a tiny
runner. `Request`/`Decision` are no longer copy-pasted per app; the handler module name is explicit and
app-chosen rather than a hidden lowerer constant.

**Remaining (deferred):** the generated module name (`AppRoutes`) and the prelude module name
(`IgWebPrelude`) are still fixed conventions (fine for v0); no `.igweb→.ig` source map; `InvokeEffect`
observed (not executed); only one `.igweb` per build is the proven shape.

## Closed surfaces (held)

No `igweb.toml`/CLI/source-map · no `igniter-server/src` route table/domain · no SparkCRM · no
live/public listener · no real effect execution · no new framework abstraction beyond the prelude +
`handlers` convention · no canon claim for `.igweb`.

---

*Lab implementation. Compiled 2026-06-18; igniter-web 12 + igweb lib 5 + P4 lowering 2 green;
igniter-server 49/71; example runs from 2 files (no `web_types.ig`); generated output deterministic.*
