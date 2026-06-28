# LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35

Status: OPEN
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

- [ ] Live P34/P33/server-gate surfaces are characterized.
- [ ] Gate decision states whether to proceed, hold, or require another
      prerequisite.
- [ ] Required authority artifacts are listed: checklist, signed passport,
      TLS/operator proof, human approval.
- [ ] No public/non-loopback listener is opened.
- [ ] Future implementation cards are named with closed surfaces.
- [ ] Proof/readiness packet is created.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

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
