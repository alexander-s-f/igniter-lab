# LAB-MACHINE-RECEIPT-SEQID-ORDERING-READINESS-P3

Status: OPEN
Route: standard / main-audit / machine / durability
Skill: idd-agent-protocol
Depends-On: `LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2`,
`LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2`

## Goal

Decide the next machine-owned receipt ordering / `seq_id` slice after PG CAS and
WAL fsync/recovery are closed.

A21 is now "PG-CAS + WAL DONE; seq remain". This card should not blindly copy
TBackend's daemon seq model. It should characterize machine receipt ordering,
clock reliance, replay/recovery behavior, and decide whether the next step is a
small implementation, a storage-model readiness packet, or deferral to TBackend
receipt adoption.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md`
- `lab-docs/lang/lab-machine-durable-cas-pg-exactly-once-p2-v0.md`
- `lab-docs/lang/lab-machine-wal-fsync-nonsilent-recovery-p2-v0.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/src/write.rs`
- `runtime/igniter-machine/src/recovery.rs`
- receipt/reconcile/retry tests under `runtime/igniter-machine/tests/`
- TBackend hardening docs only as external evidence, not editable scope.

Known facts to re-verify:

- owner split says TBackend already owns daemon seq_id/CAS/group-commit;
- machine still has clock-ordered receipt concerns;
- PG CAS and WAL fsync are now closed, so this is the remaining ordering tail.

## Scope

Allowed:

- Produce a readiness packet with a concrete next card recommendation.
- Characterize current machine receipt ordering, timestamps, recovery ordering,
  and conflict/replay behavior.
- Define the meaning of a machine `seq_id` if one is needed.
- Name one implementation card only if the shape is clear.

Closed:

- No code unless a trivial read-only test/proof is explicitly justified.
- No TBackend/home-lab/SparkCRM edits.
- No cross-project receipt adoption implementation.
- No schema migration or live DB mutation.
- No claim that machine seq_id equals TBackend fact-log seq_id.

## Questions To Answer

1. What is currently the ordering authority for machine receipts: wall-clock,
   WAL append order, store iteration, PG committed_at, or none?
2. Which user-visible behaviors can break under clock skew or same-timestamp
   receipts?
3. Should machine add local monotonic `receipt_seq`, reuse WAL offset, or defer
   to TBackend daemon adoption?
4. What can be proven DB-free vs PG-gated?
5. What is the smallest next implementation card, if any?

## Acceptance

- [ ] Live receipt ordering/recovery paths characterized.
- [ ] TBackend seq_id treated as external evidence, not copied authority.
- [ ] Machine `seq_id` meaning is accepted, rejected, or deferred with reasons.
- [ ] At least two options compared.
- [ ] One next card named, or explicit HOLD/DEFER decision made.
- [ ] No code/home-lab/production mutation unless explicitly scoped.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test capability_io_recovery_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_reconcile_tests
git diff --check
```

Tests are optional if the packet stays doc-only; any behavior claim should be
grounded in live source or command output.

## Required Packet

Create:

```text
lab-docs/lang/lab-machine-receipt-seqid-ordering-readiness-p3-v0.md
```

Packet must include:

- live ordering model;
- risk analysis;
- options comparison;
- next card or hold decision.
