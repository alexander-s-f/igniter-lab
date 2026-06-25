# lab-igniter-web-ssr-descriptor-boundary-readiness-p27-v0

Card: `LAB-IGNITER-WEB-SSR-DESCRIPTOR-BOUNDARY-READINESS-P27`
Route: standard / architecture readiness · Skill: idd-agent-protocol
Status: readiness packet (no code/renderer/server/asset/export change; no canon claim)
Date: 2026-06-25
Builds on: P24 HTML expression model · P25 dialect · P26 vocab · Data Projection P1-P5 (esp. P5 §10 export).

> **Authority boundary.** Design only. No server/renderer change, no asset pipeline, no file export
> implementation, no public-hosting claim. Cited against live source.

---

## Headline

**Recommended boundary: `app descriptor → host projector → server raw seam` — three roles, already cleanly
separated in live code.** The app returns a **structured descriptor** (`ViewArtifact`), never bytes; a **host
projector** (`igniter_render_html`, a plugin layer) turns it into escaped bytes + a content-type; **server-core**
(`igniter-server`) ships those bytes through the generic `ResponseBody::Raw { bytes, content_type }` seam and
stays renderer-free.

The decisive finding: that raw seam is **already the generalized file/export seam** — `ResponseBody::Raw` is
documented as *"the generic seam for HTML / CSV / XLSX / PDF / binary downloads: server-core ships bytes"*
(`server/igniter-server/src/protocol.rs:39-46`), with `content-disposition` already supported
(`server/igniter-server/src/host.rs:354`). So **SSR-HTML and file export are the same boundary**, differing
only by *projector + content-type*. This is the outbound mirror of the Data Projection Boundary (P5 §10's
"export = reverse arrow"), and it is **live, not aspirational**.

**Recommended naming:** drop "render middleware" (implies a hidden transform pipeline). Use **descriptor →
projector → raw seam**; the projector layer is a **"projector"** (the term the code already uses,
`frame-ui/igniter-render-html/src/lib.rs:3`; cf. frame `RenderHost`).

---

## 1. Current SSR path (Q1) — exact, verified

```text
.ig handler                          host (igniter-web)                         server-core (igniter-server)
───────────                          ──────────────────                         ────────────────────────────
RenderView { status, view:ViewArtifact } ─► map_decision → render_to_decision ─► render_html(view) ─► ServerResponse::raw(status, bytes, "text/html; charset=utf-8")
Render     { status, artifact_json:String }─► render_to_decision (JSON-string source) ─► render_html ─►  (same raw seam)
RespondView{ status, view:View }     ─► map_decision ─► JSON body root (no render)  ─► ServerResponse::json
Respond / RespondError               ─► map_decision ─► JSON                          ─► ServerResponse::json
```

Citations:
- `RenderView`/`Render` → `render_to_decision` → `igniter_render_html::render_html` → raw `text/html`
  (`server/igniter-web/src/lib.rs:414-453`); failure → JSON 500, no artifact-body leak (`:446-452`).
- The descriptor projector is **standalone + renderer-free server**: *"igniter-server stays renderer-free —
  the dependency lives here [igniter-web]"* (`lib.rs:413,440`); the renderer *"is a projector / render target,
  not a language feature and not server authority"* (`frame-ui/igniter-render-html/src/lib.rs:3`).
- Server raw seam: `ResponseBody::Raw { bytes, content_type }` (`protocol.rs:42-46`), written with its
  content-type header (`host.rs:258-263`); proven by `raw_html_is_written_verbatim`,
  `raw_preserves_binary_bytes_including_nul_and_non_utf8`, `raw_carries_content_disposition_as_a_normal_header`
  (`host.rs:323-354`).

---

## 2. Responsibility map (Q2) — descriptor / projector / server

| Layer | Owns | Does **not** own | Live anchor |
| --- | --- | --- | --- |
| **App** (`.ig`) | the **descriptor** (`ViewArtifact` via `RenderView`; data `View` via `RespondView`; JSON via `Respond`) — a structured value | bytes, escaping, content-type, HTML generation | `todo_views.ig`; `igweb.rs:80-88` |
| **Projector** (host plugin) | descriptor → **escaped bytes + content-type**; format + XSS + URL safety; fail-closed on bad/unknown nodes | the wire, headers framing, routing | `render-html:45-102`; wired at `lib.rs:441` |
| **Server-core** (`igniter-server`) | the **raw bytes seam** + headers (`ResponseBody::Raw{bytes, content_type}`, content-disposition); transport | rendering, escaping, descriptor meaning | `protocol.rs:39-46`; `host.rs:258-263,354` |

Invariant: **the app never emits bytes or markup; the projector never decides routing; server-core never
renders.** Escaping lives entirely in the projector (structured input → "no markup-injection surface",
`render-html:9-13`), which is *why* the app can stay pure-data.

---

## 3. Naming (Q3)

| Candidate | Verdict |
| --- | --- |
| "render middleware" | **Reject** — "middleware" implies a hidden transform pipeline / interceptor chain; the code is a *direct* descriptor→bytes projection, not a middleware stack. |
| **"projector"** | **Recommended** for the descriptor→bytes layer — already the code's word (`render-html:3`), and aligns with the frame `RenderHost` family (HTML/SVG/GUI/3D projectors of one descriptor). |
| **"raw seam" / `ResponseBody::Raw`** | **Recommended** for the server bytes layer — the existing, content-type-agnostic generic seam. |
| "descriptor-to-bytes seam" | good **generic** name for the whole boundary. |

So: **`app descriptor → host projector → server raw seam`** is the boundary vocabulary.

---

## 4. Generalization to xlsx / csv / pdf / file export (Q4)

**Already generalized — no new seam needed.** `ResponseBody::Raw` is content-type-agnostic and explicitly
spans *"HTML / CSV / XLSX / PDF / binary downloads"* (`protocol.rs:39`); `content-disposition` (attachment
downloads) already rides it as a normal header (`host.rs:354`). So a file export is the **same boundary** with
a different projector:

```text
HTML view:   ViewArtifact descriptor   ──[ html projector  ]──► text/html bytes        ─► Raw seam
CSV export:  tabular/Dataset descriptor ──[ csv projector   ]──► text/csv bytes + disp  ─► Raw seam
XLSX export: tabular/Dataset descriptor ──[ xlsx projector  ]──► xlsx bytes + disp      ─► Raw seam
PDF export:  document descriptor        ──[ pdf projector   ]──► application/pdf + disp ─► Raw seam
```

This is the **outbound mirror of Data Projection** (P5 §10): inbound `external → [host projector] → typed
data`; outbound `descriptor → [host projector] → bytes`. The tabular export descriptor is naturally a
`Collection[<Record>]` (the same shape projection *produces* inbound) — closing the loop. **A CSV/XLSX/PDF
projector is a sibling of `igniter_render_html`, not a new architecture.** (Implementation is out of scope
here; the seam is the point.)

---

## 5. SSR alongside JSON/API (Q5)

The same app serves both by **Decision variant**, per route — no separate server mode:
- `RenderView`/`Render` → HTML (raw seam);
- `RespondView` → JSON view descriptor (body root);
- `Respond`/`RespondError` → JSON API.

So a TodoApp route can return HTML for a browser and JSON for an API client by emitting a different `Decision`
(`lib.rs:365-433`). v0 selects the projector by the **explicit Decision variant**; Accept-header content
negotiation over *one* descriptor (same `ViewArtifact` → HTML *or* a JSON view) is a clean future option, not
required now.

---

## 6. Forms / actions round-trip (Q6)

No new mechanism — the loop closes through the **existing request path**:
- **Outbound:** the descriptor's `form`/`button`/`text`/`select` (+ future `link`, P26) → projector emits
  `<form>`/`<button data-action>`/`<input>`/`<a href>` (`render-html:240-300`).
- **Inbound:** the browser GET/POSTs back to a route; the **same `.ig` handler contracts** process it —
  POST body via `req.body_json : Map[String,Unknown]` (`lib.rs:304`), GET cursor via `req.query`
  (`lib.rs:311`), idempotency/surrogate via the existing fields (P1). Pagination `link` → `?after=` (already
  live, P1).

So forms/actions are descriptor-out, normal-request-in. The descriptor never carries behavior — only the
shape; the handler owns the action. (No client runtime — SSR only.)

---

## 7. What remains closed (Q7)

| Closed | Why |
| --- | --- |
| streaming responses | bounded single-response seam; out of v0 |
| public assets pipeline (css/js files) | host concern; SSR emits inline classes only (`ig-*`) |
| **raw HTML node** | the closed vocabulary is what removes the injection surface (P24/P26) |
| **template runtime** | rejected (P25) — dialects lower to the descriptor, no engine |
| **client hydration / interactivity** | out of an SSR-descriptor model entirely |
| file export *implementation* | seam is ready; CSV/XLSX/PDF projectors are named follow-ons, not built here |

---

## 8. TodoApp HTML implications (what to rely on now)

- Return **`RenderView { view : ViewArtifact }`** for HTML views; keep `Respond`/`RespondError` for the JSON
  API on the same routes (§5).
- Build the `ViewArtifact` via P24 Idiom A (`Collection[TodoRow] → map(TodoRowToNode) → FormView`), plus the
  `link` node (P26) for pagination/navigation once it lands.
- Rely on the **projector** for all escaping/URL safety; never emit bytes or markup from `.ig`.
- Forms post back to existing handler contracts via `body_json`/`query` (§6).

---

## Verification

```bash
rg -n "RenderView|Render \{|render_html|ServerResponse::raw|ResponseBody::Raw|content-type|descriptor|Project|xlsx|csv|pdf|export" \
  server runtime lab-docs .agents \
  > /tmp/igniter-ssr-descriptor-boundary-grep.txt        # 2056 hits

git diff --check                                          # clean
```

---

## Reporting

- **Boundary vocabulary:** **`app descriptor → host projector → server raw seam`** (drop "render middleware";
  use "projector" + `ResponseBody::Raw`). It is the outbound mirror of the Data Projection Boundary.
- **Responsibility map:** app owns the structured descriptor; projector owns descriptor→escaped-bytes +
  content-type + XSS/URL safety; server-core owns the generic raw bytes seam + headers and stays
  renderer-free. Already separated in live code.
- **Relation to file export:** the **same seam** — `ResponseBody::Raw` already spans HTML/CSV/XLSX/PDF/binary
  with content-disposition; a CSV/XLSX/PDF export is a sibling *projector* over a tabular descriptor (the
  outbound `Collection[<Record>]`), not a new boundary.
- **Next cards / holds:** (impl, after Data Projection P6) TodoApp HTML via `RenderView` + Idiom A;
  (follow-on) the `link` node (P26); (named, held) a CSV/XLSX export projector over a tabular descriptor —
  the file-export realization of this seam. Streaming / assets / hydration / raw-HTML stay closed.
