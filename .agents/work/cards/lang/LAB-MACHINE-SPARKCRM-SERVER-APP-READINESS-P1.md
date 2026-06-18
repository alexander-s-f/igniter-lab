# Card: LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1 - SparkCRM-shaped ServerApp without live IO

**Lane:** standard / readiness-design  
**Status:** OPEN  
**Date opened:** 2026-06-18  
**Authority:** Lab-only product-shape packet. No live SparkCRM, no credentials, no production claim.

## Why this card exists

`igniter-server` now has a local Rack-like protocol and a machine-backed `InvokeEffect` path. The
next product question is not live integration; it is shape:

```text
vendor-like webhook -> SparkCRM-shaped ServerApp -> ServerDecision::InvokeEffect { target, input }
  -> local machine fixture -> receipt-backed response
```

This card turns the useful Gemini A4 findings into a bounded readiness packet. It must not open live
SparkCRM, a real public ingress, or real credentials.

## Read first

- `igniter-server/src/protocol.rs`
- `igniter-server/src/effect_host.rs`
- `lab-docs/lang/lab-machine-igniter-server-effect-p3-v0.md`
- `lab-docs/lang/lab-sparkcrm-webhook-auction-policy-p1-v0.md`
- `lab-docs/lang/lab-machine-sparkcrm-live-gate-p1-v0.md`
- `.agents/work/cards/lang/LAB-MACHINE-SPARKCRM-LIVE-GATE-P1.md`
- `lab-docs/lang/lab-machine-igniter-server-gemini-wave-a-synthesis-v0.md`

## Goal

Write a readiness packet for a SparkCRM-shaped `ServerApp` that maps vendor-style webhook requests
to logical server targets and duplicate policy decisions, while keeping effect identity and live IO
host-owned/gated.

## Required answers

1. **Candidate targets.**
   - Propose logical inbound targets such as `lead-intake`, `lead-bid`, or `lead-status`.
   - Distinguish them from outbound capability IDs like a SparkCRM API executor.
   - Do not put `capability_id`, `operation`, or `scope` in app decisions.

2. **Request normalization.**
   - Define how raw vendor-like fields become a stable local input shape.
   - Include duplicate key extraction precedence.
   - Include what happens when no key exists.
   - Keep all examples local/fixture-safe.

3. **Duplicate / auction policy.**
   - Preserve the existing distinction:
     `idempotency = safety envelope`, `duplicate_policy = business strategy`.
   - Explain `bounded_fresh(n)` and deterministic `attempt_index` code generation.
   - Explain `after_limit = dedup_last` as a proposed auction profile, not canon.

4. **Authority and live gate.**
   - State exactly what remains behind the human live gate:
     public ingress, real SparkCRM endpoint, credentials, mutating live actions, deployment.
   - Do not propose live DB or live SparkCRM as an implementation next step.

5. **Shadow path.**
   - Propose a local/offline shadow harness using recorded fixture payloads.
   - It may compare legacy outcomes if data is provided, but it must not touch production systems.

## Deliverables

- Readiness packet:
  `lab-docs/lang/lab-machine-sparkcrm-server-app-readiness-p1-v0.md`
- Closing report in this card.

## Acceptance

- [ ] Packet answers all five required question groups.
- [ ] Packet uses current live status: P3 server effect path is closed; Postgres P2/P3/P4/P7/P8
      are not proposed as future work if already closed.
- [ ] Packet contains no live DB, live SparkCRM, public network, or credential instructions.
- [ ] Packet separates inbound server target names from outbound capability/executor names.
- [ ] Packet preserves auction duplicate policy as configurable product strategy, not language canon.
- [ ] Packet proposes a next local/shadow card, not a live implementation.

## Closed surfaces

- No code.
- No live SparkCRM.
- No live DB.
- No public ingress.
- No credentials.
- No deployment.
- No canon claim.

## Suggested next local card

`LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2` - fixture-only `ServerApp` plus recorded sample payloads
that produce `InvokeEffect` decisions through local fake executors, with no external IO.

