# lab-distribution-devops-deploy-readiness-p31-v0 — the Igniter deploy ladder

Card: `LAB-DISTRIBUTION-DEVOPS-DEPLOY-READINESS-P31`
Status: CLOSED (2026-06-25)
Authority: lab readiness/research — a recommendation, not a deploy. Closed surfaces honored: no code, no
deploy/apply, no remote host mutation, no systemd install/enable, no public bind, no TLS, no DB migration,
no Docker image, no secrets, no registry/signing.

## Verify-first basis (live, cited)

**Control center (`bin/igniter` dispatch):** `serve`, `check`, `doctor`, `toolchain {list,install,update}`,
`package {lock,verify,verify-archive,graph,pack,admit}`, `app bundle`, `agent`. All shell-delegate to owners;
the wrapper grants no authority.

**App bundle (P14/P16), the rung we build on — guarantees:** `igniter app bundle <app> --out <dir>
--version <v>` assembles `<out>/<app>-<v>/` = `{bin/igweb-serve (copied, sha256-pinned), app/<app>/…,
run/run-<app>.sh, checks/check.sh, systemd/<app>.service.example (TEMPLATE), host.toml.example?,
manifest.json}`. Fail-closed: real `host.toml`, inline secrets, missing `--version`, non-loopback mode, or a
failing `igweb-serve check` all refuse with **no partial bundle**. `manifest.json` carries
`bind_policy:"loopback"`, `public_release:false`, runner sha, app-source hashes, `requires_machine`.
**Non-guarantees:** it does NOT install systemd, enable/restart services, swap a `current` symlink, bind
public, create a DB, ship secrets, or copy to a remote host.

**Host-config boundary** (`server/igniter-web/src/host_config.rs`, RUNBOOK): `host.toml` holds env-var
**NAMES** only (`dsn_env`, `passport_env`, …); the runner fails `[CONFIG_RESOLVE]` (exit 3) **before binding**
if a named env var is unset, and **never echoes the value**. `todo_postgres_app/RUNBOOK.md` is explicit:
loopback-only, local Postgres only, **NOT production**; DSN/token are exported into the environment, never
committed.

**Home-lab precedent (evidence, NOT authority)** — exact paths:
- `igniter-home-lab/artifacts/tbackend/p3/` — native tarballs (`x86_64`+`aarch64`), `manifest.json` +
  `SHA256SUMS` + on-target loopback smoke, `public_release:false`.
- `igniter-home-lab/artifacts/tbackend/p4/` — `.deb` (`amd64`+`arm64`): payload `/usr/bin/tbackend` +
  `/etc/tbackend/…conffile` + `/var/lib` + `/var/log` + `/lib/systemd/system/tbackend.service`; `dpkg-deb`
  structure + `systemd-analyze verify` validated.
- `igniter-home-lab/deploy/` — `igniter-stack-deployment-models.md` (7 shapes; **Model B "release bundle +
  systemd"** recommended), `pi5-lab/*` (run script + `.service` + check), `hp-*-docker-readiness.md`
  (Docker/Compose = readiness only). Lifecycle: `…/releases/<UTC-stamp>/` + `…/current/<app>` symlink;
  rollback = symlink swap + `daemon-reload` + restart, all **host** actions.
- `igniter-home-lab/docs/inventory/` — `ai-main-lab` (x86_64), `pi5-lab`/`pi5-lab2` (aarch64).

**In-flight neighbors:** `LAB-DISTRIBUTION-APP-BUNDLE-MACHINE-MODE-P29` (host-config-ready run scripts) and
`LAB-DISTRIBUTION-IGNITER-ENV-READINESS-P30` (env surface) are OPEN; `LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-
READINESS-P32` is already drafted as this card's successor.

## The Igniter deploy ladder

| # | Rung | Proven? (by) | Owner |
|---|---|---|---|
| 0 | **local run** `igniter serve` (loopback, bounded) | ✅ P2/P16, wrapper smoke | igniter (bounded, loopback-refusal in igweb-serve) |
| 1 | **app bundle** `igniter app bundle` (assembly only) | ✅ P14; run-proven P16 | igniter (assembly) |
| 2 | **local app release** versioned `releases/<v>/` + `current` symlink | ⚠️ home-lab **manual** (P14 on pi5-lab); NOT in `igniter` | *candidate next rung* (local FS only) |
| 3 | **systemd user service** | ⚠️ home-lab manual (pi5-lab); igniter emits only a `*.service.example` **template** | **host** (install/enable/restart) |
| 4 | **Docker / Compose** | ❌ sketched only (`deploy/hp-*-docker-readiness.md`) | host |
| 5 | **remote host copy / admit** (`.igpkg` admit exists via `igc`; app-bundle remote copy does not) | ❌ not built | host + future package channel |
| 6 | **public ingress / TLS / reverse proxy** | ❌ not built | host |

## Alternatives compared (≥7)

| | Option | Verdict |
|---|---|---|
| **A** | No deploy command; app bundle only | Too little — leaves the proven rung-2 (release dir + symlink) as undocumented manual work. |
| **B** | **`igniter app release`** — local versioned `releases/<v>/` + atomic `current` symlink swap; NO service control | **★ Recommended next rung.** Local, filesystem-only, reversible; mirrors the home-lab Model B lifecycle; keeps systemd/restart host-owned. |
| **C** | `igniter app systemd-template` / `systemd check` only | Mostly already done — app bundle emits `*.service.example`; a `systemd check` (lint the unit, no install) could fold into B/P32, not its own rung. |
| **D** | `igniter deploy local` that swaps `current` AND restarts a user service | **Reject for v0.** Restarting/`daemon-reload` is systemd/service authority; crosses the assembly→operation line. The restart stays a host action B only *prints*. |
| **E** | Docker/Compose generation | Defer — readiness only in home-lab; adds a container authority surface. |
| **F** | remote rsync/scp deploy | **Reject** — remote host mutation + transport authority; explicitly closed. |
| **G** | package-admit remote node flow (`.igpkg`/bundle admission) | Defer — `igc package admit` exists for `.igpkg`, but app-bundle remote admission is a separate trust surface; after B. |
| **H** | Kamal-like SSH orchestrator | **Reject for v0** — SSH + remote service control + registry; far past the next safe rung. |
| **I** | managed host/platform model | **Reject** — not a lab concern; maximal authority. |

## Recommendation

**Next rung = B: `igniter app release` (local release-directory + `current` symlink manager).**
`igniter deploy` should **NOT** exist in v0 — keep the vocabulary at `igniter app bundle` (assembly) +
`igniter app release` (local activation convention). `app release` would:
- take a produced bundle, place/copy it into `<root>/releases/<version>/` (no rebuild),
- atomically repoint `<root>/current` → that release,
- **print** the host-owned activation step (`systemctl --user restart <unit>`) — never execute it,
- never install/enable systemd, never bind, never touch secrets/DB/remote hosts.

This is the smallest deploy-*like* step, is fully local + reversible, and matches the only deploy lifecycle
the home lab has actually proven (versioned dir + symlink, P14 on pi5-lab).

**What stays host-owned:** `systemctl enable/restart` + `daemon-reload`; the real `host.toml` + all secrets/
DSNs/tokens (env, never bundled); TLS certs + reverse proxy; public bind; DB creation/migration; remote
transport; Docker. `igniter` emits *templates and printed next-steps* for these, never performs them.

**Rollback model:** re-point `current` to a prior `releases/<v>/` (symlink swap — local, instant,
reversible); the host then restarts the service. No bundle is mutated in place; `manifest.json` sha/version
make each release identifiable. (Manifest-admission-based rollback is a later, remote concern.)

**MCP / agent safety:** `igniter-agent` may expose `app release` **dry-run / status** at most (what `current`
points at, which releases exist) — read-only, secret-free, like the existing P28 envelopes. It must **not**
get a tool that restarts services, swaps `current` on a remote, or binds publicly. Any release *mutation*
tool stays a deliberate, separately-authorized step — an agent that can "release" must not silently become a
deploy bot.

## External models — what we borrow, what we refuse

- **systemd user services** (most useful): the bundle already emits a `*.service.example`; the
  release-dir + `current` symlink + `WantedBy=default.target` shape is directly borrowed. We refuse to *run*
  `systemctl` — the unit is host-installed.
- **Kamal / Heroku / Fly**: borrow the *immutable versioned release + instant rollback* idea (our
  `releases/<v>/` + `current`); refuse their authority model (SSH orchestration, remote registries, managed
  builders, app-platform secrets stores).
- **Nix/direnv/devenv**: borrow the env-name-not-value discipline (already in `host.toml`); refuse becoming
  an environment manager (that's the separate P30 `igniter env` question).

## Minimum production-hygiene prerequisites (before ANY real deploy command)

1. Machine-mode run scripts that wire `--host-config` cleanly (P29).
2. A coherent env surface — required env-var names, presence/empty checks, values never printed (P30).
3. Release identity: stable `manifest.json` version + runner sha (have, P14).
4. A documented, host-owned secret path (RUNBOOK pattern; never bundled).
5. Loopback-only default everywhere; public bind an explicit, separate, host-authorized surface.
6. Reversible-by-construction activation (symlink swap, no in-place mutation).

## Next card (one)

**`LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32`** (already drafted) — scope `igniter app release`
(rung B): the local `releases/<version>/` + `current` symlink contract and its bounded acceptance
(atomic swap, rollback by re-point, prints-but-never-runs `systemctl`, no service/secret/remote authority).
P32 then yields the bounded implementation card. (The lane's readiness-before-implementation cadence —
P13→P14, P23→P24 — is preserved.)

## Acceptance trace

- [x] Readiness packet written (`lab-docs/lang/lab-distribution-devops-deploy-readiness-p31-v0.md`).
- [x] ≥7 alternatives compared (A–I).
- [x] Home-lab evidence summarized with exact paths (artifacts/tbackend/p3,p4; deploy; docs/inventory).
- [x] App-bundle guarantees + non-guarantees listed.
- [x] Deploy ladder proposed with rung names + authority boundaries.
- [x] Exactly one next card recommended (P32, drafted).
- [x] MCP/agent safety boundary explicit (read-only dry-run/status only).
- [x] No code changes.

## Reporting

1. **Recommended next rung:** B — `igniter app release` (local versioned releases + `current` symlink; no
   service control). `igniter deploy` stays out of v0.
2. **Host-owned:** systemd enable/restart, secrets/DSNs/TLS, public bind, DB migrations, remote transport,
   Docker — igniter emits templates + printed next-steps only.
3. **Most useful external model:** systemd user services (directly shapes the unit + release-dir/symlink);
   Kamal/Heroku contributed the immutable-release + instant-rollback idea.
4. **Rejected shape:** `igniter deploy local` that restarts a service (D) and any remote/Kamal/Docker rung
   (F/H/E) — they cross from local assembly into service/remote/transport authority.
5. **Next card:** `LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32` — define the `igniter app release`
   local contract (atomic symlink swap, rollback by re-point, prints-not-runs systemd, zero new authority),
   yielding the implementation card.
