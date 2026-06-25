# LAB-IGNITER-WEB-VIEWARTIFACT-EVOLUTION-READINESS-P26

Status: CLOSED (schema readiness packet delivered 2026-06-25)
Route: standard / schema readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-web-viewartifact-evolution-readiness-p26-v0.md`.

**Verdict: mostly hold — ONE minimal pre-designed extension warranted now: a `link` node.** Almost every
TodoApp HTML need is met by current vocab + helpers (P24 Idiom A). The single genuine *schema* gap is
links/anchors (pagination "load more" + index↔detail nav), and its safety machinery `safe_url` is **already
built + tested but unused** (`render-html:76-102,317-341`).

**Inventory (verified):** layouts form/workbench; components label/button/text/select/checkbox; body is a
**flat** array (no nesting); only list = hardcoded workbench `data.leads`; no link node; flatness is by design
(`view_artifact.rs:1-8`). Tests green: render_html 11/11 (3 lib + 8 integration), todo_view_app 14/14.

**Need matrix collapses to two questions:** links (needed now) + per-item grouping (optional). Create form,
done/delete actions, detail, empty/error, flat list = current vocab + helpers.

**Minimal extension = `link` node:** reuse existing flat `HtmlNode` fields (`kind:"link"`, `text`=label,
`action`=href); renderer arm emits `<a href={safe_url(action)}>{escape(text)}</a>` — **zero new safety code**
(safe_url fail-closed already built). Unblocks pagination + navigation.

**No-recursion discipline (Meta-Architect red flag honored):** a richer per-item list, IF needed, = a bounded
`list` layout with a **distinct non-recursive `ListItem { title, body : Collection[HtmlNode] }`** (one level,
mirrors the existing 2-level workbench). **Never** add `children : Collection[HtmlNode]` to `HtmlNode` itself
(self-referential → recursive types in `.ig`, which has none). Hold tables/sections/raw-HTML/assets.

**XSS preserved:** link href via fail-closed `safe_url` (`javascript:`/`data:`→UnsafeUrl); unknown kind →
UnsupportedNode; no raw HTML ever. Future tests listed (§6).

**Next card:** `LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE` (link node + safe_url wiring + prelude field + tests);
bounded `list` layout = held follow-on on demonstrated need.

**Boundary honored.** No code/schema/renderer/Todo change; no canon. Docs only. `git diff --check` clean;
grep → `/tmp/igniter-viewartifact-evolution-grep.txt` (3231 hits).

## Goal

Evaluate whether the current `ViewArtifact` / `HtmlNode` vocabulary is enough for real TodoApp HTML and
near-term app UI, or whether the descriptor needs a small evolution before richer views.

This is schema/readiness only, not an implementation card.

## Current Authority

- `RenderView` and current IgWeb prelude records.
- `server/igniter-render-html` behavior.
- `todo_view_app` examples/tests.
- P18-P23 cards/docs: ViewArtifact authoring, helper contracts, list authoring, conditional lists,
  select options.
- TodoApp API routes and pending HTML needs.

## Questions To Answer

1. What nodes exist today and what do they render to?
   - labels/text;
   - buttons/actions;
   - inputs/checkbox/select/options;
   - layout/form/workbench.
2. What does TodoApp HTML need soon?
   - index/list;
   - detail;
   - create form;
   - done/delete actions;
   - error/empty/loading states;
   - pagination affordance;
   - navigation/links;
   - CSS classes/assets.
3. Which gaps are vocabulary gaps vs helper/convention gaps?
4. Which should be solved by app-local helper contracts first?
5. Which require renderer/schema changes?
6. What is the minimal v0 extension, if any?
7. How do we preserve XSS/escape and fail-closed behavior?

## Design Bias

- Prefer app-local helpers/conventions before changing the shared schema.
- Keep the schema small and closed.
- Unknown node kinds must fail closed.
- Do not add raw HTML.
- Do not make ViewArtifact a full browser framework.

## Boundary

Allowed:

- Write a readiness packet.
- Add tables and pseudo-ViewArtifact examples.
- Recommend a minimal schema-extension card if needed.

Closed:

- No code/schema changes.
- No renderer changes.
- No TodoApp HTML implementation.
- No canon claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-web-viewartifact-evolution-readiness-p26-v0.md`

Must include:

- current node inventory;
- TodoApp need matrix;
- helper-vs-schema decision;
- minimal extension recommendation or "hold";
- tests that a future implementation would need.

## Verification

Run:

```bash
rg -n "HtmlNode|ViewArtifact|kind|label|button|checkbox|select|options|unsupported_node|RenderView|escape" \
  server/igniter-web server/igniter-render-html lab-docs/lang .agents/work/cards/lang \
  > /tmp/igniter-viewartifact-evolution-grep.txt

cargo test --test todo_view_app_tests
cargo test -p igniter_render_html 2>/dev/null || true
git diff --check
```

Run relevant Cargo commands from the appropriate crate directories and report exactly what you ran.

## Acceptance

- [x] Packet exists.
- [x] It inventories current live node vocabulary.
- [x] It maps TodoApp needs to helper/schema gaps.
- [x] It recommends hold or a minimal schema extension.
- [x] It keeps raw HTML closed.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- current vocabulary verdict;
- recommended evolution/hold;
- next implementation card if any.
