# LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26

Status: DONE
Date: 2026-06-27
Lane: igniter-lab / runtime / igniter-machine / foundation-hardening / T1

## Authority

Live `runtime/igniter-machine` source and tests decide this lab behavior. Audit
docs and prior proof docs were evidence only. This is local machine authority
wiring; it does not change public transport, listener, or bind policy.

## Verifier Threading

The existing signed primitive remains the authority source:

- `PassportVerifier`
- `sign_passport`
- `verify_passport_signed`

This slice wires signed verification onto explicit machine data-plane entrypoints:

- `write::run_write_effect_signed(...)`
  - authenticates with `verify_passport_signed` before the two-phase write gate;
  - forged, unsigned, or untrusted passports write no receipt and reach no executor;
  - after authenticity succeeds, existing capability/scope/expiry/revocation checks
    still run.
- `single_flight::run_write_effect_atomic_signed(...)`
  - signed variant of the per-key atomic write gate.
- `coordination::CoordinationHub::new_signed(...)`
  - stores an explicit `PassportVerifier`;
  - all pool and messenger guards route through the signed verifier when present.
- `service_loop::run_service_with_verified_passport(...)`
  - signed variant of the typed-passport service entrypoint.

`PassportVerifier` is now `Clone` so it can be carried by configured host
surfaces without global mutable state.

## Negative Tests

Added `runtime/igniter-machine/tests/signed_passport_dataplane_tests.rs`.

Covered:

- write path refuses a hand-constructed forged `evidence_digest`;
- write path refuses a passport signed by an untrusted issuer;
- write path accepts a valid signed passport;
- write path preserves missing-scope and expired-passport refusals;
- coordination path refuses a forged/unsigned passport via `CoordinationHub::new_signed`;
- coordination path accepts a valid signed passport and audits the allowed operation.

## Remaining Unsigned Call-Sites

These remain intentionally available as legacy/proof compatibility surfaces:

- `capability::run_effect_with_passport`
- `write::run_write_effect`
- `single_flight::run_write_effect_atomic`
- `coordination::CoordinationHub::new`

Current source callers still using legacy unsigned entrypoints include retry,
retry queue, ingress, bridge-effect, and frame-binding-effect paths. Migrating
those fully requires a larger host configuration decision: token/passport
resolution and fixture passports across the historical test matrix need signed
issuer material. This card therefore adds signed data-plane entrypoints and
proves forged passports are refused there instead of adding ad hoc bypasses.

## Verification

Commands run from `runtime/igniter-machine` unless noted otherwise:

```text
cargo test --test signed_passport_dataplane_tests
cargo test --test capability_io_signed_passport_tests --test capability_io_write_tests --test coordination_pools_tests --test coordination_messenger_tests --test coordination_recipe_tests --test coordination_transfer_tests --test capability_io_host_tests
cargo test
git diff --check
```

Results:

```text
cargo test --test signed_passport_dataplane_tests
  5 passed; 0 failed

focused adjacent tests
  capability_io_host_tests: 9 passed; 0 failed
  capability_io_signed_passport_tests: 5 passed; 0 failed
  capability_io_write_tests: 9 passed; 0 failed
  coordination_messenger_tests: 9 passed; 0 failed
  coordination_pools_tests: 9 passed; 0 failed
  coordination_recipe_tests: 7 passed; 0 failed
  coordination_transfer_tests: 9 passed; 0 failed

cargo test
  PASS - full runtime/igniter-machine default-feature test suite green
  feature-gated postgres/tls/sparkcrm tests were compiled as 0-test default runs

git diff --check
  PASS
```

Existing warnings remain in dependency/compiler/vm/machine test surfaces and
were not introduced by this card.
