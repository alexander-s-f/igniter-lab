# LAB-IGNITER-WEB-RENDER-DECISION-P16 - IgWeb Render decision to raw HTML

Status: CLOSED
Lane: standard
Type: implementation
Delegation code: OPUS-IGWEB-RENDER-DECISION-P16
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

Two prerequisites are now closed:

- `LAB-IGNITER-RENDER-HTML-P3` — `igniter-render-html` proves
  `ViewArtifact JSON -> deterministic escaped HTML string`.
- `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P15` — `igniter-server` can send
  `ResponseBody::Raw { bytes, content_type }` verbatim.

P16 wires those together in `igniter-web`:

```text
.ig/.igweb handler returns Render decision
  -> igniter-web map_decision
  -> igniter_render_html::render_html(...)
  -> ServerResponse::raw(..., "text/html; charset=utf-8")
  -> loopback response body is real HTML bytes
```

This is still lab-only. It is not `.ig.html`, not a template engine, not file serving, and not a server-core
render dependency.

## Goal

Implement the smallest end-to-end HTML render decision for IgWeb:

- app/handler can return a `Render`-style decision carrying a ViewArtifact JSON descriptor;
- `igniter-web` invokes `igniter-render-html`;
- the response goes out through the P15 raw response seam as `text/html`;
- existing `Respond` and `RespondView` JSON behavior remains unchanged.

## Verify First

Read live code before editing:

- `server/igniter-web/Cargo.toml`
- `server/igniter-web/src/lib.rs`
  - `map_decision`
  - `variant_of`
  - `IgWebServerApp::call`
  - `runner`
- `lang/igniter-compiler/src/igweb.rs`
  - shared prelude / `variant Decision`
  - current `View` / `RespondView` shape
- `server/igniter-web/examples/todo_view_app/`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
- `server/igniter-server/src/protocol.rs`
- `server/igniter-server/src/host.rs`
- `lab-docs/lang/lab-igniter-render-html-p3-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-raw-response-p15-v0.md`
- `lab-docs/lang/lab-todoapp-view-manifest-p2-v0.md`

Confirm or correct:

- `igniter-server` already has `ServerResponse::raw`; do not change server-core unless verify-first proves
  a tiny compatibility fix is required.
- `igniter-web` currently maps `RespondView` to JSON, and that must remain JSON.
- `todo_view_app` uses a smaller `View { kind, title, items }` descriptor, not the full ViewArtifact schema.
- `igniter-render-html` accepts full ViewArtifact JSON (`artifact:"view", layout:"form"|"workbench"`).
- `.ig` string literals currently do **not** support escaped quotes: `lexer.rs::read_string` reads until
  the first `"`. Therefore a JSON object cannot be authored inline as a normal `.ig` string literal.

## Recommended Minimal Shape

Use a bridge-proof decision first:

```ig
variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : String, idempotency_key : String }
  RespondView  { status : Integer, view : View }
  Render       { status : Integer, artifact_json : String }
}
```

Why `artifact_json : String` for P16?

- It proves the real transport/projector seam without opening a large typed ViewArtifact authoring surface.
- `igniter-render-html` still validates the structure; bad JSON or unsupported nodes fail closed.
- It avoids prematurely baking full ViewArtifact types into the IgWeb prelude.
- It must **not** rely on inline JSON inside `.ig` source, because `.ig` string literals cannot encode
  JSON quotes today. For the proof, use request-provided JSON text (for example `req.body`) or another
  host/test-provided string value.

If verify-first shows a clean, tiny typed ViewArtifact record is already easy, Opus may choose that instead,
but must justify why the added surface is still bounded. Do not block P16 on ideal authoring DX.

## Implementation Guidance

In `server/igniter-web`:

- Add dependency:

```toml
igniter_render_html = { path = "../../frame-ui/igniter-render-html" }
```

- Extend `map_decision` to recognize `Render`.
- On success:

```rust
let html = igniter_render_html::render_html(&artifact_json)?;
ServerResponse::raw(status, html.into_bytes(), "text/html; charset=utf-8")
```

- On render failure:
  - return a JSON error response, likely 500;
  - include only error kind/message, never the raw artifact body;
  - keep `content-type: application/json`.

In `lang/igniter-compiler/src/igweb.rs`:

- Add the `Render` variant to the shared IgWeb prelude.
- Do not alter route lowering, resource/scope/via/context behavior.

Add or extend an example app, preferably a new small fixture:

```text
server/igniter-web/examples/render_html_app/
```

The app should return a minimal full ViewArtifact form JSON string through `Render`, not raw HTML. Because
`.ig` cannot inline JSON strings with escaped quotes, the fixture should source `artifact_json` from the
request body (or another external string passed into the app), not from an inline `.ig` literal.

## Closed Scope

- No `igniter-server` renderer dependency.
- No `igniter-server` route/domain/view code.
- No `.ig.html`.
- No template language.
- No raw HTML string from `.ig` as the rendered body.
- No file serving.
- No `send_file(path)`.
- No CSV/XLSX/PDF/export.
- No streaming/chunked response.
- No DB/effect-host work.
- No public listener.
- No canon/stable API claim.

## Required Tests / Acceptance

- [x] Existing `Respond` still returns JSON `{"body": ...}`.
- [x] Existing `RespondView` still returns JSON body root and keeps `todo_view_app` tests green.
- [x] `Render` returns `Content-Type: text/html; charset=utf-8`.
- [x] `Render` wire body starts with `<!DOCTYPE html>` and is not JSON quoted/wrapped.
- [x] Rendered HTML contains expected escaped ViewArtifact content.
- [x] Malicious content in artifact (`<script>`) is escaped by `igniter-render-html`.
- [x] Render fixture does **not** depend on inline JSON string literals in `.ig`; the artifact JSON comes
  from request/test input or another external string source.
- [x] Invalid artifact JSON returns JSON error, not panic and not raw artifact leak.
- [x] `igniter-server` normal dependency tree still has no `igniter_render_html`, `igniter_frame`,
  `igniter_ui_kit`, or export crates.
- [x] `igniter-web` normal dependency tree includes `igniter_render_html` intentionally.
- [x] `frame-ui/igniter-render-html` tests still pass.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Files changed (igniter-web + IgWeb prelude):** `lang/igniter-compiler/src/igweb.rs` (prelude
`variant Decision` += `Render { status: Integer, artifact_json: String }`); `server/igniter-web/Cargo.toml`
(+`igniter_render_html` path dep); `server/igniter-web/src/lib.rs` (`map_decision` `Render` arm +
`render_error_kind` + `testkit::roundtrip_raw`); new `examples/render_html_app/` +
`tests/render_html_app_tests.rs`. Proof doc: `lab-docs/lang/lab-igniter-web-render-decision-p16-v0.md`. No
`igniter-server` change. Cargo.lock updated by the new dep.

**End-to-end proven:** `Render { artifact_json }` → `igniter_render_html::render_html` →
`ServerResponse::raw(…, "text/html; charset=utf-8")` → wire body verbatim `<!DOCTYPE html>…`, ViewArtifact
content **escaped** (`Hi &lt;there&gt; &amp; &lt;script&gt;`, no raw `<script>`). Invalid artifact → JSON
500 (`"kind":"invalid_artifact"`), no panic, no artifact leak. `Respond`/`RespondView` stay JSON.

**Decisive verify-first delta:** `.ig` string literals **cannot contain `"`** (`lexer.rs:508` `read_string`
has no escapes) — an inline JSON literal is impossible in `.ig` (it produced a wall of `OOF-P0`). The proof
sources the ViewArtifact JSON from **`req.body`** (handed to `.ig` as a String). HTML **delivery** from a
structured ViewArtifact is proven; ViewArtifact **authoring in `.ig`** is a named follow-up. (The card's
acceptance was updated to require exactly this — fixture not dependent on inline `.ig` JSON literals.)

**Proof — all green:** igniter-web +3 render tests (todo_view RespondView still JSON); render-html 11;
igweb lowering 11 (prelude arm compiles); `igniter-server` tree renderer-free; `igniter-web` tree
intentionally carries `igniter_render_html`; `git diff --check` clean.

**Next:** `LAB-TODOAPP-VIEW-HTML-P17` · `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P*` (typed authoring, given
the no-string-escape constraint) · `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*`.

## Suggested Verification Commands

```bash
cd frame-ui/igniter-render-html && cargo test
cd server/igniter-web && cargo test
cd server/igniter-server && cargo test
cd server/igniter-server && cargo tree -e normal
cd server/igniter-web && cargo tree -e normal
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
git diff --check
```

Explicitly report:

- `igniter-server` dependency tree has no renderer/frame/export deps;
- `igniter-web` dependency tree intentionally includes `igniter_render_html`;
- exact test counts.

## Deliverables

- code changes in `igniter-web` and the IgWeb prelude only, unless verify-first requires a tiny compatibility
  touch elsewhere;
- a render-html IgWeb fixture/example and loopback test;
- proof doc:
  - `lab-docs/lang/lab-igniter-web-render-decision-p16-v0.md`
- closing report in this card.

## Notes

This card should prove **delivery of HTML generated from structured ViewArtifact**, not final authoring DX.

Do not solve all view modeling here. The known mismatch remains:

- `RespondView` uses a small Todo `View {kind,title,items}` descriptor and stays JSON-first.
- `Render` uses full ViewArtifact JSON and produces HTML.
- P16 intentionally works around the current string-literal limitation by accepting artifact JSON as an
  external string; this is a bridge proof, not final authoring DX.

A later card may migrate Todo views to full ViewArtifact or introduce typed ViewArtifact authoring in IgWeb.

Related follow-up, but not a P16 blocker:

- `LAB-IGNITER-STRING-ESCAPES-P*` or equivalent — decide whether `.ig` string literals should support
  escapes such as `\"`, `\\`, `\n`, or whether large structured literals should be expressed another way.

## Next

Likely follow-ups:

- `LAB-TODOAPP-VIEW-HTML-P17` - make Todo view app render real HTML via P16.
- `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P*` - typed ViewArtifact authoring surface if `artifact_json`
  is too clunky.
- `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*` - descriptor-to-bytes export family.
