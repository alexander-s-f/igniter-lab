# LAB-IGNITER-WEB-READTHEN-DISPATCH-P11 - staged read decision and async continuation driver

Status: READY
Lane: server / IgWeb / staged reads
Type: implementation
Delegation code: OPUS-WEB-READTHEN-DISPATCH-P11
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

`ReadThen` has been designed several times and proved by direct harnesses, but it is not yet a live runner
surface:

- P5 designed `ReadThen { plan, then }`;
- P6 hand-orchestrated query contract -> fake `PostgresReadExecutor` -> continuation contract;
- P10 readiness named `LAB-IGNITER-WEB-READTHEN-DISPATCH-P11`;
- P1 host IO substrate reconfirmed: `ReadThen` is `designed` + `harness-proven`, not `implemented` or
  `runner-integrated`.

This card should come after or alongside the async machine runner seam. If P2 has not landed, stop at a
compile/runtime feasibility packet and do not force staged reads into the sync runner.

## Goal

Implement the smallest honest staged-read surface:

```text
Serve(req) -> ReadThen { plan, then }
host executes plan through PostgresReadExecutor
host dispatches continuation `then` with rows
continuation returns final Decision
```

No new `.igweb` sugar in this card. Author `ReadThen` explicitly in `.ig` fixture/prelude first.

## Verify first

Read:

```text
lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md
lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md
lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md
lab-docs/lang/lab-igniter-machine-host-io-substrate-readiness-p1-v0.md
server/igniter-web/src/lib.rs
server/igniter-web/tests/todo_postgres_read_host_tests.rs
runtime/igniter-machine/src/postgres_read.rs
```

Confirm live absence/presence:

```text
rg -n "ReadThen|read then|staged read" lang/igniter-compiler/src server/igniter-web/src server/igniter-server/src lang/igniter-vm/src
```

## Implementation shape

Minimum expected pieces:

- Extend IgWeb prelude `Decision` with:

```ig
ReadThen { plan : Unknown, then : String }
```

- Add a host-side staged marker or async driver path. Do not map `ReadThen` to a normal final
  `ServerDecision::Respond`.
- The async runner/driver:
  1. dispatches entry;
  2. sees `ReadThen`;
  3. decodes `plan`;
  4. executes fake `PostgresReadExecutor` under host policy;
  5. serializes rows as the current v0 rows JSON string/value agreed by P6;
  6. dispatches continuation contract by name;
  7. maps the final Decision normally.

If P2 has not provided an async core dispatch seam, implement only direct async test harness extraction and
write the next P2 dependency in the closing report.

## Closed surfaces

- No `.igweb` `read ... as ...` syntax.
- No parser keyword for `read`.
- No live Postgres requirement; fake read executor is enough.
- No raw SQL.
- No typed row destructuring; rows JSON/string v0 is acceptable.
- No hidden DB authority in `.ig`.
- No background mailbox.

## Acceptance

- [ ] Live source inventory is included in closing report.
- [ ] `ReadThen` arm exists in the IgWeb prelude or the card stops with an exact blocker if P2 is missing.
- [ ] A fixture app authors `ReadThen` explicitly, without new `.igweb` sugar.
- [ ] Fake read executor is called through host policy; denied source/field fails before adapter.
- [ ] Found rows -> continuation -> final `Respond` 200.
- [ ] Empty rows -> continuation-owned 404 (not infra error).
- [ ] Raw SQL refusal remains fail-closed.
- [ ] No nested `block_on` in the new staged driver path.
- [ ] Existing P6 direct-read tests remain green.
- [ ] `git diff --check` clean.

## Closing report

TBD.
