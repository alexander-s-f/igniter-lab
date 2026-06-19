# lab-igniter-web-render-middleware-readiness-p2-v0 — host-side ViewArtifact→HTML render seam

**Card:** `LAB-IGNITER-WEB-RENDER-MIDDLEWARE-READINESS-P2` · **Delegation:** `OPUS-IGWEB-RENDER-MIDDLEWARE-P2`
**Status:** READINESS / DESIGN (v0) — where/how to project app-owned **ViewArtifact JSON → HTML bytes**
outside the Igniter language, before inventing `.ig.html` or putting view/runtime knowledge into
`igniter-server` core. **No code, no `RAW-RESPONSE`, no renderer, no `.ig.html`, no static serving, no
canon claim.**
**Authority:** Lab readiness. Grounded in live `protocol.rs`/`host.rs`/`middleware.rs`,
`igniter-web/src/lib.rs`, the `frame-ui/` ViewArtifact+RenderHost stack, and P0/P11/P1.

---

## 1. Current live facts (verified)

| Fact | Evidence |
|---|---|
| `ServerResponse.body: serde_json::Value`; the wire encoder **always JSON-serializes** it | `host.rs encode_response`: `serde_json::to_vec(&resp.body)` → **HTML cannot be sent verbatim today** |
| headers (incl. `content-type`) are written to the wire, but the body bytes are still JSON | `host.rs` header loop + `to_vec` |
| IgWeb narrows further: prelude `Respond { status, body:String }`; `map_decision` double-wraps `{"body": <str>}` + forces `application/json` | `igweb.rs PRELUDE_SOURCE`, `igniter-web/src/lib.rs:164-170` |
| **middleware wrappers are `ServerApp` decorators** (`call(req) -> ServerDecision`) — they touch **request + decision, NOT wire bytes**; there is **no response-body encoder hook** in the middleware layer | `middleware.rs` `TraceApp`/`AuthTokenApp`/`BodyLimitApp` all `impl ServerApp` |
| **ViewArtifact JSON is a proven, app-owned, machine-free representation** with a `RenderHost` trait and multiple impls + `from_artifact(json)` | `frame-ui/igniter-frame`, `igniter-ui-kit`, `igniter-gui`, `igniter-3d`, `igniter-console` (`impl RenderHost`, `from_artifact`) |

**Load-bearing consequence:** a ViewArtifact→HTML renderer that produces a `ServerResponse` with a JSON body
would *still* be JSON-serialized by `encode_response`. So **HTML output requires a raw-byte seam at the
encoder level (host.rs), not at the middleware level** — middleware can't reach the wire bytes. The
"rendering decision" (app says *render this*) and the "wire bytes" (verbatim HTML emitted by the encoder)
are two different things (Q3).

## 2. The proposed seam, end to end

```text
IgWeb app (.ig handler) returns an EXPLICIT Render decision carrying a ViewArtifact + content-type
   │   (the app opts in per response; arbitrary JSON is NEVER auto-rendered)
   ▼
igniter-web render extension: ViewArtifact JSON --[igniter-render-html projector]--> escaped HTML bytes
   │   (reuses the frame RenderHost discipline; machine-free; pure function)
   ▼
RAW-RESPONSE seam: ServerResponse carries Raw { bytes, content_type } instead of a JSON Value
   ▼
host.rs encoder writes the bytes VERBATIM with text/html — no serde_json::to_vec
```

`igniter-server` core gains **only** the generic raw-byte capability; it never learns about HTML,
ViewArtifact, or the frame stack.

## 3. Render protocol (Q1) — reject magic, demand explicitness

| Option | Verdict |
|---|---|
| **(a) explicit app decision `Render { artifact, content_type }`** | **RECOMMEND** — the app explicitly hands a ViewArtifact + names the target; the renderer runs only on this decision |
| (b) structured marker inside `Respond` (`{"__render":"html", …}`) | reject — overloads `Respond`, host must sniff a magic key in app data |
| (c) header-driven transform (`content-type: text/html` ⇒ render) | reject — couples a header to a transform; surprising |
| (d) "postprocess all JSON" | **REJECT outright** — arbitrary app JSON would become render/template authority; the card forbids it |

**Decision: a new explicit `Render { artifact, content_type }` decision at the IgWeb/app layer.** The
renderer is invoked **only** on this opt-in decision — never on arbitrary `Respond` JSON. Because the
artifact is a **structured ViewArtifact** (a closed node vocabulary), not a template string, app data can
never become markup/structure authority (Q5). This is the anti-magic core: rendering is a per-response,
explicit, structural projection.

## 4. Where the renderer lives (Q2) — decision matrix

| Location | Verdict |
|---|---|
| `igniter-server` core built-in | **REJECT** — core must stay route/domain/view-free; depending on frame/ViewArtifact inverts the P6/P7 dependency direction |
| generic `igniter-server` response-middleware hook | **REJECT for the renderer** — middleware is `ServerApp`-decorator shaped with no wire-body hook; adding a body-transform hook to core is framework drift. (The **raw-byte seam** *is* core — but as a generic capability, §5, not a renderer.) |
| **separate `igniter-render-html` crate** | **RECOMMEND** — pure `ViewArtifact JSON → HTML` projector, depends on `igniter-frame` (a new RenderHost target), **machine-free**, independently testable |
| **`igniter-web` runner extension wires it** | **RECOMMEND** — `igniter-web` already maps `Decision → ServerResponse` (`map_decision`); it recognizes the `Render` decision and calls `igniter-render-html`, producing a Raw-bodied `ServerResponse` |

**Dependency direction (one way, never reversed):**
`igniter-web → igniter-render-html → igniter-frame`. `igniter-server` core depends on **none** of them; it
only learns to emit raw bytes (§5). This keeps "ViewArtifact→HTML is just another RenderHost" literally
true — the SVG/wireframe/GUI hosts already exist; HTML is the same shape, in its own crate.

## 5. Raw-response dependency (Q3) — the minimal seam

Today: `ServerResponse { status, headers, body: Value }` + `encode_response` ⇒ `serde_json::to_vec(body)`.
**Minimal change (the named `RAW-RESPONSE` gate):** let the body carry raw bytes:

```rust
enum ResponseBody { Json(Value), Raw { bytes: Vec<u8>, content_type: String } }
// encode_response branches: Json → serde_json::to_vec (today's path, unchanged);
//                           Raw  → write bytes VERBATIM, set the carried content-type.
```

- **In server core, but view-free:** the encoder learns "emit raw bytes," **not** "render HTML." It is a
  generic capability (also unlocks SVG, plain text, binary).
- **Distinguish decision vs bytes:** the `Render` decision (app intent) is produced/handled in
  `igniter-web`; the `Raw` body (wire bytes) is what the encoder emits. The renderer turns one into the
  other; core only carries the bytes.
- This is the single core protocol change the whole SSR path depends on. It is small, deliberate, and
  testable (verbatim bytes; content-type preserved; middleware still applies).

## 6. Middleware order (Q4)

Render is **post-app / pre-encode**, living where `map_decision` lives (igniter-web), **not** at the
encoder and **not** pre-app:

```text
request → BodyLimitApp → AuthTokenApp → TraceApp → ReloadableApp(app)
        → app returns Render{artifact,content_type}
        → [igniter-web] igniter-render-html projects → Raw{bytes,text/html}
        → ServerResponse{ Raw } → host.rs encode_response (verbatim)
```

- `BodyLimit`/`Auth`/`Trace` stay **pre-app request decorators** — unchanged; they never see the rendered
  bytes (Trace still composes a correlation **header**, which survives into the Raw response).
- Render is a **pure projection** with no effect — distinct from the `Invoke`/`InvokeEffect` arms (future
  effect-host execution is a different decision path; Render never touches the machine).
- It is **not** encoder-level: the encoder stays dumb (Json→serialize, Raw→passthrough).

## 7. Security / escaping model (Q5) — the strongest argument for renderer-first

**Structural ViewArtifact removes template-injection risk.** Because the view is a **typed node tree**
(closed vocabulary: Label/Text/Select/Button/…), user data only ever lands in **escaped leaf positions**,
never in tag names or structure. There is no string-template surface to inject into.

- **Default escaping (always on):** text nodes → HTML-entity-escape (`<`,`>`,`&`,`"`,`'`); attribute values
  → attribute-escape; **URLs** (href/src) → scheme allowlist (`http`/`https`/relative only; reject
  `javascript:`/`data:` by default).
- **Raw HTML opt-in:** **none in v0** — no raw-HTML node. If ever added, a `RawHtml` node must be a loud,
  explicit, audited opt-in defaulting OFF (the app takes responsibility); v0 keeps the projector
  injection-proof by construction.
- **Default headers:** the render extension may emit a sane default `Content-Security-Policy` +
  `X-Content-Type-Options: nosniff`, app-overridable. Not in server core.
- **User strings** flow through the projector's escape functions at the leaf; they can never become markup.

This structural-safety property is the decisive reason to prefer renderer-first over `.ig.html` string
templates (Q6) — templates re-introduce the injection surface that ViewArtifact eliminates.

## 8. ViewArtifact→HTML vs `.ig.html` (Q6)

**Renderer-first is the better next step.** Reasons: reuses the proven ViewArtifact + RenderHost stack (one
more render target); structurally injection-proof (§7); one view model, two projections (client DOM today,
server HTML next); no new dialect.

`.ig.html` is **not rejected forever** — positioned under **Projection-Dialect governance (P0)**: a *future*
dialect that must lower deterministically to an **inspectable artifact** — ideally **ViewArtifact JSON**, or
a **pure `.ig` `View(data) -> Html` contract** (sugar, not a runtime template engine; auto-escaping
compiled in). It would be justified only when content-heavy pages make a component tree clumsy, and it must
target the **same** ViewArtifact/HTML pipeline, never a server-core runtime special-case. So: renderer now;
`.ig.html` is a later, separately-gated dialect, never a competing runtime.

## 9. Assets (Q7)

Rendered HTML may **reference** CSS/JS/wasm/images via `<link>`/`<script>`/`<img>` URLs pointing at an
**external static server** (the P1/P11 boundary). In v0 the render extension **bundles nothing** and the
server core **serves no files**. This packet does **not** prove static file serving in core is unavoidable —
it is not: SSR HTML + externally-served assets is sufficient. Static serving stays out of core, behind the
same future gate with the same security checks (canonical root / no `..` / no symlink escape / no listing /
extension allowlist / no dotfiles / max size / no public listener — P11 §7).

## 10. Caching & observability (Q8)

The render is a **pure function** of `(ViewArtifact, renderer_version)` ⇒ deterministic, safely cacheable.

- **Safe to log/count:** artifact **digest** (content hash, not contents), renderer version, **app
  identity** (already in `protocol.rs`), content-type, output byte length, render duration, correlation id.
- **Never log:** raw user HTML, ViewArtifact contents, or any data values.
- **Valid cache key:** `(artifact_digest, renderer_version, app_identity)` → cached HTML bytes. Caching is
  **optional/external** in v0 (no core cache machinery — P11 §5).

## 11. Test / proof plan (Q9)

Layered, smallest-first, **no browser**:

1. **Pure projector (no server):** a fake minimal ViewArtifact fixture → `igniter-render-html` → a
   **deterministic, byte-stable** HTML string. Assert: byte-identity across two renders; a `<script>`-bearing
   text value comes out **escaped**; a `javascript:` href is **rejected/neutralized**; an allowed `https:`
   href passes. This proves the structural-safety + determinism thesis with **zero server/protocol change**.
2. **Wire test (only once `RAW-RESPONSE` exists):** an app returns `Render{artifact, text/html}` → loopback
   response wire body is **verbatim HTML** (no JSON quoting), `content-type: text/html`, and
   `BodyLimit`/`Auth`/`Trace` middleware still apply.

## 12. Next-card recommendation (Q10)

**`LAB-IGNITER-RENDER-HTML-P3`** — a pure `igniter-render-html` crate: `ViewArtifact JSON → deterministic,
escaped HTML string`, as a new `RenderHost`-shaped target depending on `igniter-frame`, with the §11.1
unit tests (determinism + text/attr/url escaping + scheme allowlist). **No server change, no
`RAW-RESPONSE`, no browser, no DB.**

**Why this order (renderer crate before the seam):**
1. **Highest value, lowest risk, fully isolated** — proves the structural-no-injection + determinism thesis
   with zero core/protocol risk.
2. **Useful even without SSR** — emits static HTML files or feeds an external static server immediately.
3. **De-risks the view model before touching the server protocol** — `RAW-RESPONSE` is a separate, smaller
   core change that follows once we have HTML bytes worth emitting.

**Sequence:** `RENDER-HTML-P3` (pure projector) → `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*` (the
`ResponseBody::Raw` seam + encoder branch + wire tests) → `LAB-IGNITER-WEB-RENDER-DECISION-P*` (wire the
`Render` decision in `igniter-web`, end-to-end loopback `text/html`). `.ig.html` only later, gated, as a
Projection Dialect over the same pipeline.

## 13. Closed surfaces

No implementation. No `RAW-RESPONSE` code. No HTML renderer code. No `.ig.html` syntax. No static file
serving. No browser-runtime change. No DB. No live network / public listener. No effect-host execution. No
`igniter-frame`/`igniter-render-html` dependency in `igniter-server` core. No canon claim.

---

*Readiness/design only. Compiled 2026-06-19; verified against live `protocol.rs`, `host.rs encode_response`,
`middleware.rs`, `igniter-web/src/lib.rs map_decision`, and the `frame-ui/` ViewArtifact+RenderHost stack.
No code, dependency, or example change.*
