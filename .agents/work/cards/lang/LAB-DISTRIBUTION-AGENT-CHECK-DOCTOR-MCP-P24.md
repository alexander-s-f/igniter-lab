# LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24 - first safe `igniter agent` MCP tools

Status: CLOSED (2026-06-25) — `igniter agent` stdio MCP live (doctor/toolchain_list/check_app/package_verify, shell-delegated); 4 hermetic tests green
Lane: distribution / agent-dx
Type: implementation + proof
Date: 2026-06-25

## Dependency

Run after `LAB-DISTRIBUTION-AGENT-DX-READINESS-P23` closes. If P23 has not closed, stop and report blocked.

This implementation card should follow P23's recommended shape. The acceptance below assumes the likely v0:
a local stdio MCP surface reachable via `igniter agent`, exposing only safe command-center tools.

## Goal

Implement the smallest agent-facing command-center MCP surface:

```text
igniter agent
```

with safe, local, bounded tools only.

The v0 tool set should be deliberately boring:

- `doctor`
- `toolchain_list`
- `check_app`
- optionally `package_verify` if it is a direct argv delegation to `igc verify`

No deploy, no public bind, no process supervisor, no secrets.

## Verify First

Before editing:

- read P23 closing report and follow its chosen shape;
- read `bin/igniter`;
- read existing MCP framing in `runtime/igniter-machine/src/bin/mcp.rs`;
- run `bin/igniter doctor`, `bin/igniter toolchain list`, and `bin/igniter check <known-app>` manually;
- identify a known tiny app fixture, probably:

```text
server/igniter-web/examples/todo_app
```

## Required Behavior

Expose MCP tools that call the existing command center, not duplicate authority:

### `doctor`

Input:

```json
{ "app_dir": "optional/path", "json": true }
```

Behavior:

- invokes equivalent of `igniter doctor [app_dir] --json`;
- returns the stdout and exit code;
- must not mutate or build.

### `toolchain_list`

Input: `{}`.

Behavior:

- returns `igniter toolchain list` output;
- must mention the default 5-binary fleet and optional `igniter-repl`.

### `check_app`

Input:

```json
{ "app_dir": "path" }
```

Behavior:

- invokes equivalent of `igniter check <app_dir>`;
- opens no socket;
- returns stdout/stderr/exit code.

### Optional: `package_verify`

Input:

```json
{ "workspace": "path", "strict": true }
```

Behavior:

- delegates to `igniter package verify`;
- do not invent a new package verifier.

## MCP Protocol

Use MCP JSON-RPC over stdio like existing `igniter-mcp` unless P23 recommends otherwise:

- `initialize`
- `tools/list`
- `tools/call`

For v0, text content is acceptable, but include enough structured text to be machine-readable:

```text
exit_code: 0
stdout:
...
stderr:
...
```

If returning JSON text, keep it valid JSON and bounded.

## Acceptance

- [x] `igniter agent` starts a local stdio MCP server and answers `initialize` (serverInfo `igniter-agent`).
- [x] `tools/list` includes only the v0 safe tools (doctor/toolchain_list/check_app/package_verify); test
      asserts NO deploy/serve/bind/install/systemd/secret/apply tool exists.
- [x] `doctor` tool returns a successful local report (`exit_code: 0`).
- [x] `toolchain_list` returns the default fleet (`5 default binaries`) + optional repl.
- [x] `check_app` on `examples/todo_app` succeeds (`isError:false`) and includes `check ok` + `no socket opened`.
- [x] Bad `check_app` path → `isError:true` (no panic); missing `app_dir` → clean error; unknown tool → clean error.
- [x] Hermetic: tools shell to `bin/igniter` (doctor/list/check are read-only/dry); agent pinned via
      `IGNITER_AGENT_BIN`, check pinned via `IGNITER_IGWEB_SERVE_BIN`; no network/DB/socket/nested-build.
- [x] `igniter-mcp` UNTOUCHED — `igniter-agent` is a SEPARATE binary/surface (language/machine MCP vs
      control-center MCP); `runtime/igniter-machine/src/bin/mcp.rs` has no diff.
- [x] `bash -n bin/igniter` succeeds.
- [x] Tests pass: agent 4/4; regression wrapper 17, package 9 green.
- [x] `git diff --check` clean.

## Reporting

1. **Chosen shape (P23 B+C):** a separate minimal **`igniter-agent`** stdio JSON-RPC binary
   (`server/igniter-web/src/bin/igniter-agent.rs`, auto-discovered bin, deps = std + serde_json), launched by
   the **`igniter agent`** front-door subcommand (`bin/igniter`: `resolve_agent` → `exec env
   IGNITER_BIN=<self> igniter-agent`). Its tools **shell-delegate** to `bin/igniter`.
2. **Tools exposed:** `doctor` (`igniter doctor [app_dir] [--json]`), `toolchain_list` (`igniter toolchain
   list`), `check_app` (`igniter check <app_dir>`), `package_verify` (`igniter package verify
   [--project-root] [--strict]` → `igc verify`). Each returns `exit_code:/stdout:/stderr:` text + MCP
   `isError`.
3. **MCP smoke sequence:** `initialize` → `tools/list` → `tools/call` for `toolchain_list`, `doctor`,
   `check_app`(todo_app), `check_app`(bad path), `check_app`(missing arg), unknown tool — over child stdio.
4. **No new authority:** `tools/list` carries only the 4 safe verbs (test forbids deploy/serve/bind/install/
   systemd/secret/apply); every tool runs the same `bin/igniter` verb a human runs, so loopback/bounded/
   secret-free/fail-closed all stay in `bin/igniter`+owners; `check_app` opens no socket; the agent's only
   capability is `IGNITER_BIN`. No deploy/public-bind/secrets/systemd path exists.
5. **Next card:** `LAB-DISTRIBUTION-AGENT-BOUNDED-SERVE-P25` — add the `serve_app_bounded` MCP tool
   (loopback + max-requests, bounded, no daemon/registry). `igniter-agent` stays an opt-in surface (not in
   the default 5-binary installer fleet).

## Closed Surfaces

No deploy/apply. No public bind. No systemd. No secrets/DSNs. No DB migrations. No long-running process
registry. No remote registry/download/signing. No replacement of existing `igniter-mcp` unless P23 explicitly
authorized it.
