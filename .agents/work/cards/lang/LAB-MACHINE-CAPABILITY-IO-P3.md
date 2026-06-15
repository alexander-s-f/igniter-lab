# Card: LAB-MACHINE-CAPABILITY-IO-P3 — first real substrate (read-only local TBackend)

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole P1–P6b picture; this is one slice of it.

**Status: CLOSED 2026-06-15 — first real executor implemented + proven.**
Route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. Builds on P1 (executor+receipt) and P2
(host entrypoint). 5 machine tests (`igniter-machine/tests/capability_io_real_tests.rs`);
full machine suite green (`cargo test --no-default-features`: 9 + 5 + 13 + 12 = 39). Design
doc: `lab-docs/lang/lab-machine-capability-io-p3-real-substrate-v0.md`.

## Goal (met)

Bind ONE real substrate behind the proven boundary: a **read-only local TBackend/RocksDB
read**, reusing `run_service` and the receipt/idempotency machinery unchanged. Only a real
`CapabilityExecutor` replaces the fake.

## Implementation

`igniter-machine/src/executors.rs` — `TBackendReadExecutor`: read-only wrapper over
`Arc<dyn TBackend>`. Reads `{store, key, as_of?}` from the request args via `read_as_of`.
Receipts stay in `machine.storage` (separate from the read substrate).

Explicit outcome mapping (acceptance #3/#4):
- `Ok(Some)` → `Succeeded{result:fact.value}`
- `Ok(None)` → `PermanentFailure` (definite not-found)
- `Err` (unavailable) → `UnknownExternalState` (substrate didn't answer — epistemic)
- malformed args → `PermanentFailure`
Decision: unavailability → unknown; transient→`retryable` + scheduler is a later slice.

## Acceptance (all proven)

1. First call reads the real backend + writes a receipt — `real_rocksdb_read_succeeds_and_writes_receipt` (RocksDB on disk).
2. Second call same idempotency key replays; backend read not repeated; explicit `Replay` too — `real_read_idempotency_replays_without_backend`.
3. Missing record → typed `permanent_failure`, no panic — `missing_record_is_permanent_failure_not_panic`.
4. Backend unavailable → `unknown_external_state`, recorded as receipt — `backend_unavailable_is_unknown_external_state` (real `RemoteTcpBackend` → dead port).
5. Contract body still cannot perform IO through `dispatch` (read-count 0 → 1) — `contract_body_cannot_read_real_backend`.

Two real `TBackend` impls exercised: `RocksDBBackend` (read path) + `RemoteTcpBackend`
(unavailable path) — #4 proven against a real backend's real connection failure.

## Closed

ONE real substrate; read-only (no writes). No HTTP/Redis/queue/network policy/TLS/credentials.
No retry scheduler. No language syntax. No contract-body IO. No MCP hot path. No canon IO
claim. No D-001 implemented claim. `TBackend` not replaced — it is the substrate.

## Next (each its own bounded card; none started)

- real clock for receipt `transaction_time` (currently fixed `1.0`).
- richer authority (verified passport/capability-token, tie to `escape_boundaries`).
- `retryable` + bounded retry scheduler (transient vs permanent unavailability).
- a write/effect substrate (idempotent writes: receipt gates the write, not just records it).
- HTTP / SparkCRM API executor — only after clock + authority + retry are settled.

## Track status

The capability IO boundary (P1 model → P2 declared-effect host → P3 real substrate) is proven
end-to-end. `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` route complete through P3. Portfolio batch
entry filed: `igniter-gov/portfolio/governance/2026-06-15-lab-machine-capability-io-p1-p3-real-substrate-v0.md`.
