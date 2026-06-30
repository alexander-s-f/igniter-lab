# LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-OWNER-SPLIT-P1

Status: CLOSED (2026-06-28) — readiness/owner-split, doc-only

## Closure Report

Verify-first owner split for the durable exactly-once substrate (A21 / lever
L6). Packet: `lab-docs/lang/lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md`.

**Headline (overturned the A21 framing):** L6 was scoped as a *shared* gap, but
live source shows TBackend **already built** the substrate in its daemon core
(`runtime/igniter-tbackend/src/pure_core.rs`): per-store `seq_id` (P9),
group-commit `fdatasync` (P6), durable write-once CAS `push_once` (P15/P3), safe
compaction (P12) — all CLOSED PASS with home-lab proofs. Machine still has the
gap AND consumes only the *legacy* `ShardedFactLog`/`FactData` from the tbackend
crate (`backend.rs:4-5`), not the hardened daemon. So the split is "TBackend owns
it; machine closes its own gaps without forking the daemon," not "two agents
build seq_id."

**Owner matrix (full in packet):** TBackend-owned (DONE) = fact-log seq_id,
durable-ack+group-commit, push_once CAS, canonical hash, compaction, mesh
watermark. Machine-owned (GAP) = multi-process exactly-once for *effects*
(`single_flight.rs:11-15` in-process only), receipt ordering (clock last-wins
`recovery.rs:48`), WAL fsync (`wal.rs:39` flush-only), non-silent WAL recovery
(`wal.rs:69`). Shared = the *concept* (seq token), *vocabulary*
(accepted/durable), and *proof shape* — NOT shared code (different number-spaces,
different mechanisms). Cross-project/deferred = daemon adoption + seq number-space
reconciliation.

**Cards named (non-overlapping):**
- **A (recommended first)** `LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2` — real
  PG `effect_receipts(idempotency_key)` UNIQUE + `ON CONFLICT` durable CAS +
  concurrent-double-execute proof vs real local PG. Machine-only.
- **B (parallel, orthogonal)** `LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2` —
  WAL fsync/group-commit + non-silent replay (T2.4).
- **C (deferred, cross-project design)**
  `LAB-MACHINE-TBACKEND-RECEIPT-ADOPTION-READINESS-P2` — adopt the tbackend
  daemon as machine's receipt backend, delete single_flight.

**Recommendation:** Card A first — closes the most dangerous machine durability
finding (multi-process double-execute), fully machine-scoped, DB-native CAS (no
parallel power-loss mechanism to reconcile), provable vs real local PG without
touching TBackend or home-lab.

Acceptance:
- [x] Live machine durability/receipt surfaces characterized (file:line).
- [x] TBackend lane treated as external evidence (not edited); home-lab untouched.
- [x] Owner matrix produced (machine / TBackend / shared concept / deferred).
- [x] ≥2 non-overlapping implementation cards named (A, B, + design C).
- [x] Recommendation chooses the next first card (A).
- [x] No code / production / home-lab mutation (doc-only).
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Grounding (current behavior): `postgres_write_tests` 11/11,
`postgres_reconcile_tests` 7/7, `storage_durability_proof_tests` 3/3.

---

Status: CLOSED — original card below.
Route: standard / main-audit / durability / owner split
Skill: idd-agent-protocol

## Goal

Decide how to split the durable exactly-once substrate work between
`igniter-machine` and the active TBackend lane before dispatching
implementation cards.

The audit-control-board row A21 names the substrate gap:
server-assigned monotonic `seq_id`, durable CAS/prepared, and fsync/group
commit. This card must prevent two agents from implementing incompatible
versions in machine and TBackend.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md` lever L6
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/write.rs`
- `runtime/igniter-machine/src/single_flight.rs`
- `runtime/igniter-machine/src/wal.rs`
- `runtime/igniter-machine/src/recovery.rs`
- `runtime/igniter-machine/tests/postgres_write_tests.rs`
- active TBackend checkpoint docs/cards in `igniter-home-lab` only as evidence,
  not as editable scope unless explicitly authorized.

Known live facts to re-verify:

- machine has receipt/idempotency machinery and in-process single-flight style
  protection;
- TBackend hardening is actively moving in home-lab/business lane;
- this lab card must not mutate home-lab unless the user explicitly authorizes
  it.

## Scope

Allowed:

- Produce an owner-split readiness packet.
- Characterize which pieces belong to machine, which to TBackend, and which are
  shared concepts only.
- Name implementation card(s) with non-overlapping authority boundaries.
- Identify tests/proofs needed for each owner.

Closed:

- No code changes unless they are read-only proof helpers in igniter-lab and
  clearly scoped.
- No home-lab edits without explicit user authorization.
- No production SparkCRM or business data access.
- No schema migration or live DB mutation.
- No claim that TBackend semantics are machine semantics or vice versa.

## Questions To Answer

1. What does `seq_id` mean in machine receipts vs TBackend fact log?
2. Is durable CAS a machine Postgres concern, a TBackend WAL concern, or two
   different mechanisms with a shared proof shape?
3. Where is fsync/group commit relevant today?
4. What can be proven DB-free/fake, and what requires real local Postgres or
   filesystem durability tests?
5. Which first implementation slice has the highest safety payoff without
   conflicting with active TBackend work?
6. What must remain a cross-project design note rather than lab code?

## Acceptance

- [ ] Live machine durability/receipt surfaces are characterized.
- [ ] Active TBackend lane is treated as external evidence unless explicitly
      authorized for edits.
- [ ] Owner matrix is produced: machine-owned, TBackend-owned, shared concept,
      deferred.
- [ ] At least two implementation card candidates are named with non-overlap.
- [ ] Recommendation chooses the next first card.
- [ ] No code or production/home-lab mutation unless explicitly justified.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_write_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_reconcile_tests
git diff --check
```

Tests are optional if this stays doc-only and source characterization is enough,
but any current behavior claim should be grounded in live source or a command.

## Required Packet

Create:

```text
lab-docs/lang/lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md
```

Packet must include:

- owner matrix;
- risk of duplicated/incompatible implementations;
- first recommended implementation card;
- explicit note that home-lab/TBackend edits are out of scope unless separately
  authorized.

