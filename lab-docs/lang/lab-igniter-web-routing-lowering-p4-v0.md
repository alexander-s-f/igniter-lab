# lab-igniter-web-routing-lowering-p4-v0 — `.igweb` routes → explicit `.ig` Serve

**Card:** `LAB-IGNITER-WEB-ROUTING-LOWERING-P4` · **Delegation:** `OPUS-IGWEB-ROUTING-D`
**Status:** CLOSED (lab implementation) — a deterministic `.igweb` route-authoring sugar that lowers to
an explicit `Serve(Request) -> Decision` `.ig` contract, which compiles through the real multifile
compiler using `stdlib.regexp.matches`/`capture` (P3) for params and static `call_contract` arms.
**No canon `.ig` syntax, no server-core routing, no `igniter-server` change, no dynamic dispatch, no
DB/live.**
**Authority:** Lab tooling. Mirrors the proven `.igv`→ViewArtifact lowering; verified against live code.

## What this card proves

```text
app TodoWeb entry Serve {
  route GET  "/todos/:id"      -> TodoShow
  route POST "/todos/:id/done" -> TodoDone requires idempotency
}
        │  lower_igweb (deterministic; IgwebError{line,message})
        ▼  module AppRoutes — pure contract Serve(req: Request) -> Decision
           if matches(req.path, "^/todos/([^/]+)$") { if req.method == "GET" {
               call_contract("TodoShow", req, capture(req.path, "^/todos/([^/]+)$", 1))
           } else { Respond { status: 405, ... } } } else { … Respond { status: 404, ... } }
        │  multifile compile (web_types.ig + handlers.ig + generated routes.ig)
        ▼  compiles clean — NO OOF-RE1 / OOF-TY0
```

Routing/product meaning lives in the generated app (`AppRoutes::Serve`), never in `igniter-server`.
The `.igweb` is sugar; the generated `.ig` is the inspectable truth.

## Where it lives

`igniter-compiler/src/igweb.rs` — `pub fn lower_igweb(src: &str) -> Result<String, IgwebError>` +
`pub struct IgwebError { line, message }`. Compiler-tooling layer (lab), **not** `igniter-server`.
It emits `.ig` source text (the analogue of `lower_igv` emitting ViewArtifact JSON).

## `.igweb` v0 grammar

```text
app <Name> entry <ServeContract> {
  route <METHOD> "<pattern>" -> <Contract> [requires idempotency]
  ...
}
```
- `--` / `#` comments and blank lines allowed; malformed lines → `IgwebError { line, message }`.
- deterministic: routes keep source order; patterns grouped first-seen; no map iteration in output.
- v0 convention (project plumbing, not route authoring, so fixed in the lowering not the grammar): the
  generated module is `AppRoutes`, importing `WebTypes` (Request + Decision) and `TodoHandlers`.

## Generated `.ig` shape (explicit, boring, inspectable)

- one `pure contract <entry>` with `input req : Request`, `compute decision : Decision = <tree>`,
  `output decision : Decision`;
- a chain of `if matches(req.path, "<anchored-regex>") { <method-dispatch> } else { <next pattern> }`,
  terminating in `Respond { status: 404, body: "not found" }`;
- per pattern, a method chain `if req.method == "M" { <arm> } else { … else { Respond 405 } }`;
- each arm is a **static** `call_contract("LiteralName", req[, capture(...)...])` — never dynamic;
- `requires idempotency` wraps the call in `if req.idempotency_key == "" { Respond 400 } else { <call> }`.

## How params lower to regexp

A pattern segment `:name` becomes a regex capture group `([^/]+)`; the whole pattern becomes an
anchored regex (`/todos/:id/done` → `^/todos/([^/]+)/done$`). `matches(req.path, "<re>")` gates the
route; each param is extracted positionally via `capture(req.path, "<re>", <i>)` (1-based), passed to
the handler as `Option[String]` (capture's return type — no `split`/`nth`/unwrap tricks). The
**middle-param** case `/accounts/:account_id/todos/:id` lowers to `capture(..., 1)` + `capture(..., 2)`
— the exact case `split`+`nth` could not express (the P3 regexp unlock).

## How idempotency guards lower

`requires idempotency` → a fail-closed `400` guard BEFORE the handler/effect:
`if req.idempotency_key == "" { Respond { status: 400, body: "missing idempotency-key" } } else { call_contract(...) }`.
The handler only runs (and only then can return `InvokeEffect`) when a key is present.

## Why there is no server route table

The route table IS the generated `Serve` contract (an `.ig` `match`/`if` tree), compiled and run as an
app capsule. `igniter-server` never sees patterns: it is Rack/Puma-like substrate that calls
`ServerApp::call`. Targets are static `call_contract` literals — there is no dynamic dispatch (Igniter
has none; `call_contract` resolves a literal name against the contract registry at compile time and
validates pure-ness + arity). The app names a logical effect `target` in its `Decision`; effect
authority stays host-owned (P3/earlier).

## Compile + test commands / pass counts

```text
$ cd igniter-compiler && cargo test --lib igweb::tests                    → 4 passed; 0 failed
$ cd igniter-compiler && cargo test --test igweb_lowering_tests           → 2 passed; 0 failed
$ cd igniter-compiler && cargo test --test regexp_typecheck_tests         → 8 passed; 0 failed (P3, intact)
$ cd igniter-vm       && cargo test --test regexp_runtime_tests           → 6 passed; 0 failed (P3, intact)
```

- **lib unit (4):** deterministic/byte-stable lowering + static `call_contract("TodoShow", …)` + regexp
  param lines + 404/405/400 present + no dynamic dispatch; malformed route → line-positioned error;
  bad `requires` clause → line-positioned error; nested middle-param lowers to two captures.
- **integration (2):** `generated_todo_project_compiles_clean` — lowers the 5-route Todo `.igweb`,
  writes `web_types.ig` + `handlers.ig` + generated `routes.ig` to a temp dir, runs the **real**
  multifile compile (via the `igniter_compiler` binary), asserts **no `OOF-RE1` and no `OOF-TY0`** (so
  the generated regexp patterns are valid AND the static `call_contract` arms typecheck — cross-module,
  pure, arity-matched); `nested_middle_param_lowers_two_captures` — the `/accounts/:account_id/todos/:id`
  shape (two positional captures).

## VM / request-decision proof (scoping, honest)

The generated `Serve` is composed entirely of primitives already proven to execute through the VM:
`matches`/`capture` (P3 `regexp_runtime_tests`, 6 green), `call_contract` (live `web_router` /
`advanced_logistics`), variant construction + `if`/`match` (live `web_router`). The full single-shot
VM dispatch of the *compiled `Serve` capsule* against a sample `Request` (load `.igapp` → dispatch →
assert `Decision`) belongs to the named next card **`LAB-IGNITER-WEB-ROUTING-ADAPTER-P5`** (run a
compiled IgWeb capsule behind `igniter-server::ServerApp`). This is a deliberate scope boundary, not a
hand-wave: P4 proves *lowering + real compile*; P5 proves *capsule-behind-server execution*.

## Acceptance — met

- [x] `.igweb` v0 parser/lowerer in the lab/tooling layer (`igniter-compiler/src/igweb.rs`), not server core.
- [x] Deterministic, line-positioned diagnostics (`IgwebError{line,message}`).
- [x] Generated `.ig` is explicit and inspectable.
- [x] Targets lower to static literal `call_contract`, never dynamic dispatch.
- [x] Path params lower through `stdlib.regexp.matches`/`capture`.
- [x] `/todos/:id` and `/todos/:id/done` represented without split/nth.
- [x] Effectful routes enforce the idempotency key (`400`) before any `InvokeEffect`.
- [x] 404 / 405 / 400 represented and tested.
- [x] Generated project compiles through the real multifile compiler (no OOF-RE1/OOF-TY0).
- [x] VM/request decision proof: compile-proven + primitive-VM-proven (P3); full capsule dispatch
      scoped to P5 ADAPTER (documented).
- [x] No `igniter-server` change; no parser/canon `.ig` syntax change; no DB/live/SparkCRM.

## Limitations (honest)

- Import plumbing (`WebTypes` / `TodoHandlers` module names) is a fixed v0 convention in the lowering,
  not parsed from `.igweb`. A real system would parameterize it; out of scope here.
- Literal route segments are assumed regex-safe (alphanumeric / `-` / `_`); a production lowering would
  escape regex metacharacters in literal segments.
- No resource grouping (deferred to `…-RESOURCE-SUGAR-P*`), no assets (separate readiness), no full
  capsule VM dispatch (P5 ADAPTER).

## Next cards

1. **`LAB-IGNITER-WEB-ROUTING-ADAPTER-P5`** — app-layer adapter running a compiled IgWeb capsule behind
   `igniter-server::ServerApp` (`Request` JSON → `dispatch(Serve)` → `Decision` → `ServerDecision`),
   still with no server-owned routing. Closes the VM/request execution proof end-to-end.
2. `LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P*` — optional `resource todos { ... }` grouping lowering to
   the same flat routes (only after flat routes proven — they now are).
3. `LAB-IGNITER-WEB-ASSETS-READINESS-P*` — static/raw responses, separate from routing.

---

*Lab implementation. Compiled 2026-06-18; 6 igweb tests + 14 P3 regexp tests green; generated Todo
project compiles clean through real multifile. No server/canon/DB change.*
