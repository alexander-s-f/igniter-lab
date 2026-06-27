# IGNITER-WEB-CORE-FOUNDATION-AUDIT-P1 - fresh verify-first audit of the web layer (render-html + igniter-web + igniter-server)

Status: OPEN - findings (no code changed)
Lane: igniter-lab / server / web-layer / foundation-hardening
Type: audit / fresh verify-first (security-focused)
Date: 2026-06-26
Skill: idd-agent-protocol

> Refresh note 2026-06-27: this remains a 2026-06-26 audit snapshot. Some
> findings below have since closed; route current work through
> `lab-docs/igniter-foundation-hardening-roadmap-p1.md` and
> `lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md`, not the
> `Status: OPEN` line alone.

## Onboarding

Lab/frontier evidence, not authority. Code-first verify-first audit of the **web
layer = 3 crates**: `igniter-web` (app builder + data projection, ~5.5k LOC),
`igniter-render-html` (the ViewArtifact→HTML projector / **the XSS-critical
surface**, 351 LOC — read in full first-hand), `igniter-server` (Rack-like
transport/routing, ~1.3k LOC). 4 parallel subagent audits + a first-hand read of
render-html and `IMPLEMENTED_SURFACE.md`. Do NOT lean on docs; the code is truth.

## Executive Decision

```text
decision=AUDIT - the web layer is the best-DESIGNED security surface in the series (render-html is safe-by-construction; allowlists default-closed; intent bridge host-bound; routing app-owned) but the enforcement gaps repeat the family pattern
severity=high: 1 real XSS (safe_url control-char bypass) + web effect authority forgeable+never-expiring + igniter-server transport disease (unbounded/untimed/plaintext) + server auth OFF-by-default & UNWIRED on the effect path
good_news=render-html escapes every leaf + no raw-HTML node + fail-closed unknown nodes (one bug); data-projection descriptor->escaped-bytes seam is injection-safe; source/field/op allowlists exact-match + default-CLOSED; intent bridge cannot SQLi or widen columns (host-bound); igniter-agent bin is a GOOD posture (read-only, loopback, no IO authority); routing app-owned (no host path-normalization bypass); parsers panic-hardened
root_cause=5th audit pattern again - model/design right, enforcement thin/optional/unwired. Most acute: signed-passport dead at the web seam (one mint point), server auth opt-in+fail-open+bypassed on machine-mode, safe_url claim defeated by control chars
keystone=fix safe_url (strip/reject C0 controls) + wire the signed passport at the ONE web mint point + make body-cap/timeout/auth structural (default-on in compose + read loop) + call compose() on machine-mode
next=IGNITER-RENDER-HTML-SAFE-URL-P2 + IGNITER-WEB-WIRE-SIGNED-EFFECT-PASSPORT-P2 + IGNITER-SERVER-INBOUND-HARDENING-P2 + IGNITER-SERVER-AUTH-STRUCTURAL-P2
architectural_decision_needed=yes - loopback invariant is again load-bearing; "bind non-loopback" must be a security gate (same as the machine audit)
```

## GOOD NEWS — the best-designed security surface in the series

- **`igniter-render-html` is safe-by-construction.** Input is a STRUCTURED
  ViewArtifact (a closed node vocabulary), never a template string; every leaf
  (label/id/action/text/options/leads/title) routes through `escape()` which covers
  all five HTML-significant chars (`& < > " '`) and is correct in both element-text
  and double-quoted-attribute contexts; **there is NO raw-HTML node**; unknown node
  kinds **fail closed** (`UnsupportedNode`); it never panics (Result everywhere) and
  error messages carry the node *kind/key*, never the artifact body
  (`render-html/src/lib.rs:58,238,261`). This is the right design — the rest of the
  series should emulate it.
- **The data-projection seam is injection-safe.** Rows cross to the view only as
  structured values (`rows`/`rows_json:String`), never as pre-built markup; HTML is
  produced solely in render-html → escaped. The `rows_json:String` flattening does
  not let HTML survive as trusted text (it is re-parsed by `.ig`, never concatenated
  into markup).
- **Host allowlists are real, exact-match, and default-CLOSED** — source/field/op
  gates enforced in the machine executor *before* any adapter call (empty allowlist
  denies all; `postgres_read.rs:471/486/493`). The **intent bridge is the strongest
  link**: values bound `$1..$n`, columns/target host-bound (not intent-controlled),
  raw-SQL refused, extra intent keys silently ignored — **no SQLi, no column
  widening** (`host_binding.rs:170`).
- **`igniter-agent` bin is a GOOD posture** — read-only/bounded stdio tools,
  loopback-pinned, max-requests clamped, env values never echoed, **no IO authority
  added** (better than the machine's no-auth MCP).
- **Routing is app-owned** (host holds no route table → no host-side path-
  normalization/authz-bypass surface); **reload is safe-by-construction** (explicit
  `Arc` swap, no dynamic code load, snapshot-then-serve avoids TOCTOU); parsers are
  **panic-hardened** on malformed bytes (materially better than the machine ingress).

## Root cause (5th audit running, same family)

**Design/model right, enforcement thin/optional/unwired.** render-html is sound but
its one URL check is defeatable; allowlists are default-closed but the effect passport
is a static forgeable never-expiring host token; routing is clean but the server's auth
is opt-in, fail-open, and *not wired at all on the effect-executing machine-mode path*.

## BLOCKERS

### A. XSS — the one real injection in render-html

**B-A1. `safe_url` is bypassable via an embedded control character → `javascript:`
executes.** `safe_url` only validates the scheme when the chars before `:` match the
URI scheme charset (`render-html/src/lib.rs:82-90`). An embedded C0 control
(`java\nscript:`, `java\tscript:`, `java\rscript:`) breaks that charset → `is_scheme =
false` → the value is treated as **relative** and passed through `escape()` (which does
NOT touch control chars or `:`). The emitted `<a href="java&#10;script:…">` is then
parsed by the browser, which **strips `\t`/`\r`/`\n` from URLs before scheme detection**
→ `javascript:…` runs on click. This **defeats the crate's own stated guarantee** ("URL
fails closed on non-`http(s)`/relative schemes"). **Reachable** when a `link` node's
`action`/href carries untrusted data (the link node is implemented;
`IMPLEMENTED_SURFACE` shows `MakeLink`/`TodoLinkHtml`/`TodoNavHtml`). Fix: reject or
strip C0 controls (and normalize) **before** scheme detection.

### B. Web effect authority — forgeable + never-expiring

**B-B1. The web write effect runs under a static, host-fabricated, never-expiring
passport verified by the FORGEABLE `verify_passport`.** `host_binding.rs:414-422` mints
ONE `CapabilityPassport { subject:"host", scopes:["write"], expires_at: f64::MAX,
revoked:false, evidence_digest:"host-owned" }` at boot and hands it to every effect; the
machine verifies it with the unsigned field-only `verify_passport` while
`verify_passport_signed` (the blake3-MAC path) stays dead code. The **inbound bearer
never authorizes the effect** — it only maps to the coordination passport for capsule
invoke. So this confirms the machine audit AT the web seam, and the web layer is the
**cleanest place in the workspace to wire the signed path** (exactly one effect-passport
mint point). *(Mitigant: the inbound token gate IS fail-closed — no configured token =
no write path; anonymous → 401. So it is "forgeable authority," not "open write.")*

### C. igniter-server transport — the machine-ingress disease, repeated

**B-C1. Unbounded request body → OOM.** `read_request`/`read_server_request` loop
`while buf.len() < need` where `need` derives from the attacker-controlled
`Content-Length` with no ceiling (`host.rs:213`, `effect_host.rs:156`); `BodyLimitApp`
runs *after* the body is already in memory. **B-C2. No read timeout → slowloris**
(no `set_read_timeout` anywhere; the sequential loop means one slow client wedges the
whole server). **B-C3. Plaintext only — no inbound TLS** (raw `TcpStream`; bearer
tokens + bodies in cleartext). All three are latent behind the loopback pin and
activate on a non-loopback bind.

### D. igniter-server auth — off by default, fail-open, unwired on the effect path

**B-D1. The effect-executing machine-mode path composes NO auth.** `compose()` (which
wraps `AuthTokenApp`) is only on the sync `build_app_from_dir` path; `run_machine_mode`
serves the raw `loaded` app and **never calls `compose()`** (`igweb-serve.rs:300/328`)
→ no server-layer bearer check before a request reaches `InvokeEffect`.

**B-D2. `AuthTokenApp` fails OPEN on a missing env var.** `std::env::var(name)
.unwrap_or_default()` → unset secret ⇒ `expected_token == ""` ⇒ a client sending
`Authorization: Bearer ` (empty) authenticates (`igniter-web lib.rs:912`). Misconfig =
open. Plus the compare is non-constant-time and prefix-lenient (bare token without
`Bearer ` matches), and the injected `x-auth-ok: true` marker is client-spoofable
(inbound copies not stripped, `middleware.rs:113`).

## PROBLEMS

- **Forgeable pagination cursor, no host scope backstop.** The keyset `after` cursor is
  a plain query param crossed verbatim; the host signs/checks nothing
  (`lib.rs:394`). Tenant/scope protection rests entirely on the app's WHERE clause —
  no host net. (`carry` is correctly opaque.)
- **Legacy `rows_json` type-erosion + trust-the-result.** The stringly path silently
  falls back to stringifying the whole outcome (`read_dispatch.rs:194`); `DatasetMeta.
  count`/`truncated` are read from the executor result and NOT cross-checked against the
  materialized rows (a wrong `count` lies to the view). The typed path is solid.
- **CL.TE request smuggling latent.** The hand-rolled parser honors only
  `Content-Length`, **ignores `Transfer-Encoding: chunked`**, and keeps the last of
  duplicate `Content-Length` headers (`host.rs:179`) → a classic CL.TE primitive behind
  any chunked-aware proxy.
- **`reload` re-validates no authority + `RwLock` poison DoS.** A `swap` can replace the
  stack with one lacking `AuthTokenApp`; no identity gate on the swapped app; a panic
  while holding the reload lock bricks every later request (`reload.rs:33/39`).
- **Build-path injection of operator-controlled `entry`/manifest `sources`** into the
  temp build dir / `app_dir` join (`lib.rs:256`, `resolve_sources`) — no `..`/absolute
  reject (operator-trust-bounded, but unsanitized).
- **Two-path dispatch capability cliff + `block_on` footgun.** The sync `dispatch`
  adapter 500s on `ReadThen` (no read host) while `dispatch_with_read` enforces policy;
  and `IgWebServerApp::call` does `rt.block_on` → calling it from inside a tokio runtime
  panics (`lib.rs:307`).
- **Surrogate id is client-CHOOSABLE** (`blake3(method,path,idempotency_key)`, all
  attacker-controlled) — safe ONLY because nothing scopes authority on it; the
  invariant "never scope on surrogate_id" is a comment, not enforced (`lib.rs:328`).
- **`ResolvedHostConfig` derives `Debug`** — a stray `{:?}` would print the resolved DSN/
  passport; redaction relies on a comment, not a redacting `Debug` impl (`host_config.rs:112`).
- **`row_limit` / `policy` has no sane ceiling at construction** → a misconfigured large
  cap + real adapter is a config-shaped OOM; reads fully materialize (no streaming).
- **safe_url allows protocol-relative `//host`** → cross-origin navigation / open-redirect
  via a link (not XSS, but unexpected).

## INSIGHTS

- **I1. render-html is the model the rest of the series should emulate** — closed
  vocabulary + escape-every-leaf + scheme-allowlist + fail-closed-unknown + non-panicking.
  Its single bug (B-A1) is a missing control-char normalization, not a design flaw.
- **I2. The loopback invariant is load-bearing AGAIN** (same as the machine): B-C1/C2/C3
  and most of the auth exposure are dormant on `127.0.0.1` and live on a public bind.
  `IMPLEMENTED_SURFACE` says loopback-only / non-loopback refused — but that is a CLI/
  policy pin (`parse_loopback_addr`), not a structural server invariant. **"Bind
  non-loopback" must be the same security gate recommended for the machine.**
- **I3. The web seam is the cleanest place to fix the forgeable-passport blocker** — one
  effect-passport mint point (`host_binding.rs:414`), one call-site swap to the
  already-built signed verifier. The web layer can demonstrate the signed path end-to-end.
- **I4. The strong links are genuinely strong** — the intent bridge (host-bound columns,
  no SQLi), the default-closed allowlists, the app-owned routing, and the agent bin are
  real positives; the gaps are at the transport edge and the (unwired) authority wiring.

## SUPER-COOL (high-leverage)

- **S1. Fix `safe_url` once, kill the XSS class.** Strip/reject all C0 controls (and
  trim Unicode whitespace) **before** scheme detection, and reject protocol-relative
  `//host` unless intended. ~5 lines in the one URL function closes B-A1 and the
  open-redirect PROBLEM. Add a fuzz test over the scheme (`java\tscript:`, `\x01…`,
  `//evil`) so it stays closed.
- **S2. Wire the signed passport at the one web mint point.** Replace the static `ep`
  (`host_binding.rs:414`) with a `verify_passport_signed`-backed, bearer-derived,
  scoped, EXPIRING passport. Closes B-B1 for the whole web write path in one focused
  change and turns the audit receipt into a real attribution chain (the `correlation_id`
  is already the carrier).
- **S3. Make body-cap / timeout / auth STRUCTURAL, and wire compose() into machine-mode.**
  Push a `max_body_bytes` check into the read loop *before* allocation (413), add a
  shared `harden(stream)` read-timeout helper, flip `compose()` to default-on
  (body-limit + fail-CLOSED auth) AND call it on `run_machine_mode`. Closes
  B-C1/B-C2/B-D1/B-D2 with a handful of shared lines (the agent bin already sets a 10s
  child-read timeout — mirror it).
- **S4. Host-signed pagination cursor** (HMAC `{source,last_key,scope}`, opaque to `.ig`
  like `carry`) → forge-and-scan-beyond-scope becomes a fail-closed `Denied`, giving the
  host a real tenant-scope backstop instead of trusting the app's WHERE clause.
- **S5. Promote `count`/`truncated` to proof** (derive from the materialized rows; treat
  a divergent executor count as a schema fault) and **retire the legacy `rows_json`
  erosion branch** behind the typed crossing — the projection boundary becomes uniformly
  "typed-or-denied."
- **S6. "Bind non-loopback" as an explicit security gate** (make `loopback_only`
  structural; require a checklist token — signed passport wired, inbound TLS, body-cap,
  timeout, fail-closed auth — before a public bind is even constructible). Same keystone
  as the machine audit; the two share the gate.

## Keystone recommendation

- **IGNITER-RENDER-HTML-SAFE-URL-P2** — S1 (control-char normalization + fuzz). Closes
  the one real XSS.
- **IGNITER-WEB-WIRE-SIGNED-EFFECT-PASSPORT-P2** — S2. Closes B-B1 at the one mint point.
- **IGNITER-SERVER-INBOUND-HARDENING-P2** — S3 (body-cap + timeout + TLS-ready). Closes
  B-C1/B-C2/B-C3.
- **IGNITER-SERVER-AUTH-STRUCTURAL-P2** — default-on fail-closed auth + compose() on
  machine-mode (S3). Closes B-D1/B-D2.

The design is the strongest in the series; the work is **closing one URL gap, wiring the
proven authority, and making the transport defaults structural** — not a redesign.

## Boundary / not covered

Lab evidence only; no code changed. This audit covers the web LAYER (3 crates). It
completes the foundation-audit sweep (TBackend → compiler → stdlib → VM → machine → web;
sibling docs in `lab-docs/`). The B-A1 safe_url bypass was found by first-hand read; its
browser-side reachability (control-char stripping in href parsing) is asserted from
known browser URL behavior, not executed here — worth a real browser repro before fix
sign-off, though the filter-bypass logic in `safe_url` is verified in code regardless.
