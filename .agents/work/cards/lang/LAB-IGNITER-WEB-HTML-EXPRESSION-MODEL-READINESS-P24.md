# LAB-IGNITER-WEB-HTML-EXPRESSION-MODEL-READINESS-P24

Status: CLOSED (keystone readiness packet delivered 2026-06-25)
Route: standard / architecture readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-web-html-expression-model-readiness-p24-v0.md`.

**Recommended model: View Descriptor Projection** — the outbound mirror of the Data Projection Boundary. App
projects domain data → typed `ViewArtifact` descriptor; **host projector** renders it → bytes. App never emits
HTML strings/bytes; descriptor = the contract; dialects (`.igv` today, `.ig.html` later) = *projection sugar
that lowers to the descriptor*, never a hidden runtime; host owns rendering + escaping + surface choice.

**It's the model the live code already implements — not a proposal.** `igniter_render_html` declares itself
"a projector / render target, not a language feature… the HTML analogue of the frame `RenderHost` impls
(SVG/wireframe/GUI)" (`frame-ui/igniter-render-html/src/lib.rs:3-6`) → ViewArtifact is a **multi-surface**
descriptor, HTML is one RenderHost. `.igv` already proves the projection-dialect pattern ("LOWERS to the
proven ViewArtifact JSON… SUGAR… does not touch `.ig`", `frame-ui/igniter-ui-kit/src/igv.rs:1-12`).

**Projection symmetry (the unifying frame):** INBOUND external→[host projector]→typed data (P1-P5); COMPUTE
typed data→[app transform]→view model (P4); OUTBOUND ViewArtifact→[host projector HTML|SVG|GUI|3D]→bytes
(P24). App lives entirely in the typed middle. Both ends are host-owned projectors that already exist.

**Escaping/XSS wholly projector-owned:** structured input → user data only in escaped leaves → "no
markup-injection surface" (`render-html:9-13,58`); `safe_url` fail-closed; no raw-HTML node. This is the
security argument FOR descriptors and AGAINST HTML strings (rejected #6).

**Live bound (→ P26):** descriptor is flat/non-recursive (`.ig` has no recursive types `igweb.rs:36`);
`HtmlNode` flat all-required; layouts form/workbench; nodes label/button/text/select/checkbox; no nesting,
no list primitive, no link (safe_url unused `:76`). Enough for Todo form/list; not arbitrary UI. Model holds
regardless of vocab breadth.

**Alternatives (8 compared):** recommend #7 (the model) via #1 typed records + #2 helper conventions; #3
`.igv` = dialect precedent; #4 `.ig.html` deferred→P25; **reject #5 host template engine + #6 HTML strings**;
#8 multi-surface framing = a strength.

**TodoApp first HTML after P6 (Q4):** Idiom A unchanged — `Collection[TodoRow] → map(TodoRowToNode) →
FormView → RenderView` on the `form` layout. All green; needs nothing from P25/P26/P27.

**Doesn't block Data Projection P6:** model consumes `Collection[TodoRow]` via the already-green
transform→ViewArtifact→RenderView path; downstream/additive.

**Verification:** grep → `/tmp/igniter-html-expression-grep.txt` (1210 hits); `cargo test --test
todo_view_app_tests` → **14/14**; `git diff --check` clean. Boundary honored: no code/renderer/dialect/Todo
change, no canon claim; docs only.

## Goal

Decide the high-level model for authoring HTML UI in Igniter after the current `RenderView`/ViewArtifact
proofs and before TodoApp grows a real HTML surface.

This is a **background research card**. It must not block Data Projection P6. It should answer:

```text
typed data projection
  -> app transform
  -> ??? HTML expression model
  -> ViewArtifact / Html tree / Render decision
  -> host projector -> bytes
```

## Current Authority

Live source wins:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/lib.rs` (`Render`, `RenderView`, `RespondView`)
- `server/igniter-web/examples/todo_view_app/`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `server/igniter-render-html/` if present
- cards/docs P16-P23 around `Render`, `RenderView`, helper contracts, lists, conditionals, select options
- Data Projection packets P1-P5

## Questions To Answer

1. What is the authoring surface today?
   - typed `.ig` records;
   - helper contracts;
   - `RenderView`;
   - request-sourced `Render { artifact_json }`;
   - `RespondView` JSON.
2. What is the target intermediate representation?
   - current `ViewArtifact`;
   - typed `HtmlNode` tree;
   - smaller domain view model;
   - template AST;
   - another descriptor.
3. Which layer should own each concern?
   - domain data;
   - view model;
   - layout;
   - escaping / XSS;
   - assets;
   - actions/forms;
   - HTTP response bytes.
4. What should TodoApp HTML use first after Data Projection P6?
5. What should stay explicitly out of v0?

## Design Bias

- Do not make `.ig.html` the default answer.
- Do not put HTML strings in `.ig` as the main DX.
- Treat ViewArtifact as the **proven substrate** unless evidence shows it cannot carry app UI.
- Any future dialect must be a projection dialect: it lowers to existing Igniter values / ViewArtifact,
  not to a hidden template runtime.
- Keep host renderer/projector authority outside `.ig`; app returns structured descriptors.

## Alternatives To Compare

Compare at least:

1. Typed `.ig` `HtmlNode`/`ViewArtifact` records + helper contracts.
2. App-local UI helper package/conventions (`MakeLabel`, `FormView`, `<Row>ToNode`).
3. `.igv` as a ViewArtifact projection dialect.
4. `.ig.html` as a template projection dialect.
5. Host-side template engine / middleware.
6. Direct HTML string return from `.ig`.
7. Hybrid: `.ig` transforms data to ViewModel, dialect renders ViewModel to ViewArtifact.

## Boundary

Allowed:

- Write a readiness packet.
- Include pseudo-code and comparison tables.
- Recommend next cards.

Closed:

- No code changes.
- No renderer changes.
- No new dialect implementation.
- No TodoApp route/view implementation.
- No claim that any HTML dialect is canon or implemented.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-web-html-expression-model-readiness-p24-v0.md`

Must include:

- current live HTML/rendering surface;
- model recommendation;
- layer ownership map;
- comparison of alternatives;
- how it composes with Data Projection P6;
- first implementation/research cards after P24.

## Verification

Run:

```bash
rg -n "RenderView|Render \\{|RespondView|ViewArtifact|HtmlNode|MakeLabel|FormView|TodoLabel|html-preview|text/html" \
  server/igniter-web server/igniter-render-html lab-docs/lang .agents/work/cards/lang \
  > /tmp/igniter-html-expression-grep.txt

cargo test --test todo_view_app_tests
git diff --check
```

Run Cargo from `server/igniter-web`.

## Acceptance

- [x] Packet exists.
- [x] It verifies live surface before recommending.
- [x] It keeps ViewArtifact vs dialect vs renderer layers distinct.
- [x] It says what TodoApp should use first after Data Projection P6.
- [x] It compares at least seven alternatives (8 compared).
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- recommended HTML expression model;
- why it does not block Data Projection P6;
- next cards.
