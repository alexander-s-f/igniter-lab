# LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19 - Typed ViewArtifact authoring in IgWeb

Status: CLOSED
Lane: standard
Type: implementation-proof
Delegation code: OPUS-IGWEB-VIEWARTIFACT-AUTHORING-P19
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The HTML delivery seam is already proven:

- `LAB-IGNITER-WEB-RENDER-DECISION-P16` added `Render { status, artifact_json }`:
  ViewArtifact JSON string -> `igniter-render-html` -> raw `text/html`.
- `LAB-TODOAPP-VIEW-HTML-P17` proved a Todo route can return real HTML, but the ViewArtifact JSON is
  sourced from `req.body` because `.ig` cannot author escaped JSON strings.
- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18` chose the next authoring form:
  **typed prelude records + `RenderView { status, view : ViewArtifact }`**, with helper contracts as
  ergonomics later.

P19 turns that P18 recommendation into the smallest working proof.

The goal is not to invent `.ig.html`, revive `.igv`, or create a Temple-like template engine. The goal is
to prove the structured descriptor path end to end:

```text
author writes typed `.ig` records
  -> IgWeb decision carries a structured ViewArtifact value
  -> igniter-web serializes that value to JSON
  -> igniter-render-html projects it to escaped HTML
  -> raw text/html response
```

## Goal

Implement a minimal `RenderView` path so an IgWeb app can author a ViewArtifact in ordinary `.ig` records
and return real HTML without request-body JSON or manual JSON-string construction.

The proof should be Todo-shaped but domain-free at the prelude level.

## Verify First

Read live code before editing:

- `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p18-v0.md`
- `lab-docs/lang/lab-igniter-web-render-decision-p16-v0.md`
- `lab-docs/lang/lab-todoapp-view-html-p17-v0.md`
- `lang/igniter-compiler/src/igweb.rs`
  - IgWeb prelude
  - `Decision`
  - current `ViewItem` / `View` / `RespondView`
  - current `Render`
- `server/igniter-web/src/lib.rs`
  - `map_decision`
  - current `RespondView` path
  - current `Render` path
- `server/igniter-web/examples/todo_view_app/`
  - `routes.igweb`
  - `todo_views.ig`
  - `igweb.toml`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `server/igniter-web/tests/render_html_app_tests.rs`
- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
- `frame-ui/igniter-ui-kit/src/view_artifact.rs`

Confirm or correct these assumptions:

- records and collections serialize to clean JSON values; only variants carry `__arm`/variant metadata;
- `map_decision` can access a nested `view` JSON value in a decision arm, similar to `RespondView`;
- `igniter-render-html` supports the bounded v0 form vocabulary:
  - `artifact: "view"`
  - `layout: "form"`
  - `title`
  - `body: Collection` of nodes with `kind`
  - `label`, `button`, `text`, `checkbox`, and possibly `select`;
- unknown node kinds fail closed;
- `Render { artifact_json }` must remain green and additive.

## Recommended Minimal Shape

Extend the IgWeb prelude with bounded records and one decision arm:

```ig
type HtmlNode {
  kind     : String
  id       : String
  label    : String
  text     : String
  required : Bool
  action   : String
}

type ViewArtifact {
  artifact : String
  layout   : String
  title    : String
  body     : Collection[HtmlNode]
}

variant Decision {
  ...
  RenderView { status : Integer, view : ViewArtifact }
}
```

Keep this intentionally flat and small. Do **not** add a full UI schema, variant nodes, raw HTML nodes,
CSS, JS, URL fields, asset references, or Todo-specific fields.

If `select` support is trivial and already requires only `options : Collection[String]`, Opus may include
it only if it does not expand the proof materially. Otherwise defer `select` explicitly.

`igniter-web` handling:

```text
Decision.RenderView { status, view }
  -> serde_json::to_string(view)
  -> igniter_render_html::render_html(...)
  -> ServerResponse::raw(status, html, "text/html; charset=utf-8")
```

`Render { artifact_json }` remains as the raw JSON/string seam from P16/P17.

`RespondView` remains JSON and is not merged with `RenderView`.

## Todo Proof Shape

Prefer updating `todo_view_app` rather than creating a new app unless the existing fixture becomes noisy.

Add one authored HTML route, for example:

```igweb
GET /todos/authored-html/:todo_id -> TodoAuthoredHtml
```

The handler must build the artifact from typed `.ig` records:

```ig
pure contract TodoAuthoredHtml {
  input req : Request
  input todo_id : String

  compute body : Collection[HtmlNode] = [
    { kind: "label", id: "", label: "", text: todo_id, required: false, action: "" },
    { kind: "button", id: "done", label: "Done", text: "", required: false, action: "submit" }
  ]
  compute view : ViewArtifact = {
    artifact: "view",
    layout: "form",
    title: "Todo Detail",
    body: body
  }
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

The exact route/name/content can differ, but the proof must use:

- ordinary `.ig` records;
- route params or request data flowing into the artifact;
- no request-body ViewArtifact JSON;
- no JSON string literal;
- no string concatenation to build JSON or HTML.

## Edge Cases To Prove

1. malicious leaf text like `<script>` is escaped in HTML;
2. unsupported `kind` fails closed to the same JSON error shape used by the existing render path;
3. existing `Render { artifact_json: req.body }` route from P17 still works;
4. existing `RespondView` JSON routes remain JSON and green.

If constructing a deliberately unsupported node in `.ig` is awkward, add a small test-only route/handler
using `kind: "marquee"` and keep it clearly scoped as failure proof.

## Closed Scope

- No `.ig.html`.
- No Temple-like intermediate representation or template compiler.
- No `.igv` implementation or binding layer.
- No manual JSON strings in `.ig`.
- No raw HTML strings in `.ig`.
- No helper library beyond what is needed inside the app fixture.
- No generic `Project { target, descriptor }`.
- No file export / xlsx / csv / pdf.
- No CSS/assets/static shell.
- No live DB, read guard host, or effect-host work.
- No source-map or diagnostics expansion beyond existing errors.
- No canon/stable API claim.

## Required Tests / Acceptance

- [x] A Todo-authored `RenderView` route returns real `text/html`.
- [x] The response body starts with `<!DOCTYPE html>` and is not JSON-quoted/wrapped.
- [x] The artifact is built from typed `.ig` records, not request-body JSON.
- [x] No inline JSON string or manual JSON/HTML concatenation is introduced in `.ig`.
- [x] Route params or request data flow into the rendered artifact.
- [x] Malicious text such as `<script>` is escaped; no raw script tag appears.
- [x] Unsupported node kind or bad artifact fails closed to JSON 500, not panic.
- [x] P17 `Render { artifact_json: req.body }` path remains green.
- [x] `RespondView` JSON routes remain green.
- [x] `render_html_app_tests` remain green.
- [x] `igniter-render-html` tests remain green.
- [x] `igniter-server` normal dependency tree remains renderer-free.
- [x] `igniter-web` normal dependency tree intentionally includes `igniter_render_html`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Files changed (prelude + igniter-web + Todo fixture):** `lang/igniter-compiler/src/igweb.rs` (prelude +=
`type HtmlNode`, `type ViewArtifact`, `RenderView` arm); `server/igniter-web/src/lib.rs` (`RenderView` arm
+ shared `render_to_decision` helper refactored from `Render`); `examples/todo_view_app/{routes.igweb,
todo_views.ig}` (+`TodoAuthoredHtml`/`TodoBadNode` authored from `.ig` records); `tests/todo_view_app_tests.rs`
(+2 tests). Proof doc: `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p19-v0.md`. No
`igniter-server` change.

**Implemented P18's recommendation (Alternative A):** typed flat `HtmlNode` record + `ViewArtifact` record +
`RenderView { status, view }`. Because records serialize **clean** (no `__arm`/`__variant` — only variants
carry those), the VM-serialized `view` matches the renderer's kind-dispatched JSON **directly, with no
adapter** — the crux that made A the smallest path. `RenderView` and `Render` share one
`render_to_decision` helper. Route params flow in via contract inputs (`/todos/authored-html/42` →
`<p class="ig-label">42</p>`); `<script>` escaped; `marquee` → JSON 500 (`unsupported_node`).

**Proof — all green:** todo_view_app **10** (6 RespondView JSON + 2 P17 Render + 2 new P19 RenderView);
render_html_app 3; igniter-render-html 11; igweb lowering 11 + lib 55 (new prelude compiles through the real
compiler); igniter-server green + renderer-free; igniter-web carries `igniter_render_html`;
`git diff --check` clean.

**TodoApp now has both authoring paths:** P17 external/request JSON → `Render`; P19 authored `.ig` records →
`RenderView`. The ViewArtifact authoring gap is closed without `.ig.html`/`.igv`/template syntax.

**Next:** helper contracts (P18 Alt B, ergonomics) · `select` node (`options`) when needed · later/gated:
`.igv`, `.ig.html`, assets/static shell, file-export family.

## Suggested Verification Commands

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test todo_view_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test render_html_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-render-html && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server && cargo tree -e normal
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo tree -e normal
git diff --check
```

Report exact test counts. If a broad suite has unrelated failures, isolate and name them with evidence.

## Deliverables

- Implementation in the narrowest needed files.
- Updated/added Todo view tests.
- Proof doc:
  - `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p19-v0.md`
- Closing report in this card.

## Expected Result

After P19, TodoApp has both:

```text
P17: external/request ViewArtifact JSON -> Render -> HTML
P19: authored `.ig` records -> RenderView -> HTML
```

This closes the current ViewArtifact authoring gap while keeping `.ig.html`, `.igv`, and Temple-style
template ideas as future, better-informed layers rather than premature syntax.
