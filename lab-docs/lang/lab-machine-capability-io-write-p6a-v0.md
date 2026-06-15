# lab-machine-capability-io-write-p6a-v0 — receipt-gated write semantics

**Card:** `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` (P6a slice; route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`, branch A)
**Status:** CLOSED — readiness/design + lifecycle proven on a fake write executor. 9 machine
tests (`tests/capability_io_write_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 9 + 5 + 9 + 5 + 13 + 9 + 12 = 62).
**Boundary held:** fake write executor only — no real substrate, no HTTP/queue, no retry
scheduler. P6b binds a local TBackend write executor.

## The read/write asymmetry

```text
read:   receipt records WHAT HAPPENED
write:  receipt must GATE WHETHER the external mutation may happen
```

Write opens failure states read never had: receipt-written-but-write-failed,
write-succeeded-but-receipt-failed, timeout-after-dispatch (mutation unknown), retry-after-
unknown, duplicate-key-different-payload. P6a models them deliberately rather than "just
writing."

## Two-phase receipt lifecycle

```text
prepared   -- written BEFORE the executor (the gate). If it cannot be written, NO executor call.
committed  -- executor succeeded
denied     -- executor refused (denial-as-data)
unknown_external_state -- timeout / no answer; mutation status UNKNOWN; never blindly retried
aborted    -- reserved: explicit host abort after prepare (compensation) — not produced in P6a
```

`prepared` and the terminal state are two facts on the same `(store, key)` receipt timeline;
the terminal (later-appended) fact wins the read. A dangling `prepared` (crash mid-write) reads
back as **unknown** — we cannot claim the mutation did or did not happen.

## Must-decide answers (per card)

**1. Lifecycle:** `prepared / committed / denied / unknown_external_state` + reserved
`aborted` (above).

**2. Idempotency key binds to:** `capability_id + operation + authority_digest +
payload_digest`. (`operation` is on the receipt; `payload_digest` = blake3 of the canonical
payload JSON; `authority_digest` from P5.)

**3. Duplicate same key + same payload:** replay the existing terminal receipt; the executor is
NOT reached again (proven: `attempts == 1`, `applied == 1`).

**4. Duplicate same key + different payload:** refuse **before** the executor, no write
(`idempotency key reused with a different payload`); the original receipt is intact.

**5. External timeout after dispatch:** `unknown_external_state`. A subsequent identical call
returns unknown and does **NOT** re-run the executor — **no blind retry** (proven:
`attempts == 1` across two calls). Reconciliation is out of band (P6b+).

**6. Receipt write failure:** if the `prepared` receipt cannot be written, the executor is not
called (proven with a backend whose `write_fact` always errors → `attempts == 0`).

**7. P6a implementation target:** **fake write executor only** (`FakeWriteExecutor` with
`Commit` / `Deny` / `Timeout` behaviors). No real substrate — that is P6b.

## Implementation

`igniter-machine/src/write.rs`:
- `WriteState` (lifecycle), `WriteRequest { capability_id, operation, idempotency_key,
  payload }`, `WriteResult { state, result, detail }`, `payload_digest()`.
- `run_write_effect(registry, receipts, clock, passport, required_scope, req, mode)` — the
  receipt-gated runner: authority (P5) → idempotency/duplicate/replay resolution → **prepare
  gate** → execute once → finalize. Reuses `verify_passport` + `ClockProvider`.
- `FakeWriteExecutor` (proof only): records applied mutations + counts attempts.

## Proof (9 tests, `tests/capability_io_write_tests.rs`)

| claim | test |
|---|---|
| commit lifecycle: two-phase receipt (prepared + committed), terminal wins | `commit_lifecycle_writes_two_phase_receipt` |
| duplicate same payload → replay, mutation runs once | `duplicate_same_payload_replays_no_second_write` |
| duplicate different payload → refused before executor; original intact | `duplicate_different_payload_refused` |
| executor denial → `denied` state with receipt (no mutation applied) | `executor_denial_is_denied_state_with_receipt` |
| timeout → `unknown_external_state`; second call no blind retry | `timeout_is_unknown_and_not_blindly_retried` |
| prepare-receipt failure → executor not called | `prepare_receipt_failure_blocks_executor` |
| authority refused (missing scope) → no receipt, no executor | `authority_refused_writes_no_receipt` |
| replay with different authority → refused | `replay_with_different_authority_refused` |
| replay mode without a receipt → unknown, nothing prepared | `replay_mode_without_receipt_is_unknown` |

## Closed (held)

Fake write executor only. No real substrate/DB/HTTP/queue/filesystem. No retry scheduler /
background worker. No compensation engine (`aborted` reserved, not driven). No language change.
No contract-body IO. No MCP hot path. The `prepared→committed` overwrite relies on the receipt
timeline's last-write-wins at equal tx-time (and strictly-greater tx-time under a real clock).

## Next route — P6b

`LAB-MACHINE-CAPABILITY-IO-WRITE-P6b` — implement a **local TBackend write executor** behind
this exact protocol (no HTTP/queue, no retry scheduler). The protocol does not change; only a
real write `CapabilityExecutor` replaces the fake — the same leaf-change shape as P3 for reads.
Open beyond P6b: reconciliation of `unknown_external_state` (read-back/verify), compensation
(`aborted`), `retryable` + bounded retry, the write-succeeded-but-receipt-failed window
(needs executor-side idempotency or a two-way handshake).
