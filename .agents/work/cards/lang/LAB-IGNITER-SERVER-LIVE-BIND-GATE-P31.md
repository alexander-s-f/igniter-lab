# LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31 - server-owned structural gate for non-loopback bind

Status: DONE
Lane: igniter-lab / server / foundation-hardening / live-bind-gate
Type: implementation / authority gate
Date: 2026-06-27
Skill: idd-agent-protocol
Depends-On:
- `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`
- `LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27`
- `LAB-IGNITER-SERVER-INBOUND-HARDENED-READ-P28`
- `LAB-IGNITER-SERVER-LOOPBACK-LIVE-GATE-READINESS-P29`

## Agent Onboarding Header

This is the first implementation slice after P29 readiness.

Add a **server-owned structural gate type** that makes non-loopback serving impossible unless a host-owned
live-bind checklist is explicitly authorized. Keep all current loopback behavior working.

Do **not** open a public listener. Do **not** wire `igweb-serve` CLI yet. Do **not** implement TLS.

## Goal

Implement the minimal `igniter-server` gate API recommended by P29:

```text
loopback addr     -> allowed without token
non-loopback addr -> refused unless a complete host-owned checklist authorizes a LiveBindToken
```

This card should make the authority model concrete inside `server/igniter-server`, while preserving the
current loopback lab surface.

## Current Authority

Live code and tests decide behavior.

Start from:

- `lab-docs/lang/lab-igniter-server-loopback-live-gate-readiness-p29.md`
- `server/igniter-server/src/serving_loop.rs`
- `server/igniter-server/src/effect_host.rs`
- `server/igniter-server/tests/loopback_tests.rs`
- `server/igniter-server/tests/effect_machine_tests.rs`

Fresh live facts at card creation:

- `ServingPolicy::new(max)` defaults `loopback_only=false`.
- `ServingPolicy::loopback_only()` exists as an opt-in post-bind guard.
- `serve_loop` and `serve_loop_effect` call `enforce_loopback(addr, policy.loopback_only)`.
- `igweb-serve` already parses `--addr` through loopback-only parsing, but that is not structural.
- IgWeb machine runner currently duplicates loopback checks. That wiring is P32, not this card.

## Closed Surfaces

- No public bind enablement.
- No `igweb-serve` CLI wiring.
- No machine runner wiring.
- No TLS implementation.
- No host-config schema stabilization.
- No changes to app route/domain semantics, `.igweb` grammar, VM, compiler, stdlib, frame-ui,
  home-lab, SparkCRM, or canon `igniter-lang`.
- Do not touch unrelated dirty files, especially `frame-ui/igniter-frame/Cargo.lock`.

## Required Design

Add a small module or section in `igniter-server`, preferably under `serving_loop` or a new
`serving_gate` module, with names close to P29:

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

pub struct LiveBindToken { /* private fields */ }

pub enum LiveBindRefusal {
    NonLoopbackWithoutChecklist,
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

Shape can vary if live code suggests a better Rust API, but preserve these semantics:

- loopback returns `Ok(None)`;
- non-loopback with no checklist returns a stable refusal;
- non-loopback with incomplete checklist returns stable missing-field refusals;
- non-loopback with complete checklist returns `Ok(Some(LiveBindToken))`;
- `LiveBindToken` fields are private; app code cannot construct a fake token directly;
- refusal diagnostics must reveal only stable codes / missing field names, never tokens, DSNs, signing keys,
  TLS private material, or host config values.

Integrate only inside `igniter-server` enough to prove the gate exists:

- keep current `ServingPolicy::loopback_only()` behavior green;
- optionally add `ServingPolicy` helper(s) that carry an authorization result for future P32, but do not break
  current callers;
- post-bind `enforce_loopback` remains as defense-in-depth for pre-bound listeners.

## Questions To Answer

1. Should the module be `serving_loop::gate` or `serving_gate`?
2. Is `OperatorSignoff` a bool-like marker, timestamped string, or small enum in v0?
3. How is `checklist_digest` computed without leaking checklist values?
4. Which refusal codes should implement `Display` / `std::error::Error`?
5. Does any existing loopback test break if the gate module is introduced?
6. What exact API should P32 use from IgWeb to pre-authorize a bind before `TcpListener::bind`?

## Acceptance

- [x] `classify_bind(127.0.0.1:*)` and `[::1]:*` return `Loopback`.
- [x] `classify_bind(0.0.0.0:*)` and a non-loopback address return `NonLoopback`.
- [x] Loopback authorization succeeds without checklist/token.
- [x] Non-loopback without checklist is refused before any bind attempt in a pure unit test.
- [x] Non-loopback with each missing checklist field is refused with a stable sanitized code.
- [x] Complete checklist returns an opaque `LiveBindToken`.
- [x] `LiveBindToken` cannot be constructed by external crates except through the gate function.
- [x] Existing `serve_loop` / `serve_loop_effect` loopback tests remain green.
- [x] No `igweb-serve` public bind behavior changes.
- [x] Proof packet created.
- [x] `git diff --check` clean.

## Required Proof Packet

Create:

```text
lab-docs/lang/lab-igniter-server-live-bind-gate-p31.md
```

Include:

- exact API added;
- refusal taxonomy;
- token opacity strategy;
- checklist digest strategy;
- tests and commands;
- proof that no public bind was opened/enabled;
- exact P32 handoff API for IgWeb wiring.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-server

cargo test --test loopback_tests --test middleware_tests
cargo test --features machine --test effect_machine_tests

cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git diff --check
```

If the gate module has its own unit tests in `src`, ensure the relevant crate unit tests run as well.

## Dirty Worktree Warning

At card creation time, the only known unrelated dirty file is:

```text
frame-ui/igniter-frame/Cargo.lock
```

Treat it as another agent's work. Do not stage, revert, or depend on it.

## Closing Report

Fill this in when done:

- Result: DONE. Added a server-owned pure live bind gate module for pre-bind authorization.
- Files changed:
  - `server/igniter-server/src/lib.rs`
  - `server/igniter-server/src/serving_gate.rs`
  - `lab-docs/lang/lab-igniter-server-live-bind-gate-p31.md`
  - this card
- API added:
  - `igniter_server::serving_gate::{BindClass, InboundTlsMode, OperatorSignoff, LiveBindChecklist, LiveBindToken, LiveBindRefusal, classify_bind, authorize_bind}`
- Commands run:
  - `cargo fmt --manifest-path server/igniter-server/Cargo.toml`
  - `cd server/igniter-server && cargo test --lib`
  - `cd server/igniter-server && cargo test --test loopback_tests --test middleware_tests`
  - `cd server/igniter-server && cargo test --features machine --test effect_machine_tests`
  - `cd server/igniter-server && cargo test --doc`
  - `git diff --check`
- Tests:
  - `cargo test --lib`: pass, 18 tests
  - `loopback_tests`: pass, 7 tests
  - `middleware_tests`: pass, 10 tests
  - `effect_machine_tests` with `machine`: pass, 10 tests
  - `cargo test --doc`: pass, 1 compile-fail doctest
- Public bind status: unchanged. No listener was opened, no public bind was enabled, and no `igweb-serve` wiring was added.
- P32 handoff: IgWeb should call `authorize_bind(addr, maybe_checklist.as_ref())` before `TcpListener::bind`; loopback receives `None`, non-loopback receives an opaque `LiveBindToken` only after complete checklist validation.
- Remaining blockers: P32 still needs IgWeb sync/machine runner wiring; TLS implementation and host config schema remain outside P31.
