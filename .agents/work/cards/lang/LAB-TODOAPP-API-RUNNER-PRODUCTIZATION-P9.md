# LAB-TODOAPP-API-RUNNER-PRODUCTIZATION-P9 - Todo API runner contour after local Postgres

Status: CLOSED
Lane: TodoApp API / IgWeb runner / local Postgres
Type: readiness + narrow proof plan
Delegation code: OPUS-TODOAPP-API-RUNNER-PRODUCTIZATION-P9
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- `LAB-TODOAPP-API-LOCAL-POSTGRES-P8` - local Postgres e2e over real adapters.
- `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9` - typed write intent through `MachineEffectHost` contour.
- earlier read/write fake and local harness proofs.

The remaining product pressure is not "can the pieces work"; it is "what is the smallest runner-shaped flow that a developer/operator would actually use?"

## Goal

Design the next implementation slice for Todo API runner productization, without merging read, write, Postgres setup, effect host, and live HTTP into one oversized card.

The output should decide one next implementation card:

- local loopback runner with write effects only;
- staged read runner only;
- local Postgres config/manifest shape;
- or a bounded all-in-one smoke if live code makes it small.

## Verify first

Read:

- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/tests/todo_postgres_*`
- `runtime/igniter-machine/src/postgres_*`
- `server/igniter-server/src/effect_host.rs`
- P8/P9 proof docs.

Confirm live status of:

- how runner manifest currently rejects or accepts effects/read config;
- whether local Postgres env/config is test-only or runner-addressable;
- whether `ReadThen` exists or is still only readiness;
- whether `MachineEffectHost` can be wired without async/blocking hazards.

## Required answers

- Which seam should productize first: write, read, or config?
- What is operator-owned config and what remains app-owned?
- What must stay test-only?
- What is the smallest command a developer would run?
- Which parts are blocked by async/socket-loop shape?
- What exact implementation card follows?

## Acceptance

- [x] Live surfaces are verified and corrected where older docs drifted.
- [x] One next implementation card is named with scope and acceptance.
- [x] The plan avoids hiding DSN/schema/effect authority in `.igweb`.
- [x] The plan does not make `igniter-server` domain-aware.
- [x] The plan separates read continuation from write effect execution.
- [x] No production code changes unless they are tiny documentation-only clarifications.
- [x] `git diff --check` clean.

## Closed scope

No implementation unless live code reveals a trivial doc-only fix. No schema migration runner. No public network. No production DB.

## Next

Likely follow-up: `LAB-TODOAPP-API-RUNNER-WRITE-P10` or `LAB-IGNITER-WEB-READTHEN-RUNNER-P10`, depending on this readiness result.

## Closing report

Readiness/design packet completed: `lab-docs/lang/lab-todoapp-api-runner-productization-p9-v0.md`.

Live surfaces verified: `igweb.toml` still rejects `[effects]`, runner has no DB config, local Postgres setup is
test-harness-owned, and read continuation remains separate from write effect execution. Recommendation:
productize operator-owned runner config and async loop wiring as a separate follow-up. Naming caveat: active
`LAB-IGNITER-WEB-READTHEN-RUNNER-P10` already occupies P10 in the web runner lane, so open the config follow-up
with a non-colliding id if needed.
