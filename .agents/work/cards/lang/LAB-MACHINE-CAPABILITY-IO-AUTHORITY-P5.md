# Card: LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5 — typed capability passport

**Status: CLOSED 2026-06-15 — typed caller authority implemented + proven.**
Route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`, branch A (harden the boundary before write IO).
9 machine tests (`igniter-machine/tests/capability_io_authority_tests.rs`); full machine suite
green (`cargo test --no-default-features`: 9 + 5 + 9 + 5 + 13 + 12 = 53). Design doc:
`lab-docs/lang/lab-machine-capability-io-authority-p5-v0.md`.

## Goal (met)

Replace presence-only `authority_ref` with a verifiable `CapabilityPassport`, checked at the
host boundary before the executor. Minimal — no OAuth/JWT/ACL/roles/sessions.

## Implementation

`capability.rs`:
- `CapabilityPassport { subject, capability_id, scopes, issued_at, expires_at, revoked,
  evidence_digest }` + `authority_digest()` (blake3 over subject|capability|sorted-scopes|
  evidence; identity, independent of validity fields).
- `verify_passport(passport, capability_id, required_scope, clock) -> Result<digest, AuthRefusal>`
  (`WrongCapability`/`MissingScope`/`Revoked`/`Expired`; expiry uses the injected P4 clock).
- `run_effect_with_passport(...)` → verify at boundary → shared `run_effect_core`.
- Refactor: `run_effect_core` (executor + receipt + idempotency/replay) shared by presence-only
  (`run_effect_with_clock`) + passport paths. **Zero churn** to P1–P4. Receipt gains
  `authority_digest` alongside `authority_ref`.

`service_loop.rs`: `run_service_with_passport(machine, registry, clock, passport,
required_scope, req, mode)`.

## Decisions

- Expiry via injected `ClockProvider` (P4).
- revoked/expired/wrong-capability/wrong-scope → runtime refusal, **no receipt**.
- executor denial → **denial-as-data with receipt** (passport passed, executor refused).
- replay policy: same `capability_id + idempotency_key` AND same `authority_digest` (default
  strict; `replay_override` is a documented future knob, not implemented).
- authority host-side: `dispatch` takes no passport; contract/VM never receive it.

## Proof (9 tests)

`valid_passport_authorizes_and_records_digest`, `wrong_capability_refused_no_receipt`,
`missing_scope_refused_no_receipt`, `revoked_passport_refused_no_receipt`,
`expiry_uses_injected_clock`, `verify_passport_unit_refusals`,
`replay_requires_same_authority_digest`, `executor_denial_remains_denial_as_data`,
`authority_is_host_side_not_contract` (real `ExecuteQuery`).

## Closed

No OAuth/JWT parsing. No external auth service. No user/session. No role hierarchy. No write
substrate. No network. `evidence_digest` opaque (not parsed/validated). No contract access.

## Next

- **P6** `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` — receipt-gated idempotent write substrate, now
  unblocked (P4 time + P5 caller authority in place). Scope tightly: idempotent write semantics
  (receipt **gates** the write), partial-failure / unknown-after-write, duplicate prevention.

Open: subject/scope detail in receipt (digest-only today); `replay_override`; signature
verification of `evidence_digest`; `retryable` + retry scheduler.
