# LAB-TODOAPP-API-CREATE-OBJECT-BODY-READINESS-P25 - JSON object create body shape

Status: TODO
Lane: TodoApp API / request body ergonomics / readiness
Type: readiness packet
Delegation code: OPUS-TODOAPP-API-CREATE-OBJECT-BODY-READINESS-P25
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P18 made create safe but intentionally awkward:

```text
POST /accounts/:id/todos
body: "Buy milk"
```

The body must be a non-empty JSON string literal. A real API wants an object:

```json
{ "title": "Buy milk" }
```

Today `.ig` receives `req.body : String` and `req.body_kind : String`. It does not parse JSON and should not
gain hidden authority. The question is where the first object-field extraction belongs.

## Goal

Produce a readiness packet that chooses the smallest honest path from string-body v0 to object-body v1.

Compare at least these options:

1. host-projected request fields, e.g. `req.body_title`;
2. generic `Request.body_json` / `Map[String, Unknown]` surface;
3. stdlib JSON extractor contract, e.g. `json.get_string(req.body, "title")`;
4. keep string body and document it as v0;
5. move create body parsing into a host capability (likely reject: product meaning leak).

## Verify first

Read live code:

- `server/igniter-web/src/lib.rs` (`build_request_input`)
- `lang/igniter-compiler/src/igweb.rs` (prelude `Request`)
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- any existing JSON/Map/string stdlib surfaces in `lang/igniter-compiler/src` and `runtime/igniter-machine/src`

Do not implement unless the packet finds a clearly tiny and safe slice. This card is readiness-first.

## Questions to answer

1. What body surface can `.ig` consume without raw JSON parsing becoming app magic?
2. Can the compiler/typechecker express optional object fields today?
3. Does Map/Unknown support make this easy or does it create a larger language gate?
4. Which failure cases become 400: missing title, non-string title, empty title, malformed JSON?
5. Where should escaping/redaction happen in diagnostics?
6. What is the exact first implementation card after this readiness packet?

## Acceptance

- [ ] Packet names the recommended v1 body shape.
- [ ] At least 5 options compared with tradeoffs.
- [ ] Live code constraints cited; no stale-doc claims.
- [ ] Failure matrix for malformed/missing/non-string/empty title included.
- [ ] Authority boundary explicit: app owns product field meaning; host owns parsing transport only.
- [ ] Next implementation card specified with file/test scope.
- [ ] No production code changes except optional doc link to the packet.
- [ ] `git diff --check` clean.

## Deliverable

Preferred:

```text
lab-docs/lang/lab-todoapp-api-create-object-body-readiness-p25-v0.md
```

## Closed surfaces

- No compiler grammar change in this card.
- No app behavior change in this card unless explicitly justified as tiny doc-only.
- No schema change.
- No public API stability claim.

