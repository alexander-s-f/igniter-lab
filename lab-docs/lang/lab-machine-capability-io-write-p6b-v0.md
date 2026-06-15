# lab-machine-capability-io-write-p6b-v0 — real local TBackend write executor

**Card:** `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` (P6b slice; route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`, branch A)
**Status:** CLOSED — real local write executor behind the P6a protocol. 8 machine tests
(`tests/capability_io_write_real_tests.rs`); full machine suite green
(`cargo test --no-default-features`: **70 passed total**).
**Boundary held:** real LOCAL TBackend write only — no HTTP/queue/retry/compensation/
reconciliation.

## What P6b adds

P6a proved the receipt-gated write lifecycle on a fake executor. P6b binds a **real**
executor — `TBackendWriteExecutor` over an on-disk `RocksDBBackend` — and **changes nothing
else**: the prepare gate, idempotency, authority, replay, and no-blind-retry are exactly P6a.
The same leaf-change shape as P3 did for reads.

Implementation: `igniter-machine/src/executors.rs::TBackendWriteExecutor` (+ `failing()`
variant for the injected-failure proof) and `write::FactWrite` (the typed write target).

## The forced-identity decision (per card)

The write `payload_digest` is **forced to include the full target fact identity**:

```text
payload_digest = digest(store + key + value + valid_time)   -- via FactWrite::to_payload()
```

So two writes to *different* keys (or different `valid_time`) with the same value never collide
under one `(capability, idempotency_key)` envelope, and a reused idempotency key with a
different target is caught as a payload conflict (P6a #4). Proven directly
(`payload_digest_includes_target_identity`): same value + different key → different digest;
different valid_time → different digest; identical identity → identical digest (legitimate
replay).

## Outcome mapping (real executor)

- backend `write_fact` ok → `Succeeded` → receipt `committed`; fact readable from the backend.
- backend error / injected failure → `UnknownExternalState` → receipt `unknown_external_state`
  (we cannot claim the mutation did/did not land — epistemic), and the protocol then refuses to
  blindly retry. Malformed request (missing store/key) → `PermanentFailure`.

## Acceptance — all proven (8 tests, `tests/capability_io_write_real_tests.rs`)

| # | acceptance | test |
|---|---|---|
| 1 | success: prepared → backend fact → committed → read-back sees fact | `successful_write_full_lifecycle` |
| 2 | duplicate same key/payload → no second backend write (one version) | `duplicate_same_payload_no_second_backend_write` |
| 3 | duplicate same key/different payload → refusal before write | `duplicate_different_payload_refused_before_write` |
| 4 | missing/invalid authority → refusal, no receipt, no backend write | `missing_authority_no_write` |
| 5 | injected write failure → `unknown_external_state`, no blind retry | `injected_write_failure_is_unknown_no_blind_retry` |
| 6 | replay mode → no backend write | `replay_mode_no_backend_write` |
| 7 | contract body / VM still cannot write (dispatch has no write executor) | `contract_body_cannot_write` |
| — | payload digest includes target fact identity | `payload_digest_includes_target_identity` |

The write substrate is a real on-disk `RocksDBBackend`; receipts live in a separate store. #1
reads the fact back from the real backend after commit.

## Milestone

With P6b, igniter-machine has **real read + write local capability IO** with receipts,
idempotency, authority (typed passport), and a host clock — the full minimal production
data-plane on a real substrate:

```text
contract declares effect/capability
host ServiceLoop: authority (P5) + idempotency + clock (P4)
CapabilityExecutor: real local TBackend READ (P3) / WRITE (P6b)
EffectReceipt: bitemporal fact; write = two-phase gate (P6a)
replay / no-blind-retry / denial-as-data / unknown-as-epistemic
```

## Closed (held)

Real LOCAL TBackend write only. No HTTP/Redis/queue/socket/network. No retry scheduler. No
compensation (`aborted` reserved). No reconciliation loop. No write-after-unknown retry. No
language change. No contract-body IO. No MCP hot path.

## Next route (each its own bounded card; none started)

- reconciliation of `unknown_external_state` (read-back / verify after an unknown write).
- compensation (`aborted`) for explicit host rollback after prepare.
- `retryable` + bounded retry (split transient from permanent; safe only with reconciliation).
- the write-succeeded-but-receipt-failed window (needs executor-side idempotency or a two-way
  handshake — currently the prepare gate covers the receipt-then-write direction only).
- HTTP / SparkCRM API executor — only after retry + reconciliation are mature.
