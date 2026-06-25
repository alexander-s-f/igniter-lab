# LAB-DISTRIBUTION-AGENT-STRUCTURED-RESULTS-IMPL-P28 - add JSON envelopes to `igniter-agent` tool results

Status: CLOSED (2026-06-25) — additive JSON envelope (content[1]) on every igniter-agent tool result; agent suite 16/16, content[0] back-compat preserved
Lane: distribution / agent-dx
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

P23-P26 made `igniter agent` a useful command-center MCP surface:

- `doctor`
- `toolchain_list`
- `check_app`
- `package_verify`
- `serve_app_bounded`
- `app_bundle`

P27 selected the structured-result shape:

```text
content[0] = existing human text
content[1] = JSON envelope text
```

No `structuredContent` / protocol-version bump in v0. The result is additive and keeps all existing text
assertions working.

## Goal

Implement the P27 recommendation in `igniter-agent`: every tool call returns a second MCP text content item
containing bounded JSON:

```json
{
  "tool": "doctor",
  "ok": true,
  "exit_code": 0,
  "stdout": "...",
  "stderr": "...",
  "parsed": null
}
```

where `parsed` is filled when reliable structured data exists today.

## Verify First

Read live sources before editing:

- `lab-docs/lang/lab-distribution-agent-structured-mcp-responses-readiness-p27-v0.md`
- `.agents/work/cards/lang/LAB-DISTRIBUTION-AGENT-STRUCTURED-MCP-RESPONSES-READINESS-P27.md`
- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `bin/igniter`
- `server/igniter-web/tests/igniter_doctor_tests.rs`
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`

Confirm current MCP result shape is:

```json
{ "content": [{ "type": "text", "text": "..." }], "isError": false }
```

and preserve `content[0]` exactly enough for existing tests.

## Required Behavior

Add a shared helper, for example:

```rust
tool_result_enveloped(out, id, tool, human_text, is_error, exit_code, stdout, stderr, parsed)
```

It must return:

```json
{
  "content": [
    { "type": "text", "text": "<human text, backwards-compatible>" },
    { "type": "text", "text": "<valid JSON envelope>" }
  ],
  "isError": <bool>
}
```

Envelope fields:

- `tool: String`
- `ok: bool` (`!isError`)
- `exit_code: Integer | null` (null for argument-validation tool errors that did not launch a command)
- `stdout: String` (bounded)
- `stderr: String` (bounded)
- `parsed: Value | null`

Use P27 parsed-field policy:

| Tool | `parsed` v0 |
|---|---|
| `doctor` | JSON array from `igniter doctor --json` |
| `serve_app_bounded` | synthesized object: `listen`, `path`, `requests_issued`, `http_status`, `all_200`, `exit_code` |
| `app_bundle` | emitted `manifest.json` plus bundle path when available |
| `check_app` | parsed object from `check ok` line: at least `ok`, `entry`, `sources`, `no_socket_opened` |
| `package_verify` | `null` |
| `toolchain_list` | `null` |

Parse failure policy:

- parsing failure is **not** a JSON-RPC protocol error;
- parsing failure does **not** force `ok:false`;
- preserve command `exit_code`, stdout, stderr;
- set `parsed:null`.

Doctor policy:

- For `doctor`, fill `parsed` from `igniter doctor --json`.
- Preserve human text in `content[0]`. This can be done with a second cheap `igniter doctor` call without
  `--json`, or with `json:true` using JSON as the human text if preserving the requested behavior requires it.
- Do not print secret/env values; inherit existing doctor redaction.

## Acceptance

- [x] Every tool result has `content[0]` human text and `content[1]` valid JSON envelope text.
- [x] Existing P24/P25/P26 text assertions pass unchanged (the 10 prior agent tests stayed green; helper-only).
- [x] `doctor` envelope: `tool:"doctor"`, `ok:true`, `exit_code:0`, `parsed` is an array with ≥1
      `{scope,check,severity}` item (from a second `igniter doctor --json` call; human report kept in content[0]).
- [x] `serve_app_bounded` envelope `parsed`: `listen` starts `127.0.0.1:`, `requests_issued`, `http_status`
      contains `HTTP/1.1 200` on the happy path.
- [x] `app_bundle` envelope `parsed`: `bundle_path` (…todo_app-V1) + `manifest` with `bind_policy:"loopback"`,
      `public_release:false`.
- [x] `check_app` envelope `parsed`: `entry:"Serve"`, numeric `sources`, `no_socket_opened:true`.
- [x] `package_verify` and `toolchain_list` envelopes valid with `parsed:null` (and `ok` mirrors the real
      exit — package_verify legitimately fails with no lockfile, still a valid envelope).
- [x] Missing-arg errors (`check_app`/`serve_app_bounded`/`app_bundle`) → `isError:true`, `ok:false`,
      `exit_code:null`, valid envelope JSON.
- [x] Bad path / refused host.toml / inline secret stay tool errors (not JSON-RPC errors); the secret value is
      absent from BOTH `content[0]` and `content[1]` (asserted on the serialized envelope).
- [x] `tools/list` unchanged (no schema/tool change); still forbids deploy/public-bind/install/systemd/secret/
      apply/daemon/restart/bind/upload.
- [x] No `structuredContent`, no protocol-version bump (envelope is a second `text` content item).
- [x] `igniter_agent_mcp_smoke_tests` 16/16; `igniter_app_bundle_smoke_tests` 6/6; `igniter_serve_wrapper_smoke_tests` 17/17.
- [x] `cargo build --release --bin igniter-agent` OK; `bash -n bin/igniter` + `git diff --check` clean.

## Reporting

1. **Envelope shape:** result `content = [ {type:text, text:<human>}, {type:text, text:<JSON>} ]`,
   `isError` unchanged. Envelope JSON = `{ tool, ok (= !isError), exit_code (Integer|null), stdout (bounded),
   stderr (bounded), parsed (Value|null) }`. Helper `tool_enveloped(...)` (+ `tool_command_result`,
   `tool_arg_error`).
2. **Non-null `parsed`:** `doctor` (the `--json` array), `serve_app_bounded` (`{listen,path,requests_issued,
   http_status,all_200,exit_code}`), `app_bundle` (`{bundle_path, manifest}`), `check_app`
   (`{ok,entry,sources,no_socket_opened}`). **Null:** `package_verify`, `toolchain_list`, unknown-tool,
   and arg-validation errors.
3. **Parse failures:** `parsed:null`; command `exit_code`/`stdout`/`stderr` preserved; NOT a JSON-RPC protocol
   error; `ok` keeps mirroring the command's success (a parse miss never forces `ok:false`).
4. **`content[0]` back-compat:** the 10 prior P24/P25/P26 tests pass with zero edits — `content[0]` is the same
   `tool_body`/human text. Doctor also preserves the pre-existing `json:true` behavior: content[0] becomes
   the JSON report when explicitly requested.
5. **Tests:** agent **16/16** (10 prior + 6 new envelope tests), app-bundle **6/6**, serve-wrapper **17/17**,
   release build OK.

Implementation: `server/igniter-web/src/bin/igniter-agent.rs` (envelope helpers + per-tool `parsed`; serve
refactored to a `ServeOut` struct); tests in `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`.
`bin/igniter` untouched. `igniter-agent` stays opt-in (not in the default 5-binary fleet).

## Closed Surfaces

No new tools. No deploy/apply. No public bind. No systemd. No secrets/DSNs. No DB migrations. No daemon or
process registry. No `structuredContent`. No MCP protocol-version bump. No replacement of `igniter-mcp`.
