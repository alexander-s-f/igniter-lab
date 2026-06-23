# LAB-TODOAPP-API-CREATE-OBJECT-BODY-READINESS-P25 - JSON object create body shape

Status: CLOSED
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

- [x] Packet names the recommended v1 body shape. (`{ "title": "…" }` via generic `Map[String,Unknown]` + `stdlib.map.get`)
- [x] At least 5 options compared with tradeoffs. (6: host-projected field, generic Map, Unknown field-access interim, json extractor, keep-string, host capability)
- [x] Live code constraints cited; no stale-doc claims. (build_request_input, prelude Request, todo_handlers, stdlib_calls.rs:2468 Map-typechecker-only, no VM map dispatch, no stdlib.json)
- [x] Failure matrix for malformed/missing/non-string/empty title included.
- [x] Authority boundary explicit: app owns product field meaning; host owns parsing transport only.
- [x] Next implementation card specified with file/test scope. (Card A machine/VM Map; Card B Todo object body)
- [x] No production code changes except optional doc link to the packet. (only API.md roadmap pointer)
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Deliverable:** `lab-docs/lang/lab-todoapp-api-create-object-body-readiness-p25-v0.md`

**Recommendation:** target v1 = `{ "title": "…" }` consumed via a GENERIC `req.body_json :
Map[String, Unknown]` host surface + a real `stdlib.map.get(req.body_json, "title")` in `.ig` (Option 2)
— the only path that keeps the host as pure transport (JSON→Map) and the app as the owner of which field
means the title. **It is blocked on a small machine/VM gate, not on the Todo app:** the `Map` type is
typechecker-only (LAB-MAP-RUST-P1, signature at `typechecker/stdlib_calls.rs:2468`); the VM has **no
`Value::Map` and no `stdlib.map.get` evaluation**, and there is **no `stdlib.json.*`** at all. So the Todo
API **holds at string-body v0 (P18)** until the language gate lands. Host-projected `req.body_title`
(Option 1) is rejected — it leaks a product field name into the generic prelude/runner.

**Two next cards specified:** (A) machine/VM `LAB-MACHINE-MAP-VALUE-AND-STDLIB-GET-Pxx` — `Value::Map` +
`from_json` object→Map + `stdlib.map.get` eval (+ optional `get_string`); (B) after A,
`LAB-TODOAPP-API-CREATE-OBJECT-BODY-Pxx` — `body_json` crossing, prelude field, `AccountTodoCreate`
extraction + 400 matrix, API.md + tests. Doc-only change to the repo: a roadmap pointer added to
`API.md`'s body-contract section. `git diff --check` clean.

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

