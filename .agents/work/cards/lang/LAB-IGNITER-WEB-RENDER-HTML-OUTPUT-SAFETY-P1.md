# LAB-IGNITER-WEB-RENDER-HTML-OUTPUT-SAFETY-P1 - safe_url and escaping hardening

Status: DONE
Lane: igniter-lab / web / render-html / foundation-hardening
Type: implementation / output-safety
Date: 2026-06-27
Skill: idd-agent-protocol
Source:
- `lab-docs/igniter-web-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is the small now-live web output-safety slice from the foundation audit.
The renderer design is good and bounded, but `safe_url` and escaping need to be
strict enough that a malicious ViewArtifact cannot turn into active content.

## Goal

Harden URL and HTML escaping in the rendering path:

```text
java\nscript:...  -> rejected / safe fallback
java\tscript:...  -> rejected / safe fallback
\x01javascript:   -> rejected / safe fallback
//evil.example    -> rejected / safe fallback
attribute quotes  -> escaped in attribute context
```

## Verify-First Anchors

Before editing, verify live line numbers. Audit anchors:

```text
server/igniter-render-html/src/lib.rs
  safe_url around prior anchor :77
  esc around prior anchor :58
frame-ui/igniter-gui/src/lib.rs and frame-ui/igniter-ui-kit/src/lib.rs
  shared or duplicated esc helpers around prior anchors :125 / :355
```

Important: if frame-ui is actively owned by another agent, do not edit it unless
the current user explicitly authorizes it. It is acceptable for this card to
fix `igniter-render-html` first and document duplicated helper follow-up.

## Current Authority

- Live renderer source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit `server/igniter-render-html` and its tests.
- Edit frame-ui escape helpers only if there is no active conflicting frame-ui
  work and the patch is obviously identical/minimal.

## Closed Surfaces

- Do not change ViewArtifact schema.
- Do not add template/runtime features.
- Do not edit server core transport, machine, compiler, VM, stdlib, home-lab,
  SparkCRM, or canon `igniter-lang`.

## Required Design

- Normalize/strip leading C0 controls and ASCII whitespace before scheme
  detection, or otherwise ensure browsers cannot reinterpret rejected schemes.
- Reject protocol-relative URLs (`//host`) unless there is an explicit allowlist
  already present.
- Escape `&`, `<`, `>`, and quote characters where emitted into attributes.
- Keep text-context and attribute-context behavior explicit if the current code
  uses one helper for both.

## Acceptance

- [x] Tests cover `java\nscript:`, `java\tscript:`, C0-prefixed schemes, and
      protocol-relative URLs.
- [x] Tests cover `"` and `'` escaping in an attribute-bearing node.
- [x] Existing render-html tests pass.
- [x] `cargo test` from live `frame-ui/igniter-render-html` passes.
- [x] `git diff --check` passes.
- [x] Patch is limited to renderer/tests plus this card unless frame-ui helper
      edits were explicitly safe and documented.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-igniter-web-render-html-output-safety-p1.md
```

Close with exact escaping/URL policy, exact commands/results, and whether
frame-ui duplicated helpers were left as follow-up.

## Closing Report - 2026-06-27

Live path note: the card's older `server/igniter-render-html` anchor is currently
`frame-ui/igniter-render-html`; verification and tests were run there.

Changed:

- `frame-ui/igniter-render-html/src/lib.rs`
  - `safe_url` now rejects ASCII control characters before scheme parsing.
  - `safe_url` now rejects protocol-relative URLs (`//host`) fail-closed.
  - Existing relative / `http` / `https` behavior remains intact.
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
  - Added link-node coverage for `java\nscript:`, `java\tscript:`,
    C0-prefixed `javascript:`, and `//evil.example/x`.
  - Added link `href` attribute coverage for both `"` and `'` escaping.
- `lab-docs/lang/lab-igniter-web-render-html-output-safety-p1.md`
  - Captures exact policy, command results, and duplicated helper follow-up.

Verification:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-render-html
cargo test -- --nocapture
```

Result: 5 unit tests passed, 14 integration tests passed, 0 doc tests.

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git diff --check
```

Result: passed.

Frame-ui duplicated helpers:

- `frame-ui/igniter-gui/src/lib.rs`
- `frame-ui/igniter-ui-kit/src/lib.rs`

These still have SVG-oriented `esc` helpers that escape only `&`, `<`, and `>`.
They were intentionally left as follow-up because the current worktree already
has unrelated frame-ui activity and this card can close safely at the render-html
output boundary.
