# Card: LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P11 — assets and non-API app surface

**Lane:** standard / readiness-design
**Skill:** idd-agent-protocol
**Status:** CLOSED (readiness packet)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab-only design/readiness. No implementation. No assets protocol authority.

## Why this card exists

`igniter-server` now supports external `ServerApp` examples (P10), middleware (P8), reload (P4), and
the serving loop (P5). The next architectural question is whether the same app protocol can cover
non-API apps: operator consoles, VoIP UI shells, static manifests, small browser assets, or future
Frame/console artifacts.

The risk: accidentally turning `igniter-server` into a web framework with route config, content-type
policy, caching, range requests, and asset pipelines in core. This card decides the v0 boundary before
any implementation.

## Read first

- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/examples/server_app_basic.rs`
- `lab-docs/lang/lab-machine-igniter-server-extensions-readiness-p7-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-example-app-p10-v0.md`
- `lab-docs/lang/lab-frame-binding-console-live-demo-p21-v0.md` (if present; only for UI-context, not authority)

## Goal

Write a readiness packet answering how assets/non-API responses should fit into `ServerApp` v0:

- can an app serve static-like bytes today via `Respond`?
- what should core support now vs defer?
- what would a future `AssetManifest` need before becoming real?
- how do UI/frame artifacts stay app-owned rather than server-owned?

This is design only. Do not implement an assets API.

## Required questions

1. **Current capability.**
   - What does `ServerResponse` support today?
   - Can an app return HTML/JSON/text/static bytes through `Respond` without new protocol?
   - What are the limits (body type, headers, content-type)?

2. **Core boundary.**
   - What belongs in `igniter-server` core for assets?
   - What must remain in the app or external static server?
   - Why should core not own an asset pipeline in v0?

3. **Three candidate shapes.** Compare:
   - App returns `Respond` with body + headers (v0 likely answer).
   - Future `AssetManifest` trait or `ServerDecision::Asset`.
   - External static asset server/CDN next to Igniter server.

4. **UI and Frame artifacts.**
   - How would a future operator console / Frame app expose assets?
   - What is app-owned vs server-owned?
   - Avoid importing `igniter-frame`/`igniter-console` into server core.

5. **Content types and caching.**
   - Should content-type be explicit app response headers?
   - Are ETag/cache/range requests in scope for v0?
   - What minimum evidence would justify adding generic helpers later?

6. **Middleware interaction.**
   - How do P8 `Trace/Auth/BodyLimit` wrappers apply to assets?
   - Should middleware be content-aware? (Likely no, except generic size/auth.)

7. **Security / live gate.**
   - Public listener, static file path traversal, directory serving, credentials, and external assets
     must stay gated/deferred.
   - If file serving is ever implemented, name required traversal/root checks.

8. **Testing shape for a future implementation.**
   - What would a tiny proof look like if implemented later?
   - Name exact candidate files/tests but do not create them.

9. **What is explicitly rejected.**
   - No route table in core.
   - No auto-directory serving.
   - No HTML framework or template engine in core.
   - No Frame/console dependency in core.

10. **Next card recommendation.**
    - One bounded implementation card max, only if readiness justifies it.
    - Otherwise recommend stopping at v0 `Respond` guidance.

## Deliverable

Readiness packet:

`lab-docs/lang/lab-machine-igniter-server-assets-readiness-p11-v0.md`

Closing report in this card with:

- recommended v0 asset stance;
- rejected/deferred surfaces;
- next route or explicit no-op decision.

## Acceptance

- [ ] Packet answers all 10 required question groups.
- [ ] Packet keeps assets/UI domain outside server core.
- [ ] Packet distinguishes `Respond` today from future assets protocol.
- [ ] Packet covers content-type/cache/range/path traversal boundaries.
- [ ] Packet names what would justify future implementation.
- [ ] Packet proposes no live/public/static-directory work.
- [ ] No code changes.
- [ ] No new crates.
- [ ] No dependency on frame/console crates.

## Closed surfaces

- No code.
- No assets protocol implementation.
- No static directory serving.
- No route table.
- No public listener.
- No file-system serving.
- No Frame/console dependency in server core.
- No live network/CDN.
- No credentials.
- No canon claim.

## Suggested conclusion shape

Likely v0:

```text
ServerApp returns Respond { status, headers, body }
  -> app owns content type and body shape
  -> middleware remains generic
  -> core does not serve directories or own assets manifests yet
  -> future AssetManifest requires a separate readiness/implementation gate
```

Verify against live `ServerResponse` before finalizing.

---

## Closing report — 2026-06-18

**Outcome:** Readiness packet delivered, answering all 10 question groups, grounded in the live
`ServerResponse` + host wire encoder. Design only — no code, no assets protocol, no new crate, no
frame/console dependency.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-assets-readiness-p11-v0.md`.

**Load-bearing finding (verified):** `ServerResponse { status, headers: BTreeMap, body: serde_json::
Value }` and `host::encode_response` ALWAYS does `serde_json::to_vec(body)`. So an app can set any
status + any headers (incl. `content-type`) + a JSON body, but **the wire body is always JSON-
serialized** → JSON/manifests are first-class, but **verbatim HTML/binary bytes are NOT servable today**
(HTML in a `Value::String` arrives JSON-quoted/escaped).

**Recommended v0 stance:** apps serve **JSON through `Respond`** (manifests, data, JSON-carried UI
descriptors); app owns content-type via headers; middleware stays generic (size/auth/correlation, never
content-aware); core owns **no** asset pipeline. Verbatim non-JSON bytes → deferred behind a protocol
gate; production static assets → an external static server.

**Rejected / deferred:** route table in core; auto-directory serving/index; HTML framework/template
engine in core; `igniter-frame`/`igniter-console` dependency in core (UI app → server, never reverse);
ETag/cache/range machinery; filesystem serving (if ever built: canonicalized-path-within-root, no `..`
traversal, no symlink escape, no directory listing, extension allowlist — named, not implemented).

**UI/Frame:** a future operator console / Frame app is an APP that imports frame/console itself and
returns its projection (JSON today; verbatim SVG/HTML once the raw-body gate exists) — never a core
feature.

**Next route:** **STOP at v0 `Respond`(JSON) — no implementation card now.** One named, trigger-gated
future route only: `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*` (add a raw-bytes body variant + wire
branch + tests), opened **only** when a real in-tree app must emit verbatim HTML/SVG/binary.

**Acceptance:** all boxes met — 10 groups answered; assets/UI kept outside core; `Respond`-today vs
future-assets-protocol distinguished; content-type/cache/range/path-traversal boundaries covered;
future-implementation triggers named; no live/public/static-directory work proposed; no code; no new
crates; no frame/console dependency.
