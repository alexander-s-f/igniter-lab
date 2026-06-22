# LAB-HYGIENE-READTHEN-STATUS-CLARITY-P7 - stop docs implying staged ReadThen is implemented

Status: READY
Lane: workspace hygiene / IgWeb reads
Type: documentation cleanup
Delegation code: OPUS-HYGIENE-READTHEN-STATUS-CLARITY-P7
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics flagged a recurring ambiguity: some docs/cards discuss `ReadThen` as if it might be
active, while the latest live story is:

- P5/P10 designed the staged decision surface;
- P6 proved read -> continuation by hand/direct-dispatch harness;
- runner/productization work may exist adjacent to it;
- the actual compiler/prelude/runner support must be verified before any doc says "implemented".

Agents lose time when they infer `ReadThen` exists from readiness prose.

## Goal

Create a short, current status clarification for `ReadThen` and patch any high-traffic docs that currently
overstate implementation.

## Verify first

Run:

```text
rg -n "ReadThen|read then|staged read" lang/igniter-compiler/src server/igniter-web/src server/igniter-server/src lang/igniter-vm/src
rg -n "ReadThen|read then|staged read" lab-docs/lang .agents/work/cards/lang
```

Do not trust old proof docs. Live source wins.

## Allowed changes

- Update at most 3 high-traffic docs/cards with a short "Status as of 2026-06-22" note.
- Preferred targets if still stale:
  - `lab-docs/lang/lab-todoapp-api-runner-productization-p9-v0.md`
  - `lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md`
  - `lab-docs/lang/lab-igniter-workspace-drift-forensics-p1-v0.md`
- Update this card with a closing report.

## Closed surfaces

- No compiler, VM, runner, or `.igweb` implementation.
- No broad rewrite of historical proof docs.
- No claim of whole web-read stack green unless tested.

## Acceptance

- [ ] Live source inventory states whether a `ReadThen` arm/runner exists today.
- [ ] Any patched doc uses one of these exact categories: `designed`, `harness-proven`, `implemented`, `runner-integrated`.
- [ ] No doc claims `ReadThen` is active unless live source proves it.
- [ ] `git diff --check` clean.

## Closing report

TBD.
