# LAB-HYGIENE-IMPLEMENTED-SURFACE-REFRESH-P43

Status: CLOSED (2026-06-26)
Route: standard / hygiene
Skill: idd-agent-protocol

## Goal

Refresh the active implemented-surface front doors after the latest data-projection, TodoApp API, and
ViewArtifact work so agents stop routing around already-closed blockers.

This is a documentation hygiene card. Live source and tests win over older proof docs.

## Current Authority

Read first:

- `/Users/alex/dev/projects/igniter/docs/current-waves-2026-06-26.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- any adjacent `IMPLEMENTED_SURFACE.md` files under `server/`, `runtime/`, and `lang/`
- recent proof docs:
  - `lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md`
  - `lab-docs/lang/lab-igniter-data-projection-boot-diagnostic-p8-v0.md`
  - `lab-docs/lang/lab-todoapp-view-typed-rows-html-p18-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-link-node-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-link-nav-p27-v0.md`
  - `lab-docs/lang/lab-todoapp-api-product-surface-p41-v0.md`

## Verify-First Questions

Answer before editing:

1. Does `server/igniter-web/IMPLEMENTED_SURFACE.md` still claim typed row destructuring is missing or
   `rows_json`-only?
2. Does it distinguish:
   - `ReadThen` designed;
   - harness-proven;
   - runner-integrated;
   - boot/check diagnostic;
   - typed rows + `DatasetMeta`;
   - legacy `rows_json` compatibility?
3. Does it mention `RenderView`, `Render`, link node, typed rows -> HTML, and remaining held view-engine work?
4. Does TodoApp API surface include delete/keyset pagination/error envelope if those are live?
5. Are any "not implemented" claims stale?

## Boundary

Allowed:

- Update implemented-surface docs and small README pointers.
- Add a short "last refreshed" note with live code anchors.
- Add or update guard tests only if an existing guard already covers this doc shape.
- Update this card with a closing report.

Closed:

- No production source behavior changes.
- No new implementation.
- No canon claims.
- No broad proof-doc rewrite.
- Do not treat old readiness docs as current truth without live source checks.

## Required Verification

Run and report:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rg -n "rows_json only|typed row.*not|not implemented|harness-only|ReadThen|DatasetMeta|RenderView|link node|keyset|delete" \
  server runtime lang lab-docs .agents/work/cards/lang

cd server/igniter-web
cargo test --features machine --test implemented_surface_guard_tests
cargo test --features machine --test typed_readthen_tests --test typed_html_tests --test boot_diagnostic_tests

git diff --check
```

If some stale claims are intentionally preserved in old proof packets, do not edit them; note that the
implemented-surface front door supersedes them.

## Acceptance

- [x] Front-door docs reflect typed `ReadThen` runner integration.
- [x] Typed rows + `DatasetMeta` and legacy `rows_json` compatibility are both stated.
- [x] Boot/check structural diagnostics are stated without over-claiming dynamic source drift.
- [x] ViewArtifact link/nav and typed rows -> HTML are stated.
- [x] TodoApp API product surface is current or explicitly linked to current product docs.
- [x] Old proof packets are not rewritten unless they are active front doors.
- [x] Relevant guard/focused tests pass.
- [x] `git diff --check` clean.

## Reporting

Close with:

- files updated;
- stale claims removed or intentionally left in archived packets;
- exact tests/counts;
- remaining open surface gaps.

## Closing Report (2026-06-26)

Status: implemented-surface refresh complete.

Files updated:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
  - refreshed date/scope to 2026-06-26;
  - replaced stale typed-row `designed/not implemented` wording with typed `ReadThen` + `DatasetMeta`
    runner integration;
  - documented legacy `rows_json` compatibility;
  - documented `PROJECTION_SCHEMA_INVALID` boot/check structural diagnostics;
  - documented ViewArtifact `link`, flat nav, typed rows -> HTML, and remaining held grouped layout/export work;
  - clarified that current Todo JSON routes still use legacy `rows_json` even though the runner supports typed rows.
- `server/igniter-web/examples/todo_postgres_app/API.md`
  - changed keyset/envelope and open-limitations wording from "needs typed row destructuring" to "generic typed
    boundary exists; this product JSON route has not adopted it yet."
- `lab-docs/lang/current-waves-index.md`
  - moved typed rows + `DatasetMeta` from readiness-only to implemented runner surface;
  - routed next work to typed-row product payoff (`LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19`,
    `LAB-LANG-NUMBER-TO-TEXT-P1`) rather than substrate rediscovery.
- `lab-docs/lang/lab-todoapp-api-product-surface-p41-v0.md`
  - marked P41 as a historical checkpoint superseded by current `API.md` and `IMPLEMENTED_SURFACE.md`.
- `server/igniter-web/tests/implemented_surface_guard_tests.rs`
  - added stable anchors for `read_continuation`, `DatasetMeta`, `PROJECTION_SCHEMA_INVALID`,
    `typed_html_tests`, `RenderView`, and `link`.

Stale claims handled:

- Removed/qualified active-front-door claims that typed rows are "not implemented" or `rows_json`-only.
- Left old proof packets/cards intact when their stale wording is historical evidence, not an active front door.
- Added one supersession note to P41 because its title/content still presented it as the current Todo surface.

Verification:

- `rg -n "rows_json only|typed row.*not|not implemented|harness-only|ReadThen|DatasetMeta|RenderView|link node|keyset|delete" server runtime lang lab-docs .agents/work/cards/lang` completed; remaining hits are historical cards/proof packets or intentionally current product-route notes.
- `cargo test --features machine --test implemented_surface_guard_tests` passed: 2 passed, 0 failed.
- `cargo test --features machine --test typed_readthen_tests --test typed_html_tests --test boot_diagnostic_tests` passed in the current worktree: `typed_readthen_tests` 9 passed, `typed_html_tests` 6 passed, `boot_diagnostic_tests` 6 passed.
- `git diff --check` clean.
- Existing compiler/vm/tbackend/machine warnings only.

Remaining open surface gaps:

- Current Todo JSON list/show routes still use legacy `rows_json`; typed route adoption is app/product work.
- Source-dependent host-kind drift remains first-dispatch; boot/check only covers source-independent structural
  typed-continuation errors.
- Global cross-crate protocol error envelope remains deferred.
- Multi-DSN/cross-DB joins, schema migrations, public hosting, connection pooling, streaming/file export, and
  richer grouped ViewArtifact layout remain closed/deferred.
