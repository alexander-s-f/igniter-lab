# LAB-IGNITER-WEB-RENDER-MIDDLEWARE-READINESS-P2

Status: CLOSED
Route: standard / lab readiness
Date: 2026-06-19
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-RENDER-MIDDLEWARE-P2

## Goal

Research the host-side shape for rendering app-owned ViewArtifact JSON into
HTML bytes **outside the Igniter language**, as a server extension/middleware or
plugin, before inventing `.ig.html` or putting view/runtime knowledge into
`igniter-server` core.

The pressure comes from TodoApp views/assets P1: JSON-first ViewArtifact is a
good app model, but browsers eventually need either a client frame runtime or
verbatim HTML. This card asks whether the right SSR seam is:

```text
IgWeb app returns explicit ViewArtifact/render-intent JSON
  -> host render extension projects ViewArtifact -> HTML
  -> raw-response gate sends bytes with text/html
```

## Current Authority

- `.ig` / `.igweb` own app meaning: routes, handlers, domain data, logical view
  descriptors.
- `igniter-server` owns transport, loop/concurrency, request/response encoding,
  reload, and generic middleware mechanics.
- Frame/ViewArtifact work owns the existing structural view model.
- `RAW-RESPONSE` is not available today; current `ServerResponse.body` is JSON
  and is serialized with `serde_json::to_vec`.
- This card is readiness only. It may recommend a next implementation card but
  must not implement rendering, raw response, `.ig.html`, or server assets.

## Verify First

Read live surfaces before writing the packet:

- `lab-docs/lang/lab-todoapp-views-assets-readiness-p1-v0.md`
- `server/igniter-server/src/protocol.rs`
- `server/igniter-server/src/host.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/middleware.rs`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- relevant ViewArtifact / `.igv` / frame docs and live code
  (`frame/`, `ui/`, or current post-reorg paths)

Confirm explicitly:

- HTML strings cannot be sent verbatim today; they are JSON encoded.
- IgWeb `Respond` currently narrows responses even further (`body:String` and
  double-wrap into JSON).
- ViewArtifact JSON is already a proven app-owned representation.
- Current middleware wrappers are request/app-decision decorators, not a raw
  wire-body encoder hook.
- A ViewArtifact -> HTML projector needs a raw-byte response seam somewhere.

## Questions To Answer

1. **What is the explicit render protocol?** Compare:
   - a new app decision / response shape such as `Render { target, artifact }`;
   - a structured JSON marker inside `Respond`;
   - a header-driven transform;
   - magical "postprocess all JSON".
   
   Reject any option that silently renders arbitrary JSON or lets app data
   become executable/template authority.

2. **Where should the renderer live?** Compare:
   - `igniter-web` runner extension;
   - generic `igniter-server` response middleware hook;
   - separate `igniter-render-html` / `igniter-view-html` crate;
   - server-core built-in.
   
   Keep `igniter-server` app/domain/view-model free unless there is a very
   strong reason.

3. **What raw-response seam is minimally required?** Name the exact boundary:
   `ServerResponse` variant, body enum, encoder hook, content-type handling, or
   another shape. Do not implement it. Distinguish "rendering decision" from
   "wire bytes".

4. **How does this compose with middleware order?** Place render relative to
   `BodyLimitApp`, `AuthTokenApp`, `TraceApp`, `ReloadableApp`, and future
   effect-host execution. State whether render is pre-app, post-app/pre-encode,
   or encoder-level.

5. **What is the security model?** Cover:
   - default escaping;
   - attribute/text/url escaping;
   - raw HTML opt-in (if any);
   - CSP/default headers;
   - whether structural ViewArtifact removes template injection risk;
   - how user strings move through the projector.

6. **ViewArtifact -> HTML vs `.ig.html`:** Decide whether renderer-first is the
   better next step. If `.ig.html` remains plausible, define it only as a future
   Projection Dialect that lowers to an inspectable artifact or pure `.ig`
   contract, not as a server runtime special case.

7. **Assets:** Decide what HTML may reference (CSS/JS/wasm/images) and who serves
   them in v0. Keep static file serving out of core unless this packet proves it
   is unavoidable.

8. **Caching and observability:** What may be logged/counted safely? What cache
   keys would be valid: artifact digest, renderer version, app identity, content
   type? Avoid logging raw user HTML/data.

9. **Test/proof plan:** Propose the smallest proof:
   - fake/minimal ViewArtifact fixture;
   - render to deterministic HTML string/bytes;
   - loopback response with `text/html` only if raw-response gate exists;
   - no browser dependency unless necessary.

10. **Next implementation card:** Recommend exactly one next slice. It may be
    `RAW-RESPONSE` first, a renderer proof crate first, or an integrated
    render-middleware proof, but justify the order.

## Expected Deliverable

Create:

- `lab-docs/lang/lab-igniter-web-render-middleware-readiness-p2-v0.md`
- closing report in this card

The packet must include:

- current live facts;
- explicit decision matrix for renderer location;
- raw-response dependency;
- security/escaping model;
- relation to ViewArtifact and Projection Dialects;
- recommended next card.

## Acceptance

- [x] No source code, dependencies, or examples changed.
- [x] Confirms the current JSON-only response gap from live code.
- [x] Does not claim `.ig.html` is required or rejected forever; positions it
      under Projection Dialect governance.
- [x] Rejects magical JSON postprocessing.
- [x] Keeps `igniter-server` core route/domain/view-free.
- [x] Names the minimal raw-response requirement.
- [x] Defines where render middleware/plugin would sit in the request/response
      flow.
- [x] Covers escaping/XSS and raw HTML policy.
- [x] Separates assets/static serving from render projection.
- [x] Provides a single next-card recommendation.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-igniter-web-render-middleware-readiness-p2-v0.md` — readiness packet,
**no code** (only the packet + this card). Answers Q1–Q10 with a decision matrix, the raw-response
dependency, an escaping model, and a single next card.

**Verify-first (live):** `host.rs encode_response` always `serde_json::to_vec`s the body (no verbatim
HTML); IgWeb `Respond` narrows to `status`+`String`, double-wrapped; **middleware wrappers are `ServerApp`
decorators over request/decision with NO wire-body hook** (`middleware.rs`); ViewArtifact JSON +
`RenderHost` + `from_artifact` are a proven machine-free stack in `frame-ui/`. **Key consequence:** HTML
output needs a raw-byte seam at the **encoder** level — middleware can't reach the wire bytes.

**Recommendation:**
- **Render protocol:** an explicit app `Render { artifact, content_type }` decision — never auto-render
  arbitrary JSON (magic postprocessing rejected).
- **Renderer location:** a separate **`igniter-render-html`** crate (ViewArtifact→HTML, depends on
  `igniter-frame`, machine-free), **wired by `igniter-web`**; `igniter-server` core stays view-free, gaining
  **only** the generic raw-byte seam. Dependency one-way: `igniter-web → igniter-render-html → igniter-frame`.
- **Raw-response seam:** `ResponseBody { Json(Value) | Raw { bytes, content_type } }` + encoder branch — the
  one small core change SSR depends on (generic, not HTML-specific).
- **Order in flow:** render is **post-app/pre-encode** (where `map_decision` lives), not encoder-level, not
  pre-app; BodyLimit/Auth/Trace stay pre-app request decorators.
- **Security:** structural ViewArtifact **removes template injection** (data only lands in escaped leaves);
  default text/attr escaping + URL scheme allowlist; **no raw-HTML opt-in in v0**; this is the decisive
  reason to prefer renderer-first over `.ig.html`.
- **`.ig.html`:** not rejected forever — a *future* Projection Dialect (P0) that must lower to ViewArtifact
  JSON or a pure `.ig` `View(data)->Html` contract, never a server runtime special-case.

**Next card:** **`LAB-IGNITER-RENDER-HTML-P3`** — a pure `igniter-render-html` crate (ViewArtifact JSON →
deterministic, escaped HTML; determinism + escaping + url-scheme tests; no server/protocol/browser change).
Then `…-RAW-RESPONSE-P*` (the `ResponseBody::Raw` seam) → `…-WEB-RENDER-DECISION-P*` (wire the `Render`
decision end-to-end). Renderer-first because it is the highest-value, lowest-risk, fully-isolated proof and
de-risks the view model before touching the server protocol.

## Closed Surfaces

No implementation. No `RAW-RESPONSE` code. No HTML renderer code. No `.ig.html`
syntax. No server static file serving. No browser runtime change. No DB. No live
network/public listener. No effect-host execution. No canon claim.
