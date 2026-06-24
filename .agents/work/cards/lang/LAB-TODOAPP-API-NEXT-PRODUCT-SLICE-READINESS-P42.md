# LAB-TODOAPP-API-NEXT-PRODUCT-SLICE-READINESS-P42 - choose the next TodoApp API product slice

Status: CLOSED — readiness packet written; recommends error-envelope implementation next
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

- [x] Packet is grounded in live routes/tests/docs, not stale cards alone.
- [x] At least 5 candidates compared.
- [x] One recommended next slice named with a concrete card ID.
- [x] Any required substrate/language work is explicitly called out or avoided.
- [x] No production code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

- No API behavior changes.
- No DB migrations.
- No new runner code.
- No canon claim.

## Closing Report (2026-06-24)

Produced [`lab-docs/lang/lab-todoapp-api-next-product-slice-readiness-p42-v0.md`](../../../../lab-docs/lang/lab-todoapp-api-next-product-slice-readiness-p42-v0.md).

Verify-first read the live TodoApp API surface (`routes.igweb`, `todo_handlers.ig`, `API.md`,
`host.example.toml`, `IMPLEMENTED_SURFACE.md`, `map_decision`/`surrogate_id`, and live tests) rather than
routing from stale cards. The packet confirms the current usable surface: health, account-scoped list/show,
create with object body + host surrogate id, and done via full-row upsert over the ReadThen/EffectHost runner
path.

Seven candidates were compared. The recommended next slice is
`LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43`: implement the P39-designed app error envelope (`RespondError` +
`ApiError`) because it adds zero DB/runtime substrate while improving every endpoint's client contract.
Delete/update/pagination/auth were parked because each forces new machine/read/write/identity substrate.

No production code changed in this card.
