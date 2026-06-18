# Card: LAB-IGNITER-WEB-ROUTING-PURE-IG-P1 — pure Igniter web routing shape

**Lane:** standard / research-readiness
**Skill:** idd-agent-protocol
**Status:** CLOSED (research/readiness packet)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Delegation label:** OPUS-SERVER-WEB-DX-A
**Authority:** Lab research/design only. No canon claim. No server-core routing implementation.

## Why this card exists

`igniter-server` has intentionally stayed Rack/Puma-like: it owns wire transport,
concurrency, lifecycle, hot reload, middleware, and optional machine/effect host
bridging. It must not become the owner of app domains or route tables.

The next pressure point is developer DX: can a developer describe a normal web app
(Todo first) mostly in **pure Igniter** instead of writing Rust routing/domain code?

This card researches the framework layer that should sit **above** `igniter-server`:
a small Igniter web-routing vocabulary, analogous in spirit to Rails routes, but
compiled to the existing `ServerApp` protocol rather than embedded in the server.

## Core thesis to test

```text
HTTP wire -> igniter-server generic host -> IgWeb app adapter
  -> pure Igniter route decision / handler contracts
  -> ServerDecision JSON (Respond | Invoke | InvokeEffect)
  -> host executes through existing paths
```

The routing/product meaning belongs to the app/framework layer. The server remains
a generic mediator.

## Read first (verify-first, live code wins)

Do not trust stale cards. Check the live surface before proposing syntax.

- `igniter-server/README.md`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/examples/server_app_runner.rs`
- `lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md` if present
- `igniter-compiler/src/project.rs`
- `igniter-compiler/src/main.rs`
- `igniter-compiler/tests/project_mode_tests.rs`
- `igniter-compiler/tests/project_overlay_tests.rs`
- current `.ig` example apps under `igniter-lab/` (use `rg --files -g '*.ig'`)

## Research goal

Produce a compact readiness packet that answers:

> What is the smallest elegant **pure Igniter** routing shape that can express a
> Todo web app and compile down to the existing `igniter-server` protocol, without
> moving route tables or domain semantics into Rust server core?

This is not a request to build the full framework. It is a pressure-test and shape
selection card.

## Required research questions

1. **Layer boundary.**
   Where exactly does `IgWeb` live: pure `.ig` library, generated app adapter,
   Rust fixture adapter, or a mix? Which part is framework, which part is app?

2. **Route representation.**
   What is the smallest route vocabulary for v0?
   Consider exact routes, method dispatch, path params (`/todos/:id`), query params,
   and fallback routes. Prefer data/contract declarations over hidden config.

3. **Request algebra.**
   What shape should an Igniter contract receive?
   Example fields: method, path, segments, params, query, headers, body_json,
   correlation_id, idempotency_key. Name which fields are host-provided and which
   are app-derived.

4. **Response algebra.**
   What shape should pure Igniter return so it maps to `ServerDecision`?
   Separate `Respond` from `Invoke` / `InvokeEffect`. Do not let the app name
   `capability_id`, `operation`, or `scope`.

5. **Handler model.**
   Are handlers plain contracts? route-specific contracts? resource-style grouped
   contracts? What does the app author write for `Todo#index`, `Todo#create`,
   `Todo#show`, `Todo#complete`?

6. **Path params and parsing pressure.**
   Can current Igniter express route matching and param extraction elegantly today?
   If not, identify the exact missing primitive/stdlib helper. Do not paper over
   the gap with Rust routing.

7. **State model.**
   For Todo v0, what is pure request/response demo state versus real persistence?
   Distinguish in-memory fixture, Postgres capability, and future domain model.
   No DB/live in this card.

8. **Project/import DX.**
   How should a small web app be laid out on disk?
   Example: `app/routes.ig`, `app/todos/contracts.ig`, `app/web/request.ig`,
   `app/web/response.ig`. Check against current project mode/import behavior.

9. **Adapter contract.**
   What generic adapter is needed to run a compiled `.ig` web app behind
   `igniter-server`? Name the entry contract(s), input/output JSON shapes, and
   where overlay/unsaved-buffer support would matter for IDE.

10. **Rails analogy, without Rails baggage.**
    What should be inspired by Rails routing, and what must be rejected?
    Examples: declarative routes yes; controller global state no; implicit DB ORM no;
    server-owned config no.

11. **Failure taxonomy.**
    How should unknown route, method not allowed, bad JSON, validation failure,
    missing idempotency key, and handler refusal map to `ServerResponse` /
    `ServerDecision`?

12. **Next implementation slice.**
    Name one smallest safe P2 implementation card. It should likely be fixture-only:
    compile a tiny Todo `.ig` routing app and run it through a generic adapter,
    with no new server-core route table.

## Required Todo pressure fixture (design-level)

Use Todo because it forces common web cases without domain vendor noise:

```text
GET    /todos          -> list todos
POST   /todos          -> create todo (requires idempotency key if effectful)
GET    /todos/:id      -> show todo
POST   /todos/:id/done -> mark done / emit effect intent
GET    /health         -> direct Respond
GET    /missing        -> 404
POST   /todos/:id      -> 405 or explicit unsupported
```

The packet should sketch how these routes look in pure Igniter. Keep the sketch
small and honest; if current `.ig` syntax cannot express it cleanly, say so and
name the missing surface.

## Deliverable

Write:

`lab-docs/lang/lab-igniter-web-routing-pure-ig-p1-v0.md`

Include:

- executive summary;
- live surface inventory;
- proposed minimal routing vocabulary;
- Todo route sketch;
- request/response algebra;
- adapter shape;
- current-language gaps (if any);
- exact closed surfaces;
- recommended P2 card.

Then close this card with a compact report.

Optional: add a one-line pointer to the server wave checkpoint only if it already
exists and the pointer reduces discovery friction. Do not rewrite broad docs.

## Acceptance

- [ ] Packet answers all 12 research questions.
- [ ] Packet is grounded in live `igniter-server` and compiler/project-mode code.
- [ ] Todo pressure fixture is included.
- [ ] It keeps routing/domain meaning out of `igniter-server` core.
- [ ] It clearly separates framework vocabulary, app code, adapter, and host.
- [ ] It names exact language/runtime gaps instead of hiding them.
- [ ] It proposes one bounded P2 implementation card.
- [ ] No code changes unless only a tiny doc pointer is explicitly justified.
- [ ] No server-core route table.
- [ ] No Rust domain Todo app implementation.
- [ ] No DB, live listener, public network, credentials, SparkCRM, or vendor API.
- [ ] No canon claim for `.ig` routing syntax.

## Closed surfaces

- Do not implement a Rust router in `igniter-server`.
- Do not add a route config format to server core.
- Do not add web framework dependencies.
- Do not introduce canonical `.ig` web syntax.
- Do not modify compiler semantics in this card.
- Do not add Postgres or persistence.
- Do not use live network or public listener.
- Do not create SparkCRM-specific shapes.
- Do not move product/domain vocabulary into `igniter-server/src`.

## Suggested P2 shape (verify before accepting)

`LAB-IGNITER-WEB-ROUTING-TODO-P2` — fixture proof only:

- one tiny `.ig` Todo routing app;
- one generic host adapter that invokes a declared route-entry contract;
- tests for exact route, path param, method dispatch, not_found, method_not_allowed,
  idempotency propagation;
- no DB, no real effects, no server-core routing.

This P2 suggestion is not authority. The P1 packet may refine or reject it.

---

## Closing report — 2026-06-18

**Outcome:** Research/readiness packet delivered, answering all 12 questions, grounded in live code
(verified `igniter-server` protocol, `igniter-compiler/src/project.rs` project mode, the existing
`igniter-apps/web_router/` app + its `PRESSURE_REGISTRY.md`, and `igniter-stdlib`) — not card lore. No
code, no server-core router, no compiler change.

**Deliverable:** `lab-docs/lang/lab-igniter-web-routing-pure-ig-p1-v0.md`.

**Core finding:** a pure-Igniter web app = **a compiled `.ig` capsule whose entry contract maps
`Request → Decision` (a sealed variant)**, run behind the generic server by a small **app-layer**
adapter that dispatches the request record through the capsule (`IgniterMachine::dispatch`) and maps
the `Decision` variant → `ServerDecision`. Routing is a `match`/`if` in the entry contract; the adapter
holds no route table; the app never names `capability_id`/`operation`/`scope`. Layer split:
framework = pure `.ig` `Request`/`Decision` vocab; app = route + handler contracts (`Serve` entry);
adapter = generic Rust `ServerApp` (feature `machine`, app-layer, NOT server core); host = unchanged
`igniter-server`.

**The language ALREADY expresses HTTP routing + response composition** as a pure, exhaustive,
fail-closed core (proven by `web_router`: `HttpRequest → ContractResult variant → match → HttpResponse`,
`call_contract` pipeline, project-mode multifile compile, IDE overlay support).

**The one real gap (named, not papered over):** positional path-param capture (`/todos/:id`) —
**WR-P04 / OOF-TY1**: `split` doesn't infer `Collection[String]`; no `nth`/`substring`/`index_of`/regex;
Option destructuring unergonomic. v0 routes on exact path + method + host-tokenized segment arity +
first/last; multi-param positional routes are explicitly out until a small **language** card lands
(`split` typing + `nth` + Option match). Secondary: WR-P03 (no Map construction → host injects headers),
WR-P06 (use annotated computes), WR-P05 (no accept loop = exactly what the server provides). **None are
server gaps.**

**Recommended P2:** `LAB-IGNITER-WEB-ROUTING-TODO-P2` — fixture-only Todo `.ig` app + generic app-layer
`IgAppServer` adapter (`Serve(Request)->Decision` → `ServerDecision`); tests for exact route / method
405 / segment routing within the WR-P04 limit / 404 / idempotency propagation / no effect identity; no
DB, no real effects, no server-core route table. True `:id` capture is gated on a separate language
card (WR-P04), not a server change.

**Acceptance:** all boxes met — 12 questions answered; grounded in live server + compiler/project-mode;
Todo pressure fixture sketched; routing/domain kept out of server core; framework/app/adapter/host
cleanly separated; exact language gaps named with registry IDs (not hidden); one bounded P2 proposed;
no code change (doc only); no route table in core; no Rust Todo app; no DB/live/SparkCRM; no canon claim.
