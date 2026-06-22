# LAB-HYGIENE-SPARKCRM-ROUTE-SCOPE-P8 - ensure SparkCRM route-shape docs stay static-pressure only

Status: READY
Lane: workspace hygiene / product pressure docs
Type: documentation cleanup
Delegation code: OPUS-HYGIENE-SPARKCRM-ROUTE-SCOPE-P8
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics flagged a possible overclaim around SparkCRM route-shape pressure. The intended
boundary is:

```text
static route-file characterization only; no SparkCRM execution; no Ruby runtime integration; no DB; no secrets.
```

The current route-shape doc may already say this clearly. This card exists to verify and patch only if needed.

## Goal

Make the SparkCRM route-shape pressure doc unambiguous for future agents: it is product pressure for IgWeb
route scaling and syntax, not a migration proof and not live compatibility.

## Verify first

Run:

```text
sed -n '1,220p' lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md
rg -n "SparkCRM.*(execute|execution|live|DB|database|Ruby|migration|compatib|supports|validates)" lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md
```

If the doc is already clear, only update this card's closing report and do not touch the doc.

## Allowed changes

- Add a small "Scope guard" note near the top of the route-shape doc only if ambiguity remains.
- Optionally update the drift-forensics doc if it still marks this as unresolved after your verification.

## Closed surfaces

- No SparkCRM repo access required.
- No live SparkCRM, Ruby, DB, credentials, route parser, or migration work.
- No rewrite of the route-shape report.

## Acceptance

- [ ] The doc clearly says static route-file characterization only.
- [ ] The doc does not imply route execution, Rails compatibility, migration readiness, or live app support.
- [ ] If no edit is needed, closing report says "verified already clear" with line references.
- [ ] `git diff --check` clean.

## Closing report

TBD.
