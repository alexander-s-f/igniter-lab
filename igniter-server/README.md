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

## Current contents

- `src/protocol.rs` — tiny JSON-stable request/response/decision envelope.
- `src/lib.rs` — exports the protocol module.

## Next

Research card:

- `LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1`

That card should decide the durable app protocol before adding listener/runtime code.
