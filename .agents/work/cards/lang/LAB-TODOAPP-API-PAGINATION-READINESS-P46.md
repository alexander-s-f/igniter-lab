# LAB-TODOAPP-API-PAGINATION-READINESS-P46 - design account-scoped Todo list pagination

Status: CLOSED (2026-06-24) — readiness packet delivered; recommends keyset-on-id (one substrate delta + one transport prereq); next card LAB-TODOAPP-API-PAGINATION-KEYSET-P47
Lane: TodoApp API / product planning
Type: readiness packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

TodoApp API now has a useful product surface: health, list, show, create, done, delete, error envelope,
account existence semantics, ReadThen, multi-source reads, and EffectHost writes.

The next tempting endpoint class is pagination for account-scoped list. This is not a UI-only tweak: keyset
pagination probably forces new read-substrate support (`order_by`, range predicates, cursor semantics, and
stable sort keys). Offset pagination is easier but likely the wrong long-term contract.

Before implementation, choose the smallest honest product pagination semantics and name the substrate delta.

## Goal

Produce a readiness packet for Todo list pagination:

```text
GET /accounts/:account_id/todos?limit=...&after=...
```

or a better explicitly justified alternative.

## Verify First

Read live code and docs:

- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/tests/todo_postgres_*`
- machine/web `IMPLEMENTED_SURFACE.md`
- prior Postgres predicate/readiness cards P9/P10/P11 if present

Confirm what the read executor actually supports today. Do not infer `order_by`/range support from plans.

## Questions To Answer

1. What list ordering is product-stable today, if any?
2. Should v0 use keyset, offset, or explicit "not paginated yet" with cap-only?
3. Which cursor field is legitimate: surrogate todo id, created_at, effect receipt time, or another field?
4. Which new `QueryPlan` fields/operators are required?
5. How does account-existence `404` compose with empty page `200 []`?
6. How should cursors be encoded without leaking DB internals?
7. Which tests prove no duplicate/missing rows across page boundaries?
8. What exact implementation card should follow?

## Required Output

Write `lab-docs/lang/lab-todoapp-api-pagination-readiness-p46-v0.md` with:

- current read-substrate table;
- candidate comparison: cap-only, offset, keyset, opaque cursor, no pagination;
- recommended v0;
- required machine/web deltas;
- refusal/error semantics;
- acceptance matrix for the next implementation card.

## Acceptance

- [x] Grounded in live read executor and Todo app code.
- [x] At least 4 pagination alternatives compared.
- [x] Names exact new substrate, or explains why none is needed.
- [x] Recommends one bounded next card ID.
- [x] Separates product API contract from DB implementation details.
- [x] No production code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

- No implementation.
- No DB migration.
- No new route behavior.
- No canon claim.

## Closing Report (2026-06-24)

**Packet:** `lab-docs/lang/lab-todoapp-api-pagination-readiness-p46-v0.md`.

**Verify-first findings (live source, not inferred from plans):**
- The read substrate ALREADY supports `order_by`, range predicates (`gt/gte/lt/lte`), `in`, and a clamped
  `LIMIT` — fake AND real adapter (`postgres_read.rs` gates; `postgres_real.rs::query` renders `ORDER BY`,
  `<op> $n`, `LIMIT`). It does **NOT** render `OFFSET`.
- `kind_allows_op` permits range only on **Integer/Timestamp**, not **Text**. The Todo `id` is a unique
  **Text** PK (`todo_<blake3>`) → orderable but currently NOT range-filterable, so `WHERE id > $cursor`
  is denied today.
- `ListTodosByAccount` emits **no `order_by`** → the list is currently **unordered** (latent determinism
  bug any pagination must fix first).
- `parse_request` keeps the raw `?query` in `ServerRequest.path` and never parses it → a `?limit=…`
  request would **break route matching outright** today. Query-string support is a real transport
  prerequisite.

**Recommendation:** keyset pagination on the surrogate `id` — `GET …/todos?limit=&after=`, response
`{ items, next }`, opaque base64url cursor = last `id`. `id` is unique+stable ⇒ no duplicate/missing rows
across pages (order is hash-arbitrary, not chronological — acceptable v0). Two bounded deltas:
(1) substrate — allow range ops on Text in `kind_allows_op` (+ pin `COLLATE "C"` in the real adapter for
cross-env determinism); (2) host transport — parse `?query` into a new prelude `Request.query` field.
No new `QueryPlan` field, **no migration**.

**Parked alternatives:** offset (needs new `OFFSET` substrate + wrong long-term contract); composite
chronological keyset `(inserted_at, id)` (needs OR/tuple-comparison substrate — defer); cap-only-forever
(honest fallback, but only real value is adding a stable order); total-count headers (O(n), drifts).

**Next implementation card:** `LAB-TODOAPP-API-PAGINATION-KEYSET-P47` (acceptance matrix §6 of the packet,
incl. a row-0 query-string transport prerequisite).

**Checks:** no production code changed; `git diff --check` clean. Acceptance: grounded in live executor +
app code; 6 alternatives compared; exact substrate/transport deltas named; one bounded next card; product
contract (§3/§5) separated from DB implementation (§4).
