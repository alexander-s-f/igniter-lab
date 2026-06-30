# LAB-FRAME-UI-EMPTY-LEADS-PANIC-P1 - fail closed on empty workbench leads

Status: CLOSED
Lane: frame-ui / igniter-ui-kit / ViewArtifact
Type: tiny implementation + regression test
Date: 2026-06-27
Source: `/Users/alex/dev/projects/igniter/audit/igniter-audit-assimilation-triage-p1.md`

## Agent Onboarding Header

This is a small T0 audit-hardening fix. It is intended for the agent already
working in `frame-ui`, so do not start a competing frame-ui branch if another
agent owns the area.

The issue: a workbench ViewArtifact with `data.leads = []` passes
`workbench_from_value` validation but later panics when
`Workbench::initial_world()` indexes `self.leads[0]`.

## Goal

Make a workbench ViewArtifact with:

```json
{"data":{"leads":[]}}
```

fail closed with `ViewError::Schema` instead of constructing a `Workbench` that
can panic.

## Context

Read first:

```text
/Users/alex/dev/projects/igniter/audit/igniter-audit-assimilation-triage-p1.md
frame-ui/igniter-ui-kit/src/view_artifact.rs
frame-ui/igniter-ui-kit/src/composition.rs
frame-ui/igniter-ui-kit/src/wasm.rs
frame-ui/igniter-ui-kit/tests/view_artifact_tests.rs
```

Live anchors from triage:

- `frame-ui/igniter-ui-kit/src/view_artifact.rs:132-165` collects `leads` and
  checks `fields.is_empty()`, but does not reject `leads.is_empty()`.
- `frame-ui/igniter-ui-kit/src/composition.rs:76-91` indexes `self.leads[0]`
  while building the initial selection fact.
- `frame-ui/igniter-ui-kit/src/wasm.rs` exposes `from_artifact` to the browser
  path.

If line numbers moved, use `rg` / `nl -ba` and state the current anchors in the
closing report.

## Current Authority

- Live `igniter-ui-kit` source and tests decide behavior.
- Opus audit and command-center triage are evidence, not authority.

## Closed Surfaces

- Do not edit `igniter-render-html`, `igniter-gui`, VM, stdlib, server,
  machine, home-lab, SparkCRM, or canon `igniter-lang`.
- Do not bind listeners, run deployments, or change runtime/product behavior
  outside this validation guard.
- Do not widen into `safe_url`, Decimal, or VM arithmetic work.

## Change

1. In `workbench_from_value`, after collecting `leads`, return a schema error
   when `leads.is_empty()`. Suggested message:

```text
workbench: at least one lead required
```

2. Add a focused regression test in `tests/view_artifact_tests.rs` with a
   minimal workbench JSON containing:

```json
{
  "kind": "workbench",
  "data": {
    "fields": [{"id":"name","label":"Name","kind":"text"}],
    "leads": []
  }
}
```

Adjust the exact fixture shape to match current tests. Assert that the compile
path returns `ViewError::Schema` and the message contains `lead`.

## Acceptance

- [ ] New empty-`leads` regression fails before the guard and passes after it,
      or the closing report explains why a direct before/after was impractical.
- [ ] `cargo test --test view_artifact_tests`
- [ ] `cargo test --lib`
- [ ] `git diff --check`
- [ ] Only `igniter-ui-kit` source/tests changed.

## Closing Report

CLOSED 2026-06-27.

### What changed

Fail-closed guard added to `workbench_from_value`: after the `leads` array is
collected (and lead-shape validated), an EMPTY lead set now returns
`ViewError::Schema("workbench: at least one lead required")` instead of
constructing a `Workbench { leads: [], … }` that panics later. The guard is
placed *before* field parsing, so an empty workbench fails on the lead check
first (matches "fail closed on empty leads").

### Exact files changed (only `igniter-ui-kit`)

- `frame-ui/igniter-ui-kit/src/view_artifact.rs` — the guard.
- `frame-ui/igniter-ui-kit/tests/view_artifact_tests.rs` — the regression test.

### Current live line anchors

- Guard: `src/view_artifact.rs:149` (`if leads.is_empty()`), message at `:151`.
  (Triage cited `132-165`; `workbench_from_value` still begins at `:132`.)
- Panic site this guards: `src/composition.rs:90` (`self.leads[0]` in
  `initial_world`). (Triage cited `76-91`; the loop is `:79`, the index `:90`.)
- Regression test: `tests/view_artifact_tests.rs:149`
  (`fn empty_leads_is_a_schema_error`).

### Commands and results

```text
# before/after (acceptance #1) — guard temporarily stashed:
BEFORE: test empty_leads_is_a_schema_error ... FAILED
        (compile returned Ok(Workbench { leads: [], fields: [name:Text] }) — the
         exact value that would then panic at composition.rs:90)
AFTER : test empty_leads_is_a_schema_error ... ok

cargo test --test view_artifact_tests   →  ok. 10 passed; 0 failed
cargo test --lib                        →  ok. 0 passed; 0 failed (no lib unit tests; tests live in tests/)
git diff --check                        →  clean (no whitespace errors)
```

### Scope confirmation

Only `igniter-ui-kit` source + tests were edited. No `igniter-render-html`,
`igniter-gui`, VM, stdlib, server, machine, home-lab, SparkCRM, or canon
`igniter-lang` files touched. No listeners bound, no deployments, no runtime/
product behavior changed beyond this validation guard. Did not widen into
`safe_url`, Decimal, or VM arithmetic.
