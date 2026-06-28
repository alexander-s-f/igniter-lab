# LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2

Status: CLOSED (2026-06-28)
Route: standard / main-audit / machine / durability
Skill: idd-agent-protocol
Depends-On: `LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-OWNER-SPLIT-P1`

## Goal

Close the machine-owned WAL durability hygiene gap: make WAL persistence
fsync/group-commit explicit enough for machine receipts and make recovery
non-silent when it encounters corrupt/truncated/unreadable entries.

This is the orthogonal A21 machine slice. It does not implement PG exactly-once
CAS and does not adopt TBackend's daemon.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/src/wal.rs`
- `runtime/igniter-machine/src/recovery.rs`
- `runtime/igniter-machine/tests/storage_durability_proof_tests.rs`
- related receipt/recovery tests under `runtime/igniter-machine/tests/`

Known facts to re-verify:

- owner-split packet identified `wal.rs` flush-only and recovery silence as the
  machine gap;
- TBackend group-commit/fdatasync evidence is external inspiration only, not
  code to copy blindly;
- tests should not claim real power-loss safety unless they actually simulate
  it.

## Scope

Allowed:

- Add explicit fsync / sync_data / configurable group-commit behavior for the
  machine WAL path if live source confirms the gap.
- Add recovery reporting: counts, quarantined/skipped entries, or structured
  diagnostics for corrupt/truncated records.
- Add tests with tempdirs and deliberately corrupted WAL files.
- Update machine implemented-surface/proof docs if current truth changes.

Closed:

- No TBackend/home-lab/SparkCRM edits.
- No real power-loss claim beyond what tests prove.
- No Postgres receipt CAS changes.
- No public API churn unless the recovery report needs a small internal type.
- No server/web changes.

## Questions To Answer

1. Does `wal.rs` currently call `flush`, `sync_data`, or neither?
2. Is fsync required per record, per batch, or config-driven for machine use?
3. What should recovery return when it sees a malformed/truncated entry?
4. Should corrupt entries be quarantined, skipped with counts, or hard-fail?
5. Which guarantees remain weaker than TBackend's daemon after this slice?

## Acceptance

- [ ] Live WAL/recovery behavior characterized before editing.
- [ ] WAL durability policy is explicit in code and docs.
- [ ] Recovery no longer silently ignores corruption/truncation without a
      reportable signal.
- [ ] Tests cover clean replay and at least one corrupt/truncated WAL case.
- [ ] No hardware/power-loss guarantee is claimed beyond test evidence.
- [ ] Relevant machine tests pass.
- [ ] Proof packet states durability level and remaining gaps.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test storage_durability_proof_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml
git diff --check
```

Adapt exact filters after verify-first.

## Required Packet

Create:

```text
lab-docs/lang/lab-machine-wal-fsync-nonsilent-recovery-p2-v0.md
```

Packet must include:

- before-state;
- chosen fsync/group-commit policy;
- recovery failure taxonomy;
- tests/proofs run;
- explicit non-claims.

## Closing Report (2026-06-28)

Outcome: **implemented** in `runtime/igniter-machine/src/wal.rs` (machine-only).

Before: `append` did `flush()` only (no fsync); `replay()` silently `break`/
`continue`d on every truncation/corruption. The `.mpk` store already had the
explicit-fsync + corruption-report posture — the WAL is brought to match.

Changes (all additive to the public API; `replay()` signature unchanged):
- **Durability explicit:** `WalDurability { Flush, Sync }`; `append` flushes then
  (default `Sync`) `File::sync_data` (fdatasync); `with_durability` / `durability`
  accessors. Group-commit deliberately deferred (named in packet).
- **Non-silent recovery:** `replay_reported() -> WalReplay { facts, recovered,
  truncated_tail, corrupt: Vec<WalCorruption{offset,kind,detail}> }` with
  `WalCorruptionKind { CrcMismatch (stop), Deserialize (continue) }`. A torn tail
  is flagged + tolerated; mid-stream corruption is reported. Boot-facing
  `replay()` recovers the healthy prefix, tolerates a torn tail, and **fails
  closed** with `EngineError::Corruption` on mid-stream corruption — used at
  `machine.rs:77` with zero call-site change. Pre-alloc huge-length guard added.

Deliverable: `lab-docs/lang/lab-machine-wal-fsync-nonsilent-recovery-p2-v0.md`
(before-state, fsync policy, recovery taxonomy table, tests, durability level +
non-claims, remaining gaps).

Acceptance:

- [x] Live WAL/recovery behavior characterized before editing.
- [x] WAL durability policy explicit in code (`WalDurability`, per-record
      `sync_data`) and docs.
- [x] Recovery no longer silently ignores corruption/truncation — `WalReplay`
      report + fail-closed boot.
- [x] Tests cover clean replay + truncated tail + CRC mismatch + deserialize
      (5 tests, tempdirs, deliberately corrupted WAL files).
- [x] No power-loss guarantee claimed beyond test evidence (explicit non-claim;
      on-disk truncation/byte-flip = torn-write stand-in).
- [x] Machine tests pass — full suite 58 ok / 362 passed / 0 failed.
- [x] Proof packet states durability level + remaining gaps.
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Side updates: `IMPLEMENTED_SURFACE.md` gained a WAL durability row; audit-board
A21 → "PG-CAS + WAL DONE; seq remain".

Verification:

```text
cargo test … --test wal_fsync_recovery_tests        → 5 passed; 0 failed
cargo test … --test storage_durability_proof_tests  → 3 passed; 0 failed
cargo test … (full igniter-machine suite)           → 58 suites ok, 362 passed, 0 failed
git diff --check                                     → PASS
```
