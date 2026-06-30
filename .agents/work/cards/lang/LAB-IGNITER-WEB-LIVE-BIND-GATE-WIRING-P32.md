# LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32

Status: DONE
Route: standard / main-audit / web-server / live-bind gate wiring
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`

## Goal

Wire the server-owned `serving_gate::authorize_bind` into IgWeb runner paths
before any listener bind, without enabling public bind by default.

P31 added the pure server gate. This card makes IgWeb consume it so the
loopback->live transition has one structural authority seam instead of local
ad hoc loopback checks.

## Current Authority

Live code wins.

Read first:

- `.agents/work/cards/lang/LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31.md`
- `lab-docs/lang/lab-igniter-server-live-bind-gate-p31.md`
- `server/igniter-server/src/serving_gate.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/lib.rs` runner addr parsing
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/tests/*serve*`

Known live facts:

- `igweb-serve` currently accepts only loopback addresses at CLI parse/config
  layers.
- Sync and machine-mode runner paths still bind directly.
- `ServingPolicy::loopback_only()` remains defense-in-depth after bind.
- P31's gate supports non-loopback checklist authorization but no IgWeb wiring.

## Scope

Allowed:

- Call `authorize_bind(addr, None)` or a resolved checklist before
  `TcpListener::bind` in sync and async/machine paths.
- Keep v0 host mode loopback-only. Non-loopback should still be refused unless
  a complete checklist is explicitly present, and this card may decide the
  checklist is not yet configurable in IgWeb v0.
- Add tests proving pre-bind refusal without opening a public listener.
- Update Implemented Surface / proof docs.

Closed:

- Do not enable public bind by default.
- Do not add TLS.
- Do not design full production host-config schema unless needed for a minimal
  checklist parser.
- Do not change route semantics, `.igweb`, VM, compiler, machine, frame-ui, or
  canon `igniter-lang`.

## Design Constraint

The safe v0 outcome is acceptable:

```text
loopback addr -> authorize_bind(...)=Ok(None) -> bind as today
non-loopback -> refused before bind because no complete host checklist exists
```

If a checklist parser is added, it must be host-owned and secret-free in tests.
No real certificate/key/token material in fixtures.

## Acceptance

- [x] Sync `igweb-serve` path calls server gate before `TcpListener::bind`.
- [x] Machine/async path calls server gate before `tokio::net::TcpListener::bind`.
- [x] Non-loopback refusal is tested without creating a public listener.
- [x] Loopback behavior and existing smoke tests remain green.
- [x] Post-bind `ServingPolicy::loopback_only()` remains in place.
- [x] `server/igniter-web/IMPLEMENTED_SURFACE.md` accurately states the current
      live-bind status.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --test igweb_serve_machine_mode_tests
cargo test --manifest-path server/igniter-server/Cargo.toml --lib
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-live-bind-gate-wiring-p32.md
```

Include exact gate call sites, refusal tests, public-bind status, and remaining
TLS/host-config gaps.

## Closing Report

- Result: DONE. Wired IgWeb sync and machine-mode runner paths through
  `igniter_server::serving_gate::authorize_bind(addr, None)` before listener
  bind.
- Files changed:
  - `server/igniter-web/src/bin/igweb-serve.rs`
  - `server/igniter-web/src/lib.rs`
  - `server/igniter-web/tests/runner_tests.rs`
  - `server/igniter-web/tests/igweb_serve_diagnostics_tests.rs`
  - `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`
  - `server/igniter-web/IMPLEMENTED_SURFACE.md`
  - `lab-docs/lang/lab-igniter-web-live-bind-gate-wiring-p32.md`
  - this card
- Public bind status: unchanged/closed. IgWeb v0 has no checklist parser and
  passes `None`, so non-loopback fails with `BIND_REFUSED` /
  `non_loopback_without_checklist` before bind.
- Post-bind guard status: retained. Sync and machine paths still pass
  `ServingPolicy::new(max).loopback_only()`.
- Commands run:
  - `cargo test --manifest-path server/igniter-web/Cargo.toml --test runner_tests --test igweb_serve_diagnostics_tests`
  - `cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests`
  - `cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests`
  - `cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests`
  - `cargo test --manifest-path server/igniter-server/Cargo.toml --lib`
  - `git diff --check`
- Remaining gaps: TLS, public-bind enablement, and a host-owned
  `LiveBindChecklist` config/parser remain future work.
