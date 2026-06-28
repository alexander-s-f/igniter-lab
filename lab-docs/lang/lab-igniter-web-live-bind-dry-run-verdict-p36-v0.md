# LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36 v0

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36.md`
Depends-On: `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35`,
`LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34`
Implements: audit-control-board row **A10** (next tail; public bind stays HOLD)

## Authority boundary

Adds a **report-only** operator command. It opens **no** listener, wires
**nothing** into the real bind path, implements **no** TLS, and weakens **no**
loopback default. A `would_authorize` verdict grants **no** bind authority — the
public-bind HOLD from P35 is preserved. No canon/VM/compiler/machine/home-lab
edits.

## What shipped

`igweb-serve live-bind-check --host-config PATH [--addr HOST:PORT]` — converts the
parsed `[host.live_bind]` checklist (P34) into the server-owned
`LiveBindChecklist` and asks the **pure** `authorize_bind` gate
(`igniter-server/src/serving_gate.rs`) what it WOULD decide for `addr`, then
prints a single-line verdict. It never binds.

New code (igniter-web only):
- `src/live_bind_check.rs` — `config_to_checklist()`, `LiveBindVerdict`,
  `evaluate()`, `render()`. Pure; no I/O; depends only on `crate::host_config`
  and `igniter_server::serving_gate`. Not feature-gated (the dry run needs no
  `machine` build).
- `src/lib.rs` runner — new `RunnerCliCommand::LiveBindCheck`,
  `RunnerLiveBindCheckOptions { host_config_path, addr }`,
  `parse_live_bind_check_args`, `DEFAULT_LIVE_BIND_CHECK_ADDR = "0.0.0.0:8080"`,
  usage text.
- `src/bin/igweb-serve.rs` — a `LiveBindCheck` match arm: parse host config
  (`load_host_config`; parse error → `fail(classify_host_config_error)`),
  evaluate, print verdict, exit 0 on would_authorize / `BIND_REFUSED` exit (5) on
  would_refuse. The real `Run`/`Check` paths are untouched.

## Answers to the card questions

1. **How is the dry run exposed?** A dedicated subcommand
   `igweb-serve live-bind-check` (not a flag on `run`, so it can never share the
   bind path). Q1's three options collapsed to this because the dry run must be a
   distinct, never-binds entrypoint.
2. **Verdict shape tests assert.** A stable single line:
   `[LIVE_BIND_DRY_RUN] addr=… class=loopback|non_loopback verdict=would_authorize|would_refuse …
   socket_opened=false public_bind=closed`. would_authorize (non-loopback) adds
   `checklist_digest=live-bind-v0:…`; would_refuse adds `code=…
   missing_field=…`. The structured `LiveBindVerdict` enum is the unit-test
   surface.
3. **Copied operator assertions vs host-verified state.** In this slice **all**
   checklist booleans are a 1:1 readiness mapping from the *operator's asserted*
   `[host.live_bind]` config — explicitly sound **only because the dry run never
   binds** (it reports what the gate would decide for the asserted config).
   Host-verified backing (each boolean set from real runtime state, durable
   inbound signed-passport key) is **P37**; no real bind path consumes this
   conversion.
4. **How does the verdict prove no listener opened?** Three layers: (a) the code
   path calls only the **pure** `authorize_bind` and `load_host_config` — there is
   no `TcpListener::bind` on it; (b) every verdict line literally states
   `socket_opened=false public_bind=closed`; (c) subprocess tests assert stdout
   never contains the runner's `listening http://…` line in any case.
5. **What remains (P37/P38/P39).** P37 durable operator-provided inbound
   signed-passport key + wired verifier (forged-passport rejected) — turns the
   `signed_passport_path_wired` assertion into host-verified state. P38
   `terminated_upstream` TLS runbook + proxy-header trust proof. P39 the actual
   human-gated non-loopback bind proof (terminated_upstream only), requiring
   P36+P37+P38. Only P39 may open a public listener, under explicit human
   approval.

## Accept / refuse taxonomy

| Input | Verdict | Exit |
|---|---|---|
| loopback `--addr` (any config) | `would_authorize` (loopback, no checklist needed) | 0 |
| non-loopback `--addr` + complete `[host.live_bind]` | `would_authorize` + opaque `checklist_digest`, `note=report_only_no_bind_authority` | 0 |
| non-loopback `--addr`, **no** `[host.live_bind]` section | `would_refuse code=non_loopback_without_checklist` | 5 (`BIND_REFUSED`) |
| non-loopback `--addr`, single missing checklist field | `would_refuse code=missing_<field>` (defensive; P34 parse currently rejects partials first) | 5 |
| malformed/incomplete `[host.live_bind]` | parse fails closed → `[CONFIG_PARSE]` on stderr, no verdict | 2 (`CONFIG_PARSE`) |
| missing `--host-config` | CLI argument error → `[CONFIG_PARSE]` | 2 |

Note: P34 parsing forces every boolean to `"true"` and every reference
non-empty, so a *successfully parsed* config always maps to a *complete*
checklist; the per-field `would_refuse` rows are reachable only through the unit
API today (kept honest for if the config shape loosens). The common
operator-facing refusal is `non_loopback_without_checklist`.

## Proof: no socket is opened

- `evaluate()` / `config_to_checklist()` are pure (no `std::net`); `authorize_bind`
  is pure by construction (`serving_gate.rs` module doc).
- Every verdict line carries `socket_opened=false public_bind=closed`.
- Subprocess tests assert `!stdout.contains("listening http")` in all six cases.
- The real `Run` path (`TcpListener::bind`) and `authorize_runner_bind(addr,
  None)` are unchanged; non-loopback `run` still fails closed with `BIND_REFUSED`.

## Tests

- `src/live_bind_check.rs` unit tests (7): complete-config→complete-checklist,
  native_tls mapping, loopback would-authorize (with/without config),
  non-loopback complete would-authorize + digest is field-value-free, missing
  section would-refuse, incomplete checklist names the missing field, render is
  secret-free + marks no socket.
- `tests/igweb_live_bind_dry_run_tests.rs` subprocess (6): loopback authorize,
  non-loopback complete authorize + digest + no secret leak, default-addr is
  non-loopback, missing-section refuse (non-zero exit), incomplete →
  `CONFIG_PARSE` exit 2, missing `--host-config` CLI error.

Regression (existing serve behavior unchanged):
- `igweb_serve_diagnostics_tests` (machine) 8/8.
- `igweb_serve_machine_mode_tests` (machine) 12/12.
- Full `--features machine` suite: all ~40 test binaries pass, 0 failed (~269 tests).
- `git diff --check`: clean.

## Public bind remains CLOSED

This card does not open a public/non-loopback listener and grants no bind
authority. The runner's real bind path still calls `authorize_bind(addr, None)`;
non-loopback `run` still fails closed. `[host] mode` still accepts only
`"loopback"`. A real flip requires the P37+P38 prerequisites and the P39
human-gated proof.
