# LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-OWNER-SPLIT-P1

Status: OPEN
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

