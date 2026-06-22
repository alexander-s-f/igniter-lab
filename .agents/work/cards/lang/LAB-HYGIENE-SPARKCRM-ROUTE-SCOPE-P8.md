# LAB-HYGIENE-SPARKCRM-ROUTE-SCOPE-P8 - ensure SparkCRM route-shape docs stay static-pressure only

Status: CLOSED - 2026-06-22
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

- [x] The doc clearly says static route-file characterization only.
- [x] The doc does not imply route execution, Rails compatibility, migration readiness, or live app support.
- [x] If no edit is needed, closing report says "verified already clear" with line references.
- [x] `git diff --check` clean.

## Closing report

Closed on 2026-06-22.

Verified already clear: `lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md`
already frames the work as static product-pressure evidence:

- line 1: title says "product route-shape pressure (no live SparkCRM)";
- lines 4-7: status says static file characterization only, with no SparkCRM
  execution, Ruby, DB, secrets/data, migration claim, or canon claim;
- lines 149-155: acceptance says counts come from live route files, but no
  SparkCRM secrets/DB/data were read, no execution happened, and no migration
  or live claim is made;
- lines 164-165: closed scope says no SparkCRM migration, Rails route-parser
  implementation, live SparkCRM execution, or route-semantics claim beyond
  static file characterization;
- lines 169-172: footer repeats readiness/product-pressure only, static
  characterization, no code, no migration, no live SparkCRM execution.

The requested verification command:

```text
rg -n "SparkCRM.*(execute|execution|live|DB|database|Ruby|migration|compatib|supports|validates)" lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md
```

returned only scope-guard or product-pressure context:

```text
line 5: Static file characterization only: no SparkCRM execution, no Ruby, no DB...
line 47: SparkCRM validates the P4 design assumption.
line 151: no SparkCRM secrets/DB/data read; no execution...
line 164: No SparkCRM migration; no Rails route-parser implementation; no live SparkCRM execution...
line 172: No code, no migration, no live SparkCRM execution.
```

No route-shape doc edit was needed. Added a one-line P8 hygiene verification
note to `lab-docs/lang/lab-igniter-workspace-drift-forensics-p1-v0.md` so the
forensics packet no longer leaves this item looking unresolved.

Verification:

```text
git diff --check
```
