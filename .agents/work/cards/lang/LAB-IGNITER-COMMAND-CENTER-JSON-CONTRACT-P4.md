# LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4 — unify JSON/CI/MCP result contract

Status: OPEN
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

- [ ] Packet written under `lab-docs/lang/`.
- [ ] Live JSON surfaces verified.
- [ ] Canonical record/envelope shape chosen.
- [ ] Severity vocabulary documented.
- [ ] Exit-code conventions documented.
- [ ] MCP shape C confirmed or revised with evidence.
- [ ] Human text vs machine JSON boundary is explicit.
- [ ] Compatibility/migration impact documented.
- [ ] Rust CLI pressure assessed but not over-claimed.
- [ ] Next implementation card named if code is not changed here.
- [ ] `git diff --check` clean.

## Closing report

Fill when complete.
