# lab-igniter-web-viewartifact-list-authoring-p21-v0 — ViewArtifact list authoring from collections

**Card:** `LAB-IGNITER-WEB-VIEWARTIFACT-LIST-AUTHORING-P21` · **Delegation:** `OPUS-IGWEB-VIEWARTIFACT-LISTS-P21`
**Status:** CLOSED (lab implementation-proof) — a list view is authored by **`map`-ing a domain
`Collection[TodoItem]` into `Collection[HtmlNode]`** with a helper-contract callback, then `FormView` +
`RenderView` → real `text/html`. **Alternative A worked first try with existing live language features — no
new syntax, no prelude/compiler/Rust/renderer change, no `.ig.html`/`.igv`/template engine.**
**Authority:** Lab tooling. App-local only (Todo fixture + test); the renderer/server boundary is untouched.

## Verify-first (decisive live findings)

`map` + lambda + helper-contract callback is **already a live, proven `.ig` shape** — no invention needed:

| Fact | Evidence |
|---|---|
| `map(coll: Collection[T], mapper: (T) -> U) -> Collection[U]` | `lang/igniter-stdlib/stdlib/collections.ig` (`def map`) |
| lambda syntax is `param -> expr` (arrow), `map` is a plain call | `apps/.../bookkeeping/ledger.ig:8` `map(debits, p -> p.amount)` |
| **the lambda can call a helper contract** | `apps/.../batch_importer/validate.ig:37` `map(rows, r -> call_contract("ValidateRow", r))` |
| **`map(...) → Collection[Record]` via `call_contract`, with element-type annotation** | `apps/.../bloom_filter/example.ig:18` `compute slots : Collection[BitSlot] = map(range(0,16), i -> call_contract("MakeSlot", i))` |
| records serialize clean; renderer kind-dispatched + escapes (P19/P20) | unchanged |

So **Alternative A** (`map` + helper) is the live shape; **B** (finite `for` + `append`) and **C**
(`filter_map`) were **not needed** — no rejected-alternative diagnostics to report.

## What changed (Todo fixture + its test only — zero prelude/compiler/Rust change)

App-local domain type + helper + handler in `examples/todo_view_app/todo_views.ig`:
```ig
type TodoItem { id : String, title : String, done : Bool }

pure contract TodoLabel {            -- one domain row → one node, via the P20 MakeLabel helper
  input todo : TodoItem
  compute text : String = todo.title
  compute node : HtmlNode = call_contract("MakeLabel", text)
  output node : HtmlNode
}

pure contract TodoListHtml {
  input req : Request
  compute todos : Collection[TodoItem] = [
    { id: "1", title: "Buy milk <script>", done: false },
    { id: "2", title: "Write the spec",    done: true  }
  ]
  compute body : Collection[HtmlNode] = map(todos, t -> call_contract("TodoLabel", t))   -- the bottleneck, solved
  compute view : ViewArtifact = call_contract("FormView", "Todos", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```
Route `GET /todos/list-html` (authored **before** `/todos/:todo_id` so the static suffix is reachable —
P18 priority policy). Fake/static data; no DB.

Authoring progression now reads:
```
P19  manual records      { kind:"label", … } per node
P20  helper contracts    call_contract("MakeLabel", text)         -- per node, pleasant
P21  domain collection   map(todos, t -> call_contract("TodoLabel", t))   -- N nodes from N rows
```

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests
  → 12 passed  (6 RespondView JSON + 2 P17 Render + 2 P19 RenderView + 1 P20 helper byte-identical +
                1 NEW P21: list-from-collection renders both items in order, escaped)
$ cd server/igniter-web && cargo test --test render_html_app_tests   → 3 passed (P16/P17, untouched)
$ cd server/igniter-web && cargo test                                → all suites green
$ cd frame-ui/igniter-render-html && cargo test                      → 11 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed (prelude unchanged)
$ cd server/igniter-server && cargo test                             → green (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit'  → (none)
$ git diff --check                                                   → clean
  (changed: routes.igweb +4, todo_views.ig +29, todo_view_app_tests.rs +21 — fixture + test only)
```

## Acceptance — mapping

- [x] Todo list route renders real `text/html` through `RenderView`.
- [x] `body : Collection[HtmlNode]` built from `Collection[TodoItem]` via `map` (not manual enumeration).
- [x] Two Todo items render in deterministic authored order (`map` preserves order; `Buy milk` before
      `Write the spec`).
- [x] Malicious Todo title escaped (`Buy milk &lt;script&gt;`; no raw `<script>`).
- [x] Transformation style documented: **`map(coll, x -> call_contract(...))`** (Alternative A).
- [x] P20 helper route still green + byte-identical to P19 direct route.
- [x] P17 request-body `Render` path green.
- [x] `RespondView` JSON routes green.
- [x] `render_html_app_tests` (3) + `igniter-render-html` (11) green.
- [x] `igweb_lowering_tests` (11) green (prelude/compiler untouched — run as regression).
- [x] `igniter-server` normal deps renderer-free.
- [x] `git diff --check` clean.

## Closing-report items

- **Chosen transformation form:** **Alternative A** — `map(todos, t -> call_contract("TodoLabel", t))`.
  The `map(coll, lambda)` call with an arrow lambda calling a helper contract is the live, proven shape
  (batch_importer, bloom_filter); element type flows from the `: Collection[HtmlNode]` annotation +
  `TodoLabel`'s `HtmlNode` output.
- **Rejected alternatives / diagnostics:** none — A compiled and rendered first try, so B (finite
  `for`+`append`) and C (`filter_map`) were not needed; no compiler diagnostics to report.
- **Next bottleneck:** (a) **conditional lists** (`filter`/`filter_map` to omit nodes, e.g. only `done:false`
  todos) — the natural next step from `map`; (b) **`select` options** node; (c) **nested layout** (the form
  is flat); (d) **source-map diagnostics** (errors point at generated `.ig`, not the helper/authoring site).
  Likely (a) next, then (b).

## Closed scope (honored)

No DB / read-guard host / `ReadThen` / live Postgres; no new `.igweb` syntax; no new `Decision` arm; no
renderer change; no prelude change (the live `map` + P19/P20 records sufficed); no `.ig.html`/`.igv`/template
runtime; no host-side domain-row→node mapping (the mapping is **app `.ig`**, via `TodoLabel`); no `select`
options; no source-map expansion; no canon claim.

## Next

1. **conditional lists** — `filter`/`filter_map` over a domain collection (e.g. render only pending todos).
2. **`select`** node (`options : Collection[String]`).
3. Later/gated: promote helpers to a shared module/package (after a 2nd app), nested layout, `.igv`,
   `.ig.html`, assets, file-export.

---

*Lab implementation-proof. Compiled 2026-06-20; todo_view_app 12 green (incl. list-from-collection),
render_html_app 3, igniter-render-html 11, igweb lowering 11 (prelude unchanged), igniter-server green +
renderer-free, `git diff --check` clean. A domain `Collection[TodoItem]` now produces a ViewArtifact body
via `map` + helper contract — real app-list authoring, no new syntax, no `.ig.html`/`.igv`.*
