# LAB-HYGIENE-CLOSED-CARD-COMPACTION-P3 - compact closed-card navigation without rewriting history

Status: CLOSED (2026-06-24) — closed-card archive index created without moving cards
Lane: hygiene / card archive
Type: documentation + index
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

The `.agents/work/cards/lang/` directory contains a long audit trail. That history is valuable, but it is
too noisy as an entry point. New agents sometimes start from old CLOSED cards and route around features
that already exist. We need an index/compaction layer, not deletion.

## Goal

Create a compact archive/index for CLOSED cards by direction, preserving the audit trail while making clear
which cards are historical evidence and which docs are the current front doors.

Suggested output:

`lab-docs/lang/closed-card-index.md`

## Verify First

- Do not move/delete cards.
- Use `rg '^Status: CLOSED' .agents/work/cards/lang` or equivalent to identify candidates.
- Cross-check high-volume themes against `IMPLEMENTED_SURFACE.md` and `current-waves-index.md` if P2 has
  landed.
- Treat duplicate numbering (for example multiple P22/P35-style lanes) as normal; disambiguate by title.

## Required Shape

Group CLOSED cards by topic:

- IgWeb routing/render/context.
- TodoApp API.
- Machine/Postgres/host IO.
- Package/workspace/archive/admission.
- Stdlib collections/math/linalg/statistics/random.
- VM/language pressure.
- Emergence/public science pointers.
- Hygiene/readiness/meta.

For each group, provide:

- newest/current front-door doc;
- notable closed milestones;
- superseded assumptions to ignore;
- "do not start here" warning if applicable.

## Acceptance

- [x] `closed-card-index.md` exists and groups CLOSED cards by topic.
- [x] It does not claim implementation from a card alone; it points to current surface docs/tests.
- [x] It names at least 5 superseded assumptions that caused agent drift.
- [x] It preserves audit trail: no cards moved/deleted/renamed.
- [x] It has an "Agent entrypoint" section that points to Implemented Surface + Current Waves first.
- [x] `git diff --check` clean.

## Closed Surfaces

No production code changes. No card deletion or mass editing. No status changes to old cards except if a
single obvious checkbox/status typo is blocking the index and is verified live.

## Closing Report (2026-06-24)

Created `lab-docs/lang/closed-card-index.md`. The index groups CLOSED cards by topic, names current
front doors, preserves the audit trail, and records superseded assumptions such as string-only Todo
create body, idempotency key as business id, fake-only Postgres, missing `zip`, Vec3-only linalg,
package admission as execution/deploy, and stale ReadThen runner status.

No cards were moved, deleted, or renamed.
