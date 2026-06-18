# lab-igniter-web-routing-adapter-p5-v0 — `.igweb` live behind igniter-server

**Card:** `LAB-IGNITER-WEB-ROUTING-ADAPTER-P5` · **Delegation:** `OPUS-IGWEB-ADAPTER-E`
**Status:** CLOSED (lab implementation proof) — a `.igweb`-authored app runs **live behind
`igniter-server`** over real loopback HTTP, with the server owning NO route table. The generated `.ig`
is lowered (P4), compiled, loaded, and dispatched through the existing compiler/machine surfaces — no
hand-coded route match substitutes for the proof.
**Authority:** Lab proof. No canon claim for `.igweb`; no server-core domain module; effect identity
stays host-owned.

## Contour proven (end to end)

```text
.igweb text
  → lower_igweb (igniter-compiler, P4)            → generated .ig: module AppRoutes, Serve(Request)->Decision
  → IgniterMachine::load_program([web_types, handlers, routes], "Serve")   (real multifile compile + register)
  → IgWebServerApp: ServerApp::call(req)
       → dispatch("Serve", { req: {method,path,body,correlation_id,idempotency_key} })   (async, block_on)
       → Decision variant JSON  { "__arm": "Respond"|"InvokeEffect", ...fields }
       → map → ServerDecision
  → host::serve_once (igniter-server, real 127.0.0.1 loopback)
  → ServerResponse / ServerDecision over the socket
```

One request/response trace (`igweb_app_route_param_roundtrip`):
```text
GET /todos/42  →  IgWebServerApp.call builds {req:{method:"GET", path:"/todos/42", ...}}
              →  Serve matches "^/todos/([^/]+)$", capture(...,1)="42", call_contract("TodoShow", req, Some("42"))
              →  Decision { __arm:"Respond", status:200, body: or_else(Some("42"),"none")="42" }
              →  ServerResponse 200 {"body":"42"}  →  HTTP/1.1 200 over the socket
```
The captured `id=42` reached the response **through the generated `stdlib.regexp` capture** — not a
Rust route match.

## Where the adapter lives (and why)

A **test/example harness**: `igniter-server/tests/igweb_adapter_tests.rs` (gated `#![cfg(feature =
"machine")]`). `IgWebServerApp { machine: IgniterMachine, rt: tokio::Runtime }` implements `ServerApp`.
It is NOT in `igniter-server/src`: the adapter needs `igniter_compiler` (to lower `.igweb`) and
`igniter_machine` (to run the capsule), and pulling those into the server lib would defeat the
machine-free default build. Per the card's guidance, the honest result is a **packaging seam proven as
a test**, not a premature public framework API. `igniter_compiler` is a **dev-dependency**;
`igniter_machine` comes via the existing optional `machine` feature. The default `igniter-server` lib
build stays **serde-only** (verified: `cargo tree -e normal` shows no machine/compiler/regex/tokio).

The adapter maps the `Decision` variant → `ServerDecision`:
- `Respond { status, body }` → `ServerResponse(status, {"body": body})`;
- `InvokeEffect { target, input, idempotency_key }` → `ServerDecision::InvokeEffect { target, input,
  correlation_id, idempotency_key }` — a **logical** target only; `host::execute` observes it as the
  P2 `202 deferred_to_p3` (effect execution is the already-proven P3 path, not re-proven here).

## Acceptance — met

1. ✓ `.igweb` lowered by `lower_igweb` in the proof path (`IgWebServerApp::build`).
2. ✓ Generated `.ig` compiled/loaded/invoked via `IgniterMachine::load_program` + `dispatch` — no
   hand-coded route match.
3. ✓ Real loopback `127.0.0.1` HTTP reaches the IgWeb-backed `ServerApp` (`host::serve_once`).
4. ✓ `GET /health` → `200` through the server host (`igweb_app_health_roundtrip`), not a direct call.
5. ✓ Route params from generated regexp/capture: `GET /todos/42` → body `"42"`
   (`igweb_app_route_param_roundtrip`).
6. ✓ Keyless mutating route → `400` before effect (`igweb_app_mutation_requires_idempotency_key`).
7. ✓ Keyed mutating route → `InvokeEffect` (observed `202`), logical `target: "todo-done"`,
   `idempotency_key: "k-9"`, and **no `capability_id`/`operation`/`scope`** in the decision
   (`igweb_app_mutation_emits_invoke_effect`).
8. ✓ Unknown path → `404`, wrong method → `405` (`igweb_app_unknown_and_method_refusals`).
9. ✓ `igniter-server` gained no route table / domain routing (`server_host_has_no_route_table`: a
   different app on the same host routes differently; routing lives in the generated capsule).
10. ✓ Default server build stays small — `igniter_compiler` is dev-only; `igniter_machine`/`tokio`
    stay behind the `machine` feature; default lib = serde only.
11. ✓ Existing P4 lowering tests still pass (2/2).
12. ✓ This doc states proven vs deferred.

## Test commands + pass counts

```text
$ cd igniter-server && cargo test --features machine --test igweb_adapter_tests → 6 passed; 0 failed
$ cd igniter-server && cargo test                                               → 49 passed; 0 failed (machine-free; adapter gated off)
$ cd igniter-server && cargo test --features machine                            → 68 passed; 0 failed (incl. +6 adapter)
$ cd igniter-compiler && cargo test --test igweb_lowering_tests                 → 2 passed; 0 failed (P4 intact)
$ cd igniter-server && cargo tree -e normal | grep -E 'machine|compiler|regex|tokio'  → (none) — default lib serde-only
```

**Adapter tests (6):** health roundtrip; route-param (id=42); keyless→400; keyed→InvokeEffect (202,
target+idem, no effect identity); unknown→404 + wrong-method→405; host-has-no-route-table.

## Default-build dependency check

`igniter-server`'s default (lib) build gained **no new normal dependency**: `igniter_compiler` is a
`[dev-dependencies]` entry (test-only), and `igniter_machine` + `tokio` remain optional behind the
`machine` feature. `cargo build` is unchanged and `cargo tree -e normal` confirms serde-only.

## What remains deferred (honest)

- **Real effect execution of `InvokeEffect`** — observed as `202` here; full commit-through-receipt is
  the already-proven P3 `MachineEffectHost`/`serve_once_effect` path (a fake-effect wiring is optional
  per the card and not added, to keep the adapter narrow).
- **A public adapter API** — this is a test/packaging seam, not a shipped `IgWebServerApp` in
  `igniter-server/src`. Graduating it (and parameterizing module/import names) is future work.
- Dialect registry/tooling (P0 `LAB-IGNITER-DIALECT-REGISTRY-P1`), resource-grouping sugar, source
  maps, assets/raw responses, real domain apps, and live effect hosts — all out of scope.

## Closed surfaces (held)

No canon `.igweb` claim · no dialect registry · no live network beyond loopback · no SparkCRM/live
DB/credentials · no server-core domain module · no server route table/config router · no effect
identity (`capability_id`/`operation`/`scope`) in app decisions.

---

*Lab implementation proof. Compiled 2026-06-18; 6 adapter + 2 P4 lowering tests green; default
`igniter-server` build serde-only. `.igweb` is the first Projection Dialect (P0) proven live behind the
server.*
