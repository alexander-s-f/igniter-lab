# lab-machine-capability-io-reconciliation-p7-v0 — read-back resolution of unknown writes

**Card:** `LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #1)
**Status:** CLOSED — reconciliation implemented + proven. 6 machine tests
(`tests/capability_io_reconcile_tests.rs`); full machine suite green
(`cargo test --no-default-features`: **76 passed total**).
**Boundary held:** read-back only — reconciliation never writes the substrate, never retries
the mutation. No retry scheduler, no compensation, no network.

## The problem P7 solves

A write that resolved to `unknown_external_state` (P6a/P6b) left the mutation status genuinely
unknown — the prepare receipt was written, the executor was called, but we never got
confirmation. P6a forbids blind retry. P7 is the safe way out: **read the target back** to
learn what actually happened, and resolve the receipt.

```text
read-back the target fact history (append-only)
  our value present in history -> committed          (the mutation did land)
  our value absent             -> permanent_failure  (it did not land)
  substrate read error         -> still unknown      (cannot determine; no resolution, no write)
```

Reconciliation writes only to the **receipt ledger** (upgrading the unknown receipt to a
terminal state), never to the external substrate. It is the prerequisite for any future retry:
only a reconciled `permanent_failure` is safe to re-issue — and then only under a NEW
idempotency key.

## Implementation

- `write.rs`: `WriteState` gains the terminal `PermanentFailure` (reached only by P7); the
  write receipt now records `target_store`, `target_key`, and `value_digest` (a digest, not the
  raw value — privacy preserved) so reconciliation can read the target back. `value_digest()`
  helper added.
- `reconcile.rs`: `reconcile_unknown_write(receipts, substrate, clock, capability_id,
  idempotency_key) -> ReconcileResult` — looks up the receipt; if it is `unknown_external_state`,
  scans the target's append-only history via `facts_for` and resolves; otherwise a no-op.
  `ReconcileResult ∈ { NotApplicable(state), ResolvedCommitted, ResolvedPermanentFailure,
  StillUnknown }`.

A reconciled receipt carries `reconciled: true`. A terminal receipt (already
committed/denied/permanent_failure) is returned `NotApplicable` — reconciliation is idempotent.

## Decisions

- **Read-back, not retry.** Reconciliation calls `facts_for` on the substrate; it never calls
  a write executor and never mutates. Proven: substrate version count is unchanged across a
  reconcile pass.
- **Append-only history scan**, not just latest: if our value ever appeared at the target it
  landed → `committed`, even if a later write superseded it. Absent from all versions →
  `permanent_failure`.
- **Substrate unavailable → still unknown.** No premature resolution; the receipt is left
  unknown and nothing is written.
- **Re-issue after permanent_failure** needs a NEW idempotency key — the old key replays the
  terminal `permanent_failure` receipt (no silent retry under the same envelope).

## Known caveat (documented, bounded)

The read-back matches by `(target_store, target_key, value_digest)`. An *independent* write of
the **same value** to the **same key** by someone else would be read as "ours landed"
(false-committed). For idempotency-keyed writes this is unlikely, but closing it fully needs a
fact↔receipt correlation id (the executor would stamp the written fact with the receipt key).
That correlation is a later slice; P7 documents the caveat rather than hiding it.

## Proof (6 tests, `tests/capability_io_reconcile_tests.rs`)

| claim | test |
|---|---|
| unknown → committed when the value actually landed; substrate unchanged | `reconcile_resolves_committed_when_value_landed` |
| unknown → permanent_failure when the value never landed; no write | `reconcile_resolves_permanent_failure_when_absent` |
| substrate unavailable → still unknown; receipt untouched | `reconcile_still_unknown_when_substrate_unavailable` |
| terminal receipt → NotApplicable (idempotent no-op) | `reconcile_is_noop_on_terminal_receipt` |
| after reconcile→committed, re-issued same write replays (no re-exec) | `reconciled_committed_then_replays` |
| reconcile twice → second pass is a no-op | `reconcile_twice_is_idempotent` |

## Closed (held)

Read-back only — no substrate write, no mutation retry. No retry scheduler. No compensation
(`aborted` still reserved). No network beyond the substrate's own read. No language change. No
contract-body IO.

## Next route (each its own bounded card; none started)

- **retryable + bounded retry scheduler** — now unblocked: a reconciled `permanent_failure` is
  the safe signal to re-issue (new idempotency key). Transient vs permanent split lives here.
- compensation (`aborted`) — explicit host rollback after prepare.
- fact↔receipt correlation id — close the same-value caveat above.
- the write-succeeded-but-receipt-failed window — executor-side idempotency / two-way handshake.
- HTTP / SparkCRM API executor — only after retry + reconciliation are mature (now one of the
  two prerequisites, reconciliation, is in place).
