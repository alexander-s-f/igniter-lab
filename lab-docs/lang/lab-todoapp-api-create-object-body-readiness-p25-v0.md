# LAB-TODOAPP-API-CREATE-OBJECT-BODY-READINESS-P25 — readiness packet

**Date:** 2026-06-23
**Type:** readiness packet (no implementation)
**Question:** how to move the create body from the awkward v0 (`"Buy milk"` bare JSON string) to a real
object (`{ "title": "Buy milk" }`) without `.ig` gaining hidden JSON-parsing authority?

## TL;DR recommendation

**Target v1 shape: `{ "title": "Buy milk" }`, consumed via a GENERIC typed host body surface
(`req.body_json : Map[String, Unknown]`) + a real `stdlib.map.get(req.body_json, "title")` in `.ig`.**
This is the only option that keeps the authority boundary honest: the **host parses transport** (JSON →
Map, never knowing "title" is special); the **app owns the product field meaning**.

**It is NOT tiny today — it is blocked on a language/VM gate, not on the Todo app.** The Map type exists
only in the typechecker (LAB-MAP-RUST-P1); the **VM has no `Value::Map` and no `stdlib.map.get`
evaluation**. So the first card after this packet is a **machine/VM card**, and **until it lands the
Todo API stays on string-body v0 (P18)** — which is already shipped, fail-closed, and honest. Forcing
object body sooner (host-projected `req.body_title`) is rejected: it leaks a product field name into the
generic prelude/runner.

## Verify-first: live-code constraints (cited)

- **Body crossing** — `server/igniter-web/src/lib.rs::build_request_input` crosses `req.body : String`
  (a JSON-string body → its inner string; any other shape → compact text / empty) and, since P18,
  `req.body_kind : String` (host-computed JSON SHAPE: `"string"` / `"empty"` / `"object"` / `"array"` /
  `"number"` / `"bool"`). The host already holds the parsed `serde_json::Value` here — the one place the
  shape is known.
- **Prelude `Request`** — `lang/igniter-compiler/src/igweb.rs`: fields `method, path, body, body_kind,
  correlation_id, idempotency_key`, all `: String`. No `Map`/object field.
- **App handler** — `examples/todo_postgres_app/todo_handlers.ig::AccountTodoCreate` guards
  `if req.body_kind == "string" { InvokeEffect … } else { Respond 400 }`; the title is the whole
  `req.body` string. Field access in `.ig` is only ever on **typed** records (`ctx.account_id`,
  `intent.key`) whose field types the typechecker resolves — never on an untyped/`Unknown` value.
- **stdlib surfaces** —
  - `stdlib.map.get|has_key|from_pairs|empty` have **typechecker signatures**
    (`typechecker/stdlib_calls.rs:2468+`, `stdlib.map.get(Map[String,V], String) → Option[V]`) but
    **no VM dispatch** (`grep` of `runtime/igniter-machine/src` finds zero `stdlib.map.*` evaluation).
    `Map[String,V]` is compile-time inference only (LAB-MAP-RUST-P1).
  - **No `stdlib.json.*`** anywhere (no parse / get_string).
  - `string` ops exist (`stdlib.string.{concat,char_at,substring}`) — character surgery, not JSON.
  - `VMValue::from_json` is the **host→VM input bridge** (crosses a serde `Value` into a VMValue for
    contract inputs), not an `.ig`-callable accessor.
- **Conclusion:** `.ig` cannot extract a JSON-object field today. Any object-body path needs EITHER a new
  host-projected field (product-meaning leak) OR a real VM Map/JSON surface (language gate).

## Options compared

| # | Option | Authority | Tiny today? | Verdict |
|---|---|---|---|---|
| 1 | **Host-projected product field** `req.body_title : String` (host parses `{title}` and crosses the value) | ✗ host learns a product field name; the *generic* prelude/runner gains Todo-specific meaning | mechanically yes | **Reject as the generic path.** Acceptable only as a per-app escape hatch, which we don't need. |
| 2 | **Generic `req.body_json : Map[String, Unknown]`** + `stdlib.map.get(body_json,"title")` in `.ig` | ✓ host = transport (JSON→Map); app = field meaning | **No** — needs VM `Value::Map` + `stdlib.map.get` eval | **Recommended v1**, gated on a language card. |
| 2b | Interim: host crosses `req.body_json : Unknown` (parsed object) + `.ig` does `req.body_json.title` | ✓ same split as #2 | partial — relies on VM dynamic field access on `Unknown`, which is **not an established pattern** (all `.ig` field access is on typed records) and is typechecker-soft (everything `Unknown`); gives no clean missing/non-string 400 | **Reject** — softer and less honest than #2; not worth a half-measure. |
| 3 | **stdlib JSON extractor** `stdlib.json.get_string(req.body, "title") → Option[String]` | ✓ host parses nothing; `.ig` calls a pure stdlib | **No** — new stdlib builtin: compiler signature + VM impl | Viable alternative to #2; slightly worse (a bespoke JSON surface vs reusing the already-typechecked Map). Prefer #2. |
| 4 | **Keep string body v0** (P18), document it | ✓ trivially | **Yes — already shipped** | **Current state. Recommended to hold here until #2's language gate lands.** |
| 5 | **Host capability parses the body** | ✗ product meaning moves into a host capability | n/a | **Reject** (per the card) — capability would encode "a Todo has a title". |

## Questions answered

1. **What body surface can `.ig` consume without raw JSON parsing becoming app magic?** A typed
   `Map[String, Unknown]` (Option 2) — the host does the parse; `.ig` only *selects* a key via a real
   stdlib accessor. `.ig` never parses bytes.
2. **Can the compiler/typechecker express optional object fields today?** Partially: `stdlib.map.get`
   already types to `Option[V]` (`stdlib_calls.rs:2468`), and Option handling (`or_else`) is live in the
   handlers. The **typechecker is ready; the VM is not** (no Map evaluation).
3. **Does Map/Unknown support make this easy or a larger language gate?** It is a **language gate**: the
   VM must gain `Value::Map`, `VMValue::from_json` must map a JSON object → `Value::Map`, and
   `stdlib.map.get` (ideally also a `get_string` returning `Option[String]`) must be evaluated. Bounded,
   but real machine work — not a Todo-app edit.
4. **Failure matrix (object body v1, once Map lands):**

   | Body | Detection | Status |
   |---|---|---|
   | `{ "title": "Buy milk" }` | `map.get → Some("Buy milk")` (non-empty string) | 200 |
   | missing `title` key | `map.get → None` → app maps None | **400** |
   | `{ "title": 5 }` non-string | `map.get → Some(non-string)` → app/`get_string` rejects | **400** |
   | `{ "title": "" }` empty | `map.get → Some("")` → app's non-empty rule (same as today) | **400** |
   | malformed JSON / non-object body | host can't build a Map → `body_kind != "object"` → guarded **before** `body_json` is read | **400** |

   The host pre-check (`body_kind`) keeps malformed/non-object out before the app touches `body_json`;
   the in-`.ig` `map.get` covers missing/non-string/empty title. No new host product knowledge.
5. **Where should escaping/redaction happen in diagnostics?** Body content is **user data, not a
   secret** — the P29 redactor (DSN/passport) does not apply. The rule is simpler: **never echo raw body
   bytes into a diagnostic.** A rejection names the *failure* (`"missing title"`, `"title not a
   string"`), never the submitted body — this avoids log-injection / oversized-payload noise. No new
   redaction machinery needed.
6. **Authority boundary (explicit):** the **app** owns product field meaning — only `.ig` says the title
   lives at key `"title"`. The **host** owns transport only — `build_request_input` parses JSON into a
   generic `Map`/shape signal and never names `"title"`. This mirrors the existing `body_kind` split
   (host = shape, app = decision).

## Next implementation cards (specified)

**Card A — prerequisite, language/VM (machine):**
`LAB-MACHINE-MAP-VALUE-AND-STDLIB-GET-Pxx`
- Add a `Value::Map` (string-keyed) to the VM value model; `VMValue::from_json` maps a JSON object →
  `Value::Map`. Implement `stdlib.map.get(map, key) → Option[V]` evaluation (the typechecker signature
  already exists at `typechecker/stdlib_calls.rs:2468`); add `stdlib.map.has_key`; consider
  `stdlib.map.get_string → Option[String]` (fails closed on a non-string value, simplifying the v1 400
  matrix). Bump `STDLIB_VERSION` if the surface changes.
- Scope: `runtime/igniter-machine/src/` (value model + stdlib dispatch); machine unit tests. No Todo app
  files. No grammar change.

**Card B — after A, Todo app (igniter-web):**
`LAB-TODOAPP-API-CREATE-OBJECT-BODY-Pxx`
- `build_request_input` (lib.rs): when the body is a JSON object, cross it as
  `req.body_json : Map[String, Unknown]` (keep `body` + `body_kind` for back-compat).
- prelude `Request` (igweb.rs): add `body_json : Map[String, Unknown]`.
- `AccountTodoCreate` (todo_handlers.ig): read `title` via `stdlib.map.get(req.body_json, "title")`,
  build the failure matrix above. Accept BOTH the new object form and the legacy string form during a
  deprecation window if desired (or flip to object-only with a documented break).
- API.md: document object body as v1; tests in `todo_postgres_app_tests` (shape/400 matrix, sync),
  `todo_postgres_effect_host_tests` (rejected → no effect host), `todo_postgres_local_e2e_tests`
  (real-DB happy path + rejected-writes-no-row).

## Recommendation summary

Hold the Todo API at **string-body v0** now. The honest v1 is **object body via a generic
`Map[String, Unknown]` surface (Option 2)**, which is **blocked on a small machine/VM card (Card A)**.
Do Card A first (it benefits the whole language, not just Todo), then Card B. Do not ship a
host-projected product field as a shortcut — it would leak Todo meaning into the generic runner.
