# LAB-MACHINE / IgWeb Routing Adapter P5

Status: CLOSED (lab implementation proof)  
Lane: standard / lab implementation proof  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGWEB-ADAPTER-E  
Skill: idd-agent-protocol  

## Intent

Prove `.igweb` live behind `igniter-server` without making the server own application routing or domain vocabulary.

P4 proved:

```text
.igweb text -> deterministic generated .ig Serve(Request)->Decision -> compiler accepts
```

P5 should prove the next hop:

```text
.igweb text
  -> P4 lower_igweb generated .ig
  -> compiled/loaded Serve capsule or equivalent lab app artifact
  -> app-layer ServerApp adapter
  -> host::serve_once loopback HTTP
  -> ServerDecision / ServerResponse
```

The server remains Rack/Puma-like infrastructure. The `.igweb` adapter is an application/runtime adapter, not a server route table and not a domain module inside core server.

## Authority

This is a lab implementation proof inside `igniter-lab`.

Allowed:
- Add a narrow IgWeb adapter/proof surface if needed.
- Add tests/examples/fixtures/docs/cards.
- Add optional feature-gated dependencies only if verify-first shows they are necessary and the default server build stays small.

Not allowed:
- No canon language claim for `.igweb`.
- No dialect registry implementation.
- No live network beyond loopback.
- No SparkCRM/live DB/credentials.
- No server-core domain module.
- No server route table or config router.
- No dynamic effect identity in app decisions (`capability_id` / `operation` / `scope` stay host-owned).

## Verify First

Read and ground the implementation in live code before editing:

- `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `igniter-compiler/src/igweb.rs`
- `igniter-compiler/tests/igweb_lowering_tests.rs`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/effect_host.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/Cargo.toml`
- `igniter-server/tests/effect_machine_tests.rs`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/examples/server_app_runner.rs`

Live code beats this card if signatures drift.

## Design Target

Build the smallest adapter that makes an IgWeb-authored app observable through the existing server protocol.

Preferred shape:

```rust
// Exact names are not mandatory.
struct IgWebServerApp { ... }

impl ServerApp for IgWebServerApp {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        // serialize request into the generated Serve input,
        // invoke the compiled generated .ig artifact,
        // map the returned Decision JSON/value into ServerDecision.
    }
}
```

The adapter may live:
- in `igniter-server` behind an explicit feature, if dependency boundaries remain clean; or
- in an integration test/example harness, if putting compiler/machine dependencies into `igniter-server` would be too broad for P5.

Do not force a beautiful public API if the honest result is "test-only proof plus a packaging seam". The core requirement is live proof of the contour, not premature framework shape.

## Required Behavior

Use P4 lowering. Do not hand-write the generated `.ig` for the main proof.

The fixture should cover at least:

```text
GET  /health             -> Respond 200
GET  /todos/42           -> Respond 200 or Invoke target proving param id=42
POST /todos/42/done      -> keyless 400
POST /todos/42/done      -> with idempotency-key => InvokeEffect target "todo-done"
GET  /missing            -> 404
POST /health             -> 405
```

If P5 stays protocol-only, `InvokeEffect` may be observed as the existing `202 deferred` response through `host::execute`.

If using the `machine` feature is small and clean, add one fake-effect proof through `MachineEffectHost` / `serve_once_effect` that commits a fake receipt. Do not make that mandatory if it bloats the adapter; P3/P4 server effect machinery is already proven.

## Acceptance

1. `.igweb` source is lowered by `lower_igweb` in the test/proof path.
2. The generated `.ig` is compiled/loaded/invoked through existing compiler/VM/machine surfaces; no hand-coded route match substitutes for the main proof.
3. A real loopback `127.0.0.1` HTTP request reaches the IgWeb-backed `ServerApp`.
4. `GET /health` returns `200` through the server host, not by calling the adapter directly.
5. Route params are extracted from the generated regexp/capture logic (`/todos/42` proves `id=42` in the response or decision payload).
6. Keyless mutating route returns `400` before effect dispatch.
7. Keyed mutating route produces `InvokeEffect` with logical target and idempotency key, and does not expose `capability_id` / `operation` / `scope` in the app decision.
8. Unknown path and wrong method produce deterministic `404` / `405`.
9. `igniter-server` does not gain a route table or domain-specific routing logic.
10. Default `igniter-server` build remains small; any new heavy dependency is feature-gated or confined to tests/examples.
11. Existing P4 lowering tests still pass.
12. Proof doc states exactly what is now proven and what remains deferred.

## Suggested Tests

Names are illustrative:

- `igweb_app_health_roundtrip`
- `igweb_app_route_param_roundtrip`
- `igweb_app_mutation_requires_idempotency_key`
- `igweb_app_mutation_emits_invoke_effect`
- `igweb_app_unknown_and_method_refusals`
- `server_host_has_no_route_table`
- `default_server_build_stays_machine_free`

Suggested commands, adjusted to the actual files created:

```bash
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
cd igniter-compiler && cargo test --test igweb_lowering_tests
```

If a new feature is introduced, also run its exact feature combination.

## Deliverables

- Implementation/test files for the adapter proof.
- `lab-docs/lang/lab-igniter-web-routing-adapter-p5-v0.md`
- Closing report in this card.
- Thin pointer from P4 proof doc to P5 result.

## Closing Report Template

When done, report:

- Where the adapter lives and why.
- Exact contour proven, with one short request/response trace.
- Exact test commands and pass counts.
- Whether default `igniter-server` gained any new normal dependency.
- What remains deferred: dialect registry, richer web framework, source maps, assets, domain apps, live effect hosts.

---

## Closing report — 2026-06-18

**Where the adapter lives & why:** `igniter-server/tests/igweb_adapter_tests.rs` (gated
`#![cfg(feature="machine")]`) — a test/packaging seam, NOT `igniter-server/src`. `IgWebServerApp {
machine: IgniterMachine, rt: tokio::Runtime }` implements `ServerApp`. It needs `igniter_compiler`
(lower `.igweb`) + `igniter_machine` (run capsule); putting those in the server lib would break the
machine-free default. So `igniter_compiler` is a **dev-dependency**; `igniter_machine`/`tokio` stay
behind the optional `machine` feature. Default lib build = serde only (verified).

**Exact contour proven:** `.igweb` → `lower_igweb` (P4) → `IgniterMachine::load_program([web_types,
handlers, routes], "Serve")` (real multifile compile + register) → `ServerApp::call` builds the Serve
`Request` input → `block_on(dispatch("Serve", …))` → `Decision` variant JSON (`{__arm:"Respond"|
"InvokeEffect", …}`) → mapped to `ServerDecision` → `host::serve_once` real loopback.
Trace: `GET /todos/42` → Serve matches `^/todos/([^/]+)$`, `capture(...,1)="42"`,
`call_contract("TodoShow", req, Some("42"))` → `Respond{200, body:or_else(Some("42"))="42"}` → HTTP 200
`{"body":"42"}`. The id flowed through the generated regexp capture, not a Rust match.

**Commands + counts:**
```text
cargo test --features machine --test igweb_adapter_tests → 6 passed
cargo test                                               → 49 passed (machine-free; adapter gated off)
cargo test --features machine                            → 68 passed (+6 adapter)
(igniter-compiler) cargo test --test igweb_lowering_tests → 2 passed (P4 intact)
cargo tree -e normal | grep machine|compiler|regex|tokio → none (default lib serde-only)
```
Adapter tests: health roundtrip; route-param id=42; keyless→400; keyed→InvokeEffect (202, target
"todo-done", idem "k-9", no capability_id/scope); unknown→404 + wrong-method→405; host-has-no-route-table.

**Default `igniter-server` new normal dependency:** NONE. `igniter_compiler` is dev-only;
`igniter_machine`/`tokio` stay feature-gated; `cargo build` unchanged, `cargo tree -e normal` serde-only.

**Deferred:** real `InvokeEffect` commit (observed 202; full path = proven P3); a public adapter API
(this is a test/seam); dialect registry; resource sugar; source maps; assets/raw responses; domain
apps; live effect hosts.

**Acceptance:** all 12 boxes met (see deliverable `lab-docs/lang/lab-igniter-web-routing-adapter-p5-v0.md`).
Thin pointer added from the P4 proof doc to this P5 result. No `igniter-server` route table / domain
module; no canon claim; loopback only.

