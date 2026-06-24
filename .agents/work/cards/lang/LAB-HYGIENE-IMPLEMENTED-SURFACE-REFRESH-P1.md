# LAB-HYGIENE-IMPLEMENTED-SURFACE-REFRESH-P1 - refresh implemented-surface front doors from live code

Status: CLOSED (2026-06-24) — implemented-surface front doors refreshed; Gemini follow-up found live fleet HOLD and docs were corrected
Lane: hygiene / implemented surface
Type: documentation + verification
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

The lab has moved quickly across IgWeb/TodoApp, machine/Postgres, stdlib science, package/admission,
and VM/language pressure. Agents are starting from stale proof packets and rediscovering already-shipped
surfaces. This card refreshes the front-door `IMPLEMENTED_SURFACE.md` documents from live code so future
agents can verify first without archaeology.

Live docs currently known:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`

## Goal

Update implemented-surface docs so they answer, compactly and code-anchored:

1. What is implemented today.
2. What is harness-proven but not product-integrated.
3. What is readiness/design-only.
4. What is explicitly deferred.
5. Which tests/scripts prove each high-risk claim.

## Verify First

- Start with `find . -name IMPLEMENTED_SURFACE.md -print`.
- Read each existing implemented-surface doc.
- Grep live source/tests before changing any "missing", "deferred", or "not implemented" claim.
- For IgWeb/TodoApp, verify against:
  - `server/igniter-web/src/lib.rs`
  - `server/igniter-web/examples/todo_postgres_app/`
  - `server/igniter-web/tests/`
  - `server/igniter-web/scripts/check_todo_product_surface.sh`
- For machine/Postgres, verify against:
  - `runtime/igniter-machine/src/postgres_read.rs`
  - `runtime/igniter-machine/src/postgres_real.rs`
  - `runtime/igniter-machine/src/postgres_write*.rs`
  - `runtime/igniter-machine/tests/`
- For VM/stdlib/language, verify against:
  - `lang/igniter-vm/tests/`
  - `lang/igniter-compiler/tests/`
  - `lang/igniter-stdlib/stdlib/`

## Required Coverage

At minimum, make sure the refreshed docs cover these recent surfaces accurately:

- IgWeb route sugar: `scope`, `resource`, nested composition, route-level `via`, context `let`/single
  `guard`, `Render`, `RenderView`, raw response, typed ViewArtifact authoring.
- ReadThen/effect host: distinguish `designed`, `harness-proven`, `implemented`, and
  `runner-integrated`.
- TodoApp API: object body, surrogate IDs, error envelope, delete, keyset pagination, smoke/runbook
  status, account existence behavior.
- Machine/Postgres: typed reads, Text range/order with `COLLATE "C"`, fake vs real adapter, write
  receipts, idempotency, host policy, DSN safety.
- Stdlib/VM: collection `zip`, nested HOF coverage status, linalg Vec3/Mat3 package proofs, det math
  evidence tiers, known loop/VM gaps if still live.
- Package/admission if there is no dedicated implemented-surface doc: add a short pointer section or
  name the right front door to avoid agents hunting old cards.

## Acceptance

- [x] Every edited implemented-surface claim is backed by live code/tests, not old card memory.
- [x] Stale "not implemented/deferred" claims are either corrected or explicitly scoped with current
      evidence.
- [x] Each doc has a compact "Do not infer" / "Still not implemented" section.
- [x] IgWeb/TodoApp and machine status are separated; compile status and runner/live-DB status are not
      collapsed.
- [x] `git diff --check` clean.
- [x] Closing report lists edited files, key corrected stale claims, and tests/scripts used for evidence.

## Closed Surfaces

No production code changes. No new features. No card archiving. No canon/governance claims. Do not mark a
readiness packet as implemented unless live code/tests prove it.

## Closing Report (2026-06-24)

Edited front doors:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`

Key corrections/additions: IgWeb/TodoApp now names object create body, surrogate IDs, error envelope,
delete, keyset pagination, `ReadThen`/EffectHost categories, raw response, `RenderView`, and remaining
typed-row/global-envelope gaps. Machine now names typed reads, Text range/order with `COLLATE "C"`,
real/fake adapter split, delete op, DSN safety, and Postgres deferred boundaries. VM now names `zip`,
HOF math parity, Vec3/Mat3 package proofs, package/admission pointers, and bounded nested-HOF status.

Gemini P5 later found a live machine-fleet HOLD. I verified it with
`cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture` (11/13) and patched the machine
and VM front doors to stop claiming current whole-fleet green. Follow-up cards:
`LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5` and
`LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1`.
