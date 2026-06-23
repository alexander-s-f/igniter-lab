# LAB-TODOAPP-API-GENERATED-ID-READINESS-P26 - create ids beyond idempotency key

Status: CLOSED
Lane: TodoApp API / product semantics / readiness
Type: readiness packet
Delegation code: OPUS-TODOAPP-API-GENERATED-ID-READINESS-P26
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

Current v0 create uses the idempotency key as the business todo id:

```text
idempotency-key: create-123
todo.id = create-123
```

That was perfect for proving exactly-once write semantics, but it is not a natural product API. A real API
usually separates:

- idempotency key = request/effect dedup identity;
- business id = todo identity.

The design must preserve replay safety and authority separation.

## Goal

Decide the first safe path for generated or client-provided todo ids.

Compare at least:

1. client-provided `todo_id` in request body;
2. host-generated UUID in effect host;
3. app-generated deterministic id from idempotency key (current, documented v0);
4. Postgres-generated id (`DEFAULT gen_random_uuid()`), then receipt/readback;
5. two-step create: write request returns receipt only, follow-up read by correlation/business key.

## Verify first

Read:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/host_policy.md`
- `runtime/igniter-machine/src/postgres_write*.rs`
- `runtime/igniter-machine/tests/postgres*_write*`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`

Pay attention to what the write adapter returns today and whether it can surface a generated id.

## Questions to answer

1. Who owns business id generation in Igniter's authority model?
2. Can a host-generated id be deterministic under replay?
3. Does Postgres-generated id require a readback path or RETURNING support?
4. How does replay return the same business id without a second mutation?
5. How does conflict detection change if body contains a client id?
6. What is the smallest implementation after this readiness card?

## Acceptance

- [x] Packet chooses a recommended v1 id strategy.
- [x] Replay semantics are explicit: same idempotency key returns the same business result.
- [x] Conflict semantics are explicit: same key + different title/id refuses.
- [x] Host/app authority boundary preserved.
- [x] Necessary adapter changes, if any, are named.
- [x] Next implementation card is specific and bounded.
- [x] No production code changes except optional doc link.
- [x] `git diff --check` clean.

## Deliverable

Preferred:

```text
lab-docs/lang/lab-todoapp-api-generated-id-readiness-p26-v0.md
```

## Closing report

**Date:** 2026-06-23
**Deliverable:** [`lab-docs/lang/lab-todoapp-api-generated-id-readiness-p26-v0.md`](../../../../lab-docs/lang/lab-todoapp-api-generated-id-readiness-p26-v0.md)
**Outcome:** Readiness packet, doc-only. No production code changed; `git diff --check` clean.

### Recommendation (sequenced)

- **v1 (next, smallest, no dependency):** host-minted **deterministic surrogate** id —
  `id = "todo-" + blake3(idempotency_key)[..16]`, computed host-side. Replay-safe by pure determinism
  (no clock/random/readback), **zero adapter or schema change**, conflict unchanged. Decouples the row id
  from the literal request key within every closed surface.
- **v2 (after P25 object-body):** client-provided `id` in the JSON object body — natural REST shape;
  blocked on object-body parsing.
- **deferred:** Postgres-generated id (`gen_random_uuid()` + `RETURNING`) — needs a write-adapter
  refactor (the adapter currently does `RETURNING 1`, surfaces no id); out of this card's closed surface.

### Key live-code facts that drove it

- The real write adapter returns no id (`RETURNING 1` sentinel); business id = `intent.key` today.
- `effect_receipts.business_key` already exists → a readback path is available for any recorded id.
- `blake3` is already an `igniter-machine` dep → a deterministic surrogate needs no new crate.
- Conflict already keys on a blake3 digest of the whole intent body → a client id in the body gets 409
  on mismatch for free (the P19 mechanism).

### Authority boundary

Opaque surrogate id = host transport authority (sequence-equivalent); meaningful id value = app/client.
A host minting a *meaningful* id would be an authority leak (rejected), same principle that rejects
host-side body parsing (option 5).

### Next card

`LAB-TODOAPP-API-HOST-SURROGATE-ID-P27` — fully scoped in the packet (host-side write-key derivation
preferred to keep `.ig` hash-free; fake + real-PG tests for id≠key, replay-same-id-one-mutation,
same-key/different-title→409; API.md v0→v1 note). No client id, no PG-generated id, no schema change.

## Closed surfaces

- No DB schema migration in this card.
- No write adapter refactor in this card.
- No public API stability claim.

