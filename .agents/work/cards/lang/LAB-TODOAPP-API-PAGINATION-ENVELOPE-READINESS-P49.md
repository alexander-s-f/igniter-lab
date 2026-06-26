# LAB-TODOAPP-API-PAGINATION-ENVELOPE-READINESS-P49

Status: CLOSED (2026-06-26) — readiness/design (no code); recommend Alt B (`{items,next}` via generic `RespondJson` arm), next card `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50`
Route: standard / product API readiness
Skill: idd-agent-protocol

## Goal

Decide the next product shape for Todo list pagination:

```json
{ "items": [ ... ], "next": "todo_..." }
```

or a deliberately smaller alternative.

Today keyset pagination is implemented via `?after=<id>`, but the JSON route
returns a bare rows array and clients derive the next cursor from the last row.
This card should decide whether we now have enough typed-row substrate to move
the product route to an explicit envelope without inventing new host machinery.

This is readiness/design only unless the live source proves the implementation
is trivial and already scoped by an existing card. Default: no code.

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/typed_readthen_tests.rs`
- `server/igniter-web/tests/typed_row_crossing_tests.rs`
- `server/igniter-web/tests/typed_html_tests.rs`
- `lab-docs/lang/current-waves-index.md`

Live code wins. In particular, verify whether typed continuations can already
receive `rows : Collection[TodoRow]` and `meta : DatasetMeta` for a product
route, rather than assuming the old `rows_json` limitation still holds.

## Questions To Answer

1. Should the product JSON list route migrate from legacy `rows_json` to typed
   `rows : Collection[TodoRow]` now?
2. Where should `next` be computed?
   - app continuation from `last(map(rows, r -> r.id))`;
   - host `DatasetMeta`;
   - client only (status quo).
3. What is the v0 response shape?
   - `{ "items": rows, "next": cursor_or_empty }`;
   - `{ "items": rows, "page": { "next": ... } }`;
   - keep bare array until client pressure.
4. How should exhausted pages represent no cursor?
   - `""`;
   - `null`;
   - omit `next`.
5. Does client `?limit=` belong in the same slice, or stay deferred behind
   host cap / validation?
6. What exactly breaks, if anything, if the current app still uses legacy
   `rows_json` for JSON while typed rows are proven for HTML fixtures?

## Closed Surfaces

- No implementation unless explicitly and narrowly justified in the report.
- No new host pagination substrate.
- No DB schema changes.
- No offset pagination.
- No chronological ordering unless a composite cursor is designed separately.
- No global API protocol envelope.
- No production API stability claim.

## Acceptance

- [x] At least three alternatives compared, incl. status quo. — A (status quo) / B (envelope) / C (host-assembled) / D (nested)
- [x] Recommendation names one concrete next card with ID. — `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50`
- [x] States whether typed rows are sufficient today for the product route. — INPUT ready (P7/P21); OUTPUT needs generic `RespondJson` arm
- [x] States exact envelope shape if recommended. — flat `{ "items": [...], "next": "<id>"|"" }`
- [x] States whether `?limit=` included or deferred. — **deferred** (host cap + meta.truncated suffice)
- [x] States test matrix (empty / truncated / missing account / denied source / malformed cursor + arm unit).
- [x] No production code changes.
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Verdict:** readiness/design, **no code**. Verify-first found the precise gap: typed-row INPUT is ready for a
product route TODAY (P7 auto-routing + P21's `AccountTodoHtmlFromRows(rows:Collection, meta:DatasetMeta)`), but
a typed `{items, next}` JSON OUTPUT needs ONE small generic decision arm — `RespondJson { status, body :
Unknown }` (the JSON-lane analogue of `RespondView`; `src/lib.rs:470` is the ~10-line template; `Unknown`
payload is the proven `InvokeEffect.input` pattern). The host CANNOT build the envelope: `DatasetMeta` has no
cursor; `next` is app-derived (`last(map(rows, r->r.id))`, P21), and host pagination is out of scope.

**Recommendation = Alternative B.** Flat `{ "items": [<TodoRow>...], "next": "<id>"|"" }`; `next` computed in
the app continuation `if meta.truncated { or_else(last(ids),"") } else { "" }`; exhausted page → `""`; `?limit=`
deferred (host cap + `meta.truncated` suffice). Nothing breaks keeping JSON on `rows_json` meanwhile (P21 runs
both lanes green) — migration is an ergonomics upgrade, not a fix. Rejected: C (host-assembled — no cursor /
forbidden substrate), D (nested `page` — premature).

**Next card:** `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50` (two steps: land `RespondJson` generic arm; migrate
the Todo JSON list to typed rows + `{items,next}`). Doc:
`lab-docs/lang/lab-todoapp-api-pagination-envelope-readiness-p49-v0.md`. `git diff --check` clean.

## Suggested Output

Create:

```text
lab-docs/lang/lab-todoapp-api-pagination-envelope-readiness-p49-v0.md
```

Close the card with a compact decision table and next-card route.

