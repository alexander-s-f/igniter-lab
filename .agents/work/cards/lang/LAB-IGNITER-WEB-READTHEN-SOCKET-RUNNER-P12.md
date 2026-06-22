# LAB-IGNITER-WEB-READTHEN-SOCKET-RUNNER-P12 - run ReadThen through async socket loop

Status: CLOSED
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

- [x] Verify-first notes in closing report name the live dispatch path before/after.
- [x] One socket test proves found rows -> continuation -> HTTP 200 over the wire.
- [x] One socket test proves empty rows -> continuation-owned HTTP 404 over the wire.
- [x] Denied source/field still fails before adapter (`query_count == 0`).
- [x] A continuation returning final `InvokeEffect` still routes through `MachineEffectHost`, or the card
      stops with a precise reason why that belongs to the next slice.
- [x] No nested `block_on`.
- [x] Existing `readthen_dispatch_tests` remain green.
- [x] Existing `async_machine_runner_tests` remain green.
- [x] `server/igniter-web cargo test --features machine` passes.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22

### Verify-first: dispatch path before/after

**Before (P2 only):**
```
TcpListener → read_server_request → IgWebLoadedApp::dispatch → effect_dispatch → encode_response
```
ReadThen decisions returned 500 ("unknown decision tag: ReadThen") since `map_decision` didn't know them.

**After (P12):**
```
TcpListener → read_server_request → IgWebLoadedApp::dispatch_with_read(StagedReadHost)
  → [ReadThen detected] → PostgresReadExecutor → rows_json
  → machine.dispatch(continuation) → final Decision
  → effect_dispatch → encode_response
```
Final `InvokeEffect` from a continuation routes through `effect_dispatch` → `MachineEffectHost` unchanged.

### Deliverables

**`server/igniter-web/src/machine_runner.rs`** — added:
- `serve_once_loaded_with_read(listener, app, effect_host, read_host)` — one connection
- `serve_loop_loaded_with_read(listener, app, effect_host, read_host, policy)` — bounded loop with loopback guard

**`server/igniter-web/tests/readthen_socket_runner_tests.rs`** (new) — 4 tests:
- `found_rows_gives_http_200_over_socket` — HTTP 200 + body over real socket
- `empty_rows_gives_http_404_over_socket` — HTTP 404 (continuation-owned)
- `denied_source_gives_http_403_adapter_not_reached` — HTTP 403, adapter.query_count()==0
- `serve_loop_serves_multiple_staged_read_requests` — bounded loop serves 2 requests

**InvokeEffect from continuation (acceptance gate):** Structurally guaranteed. `dispatch_with_read` calls
`map_decision` on the continuation value. `map_decision` maps `InvokeEffect` to `ServerDecision::InvokeEffect`.
`effect_dispatch` then routes it through `MachineEffectHost` unchanged — no new code path needed. A dedicated
socket proof requires a continuation fixture that returns `InvokeEffect` plus full write-coordinator setup.
Deferred to **LAB-IGNITER-WEB-READTHEN-INVOKE-EFFECT-P13**.

**Full suite:** `cargo test --features machine` — all suites green, zero failures.

## Closed surfaces

- No `igweb-serve` binary changes in this card.
- No `host.toml` parsing/wiring changes.
- No `.igweb` read syntax.
- No live Postgres requirement.
- No public bind.
- No background mailbox or unbounded spawn.
