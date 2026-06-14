# LAB-AIR-COMBAT-BASELINE-P2

**Status:** CLOSED — PROVED 115/115 PASS  
**Route:** lab / app baseline / air_combat rebaseline after entrypoint  
**Date:** 2026-06-14  
**Authority:** evidence rebaseline only; no implementation

## Goal

Re-freeze `air_combat` after the safe `entrypoint RunDuel` refactor.

`LAB-AIR-COMBAT-BASELINE-P1` closed at 99/99 with the pre-entrypoint source hash. Opus added the first fleet use of the implemented bare `entrypoint` selector to `air_combat/example.ig`, which intentionally changed the source hash and added AC-P10 pressure for rich PROP-029 named run profiles.

## Current Claimed Baseline

From `air_combat/PRESSURE_REGISTRY.md` after the refactor:

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| contracts | 31 |
| entrypoint | `RunDuel` |
| source_hash | `sha256:8b698e66d8635f83306d209c702f7231c8184b1e6ffddb8a63f3a147ed9600f8` |
| new pressure | AC-P10 — named run-profiles wanted |

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-AIR-COMBAT-BASELINE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/report.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/example.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch13-managed-recursion.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md`

## Proof Questions

1. Does full `air_combat` still compile cleanly in Ruby and Rust after `entrypoint RunDuel`?
2. Is the new source hash stable and different only because of the entrypoint line/comment pressure note?
3. Does manifest/metadata contain `entrypoint RunDuel` as the program selector?
4. Are P1 metrics still stable: files, types, contracts, static calls, folds, maps/filters?
5. Are AC-P01..AC-P09 preserved unchanged?
6. Is AC-P10 correctly routed to rich PROP-029 named run profiles, not app-specific host-loop config?
7. Is ServiceLoop / PROP-037 direction still preserved for tick-loop work?
8. Is the Rust package-writer/stdout flake avoided through Open3/mktmpdir or an equivalent clean subprocess path?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_air_combat_baseline_p2.rb`, target at least 70 checks.
- Rebaseline doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-air-combat-entrypoint-rebaseline-v0.md`.
- Update `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/PRESSURE_REGISTRY.md` closure summary if needed.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is ok / 0 diagnostics.
- Rust compile is ok / 0 diagnostics.
- `entrypoint RunDuel` is verified in source and artifact metadata.
- Source hash is frozen as `sha256:8b698e66d8635f83306d209c702f7231c8184b1e6ffddb8a63f3a147ed9600f8` or drift is explained.
- AC-P01..AC-P10 are preserved and routed.
- No app source edits.

## Closed Surfaces

- No compiler changes.
- No app source migration.
- No rich entrypoint / profile implementation.
- No ServiceLoop runtime work.
- No IO/runtime/capability work.

## Closure Summary

Closed on 2026-06-14.

Result:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
ruby igniter-view-engine/proofs/verify_lab_air_combat_baseline_p2.rb
RESULT: 115/115 PASS  |  0 FAIL
```

Live dual-toolchain baseline:

- Ruby: `ok` / 0 diagnostics.
- Rust: `ok` / 0 diagnostics.
- contracts: 31.
- entrypoint: `RunDuel`.
- source_hash:
  `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55`.

The dispatch-card hash
`sha256:8b698e66d8635f83306d209c702f7231c8184b1e6ffddb8a63f3a147ed9600f8`
is superseded by the live Ruby/Rust artifact evidence. No `.ig` app source files
were changed for this P2 rebaseline.

AC-P01..AC-P10 are preserved. AC-P10 is routed to PROP-029 rich named run
profiles, not app-specific host-loop config. ServiceLoop / PROP-037 direction is
preserved as evidence only; no runtime authority is introduced.
