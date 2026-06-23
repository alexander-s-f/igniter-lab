# LAB-TODOAPP-API-HOST-SURROGATE-ID-P36 — host-minted surrogate Todo id

**Date:** 2026-06-23
**Type:** implementation after verify-first
**Delegation:** OPUS-TODOAPP-API-HOST-SURROGATE-ID-P36
**Status:** landed (this doc is the proof packet)
**Authority note:** lab evidence only — igniter-lang is canon; a lab proof does not create canon authority.

## TL;DR

A Todo's **resource id** is now a host-minted deterministic **surrogate**, separate from the
idempotency key:

```text
req.surrogate_id  =  blake3(method ␟ path ␟ idempotency_key)[..32]      (host, igniter-web)
todo_id           =  "todo_" + req.surrogate_id                         (.ig product prefix)
```

- The host (`igniter-web`) mints the opaque digest and crosses it to `.ig` as `req.surrogate_id` —
  the **same host-computed-signal pattern as `body_kind`** (P18).
- `.ig` keeps the product decision: the create command contract sets the business `key` to
  `concat("todo_", surrogate_id)`. **`.ig` does no hashing** (it has no hash builtin — see *Deviations*).
- The effect idempotency key stays the request's (`InvokeEffect { idempotency_key: req.idempotency_key }`)
  — receipts, dedup, and replay-conflict detection are unchanged and still key on it.
- Generic machine/server code (`igniter-machine`, `igniter-server`) is **untouched**.

## Authority split (the reason for the chosen layer)

The card asked: app-authored intent, web effect-host binding, or machine write executor — pick the
narrowest layer that keeps product policy out of generic machine code.

| Concern | Owner | Where |
| --- | --- | --- |
| The id **recipe** (which fields, hashing, framing) | **web host** | `igniter_web::surrogate_id` + `build_request_input` (`server/igniter-web/src/lib.rs`) |
| The **decision** to use the surrogate as the business key, and the `todo_` product prefix | **app (`.ig`)** | `BuildCreateTodoIntent` (`todo_handlers.ig`) |
| The effect identity (idempotency key, dedup, receipts) | host/machine | unchanged |
| Generic write intent shape, allowlists, adapter, SQL | machine | **unchanged** |

This is narrower than rewriting `intent.key` inside the effect-path executor: the minted key is set at
**intent construction**, so every executor backend (effect-host fake, postgres fake, real Tokio adapter)
sees it uniformly, and the product prefix never leaks into the generic prelude field or machine code.

## The recipe (verified properties)

`surrogate_id(method, path, idempotency_key)` — `server/igniter-web/src/lib.rs`:

- **Deterministic / replay-safe** — pure function of request identity; no clock, no randomness, no
  readback. Same key + same request ⇒ same id on replay (proven on real Postgres).
- **Leaks no secrets / no body** — the title and any bearer token are **not** inputs; blake3 is one-way,
  so the idempotency key is not recoverable from the id (unit test `does_not_embed_the_idempotency_key`).
- **Namespaced** — `path` carries the account scope and resource (`/accounts/<id>/todos`) and `method`
  identifies the effect; `0x1f` unit-separator framing prevents concatenation collisions. The same key on
  a different account/route mints a different id (unit test `namespaced_by_account_route_and_key`).
- **Empty key ⇒ empty surrogate** — a keyless mutating request is already refused by the route-level
  `requires idempotency` 400 guard *before* intent construction, so no id is minted.
- 128-bit (32 hex) digest — ample collision resistance for a resource id.

The card's candidate `deterministic_hash(effect_target, account_id, idempotency_key)` is realized
faithfully: `path` supplies `account_id` + resource, `method`+`path` supply `effect_target`.

## What changed

| File | Change |
| --- | --- |
| `lang/igniter-compiler/src/igweb.rs` | `Request` prelude type gains `surrogate_id : String` (mirrors the `body_kind` precedent). |
| `server/igniter-web/Cargo.toml` | `blake3 = "1.5"` (already in the workspace via igniter-machine; the recipe is host policy, so it lives here). |
| `server/igniter-web/src/lib.rs` | `pub fn surrogate_id(...)`; `build_request_input` computes + crosses `req.surrogate_id`. 4 recipe unit tests. |
| `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig` | `BuildCreateTodoIntent` takes `surrogate_id`, sets `key: concat("todo_", surrogate_id)`; `AccountTodoCreate` passes `req.surrogate_id` and sets `InvokeEffect { idempotency_key: req.idempotency_key }` (was `intent.key`). Done path unchanged. |
| `tests/todo_postgres_api_write_tests.rs` | Assertions updated to the surrogate key; new `done_targets_the_minted_surrogate_id`. |
| `tests/todo_postgres_local_e2e_tests.rs` | Real-PG assertions read business rows by the minted id; subprocess e2e proves the live binary stores under `todo_<digest>` and **not** under the idempotency key. |
| `examples/todo_postgres_app/API.md`, `RUNBOOK.md` | Stop teaching idempotency-key-as-id; document the surrogate recipe. |

## Evidence

- `cargo test --features machine` (igniter-web): **all suites green** (lib 72, effect-host 11, api-write 5, …).
- `cargo test` (igniter-compiler): **green** (prelude change safe; no snapshot break).
- `IGNITER_TODO_PG_DSN=… cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests -- --test-threads=1`: **12 passed**, including:
  - `subprocess_product_command_read_write_replay_e2e` — the **real `igweb-serve` binary** over a loopback socket writes the business row under `todo_<digest>`; a query by the raw idempotency key returns **0 rows** (`P36: the idempotency key is NOT stored as a Todo id`); replay = exactly one row + one receipt.
  - `local_write_creates_business_row_and_receipt` — row stored under the surrogate; machine receipt still keyed by the idempotency key.
  - `done_targets_the_minted_surrogate_id` (api-write) — Done's intent key == the minted create id.
- `git diff --check`: clean.

## Acceptance (card)

- [x] Create no longer stores the raw idempotency key as the Todo business id.
- [x] Same idempotency key + same create request resolves to the same Todo id on replay.
- [x] Same key + different body is rejected/reconciled (existing ingress dedup + write-receipt digest, unchanged); no silent second row.
- [x] Done/update routes can target the minted id (`done_targets_the_minted_surrogate_id`; real-PG done path).
- [x] Receipts still use the idempotency key and remain auditable (machine receipt + PG `effect_receipts.idempotency_key`).
- [x] Host logs/proof show the id recipe without exposing body values or secrets (recipe takes no body/secret; blake3 one-way).
- [x] Local/fake tests pass; real Postgres-gated tests pass with a DSN (and skip cleanly without).
- [x] Docs/runbooks updated to stop teaching idempotency-key-as-id.
- [x] `git diff --check` clean.

## Closed surfaces honoured

- No random ids in `.ig` (the host digest is deterministic; `.ig` only prefixes).
- No DB sequence dependency.
- No registry/global id service.
- No object-body parsing (P25 not landed; the title is still a JSON string literal).

## Deviations from the P26 readiness packet (deliberate)

1. **Recipe inputs** — P26 suggested `blake3(idempotency_key)`; this uses `(method, path,
   idempotency_key)` to namespace by account/route per the card's `(effect_target, account_id, …)` and to
   be robust against a key reused across routes.
2. **Mint point** — P26 leaned toward rewriting the write key in the effect-path executor and flagged the
   app-side option as "blocked: `.ig` has no hash stdlib." This lands the mint at the **request-input
   boundary** (`req.surrogate_id`), so the host supplies the digest and `.ig` owns the key decision +
   prefix with **zero `.ig` hashing** — resolving P26's blocker without a language change, and keeping the
   business-key decision in the product layer.
3. **Prefix** — `todo_` (underscore), matching the card's candidate shape (P26 wrote `todo-`).

## Honest limits

- The minted id is derived from request identity, not a server sequence or random UUID — a deliberate v0
  closed surface. Client-provided ids and DB-generated ids remain deferred (P26 v2/option-4).
- The DSN-gated e2e suite must run with `--test-threads=1` (pre-existing: several tests share an account
  id and `prepare()` does delete+insert; documented in API.md). Not introduced by this card.
