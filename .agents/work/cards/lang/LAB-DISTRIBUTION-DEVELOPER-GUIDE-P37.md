# LAB-DISTRIBUTION-DEVELOPER-GUIDE-P37

Status: CLOSED (2026-06-25) — developer guide at lab-docs/lang/igniter-control-center-dev-guide-v0.md (7 sections, placeholder env only); front-door link added; leak rg clean
Route: standard / developer guide
Skill: idd-agent-protocol

## Goal

Write the first practical developer guide for the `igniter` control-center DX: from source checkout
to `serve`, `check`, `doctor`, env inspection, app bundle, and local admission. This should help a
new agent or human run the lab stack without spelunking through old proof cards.

## Current Authority

- Live behavior: `bin/igniter`, `bin/igniter-install`, `server/igniter-web/README.md`,
  `server/igniter-web/IMPLEMENTED_SURFACE.md`, and the P33-P35 tests.
- Existing front door: `lab-docs/lang/lab-distribution-implemented-surface-v0.md`.
- This guide is educational DX, not a stability promise and not new authority.

## Deliverable

Create or update a single guide. Recommended path:

`lab-docs/lang/igniter-control-center-dev-guide-v0.md`

Keep it concise and command-oriented. It should answer:

1. What is `bin/igniter`?
   - A thin control-center/router, not a new runtime authority.
2. How do I run a pure app?
   - `igniter check <app_dir>`
   - `igniter serve <app_dir> --addr 127.0.0.1:PORT --max-requests N`
3. How do I run a machine/Postgres-shaped app safely?
   - start from committed `host.example.toml`;
   - inspect required env with `igniter env doctor`;
   - generate a blank shell template with `igniter env template`;
   - gate with `igniter env check`;
   - run with `igniter serve ... --host-config ...`;
   - never commit `.env` / DSN / bearer token.
4. How do I ask the agent MCP server for the same env checks?
   - mention `igniter-agent` exposes `env_doctor` and `env_check`;
   - JSON envelope, names-only.
5. How do I create and admit a local bundle?
   - `igniter app bundle ... --out ... --version ...`;
   - `igniter app admit <bundle> --release-root <root>`;
   - explain that admit validates/copies only.
6. How do I check the toolchain?
   - `igniter doctor`
   - `igniter toolchain list`
   - `igniter toolchain install|update [--with-repl]`
7. Where do I look when docs disagree?
   - implemented-surface docs and live source win over older packets.

## Boundary

Allowed:

- Add one guide doc.
- Add short links from `README.md`, `server/igniter-web/README.md`, or
  `lab-docs/lang/lab-distribution-implemented-surface-v0.md` if that improves discoverability.

Closed:

- No code changes.
- No promises of public release, registry, semver, remote install, signing, deployment, TLS, systemd
  enablement, DB creation/migration, production readiness, or stable CLI compatibility.
- Do not include real secrets, real DSNs, or private host paths.

## Guide Style

- Prefer copy-pasteable commands.
- Mark commands that are DB-free vs require local Postgres.
- Use placeholder env values only: `export NAME=`.
- Keep boundaries explicit: "what this does" vs "what this does not do".
- Avoid long history. Link the implemented-surface doc for details.

## Verification / Evidence

Run:

```bash
rg -n "IGNITER_.*=.+(postgres|token|password|secret)|sparkcrm|production" \
  lab-docs/lang/igniter-control-center-dev-guide-v0.md

rg -n "igniter env doctor|igniter env check|igniter app admit|igniter serve|igniter doctor" \
  lab-docs/lang/igniter-control-center-dev-guide-v0.md

git diff --check
```

If README links are touched, run a quick link/path sanity check with `test -f` for each local target.

## Acceptance

- [x] Concise developer guide exists: `lab-docs/lang/igniter-control-center-dev-guide-v0.md` (7 sections,
      copy-pasteable, DB-free vs requires-Postgres marked).
- [x] Covers pure app (check/serve), machine app (env doctor/template/check + `--host-config`), MCP env tools
      (`env_doctor`/`env_check`, P28 envelope, names-only), app bundle + admit, doctor/toolchain, and the
      "current-truth docs win" pointer.
- [x] No real secrets/DSNs/private instructions — placeholder `export NAME=` only; leak rg
      (`IGNITER_.*=.+(postgres|token|password|secret)|sparkcrm|production`) returns **EMPTY**.
- [x] Admission kept separate from deploy: §5 states `admit` is validate+copy ONLY (no `current`/systemd/
      bind/run); §"What this does NOT do" reiterates.
- [x] `git diff --check` clean.

## Reporting

- **Guide path:** `lab-docs/lang/igniter-control-center-dev-guide-v0.md`.
- **Links added:** one discoverability line at the top of
  `lab-docs/lang/lab-distribution-implemented-surface-v0.md` → the guide (verified the target file exists).
  No README files were touched.
- **Grep evidence (no leak):** `rg "IGNITER_.*=.+(postgres|token|password|secret)|sparkcrm|production"` over
  the guide → **no matches** (placeholder env comments were reworded to avoid trigger words after `=`; "never
  a production one" → "live or shared one"). The verb-coverage rg matched 6 occurrences.
- **Intentionally undocumented / deferred:** deploy/activation (current symlink swap, systemd enable, running
  the app), public release / registry / semver / remote install / signing, TLS/reverse proxy, DB
  creation/migration, secret management, `.env` reading, and any stable-CLI-compatibility promise — all
  listed in the guide's closing "What this does NOT do (v0)" section as out of scope.

## Reporting

Close with:

- guide path;
- any README/front-door links added;
- exact grep evidence that secrets/private production claims did not leak;
- what remains intentionally undocumented/deferred.
