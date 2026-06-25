# LAB-DISTRIBUTION-PROOF-DOC-NORMALIZATION-P15 - normalize P11/P12 proof docs

Status: CLOSED (2026-06-25) — P11 + P12 standalone proof docs written under lab-docs/lang/
Lane: distribution / docs hygiene
Type: documentation hygiene
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

During the P10-P13 harvest, P10 and P13 had standalone `lab-docs` packets, while P11 and P12 closed their
proofs inside the cards only. That is acceptable, but the distribution lane is becoming a user-facing DX
thread; consistent proof packets make future curation easier.

## Goal

Create standalone proof docs for:

- `LAB-DISTRIBUTION-TOOLCHAIN-INSTALL-DELEGATION-P11`
- `LAB-DISTRIBUTION-PACKAGE-DELEGATION-P12`

without changing code.

## Verify First

- Read the closed P11/P12 cards.
- Read current `bin/igniter`.
- Verify the current tests / manual command surface are still true enough to summarize.
- Do not re-run expensive install builds unless needed; cite current harvest evidence and, if cheap, run small smoke commands.

## Required Docs

Write:

- `lab-docs/lang/lab-distribution-toolchain-install-delegation-p11-v0.md`
- `lab-docs/lang/lab-distribution-package-delegation-p12-v0.md`

Each should include:

- card id and status;
- verify-first basis;
- what changed;
- exact command behavior;
- tests/proofs;
- closed surfaces;
- follow-ons.

## Acceptance

- [x] P11 standalone proof doc exists (`lab-docs/lang/lab-distribution-toolchain-install-delegation-p11-v0.md`).
- [x] P12 standalone proof doc exists (`lab-docs/lang/lab-distribution-package-delegation-p12-v0.md`).
- [x] Docs do not contradict current `bin/igniter` — written against live `cmd_toolchain_iu` / `cmd_package`
      / `resolve_igc`, and re-confirmed by cheap non-mutating smoke (help text + update-no-manifest guard +
      real `package graph`→igc exit 0).
- [x] No stale transient red-test language — docs state suites green; no doctor/parallel-work red mentions.
- [x] No code changes (two new docs only).
- [x] `git diff --check` clean.

## Closed Surfaces

No implementation. No command behavior changes. No card renumbering. No release claim.

