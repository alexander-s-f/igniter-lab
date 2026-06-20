# lab-igniter-web-viewartifact-authoring-p18-v0 — ViewArtifact authoring without inline JSON

**Card:** `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18` · **Delegation:** `OPUS-IGWEB-VIEWARTIFACT-AUTHORING-P18`
**Status:** READINESS / ARCHITECTURE (v0) — selects the smallest good ViewArtifact authoring form for
IgWeb, given the `.ig` no-string-escape constraint. **No code, no prelude change, no `.igweb` grammar, no
`.ig.html`, no string-escape impl, no canon claim.**
**Authority:** Lab readiness. Closes the authoring gap P17 left open; names the P19 implementation.

## 1. Executive summary

P16/P17 proved **delivery** (ViewArtifact JSON → HTML over the wire); they sourced the JSON from `req.body`
because **`.ig` string literals cannot contain `"`** so a JSON literal can't be authored inline. P18 picks
the authoring form. **Recommendation: typed prelude records + a `RenderView { status, view : ViewArtifact }`
arm (Alternative A)** — it reuses the *exact* proven `RespondView`/`View` record+collection mechanics (P2),
serializes **directly** to renderer-compatible JSON (no adapter), composes with route params/data naturally
(the artifact is built by a per-request `.ig` contract taking `req`/params/data as inputs), and keeps the
prelude bounded. App-local **helper contracts (Alternative B)** are the ergonomic layer on top.
`.igv` and `.ig.html` stay **future Projection Dialects**, deferred. Next card:
`LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19`.

## 2. Verify-first (live facts, confirmed)

- **`.ig` strings have no escapes** — `lexer.rs:508` `read_string` reads to the next `"`; an inline JSON
  literal is impossible (confirmed by the P16/P17 `OOF-P0` wall).
- **`.ig` records + collections are authorable and serialize CLEAN.** Proven: `todo_views.ig`
  `compute items : Collection[ViewItem] = [ {key:"1",label:"Buy milk"}, … ]` →
  `compute v : View = { kind:"todo_index", title:"Todos", items: items }`; the P2 test asserts the
  serialized view root has **no `__arm`/`__variant`** (records serialize as plain objects; only *variant*
  values carry VM discriminants). `Bool` is a real type (`stdlib … -> Bool`).
- **`map_decision` already extracts a structured `view` Value** for `RespondView`
  (`fields.get("view").cloned()` → JSON `Value`, `lib.rs:174-178`). A `RenderView` arm can do the same and
  hand `view.to_string()` to `render_html`.
- **`Render { artifact_json : String }`** is the current arm; `RespondView { status, view : View }` is the
  small Todo descriptor (NOT the full ViewArtifact).
- **render-html v0 vocab** (`view_artifact.rs` / `render-html/src/lib.rs`): `artifact:"view"`,
  `layout:"form"|"workbench"`; form `body` components keyed by `kind` — `label{text}`,
  `text{id,label,required}`, `checkbox{id,label}`, `button{id,label,action}`, `select{id,label,options[],required}`.
  Renderer is **kind-dispatched** (reads only the fields a kind needs, ignores extras) and **fails closed**
  on unknown kinds / bad artifacts; escaping + URL allowlist are renderer-owned.

**Load-bearing consequence:** because the renderer is kind-dispatched and ignores extra fields, a **flat
`HtmlNode` record** (one record type carrying `kind` + all leaf fields, unused ones defaulted) serializes
to exactly the JSON the renderer expects — **no `__arm`→`kind` adapter needed**, unlike a `variant`
encoding. This is the crux that makes Alternative A the smallest path.

## 3. Alternatives compared (A–F)

| # | Form | Verdict |
|---|---|---|
| **A** | **Typed prelude records + `RenderView { status, view : ViewArtifact }`** | **RECOMMEND (primary).** Reuses proven record/collection mechanics; serializes clean to renderer JSON (no adapter); composes with params via contract inputs; bounded prelude. |
| **B** | **Helper contracts in app/lib `.ig`** (`MakeLabel(text)->HtmlNode`, `TodoIndexArtifact(req,…)->ViewArtifact`) | **RECOMMEND (ergonomic layer on A).** Cuts per-node verbosity; lives **app-local / future stdlib**, NOT the prelude. (Impl must confirm contract-call results inside a collection literal; else use record literals as P2 does.) |
| **C** | **`.igv` → ViewArtifact JSON → Render** | **DEFER (future Projection Dialect).** `.igv` is the frame/tooling authoring dialect lowering to ViewArtifact JSON; promising long-term, but it authors **static** views — flowing per-request route params/data into it needs a binding layer (the Ig-binding track). Bigger than v0. |
| **D** | **Add `.ig` string escapes / JSON literal** | **DEFER/REJECT for authoring.** Even with escapes, inline JSON is stringly-typed (no validation until render) — the wrong authoring model. A string-escape fix may be independently useful but doesn't deliver good authoring; not opened here. |
| **E** | **`.ig.html` template dialect** | **DEFER behind dedicated readiness.** Competes with the structured-descriptor direction; only acceptable if it lowers to ViewArtifact / pure `.ig` with auto-escaping (P0), and only once content-heavy templating pressure is real. Not now. |
| **F** | **Host transforms the small `View` → ViewArtifact/HTML** | **REJECT.** Bakes the Todo `View{kind,title,items}` mapping into igniter-web (app semantics in the host); hides the mapping outside app code; blocks richer views. Against the boundary. |

## 4. Answers to Q1–Q10

**Q1 — recommended v0 authoring surface.** Primary: **typed records (A)** — a bounded, domain-free
`HtmlNode` + `ViewArtifact` in the prelude + a `RenderView` arm; the author builds the artifact with
ordinary `.ig` record/collection literals inside a per-request contract. Fallback: **helper contracts (B)**
for ergonomics. It is smallest because it adds **zero new mechanism** — it is the proven `RespondView`/`View`
pattern widened to the renderer's form schema; and it is aesthetically good because user data stays in named
leaf fields, validated + escaped by the renderer.

**Q2 — protocol arm.** **Add `RenderView { status : Integer, view : ViewArtifact }`** (parallel to
`RespondView`); **keep `Render { artifact_json : String }`** unchanged (P16/P17 request-body path still
works). `map_decision`'s `RenderView` arm serializes `view` (already a JSON `Value`) and calls
`render_html(&view.to_string())` → `ServerResponse::raw(text/html)` — same delivery path as `Render`.
Do **not** replace/merge `RespondView` (it is the JSON-first small descriptor and stays). A generic
`Project { target, descriptor }` is a *later* generalization (once xlsx/csv targets land) — not v0.

**Q3 — schema in the prelude.** Keep it **bounded and domain-free**: `HtmlNode` (a flat record:
`kind`, `id`, `label`, `text`, `action` as `String`; `required` as `Bool`; plus `options : Collection[String]`
only if `select` is in the v0 subset) + `ViewArtifact { artifact, layout, title, body : Collection[HtmlNode] }`
+ the `RenderView` arm. This mirrors the existing `ViewItem`/`View`/`RespondView` precedent (P2 already put
view types in the prelude), so it is consistent, not new bloat. Anything Todo-specific or convenience-shaped
(helpers) lives **outside** the prelude (B). Recommended v0 node subset: **label/text/checkbox/button**
(no collection field needed); **select** is a small bounded add (`options`) for P19 or a follow-on.

**Q4 — relation to frame-ui ViewArtifact.** IgWeb's prelude `ViewArtifact` **mirrors the SCHEMA** of
frame-ui's ViewArtifact JSON (same `kind`/fields) and **targets** the same `igniter-render-html` projector;
it does **not import** frame-ui crates (igniter-web depends only on the projector, keeping the frame runtime
out). Mirror the shape, not the crate. **No canon claim** — both are lab.

**Q5 — relation to `.igv`.** `.igv` is the frame/tooling **authoring dialect** that lowers to ViewArtifact
JSON; it can be the **long-term** richer view-authoring surface, lowering to the same JSON `RenderView`/`Render`
consume (its exact lowering target). It is **deferred** because (a) it authors static views, so per-request
data/route-param flow needs a binding layer, and (b) typed records already give dynamic per-request views
today via contract inputs. When opened, `.igv`→ViewArtifact JSON→`Render` is the path, governed by P0.

**Q6 — `.ig.html`.** **Defer behind a dedicated readiness.** Not rejected forever; strict conditions: it
must lower to **ViewArtifact JSON or a pure `.ig` contract** (never a server runtime special-case), with
auto-escaping, and only once content-heavy templating pressure (docs/marketing pages) is real. For app-like
views (forms, dashboards, Todo), structured typed authoring (A) is the right shape and `.ig.html` would
compete with it.

**Q7 — safety / XSS ownership.** Unchanged and strong: user text is **data in structured leaf fields**
(`text`/`label`), never markup; **no raw-HTML node** in v0; the **renderer owns** escaping (text + attribute)
and the URL allowlist; **unknown nodes fail closed**. Typed-record authoring *cannot express* raw HTML
structure (the vocab is the same closed set), so it adds **no new XSS surface** — it just moves the artifact
source from `req.body` to app `.ig`, with identical leaf-escaping.

**Q8 — compose with route params/data.** **Yes, naturally** — the artifact is built by a per-request `.ig`
contract whose inputs are `req`, path params, and data:
```ig
pure contract TodoIndexArtifact {
  input req : Request
  compute body : Collection[HtmlNode] = [
    { kind: "label",  id: "", label: "", text: "Todos", required: false, action: "" },
    { kind: "button", id: "done", label: "Done", text: "", required: false, action: "submit" }
  ]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: "Todos", body: body }
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```
This is the proven P2 mechanic (records in a `Collection`, `or_else(todo_id,…)` for params). `.igv` (static
text) can't take per-request data without a binding layer — a decisive point for typed records as the v0
form. (Verbosity from defaulted fields is the cost; helper contracts (B) reduce it.)

**Q9 — next card + acceptance.** **`LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19`** — implement `RenderView`
+ the bounded prelude `HtmlNode`/`ViewArtifact` records, and a Todo artifact contract authored from `.ig`
records (no request-body JSON). Acceptance tests:
1. an authored Todo `RenderView` route returns **real `text/html`** (`<!DOCTYPE html>`, content present),
   built from `.ig` records — **no request-body JSON, no inline JSON string, no manual concatenation**;
2. malicious text (`<script>`) in a leaf field is **escaped**; no raw script tag;
3. an unknown/unsupported node `kind` (or bad artifact) **fails closed** to a JSON 500 (renderer-owned);
4. route params/data flow into the artifact (e.g. detail view with the captured `todo_id`);
5. the **P17 `Render { artifact_json: req.body }`** request-body path still works (additive, not replaced);
6. `RespondView` JSON routes stay green; determinism/byte-stability;
7. `igniter-server` normal deps gain no renderer/frame/ui-kit/export crate; `igniter-web` carries
   `igniter_render_html`; `git diff --check` clean.

**Q10 — out of scope (deferred).** CSS/assets/static shell; interactive JS; file export; live DB data;
source maps; canon/stable API. (`.igv`, `.ig.html`, generic `Project`, and `select`-options are deferred
per §3/§4.)

## 5. Reject / defer list

- **Reject:** Alternative F (host-side `View`→ViewArtifact mapping); raw HTML / manual JSON concatenation in
  `.ig`; a large/Todo-specific schema in the prelude.
- **Defer (named):** `.igv` authoring dialect (C); `.ig.html` template (E, dedicated readiness); `.ig`
  string-escape / JSON literal (D); generic `Project { target, descriptor }` arm; `select` node options;
  helper-contract-in-collection-literal ergonomics (verify in P19, else record literals).

---

*Readiness/architecture only. Compiled 2026-06-20; grounded in live `lexer.rs` (no escapes),
`igweb.rs` prelude, `igniter-web/src/lib.rs` `map_decision`, `frame-ui/igniter-ui-kit/src/view_artifact.rs`,
`igniter-render-html/src/lib.rs`, and the P2/P16/P17 proofs. No code, prelude, grammar, or canon change.*
