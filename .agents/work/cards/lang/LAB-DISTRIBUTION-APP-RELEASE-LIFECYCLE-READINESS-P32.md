# LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32 - design bundle admission, release dirs, and rollback

Status: CLOSED (2026-06-25) — recommends B (`igniter app admit` = validate+copy into release root; `current`/rollback deferred); next card = LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35; packet at lab-docs/lang/lab-distribution-app-release-lifecycle-readiness-p32-v0.md
Lane: distribution / app release lifecycle
Type: readiness / research
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

`igniter app bundle` assembles a versioned app directory but deliberately does not install or activate it.
Home-lab proved a stronger host pattern:

```text
releases/<app>/<version>/
current/<app> -> releases/<app>/<version>
systemd user unit points at current/<app>/run/run-<app>.sh
rollback = symlink swap + host-owned restart
```

Before implementing any activation command, we need a precise release lifecycle contract: what is a bundle,
what is an admitted release, what is current, what is rollback, and what is still operator-owned.

## Goal

Produce a readiness packet for a possible next app-bundle command family:

```text
igniter app admit <bundle_dir> --release-root <dir>
igniter app releases <app> --release-root <dir>
igniter app current <app> --release-root <dir>
igniter app rollback <app> --to <version> --release-root <dir>   # maybe future, maybe not v0
```

The packet must decide whether these commands should exist, and if yes, which one is the smallest safe
implementation after P29/P31.

## Verify First

Read:

- `bin/igniter` app bundle implementation.
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`.
- `lab-docs/lang/lab-distribution-app-bundle-readiness-p13-v0.md`.
- `lab-docs/lang/lab-distribution-ecosystem-readiness-p1-v0.md`.
- Home-lab release-bundle precedent:
  `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/deploy/`
- Remote trust/admission precedent:
  `lab-docs/lang/lab-igniter-package-remote-trust-readiness-p22-v0.md`
  and package `admit` docs/cards if relevant.

## Questions To Answer

1. Is "admit a bundle into a release root" conceptually different from "deploy"?
2. What checks must admission run?
   - manifest parses;
   - runner sha matches;
   - app source hashes match;
   - `checks/check.sh` passes;
   - `bind_policy == loopback`;
   - no real `host.toml` or secrets;
   - optional host-config template is safe.
3. Should admission copy, move, hardlink, or symlink a bundle?
4. Should admission create/update `current` or should that be a separate host-owned activation step?
5. How should rollback be represented without restarting anything?
6. Should release lifecycle commands live under `igniter app ...` or `igniter deploy ...`?
7. What does the MCP agent get to do?
   - inspect/admit/check?
   - never activate/restart?
8. What is the relation to package `.igpkg admit`?
9. What exact proof can run locally in temp dirs without systemd or DB?

## Alternatives To Compare

Compare at least five:

- A. Do nothing; keep bundle only.
- B. `app admit` copies a bundle into a release root but does not touch `current`.
- C. `app activate` updates `current` symlink but does not restart anything.
- D. `app rollback` updates `current` to a previous admitted release.
- E. `deploy local` combines admit + activate + systemd restart.
- F. Reuse package `admit` semantics directly.
- G. Keep all lifecycle in host scripts.

## Acceptance

- [x] Readiness packet written (`lab-docs/lang/lab-distribution-app-release-lifecycle-readiness-p32-v0.md`).
- [x] bundle / admitted-release / `current` / active-service vocabulary defined (§Vocabulary).
- [x] ≥5 alternatives compared (A do-nothing / B admit / C activate / D rollback / E deploy-local / F reuse-package-admit / G host-scripts).
- [x] Manifest/hash/check admission gates specified (7 gates: manifest parse, runner-sha, app-source-hashes, check.sh, loopback bind, no-real-host.toml/secrets, no-overwrite).
- [x] Systemd restart + public exposure explicitly kept OUT of v0 (admission = placement only; C/D/E deferred/rejected).
- [x] MCP agent bounded: inspect/admit/check only; never activate/`current`/restart/expose.
- [x] One next impl card named: `LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35` (`app admit`; `current`/rollback explicitly deferred).
- [x] No code changes; `git diff --check` clean.

## Reporting

Report:

1. Recommended vocabulary and command family.
2. Whether `current` symlink is in or out of the first implementation.
3. What safety checks define admission.
4. How this differs from deploy.
5. Next card ID.

## Closed Surfaces

No systemd install/restart. No remote copy. No public bind. No TLS/reverse proxy. No DB migration. No
Docker. No secrets. No real host.toml in bundles. No production deploy.
