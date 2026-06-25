# lab-distribution-agent-structured-mcp-responses-readiness-p27-v0 — structured `igniter-agent` tool results

Card: `LAB-DISTRIBUTION-AGENT-STRUCTURED-MCP-RESPONSES-READINESS-P27`
Status: CLOSED (2026-06-25)
Authority: lab readiness — recommendation, not implementation. Structured output adds **observability only**;
no deploy/public-bind/secrets/systemd authority, no new transport, no `igniter-mcp` change.

## Verify-first basis (live, 2026-06-25)

**Current `igniter-agent` result shape** (`server/igniter-web/src/bin/igniter-agent.rs`): every tool returns a
single MCP text content item built by `tool_body` —
```
exit_code: <n>
stdout:
<…>
stderr:
<…>
```
plus an MCP `isError` flag. `serve_app_bounded` embeds extra fields *as text* (`listen:`, `path:`,
`requests_issued:`, `http_status:`, `all_200:`). Output is bounded by `snippet()` (~1500 chars, char-safe).
Tools shell-delegate to `bin/igniter` (P24/P25); P26 added `app_bundle` (6 tools total now).

**Existing tests** (`tests/igniter_agent_mcp_smoke_tests.rs`) read `result.content[0].text` and assert on
substrings (`exit_code: 0`, `check ok`, `listen: 127.0.0.1:`, `HTTP/1.1 200`, …) + the `isError` flag. Any
structured-output change MUST keep `content[0]` as the human text or these break.

**Live CLI structured-output reality (checked, not assumed):**
- `igniter doctor --json` → a **real JSON array** of `{scope, check, severity, detail, suggest}` (verified).
  The non-`--json` form is the human report. `doctor --json` is the one first-class structured CLI path.
- `igniter package verify` → `igc verify` emits **TEXT** ("verify: no lockfile at ./igniter.lock …"), exit 0
  — **not JSON**. (Other `igc package …` verbs like `graph` emit JSON, but `verify` does not.)
- `igniter check <app>` → one structured **text** line: `igweb-serve: check ok app_dir=… entry=Serve
  sources=2 (no socket opened)` — parseable but not JSON.
- `igniter toolchain list` → human text, no JSON.
- `igniter app bundle` → prints `app bundle ok → <dest>` and writes a real **`manifest.json`** at the dest
  (P14) — a genuine JSON artifact the agent can read.
- `serve_app_bounded` fields are **agent-synthesized** (the agent already computes listen/status/counts).

## Q5 — which tools can produce reliable parsed JSON *today*

| Tool | Reliable parsed JSON today? | Source |
|---|---|---|
| `doctor` | **Yes** | native `doctor --json` array |
| `serve_app_bounded` | **Yes** | agent-synthesized (`listen`, `http_status`, `requests_issued`, `all_200`, `exit_code`) |
| `app_bundle` | **Yes** | reads the emitted `manifest.json` (dest in the summary line) |
| `check_app` | **Partial** | synthesize `{ok, entry, sources}` from the one `check ok …` line (regex; reliable) |
| `package_verify` | **No** | `igc verify` is text only → `parsed: null` (keep exit_code/text) |
| `toolchain_list` | **No** | human text only → `parsed: null` (a synthesized fleet array is a later nicety) |

## Alternatives compared

| # | Shape | Verdict |
|---|---|---|
| **A** | Keep text-only; agents parse | **Reject.** Forces every agent to re-parse brittle human text (already the friction this card removes). |
| **B** | JSON as the single text content item | **Reject.** Drops human readability and **breaks every existing `content[0]` text assertion** (P24/P25 tests). |
| **C** | Human text (`content[0]`) **plus a second JSON text content item** | **★ Recommended.** Backward-compatible (existing tests untouched), parseable, and works with the current minimal JSON-RPC: a tool result already has a `content` array — just append a second `{type:"text", text:"<json>"}`. No protocol-version bump. |
| **D** | MCP `structuredContent` + text content | **Defer.** `structuredContent` is a later MCP spec feature (≥2025-06-18); the server advertises `protocolVersion: "2024-11-05"`, and older/clients without support would silently drop it. Bias says avoid protocol cleverness unless the live shape clearly supports it — it doesn't yet. Revisit when the protocol version is bumped and clients confirm support. |

## Recommendation — **C: human text + a second JSON content item**

Every `tools/call` result becomes:
```jsonc
{ "content": [
    { "type": "text", "text": "<existing human body: exit_code/stdout/stderr or tool-specific>" },
    { "type": "text", "text": "<JSON envelope, see below>" }
  ],
  "isError": <bool>
}
```
The **envelope** (the second item, valid bounded JSON):
```jsonc
{
  "tool": "doctor",
  "ok": true,                 // mirrors !isError (exit_code == 0 and tool-level success)
  "exit_code": 0,
  "stdout": "<bounded>",
  "stderr": "<bounded>",
  "parsed": { /* tool-specific JSON when available, else null */ }
}
```

- **Q1/Q2 (shape & envelope):** shape **C**; the envelope above is the stable v0 contract.
- **Q3 (doctor):** the `doctor` tool obtains `--json` to populate `parsed` (the structured array). Preserve
  the **human** report in `content[0]` (a second cheap, non-mutating `doctor` call without `--json`), per the
  "preserve human-readable text" bias; the MCP `json:true` arg may switch `content[0]` itself to the JSON.
  (One-call alternative — put the `--json` text in both — is acceptable if the impl prefers it; the human
  report is the only reason to keep two.)
- **Q4 (parse failure):** `parsed: null`, but **keep** `exit_code`/`ok` from the CLI. A failed *parse* is NOT
  a protocol error and NOT `ok:false` — `ok` reflects the command's exit, not the agent's JSON parsing.
- **Q6 (bounding / secrets):** keep `snippet()` bounding on `stdout`/`stderr`. Secret-safety is inherited:
  the delegated verbs are secret-free (doctor prints env var **names** only, never values; check opens no
  socket; serve is loopback; app_bundle **refuses** real `host.toml`/inline secrets). The envelope carries
  only the same already-bounded output — it adds no new exposure. Rule: never add a tool that echoes env
  values; `parsed` must never include secret fields.
- **Q7 (tests):** structured tests parse `content[1]` as JSON and assert on `ok`/`exit_code`/`parsed.*` —
  decoupled from human wording. `content[0]` stays for the existing substring assertions (back-compat).

## Backwards-compatibility story

`content[0]` is unchanged → all P24/P25/P26 text assertions keep passing. The JSON envelope is **additive**
(`content[1]`). No protocol version change, no client breakage (a client that ignores extra content items
still works). Migration is per-tool and incremental: a tool can ship `parsed: null` first, then gain real
parsed fields later without changing the envelope shape.

## Q8 — first implementation card

**`LAB-DISTRIBUTION-AGENT-STRUCTURED-RESULTS-IMPL-P28`** — add the second JSON-envelope content item to all
`igniter-agent` tools:

- a shared `tool_result_structured(out, id, human_text, envelope, is_error)` helper that appends the JSON
  item; refactor the existing `tool_result` callers through it.
- per-tool `parsed`: `doctor` (from `--json`), `serve_app_bounded` (synthesized fields), `app_bundle`
  (read `manifest.json`), `check_app` (`{ok, entry, sources}` from the check line); `package_verify` /
  `toolchain_list` → `parsed: null` for now.
- **Tests** (extend `igniter_agent_mcp_smoke_tests.rs`): for each tool, parse `content[1]` and assert the
  envelope (`tool`, `ok`, `exit_code`, `parsed` shape); a parse-failure case asserts `parsed:null` with a
  preserved `exit_code`; assert `content[0]` (human text) is still present so back-compat holds.
- **Closed in P28:** no new tools, no deploy/public-bind/secrets/systemd, no `structuredContent`/protocol
  bump (that's a separate future card if/when the protocol version moves).

## Authority boundary

Structured output is **observability only**. It surfaces the same command results in a machine-readable form;
it grants no new capability. Every value in the envelope comes from a `bin/igniter` verb that already enforces
its own authority (loopback/bounded/secret-free/fail-closed). No deploy, public bind, secret, or systemd
field exists or is added.

## Reporting

1. **Recommended MCP result shape:** **C** — keep `content[0]` human text, append `content[1]` = a bounded
   JSON envelope `{tool, ok, exit_code, stdout, stderr, parsed}`. No `structuredContent`/protocol bump in v0.
2. **Tools with parsed fields in v0:** `doctor` (from `--json`), `serve_app_bounded` (synthesized),
   `app_bundle` (manifest.json), `check_app` (parsed line). `package_verify` & `toolchain_list` → `parsed:null`.
3. **`doctor --json`:** used to fill `parsed`; the human report stays in `content[0]` (a second cheap call),
   or `json:true` switches `content[0]` to JSON.
4. **Backwards-compatibility:** envelope is additive (`content[1]`); `content[0]` unchanged → all existing
   text assertions pass; no client/protocol change.
5. **First implementation card:** `LAB-DISTRIBUTION-AGENT-STRUCTURED-RESULTS-IMPL-P28`.

## Acceptance trace

- [x] Packet written (`lab-docs/lang/lab-distribution-agent-structured-mcp-responses-readiness-p27-v0.md`).
- [x] Live current `igniter-agent` response shape characterized (single text `tool_body`, `isError`, snippet bound).
- [x] `doctor --json` characterized from live CLI (real JSON array of severity records).
- [x] ≥5 tools classified by reliable-parsed-JSON-today (6 classified).
- [x] ≥3 response shapes compared (A/B/C/D).
- [x] One v0 shape recommended (C).
- [x] First implementation card named with focused tests (P28).
- [x] Authority boundary explicit (observability only).
- [x] No production code changes; `git diff --check` clean.
