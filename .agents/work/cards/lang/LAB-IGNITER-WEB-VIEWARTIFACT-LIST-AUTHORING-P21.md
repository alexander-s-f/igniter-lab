# LAB-IGNITER-WEB-VIEWARTIFACT-LIST-AUTHORING-P21 - ViewArtifact list authoring from collections

Status: CLOSED
Lane: standard
Type: implementation-proof / pressure test
Delegation code: OPUS-IGWEB-VIEWARTIFACT-LISTS-P21
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The ViewArtifact authoring stack now has three closed layers:

- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19` — typed `.ig` records can author a `ViewArtifact` and
  return real HTML through `RenderView`.
- `LAB-IGNITER-WEB-VIEWARTIFACT-HELPER-CONTRACTS-P20` — app-local helper contracts (`MakeLabel`,
  `MakeButton`, `FormView`) make single-node authoring pleasant and byte-identical to direct records.
- P20's closing report names the next ergonomic bottleneck: building `body : Collection[HtmlNode]` from a
  **domain collection** instead of manually listing each node.

P21 pressures that bottleneck:

```text
Collection[TodoItem] -> Collection[HtmlNode] -> ViewArtifact -> RenderView -> HTML
```

This is the difference between a demo page and a real app list.

## Goal

Prove the smallest good authoring form for list views in ordinary `.ig`, using the existing `RenderView`
and helper-contract model.

The author should be able to express:

```text
todos : Collection[TodoItem]
body  : Collection[HtmlNode] = todos.map(TodoLabel)   -- exact syntax TBD by live language
view  : ViewArtifact = FormView("Todos", body)
```

No new `.igweb` syntax, no `.ig.html`, no `.igv`, no renderer changes.

## Verify First

Read live surfaces before editing:

- `lab-docs/lang/lab-igniter-web-viewartifact-helper-contracts-p20-v0.md`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
  - `stdlib.collection.map`
  - `filter_map`
  - `append`
  - `concat`
- `lang/igniter-compiler/tests/loop_conformance_tests.rs`
  - finite `for` loop syntax and constraints
- any existing tests/fixtures for `stdlib.collection.map`, lambdas, `append`, or `filter_map`
- `lang/igniter-compiler/src/parser.rs`
  - lambda / finite loop syntax if needed
- `frame-ui/igniter-render-html/src/lib.rs`

Confirm or correct:

- whether `stdlib.collection.map(Collection[T], callback)` is usable from authored `.ig` today;
- whether the callback can call a helper contract such as `TodoLabel(todo) -> HtmlNode`;
- whether finite `for` + `append` is the better v0 authoring shape;
- whether `Collection[HtmlNode]` element inference remains stable;
- whether rendered list order is deterministic.

## Alternatives To Compare

### A. `stdlib.collection.map` + helper contract

Preferred if it compiles cleanly:

```ig
compute body : Collection[HtmlNode] =
  stdlib.collection.map(todos, |todo| call_contract("TodoLabel", todo))
```

Exact syntax may differ. Verify live examples; do not invent syntax.

### B. finite `for` loop + `stdlib.collection.append`

Acceptable if map/lambda ergonomics are not ready:

```ig
compute body : Collection[HtmlNode] = []
for todo in todos {
  compute node : HtmlNode = call_contract("TodoLabel", todo)
  compute body = stdlib.collection.append(body, node)
}
```

Exact loop mutation/binding semantics must be verified. If loops are unsuitable for value construction,
say so.

### C. `filter_map`

Useful if list rendering needs conditional omission, but likely too wide for v0. Consider only if map is
already hard and filter_map is somehow easier.

### D. manual enumeration

Baseline only. P20 already proves manual/named composition; P21 should not merely add another manually
enumerated list.

### E. host/projector maps domain rows to nodes

Reject unless live evidence forces it. Mapping product/domain rows to nodes is app meaning, not host meaning.

## Recommended Proof Shape

Add a small app-local domain type to `todo_view_app`:

```ig
type TodoItem {
  id    : String
  title : String
  done  : Bool
}
```

Add helper(s):

```ig
pure contract TodoLabel {
  input todo : TodoItem
  compute text : String = todo.title
  compute node : HtmlNode = call_contract("MakeLabel", text)
  output node : HtmlNode
}
```

Add one route:

```igweb
route GET "/todos/list-html" -> TodoListHtml
```

The route should build a `Collection[TodoItem]`, transform it to `Collection[HtmlNode]`, wrap it in
`FormView`, and return `RenderView`.

Keep the data fake/static in `.ig`. No DB/read-host dependency in this card.

## Required Behavior

The rendered HTML must:

- include multiple Todo items in authored order;
- include escaped malicious text from a Todo title;
- be real `text/html`, not JSON-wrapped;
- still use the P19/P20 `RenderView` path;
- not change P17/P19/P20 routes.

## Closed Scope

- No DB / read guard host / `ReadThen`.
- No live Postgres.
- No new `.igweb` syntax.
- No new `Decision` arm.
- No renderer changes.
- No prelude changes unless verify-first proves a tiny missing type is unavoidable.
- No `.ig.html`.
- No `.igv`.
- No template runtime.
- No host-side domain-row-to-node mapping.
- No `select` options; that is a separate card.
- No source-map/diagnostics expansion.
- No canon/stable API claim.

## Required Tests / Acceptance

- [x] A Todo list route renders real `text/html` through `RenderView`.
- [x] The route builds `body : Collection[HtmlNode]` from `Collection[TodoItem]`, not manual node enumeration.
- [x] At least two Todo items render in deterministic authored order.
- [x] Malicious Todo title text is escaped; no raw `<script>`.
- [x] The chosen transformation style is documented: `map`, finite loop, or justified fallback.
- [x] P20 helper route remains green and byte-identical to P19 direct route.
- [x] P17 request-body `Render` path remains green.
- [x] `RespondView` JSON routes remain green.
- [x] `render_html_app_tests` remain green.
- [x] `igniter-render-html` tests remain green.
- [x] `igweb_lowering_tests` remain green if compiler/prelude is touched, otherwise at least run as regression.
- [x] `igniter-server` normal dependency tree remains renderer-free.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Smallest diff — Todo fixture + its test ONLY, zero prelude/compiler/Rust/renderer change:**
`examples/todo_view_app/todo_views.ig` (+`type TodoItem`, `TodoLabel`, `TodoListHtml`), `routes.igweb`
(+`/todos/list-html`, authored before `/todos/:todo_id`), `tests/todo_view_app_tests.rs` (+1 list test).
Proof doc: `lab-docs/lang/lab-igniter-web-viewartifact-list-authoring-p21-v0.md`.

**Chosen form — Alternative A (first try, no fallback):**
`compute body : Collection[HtmlNode] = map(todos, t -> call_contract("TodoLabel", t))`. Verify-first found
this is a **live, proven `.ig` shape** — `map(coll, x -> call_contract(...))` is used in apps/batch_importer
(`map(rows, r -> call_contract("ValidateRow", r))`) and bloom_filter
(`map(range(...), i -> call_contract("MakeSlot", i)) : Collection[BitSlot]`). No new syntax invented; B
(finite `for`+`append`) and C (`filter_map`) were unnecessary; **no rejected-alternative diagnostics**.

**Behavior:** two `TodoItem`s render in authored order (`map` preserves order); a `<script>` title is
escaped (`Buy milk &lt;script&gt;`); real `text/html` via the unchanged `RenderView` path. Domain-row→node
mapping is **app `.ig`** (`TodoLabel`), not host-side.

**Proof — all green:** todo_view_app **12** (incl. list test); render_html_app 3; igniter-render-html 11;
igweb lowering 11 (prelude unchanged); igniter-server green + renderer-free; `git diff --check` clean.

**Authoring stack now:** P19 typed records → P20 helper contracts (single node) → P21 domain collections →
node collections (`map`). **Next bottleneck:** conditional lists (`filter`/`filter_map`), then `select`
options.

## Suggested Verification Commands

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test todo_view_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test render_html_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-render-html && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server && cargo tree -e normal
git diff --check
```

If `map`/loop syntax fails, include the exact compiler diagnostic in the proof doc and choose the smallest
honest fallback. Do not silently switch back to manual enumeration.

## Deliverables

- Narrow implementation in `todo_view_app` and tests.
- Proof doc:
  - `lab-docs/lang/lab-igniter-web-viewartifact-list-authoring-p21-v0.md`
- Closing report in this card with:
  - chosen transformation form;
  - exact diagnostics for rejected alternatives, if any;
  - next bottleneck.

## Expected Result

After P21, the authoring stack should cover:

```text
P19: typed records can produce HTML
P20: helpers make single-node authoring pleasant
P21: domain collections can produce ViewArtifact body collections
```

Then the next focused cards are likely:

1. `select` / `options` node support;
2. shared helper module or package only after a second app uses the helpers;
3. `.igv` binding or `.ig.html` only if these app-local forms still feel too weak.
