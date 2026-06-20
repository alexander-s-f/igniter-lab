# LAB-TODOAPP-VIEW-HTML-P17 - Todo view HTML over IgWeb Render

Status: CLOSED
Lane: standard
Type: implementation-pressure
Delegation code: OPUS-TODOAPP-VIEW-HTML-P17
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

Two app/view slices are now closed:

- `LAB-TODOAPP-VIEW-MANIFEST-P2` proves a Todo view app that returns clean JSON view descriptors through
  `RespondView`.
- `LAB-IGNITER-WEB-RENDER-DECISION-P16` proves a generic `Render { status, artifact_json }` decision:
  ViewArtifact JSON string -> `igniter-render-html` -> `ServerResponse::raw(..., "text/html; charset=utf-8")`.

P17 applies that seam to the Todo view pressure case. The goal is not a final HTML authoring model; it is
to make a Todo-facing IgWeb app return **real HTML bytes** over loopback without putting render logic into
`igniter-server`.

Important live constraint from P16: `.ig` string literals cannot contain escaped quotes. Do **not** fake a
ViewArtifact JSON literal inside `.ig`.

## Goal

Make the Todo view app prove an HTML route using the P16 `Render` decision:

```text
authored Todo IgWeb app
  -> route returns Render { artifact_json }
  -> igniter-web projects ViewArtifact JSON to escaped HTML
  -> raw text/html response on the wire
```

Keep the existing JSON-first `RespondView` routes green and unchanged unless a tiny compatibility adjustment
is unavoidable.

## Verify First

Read live code before editing:

- `server/igniter-web/examples/todo_view_app/`
  - `igweb.toml`
  - `routes.igweb`
  - `todo_views.ig`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `server/igniter-web/examples/render_html_app/`
- `server/igniter-web/tests/render_html_app_tests.rs`
- `server/igniter-web/src/lib.rs`
  - `map_decision`
  - `testkit::roundtrip`
  - `testkit::roundtrip_raw`
- `lang/igniter-compiler/src/igweb.rs`
  - `IgWebPrelude`
  - `Decision.Render`
- `frame-ui/igniter-render-html/src/lib.rs`
- `lab-docs/lang/lab-todoapp-view-manifest-p2-v0.md`
- `lab-docs/lang/lab-igniter-web-render-decision-p16-v0.md`

Confirm or correct:

- `todo_view_app` currently returns a small `View { kind, title, items }` descriptor through `RespondView`;
  this is not the full ViewArtifact schema accepted by `igniter-render-html`.
- `Render` currently expects `artifact_json : String`.
- Inline full JSON in `.ig` is impossible because the lexer has no string escapes.
- `roundtrip_raw` can inspect `text/html` bodies.

## Recommended Minimal Shape

Prefer the smallest honest Todo-facing proof:

1. Keep `todo_view_app` JSON routes:
   - `GET /`
   - `GET /todos`
   - `GET /todos/:todo_id`
   - `/api/health`
2. Add one HTML render route to the same app, or create a clearly named sibling app if that is cleaner:
   - example: `POST /html` or `POST /todos/html-preview`
   - handler returns `Render { status: 200, artifact_json: req.body }`
3. The test sends a Todo-shaped full ViewArtifact JSON document in the request body.
4. The response must be real `text/html` bytes, not JSON.

Why request body is acceptable for P17:

- P16 already proved the generic delivery seam with request-sourced ViewArtifact JSON.
- P17 adds TodoApp pressure and keeps the app runner path (`igweb.toml` + authored `.igweb`/`.ig`) honest.
- It does **not** pretend that Todo can yet author a full ViewArtifact in `.ig`.

If, during verify-first, Opus finds a genuinely small typed ViewArtifact authoring path in `.ig`, it may
choose that instead. But do not widen the IgWeb prelude with a large schema in this card, and do not build
manual JSON by string concatenation.

## Implementation Guidance

Likely files:

- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- optional new proof doc under `lab-docs/lang/`

Possible handler:

```ig
pure contract TodoHtmlPreview {
  input req : Request
  compute d : Decision = Render { status: 200, artifact_json: req.body }
  output d : Decision
}
```

The test should send a full ViewArtifact JSON body with Todo content, for example:

```json
{
  "artifact": "view",
  "layout": "form",
  "title": "Todos",
  "body": [
    { "kind": "label", "text": "Buy milk <script>" },
    { "kind": "label", "text": "Write the spec" },
    { "kind": "button", "id": "done", "label": "Done", "action": "submit" }
  ]
}
```

Assert that `<script>` is escaped in the returned HTML.

## Closed Scope

- No `.ig.html`.
- No template language.
- No raw HTML strings authored in `.ig`.
- No manual JSON-string construction in `.ig`.
- No large typed ViewArtifact schema in the IgWeb prelude unless it is proven tiny and justified.
- No `igniter-server` renderer/view dependency.
- No static asset serving.
- No CSS/JS bundling.
- No DB/live effect-host work.
- No file export / send-file / streaming.
- No source-map or diagnostics expansion.
- No canon/stable API claim.

## Required Tests / Acceptance

- [x] Existing `todo_view_app` JSON tests still pass: index/detail/API/404/405.
- [x] New Todo HTML route builds through `igweb.toml` with no authored Rust.
- [x] New route returns `Content-Type: text/html; charset=utf-8`.
- [x] New route wire body starts with `<!DOCTYPE html>` and is not JSON quoted/wrapped.
- [x] Returned HTML contains Todo content from the supplied ViewArtifact.
- [x] Malicious Todo text such as `<script>` is escaped; no raw script tag appears.
- [x] Invalid artifact body returns JSON 500, not HTML and not a panic.
- [x] `render_html_app_tests` remain green.
- [x] `igniter-render-html` tests remain green.
- [x] `igniter-server` normal dependency tree still has no `igniter_render_html`, `igniter_frame`,
  `igniter_ui_kit`, export, xlsx, or pdf crate.
- [x] `igniter-web` normal dependency tree intentionally includes `igniter_render_html`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Smallest honest diff (todo_view_app + its test only; no Rust, no prelude change):**
`examples/todo_view_app/routes.igweb` (+`POST /todos/html-preview`), `todo_views.ig` (+`TodoHtmlPreview`
contract returning `Render { artifact_json: req.body }`), `tests/todo_view_app_tests.rs` (+2 tests + a
Todo ViewArtifact const). Proof doc: `lab-docs/lang/lab-todoapp-view-html-p17-v0.md`.

**End-to-end proven:** `POST /todos/html-preview` with a Todo ViewArtifact body → `Render` →
`igniter_render_html` → `ServerResponse::raw(…, text/html)` → verbatim `<!DOCTYPE html>…` with Todo content
**escaped** (`Buy milk &lt;script&gt;`, no raw `<script>`). Invalid body → JSON 500 (`render failed`).
JSON-first `RespondView` routes unchanged (6 existing tests green).

**Route-priority pressure (live P18 demonstration):** `/todos/html-preview` collides with
`/todos/:todo_id` (`^/todos/([^/]+)$`). Authoring the static route AFTER the param route shadowed it
(POST → GET-only group → 405); authoring it BEFORE makes it reachable while `/todos/42` still hits the
detail view. IgWeb matches in authored order and does not auto-rank static over param — exactly the P18
policy, captured as a test.

**Reported facts:** Todo HTML route used **request-sourced** ViewArtifact JSON (not new typed authoring),
consistent with the `.ig` no-string-escape constraint; `RespondView` stayed JSON; `igniter-server`
renderer-free, `igniter-web` intentionally carries `igniter_render_html`.

**Proof — all green:** todo_view_app 8 (6 JSON + 2 HTML); render_html_app 3; igniter-render-html 11;
igniter-server green + renderer-free; `git diff --check` clean.

**Next:** `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18` — real ViewArtifact authoring in Igniter **without**
inline JSON strings (the gap P17 deliberately left open). Then assets/static-shell + file-export readiness.

## Suggested Verification Commands

```bash
cd server/igniter-web && cargo test --test todo_view_app_tests
cd server/igniter-web && cargo test --test render_html_app_tests
cd server/igniter-web && cargo test
cd frame-ui/igniter-render-html && cargo test
cd server/igniter-server && cargo test
cd server/igniter-server && cargo tree -e normal
cd server/igniter-web && cargo tree -e normal
git diff --check
```

Explicitly report:

- exact test counts;
- whether the Todo HTML route used request-sourced ViewArtifact JSON or a new typed authoring path;
- whether existing `RespondView` routes stayed JSON;
- dependency-boundary result for `igniter-server` vs `igniter-web`.

## Deliverables

- Todo-facing HTML route proof (`todo_view_app` or a clearly named sibling fixture);
- loopback tests proving real HTML bytes + escaping + failure mode;
- proof doc `lab-docs/lang/lab-todoapp-view-html-p17-v0.md`;
- closing report in this card.

## Next

Likely follow-up after P17:

- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18` — choose a real authoring form for full ViewArtifact in
  Igniter without inline JSON strings.
- Later: assets/static shell and file-export readiness.
