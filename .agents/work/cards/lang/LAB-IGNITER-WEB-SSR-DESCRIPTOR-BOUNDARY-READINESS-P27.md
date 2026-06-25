# LAB-IGNITER-WEB-SSR-DESCRIPTOR-BOUNDARY-READINESS-P27

Status: CLOSED (readiness packet delivered 2026-06-25)
Route: standard / architecture readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-web-ssr-descriptor-boundary-readiness-p27-v0.md`.

**Boundary vocabulary: `app descriptor → host projector → server raw seam`** — three roles already cleanly
separated in live code; drop "render middleware" (implies hidden pipeline), use "projector" (the code's word
`render-html:3`) + `ResponseBody::Raw`.

**Current SSR path (verified):** `RenderView{view:ViewArtifact}` / `Render{artifact_json}` → `render_to_decision`
→ `render_html` → `ServerResponse::raw(status,bytes,"text/html")` (`lib.rs:414-453`); `RespondView`/`Respond`
→ JSON. igniter-server stays renderer-free (dep lives in igniter-web, `lib.rs:413,440`).

**Responsibility map:** app owns the structured descriptor (never bytes); projector owns descriptor→escaped
bytes + content-type + XSS/URL safety; server-core owns the generic raw seam + headers. Escaping wholly in
the projector (`render-html:9-13`).

**Decisive find — file export is the SAME seam:** `ResponseBody::Raw{bytes,content_type}` is documented as
"the generic seam for HTML / CSV / XLSX / PDF / binary downloads" (`protocol.rs:39-46`), content-disposition
already supported (`host.rs:354`). So SSR-HTML and CSV/XLSX/PDF export differ only by *projector + content-type*
— the outbound mirror of Data Projection (P5 §10 export reverse-arrow); a tabular export descriptor is the
outbound `Collection[<Record>]`. A CSV/XLSX/PDF projector is a sibling of `igniter_render_html`, not a new
architecture.

**SSR + JSON coexist by Decision variant** (RenderView=HTML / Respond=JSON), per route, no separate mode;
Accept-negotiation over one descriptor = future option. **Forms round-trip** through the existing request path
(descriptor-out → browser → same handler via `body_json`/`query`); no client runtime. **Closed:** streaming,
assets pipeline, raw-HTML, template runtime, hydration, export *impl*.

**Next:** (impl after Data Projection P6) TodoApp HTML via RenderView + Idiom A; (follow-on) `link` node (P26);
(named/held) a CSV/XLSX export projector over a tabular descriptor.

**Boundary honored.** No server/renderer/asset/export change; no canon. Docs only. `git diff --check` clean;
grep → `/tmp/igniter-ssr-descriptor-boundary-grep.txt` (2056 hits).

## Goal

Clarify the server-side rendering boundary for Igniter web apps:

```text
app returns structured descriptor
  -> host/projector renders bytes
  -> server sends raw response
```

versus alternatives where the app returns HTML strings, templates render in the host, or middleware
transforms JSON into bytes. This card should decide the boundary vocabulary and keep future TodoApp HTML
from blurring app/host/server roles.

## Current Authority

- `igniter-web` `Render` / `RenderView` implementation.
- `igniter-render-html`.
- `igniter-server` raw response support.
- Render middleware/readiness docs.
- File/export notes if present.
- Data Projection P1-P5.

## Questions To Answer

1. What is the current SSR path exactly?
   - `Render { artifact_json }`;
   - `RenderView { view }`;
   - `render_html`;
   - `ServerResponse::raw`.
2. What is the descriptor/projector boundary?
   - app owns descriptor;
   - projector owns escaping/HTML generation;
   - server owns bytes/headers.
3. Is "render middleware" still the right name?
   - projector?
   - render host?
   - descriptor-to-bytes seam?
4. How does this generalize to xlsx/csv/pdf/file export?
5. What does SSR mean when the app may also serve JSON/API?
6. How do forms/actions round-trip?
7. What remains closed?
   - streaming;
   - public assets;
   - raw HTML;
   - template runtime;
   - client hydration.

## Design Bias

- Server-core stays renderer-free except for generic raw response support.
- Renderer/projector is host/plugin layer.
- App returns structured descriptor, not bytes, unless explicitly using a host-approved export/render
  decision.
- Descriptor-to-bytes seam should generalize beyond HTML.

## Boundary

Allowed:

- Write a readiness packet.
- Include diagrams.
- Recommend naming and next cards.

Closed:

- No code changes.
- No renderer/server changes.
- No asset pipeline implementation.
- No file export implementation.
- No stable public hosting claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-web-ssr-descriptor-boundary-readiness-p27-v0.md`

Must include:

- current SSR path;
- descriptor/projector/server responsibility map;
- relationship to file export;
- TodoApp HTML implications;
- recommended naming;
- next cards.

## Verification

Run:

```bash
rg -n "RenderView|Render \\{|render_html|ServerResponse::raw|ResponseBody::Raw|content-type|descriptor|Project|xlsx|csv|pdf|export" \
  server runtime lab-docs .agents \
  > /tmp/igniter-ssr-descriptor-boundary-grep.txt

git diff --check
```

## Acceptance

- [x] Packet exists.
- [x] It maps current SSR path against live code.
- [x] It keeps app/projector/server roles distinct.
- [x] It explains relation to file/export descriptor-to-bytes seam.
- [x] It says what TodoApp HTML should rely on now.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- boundary vocabulary;
- responsibility map;
- next cards / hold decisions.
