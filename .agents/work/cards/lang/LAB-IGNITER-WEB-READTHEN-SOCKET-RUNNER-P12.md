# LAB-IGNITER-WEB-READTHEN-SOCKET-RUNNER-P12 - run ReadThen through async socket loop

Status: OPEN
Lane: IgWeb / async runner / staged reads
Type: implementation
Delegation code: OPUS-WEB-READTHEN-SOCKET-RUNNER-P12
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P11 implemented `ReadThen { plan, then }` and proved `IgWebLoadedApp::dispatch_with_read` in a direct
async harness. P2 implemented `machine_runner::serve_once_loaded`, but that socket helper currently calls
`IgWebLoadedApp::dispatch` and therefore only handles final `InvokeEffect` decisions.

This card composes already-landed pieces:

```text
tokio socket -> IgWebLoadedApp::dispatch_with_read -> StagedReadHost
  -> continuation -> final Decision -> effect_dispatch/render/respond
```

## Goal

Make a real async socket request exercise staged reads, not only direct in-process dispatch.

## Verify first

Read live code before editing:

- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/lib.rs` (`IgWebLoadedApp::dispatch_with_read`)
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
- `server/igniter-web/tests/async_machine_runner_tests.rs`
- `server/igniter-web/tests/fixtures/read_then_fixture/read_then_fixture.ig`

Confirm whether the smallest change is:

- a new `serve_once_loaded_with_read` / `serve_loop_loaded_with_read`, or
- a generic driver enum/function that accepts optional `StagedReadHost`.

Prefer the smallest readable API. Do not delete the final-effect-only helper.

## Implementation shape

Expected minimum:

- add async socket helper that uses `dispatch_with_read`;
- keep loopback-only guard in loop helper;
- preserve `MachineEffectHost` for final `InvokeEffect` decisions returned by continuations;
- add tests that open a real `tokio::net::TcpListener`, send HTTP, and assert the wire response.

## Acceptance

- [ ] Verify-first notes in closing report name the live dispatch path before/after.
- [ ] One socket test proves found rows -> continuation -> HTTP 200 over the wire.
- [ ] One socket test proves empty rows -> continuation-owned HTTP 404 over the wire.
- [ ] Denied source/field still fails before adapter (`query_count == 0`).
- [ ] A continuation returning final `InvokeEffect` still routes through `MachineEffectHost`, or the card
      stops with a precise reason why that belongs to the next slice.
- [ ] No nested `block_on`.
- [ ] Existing `readthen_dispatch_tests` remain green.
- [ ] Existing `async_machine_runner_tests` remain green.
- [ ] `server/igniter-web cargo test --features machine` passes.
- [ ] `git diff --check` clean.

## Closed surfaces

- No `igweb-serve` binary changes in this card.
- No `host.toml` parsing/wiring changes.
- No `.igweb` read syntax.
- No live Postgres requirement.
- No public bind.
- No background mailbox or unbounded spawn.
