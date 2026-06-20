# LAB-IGNITER-WEB-VIEWARTIFACT-HELPER-CONTRACTS-P20 - Ergonomic ViewArtifact helper contracts

Status: CLOSED
Lane: standard
Type: implementation-proof
Delegation code: OPUS-IGWEB-VIEWARTIFACT-HELPERS-P20
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The structured HTML path is now proven:

- `LAB-IGNITER-WEB-RENDER-DECISION-P16` — `Render { artifact_json }` projects ViewArtifact JSON to
  escaped raw `text/html`.
- `LAB-TODOAPP-VIEW-HTML-P17` — Todo can return real HTML using request-sourced ViewArtifact JSON.
- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18` — selected typed `.ig` record authoring as the v0 path.
- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19` — implemented `RenderView { status, view }` and bounded
  `HtmlNode` / `ViewArtifact` records; Todo now authors ViewArtifact in `.ig` records.

P19 intentionally accepted some verbosity:

```ig
{ kind: "label", id: "", label: "", text: "...", required: false, action: "" }
```

That verbosity was worth it because flat records serialize directly to the renderer schema without a
variant/`__arm` adapter. P20 should improve the authoring feel **without changing the protocol**.

Think of this as borrowing the good idea from Temple — a compact intermediate expression tree — but keeping
it in Igniter's world: ordinary typed `.ig` helper contracts that return the already-proven `HtmlNode`
records. No template runtime, no `.ig.html`, no new parser.

## Goal

Prove that ViewArtifact authoring can be made pleasant through helper contracts, while preserving P19's
plain data model:

```text
MakeLabel("Todos")      -> HtmlNode
MakeButton("done", ...) -> HtmlNode
FormView("Todos", body) -> ViewArtifact
RenderView { status, view }
```

The goal is ergonomic pressure, not feature breadth.

## Verify First

Read live surfaces before editing:

- `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p19-v0.md`
- `lang/igniter-compiler/src/igweb.rs`
  - `HtmlNode`
  - `ViewArtifact`
  - `RenderView`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
  - current verbose `TodoAuthoredHtml`
- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `server/igniter-web/src/lib.rs`
  - `RenderView` handling
- `frame-ui/igniter-render-html/src/lib.rs`

Confirm or correct:

- contract calls can be used inside collection literals; if not, use named `compute` nodes before the
  collection and document the limitation;
- helper-returned records serialize identically to inline record literals;
- `RenderView` path remains unchanged;
- unsupported kinds still fail closed in the renderer.

## Recommended Minimal Shape

Add helper contracts in the Todo view app fixture first, not the IgWeb prelude:

```ig
pure contract MakeLabel {
  input text : String
  compute node : HtmlNode = { kind: "label", id: "", label: "", text: text, required: false, action: "" }
  output node : HtmlNode
}

pure contract MakeButton {
  input id : String
  input label : String
  input action : String
  compute node : HtmlNode = { kind: "button", id: id, label: label, text: "", required: false, action: action }
  output node : HtmlNode
}

pure contract FormView {
  input title : String
  input body : Collection[HtmlNode]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: title, body: body }
  output view : ViewArtifact
}
```

Then rewrite or add one route whose artifact reads like composition:

```ig
compute title : HtmlNode = call_contract("MakeLabel", "Todos")
compute done  : HtmlNode = call_contract("MakeButton", "done", "Done", "submit")
compute body  : Collection[HtmlNode] = [title, done]
compute view  : ViewArtifact = call_contract("FormView", "Todo Detail", body)
compute d     : Decision = RenderView { status: 200, view: view }
```

If the language already supports calling helper contracts directly inside arrays, this shape may be tighter:

```ig
compute body : Collection[HtmlNode] = [
  call_contract("MakeLabel", "Todos"),
  call_contract("MakeButton", "done", "Done", "submit")
]
```

But do not force this if the compiler does not support it cleanly. Named `compute` nodes are acceptable and
agent-readable.

## Design Rules

- Helpers are app-local / example-local for P20. Do not promote them to prelude or stdlib yet.
- Helpers return the existing P19 flat records. Do not introduce a new node enum or adapter.
- Helpers are pure `.ig` contracts. No Rust helpers, no host mapping, no renderer changes.
- Do not widen the renderer vocabulary unless a test proves the need.
- Do not remove the verbose P19 route unless keeping both is noisy. At least one test must continue proving
  P19's direct record path or explicitly state that P20 supersedes it with identical output.
- Keep Temple as an inspiration only: expression-tree discipline, not Ruby metaprogramming or a template
  DSL.

## Questions To Answer In The Closing Report

1. Can `call_contract(...)` appear inside `Collection[HtmlNode]` literals?
2. If not, is the named-compute style still good enough?
3. Does helper output render byte-identically or behavior-identically to direct records?
4. Should helpers stay app-local, move to an `igniter-web` example module, or become a future package?
5. Does this reduce enough verbosity to delay `.ig.html` / `.igv` pressure?
6. What is the next ergonomic bottleneck: `select options`, nested layout, lists, or source-map diagnostics?

## Closed Scope

- No `.ig.html`.
- No `.igv` binding layer.
- No new parser/lowering syntax.
- No Temple-like runtime or Ruby-style metaprogramming.
- No new `Decision` arm.
- No change to `RenderView` protocol.
- No `HtmlNode` variant enum.
- No renderer changes unless a small bug is discovered and justified.
- No static assets/CSS/JS.
- No live DB/effect-host/read-guard work.
- No canon/stable API claim.

## Required Tests / Acceptance

- [x] A helper-authored Todo HTML route returns real `text/html`.
- [x] The route uses helper contracts returning `HtmlNode` / `ViewArtifact`, not raw record literals for every node.
- [x] Route param or request data flows through a helper into rendered HTML.
- [x] Malicious text passed through a helper is escaped; no raw `<script>`.
- [x] P19 direct `RenderView` route remains green, AND helper route is proven byte-identical to it.
- [x] P17 `Render { artifact_json }` path remains green.
- [x] `RespondView` JSON routes remain green.
- [x] Unsupported node failure remains renderer-owned and fail-closed.
- [x] `render_html_app_tests` remain green.
- [x] `igniter-render-html` tests remain green.
- [x] `igniter-server` normal dependency tree remains renderer-free.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Smallest possible diff — Todo fixture + its test ONLY, zero prelude/compiler/Rust/renderer change:**
`examples/todo_view_app/todo_views.ig` (+`MakeLabel`/`MakeButton`/`FormView` helpers + `TodoHelperHtml`),
`routes.igweb` (+`/todos/helper-html/:todo_id`), `tests/todo_view_app_tests.rs` (+1 byte-identity test).
Proof doc: `lab-docs/lang/lab-igniter-web-viewartifact-helper-contracts-p20-v0.md`.

**Result:** app-local pure `.ig` helper contracts return the proven P19 flat `HtmlNode`/`ViewArtifact`
records, so the verbose 6-field-per-node literal becomes a single `call_contract("MakeLabel", …)`. The
helper-authored route is **byte-identical** to the direct-record route for the same inputs
(`helper_authored_html_is_byte_identical_to_direct_records`). Param flows through a helper; `<script>`
escaped; unsupported `kind` still fails closed.

**Closing-report answers:** (1) `call_contract` works **both** inline in a `Collection[HtmlNode]` literal
**and** as named computes (inline probed, named committed); (2) named-compute is readable + sufficient;
(3) helper output is **byte-identical** to direct records; (4) helpers stay **app-local** (promote to a
shared module/package only when ≥2 apps need them); (5) yes — materially cuts verbosity, delaying
`.ig.html`/`.igv` pressure; (6) next bottleneck = **lists/iteration** (map a `Collection[domain]` →
`Collection[HtmlNode]`) and **`select` options**.

**Proof — all green:** todo_view_app 11 (incl. byte-identical helper test); render_html_app 3;
igniter-render-html 11; igweb lowering 11 (prelude unchanged); igniter-server green + renderer-free;
`git diff --check` clean.

**Next:** lists/iteration authoring (top bottleneck) · `select` node · later/gated: shared helper module,
`.igv`, `.ig.html`, assets, file-export.

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

Report exact counts. If broad suites have unrelated failures, isolate them by touched files and state the
evidence.

## Deliverables

- Narrow implementation in `todo_view_app` and tests, plus any tiny compiler/prelude adjustment only if
  verify-first proves it is unavoidable.
- Proof doc:
  - `lab-docs/lang/lab-igniter-web-viewartifact-helper-contracts-p20-v0.md`
- Closing report in this card.

## Expected Result

After P20, the authoring progression should be clear:

```text
P19: raw typed records are possible and correct
P20: helper contracts make the same model pleasant enough for real app work
```

Only after this should we reopen heavier authoring ideas like `.igv` binding, `.ig.html`, or a Temple-like
projection dialect.
