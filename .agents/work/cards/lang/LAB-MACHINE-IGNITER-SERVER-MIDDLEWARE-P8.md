# Card: LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P8 — generic middleware wrappers

**Lane:** standard / implementation
**Skill:** idd-agent-protocol
**Status:** CLOSED (implementation proof)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab implementation in `igniter-server` only. Generic server substrate, no domain app.

## Why this card exists

P7 closed the extension-model readiness question: domain apps live outside `igniter-server` core,
while the server owns wire/concurrency/lifecycle/reload and composes generic wrapper middleware.
The next small implementation slice is to prove that middleware can extend the server without
becoming routing, app logic, effect authority, or a hidden mutable subsystem.

This card implements the **generic wrapper shape only**:

```text
request -> BodyLimit -> AuthToken -> Trace -> ServerApp::call -> response
```

Middleware must be ordinary `ServerApp` wrappers. No new server framework, no route table, no live IO.

## Read first

- `igniter-server/src/protocol.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/effect_host.rs`
- `igniter-server/README.md`
- `lab-docs/lang/lab-machine-igniter-server-extensions-readiness-p7-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-middleware-shape-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-app-stack-composition-v0.md`

## Goal

Add a small generic middleware module to `igniter-server` proving the P7 model:

- wrappers implement `ServerApp`;
- wrappers compose into one stack;
- `ReloadableApp` can wrap the outer stack;
- short-circuit middleware does not call the inner app;
- no wrapper injects effect identity or owns routing.

## Suggested implementation shape

Create `src/middleware.rs` with small wrapper structs:

1. `TraceApp<A>`
   - wraps any `A: ServerApp`;
   - adds deterministic observation headers or JSON fields without changing the decision kind;
   - should be immutable / `Send + Sync` friendly.

2. `AuthTokenApp<A>`
   - checks a configured header value (for lab, static token string is enough);
   - on failure returns `ServerDecision::Respond` with 401/403;
   - must **not** call `inner.call` on failure.

3. `BodyLimitApp<A>`
   - checks `ServerRequest.body.len()`;
   - returns 413 before inner on overflow;
   - no streaming/body parser scope.

Exact names may differ if live code suggests better names, but keep the shape small.

## Required tests

Add `tests/middleware_tests.rs` (or equivalent) proving:

1. **Sequential decoration:** wrappers compose and preserve inner app decisions when allowed.
2. **Short-circuit auth:** invalid token returns 401/403 and inner app call count remains 0.
3. **Short-circuit body limit:** oversized body returns 413 and inner app call count remains 0.
4. **Route-agnostic:** wrappers do not route by `(method, path)`; a changed inner app still owns routing.
5. **Effect identity not injectable:** middleware cannot add/change `capability_id`, `operation`, or `scope`
   because `ServerDecision` has no such fields; include a structural/unit assertion if useful.
6. **Reload wraps whole stack:** `ReloadableApp` around the composed stack preserves stack identity per
   in-flight request and swaps the whole stack for the next request.
7. **Send + Sync:** composed stack can be stored as `Arc<dyn ServerApp + Send + Sync>`.
8. **No hidden cross-request mutable state:** at least the provided wrappers work with `&self`; test no
   counter/cache is required for correctness.

Run:

```bash
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
```

## Deliverable

- implementation in `igniter-server/src/middleware.rs` (or a better generic module name);
- tests proving the required behavior;
- proof doc: `lab-docs/lang/lab-machine-igniter-server-middleware-p8-v0.md`;
- closing report in this card;
- README pointer only if it helps discovery.

## Acceptance

- [ ] Generic middleware wrappers implemented.
- [ ] Wrappers implement or preserve `ServerApp` composition; no special runtime.
- [ ] Auth/body-limit short-circuit before inner call.
- [ ] Trace/decorate behavior does not alter routing or effect authority.
- [ ] `ReloadableApp` wraps the entire composed stack; proof covers swap/in-flight behavior.
- [ ] No route table in middleware.
- [ ] No domain vocabulary (SparkCRM/VoIP/operator/etc.) in core middleware.
- [ ] No live network, public listener, DB, credentials, or vendor API.
- [ ] `cargo test` green.
- [ ] `cargo test --features machine` green.
- [ ] Proof doc and closing report written.

## Closed surfaces

- No domain app implementation.
- No dynamic plugin system.
- No assets protocol.
- No public listener.
- No live SparkCRM/vendor calls.
- No database.
- No credentials.
- No route config framework.
- No effect identity injection from app/middleware.
- No changes to `igniter-machine` semantics.

## Notes / guardrails

Middleware is a server-side **wrapper**, not a new authority plane. It may observe, reject, or decorate
requests/responses; it must not decide product routing, name effects, or own business policy. Product
meaning remains in the `ServerApp`; effect authority remains in the host/recipe bridge.

If the implementation wants more than these three wrappers, stop and narrow the card rather than
inventing a framework.

---

## Closing report — 2026-06-18

**Outcome:** Three generic zero-cost wrapper middlewares implemented and proven. Middleware extends the
server as ordinary `ServerApp` wrappers — no new runtime, no routing, no effect authority, no hidden
state. All guardrails held; `igniter-machine` untouched.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-middleware-p8-v0.md`.

**Implementation (`igniter-server/src/middleware.rs`, machine-free):**
- `TraceApp<A>` — ensures/propagates a deterministic correlation id (no clock/RNG), decorates `Respond`
  with `x-correlation-id`; decision kind unchanged; `Invoke`/`InvokeEffect` pass through verbatim.
- `AuthTokenApp<A>` — static bearer-token gate; `401` WITHOUT calling inner on failure.
- `BodyLimitApp<A>` — `413` for oversized serialized body BEFORE inner.
- `ServerAppExt` — `app.with_trace().with_auth(token).with_body_limit(n)` sugar → the card pipeline.
- All `&self`-pure, `Send + Sync`, `identity()` delegates to inner. No route table, no domain vocab
  (`rg` clean), no effect identity (structurally impossible on `ServerDecision`).

**Tests (`tests/middleware_tests.rs`, 8):** sequential decoration; auth short-circuit (PanicApp);
body-limit short-circuit (PanicApp); route-agnostic (same wrapper, different inner); effect identity
not injectable; `ReloadableApp` wraps the WHOLE stack (real loopback: TOKA→200 under v1, swap whole
stack, TOKA→401 under v2; in-flight snapshot keeps v1); composed stack `Send+Sync` + erasable to
`Arc<dyn ServerApp + Send + Sync>`; no hidden cross-request state (200/401/200).

**Exact commands + pass counts:**
```text
$ cd igniter-server && cargo test                    → 34 passed; 0 failed  (+8 middleware)
$ cd igniter-server && cargo test --features machine → 47 passed; 0 failed
```
`igniter-server` warning-clean both builds.

**Acceptance:** all boxes met. README pointer added. Kept to exactly the three wrappers (no framework).
