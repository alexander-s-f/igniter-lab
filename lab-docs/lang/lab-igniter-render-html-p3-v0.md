# lab-igniter-render-html-p3-v0 — pure ViewArtifact → HTML projector

**Card:** `LAB-IGNITER-RENDER-HTML-P3` · **Delegation:** `OPUS-RENDER-HTML-P3`
**Status:** CLOSED (lab implementation proof) — a standalone `igniter_render_html` crate projecting
**ViewArtifact JSON → deterministic, escaped HTML**, the HTML analogue of the frame `RenderHost` targets.
**No `igniter-server`/`igniter-web` protocol change, no `RAW-RESPONSE`, no `.ig.html`, no browser/wasm,
no static serving, no DB, no canon claim.**
**Authority:** Lab tooling. Implements the P2 render-middleware recommendation (renderer-first, before the
raw-response seam). Mirrors the canonical ViewArtifact schema; depends only on `serde_json`.

## Verify-first (live facts confirmed)

- **ViewArtifact JSON shape** (`frame-ui/igniter-ui-kit/src/view_artifact.rs`): `{ "artifact":"view",
  "layout":"form"|"workbench", … }`. Form = `{ title?, body:[component…] }`; components
  `label{text}` / `text{id,label,required}` / `select{id,label,options[],required}` /
  `checkbox{id,label}` / `button{id,label,action}`. Workbench reads `data.leads[]` +
  `regions.main.fields[]` (richer region hints exist in the fixture but the canonical compiler ignores
  them).
- **Real fixtures** `frame-ui/igniter-ui-kit/web/lead_intake.view.json` (form) and `lead_review.view.json`
  (workbench) are the canonical artifacts — used as the proof inputs.
- **`todo_view_app` uses a SMALLER descriptor**, not full ViewArtifact: `todo_views.ig` returns a `View =
  { kind, title, items:[{key,label}] }` via `RespondView`. **Decision (per the card): P3 targets full
  ViewArtifact**; the Todo `View` shape is a *different, smaller* descriptor and is **not** a P3 target —
  honest mismatch documented below.
- **No Cargo workspace** under `frame-ui/` (standalone crates, path-deps) → P3 is a new standalone crate.
- **`igniter-server` stays JSON-response oriented** — P3 opens no raw response.

## What was built

`frame-ui/igniter-render-html/` — a standalone crate (`serde_json` only; **no** dependency on
`igniter-server`/`igniter-web`/`igniter-frame`/`igniter-ui-kit`). It mirrors the canonical ViewArtifact
schema so it accepts exactly what the frame runtime accepts, proven by rendering the same canonical
fixtures.

### API

```rust
pub fn render_html(artifact_json: &str)          -> Result<String, RenderHtmlError>; // full <!DOCTYPE> document
pub fn render_html_fragment(artifact_json: &str) -> Result<String, RenderHtmlError>; // body markup only
pub fn escape(s: &str) -> String;                                                    // HTML-escape primitive
pub fn safe_url(url: &str) -> Result<String, RenderHtmlError>;                        // URL allowlist primitive

pub enum RenderHtmlError { InvalidArtifact(String), UnsupportedNode(String), UnsafeUrl(String), Render(String) }
```

**Output form (chosen + stable):** `render_html` → a **full HTML document** (`<!DOCTYPE html>` … `<title>`
from the artifact title/screen … `<body>`); `render_html_fragment` → the **body fragment** only. Forms
render as `<form class="ig-form">` with escaped labels/inputs/selects/checkboxes and a submit `<button
data-action>`; workbench renders the `data.leads` as a `<ul>` plus the `regions.main.fields` as a form.

### Safety behavior

- **Structural input ⇒ no injection surface.** The artifact is a closed node vocabulary, never a template
  string, so user data only ever reaches **escaped leaf positions** — it can never become tags/structure.
- **Text + attribute escaping** (always on): `&`,`<`,`>`,`"`,`'` → entities; attributes are always
  double-quoted, so the same escape is safe in both contexts. Proven: `<script>alert(1)</script>` in a
  label renders as `&lt;script&gt;…` and **never** as a raw `<script>`; an `id` of `x" onload="evil` is
  emitted as `name="x&quot; onload=&quot;evil"` and **cannot** break out of the attribute.
- **URL allowlist** (`safe_url`): relative / `http` / `https` pass; any other explicit scheme
  (`javascript:`, `data:`, `mailto:`, …) **fails closed** with `UnsafeUrl`. The v0 ViewArtifact vocabulary
  has **no URL-bearing node**, so no URL is emitted today; `safe_url` is implemented + unit-tested and is
  the required gate for the first `link`/`image` node added later.
- **Fail closed:** unknown component/field `kind` → `UnsupportedNode`; non-`view` artifact / unknown
  layout / invalid JSON / missing required field → `InvalidArtifact`. **No raw-HTML node** in v0. Errors
  carry the offending *kind/key*, never the raw artifact body.

### Determinism

The walker reads specific JSON keys (never iterates a map) and preserves array order, so a fixed artifact
yields **byte-identical** HTML. Proven by rendering each fixture twice and asserting equality.

## Tests & commands — exact counts

```text
$ cd frame-ui/igniter-render-html && cargo test
  unit (src/lib.rs):  3 passed   (escape coverage; safe_url allow http/https/relative; safe_url reject javascript/data/mailto)
  integration:        8 passed   (form fixture deterministic + escaped; workbench fixture leads+fields;
                                  fragment has no doc wrapper; <script> escaped; attribute break-out blocked;
                                  unknown kind → UnsupportedNode; non-view/bad-json/bad-layout → InvalidArtifact;
                                  empty form body rejected)
$ cd frame-ui/igniter-ui-kit && cargo test --test view_artifact_tests   → 9 passed (existing, untouched)
$ cd server/igniter-server && cargo tree -e normal | rg 'igniter_render_html|igniter_frame|igniter_ui_kit'
  → (no output) — the renderer stayed entirely outside the server normal deps
$ git diff --check   → clean
```

## Acceptance — mapping

- [x] **Deterministic:** fixed fixture → byte-identical output (`renders_canonical_form_fixture_deterministically`).
- [x] **Text escaped:** `<script>` never a raw node (`text_content_is_escaped_never_a_raw_script`).
- [x] **Attribute values escaped** (`attribute_values_are_escaped`).
- [x] **URL allowlist:** relative/http/https allowed, `javascript:` → explicit `UnsafeUrl` error
      (`safe_url_*` unit tests). No URL node in the vocab yet — gate provided + tested for the first one.
- [x] **Raw HTML unsupported; unknown nodes fail closed** (`unknown_component_kind_fails_closed`, no raw-HTML node).
- [x] **Output form documented** — full document (`render_html`) vs fragment (`render_html_fragment`), stable.
- [x] **No `igniter-server` dependency, no raw-response, no web/server protocol change** (`cargo tree` clean).
- [x] **Existing ViewArtifact tests still pass** (ui-kit 9 green).
- [x] **Todo view fixture:** documented shape mismatch — `todo_views.ig` uses a smaller `View {kind,title,
      items}` descriptor (not ViewArtifact), so it is **not** a P3 input; a future card may add a `View`→HTML
      path or migrate Todo to ViewArtifact.
- [x] **`git diff --check` clean.**

## Honest limitations

- Targets the **canonical ViewArtifact** form/workbench subset (the kit compiler's read surface). Richer
  workbench region hints (`sidebar`/`inspector`/`for_each`) are ignored — static HTML renders the data
  (leads + main fields), not the interactive region wiring.
- The Todo `View {kind,title,items}` descriptor is a separate shape, intentionally out of scope.
- No URL-bearing node exists yet; `safe_url` is ready but unexercised by the render path (unit-tested directly).

## RAW-RESPONSE is still NOT opened

P3 produces an HTML **string**; it does **not** put bytes on the wire. `igniter-server`/`igniter-web`
remain JSON-response oriented and unchanged. Emitting this HTML over HTTP with `text/html` is the **next**,
separate slice.

## Next card recommendation

1. **`LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*`** — the `ResponseBody { Json(Value) | Raw { bytes,
   content_type } }` seam + encoder branch + wire tests (verbatim bytes; content-type preserved; middleware
   still applies). The single core change every server-emitted HTML/binary path depends on.
2. then **`LAB-IGNITER-WEB-RENDER-DECISION-P*`** — wire an explicit IgWeb `Render { artifact, content_type }`
   decision through `igniter-web` → `igniter_render_html` → a `Raw` response, end-to-end loopback `text/html`.
3. (optional, faster user-visible proof) **static HTML export** — write `render_html` output to a file an
   external static server serves, needing no raw-response at all.

---

*Lab implementation proof. Compiled 2026-06-20; `igniter-render-html` 11 tests green (3 unit + 8
integration), renders the canonical `lead_intake`/`lead_review` fixtures deterministically; ui-kit 9 green;
server normal deps renderer-free. No server/web protocol, raw-response, `.ig.html`, or canon change.*
