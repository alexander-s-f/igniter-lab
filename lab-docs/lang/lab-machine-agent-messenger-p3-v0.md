# lab-machine-agent-messenger-p3-v0 — append-only audited messenger bus

**Card:** `LAB-MACHINE-AGENT-MESSENGER-P3` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — messenger implemented + proven. 9 machine tests
(`tests/coordination_messenger_tests.rs`); full machine suite green. Builds on the P2 foundation
(`coordination.rs`). **No delivery worker, no federation, no voting/consensus, no production
serving.**

## Guardrail (held)

> The messenger is **not hidden chat state**. It is **facts + audit + ACL**. No mutable inbox
> magic.

Every message is an append-only **fact** in `__messenger__`. "List my inbox" is a **query** over
message facts filtered by recipient + visibility — there is no mutable inbox object. A request
that `requires_ack` stays pending until an `Ack` fact links back to it. Every message operation
writes an audit fact (reusing the P2 audit channel).

## Implementation (in `coordination.rs`)

- `MessageKind` (`note|request|ack|escalation|decision`), `Message` (message_id, thread_id,
  from, to, kind, body_digest, capsule_refs, requires_ack, in_reply_to, created_at).
- `send_message` / `escalate` / `ack` / `list_inbox` / `read_thread` / `pending_requests`.
- Shared `authed()` helper = P5 `verify_passport` (op-class scope) + registered + active;
  messenger ops write exactly one audit fact (allowed or denied). Messages stored as facts via
  `write_message`; reads via a fact scan (`all_messages`).

Authority model: messaging authenticates the subject (passport, P5) but is not pool-scoped;
**carrying a `CapsuleRef` in a message does NOT grant capsule access** — pool ACL (P2
`check_right`) still governs.

## Proof (9 tests — Meta-Architect acceptance)

| # | acceptance | test |
|---|---|---|
| 1 | agent can send a note to a registered agent | `agent_can_send_note` |
| 2 | recipient can list/read messages addressed to them | `recipient_can_list_and_read` |
| 3 | third party cannot read a thread / another's inbox | `third_party_cannot_read` |
| 4 | a request requiring ack stays pending until acked | `request_pending_until_ack` |
| 5 | the ack is linked to the request id + routed to the requester | `ack_linked_to_request` |
| 6 | developer escalation → developer mailbox, audited | `developer_escalation_audited` |
| 7 | a message can carry a CapsuleRef, but access still needs pool rights | `capsule_ref_in_message_does_not_grant_access` |
| 8 | a revoked agent cannot send or read | `revoked_agent_cannot_send_or_read` |
| 9 | all message ops create bitemporal audit facts (allowed + denied) | `all_message_ops_audited` |

## Decisions

- **Messages = facts** in `__messenger__`; reads are queries (no mutable inbox).
- **Pending = computed** from facts (requests minus acks via `in_reply_to`), not a flag flipped
  on an object.
- **Inbox/thread visibility**: only the addressed agent, a thread participant, or a developer.
- **Developer mailbox** = the reserved recipient `"developer"`; any developer-kind agent reads it.
- **Capsule refs are pointers, not grants** — pool ACL is the only access authority.

## Closed (held)

No delivery worker / background dispatch. No federation. No voting / consensus / decision
quorum. No production serving. No mutable inbox. No crypto. No language/VM change. The
fact-scan read path is proof-local (a real host indexes by recipient/thread).

## Next route

- **P4 — CapsuleTransferEnvelope**: `proposed → accepted/rejected/revoked` (≅ receipt-gated
  write, P6), import into a target pool with rights — builds on P2 `transfer_ownership` + P3
  messages (the envelope is a message kind / thread).
- **P5 — votes/coordination** as messages (proposal/vote/decision); no consensus yet.
- later: ServiceRecipe + dev→prod handoff + agentless serving; then federation.
- engineering: recipient/thread indexing instead of a full scan; message body storage (P3 keeps
  only `body_digest`).
