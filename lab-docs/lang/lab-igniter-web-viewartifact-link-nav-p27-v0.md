# lab-igniter-web-viewartifact-link-nav-p27-v0

Card: `LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NAV-P27`
Route: standard / UI vocabulary proof · Skill: idd-agent-protocol
Status: PROVEN (2026-06-25)
Builds on: `LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE` · P26 ViewArtifact evolution readiness.

> Pressure test: is the flat `link` node + app-local helpers enough for real Todo index↔detail navigation
> and next-page pagination — **without** expanding the ViewArtifact schema (no new node kind, no nesting,
> no layout)?

---

## Verdict

**Yes — flat `link` nodes + helpers are enough for v0 navigation and pagination.** Index→detail links and a
"next page" cursor link are expressed as a flat `Collection[HtmlNode]` built by `map` + `append` over a
domain collection, with hrefs from `concat`. **No renderer/schema change was needed** (renderer untouched,
still 15/15). The bounded non-recursive `list`/`item` layout (P26) stays **held** — nav-as-links does not
justify it; it would only be justified by per-item *grouping* (multiple controls bundled per row), which
navigation links do not require.

---

## 1. Exact helper shape (app-local only)

Two helpers over the existing `MakeLink` (`text` = label, `action` = href), plus the nav view contract —
all in `server/igniter-web/examples/todo_view_app/todo_views.ig`:

```ig
pure contract TodoDetailLink {           -- index → /todos/<id>, label = title
  input todo : TodoItem
  compute href : String = concat("/todos/", todo.id)
  compute node : HtmlNode = call_contract("MakeLink", todo.title, href)
  output node : HtmlNode
}

pure contract NextPageLink {             -- cursor pagination: /todos?after=<id>
  input after : String
  compute href : String = concat("/todos?after=", after)
  compute node : HtmlNode = call_contract("MakeLink", "Next page", href)
  output node : HtmlNode
}

pure contract TodoNavHtml {              -- map → detail links, then append the next-page link (flat list)
  input req : Request
  compute todos : Collection[TodoItem] = [
    { id: "1", title: "Buy milk <script>", done: false },
    { id: "2", title: "Write the spec",    done: true  }
  ]
  compute detail_links : Collection[HtmlNode] = map(todos, t -> call_contract("TodoDetailLink", t))
  compute next : HtmlNode = call_contract("NextPageLink", "todo_2")
  compute body : Collection[HtmlNode] = append(detail_links, next)
  compute view : ViewArtifact = call_contract("FormView", "Todos", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

Route (2-segment static suffix, authored before `/todos/:todo_id` per the P18 priority rule):
`route GET "/todos/nav-html" -> TodoNavHtml`.

Renders (inside the `form` layout):
```html
<a class="ig-link" href="/todos/1">Buy milk &lt;script&gt;</a>
<a class="ig-link" href="/todos/2">Write the spec</a>
<a class="ig-link" href="/todos?after=todo_2">Next page</a>
```

---

## 2. href construction — no DX pressure found

`concat(String, String) -> String` is sufficient and clean for every href in scope:
`concat("/todos/", todo.id)` and `concat("/todos?after=", after)`. It is the same string-concat already
proven in `TodoLinkHtml` (link-node card) and across the fleet. **No awkwardness, no missing primitive** for
href building — the card's "if string concatenation is awkward" caveat did not trigger.

List assembly ("map detail links, then add one") is equally clean: **`append(Collection[T], T)`**
(`stdlib.collection.append`, `stdlib_calls.rs:2099`) — `append(detail_links, next)`. (The fleet-proven
`concat(coll, [x])` is an equivalent alternative — `dsa/sets.ig:36`, `trade_robot/robot.ig:94`.) So both
"transform a collection to links" and "append a trailing affordance" are first-class today.

---

## 3. Pagination UX — links only; no layout node needed

A "next page" affordance is exactly one URL-bearing leaf carrying the keyset cursor (`?after=<id>`, already a
live route, data-projection P1). The flat `link` node covers it with no layout/container. A `{items, next}`
*envelope* (server-built next cursor) is a separate data-projection concern (deferred there), not a view-vocab
gap. **Pagination UX needs only links, not a future layout node.**

## 4. One honest observation (not a blocker)

Links render as siblings inside the `form` layout body — there is no dedicated *nav*/*list* semantic
container, and no way to **group** a row's controls (e.g. `title-label + done-button + detail-link` as one
unit). For pure link-lists this is purely cosmetic. It is the *grouping* need — not navigation — that would
justify the bounded `list`/`item` layout (P26 §4); this card does **not** surface that pressure.

---

## 5. Tests / counts (green, 2026-06-25)

- **`server/igniter-web` — `cargo test --test todo_view_app_tests`: 16 passed** (15 prior + 1 new):
  - `nav_html_renders_detail_links_and_next_page_link` — two detail links (`/todos/1`, `/todos/2`) in
    authored order, a next-page link (`/todos?after=todo_2`) appended last, malicious title escaped
    (`Buy milk &lt;script&gt;`), no raw `<script>`.
- **`frame-ui/igniter-render-html` — `cargo test`: 15** (3 lib + 12 integration) — **unchanged**; the
  renderer was not touched. Unsafe-scheme fail-closed is already covered by
  `link_rejects_dangerous_schemes_without_emitting_anchor` (link-node card), so no new renderer test was
  needed.
- `git diff --check` clean. Card diff: **3 files** (`todo_views.ig`, `routes.igweb`, `todo_view_app_tests.rs`),
  additive only. No renderer/schema change; no new node kind; no nesting; no raw HTML; no DB; no CSS.

---

## Reporting

- **Flat link-node nav is enough for v0:** index↔detail links + next-page cursor link are expressed as a flat
  `Collection[HtmlNode]` (`map` + `append`, `concat` hrefs) with app-local helpers — no schema/renderer change.
  href construction shows **no DX pressure** (`concat` suffices).
- **Bounded non-recursive list layout: still HELD, not yet justified.** Navigation-as-links does not need
  grouping; only per-item *grouping* (multiple controls per row) would justify the P26 `list`/`item` layout,
  and this card did not surface that need.
- **Next UI card:** none required now. A `list`/`item` layout card becomes justified only when a real view
  needs to group multiple controls per row (e.g. a todo row with title + done toggle + delete + detail link).
  Until then, continue with flat helpers.
