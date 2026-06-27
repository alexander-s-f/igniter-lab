# LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26 - wire signed passports onto machine authority paths

Status: DONE
Lane: igniter-lab / runtime / igniter-machine / foundation-hardening / T1
Type: implementation / authority wiring
Date: 2026-06-27
Skill: idd-agent-protocol
Source:
- `lab-docs/igniter-machine-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`
- `.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21.md`

## Agent Onboarding Header

This is T1-1, first slice: the signed passport primitive exists and is tested,
but several production authority paths still call the weaker digest-only
`verify_passport`. Wire the proven signed verifier into the machine data-plane.

Do not solve web/server public bind in this card. Do not add network exposure.
This is local authority verification only.

## Goal

Replace forgeable digest-only checks on machine authority paths with
`verify_passport_signed` / `PassportVerifier`, and add a negative test proving a
hand-constructed passport with a forged `evidence_digest` is refused.

## Verify-First Anchors

Before editing, verify live line numbers:

```text
runtime/igniter-machine/src/capability.rs
  CapabilityPassport
  PassportVerifier
  verify_passport
  verify_passport_signed
runtime/igniter-machine/src/write.rs
  run_write_effect / run_write_effect_* authority check
runtime/igniter-machine/src/coordination.rs
  CoordinationHub authority check sites
runtime/igniter-machine/src/service_loop.rs
  typed passport serving path
```

Fresh grep from card creation showed:

```text
capability.rs:284 verify_passport_signed
write.rs:232 verify_passport(...)
coordination.rs:304 / :625 verify_passport(...)
service_loop.rs typed CapabilityPassport path
```

The exact call-sites may have moved; live source wins.

## Current Authority

- Live `runtime/igniter-machine` source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit `runtime/igniter-machine` source/tests and this card.

## Closed Surfaces

- Do not edit `server/igniter-web`, `server/igniter-server`, VM, compiler,
  stdlib, frame-ui, home-lab, SparkCRM, or canon `igniter-lang`.
- Do not create public listeners or change bind policy.
- Do not redesign `CapabilityPassport`; use the existing signed primitive.
- Do not change effect semantics beyond refusing unsigned/forged authority.

## Required Design

- Introduce or thread a `PassportVerifier` through the machine paths that
  currently need to authenticate passports.
- Prefer explicit constructor/config for the verifier over hidden global state.
- Preserve existing scope/time checks after authenticity succeeds.
- Add a deterministic test fixture/key; do not use real secrets.
- Negative test must fail before the patch: forged `evidence_digest` + no valid
  MAC should be refused.

If a call-site cannot be migrated without a larger host-config decision, leave
it closed and document the exact reason in the closing report instead of adding
ad hoc bypasses.

## Acceptance

- [x] Machine write path refuses a forged/unsigned passport.
- [x] Coordination path refuses a forged/unsigned passport.
- [x] Existing valid signed passport path succeeds.
- [x] Existing scope/time refusals still behave as before.
- [x] No public bind or transport behavior changed.
- [x] Focused machine tests pass.
- [x] Full relevant machine crate tests pass or any unrelated failure is
      isolated with evidence.
- [x] `git diff --check` passes.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-machine-signed-passport-dataplane-p26.md
```

Close with exact verifier threading, exact negative tests, commands/results,
and a list of any remaining unsigned passport call-sites if they intentionally
remain.
