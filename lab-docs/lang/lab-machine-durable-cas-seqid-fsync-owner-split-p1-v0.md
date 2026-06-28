# LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-OWNER-SPLIT-P1 v0

Status: readiness complete (owner split)
Date: 2026-06-28
Scope: `igniter-lab` design/characterization only. No code changed. No
`igniter-home-lab` edits. No production/business DB access. TBackend lane treated
as **external evidence**, not editable scope.
Addresses: audit-control-board row A21, roadmap lever **L6** (T2.1).

## The headline (what verify-first overturned)

A21/L6 was written as a **shared** gap ("server-assigned `seq_id`, durable
CAS/prepared, fsync group-commit" for "TBackend AND machine"). Live source shows
the two lanes are at very different states:

- **TBackend has already built the substrate** in its daemon core
  (`runtime/igniter-tbackend/src/pure_core.rs`): per-store monotonic `seq_id`
  (P9), durable-ack + group-commit `fdatasync` (P6), durable write-once CAS via
  `push_once` (P15/P3), canonical hash (P4), safe compaction (P12). All CLOSED
  PASS with home-lab proofs.
- **Machine still has the gap**, AND it consumes only the *legacy* part of the
  tbackend crate — `igniter_tbackend_playground::timeline::ShardedFactLog` +
  `FactData` (`backend.rs:4-5`) — **not** the hardened daemon `pure_core`. The
  daemon's seq/CAS/group-commit are invisible to machine today.

So the real owner-split question is **not** "how do two agents both build
seq_id" — it is "TBackend already built it; machine must close its own
multi-process / power-loss gaps **without duplicating or forking the daemon
design**, and we must decide whether machine eventually *adopts* the daemon or
keeps a narrower parallel mechanism."

## Live machine durability surfaces (characterized, file:line)

| Surface | State today | Evidence |
| --- | --- | --- |
| Receipt protocol (`prepared` gate → terminal) | sound, sequential-dup safe | `write.rs:35-65,345` |
| Sequential duplicate / replay | resolved by reading prior receipt | `write.rs:307-342` |
| Concurrent duplicate (same process) | in-process per-key lock | `single_flight.rs:27-72` |
| Concurrent duplicate (multi-process) | **GAP — double effect possible** | `single_flight.rs:11-15` ("would need a distributed lock or a backend compare-and-set `prepared` write; that is a later slice") |
| Two-layer idempotency (machine receipt + PG `effect_receipts(idempotency_key)`) | designed; PG side is a **fake** adapter in tests | `postgres_write.rs:9-22,256-367` |
| `seq_id` in machine | **absent everywhere** (receipts ordered by `transaction_time` clock last-wins) | `recovery.rs:38-52`; `rg seq_id src/` → none |
| WAL durability (`WALWriter::append`) | `flush()` only — page cache, **no fsync** = acked-but-lost on power-loss; CRC32 | `wal.rs:39` |
| WAL recovery (`replay`) | **silently truncates** on first bad record (no counts/quarantine) | `wal.rs:55,61,66,69` |
| MpkFileBackend persistence | atomic temp→fsync→rename→dir-fsync; corruption observable; but whole-file rewrite per key (O(history)), no group-commit, no seq | `backend.rs:177-318` |
| Crash recovery of dangling `prepared` | reconcile by read-back / correlation; never re-runs executor | `recovery.rs:72-113` |

Grounding (current behavior is green): `postgres_write_tests` 11/11,
`postgres_reconcile_tests` 7/7, `storage_durability_proof_tests` 3/3.
`git diff --check` clean. Machine receipt/idempotency machinery works today; the
gaps are **multi-process exactly-once**, **fsync/power-loss**, and
**clock-ordered receipts**.

## Owner matrix

| Concern | Owner | Status | Anchor |
| --- | --- | --- | --- |
| Per-store monotonic `seq_id` for the **fact log** | **TBackend** | DONE (P9) | `pure_core.rs:133,162,217` |
| Durable-ack vocab (`in_memory`/`accepted`/`durable`) + group-commit `fdatasync` | **TBackend** | DONE (P6) | `pure_core.rs:503,613` |
| Durable write-once CAS (`push_once`) — multi-process exactly-once for facts | **TBackend** | DONE (P15/P3) | `pure_core.rs:292-320` |
| Canonical fact hash; safe compaction; mesh seq watermark | **TBackend** | DONE / DESIGNED | `pure_core`, `packs/snapshot.rs`, P13 readiness |
| Multi-process exactly-once for capability **effects** (the `prepared` CAS) | **MACHINE** | GAP | `single_flight.rs:11-15`, `postgres_write.rs:256` |
| Durable receipt **ordering** (replace `transaction_time` last-wins) | **MACHINE** | GAP | `recovery.rs:48` |
| WAL **fsync / group-commit** (machine `WALWriter`) | **MACHINE** | GAP | `wal.rs:39` |
| **Non-silent** WAL recovery (counts + quarantine) — roadmap T2.4 | **MACHINE** | GAP | `wal.rs:69` |
| `seq_id` as a *concept* (server-assigned monotonic ordering token) | **SHARED CONCEPT** | — | different number-spaces (fact log ≠ receipt store) |
| `accepted` vs `durable` ack *vocabulary* | **SHARED CONCEPT** | — | machine should adopt TBackend's words, not its code |
| Proof *shape* (SIGKILL-survive acked writes; exactly-once under concurrency) | **SHARED PROOF CONTRACT** | — | each lane proves the same contract with its own mechanism |
| The daemon engine (`pure_core`) itself | **TBackend (do not fork)** | — | machine adopts or stays parallel — never copies |
| Adopting the tbackend **daemon** as machine's receipt backend (→ seq-as-receipt-order, delete `single_flight`) | **CROSS-PROJECT (deferred)** | DESIGN NOTE | spans machine + tbackend + home-lab deploy |

## Answers to the card's questions

1. **`seq_id` meaning — machine receipt vs TBackend fact log.** Same *concept*
   (server-assigned monotonic ordering, excluded from idempotency identity),
   **different scope and number-space**. TBackend's seq orders **facts in the
   log** per store (`pure_core.rs:162`). A machine receipt seq would order
   **receipt facts** to replace the `transaction_time` clock last-wins in
   `recovery.rs:48`. They are NOT the same counter unless machine adopts the
   daemon as its receipt backend (the deferred cross-project move). **Risk to
   forbid:** an agent assuming TBackend's seq is automatically machine's receipt
   seq.

2. **Durable CAS — machine-PG, TBackend-WAL, or shared?** **Two different
   mechanisms, one shared proof shape.**
   - TBackend WAL: `push_once` under `write_once_lock` + group-commit fsync IS
     its durable CAS (`pure_core.rs:292`).
   - Machine: for the **Postgres executor** path, the durable CAS is the PG
     `effect_receipts(idempotency_key)` **UNIQUE** constraint +
     `INSERT … ON CONFLICT` (a real DB CAS) — but it is a *fake* adapter today
     (`postgres_write.rs:256-367`). For **non-PG effects** (HTTP/remote), no
     durable CAS exists; it would require the receipt backend's write-once,
     which the machine `TBackend` trait lacks (`backend.rs:14-31` has only blind
     `write_fact`).
   - Shared proof shape: *two concurrent same-key prepares ⇒ exactly one effect;
     the loser replays.*

3. **Where is fsync/group-commit relevant today?** In machine's
   `WALWriter::append` (`wal.rs:39`, `flush`-only ⇒ acked-but-lost on
   power-loss) and partially in `MpkFileBackend` (per-write `fsync` but
   whole-file rewrite, no group-commit, `backend.rs:194-209`). TBackend already
   has amortized group-commit `fdatasync` (`pure_core.rs:613`); machine does
   not.

4. **Provable fake vs real.**
   - **Fake / in-process / local-fs (CI-safe, already green):** receipt replay,
     `single_flight` concurrency, WAL CRC round-trip, `MpkFileBackend`
     atomic-rename + corruption observability, dangling-`prepared` reconcile.
   - **Requires real local Postgres** (opt-in feature + `IGNITER_PG_WRITE_DSN`,
     dedicated `igniter_pg_test`): the `effect_receipts` UNIQUE/`ON CONFLICT`
     durable CAS under genuine concurrent transactions
     (`postgres_real_write_tests`).
   - **Requires real filesystem durability:** fsync/group-commit "acked ⇒ not
     lost" under SIGKILL (`storage_durability_proof_tests`); full **power-loss**
     is a gated hardware test (same stance as TBackend P6), not CI.

5. **Highest-payoff first slice without conflicting with active TBackend.**
   **Machine multi-process exactly-once via a real durable CAS on the Postgres
   executor path** — make `effect_receipts(idempotency_key)` a genuine
   UNIQUE-constraint CAS (`INSERT … ON CONFLICT DO NOTHING`, observe who won) in
   the *real* PG adapter, with a concurrent-double-execute proof against real
   local PG. It closes the machine audit's most dangerous durability blocker
   ("`single_flight` no-CAS multi-process double-execute"), is **entirely
   machine-owned**, touches **no** TBackend daemon code and **no** home-lab, and
   leaves `single_flight` as the in-process fast-path with the DB CAS as the
   cross-process backstop. (Deleting `single_flight`, as L6 muses, is deferred —
   it needs a durable CAS on *every* effect path, incl. non-PG.)

6. **What stays a cross-project design note (not lab code).** The **seq_id
   number-space reconciliation** and the **daemon-adoption** decision: if machine
   later replaces `MpkFileBackend`/`WALWriter` with the tbackend daemon as its
   receipt backend, the daemon's per-store seq becomes machine's receipt
   ordering and `single_flight` can be deleted. That spans both crates and the
   home-lab deployment and must be a readiness/letter first. Also: any change to
   the **shared `FactData`/`Fact` struct** (e.g. adding `seq_id`) crosses the
   `machine ↔ igniter-tbackend` crate boundary and must be **additive only**
   (`#[serde(default)]`), coordinated, never forked.

## Risk of duplicated / incompatible implementations

- **Re-building seq_id in machine** while TBackend already owns the fact-log
  seq, in an incompatible number-space → two "seq" meanings that can never
  reconcile. *Mitigation:* machine receipt-ordering seq is explicitly a
  **separate, narrower** token; daemon adoption is the only path that unifies
  them, and it is deferred behind a readiness card.
- **Forking the daemon's durable-CAS/group-commit** into machine instead of
  adopting or using a DB-native CAS → two power-loss stories to maintain.
  *Mitigation:* machine's first slice uses the **PG-native** CAS (DB owns
  durability), not a re-implementation of `push_once`.
- **Editing the tbackend crate or home-lab** to satisfy a machine need →
  cross-lane coupling without authorization. *Mitigation:* both are out of scope
  here (see note below); shared-struct changes are additive-only and
  letter-gated.

## Implementation card candidates (non-overlapping authority)

**Card A — RECOMMENDED FIRST**
```
LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2
```
Real PG `effect_receipts(idempotency_key)` UNIQUE + `INSERT … ON CONFLICT`
durable CAS in the real Postgres write adapter; concurrent-double-execute proof
against real local PG (opt-in `postgres` feature, `IGNITER_PG_WRITE_DSN`,
dedicated `igniter_pg_test`). `single_flight` stays as in-process fast-path.
- Authority: `runtime/igniter-machine/src/postgres_write.rs` + machine tests.
- Closed: no TBackend daemon edits, no home-lab, no business/shared-DB schema
  migration, no `single_flight` deletion.

**Card B**
```
LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2
```
Machine `WALWriter` fsync + bounded group-commit; `replay` surfaces
partial/corrupt with counts + quarantine instead of silent truncation
(roadmap T2.4). Filesystem durability proof (SIGKILL acked-not-lost).
- Authority: `runtime/igniter-machine/src/wal.rs`, recovery path,
  `storage_durability_*` tests.
- Closed: no TBackend, no home-lab, no power-loss hardware claim.

**Card C — cross-project design (deferred)**
```
LAB-MACHINE-TBACKEND-RECEIPT-ADOPTION-READINESS-P2
```
Readiness for machine adopting the tbackend **daemon** (`pure_core`) as its
receipt backend: seq-as-receipt-order, `accepted`/`durable` vocab passthrough,
delete `single_flight`, shared-struct `seq_id` (additive). Cross-project; a
design note / letter before any code.
- Authority: design packet only (no code); coordinates machine + tbackend +
  home-lab deploy.

A (PG CAS) and B (WAL fsync) are **orthogonal** (different files, different proof
beds) and can run in parallel. C is the umbrella that would eventually subsume
both if daemon-adoption is chosen — so it is explicitly **after** A/B, not
concurrent.

## Recommendation

Do **Card A (`LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2`) first.** It closes the
single most dangerous open machine durability finding (multi-process
double-execute), is fully machine-scoped, is provable against real local
Postgres without touching TBackend or home-lab, and uses a DB-native CAS so it
creates no parallel power-loss mechanism to reconcile later. Run **Card B** in
parallel if a second agent is free (orthogonal files). Hold **Card C** until A/B
land and the daemon-adoption question is explicitly raised — it is the only item
that crosses lanes and it must be a readiness/letter, not code.

## Out-of-scope note (explicit)

This card and its recommended follow-ups touch **only**
`runtime/igniter-machine` in `igniter-lab`. The active **TBackend** lane
(`runtime/igniter-tbackend` daemon + `igniter-home-lab` cards/proofs/deploy) is
**external evidence**, not editable scope. No home-lab file, no
production/business SparkCRM data, no shared/`igniter_pg_test`-external DB, and
no shared `Fact`/`FactData` struct change may be made without **separate,
explicit user authorization**. The `seq_id` number-space and any daemon-adoption
are cross-project decisions reserved for Card C.
