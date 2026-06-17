# Card: LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1 — Rack-like server app protocol

**Lane:** standard / architecture readiness · **Skill:** idd-agent-protocol  
**Status:** CLOSED (readiness)
**Date opened:** 2026-06-17  
**Date closed:** 2026-06-17
**Authority:** Lab-only. No canon claim. No live listener. No SparkCRM-specific implementation.

## Why this card exists

`igniter-machine` now has the hard substrate: ingress, serving loop, duplicate policy, replica
selection, atomic effect gate, Postgres read/write, receipts, recovery, orchestrator, observability.

The next risk is architectural drift: making `igniter-server` a config-driven router that hardcodes
paths and parameters outside the app. That would split business meaning between server config and
Igniter contracts.

This card researches the opposite shape: **Rack-like protocol first**.

```text
wire transport
  -> ServerRequest
  -> server app protocol
  -> ServerDecision
  -> host executes through igniter-machine
  -> ServerResponse
```

The server owns infrastructure. The app owns routing/product meaning.

## Seed scaffold

Read first:

- `igniter-server/README.md`
- `igniter-server/src/protocol.rs`
- `igniter-machine/src/ingress.rs`
- `igniter-machine/src/serving_loop.rs`
- `igniter-machine/src/coordination.rs`
- `igniter-machine/src/single_flight.rs`
- `lab-docs/lang/lab-machine-deployment-topology-p1-v0.md`
- `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7.md`
- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8.md`

## Research questions

Answer these before code beyond the seed protocol:

1. What is the smallest durable `ServerRequest` / `ServerResponse` shape?
2. Should the app protocol return direct `response`, `invoke`, `effect_intent`, or a richer enum?
3. Where does path routing live if not in server config? Contract? Middleware contract? App adapter?
4. How does middleware compose without becoming hidden mutable server state?
5. How does a minimal app implement the protocol with no framework?
6. How can a richer framework compile down to the same protocol?
7. How does hot reload work for app protocol artifacts?
8. What can be hot-reloaded safely: config, capsule digest, recipe, executor config, binary?
9. How does the protocol preserve P7/P8 guarantees: one selected replica, one atomic effect?
10. What is the first implementation slice after readiness?

## Guardrails

- Do not add a live listener in this card.
- Do not add server route config as the source of product meaning.
- Do not hardcode SparkCRM paths or tables.
- Do not introduce a web framework dependency.
- Do not change `igniter-machine` semantics.
- Do not claim language canon.

## Expected deliverable

- `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md`
- Closing report in this card.
- Optional updates to `igniter-server/README.md` if the readiness decision changes the seed framing.

## Likely next implementation route

`LAB-MACHINE-IGNITER-SERVER-BINARY-P2` — local loopback binary that accepts one request, converts it
to `ServerRequest`, calls a fixture app implementing the protocol, and returns `ServerResponse`.

Still no SparkCRM live, no public listener, no hardcoded route table as product authority.

---

## Closing report — 2026-06-17

**Outcome:** READINESS settled. Deliverable doc written; all 10 research questions answered grounded
in the live surface. No code beyond the seed protocol. All guardrails held (no listener, no web
framework dep, no SparkCRM, no DB/live, no `igniter-machine` semantic change, no canon claim).

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md`.

**Central finding.** Two execution contours are already proven — wire-to-effect (`ingress::
handle_effect`, P7/P8) and frame-binding (`FrameBindingBridge`, UI). Both follow one discipline:
*the caller declares product meaning as DATA; the host executes it through a fixed proven path.*
Today routing is the exception — it lives as **server config** (`IngressRouter.routes: path→pool_id`,
`ingress.rs:62-71`), which IS the drift the card names. The Rack-like protocol relocates routing into
a `ServerApp`, re-shaping WHO DECIDES routing without re-shaping HOW an effect runs.

**Answers (condensed):**
1. Keep the seeded `ServerRequest`/`ServerResponse` — JSON-stable (`BTreeMap`), `correlation_id`/
   `idempotency_key` first-class; duplicate key stays in headers (it's recipe-named business policy).
2. A small CLOSED enum mirroring the three proven host shapes: `Respond` | `Invoke` | **`InvokeEffect`**
   (add in P2). **Reject free-form `effect_intent`** — the app must never name `capability_id`/`scope`;
   the effect identity comes from the signed recipe + host `EffectBridgeConfig` (double authority).
3. Three authorities: routing/classification → `ServerApp` (product); `target→pool` + transport +
   single-flight → host (topology); `capsule_digest`/`entry_contract`/duplicate policy → signed recipe.
4. App middleware = pure `ServerApp` decorators, zero mutable state; authority + idempotency stay as
   fixed host pipeline steps (unskippable). "Stateful middleware" = a fact read, not in-RAM state.
5. Minimal app = ~20-line Rust `match` on `(method, path)` → `ServerDecision`, deps = protocol only.
6. A framework is a library above `ServerApp`; correctness gate = byte-identical decision-equality
   (same discipline as `ViewArtifact ≡ hand-written`).
7. Hot reload = atomic `Arc<ArcSwap<dyn ServerApp>>` swap between requests; safe because the app is
   stateless (state is facts); touches no lock map / receipts / in-flight effect.
8. Tiered: app routing (free) → recipe re-sign (proven) → executor/secrets/keys (gated) → binary
   (restart, crash-safe via `boot()`) → receipts/idempotency (never rewritten).
9. P7/P8 preserved by construction: the app has no effect API; the host runs the unchanged
   `serve_once_effect` path → one replica (`select_replica`), one atomic effect
   (`run_write_effect_atomic`). Proof obligation for P2 = byte-identical facts vs direct ingress.
10. Next slice = `LAB-MACHINE-IGNITER-SERVER-BINARY-P2` (loopback binary + fixture app + equality proof).

**Optional README correction:** APPLIED — `igniter-server/README.md` updated to state the three
execution shapes and the routing-authority split (the readiness decision refined the seed framing).

**Recommended protocol delta (for P2, NOT applied here):** rename `Invoke{contract}` → `Invoke{target}`;
add `InvokeEffect{target,input,correlation_id}` (no `capability_id`/`scope`); hold app behind
`Arc<ArcSwap<dyn ServerApp>>`. See doc §"Recommended protocol delta".
