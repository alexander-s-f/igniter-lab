# lab-igniter-mcp-stdlib-surface-readiness-p1-v0 - stdlib/explain tools for `igniter agent`

Card: `LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1`
Status: CLOSED (2026-06-30)
Authority: lab readiness - recommendation only. No production code changed in this card.

## Verify-first basis

Live command-center boundary:

- `igc` owns the stdlib/help implementation in `lang/igniter-compiler/src/stdlib_surface.rs`.
- `bin/igniter` exposes `stdlib` and `explain` as routing only. It resolves `igc`, execs
  `igc stdlib ...` / `igc explain ...`, preserves argv and exit code, and does not parse
  `stdlib-inventory.json` or recompute the digest.
- `igniter agent` is the command-center MCP surface in
  `server/igniter-web/src/bin/igniter-agent.rs`. It is distinct from `igniter-mcp`, which remains the
  machine/capsule/fact MCP surface.
- Current `igniter-agent` tools shell-delegate through `run_igniter(args: &[&str])`, so new tools should add
  routing/schema only and inherit the same human front door.

Live stdlib JSON, via `bin/igniter` on 2026-06-30:

- `igniter stdlib list --json` -> `kind=igniter_stdlib_list_result`, `ok=true`, digest
  `d6ec4b7fddc931243c4b59d925680a63da2814fa6aae041b5dcd05f756daf0bc`, count `46`.
- `igniter stdlib search predicate --json` -> `kind=igniter_stdlib_search_result`, `ok=true`, count `3`
  (`all`, `any`, `find` family).
- `igniter stdlib show find --json` -> `kind=igniter_stdlib_show_result`, `ok=true`,
  `entry.canonical_name=stdlib.collection.find`.
- `igniter explain OOF-COL3 --json` -> `kind=igniter_diagnostic_explain_result`, `ok=true`, count `5`,
  entries include `stdlib.collection.find`, `stdlib.collection.any`, and `stdlib.collection.all`.
- `igniter stdlib show definitely.not.real --json` exits `1` and prints structured JSON
  `{ "ok": false, "reason": "not_found" }` on stdout.
- `igniter stdlib search --json` exits `1`, stdout empty, stderr usage text.
- `igniter explain OOF-NOPE --json` is not an error by current `igc` contract: `ok=true`, `entries=[]`,
  exit `0`.

## Current MCP response convention

`igniter-agent` returns tool results as MCP `result` objects:

```json
{
  "content": [
    { "type": "text", "text": "exit_code: 0\nstdout:\n...\nstderr:\n..." },
    { "type": "text", "text": "{\"tool\":\"...\",\"ok\":true,\"exit_code\":0,\"stdout\":\"...\",\"stderr\":\"...\",\"parsed\":...}" }
  ],
  "isError": false
}
```

The stable v0 machine payload is `JSON.parse(result.content[1].text)`. `parsed` lives inside that envelope:

```json
{
  "tool": "stdlib_show",
  "ok": true,
  "exit_code": 0,
  "stdout": "...bounded...",
  "stderr": "...bounded...",
  "parsed": { "kind": "igniter_stdlib_show_result" }
}
```

`content[0]` remains the human text body. `stdout` and `stderr` in the envelope are bounded by the existing
`snippet()` helper. Argument-validation errors that do not launch a command use `exit_code:null`,
`parsed:null`, and `isError:true`. Unknown tools and delegated non-zero exits are tool errors (`isError:true`),
not JSON-RPC transport errors.

## Candidate shapes

| Shape | Description | Verdict |
|---|---|---|
| A | Shell-delegate from MCP to `igniter stdlib ... --json` and `igniter explain ... --json`. | Recommended. Preserves `bin/igniter` as the command-center front door; MCP adds only schemas, argv routing, and response wrapping. |
| B | Shell-delegate from MCP directly to `igc`. | Reject for v0. It would work technically but bypasses the human command-center path and duplicates resolution policy already owned by `bin/igniter`. |
| C | Import Rust `stdlib_surface` inside `igniter-agent`. | Reject/defer. It creates a second Rust consumer of compiler internals in the web crate and weakens the "igc owns stdlib/help" boundary. |
| D | No MCP addition; agents shell out manually. | Reject as the next step. It preserves authority but leaves agents parsing CLI calls ad hoc and keeps DX worse than the existing command-center MCP pattern. |

Recommendation: implement shape A in `LAB-IGNITER-MCP-STDLIB-SURFACE-P2`.

## Tool contracts for P2

All four tools are read-only, non-mutating, local stdio MCP tools. They always request CLI JSON and place the
parsed CLI JSON in the MCP envelope's `parsed` field when stdout is valid JSON.

### `stdlib_list`

Input schema:

```json
{
  "type": "object",
  "properties": {
    "category": {
      "type": "string",
      "description": "Optional exact stdlib category filter, passed to --category"
    }
  }
}
```

Delegated argv:

```text
["stdlib", "list", "--json"]
["stdlib", "list", "--category", category, "--json"]
```

Response: `parsed.kind=igniter_stdlib_list_result`, `parsed.ok=true`, `parsed.digest`, `parsed.category`,
`parsed.count`, `parsed.entries`.

Category filtering should be exposed in v0 because the CLI already owns it and the MCP layer need only pass
the exact string through. An unknown category is a valid empty list (`count:0`) unless `igc` changes that
contract.

### `stdlib_search`

Input schema:

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Required non-empty search query"
    }
  },
  "required": ["query"]
}
```

Delegated argv:

```text
["stdlib", "search", query, "--json"]
```

The MCP tool should trim validation only enough to reject a missing or all-whitespace query before launch:
`tool_arg_error(..., "missing required argument: query")`. Do not treat empty query as list-all; callers
should use `stdlib_list` for that. Preserve the query as one argv element so phrase-like searches remain
caller-controlled; `igc` already tokenizes whitespace internally.

Response: `parsed.kind=igniter_stdlib_search_result`, `parsed.ok=true`, `parsed.query`, `parsed.count`,
`parsed.matches`.

### `stdlib_show`

Input schema:

```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Required canonical stdlib name, semantic IR name, or source alias"
    }
  },
  "required": ["name"]
}
```

Delegated argv:

```text
["stdlib", "show", name, "--json"]
```

Reject missing/all-whitespace `name` before launch. On success, response has
`parsed.kind=igniter_stdlib_show_result`, `parsed.ok=true`, and `parsed.entry`.

Unknown function/alias: preserve delegated exit `1`, set MCP `isError:true`, and put the parsed stdout JSON
in `parsed` when possible (`ok:false`, `reason:"not_found"`). This is not a JSON-RPC transport error.

### `diagnostic_explain`

Input schema:

```json
{
  "type": "object",
  "properties": {
    "rule": {
      "type": "string",
      "description": "Required diagnostic rule id, for example OOF-COL3"
    }
  },
  "required": ["rule"]
}
```

Delegated argv:

```text
["explain", rule, "--json"]
```

Reject missing/all-whitespace `rule` before launch. On success, response has
`parsed.kind=igniter_diagnostic_explain_result`, `parsed.ok=true`, `parsed.rule`, `parsed.count`,
`parsed.entries`.

Unknown or currently-unused diagnostic rule follows current `igc` behavior: successful empty explanation
(`isError:false`, exit `0`, `parsed.entries=[]`). Only missing rule is an MCP argument error.

## Error mapping

| Case | Launch command? | MCP `isError` | envelope `exit_code` | envelope `parsed` |
|---|---:|---:|---:|---|
| Missing/blank MCP argument | No | `true` | `null` | `null` |
| `stdlib_search` empty query | No | `true` | `null` | `null` |
| Delegated success | Yes | `false` | CLI exit code, normally `0` | Parsed CLI JSON |
| Unknown stdlib show target | Yes | `true` | `1` | Parsed `{ok:false, reason:"not_found"}` if stdout parses |
| Unknown diagnostic rule | Yes | `false` | `0` | Parsed `{ok:true, count:0, entries:[]}` |
| CLI usage/non-zero without JSON | Yes | `true` | CLI exit code | `null` |
| Launch failure | Yes attempted | `true` | `-1` | `null` |
| JSON parse failure on exit 0 | Yes | `false` for v0 compatibility | `0` | `null` |

The parse-failure row preserves the existing structured-response rule from P27/P28: parsing is observability,
not transport authority. A later hardening card may add a separate `parse_error` field, but P2 should not
invent a new envelope contract.

## Hermetic tests for P2

Extend `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`:

1. `tools/list` includes `stdlib_list`, `stdlib_search`, `stdlib_show`, and `diagnostic_explain`.
2. The existing forbidden-tool assertions still reject deploy/install/systemd/secret/apply/daemon/restart/
   bind/upload shaped names.
3. `stdlib_show` with `{ "name": "find" }` succeeds; `envelope(...).parsed.entry.canonical_name` is
   `stdlib.collection.find`.
4. `stdlib_search` with `{ "query": "predicate" }` succeeds and returns matches containing
   `stdlib.collection.find`, `stdlib.collection.any`, and `stdlib.collection.all`.
5. `diagnostic_explain` with `{ "rule": "OOF-COL3" }` succeeds and returns entries containing the predicate
   collection family.
6. `stdlib_list` with `{ "category": "collection" }` succeeds and every parsed entry has
   `category="collection"`.
7. Missing/blank `query`, `name`, and `rule` are clean MCP tool errors: `isError:true`, `exit_code:null`,
   no panic, no command launch.
8. Unknown `stdlib_show` target returns `isError:true`, delegated `exit_code:1`, and parsed
   `reason="not_found"`.
9. Unknown/unused diagnostic rule returns `isError:false`, exit `0`, and parsed empty entries.
10. `content[0]` remains human text and `content[1]` remains valid JSON for all new tools.
11. No env values, secrets, DSNs, public bind addresses, registry writes, or process handles appear in output.

Test setup should keep the current hermetic pattern: drive `bin/igniter agent` over stdio, pin the test-built
`igniter-agent` with `IGNITER_AGENT_BIN`, and rely on the repo-local `bin/igniter` front door.

## P2 implementation card

Recommended next card:

```text
LAB-IGNITER-MCP-STDLIB-SURFACE-P2
```

P2 scope:

- add the four tool descriptors to `tools_list()`;
- add four `handle_tool_call` branches;
- add a small helper for "run JSON stdlib command and parse stdout";
- validate required string args before launch;
- delegate only through `run_igniter(...)` to `bin/igniter`;
- extend MCP smoke tests as listed above.

P2 closed surfaces:

- no `igniter-mcp` changes;
- no new MCP server;
- no direct `igc` process resolution in the agent;
- no Rust `stdlib_surface` import into `server/igniter-web`;
- no inventory parsing in the agent;
- no deploy/apply/public bind/systemd/secrets/DSNs/registry/network/process supervisor.

## Recommendation summary

Use shape A: command-center MCP tools shell-delegate to `igniter stdlib/explain --json` and return the parsed
`igc` JSON inside the existing MCP envelope. This keeps `igc` as the stdlib/help authority, keeps
`bin/igniter` as the human and agent front door, and leaves `igniter-mcp` untouched as the machine/capsule/fact
surface.
