# lab-igniter-web-viewartifact-authoring-p19-v0 — typed ViewArtifact authoring in IgWeb

**Card:** `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19` · **Delegation:** `OPUS-IGWEB-VIEWARTIFACT-AUTHORING-P19`
**Status:** CLOSED (lab implementation-proof) — an IgWeb app can now author a **ViewArtifact in ordinary
`.ig` records** and return real `text/html` via a new `RenderView { status, view : ViewArtifact }` decision
— **no request-body JSON, no inline JSON/HTML string, no concatenation, no `.ig.html`, no `.igv`, no
template engine.** Implements the P18 recommendation (typed prelude records).
**Authority:** Lab tooling. `igniter-server` stays renderer-free; the renderer dep lives in `igniter-web`.

## Verify-first (confirmed live)

- **Records/collections serialize to clean JSON; only variants carry `__arm`/`__variant`** — proven by P2's
  `View` (the test asserts no discriminants in the view root). So a flat record value matches the
  renderer's `kind`-dispatched JSON **directly, with no adapter**.
- `map_decision` already reads a nested `view` JSON value for `RespondView` (`fields.get("view")`) — the
  same access works for a `RenderView` arm.
- render-html v0 form vocab: `artifact:"view"`, `layout:"form"`, `title`, `body` of `kind`-keyed nodes
  (`label`/`text`/`checkbox`/`button`[/`select`]); kind-dispatched, ignores extra fields, fails closed.
- `Bool` is a real `.ig` type; `Collection[T]` record fields + record/collection literals are authorable
  (P2 mechanics).
- `Render { artifact_json }` (P16/P17) must remain additive and green.

## What changed (prelude + igniter-web + the Todo fixture)

**1. IgWeb prelude** (`lang/igniter-compiler/src/igweb.rs`) — bounded, domain-free records + one arm:
```ig
type HtmlNode    { kind:String, id:String, label:String, text:String, required:Bool, action:String }
type ViewArtifact{ artifact:String, layout:String, title:String, body:Collection[HtmlNode] }
variant Decision { … RenderView { status:Integer, view:ViewArtifact } }
```
Flat `HtmlNode` (one record, `kind` + leaf fields, unused defaulted) so the VM serializes it **directly**
to the renderer's schema — no variant/`__arm` adapter. `select` is **deferred** (would need an
`options:Collection[String]` field); v0 covers `label`/`text`/`checkbox`/`button`.

**2. `igniter-web` `map_decision`** (`server/igniter-web/src/lib.rs`) — a `RenderView` arm + a shared
`render_to_decision(status, artifact_json)` helper (refactored out of `Render`):
```text
RenderView { status, view } → serde view Value → render_to_decision → render_html → ServerResponse::raw(text/html)
Render     { artifact_json } → render_to_decision (unchanged P16/P17 path)
```
Success → raw `text/html`; failure → JSON 500 (`kind`/`message`, no artifact leak). `RespondView` stays
JSON, unmerged.

**3. Todo fixture** (`examples/todo_view_app/`) — two authored routes + contracts, **built from `.ig`
records** (no request-body JSON):
- `GET /todos/authored-html/:todo_id → TodoAuthoredHtml` — builds a `ViewArtifact` from record/collection
  literals; the captured `todo_id` flows into a `label` leaf; a `Buy milk <script>` leaf proves escaping.
- `GET /bad-node → TodoBadNode` — a `kind:"marquee"` node (failure proof).

## End-to-end shape (proven)

```text
.ig: compute view : ViewArtifact = { artifact:"view", layout:"form", title:"Todo Detail", body: [ {kind:"label", text: or_else(todo_id,"none"), …}, … ] }
     compute d : Decision = RenderView { status: 200, view: view }
   → VM serializes `view` to clean JSON (records → no __arm)
   → igniter-web RenderView arm → render_html(view.to_string())
   → ServerResponse::raw(200, html, "text/html; charset=utf-8")   (P15 seam)
   → wire body = verbatim <!DOCTYPE html>…  (param + content, ESCAPED)
```

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests
  → 10 passed  (6 JSON RespondView + 2 P17 Render(req.body) + 2 NEW P19 RenderView:
                authored-from-records HTML w/ param + escaping; unsupported kind → JSON 500)
$ cd server/igniter-web && cargo test --test render_html_app_tests     → 3 passed (P16/P17, untouched)
$ cd server/igniter-web && cargo test                                  → all suites green
$ cd frame-ui/igniter-render-html && cargo test                        → 11 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests   → 11 passed (new prelude compiles
                                                                          through the real compiler)
$ cd lang/igniter-compiler && cargo test --lib igweb                   → 55 passed
$ cd server/igniter-server && cargo test                               → green (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit'  → (none)
$ cd server/igniter-web && cargo tree -e normal | rg render_html       → igniter_render_html (intentional)
$ git diff --check                                                     → clean
```

## Acceptance — mapping

- [x] Todo-authored `RenderView` route returns real `text/html`.
- [x] Body starts with `<!DOCTYPE html>`, not JSON-quoted/wrapped.
- [x] Artifact built from **typed `.ig` records**, not request-body JSON.
- [x] No inline JSON string / manual JSON-or-HTML concatenation in `.ig`.
- [x] Route param flows into the rendered artifact (`/todos/authored-html/42` → `<p class="ig-label">42</p>`).
- [x] `<script>` escaped (`Buy milk &lt;script&gt;`); no raw script tag.
- [x] Unsupported `kind` (`marquee`) → JSON 500 (`unsupported_node`), not a panic.
- [x] P17 `Render { artifact_json: req.body }` path green.
- [x] `RespondView` JSON routes green.
- [x] `render_html_app_tests` green (3).
- [x] `igniter-render-html` tests green (11).
- [x] `igniter-server` normal deps renderer-free.
- [x] `igniter-web` normal deps intentionally include `igniter_render_html`.
- [x] `git diff --check` clean.

## Notes / honest scope

- The flat-record verbosity (defaulted `id`/`label`/`text`/`action`) is the accepted cost of the
  no-`__arm`-adapter win; **helper contracts** (P18 Alternative B) are the ergonomic follow-on, app-local.
- `select` deferred (needs `options:Collection[String]`); v0 = label/text/checkbox/button.
- TodoApp now has **both** authoring paths: P17 external/request JSON → `Render`; P19 authored `.ig` records
  → `RenderView`. The authoring gap is closed without `.ig.html`/`.igv`/template syntax.

## Closed scope (honored)

No `.ig.html`, no template/IR compiler, no `.igv`/binding layer, no manual JSON/HTML strings in `.ig`, no
helper library beyond the fixture, no generic `Project` arm, no file export, no CSS/assets, no DB/effect-host,
no source-map expansion, no canon claim.

## Next

1. **Ergonomics:** helper contracts (`MakeLabel`/`MakeButton`/`TodoIndexArtifact`) in an app/lib module to
   cut per-node verbosity (P18 Alternative B) — verify contract-calls-inside-a-collection-literal.
2. **`select`** node (`options:Collection[String]`) when a real form needs it.
3. Later, separately gated: `.igv` authoring dialect, `.ig.html`, assets/static shell, file-export family.

---

*Lab implementation-proof. Compiled 2026-06-20; todo_view_app 10 green (6 RespondView + 2 Render + 2
RenderView), render_html_app 3, igniter-render-html 11, igweb lowering 11 + lib 55 (new prelude compiles),
igniter-server green + renderer-free, igniter-web carries the renderer, `git diff --check` clean. ViewArtifact
is now authored in typed `.ig` records and delivered as escaped HTML — no `.ig.html`, no server-core render
dependency.*
