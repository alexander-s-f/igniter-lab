# Card: LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P11 — assets and non-API app surface

**Lane:** standard / readiness-design
**Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-18
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
