# LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35 - admit app bundles into a local release root

Status: CLOSED (2026-06-25) — `igniter app admit` live (10 gates, atomic copy into releases/<app>/<version>, no current); app-bundle 12/12
Lane: distribution / app release lifecycle
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14`
- `LAB-DISTRIBUTION-APP-BUNDLE-RUN-SMOKE-P16`
- `LAB-DISTRIBUTION-APP-BUNDLE-MACHINE-MODE-P29`
- `LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32`

P32 decided the next safe release-lifecycle rung:

```text
igniter app admit <bundle_dir> --release-root <dir>
```

Admission is **validate + copy into a release root**. It is not deploy. It does not touch `current`,
systemd, network exposure, secrets, DBs, Docker, or remote hosts.

## Goal

Implement:

```text
igniter app admit <bundle_dir> --release-root <dir>
```

Result:

```text
<release-root>/
  releases/<app>/<version>/...   # copied admitted release
```

No `current` symlink is created or changed in this card.

## Verify First

Read:

- `lab-docs/lang/lab-distribution-app-release-lifecycle-readiness-p32-v0.md`
- `.agents/work/cards/lang/LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32.md`
- `bin/igniter` app bundle implementation
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`
- package admit docs/cards only for discipline, not direct command reuse

Confirm:

- Bundle manifests contain runner sha, app source hashes, bind policy, app, version.
- `checks/check.sh` passes inside a bundle.
- P29 machine-mode bundle still carries only `host.toml.example`, not real `host.toml`.

## Required Behavior

Command:

```text
igniter app admit <bundle_dir> --release-root <dir>
```

Admission gates:

1. `manifest.json` parses.
2. `bundle_format_version == "1"`.
3. `bind_policy == "loopback"`.
4. `public_release == false`.
5. Re-hash `bin/igweb-serve`; it must equal `manifest.runner.sha256`.
6. Re-hash every `app_sources[]` entry; each file must exist and match.
7. `checks/check.sh` passes inside the bundle.
8. Bundle must not contain a real `host.toml`.
9. If `requires_machine == true`, bundle must contain `host.toml.example`.
10. Destination `<release-root>/releases/<app>/<version>` must not already exist.

Copy semantics:

- Copy the bundle into the destination release dir.
- Do not move or symlink the source bundle.
- Copy into a temporary staging dir and atomically rename into place.
- On refusal/failure, leave no partial release.

Output:

- On success, print a concise receipt:
  - app
  - version
  - admitted path
  - runner sha
  - `requires_machine`
  - next host-owned step: "activation/current/service restart are not performed"
- On failure, name the failing gate without leaking secrets.

CLI:

- `igniter app --help` should include `admit`.
- Unknown app subcommands still fail closed.

## Acceptance

- [x] Admit a pure `todo_app` bundle into a temp release root (receipt: app/version/admitted_path/runner_sha/requires_machine/next-note).
- [x] Result path is `<root>/releases/todo_app/V1` with copied bundle files (bin/app/run/checks/systemd/manifest).
- [x] Source bundle remains intact (cp, never moved/symlinked).
- [x] No `current` symlink created or modified (asserted).
- [x] Re-hash runner (gate 5) + every app source (gate 6); tamper of either is refused.
- [x] Tampered/refused admit leaves no partial release (gates run on source before staging; atomic rename).
- [x] Real `host.toml` in a bundle refused (gate 8).
- [x] Machine-mode `todo_postgres_app` admits with `host.toml.example`, no real `host.toml`.
- [x] Duplicate admit to an existing release path refused (gate 10; no `--force` added).
- [x] Existing tests green: app-bundle 12/12 (incl 5 admit), agent 16/16, serve_wrapper 17/17.
- [x] `bash -n bin/igniter` + `git diff --check` clean.

## Reporting

1. **Destination layout:** `<release-root>/releases/<app>/<version>/` holding the full copied bundle
   (`bin/igweb-serve`, `app/<app>/…`, `run/`, `checks/`, `systemd/…example`, `manifest.json`, and
   `host.toml.example` for machine-mode). No `current`, no symlink.
2. **Admission gates (all 10, fail-closed):** (1) manifest.json parses (app/version/runner.sha present);
   (2) `bundle_format_version=="1"`; (3) `bind_policy=="loopback"`; (4) `public_release==false`;
   (5) re-hash `bin/igweb-serve` == `manifest.runner.sha256`; (6) re-hash every `app_sources[]` (exists +
   matches); (7) `checks/check.sh` passes (opens no socket/DB); (8) no real `host.toml`; (9)
   `requires_machine ⇒ host.toml.example`; (10) destination must not already exist. Manifest is read with a
   narrow grep/sed parse (the manifest is emitted by this same tool) — no JSON dependency added.
3. **`current` untouched:** admit never creates/modifies a `current` symlink; activation/restart/exposure
   stay host-owned (the receipt says so explicitly).
4. **Negative/tamper tests:** gate 5 (appended bytes to runner → refused), gate 6 (appended to an app
   source → refused), gate 8 (real `host.toml` added → refused), gate 10 (second admit → refused). Each
   leaves no `releases/<app>/<version>` behind.
5. **Test counts:** `igniter_app_bundle_smoke_tests` **12/12** (5 new admit tests),
   `igniter_agent_mcp_smoke_tests` **16/16**, `igniter_serve_wrapper_smoke_tests` **17/17**.

Implementation: `bin/igniter` — `app_admit` + `mjson_str`/`mjson_bool`/`mjson_runner_sha` readers + `app
admit` dispatch + `app --help` admit section. Copy is staged WITHIN the release root (same filesystem →
atomic `mv`). Tests in `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`.

## Closed Surfaces

No `current` symlink. No rollback. No systemd install/restart. No deploy/apply. No public bind. No TLS /
reverse proxy. No DB creation/migration. No Docker. No remote copy. No secrets or real `host.toml` in
admitted releases.
