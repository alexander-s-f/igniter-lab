# LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31

Date: 2026-06-27
Lane: igniter-lab / server / foundation-hardening / live-bind-gate
Status: DONE

## Authority

This is lab evidence for `server/igniter-server`. Live source and tests decide
current behavior. This packet does not create canon language authority and does
not change IgWeb CLI wiring, machine-runner wiring, TLS implementation, public
bind behavior, route semantics, `.igweb` grammar, VM, compiler, stdlib,
frame-ui, home-lab, SparkCRM, or `igniter-lang`.

## API Added

New public module:

```rust
igniter_server::serving_gate
```

Types and functions:

```rust
pub enum BindClass { Loopback, NonLoopback }

pub enum InboundTlsMode {
    TerminatedUpstream,
    NativeTls,
}

pub enum OperatorSignoff {
    Missing,
    Present,
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

pub enum LiveBindRefusal { /* stable refusal taxonomy */ }

pub fn classify_bind(addr: SocketAddr) -> BindClass;

pub fn authorize_bind(
    addr: SocketAddr,
    checklist: Option<&LiveBindChecklist>,
) -> Result<Option<LiveBindToken>, LiveBindRefusal>;
```

Semantics:

```text
loopback addr     -> Ok(None)
non-loopback none -> Err(NonLoopbackWithoutChecklist)
non-loopback bad  -> Err(Missing*)
non-loopback full -> Ok(Some(LiveBindToken))
```

## Refusal Taxonomy

Stable sanitized refusal codes:

```text
non_loopback_without_checklist
missing_signed_passport
missing_body_cap
missing_read_timeout
missing_fail_closed_auth
missing_inbound_tls_decision
missing_operator_signoff
```

`LiveBindRefusal` implements `Display` and `std::error::Error`. Diagnostics
emit only the stable code plus a missing field name where relevant. They do not
include tokens, DSNs, signing keys, TLS material, or host config values.

## Token Opacity

`LiveBindToken` fields are private:

```rust
bind_addr: SocketAddr
issued_for: BindClass
checklist_digest: String
```

External crates can inspect sanitized metadata through accessors, but cannot
construct a token literal. This is covered by a `compile_fail` doctest on
`LiveBindToken`.

## Checklist Digest

The token stores a structural digest:

```text
live-bind-v0:<fnv1a64 hex>
```

The digest input is a canonical string containing only v0 structural markers:
boolean checklist fields, selected TLS mode name, and operator signoff marker.
It does not include bearer tokens, DSNs, signing keys, certificate/private-key
material, host config values, or operator free text.

## Public Bind Status

No public bind was opened or enabled. The new module is pure and calls no
`TcpListener::bind`. Existing `serve_loop` / `serve_loop_effect` behavior is
unchanged, including the current opt-in post-bind `loopback_only` guard.

No `igweb-serve` CLI wiring was added in this card.

## P32 Handoff

IgWeb should pre-authorize before `TcpListener::bind`:

```rust
use igniter_server::serving_gate::{authorize_bind, LiveBindChecklist};

let auth = authorize_bind(addr, maybe_checklist.as_ref())?;
match auth {
    None => {
        // loopback: bind as today
    }
    Some(token) => {
        // non-loopback: carry token into the future ServingPolicy/bind helper
        // without exposing or reconstructing token internals
    }
}
```

P32 should wire both sync and machine-mode IgWeb paths through this gate and
remove duplicate local loopback classification from IgWeb runner code. The
server post-bind `enforce_loopback` guard should remain as defense-in-depth for
pre-bound listeners.

## Evidence

Changed source:

```text
server/igniter-server/src/lib.rs
server/igniter-server/src/serving_gate.rs
```

Commands:

```text
cargo fmt --manifest-path server/igniter-server/Cargo.toml
cd server/igniter-server && cargo test --lib
cd server/igniter-server && cargo test --test loopback_tests --test middleware_tests
cd server/igniter-server && cargo test --features machine --test effect_machine_tests
cd server/igniter-server && cargo test --doc
git diff --check
```

Results:

```text
cargo fmt: pass
cargo test --lib: pass, 18 tests
loopback_tests: pass, 7 tests
middleware_tests: pass, 10 tests
effect_machine_tests with machine feature: pass, 10 tests
cargo test --doc: pass, 1 compile_fail doctest
git diff --check: pass
```
