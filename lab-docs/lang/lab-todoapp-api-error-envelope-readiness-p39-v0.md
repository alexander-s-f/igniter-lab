# LAB-TODOAPP-API-ERROR-ENVELOPE-READINESS-P39 — product error envelope

**Date:** 2026-06-23
**Type:** readiness packet (NO production code changed)
**Delegation:** OPUS-TODOAPP-API-ERROR-ENVELOPE-READINESS-P39
**Depends on:** LAB-TODOAPP-API-ERROR-CONTRACT-P20 (the current two-family contract)
**Authority note:** lab evidence only — igniter-lang is canon; an example-app choice must not become global canon.

## TL;DR recommendation

**Proceed — but the smallest, app-scoped slice.** Introduce a typed IgWeb-prelude `RespondError { status,
error : ApiError }` variant (mirroring the proven `RespondView`/`RenderView` typed-body pattern) and migrate
**only the Todo app's app-authored errors** to it. Keep host-owned errors exactly as they are.

- The product error **`code` taxonomy is owned by the app (`.ig`)**; the prelude owns only the *shape*.
- **Do NOT normalize host effect-outcomes** — they carry `status`/`detail`/`correlation_id`/`result` that a
  flat `{error:{code,message}}` would lose (live proof below).
- **Defer** the global `igniter-server` protocol envelope (option 4) to a separate, explicitly-justified
  card — high blast radius, would flatten host outcomes, and risks turning a lab choice into canon.
- The compiler-generated guard errors (keyless 400, route-miss 404, method 405) are **lowered** in
  `igniter_compiler::igweb`, not authored — enveloping them is a *second* IgWeb-lowering slice, called out
  below so it is not silently dropped.

## 1. Live current error mappings (cited)

### App-owned — `map_decision` (`server/igniter-web/src/lib.rs`)

| Decision | Status | Body | Source |
| --- | --- | --- | --- |
| `Respond { status, body }` | the `status` | `{"body": "<message>"}` | `lib.rs:357-360` |
| `RespondView { status, view }` | the `status` | the `view` **record as JSON body root** | `lib.rs` `"RespondView"` arm |
| `RenderView { status, view }` / `Render` | the `status` | rendered HTML / artifact | `lib.rs` render arms |
| unmapped / unknown decision tag | **500** | `{"error": "unmapped decision"/"unknown decision tag: …", "raw": <decision>}` | `lib.rs:338-343` |

Key fact: `RespondView`/`RenderView` already prove `.ig` can return a **typed record** that the runner
serializes as the JSON body **root** (no stringly JSON, no `{"body":"…"}` wrapper). A `RespondError`
variant is the same mechanism applied to errors.

### Host-owned (read) — `dispatch_with_read` (`server/igniter-web/src/lib.rs`)

| Condition | Status | Body | Source |
| --- | --- | --- | --- |
| read denied by host policy | **403** | `{"error": "<reason>"}` (names requested source/field/op only) | `lib.rs:130` |
| host read error / adapter failure | **503** | `{"error": "<msg>"}` | `lib.rs:135` |
| staged-read bound exceeded (P38) | **500** | `{"error": "staged read exceeded maximum hops"}` | `lib.rs:145` |
| machine dispatch error | **500** | `{"error": "<debug>"}` | `lib.rs:57,92` |

### Host-owned (write) — effect outcome → HTTP (`runtime/igniter-machine/src/ingress.rs:111-120`)

| `WriteState` | Status | Body |
| --- | --- | --- |
| `Committed` | **200** | `{"status":"committed","result": <result, incl. minted id>}` |
| `UnknownExternalState` | **202** | `{"status":"accepted_unknown","correlation_id": <reconcile key>}` |
| `Denied` | **403** | `{"status":"denied","detail": <message>}` |
| `Retryable` | **503** | `{"status":"retry_later"}` |
| `PermanentFailure` | **502** | `{"status":"failed","detail": <message>}` |
| other | **500** | `{"status":"<state>"}` |

So "host-owned" is itself **two** shapes — read errors `{"error": <string>}` and write outcomes
`{"status", "detail"/"result"/"correlation_id"}`. There is no single host shape to align to.

### Tests that pin the contract

- `tests/todo_error_contract_tests.rs` — `assert_app_error` asserts the app shape is `{"body": "<message>"}`
  (`body.get("body").is_some()`) and `assert_no_leak` forbids `postgres://`/`password`/`dsn`/`bearer`/SQL/
  `host.toml`/`/tmp/`. Covers route-miss 404, method 405, keyless 400, invalid create body 400.
- `tests/todo_postgres_async_runner_smoke_tests.rs` (P20) — host-owned 403 (denied), 401 (unauthorized),
  409 (conflict), and (P38) 404 (missing account) on the machine path.
- `examples/todo_postgres_app/API.md` "Error contract (v0)" — the full owner-shaped table (the documented
  source of truth).

## 2. Options compared (≥5)

| # | Option | `code` owner | `.ig` typed? | Host detail preserved | Blast radius | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Todo-local app envelope, stringly JSON in `Respond.body`** | app | no (JSON-in-string) | n/a | small | ✗ double-encodes as `{"body":"{…}"}`; runner would need to detect/avoid wrapping → hacky |
| 2 | **IgWeb prelude `RespondError` typed variant** (recommended) | app (values) / prelude (shape) | **yes** | yes (host untouched) | small–medium (prelude + 1 `map_decision` arm + app + tests) | ✓ clean, mirrors `RespondView`; no server change; no host flattening |
| 3 | **Runner-level normalization** (Todo runner wraps app+host errors) | runner | no | **no** (flattens host outcomes) | medium | ✗ runner would have to invent codes for host errors + drop `correlation_id`/`result`; product logic leaks into the runner |
| 4 | **Global `igniter-server` protocol envelope** | server/protocol | n/a | **no** | **large** (cross-crate: server + machine + every app) | ✗ defer — flattens write outcomes, risks canonizing a lab choice; only as a separately-justified future card |
| 5 | **No-op — docs/tests only** | — | — | yes | none | ⚖ viable; loses the one real benefit (a machine-readable `code`); clients keep string-matching messages |

## 3. Answers to the card's questions

- **Which layer owns product error `code` values?** The **app** (`.ig`), as string literals in its error
  contracts. The IgWeb prelude owns only the record *shape* (`ApiError { code, message }`); `igniter-server`
  and canon own **nothing** here. This is the product/canon boundary.
- **Can `.ig` author structured error objects without stringly JSON today?** **Yes**, via the existing
  typed-record-as-body mechanism (`RespondView`/`RenderView`). A new `RespondError { status, error : ApiError }`
  lets `.ig` build and return a typed `ApiError` record that `map_decision` serializes as the body root.
  Without such a variant, the only path is JSON-in-`Respond.body`, which the runner double-wraps — rejected.
- **Would host-owned effect outcomes lose useful status/detail if normalized?** **Yes.** `ingress.rs:111-120`
  carries the `accepted_unknown` **`correlation_id`** (the client's reconcile key for a 202), the committed
  **`result`** (the write payload incl. the P36 minted id), and `denied`/`failed` **`detail`**. Flattening to
  `{error:{code,message}}` discards all of these → host outcomes must stay as-is.
- **Migration / compatibility risk?** Switching app-error bodies `{"body":"<msg>"}` → `{"error":{"code","message"}}`
  breaks `todo_error_contract_tests.rs` pins and the API.md table. The Todo app is a **lab example with no
  external clients**, so a clean switch (not a compatibility window) is acceptable — update the pinning
  tests + docs in the same slice. Host shapes are unchanged, so host-path tests are unaffected.
- **Smallest follow-up implementation slice?** See §5.

## 4. Concrete Todo error code taxonomy (if proceeding)

`snake_case`, stable, message-independent. Values owned by the Todo app.

| `code` | Status | Where (today) | Notes |
| --- | --- | --- | --- |
| `invalid_create_body` | 400 | `AccountTodoCreate` (P35) | message: "create body must provide a non-empty title" |
| `account_not_found` | 404 | `CheckAccountThenList` (P38) | |
| `todo_not_found` | 404 | `AccountTodoShowFromRows` (P14) | |
| `missing_idempotency_key` | 400 | **compiler-lowered** guard (`igweb.rs`) | needs the lowering slice (§5b) |
| `route_not_found` | 404 | **compiler-lowered** router | lowering slice |
| `method_not_allowed` | 405 | **compiler-lowered** router | lowering slice |

Every value is a fixed product string — it never embeds a host `detail`, DSN, token, SQL, or path, so the
no-leak invariant holds by construction (the `message` is also a fixed product string, not host-derived).

## 5. Named next implementation slice (proposed P42)

Proposed card name: `LAB-TODOAPP-API-RESPOND-ERROR-P42`. P40 is already used by the create-body
compatibility policy slice, so this packet intentionally names the next free implementation slot instead
of reusing P40.

### 5a. Smallest slice — app-authored errors only

- `lang/igniter-compiler/src/igweb.rs` (`PRELUDE_SOURCE`): add `type ApiError { code : String, message : String }`
  and `Decision` arm `RespondError { status : Integer, error : ApiError }`.
- `server/igniter-web/src/lib.rs` (`map_decision`): one arm — `"RespondError" => ServerResponse::json(status, fields.get("error"))`.
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`: migrate `AccountTodoCreate` (400),
  `CheckAccountThenList` (404), `AccountTodoShowFromRows` (404) to `RespondError`.
- `server/igniter-web/tests/todo_error_contract_tests.rs`: update `assert_app_error` to the `{"error":{"code","message"}}`
  shape (keep `assert_no_leak`); add a code-value assertion. `tests/todo_postgres_app_tests.rs` /
  `todo_postgres_async_runner_smoke_tests.rs` / `todo_postgres_local_e2e_tests.rs`: update the migrated
  bodies (status codes are unchanged).
- `examples/todo_postgres_app/API.md` + `RUNBOOK.md`: document the app envelope; keep the host families as-is.

### 5b. Optional follow-on — compiler-lowered guard errors

The keyless 400 and route-miss 404 / method 405 are emitted by `igniter_compiler::igweb` lowering, not by
`todo_handlers.ig`. Enveloping them means the lowering emits `RespondError` instead of `Respond` — an
IgWeb-framework change affecting **all** IgWeb apps. Keep it a separate card so 5a stays small and the
product/framework boundary is explicit.

### Explicitly out (this card and the recommended slice)

- No global `igniter-server`/protocol envelope (option 4).
- No host effect-outcome normalization / receipt changes.
- No body-contract/id/account-existence behavior changes (P35/P36/P38 closed).

## 6. Acceptance (this readiness card)

- [x] Packet cites live current error mappings and tests (§1, file:line).
- [x] ≥5 alternatives compared (§2).
- [x] Recommends one path — **proceed** with the app-scoped slice; defer global (§TL;DR, §2).
- [x] Defines a concrete Todo error code taxonomy (§4).
- [x] Keeps host secrets and raw SQL out of every proposed body shape (codes/messages are fixed product strings; §4).
- [x] Separates Todo product contract from global Igniter canon (codes owned by app; prelude shape is IgWeb-framework, not `igniter-server`/canon; §3).
- [x] Names exact files/tests for the next slice (§5).
- [x] No production code changes (this doc + an optional one-line pointer in API.md).
- [x] `git diff --check` clean.

## 7. Honest caveats

- 5a leaves a **transient inconsistency**: app-authored errors become `{"error":{"code","message"}}` while
  compiler-lowered guard errors stay `{"body":"…"}` and host errors stay `{"error":"…"}`/`{"status":…}` until
  their own slices. Acceptable for a lab example; the end state (after 5b + a future host card) is uniform.
- The recommendation is "proceed" because a machine-readable `code` is the one concrete client benefit the v0
  contract lacks. If the lead prefers to spend the slice elsewhere, **option 5 (no-op)** is a defensible hold —
  the current contract is documented, stable, and leak-safe.
