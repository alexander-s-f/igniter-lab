# LAB-DISTRIBUTION-AGENT-APP-BUNDLE-P26 - expose `igniter app bundle` through `igniter agent`

Status: CLOSED (2026-06-25) — `app_bundle` MCP tool live (shell-delegates to `igniter app bundle`; bundler owns all safety); agent suite 10/10
Lane: distribution / agent-dx
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

The command-center MCP surface is live:

- P23 chose a separate `igniter-agent` MCP binary launched by `bin/igniter agent`.
- P24 exposed safe check tools (`doctor`, `toolchain_list`, `check_app`, `package_verify`).
- P25 exposed `serve_app_bounded` (loopback, clamped, no daemon).

The human distribution surface already has `igniter app bundle`:

- P13 defined bundle boundaries.
- P14 implemented `igniter app bundle <app_dir> --out <dir> --version <stamp>`.
- P16 proved the emitted bundle run script serves from inside the bundle.

This card should expose that existing assembly-only command through the agent MCP surface. Do **not**
reimplement the bundler in Rust. The agent tool must shell-delegate to `bin/igniter app bundle`, just like
the existing tools.

## Goal

Add an MCP tool:

```text
app_bundle
```

that delegates to:

```text
igniter app bundle <app_dir> --out <out_dir> --version <version>
```

and returns a bounded, machine-readable text result.

## Verify First

Read live surfaces before editing:

- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `bin/igniter` (`app_usage`, `app_bundle`, `cmd_app`, `resolve_igweb_serve`)
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`
- cards/docs:
  - `LAB-DISTRIBUTION-APP-BUNDLE-READINESS-P13`
  - `LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14`
  - `LAB-DISTRIBUTION-APP-BUNDLE-RUN-SMOKE-P16`
  - `LAB-DISTRIBUTION-AGENT-DX-READINESS-P23`
  - `LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24`
  - `LAB-DISTRIBUTION-AGENT-BOUNDED-SERVE-P25`

Confirm the existing bundle command owns all safety checks:

- refuses real `host.toml`;
- refuses inline secrets without printing secret values;
- uses `igweb-serve check` before assembly;
- stages atomically and leaves no partial bundle on refusal;
- emits loopback runner and example systemd only.

## Required Behavior

Add `app_bundle` to `tools/list` with schema:

```json
{
  "app_dir": "string",
  "out_dir": "string",
  "version": "string"
}
```

Implementation rules:

- shell-delegate to `igniter app bundle`;
- require all three arguments;
- pass `IGNITER_IGWEB_SERVE_BIN` through from the agent process environment automatically (tests rely on this
  through the existing `bin/igniter` resolver path);
- do not accept public bind, systemd, deploy, secret, DSN, Docker, or upload arguments;
- return `isError:true` for missing args / failed command;
- return `exit_code`, stdout, stderr, and bundle destination summary in text.

## Acceptance

- [x] `tools/list` includes `app_bundle`.
- [x] `tools/list` forbids deploy/install/systemd/secret/apply/daemon/restart/bind/upload (list test).
- [x] `app_bundle` on `examples/todo_app` succeeds into a temp out dir via MCP (`isError:false`, "app bundle ok").
- [x] Produced bundle contains all 6: `bin/igweb-serve`, `app/todo_app/igweb.toml`, `run/run-todo_app.sh`,
      `checks/check.sh`, `systemd/todo_app.service.example`, `manifest.json`.
- [x] Emitted `checks/check.sh` succeeds (run in-test).
- [x] `manifest.json` parses (serde) and carries `bind_policy:"loopback"`, `public_release:false`, runner
      `sha256`, non-empty `app_sources`.
- [x] Missing `version`/`out_dir`/`app_dir` → clean MCP tool error (`isError:true`, "missing required argument"),
      NOT a JSON-RPC protocol error.
- [x] Real `host.toml` refused through MCP (`isError:true`); no partial `hostapp-V1` dir remains.
- [x] Inline secret in `host.example.toml` refused through MCP; the secret value is ABSENT from the tool text;
      no partial bundle remains.
- [x] P25 `serve_app_bounded` tests still pass (agent suite 10/10 total).
- [x] App-bundle suite still passes (6/6).
- [x] `bash -n bin/igniter`, `cargo build --release --bin igniter-agent`, `git diff --check` all pass.

## Reporting

1. **Exact delegated argv:** `igniter app bundle <app_dir> --out <out_dir> --version <version>` (all three
   required; shell-delegated via the agent's `run_igniter`, which inherits the agent's env so
   `IGNITER_IGWEB_SERVE_BIN` passes through to the bundler automatically — no nested cargo build).
2. **Bundle path created:** `<out_dir>/<appname>-<version>/` (tests use temp dirs under `std::env::temp_dir`;
   nothing is written into the repo).
3. **Safety refusals proven through MCP:** real `host.toml` → `isError:true`, no partial dir; inline secret in
   `host.example.toml` → `isError:true`, secret string absent from the tool text, no partial dir; missing any
   of the 3 args → clean `isError:true` tool error.
4. **No new authority:** `app_bundle` only shells the EXISTING `igniter app bundle` (P14) — no bundler
   rewrite; all host.toml/secret/`igweb-serve check`/atomic-staging guarantees stay in the bundler. The
   `tools/list` test forbids deploy/install/systemd/secret/apply/daemon/restart/bind/upload; there is no
   deploy/public-bind/systemd path.
5. **Tests run:** agent MCP suite **10/10** (4 P24 + 3 P25 + 3 P26); app-bundle suite **6/6**; release build
   of `igniter-agent` OK; `bash -n` + `git diff --check` clean.

Implementation: `server/igniter-web/src/bin/igniter-agent.rs` (`app_bundle` tool + handler); `bin/igniter`
agent help updated; tests in `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`. `igniter-agent`
stays an opt-in surface (not in the default 5-binary installer fleet). This completes the agent command-center
tool set (P23→P24→P25→P26).

## Closed Surfaces

No bundler rewrite. No deploy/apply. No public bind. No systemd install/enable. No secrets/DSNs. No DB
creation/migration. No Docker. No upload/signing/remote registry. No long-running process registry.
