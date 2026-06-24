# LAB-HYGIENE-CURRENT-WAVES-INDEX-P2 - create a current waves index for active Igniter directions

Status: CLOSED (2026-06-24) — current waves index created and corrected after Gemini fleet-HOLD finding
Lane: hygiene / planning
Type: documentation + navigation
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

The lab now has several active engines: business/TodoApp API, science/stdlib/emergence, package/remote
trust, machine/Postgres, IgWeb rendering, VM/language ergonomics, and home-lab side tracks. The user wants
a command-center view so agents stop routing from stale individual cards.

## Goal

Create or update one living index under `lab-docs/lang/` that maps the active waves and their next safe
slices. Suggested path:

`lab-docs/lang/current-waves-index.md`

This is a living navigation doc, not a dated snapshot. Keep it compact enough to be read before dispatching
agents.

## Verify First

- Read current `IMPLEMENTED_SURFACE.md` docs.
- Inspect recent CLOSED cards in `.agents/work/cards/lang/` only as evidence, not authority.
- Prefer live test/script names and current docs over old proof-packet claims.
- Check `git log --oneline -20` for recently landed slices.

## Required Shape

For each wave, include:

- **Implemented:** what is live and where to verify it.
- **Harness-proven:** real proof exists, but not product-integrated.
- **Readiness-only:** designed but not implemented.
- **Deferred/blocked:** what not to assume.
- **Next cards:** 1-3 concrete next slices.

At minimum cover:

- TodoApp API/product hardening.
- IgWeb rendering/ViewArtifact/html/raw response.
- Machine/Postgres host IO, ReadThen, EffectHost.
- Stdlib science: random/statistics/linalg/det math/collections.
- Package/workspace/archive/admission/remote trust.
- VM/language pressure: loops, HOF eval_ast, signature-bound contract surface, typed rows if current.
- Emergence/public science boundary and pointers, without importing private home-lab details.

## Acceptance

- [x] A single current-waves index exists and is easy to scan.
- [x] Every wave has `implemented/harness-proven/readiness-only/deferred/next` labels.
- [x] At least one code/test/doc anchor is named for each implemented or harness-proven claim.
- [x] The doc explicitly says old cards are evidence, not backlog authority.
- [x] No secrets/private host details are copied.
- [x] `git diff --check` clean.
- [x] Closing report names the recommended next parallel wave.

## Closed Surfaces

No production code changes. No new readiness decisions beyond summarizing current evidence. Do not update
public emergence docs unless specifically required; link or summarize only.

## Closing Report (2026-06-24)

Created `lab-docs/lang/current-waves-index.md` with wave rows for TodoApp API, IgWeb rendering/routing,
Machine/Postgres/host IO, ReadThen/EffectHost, stdlib science, package/archive/admission, VM/language,
emergence, and remote-node/substrate work. Each row separates implemented, harness-proven,
readiness-only, deferred/blocked, and next cards.

After Gemini P5, updated the VM/language row to name the current 2026-06-24 machine-fleet HOLD:
`batch_importer` (`eval_ast variant_construct`) and `web_router` (match-arm record literal/block
ambiguity). Recommended immediate repair cards now appear before feature-wave continuation.
