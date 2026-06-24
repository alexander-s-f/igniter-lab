# LAB-TODOAPP-API-NEXT-PRODUCT-SLICE-READINESS-P42 - choose the next TodoApp API product slice

Status: DRAFT
Lane: TodoApp API / product planning
Type: readiness packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

TodoApp API has crossed the toy boundary:

- local Postgres smoke and `igweb-serve` E2E are closed;
- `ReadThen` / EffectHost / host-config runner path is proven;
- object request body, surrogate ID, account existence, list-empty semantics, create-body compatibility,
  error-envelope readiness, read freshness, operator smoke, runbook, and product surface cards are closed.

The next slice should be chosen deliberately. Avoid adding endpoints just because they are easy; choose the
slice with the best product pressure and least architectural ambiguity.

## Goal

Recommend the next bounded TodoApp API product slice after local-PG E2E and product-surface hardening.

Compare at least these candidates:

1. update/toggle done;
2. delete;
3. pagination/keyset reads;
4. account/auth boundary;
5. error envelope implementation;
6. CI/product smoke hardening;
7. API docs/client fixture generation.

## Verify First

Read live app surfaces and latest cards:

- TodoApp API `.igweb` / `.ig` example files;
- host config example;
- API docs / runbook;
- local Postgres smoke tests;
- product smoke CI card;
- cards `P35`-`P41`;
- `server/igniter-web/IMPLEMENTED_SURFACE.md`.

Do not trust old readiness docs about missing runner support without checking source.

## Questions To Answer

1. What user-visible API is already usable end-to-end?
2. Which candidate adds the most product value with the least new substrate?
3. Which candidate would force new language/runtime work?
4. Which candidate improves confidence/operability rather than feature count?
5. What exact next implementation card should be written?

## Required Output

Write a readiness packet under `lab-docs/lang/` with:

- current Todo API surface table;
- candidate comparison;
- recommendation;
- rejected/parked candidates and why;
- acceptance matrix for the recommended implementation card.

## Acceptance

- [ ] Packet is grounded in live routes/tests/docs, not stale cards alone.
- [ ] At least 5 candidates compared.
- [ ] One recommended next slice named with a concrete card ID.
- [ ] Any required substrate/language work is explicitly called out or avoided.
- [ ] No production code changes.
- [ ] `git diff --check` clean.

## Closed Surfaces

- No API behavior changes.
- No DB migrations.
- No new runner code.
- No canon claim.
