# LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27 - sign the IgWeb effect passport mint point

Status: DONE
Lane: igniter-lab / web / igniter-web / foundation-hardening / T1
Type: implementation / authority wiring
Date: 2026-06-27
Skill: idd-agent-protocol
Depends-On:
- `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`
Source:
- `lab-docs/igniter-web-core-foundation-audit-p1.md`
- `lab-docs/igniter-machine-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is T1-1, second slice: after the machine data-plane accepts signed
passports, IgWeb must stop minting static/forgeable effect passports. The audit
claims there is one clean web mint point; verify that live.

Do not start this card until P26 is merged or until you can prove the machine
signed verifier path is already live.

## Goal

Wire IgWeb effect execution to signed `CapabilityPassport` creation/verification
without giving `.igweb` or app code ambient authority.

## Verify-First Anchors

Before editing, verify live line numbers:

```text
server/igniter-web/src/host_binding.rs
  effect passport mint point around prior :414
server/igniter-web/src/bin/igweb-serve.rs
  local host-config / machine-mode passport creation around prior :179
runtime/igniter-machine/src/capability.rs
  sign_passport / PassportVerifier / verify_passport_signed
```

Fresh grep from card creation showed:

```text
host_binding.rs:414 let ep = CapabilityPassport { ... }
igweb-serve.rs:179 let ep = CapabilityPassport { ... }
```

## Current Authority

- Live IgWeb + machine source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit `server/igniter-web` and narrowly import/use the machine
  signed passport API if P26 made it available.

## Closed Surfaces

- Do not edit route lowering, `.igweb` grammar, app examples, Postgres
  executor semantics, VM, compiler, stdlib, frame-ui, home-lab, SparkCRM, or
  canon `igniter-lang`.
- Do not create public listeners or loosen loopback-only behavior.
- Do not put secrets in app files or proof docs.

## Required Design

- Host-owned key material only. Prefer test-only deterministic keys and
  host-config/env shape already used by IgWeb; if no config shape exists, create
  the smallest explicit host-owned seam and document it.
- The `.igweb` app must never choose or see the signing key.
- Keep effect identity/correlation/idempotency behavior unchanged.
- Add a forged-passport negative test at the web effect-host boundary.

If host-config design is not yet sufficient for real signing key injection,
implement the test-local signed path and write a follow-up for host config
rather than embedding a magic production key.

## Acceptance

- [x] IgWeb effect host uses signed passports when calling the machine path.
- [x] Forged/unsigned effect passport is refused in a focused test.
- [x] Valid signed effect flow still succeeds with fake/local executor.
- [x] No `.igweb` syntax or app contract changes.
- [x] No public bind behavior changed.
- [x] Focused IgWeb/machine effect tests pass.
- [x] `git diff --check` passes.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-igniter-web-signed-effect-passport-p27.md
```

Close with exact mint/sign/verify path, host-owned key boundary, tests, and any
host-config follow-up.

Closed in:

```text
lab-docs/lang/lab-igniter-web-signed-effect-passport-p27.md
```
