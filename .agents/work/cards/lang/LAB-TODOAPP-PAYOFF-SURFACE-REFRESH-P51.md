# LAB-TODOAPP-PAYOFF-SURFACE-REFRESH-P51

Status: CLOSED (2026-06-26)
Route: fast_lane / implemented-surface hygiene
Skill: idd-agent-protocol

## Goal

Refresh the active front-door docs after the Todo payoff wave so future agents
do not rediscover stale gaps.

This is a hygiene card. It should run after at least one of these lands:

- `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50`
- `LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23`
- `LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24`

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/current-waves-index.md`
- landed cards/closing reports from P50/P23/P24
- live source and tests named by those reports

Live code wins. Historical proof packets are evidence, not current backlog.

## Task

Update only active front doors/current indexes so they accurately say:

- whether `RespondJson` exists and what it means;
- whether Todo list JSON now returns `{items,next}` or still returns a bare array;
- whether Decimal typed row crossing exists;
- whether DB-backed Decimal money HTML exists;
- what remains deferred.

## Closed Surfaces

- No implementation changes.
- No historical proof packet rewrites unless an active front door points to a
  stale claim and needs a small current-status pointer.
- No canon claim.
- No production/stable API claim.

## Acceptance

- [x] Active docs reflect P50 if landed.
- [x] Active docs reflect P23 if landed.
- [x] Active docs reflect P24 if landed.
- [x] Stale claims like "generic JSON response missing" or "Decimal crossing absent"
      are removed only if live code proves they are now false.
- [x] Remaining deferred surfaces are named plainly.
- [x] Relevant doc guard scripts/tests pass.
- [x] `git diff --check` clean.

## Closing Report

Docs touched:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/current-waves-index.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `.agents/work/cards/lang/LAB-TODOAPP-PAYOFF-SURFACE-REFRESH-P51.md`

Stale claims removed / replaced:

- Todo list `{items,next}` is no longer described as deferred in active docs.
- Todo JSON routes are no longer described as all-legacy `rows_json`: list is
  typed + `RespondJson`; show remains legacy `rows_json`.
- `RespondJson` is named as implemented generic IgWeb JSON-body-root arm, not
  a product-only pagination arm and not a global error envelope.
- Decimal row crossing is named as implemented for host `Decimal{scale}` ->
  `.ig Decimal[N]`; scale drift fails closed.
- DB-backed Decimal money HTML is named as a P24 test fixture/proof, not a
  product route or production report surface.
- Todo API list-empty prose now matches P50: existing empty account returns
  `200 { "items": [], "next": "" }`, not bare `200 []`.

Remaining open surfaces:

- Single Todo `show` still uses legacy `rows_json`.
- Todo `done` remains Text/String in the product list until a typed Bool
  host-policy lane is chosen.
- Client `?limit=`, nested page metadata, chronological/composite cursor, and
  typed show JSON remain future product slices.
- P24 money report remains test-only; product route promotion and DSN-gated
  real `numeric` proof are separate.
- Timestamp/nested row decoders, generic `Dataset[T]`, broad decoder policy,
  schema migrations, production DB ownership, public/stable API promise, and
  global protocol error envelope remain closed/deferred.

Verification commands:

```bash
# doc/source sweeps
rg -n 'RespondJson|Decimal\\[|money report|items.*next|rows_json' \
  server/igniter-web/IMPLEMENTED_SURFACE.md \
  runtime/igniter-machine/IMPLEMENTED_SURFACE.md \
  lab-docs/lang/current-waves-index.md \
  server/igniter-web/examples/todo_postgres_app/API.md

# guards / focused proof suites
cargo test --features machine --test implemented_surface_guard_tests --quiet
scripts/check_todo_product_surface.sh
cargo test --features machine --test todo_postgres_api_read_tests --quiet
cargo test --features machine --test decimal_crossing_tests --quiet
cargo test --features machine --test db_money_report_tests --quiet
cd ../../runtime/igniter-machine && cargo test --test postgres_read_tests --quiet

# hygiene
git diff --check
rg -n '[ \t]+$' \
  server/igniter-web/IMPLEMENTED_SURFACE.md \
  runtime/igniter-machine/IMPLEMENTED_SURFACE.md \
  lab-docs/lang/current-waves-index.md \
  server/igniter-web/examples/todo_postgres_app/API.md \
  .agents/work/cards/lang/LAB-TODOAPP-PAYOFF-SURFACE-REFRESH-P51.md
```

Results:

- `implemented_surface_guard_tests`: 2 passed.
- `scripts/check_todo_product_surface.sh`: `todo-product: PASS`.
- `todo_postgres_api_read_tests`: 4 passed.
- `decimal_crossing_tests`: 4 passed.
- `db_money_report_tests`: 2 passed.
- `runtime/igniter-machine postgres_read_tests`: 19 passed.
- `git diff --check`: clean.
- Trailing whitespace sweep: no matches.

No implementation, route, host config, DB schema, smoke-script, production, or
canon behavior changed in this P51 slice.

## Reporting

Close with:

- docs touched;
- stale claims removed;
- remaining open surfaces;
- exact verification commands.
