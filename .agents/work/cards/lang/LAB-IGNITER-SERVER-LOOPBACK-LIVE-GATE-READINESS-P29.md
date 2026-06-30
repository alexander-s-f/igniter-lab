# LAB-IGNITER-SERVER-LOOPBACK-LIVE-GATE-READINESS-P29 - design the non-loopback bind gate

Status: DONE
Lane: igniter-lab / server / web / machine / foundation-hardening / T1
Type: readiness / gate design
Date: 2026-06-27
Skill: idd-agent-protocol
Depends-On:
- `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`
- `LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27`
- `LAB-IGNITER-SERVER-INBOUND-HARDENED-READ-P28`
Source:
- `lab-docs/igniter-server-core-foundation-audit-p1.md`
- `lab-docs/igniter-web-core-foundation-audit-p1.md`
- `lab-docs/igniter-machine-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`

## Agent Onboarding Header

This is a readiness card, not an implementation card. The foundation audits
converge on one hard gate: non-loopback bind must be impossible unless a
security checklist has been satisfied. Design that gate precisely.

Do not open a public listener. Do not add a bypass. Do not implement live bind.

## Goal

Specify the minimal structural gate for `bind != loopback` across
`igniter-server`, IgWeb, and machine runners.

The gate should make non-loopback construction require a host-owned checklist
token proving:

```text
signed passport path wired
body cap enabled
read timeout enabled
fail-closed auth enabled when auth is configured
inbound TLS story explicitly chosen or non-loopback refused
operator/human sign-off present
```

## Verify-First Anchors

Before writing, verify live code:

```text
server/igniter-server/src/serving_loop.rs
  ServingPolicy::new default loopback_only=false
  enforce_loopback
server/igniter-server/src/effect_host.rs
  serve_once_effect loopback gap
server/igniter-web/src/bin/igweb-serve.rs
  parse_loopback_addr / CLI refusal behavior
server/igniter-web/src/machine_runner.rs
  machine-mode loopback checks
runtime/igniter-machine/src/serving_loop.rs / ingress.rs
  local serving loop assumptions
```

Also verify what P26/P27/P28 have changed if they have already landed.

## Current Authority

- Live server/web/machine code decides current behavior.
- Audit docs are evidence only.
- This card may write only a readiness packet and update this card.

## Closed Surfaces

- No production code changes.
- No public bind.
- No TLS implementation.
- No host-config schema changes unless only described as proposed shape.
- Do not edit app examples, VM, compiler, stdlib, frame-ui, home-lab, SparkCRM,
  or canon `igniter-lang`.

## Questions To Answer

1. Which crate owns the canonical gate type? Audit bias says
   `igniter-server`; verify.
2. Is `loopback_only` default-on a breaking change for current tests/tools?
3. Should non-loopback be compile-time impossible, config-parse refused, or
   runtime refused?
4. What exact checklist fields are required for v0?
5. How do IgWeb runner and machine runner prove they use the same gate?
6. How does the gate report refusal without leaking secrets/config?
7. What is explicitly out of v0 (public TLS, ACME, reverse proxy, deploy)?

## Acceptance

- [x] Readiness packet compares at least three gate designs.
- [x] Recommends one v0 design with exact owner crate and type/API sketch.
- [x] Names exact implementation card(s) after readiness.
- [x] Confirms no code changes and no public bind.
- [x] `git diff --check` passes.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-igniter-server-loopback-live-gate-readiness-p29.md
```

Close with recommendation, rejected alternatives, dependency status
(P26/P27/P28), and the smallest next implementation card.
