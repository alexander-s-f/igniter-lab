# LAB-DISTRIBUTION-AGENT-STRUCTURED-MCP-RESPONSES-READINESS-P27 - design structured agent tool results

Status: CLOSED (2026-06-25) — recommends shape C (human text + second JSON-envelope content item); first impl = P28; packet at lab-docs/lang/lab-distribution-agent-structured-mcp-responses-readiness-p27-v0.md
Lane: distribution / agent-dx
Type: readiness / architecture
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

`igniter-agent` currently returns MCP text content shaped like:

```text
exit_code: 0
stdout:
...
stderr:
...
```

That was enough for P24/P25, but agent UX will quickly benefit from structured output:

- `doctor --json` already exists and is tested.
- `package verify` / `igc verify` have structured JSON paths.
- `app_bundle` will produce a manifest path and parseable `manifest.json`.
- `serve_app_bounded` has structured fields (`listen`, `http_status`, `requests_issued`) currently embedded
  in text.

Before changing all tools, design the smallest MCP response convention that keeps backwards-compatible text
content while adding structured JSON for agents.

This is readiness only. It may run in parallel with P26 because it should not edit production code.

## Goal

Write a readiness packet:

```text
lab-docs/lang/lab-distribution-agent-structured-mcp-responses-readiness-p27-v0.md
```

that decides the v0 structured result shape for `igniter-agent`.

## Verify First

Read live surfaces:

- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `bin/igniter`:
  - `doctor --json`
  - `toolchain list`
  - `check`
  - `package verify`
  - `app bundle`
- `server/igniter-web/tests/igniter_doctor_tests.rs`
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`
- package verify / lock tests that assert JSON or structured diagnostics.

Do not trust old "text-only" claims without checking the current CLI outputs.

## Questions To Answer

1. Should MCP tool results include:
   - text content only;
   - JSON text content only;
   - text content plus an embedded structured JSON content item;
   - text content plus `structuredContent` if compatible with the MCP schema used here?
2. What is the stable envelope?
   Candidate:
   ```json
   {
     "tool": "doctor",
     "ok": true,
     "exit_code": 0,
     "stdout": "...",
     "stderr": "...",
     "parsed": { "...": "tool-specific JSON when available" }
   }
   ```
3. Should `doctor` always call `igniter doctor --json`, or only when the MCP argument `json:true` is passed?
4. How should structured parsing fail?
   - parse failure as `ok:false`;
   - parse failure as `parsed:null` but keep CLI `exit_code`;
   - protocol error?
5. Which tools have reliable parsed fields today?
   - `doctor`
   - `serve_app_bounded`
   - `package_verify`
   - `app_bundle`
   - `check_app`
   - `toolchain_list`
6. How do we bound stdout/stderr and avoid leaking secrets?
7. How do tests assert structured fields without making human text brittle?
8. What is the first implementation card?

## Required Recommendations

Compare at least three shapes:

- **A. Keep text-only** and let agents parse.
- **B. Return JSON as the single text content item**.
- **C. Return human text plus a second JSON text item**.
- **D. Return MCP `structuredContent` plus text content**, if our current minimal JSON-RPC shape can support it
  without breaking clients/tests.

Name one v0 path and one implementation card.

Bias:

```text
Preserve human-readable text, add structured fields for agents, avoid protocol cleverness unless live MCP
shape clearly supports it.
```

## Acceptance

- [x] Packet written at `lab-docs/lang/lab-distribution-agent-structured-mcp-responses-readiness-p27-v0.md`.
- [x] Live `igniter-agent` shape characterized (single text `tool_body`, `isError`, `snippet` bound; 6 tools after P26).
- [x] `doctor --json` characterized from live CLI (real JSON array of `{scope,check,severity,detail,suggest}`).
- [x] 6 tools classified by reliable-parsed-JSON-today (doctor/serve/app_bundle = yes; check = partial; package_verify/toolchain_list = no).
- [x] ≥3 shapes compared (A text-only / B JSON-only / C text+JSON-item / D structuredContent).
- [x] One v0 shape recommended: **C** (human `content[0]` + JSON-envelope `content[1]`; no protocol bump).
- [x] First impl card named with tests (`P28`: per-tool `parsed` + envelope, content[1] assertions, parse-failure→`parsed:null`).
- [x] Authority boundary explicit: observability only — every value comes from a `bin/igniter` verb that already enforces its authority.
- [x] No production code changes; `git diff --check` clean.

## Reporting

1. **Shape:** **C** — keep `content[0]` human text, append `content[1]` JSON envelope
   `{tool, ok, exit_code, stdout, stderr, parsed}` (bounded). No `structuredContent`/protocol bump in v0
   (server advertises `2024-11-05`, which predates it).
2. **Parsed fields v0:** `doctor` (from `--json`), `serve_app_bounded` (synthesized), `app_bundle`
   (manifest.json), `check_app` (parsed `entry`/`sources`); `package_verify`/`toolchain_list` → `parsed:null`
   (live `igc verify` and `toolchain list` are text-only — verified).
3. **`doctor --json`:** fills `parsed`; human report stays in `content[0]` (cheap second non-mutating call),
   or `json:true` switches `content[0]` to JSON.
4. **Back-compat:** envelope is additive (`content[1]`); `content[0]` unchanged → all P24/P25/P26 text
   assertions still pass; no client/protocol change; per-tool incremental migration (`parsed:null` first).
5. **First impl card:** `LAB-DISTRIBUTION-AGENT-STRUCTURED-RESULTS-IMPL-P28`.

## Closed Surfaces

No implementation in this card. No deploy/apply. No public bind. No secrets/DSNs. No new MCP transport. No
replacement of `igniter-mcp`. No schema commitment beyond v0 command-center agent results.
