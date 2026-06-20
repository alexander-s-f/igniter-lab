# lab-machine-igniter-server-raw-response-p15-v0 — generic raw response seam

**Card:** `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P15` · **Delegation:** `OPUS-SERVER-RAW-RESPONSE-P15`
**Status:** CLOSED (lab implementation) — `igniter-server` can now send **already-produced bytes
verbatim** via a generic `ResponseBody::Raw { bytes, content_type }`, alongside the unchanged JSON path.
**Format-agnostic: no HTML renderer, no Excel/CSV/PDF, no `send_file`, no filesystem, no streaming, no
compression, no `igniter-render-html`/frame dependency, no canon claim.**
**Authority:** Lab tooling. The common seam the P2 render-middleware readiness named; opens the path for
P3's `igniter-render-html`, export projectors, and downloads — none implemented here.

## Verify-first (confirmed live)

- `ServerResponse.body` was `serde_json::Value`; `ServerResponse::json` set `content-type: application/json`
  (`protocol.rs`).
- `host::encode_response` JSON-serialized **every** body (`serde_json::to_vec(&resp.body)`).
- `effect_host.rs` builds its response with a `ServerResponse { … body: resp.body }` struct literal and
  otherwise reuses `host`/`ServerResponse::json`.
- Middleware short-circuits (`401`/`413`) use `ServerResponse::json`; `igniter-web` maps `Respond` /
  `RespondView` / `InvokeEffect` through `ServerResponse::json`.
- **Body-as-Value reads:** only one production literal (`effect_host.rs`) and one test indexed the body
  as a `Value` (`sparkcrm_app_tests.rs` `response.body["error"]`). All other `.body` reads in tests parse
  the **wire bytes** (unaffected).

## What changed (igniter-server only)

`protocol.rs`:
```rust
pub enum ResponseBody { Json(Value), Raw { bytes: Vec<u8>, content_type: String } }
impl ResponseBody { pub fn as_json(&self) -> Option<&Value> { … } }   // ergonomic accessor for callers

pub struct ServerResponse { pub status: u16, pub headers: BTreeMap<String,String>, pub body: ResponseBody }
impl ServerResponse {
    pub fn json(status, body: Value) -> Self;                         // → ResponseBody::Json (+ content-type header)
    pub fn raw(status, bytes: Vec<u8>, content_type: impl Into<String>) -> Self; // → ResponseBody::Raw
}
```

`host::encode_response` now branches:
```rust
match &resp.body {
    ResponseBody::Json(v)               => serde_json::to_vec(v),                 // unchanged JSON path
    ResponseBody::Raw { bytes, content_type } => { head += "content-type: {ct}"; bytes.clone() } // verbatim
}
// status line + headers + (raw's own content-type) + Content-Length(body.len()) + body bytes
```

Compatibility touches: `effect_host.rs` wraps its ingress body as `ResponseBody::Json(resp.body)`;
`sparkcrm_app_tests.rs` reads `response.body.as_json().unwrap()["error"]`. No other call site changed —
all construction flows through `ServerResponse::json`.

### Design notes

- **Content-type ownership.** JSON keeps content-type in `headers` (set by `json`); `raw` carries its
  content-type in the `Raw` field (set verbatim by the encoder). `raw()` does NOT also put content-type in
  `headers`, so there is no duplicate header. Other headers (e.g. `content-disposition`) flow through
  `headers` normally — so a download is just `raw()` + a `content-disposition` header, **no special
  download API** (per the card).
- **No reserialization for raw:** the bytes are `bytes.clone()` straight into the wire; `Content-Length`
  = `body.len()` (exact raw length); binary-safe (`Vec<u8>`), preserving `0x00` and non-UTF8 bytes.
- The server stays **format-agnostic**: it ships bytes a projector/exporter already produced; it never
  produces, renders, reads, or interprets them.

## Tests & commands — exact counts

```text
$ cd server/igniter-server && cargo test                    → all green; +4 new
$ cd server/igniter-server && cargo test --features machine → all green (incl. effect_host); 0 failed
$ cd server/igniter-web    && cargo test                    → all green (RespondView stays JSON)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit|xlsx|export'
                                                            → (no output) — server format-agnostic
$ git diff --check                                          → clean
```

New tests (4):
- `protocol::tests::raw_helper_carries_bytes_and_content_type` — `raw()` builds `ResponseBody::Raw`;
  `as_json()` is `None`; `json()` body `as_json()` round-trips.
- `host::tests::json_response_encodes_unchanged` — JSON wire body = `{"ok":true}` (not double-wrapped),
  `content-type: application/json`, exact `Content-Length`.
- `host::tests::raw_html_is_written_verbatim` — wire body is **exactly** `<h1>Hello</h1>` (no quoting/
  escaping/`{"body":…}`), `content-type: text/html; charset=utf-8`, `Content-Length: 14`, no JSON type.
- `host::tests::raw_preserves_binary_bytes_including_nul_and_non_utf8` — `[0x00,0xFF,0x42,0xFE,\n]`
  preserved exactly with the right length.
- `host::tests::raw_carries_content_disposition_as_a_normal_header` — `content-disposition` set as a plain
  header appears on the wire next to `content-type: text/csv`.

## Acceptance — mapping

- [x] JSON behavior unchanged: `json(200,{ok:true})` → JSON wire bytes, `application/json`
      (`json_response_encodes_unchanged`).
- [x] Raw verbatim: `<h1>Hello</h1>` → wire body exactly that, not `"…"`, not `{"body":…}`
      (`raw_html_is_written_verbatim`).
- [x] Raw `Content-Length` = exact byte length (raw tests).
- [x] Raw `content-type` preserved (`text/html; charset=utf-8`).
- [x] Binary bytes incl `0x00`/non-UTF8 preserved (`raw_preserves_binary_bytes_…`).
- [x] `Content-Disposition` is a normal header; no special download API
      (`raw_carries_content_disposition_…`).
- [x] Middleware JSON short-circuit tests still pass (`401`/`413` via `json`).
- [x] `effect_host` machine-feature tests pass (`--features machine` green).
- [x] `igniter-web` tests pass; `RespondView` stays JSON.
- [x] Normal dep tree gains no renderer/frame/ui-kit/export crate.
- [x] `git diff --check` clean.

## Closed scope (honored)

No `igniter-render-html` dependency, no IgWeb render decision, no HTML/Excel/CSV/PDF code, no
`send_file(path)`, no filesystem reads, no streaming/chunked, no compression, no public-listener/deploy
change, no route table, no DB/effect-host *work*, no canon claim. P15 only teaches the server to send
**already-produced bytes**.

## Next

1. **`LAB-IGNITER-WEB-RENDER-DECISION-P16`** — wire an explicit IgWeb `Render { artifact, content_type }`
   decision through `igniter-web` → `igniter-render-html` (P3) → `ServerResponse::raw` → `text/html`,
   end-to-end loopback. (igniter-web gains the renderer dep; server core stays clean.)
2. **`LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*`** — the descriptor→bytes export family
   (ReportDescriptor → xlsx/csv/pdf), sync inline vs async-generate-then-download.
3. **`LAB-IGNITER-EXPORT-XLSX-P*`** — `ReportDescriptor → .xlsx` projector crate (host-owned, like
   `igniter-render-html`).
4. streaming/chunked response gate **later**, only after bounded buffered raw responses are proven.

---

*Lab implementation. Compiled 2026-06-20; igniter-server default + `--features machine` green (+4 raw/JSON
encoder tests), igniter-web green, server normal deps renderer/frame/export-free, `git diff --check` clean.
No renderer, export, file-serving, streaming, or canon change — only the generic raw-byte seam.*
