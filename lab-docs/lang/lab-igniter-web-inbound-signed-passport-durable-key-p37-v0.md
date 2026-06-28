# LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37 v0

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate / authority backing
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37.md`
Depends-On: `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35`,
`LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36`,
`LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`
Implements: audit-control-board row **A10** signed-passport authority backing;
public bind stays HOLD.

## Authority boundary

This card upgrades one dry-run/check fact only:

`signed_passport_path_wired=true` now means the host loaded durable verifier
material and constructed/validated an `igniter_machine::capability::PassportVerifier`
for the dry-run non-loopback checklist path.

It still opens no socket, grants no bind authority, and does not wire the dry-run
result into the real `Run` bind path. `authorize_bind` remains pure and sees only
`LiveBindChecklist` booleans/enums. The runner still calls `authorize_bind(addr,
None)` before real sync and machine-mode binds, so public/non-loopback run remains
refused before `TcpListener::bind`.

## v0 material format

Current `PassportVerifier` is symmetric-key based. There is no public verifier
handle yet. For this bounded v0, `[host.live_bind].signed_passport_path` points
to a local trusted-issuer key file containing exactly one 64-hex-character
32-byte issuer key, with optional surrounding whitespace.

Why this is acceptable for v0:

- it uses the live P26 primitive (`PassportVerifier`, `sign_passport`,
  `verify_passport_signed`) instead of inventing a second verifier surface;
- it is host-side only and used only in `live-bind-check`;
- tests create synthetic temporary key files at runtime; no real key material is
  committed in examples or docs;
- diagnostics and verdicts expose only stable refusal codes, not file contents
  or key/passport material.

Future public-key verifier handles, KMS, rotation, revocation lists, and route
auth remain outside this card.

## What shipped

Code:

- `server/igniter-web/src/live_bind_check.rs`
  - added `load_inbound_passport_verifier(path)`;
  - parses 64-hex-char trusted issuer key material;
  - constructs `PassportVerifier::new().trust(key)`;
  - validates the verifier by signing and verifying a synthetic
    `CapabilityPassport` probe;
  - changes `config_to_checklist` to return `Result<LiveBindChecklist,
    LiveBindVerifierLoadError>` and set `signed_passport_path_wired=true` only
    after successful load/validation;
  - changes non-loopback `evaluate` to refuse on missing/malformed verifier
    material before calling `authorize_bind`.
- `server/igniter-web/tests/igweb_live_bind_dry_run_tests.rs`
  - complete dry-run configs now point to temp valid verifier material;
  - added missing-material and malformed-material subprocess tests;
  - asserts stdout/stderr do not leak verifier path or material.

Docs:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/lab-audit-control-board-v1.md`

## Refusal taxonomy

| Input | Verdict / diagnostic | Exit |
|---|---|---|
| non-loopback + valid verifier material + complete checklist | `would_authorize`, opaque `checklist_digest=live-bind-v0:...`, `socket_opened=false public_bind=closed` | 0 |
| non-loopback + missing verifier file/ref | `would_refuse code=signed_passport_verifier_unavailable missing_field=signed_passport_path` | 5 (`BIND_REFUSED`) |
| non-loopback + malformed verifier material | `would_refuse code=signed_passport_verifier_invalid missing_field=signed_passport_path` | 5 (`BIND_REFUSED`) |
| non-loopback + no `[host.live_bind]` section | `would_refuse code=non_loopback_without_checklist` | 5 (`BIND_REFUSED`) |
| incomplete checklist shape | `[CONFIG_PARSE]`, no verdict | 2 (`CONFIG_PARSE`) |
| real `igweb-serve run --addr 0.0.0.0:...` | `[BIND_REFUSED] non_loopback_without_checklist`, no listening line | 5 (`BIND_REFUSED`) |

Loopback dry-run still authorizes with no checklist required and does not load
verifier material, because it does not construct a non-loopback live-bind
checklist.

## Host-verified vs operator assertion

P36 copied `signed_passport_path` into `signed_passport_path_wired=true` after
shape parsing. P37 changes the implemented non-loopback dry-run path so the
boolean is true only after:

1. the host reads the referenced file;
2. the content parses as one 32-byte trusted issuer key;
3. a `PassportVerifier` built from that key verifies a signed synthetic
   passport probe through `verify_passport_signed`.

The dry-run output does not need a new success field: a non-loopback
`would_authorize` verdict now implies the signed-passport verifier backing
loaded successfully. Failures use explicit stable refusal codes above.

## Public bind remains CLOSED

- `igweb-serve live-bind-check` never calls `TcpListener::bind`; all verdicts
  render `socket_opened=false public_bind=closed`.
- `igweb_serve_diagnostics_tests::complete_live_bind_still_refuses_non_loopback_bind`
  remains green: a full `[host.live_bind]` checklist in `Run` mode still does
  not relax the gate.
- No TLS transport was added. P38 remains the terminated-upstream TLS runbook
  proof, and P39 remains the first possible human-gated public-bind proof.

## Verification

Commands run from `/Users/alex/dev/projects/igniter-workspace/igniter-lab`:

```bash
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine live_bind_check -- --nocapture
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_dry_run_tests -- --nocapture
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests -- --nocapture
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test signed_passport_dataplane_tests -- --nocapture
```

Results:

- `live_bind_check`: 9 passed.
- `igweb_live_bind_dry_run_tests`: 8 passed.
- `igweb_serve_diagnostics_tests`: 8 passed.
- `signed_passport_dataplane_tests`: 5 passed.

Warnings observed are pre-existing unused/dead-code warnings in adjacent crates;
no new test failures.

## Remaining work

- P38: terminated-upstream TLS runbook/proxy-header trust proof.
- P39: explicit human-gated live-bind proof, after P36+P37+P38, and only then may
  a public listener proof be considered.
- Future key model: asymmetric/public verifier material or KMS/rotation is a
  separate card; v0 deliberately stays inside the existing symmetric
  `PassportVerifier` primitive.
