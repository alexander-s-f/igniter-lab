# LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35

Status: CLOSED (2026-06-28)
Route: standard / main-audit / igniter-web / live-bind gate
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34`

## Goal

Design the actual live-bind authority gate after P34 parse-only checklist,
without opening public bind.

P34 proved that IgWeb can parse and diagnose `[host.live_bind]`, but explicitly
kept the runner calling `authorize_bind(addr, None)`. This card decides the next
safe gate: how operator assertions become a server `LiveBindChecklist`, how
signed inbound authority is verified, and what TLS/human-proof is required
before any non-loopback listener can be demonstrated.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-web-host-live-bind-checklist-parse-p34-v0.md`
- `lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- server live-bind gate source in `server/igniter-server`

Known facts to re-verify:

- public/non-loopback bind remains closed even with a complete parsed checklist;
- P34 is parse/diagnostic only;
- TLS is metadata-only so far unless live source says otherwise;
- this card is a gate decision/readiness packet, not a non-loopback demo.

## Scope

Allowed:

- Produce a readiness/gate decision packet.
- Define the operator assertion verification flow.
- Define how parsed checklist becomes server `LiveBindChecklist`.
- Define signed-passport/inbound authority seam and TLS transport requirement.
- Name the future implementation/proof cards.
- Update audit control board only if this card reaches a clear decision.

Closed:

- Do not open or demonstrate a public/non-loopback listener.
- Do not wire checklist into `authorize_bind` unless the card proves this is a
  tiny readiness-only refactor that still fails closed.
- Do not implement TLS transport.
- Do not create production deploy instructions.
- Do not weaken loopback defaults.

## Questions To Answer

1. What exact evidence converts operator config assertions into server bind
   authority?
2. Is signed-passport verification required before or inside `authorize_bind`?
3. What TLS mode is acceptable for a first human-gated proof?
4. What must be logged/reported without leaking secrets?
5. What is the smallest future implementation card that still keeps public bind
   closed until human approval?

## Acceptance

- [x] Live P34/P33/server-gate surfaces are characterized.
- [x] Gate decision states whether to proceed, hold, or require another
      prerequisite.
- [x] Required authority artifacts are listed: checklist, signed passport,
      TLS/operator proof, human approval.
- [x] No public/non-loopback listener is opened.
- [x] Future implementation cards are named with closed surfaces.
- [x] Proof/readiness packet is created.
- [x] `git diff --check` passes.
- [x] Card is closed with a concise report.

## Report (2026-06-28)

Doc-only gate-decision packet. **No source changed.** Decision: **HOLD** public-bind
enablement, **PROCEED** with a defined authority chain, **require two prerequisites**
(durable signed passport + inbound verification; TLS in force) before any non-loopback
proof.

Verify-first re-characterized the live surface (§1 of the packet). Load-bearing facts:
`authorize_bind` is **pure** (so passport verification cannot live inside it); inbound auth
is a **static shared-bearer-token map** (`ingress.rs`), not cryptographic; the effect
signing key is **ephemeral pid+nanos** (`host_binding.rs`); `igweb-serve` still calls
`authorize_bind(addr, None)` and nothing converts a parsed `LiveBindConfig` into a server
`LiveBindChecklist`.

Answers (full detail in §4):
1. Evidence = host-verified runtime state set into `LiveBindChecklist` (not raw operator
   booleans) + TLS proof + human approval. Operator=intent, host=capability, human=authority.
2. Signed-passport verification is **before/outside** `authorize_bind` (pure); it lives at
   the inbound request seam via a durable `PassportVerifier`. The boolean is an attestation.
3. First proof TLS = `terminated_upstream` only; `native_tls` blocked (no transport).
4. Log: bind class, opaque `checklist_digest`, refusal code + missing field, signoff/approval
   id, TLS enum. Never: passport/file/DSN/token material. Reuse P29 redaction + P34 diags.
5. Smallest next card = **dry-run verdict** (P36): config→checklist→`authorize_bind` verdict
   REPORTED, never binds non-loopback. Fails closed; high operator value.

Named cards (closed surfaces in packet §5): `…DRY-RUN-VERDICT-P36` (now) → parallel
`…INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37` + `…TLS-TERMINATED-UPSTREAM-RUNBOOK-P38` →
human-gated `…LIVE-BIND-HUMAN-GATED-PROOF-P39` (last; only this may open a non-loopback
socket, under human approval). Public bind stays closed through P36–P38.

Artifacts: packet `lab-docs/lang/lab-igniter-web-live-bind-gate-decision-readiness-p35-v0.md`;
audit board A10 next-slice updated to the P35 chain. `git diff --check` PASS.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git diff --check
```

If you inspect code with tests, keep them read-only/proof-oriented and do not
bind non-loopback addresses.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-live-bind-gate-decision-readiness-p35-v0.md
```

Packet must include:

- gate decision;
- required authority chain;
- explicit refusal to open public bind in this card;
- next implementation/proof card names.
