# LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4

Date: 2026-06-28
Status: DONE
Route: standard / igniter-lab / runtime / igniter-machine / receipt ordering
Implements: the `LAB-MACHINE-RECEIPT-SEQID-ORDERING-READINESS-P3` decision (Option A); A21 seq tail
Depends-On: `lab-machine-receipt-seqid-ordering-readiness-p3-v0.md`

Machine-crate scope. **No** TBackend daemon change, **no** Postgres `effect_receipts` CAS / DDL
change, **no** external wire-protocol change, **no** new dependency. DB-free (in-memory backend +
`FixedClock`).

## What changed and why

Machine receipt "latest state" selection used wall-clock `transaction_time` alone. When a key's
`prepared` and terminal receipt land at the **same** timestamp (always under `FixedClock`; possible
under a coarse/loaded `SystemClock`), the winner fell to incidental push order (`max_by` last-equal)
or `HashMap` iteration order. P3 chose **Option A**: a per-process `receipt_seq` tie-breaker;
selection becomes `(transaction_time, receipt_seq)` lexicographic — `transaction_time` primary,
`receipt_seq` only breaks equal-timestamp ties.

## Ordering sites changed (exact)

A single shared helper in `capability.rs` is now used by every place the machine folds receipt facts
to the latest:

- `runtime/igniter-machine/src/capability.rs`
  - `static RECEIPT_SEQ: AtomicU64` (starts at 1; 0 reserved for legacy receipts) +
    `next_receipt_seq()` (called **only** when a receipt fact is written).
  - `receipt_seq_of(value) -> u64` (0 if absent) and
    `receipt_is_newer_or_equal(cand_tx, cand_val, cur_tx, cur_val) -> bool` (the `(tx, seq)`
    lexicographic rule; `tx` primary, `seq` tie-break).
  - `write_receipt` stamps `"receipt_seq": next_receipt_seq()` into the effect-receipt value.
- `runtime/igniter-machine/src/write.rs`
  - `write_receipt` stamps `"receipt_seq"` into the write-receipt value (both `prepared` and the
    terminal fact).
  - Resolution (step 2 of `run_write_effect`) no longer takes `read_as_of(f64::MAX)` (max-by-tx,
    incidental on ties). It reads **all** facts for the key (`facts_for`) and `reduce`s by
    `receipt_is_newer_or_equal`, so the terminal deterministically outranks its own `prepared` at
    equal tx.
- `runtime/igniter-machine/src/recovery.rs` — `latest_receipts` fold now uses
  `receipt_is_newer_or_equal` instead of the wall-clock-only `>=`.
- `runtime/igniter-machine/src/observability.rs` — `latest_by_key` fold uses the same helper (receipt
  facts carry `receipt_seq`; other stores read it as 0, degrading to prior behavior).

`transaction_time` semantics and public audit meaning are unchanged: it is still the host-stamped
audit time and the primary order. `receipt_seq` is additive metadata.

## Final receipt value shape

Both receipt writers add one additive field (older facts without it read back as `0`):

```jsonc
// capability.rs write_receipt (effect receipts)
{ "capability_id", "idempotency_key", "authority_ref", "authority_digest", "correlation_id",
  "outcome_kind", "result", "failure_kind",
  "receipt_seq": <u64>            // P4 — per-process tie-breaker
}
// write.rs write_receipt (write receipts: prepared + terminal)
{ "capability_id", "operation", "idempotency_key", "authority_digest", "payload_digest",
  "target_store", "target_key", "value_digest", "correlation_id", "state", "result", "detail",
  "receipt_seq": <u64>            // P4 — per-process tie-breaker
}
```

No `Fact` struct field was added (no fact-schema/hash break); `receipt_seq` lives in the receipt
`value` JSON only.

## Equal-timestamp evidence

- Unit (`capability::receipt_seq_tiebreak_tests`): `equal_tx_higher_seq_wins` — at equal tx the
  higher-seq receipt wins; `legacy_zero_seq_loses_tie_to_stamped` — a legacy (seq 0) receipt loses an
  equal-tx tie to a stamped one.
- Integration (`tests/receipt_seq_tiebreak_tests.rs`):
  - `equal_timestamp_terminal_outranks_prepared_via_receipt_seq` — `run_write_effect` under
    `FixedClock(100)`: both `prepared` and `committed` facts have `transaction_time == 100`, and the
    terminal's `receipt_seq` is strictly greater, so only the seq can order them.
  - `recovery_equal_tx_higher_seq_terminal_is_latest_not_dangling` — receipt facts written in
    **adversarial push order** (terminal first, prepared last) at equal tx: the higher-seq terminal
    is still selected as latest (`scanned == 0`), deterministically across 3 runs. The old
    `>=`/last-equal rule would have picked the last-pushed `prepared` and mis-flagged it dangling.
  - `recovery_equal_tx_higher_seq_prepared_is_latest_and_dangling` — negative control: when
    `prepared` carries the higher seq it IS latest and dangling (`scanned == 1`), proving the seq
    genuinely orders rather than "terminal always wins".

## Replay / no-new-seq evidence

`replay_writes_no_new_receipt_and_does_not_increment_seq`: a second `run_write_effect` with the same
key + payload returns the recorded `Committed` outcome, and `facts_for` shows the **same** receipt
rows before and after (same count, same `transaction_time`, same `receipt_seq`). `next_receipt_seq()`
is called only inside `write_receipt`, and replay returns before any write — so no new fact and no
seq increment. Executor `attempts` likewise unaffected (existing idempotency tests stay green).

## Non-monotonic-clock boundary (documented)

`transaction_time_is_primary_seq_only_breaks_equal_tx`: a higher tx wins even with a lower seq, and a
lower tx loses even with a higher seq. So `receipt_seq` **never** reorders receipts that differ in
timestamp — a backwards wall-clock step is NOT corrected by seq (that case self-heals via the P7
read-back reconcile). `transaction_time` remains the audit time; `receipt_seq` is strictly a
tie-break for equal timestamps.

## Verification

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --lib receipt_seq_tiebreak     # 4/4 (helper + boundary)
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test receipt_seq_tiebreak_tests  # 4/4
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test capability_io_clock_tests    # 5/5
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test capability_io_host_tests     # 9/9
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test capability_io_recovery_tests # 7/7
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_write_tests         # 12/12
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_reconcile_tests     # 7/7
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep  # 13/13
cargo test --manifest-path runtime/igniter-machine/Cargo.toml                                      # full suite (see note)
git diff --check                                                                                   # PASS
```

(The card's `-p igniter-machine` form does not match the crate's package name `igniter_machine`;
`--manifest-path runtime/igniter-machine/Cargo.toml` is the live equivalent used above. The full
suite includes the heavy `capability_io_load_tests` concurrency storm and runs long; the targeted
suites above + fleet sweep are the focused green evidence.)

## Non-claims

- `receipt_seq` is **NOT** the TBackend daemon fact-log `seq_id`: it is per-machine-process,
  non-durable (resets on restart — fine because `transaction_time` is primary, so cross-restart
  equal-tx collisions are vanishing), and makes **no** global/replicated/cross-node ordering claim.
- No durability/power-loss claim for the counter; it is a tie-breaker, not a durable log position.
- No exactly-once change: Postgres `effect_receipts(idempotency_key)` CAS (P2) owns exactly-once;
  this is ordering/determinism hygiene only. Postgres CAS / DDL untouched.
