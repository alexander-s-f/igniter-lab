# lab-machine-capability-io-p3-real-substrate-v0 — first real substrate (read-only local TBackend)

**Card:** `LAB-MACHINE-CAPABILITY-IO-P3` (route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`)
**Status:** CLOSED — first real executor implemented + proven. 5 machine tests
(`tests/capability_io_real_tests.rs`), full machine suite green
(`cargo test --no-default-features`: 9 + 5 + 13 + 12 = 39).
**Boundary held:** ONE real substrate, **read-only**, local TBackend/RocksDB (not HTTP); no
writes; no external network policy/TLS/retry scheduler; contract body still does no IO.

## What P3 adds

P1 proved the executor+receipt model; P2 wired a declared-effect contract to `run_service`
with fake executors. P3 replaces the fake with the **first real `CapabilityExecutor`** over a
real `TBackend` — and changes nothing else:

```text
declared-effect contract (ExecuteQuery)
-> run_service (UNCHANGED) -> TBackendReadExecutor (REAL) -> RocksDBBackend read
-> receipt fact in machine.storage -> typed outcome / replay
```

Implementation: `igniter-machine/src/executors.rs` — `TBackendReadExecutor`, a read-only
wrapper over `Arc<dyn TBackend>` (so any real backend — RocksDB on disk, remote-TCP — is a
capability). Receipts continue to live in `machine.storage`, **separate** from the read
substrate (external data store ≠ receipt ledger).

## Explicit outcome decisions (acceptance #3/#4)

The executor maps backend results to the epistemic taxonomy with deliberate, documented
choices:

| backend result | outcome | rationale |
|---|---|---|
| `Ok(Some(fact))` | `Succeeded { result: fact.value }` | the record exists |
| `Ok(None)` | `PermanentFailure` | a **definite** "not found" — knowable negative, not epistemic |
| `Err(_)` (unavailable) | `UnknownExternalState` | the substrate **did not answer** — we cannot determine the external truth, so it stays epistemic, never collapsed to "failed" |
| malformed args (no store/key) | `PermanentFailure` | the request can never succeed as written |

**Decision on #4**: unavailability → `unknown_external_state`. Splitting *transient*
unavailability into `retryable` (and a retry scheduler) is an explicit later slice, not P3.

## Acceptance — all proven (5 tests, `tests/capability_io_real_tests.rs`)

| # | acceptance | test | substrate |
|---|---|---|---|
| 1 | first call reads the real backend + writes a receipt | `real_rocksdb_read_succeeds_and_writes_receipt` | RocksDB (on-disk temp dir) |
| 2 | second call same idempotency key replays receipt; backend read NOT repeated (and explicit `Replay` too) | `real_read_idempotency_replays_without_backend` | RocksDB |
| 3 | missing record → typed `permanent_failure`, no panic | `missing_record_is_permanent_failure_not_panic` | RocksDB |
| 4 | backend unavailable → `unknown_external_state` (recorded as a receipt fact) | `backend_unavailable_is_unknown_external_state` | RemoteTcp → dead port (real connection-refused) |
| 5 | contract body still cannot perform IO through `dispatch` (read-count 0 after dispatch, 1 after host) | `contract_body_cannot_read_real_backend` | RocksDB |

Two real `TBackend` impls are exercised: `RocksDBBackend` (real on-disk serialization) for the
read path, and `RemoteTcpBackend` (genuinely unreachable port) for the unavailable path — so
#4 is proven against a real backend's real failure, not a simulated error.

## What did NOT change (the point)

`run_service`, `discover_effect_surface`, `run_effect`, the receipt schema, and the idempotency
/replay logic are **byte-for-byte the same** as P2. The only new code is one `CapabilityExecutor`
impl. This is the payoff of the P1/P2 boundary: binding a real substrate is a leaf change.

## Closed (held)

ONE real substrate only. Read-only — no writes to the external store. No HTTP/Redis/queue.
No network policy / TLS / DNS / credentials. No retry scheduler / background worker. No
language syntax. No contract-body IO. No MCP hot path. No canon IO claim. No D-001 implemented
claim. `TBackend` not replaced — it IS the substrate.

## Next route

The IO boundary is now proven end-to-end on a real substrate. Candidate follow-ups (each its
own bounded card; none implied as started):

- **real clock** for receipt `transaction_time` (currently fixed `1.0`) — needed before
  receipts are used for real audit windows.
- **richer authority**: replace presence-only `authority_ref` with a verified passport /
  capability-token shape (tie to the existing `escape_boundaries` / capability grammar).
- **`retryable` + scheduler**: split transient vs permanent unavailability and add a bounded
  retry policy (kept out of P3 deliberately).
- **a write/effect substrate** (e.g. append a fact) — a larger step: idempotent writes need
  the receipt to gate the write, not just record it. Read-only was chosen first on purpose.
- **HTTP / SparkCRM API executor** — only after clock + authority + retry are settled; same
  trait + receipt + idempotency, new `CapabilityExecutor` impl.
