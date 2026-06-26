# lab-todoapp-api-pagination-envelope-readiness-p49-v0

Card: `LAB-TODOAPP-API-PAGINATION-ENVELOPE-READINESS-P49`
Route: standard / product API readiness · Skill: idd-agent-protocol
Status: readiness/design only — **no production code** · no canon claim
Date: 2026-06-26
Builds on: P47 keyset `?after=` · P7 typed `ReadThen` crossing · P21 DB-backed Todo HTML (typed product route)

> **Authority boundary.** Design only. Decides the next product shape for Todo list pagination; implements
> nothing, changes no host machinery, makes no API-stability or canon claim. Every concrete claim is checked
> against live `igniter-lab` source.

---

## Headline

**Typed rows are READY for the product route's INPUT, but a typed `{items, next}` JSON OUTPUT envelope needs
exactly ONE small generic decision arm — `RespondJson { status, body : Unknown }` — not new pagination
machinery.** The input half (a continuation receiving `rows : Collection[TodoRow]` + `meta : DatasetMeta`) is
already proven for a *product* route (P21's `AccountTodoHtmlFromRows`). The output half is blocked only because
(a) `.ig` cannot serialize a record to a JSON string, and (b) no decision arm carries an arbitrary app record
to the JSON body root (`RespondView` is typed to the fixed `View`). The host cannot fill the gap: it has
`DatasetMeta {source,count,truncated}` but **no cursor** — `next` is app-derived (last row id), and host-built
pagination is out of scope.

**Recommendation: implement the envelope (Alternative B)** as a single next card that lands the generic
`RespondJson` arm (the JSON-lane analogue of `RespondView`) and migrates the list continuation to typed rows.
**`?limit=` deferred.**

---

## Verify-first findings (live source)

| Claim | Live evidence |
| --- | --- |
| Current JSON list returns a **bare array string** | `AccountTodoIndexFromRows(rows_json : String) → Respond { body: rows_json }` (`examples/todo_postgres_app/todo_handlers.ig:161-166`). Client derives the next cursor from the last row's `id`. |
| Typed rows + meta reach a **product** continuation today | P21 `AccountTodoHtmlFromRows(rows : Collection[TodoHtmlRow], meta : DatasetMeta)` is auto-routed through `dispatch_with_read` (P7) and green (`tests/todo_postgres_html_tests.rs`). |
| App can derive `next` in-language | P21: `or_else(last(map(rows, r -> r.id)), "")` — last crossed row id (the `?after=` cursor). |
| **No generic JSON-record response arm exists** | The `Decision` variant has `Respond{body:String}` / `RespondView{view:View}` / `RespondError{error:ApiError}` / `RenderView{view:ViewArtifact}` / … — none carries an arbitrary app record to a JSON body root (`lang/igniter-compiler/src/igweb.rs` PRELUDE_SOURCE; `grep RespondJson` = no match). |
| `RespondView` already serializes a record → JSON root | `map_decision`: `"RespondView" => ServerResponse::json(status, fields.get("view"))` (`src/lib.rs:470-474`). A `RespondJson` arm is a ~10-line clone reading `body` instead of `view`. |
| `Unknown`-typed payload in a Decision is a proven pattern | `InvokeEffect { input : Unknown }` (P7 structured effect input) — `RespondJson { body : Unknown }` reuses it exactly. |
| Two lanes already coexist | P21: the same app serves the legacy `rows_json` JSON index AND the typed HTML route; both green. **Nothing breaks** keeping JSON on `rows_json` while HTML uses typed rows (Q6). |

**So the gap is precise and small:** a generic `RespondJson { status, body : Unknown }` decision arm +
map_decision arm (serialize `body` as the JSON root). It is NOT pagination-specific, NOT a host substrate, NOT
a global protocol envelope — it is the JSON-lane analogue of `RespondView`, reusable anywhere an app wants to
return a typed record as JSON.

---

## Alternatives compared (≥3, incl. status quo)

| # | Option | Code cost | Pros | Cons | Verdict |
| --- | --- | --- | --- | --- | --- |
| **A** | **Status quo** — bare `rows_json` array; client derives cursor | none | zero work; already shipping | client must know the cursor field (`id`); no explicit "no more pages" signal in JSON (client infers from page size); HTML lane already computes `next` app-side → duplication | baseline |
| **B** | **Typed `{ items, next }` via a generic `RespondJson { body : Unknown }`** | small (1 decision arm + 1 map_decision arm + typed list continuation) | explicit envelope; `next` computed once app-side (reuses P21 `last(map(..,r->r.id))`); the `RespondJson` arm is reusable infra (JSON analogue of RespondView); typed rows already proven | adds one decision-grammar arm (prelude + map_decision); `done` stays a String in `items` (host Text decode) until a typed-Bool lane | **RECOMMENDED** |
| C | **Host-assembled envelope** (`{items, meta}` built by the host) | medium | host owns provenance | host has **no cursor** (`DatasetMeta` lacks `next`); building it = new host pagination substrate (FORBIDDEN); mixes authority (cursor is app meaning) | rejected |
| D | **Nested `{ items, page: { next } }`** | small+ | room for future page fields (`has_more`, `count`) | more structure than v0 needs; no current consumer for a `page` object | defer (revisit if a 2nd page field lands) |

---

## Decisions (Q1–Q6)

1. **Migrate the JSON list to typed rows now?** — **Yes (via B).** The typed input is ready (P7/P21); the only
   blocker is the output arm. Migrating also removes the `rows_json` stringly boundary from the product's main
   list route, aligning it with the HTML lane.
2. **Where is `next` computed?** — **App continuation**, `next = if meta.truncated { or_else(last(map(rows, r
   -> r.id)), "") } else { "" }`. Uses the **app-derived cursor** (last id) gated by **host `meta.truncated`**
   (is there another page). Not host-built (C rejected); not client-only (that's status quo A).
3. **v0 response shape?** — flat **`{ "items": [<TodoRow>...], "next": "<id>" | "" }`** (Alternative B's shape).
   Reject the nested `page` object (D) until a second page field is needed.
4. **Exhausted page cursor?** — **`""`** (empty string). Consistent with the existing `?after=""` = first-page
   convention; avoids `null`/omit, which would need an `Option` field + conditional serialization (more
   machinery). `meta.truncated == false → next == ""`.
5. **`?limit=`?** — **DEFERRED.** The host `row_limit` cap already clamps and `meta.truncated` already signals
   more; a client `?limit=` adds a bound-check + host-cap-interaction surface with no current product pressure.
   Separate card behind real pressure.
6. **What breaks if JSON stays `rows_json` while HTML is typed?** — **Nothing.** P21 already runs both lanes in
   one app, green. Migration is an ergonomics upgrade (explicit envelope + single cursor source), not a fix.

---

## Recommended envelope (if B is taken)

```text
type TodoPage {
  items : Collection[TodoRow]   -- TodoRow {id, account_id, title, done : String}  (host Text decode; matches P21)
  next  : String                -- last row id when meta.truncated, else ""
}

pure contract AccountTodoListEnvelope {        -- the typed list continuation
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  compute ids  : Collection[String] = map(rows, r -> r.id)
  compute next : String = if meta.truncated { or_else(last(ids), "") } else { "" }
  compute page : TodoPage = { items: rows, next: next }
  compute d : Decision = RespondJson { status: 200, body: page }   -- NEW generic arm
  output d : Decision
}
```

Wire body: `"RespondJson" => ServerResponse::json(get_i("status"), fields.get("body"))` — the exact
`RespondView` shape (`src/lib.rs:470`), reading `body` instead of `view`. Prelude gains
`RespondJson { status : Integer, body : Unknown }` (the `Unknown` open-payload pattern from `InvokeEffect`).

**Empty page** → `items: [], next: ""` (a list of zero is a valid 200, not a 404 — same posture as the HTML
empty state). **Account existence** stays the JSON index's two-stage concern (unchanged) if the envelope route
reuses `AccountTodoIndex`'s two-stage read; a single-stage envelope lists `200 {items:[],next:""}` for an
unknown account (document whichever the impl picks).

---

## Test matrix (for the implementation card)

DB-free, fake adapter, `--features machine`:

- **Found page (not truncated):** `cap ≥ rows` → `{ items: [t1,t2], next: "" }` (no more pages).
- **Truncated page:** `cap 1` → `{ items: [t1], next: "t1" }` (cursor = last crossed id); a follow-up
  `?after=t1` returns the next page.
- **Empty page:** no rows → `{ items: [], next: "" }`, 200 (app-owned, not host error).
- **Missing account:** per the chosen read shape — two-stage → 404 (unchanged), or single-stage → `{items:[],
  next:""}` 200 (documented).
- **Denied source:** host policy without `todos` → 403 before adapter (P7 path, unchanged).
- **Malformed cursor:** `?after=<opaque>` is a keyset value, not parsed — returns rows after it (possibly
  empty); no validation error (the cursor is an opaque id string). Note this explicitly so "malformed" isn't
  expected to 400.
- **RespondJson arm unit:** a `RespondJson { body: <record> }` serializes the record as the JSON body root
  (mirrors the `RespondView` test).

---

## Recommendation + next card

**Take Alternative B.** Typed rows are sufficient for the product route *today*; the only missing piece is one
small, reusable decision arm.

**Next card: `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50`** — two narrow steps in one card:
1. **`RespondJson { status, body : Unknown }`** — generic structured-JSON response (prelude `Decision` arm +
   `map_decision` arm cloned from `RespondView`); the JSON-lane analogue of `RespondView`, reusable beyond
   pagination. (If preferred, split this as `LAB-IGNITER-WEB-RESPOND-JSON-DECISION-P50a` first.)
2. **Migrate the Todo JSON list** to a typed continuation building `TodoPage { items, next }` and returning
   `RespondJson`; `next` per Q2/Q4; keep `?after=` as-is; `?limit=` out of scope; JSON show/create/done/delete
   untouched.

Deferred (named): `?limit=` validation; nested `{items, page:{...}}` (D); typed-`Bool` `done` in `items` (the
typed-Bool projection lane); a `total`/`has_more` field on the envelope.

---

## Acceptance self-check

- [x] ≥3 alternatives compared incl. status quo (A/B/C/D).
- [x] Recommendation names one concrete next card with ID (`LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50`).
- [x] States typed rows are sufficient *today* for the product route input (yes; output needs `RespondJson`).
- [x] States exact envelope shape (`{ "items": [...], "next": "<id>"|"" }`).
- [x] States `?limit=` deferred.
- [x] States test matrix (empty / truncated / missing account / denied source / malformed cursor + arm unit).
- [x] No production code changes; `git diff --check` clean.
