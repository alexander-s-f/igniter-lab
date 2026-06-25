# LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE

Status: CLOSED (implemented + proven 2026-06-25)
Route: standard / implementation proof
Skill: idd-agent-protocol
Suggested sequence: P28 (after P24-P27 HTML descriptor wave; after existing P21-P23 list/filter/select proofs)

## Closing report (2026-06-25)

Proof doc: `lab-docs/lang/lab-igniter-web-viewartifact-link-node-v0.md`.

**Done — the first URL-bearing ViewArtifact node, wiring the pre-built `safe_url`.**

**Files changed (5, +134 lines, additive only):**
- `frame-ui/igniter-render-html/src/lib.rs` (+9) — `link` arm in `render_component`: `href =
  safe_url(req(action))?; text = escape(req(text))?` → `<a class="ig-link" href={href}>{text}</a>`.
- `frame-ui/igniter-render-html/tests/render_html_tests.rs` (+73) — 4 `link_*` tests.
- `server/igniter-web/examples/todo_view_app/todo_views.ig` (+27) — `MakeLink` helper + `TodoLinkHtml`.
- `server/igniter-web/examples/todo_view_app/routes.igweb` (+2) — `/todos/link-html/:todo_id`.
- `server/igniter-web/tests/todo_view_app_tests.rs` (+23) — authored-route test.

**Node shape:** reused flat `HtmlNode` fields — `kind:"link"`, **`text`=label, `action`=href** (no `href`
field added; no prelude change).

**Dangerous schemes fail closed (confirmed):** `javascript:`/`data:`/`mailto:` → `UnsafeUrl`, no `<a>`
emitted (`link_rejects_dangerous_schemes_without_emitting_anchor`); missing text/action → `InvalidArtifact`;
href+label escaped. Unknown-node fail-closed unchanged.

**Tests (green):** `igniter-render-html` `cargo test` = **15** (3 lib + 12 integration, +4 new);
`server/igniter-web` `cargo test --test todo_view_app_tests` = **15** (14 prior + 1 new). `git diff --check`
clean. No prelude/server-core/protocol change; no recursion; no raw HTML; no new language syntax.

**Enough for TodoApp nav/pagination?** Yes for index→detail links + `?after=` "load more" (one URL-bearing
leaf). Richer per-item rows = the bounded non-recursive `list`/`item` layout (P26 §4), held until demonstrated
need.

**Next:** `LAB-IGNITER-WEB-VIEWARTIFACT-LIST-LAYOUT` (held); TodoApp HTML list after typed-row crossing (now
can include per-row links); download/export links (P27 raw seam) later.

> **Scope note (not part of this card):** the working tree also carried pre-existing uncommitted changes in
> `runtime/igniter-machine/src/{machine.rs,registry.rs}` and `server/igniter-web/src/read_dispatch.rs`
> (+64 lines total) that I did **not** author and **left untouched** — likely the parallel data-projection
> typed-row-crossing work. This card's diff is exactly the 5 files above.

## Goal

Add the smallest URL-bearing `ViewArtifact` node:

```json
{ "kind": "link", "text": "Next", "action": "/todos?after=todo_2" }
```

Rendered as escaped, fail-closed HTML:

```html
<a href="/todos?after=todo_2">Next</a>
```

This should unlock TodoApp navigation and pagination without introducing nesting, raw HTML, a template
runtime, or a new dialect.

## Why This Card Exists

P26 (`lab-igniter-web-viewartifact-evolution-readiness-p26-v0`) found that current Todo HTML pressure is
mostly covered by the existing flat `HtmlNode` vocabulary plus helper contracts:

- labels;
- buttons;
- text/select/checkbox inputs;
- list/filter/select authoring via P21-P23.

The one real schema gap is **links/anchors**:

- index -> detail navigation;
- pagination / "load more" via `?after=<cursor>`;
- later download/export links.

The safety machinery already exists: `igniter-render-html::safe_url` is built and tested, but not wired to
any node because v0 had no URL-bearing node. This card should wire that pre-designed seam.

## Current Authority

Read these first:

- `lab-docs/lang/lab-igniter-web-viewartifact-evolution-readiness-p26-v0.md`
- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
- `lang/igniter-compiler/src/igweb.rs` (`HtmlNode`, `ViewArtifact`, `RenderView`)
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/tests/todo_view_app_tests.rs`

Live code wins over packet prose. Verify `safe_url` behavior before adding the renderer arm.

## Implementation Target

Use the existing flat `HtmlNode` fields:

- `kind = "link"`
- `text` = visible label
- `action` = href

Do **not** add `href` unless live code proves reusing `action` is impossible. The point is to keep the
descriptor flat and avoid prelude churn.

Recommended changes:

1. `igniter-render-html`:
   - add `render_component` arm for `kind == "link"`;
   - render `<a class="ig-link" href="{safe_url(action)}">{escape(text)}</a>` or equivalent simple class;
   - href must go through `safe_url`;
   - text must go through `escape`;
   - missing `text`/`action` fails closed with `InvalidArtifact`;
   - unsupported/dangerous scheme fails closed with `UnsafeUrl`.
2. `todo_view_app`:
   - add app-local helper `MakeLink(text, href) -> HtmlNode`;
   - add a small authored route, e.g. `GET /todos/link-html/:todo_id`, proving path-param -> href/text.
3. Tests:
   - renderer accepts relative and http(s) links;
   - renderer rejects `javascript:`, `data:`, `mailto:` without emitting an `<a>`;
   - link text and href attributes are escaped;
   - Todo route renders a link from authored `.ig` records through `RenderView`;
   - existing Todo view tests remain green.

## Safety Rules

- No raw HTML node.
- No template strings.
- No bypass around `safe_url`.
- No arbitrary attributes.
- No `target`, `rel`, `download`, or `Content-Disposition` in this slice.
- Unknown / unsafe URL must be a render error, surfaced by IgWeb as the existing JSON 500 render-error shape.
- Relative URLs, `http://`, and `https://` are allowed per existing `safe_url`.

## Boundary

Allowed:

- Edit `frame-ui/igniter-render-html`.
- Edit `server/igniter-web/examples/todo_view_app` and its tests.
- If strictly needed, update comments/docs around `HtmlNode` in `lang/igniter-compiler/src/igweb.rs`.
- Add proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No recursive `children : Collection[HtmlNode]`.
- No new layout (`list`, `nav`, etc.) in this card.
- No `.ig.html` or `.igv` work.
- No raw bytes / server protocol changes.
- No TodoApp Postgres / data projection integration.
- No file export/download implementation.
- No new language syntax.

## Required Proof Doc

Create:

`lab-docs/lang/lab-igniter-web-viewartifact-link-node-v0.md`

Include:

- exact node shape;
- renderer behavior and error behavior;
- safety story (`safe_url`, escaping, fail-closed);
- Todo authored proof route;
- test matrix;
- next cards.

## Acceptance

- [x] `link` node renders to `<a ...>` in `igniter-render-html`.
- [x] Href is validated via existing `safe_url`.
- [x] Link text is HTML-escaped.
- [x] Href attribute is escaped.
- [x] Relative URL renders.
- [x] `http` / `https` URL renders.
- [x] `javascript:` / `data:` / `mailto:` fails closed with `UnsafeUrl`.
- [x] Todo authored `.ig` helper `MakeLink` builds the node without request-body JSON.
- [x] Todo route proves path param flows into a safe relative href.
- [x] Existing unsupported-node behavior remains fail-closed.
- [x] No recursive descriptor field, raw HTML, template runtime, or server protocol change.
- [x] `igniter-render-html cargo test` green.
- [x] `server/igniter-web cargo test --test todo_view_app_tests` green.
- [x] `git diff --check` clean.

## Suggested Tests

Run:

```bash
cd frame-ui/igniter-render-html
cargo test

cd ../../server/igniter-web
cargo test --test todo_view_app_tests
```

If you touch prelude/lowering comments or examples broadly, also run the smallest relevant IgWeb test target.

## Reporting

Close with:

- files changed;
- exact node shape used (`text`/`action` vs any deviation);
- exact tests and counts;
- confirmation that dangerous schemes fail closed;
- whether this is enough for TodoApp navigation/pagination, or what remains;
- next recommended card.

