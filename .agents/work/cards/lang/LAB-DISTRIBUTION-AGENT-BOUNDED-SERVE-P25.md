# LAB-DISTRIBUTION-AGENT-BOUNDED-SERVE-P25 - MCP `serve_app_bounded` proof

Status: CLOSED (2026-06-25) — `serve_app_bounded` MCP tool live (loopback, clamped ≤5, bounded, no daemon); 7 agent tests green
Lane: distribution / agent-dx
Type: implementation + proof
Date: 2026-06-25

## Dependency

Run after `LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24` closes. If P24 has not closed, stop and report
blocked.

## Context

P24 gives agents a safe command-center MCP surface for diagnostics and checks. The next DX jump is letting an
agent start a local app run the same way a human uses:

```text
igniter serve <app_dir> --addr 127.0.0.1:0 --max-requests N
```

But v0 must not become a daemon/process supervisor. It should be bounded, loopback-only, and testable.

## Goal

Add one MCP tool:

```text
serve_app_bounded
```

It should start an IgWeb app through the existing `igniter serve` command center path, parse the listening
address, optionally perform a health request, wait for the bounded run to exit, and return a compact result.

## Required Behavior

Input:

```json
{
  "app_dir": "path",
  "max_requests": 1,
  "path": "/health"
}
```

Rules:

- force loopback: default `--addr 127.0.0.1:0`;
- force bounded run: require `max_requests` and clamp/refuse large values (v0 max <= 5);
- no public bind parameter in v0;
- no background process handle in v0;
- no daemonization/restart in v0;
- no DB/host-config unless already supported by explicit command-center flags and P23/P24 authorize them.

Output should include:

- listen address;
- request path;
- HTTP status;
- child exit status;
- stdout/stderr snippets, bounded.

## Verify First

Read:

- P24 implementation and tests;
- `bin/igniter` serve path;
- `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs` for the existing loopback/bounded proof;
- `igweb-serve` output shape for the listening line.

Do not invent a second server runner. Use the existing command-center path.

## Acceptance

- [x] `tools/list` includes `serve_app_bounded` (and the list test now allows it as the sole bounded serve tool).
- [x] Tool starts `examples/todo_app` on `127.0.0.1:0`, performs `GET /health` → `HTTP/1.1 200` (`all_200:true`),
      waits for clean bounded exit (`exit_code: 0`).
- [x] No public-bind path: `--addr 127.0.0.1:0` is hardcoded; there is NO addr/host input field; igweb-serve
      also refuses non-loopback. Test asserts `listen: 127.0.0.1:`.
- [x] `max_requests` clamped to `[1,5]` (test: `99` → `clamped 99→5`, `requests_issued: 5`).
- [x] Bad app path → controlled tool error (`isError:true`, `never bound`); missing `app_dir` → clean error.
- [x] No long-running child: the tool issues exactly `max` GETs so the bounded server exits, then `child.wait()`
      reaps it — `exit_code: 0` in the result proves the child was reaped (manual smoke confirmed no leftover
      `igweb-serve` process).
- [x] Existing P24 tools still pass (agent suite 7/7: 4 P24 + 3 P25).
- [x] Existing wrapper serve smoke still passes (17/17).
- [x] `git diff --check` clean.

## Reporting

1. **Exact `igniter serve` argv:** `igniter serve <app_dir> --addr 127.0.0.1:0 --max-requests <max>` where
   `<max>` is the input `max_requests` clamped to `[1,5]` (default 1). Run as a CHILD (`stdout`/`stderr`
   piped); no other flags — no addr/host/public param exists.
2. **Listening address parsing:** read the child's stdout line-by-line; on the line containing
   `listening http://`, take the whitespace-delimited token after it (e.g. `127.0.0.1:PORT`). If stdout hits
   EOF first (app never bound), it's a controlled error (`never bound`, `isError:true`).
3. **Bounded lifecycle:** clamp `max` to `[1,5]`; issue EXACTLY `max` sequential `GET <path>` requests so a
   server bounded to `max` serves them all and exits on its own; then drain stdout, read stderr, and
   `child.wait()` to reap. No kill, no background handle, no daemon. (Deadlock-safe: stderr is read AFTER the
   requests, never before — reading it first would block on a child that hasn't been driven yet.)
4. **Public-bind / daemon / restart / deploy stay CLOSED:** loopback is hardcoded and there is no input to
   change it; the child is reaped synchronously (no process registry/handle); there is no restart/deploy/
   systemd tool, and the `tools/list` test forbids `deploy|install|systemd|secret|apply|daemon|restart`.

Implementation: `server/igniter-web/src/bin/igniter-agent.rs` (`serve_app_bounded` tool + helpers
`http_get_status`/`serve_app_bounded`/`snippet`); `bin/igniter` agent help updated; tests in
`server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`. `igniter-agent` stays an opt-in surface (not in
the default 5-binary installer fleet). This completes the agent-dx wave (P23→P24→P25).

## Closed Surfaces

No restart tool. No background process registry. No public bind. No deploy. No systemd. No secrets/DSNs. No
unbounded server. No remote host operation.
