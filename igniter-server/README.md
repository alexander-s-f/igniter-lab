# igniter-server

Lab-only server shell for Igniter.

This crate starts as a **protocol boundary**, not a framework:

- no hardcoded route table;
- no live listener yet;
- no SparkCRM-specific code;
- no Postgres/SparkCRM credentials;
- no hidden global machine;
- no claim that this is canon language surface.

The intended shape is Rack-like:

```text
wire transport
  -> ServerRequest
  -> Igniter server app protocol
  -> ServerDecision
  -> host executes the decision through igniter-machine
  -> ServerResponse
```

The server process owns infrastructure: listener, backend, clock, secrets, passport verification,
single-flight gate, executor registry, and orchestrator tick cadence. The **server app** owns product
meaning: routing, request classification, parameter extraction, validation, and which capsule/effect
intent should run.

In other words: `igniter-server` should not become a config-driven router with duplicated business
meaning. A minimal app may implement only the protocol directly. A richer app/framework may add
helpers, as long as it still compiles down to the same protocol.

## Three execution shapes (readiness P1)

The app's `ServerDecision` names WHICH proven host path to run — never HOW an effect runs:

- `Respond` — the app answers directly (health, 404, validation); the machine is never touched.
- `Invoke` — the host activates one capsule replica (`CoordinationHub::invoke`, one replica via
  `select_replica`).
- `InvokeEffect` *(planned next slice)* — the host runs the wire-to-effect bridge
  (`ingress::handle_effect` → `run_write_effect_atomic`): one replica → one atomic effect → receipt.

The decision carries a **logical target + input**, never a hand-built effect (`capability_id` /
`operation` / `scope`). The effect identity comes from the signed `ServiceRecipe` plus the host's
effect passport — a different authority than the serving passport. This is what keeps the P7/P8
exactly-one-effect guarantees: the app declares product meaning as data; the host owns transport,
authority, and the single execution path.

Authority split: routing/classification → the **app**; `target → pool` binding, listener, passports,
single-flight, executor registry → the **host (infra)**; `capsule_digest` / `entry_contract` /
duplicate policy → the **signed recipe (deploy)**.

See `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md`.

## Current contents

- `src/protocol.rs` — tiny JSON-stable request/response/decision envelope.
- `src/lib.rs` — exports the protocol module.

## Next

Research card (CLOSED, readiness): `LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1` — the durable
app protocol is decided (see the readiness doc above).

Implemented slice (CLOSED): `LAB-MACHINE-IGNITER-SERVER-BINARY-P2` — a local-loopback binary
(`src/bin/igniter-server.rs`) parses one request into `ServerRequest`, calls a fixture `ServerApp`
(`src/fixture.rs`), and the host (`src/host.rs`) executes the returned `ServerDecision`. `Respond` is
executed fully; `Invoke` / `InvokeEffect` are returned as observed protocol decisions (202). See
`lab-docs/lang/lab-machine-igniter-server-binary-p2-v0.md`.

Next implementation slice: `LAB-MACHINE-IGNITER-SERVER-EFFECT-P3` — execute `InvokeEffect` end-to-end
through the proven `igniter-machine` ingress / P7 atomic-effect path. Still no public listener, no web
framework, no SparkCRM, no DB/live.
