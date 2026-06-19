# LAB-TODOAPP-VIEWS-ASSETS-READINESS-P1 — TodoApp UI/views/assets shape

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab readiness
Skill: idd-agent-protocol
Delegation: OPUS-TODOAPP-VIEWS-ASSETS-P1

## Intent

Design the TodoApp **views + assets** layer without turning `igniter-server`
into a web framework or smuggling domain/UI concepts into server core.

This is the fourth wave next to:

1. `.igweb` context composition;
2. Postgres connector;
3. TodoApp API with Postgres;
4. **TodoApp views/assets** (this card).

The goal is to decide how a Todo app can eventually serve UI, static assets,
and view projections while preserving the current boundaries:

```text
app owns routes/domain/views/assets meaning
server owns transport/concurrency/middleware
machine owns capabilities/receipts/effects
frame/view artifacts stay app-owned projections
```

## Authority

Readiness/design only. No code, no assets protocol, no raw-response
implementation, no file serving, no public listener, no DB, no canon claim.

This card may create:

- `lab-docs/lang/lab-todoapp-views-assets-readiness-p1-v0.md`;
- this card's closing report.

This card must **not** change:

- `igniter-server`, `igniter-web`, compiler, VM, machine, frame, ui-kit, or
  console code;
- examples/tests/assets;
- Cargo dependencies;
- docs outside the one packet and this card.

## Verify First

Read current live surfaces and prior readiness before writing:

- `lab-docs/lang/lab-machine-igniter-server-assets-readiness-p11-v0.md`
- `.agents/work/cards/lang/LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P11.md`
- `server/igniter-server/src/protocol.rs`
- `server/igniter-server/src/host.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/examples/todo_app/`
- `server/igniter-web/examples/todo_v2_app/`
- `lab-docs/lang/lab-igniter-web-runner-p12-v0.md`
- `lab-docs/lang/lab-igniter-web-runner-check-p14-v0.md`
- `lab-docs/lang/lab-todoapp-api-postgres-e2e-readiness-p1-v0.md` if it exists
- relevant frame/view docs if needed, but do not treat them as server
  authority.

Confirm the critical P11 fact live: `ServerResponse.body` is JSON
(`serde_json::Value`) and the host encoder JSON-serializes it, so HTML/binary
bytes are not currently sent verbatim.

Live code wins over old docs.

## Problem Statement

TodoApp API can be modeled with `.igweb` routes and `.ig` contracts. A real app
also needs UI:

- HTML shell or app manifest;
- CSS/JS/image assets;
- client-side route entry points;
- maybe ViewArtifact / Frame projection;
- content types, cache headers, asset digests;
- local dev reload/check behavior;
- later production deployment shape.

The danger is solving this by adding a route table, static directory serving,
or template engine to `igniter-server` core. That would violate the boundary
we just built. The readiness packet should define the app-owned shape and the
smallest future implementation slice, if any.

## Questions To Answer

### Q1. What can TodoApp serve today?

Using current `ServerResponse`:

- Can it return JSON UI descriptors?
- Can it return HTML as a string? What does the wire body actually look like?
- Can it return raw CSS/JS/images? (Likely no.)
- Can it set `content-type` headers and do they matter if body is JSON-encoded?

Be exact: distinguish **JSON string containing HTML** from **verbatim HTML**.

### Q2. What is the desired v0 UI surface?

Compare options:

A. JSON-first UI manifest / ViewArtifact response.
B. Raw HTML shell response.
C. External static server/CDN next to `igweb-serve`.
D. Future `AssetManifest` app protocol.
E. Frame/ViewArtifact app projection.

Recommend a v0 direction for TodoApp, not a universal canon.

### Q3. Where do authored view files live?

Evaluate possible app layouts:

```text
todo_app/
  igweb.toml
  routes.igweb
  todo_handlers.ig
  views/
  assets/
```

or separate app package/workspace. Decide what belongs in app-owned files vs
server/runtime files.

### Q4. Should views be `.ig`, `.igv`, ViewArtifact JSON, templates, or static?

Compare:

- pure `.ig` returning `Decision::Respond`;
- `.igv` / ViewArtifact-style projection;
- generated/static HTML;
- external frontend bundle;
- future Todo-specific view dialect (probably reject for now).

Be explicit about Projection Dialect governance: do not invent
`.igtodo-html-super-edition`.

### Q5. What does "assets" mean for v0?

Classify:

- CSS;
- JS;
- images;
- fonts;
- generated ViewArtifact runtime;
- JSON manifests;
- source maps.

For each: app-owned vs server-owned; JSON response vs raw bytes vs external
static server; cache/digest implications.

### Q6. What server protocol gap blocks real assets?

Name the exact protocol gap:

- raw bytes body?
- content-type fidelity?
- file serving?
- asset manifest?
- range/cache/etag?

Relate it to P11's likely future `RAW-RESPONSE` gate. Decide whether TodoApp
views/assets should wait for raw response or start JSON-first.

### Q7. How do routes relate to views?

Should `routes.igweb` support page routes separately from API routes?

Examples:

- `GET "/" -> TodoIndexPage`;
- `GET "/accounts/:account_id/todos" -> TodoListPage`;
- API routes under `/api/...`.

Decide whether TodoApp should split API/UI route namespaces or use content
negotiation. Avoid magic `respond_to`.

### Q8. How do assets interact with middleware?

How should P8 middleware apply?

- trace/correlation;
- auth envelope;
- body limit;
- cache headers;
- gzip/compression (probably out of scope);
- public vs authenticated assets.

Middleware should stay generic and not parse app domain.

### Q9. What are the security gates?

If future file serving happens, name required gates:

- canonical root;
- no `..`;
- no symlink escape;
- no directory listing;
- extension/content-type allowlist;
- no hidden dotfiles;
- max file size;
- no public listener by default.

This card should not implement them.

### Q10. What is the relation to TodoApp API/Postgres?

Views should consume API/domain data, but this readiness must not depend on a
live DB. Decide:

- Does the first UI proof use static/fake data?
- Does it call API routes?
- Does it return a view projection from `.ig` handlers?
- Which parts wait for `LAB-TODOAPP-API-POSTGRES-E2E-*`?

### Q11. What is the first implementation card?

Pick one smallest next card:

- JSON ViewManifest / page descriptor proof;
- raw response protocol gate;
- external static-server example;
- no implementation yet until API skeleton lands.

Justify the sequence.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-todoapp-views-assets-readiness-p1-v0.md
```

The packet must include:

1. executive summary;
2. verify-first facts (especially JSON-only `Respond` today);
3. desired TodoApp UI/app layout;
4. view-shape options and recommendation;
5. assets classification;
6. server protocol gap;
7. route/API/page strategy;
8. middleware/security boundaries;
9. relation to TodoApp API/Postgres;
10. next-card recommendation;
11. closed surfaces.

Then close this card with a compact report.

## Acceptance

- [x] Packet exists at the required path.
- [x] Packet verifies current `ServerResponse`/wire body behavior.
- [x] Packet distinguishes JSON-carried HTML from raw HTML bytes.
- [x] Packet keeps assets/views app-owned, not server-core-owned.
- [x] Packet does not propose route table/static-directory serving in
      `igniter-server` core.
- [x] Packet relates TodoApp views to API/Postgres without requiring live DB.
- [x] Packet names exact raw-response/assets protocol gaps.
- [x] Packet chooses one smallest next implementation card or explicitly says
      "no implementation yet".
- [x] No code, examples, dependencies, assets, or DB state changed.
- [x] Card closed with report.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-todoapp-views-assets-readiness-p1-v0.md` — readiness packet, **no code**
(only the packet + this card). All 12 sections; Q1–Q11 answered. App-side counterpart to the server-side
P11 assets readiness.

**Verify-first (live):** `ServerResponse.body: serde_json::Value`; `host.rs encode_response` does
`serde_json::to_vec(&resp.body)` → **wire body always JSON-serialized** (verbatim HTML/binary not servable).
**New app-side delta:** the IgWeb `Decision` path is narrower still — prelude `Respond { status, body:String }`
and `map_decision` double-wraps as `{"body":"…"}` with forced `application/json` (`igniter-web/src/lib.rs:164`),
so a handler can't yet return a clean structured JSON descriptor or set headers. Also: the API/Postgres
readiness packet now exists and confirms the first app slice stays **no-DB / observed-effects**; views
likewise stay DB-free.

**Recommendation:** TodoApp views are **JSON-first ViewArtifact descriptors** returned by `.ig` handlers
(optionally authored in `.igv`), rendered by the **existing machine-free frame runtime** in a static shell
served by an **external static server**. No server-core change, no new dialect (reuses `.igv`→ViewArtifact→
frame). API vs page routes **explicitly namespaced** (`/api/...` data vs view routes), no magic content
negotiation. Raw HTML/CSS/wasm → external static server (v0) or the deferred P11 `RAW-RESPONSE` gate (only
if verbatim server-emitted bytes are ever needed — the external-shell architecture avoids it). First UI
proof uses **fake data**, no DB.

**Two gaps named:** (1) **IgWeb-level structured JSON body** — the v0 blocker, app-layer; (2) server
**RAW-RESPONSE** (P11) — deferred, not needed for v0.

**Next card:** **`LAB-TODOAPP-VIEW-MANIFEST-P2`** — `.igweb` view route + `.ig` handler returning a
ViewArtifact JSON descriptor from fake data through `igweb-serve`, with the one bounded enhancement
(clean structured JSON body, no double-wrap), no raw bytes, no DB. Then external static-shell example →
[Postgres typed-read + TodoApp API for real data] → `RAW-RESPONSE-P*` only if verbatim bytes are required.

## Closed Surfaces

No implementation. No raw response body. No file-system serving. No static
directory serving. No route table in server core. No template engine in core.
No public listener. No CDN/live network. No auth secrets. No DB. No Frame/UI
dependency in server core. No new projection dialect. No canon claim.

## Suggested Next

Likely one of:

```text
LAB-TODOAPP-VIEW-MANIFEST-P2
LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*
```

The readiness packet should decide. If JSON-first UI manifest is enough, prefer
TodoApp-local proof before raw bytes. If verbatim HTML/CSS/JS is the blocker,
name the raw-response gate explicitly.
