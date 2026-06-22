# LAB-IGNITER-WEB-IGWEB-SERVE-READTHEN-P23 - wire ReadThen into igweb-serve machine mode

Status: OPEN
Lane: IgWeb / runner productization / staged reads
Type: implementation
Delegation code: OPUS-WEB-IGWEB-SERVE-READTHEN-P23
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- P11: `ReadThen { plan, then }` exists in the IgWeb prelude and `IgWebLoadedApp::dispatch_with_read`
  works in direct async tests.
- P12: staged reads work through real async socket helpers (`serve_loop_loaded_with_read`).
- P22: `igweb-serve --host-config` enters machine mode, but still calls `serve_loop_loaded` and does not
  attach a `StagedReadHost`.
- P10 Todo smoke: read/write works through productized runner helpers, not the actual binary.

The gap is now precise: the binary machine-mode path can serve async requests, but it cannot run `ReadThen`.

## Goal

Wire staged read support into the `igweb-serve --host-config` machine-mode path without hiding DB authority
inside `.ig` or `.igweb`.

Expected direction:

```text
igweb-serve --host-config host.toml <app_dir>
  -> load app as IgWebLoadedApp
  -> build/attach StagedReadHost from host-owned config or a narrow host bundle
  -> serve_loop_loaded_with_read
```

If live code shows that host config cannot yet build a real `StagedReadHost`, land the smallest runner
refactor that makes the binary path accept a host bundle and write the exact P24 dependency in the closing
report. Do not pretend ReadThen is fully operator-configured if it is only test-injected.

## Verify first

Read:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/tests/readthen_socket_runner_tests.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`

Confirm live state:

- whether `run_machine_mode` is testable without spawning a process;
- whether `serve_loop_loaded_with_read` can be called from binary code with a borrowed `StagedReadHost`;
- whether a default/empty fake read host is acceptable or should fail closed until host policy exists.

## Implementation shape

Prefer small, composable pieces:

- extract a machine-mode runner core if needed (`run_machine_mode_with_hosts` or equivalent);
- keep no-`--host-config` sync path unchanged;
- with read host available, call `serve_loop_loaded_with_read`;
- without read host, `ReadThen` must fail with a clear host error, not an unknown decision tag panic;
- preserve final `InvokeEffect` routing through `MachineEffectHost`.

## Acceptance

- [ ] Closing report names the live before/after dispatch path.
- [ ] `igweb-serve --host-config` machine mode no longer treats `ReadThen` as an unknown final decision.
- [ ] A machine-mode socket test proves ReadThen found rows -> HTTP 200 or explains the exact missing host-binding blocker.
- [ ] Empty rows -> continuation-owned HTTP 404 if a read host is attached.
- [ ] Denied source/field remains host-owned and happens before adapter.
- [ ] No nested `block_on` in the async path.
- [ ] Omitted `--host-config` sync path remains green.
- [ ] Existing `readthen_socket_runner_tests`, `igweb_serve_machine_mode_tests`, and Todo async smoke tests remain green.
- [ ] `server/igniter-web cargo test --features machine` passes.
- [ ] `git diff --check` clean.

## Closed surfaces

- No `.igweb` `read` syntax.
- No live Postgres requirement.
- No public bind.
- No schema migration runner.
- No secrets in app files or `igweb.toml`.
- No server route/domain table.
- No background mailbox or process supervisor.
