# lab-machine-igniter-server-assets-readiness-p11-v0 — assets & non-API app surface

**Card:** `LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P11`
**Status:** READINESS / DESIGN (v0, recommended) — how assets / non-API responses fit `ServerApp`
without turning core into a web framework. **Design only. No code, no assets protocol, no static
directory serving, no Frame/console dependency in core, no live/public/CDN, no canon claim.**
**Authority:** Lab-only. Grounded in the live `ServerResponse` + host wire encoding.

---

## 0. Live surface (verified)

```rust
// src/protocol.rs
pub struct ServerResponse { pub status: u16, pub headers: BTreeMap<String,String>, pub body: Value }
impl ServerResponse { pub fn json(status, body) -> Self { /* sets content-type: application/json */ } }

// src/host.rs — the wire encoder
fn encode_response(resp) -> Vec<u8> {
    let body = serde_json::to_vec(&resp.body)...;   // <-- the body is ALWAYS JSON-serialized
    // status line + every resp.headers entry + Content-Length + body
}
```

The single load-bearing fact for this card: **the wire body is `serde_json::to_vec(body)`** — a
JSON-serialized `Value`, always.

---

## 1. Current capability (Q1)

Today, through `Respond { response: ServerResponse }`, an app can set:
- any `status` (u16);
- any **headers** (`BTreeMap<String,String>`) — including an explicit `content-type`;
- a **JSON `Value` body**.

So **JSON is first-class**: an app can serve a JSON manifest, a data document, or a structured UI
descriptor through `Respond` today, with no protocol change. It can also set `content-type` to
whatever it likes.

**The hard limit:** because `encode_response` always does `serde_json::to_vec(body)`, the bytes on the
wire are *always* a JSON serialization. Putting HTML in a `Value::String` (`body = "<html>…"`) yields a
**JSON-quoted, escaped** string on the wire (`"<html>…"` with `\"` escapes), not verbatim HTML — a
browser told `content-type: text/html` would receive quoted junk. Raw binary is worse (a JSON array or
a base64 string the app encodes). **Verbatim HTML / raw binary bytes are NOT servable today.** That is
the boundary every answer below respects.

---

## 2. Core boundary (Q2)

**In core (now):** the generic `ServerResponse` (status/headers/JSON body) + the wire encoder. That's
the whole asset surface core should own in v0.

**Outside core (app or external static server):** content-type policy, asset bodies, HTML/templates,
binary blobs, directory layout, caching strategy.

**Why core must NOT own an asset pipeline in v0:** content-type negotiation, caching/ETag, range
requests, directory listing, and a file root are precisely the web-framework surface the card warns
against. Each is a policy with security and correctness weight; pulling them into core would re-make
`igniter-server` into the config-driven framework P1–P6 deliberately avoided. Apps that need real
static/binary assets use an external static server today.

---

## 3. Three candidate shapes (Q3)

| Shape | What it enables | Verdict |
|---|---|---|
| **(A) App returns `Respond` with JSON body + explicit headers** | JSON manifests, data, structured/JSON UI descriptors; app owns content-type | **v0 ANSWER.** Works now, zero protocol change. Limit: no verbatim non-JSON bytes. |
| **(B) Future raw-body: `ServerResponse` body as `Json(Value) \| Raw{ bytes, content_type }`, or a `ServerDecision::Asset`** | verbatim HTML / SVG / binary served byte-exact | **DEFERRED behind a protocol gate.** The only correct way to emit non-JSON bytes; needs a small, deliberate protocol change + tests (Q8). Not v0. |
| **(C) External static asset server / CDN beside the Igniter server** | real static sites, large binaries, caching/range at scale | **Recommended for production static**, out of `igniter-server` scope. |

Recommendation: **v0 = (A)** for JSON/manifests; **defer (B)** until a concrete app needs verbatim
non-JSON bytes; **(C)** for production static assets. Do not implement (B) speculatively.

---

## 4. UI & Frame artifacts (Q4)

A future operator console / Frame app is an **app**, not a server feature. It imports
`igniter-frame` / `igniter-console` *itself* and returns its projection through `Respond`:
- **today:** the frame/console projection as a **JSON** descriptor (e.g. the frame's node tree or an
  SVG string carried as JSON) — the consumer renders it;
- **once (B) exists:** the projected SVG/HTML served as verbatim bytes.

**App-owned:** the frame model, projection, render host, SVG/HTML. **Server-owned:** nothing
UI-specific. **Hard rule:** `igniter-server` core must **never** depend on `igniter-frame` or
`igniter-console` — the dependency direction is *UI app → igniter-server*, never the reverse (the P6/P7
boundary). The frame wave already keeps its core machine-free; the server stays UI-free symmetrically.

---

## 5. Content types & caching (Q5)

- **Content-type:** an **explicit app response header** — already supported (`headers` is open;
  `ServerResponse::json` just defaults it to `application/json`). No core machinery needed.
- **ETag / cache-control / range / conditional requests:** **OUT of v0 scope.** They are
  web-framework concerns with real correctness weight; an app may set `cache-control`/`etag` headers
  itself if it wants, but core neither computes nor enforces them.
- **Minimum evidence to justify generic helpers later:** a real, in-tree app (e.g. an operator
  console) with a measured need to serve large or cacheable assets through the server rather than an
  external static server. Until that exists, helpers are speculative and rejected.

---

## 6. Middleware interaction (Q6)

P8 wrappers (`TraceApp`/`AuthTokenApp`/`BodyLimitApp`) are plain `ServerApp` wrappers and apply
**uniformly** to asset responses too — Trace decorates any `Respond` with a correlation id, Auth
short-circuits before the app, BodyLimit caps the *request* body. **Middleware must NOT become
content-aware:** no content-type routing, no body transform/compression, no asset-specific branches —
that is the route-table/framework drift the P8 design forbids. Generic size/auth/correlation only.
(Response compression, if ever wanted, is a host-transport concern, not app middleware.)

---

## 7. Security / live gate (Q7)

Gated / deferred (never inferred from this readiness): public (non-loopback) listener; file-system
serving; directory listing; path-based file resolution; credentials; external assets/CDN.

**If file-backed serving is ever implemented (future, gated), the required checks are:**
- resolve to an absolute, **canonicalized** path and confirm it stays within a single configured root
  (reject any `..` traversal);
- reject symlink escape out of the root;
- **deny directory listing** by default (no auto-index);
- serve only an explicit allowlist of extensions → content-types;
- never let the request path alone select a filesystem path without the above.

Name them; do not implement. v0 has **no** filesystem surface at all.

---

## 8. Testing shape for a future implementation (Q8 — named, NOT created)

If shape (B) (raw bytes) is implemented later:

| Path | Role |
|---|---|
| `src/protocol.rs` (extend) or `src/asset.rs` | a raw-body variant (`Raw { bytes, content_type }`) or `ServerDecision::Asset` + wire encoder branch that writes bytes **without** JSON serialization |
| `tests/asset_tests.rs` | proofs |

Expected tests: an app returns raw HTML → the wire body bytes **equal the input verbatim** (no JSON
quoting/escaping); `content-type` is preserved exactly; `BodyLimit`/`Auth` middleware still apply; if
file-backed, a `..` traversal request is rejected and directory listing is denied. Commands:
`cargo test`, `cargo test --features machine`.

---

## 9. Explicitly rejected (Q9)

- **No route table in core** (routing stays in `ServerApp::call`).
- **No auto-directory serving / directory index.**
- **No HTML framework or template engine in core.**
- **No `igniter-frame` / `igniter-console` dependency in server core.**
- No content-type negotiation, ETag/cache/range machinery, or asset pipeline in v0 core.

---

## 10. Next card (Q10)

**Recommended: STOP at v0 `Respond`(JSON) guidance — no implementation card now.** Apps serve JSON
(manifests, data, JSON-carried UI descriptors) through `Respond` today; verbatim non-JSON bytes and
production static assets are handled by an external static server until a concrete need appears.

The single named future gate (trigger-based, NOT proposed as work now):
**`LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*`** — add shape (B) (a raw-bytes response body variant +
wire-encoder branch + the Q8 tests). Open it **only** when a real in-tree app must emit verbatim
HTML/SVG/binary through the server (not before).

---

## Boundary recap

- v0: `ServerApp` returns `Respond { status, headers, JSON body }`; the app owns content-type and body
  shape. JSON/manifests work today; verbatim HTML/binary do **not** (wire body is always JSON).
- Core owns no asset pipeline; assets/UI/content domain stays in apps or an external static server.
- Middleware stays generic (size/auth/correlation), never content-aware.
- File serving, caching/range, public listener, CDN, and any Frame/console dependency stay
  rejected/deferred behind a human/protocol gate.
- No implementation now; the one named future route is `RAW-RESPONSE-P*`, triggered by a real need.

*Readiness/design only. Compiled 2026-06-18. Verified against the live `ServerResponse` + host encoder.*
