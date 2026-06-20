# LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18 - ViewArtifact authoring without inline JSON

Status: CLOSED
Lane: standard
Type: readiness / architecture
Delegation code: OPUS-IGWEB-VIEWARTIFACT-AUTHORING-P18
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The delivery path is now proven:

- `LAB-IGNITER-WEB-RENDER-DECISION-P16` — `Render { artifact_json }` routes ViewArtifact JSON through
  `igniter-render-html` and P15 raw response as real `text/html`.
- `LAB-TODOAPP-VIEW-HTML-P17` — `todo_view_app` returns real HTML over loopback via that seam.

P17 deliberately left the authoring gap open:

```text
current proof:
  ViewArtifact JSON arrives as req.body
  .ig handler passes it through Render { artifact_json: req.body }

missing:
  author writes the ViewArtifact in Igniter-owned source
  without inline JSON strings, without raw HTML strings, and without .ig.html magic
```

The decisive live constraint from P16/P17: `.ig` string literals cannot contain escaped quotes, so full JSON
cannot be authored inline as a string. P18 chooses the next honest authoring form.

## Goal

Produce a readiness packet that selects the smallest good ViewArtifact authoring path for IgWeb/TodoApp and
names the next implementation card.

The design must preserve:

- ViewArtifact as a structured descriptor, not raw HTML;
- server-core renderer-free boundary;
- IgWeb as a Projection Dialect, not a hidden runtime;
- no DB/effect-host dependency;
- no premature `.ig.html` or template language.

## Verify First

Read live surfaces before writing the packet:

- `lab-docs/lang/lab-igniter-web-render-decision-p16-v0.md`
- `lab-docs/lang/lab-todoapp-view-html-p17-v0.md`
- `lab-docs/lang/lab-todoapp-view-manifest-p2-v0.md`
- `server/igniter-web/examples/todo_view_app/`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `server/igniter-web/examples/render_html_app/`
- `server/igniter-web/src/lib.rs`
  - `map_decision`
  - `RespondView`
  - `Render`
- `lang/igniter-compiler/src/igweb.rs`
  - IgWeb prelude `ViewItem`/`View`/`RespondView`/`Render`
- `lang/igniter-compiler/src/lexer.rs`
  - string literal escape behavior
- `frame-ui/igniter-ui-kit/src/view_artifact.rs`
- `frame-ui/igniter-ui-kit/tests/view_artifact_tests.rs`
- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
- `lab-docs/lang/lab-frame-viewartifact-p12-v0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`

Confirm or correct:

- current `RespondView` uses a small Todo `View { kind, title, items }`, not the full ViewArtifact schema;
- current `Render` takes `artifact_json : String`;
- full ViewArtifact accepted by `igniter-render-html` is JSON with `artifact:"view"` and `layout:"form"` or
  `layout:"workbench"`;
- `.ig` records and collections can be authored, but inline JSON strings cannot;
- `map_decision` receives VM decisions as JSON `Value`, so nested structured values may already be
  inspectable in Rust if the prelude exposes a typed artifact arm.

## Central Question

What should an app author write?

Avoid the two bad extremes:

- too low-level: manually concatenate JSON strings or raw HTML strings in `.ig`;
- too magical: invent `.ig.html`/template runtime before proving structured authoring pressure.

The likely goal is:

```text
author writes structured ViewArtifact-like values in Igniter
  -> IgWeb decision carries a structured artifact value
  -> igniter-web serializes/validates/projects with existing render-html
  -> text/html bytes
```

But P18 must compare alternatives before choosing.

## Design Alternatives To Compare

### A. Typed IgWeb prelude records + `RenderView { status, view }`

Extend the IgWeb prelude with a bounded typed descriptor matching the renderer's v0 `form` subset, e.g.

```ig
type HtmlNode { kind : String, id : Option[String], label : String, text : String, required : Bool, action : String }
type ViewArtifact { artifact : String, layout : String, title : String, body : Collection[HtmlNode] }
variant Decision {
  RenderView { status : Integer, view : ViewArtifact }
}
```

`igniter-web` serializes the `view` value to JSON and calls `render_html`.

Questions:

- Can optional fields be ergonomic enough?
- Does this bloat the IgWeb prelude too early?
- Can it stay generic/domain-free?
- Can it share naming with frame-ui's `ViewArtifact` without claiming canon?

### B. Builder/factory contracts in ordinary `.ig`

Do not put a full schema in the prelude. Provide ordinary helper contracts/types in an app/library module:

```ig
MakeLabel(text) -> ArtifactNode
MakeButton(id,label,action) -> ArtifactNode
TodoIndexArtifact(req) -> ViewArtifact
```

Questions:

- Where do shared helpers live: app-local `.ig`, `igniter-web` example, or future stdlib package?
- Does this avoid a giant prelude while keeping authoring readable?
- How does `RenderView` know the resulting record shape?

### C. `.igv` / projection dialect path

Reuse or revive the existing ViewArtifact authoring lineage:

```text
.igv authoring surface -> ViewArtifact JSON -> Render
```

Questions:

- Is `.igv` already the right authoring DSL for views?
- Is it too UI-runtime-specific for server HTML?
- How does it compose with IgWeb route handlers and route params?
- Does it fit Projection Dialects governance P0?

### D. Fix `.ig` string escapes / add JSON literal support first

Teach `.ig` strings to support escapes, or introduce a JSON literal/data block.

Questions:

- This solves inline JSON, but is inline JSON the right authoring model?
- What compiler/parser blast radius?
- Is it useful independently enough to open now?

### E. `.ig.html` template dialect

Dedicated HTML authoring surface that lowers to pure `.ig` or ViewArtifact.

Questions:

- Does it violate the current structured-descriptor direction?
- Can it lower to ViewArtifact instead of raw HTML?
- Is the demand strong enough now, or is this premature?

### F. Host/projector-only transform of small `View`

Keep current `RespondView` small descriptor and teach host/projector to map it to full ViewArtifact/HTML.

Questions:

- Is that too Todo-specific / app-specific?
- Does it create hidden mapping outside app code?
- Does it block richer views?

## Questions To Answer

### Q1. What is the recommended v0 authoring surface?

Pick one primary path and one fallback. Explain why it is smallest and still aesthetically good.

### Q2. Does the decision protocol need a new arm?

Options:

- keep `Render { artifact_json : String }`;
- add `RenderView { status, view }`;
- replace/merge `RespondView`;
- add generic `Project { target, descriptor }`.

Be explicit about compatibility with P16/P17.

### Q3. How much schema belongs in the IgWeb prelude?

Avoid dumping a large UI schema into every app if app-local/helper modules are cleaner.

### Q4. How does this relate to frame-ui ViewArtifact?

Name whether IgWeb authoring mirrors, imports, or merely targets the frame-ui ViewArtifact shape.

Do not claim canon unless the live status supports it.

### Q5. How does this relate to `.igv`?

Is `.igv` the long-term authoring dialect for views, or a separate frame/tooling artifact?

If recommending `.igv`, specify exact lowering target and how route params/data flow into it.

### Q6. What about `.ig.html`?

Give a clear answer: reject for now, defer behind a dedicated readiness, or define strict conditions under
which it would be acceptable.

### Q7. How does authoring remain safe?

Specify escaping/XSS ownership:

- user text is data in structured leaf fields;
- no raw HTML node in v0;
- renderer owns escaping and URL checks;
- unknown nodes fail closed.

### Q8. How does authoring compose with route params/data?

Example target:

```ig
TodoIndexArtifact(req, req_info, user, todos) -> ViewArtifact
TodoDetailArtifact(req, todo) -> ViewArtifact
```

Can current `.ig` records/collections express this?

### Q9. What are the exact next implementation tests?

Name the next card, likely:

`LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19`

Possible acceptance:

- authored Todo artifact contract, no request-body JSON;
- real route returns HTML via `RenderView` or chosen equivalent;
- malicious text escaped;
- invalid/unsupported node fails closed;
- existing P17 request-body path still works;
- no `.ig.html`, no server-core render dependency.

### Q10. What remains out of scope?

Explicitly defer:

- CSS/assets/static shell;
- interactive JS;
- file export;
- live DB data;
- source maps;
- canon/stable API.

## Expected Recommendation Bias

Prefer **structured typed authoring** over string/HTML/template authoring.

A good likely answer is:

```text
P18 recommends a small `RenderView` / typed-record proof for the renderer's v0 form subset,
with helper contracts for nodes, while keeping full `.igv` / `.ig.html` as future Projection Dialects.
```

But Opus must verify this against live compiler/VM ergonomics. If records/collections make the proof ugly
or impossible, recommend `.igv` or another path with evidence.

## Closed Scope

- No code changes.
- No `.igweb` grammar implementation.
- No prelude changes in this card.
- No `.ig.html` implementation.
- No string escape implementation.
- No static assets.
- No DB/effect-host work.
- No renderer changes unless only inspected.
- No canon/stable API claim.

## Required Deliverables

- readiness packet:
  - `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p18-v0.md`
- closing report in this card;
- concrete recommendation for the next implementation card;
- explicit acceptance tests for that next card;
- explicit rejection/defer list.

## Acceptance

- [x] P16/P17 live facts are correctly characterized.
- [x] `.ig` no-string-escape constraint is verified.
- [x] frame-ui ViewArtifact shape is inspected.
- [x] render-html supported vocabulary is inspected.
- [x] at least six authoring alternatives are compared.
- [x] recommended v0 authoring surface is explicit.
- [x] protocol decision impact is explicit.
- [x] XSS/escaping ownership is explicit.
- [x] relationship to `.igv` and `.ig.html` is explicit.
- [x] next implementation card is named with concrete tests.
- [x] no code changed.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p18-v0.md` — readiness packet, **no
code** (`git diff` clean; only the packet + this card). Six alternatives (A–F) compared; Q1–Q10 answered.

**Recommendation:** **Alternative A — typed prelude records + `RenderView { status, view : ViewArtifact }`.**
It adds *zero new mechanism* — it widens the proven `RespondView`/`View` record+collection pattern (P2) to
the renderer's form schema. Decisive verify-first finding: the renderer is **kind-dispatched and ignores
extra fields**, so a **flat `HtmlNode` record** (one type, `kind` + leaf fields, unused defaulted)
serializes to exactly the renderer's JSON with **no `__arm`→`kind` adapter** (records serialize clean; only
*variants* carry VM discriminants). It composes with route params/data because the artifact is built by a
**per-request `.ig` contract** taking `req`/params/data as inputs — something static `.igv` can't do without
a binding layer. App-local **helper contracts (B)** are the ergonomic layer; the prelude stays bounded +
domain-free.

**Protocol:** add `RenderView { status, view }`, **keep** `Render { artifact_json }` (P16/P17 path intact),
do **not** merge `RespondView`. `map_decision` serializes `view` → `render_html` → `ServerResponse::raw`.

**Deferred (named):** `.igv` (C, future Projection Dialect — authors static views, needs binding for
per-request data); `.ig.html` (E, dedicated readiness, must lower to ViewArtifact/pure-`.ig`); `.ig`
string-escape/JSON-literal (D); generic `Project { target, descriptor }`; `select` options.
**Rejected:** host-side `View`→ViewArtifact mapping (F); raw HTML / manual JSON in `.ig`; large/Todo-specific
prelude schema. **XSS:** unchanged — structured leaves, no raw-HTML node, renderer owns escaping/URL,
unknown fails closed; typed authoring adds no new surface.

**Next:** `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19` — implement `RenderView` + bounded `HtmlNode`/
`ViewArtifact` prelude records + a Todo artifact authored from `.ig` records (no request-body JSON); 7
acceptance tests listed in the packet §Q9.

## Suggested Read-Only Commands

```bash
rg -n "Render|RespondView|ViewItem|type View|variant Decision" lang/igniter-compiler/src/igweb.rs server/igniter-web/src/lib.rs
rg -n "read_string|string literal|escape" lang/igniter-compiler/src/lexer.rs
sed -n '1,220p' frame-ui/igniter-ui-kit/src/view_artifact.rs
sed -n '1,260p' frame-ui/igniter-render-html/src/lib.rs
rg -n "igv|ViewArtifact|Projection Dialect" lab-docs/lang .agents/work/cards/lang
git diff --check
```

## Next

Expected next card after P18:

- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19` — implementation proof for the chosen authoring form.

Downstream:

- Todo HTML route uses authored artifact, not request-body JSON;
- assets/static shell readiness;
- file-export readiness over the same descriptor-to-bytes family.
