# Card: LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13 — reconcile an unknown by correlation id

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; P13 closes milestone tail #5 (the P7 same-value caveat) before leaving loopback.

**Status: CLOSED 2026-06-15 — correlation-based reconciliation + fake-resolver proof.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 8 machine tests
(`igniter-machine/tests/capability_io_correlation_tests.rs`); full suite green
(`cargo test --no-default-features`: 127 capability+machine / 136 incl. coordination). Design
doc: `lab-docs/lang/lab-machine-capability-io-correlation-reconcile-p13-v0.md`.

## Goal (met)

Reconcile an `unknown_external_state` write by its `correlation_id` (precise per-request
identity) — closing P7's same-value caveat. Read-only; never re-issues. Fake resolver only.

## Implementation

`correlation.rs`: `CorrelationResolver { async lookup -> Landed|NotFound|Unavailable }`,
`reconcile_unknown_by_correlation(...) -> CorrelationReconcileResult { ResolvedCommitted |
ResolvedPermanentFailure | StillUnknown | MissingCorrelation | NotApplicable(state) | NoReceipt }`,
fake `MapCorrelationResolver`. `write_receipt` (both paths) now pulls `correlation_id` from the
executor result OR the request payload/args (so an `unknown` write keeps the correlation trail).

## Acceptance (all proven, 8 tests)

landed→committed; not-found→permanent_failure; **same value + different correlation → no false
match**; missing correlation → explicit `MissingCorrelation` (fall back to P7), no premature
resolution; unavailable → still unknown; reconcile never re-sends (no executor param);
compensation references original correlation id; committed→NotApplicable / absent→NoReceipt.

## Closed

Fake resolver only. No external internet / TLS / SparkCRM. No retry-scheduler changes. No
compensation automation. Read-only.

## Next

- **P14** allowlisted external host + TLS (real TLS transport + vetted allowlist + real
  `CorrelationResolver` against the API status endpoint); **P15** SparkCRM executor; host-driven
  reconcile-then-compensate loop for unknowns.
