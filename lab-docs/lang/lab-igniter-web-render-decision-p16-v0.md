# lab-igniter-web-render-decision-p16-v0 — IgWeb `Render` decision → raw HTML

**Card:** `LAB-IGNITER-WEB-RENDER-DECISION-P16` · **Delegation:** `OPUS-IGWEB-RENDER-DECISION-P16`
**Status:** CLOSED (lab implementation) — an IgWeb `Render` decision projects a ViewArtifact JSON string
through the P3 renderer (`igniter-render-html`) and ships it as **verbatim `text/html` bytes** via the P15
raw seam, end-to-end over loopback. **Not `.ig.html`, not a template engine, not file serving, not a
server-core render dependency.**
**Authority:** Lab tooling. Wires P3 (`ViewArtifact → HTML`) + P15 (`ResponseBody::Raw`) into `igniter-web`.
The renderer dependency lives in `igniter-web`; `igniter-server` core stays renderer/view-free.

## Verify-first (live facts + one decisive delta)

- `igniter-server` already has `ServerResponse::raw(status, bytes, content_type)` (P15) — server-core
  unchanged here.
- `igniter-web` `map_decision` maps `Respond`/`RespondView`/`InvokeEffect` to JSON via `ServerResponse::json`;
  `RespondView` stays JSON.
- The IgWeb prelude (`igweb.rs PRELUDE_SOURCE`) `variant Decision` had `Respond`/`InvokeEffect`/`RespondView`.
- `igniter-render-html::render_html(&str) -> Result<String, RenderHtmlError>` accepts full ViewArtifact
  JSON (`artifact:"view", layout:"form"|"workbench"`), escaping + failing closed.
- **DELTA (decisive): `.ig` string literals cannot contain `"`.** The lexer's `read_string`
  (`lexer.rs:508`) reads until the next `"` with **no escape handling at all** — so a JSON literal
  (`"{\"artifact\":…}"`) is impossible to author inline in `.ig`. An early attempt to embed the artifact in
  the handler produced a wall of `OOF-P0` parse errors. **Consequence:** the proof sources the ViewArtifact
  JSON from **`req.body`** (which `IgWebServerApp::call` already hands `.ig` as a `String`), not an inline
  literal. Authoring ViewArtifact *in `.ig`* (typed records or a future authoring surface) is a separate,
  named follow-up — this card proves **delivery of HTML from a structured ViewArtifact**, not authoring DX.

## What changed (igniter-web + the IgWeb prelude only)

1. **Prelude** (`lang/igniter-compiler/src/igweb.rs`): added one arm —
   `Render { status : Integer, artifact_json : String }` — to `variant Decision`. No route-lowering /
   scope / resource / via change.
2. **`igniter-web/Cargo.toml`:** added `igniter_render_html = { path = "../../frame-ui/igniter-render-html" }`
   (the renderer weight lives here, not in server core).
3. **`map_decision`** (`igniter-web/src/lib.rs`): a `Render` arm —
   ```rust
   "Render" => match igniter_render_html::render_html(&get_str("artifact_json")) {
       Ok(html)  => Respond { response: ServerResponse::raw(status, html.into_bytes(), "text/html; charset=utf-8") },
       Err(e)    => Respond { response: ServerResponse::json(500, { "error":"render failed", "kind": render_error_kind(&e), "message": e.to_string() }) },
   }
   ```
   plus `render_error_kind` (stable kind string; neither it nor the message leaks the artifact body).
4. **`testkit::roundtrip_raw`** — returns the RAW response text so non-JSON (HTML) bodies are inspectable.
5. **Example app** `server/igniter-web/examples/render_html_app/` (`igweb.toml` + `routes.igweb` +
   `render_handlers.ig`): `POST /render` returns `Render { status: 200, artifact_json: req.body }`;
   `GET /data` returns a plain `Respond` (JSON contrast).

## End-to-end shape (proven)

```text
client POST /render  body = {"artifact":"view","layout":"form",…}
   → IgWebServerApp hands req.body to `.ig` as a String
   → handler returns  Render { status: 200, artifact_json: <that string> }
   → igniter-web map_decision → igniter_render_html::render_html(...)   (escapes, fails closed)
   → ServerResponse::raw(200, html_bytes, "text/html; charset=utf-8")   (P15 raw seam)
   → wire body = verbatim <!DOCTYPE html>… (NOT JSON-quoted, NOT {"body":…})
```

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test
  render_html_app_tests        → 3 passed  (verbatim text/html; invalid→JSON 500; plain Respond stays JSON)
  todo_view_app_tests          → unchanged green (RespondView stays JSON)
  (+ builder / example / runner / igweb-adapter suites all green)
$ cd frame-ui/igniter-render-html && cargo test                         → 11 passed (P3, untouched)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests    → 11 passed (prelude Render arm compiles; lowering unaffected)
$ cd server/igniter-web && cargo tree -e normal | rg render_html        → igniter_render_html present (intentional)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit'  → (none) renderer-free
$ git diff --check                                                      → clean
```

## Acceptance — mapping

- [x] `Respond` still returns JSON `{"body":…}` (`plain_respond_route_stays_json`; existing suites green).
- [x] `RespondView` still returns JSON body root; `todo_view_app` tests green.
- [x] `Render` returns `Content-Type: text/html; charset=utf-8`.
- [x] `Render` wire body starts with `<!DOCTYPE html>`, not JSON-quoted/wrapped.
- [x] Rendered HTML contains expected escaped ViewArtifact content (`<title>Hello</title>`,
      `<input … name="name" required>`, `data-action="submit"`).
- [x] Malicious `<script>`/`<there>`/`&` in the artifact is **escaped**
      (`Hi &lt;there&gt; &amp; &lt;script&gt;`; no raw `<script>`).
- [x] Invalid artifact JSON → JSON 500 (`"error":"render failed"`, `"kind":"invalid_artifact"`), no panic,
      no raw-artifact leak.
- [x] `igniter-server` normal deps gain no renderer/frame/ui-kit/export crate.
- [x] `igniter-web` normal deps intentionally include `igniter_render_html`.
- [x] `igniter-render-html` tests still pass.
- [x] `git diff --check` clean.

## Closed scope (honored)

No `igniter-server` renderer dependency / route / view code; no `.ig.html`; no template language; no raw
HTML string authored in `.ig` as the body (the handler hands a ViewArtifact JSON string, the renderer
produces the HTML); no file serving; no `send_file`; no CSV/XLSX/PDF; no streaming; no DB/effect-host work;
no public listener; no canon claim.

## Known mismatch (carried, per the card)

- `RespondView` uses the small Todo `View {kind,title,items}` descriptor and stays JSON-first.
- `Render` uses full ViewArtifact JSON and produces HTML.
- Authoring ViewArtifact *in `.ig`* is blocked by the no-string-escape lexer fact; for now the descriptor
  arrives as data (`req.body`). A later card adds typed ViewArtifact authoring or migrates Todo views.

## Next

1. **`LAB-TODOAPP-VIEW-HTML-P17`** — make the Todo view app render real HTML via this `Render` seam.
2. **`LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P*`** — typed ViewArtifact authoring in IgWeb (so the
   descriptor need not arrive as a raw JSON string), given the `.ig` no-string-escape constraint.
3. **`LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*`** — the descriptor→bytes export family (ReportDescriptor →
   xlsx/csv/pdf) over the same `Render`/raw pattern.

---

*Lab implementation. Compiled 2026-06-20; igniter-web green (+3 render-decision tests), render-html 11
green, igweb lowering 11 green, igniter-server renderer-free, igniter-web intentionally carries the
renderer, `git diff --check` clean. HTML now generated from a structured ViewArtifact and delivered over
the wire as text/html — no `.ig.html`, no server-core render dependency.*
