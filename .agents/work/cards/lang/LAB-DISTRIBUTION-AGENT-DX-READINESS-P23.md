# LAB-DISTRIBUTION-AGENT-DX-READINESS-P23 - design `igniter agent` as the command-center MCP surface

Status: CLOSED (2026-06-25) — recommends B+C (separate `igniter-agent` MCP launched by `igniter agent`, tools shell-delegate to bin/igniter); first impl = P24; packet at lab-docs/lang/lab-distribution-agent-dx-readiness-p23-v0.md
Lane: distribution / agent-dx
Type: readiness / architecture
Date: 2026-06-25

## Context

The human command center is now real:

```text
igniter serve
igniter check
igniter doctor
igniter toolchain install/update/list
igniter package ...
igniter app bundle ...
```

The next DX layer is an agent-facing control plane:

```text
igniter agent
```

That should expose a local MCP surface for Codex/Claude/IDE agents to inspect, check, serve, bundle, and
eventually prepare deploys through the same command-center authority boundaries.

There is already an `igniter-mcp` binary in `runtime/igniter-machine`, but live code shows it is a
machine/capsule/fact MCP server (`igniter_compile`, `igniter_dispatch`, facts, time-travel, checkpoint,
capsules). This card must decide whether `igniter agent` should wrap/extend that binary, delegate to it, or
introduce a separate command-center MCP surface.

## Goal

Produce a readiness packet for `igniter agent`:

- what it is;
- what it is not;
- how it relates to existing `igniter-mcp`;
- which safe first tools to expose;
- which authority surfaces remain closed.

## Verify First

Read live code/docs before deciding:

- `bin/igniter`
- `runtime/igniter-machine/src/bin/mcp.rs`
- `runtime/igniter-machine/Cargo.toml`
- `lab-docs/lang/lab-distribution-implemented-surface-v0.md`
- `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`
- any existing MCP cards/proof docs:

```text
rg -n "igniter-mcp|MCP|agent" .agents/work/cards/lang lab-docs/lang runtime/igniter-machine
```

Do not rely on stale "MCP missing" claims.

## Questions To Answer

1. Is `igniter agent` a new binary, a `bin/igniter` subcommand, or an alias/wrapper to existing
   `igniter-mcp`?
2. Should the MCP surface call the `bin/igniter` shell commands, call the underlying Rust owners directly,
   or mix both?
3. What are the first safe tools? Candidate set:
   - `doctor`
   - `toolchain_list`
   - `check_app`
   - `serve_app_bounded` (loopback + max-requests only)
   - `package_verify`
   - `app_bundle` (assembly only)
4. Which tools must be explicitly deferred?
   - deploy/apply
   - public bind
   - systemd install/enable
   - secrets/DSN creation
   - DB migrations
   - long-running daemon supervision
5. What is the response shape for agent tools: text-only MCP content, structured JSON in text, or both?
6. How should process lifecycle work for `serve_app_bounded`?
   - max-requests only?
   - background process handle?
   - logs/tail?
   - restart?
   For v0, prefer no long-lived process registry unless the evidence demands it.
7. How should the command surface stay hermetic in tests?
8. What is the first implementation card and its acceptance matrix?

## Required Recommendations

Compare at least three shapes:

- **A. Extend existing `igniter-mcp`** with command-center tools.
- **B. Add a separate `igniter-agent` MCP binary** owned by distribution/control-center.
- **C. Add `igniter agent` as a shell/front-door wrapper** that launches whichever MCP server owns the
  surface.
- **D. Do nothing: use CLI commands directly from agents.**

Recommendation must name one v0 path and one implementation card.

Bias to testable minimalism:

```text
v0 should expose check/doctor/toolchain/package verify/bounded serve before anything deploy-like.
```

## Acceptance

- [x] Packet written (`lab-docs/lang/lab-distribution-agent-dx-readiness-p23-v0.md`) with a clear recommendation.
- [x] `igniter-mcp` characterized from live `mcp.rs` (16 language/machine tools over stdio JSON-RPC; NOT a control-center surface).
- [x] ≥3 alternatives compared (A extend-mcp / B separate binary / C front-door subcommand / D do-nothing).
- [x] First impl card named with concrete tools + tests (`P24`: `doctor` + `toolchain_list`, stdio-driven hermetic tests).
- [x] Authority boundary explicit: tools shell-delegate to `bin/igniter`; grants no new authority.
- [x] Closed surfaces list deploy/public-bind/secrets/systemd/remote-registry/daemon.
- [x] `git diff --check` clean (packet + card only, no code).

## Reporting

1. **Recommended shape:** B+C — add a separate `igniter-agent` command-center MCP binary and launch it via
   the human front door `bin/igniter agent`.
2. **Existing `igniter-mcp`:** leave it untouched as the machine/capsule/fact MCP surface; do not mix command
   center tools into it.
3. **First v0 tool set:** start with safe shell-delegated checks (`doctor`, `toolchain_list`, `check_app`,
   `package_verify`), then add bounded loopback serve as a separate implementation slice.
4. **First implementation card:** `LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24`; bounded serve follows as
   `LAB-DISTRIBUTION-AGENT-BOUNDED-SERVE-P25`.
5. **Top risk:** accidentally granting deployment/host authority through MCP. v0 avoids it by shell-delegating
   to existing `bin/igniter` verbs and explicitly excluding deploy/public-bind/secrets/systemd/daemon surfaces.

## Closed Surfaces

No implementation in this card. No deploy/apply. No public bind. No secrets or DSNs. No systemd. No remote
registry/download/signing. No long-running process supervisor unless explicitly justified for a later card.
