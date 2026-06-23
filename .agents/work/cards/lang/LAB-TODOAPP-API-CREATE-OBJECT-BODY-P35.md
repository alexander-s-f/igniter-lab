# LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35 - accept JSON object create bodies

Status: TODO
Lane: TodoApp API / IgWeb request surface
Type: implementation
Delegation code: OPUS-TODOAPP-API-CREATE-OBJECT-BODY-P35
Date: 2026-06-23
Skill: idd-agent-protocol

## Depends on

- `LAB-MACHINE-MAP-GET-STRING-P34`

## Context

Current Todo create v0 intentionally accepts the awkward safe body:

```http
POST /accounts/:account_id/todos
"Buy milk"
```

P25 chose the v1 shape:

```json
{ "title": "Buy milk" }
```

P28 proved runtime `Map[String, Unknown]`; P34 should provide typed string extraction. This card
then crosses the parsed object into `.ig` and updates Todo create.

## Goal

Add a generic request body object surface and make Todo create accept object bodies:

```ig
type Request {
  ...
  body : String
  body_kind : String
  body_json : Map[String, Unknown]
}
```

The host may parse transport JSON into `body_json`, but the app owns field meaning (`title`).

## Compatibility policy

Keep the string-body v0 path working for now unless live tests show it creates unacceptable ambiguity.
Object body is preferred and must be documented as the main API shape.

Expected behavior:

- object with non-empty string `title` -> create intent
- object missing `title` -> 400
- object with non-string `title` -> 400
- object with empty/blank `title` -> 400
- malformed JSON / array / number / boolean / null -> 400
- legacy JSON string body -> keep existing success behavior during the compatibility window

## Verify first

Read live source and tests:

- `server/igniter-web/src/lib.rs` (`build_request_input`, body_kind handling)
- `lang/igniter-compiler/src/igweb.rs` (`Request` prelude)
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/tests` Todo API runner/smoke tests
- P25 and P28/P34 proof docs

## Implementation notes

- `body_json` must be generic transport parsing, not `body_title`.
- Do not echo invalid body values in diagnostics.
- Keep `body` and `body_kind` stable for existing handlers.
- If non-object bodies use an empty map, make that explicit in the proof.

## Acceptance

- [ ] `Request.body_json : Map[String, Unknown]` is available to IgWeb handlers.
- [ ] Todo create accepts `{ "title": "Buy milk" }`.
- [ ] Failure matrix above is covered by tests.
- [ ] Legacy string body behavior is either preserved or intentionally removed with proof and docs.
- [ ] `API.md` and any runbook/product guard docs describe object-body v1 and compatibility status.
- [ ] No schema change.
- [ ] No id-generation change; that belongs to P36.
- [ ] Sync observed path and async machine runner path are both checked as applicable.
- [ ] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-create-object-body-p35-v0.md
```

## Closed surfaces

- No generated/surrogate IDs.
- No account existence semantics change.
- No general JSON query language.
- No product-specific request fields in IgWeb prelude.
