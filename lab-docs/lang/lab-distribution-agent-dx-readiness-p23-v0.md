# lab-distribution-agent-dx-readiness-p23-v0 — `igniter agent` as the command-center MCP surface

Card: `LAB-DISTRIBUTION-AGENT-DX-READINESS-P23`
Status: CLOSED (2026-06-25)
Authority: lab readiness — a recommendation, not an implementation. Closed surfaces honored: no code, no
deploy/apply, no public bind, no secrets, no systemd, no remote registry, no process supervisor.

## Verify-first basis (live, not guessed)

- **`runtime/igniter-machine/src/bin/mcp.rs` (963 lines)** — `igniter-mcp` is a **stdio JSON-RPC MCP server**
  (`initialize` / `notifications/initialized` / `ping` / `tools/list` / `tools/call`). Its 16 tools are the
  **language + machine** surface, operating on an in-process `IgniterMachine`:
  `igniter_compile`, `igniter_load_contract`, `igniter_dispatch`, `igniter_list_contracts`,
  `igniter_get_contract_ir`, `igniter_write_fact`, `igniter_query_facts`, `igniter_time_travel`,
  `igniter_checkpoint`, `igniter_status`, and the capsule lens (`capsule_snapshot`/`list`/`activate`/`fork`/
  `diff`/`activate_many`). **There is NOTHING about serve/check/doctor/toolchain/package/app-bundle** — it is
  not a control-center surface.
- **`bin/igniter`** — the human control center (live verbs): `serve`, `check`, `doctor`, `toolchain
  list|install|update`, `package …`, `app bundle …`. `igniter-mcp` is in the 5-binary fleet but is **not**
  wired as `igniter agent`; it is a standalone language/machine server.
- **Follow-up cards already drafted** (this is a 3-card wave): `LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24`
  (first tools: `doctor` + `toolchain_list`) and `LAB-DISTRIBUTION-AGENT-BOUNDED-SERVE-P25`
  (`serve_app_bounded`). This packet feeds them the shape.

**Conclusion from live code:** `igniter agent` is a *different authority domain* than `igniter-mcp`.
`igniter-mcp` = language/runtime (compile, dispatch, time-travel, capsules). `igniter agent` = the
**distribution / control-center** surface (diagnose, check, verify, bundle, bounded-serve). They must not be
conflated.

## Alternatives compared

| # | Shape | Verdict |
|---|---|---|
| **A** | Extend `igniter-mcp` with command-center tools | **Reject.** Mixes two distinct authority domains in one binary — `igniter-mcp` operates an in-process machine (language/runtime); control-center tools touch the filesystem/build/serve surface. Conflating them muddies the boundary and bloats a 963-line server. |
| **B** | A separate minimal `igniter-agent` stdio MCP binary, owned by distribution | **★ Recommended (the surface).** Clean separation from `igniter-mcp`; small, single-purpose; reuses the proven JSON-RPC scaffolding shape from `mcp.rs`. |
| **C** | `igniter agent` as a front-door subcommand that launches the MCP server | **★ Recommended (the entry).** `bin/igniter agent` resolves + execs the `igniter-agent` binary over stdio — exactly the existing `resolve_*` → `exec` wrapper pattern. B and C compose: C is the door, B is the room. |
| **D** | Do nothing — agents call the CLI directly | **Reject for v0 DX.** Works, but loses MCP discoverability/structured tool schemas; the whole point is an agent control plane with typed, bounded tools. (Agents *can* still call the CLI; this just adds the MCP layer.) |

## Recommendation — **B + C, tools shell-delegate to `bin/igniter`**

`igniter agent` (front-door subcommand, **C**) launches a separate minimal **`igniter-agent`** stdio MCP
binary (**B**). Its tools **shell out to `bin/igniter <verb>`** rather than calling the Rust owners directly.

**Why shell-delegation (Q2):** it is the strongest authority story — the agent surface runs *the same
command-center the human uses*, so every guarantee `bin/igniter`/`igweb-serve` already enforces (loopback-
only, request-bounded, public-bind refusal, secret-free bundles, fail-closed) is inherited for free.
`igniter agent` therefore **grants no new authority**: it is a typed MCP veneer over the existing CLI. Direct
Rust-owner calls would re-implement or bypass those guards and are rejected for v0.

`igniter-mcp` is **left entirely unchanged** — it stays the language/machine MCP. The two servers are
complementary and separately launchable.

## Questions answered

1. **What is `igniter agent`?** A front-door subcommand (`bin/igniter agent`, **C**) that launches a separate
   minimal `igniter-agent` stdio MCP binary (**B**). Not a tool inside `igniter-mcp` (A).
2. **How are tools implemented?** **Shell-delegate to `bin/igniter`** (no new authority; inherits the
   wrapper's enforced guards). Not direct Rust owners.
3. **First safe tools:** `doctor`, `toolchain_list` (P24), then `check_app`, `package_verify`,
   `app_bundle` (assembly-only); `serve_app_bounded` (loopback + max-requests) is the P25 slice. All map 1:1
   to an existing `bin/igniter` verb.
4. **Explicitly deferred (closed):** deploy/apply, public bind, systemd install/enable, secrets/DSN creation,
   DB migrations, long-running daemon/process supervision, remote registry/download/signing.
5. **Response shape:** **both** — MCP text content carrying the verb's human-readable output, plus a small
   structured JSON header (`{tool, exit_code, ok}`, and parsed fields where cheap, e.g. doctor severities).
   Mirrors `igniter-mcp`'s `tool_ok` text convention and `doctor --json`. Keep it minimal in v0: command
   output as text + an `ok`/`exit_code` envelope.
6. **`serve_app_bounded` lifecycle:** **max-requests bounded only**, loopback-only, **no** background
   process registry, **no** restart, **no** daemon. The tool runs `igniter serve --addr 127.0.0.1:0
   --max-requests N`, returns the machine-readable `listening …` line + the bounded-run result, and exits.
   No long-lived handle in v0 (P25).
7. **Hermetic tests:** the MCP binary shells to `bin/igniter`; drive the server over stdio with
   `tools/list` + `tools/call`, pinning `IGNITER_IGWEB_SERVE_BIN` (no nested cargo). Start with the
   read-only tools (`doctor`, `toolchain_list`) which need no network/DB/socket — fully hermetic.
8. **First implementation card:** **`LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24`** (see below).

## First implementation card — P24

**`LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24`** — the smallest agent MCP surface:

- **Entry:** `bin/igniter agent` resolves + execs the new `igniter-agent` binary over stdio (mirror
  `resolve_igweb_serve`; `--help` documents it as a local stdio MCP, no network).
- **Binary:** a new minimal `igniter-agent` stdio JSON-RPC server (reuse the `mcp.rs` `respond`/`tools_list`/
  `tools/call` scaffolding). It is **opt-in / not a default-fleet member** in v0 (decide home crate in P24;
  lean: a new `[[bin]]` in an existing control-center-adjacent crate, deps = std + serde_json + Command).
- **v0 tools (read-only, hermetic):** `doctor` → `bin/igniter doctor`; `toolchain_list` → `bin/igniter
  toolchain list`. Each returns text output + `{ok, exit_code}` envelope.
- **Tests:** stdio-drive `initialize` → `tools/list` (names the 2 tools) → `tools/call doctor` /
  `tools/call toolchain_list` (assert the delegated output appears, `ok:true`, exit 0); a bad tool name →
  MCP error. No network/DB/socket.
- **Closed in P24:** check_app/package_verify/app_bundle/serve (later slices); no deploy/public-bind/secrets.

Then **P25** adds `serve_app_bounded` (loopback + max-requests, bounded, no daemon).

## Authority boundary

`igniter agent` grants **no new authority**: every tool is a typed MCP call that shells to a `bin/igniter`
verb, and `bin/igniter` + its owners (`igweb-serve`/`igc`) remain the only enforcement points. The agent
surface cannot bind public, write secrets, install systemd, or deploy — because it has no verb that does, and
the verbs it has already refuse those. `igniter-mcp`'s language/machine authority is a separate domain, left
untouched.

## Closed surfaces

No implementation here. No deploy/apply. No public bind. No secrets/DSNs. No systemd. No remote
registry/download/signing. No long-running process supervisor (bounded serve only, P25). `igniter-mcp` is
not modified.

## Reporting

1. **Recommended shape:** **B + C** — a separate minimal `igniter-agent` stdio MCP binary, launched by the
   `igniter agent` front-door subcommand, with tools that **shell-delegate to `bin/igniter`** (no new
   authority).
2. **What happens to `igniter-mcp`:** **unchanged.** It stays the language/machine MCP (compile/dispatch/
   facts/time-travel/capsules). `igniter-agent` is a distinct control-center MCP; the two are complementary.
3. **First v0 tool set:** `doctor`, `toolchain_list` (read-only, hermetic) — P24. Then check/package-verify/
   app-bundle, and `serve_app_bounded` (P25).
4. **First implementation card:** `LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24`.
5. **Top risk + v0 avoidance:** scope creep into **deploy / daemon / process supervision** (an agent that can
   "serve" will want to "keep serving"). v0 avoids it structurally: bounded serve only (max-requests,
   loopback, exits), no process registry, shell-delegation so every tool inherits `bin/igniter`'s fail-closed
   guards, and an explicit deferred-tools list — diagnostics/checks ship before anything deploy-like.

## Acceptance trace

- [x] Packet written with a clear recommendation (B + C, shell-delegation).
- [x] Existing `igniter-mcp` surface characterized from live code (16 language/machine tools, stdio JSON-RPC).
- [x] ≥3 alternatives compared (A/B/C/D).
- [x] First implementation card named with concrete tools + tests (P24: `doctor` + `toolchain_list`).
- [x] Authority boundary explicit: `igniter agent` grants no authority beyond `bin/igniter` owners.
- [x] Closed surfaces list deploy/public-bind/secrets/systemd/remote-registry/daemon.
- [x] No code changes.
