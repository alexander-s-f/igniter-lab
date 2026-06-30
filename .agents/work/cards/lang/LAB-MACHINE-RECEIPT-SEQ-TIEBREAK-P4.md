# LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4

Status: CLOSED (2026-06-28)
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

- [x] Equal-timestamp receipts resolve deterministically: terminal beats earlier prepared/unknown via
      higher `receipt_seq` (`equal_timestamp_terminal_outranks_prepared_via_receipt_seq` +
      adversarial-push-order `recovery_equal_tx_higher_seq_terminal_is_latest_not_dangling`).
- [x] Non-monotonic boundary documented: tx is primary, seq only breaks equal tx
      (`transaction_time_is_primary_seq_only_breaks_equal_tx`).
- [x] Replay returns the recorded outcome and writes no new receipt / no seq increment
      (`replay_writes_no_new_receipt_and_does_not_increment_seq`).
- [x] Recovery + observability use the SAME `receipt_is_newer_or_equal` helper as write-resolution
      (no duplicated wall-clock-only logic).
- [x] Existing capability IO / Postgres write+reconcile / clock tests green (clock 5, host 9,
      recovery 7, write 12, reconcile 7, capability_io 13; fleet 13/13).
- [x] No TBackend daemon / Postgres CAS-DDL / wire-protocol change; no new dependency.
- [x] `git diff --check` clean.

## Report (2026-06-28)

Implemented P3's Option A. Added a per-process `receipt_seq` (`static AtomicU64`, starts at 1; 0 =
legacy) stamped into every receipt value (capability + write `write_receipt`), and one shared helper
`receipt_is_newer_or_equal` applying `(transaction_time, receipt_seq)` lexicographic — tx primary,
seq tie-break. Wired it into all three fold sites: `run_write_effect` resolution (now reads
`facts_for` + `reduce` instead of `read_as_of` max-by-tx), `recovery::latest_receipts`, and
`observability::latest_by_key`. `receipt_seq` lives in the receipt VALUE only (no `Fact`-schema/hash
break). Replay returns before `write_receipt`, so it neither appends a fact nor increments the seq.
tx stays the audit primary; seq never reorders different-tx receipts (backwards-clock case self-heals
via P7 reconcile — documented boundary).

Files: `runtime/igniter-machine/src/{capability.rs (helper + stamp + 4 unit tests), write.rs (stamp +
fold resolution), recovery.rs, observability.rs}`, `runtime/igniter-machine/tests/receipt_seq_tiebreak_tests.rs`
(4 integration), board A21, packet `lab-docs/lang/lab-machine-receipt-seq-tiebreak-p4-v0.md`.

Verification: P4 unit 4/4 + integration 4/4; clock/host/recovery/write/reconcile/capability_io all
green; fleet 13/13; `git diff --check` PASS. (Card's `-p igniter-machine` ⇒ live equivalent
`--manifest-path runtime/igniter-machine/Cargo.toml`, recorded in packet.)

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
