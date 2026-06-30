# LAB-MACHINE-RECEIPT-SEQID-ORDERING-READINESS-P3

Date: 2026-06-28
Status: DONE (readiness/policy — doc-only, no code)
Lane: igniter-lab / machine / durability — receipt ordering
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-MACHINE-RECEIPT-SEQID-ORDERING-READINESS-P3.md`
Decides: audit-control-board row **A21** remaining "seq" tail (after PG-CAS + WAL done).
Depends-On: `lab-machine-durable-cas-pg-exactly-once-p2-v0.md`,
`lab-machine-wal-fsync-nonsilent-recovery-p2-v0.md`

## Authority boundary

Readiness/policy packet. No code, no schema/DB mutation, no TBackend/home-lab/SparkCRM
edits. TBackend daemon seq_id is **external evidence**, not copied authority; a machine
`receipt_seq` (if adopted) is explicitly NOT the TBackend fact-log seq_id. Every behavior
claim below is grounded in live source read this session.

## Live ordering model (Q1)

Machine receipts are facts on the `RECEIPTS_STORE` timeline, keyed
`rkey = capability_id:idempotency_key`. A write emits two facts on the SAME key: a
`prepared` fact (the gate) and a terminal fact (`committed`/`denied`/`retryable`/
`permanent_failure`/`unknown_external_state`), distinguished by `Fact.id`
(`write-receipt:{rkey}:{state}`) — `write.rs:200-214`.

**The sole ordering authority is wall-clock `transaction_time` (f64).**

- `transaction_time` is stamped only at the ServiceLoop boundary from a `ClockProvider`
  (`clock.rs`): `SystemClock::now()` = `SystemTime::now()` seconds-as-`f64`;
  `FixedClock` returns a constant. `prepared_at` and `finalized_at` are two **separate**
  `clock.now()` calls (`write.rs:347, 386`).
- **Write resolution** reads the current receipt with
  `read_as_of(RECEIPTS_STORE, rkey, f64::MAX)` (`write.rs:297`) →
  `ShardedFactLog::latest_for` → `max_by(transaction_time)` (`timeline.rs:57-79`).
  Rust `max_by` returns the **last** element among equals, so at equal `transaction_time`
  the winner is the timeline's push order, not state semantics.
- **Recovery** (`recovery.rs::latest_receipts`) folds all receipt facts into a
  `HashMap<key, (tx, value)>` keeping the entry with `transaction_time >= current`
  (`recovery.rs:38-53`) — last-wins by tx, ties broken by `HashMap` iteration order
  (nondeterministic).
- **WAL append order is NOT the receipt ordering authority.** The WAL replays facts into
  the store at boot (`machine.rs:77`); the store then re-derives "latest" by
  `transaction_time`. WAL offset never reaches the receipt timeline.
- **PG path is separate.** `effect_receipts(idempotency_key)` UNIQUE CAS (P2) orders by
  the DB, not by the fact-store receipt timeline; it is not in this ordering question.

Net: the prepared→terminal "latest wins" rule is correct **only if the clock strictly
increases between the two receipt writes**. At equal `transaction_time` the resolution
falls back to incidental push order (`max_by` last-equal) / `HashMap` iteration order.

## Risk analysis (Q2)

| # | Condition | Mechanism | User-visible effect |
|---|---|---|---|
| R1 | `prepared` and terminal land at the **same** `transaction_time` | `FixedClock` makes them *always* equal; coarse/loaded `SystemClock` can too. `latest_for` = `max_by(tx)` → last-in-timeline wins, NOT terminal-by-state | "Latest state" decided by push order, not semantics. Today it resolves to the terminal fact only because it is pushed after `prepared` and stays last among equals — an **incidental** invariant, not an enforced one. |
| R2 | Wall clock steps **backwards** (NTP correction, VM migration) | `SystemClock` is `SystemTime`, **not monotonic**. `finalized_at < prepared_at` → terminal fact has earlier tx → `read_as_of(f64::MAX)` returns `prepared` | A committed/denied write reads back as dangling `prepared`. P7 read-back reconcile re-resolves a committed write correctly, so the dominant case self-heals; but a backwards-clock terminal can be transiently masked and re-driven by the recovery sweep. |
| R3 | Equal-tx receipts in the recovery sweep | `latest_receipts` `>=` + `HashMap` iteration | Nondeterministic dangling classification for equal-tx keys. Reconcile is idempotent so the resolved state converges, but the *scan verdict* (`scanned`/`still_unknown` counts) is non-reproducible run-to-run. |
| R4 | Two terminal writes / a reconcile rewrite at equal tx | same as R1 | Order-dependent winner among terminal states at identical tx. |

Severity: none is a data-loss or exactly-once break (PG-CAS owns exactly-once; reconcile
is idempotent). They are **determinism / ordering-correctness** gaps that are real,
DB-free reproducible (`FixedClock` forces equal tx), and currently masked by incidental
push order plus a usually-increasing clock.

## Options comparison (Q3)

| Option | What | Pros | Cons |
|---|---|---|---|
| **A. Local monotonic `receipt_seq`** | A per-machine atomic `u64` stamped on each receipt fact; resolution becomes `(transaction_time, receipt_seq)` lexicographic in the receipt read path + `latest_receipts` | DB-free; small + self-contained; makes equal-tx ties deterministic (R1/R3/R4) and prevents a backwards clock from inverting prepared→terminal **within one process** (R2 partial); meaning is local + explicit | Not durable across restart unless persisted/recovered (counter resets — but tx-time stays primary, so cross-restart equal-tx collisions are vanishing); must be clearly documented as **≠ TBackend fact-log seq_id** |
| **B. Reuse WAL offset as order key** | Thread the WAL append offset into the receipt fact and order by it | A genuinely monotonic per-file source | WAL is optional (only when `data_dir` set); receipts may be in-memory / `.mpk` with no WAL on the receipt timeline; offset isn't on `Fact` today → invasive, couples two subsystems |
| **C. Defer to TBackend daemon receipt adoption** | Adopt the daemon's durable seq_id/CAS for receipts | Inherits a proven durable total order | Large cross-project scope; that is the already-named deferred card `LAB-MACHINE-TBACKEND-RECEIPT-ADOPTION-READINESS-P2`; overkill for a tie-break gap |
| **D. State-precedence tie-break (no counter)** | At equal tx, break ties by state rank (`prepared` < terminal states) instead of push order | Tiniest DB-free change; directly fixes the dominant R1 (prepared-vs-terminal) | Does not order two *distinct terminal* writes at equal tx (R4); no help for R2 across writes; a rank table is a policy surface of its own |

## Decision (Q3, Q5) — machine `receipt_seq` ACCEPTED, scoped; next card named

**Adopt Option A as a small implementation slice.** A machine `receipt_seq` is accepted
with this **meaning**, which is explicitly NOT the TBackend fact-log seq_id:

> `receipt_seq` is a per-machine-process monotonic counter stamped on each receipt fact,
> used ONLY as the deterministic tie-breaker for receipts sharing a `transaction_time`.
> `transaction_time` remains the primary order; `receipt_seq` is secondary. It is local to
> one machine process, is not a global/durable/replicated sequence, and makes no
> cross-node ordering claim.

Why A over the others: it closes the reproducible DB-free determinism holes (R1/R3/R4)
and the within-process prepared→terminal inversion (R2) with a small, self-contained
change; B couples WAL into the receipt timeline; C is the heavyweight deferred path; D is
smaller but leaves R4 and is itself a policy surface. A also subsumes D's benefit (terminal
is always stamped with a higher seq than its own `prepared`).

Next implementation card:

`LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4`

Scope sketch (for that card, not done here):
- Add a per-`Machine` `AtomicU64` `receipt_seq`; stamp it into the receipt fact value at
  `write_receipt` (additive JSON field, `#[serde(default)]`-style so older facts read as 0
  — confirm no SIR/fact-schema break first).
- Change the latest-receipt resolution (`read_as_of` consumer in `write.rs` and
  `latest_receipts` in `recovery.rs`) to order by `(transaction_time, receipt_seq)`.
- DB-free proof: under `FixedClock` (equal tx), `prepared` then `committed` must
  deterministically resolve to `committed`; and a forced equal-tx reconcile rewrite must
  pick the highest-seq terminal across repeated runs.
- Explicit non-claims: `receipt_seq` ≠ TBackend seq_id; not durable/replicated; counter
  reset on restart is acceptable because tx-time is primary.

## What is DB-free vs PG-gated (Q4)

- **DB-free (in-memory backend + `FixedClock`):** the equal-tx tie-break in
  `read_as_of`/`latest_for` and the `latest_receipts` determinism — fully reproducible
  without a database. This is where P4 should prove itself.
- **PG-gated:** `effect_receipts(idempotency_key)` CAS ordering (`committed_at`) — already
  owned and proven by `LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2`; a separate axis from
  the fact-store receipt timeline and out of P4's scope.

## Verification

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test capability_io_recovery_tests
  7 passed; 0 failed   (DB-free recovery baseline green)
postgres_reconcile_tests — DSN-gated (real PG), not run here; PG ordering owned by P2.
git diff --check  → PASS (no code changes; doc/card only)
```

## Non-claims

- No claim that machine `receipt_seq` equals or substitutes the TBackend daemon
  fact-log seq_id.
- No durability/power-loss claim for the proposed counter (it is a tie-breaker, not a
  durable log position).
- No exactly-once claim is affected — PG-CAS (P2) owns exactly-once; this is ordering /
  determinism hygiene only.
