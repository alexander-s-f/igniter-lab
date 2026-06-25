# LAB-DISTRIBUTION-IMPLEMENTED-SURFACE-REFRESH-P36

Status: CLOSED (2026-06-25) — front-door doc refreshed for P33/P34/P35 (env doctor/template/check, agent env_*, app admit); stale reserved/deferred phrasing only survives inside the Superseded section
Route: standard / doc hygiene
Skill: idd-agent-protocol

## Goal

Refresh the distribution/control-center implemented-surface front door after P33-P35 so agents no
longer treat `igniter env ...`, `igniter-agent` env tools, or `igniter app admit` as deferred.

## Current Authority

- Behavior authority: live `bin/igniter`, `server/igniter-web/src/bin/igniter-agent.rs`, and the
  current smoke tests.
- Documentation authority to update: `lab-docs/lang/lab-distribution-implemented-surface-v0.md`.
- Historical cards/proof docs are evidence only. If an old packet says "reserved", "deferred", or
  "placeholder" but live code disagrees, the implemented-surface doc must win.

## Verify First

Read these before editing prose:

- `bin/igniter`
- `server/igniter-web/src/bin/igniter-agent.rs`
- `server/igniter-web/tests/igniter_env_smoke_tests.rs`
- `server/igniter-web/tests/igniter_agent_mcp_smoke_tests.rs`
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`
- current cards:
  - `LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33`
  - `LAB-DISTRIBUTION-IGNITER-ENV-CHECK-AND-AGENT-P34`
  - `LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35`

## Required Updates

Update `lab-docs/lang/lab-distribution-implemented-surface-v0.md` to include, precisely:

1. `igniter env doctor <path>` is live:
   - reads `host.example.toml` / `host.toml.example` style catalogues;
   - reports env **names** and set/unset/empty status;
   - never reads `.env`;
   - never prints values.
2. `igniter env template <path>` is live:
   - emits blank `export NAME=` lines with context comments;
   - never prints values.
3. `igniter env check <path>` is live:
   - exit 0 when all required env vars are set and non-empty;
   - exit 1 when any required env var is unset/empty;
   - exit 2 for invalid usage/catalogue;
   - pure apps with no machine env pass.
4. `igniter-agent` MCP tools `env_doctor` and `env_check` are live:
   - P28-style JSON envelope;
   - same names-only/no-value discipline;
   - missing path returns a clean tool-argument error.
5. `igniter app admit <bundle_dir> --release-root <dir>` is live:
   - validates and copies a bundle into `releases/<app>/<version>`;
   - source bundle is not moved;
   - no `current` symlink, no systemd install, no deploy;
   - list the v0 gates accurately: manifest parse, format v1, loopback, private release, runner
     hash, source hashes, `checks/check.sh`, no real `host.toml`, machine bundle has
     `host.toml.example`, duplicate destination refused.
6. Add/refresh "Superseded phrasings" for older docs that still frame env/admit as future work.

## Boundary

Allowed:

- Edit the distribution implemented-surface doc.
- Add short supersession notes inside this card's closing report if helpful.

Closed:

- No code changes.
- No new CLI behavior.
- Do not rewrite old readiness packets except for one-line supersession notes only if necessary.
- Do not claim remote installation, package registry, semver, signing, public deploy, current
  symlink swap, systemd enablement, or secret management.

## Verification / Evidence

Run from `igniter-lab` / `server/igniter-web` as appropriate:

```bash
rg -n "igniter env|env_doctor|env_check|app admit|reserved|deferred|placeholder" \
  lab-docs/lang/lab-distribution-implemented-surface-v0.md \
  server/igniter-web/README.md \
  README.md

cargo test --test igniter_env_smoke_tests
cargo test --test igniter_agent_mcp_smoke_tests
cargo test --test igniter_app_bundle_smoke_tests
git diff --check
```

## Acceptance

- [x] Implemented-surface doc names P33/P34/P35 commands as live (table rows + precise sections for env, app
      admit, agent).
- [x] App-admit section says "validate + copy ONLY", lists all 10 gates, and keeps activation
      (current symlink / systemd / deploy / run) closed.
- [x] Env section says env-var NAMES only, **no `.env` reading, no value reading/printing, no injection**.
- [x] Agent `env_doctor`/`env_check` listed as live with the P28 envelope (`parsed = {path, required_env, ok}`,
      never values).
- [x] Stale "reserved/deferred/placeholder" survives ONLY inside the Superseded section (verified by rg;
      lines 119/120/134 are the historical-stale table + the P33/34/35 supersession note).
- [x] Verification passes: `git diff --check` clean; agent **19/19**, app_bundle **12/12**, env **7/7**.

## Reporting

1. **Changed files:** `lab-docs/lang/lab-distribution-implemented-surface-v0.md` only (docs; no code).
2. **Command results:** rg → "reserved/deferred/placeholder" only inside the Superseded section;
   `git diff --check` clean; `igniter_agent_mcp_smoke_tests` 19/19, `igniter_app_bundle_smoke_tests` 12/12,
   `igniter_env_smoke_tests` 7/7.
3. **Stale claims fixed:** added live table rows + precise-status sections for `igniter app admit` (P35,
   10-gate validate+copy), `igniter env doctor|template|check` (P33/P34, names-only/no-`.env`), and `igniter
   agent` (P23–P28/P34, incl. `env_doctor`/`env_check`); header range P1–P17 → P1–P35; closed-surfaces split
   so admit-is-live-but-activation-closed and env-is-names-only are explicit; added a "Superseded by
   P33/P34/P35" note so the env/admit readiness packets read as history.
4. **Surfaces intentionally still closed:** activation (`current` symlink swap, systemd install/enable,
   deploy, running the app), `.env` reading / env value printing / injection / secret management, and
   remote download/registry/semver/signing/public bind.

## Reporting

Close this card with:

- changed files;
- exact command results;
- stale claims fixed;
- surfaces intentionally still closed.
