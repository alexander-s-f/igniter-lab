# LAB-DISTRIBUTION-IGNITER-ENV-CHECK-AND-AGENT-P34 - env gate plus MCP exposure

Status: CLOSED (2026-06-25) — `igniter env check` gate + agent `env_doctor`/`env_check` (P28 envelope, names-only); env 7/7, agent 19/19
Lane: distribution / env / agent-dx
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-IGNITER-ENV-READINESS-P30`
- `LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33`
- `LAB-DISTRIBUTION-AGENT-STRUCTURED-RESULTS-IMPL-P28`

P33 gives humans:

```text
igniter env doctor <app_or_bundle>
igniter env template <app_or_bundle>
```

This card adds the gate and exposes the same safe diagnostics to `igniter-agent`.

## Goal

Implement:

```text
igniter env check <app_or_bundle>
igniter-agent tool: env_doctor
igniter-agent tool: env_check
```

`env check` is the failing gate: it exits non-zero when required env vars are unset/empty or when the env
catalogue is invalid. `env doctor` remains report-only.

The agent tools must shell-delegate to `bin/igniter` and use the P28 JSON envelope pattern. Agents must not
gain access to secret values.

## Verify First

Read:

- P30/P33 cards and proof docs.
- `bin/igniter` env implementation.
- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`

Confirm:

- P33 is landed and tests pass.
- P28 envelope helpers exist (`tool_command_result`, `tool_arg_error`, etc.).
- Existing `tools/list` does not expose env tools yet.

## Required Behavior

### CLI

Add:

```text
igniter env check <app_or_bundle>
```

Behavior:

- Uses the same catalogue resolution as P33.
- Pure apps with no env catalogue pass.
- Missing required env var => exit non-zero.
- Empty required env var => exit non-zero.
- Invalid catalogue env name (empty/template syntax) => exit non-zero.
- Never prints env values.
- Output should be human-readable and deterministic enough for tests.

### MCP agent

Add two safe tools to `igniter-agent`:

- `env_doctor { path }`
- `env_check { path }`

Rules:

- Shell-delegate to `igniter env doctor/check`.
- Use P28 additive envelope:
  - `content[0]` human output
  - `content[1]` JSON envelope
- `parsed` should include at least:
  - `path`
  - `required_env` array of `{ name, status }`
  - `ok`
- If parsing stdout is too brittle, `parsed:null` is acceptable only if documented, but prefer useful parsed
  shape.
- Missing `path` is a clean tool error: `isError:true`, `ok:false`, `exit_code:null`.
- `tools/list` must include only these env tools; do not add deploy/apply/systemd/secret tools.

## Acceptance

- [x] `igniter env check <todo_postgres_app>` exits non-zero when the required vars are unset (also on empty).
- [x] `igniter env check <todo_postgres_app>` exits zero when required vars are set to non-empty fake values.
- [x] Fake values absent from stdout/stderr (test exports `LEAKED_SECRET_XYZ`, asserts absence).
- [x] `igniter env check <todo_app>` exits zero (pure app — no catalogue — passes the gate).
- [x] `env_doctor` returns a valid P28 envelope (`parsed.required_env:[{name,status}]`) and never leaks the fake value (asserted on content[0] + content[1]).
- [x] `env_check` mirrors the CLI gate in `isError`/`ok` (unset → isError:true/ok:false; set → isError:false/ok:true).
- [x] `tools/list` includes `env_doctor` + `env_check`; still excludes deploy/install/systemd/secret/apply/daemon/restart/bind/upload.
- [x] Missing `path` for the agent env tools → clean tool error (`isError:true`, `ok:false`, `exit_code:null`, valid envelope).
- [x] Existing agent tests remain green (suite 19/19 incl. all P24/25/26/28).
- [x] `bash -n bin/igniter` + `git diff --check` clean; release build of `igniter-agent` OK.

## Reporting

1. **CLI `env check` exit semantics:** exit **0** when every required env var is set non-empty (or a pure app
   with no catalogue); exit **1** when any required var is unset/empty; exit **2** on an invalid catalogue
   (empty env-name / template syntax) or a usage error. Values are never read or printed. (`env doctor`
   stays report-only, always exit 0.)
2. **Agent tools + parsed shape:** `env_doctor` + `env_check`, each shell-delegating to `igniter env
   doctor/check <path>`. The P28 envelope's `parsed = { "path", "required_env": [{ "name", "status" }],
   "ok" }`; `env_check`'s `isError`/`ok` mirror the CLI gate exit.
3. **No-leak proof:** the CLI prints only `[status] NAME` lines (never values), so `parse_env_report` can
   carry no value; tests export a fake value and assert it is absent from BOTH `content[0]` (human) and
   `content[1]` (envelope), and from the CLI stdout/stderr.
4. **Tests:** CLI env `igniter_env_smoke_tests` **7/7** (5 P33 + 2 P34 gate); agent `igniter_agent_mcp_smoke_tests`
   **19/19** (16 prior + 3 P34 env tools); serve-wrapper **17/17**; `igniter-agent` release build OK.

Implementation: `bin/igniter` (`cmd_env` gains the `check` gate; usage/help/header), `server/igniter-web/src/
bin/igniter-agent.rs` (`env_doctor`/`env_check` tools + `parse_env_report`), tests in
`igniter_env_smoke_tests.rs` + `igniter_agent_mcp_smoke_tests.rs`. No `.env`, no value printing, no MCP-only
secret access.

## Closed Surfaces

No env value printing. No `.env` reader. No env injection. No deploy/apply. No systemd install/restart. No
public bind. No DB connection. No Docker/Compose generation. No secret-management feature.
