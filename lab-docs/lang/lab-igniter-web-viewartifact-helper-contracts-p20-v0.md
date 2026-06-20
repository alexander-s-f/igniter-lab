# lab-igniter-web-viewartifact-helper-contracts-p20-v0 — ergonomic ViewArtifact helper contracts

**Card:** `LAB-IGNITER-WEB-VIEWARTIFACT-HELPER-CONTRACTS-P20` · **Delegation:** `OPUS-IGWEB-VIEWARTIFACT-HELPERS-P20`
**Status:** CLOSED (lab implementation-proof) — ViewArtifact authoring is made pleasant via **app-local
pure `.ig` helper contracts** that return the proven P19 flat `HtmlNode`/`ViewArtifact` records. Helper
output is **byte-identical** to direct record literals. **No protocol change, no new `Decision` arm, no
node enum, no prelude/compiler/Rust/renderer change, no `.ig.html`/`.igv`/template engine.**
**Authority:** Lab tooling. The smallest possible P20: changes live **only** in the Todo fixture + its test.

## Verify-first (confirmed live)

- **`call_contract(...)` works BOTH as a named `compute` AND inline inside a `Collection[HtmlNode]` literal**
  — both forms compiled and rendered identically (the inline form was probed; the committed form uses named
  computes for readability/debuggability, which the card prefers). **Answers Q1: yes, inline is supported.**
- A helper-returned `HtmlNode`/`ViewArtifact` record serializes **identically** to an inline record literal
  (records carry no `__arm`/`__variant`), so the rendered HTML is **byte-identical** (proven, §Q3).
- `RenderView` path unchanged; unsupported kinds still fail closed in the renderer (P19 test still green).
- `Render { artifact_json }` / `RespondView` paths untouched.

## What changed (Todo fixture + its test only — zero prelude/compiler/Rust change)

App-local helpers in `examples/todo_view_app/todo_views.ig` (pure `.ig`, returning P19 records):
```ig
pure contract MakeLabel  { input text:String;                          compute node:HtmlNode = { kind:"label",  …, text:text, … };  output node:HtmlNode }
pure contract MakeButton { input id:String; input label:String; input action:String;
                                                                       compute node:HtmlNode = { kind:"button", id:id, label:label, …, action:action }; output node:HtmlNode }
pure contract FormView   { input title:String; input body:Collection[HtmlNode];
                                                                       compute view:ViewArtifact = { artifact:"view", layout:"form", title:title, body:body }; output view:ViewArtifact }
```
A helper-authored route reads like composition (named `compute` nodes → a body collection → `FormView`):
```ig
pure contract TodoHelperHtml {
  input req : Request
  input todo_id : Option[String]
  compute n_id   : HtmlNode = call_contract("MakeLabel", or_else(todo_id, "none"))
  compute n_milk : HtmlNode = call_contract("MakeLabel", "Buy milk <script>")
  compute n_done : HtmlNode = call_contract("MakeButton", "done", "Done", "submit")
  compute body   : Collection[HtmlNode] = [n_id, n_milk, n_done]
  compute view   : ViewArtifact = call_contract("FormView", "Todo Detail", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```
Route `GET /todos/helper-html/:todo_id`. The **verbose P19 `TodoAuthoredHtml` route is kept** (same inputs/
content) so the two can be proven byte-identical.

Before (P19, per node) vs after (P20):
```ig
{ kind: "label", id: "", label: "", text: "Buy milk <script>", required: false, action: "" }   -- 6 fields
call_contract("MakeLabel", "Buy milk <script>")                                                 -- 1 call
```

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests
  → 11 passed  (6 RespondView JSON + 2 P17 Render + 2 P19 RenderView + 1 NEW P20:
                helper route HTML == direct-record HTML, byte-identical; param + escaping)
$ cd server/igniter-web && cargo test --test render_html_app_tests   → 3 passed (P16/P17, untouched)
$ cd server/igniter-web && cargo test                                → all suites green
$ cd frame-ui/igniter-render-html && cargo test                      → 11 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed (prelude unchanged)
$ cd server/igniter-server && cargo test                             → green (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit'  → (none)
$ git diff --check                                                   → clean
  (changed: routes.igweb +2, todo_views.ig +39, todo_view_app_tests.rs +25 — fixture + test only)
```

## Acceptance — mapping

- [x] Helper-authored Todo HTML route returns real `text/html`.
- [x] Route uses helper contracts returning `HtmlNode`/`ViewArtifact`, not raw record literals per node.
- [x] Route param flows through a helper into rendered HTML (`/todos/helper-html/7` → `<p class="ig-label">7</p>`).
- [x] Malicious text through a helper is escaped (`Buy milk &lt;script&gt;`; no raw `<script>`).
- [x] P19 direct `RenderView` route remains green; helper route proven **byte-identical** to it.
- [x] P17 `Render { artifact_json }` path green.
- [x] `RespondView` JSON routes green.
- [x] Unsupported node failure remains renderer-owned + fail-closed (P19 `bad-node` test green).
- [x] `render_html_app_tests` green (3); `igniter-render-html` green (11).
- [x] `igniter-server` normal deps renderer-free.
- [x] `git diff --check` clean.

## Closing-report questions

1. **Can `call_contract(...)` appear inside `Collection[HtmlNode]` literals?** **Yes** — both inline
   `[call_contract(...), …]` and named-`compute` forms compile and render identically (inline probed; named
   committed).
2. **Is named-compute good enough?** Yes — readable, debuggable, agent-friendly; it is the committed form.
3. **Helper output identical to direct records?** **Byte-identical** — `helper_authored_html_is_byte_identical_to_direct_records`
   asserts `helper_body == direct_body` for the same inputs (records serialize the same; the renderer is
   kind-dispatched).
4. **Where should helpers live?** **App-local for now** (in the Todo fixture). Promote to a shared
   `igniter-web` example module or a future `.ig` package only when ≥2 apps need the same helpers — not yet.
5. **Does this delay `.ig.html`/`.igv` pressure?** **Yes** — one helper call replaces a 6-field record per
   node; composition reads cleanly for app-like forms, so heavier authoring dialects are not yet needed.
6. **Next ergonomic bottleneck?** (a) **lists/iteration** — building `body` from a `Collection` of domain
   items needs a map/loop (today nodes are enumerated manually); (b) **`select` options** (no `options`
   field on the flat `HtmlNode`); (c) **nested layout** (flat form only); (d) **source-map diagnostics**
   (render/compile errors point at generated `.ig`, not the helper/authoring site). Likely (a) and (b) next.

## Closed scope (honored)

No `.ig.html`, no `.igv`/binding, no new parser/lowering syntax, no template runtime/metaprogramming, no
new `Decision` arm, no `RenderView` change, no `HtmlNode` variant enum, no renderer change, no static
assets, no DB/effect-host, no canon claim. Helpers are pure `.ig`, app-local; **no prelude/compiler/Rust
touch**.

## Next

1. **lists/iteration** authoring (map a `Collection[domain]` → `Collection[HtmlNode]`) — the top bottleneck.
2. **`select`** node (`options : Collection[String]`) when a real form needs it.
3. Later/gated: promote helpers to a shared module/package; `.igv`, `.ig.html`, assets/static shell,
   file-export family.

---

*Lab implementation-proof. Compiled 2026-06-20; todo_view_app 11 green (incl. helper==direct byte-identical),
render_html_app 3, igniter-render-html 11, igweb lowering 11 (prelude unchanged), igniter-server green +
renderer-free, `git diff --check` clean. ViewArtifact authoring is now pleasant via pure `.ig` helper
contracts over the proven record model — no protocol/prelude/compiler change, no `.ig.html`/`.igv`.*
