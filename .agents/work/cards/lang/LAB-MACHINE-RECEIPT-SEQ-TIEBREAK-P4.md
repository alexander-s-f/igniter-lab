# LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4

Status: TODO
Route: standard / igniter-lab / runtime / igniter-machine / receipt ordering
Skill: idd-agent-protocol

## Goal

Implement the P3 decision: receipt "latest" ordering must no longer rely on wall-clock-only
`transaction_time` or incidental vector insertion order when multiple receipt facts share the same
timestamp.

Add a local, machine-owned per-process `receipt_seq` tie-breaker for receipt facts and use
`(transaction_time, receipt_seq)` wherever the machine picks the latest receipt state.

This is deliberately **not** TBackend server `seq_id`, not durable global sequencing, and not a
Postgres CAS change. It is a small DB-free ordering repair for machine receipts.

## Current Authority

Live source wins over this card if it has moved.

Read first:

- `lab-docs/lang/lab-machine-receipt-seqid-ordering-readiness-p3-v0.md`
- `runtime/igniter-machine/src/capability.rs`
- `runtime/igniter-machine/src/backend.rs`
- `runtime/igniter-machine/src/recovery.rs`
- `runtime/igniter-machine/src/observability.rs`
- `runtime/igniter-machine/tests/capability_io_clock_tests.rs`
- `runtime/igniter-machine/tests/postgres_reconcile_tests.rs`

Known live facts from the P3 readiness pass:

- `transaction_time` is host-stamped by the injected `ClockProvider`.
- Replay reads the existing receipt and must not rewrite time or sequence.
- Latest receipt selection currently relies on `transaction_time` only in multiple places.
- Equal timestamps can leave prepared/terminal ordering to incidental insertion behavior.
- Non-monotonic clocks are a known host reality; `receipt_seq` is only a tie-break, not a
  replacement for audit time.

## Requirements

- Add `receipt_seq` to machine receipt values.
- Assign `receipt_seq` at receipt-write time from a local per-process source.
- Preserve existing `transaction_time` semantics and public audit meaning.
- Use `(transaction_time, receipt_seq)` for latest receipt selection where receipt state matters.
- Keep replay idempotent: replayed calls must not write a new receipt and must not increment sequence.
- Keep Postgres `effect_receipts` CAS untouched.
- Do not adopt TBackend daemon `seq_id` in this card.

## Acceptance

- [ ] Equal-timestamp receipt facts resolve deterministically: a later terminal receipt wins over an
      earlier prepared/unknown receipt when `receipt_seq` is higher.
- [ ] Non-monotonic wall-clock test documents the boundary: transaction time remains audit time;
      `receipt_seq` only tie-breaks equal timestamps.
- [ ] Replay with the same idempotency key returns the recorded outcome and does not write a new
      receipt or increment the sequence.
- [ ] Recovery / observability latest-state helpers use the same ordering helper rather than
      duplicating wall-clock-only logic.
- [ ] Existing capability IO, Postgres write/reconcile, and clock tests remain green.
- [ ] No changes to TBackend daemon, Postgres CAS DDL, or external wire protocol are required.
- [ ] `git diff --check` clean.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test -p igniter-machine --test capability_io_clock_tests
cargo test -p igniter-machine --test capability_io_host_tests
cargo test -p igniter-machine --test postgres_write_tests
cargo test -p igniter-machine --test postgres_reconcile_tests
cargo test -p igniter-machine
git diff --check
```

If the workspace package name or test target has drifted, use the current equivalent command and
record the exact command in the proof packet.

## Required Packet

Create:

```text
lab-docs/lang/lab-machine-receipt-seq-tiebreak-p4-v0.md
```

Packet must include:

- the exact ordering sites changed,
- the final receipt value shape,
- replay/no-new-seq evidence,
- equal-timestamp evidence,
- explicit non-claim: not durable/global TBackend sequencing.
