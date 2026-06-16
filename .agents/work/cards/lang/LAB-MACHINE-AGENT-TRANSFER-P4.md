# Card: LAB-MACHINE-AGENT-TRANSFER-P4 — audited two-phase capsule transfer envelopes

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P2 gave rights, P3 gave communication, P4 gives capsule transfer.

**Status: CLOSED 2026-06-16 — implemented + proven.** 9 machine tests
(`igniter-machine/tests/coordination_transfer_tests.rs`); full suite green. Code added to
`igniter-machine/src/coordination.rs`. Design doc:
`lab-docs/lang/lab-machine-agent-transfer-p4-v0.md`.

## Goal (met)

Audited two-phase capsule transfer between agents/pools:
`proposed → accepted/rejected/revoked` (`expired` reserved). **Pattern** reuse of P6
(`proposed≈prepared`, `accepted≈committed`) — NOT the write module. Same machine; no federation
/ signatures / consensus / production serving.

## Implementation (`coordination.rs`)

`TransferState`, `TransferEnvelope` (incl. `rights_granted`, optional `recipe_digest`); facts in
`__transfers__` (state-in-id, latest tx wins); ops `propose_transfer`/`accept_transfer`/
`reject_transfer`/`revoke_transfer` (+ shared `terminalize`); ACL extracted to `pool_authorized`
(reused by `guard`). Propose=`ExportCapsule` on source (capsule must be in pool); accept=
`ImportCapsule` on target; reject=recipient, revoke=proposer; developer may do any (audited).

## Proof (9 tests = 11 acceptance)

`propose_accept_imports_ref_source_immutable` (1,3,4),
`recipient_without_import_cannot_accept` (2), `rejected_does_not_import` (5),
`revoked_prevents_accept` (6), `duplicate_accept_idempotent` (7),
`transfer_grants_only_declared_rights` (8), `developer_can_override_audited` (9),
`all_transitions_audited` (10), `transfer_carries_recipe_digest` (11).

## Decisions

- two-phase + idempotent (accept acts only on `proposed`; re-accept replays; terminals refuse);
- immutable source (accept ADDS a content-addressed ref to target, no byte copy, source kept);
- declared rights only (accept grants recipient exactly `rights_granted` on target pool);
- `recipe_digest` carried-but-inert (forward field for dev→prod handoff; P4 does not serve).

## Closed

Same machine. No federation / signatures / consensus / voting. No production serving (recipe
carried, not executed). No byte-copy explosion. No language/VM change.

## Next

- P5 — votes/coordination as messages (no consensus).
- ServiceRecipe + dev→prod handoff + **agentless production serving** — all parts now exist
  (`transfer_ownership` P2 + `recipe_digest` P4); serving is the next real step (own card).
- later: federation (multi-machine signed envelopes).
