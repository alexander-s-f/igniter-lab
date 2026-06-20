# LAB-IGNITER-RENDER-HTML-P3 - Pure ViewArtifact -> HTML projector

Status: CLOSED
Lane: standard
Type: implementation proof
Delegation code: OPUS-RENDER-HTML-P3
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

P2 established the right boundary: HTML rendering can happen outside the Igniter language as a server/plugin/projector concern. The first proof should not modify `igniter-server`, should not introduce raw responses, and should not invent `.ig.html`.

We already have a view model lineage: `.igv` / ViewArtifact JSON / frame-ui render hosts. P3 should prove the boring useful slice:

```text
ViewArtifact JSON -> deterministic escaped HTML string
```

This is a projector/render target, not a new language feature and not server authority.

## Goal

Implement a small proof-local HTML renderer for ViewArtifact-shaped JSON:

```rust
render_html(artifact_json: &str) -> Result<String, RenderHtmlError>
```

The renderer must be deterministic, fail closed on unsupported/unsafe nodes, escape text and attributes, and stay completely outside `igniter-server` and `igniter-web` runtime protocols.

## Verify First

Read live code before implementation. Do not rely on stale path memory after the repo reorganization.

- `lab-docs/lang/lab-igniter-web-render-middleware-readiness-p2-v0.md`
- `lab-docs/lang/lab-todoapp-view-manifest-p2-v0.md`
- `lab-docs/lang/lab-frame-viewartifact-p12-v0.md`
- `frame-ui/igniter-ui-kit/src/view_artifact.rs`
- `frame-ui/igniter-ui-kit/src/lib.rs`
- `frame-ui/igniter-ui-kit/src/composition.rs`
- `frame-ui/igniter-ui-kit/tests/view_artifact_tests.rs`
- `server/igniter-web/examples/todo_view_app/`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- current Cargo layout under `frame-ui/`

Confirm these live facts:

- ViewArtifact JSON is already parsed/rendered by frame-ui runtime surfaces.
- `todo_view_app` may currently use a smaller `View` / `RespondView` descriptor, not necessarily full ViewArtifact. Decide explicitly whether P3 targets full ViewArtifact first, Todo `View` first, or a minimal shared subset. Prefer full ViewArtifact if feasible.
- `igniter-server` currently remains JSON-response oriented; P3 must not open raw-response.

## Allowed Scope

- Create a new standalone proof crate if justified, likely under `frame-ui/igniter-render-html/`.
- Add narrow path dependency on the existing frame/view model crate if needed.
- Add tests/fixtures for deterministic rendering and safety behavior.
- Add proof doc:
  - `lab-docs/lang/lab-igniter-render-html-p3-v0.md`
- Close this card with a concise report and acceptance mapping.

## Closed Scope

- No `igniter-server` protocol changes.
- No `ResponseBody::Raw`, no raw HTTP bytes, no server middleware implementation.
- No `igniter-web` runner changes unless only a non-runtime documentation pointer is truly necessary.
- No browser, wasm, static file server, file watcher, or public listener.
- No `.ig.html` dialect.
- No DB/effect-host work.
- No canon/stable API claim.

## Design Requirements

Recommended public proof API:

```rust
pub fn render_html(artifact_json: &str) -> Result<String, RenderHtmlError>;
```

Optional, if useful:

```rust
pub fn render_html_fragment(artifact_json: &str) -> Result<String, RenderHtmlError>;
```

Error shape should be explicit and non-panicking:

- `InvalidArtifact`
- `UnsupportedNode`
- `UnsafeUrl`
- `Render`

Do not log raw artifact bodies in errors.

Prefer a tiny local HTML escape helper over adding a dependency unless a dependency is clearly worth the surface area. If a dependency is added, justify it in the proof doc.

## Acceptance

- [x] Renderer is deterministic: fixed fixture -> byte-identical output.
- [x] Text content is escaped: `<script>alert(1)</script>` never appears as a raw script node.
- [x] Attribute values are escaped.
- [x] URL attributes enforce an allowlist: relative, `http`, and `https` are allowed; `javascript:` fails closed with an explicit error.
- [x] Raw HTML nodes are not supported in v0; unsupported/raw node shapes fail closed.
- [x] Output form is documented: full HTML document (`render_html`) vs fragment (`render_html_fragment`), stable.
- [x] Renderer does not depend on `igniter-server`, does not require raw-response, and does not change web/server protocol.
- [x] Existing ViewArtifact tests still pass.
- [x] Todo view fixture: shape mismatch documented honestly (smaller `View{kind,title,items}` descriptor, not ViewArtifact — not a P3 input).
- [x] `git diff --check` is clean.

---

## Closing Report (2026-06-20)

**Files changed:** new standalone crate `frame-ui/igniter-render-html/` (`Cargo.toml`, `src/lib.rs`,
`tests/render_html_tests.rs`); proof doc `lab-docs/lang/lab-igniter-render-html-p3-v0.md`; this card. **No
other code touched.**

**Crate/location:** `frame-ui/igniter-render-html` — standalone, **deps: `serde_json` only** (no
igniter-server/web/frame/ui-kit dependency). Mirrors the canonical ViewArtifact schema
(`view_artifact.rs`) so it accepts exactly what the frame runtime does.

**API:** `render_html(json) -> Result<String, RenderHtmlError>` (full `<!DOCTYPE>` document) +
`render_html_fragment(json)` (body fragment) + `escape` / `safe_url` primitives;
`RenderHtmlError::{InvalidArtifact, UnsupportedNode, UnsafeUrl, Render}`.

**Safety:** structural ViewArtifact ⇒ no injection surface; text + attribute escaping always on (proven:
`<script>` escaped, attribute break-out blocked); `safe_url` allowlist (relative/http/https; `javascript:`/
`data:`/`mailto:` fail closed) — ready+tested for the first URL node (none in the vocab yet); unknown
nodes + bad artifacts fail closed; no raw-HTML node; errors carry kind/key, not the body.

**Tests:** `igniter-render-html` **11 green** (3 unit + 8 integration), renders the real
`lead_intake`(form) + `lead_review`(workbench) fixtures deterministically. ui-kit ViewArtifact **9 green**
(untouched). `cargo tree -e normal` on igniter-server shows **no** renderer/frame deps. `git diff --check`
clean.

**RAW-RESPONSE still NOT opened** — P3 produces an HTML *string*; no wire bytes, no server/web protocol
change.

**Next card:** `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*` (the `ResponseBody::Raw` seam) → then
`LAB-IGNITER-WEB-RENDER-DECISION-P*` (wire an explicit `Render { artifact, content_type }` decision
end-to-end to `text/html`). Optional faster proof: static HTML export to a file served externally (no
raw-response needed).

## Suggested Verification Commands

Adjust paths after verify-first if the live layout differs.

```bash
cd frame-ui/igniter-render-html && cargo test
cd frame-ui/igniter-ui-kit && cargo test --test view_artifact_tests
cd server/igniter-web && cargo test --test todo_view_app_tests
cd server/igniter-server && cargo tree -e normal | rg 'igniter_render_html|igniter_frame|igniter_ui_kit'
git diff --check
```

The `igniter-server` dependency check should produce no output. If P3 does not touch `server/`, this check is still useful evidence that the renderer stayed outside server normal deps.

## Deliverable

Close with:

- files changed
- chosen crate/location
- exact renderer API
- safety behavior
- test counts
- explicit statement that `RAW-RESPONSE` is still not opened
- next card recommendation

## Next

Likely follow-ups:

- `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*` - only after HTML projection is proven.
- `LAB-IGNITER-WEB-RENDER-DECISION-P*` - bridge IgWeb view decisions to the renderer, still without changing server core if possible.
- Static HTML export can happen before raw-response if it gives faster user-visible proof.
