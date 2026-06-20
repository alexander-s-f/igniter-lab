# lab-igniter-web-viewartifact-conditional-lists-p22-v0 — conditional ViewArtifact list authoring

**Card:** `LAB-IGNITER-WEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22` · **Delegation:** `OPUS-IGWEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22`
**Status:** CLOSED (lab implementation-proof) — a list view renders only a **subset** of a domain
collection via **`filter(todos, t -> t.done == false)` then `map`**, → `FormView` → `RenderView` → real
`text/html`. **Alternative A worked first try with existing live language features — no new syntax, no
prelude/compiler/Rust/renderer change.**
**Authority:** Lab tooling. App-local only (Todo fixture + test).

## Verify-first (decisive live findings)

`filter` + a record-field Bool predicate is **already a live, proven `.ig` shape** — no invention:

| Fact | Evidence |
|---|---|
| `filter(coll: Collection[T], predicate: (T) -> Bool) -> Collection[T]` | `lang/igniter-stdlib/stdlib/collections.ig` (`def filter`) |
| `filter(coll, x -> <record-field predicate>)` compiles on records | `apps/.../bookkeeping/ledger.ig:7` `filter(tx.postings, p -> p.direction == "Debit")` |
| **`Bool` `==` comparison + `false`/`true` literals work** | P21 records author `done: false`/`done: true`; this card's `t.done == false` compiled + ran first try |
| `filter_map(Collection[T], (T -> Option[U])) -> Collection[U]` exists (callback returns `Option[U]`) | `typechecker/stdlib_calls.rs:670-843` |
| `map` preserves order; renderer kind-dispatched + escapes (P21) | unchanged |

So **Alternative A** (`filter` then `map`) is the live shape. **B** (`filter_map`) and **C** (Option-returning
helper) were **not needed**; **D** (loop+append) / **E** (manual) not used. The clean `t.done == false`
predicate compiled on the first try, so the call_router `if t.done { false } else { true }` fallback was
unnecessary — **no rejected-alternative diagnostics**.

## What changed (Todo fixture + its test only — zero prelude/compiler/Rust/renderer change)

One handler in `examples/todo_view_app/todo_views.ig`, reusing the P21 `TodoItem`/`TodoLabel` + P20
`FormView`:
```ig
pure contract TodoPendingHtml {
  input req : Request
  compute todos : Collection[TodoItem] = [
    { id: "1", title: "Buy milk <script>", done: false },
    { id: "2", title: "Write the spec",    done: true  },
    { id: "3", title: "Pay bills",         done: false }
  ]
  compute pending : Collection[TodoItem] = filter(todos, t -> t.done == false)   -- the conditional, solved
  compute body : Collection[HtmlNode] = map(pending, t -> call_contract("TodoLabel", t))
  compute view : ViewArtifact = call_contract("FormView", "Pending", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```
Route `GET /todos/pending-html` (authored before `/todos/:todo_id` — P18 priority policy).

Authoring stack now:
```
P19  manual records        P20  helper contracts (single node)
P21  map(domain → nodes)   P22  filter(domain) then map (conditional list)
```

## Behavior (proven)

Of 3 todos, the one `done: true` (`"Write the spec"`) is **omitted**; the two `done: false`
(`"Buy milk <script>"`, `"Pay bills"`) are **kept in original order** (`filter` then `map` both preserve
order). Kept malicious text is escaped (`Buy milk &lt;script&gt;`; no raw `<script>`). Real `text/html`
via the unchanged `RenderView` path.

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests
  → 13 passed  (… + 1 P21 list + 1 NEW P22: pending-only renders 2 kept items in order, done item omitted, escaped)
$ cd server/igniter-web && cargo test --test render_html_app_tests   → 3 passed (P16/P17, untouched)
$ cd server/igniter-web && cargo test                                → all suites green
$ cd frame-ui/igniter-render-html && cargo test                      → 11 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed (prelude unchanged)
$ cd server/igniter-server && cargo test                             → green (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit'  → (none)
$ git diff --check                                                   → clean
```

**Scope note (honest):** P22 changes are **only** the three `todo_view_app` files (`routes.igweb` +2,
`todo_views.ig` +18, `todo_view_app_tests.rs` +23). Todo Postgres write work is a separate P4 slice in
the same harvest; it is not part of this proof.

## Acceptance — mapping

- [x] Pending-list route renders real `text/html` through `RenderView`.
- [x] Handler starts from `Collection[TodoItem]`, not manual node enumeration.
- [x] Conditionally omits the `done:true` item.
- [x] Renders two kept items in deterministic original order (`Buy milk` before `Pay bills`).
- [x] Kept malicious text escaped (`Buy milk &lt;script&gt;`; no raw `<script>`).
- [x] Conditional style documented: **`filter(todos, t -> t.done == false)` then `map`** (Alternative A).
- [x] P21 list route + P20 helper (byte-identical) + P17 Render + RespondView JSON routes all green.
- [x] `render_html_app_tests` (3) + `igniter-render-html` (11) + `igweb_lowering_tests` (11) green.
- [x] `igniter-server` normal deps renderer-free; `git diff --check` clean.

## Closing-report items

- **Chosen conditional style:** **Alternative A — `filter` then `map`.** `filter(coll, x -> Bool-predicate)`
  is the live shape (bookkeeping); the clean `t.done == false` predicate compiled first try.
- **Live evidence:** `def filter` in stdlib; `filter(tx.postings, p -> p.direction == "Debit")` (bookkeeping);
  `Bool` `==`/`false` literals proven by compile+run here.
- **`filter`/`filter_map`:** `filter` worked; `filter_map` exists but was unnecessary (no Option plumbing
  needed for a simple keep/omit).
- **Kept/omitted behavior + ordering:** `done:true` omitted; two `done:false` kept in original order;
  `filter` then `map` both order-preserving.
- **Next bottleneck:** (a) **`select` options** node (`options : Collection[String]`) — the last form-vocab
  gap; (b) **nested layout / grouping** (sections, not a flat body); (c) **source-map diagnostics** (errors
  point at generated `.ig`). Likely (a) next.

## Closed scope (honored)

No DB / read-guard host / live Postgres; no new `.igweb` syntax; no new `Decision` arm; no renderer change;
no prelude change (live `filter`/`map` + P19/P20/P21 sufficed); no `.ig.html`/`.igv`/template runtime; no
host-side domain-row→node mapping (`TodoLabel` is app `.ig`); no `select` options; no source-map expansion;
no canon claim.

## Next

1. **`select`** node + `options` authoring (`LAB-IGNITER-WEB-VIEWARTIFACT-SELECT-OPTIONS-P23`).
2. nested layout / grouping; shared helper module/package (after a 2nd app).
3. Later/gated: `.igv`, `.ig.html`, assets, file-export.

---

*Lab implementation-proof. Compiled 2026-06-20; todo_view_app 13 green (incl. conditional pending list),
render_html_app 3, igniter-render-html 11, igweb lowering 11 (prelude unchanged), igniter-server green +
renderer-free, `git diff --check` clean. A domain collection is now `filter`ed then `map`ped into a
ViewArtifact body — conditional app-list authoring, no new syntax, no `.ig.html`/`.igv`.*
