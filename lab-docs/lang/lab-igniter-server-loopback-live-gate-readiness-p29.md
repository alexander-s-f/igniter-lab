# LAB-IGNITER-SERVER-LOOPBACK-LIVE-GATE-READINESS-P29

Status: DONE
Date: 2026-06-27
Lane: igniter-lab / server / web / machine / foundation-hardening / T1

## Authority

Live `server/igniter-server`, `server/igniter-web`, and
`runtime/igniter-machine` source decide current behavior. Audit docs were used as
evidence only. No production code changed and no public listener was opened.

## Verify-First Facts

- `igniter-server::serving_loop::ServingPolicy::new` defaults
  `loopback_only=false`; `enforce_loopback` is a narrow check over an already
  bound listener address.
- `serve_loop` and `serve_loop_effect` call the loopback guard when the policy is
  opted in; `serve_once_effect` accepts one connection and has no independent
  bind/readiness gate.
- `igweb-serve` parses `--addr` through a loopback-only parser and defaults to
  `127.0.0.1:0`; both sync and machine-mode runner paths call
  `ServingPolicy::new(max).loopback_only()`.
- `machine_runner::{serve_loop_loaded, serve_loop_loaded_with_read}` duplicate
  the same loopback-only check instead of importing one gate type.
- `runtime/igniter-machine::serving_loop` is a local shell over a caller-bound
  `TcpListener`; it assumes loopback/local scope and does not bind addresses.
- P26 is DONE in the current worktree: signed passport data-plane entrypoints
  exist and are tested.
- P27 is DONE in the current worktree: IgWeb effect-host passports are signed
  before crossing into the machine effect path.
- P28 is DONE in the current worktree: hardened inbound read limits/timeouts and
  fail-closed auth are wired across server/web/machine local paths.

## Designs Compared

### A. CLI Parse Refusal Only

Keep the current `igweb-serve` posture: parse `--addr` as loopback-only and fail
before socket bind.

Pros:

- already exists;
- not breaking for current CLI/tests;
- fails before bind for the main lab runner.

Cons:

- not structural: direct library callers can still bind non-loopback and pass the
  listener to server/machine loops;
- duplicate checks remain in IgWeb machine runner;
- cannot express the live-readiness checklist.

Decision: insufficient as the canonical gate. Keep it as a first-line CLI
refusal.

### B. Default-On Loopback Policy Only

Change `ServingPolicy::new` to `loopback_only=true` and require callers to opt
out.

Pros:

- simple;
- makes existing loop helpers safer by default;
- likely compatible with current CLI because it already opts in.

Cons:

- opt-out can become the bypass unless it requires a token;
- still operates after a caller has already bound the socket;
- does not prove signed passport/body cap/timeout/auth/TLS readiness.

Decision: useful implementation detail, not enough for non-loopback readiness.

### C. Canonical Gate Token In `igniter-server`

Define a server-owned gate type that evaluates the requested bind address and a
host-owned checklist before any bind. Non-loopback construction requires an
opaque token produced only by successful checklist validation.

Pros:

- owner crate matches the transport altitude: `igniter-server` already owns
  `ServingPolicy`, `ServingReport`, and the loopback guard;
- IgWeb and machine runner can prove they use the same gate by importing the
  same result/token type;
- preserves current loopback flows while making live bind impossible without
  explicit host evidence;
- refusal can be sanitized and deterministic.

Cons:

- requires a small API addition and runner rewiring;
- P27/P28 satisfy the signed-passport and hardened-read/auth prerequisites.
  TLS/live-operator choices still must close before token creation can allow
  non-loopback.

Decision: recommended v0 design.

### D. Compile-Time Feature Gate Only

Make non-loopback code compile only under a feature such as `live-bind`.

Pros:

- hard separation for release artifacts;
- useful as defense-in-depth for distribution later.

Cons:

- does not prove runtime host checklist;
- incompatible with one binary that can run loopback in dev and live only after
  operator approval;
- cannot represent TLS/auth/body-cap readiness by itself.

Decision: defer as optional packaging defense; do not use as the main gate.

## Recommended V0

Owner crate: `server/igniter-server`.

Canonical shape:

```rust
pub enum BindClass {
    Loopback,
    NonLoopback,
}

pub enum InboundTlsMode {
    TerminatedUpstream,
    NativeTls,
}

pub struct LiveBindChecklist {
    pub signed_passport_path_wired: bool,
    pub body_cap_enabled: bool,
    pub read_timeout_enabled: bool,
    pub fail_closed_auth_enabled: bool,
    pub inbound_tls_mode: Option<InboundTlsMode>,
    pub operator_signoff: OperatorSignoff,
}

pub struct LiveBindToken {
    bind_addr: SocketAddr,
    issued_for: BindClass,
    checklist_digest: String,
}

pub enum LiveBindRefusal {
    NonLoopbackWithoutToken,
    MissingSignedPassport,
    MissingBodyCap,
    MissingReadTimeout,
    MissingFailClosedAuth,
    MissingInboundTlsDecision,
    MissingOperatorSignoff,
}

pub fn classify_bind(addr: SocketAddr) -> BindClass;

pub fn authorize_bind(
    addr: SocketAddr,
    checklist: Option<&LiveBindChecklist>,
) -> Result<Option<LiveBindToken>, LiveBindRefusal>;
```

Policy:

- loopback bind returns `Ok(None)` and does not need a token;
- non-loopback bind requires `Ok(Some(LiveBindToken))`;
- `LiveBindToken` fields are private and must not be constructible by app code;
- `ServingPolicy` should carry `BindClass`/token status or a derived
  `ServingBindAuthorization`, not raw booleans;
- refusal diagnostics name missing checklist fields only; they must not print
  bearer tokens, DSNs, signing keys, TLS private material, or host config values.

The gate should run before `TcpListener::bind` in IgWeb CLI/runner paths. The
post-bind `enforce_loopback` check should remain as defense-in-depth for callers
that hand a pre-bound listener directly to `igniter-server`.

## Answers

1. Canonical gate owner: `igniter-server`. It is the transport crate and already
   owns serving policy/report types.
2. Default-on `loopback_only` is probably not breaking for `igweb-serve`, because
   current runner paths already call `.loopback_only()`. It may affect direct
   library callers, so implement it under an explicit migration card with tests.
3. Non-loopback should be refused at config/parse/pre-bind time and rechecked at
   runtime on pre-bound listeners. Compile-time feature gating is optional later.
4. Required v0 checklist fields: signed passport path wired, body cap enabled,
   read timeout enabled, fail-closed auth enabled when auth is configured,
   inbound TLS mode explicitly chosen, operator sign-off present.
5. IgWeb runner and machine runner prove shared use by importing
   `igniter_server::serving_gate::{authorize_bind, LiveBindToken}` and deleting
   their duplicate loopback checks.
6. Refusal reports a stable code plus missing field names. It must redact all
   token, DSN, key, and certificate material.
7. Out of v0: ACME, public CA automation, reverse-proxy deployment model,
   production TLS implementation, mTLS, systemd/install/deploy, external internet
   listeners, host config schema stabilization.

## Dependency Status

- P26 `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`: DONE in current worktree.
- P27 `LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27`: DONE in current worktree;
  required signed effect-passport prerequisite satisfied.
- P28 `LAB-IGNITER-SERVER-INBOUND-HARDENED-READ-P28`: DONE in current worktree;
  required hardened read/auth prerequisite satisfied.
- Inbound TLS: no implementation card closed; v0 gate must refuse non-loopback
  unless TLS mode is explicitly selected, and until an accepted TLS story exists
  the only safe result is refusal.

## Next Implementation Cards

1. `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`
   - add `igniter-server` gate types;
   - keep loopback paths unchanged;
   - prove non-loopback without token fails before bind;
   - make refusal diagnostics sanitized.
2. `LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32`
   - route `igweb-serve` sync and machine-mode bind through the server gate;
   - replace duplicate machine-runner loopback checks with the shared gate result.
3. `LAB-MACHINE-SERVING-LOOP-LIVE-BIND-GATE-P33`
   - add the same token requirement to machine serving-loop host wrappers that
     accept pre-bound listeners, preserving loopback default.

Smallest next card: `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`.

## Verification

```text
git diff --check
```

Result:

```text
PASS
```
