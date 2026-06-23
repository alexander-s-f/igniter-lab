# LAB-TODOAPP-API-GENERATED-ID-READINESS-P26 — readiness packet

**Date:** 2026-06-23
**Type:** readiness packet (no production code changed)
**Question:** where should a Todo's *business id* come from, once it is no longer just the idempotency key?

## TL;DR recommendation

Sequence, smallest-safe-first:

1. **v1 (next, smallest, no dependency): host-minted deterministic surrogate id** —
   `id = "todo-" + blake3(idempotency_key)[..16]`, computed host-side in the effect path and used as the
   business key. Replay-safe by pure determinism (no clock/no random/no readback), **zero adapter or
   schema change**, conflict semantics unchanged. Decouples the row id from the *literal* request key
   (the product complaint) while staying inside every closed surface of this card.
2. **v2 (after [P25 object-body](lab-todoapp-api-create-object-body-readiness-p25-v0.md) lands):
   client-provided `id`** in the JSON object body — the natural REST shape; authority for the id *value*
   moves to the client/app. Needs object-body parsing first, so it is blocked on P25.
3. **deferred: Postgres-generated id** (`DEFAULT gen_random_uuid()` + `RETURNING`) — the most "real"
   server-sequence model, but requires a write-adapter refactor (capture the generated id, store it in
   `effect_receipts.business_key`, read it back on replay). Explicitly out of this card's closed surface.

v0 (id == idempotency key) stays the documented baseline until v1 ships.

## Live-code constraints (verified 2026-06-23)

| Fact | Source | Implication |
| --- | --- | --- |
| The write adapter returns only `Committed`/`DuplicateKey`/… — **no id** | `runtime/igniter-machine/src/postgres_real.rs::transact` (SQL ends `… RETURNING 1`, a sentinel) | A PG-generated id is **not** surfaced today → option 4 needs an adapter change. |
| Business id today = `intent.key` | `postgres_write.rs` (`$5 = business key`, `business_key = intent.key`); app sets `key: idempotency_key` in `BuildCreateTodoIntent` (`todo_handlers.ig`) | Splitting id from the dedup key means setting `intent.key` (or the host write key) to something other than the request key. |
| `effect_receipts(idempotency_key PK, correlation_id, target, business_key)` already stores `business_key` | `postgres_real.rs` CTE + DDL in `tests/todo_postgres_local_e2e_tests.rs` | A **readback path already exists** (`PostgresWriteReceiptResolver::lookup_effect_receipt` → `Found { key }`) — so any id recorded at first write can be returned on replay without a 2nd mutation. |
| Create success returns `result.key` to the client | `postgres_write.rs` `EffectOutcome::succeeded({committed,duplicate,target,key,correlation_id})` → ingress `{status:"committed", result}` | The id the client sees is `result.key`; changing the id strategy changes this field only. |
| Conflict is decided on a blake3 digest of the **whole** intent body | `runtime/igniter-machine/src/ingress.rs::decide_duplicate` (`variant_payload=false`) | If a client id lives in the body, "same key + different id" is already a **409** with no new machinery (the P19 mechanism). |
| `blake3` is already a dependency of `igniter-machine` | `runtime/igniter-machine/Cargo.toml` (`blake3 = "1.5"`, used by `write.rs::payload_digest`) | A deterministic surrogate id needs **no new crate** (no `uuid` dep required). |
| Reads run fresh by default; replay is correlation-opt-in | API.md "Reads & freshness" (P23) | A two-step create + readback (option 5) would read fresh — but adds round-trips/routes. |

## Options compared

| # | Strategy | Replay-safe? | Authority | Code/schema cost | Verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | **Client-provided `id` in body** | Yes — id is in the payload; same key+same body → dedup; same key+different id → 409 | Client/app owns id **value** (a meaningful product id) | Needs object-body (P25) + a host write-key = body.id wiring | **v2** — best product shape, blocked on P25 |
| 2 | **Host-minted deterministic surrogate** `blake3(idem_key)` | Yes — pure function of the dedup key; replay recomputes identical, machine receipt blocks 2nd write | Host mints an **opaque** surrogate PK (transport/identity, no product meaning) — app still owns title/account via the intent | Small host-side derivation; **no adapter/schema change**; no readback | **v1 (recommended next)** |
| 3 | **App-generated = idempotency key** (current v0) | Yes — trivially | App, but id == request key (not natural) | Zero | Documented baseline until v1 |
| 4 | **Postgres-generated** (`gen_random_uuid()` + `RETURNING`) | Only with readback: capture generated id, store in `effect_receipts.business_key`, replay reads it back | Host/DB owns surrogate (clean) | **Adapter refactor** (`RETURNING <id>`, propagate through `PostgresWriteResult`, replay readback) — closed surface here | **Deferred** to its own card |
| 5 | **Two-step: write returns receipt only; follow-up read by correlation/business key** | Yes — id is read back, not minted in the write | Split cleanly; client resolves id via a read | New read-by-correlation route + a client round-trip; heavier API | Rejected for v1 (more surface, worse DX) |

## Questions answered

1. **Who owns business-id generation?** Split by *meaning*: an **opaque surrogate PK** is effect/storage
   identity → the **host** may mint it (like a DB sequence); a **meaningful** id (human-facing slug,
   client correlation) is product meaning → the **app/client**. v1 (host surrogate) and v2 (client id)
   sit on the correct sides of that line; a host minting a *meaningful* id would be an authority leak
   (rejected — same reason this card rejects host-side body parsing).
2. **Can a host-generated id be deterministic under replay?** Yes — derive it as a pure function of the
   idempotency key (`blake3(idem_key)`), no clock/no random. Replay recomputes the identical id, and the
   machine receipt already prevents a second mutation, so no readback is needed for v1.
3. **Does a Postgres-generated id require a readback / RETURNING?** Yes. The adapter currently does
   `RETURNING 1` (a presence sentinel), not `RETURNING <id>`, and `PostgresWriteResult` carries no id
   field. Option 4 needs: `RETURNING <key_column>`, a new id-bearing result variant, persistence into
   `effect_receipts.business_key` at first write, and a replay path that reads it back.
4. **How does replay return the same business id without a second mutation?**
   - v1/v3 (deterministic): recompute the same id; the machine receipt replays the cached
     `EffectOutcome.result` (which carries `key`) — no executor re-entry.
   - v4 (PG-generated): the first write records the generated id in `effect_receipts.business_key`;
     replay (machine-receipt or PG `ON CONFLICT (idempotency_key) DO NOTHING`) reads it back.
5. **How does conflict detection change if the body carries a client id (v2)?** It does not need new
   machinery: the id is part of the intent body, so "same idempotency key + different id (or title)"
   yields a different blake3 payload digest → **409** at the ingress dedup gate (the P19 path), before
   any mutation. "Same key + same body (incl. id)" → dedup replay → same id.
6. **Smallest implementation after this packet?** v1 (see next card below).

## Authority boundary (explicit)

- **App owns**: product field meaning — `title`, `account_id`, `done`, and (in v2) the *value* of a
  client-supplied id. It emits a typed `WriteIntent`; it never names a DSN, SQL, capability, or column.
- **Host owns**: effect identity + transport — the idempotency/dedup key, the surrogate PK value (v1),
  the table/column binding, receipts, the DB connection. Minting an **opaque** surrogate id is host
  transport authority (a sequence-equivalent), not a product decision.

## Failure / replay matrix (recommended v1)

| Request | Result |
| --- | --- |
| create, key `k1`, title `"Buy milk"` | 200; `result.key = blake3(k1)` surrogate; one row |
| replay: same key `k1`, same title | 200 dedup; **same** `result.key`; no 2nd mutation |
| same key `k1`, **different** title | **409 conflict** (payload-digest mismatch); no mutation |
| keyless | **400** (idempotency guard) |
| non-string / empty / malformed body | **400** (P18 body contract) |

## Adapter changes named

- **v1 / v2:** none to the write adapter or schema — the host sets the write key (surrogate in v1, body
  id in v2); the existing `intent.key → business_key` plumbing and `effect_receipts` are unchanged.
- **v4 (deferred):** `TokioPostgresWriteAdapter::transact` must `RETURNING <key_column>`,
  `PostgresWriteResult` (and the fake) must carry the generated id, and the replay/reconcile path must
  read `effect_receipts.business_key` back into the response.

## Next implementation card (specific, bounded)

`LAB-TODOAPP-API-HOST-SURROGATE-ID-P27` — host-minted deterministic surrogate todo id (v1):

- **Scope:** in the create write path, set the business key to `"todo-" + blake3(idempotency_key)` hex
  (truncated), keeping the idempotency/dedup key = the request key. Return it as `result.key`.
- **Where:** the smallest seam is the app's `BuildCreateTodoIntent` if it can derive the id (needs a
  blake3/stable-hash stdlib surface in `.ig` — likely absent, verify) **or** a host-side write-key
  derivation in the effect-host/bridge (`igniter-server`/`igniter-web`) so `.ig` stays hash-free.
  Verify-first which seam avoids new `.ig` syntax; prefer host-side derivation (keeps `.ig` pure).
- **Tests:** fake + real-PG — create returns a surrogate id ≠ idempotency key; replay returns the
  **same** id with one mutation; same-key/different-title → 409; `done` keeps keying by `todo_id`.
- **Docs:** update `API.md` Idempotency note ("create: business id = host surrogate, decoupled from the
  idempotency key") and the v0→v1 boundary.
- **Closed:** no client-provided id (that is v2, blocked on P25), no PG-generated id, no schema change.

## Closed surfaces (this card)

- No DB schema migration. No write-adapter refactor. No public API stability claim. No production code
  changed — this packet is doc-only (the only optional code touch would be a one-line doc link).
