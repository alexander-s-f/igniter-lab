# Card: LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7 — read-back resolution of unknown writes

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole P1–P6b picture; P7 is the milestone's tail #1.

**Status: CLOSED 2026-06-15 — reconciliation implemented + proven.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 6 machine tests
(`igniter-machine/tests/capability_io_reconcile_tests.rs`); full suite green
(`cargo test --no-default-features`: **76 passed total**). Design doc:
`lab-docs/lang/lab-machine-capability-io-reconciliation-p7-v0.md`.

## Goal (met)

Resolve an `unknown_external_state` write by **reading the target back** (never re-writing):
→ `committed` / `permanent_failure` / still-`unknown`. No blind retry. Prerequisite for a retry
scheduler.

## Implementation

- `write.rs`: `WriteState::PermanentFailure` (terminal, reached only by P7); write receipt now
  records `target_store` / `target_key` / `value_digest` (digest, not raw value) for read-back;
  `value_digest()` helper.
- `reconcile.rs`: `reconcile_unknown_write(receipts, substrate, clock, capability_id,
  idempotency_key) -> ReconcileResult { NotApplicable(state) | ResolvedCommitted |
  ResolvedPermanentFailure | StillUnknown }`. Scans the target's append-only history
  (`facts_for`); resolves only `unknown` receipts; idempotent on terminals; writes only the
  receipt ledger.

## Decisions

- read-back not retry (never calls a write executor / mutates the substrate — proven by
  unchanged version count);
- append-only history scan (value ever present → committed, even if later superseded);
- substrate unavailable → still unknown, receipt untouched;
- re-issue after permanent_failure requires a NEW idempotency key (old key replays terminal).

## Caveat (documented)

Matches by (store, key, value_digest); an independent same-value write to the same key reads as
"ours landed". Closing it fully needs a fact↔receipt correlation id (later slice).

## Proof (6 tests)

`reconcile_resolves_committed_when_value_landed`,
`reconcile_resolves_permanent_failure_when_absent`,
`reconcile_still_unknown_when_substrate_unavailable`, `reconcile_is_noop_on_terminal_receipt`,
`reconciled_committed_then_replays`, `reconcile_twice_is_idempotent`.

## Closed

Read-back only; no substrate write / mutation retry. No retry scheduler. No compensation. No
network beyond the substrate read. No language change. No contract-body IO.

## Next

- retryable + bounded retry scheduler (unblocked — reconciled `permanent_failure` is the safe
  re-issue signal, new idempotency key);
- compensation (`aborted`); fact↔receipt correlation id; write-succeeded-but-receipt-failed
  window; HTTP/SparkCRM executor (after retry).
