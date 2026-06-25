# LAB-DISTRIBUTION-DEVOPS-DEPLOY-READINESS-P31 - research the Igniter deploy ladder

Status: CLOSED (2026-06-25) — deploy-ladder packet; next rung = `igniter app release` (local symlink, no service control); next card = P32; packet at lab-docs/lang/lab-distribution-devops-deploy-readiness-p31-v0.md
Lane: distribution / devops / deploy
Type: readiness / research
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Igniter has a real control-center foundation:

- `igniter serve`, `check`, `doctor`, `toolchain`, `package`, `app bundle`.
- `igniter-agent` MCP with structured tool envelopes.
- App bundle assembly with loopback run/check/systemd example and manifest.
- Host config boundary for DB/effects.
- Home-lab precedents for tbackend tarballs, `.deb`, loopback systemd bundles, and devices.

The risk is jumping straight to `igniter deploy` and accidentally mixing app assembly, host authority,
secrets, public exposure, service management, DB migrations, and remote transport.

## Goal

Produce a strong research/readiness packet for the Igniter deploy ladder: what "deploy" could mean, which
rungs are safe next, and which stay host/operator-owned.

This is not an implementation card.

## Verify First

Read live distribution/app surfaces:

- `lab-docs/lang/lab-distribution-implemented-surface-v0.md`
- `lab-docs/lang/lab-distribution-ecosystem-readiness-p1-v0.md`
- `lab-docs/lang/lab-distribution-app-bundle-readiness-p13-v0.md`
- `bin/igniter`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`

Read home-lab precedent, but treat it as evidence, not authority:

- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/artifacts/tbackend`
- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/deploy`
- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/docs/inventory`

External research is allowed if useful, but keep it comparative and bounded:

- Rails/Kamal
- systemd user services
- Docker Compose
- Heroku/Fly/Render style release models
- Nix/direnv/devenv

## Questions To Answer

1. What are the deploy rungs for Igniter?
   - local run
   - app bundle
   - local release directory + `current` symlink
   - systemd user service
   - Docker/Compose
   - remote host copy/admit
   - public ingress/TLS
2. Which rungs are already proven, and by what exact artifacts?
3. What is the first deploy-like rung that is safe to implement after app bundle?
4. Should `igniter deploy` exist in v0, or should it stay `igniter app release/check` until authority is clear?
5. Where do host-owned secrets, DSNs, TLS certs, reverse proxy config, and DB migrations live?
6. How should rollback work?
   - symlink swap?
   - bundle manifest admission?
   - host-owned systemctl restart?
7. How should `igniter-agent` expose deploy-adjacent operations through MCP without becoming a remote deploy
   bot?
8. What do we learn from Kamal/Heroku/Fly/systemd without copying their authority model?
9. What is the minimum production-hygiene prerequisite list before any real deploy command?
10. What exact follow-up cards should be opened?

## Alternatives To Compare

Compare at least seven:

- A. No deploy command; app bundle only.
- B. `igniter app release` local symlink manager (no service install).
- C. `igniter app systemd-template` / `systemd check` only.
- D. `igniter deploy local` that swaps `current` and restarts a user service.
- E. Docker/Compose generation.
- F. remote rsync/scp deploy.
- G. package-admit remote node flow (`.igpkg` / app bundle admission).
- H. Kamal-like SSH orchestrator.
- I. managed host/platform model.

## Acceptance

- [x] Readiness packet written (`lab-docs/lang/lab-distribution-devops-deploy-readiness-p31-v0.md`).
- [x] ≥7 alternatives compared (A–I).
- [x] Home-lab evidence summarized with exact paths (artifacts/tbackend/p3+p4; deploy/ Model B; docs/inventory).
- [x] App-bundle guarantees + non-guarantees listed.
- [x] Deploy ladder (rungs 0–6) with authority boundaries proposed.
- [x] Exactly one next card recommended — `LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32` (already
      drafted; the lane's readiness-before-impl cadence yields the implementation card from it).
- [x] MCP/agent safety boundary explicit (read-only dry-run/status only; no service/remote mutation tool).
- [x] No code changes; `git diff --check` clean.

## Reporting

1. **Next rung:** `igniter app release` — local versioned `releases/<v>/` + atomic `current` symlink swap,
   prints (never runs) the host `systemctl restart`. `igniter deploy` stays OUT of v0.
2. **Host-owned:** systemd enable/restart, secrets/DSNs/TLS, public bind, DB migrations, remote transport,
   Docker — igniter emits templates + printed next-steps only.
3. **Most useful external model:** systemd user services (unit + release-dir/`current` symlink shape);
   Kamal/Heroku contributed immutable-release + instant rollback.
4. **Rejected:** `igniter deploy local` restarting a service (D) and remote/Kamal/Docker rungs (F/H/E) —
   they cross from local assembly into service/remote/transport authority.
5. **Next card:** `LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32` (contract: atomic symlink swap,
   rollback by re-point, prints-not-runs systemd, zero new authority).

## Closed Surfaces

No deploy/apply. No remote host mutation. No systemd install/enable. No public bind. No TLS/reverse proxy.
No DB migration. No Docker image generation. No secrets. No registry/signing changes.
