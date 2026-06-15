# lab-machine-capability-io-authority-p5-v0 — typed capability passport

**Card:** `LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5` (route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`,
branch A — harden the boundary before write IO)
**Status:** CLOSED — typed caller authority implemented + proven. 9 machine tests
(`tests/capability_io_authority_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 9 + 5 + 9 + 5 + 13 + 12 = 53).
**Boundary held:** minimal verifiable passport — NO OAuth/JWT/ACL/roles/sessions; verified at
the host boundary; contract/VM never receive it; no write substrate; no network.

## What P5 changes

P4 closed time authority. P5 closes the second base invariant: **caller authority**. Presence-
only `authority_ref` is replaced (for the typed path) by a verifiable `CapabilityPassport`,
checked at the host boundary before the executor.

```text
contract declares effect/capability
host VERIFIES passport (capability + scope + not-revoked + not-expired)   ← P5
host injects capability executor
receipt records authority digest (evidence)                              ← P5
replay requires the SAME authority digest                                ← P5
```

## Implementation

`igniter-machine/src/capability.rs`:
- `CapabilityPassport { subject, capability_id, scopes, issued_at, expires_at, revoked,
  evidence_digest }` + `authority_digest()` (blake3 over subject|capability|sorted-scopes|
  evidence — identity, independent of validity fields).
- `verify_passport(passport, capability_id, required_scope, clock) -> Result<digest, AuthRefusal>`
  — pure, no IO; expiry uses the **injected clock** (P4); refusals: `WrongCapability`,
  `MissingScope`, `Revoked`, `Expired`.
- `run_effect_with_passport(registry, receipts, clock, passport, required_scope, req, mode)`
  — verifies at the boundary, then the shared `run_effect_core`.
- Refactor: extracted `run_effect_core` (executor + receipt + idempotency/replay), shared by
  the presence-only path (`run_effect_with_clock`) and the passport path. **Zero churn** to
  P1–P4 call sites; the receipt gains an `authority_digest` field alongside `authority_ref`.

`service_loop.rs`: `run_service_with_passport(machine, registry, clock, passport,
required_scope, req, mode)`.

## Decisions (per card)

- **Expiry uses the injected `ClockProvider`** (P4) — proven by clock@200 vs clock@50 around
  `expires_at=100`.
- **Revoked / expired / wrong-capability / wrong-scope → runtime refusal, NO receipt** (nothing
  happened externally).
- **Executor denial remains denial-as-data WITH receipt** (passport passed, executor refused).
- **Replay policy**: same `capability_id + idempotency_key` AND **same `authority_digest`**
  (default strict). A receipt presented with a different authority is refused
  (`replay: authority scope mismatch`). A `replay_override` knob is a documented future slice,
  not implemented (default = strict).
- **Authority is host-side**: `dispatch` takes no passport; the contract/VM never receive it.

## Proof (9 tests, `tests/capability_io_authority_tests.rs`)

| claim | test |
|---|---|
| valid passport authorizes; receipt records `authority_digest` | `valid_passport_authorizes_and_records_digest` |
| wrong capability → refused, no executor, no receipt | `wrong_capability_refused_no_receipt` |
| missing scope → refused, no receipt | `missing_scope_refused_no_receipt` |
| revoked → refused, no receipt | `revoked_passport_refused_no_receipt` |
| expiry uses injected clock (200→Expired, 50→OK) | `expiry_uses_injected_clock` |
| `verify_passport` unit refusals (all four + ok) | `verify_passport_unit_refusals` |
| replay requires same authority digest (different passport → refused; same → replay) | `replay_requires_same_authority_digest` |
| executor denial under passport path → denial-as-data with receipt | `executor_denial_remains_denial_as_data` |
| authority host-side: `dispatch` 0 / host boundary authorizes on real `ExecuteQuery` | `authority_is_host_side_not_contract` |

## Closed (held)

No OAuth/JWT parsing. No external auth service. No user/session model. No role hierarchy. No
write substrate. No network. The passport's `evidence_digest` is opaque (folded into the
identity digest; its internal structure is not parsed/validated here). No contract access to
the passport.

## Next route

- **P6** `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` — receipt-gated idempotent write substrate, now
  unblocked: time authority (P4) + caller authority (P5) are both in place. Write IO needs
  idempotent write semantics (the receipt must **gate** the write, not just record it),
  partial-failure / unknown-after-write handling, and duplicate prevention — almost its own
  small covenant; scope it tightly.

Open items carried forward: subject/scope detail in the receipt (currently digest-only);
`replay_override` policy knob; signature verification of `evidence_digest` (opaque today);
`retryable` + retry scheduler.
