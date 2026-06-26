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
| `GET /accounts/:account_id/todos?after=<id>` | `AccountTodoIndex` → two-stage `ReadThen` | — | 200 (rows JSON, **ordered by `id` asc**; existing account + **empty list → `200 []`**, P24). Keyset paginated: optional `?after=<id>` returns rows with `id > after`; page size = host cap (P47). | **404 `account not found`** if the account does not exist (P38); read denied by host policy → 403; host read error → 503 |
| `GET /accounts/:account_id/todos/:todo_id` | `AccountTodoShow` → `ReadThen` (`FindTodo`) | — | 200 (row JSON) | 404 `todo not found` (no matching row); 404 if account/todo missing (guard); 403/503 as above |
| `POST /accounts/:account_id/todos` | `AccountTodoCreate` → `InvokeEffect{todo-create}` | **required** | 200 committed (replay same key → 200 dedup, no 2nd write) | keyless → **400**; non-string/empty/malformed body → **400**; same key + different body → **409 conflict**; sync mode → 202 observed |
| `POST /accounts/:account_id/todos/:todo_id/done` | `AccountTodoDone` → `InvokeEffect{todo-done}` | **required** | 200 committed (replay → 200 dedup) | keyless → **400**; same key + different `todo_id` → **409 conflict**; sync mode → 202 observed |
| `DELETE /accounts/:account_id/todos/:todo_id` | `AccountTodoDelete` → `InvokeEffect{todo-delete}` | **required** | 200 committed — the row is removed; **idempotent** (replay → 200 dedup; a later `show` → 404, `list` no longer shows it) | keyless → **400**; same key + different `todo_id` → **409 conflict**; sync mode → 202 observed (P44) |

Unmatched path → **404**; wrong method on a known pattern → **405**.

### List-empty vs missing-account semantics (P24 + P38)

`GET /accounts/:id/todos` is a **collection**, and the two empty-ish outcomes are now distinguished
(LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38):

- **account exists, zero todos → `200 []`** (an empty collection is a valid 200, not a 404).
- **account does not exist → `404 account not found`** (app-owned).

The handler is a **two-stage staged read**: stage 1 reads the `accounts` table to prove the account
exists (empty rows ⇒ 404); only then does stage 2 issue the `todos` list (empty rows ⇒ `200 []`). A single
`todos` read could not tell the two apart (both yield `[]`). The host read policy must allowlist **both**
the `todos` and `accounts` sources (multi-source `[postgres.read.*]`, see [`host_policy.md`](host_policy.md));
the generic runner threads the route-captured `account_id` from stage 1 to stage 2 via an opaque `carry`
on `ReadThen` and bounds the staged-read chain (no infinite continuation loop). `show`
(`GET …/todos/:todo_id`) addresses a **single resource** and returns **404 `todo not found`** when the row
is absent.

### Keyset pagination (P47)

The list is **ordered by the surrogate `id` ascending** (a stable total order; the id is hash-arbitrary,
not chronological). Pass `?after=<id>` to get the next page — rows with `id > after`:

```bash
curl 'http://127.0.0.1:PORT/accounts/acct-1/todos'                  # first page
curl 'http://127.0.0.1:PORT/accounts/acct-1/todos?after=todo_<lastid>'  # next page
```

Page size is **server-fixed** at the host read cap. The cursor is the **`id` of the last item** you
received — keyset, so paging never duplicates or skips rows (even under concurrent insert). An empty /
exhausted page is `200 []`; a missing account is still `404`.

**Deferred (no dead-end):** a typed `{ "items": […], "next": <cursor> }` envelope and a client-tunable
`?limit=` are not yet exposed. The generic runner now supports typed row continuations + `DatasetMeta`,
but this product JSON route still uses the legacy `rows_json` continuation; adopting the envelope is an app
slice plus a small numeric/string DX slice for `limit`/badges. Today the client derives the next cursor from
the last item's `id`. A bare non-`id`-monotone chronological order would need a composite `(inserted_at, id)`
cursor (more substrate).

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

The status code carries the error class. Error bodies have **three stable shapes by owner**:

> **Envelope (P39 design → P43 impl):** app-authored errors carry a small, **app-scoped** typed envelope
> `RespondError { status, error: { code, message } }` → `{"error": {"code", "message"}}` (design:
> `lab-docs/lang/lab-todoapp-api-error-envelope-readiness-p39-v0.md`; implemented in
> `LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43`). The global cross-crate protocol envelope (unifying host
> shapes too) stays deferred.

- **App-authored** (`.ig` `RespondError` decisions — invalid create body, account/todo not-found):
  `{"error": {"code": "<token>", "message": "<message>"}}`. The `code` is app-owned and stable.
- **Framework-app** (errors from the `.igweb` lowering — route miss 404, method mismatch 405, keyless
  guard 400): `{"body": "<message>"}` (the v0 shape; unchanged).
- **Host-owned** (machine ingress / staged-read / effect host): `{"error": "<message>"}`, or for write
  outcomes `{"status": "<word>", "detail": "<message>"}`.

| Condition | Owner | Status | Body | Leak risk |
| --- | --- | --- | --- | --- |
| route miss (unknown path) | app | **404** | `{"body":"…"}` | none |
| wrong method on a known pattern | app | **405** | `{"body":"…"}` | none |
| missing idempotency key | app | **400** | `{"body":"…"}` | none |
| invalid create body (P35) | app | **400** | `{"error":{"code":"invalid_body","message":"create body must provide a non-empty title"}}` (P43) | none |
| account not found | app | **404** | `{"error":{"code":"account_not_found","message":"account not found"}}` (P43) | none |
| todo not found (show) | app | **404** | `{"error":{"code":"todo_not_found","message":"todo not found"}}` (P43) | none |
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

**Legacy v0 (REMOVED):** the bare JSON string title (e.g. `"Buy milk"`, with quotes) was accepted during a
deprecation window (P35 introduced, P40 deprecated) and is now **removed**
(LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL-P45): a bare string body is treated like any other non-object
shape and **fails closed to a 400**. The object body `{ "title": … }` is the **only** accepted create shape.

Every other shape **fails closed to a product-owned 400, before any effect / DB mutation**:

| Body | Result |
| --- | --- |
| `{ "title": "Buy milk" }` (object, non-empty string title) | accepted → title `Buy milk` |
| `"Buy milk"` (bare JSON string — the removed legacy form) | **400** (P45: a non-object body is rejected) |
| object missing `title` · `title` non-string · `title` empty/blank | **400** `create body must provide a non-empty title` |
| `[...]` array · `5` number · `true` bool | **400** |
| `null` · empty body · `""` (empty string) | **400** (no title) |
| malformed JSON | **400** |

Enforcement seam: the runner classifies the body's JSON shape into a host-computed `req.body_kind`
("object" for an object; "string" for a non-empty string; "empty" for empty/absent/malformed; otherwise the
shape name) and parses an object into `req.body_json`. `ResolveCreateTitle` reads the title from
`body_json.title` for an **object body only** (P45) and resolves any other shape — including a bare string —
to `""`; the handler rejects an empty/blank title (via `trim`) with a 400. `.ig` parses no transport JSON — it reads typed
fields only. The runner cannot distinguish a malformed body from an absent one (the HTTP parse collapses
malformed JSON to an empty body); both are rejected. `done` ignores the body. (Reads carry no body.)

```bash
# the object body is the only accepted create shape: title is a field of the JSON object
curl -X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
     -H 'idempotency-key: k1' --data '{"title":"Buy milk"}' \
     http://127.0.0.1:PORT/accounts/acct-1/todos

# a bare JSON string body (the removed legacy form) now fails closed → 400
#   --data '"Buy milk"'   # rejected (P45)
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

- The generic runner supports typed rows + `DatasetMeta` continuations, and typed rows can render HTML via
  `RenderView`; this Todo JSON API still uses the legacy `rows_json` continuation for list/show responses.
  Moving these product routes to typed rows is a separate app slice, not a current runner blocker.
- Object create bodies are parsed generically into `req.body_json : Map[String, Unknown]` (P35); the app
  reads only the `title` field. There is no general JSON query language and no nested/typed destructuring
  beyond `map_get_string`.
- Create ids are **host-minted deterministic surrogates** (`todo_<digest>`), decoupled from the
  idempotency key (P36) — but they are derived from request identity, not a DB sequence or random id.
- No schema migration runner (DDL is operator-owned).
- No connection pool / backpressure; bounded, one-request-at-a-time loopback loop.
- No public listener mode, no deployment story, no stable CLI/API promise.
