# LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32

Date: 2026-06-27
Status: CLOSED
Route: standard / main-audit / web-server / live-bind gate wiring

## Scope

This packet covers IgWeb wiring to the server-owned live bind gate from P31.
It is lab evidence only. It does not create canon language authority, does not
enable public bind by default, does not add TLS, and does not change app route
semantics, `.igweb`, VM, compiler, machine, frame-ui, home-lab, SparkCRM, or
`igniter-lang`.

## Gate Call Sites

IgWeb now calls:

```rust
igniter_server::serving_gate::authorize_bind(addr, None)
```

from `server/igniter-web/src/bin/igweb-serve.rs` through the local helper
`authorize_runner_bind`.

Covered call sites:

- sync/default runner path:
  - after app build and before `std::net::TcpListener::bind(cli.addr)`
  - failure exits through `RunnerDiagnostic { code: BIND_REFUSED }`

- machine/async runner path:
  - after host config resolution/app build and before the Tokio runtime can
    reach either `tokio::net::TcpListener::bind(addr)` branch
  - the same pre-bind helper covers both real write-host and fallback
    effect-host paths

`server/igniter-web/src/lib.rs` now parses `--addr` as a plain `SocketAddr`.
It no longer treats CLI parsing as live-bind authority. Non-loopback addresses
therefore reach the server gate and are refused before any listener bind in v0.

## Current v0 Authorization

IgWeb v0 passes no live checklist:

```text
loopback addr     -> authorize_bind(addr, None) -> Ok(None) -> bind as before
non-loopback addr -> authorize_bind(addr, None) -> Err(non_loopback_without_checklist)
```

This preserves the safe outcome while making the authority seam server-owned.
No public bind checklist parser was added. No certificate, private key, bearer
token, DSN, or operator secret appears in fixtures.

## Refusal Shape

Non-loopback runner refusal is sanitized:

```text
igweb-serve: [BIND_REFUSED] live bind gate refused 0.0.0.0:0: non_loopback_without_checklist
```

The refusal happens before `TcpListener::bind`, and tests assert stdout never
prints `listening http`.

## Defense In Depth

Post-bind loopback guards remain in place:

- sync path still uses `ServingPolicy::new(max).loopback_only()`
- machine path still uses `ServingPolicy::new(max).loopback_only()`
- `server/igniter-web/src/machine_runner.rs` still checks `policy.loopback_only`
  against the bound address

## Implemented Surface

Updated:

```text
server/igniter-web/IMPLEMENTED_SURFACE.md
```

It now states that public listener mode remains closed, that IgWeb calls the
server live-bind gate before sync and machine-mode binds, and that
`ServingPolicy::loopback_only()` remains defense-in-depth.

## Proof Commands

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --test runner_tests --test igweb_serve_diagnostics_tests
```

Result: PASS. `runner_tests` 17/17. The diagnostics suite is feature-gated and
ran 0 tests in this non-machine invocation.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
```

Result: PASS, 5/5.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests
```

Result: PASS, 17/17.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
```

Result: PASS, 12/12.

```text
cargo test --manifest-path server/igniter-server/Cargo.toml --lib
```

Result: PASS, 18/18.

```text
git diff --check
```

Result: PASS, no whitespace errors.

## Acceptance Mapping

- Sync `igweb-serve` path calls server gate before bind:
  `authorize_runner_bind(cli.addr)` before `TcpListener::bind(cli.addr)`.

- Machine/async path calls server gate before bind:
  `authorize_runner_bind(addr)?` before Tokio bind branches.

- Non-loopback refusal without public listener:
  `igweb_serve_diagnostics_tests::non_loopback_addr_fails_closed` and
  `igniter_serve_wrapper_smoke_tests::igniter_serve_refuses_public_bind`.

- Loopback behavior remains green:
  `runner_tests`, `igweb_serve_diagnostics_tests`, `igweb_serve_machine_mode_tests`,
  and `igniter_serve_wrapper_smoke_tests`.

- Post-bind defense remains:
  `ServingPolicy::loopback_only()` still passed in sync and machine paths.

## Remaining Gaps

- No public bind mode is enabled.
- No TLS implementation is added.
- No IgWeb host-config schema for a complete `LiveBindChecklist` exists yet.
- A future slice may add a host-owned, secret-free checklist parser and carry
  the opaque `LiveBindToken` deeper into serving policy/bind helpers.
