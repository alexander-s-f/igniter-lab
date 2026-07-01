# LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4 — unify JSON/CI/MCP result contract

Status: DONE
Lane: distribution / command center / structured output
Type: readiness + small conformance implementation if obvious
Delegation code: OPUS-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P1 found that shell remains acceptable for the immediate `workspace` lane, but structured output is now the
main pressure point:

- `bin/igniter doctor --json` already emits diagnostic records.
- `igniter-agent` MCP uses shape C: human text plus a second JSON-envelope content item.
- `bin/igniter` hand-rolls JSON escaping and uses narrow text parsing in places.
- New `workspace` commands will add more JSON consumers.

Before the command center grows further, we need a small contract that agents/CI can rely on.

## Goal

Define and, if low-risk, enforce the v0 structured output contract for command-center diagnostics.

This card should answer:

1. What is the canonical diagnostic record shape?
2. Which commands must support `--json`?
3. What exit-code semantics are stable?
4. How should MCP tools wrap command results?
5. What is explicitly human-only text and must not be parsed by agents?
6. Is this enough in shell, or does the evidence force a Rust CLI readiness card next?

## Verify first

Read live code and tests:

- `bin/igniter`
- `server/igniter-web` agent/MCP implementation
- tests for doctor / agent structured responses
- P1 packet:
  `lab-docs/lang/lab-igniter-command-center-autonomy-readiness-p1-v0.md`
- P2/P3 workspace implementation if already landed

Do not invent a new schema if a live one already works.

## Candidate v0 schema

Prefer reusing the existing doctor record:

```json
{
  "scope": "workspace",
  "check": "igniter-lang sibling",
  "severity": "ok",
  "detail": "../igniter-lang/docs/spec/stdlib-inventory.json present",
  "suggest": ""
}
```

Severity vocabulary:

```text
ok | info | warn | fail
```

For command results that need a top-level envelope, consider:

```json
{
  "ok": true,
  "command": "workspace doctor",
  "records": [ ... ],
  "summary": { "ok": 7, "warn": 1, "fail": 0 }
}
```

But do not force an envelope if it breaks existing consumers unnecessarily. The packet must decide array vs
envelope and document migration.

## MCP shape

Preserve the existing MCP shape C unless live evidence says otherwise:

- content item 1: human text;
- content item 2: JSON envelope / structured payload.

Agents should consume the JSON item, not scrape text.

## Exit-code expectations

Document stable conventions:

- `0`: command ran and no required gate failed;
- `2`: usage error;
- non-zero gate: required local check failed (`env check`, future `workspace doctor` if required layout is bad);
- remote best-effort warnings should not fail a local doctor unless command is explicitly a network gate.

## Design constraints

- Do not rewrite `bin/igniter` wholesale.
- Do not port to Rust in this card unless it is truly tiny and explicitly justified.
- Do not change authority boundaries.
- Do not make agents parse human text.
- Do not silently change existing JSON shape without documenting compatibility.

## Output

Write:

`lab-docs/lang/lab-igniter-command-center-json-contract-p4-v0.md`

If a tiny conformance test is obvious and low-risk, add it. Otherwise keep this doc-only and name the
implementation follow-up.

## Acceptance

- [x] Packet written under `lab-docs/lang/`.
- [x] Live JSON surfaces verified.
- [x] Canonical record/envelope shape chosen.
- [x] Severity vocabulary documented.
- [x] Exit-code conventions documented.
- [x] MCP shape C confirmed or revised with evidence.
- [x] Human text vs machine JSON boundary is explicit.
- [x] Compatibility/migration impact documented.
- [x] Rust CLI pressure assessed but not over-claimed.
- [x] Next implementation card named if code is not changed here.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-07-01 · Packet: `lab-docs/lang/lab-igniter-command-center-json-contract-p4-v0.md`.
Changes staged (not committed). No shape change, no Rust port, no authority change.

**Decision — freeze the two live shapes, don't reinvent:**
- **CLI `--json` = a bare JSON array of records** `{scope,check,severity,detail,suggest}` (doctor +
  `workspace status|doctor|build|test`; severity ∈ closed set `ok|info|warn|fail`; `suggest` = string|null).
  The candidate top-level `{ok,command,records,summary}` envelope is **rejected as the default** — it would
  break live consumers (`igniter_doctor_tests` + `igniter_workspace_tests` assert the output
  `starts_with('[')`). A summary is trivially derivable; if CI ever needs one, add an **opt-in
  `--json-envelope`** (additive), named as a follow-up.
- **MCP = shape C** (P28), confirmed live + tested: `content[0]`=human text, `content[1]`=envelope
  `{tool,ok,exit_code,stdout,stderr,parsed}`, `isError`; `parsed` carries the record array so agents get the
  same schema from the MCP tool as from the CLI. Agents consume `content[1]`, never `content[0]`.

**Verified live (§2 of packet):** doctor + workspace emit the bare record array via `doc_render_json`;
severities actually emitted across `bin/igniter` are exactly ok(16)/warn(10)/fail(8)/info(7); `stdlib`/
`explain` `--json` are **igc-owned** (center routes argv only); `env` is names-only text (value-safe, no
`--json` today). Exit codes: `0` ran/no-gate, `2` usage, `1` required-local gate (`env check`, `workspace
doctor` layout, `workspace build/test` step); remote best-effort → `warn`, never fatal.

**Small conformance implementation added** (the card's "add a tiny test if obvious"):
`server/igniter-web/tests/igniter_json_contract_tests.rs` (**5 tests, all pass**) pins the invariants —
bare array, all five keys per record, closed severity vocabulary, and no env-value leak — across `doctor`,
`workspace status`, `workspace doctor` `--json`. Hermetic (`IGNITER_WORKSPACE_NO_REMOTE=1`). This makes the
"agents never parse text" guard executable so the shape can't drift silently.

**Rust-CLI pressure:** real but **not forcing** (hand-rolled `json_escape`/`doc_render_json` is small,
stable, tested, conformant). Verdict LOW-MODERATE; the trigger is typed/streamed records or the opt-in
envelope's computed summary → `LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P5`.

**Verification:** new `igniter_json_contract_tests` → 5/5. Regression: `igniter_agent_mcp_smoke_tests` 21/21,
`igniter_doctor_tests` 6/6, `igniter_workspace_tests` 9/9. `git diff --check` clean; no trailing whitespace.
No `bin/igniter` behavior change (this card only pins + tests the existing contract).

**Next cards named:** `LAB-IGNITER-COMMAND-CENTER-JSON-ENVELOPE-OPTIN-P5a` (optional additive
`--json-envelope`), `LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P5` (Rust pivot), and candidate
`LAB-IGNITER-ENV-JSON-ALIGN-P6` (record-array `--json` for `env` if a need appears).
