# LAB-TODOAPP-API-CLIENT-LIMIT-READINESS-P54

Status: CLOSED (2026-06-26) — readiness (no code); recommend status quo A (host-cap page size); arbitrary `?limit=` deferred behind 2 enablers (String→Integer parser + faithful truncated)
Route: standard / product API readiness
Skill: idd-agent-protocol

## Goal

Decide whether and how the Todo API should expose a client-tunable `?limit=`
parameter on the list route now that P47/P50 provide server-fixed keyset
pagination:

```text
GET /accounts/:account_id/todos?after=<id>&limit=<n>
```

This is a readiness card because `limit` touches product semantics, host caps,
bad-input behavior, query parsing, and abuse boundaries. Do not implement a
parser or host behavior change until this packet makes the contract crisp.

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/src/lib.rs` request/query crossing
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/read_materialize.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`

Live source wins. Verify what `Request.query` can represent today and how
`QueryPlan.limit` is currently clamped by host policy.

## Questions To Answer

1. Should `limit` be app-owned (`.ig` reads `req.query`) or host-owned
   (`host.toml` cap only, no client parameter)?
2. What is the accepted syntax: missing, empty, non-integer, negative, zero,
   huge, repeated `limit`?
3. What is the product default?
4. What is the max bound and who owns it: app constant or host cap?
5. Does `limit=0` mean bad request or empty page?
6. Should the response expose `next` only, or also nested metadata like
   `{page:{limit,truncated}}`?
7. Does a smaller client limit affect `meta.truncated` and `next` correctly?
8. Should bad `limit` be an app `RespondError` 400 or a host 400/403?
9. Does this require new stdlib parsing (`to_integer`, parse_int) or can the
   current language express it cleanly?
10. What is the minimum implementation card if the answer is proceed?

## Candidate Shapes

Compare at least these:

- A. no client limit; host cap only (current behavior);
- B. app parses `req.query.limit` and sets `QueryPlan.limit`, host still clamps;
- C. host parses and clamps `limit` before `.ig`;
- D. expose only a few named sizes (`small`/`large`) rather than arbitrary int;
- E. defer until typed query-param parsing exists.

## Closed Surfaces

- No implementation in this card.
- No offset pagination.
- No chronological/composite cursor.
- No global request parser redesign.
- No raw SQL.
- No host cap bypass.
- No production stability promise.

## Acceptance

- [x] Packet written under `lab-docs/lang/`. — `lab-todoapp-api-client-limit-readiness-p54-v0.md`
- [x] Live `Request.query` + `QueryPlan.limit` verified. — query=`Map[String,Unknown]` strings (lib.rs:394-411); clamp `clamp(0,cap)`, `truncated=requested>cap` (postgres_read.rs:518-533)
- [x] ≥5 alternatives compared. — A–E
- [x] Bad-input taxonomy specified.
- [x] Authority split named. — host owns cap; app owns product page-size + 400s
- [x] Recommended next card named / defer decision. — status quo A now; B behind `LAB-LANG-STRING-TO-INTEGER` + `…-FAITHFUL-PAGE-TRUNCATED` + `…-CLIENT-LIMIT-IMPL`
- [x] No production code changed.
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Verdict:** readiness, **no code**. **Recommend status quo A (host-cap page size); do NOT add arbitrary
`?limit=<n>` yet.** Two independent live-source blockers:
1. **No String→Integer parser in `.ig`** — `?limit=20` crosses as String `"20"` (`req.query : Map[String,
   Unknown]`, lib.rs:394-411) but `QueryPlan.limit : Integer`; `grep to_integer|parse_int` = no match (only
   `to_float`). So the app can't set a numeric plan limit from the query (Alternative B blocked).
2. **`truncated` unfaithful below cap** — `clamped = requested > row_limit` (postgres_read.rs:533), i.e.
   `truncated` = "requested > host cap", NOT "more rows exist." A sub-cap client limit → `truncated=false` even
   with more rows → `next` wrongly empty. Faithful client-limit paging needs host N+1/count (new host behavior).

Only **D (named sizes)** is expressible today (string equality, no parser) but still needs blocker #2. **Authority:**
host owns the hard cap (`row_limit`); app owns the product page-size semantics + bad-input 400s
(`RespondError`). **`limit=0`/negative/non-integer → app 400; `>cap` → clamp (not error); absent → default.**
The **P50 `{items, next}` envelope remains valid and correct WITHOUT a client limit** (now live in
`todo_handlers.ig` `AccountTodoIndexFromRows`).

**Next (if proceeding):** `LAB-LANG-STRING-TO-INTEGER` (stdlib parser, mirrors to_float/to_text) →
`LAB-TODOAPP-API-FAITHFUL-PAGE-TRUNCATED` (host N+1/count) → `LAB-TODOAPP-API-CLIENT-LIMIT-IMPL` (Alt B).
Otherwise defer (E). Doc: `lab-docs/lang/lab-todoapp-api-client-limit-readiness-p54-v0.md`. `git diff --check` clean.

## Reporting

Close with:

- recommended contract for `?limit=`;
- exact bad-input behavior;
- whether new language/std-lib parsing is required;
- next card ID if proceeding;
- explicit statement that current P50 `{items,next}` remains valid without
  client `limit`.

