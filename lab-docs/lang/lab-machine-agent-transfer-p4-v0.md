# lab-machine-agent-transfer-p4-v0 — audited two-phase capsule transfer envelopes

**Card:** `LAB-MACHINE-AGENT-TRANSFER-P4` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — transfer envelopes implemented + proven. 9 machine tests
(`tests/coordination_transfer_tests.rs`); full machine suite green. Builds on P2 (pools/ACL) +
P3 (messages). **Same machine; no federation, no signatures, no consensus, no production
serving.**

## What P4 adds

An audited **two-phase** handoff of a capsule ref between agents/pools:

```text
proposed → accepted          (the import happens here, once)
         → rejected          (recipient declines; no import)
         → revoked           (proposer/developer cancels; future accept refused)
         (expired)           reserved design-only — clock exists, P4 never produces it
```

**Pattern reuse of the P6 write lifecycle, NOT the write module** (the semantics differ enough
that direct reuse would be dirty): `proposed ≈ prepared`, `accepted ≈ committed`,
`rejected/revoked ≈ denied/aborted`. The shared properties are what matter — two-phase,
idempotent, audited, immutable source.

## Implementation (in `coordination.rs`)

- `TransferState` (`proposed|accepted|rejected|revoked|expired`), `TransferEnvelope`
  (transfer_id, from/to agent+pool, capsule_id, capsule_digest, `rights_granted`, reason, state,
  `recipe_digest?`, created_at).
- Stored as facts in `__transfers__`, keyed by transfer_id with state in the id → latest tx
  wins (same last-write-wins as the write receipt). `read_transfer` = latest state.
- Ops: `propose_transfer` / `accept_transfer` / `reject_transfer` / `revoke_transfer`, sharing a
  `terminalize` helper for reject/revoke. Refactor: the ACL decision is now `pool_authorized`
  (reused by `guard` and the transfer ops).

Authority: propose needs `ExportCapsule` on `from_pool` (and the capsule must be in it); accept
needs `ImportCapsule` on `to_pool`; reject = recipient, revoke = proposer; developer may do any
(audited).

## Proof (9 tests — 11 acceptance criteria)

| # | acceptance | test |
|---|---|---|
| 1,3,4 | propose (export) → accept (import) → ref appears; **source immutable, no byte copy** | `propose_accept_imports_ref_source_immutable` |
| 2 | recipient without `import_capsule` cannot accept | `recipient_without_import_cannot_accept` |
| 5 | rejected transfer does not import (and can't then be accepted) | `rejected_does_not_import` |
| 6 | revoked transfer prevents future accept | `revoked_prevents_accept` |
| 7 | duplicate accept is idempotent (no second import) | `duplicate_accept_idempotent` |
| 8 | transfer grants ONLY the declared rights | `transfer_grants_only_declared_rights` |
| 9 | developer can approve/override, audited | `developer_can_override_audited` |
| 10 | all state transitions are bitemporal audit facts | `all_transitions_audited` |
| 11 | transfer can carry a `ServiceRecipe` digest (optional, not served) | `transfer_carries_recipe_digest` |

## Decisions

- **Two-phase, idempotent**: accept only acts on a `proposed` envelope; an already-`accepted`
  one replays (no second import); terminal states (rejected/revoked) refuse accept.
- **Immutable source**: accept ADDS a content-addressed ref to the target pool (bytes already
  deduped in the content store), never copies bytes, never removes the source ref.
- **Declared rights only**: accept creates `PoolGrant`s for the recipient on the target pool
  limited to `rights_granted`.
- **`recipe_digest`** is a carried-but-inert forward field for the future dev→prod handoff; P4
  does not deploy or serve.

## Closed (held)

Same machine only. No federation. No signatures / crypto. No consensus / voting. No production
serving (recipe digest carried, not executed). No byte-copy explosion (content-addressed refs).
No language/VM change. (Transfer read path is proof-local via `read_as_of`.)

## Next route

- **P5 — votes/coordination** as messages (proposal/vote/decision over the P3 bus); no
  consensus.
- **ServiceRecipe + dev→prod handoff + agentless production serving** — now that transfer (P4)
  carries `recipe_digest` and `transfer_ownership` (P2) exists, the handoff has all its parts;
  serving is the next real step (its own card).
- later: federation (multi-machine signed envelopes).
