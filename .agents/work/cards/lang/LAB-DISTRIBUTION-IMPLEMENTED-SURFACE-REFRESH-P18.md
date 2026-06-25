# LAB-DISTRIBUTION-IMPLEMENTED-SURFACE-REFRESH-P18 - remove stale distribution claims

Status: CLOSED (2026-06-25) — front-door surface doc created; 3 stale packets given supersession notes
Lane: distribution / hygiene
Type: docs hygiene
Date: 2026-06-25

## Context

The distribution surface moved quickly:

- `igniter app bundle` is now implemented (P14).
- `igniter-repl` release build is recovered, but fleet inclusion is still pending.
- `igniter package ...` and `igniter toolchain install|update` are live delegations.

Older readiness/proof docs still contain stale phrases like:

- `igniter app bundle` deferred / placeholder;
- `igniter-repl` build-broken;
- `app bundle stays in release-bundle/systemd scripts`;
- install fleet excludes repl specifically because it cannot build.

These old docs are evidence, not current authority, but agents keep reading them during verify-first. We need
a narrow distribution surface refresh that points readers to current truth without rewriting history.

## Goal

Update the distribution implemented-surface/front-door docs so agents can quickly answer:

1. What distribution commands are live today?
2. What is still deliberately excluded?
3. Which old proof docs are superseded and by what?

## Verify First

- Read live:
  - `bin/igniter`
  - `bin/igniter-install`
  - relevant wrapper tests under `server/igniter-web/tests/`
  - `LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14`
  - `LAB-MACHINE-REPL-ASYNC-RESUME-FIX-P1`
- Search `lab-docs/lang` and `.agents/work/cards/lang` for:
  - `build-broken`
  - `build fails`
  - `app bundle` + `deferred`
  - `fail-closed placeholder`
- Decide which docs should be edited and which should remain historical.

## Required Behavior

Prefer one current front-door doc over editing every old packet. If no distribution implemented-surface doc
exists, create one under `lab-docs/lang/` with a stable name, for example:

```text
lab-docs/lang/lab-distribution-implemented-surface-v0.md
```

It should list:

- `igniter serve`
- `igniter check`
- `igniter doctor`
- `igniter toolchain list/install/update`
- `igniter package lock/verify/verify-archive/graph/pack/admit`
- `igniter app bundle`
- `igniter-repl` status: build recovered, not fleet-included

For older docs, add only small supersession notes where they are likely to mislead active agents. Do not
rewrite historical proof narrative wholesale.

## Acceptance

- [x] Current distribution surface doc **created**: `lab-docs/lang/lab-distribution-implemented-surface-v0.md`.
- [x] Names live commands + owning authority (serve→igweb-serve, check, doctor, toolchain→installer, package→igc, app bundle→orchestration; table).
- [x] Names closed surfaces: registry/download/signing, public bind, systemd install, Docker, secrets, REPL fleet inclusion, root workspace.
- [x] States `igniter-repl` precisely: release build recovered (P1); NOT fleet-included (P17), opt-in, no default-dep change.
- [x] States `igniter app bundle` precisely: implemented (P14), assembly-only, run-proven (P16); host-owned surfaces excluded.
- [x] Stale high-risk packets given one-line supersession notes pointing to the front door: P6 (`app bundle` RESERVED→implemented), P7 (placeholders→live), P13 (design→implemented). Other packets (P11/P12/P17) already describe live truth — left as-is.
- [x] No production code changes — docs only (front door + 3 notes). The stale `build-broken` wrapper/installer text is explicitly routed to the P17 label-hygiene follow-up, NOT edited here (would touch a test-asserted label; out of this hygiene pass).
- [x] `git diff --check` clean.

## Closing report

Created the front-door `lab-distribution-implemented-surface-v0.md` as the single current-truth index for
the distribution lane (live commands + owners, precise repl/app-bundle status, closed surfaces, install
model, and a superseded-phrasings map). Added narrow one-line supersession blockquotes to the 3 packets most
likely to mislead a verify-first agent (P6/P7/P13). Left P11/P12/P17 untouched (already current). Did NOT
edit the `bin/igniter-install` "build-broken" wording or the `bin/igniter` `[blocked]` label — those are
coupled to the `igniter_toolchain_list_names_fleet_and_marks_repl` test assertion and belong to the P17
label-hygiene follow-up; the front-door doc flags them as stale instead. Docs-only; `git diff --check` clean.

## Closed Surfaces

No code feature work. No installer behavior change. No REPL inclusion. No app install/current symlink. No
network/registry/signing. This is a hygiene pass only.

