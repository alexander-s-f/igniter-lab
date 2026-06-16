# Card: LAB-MACHINE-AGENT-MESSENGER-P3 — append-only audited messenger bus

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P2 gave rights; P3 gives communication; P4 will give capsule transfer.

**Status: CLOSED 2026-06-16 — messenger implemented + proven.** 9 machine tests
(`igniter-machine/tests/coordination_messenger_tests.rs`); full suite green. Code added to
`igniter-machine/src/coordination.rs`. Design doc:
`lab-docs/lang/lab-machine-agent-messenger-p3-v0.md`.

## Goal (met)

Append-only audited messages on the P2 foundation: direct note, request/ack, developer
escalation, capsule refs in messages, participant visibility, every op audited. **No delivery
worker, no federation, no voting/consensus, no production serving.**

## Guardrail

The messenger is NOT hidden chat state — it is **facts + audit + ACL**. Messages are append-only
facts in `__messenger__`; "list inbox" is a query; "pending" is computed (requests minus acks).

## Implementation (`coordination.rs`)

`MessageKind`, `Message`, `send_message`/`escalate`/`ack`/`list_inbox`/`read_thread`/
`pending_requests`; shared `authed()` (P5 verify_passport + active) + one audit fact per op.
Carrying a `CapsuleRef` does NOT grant access — pool ACL (`check_right`) still governs.

## Proof (9 tests = acceptance)

`agent_can_send_note`, `recipient_can_list_and_read`, `third_party_cannot_read`,
`request_pending_until_ack`, `ack_linked_to_request`, `developer_escalation_audited`,
`capsule_ref_in_message_does_not_grant_access`, `revoked_agent_cannot_send_or_read`,
`all_message_ops_audited`.

## Closed

No delivery worker / background dispatch. No federation. No voting/consensus. No production
serving. No mutable inbox. No crypto. No language/VM change. (Fact-scan read path is proof-local;
real host indexes by recipient/thread.)

## Next

- P4 — CapsuleTransferEnvelope (`proposed→accepted/rejected/revoked` ≅ receipt-gated write;
  import into target pool with rights; builds on `transfer_ownership` + P3 messages).
- P5 — votes/coordination as messages (no consensus). Later: ServiceRecipe + handoff +
  agentless serving; then federation.
