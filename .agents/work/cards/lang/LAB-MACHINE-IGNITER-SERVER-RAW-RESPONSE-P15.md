# LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P15 - Generic raw response seam

Status: CLOSED
Lane: standard
Type: implementation
Delegation code: OPUS-SERVER-RAW-RESPONSE-P15
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-RENDER-HTML-P3` proved the first renderer/projector:

```text
ViewArtifact JSON -> deterministic escaped HTML string
```

But `igniter-server` still encodes every `ServerResponse.body` as JSON:

```rust
serde_json::to_vec(&resp.body)
```

So HTML, CSV, XLSX, PDF, and other descriptor-to-bytes outputs cannot be sent verbatim yet. This card
opens the **generic raw response seam** in server-core. It must stay format-agnostic: no HTML renderer,
no Excel, no file path sending, no static server.

## Goal

Add a small, explicit response-body abstraction to `igniter-server`:

```text
ResponseBody = Json(Value) | Raw { bytes, content_type }
```

and update the HTTP encoder so:

- JSON responses keep existing behavior and compatibility;
- raw responses are written verbatim with exact `Content-Length`;
- headers still flow normally;
- server-core remains route/domain/view/export free.

## Verify First

Read live code before editing:

- `server/igniter-server/src/protocol.rs`
- `server/igniter-server/src/host.rs`
- `server/igniter-server/src/effect_host.rs`
- `server/igniter-server/src/middleware.rs`
- `server/igniter-server/tests/*`
- `server/igniter-web/src/lib.rs`
- `lab-docs/lang/lab-igniter-render-html-p3-v0.md`
- `lab-docs/lang/lab-igniter-web-file-export-thread-v0.md`
- `lab-docs/lang/lab-todoapp-views-assets-readiness-p1-v0.md`

Confirm these facts:

- `ServerResponse` currently stores `body: serde_json::Value`.
- `ServerResponse::json` sets `content-type: application/json`.
- `host::encode_response` JSON-serializes every body.
- `effect_host.rs` writes responses through the same `host::encode_response`.
- Middleware short-circuit responses use `ServerResponse::json`.
- `igniter-web` maps `Respond`, `RespondView`, and `InvokeEffect` into existing JSON responses.

## Required Design

Prefer an explicit enum, not ad-hoc flags:

```rust
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ResponseBody {
    Json(Value),
    Raw { bytes: Vec<u8>, content_type: String },
}

pub struct ServerResponse {
    pub status: u16,
    pub headers: BTreeMap<String, String>,
    pub body: ResponseBody,
}
```

Exact naming can differ if the implementation is cleaner, but the semantics must be equivalent.

Add helpers:

```rust
ServerResponse::json(status, value)
ServerResponse::raw(status, bytes, content_type)
```

`ServerResponse::raw` should set `content-type` unless caller already passed a more explicit header shape
through a separate helper. Keep v0 minimal; do not over-design a builder unless the tests need it.

## Encoding Rules

JSON:

- body bytes = `serde_json::to_vec(value)`;
- `content-type` defaults to `application/json`;
- existing JSON tests continue to pass.

Raw:

- body bytes = exact `bytes`;
- `content-type` is preserved;
- no JSON quoting, escaping, wrapping, or reserialization;
- `Content-Length` equals raw byte length.

Headers:

- existing `headers` still write to the wire.
- Do not invent download semantics here beyond allowing headers such as `content-disposition`.

## Closed Scope

- No `igniter-render-html` dependency in `igniter-server`.
- No `igniter-web` render decision.
- No HTML-specific code.
- No Excel/CSV/PDF/export implementation.
- No `send_file(path)` primitive.
- No filesystem reads.
- No streaming/chunked transfer.
- No compression.
- No public listener / deployment changes.
- No route table.
- No DB/effect-host work.
- No canon/stable API claim.

## Tests / Acceptance

- [x] Existing JSON response behavior remains unchanged:
  - `ServerResponse::json(200, json!({"ok":true}))`
  - body on wire is JSON bytes.
  - content-type is `application/json`.
- [x] Raw response encodes verbatim bytes:
  - input bytes `<h1>Hello</h1>`
  - wire body is exactly `<h1>Hello</h1>`, not `"..."` and not `{"body":...}`.
- [x] Raw `Content-Length` is exact byte length.
- [x] Raw `content-type` is preserved, e.g. `text/html; charset=utf-8`.
- [x] Binary bytes are preserved, including `0x00` and non-UTF8 bytes.
- [x] `Content-Disposition` can be set as a normal header and appears on wire; no special download API.
- [x] Middleware JSON short-circuit tests still pass.
- [x] `effect_host` machine feature tests compile/pass or stay correctly gated.
- [x] `igniter-web` tests still pass; its current `RespondView` remains JSON until a later card.
- [x] `igniter-server` normal dependency tree does not gain `igniter-render-html`, `igniter-frame`,
  `igniter-ui-kit`, or export crates.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Files changed (igniter-server only):** `src/protocol.rs` (the `ResponseBody` enum + `ServerResponse::raw`
+ `as_json`), `src/host.rs` (encoder branch + 4 wire tests), `src/effect_host.rs` (wrap ingress body as
`ResponseBody::Json`), `tests/sparkcrm_app_tests.rs` (one body read → `as_json()`). Proof doc:
`lab-docs/lang/lab-machine-igniter-server-raw-response-p15-v0.md`. No `igniter-web` change needed.

**Design:** `ResponseBody { Json(Value) | Raw { bytes, content_type } }`. JSON path unchanged
(`serde_json::to_vec`, content-type from headers). Raw path writes bytes **verbatim** with its own
content-type, exact `Content-Length`, binary-safe; `content-disposition` (and any other header) flows
through `headers`, so a download is just `raw()` + a header — no special download API. Server stays
**format-agnostic** (ships already-produced bytes; never renders/reads them).

**Verify-first paid off:** only one production literal (`effect_host`) and one test (`sparkcrm_app_tests`
indexing `body["error"]`) read the body as a `Value`; every other `.body` read parses wire bytes. So the
migration was 4 tiny edits, all caught up front.

**Proof — all green:** `igniter-server` default + `--features machine` (+4 new raw/JSON encoder tests:
verbatim `<h1>Hello</h1>`, binary `0x00`/non-UTF8 preserved, exact `Content-Length`, `content-disposition`
header, JSON unchanged); `igniter-web` green (`RespondView` stays JSON); `cargo tree -e normal` has **no**
renderer/frame/ui-kit/export crate; `git diff --check` clean.

**RAW-RESPONSE is now open as a generic seam** — the common dependency for server-side HTML (P3 renderer),
CSV/XLSX/PDF export, and downloads, none implemented here.

**Next:** `LAB-IGNITER-WEB-RENDER-DECISION-P16` (wire `Render { artifact, content_type }` →
`igniter-render-html` → `ServerResponse::raw` `text/html`, end-to-end) → `…-FILE-EXPORT-READINESS-P*` →
`…-EXPORT-XLSX-P*`; streaming gate later.

## Suggested Verification Commands

```bash
cd server/igniter-server && cargo test
cd server/igniter-server && cargo test --features machine
cd server/igniter-web && cargo test
cd server/igniter-server && cargo tree -e normal
git diff --check
```

For the dependency check, explicitly confirm no renderer/frame/export crates are in the normal tree.

## Deliverables

- Code changes in `server/igniter-server` only, unless verify-first proves a tiny compatibility adjustment
  is required elsewhere.
- Tests proving JSON compatibility and raw verbatim wire output.
- Proof doc:
  - `lab-docs/lang/lab-machine-igniter-server-raw-response-p15-v0.md`
- Closing report in this card with exact test counts.

## Notes

This card is the common seam for multiple future paths:

- server-side HTML from `igniter-render-html`;
- CSV/XLSX/PDF export projectors;
- small synchronous downloads;
- later async artifact downloads.

Do not implement any of those here. P15 only teaches the server how to send **already-produced bytes**.

## Next

Likely follow-ups:

- `LAB-IGNITER-WEB-RENDER-DECISION-P16` - IgWeb decision -> `igniter-render-html` -> raw `text/html`.
- `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*` - descriptor-to-bytes export family.
- `LAB-IGNITER-EXPORT-XLSX-P*` - `ReportDescriptor -> .xlsx bytes` proof crate.
- streaming/chunked response gate later, only after bounded buffered raw responses are proven.
