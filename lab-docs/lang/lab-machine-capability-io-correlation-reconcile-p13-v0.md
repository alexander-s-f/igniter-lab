# lab-machine-capability-io-correlation-reconcile-p13-v0 — reconcile by correlation id

**Card:** `LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #5)
**Status:** CLOSED — correlation-based reconciliation + fake-resolver proof. 8 machine tests
(`tests/capability_io_correlation_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 127 capability+machine / 136 incl. coordination).
**Boundary held:** fake/loopback resolver only — no external internet, no SparkCRM, no TLS, no
retry-scheduler or compensation-automation changes.

## Why — closing the P7 same-value caveat

P7 reconciles an `unknown_external_state` write by reading the TARGET VALUE back — which has a
same-value caveat: an independent identical write could falsely match. P13 reconciles by the
`correlation_id` (first-class since P11) — a precise per-request identity. External APIs almost
always expose a correlation/request id as the only reliable way to learn the fate of a request
after a lost response.

```text
unknown_external_state receipt (carries correlation_id)
-> resolver.lookup(correlation_id)     (READ-ONLY; never re-issues)
   Landed      -> committed
   NotFound    -> permanent_failure
   Unavailable -> still unknown
```

## Implementation

- `correlation.rs`: `CorrelationResolver { async lookup(correlation_id) -> CorrelationLookup
  {Landed|NotFound|Unavailable} }`; `reconcile_unknown_by_correlation(receipts, resolver, clock,
  capability_id, idempotency_key) -> CorrelationReconcileResult { ResolvedCommitted |
  ResolvedPermanentFailure | StillUnknown | MissingCorrelation | NotApplicable(state) |
  NoReceipt }`; fake `MapCorrelationResolver`.
- The resolved receipt is appended (committed/permanent_failure), tagged `reconciled_by:
  "correlation_id"`; the unknown fact is preserved (auditable).
- `write_receipt` (read + write paths) now pulls `correlation_id` from the executor result OR the
  request payload/args — so an `unknown` write (whose result is null) still carries the
  correlation trail.

## Acceptance — all proven (8 tests)

| # | acceptance | test |
|---|---|---|
| 1 | unknown with correlation reconciled by lookup → committed | `unknown_reconciled_committed_by_correlation` |
| 2 | same value, different correlation → no false match | `same_value_different_correlation_no_false_match` |
| 3 | missing correlation → explicit `MissingCorrelation` (caller falls back to P7), no premature resolution | `missing_correlation_returns_missing` |
| 4 | committed-by-correlation upgrades the receipt to committed | `unknown_reconciled_committed_by_correlation` |
| 5 | not-found-by-correlation upgrades to permanent_failure | `not_found_by_correlation_is_permanent_failure` |
| 6 | lookup unavailable → still unknown | `lookup_unavailable_stays_unknown` |
| 7 | reconciliation never re-sends the original effect (read-only) | `reconciliation_never_resends` |
| 8 | compensation references the original `correlation_id` | `compensation_references_original_correlation` |
| — | committed → NotApplicable; absent → NoReceipt | `committed_is_not_applicable_and_absent_is_no_receipt` |

#2 is the headline: two unknown receipts with the IDENTICAL value but different correlation ids;
the resolver knows only correlation A landed → A→committed, B→permanent_failure. Identical value
does not cause a false match. #7: `reconcile_unknown_by_correlation` takes no executor — it cannot
re-send by construction; the original write executor's attempt count is unchanged after reconcile.

## Closed (held)

Fake resolver only. No external internet / TLS / SparkCRM. No retry-scheduler changes. No
compensation automation. Read-only reconciliation (never re-issues).

## Next route

The reconciliation story is now precise (value AND correlation). Door past loopback is clean:
- **P14** `LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14` — allowlisted external host + TLS (the
  `with_allowed_hosts` mechanism already exists; add a real TLS-capable transport, an explicit
  vetted host allowlist, and a real `CorrelationResolver` against the API's status endpoint).
- **P15** SparkCRM API executor (forward + compensating actions, reconcile by correlation).
- a host-driven (non-automatic) reconcile-then-compensate loop for unknowns.
