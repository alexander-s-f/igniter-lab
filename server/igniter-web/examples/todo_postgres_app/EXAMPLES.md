# todo_postgres_app — copy/paste API examples

**Status:** lab example, loopback/local Postgres only. These examples assume the
async machine runner is already serving `examples/todo_postgres_app` on
`127.0.0.1:$PORT` with `host.example.toml`. They are examples of the current
product API contract, not a public/stable API promise.

Keep secrets in the environment. Do not paste a DSN or bearer token into this
file or into shell history.

```bash
export PORT=PORT
export ACCOUNT=ACCOUNT
export IDEMPOTENCY_KEY=IDEMPOTENCY_KEY
export BASE="http://127.0.0.1:$PORT"
```

Writes use the bearer token from the environment only:

```bash
-H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN"
```

## Health

```bash
curl -i "$BASE/health"
```

Expected: `200` with body `ok`.

## List Todos

```bash
curl -i "$BASE/accounts/$ACCOUNT/todos"
```

Account-existence semantics:

- existing account with no todos -> `200 []`
- missing account -> app-owned `404`

The app-owned error envelope is:

```json
{"error":{"code":"account_not_found","message":"account not found"}}
```

That shape is authored as `RespondError { status, error }` in the app. Host
policy errors and framework guard errors keep their own v0 shapes; `RespondError`
does not make a global protocol envelope.

## Create Todo

Create accepts a JSON object body only:

```bash
curl -i -X POST "$BASE/accounts/$ACCOUNT/todos" \
  -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
  -H "idempotency-key: $IDEMPOTENCY_KEY" \
  --data '{"title":"Buy milk"}'
```

The legacy bare JSON string body is removed and rejected:

```bash
curl -i -X POST "$BASE/accounts/$ACCOUNT/todos" \
  -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
  -H "idempotency-key: ${IDEMPOTENCY_KEY}-bad-body" \
  --data '"Buy milk"'
```

Expected: app-owned `400` with:

```json
{"error":{"code":"invalid_body","message":"create body must provide a non-empty title"}}
```

## Surrogate Id vs Idempotency Key

`IDEMPOTENCY_KEY` is the effect replay key. It is not the Todo resource id.

On create, the host mints a deterministic surrogate business id shaped like
`todo_<digest>`, based on method + path + idempotency key. The app receives the
opaque host signal and prefixes it as the Todo id. Replaying the same request
uses the same idempotency key and resolves to the same surrogate id, but clients
should discover the actual `todo_...` id from a later read.

```bash
curl -s "$BASE/accounts/$ACCOUNT/todos"
```

Set `TODO_ID` to the returned row's `id` before using show/done/delete:

```bash
export TODO_ID=TODO_ID
```

## Replay and Conflict

Same idempotency key + same body is a replay: no second mutation.

```bash
curl -i -X POST "$BASE/accounts/$ACCOUNT/todos" \
  -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
  -H "idempotency-key: $IDEMPOTENCY_KEY" \
  --data '{"title":"Buy milk"}'
```

Same idempotency key + different body is a conflict: no mutation.

```bash
curl -i -X POST "$BASE/accounts/$ACCOUNT/todos" \
  -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
  -H "idempotency-key: $IDEMPOTENCY_KEY" \
  --data '{"title":"Buy oat milk"}'
```

Expected conflict body:

```json
{"error":"conflict"}
```

## Show Todo

```bash
curl -i "$BASE/accounts/$ACCOUNT/todos/$TODO_ID"
```

Missing Todo rows return app-owned `404`:

```json
{"error":{"code":"todo_not_found","message":"todo not found"}}
```

## Mark Done

```bash
curl -i -X POST "$BASE/accounts/$ACCOUNT/todos/$TODO_ID/done" \
  -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
  -H "idempotency-key: ${IDEMPOTENCY_KEY}-done" \
  --data '{}'
```

`done` targets the route `TODO_ID` as the business key. Its idempotency key is
still only the effect replay key.

## Delete Todo

```bash
curl -i -X DELETE "$BASE/accounts/$ACCOUNT/todos/$TODO_ID" \
  -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
  -H "idempotency-key: ${IDEMPOTENCY_KEY}-delete" \
  --data '{}'
```

Delete is idempotent. Replaying the same delete key performs no second mutation;
a later `show` for the same `TODO_ID` returns `404`.

## Keyset Pagination

List is ordered by surrogate `id` ascending. To fetch the next page, pass the
last returned `id` as `after`:

```bash
curl -i "$BASE/accounts/$ACCOUNT/todos?after=$TODO_ID"
```

Today the client derives the next cursor from the last row's `id` in the current
array response. A typed `{items,next}` response envelope and client `limit`
parameter are deferred to a separate product slice.

## Secret Safety

- Use `Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN`; do not inline token
  values.
- Keep `IGNITER_TODO_PG_DSN` outside examples; DSN setup belongs to the runbook
  and host config, not request examples.
- Do not use production or SparkCRM databases with this lab app.
