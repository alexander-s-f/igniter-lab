# lab-igniter-web-viewartifact-select-options-p23-v0 — select options authoring

**Card:** `LAB-IGNITER-WEB-VIEWARTIFACT-SELECT-OPTIONS-P23` · **Delegation:** `OPUS-IGWEB-VIEWARTIFACT-SELECT-OPTIONS-P23`
**Status:** CLOSED (lab implementation-proof) — a `select` node is authored from a `Collection[String]`
via an app-local `MakeSelect` helper; options render in authored order, each escaped, through the unchanged
`RenderView` path. **One bounded prelude extension (`HtmlNode.options`), no new dialect/template/renderer
change.**
**Authority:** Lab tooling. Implements P23 over the P19–P22 authoring stack.

## Verify-first (live findings)

| Fact | Evidence |
|---|---|
| renderer `select` schema = `{ id, label, required, options:[string,…] }`; options rendered in order, each `escape`d as `<option value="s">s</option>` | `frame-ui/igniter-render-html/src/lib.rs` `render_input` "select" |
| **missing** `options` → fail-closed `InvalidArtifact`; non-string option → `InvalidArtifact`; **empty** options → valid empty `<select></select>` (no failure) | same |
| the P19 flat `HtmlNode` had **no** `options` field | `igweb.rs` prelude (pre-P23) |
| **`.ig` records require ALL fields** (no partial/defaulted records) | adding `options` without backfilling → `OOF-TY0: Record type 'HtmlNode': required field 'options' is missing` |

So a select node **must** carry `options`, the field **must** live on `HtmlNode` (the body is a homogeneous
`Collection[HtmlNode]`), and — because records require all fields — adding it forces every existing node to
set it.

## What changed

**1. Prelude (bounded schema extension, `igweb.rs`):** `HtmlNode` += `options : Collection[String]`. This
is **schema, not behavior** — the renderer already knew the select `options` shape; the prelude record just
gains the field to carry it.

**2. `todo_views.ig` (app-local):**
- new `MakeSelect(id, label, options) -> HtmlNode` helper:
  `{ kind: "select", id, label, text:"", required:false, action:"", options }`;
- new `TodoFilterHtml` route handler building a status `select` from an authored `Collection[String]` +
  a sibling button;
- **backfill:** `options: []` added to every existing node (MakeLabel, MakeButton, the P19 inline
  literals in `TodoAuthoredHtml` ×3 and `TodoBadNode` ×1) — the "all fields required" cost (below).

**3. Route:** `GET /todos/filter-html` (authored before `/todos/:todo_id` — P18 priority policy).

```ig
pure contract TodoFilterHtml {
  input req : Request
  compute options : Collection[String] = ["all", "pending <script>", "done"]
  compute sel   : HtmlNode = call_contract("MakeSelect", "status", "Status", options)
  compute apply : HtmlNode = call_contract("MakeButton", "apply", "Apply", "/todos")
  compute body  : Collection[HtmlNode] = [sel, apply]
  compute view  : ViewArtifact = call_contract("FormView", "Filter", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

## Rendered behavior (proven)

`GET /todos/filter-html` → real `text/html`: `<select name="status">` with three `<option>`s in **authored
order** (`all`, `pending &lt;script&gt;`, `done`); the malicious option text is **escaped** (no raw
`<script>`); a sibling `button` renders in the same body (mixed node kinds). Non-select nodes carry
`options: []` which the renderer **ignores** (kind-dispatched). A select with empty options would render a
valid empty `<select></select>`; the renderer's **missing-options** fail-closed path is now *unreachable*
from typed authoring because `HtmlNode` always carries the field.

## The honest cost (a signal for the language-ergonomics track)

`.ig` records require **all** fields and there is **no record spread / optional fields** today
(`LANG-OPTIONAL-FIELD-PARTIAL-RECORD` is a pending proposal). So a single new `HtmlNode` field forced
editing **every** node literal + helper (`options: []` ×6). The helpers (P20) absorb most of it, but this
is exactly the verbosity that **record spread `{ ...base, options: opts }`** or **optional fields** would
remove — concrete pressure for the parallel surface-ergonomics branch.

## Alternatives (card)

- **A. `HtmlNode.options : Collection[String]`** — **chosen.** Matches the renderer's existing select
  vocabulary; smallest schema add.
- **B. `Collection[OptionNode]`** — rejected (premature; renderer expects string options).
- **C. domain enum/variant options** — rejected for v0.
- **D. HTML string options** — rejected (options are structured data; renderer owns escaping).

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests → 14 passed (+1 NEW select test)
$ cd server/igniter-web && cargo test --test render_html_app_tests → 3 passed (untouched)
$ cd server/igniter-web && cargo test                            → all suites green
$ cd frame-ui/igniter-render-html && cargo test                  → 11 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed (PRELUDE CHANGED — still compiles)
$ cd lang/igniter-compiler && cargo test --lib igweb             → 55 passed
$ cd server/igniter-server && cargo test                         → green (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit' → (none)
$ git diff --check                                               → clean
```

## Acceptance — mapping

- [x] Select route renders real `text/html` through `RenderView`.
- [x] Handler starts from an authored option `Collection[String]`, not hardcoded HTML.
- [x] Select node built via app-local helper (`MakeSelect`).
- [x] Options render in deterministic authored order.
- [x] Malicious option text escaped (`pending &lt;script&gt;`; no raw `<script>`).
- [x] Empty/missing select behavior documented + reasoned (empty → empty `<select>`; missing now unreachable).
- [x] P19/P20/P21/P22 routes green (todo_view_app 14).
- [x] `render_html_app_tests` (3) + `igniter-render-html` (11) green.
- [x] `igweb_lowering_tests` (11) green — prelude changed but still compiles (noted).
- [x] `igniter-server` renderer-free; `git diff --check` clean.

## Why structured ViewArtifact, not `.ig.html`

Options are **structured data** in a typed leaf field; the renderer owns escaping + the `<option>` shape.
An HTML-string authoring path would re-introduce the injection surface the structured node eliminates — so
`select` stays a typed node, consistent with P18's structural-safety rationale.

## Next bottleneck

The form **vocabulary** is now complete for v0 (label/text/checkbox/button/select). The next pressures are
**nested layout / grouping** (sections, not a flat `body`) and the **record verbosity** this card exposed
(record spread / optional fields). The latter is a *language-ergonomics* item for the parallel branch, not
an app-local card.

## Closed scope (honored)

No `.ig.html`/`.igv`/template engine; no client JS; no live DB; no assets/static-shell; no server-core
renderer dep; helper stays app-local (not promoted to prelude/shared); no canon claim. The only prelude
touch is the single `options` field on `HtmlNode` (schema, not behavior).

## Next

1. `LAB-IGNITER-WEB-VIEWARTIFACT-NESTED-LAYOUT-P24` (layout/grouping) if layout becomes the pressure.
2. **Parallel surface-ergonomics branch:** record spread / optional fields (this card is concrete evidence).
3. `LAB-TODOAPP-VIEW-STATIC-SHELL-P*`; file/export readiness can resume with full form coverage.

---

*Lab implementation-proof. Compiled 2026-06-20; todo_view_app 14 green (incl. select), render_html_app 3,
igniter-render-html 11, igweb lowering 11 + lib 55 (prelude `options` field compiles through the real
compiler), igniter-server green + renderer-free, `git diff --check` clean. The form vocabulary is complete;
the only cost was the all-fields-required record verbosity, flagged for the language branch.*
