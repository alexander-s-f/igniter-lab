# LAB-TODOAPP-API-HOST-SURROGATE-ID-P36 - decouple Todo id from idempotency key

Status: TODO
Lane: TodoApp API / effect host / product hardening
Type: implementation after verify-first
Delegation code: OPUS-TODOAPP-API-HOST-SURROGATE-ID-P36
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The current create path is intentionally safe but product-awkward: the idempotency key still acts as
the Todo business key in parts of the flow. That was acceptable for early effect-host proof, but a
real API needs to separate:

- idempotency key: replay/correlation identity
- todo id: stable resource identity

P26 recommended a deterministic host-minted surrogate as the smallest safe step before a full
schema/adapter redesign.

## Goal

Implement a deterministic, replay-safe Todo id minted by the host/effect path, not by client input.

Candidate shape:

```text
todo_id = "todo_" + deterministic_hash(effect_target, account_id, idempotency_key)
```

The exact recipe is part of this card's verify-first work. It must be deterministic across replay,
not leak secrets, and not depend on request timing/randomness.

## Verify first

Read live write path before choosing the edit point:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- Todo write/effect tests under `server/igniter-web/tests`
- `runtime/igniter-machine/src` Postgres write intent/executor code
- `server/igniter-web` effect-host binding code
- P4/P8/P18/P26 Todo API proof docs and runbooks

Decide whether the surrogate belongs in the app-authored write intent, the web effect-host binding,
or the machine write executor. Prefer the narrowest layer that keeps product policy out of generic
machine code.

## Acceptance

- [ ] Create no longer stores the raw idempotency key as the Todo business id.
- [ ] Same idempotency key + same create request resolves to the same Todo id on replay.
- [ ] Same key + different body is rejected or reconciled according to existing idempotency policy; no silent second row.
- [ ] Done/update routes can target the minted id in tests.
- [ ] Receipts still use the idempotency key and remain auditable.
- [ ] Host logs/proof show the id recipe without exposing body values or secrets.
- [ ] Local/fake tests pass; real Postgres-gated tests compile or skip cleanly if no DSN.
- [ ] Docs/runbooks updated to stop teaching idempotency-key-as-id.
- [ ] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-host-surrogate-id-p36-v0.md
```

## Closed surfaces

- No random IDs in `.ig`.
- No DB sequence dependency unless explicitly justified after verify-first.
- No registry/global ID service.
- No object-body parsing unless P35 is already landed; otherwise keep body-shape changes out.
