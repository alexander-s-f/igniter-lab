# todo_postgres_app — API contract

**Status: lab example. Loopback-only, local Postgres only. NOT a public or production API and not a
stable surface.** This is the product-facing contract for the example Todo API authored in `.igweb` +
`.ig` and served by the generic `igweb-serve` runner. For what the runner/host machinery actually
implements, see the crate's [`IMPLEMENTED_SURFACE.md`](../../IMPLEMENTED_SURFACE.md).

The app names only logical effect targets and structured intents; all DB authority (DSN, capability,
allowlist, receipts, passport) is host-owned — see [`host.example.toml`](host.example.toml) and
[`host_policy.md`](host_policy.md).

**New here? Start with the one-page [`RUNBOOK.md`](RUNBOOK.md)** — run it locally, what's real vs not
product-ready, troubleshooting, and the command that proves each claim.

## Two run modes

| Mode | How | Reads (`ReadThen`) | Writes (`InvokeEffect`) |
| --- | --- | --- | --- |
| **Sync observed** (default build) | `igweb-serve <app_dir>` | a `ReadThen` decision is unhandled → **500** | observed only → **202** (no DB write) |
| **Async machine** (`--features postgres` + `--host-config`) | `igweb-serve --host-config host.toml <app_dir>` | executed against Postgres → 200/404 | executed via `MachineEffectHost` → 200 committed / dedup |

`/health` is a plain `Respond` and returns 200 in **both** modes.

## Routes

Source of truth: [`routes.igweb`](routes.igweb) (+ handlers in [`todo_handlers.ig`](todo_handlers.ig)).
"Machine status" = behavior under async machine mode (the product path).

| Method & path | Handler | Idempotency | Success | Not-found / denied |
| --- | --- | --- | --- | --- |
| `GET /health` | `Health` | — | 200 `ok` | — |
| `GET /accounts/:account_id/todos` | `AccountTodoIndex` → `ReadThen` | — | 200 (rows JSON; **empty list → `200 []`**, P24) | 404 if account capture missing (guard); read denied by host policy → 403; host read error → 503 |
| `GET /accounts/:account_id/todos/:todo_id` | `AccountTodoShow` → `ReadThen` (`FindTodo`) | — | 200 (row JSON) | 404 `todo not found` (no matching row); 404 if account/todo missing (guard); 403/503 as above |
| `POST /accounts/:account_id/todos` | `AccountTodoCreate` → `InvokeEffect{todo-create}` | **required** | 200 committed (replay same key → 200 dedup, no 2nd write) | keyless → **400**; non-string/empty/malformed body → **400**; same key + different body → **409 conflict**; sync mode → 202 observed |
| `POST /accounts/:account_id/todos/:todo_id/done` | `AccountTodoDone` → `InvokeEffect{todo-done}` | **required** | 200 committed (replay → 200 dedup) | keyless → **400**; same key + different `todo_id` → **409 conflict**; sync mode → 202 observed |

Unmatched path → **404**; wrong method on a known pattern → **405**.

### List-empty semantics (P24)

`GET /accounts/:id/todos` is a **collection**: zero todos is a valid result and returns **`200 []`**, not
a 404. v0 does **not** verify account existence on list beyond the route capture (the guard only checks
the `:account_id` segment is non-empty), so a request for an unknown account also returns `200 []` rather
than `404 account not found`. Distinguishing "account exists, no todos" from "no such account" needs an
accounts-table existence read — a separate future card (out of P24's scope). `show`
(`GET …/todos/:todo_id`) addresses a **single resource** and still returns **404 `todo not found`** when
the row is absent.

### Reads & freshness (`x-correlation-id`)

Reads run **fresh by default**: each `GET` without an `x-correlation-id` header executes its query anew,
so a `list → create → list` against the same account in one server run observes the new row (it never
replays an earlier empty result). Read **replay is opt-in**: a client that wants a stable snapshot
across a retry sends the same `x-correlation-id` — the host then returns the prior result for that
(correlation, query) pair. Different queries never share a cache even under one correlation. Pinned by
`uncorrelated_same_plan_reads_run_fresh` / `explicit_same_correlation_same_plan_replays` /
`distinct_plans_never_collide` (`tests/readthen_dispatch_tests.rs`) and the live
`local_read_after_write_is_fresh_same_process` (`tests/todo_postgres_local_e2e_tests.rs`).

## Error contract (v0)

The status code carries the error class. Bodies have **two stable shapes by owner** (v0 does not yet
unify them into a single `{"error": {"code", "message"}}` envelope — that would be a cross-crate change
to `igniter-server` + `igniter-machine` + the `.ig` `Respond` decision, deferred to a separate card):

- **App-owned** (`.ig` `Respond` decisions): `{"body": "<message>"}` — the same shape as a success body,
  with the status carrying the error class.
- **Host-owned** (machine ingress / staged-read / effect host): `{"error": "<message>"}`, or for write
  outcomes `{"status": "<word>", "detail": "<message>"}`.

| Condition | Owner | Status | Body | Leak risk |
| --- | --- | --- | --- | --- |
| route miss (unknown path) | app | **404** | `{"body":"…"}` | none |
| wrong method on a known pattern | app | **405** | `{"body":"…"}` | none |
| missing idempotency key | app | **400** | `{"body":"…"}` | none |
| invalid create body (P35) | app | **400** | `{"body":"create body must provide a non-empty title"}` | none |
| account not found | app | **404** | `{"body":"account not found"}` | none |
| todo not found (show) | app | **404** | `{"body":"todo not found"}` | none |
| list empty (no todos) | app | **200** | `{"body":"[]"}` (P24: an empty list is a valid 200, not a not-found) | none |
| read denied by host policy | host | **403** | `{"error":"…"}` (names the requested source/field/op) | no DSN/SQL |
| read host unavailable | host | **503** | `{"error":"…"}` | no DSN |
| write committed | host | **200** | `{"status":"committed","result":…}` | none |
| write denied (target/op) | host | **403** | `{"status":"denied","detail":"…"}` | names target/op |
| write conflict (same key, different body) | host | **409** | `{"error":"conflict"}` | none |
| write duplicate-limit | host | **429** | `{"error":"duplicate limit reached"}` | none |
| write retryable | host | **503** | `{"status":"retry_later"}` | none |
| write permanent failure | host | **502** | `{"status":"failed","detail":"…"}` | none |
| write state unknown | host | **202** | `{"status":"accepted_unknown","correlation_id":…}` | none |
| unauthorized (missing/invalid passport) | host | **401** | `{"error":"unauthorized"}` | none |
| unbound effect target | host | **502** | `{"error":"unbound target","target":"…"}` | none (logical target only) |
| unknown/unmapped decision | runner | **500** | `{"error":"unknown decision tag: …","raw":…}` | app decision echo (no secrets in Todo) |

No product error body leaks a DSN, bearer token, raw SQL, or a host-config path — the host-denied read
reason names only what the *client* requested (the source/field/op), never the allowlist or connection
string. Pinned by `tests/todo_error_contract_tests.rs` (app-owned, sync) and the `P20` tests in
`tests/todo_postgres_async_runner_smoke_tests.rs` (host-owned, machine).

### Idempotency

`create` and `done` require an `idempotency-key` header (the `.igweb` `requires idempotency` guard;
keyless → 400). The header value is the **effect** idempotency key (replay/correlation identity);
replaying the same key performs no second mutation. The **resource id is a separate identity** from the
idempotency key (LAB-TODOAPP-API-HOST-SURROGATE-ID-P36):

- **create**: the business row primary key is a **host-minted surrogate id** —
  `todo_<blake3(method ␟ path ␟ idempotency_key)[..32]>` — minted by the host and crossed to `.ig` as
  `req.surrogate_id`; the `.ig` create contract prefixes it `todo_`. The raw idempotency key is **never**
  stored as the Todo id. The recipe is deterministic, so the *same* key + *same* request resolves to the
  *same* id on replay; it depends on no body value, secret, clock, or randomness, and a different account
  or route (carried in `path`) mints a different id.
- **done**: the business row primary key is the route `todo_id` — which is the previously-minted create
  id (a client takes the id returned by create and targets it). The idempotency key stays the effect key.

#### Replay vs replay-conflict

The same idempotency key is only safe to reuse with the **same** request payload. The host distinguishes
a benign replay from a conflicting reuse:

| Client sends | Result | Status |
| --- | --- | --- |
| same key + **same** body | dedup replay — no second mutation, prior response returned | **200** |
| same key + **different** body (e.g. different create title, or `done` against a different `todo_id`) | **conflict** — refused before any mutation, never a silent success | **409** `{"error":"conflict"}` |

A conflict is decided at the host **ingress dedup gate** (`duplicate_policy = dedup_strict`,
`variant_payload = false`): the gate compares a blake3 digest of the full effect intent body — for
`create` that includes the title; for `done` the `todo_id` (intent `key`). A mismatch against a prior
attempt under the same key → 409 **before** a replica is activated, so the wrong row is never written.

Defence in depth: even if a request reached the write-receipt layer, the machine receipt binds the
idempotency key to `capability_id + operation + authority_digest + payload_digest`. A reused key with a
different payload is **denied** there too (`WriteState::Denied`, detail *"idempotency key reused with a
different payload"* → **403**), before the executor runs.

Note the **PG `effect_receipts`** table is keyed by idempotency key **only** — it is a second
mutation-prevention backstop (a reused key cannot write twice), **not** a payload-conflict detector.
Conflict *detection* is the machine layer's job (ingress dedup + write-receipt digest); the PG unique
key guarantees at-most-one mutation even if a receipt is lost.

## Request body (create)

**v1 (preferred, LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35):** the create body is a JSON **object** with a
non-empty string `title`:

```json
{ "title": "Buy milk" }
```

The host parses the transport object into the generic `req.body_json : Map[String, Unknown]`; the app reads
the `title` field via `map_get_string` (a fail-closed `Option[String]`). The host owns transport parsing;
the **app owns the field meaning** — extra object fields are ignored.

**Legacy v0 (compatibility window):** a bare **non-empty JSON string literal** whose whole value is the
title (e.g. `"Buy milk"`, with quotes) is still accepted. It remains supported for now; the object body is
the documented main shape. (No removal date; this window closes in a later card.)

Every other shape **fails closed to a product-owned 400, before any effect / DB mutation**:

| Body | Result |
| --- | --- |
| `{ "title": "Buy milk" }` (object, non-empty string title) | accepted → title `Buy milk` |
| `"Buy milk"` (legacy non-empty JSON string) | accepted → title `Buy milk` |
| object missing `title` · `title` non-string · `title` empty/blank | **400** `create body must provide a non-empty title` |
| `[...]` array · `5` number · `true` bool | **400** |
| `null` · empty body · `""` (empty string) | **400** (no title) |
| malformed JSON | **400** |

Enforcement seam: the runner classifies the body's JSON shape into a host-computed `req.body_kind`
("object" for an object; "string" for a non-empty string; "empty" for empty/absent/malformed; otherwise the
shape name) and parses an object into `req.body_json`. `ResolveCreateTitle` reads the title from
`body_json.title` (object) or the body string (legacy) and resolves anything else to `""`; the handler
rejects an empty/blank title (via `trim`) with a 400. `.ig` parses no transport JSON — it reads typed
fields only. The runner cannot distinguish a malformed body from an absent one (the HTTP parse collapses
malformed JSON to an empty body); both are rejected. `done` ignores the body. (Reads carry no body.)

```bash
# v1 (preferred): title is a field of the JSON object body
curl -X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
     -H 'idempotency-key: k1' --data '{"title":"Buy milk"}' \
     http://127.0.0.1:PORT/accounts/acct-1/todos

# legacy (compatibility window): a bare JSON string title
curl -X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
     -H 'idempotency-key: k2' --data '"Buy milk"' \
     http://127.0.0.1:PORT/accounts/acct-1/todos
```

`done` is a **full-row upsert** keyed by `todo_id` (the host adapter is `INSERT … ON CONFLICT DO
UPDATE`): it carries `account_id` (FK-valid) and sets `done="true"`. v0 does **not** preserve the
existing `title` (no partial PATCH).

## Host requirements (async machine mode)

- Build with `--features postgres`; pass `--host-config` pointing at a host TOML
  (see [`host.example.toml`](host.example.toml), commit-safe, env-var names only).
- `IGNITER_TODO_PG_DSN` — read **and** write DSN; use a **dedicated local test DB** (e.g.
  `igniter_todo_test`), never production / never SparkCRM.
- `IGNITER_TODO_EFFECT_TOKEN` — the bearer token clients present (`Authorization: Bearer …`) for
  `todo-create` / `todo-done`; both effects are bound to host route `/w`.
- Schema (`accounts`, `todos`, `effect_receipts`) is operator-owned; the runner never migrates it.

## Evidence

From `server/igniter-web/`:

```bash
scripts/check_implemented_surface.sh                  # bounded guard for the runner surface
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
  scripts/todo_postgres_smoke.sh                      # one-command operator smoke (PASS/FAIL receipt)
cargo test --features machine                         # ReadThen + effect host + app tests (no DB)
IGNITER_TODO_PG_DSN=… cargo test --features postgres \
  --test todo_postgres_local_e2e_tests -- --test-threads=1   # real Postgres E2E (skips w/o DSN)
```

## Open product limitations (intentional v0)

- No typed row destructuring — `ReadThen` continuations receive rows as a JSON **string**.
- Object create bodies are parsed generically into `req.body_json : Map[String, Unknown]` (P35); the app
  reads only the `title` field. There is no general JSON query language and no nested/typed destructuring
  beyond `map_get_string`.
- Create ids are **host-minted deterministic surrogates** (`todo_<digest>`), decoupled from the
  idempotency key (P36) — but they are derived from request identity, not a DB sequence or random id.
- No schema migration runner (DDL is operator-owned).
- No connection pool / backpressure; bounded, one-request-at-a-time loopback loop.
- No public listener mode, no deployment story, no stable CLI/API promise.
