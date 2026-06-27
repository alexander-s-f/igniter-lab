# LAB-STDLIB-IO-SANDBOX-HARDENING-P1 - canonical sandbox root and symlink-safe writes

Status: DONE
Lane: igniter-lab / stdlib / IO / foundation-hardening
Type: implementation / sandbox hardening
Date: 2026-06-27
Skill: idd-agent-protocol
Source:
- `lab-docs/igniter-stdlib-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is the stdlib IO sandbox hardening slice. The audit found a write
symlink-escape and a brittle hardcoded substring gate. The goal is not to build
a new capability system; it is to make the current experimental IO surface fail
closed and stop relying on string containment.

## Goal

Make stdlib IO sandbox checks canonical and symlink-safe:

```text
write through symlink inside sandbox -> refused
target absent but parent escapes      -> refused
path containing "/igniter-stdlib/out" as substring outside sandbox -> refused
normal write inside sandbox           -> still works
```

## Verify-First Anchors

Before editing, verify live line numbers. Audit anchors:

```text
lang/igniter-stdlib/src/io.rs
  lexical clean_path / absent-target canonical re-check skip around prior :114-128
  write follows symlink around prior :363
  hardcoded substring gate around prior :80
```

Also read:

```text
lang/igniter-stdlib/IMPLEMENTED_SURFACE.md
lab-docs/stdlib/lab-experimental-io-*.md
```

## Current Authority

- Live stdlib source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit only `lang/igniter-stdlib` source/tests and this card.

## Closed Surfaces

- Do not redesign capability passports.
- Do not route IO through machine unless a tiny adapter already exists and the
  patch stays obviously local; otherwise document it as a follow-up.
- Do not edit VM, compiler, web, server, machine, frame-ui, home-lab, SparkCRM,
  or canon `igniter-lang`.

## Required Design

- Replace substring checks with a canonical sandbox root and `starts_with`
  containment.
- For writes to a missing file, canonicalize and validate the parent directory
  before opening.
- Refuse symlink traversal for write targets. Prefer platform-supported
  no-follow/open options where available, with a deterministic fallback if the
  crate currently avoids platform-specific APIs.
- Keep the sandbox root configurable through the existing authority/config path
  if one exists; otherwise keep the existing default but remove substring logic.

## Acceptance

- [x] Test proves hardcoded substring path outside the real sandbox is refused.
- [x] Test proves write through symlink escape is refused.
- [x] Test proves missing-target parent escape is refused.
- [x] Test proves normal write inside sandbox still succeeds.
- [x] Existing stdlib tests pass.
- [x] `cargo test` from `lang/igniter-stdlib` passes.
- [x] `git diff --check` passes.
- [x] Patch is limited to `lang/igniter-stdlib` plus this card and the required proof doc.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-stdlib-io-sandbox-hardening-p1.md
```

Close with exact sandbox policy, platform-specific notes, exact
commands/results, and any follow-up recommendation to route experimental IO
through `igniter-machine`.
