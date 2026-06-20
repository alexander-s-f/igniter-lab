# LAB-IGNITER-WEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22 - Conditional ViewArtifact list authoring

Status: CLOSED
Lane: standard
Type: implementation-proof / pressure test
Delegation code: OPUS-IGWEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The ViewArtifact authoring stack now has:

- P19: typed `.ig` records can author `ViewArtifact` and return real HTML through `RenderView`.
- P20: app-local helper contracts make single-node authoring pleasant.
- P21: `Collection[TodoItem]` can become `Collection[HtmlNode]` via
  `map(todos, t -> call_contract("TodoLabel", t))`.

P21 named the next bottleneck: conditional lists. Real views need to omit or group items, not only map every
row.

P22 pressures the smallest useful conditional list:

```text
Collection[TodoItem]
  -> filter / filter_map / equivalent
  -> Collection[HtmlNode]
  -> FormView
  -> RenderView
  -> text/html
```

No DB, no renderer changes, no new syntax unless live language proves the existing stdlib cannot express the
case.

## Goal

Prove a Todo view can render only a subset of a domain collection, e.g. pending todos only:

```text
todos : Collection[TodoItem]
pending : Collection[TodoItem] = filter(todos, t -> not(t.done))
body : Collection[HtmlNode] = map(pending, t -> TodoLabel(t))
```

Exact syntax must come from live `.ig` examples and stdlib, not invention.

## Verify First

Read live surfaces before editing:

- `lab-docs/lang/lab-igniter-web-viewartifact-list-authoring-p21-v0.md`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `lang/igniter-stdlib/stdlib/collections.ig`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- tests/fixtures using:
  - `filter`
  - `filter_map`
  - lambdas returning `Bool`
  - boolean negation / comparisons
  - `append` / `concat` fallback
- `frame-ui/igniter-render-html/src/lib.rs`

Confirm or correct:

- whether `filter(collection, x -> predicate)` exists and compiles for records;
- whether `filter_map` exists and is better for node omission;
- whether lambdas can access record fields such as `todo.done`;
- whether `Bool` comparison / negation syntax is already available;
- whether map-after-filter preserves authored order.

Live code wins over this card.

## Alternatives To Compare

### A. `filter` then `map`

Preferred if live stdlib supports it:

```ig
compute pending : Collection[TodoItem] = filter(todos, t -> t.done == false)
compute body : Collection[HtmlNode] = map(pending, t -> call_contract("TodoLabel", t))
```

### B. `filter_map`

Use if it is already supported and cleaner:

```ig
compute body : Collection[HtmlNode] =
  filter_map(todos, t -> if t.done == false { some(call_contract("TodoLabel", t)) } else { none() })
```

### C. helper contract returns `Option[HtmlNode]`

Useful if `filter_map` wants an Option-returning helper:

```ig
PendingTodoLabel(todo) -> Option[HtmlNode]
filter_map(todos, t -> call_contract("PendingTodoLabel", t))
```

### D. finite loop + append

Accept only if `filter`/`filter_map` are unavailable or broken for records. This is less declarative, but it
is still app-authored `.ig`.

### E. manual enumeration

Rejected except as a baseline check. P22 must not just add another fixed two-node list.

## Recommended Proof Shape

Extend `todo_view_app` with one route:

```igweb
route GET "/todos/pending-html" -> TodoPendingHtml
```

Author it before `/todos/:todo_id`, following the P18 priority policy.

Use the existing `TodoItem` / `TodoLabel` / `FormView` helpers from P21. Add one handler:

```ig
pure contract TodoPendingHtml {
  input req : Request
  compute todos : Collection[TodoItem] = [
    { id: "1", title: "Buy milk <script>", done: false },
    { id: "2", title: "Write the spec",    done: true  },
    { id: "3", title: "Pay bills",         done: false }
  ]
  ...
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

The rendered HTML should include only the pending items (`done:false`) in original order, and still escape
malicious text.

## Required Acceptance

- [x] Todo pending-list route renders real `text/html` through `RenderView`.
- [x] The handler starts from `Collection[TodoItem]`, not manual node enumeration.
- [x] It conditionally omits at least one done item.
- [x] It renders at least two kept items in deterministic original order.
- [x] Malicious kept item text is escaped; no raw `<script>`.
- [x] The chosen conditional style is documented: `filter` then `map` (Alternative A).
- [x] P21 list route remains green.
- [x] P20 helper route remains green and byte-identical to P19 direct route.
- [x] P17 request-body `Render` path remains green.
- [x] `RespondView` JSON routes remain green.
- [x] `render_html_app_tests` remain green.
- [x] `igniter-render-html` tests remain green.
- [x] `igweb_lowering_tests` remain green (prelude untouched — run as regression).
- [x] `igniter-server` normal dependency tree remains renderer-free.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Smallest diff — Todo fixture + its test ONLY, zero prelude/compiler/Rust/renderer change:**
`examples/todo_view_app/todo_views.ig` (+`TodoPendingHtml`), `routes.igweb` (+`/todos/pending-html`,
before `/todos/:todo_id`), `tests/todo_view_app_tests.rs` (+1 conditional test). Proof doc:
`lab-docs/lang/lab-igniter-web-viewartifact-conditional-lists-p22-v0.md`. Todo Postgres write work is a
separate P4 slice and is **not** part of P22.

**Chosen form — Alternative A (first try):** `compute pending = filter(todos, t -> t.done == false)` then
`map(pending, t -> call_contract("TodoLabel", t))`. Verify-first found `filter(coll, x -> Bool-predicate)`
is the live shape (apps/bookkeeping `filter(tx.postings, p -> p.direction == "Debit")`); the clean
`t.done == false` predicate (`Bool` `==` + `false` literal) compiled + ran first try, so `filter_map` (B),
Option-helper (C), and the `if t.done {false} else {true}` fallback were all unnecessary — **no
rejected-alternative diagnostics**.

**Behavior:** of 3 todos the `done:true` one is omitted; the two `done:false` are kept in original order
(`filter` then `map` both order-preserving); kept `<script>` escaped; real `text/html` via unchanged
`RenderView`.

**Proof — all green:** todo_view_app **13** (incl. conditional pending test); render_html_app 3;
igniter-render-html 11; igweb lowering 11 (prelude unchanged); igniter-server green + renderer-free;
`git diff --check` clean.

**Authoring stack now:** P19 records → P20 helpers → P21 `map` (domain→nodes) → P22 `filter`+`map`
(conditional). **Next bottleneck:** `select` options node (the last form-vocab gap), then nested layout.

## Required Verification

Run and report exact counts:

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

If `filter`/`filter_map` fails, include the exact compiler diagnostic in the proof doc and choose the
smallest honest fallback. Do not silently regress to manual enumeration.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-viewartifact-conditional-lists-p22-v0.md
```

It must state:

- which conditional transformation style was chosen and why;
- exact live evidence for the syntax;
- whether `filter`/`filter_map` worked or failed;
- exact behavior of kept/omitted items;
- whether ordering is preserved;
- what remains the next authoring bottleneck.

## Closed Scope

- No DB / read guard host / `ReadThen`.
- No live Postgres.
- No new `.igweb` syntax.
- No new `Decision` arm.
- No renderer changes.
- No prelude changes unless verify-first proves a tiny missing type/function is unavoidable.
- No `.ig.html`.
- No `.igv`.
- No template runtime.
- No host-side domain-row-to-node mapping.
- No `select` options; separate card.
- No source-map/diagnostics expansion.
- No canon/stable API claim.

## Suggested Next

If this lands cleanly:

1. `LAB-IGNITER-WEB-VIEWARTIFACT-SELECT-OPTIONS-P23` — `select` node/options authoring;
2. shared helper module/package only after a second app repeats the helper pattern;
3. nested layout / richer ViewArtifact vocabulary;
4. `.igv` or `.ig.html` only if app-local `.ig` helper authoring remains too weak.
