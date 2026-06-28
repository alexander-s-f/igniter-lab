# LAB-IGNITER-SERVER-LIVE-BIND-TLS-CHECKLIST-READINESS-P33

Status: DONE
Route: standard / main-audit / server / public bind readiness
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`, `LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32`

## Goal

Design the next public-bind readiness slice after the server live-bind gate and
IgWeb pre-bind wiring, without enabling public bind.

The current safe state is deliberate: loopback binds pass; non-loopback binds
fail closed because IgWeb supplies no `LiveBindChecklist`. This card decides
what a production checklist must contain and where operator config belongs.

## Current Authority

Live server/web code wins. Read first:

- `.agents/work/cards/lang/LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31.md`
- `lab-docs/lang/lab-igniter-server-live-bind-gate-p31.md`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32.md`
- `lab-docs/lang/lab-igniter-web-live-bind-gate-wiring-p32.md`
- `server/igniter-server/src/serving_gate.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`

Known live facts:

- server gate accepts loopback with no checklist;
- non-loopback without checklist is refused;
- IgWeb passes `None` today, so public bind remains closed;
- TLS and a host-owned checklist parser are not implemented.

## Scope

Allowed:

- Produce a readiness packet comparing checklist/config shapes.
- Define secret-handling rules for cert/key/token references.
- Decide whether the next implementation should parse checklist only, add TLS
  transport, or both.
- Name exact refusal modes and tests for a future implementation.

Closed:

- Do not enable public bind.
- Do not add TLS implementation in this readiness card.
- Do not store real private keys/certs/tokens in fixtures.
- Do not change `.igweb`, app code, VM, compiler, machine, or canon.

## Questions To Answer

1. What minimum checklist fields are required before non-loopback bind?
2. Which fields are file references, env references, booleans, or opaque
   operator assertions?
3. Should TLS be mandatory for non-loopback v1?
4. Does checklist parsing live in `igniter-server`, `igniter-web`, or shared
   host config?
5. How should tests prove refusal without opening a public listener?
6. What is the migration path from loopback-only `rails s` style DX to explicit
   production serve?

## Acceptance

- [x] Live P31/P32 behavior is verified and summarized.
- [x] At least three checklist/config alternatives are compared.
- [x] A recommended next implementation card is named.
- [x] Secret policy is explicit: env/file references only, no inline secrets in
      committed config fixtures.
- [x] Public bind remains closed by this card.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-server/Cargo.toml --lib
cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md
```

Include checklist alternatives, chosen authority boundary, implementation card
proposal, and explicit non-goals.

## Closing Report - 2026-06-27

Result: DONE. Produced the readiness packet without enabling public bind or
changing server/web runtime code.

Packet:

```text
lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md
```

Live P31/P32 summary:

- `server/igniter-server/src/serving_gate.rs` owns the pure
  `LiveBindChecklist` / `LiveBindToken` gate.
- Loopback binds pass without a checklist.
- Non-loopback binds without a checklist return
  `non_loopback_without_checklist`.
- IgWeb calls `authorize_bind(addr, None)` before sync and machine-mode binds,
  so public bind remains closed in v0.
- `server/igniter-web/src/host_config.rs` still accepts only
  `[host] mode = "loopback"` and has no live-bind checklist parser.

Decision:

- TLS is mandatory as a non-loopback v1 decision:
  `terminated_upstream` is acceptable with an operator assertion; `native_tls`
  requires a later transport implementation.
- Recommended next implementation card:
  `LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34`.
- Next slice should add a host-owned, secret-free `[host.live_bind]` parser and
  diagnostics only; it should not pass a checklist into `authorize_bind`, add
  TLS transport, or open public listeners.

Verification:

```text
cargo test --manifest-path server/igniter-server/Cargo.toml --lib
```

Result: PASS, 18 tests.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests
```

Result: PASS, 17 tests.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
```

Result: PASS, 5 tests.

```text
git diff --check
```

Result: PASS.

Unrelated dirty files were left untouched.
