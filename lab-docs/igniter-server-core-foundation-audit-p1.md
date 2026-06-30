# IGNITER-SERVER-CORE-FOUNDATION-AUDIT-P1 - fresh verify-first audit of the Rack-like server core

Status: OPEN - findings (no code changed)
Lane: igniter-lab / server / igniter-server / foundation-hardening
Type: audit / fresh verify-first (security-focused, first-hand read)
Date: 2026-06-26
Skill: idd-agent-protocol

> Refresh note 2026-06-27: this remains a 2026-06-26 audit snapshot. Some
> findings below have since closed; route current work through
> `lab-docs/igniter-foundation-hardening-roadmap-p1.md` and
> `lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md`, not the
> `Status: OPEN` line alone.

## Onboarding

Lab/frontier evidence, not authority. Code-first verify-first audit of
`igniter-server` (Rack-like transport/routing core, ~1.3k LOC across
`host.rs`/`protocol.rs`/`effect_host.rs`/`middleware.rs`/`serving_loop.rs`/
`reload.rs`/`fixture.rs`/bin). **Read in full FIRST-HAND** (not delegated) — this
supersedes/deepens the `igniter-server` section of the web-layer audit. Do NOT lean
on docs; the code is truth.

## Executive Decision

```text
decision=AUDIT - the most DESIGN-disciplined crate in the series (protocol cannot carry effect authority; host owns transport-only; routing app-owned; reload snapshot-safe; parser panic-hardened) — but the transport edge repeats the family's plaintext/unbounded/untimed trio and auth is opt-in + fail-open + UNWIRED on the effect path
severity=transport blockers all LATENT behind loopback, but this crate does NOT enforce loopback by default (it disclaims deployment policy → the gate is the caller's)
good_news=PROTOCOL HYGIENE is the best in the series: ServerDecision carries NO capability_id/operation/scope so an app STRUCTURALLY cannot forge effect authority; AppIdentity is observation-only; host holds no route table (no path-normalization bypass); reload is request-start-pinned + lock-not-held-across-call; parser is unwrap-free/panic-hardened; default build is OBSERVE-ONLY (effects only under the `machine` feature)
root_cause=same family pattern: clean model, thin/optional/unwired enforcement (auth opt-in + fail-open-on-empty-token; compose() not called on machine-mode; no inbound caps/timeout/TLS; loopback guard off-by-default)
keystone=push body-cap+timeout into the shared read loop; make auth structural (fail-closed, constant-time, compose-on-machine-mode); make loopback_only structural; inbound TLS
next=IGNITER-SERVER-INBOUND-READ-HARDENING-P2 + IGNITER-SERVER-AUTH-STRUCTURAL-P2 + IGNITER-SERVER-LOOPBACK-GATE-P2
architectural_decision_needed=yes - this crate is the right altitude for the workspace-wide "bind non-loopback = security gate"
```

## GOOD NEWS — the best protocol hygiene in the series (first-hand verified)

- **An app cannot forge effect authority — the protocol has no field for it.**
  `ServerDecision::{Invoke,InvokeEffect}` carries only `{target, input,
  correlation_id, idempotency_key}` — **no `capability_id`/`operation`/`scope`**
  (`protocol.rs:101-121`); the effect identity comes from the signed `ServiceRecipe`
  + host effect passport at execution time. `AppIdentity` is explicitly
  observation-only, "never treated as authority" (`protocol.rs:123-132`). This is
  the design pattern the machine's forgeable-passport problem should adopt.
- **Host owns transport-only; routing is 100% in the app** (`host.rs:5-6, 75-81`) →
  the host never inspects `(method, path)`, so there is **no host-side path-
  normalization / route-table authz-bypass surface**.
- **Reload is genuinely correct concurrency:** request-start snapshot
  (`current()` clones the inner `Arc`, read lock dropped immediately, never held
  across `app.call`), so an in-flight request keeps its instance across a `swap`
  (`reload.rs:29-40`, `host.rs:113-125`). No reload/in-flight race, no TOCTOU.
- **Parser is panic-hardened** — `parse_request`/`content_length`/`encode_response`
  use `unwrap_or`/`unwrap_or_default` throughout (`host.rs:179-271`); a malformed/
  truncated/garbage request degrades to defaults, never panics. Raw bytes are
  written verbatim (the `ResponseBody::Raw` HTML/CSV/PDF seam). Materially better
  than the machine ingress.
- **Default build is OBSERVE-ONLY:** in the non-`machine` path,
  `Invoke`/`InvokeEffect` return a `202` "observed" record and are **not executed**
  (`host.rs:34-50`). Effects run only under `--features machine` via
  `MachineEffectHost` — so the effect-auth gap is specific to that path.

## BLOCKERS (transport edge — latent behind loopback, live on a public bind)

**B1. Unbounded request read → OOM (header AND body phase).** `read_request`
(`host.rs:213-234`) reads into an unbounded `Vec`: phase 1 accumulates until
`\r\n\r\n` is found (no header-size cap — a client that never terminates the head
grows it forever), phase 2 reads `while buf.len() < need` where `need = pos + 4 +
content_length(head)` and `content_length` is `v.trim().parse().unwrap_or(0)` into a
`usize` with **no ceiling** (`host.rs:148-156`). The async twin
(`effect_host.rs:156-178`) is identical. `BodyLimitApp` (`middleware.rs:138-149`)
runs *after* the full body is already in memory and re-serializes it to measure —
post-hoc, opt-in, useless for OOM.

**B2. No read timeout → slowloris.** No `set_read_timeout`/deadline on either read
loop (`host.rs:213`, `effect_host.rs:156`). Serving is **sequential** (no
`tokio::spawn`), so one slow/incomplete connection wedges the entire loop. (The
sibling agent bin already sets a 10s child-read timeout — the omission here is an
oversight, not a constraint.)

**B3. Plaintext only — no inbound TLS.** Raw `std::net`/`tokio::net` `TcpStream`
throughout; no rustls. Bearer tokens + bodies cross the wire in cleartext.

**B4. Auth is opt-in, fail-open, and UNWIRED on the effect path.**
- `AuthTokenApp` (`middleware.rs:99-121`) is composed only if the app opts in, and
  the **machine-mode effect path never composes it** (igniter-web `run_machine_mode`
  serves the raw loaded app) → no server-layer bearer check before an effect.
- It **accepts an empty `expected_token`** (`middleware.rs:91`) → an empty configured
  token makes `Authorization: Bearer ` authenticate; the compare is non-constant-time
  and prefix-lenient (`strip_prefix("Bearer ").unwrap_or(h)` → a bare token with no
  `Bearer ` prefix also matches, `middleware.rs:104`).
- The `x-auth-ok: true` success marker (`middleware.rs:113`) is **forgeable**: inbound
  client headers are parsed verbatim into `request.headers` (`host.rs:188-191`) with
  no stripping, and `effect_host` forwards **all** request headers to the machine
  (`effect_host.rs:90-94`) — so a client can pre-set `x-auth-ok` and it reaches the
  machine; anything keying on it is bypassed.

**B5. `effect_host` adds zero authority — it forwards a forgeable credential.**
`run_invoke_effect` copies the client's `Authorization` bearer + a **client-
controlled** `idempotency-key` straight into the `IngressRequest` and calls the
machine's `handle_effect` (`effect_host.rs:87-118`). The machine authenticates that
bearer with the (separately-audited) **forgeable `verify_passport`**, and the server
adds no defense-in-depth. The duplicate key being client-chosen also feeds the
machine's known dedup-TOCTOU.

## PROBLEMS

- **CL.TE request-smuggling latent + an internal CL desync.** `parse_request` honors
  only `Content-Length` and **ignores `Transfer-Encoding: chunked`** entirely; and
  `content_length` returns the **first** `content-length:` line (`host.rs:150-153`)
  while the header `BTreeMap` keeps the **last** duplicate (`host.rs:190`) — body
  length and header view can disagree within one parser. Behind any chunked-aware
  proxy this is a classic CL.TE primitive. (Mitigated today by one-request-per-
  connection / no keep-alive.)
- **Lossy header parse.** `line.split_once(": ")` requires exactly colon-space, so
  `Foo:bar` (no space) is silently dropped and folded/continuation headers are
  unhandled (`host.rs:189`).
- **Content-derived correlation id is collidable.** `deterministic_correlation`
  hashes `method+path+body` with a fixed-seed `DefaultHasher` (`middleware.rs:70-78`)
  → two requests with identical `(method,path,body)` get the **same** correlation id,
  and a client can deliberately craft a body to collide another request's id. That id
  feeds the machine's correlation-reconcile (P13) and read-freshness keying → cross-
  request reconcile confusion. (Replay-deterministic is the intended property; the
  collidability is the side effect.)
- **`loopback_only` is off-by-default and inconsistent.** `ServingPolicy::new` sets
  `loopback_only=false` (`serving_loop.rs:31-36`); only `serve_loop`/`serve_loop_effect`
  call `enforce_loopback` (and only when opted in). `serve_once_effect` has **no**
  loopback check at all (`effect_host.rs:183`). The crate's "the loop binds nothing,
  so it's safe" framing (`serving_loop.rs:8-10`) understates exposure: the **caller**
  binds, and the only real public-bind gate lives in the igniter-web CLI, not here.
- **Reload `swap` has no authority gate; `RwLock` `.expect` is a latent brick.**
  `swap` (`reload.rs:38`) replaces middleware+core atomically with no signature/
  identity check (operator-trust boundary, documented out-of-scope); `current()`/
  `swap` use `.expect("reload lock poisoned")` (`reload.rs:33,39`) — low likelihood
  (the critical sections are panic-free), but a poisoned lock bricks every later
  request.

## INSIGHTS

- **I1. This crate is the model the machine's authority layer should copy.** The
  protocol structurally forbids an app from naming effect authority; authority comes
  from the signed recipe + host passport. That is exactly the discipline the machine's
  forgeable-`verify_passport` finding violates — the *protocol* here is right; the
  *machine's verification* is the weak link the server faithfully forwards to.
- **I2. The loopback invariant is load-bearing AGAIN, and this crate explicitly
  disclaims the gate** ("the loop binds nothing; `loopback_only` off by default").
  Most of B1-B5 are dormant on `127.0.0.1` and live on a public bind. This is the
  right altitude for the workspace-wide **"bind non-loopback = security gate"** — make
  the structural guard live here.
- **I3. The design/enforcement split is the cleanest example of the whole series'
  root cause.** Every *design* decision is disciplined and correct; every *gap* is an
  unwired/opt-in/post-hoc enforcement (auth not composed on machine-mode; body-limit
  after the OOM window; loopback off by default; no timeout/TLS).

## SUPER-COOL (high-leverage)

- **S1. One shared `harden_read(stream)` + body-cap kills B1+B2.** `host::read_request`
  and `effect_host::read_server_request` already share `find_subslice`/`content_length`;
  add a `MAX_HEAD_BYTES`/`MAX_BODY_BYTES` check (refuse → 413) **before** the read loop
  grows the buffer, plus a `set_read_timeout`/deadline. ~10 shared lines close both
  DoS blockers for sync and async at once. Mirror the agent bin's 10s timeout.
- **S2. Make auth structural.** Flip `compose()` to default-on with a **fail-closed**
  `AuthTokenApp` (reject an empty `expected_token` at construction; constant-time
  compare; require the `Bearer ` prefix; strip inbound `x-auth-ok`/trusted markers),
  and **call `compose()` on the machine-mode effect path** (`effect_host` serve loops).
  Closes B4 and removes the forgeable-marker vector.
- **S3. Inbound TLS / mTLS** via a `TlsAcceptor` variant of `serve_once*` (the
  workspace already pins rustls behind the machine's `tls` feature) — turn the
  cleartext bearer into a second factor behind a verified client cert (B3).
- **S4. Make `loopback_only` structural + own the workspace loopback gate.** Default
  `loopback_only` on, add it to `serve_once_effect`, and require an explicit
  security-checklist token (TLS + auth + body-cap + timeout) before a non-loopback
  bind is even constructible — the single gate the machine and web audits both ask
  for, located in the crate that actually owns transport.
- **S5. Lock the protocol-hygiene win with a conformance test.** Assert (property/
  type-level) that `ServerDecision` can never carry a `capability_id`/`operation`/
  `scope` — making "an app cannot forge effect authority" a checked invariant, and
  the reference pattern to propagate to the machine.

## Keystone recommendation

- **IGNITER-SERVER-INBOUND-READ-HARDENING-P2** — S1 (shared body-cap + timeout). B1/B2.
- **IGNITER-SERVER-AUTH-STRUCTURAL-P2** — S2 (fail-closed auth + compose-on-machine-
  mode + strip `x-auth-ok`). B4 (+ B5's forwarded-marker leg).
- **IGNITER-SERVER-LOOPBACK-GATE-P2** — S4 (structural loopback + the shared bind
  gate) + S3 (inbound TLS). B3 + the latency of the whole "latent behind loopback"
  class.

The design is the strongest in the series; the work is **making the transport
defaults structural** (cap/timeout/auth/loopback) and wiring inbound TLS — not a
redesign. The protocol's "no effect authority in the decision" is a positive to
propagate, not a thing to fix.

## Boundary / not covered

Lab evidence only; no code changed. First-hand read of all of `igniter-server/src`;
the machine-mode effect execution path was traced into `igniter-machine` (audited
separately). This deepens the `igniter-server` section of
`igniter-web-core-foundation-audit-p1.md` and completes the server/web-layer sweep.
