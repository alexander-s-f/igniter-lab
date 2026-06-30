# LAB-IGNITER-MCP-STDLIB-SURFACE-P2 - implement stdlib/explain tools in `igniter agent`

Status: CLOSED (2026-06-30) - stdlib/explain MCP tools implemented in `igniter-agent`
Lane: distribution / agent-dx / stdlib
Type: implementation
Date: 2026-06-30

## Context

Readiness P1 is closed:

- card: `LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1`
- packet: `lab-docs/lang/lab-igniter-mcp-stdlib-surface-readiness-p1-v0.md`

Decision from P1: expose stdlib/explain over the command-center MCP by adding four tools to
`igniter-agent`, but **only** by shell-delegating through the existing human front door:

```text
igniter stdlib list/search/show --json
igniter explain RULE --json
```

Do not call `igc` directly from the MCP server. Do not import compiler internals. Do not parse
`stdlib-inventory.json` in `igniter-agent`.

## Goal

Implement these read-only MCP tools:

```text
stdlib_list
stdlib_search
stdlib_show
diagnostic_explain
```

They must follow the existing `igniter-agent` response convention:

- `content[0]` = human text body from the delegated command;
- `content[1]` = JSON text envelope `{tool, ok, exit_code, stdout, stderr, parsed}`;
- `parsed` = parsed delegated CLI JSON when stdout is valid JSON;
- delegated non-zero exits are MCP tool errors (`isError:true`), not JSON-RPC transport errors.

## Verify First

Before editing, read:

- `lab-docs/lang/lab-igniter-mcp-stdlib-surface-readiness-p1-v0.md`
- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `bin/igniter`

Confirm current CLI facts still hold:

```bash
./bin/igniter stdlib show find --json
./bin/igniter stdlib search predicate --json
./bin/igniter explain OOF-COL3 --json
./bin/igniter stdlib show definitely.not.real --json ; test $? -ne 0
```

If the CLI JSON contract drifted, stop and update the card/packet before implementing around stale facts.

## Implementation Scope

### `server/igniter-web/src/bin/igniter-agent.rs`

Add tool descriptors in `tools_list()`:

```text
stdlib_list
stdlib_search
stdlib_show
diagnostic_explain
```

Add `handle_tool_call` branches:

```text
stdlib_list          -> run_igniter(["stdlib", "list", "--json"])
stdlib_list(category)-> run_igniter(["stdlib", "list", "--category", category, "--json"])
stdlib_search(query) -> run_igniter(["stdlib", "search", query, "--json"])
stdlib_show(name)    -> run_igniter(["stdlib", "show", name, "--json"])
diagnostic_explain(rule) -> run_igniter(["explain", rule, "--json"])
```

Add a small helper if useful, but keep it narrow:

- run delegated command;
- parse stdout as JSON into `parsed` when possible;
- call the existing envelope helper (`tool_command_result` / `tool_enveloped`);
- preserve the existing `content[0]` + `content[1]` convention.

Validate required string arguments before launch:

- `stdlib_search.query` required and non-blank;
- `stdlib_show.name` required and non-blank;
- `diagnostic_explain.rule` required and non-blank.

Use `tool_arg_error(...)` for missing/blank args. `stdlib_list.category` is optional; if present, pass it as
one argv element. Do not split user strings manually.

## Error Mapping

Implement the P1 mapping exactly:

| Case | Launch command? | MCP `isError` | Envelope `exit_code` | Envelope `parsed` |
|---|---:|---:|---:|---|
| Missing/blank MCP argument | No | `true` | `null` | `null` |
| Delegated success | Yes | `false` | CLI exit code, normally `0` | Parsed CLI JSON |
| Unknown `stdlib_show` target | Yes | `true` | `1` | Parsed `{ok:false, reason:"not_found"}` if stdout parses |
| Unknown/unused diagnostic rule | Yes | `false` | `0` | Parsed `{ok:true, count:0, entries:[]}` |
| CLI usage/non-zero without JSON | Yes | `true` | CLI exit code | `null` |
| Launch failure | Yes attempted | `true` | `-1` | `null` |

Do not invent JSON-RPC transport errors for normal tool failures.

## Tests

Extend `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`.

Required tests:

1. `tools/list` includes `stdlib_list`, `stdlib_search`, `stdlib_show`, and `diagnostic_explain`.
2. Existing forbidden-tool assertions still reject deploy/install/systemd/secret/apply/daemon/restart/bind
   shaped names.
3. `stdlib_show` with `{ "name": "find" }` succeeds and
   `envelope(...).parsed.entry.canonical_name == "stdlib.collection.find"`.
4. `stdlib_search` with `{ "query": "predicate" }` succeeds and returns matches containing
   `stdlib.collection.find`, `stdlib.collection.any`, and `stdlib.collection.all`.
5. `diagnostic_explain` with `{ "rule": "OOF-COL3" }` succeeds and returns entries containing the predicate
   collection family.
6. `stdlib_list` with `{ "category": "collection" }` succeeds and every parsed entry has
   `category == "collection"`.
7. Missing/blank `query`, `name`, and `rule` are clean MCP tool errors:
   `isError:true`, `exit_code:null`, no panic.
8. Unknown `stdlib_show` target returns `isError:true`, delegated `exit_code:1`, and parsed
   `reason == "not_found"`.
9. Unknown/unused diagnostic rule returns `isError:false`, exit `0`, and parsed empty entries.
10. `content[0]` remains human text and `content[1]` remains valid JSON for all new tools.
11. No env values, secrets, DSNs, public bind addresses, registry writes, or process handles appear in output.

Keep the current hermetic test pattern: drive `bin/igniter agent` over stdio, pin the test-built
`igniter-agent` with `IGNITER_AGENT_BIN`, and rely on repo-local `bin/igniter`.

## Verification

Run focused checks:

```bash
cargo test --test igniter_agent_mcp_smoke_tests
./bin/igniter stdlib show find --json
./bin/igniter explain OOF-COL3 --json
git diff --check
```

If time permits, also run the broader web crate tests touched by `igniter-agent`.

## Acceptance

- [x] `tools/list` exposes all four new tools.
- [x] All four tools delegate through `run_igniter(...)` to `bin/igniter`; no direct `igc` resolution.
- [x] No inventory parsing or `stdlib_surface` import in `igniter-agent`.
- [x] Positive stdlib/show/search/explain tests pass.
- [x] Missing arg, unknown stdlib target, and unused diagnostic behaviors match P1.
- [x] Existing command-center MCP tools still pass.
- [x] No `igniter-mcp` changes.
- [x] No deploy/apply/public bind/systemd/secrets/DSNs/registry/network/process-supervisor surface.
- [x] `git diff --check` clean.
- [x] Card closed with a short report and exact test results.

## Report (2026-06-30)

**Implemented tools:** `stdlib_list`, `stdlib_search`, `stdlib_show`, `diagnostic_explain`.

**Implementation shape:** `igniter-agent` descriptors + `handle_tool_call` branches only. Each new tool uses
`run_json_igniter_tool(...)`, which delegates through `run_igniter(...)` to the repo front door:

```text
igniter stdlib list --json
igniter stdlib list --category <category> --json
igniter stdlib search <query> --json
igniter stdlib show <name> --json
igniter explain <rule> --json
```

Stdout is parsed as JSON into the existing envelope `parsed` field when possible; parse failure leaves
`parsed:null` without changing CLI exit semantics. Missing/blank `query`, `name`, and `rule` use
`tool_arg_error(...)`, so no command launches and `exit_code:null`.

**Boundary preserved:** no direct `igc` resolution in the agent, no `stdlib_surface` import, no
`stdlib-inventory.json` parsing, no `igniter-mcp` changes, no deploy/apply/public bind/systemd/secrets/DSNs/
registry/network/process-supervisor surface.

**Tests added:** `igniter_agent_mcp_smoke_tests.rs` now checks:

- `tools/list` includes all four tools and existing forbidden-tool assertions remain active;
- `stdlib_show find` resolves `stdlib.collection.find`;
- `stdlib_search predicate` returns `stdlib.collection.find`, `stdlib.collection.any`, and
  `stdlib.collection.all`;
- `diagnostic_explain OOF-COL3` returns the predicate collection family;
- `stdlib_list category=collection` returns only collection entries;
- blank/missing args are clean tool errors with `exit_code:null`;
- unknown stdlib target returns `isError:true`, delegated `exit_code:1`, and parsed `reason:not_found`;
- unused diagnostic `OOF-NOPE` returns `isError:false`, exit `0`, and empty entries.

**Verification:**

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_agent_mcp_smoke_tests
=> PASS, 21 passed, 0 failed

./bin/igniter stdlib show find --json
=> igniter_stdlib_show_result | true | stdlib.collection.find

./bin/igniter explain OOF-COL3 --json
=> igniter_diagnostic_explain_result | true | 5 | stdlib.collection.all,stdlib.collection.any,stdlib.collection.filter,stdlib.collection.filter_map,stdlib.collection.find

git diff --check
=> PASS
```

Notes: focused test run emitted pre-existing warnings in adjacent crates (`igniter_tbackend_playground`,
`igniter_compiler`, `igniter_vm`, `igniter_machine`); no new failures.

## Closed Surfaces

No new MCP server. No changes to `igniter-mcp`. No direct compiler crate dependency in `igniter-agent`.
No changes to `igc` stdlib surface unless verify-first proves a regression. No registry/network. No deploy.
No public bind. No secrets or DSNs. No long-running process supervisor.
