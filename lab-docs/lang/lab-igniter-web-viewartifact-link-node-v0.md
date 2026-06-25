# lab-igniter-web-viewartifact-link-node-v0

Card: `LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE`
Route: standard / implementation proof · Skill: idd-agent-protocol
Status: IMPLEMENTED + proven (2026-06-25)
Builds on: P26 ViewArtifact evolution readiness (`lab-igniter-web-viewartifact-evolution-readiness-p26-v0`).

> First URL-bearing `ViewArtifact` node. Wires the **already-built, already-tested** `safe_url` to a new
> `link` component — no new schema field, no nesting, no raw HTML, no template runtime, no server/protocol
> change.

---

## 1. Exact node shape

Reuses the flat `HtmlNode` fields — **no new field added** (`text` = visible label, `action` = href):

```json
{ "kind": "link", "text": "Next", "action": "/todos?after=todo_2" }
```

renders to:

```html
<a class="ig-link" href="/todos?after=todo_2">Next</a>
```

The prelude `HtmlNode { kind, id, label, text, required, action, options }`
(`lang/igniter-compiler/src/igweb.rs:53-61`) is **unchanged** — `kind` is stringly and the renderer owns the
vocabulary, so a new node kind needs no prelude churn.

---

## 2. Renderer behavior + error behavior

New arm in `render_component` (`frame-ui/igniter-render-html/src/lib.rs`):

```rust
"link" => {
    let href = safe_url(req(cv, "action", "link component")?)?;   // validate + escape href
    let text = escape(req(cv, "text", "link component")?);        // escape label
    Ok(format!("<a class=\"ig-link\" href=\"{href}\">{text}</a>"))
}
```

| Input | Outcome | Error kind |
| --- | --- | --- |
| relative / `http://` / `https://` href | `<a class="ig-link" href="…">label</a>` | — |
| `javascript:` / `data:` / `mailto:` href | **fail closed**, no `<a>` emitted | `UnsafeUrl` |
| missing `text` or `action` | **fail closed** | `InvalidArtifact` |
| href/label with `<`,`>`,`&`,`"`,`'` | escaped (via `safe_url`→`escape` / `escape`) | — |

In IgWeb, a render error surfaces through the **existing** path: `render_to_decision` → JSON **500**
`{"error":"render failed","kind":…}` with no artifact-body leak (`server/igniter-web/src/lib.rs:441-452`).
No new error shape.

---

## 3. Safety story

- **Href allowlist:** every href routes through `safe_url` (`lib.rs:77-102`) — relative refs and `http(s)`
  pass; any other explicit scheme fails closed with `UnsafeUrl`. No bypass.
- **Escaping:** href is escaped inside `safe_url` (`Ok(escape(t))`); label escaped via `escape` — both cover
  the 5 HTML-significant chars (`lib.rs:58-71`). Structured input only, so no markup-injection surface.
- **No raw HTML, no arbitrary attributes**, no `target`/`rel`/`download`/`Content-Disposition` in this slice
  (per card safety rules). Closed vocabulary preserved — unknown `kind` still → `UnsupportedNode`.

---

## 4. Todo authored proof route

`server/igniter-web/examples/todo_view_app/` (authored `.ig`/`.igweb`, no request-body JSON):

```text
-- todo_views.ig
pure contract MakeLink {                          -- app-local helper over the flat record
  input text : String   input href : String
  compute node : HtmlNode = { kind: "link", id: "", label: "", text: text, required: false, action: href, options: [] }
  output node : HtmlNode
}

pure contract TodoLinkHtml {                      -- path param → label AND safe relative href
  input req : Request   input todo_id : Option[String]
  compute id    : String = or_else(todo_id, "none")
  compute label : String = concat("Todo ", id)
  compute href  : String = concat("/todos/", id)
  compute link  : HtmlNode = call_contract("MakeLink", label, href)
  compute body  : Collection[HtmlNode] = [link]
  compute view  : ViewArtifact = call_contract("FormView", "Navigation", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- routes.igweb
route GET "/todos/link-html/:todo_id" -> TodoLinkHtml
```

`GET /todos/link-html/42` → `200 text/html` whose body contains
`<a class="ig-link" href="/todos/42">Todo 42</a>` — the route param flows into both the label and a
fail-closed relative href, end-to-end through the real `.igweb` lowering → VM → `RenderView` → renderer.

---

## 5. Test matrix (all green, 2026-06-25)

**`frame-ui/igniter-render-html` — `cargo test`: 15 passed** (3 lib + 12 integration; +4 new):
- `link_renders_relative_and_http_s_anchors` — `/todos/42`, `?after=`, `http(s)://…`, `./detail` → `<a>`;
- `link_rejects_dangerous_schemes_without_emitting_anchor` — `javascript:`/`data:`/`mailto:` → `UnsafeUrl`,
  no anchor;
- `link_text_and_href_are_escaped` — `<script>` label + `&` href both escaped;
- `link_missing_text_or_action_fails_closed` — `InvalidArtifact`.

**`server/igniter-web` — `cargo test --test todo_view_app_tests`: 15 passed** (14 prior + 1 new):
- `link_node_renders_safe_relative_href_from_path_param` — authored route → `<a class="ig-link"
  href="/todos/42">Todo 42</a>`;
- the 14 prior view tests (incl. the unsupported-node fail-closed and helper-byte-identical) remain green.

`git diff --check` clean. Card diff: **5 files, +134 lines, additive only.**

---

## 6. Files changed

| File | Change |
| --- | --- |
| `frame-ui/igniter-render-html/src/lib.rs` | +9 — `link` arm in `render_component` (safe_url + escape) |
| `frame-ui/igniter-render-html/tests/render_html_tests.rs` | +73 — 4 `link_*` tests |
| `server/igniter-web/examples/todo_view_app/todo_views.ig` | +27 — `MakeLink` + `TodoLinkHtml` |
| `server/igniter-web/examples/todo_view_app/routes.igweb` | +2 — `/todos/link-html/:todo_id` route |
| `server/igniter-web/tests/todo_view_app_tests.rs` | +23 — authored-route test |

Untouched (per boundary): prelude (`igweb.rs`), server-core (`igniter-server`), renderer layouts, no new
language syntax.

---

## 7. Is this enough for TodoApp navigation/pagination?

**Yes for the v0 affordances:** index→detail links and "load more"/`?after=<cursor>` pagination both need
exactly one URL-bearing leaf, which the `link` node now provides (the keyset `?after=` route is already live,
data-projection P1). What remains for richer list UI is **per-item grouping** (a todo row = title + its own
action buttons + its detail link grouped) — that is the **bounded, non-recursive `list`/`item` layout**
deferred by P26 (a distinct `ListItem` type, never a self-referential `HtmlNode`), pursued only on demonstrated
need.

---

## 8. Next cards

- **`LAB-IGNITER-WEB-VIEWARTIFACT-LIST-LAYOUT`** (held, on demand) — the bounded one-level `list`/`item`
  grouping from P26 §4; distinct `ListItem { title, body : Collection[HtmlNode] }`, mirrors `workbench`,
  **no recursion**.
- **TodoApp HTML list** (after data-projection typed-row crossing) — render the list from typed read rows
  (P4 Idiom A) now able to include per-row detail links via this node.
- Download/export links (`Content-Disposition`) — explicitly out of this slice; rides the P27 raw seam later.
