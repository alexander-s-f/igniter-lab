# LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37

Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate / authority backing
Skill: idd-agent-protocol
Depends-On:
- `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35`
- `LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36`
- `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`

## Goal

Close the next A10 authority gap: make the live-bind checklist's
`signed_passport_path_wired` assertion host-verified rather than operator-claimed.

P36 can map parsed `[host.live_bind]` config into a complete server
`LiveBindChecklist`, but only for a **dry run**. The key weakness is explicit in
the P36 proof packet: `signed_passport_path_wired=true` currently means "the
operator wrote a path-shaped field", not "the host has loaded durable verifier
material and can verify inbound signed passports".

This card should design and, if small enough, implement the minimal host-verified
backing for that single boolean. Public/non-loopback bind must remain closed.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md` row A10.
- `lab-docs/lang/lab-igniter-web-live-bind-gate-decision-readiness-p35-v0.md`
- `lab-docs/lang/lab-igniter-web-live-bind-dry-run-verdict-p36-v0.md`
- `lab-docs/lang/lab-machine-signed-passport-dataplane-p26.md`
- `runtime/igniter-machine/src/capability.rs`
- `server/igniter-server/src/serving_gate.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/live_bind_check.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- current `server/igniter-web/IMPLEMENTED_SURFACE.md`

Known live facts to re-verify:

- `authorize_bind` is pure and accepts only `LiveBindChecklist` booleans/enums.
- `PassportVerifier`, `sign_passport`, and `verify_passport_signed` exist in
  `igniter-machine`.
- P36 dry-run opens no sockets and does not grant bind authority.
- `[host.live_bind] signed_passport_path` is currently a path reference only.

## Scope

Allowed:

- Add a host-side loader/verifier seam for an inbound signed-passport verifier,
  preferably using file/env references already accepted by `host.toml`.
- Convert `signed_passport_path_wired` to `true` only when verifier material is
  successfully loaded/validated by the host in the relevant dry-run/check path.
- Keep parse-only diagnostics secret-safe: never print key/passport material or
  raw file contents.
- Add unit/subprocess tests proving:
  - missing file/ref -> refusal or config/load diagnostic;
  - malformed verifier material -> refusal;
  - valid durable verifier material -> dry-run can set
    `signed_passport_path_wired=true`;
  - dry-run still opens no socket.
- Produce a proof packet and update implemented surface / audit board only if
  current truth changes.

If implementation is not a small, clean slice, stop after a readiness packet that
names the exact implementation card. Do not widen.

Closed:

- Do not open or demonstrate a public/non-loopback listener.
- Do not wire dry-run success into the actual `Run` bind path.
- Do not implement TLS transport.
- Do not implement production key rotation, revocation lists, KMS, registry
  signing, or remote identity.
- Do not move signed-passport verification inside `authorize_bind`; it must stay
  pure.
- Do not add app/`.igweb` syntax or route-level auth semantics.

## Questions To Answer

1. What exact durable material does the host load for inbound passport
   verification in v0: raw 32-byte issuer key, public verifier handle, signed
   passport fixture, or a narrower live-bind-specific key file?
2. Does this card need an implementation, or is the correct first move a
   readiness packet because current `PassportVerifier` shape is symmetric-key
   only?
3. How does the host distinguish "operator provided a path" from "verifier
   actually loaded and can verify" without leaking material?
4. What dry-run output changes, if any, are needed to show host-verified backing
   without exposing secrets?
5. What remains for P38/P39 after this card?

## Acceptance

- [x] Live P35/P36/P26/server-gate surfaces are characterized.
- [x] The card either implements a bounded host-verified verifier backing or
      produces a readiness packet explaining why implementation must be a
      follow-up.
- [x] `signed_passport_path_wired` is no longer treated as purely operator
      asserted in any implemented proof path.
- [x] Secret/key/passport material is never logged, printed, committed, or
      embedded in examples.
- [x] Dry-run still opens no socket and grants no bind authority.
- [x] Normal `igweb-serve run` public bind remains refused.
- [x] Tests or readiness acceptance cover missing/malformed/valid verifier
      material.
- [x] Proof packet created under `lab-docs/lang/`.
- [x] `git diff --check` passes.
- [x] Card closed with concise report.

## Suggested Verification

Adapt after live discovery, but start with:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_dry_run_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test signed_passport_dataplane_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-inbound-signed-passport-durable-key-p37-v0.md
```

Packet must state:

- what material is loaded and why it is safe for v0;
- whether implementation landed or a smaller follow-up is required;
- how host-verified backing differs from operator assertion;
- exact refusal taxonomy;
- proof that public bind remains closed.

## Result

Closed 2026-06-28.

Implemented bounded P37 host-verified backing in
`server/igniter-web/src/live_bind_check.rs`: non-loopback `live-bind-check`
now sets `signed_passport_path_wired=true` only after loading the referenced
durable verifier material, parsing one 64-hex-character 32-byte trusted issuer
key, constructing `PassportVerifier`, and validating it with a synthetic signed
passport probe. Missing material refuses with
`signed_passport_verifier_unavailable`; malformed material refuses with
`signed_passport_verifier_invalid`; verdict output remains secret-safe.

Public bind remains closed: the real `Run` path still calls
`authorize_bind(addr, None)`, and the dry-run never opens a socket.

Proof packet:

```text
lab-docs/lang/lab-igniter-web-inbound-signed-passport-durable-key-p37-v0.md
```

Verification:

```bash
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine live_bind_check -- --nocapture
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_dry_run_tests -- --nocapture
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests -- --nocapture
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test signed_passport_dataplane_tests -- --nocapture
cargo fmt --manifest-path server/igniter-web/Cargo.toml
git diff --check
```
