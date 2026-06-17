# Card: LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1 — Rack-like server app protocol

**Lane:** standard / architecture readiness · **Skill:** idd-agent-protocol  
**Status:** OPEN  
**Date opened:** 2026-06-17  
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
