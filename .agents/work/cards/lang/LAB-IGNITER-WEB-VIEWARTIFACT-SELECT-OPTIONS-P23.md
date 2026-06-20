# LAB-IGNITER-WEB-VIEWARTIFACT-SELECT-OPTIONS-P23 - Select options authoring for ViewArtifact forms

Status: CLOSED
Lane: standard
Type: implementation-proof / pressure test
Delegation code: OPUS-IGWEB-VIEWARTIFACT-SELECT-OPTIONS-P23
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The ViewArtifact authoring stack has progressed in narrow, proven steps:

- P19: typed `.ig` records can author `ViewArtifact` and return real HTML through `RenderView`.
- P20: app-local helper contracts make single-node authoring pleasant.
- P21: `map` can convert `Collection[TodoItem]` into `Collection[HtmlNode]`.
- P22: `filter` + `map` can author conditional lists.

The remaining obvious form-vocabulary gap is `select` options. The `igniter-render-html` renderer already
knows about select-like nodes if the live code says so; this card must verify the exact schema and prove the
authoring shape from `.ig`.

## Goal

Prove a Todo view can author a select/dropdown node from a domain collection:

```text
Collection[StatusOption] or Collection[String]
  -> map / helper contracts
  -> HtmlNode { kind: "select", options: [...] }
  -> FormView
  -> RenderView
  -> text/html
```

Keep this as app-local ViewArtifact authoring. Do not add a new dialect, template engine, or prelude shape
unless live code proves the current flat `HtmlNode` cannot express select options.

## Verify First

Read live surfaces before editing:

- `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p18-v0.md`
- `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p19-v0.md`
- `lab-docs/lang/lab-igniter-web-viewartifact-helper-contracts-p20-v0.md`
- `lab-docs/lang/lab-igniter-web-viewartifact-list-authoring-p21-v0.md`
- `lab-docs/lang/lab-igniter-web-viewartifact-conditional-lists-p22-v0.md`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `frame-ui/igniter-render-html/src/lib.rs`
- render-html fixtures/tests for `select`, `options`, labels, escaping, unsupported nodes.
- `lang/igniter-compiler/tests/fixtures` for `Collection[String]` and nested collection fields in records.

Confirm or correct:

- exact renderer schema for `kind: "select"`;
- whether `HtmlNode` already has the needed `options: Collection[String]` field;
- whether options are rendered in authored order;
- whether option labels are escaped;
- whether empty options fail closed or render an empty select;
- whether there is any selected/default-value support today.

Live code wins over this card.

## Recommended Shape

Prefer the smallest Todo fixture extension:

```igweb
route GET "/todos/filter-html" -> TodoFilterHtml
```

Author a small status filter form:

```ig
pure contract TodoFilterHtml {
  input req : Request
  compute options : Collection[String] = ["all", "pending <script>", "done"]
  compute select : HtmlNode = call_contract("MakeSelect", "status", "Status", options)
  compute body : Collection[HtmlNode] = [select, call_contract("MakeButton", "apply", "Apply", "/todos")]
  compute view : ViewArtifact = call_contract("FormView", "Filter", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

If `MakeSelect` does not exist, add it as an app-local helper contract in `todo_views.ig`. Do not promote it
to prelude/shared package yet. If the flat `HtmlNode` lacks `options`, first verify whether P19 already added
it; if not, consider the narrowest prelude record extension and document why it is schema, not behavior.

## Alternatives To Compare

### A. `HtmlNode.options : Collection[String]`

Preferred if already present. Simple and matches current renderer vocabulary.

### B. `Collection[OptionNode]`

Richer but probably premature unless renderer already expects structured options.

### C. Domain enum / variant options

Rejected for v0 unless live UI pressure requires typed option values. Keep display/value semantics explicit
and small.

### D. HTML string options

Rejected. Options are structured data; renderer owns escaping.

## Required Acceptance

- [x] Todo select route renders real `text/html` through `RenderView`.
- [x] Handler starts from an authored option collection, not hardcoded HTML.
- [x] Select node is built through app-local helper (`MakeSelect`).
- [x] Options render in deterministic authored order.
- [x] Malicious option text is escaped; no raw `<script>`.
- [x] Empty/unsupported select behavior documented (empty → empty `<select>`; missing now unreachable).
- [x] Existing P19/P20/P21/P22 routes remain green.
- [x] `render_html_app_tests` remain green.
- [x] `igniter-render-html` tests remain green.
- [x] `igweb_lowering_tests` remain green (prelude CHANGED — `HtmlNode.options` field still compiles).
- [x] `igniter-server` normal dependency tree remains renderer-free.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Files changed:** `lang/igniter-compiler/src/igweb.rs` (prelude `HtmlNode` += `options : Collection[String]`),
`examples/todo_view_app/todo_views.ig` (+`MakeSelect`, +`TodoFilterHtml`, backfilled `options: []` on the 6
existing nodes/helpers), `routes.igweb` (+`/todos/filter-html`), `tests/todo_view_app_tests.rs` (+1 test).
Proof doc: `lab-docs/lang/lab-igniter-web-viewartifact-select-options-p23-v0.md`.

**Outcome (Alternative A):** the renderer's `select` schema is `{id,label,required,options:[string]}`; the
flat `HtmlNode` lacked `options`, so it was extended (schema, not behavior). A select is authored from a
`Collection[String]` via `MakeSelect`; options render in authored order, each escaped; empty options → empty
`<select>`; the missing-options fail-closed path is now unreachable from typed authoring.

**Honest cost (signal for the language branch):** `.ig` records require ALL fields and have no record
spread / optional fields, so the one new field forced `options: []` on every existing node (verified via
`OOF-TY0: required field 'options' is missing`). Concrete evidence that **record spread / optional fields**
belong on the parallel surface-ergonomics branch.

**Proof — all green:** todo_view_app **14** (incl. select); render_html_app 3; igniter-render-html 11;
igweb lowering 11 + lib 55 (prelude change compiles through the real compiler); igniter-server green +
renderer-free; `git diff --check` clean.

**Form vocabulary complete for v0** (label/text/checkbox/button/select). **Next:** nested layout (P24) and
the record-verbosity ergonomics on the parallel language branch.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test todo_view_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --test render_html_app_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-render-html && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit'
git diff --check
```

Remember: the `cargo tree | rg ...` command should have **no matches**; a non-zero exit there is success.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-viewartifact-select-options-p23-v0.md
```

It must state:

- exact renderer schema for select/options;
- whether `HtmlNode` already supported options or had to be extended;
- exact `.ig` authoring pattern chosen;
- exact rendered HTML behavior, including ordering and escaping;
- empty/invalid behavior;
- why this remains structured ViewArtifact authoring rather than `.ig.html`;
- next bottleneck after select options.

## Closed Scope

- No `.ig.html`.
- No `.igv` binding layer.
- No template engine.
- No client-side JS behavior.
- No live DB.
- No assets/static-shell work.
- No server-core renderer dependency.
- No shared/prelude helper promotion unless strictly required by schema.
- No public/canon/stable API claim.

## Suggested Next

If P23 lands cleanly:

1. `LAB-IGNITER-WEB-VIEWARTIFACT-NESTED-LAYOUT-P24` if layout expressiveness becomes the next pressure;
2. `LAB-TODOAPP-VIEW-STATIC-SHELL-P*` for serving a browser shell around JSON/HTML views;
3. file/export readiness can resume after the descriptor-to-bytes seam has this form coverage.
