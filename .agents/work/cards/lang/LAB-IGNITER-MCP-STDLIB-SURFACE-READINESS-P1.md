# LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1 - expose stdlib/explain through `igniter agent`

Status: CLOSED (2026-06-30) - readiness packet written; recommends shell-delegated `igniter agent` tools in P2
Lane: distribution / agent-dx / stdlib
Type: readiness / architecture
Date: 2026-06-30

## Context

The stdlib help surface now has a single front-door authority:

```text
igc stdlib list [--category <name>] [--json]
igc stdlib search <query> [--json]
igc stdlib show <name> [--json]
igc explain <RULE> [--json]

igniter stdlib ...
igniter explain ...
```

Important live facts from the previous slice:

- `igc` owns the canonical stdlib/help implementation (`stdlib_surface.rs`).
- `bin/igniter` delegates to `igc`; it does **not** parse `stdlib-inventory.json` or recompute the digest.
- `igniter agent` is the command-center MCP surface (`server/igniter-web/src/bin/igniter-agent.rs`).
- `igniter-agent` must remain distinct from the machine/capsule/fact MCP surface (`igniter-mcp`).
- Existing `igniter-agent` tools shell-delegate to `bin/igniter` via `run_igniter(...)` and grant no authority beyond the human front door.

This card decides how to expose the new stdlib/explain surface to agents over MCP without creating a second
docs authority.

## Goal

Produce a readiness packet that specifies the smallest safe MCP addition:

```text
stdlib_list
stdlib_search
stdlib_show
diagnostic_explain
```

The packet must define tool schemas, response shape, error mapping, tests, and the next implementation card.

## Verify First

Read live code/docs before deciding:

- `bin/igniter`
- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `.agents/work/cards/lang/LAB-DISTRIBUTION-AGENT-DX-READINESS-P23.md`
- the recent stdlib/help/delegation cards and packets:
  - `LAB-IGNITER-STDLIB-SURFACE-HELP-P1`
  - `LAB-IGNITER-CLI-CONTROL-CENTER-STDLIB-DELEGATION-P1`
  - `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4`

Do not rely on stale "MCP missing" claims. The command-center MCP is live.

## Questions To Answer

1. What is the exact current MCP response convention?
   - `content[0]` human text?
   - `content[1]` JSON envelope?
   - where does `parsed` live?
2. Should the new MCP tools delegate to:
   - `igniter stdlib ... --json` / `igniter explain ... --json`;
   - `igc` directly;
   - Rust `stdlib_surface` directly?
3. What are the exact tool names and input schemas?
4. Should unknown stdlib function / unknown diagnostic be represented as:
   - MCP transport error;
   - `isError: true` with the usual envelope;
   - `isError: false` plus `{ok:false}` parsed JSON?
5. Should `stdlib_list` expose category filtering in v0?
6. Should `stdlib_search` require a non-empty query or permit empty query as list-all?
7. How should stderr / non-zero exits be surfaced without leaking extra authority?
8. What hermetic MCP smoke tests should prove the surface?

## Candidate Shapes

Compare at least four options:

- **A. Shell-delegate from MCP to `igniter stdlib/explain --json`.**
  - Preferred bias.
  - Keeps `bin/igniter` as the only command-center front door.
  - MCP adds routing/schema only.
- **B. Shell-delegate from MCP directly to `igc`.**
  - Acceptable fallback only if `igniter` delegation is insufficient.
  - Weaker because it bypasses the human control-center path.
- **C. Import Rust `stdlib_surface` inside `igniter-agent`.**
  - Reject or defer unless evidence demands it.
  - Creates a second consumer of compiler internals in the web crate.
- **D. No MCP addition; agents shell out manually.**
  - Baseline, but poor DX and keeps agents grepping docs.

## Required Recommendations

The packet must recommend one v0 path and one implementation card.

Recommended names unless verify-first finds a better fit:

```text
stdlib_list
stdlib_search
stdlib_show
diagnostic_explain
```

Recommended implementation card:

```text
LAB-IGNITER-MCP-STDLIB-SURFACE-P2
```

## Acceptance

- [x] Readiness packet written:
  - `lab-docs/lang/lab-igniter-mcp-stdlib-surface-readiness-p1-v0.md`
- [x] Live `igniter-agent` response shape characterized from source/tests.
- [x] `igniter-mcp` boundary explicitly preserved: no machine/capsule/fact mixing.
- [x] At least four candidate shapes compared.
- [x] Tool names, JSON schemas, delegated argv, and error mapping specified.
- [x] Tests for P2 named:
  - `tools/list` includes new stdlib tools;
  - `stdlib_show find` returns `stdlib.collection.find`;
  - `stdlib_search predicate` finds `find/any/all`;
  - `diagnostic_explain OOF-COL3` returns the collection diagnostic;
  - unknown tool args / unknown function / unknown diagnostic fail cleanly without panic;
  - no secrets/env values printed.
- [x] No production code changes in this readiness card.
- [x] `git diff --check` clean.

## Report (2026-06-30)

**Readiness packet:** `lab-docs/lang/lab-igniter-mcp-stdlib-surface-readiness-p1-v0.md`.

**Recommendation:** implement shape A in `LAB-IGNITER-MCP-STDLIB-SURFACE-P2`: add `stdlib_list`,
`stdlib_search`, `stdlib_show`, and `diagnostic_explain` to `igniter-agent`, but shell-delegate only through
`run_igniter(...)` to `bin/igniter stdlib/explain --json`. Do not call `igc` directly, do not import
`stdlib_surface`, and do not parse inventory in the agent.

**Current MCP response convention:** `content[0]` is the human text body; `content[1]` is a JSON text envelope
`{tool, ok, exit_code, stdout, stderr, parsed}`; `parsed` lives in
`JSON.parse(result.content[1].text).parsed`. Tool errors use MCP `result.isError`, not JSON-RPC transport
errors.

**Live CLI facts captured:** `list --json` count `46`, digest
`d6ec4b7fddc931243c4b59d925680a63da2814fa6aae041b5dcd05f756daf0bc`; `show find` resolves to
`stdlib.collection.find`; `search predicate` finds predicate collection ops; `explain OOF-COL3` returns five
collection entries including `find/any/all`; unknown `show` is exit `1` with parsed `ok:false/not_found`;
unknown/unused diagnostic rule remains a successful empty explanation by current `igc` contract.

**P2 test matrix named:** tools/list, positive show/search/explain/list-category, missing blank args, unknown
show, unused diagnostic, envelope shape, forbidden tool names, and no secret/env-value leakage.

**Files changed in this readiness card:** packet doc + this card only. No production code changed; no
`igniter-mcp`, `bin/igniter`, compiler, or server implementation changed.

**Verification:** `git diff --check` PASS.

## Closed Surfaces

No implementation in this card. No new MCP server. No changes to `igniter-mcp`. No inventory parsing in
`igniter-agent`. No registry/network. No deploy/apply. No public bind. No secrets or DSNs. No long-running
process supervisor.
