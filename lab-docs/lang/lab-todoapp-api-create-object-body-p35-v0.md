# LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35 — accept JSON object create bodies

**Date:** 2026-06-23
**Type:** implementation after verify-first
**Delegation:** OPUS-TODOAPP-API-CREATE-OBJECT-BODY-P35
**Depends on:** LAB-MACHINE-MAP-GET-STRING-P34 (CLOSED) · P28 Map runtime gate (CLOSED)
**Status:** landed (this doc is the proof packet)
**Authority note:** lab evidence only — igniter-lang is canon; a lab proof does not create canon authority.

## TL;DR

Todo create now accepts the preferred v1 **object** body and keeps the legacy v0 string body during a
compatibility window:

```http
POST /accounts/:account_id/todos
{ "title": "Buy milk" }          # v1 (preferred)
"Buy milk"                        # v0 legacy (still accepted)
```

- The host adds a **generic transport** field `req.body_json : Map[String, Unknown]` — a JSON object body
  crosses as a map; every non-object body crosses as an **explicit empty map**. The shape distinction
  stays in `body_kind`.
- The app owns the field meaning: `ResolveCreateTitle` reads `title` via the P34 `map_get_string`
  (fail-closed `Option[String]`) for objects, falls back to the body string for legacy, and resolves
  anything else to `""`. `AccountTodoCreate` rejects an empty/blank title (`trim`) with a product 400.
- **No id-generation change** — the P36 surrogate-id wiring (`req.surrogate_id` → `todo_<digest>`) is
  untouched. **No schema change.** Generic machine/server code is untouched.

## Authority split

| Concern | Owner | Where |
| --- | --- | --- |
| Transport parse: JSON object → `Map[String, Unknown]`; non-object → empty map | **host** | `build_request_input` (`server/igniter-web/src/lib.rs`) |
| Field meaning (`title`), validity (non-empty/blank), legacy fallback | **app (`.ig`)** | `ResolveCreateTitle` + `AccountTodoCreate` (`todo_handlers.ig`) |
| Typed map string extraction (`map_get_string`), `trim` | language/stdlib (P34) | unchanged |

The host never names `title` or interprets a field — it only parses transport. `.ig` parses no JSON.

## Failure matrix (and where each is decided)

| Body | `body_kind` | Resolved title | Result |
| --- | --- | --- | --- |
| `{ "title": "Buy milk" }` | `object` | `map_get_string → Some("Buy milk")` | **create** |
| `{ "title": "Buy milk", "done": true }` | `object` | `Some("Buy milk")` (extra fields ignored) | **create** |
| `"Buy milk"` (legacy string) | `string` | body string | **create** |
| `{}` / `{ "note": "x" }` (missing title) | `object` | `None → ""` | **400** |
| `{ "title": 5 / true / null / {…} }` (non-string) | `object` | `None → ""` (fail-closed) | **400** |
| `{ "title": "" }` (empty) / `{ "title": "   " }` (blank) | `object` | `"" / "   "` → `trim == ""` | **400** |
| `[...]` array · `5` number · `true` bool | array/number/bool | `""` | **400** |
| `null` · empty body · `""` empty string | `empty` | `""` | **400** |
| malformed JSON | `empty` (HTTP parse collapses to null) | `""` | **400** |

The 400 message is `create body must provide a non-empty title` — it names the contract, never echoes the
offending body value (P35 implementation note honoured).

## What changed

| File | Change |
| --- | --- |
| `lang/igniter-compiler/src/igweb.rs` | `Request` prelude gains `body_json : Map[String, Unknown]`. |
| `server/igniter-web/src/lib.rs` | `build_request_input` crosses `body_json` (object → parsed map; else explicit `{}`). |
| `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig` | new `ResolveCreateTitle`; `AccountTodoCreate` uses the resolved title + `trim` guard. Surrogate-id (P36) wiring unchanged. |
| `tests/todo_postgres_app_tests.rs` | `create_body_contract_object_and_legacy_string` — full accept/reject matrix (sync, no DB). |
| `tests/todo_postgres_effect_host_tests.rs` | `object_create_body_executes_via_machine_host` (success) + `titleless_object_create_body_rejected_before_effect_host` (repurposed from the old object→400). |
| `tests/todo_postgres_local_e2e_tests.rs` | the comprehensive real-PG subprocess e2e now sends `{ "title": … }`; the negative subprocess test sends a title-less object. |
| `tests/todo_error_contract_tests.rs` | 400-message assertion updated to the new contract wording. |
| `examples/todo_postgres_app/API.md`, `RUNBOOK.md` | object body is the documented main shape; legacy string is a compatibility note. |

## Evidence

- `cargo test --features machine` (igniter-web): **28 suites green, 0 failures**, incl.
  - `create_body_contract_object_and_legacy_string` — 3 accepted shapes + 15 rejected shapes.
  - `object_create_body_executes_via_machine_host` — object title flows into the write intent and commits.
- `cargo test` (igniter-compiler): **green** (prelude `body_json` field safe; no snapshot break).
- `IGNITER_TODO_PG_DSN=… cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests -- --test-threads=1`: **12 passed**, incl.
  - `subprocess_product_command_read_write_replay_e2e` — the **real `igweb-serve` binary** receives
    `{ "title": "Buy milk via P35" }` over a socket; the DB row title = `Buy milk via P35`, stored under
    the P36 surrogate id; replay = one row.
  - `subprocess_non_string_create_body_writes_no_row` — a title-less object body → 400, **no** `todos`
    row and **no** PG effect receipt.
- `git diff --check`: clean.

## Acceptance (card)

- [x] `Request.body_json : Map[String, Unknown]` is available to IgWeb handlers.
- [x] Todo create accepts `{ "title": "Buy milk" }`.
- [x] Failure matrix above is covered by tests (sync decision matrix + effect-host + real-PG subprocess).
- [x] Legacy string body behavior is **preserved** (documented compatibility window; not removed).
- [x] `API.md` + RUNBOOK describe object-body v1 and the compatibility status.
- [x] No schema change.
- [x] No id-generation change (P36 surrogate wiring untouched).
- [x] Sync observed path (app_tests `roundtrip`) and async machine runner path (effect-host + subprocess
      serve loop) both checked.
- [x] `git diff --check` clean.

## Compatibility policy & honest limits

- **Legacy string body kept** — `"Buy milk"` still creates. The object body is the documented main shape;
  no removal date (a later card closes the window).
- **Blank tightening (both paths)** — a whitespace-only title (`"   "` object value, or a whitespace-only
  legacy string body) now → 400 via `trim`. Previously a whitespace-only legacy string slipped through;
  this is a deliberate, consistent tightening, not a regression of legitimate titles.
- **Generic parse, app-owned meaning** — `body_json` is a flat `Map[String, Unknown]`; the app reads only
  `title` via `map_get_string`. No nested/typed destructuring and no general JSON query language (closed
  surfaces honoured). No product-specific field is added to the IgWeb prelude — `body_json` is generic.
- **Non-object bodies cross as an explicit empty map** (`{}`), so a handler that reads `body_json` on a
  non-object request gets a present-but-empty map, never a missing field.
