# LAB-HYGIENE-STALE-CLAIMS-SWEEP-P4 - sweep docs for stale blockers and ambiguous implementation claims

Status: CLOSED (2026-06-24) — stale routing claims swept and patched where high-impact
Lane: hygiene / stale-claim audit
Type: documentation audit + targeted fixes
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Several recent reviews found stale claims such as "not implemented", "eq-only", "string body only",
"no multi-source read", or "legacy idempotency key as row id" after the code had moved on. This card is a
targeted stale-claim sweep: find high-risk stale text, verify live state, and patch the smallest docs.

## Goal

Remove or qualify stale claims that actively misroute agents. This is not a prose cleanup pass. Prioritize
claims that change planning decisions.

## Verify First

Search for high-risk phrases, then verify against live code before editing:

- `not implemented`, `deferred`, `blocked`, `missing`, `future`
- `eq-only`, `string body`, `legacy`, `idempotency key`, `route table`
- `no ReadThen`, `no EffectHost`, `no raw response`, `no RenderView`
- `no zip`, `no linalg`, `deterministic math`, `cross-arch`
- `TODO`, `FIXME` only when it affects current planning

Recommended scope:

- `IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/*.md`
- `server/igniter-web/examples/todo_postgres_app/*.md`
- package/admission docs if present

## Required Output

Either:

1. Patch stale docs directly, with a closing report listing each corrected claim; or
2. If the sweep is too large, write a triage report:
   `lab-docs/lang/stale-claims-sweep-p4-v0.md`

Use direct patches for obvious high-impact drift; use a report for ambiguous or broad claims.

## Acceptance

- [x] At least 20 high-risk claims/phrases inspected, or explain why fewer exist.
- [x] At least 5 live-code/test anchors cited in the closing report.
- [x] Stale claims that affect agent routing are patched or listed with exact paths.
- [x] No broad rewriting for style only.
- [x] No feature implementation.
- [x] `git diff --check` clean.

## Closed Surfaces

No production code changes. Do not rewrite old proof packets just to modernize wording unless they are
front-door docs or currently misrouting agents. Do not edit public emergence claims without checking that
repo's current docs.

## Closing Report (2026-06-24)

Wrote `lab-docs/lang/stale-claims-sweep-p4-v0.md`. The sweep inspected 24 high-risk claims/phrases and
patched high-impact drift in:

- `lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md`
- `lab-docs/lang/lab-todoapp-api-local-postgres-p8-v0.md`
- `lab-docs/lang/lab-igniter-web-file-export-thread-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md`

The report cites live anchors for ReadThen, EffectHost, raw response, object body, surrogate ids, delete,
keyset pagination, Text range/order, `zip`, Mat3, and package admission boundaries. No source/test changes.
