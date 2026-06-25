# LAB-DISTRIBUTION-APP-BUNDLE-READINESS-P13 — `igniter app bundle` v0 design (readiness)

> **Now implemented (2026-06-25):** this is the *design*; the command it specifies is **implemented (P14)**
> and run-proven (P16). "NO implementation" below describes the readiness phase, not current state. Live
> surface: [`lab-distribution-implemented-surface-v0.md`](lab-distribution-implemented-surface-v0.md).

Status: readiness packet (design only — NO implementation)
Card: `LAB-DISTRIBUTION-APP-BUNDLE-READINESS-P13`
Date: 2026-06-25
Authority: **recommendation, not a deploy.** Closed surfaces honored — no implementation, no systemd
install, no public bind, no TLS/reverse proxy, no DB creation, no Docker, no secrets in bundle.

Gate inputs read: P6 control-center packet (`app bundle` RESERVED/deferred, assembling-only when built),
P4 installer readiness (Model E = the proven *app-deploy* shape, distinct from tool install), P5
root-workspace readiness (defer workspace; v0 DX = xtask/shell orchestration over per-crate builds), the
home-lab `deploy/igniter-stack-deployment-models.md` (Model B/E) + `deploy/pi5-lab/*`, and the live
`igweb-serve` / `igweb.toml` / `host.example.toml` contracts.

---

## 0. Framing

The target is **"Igniter assembles a versioned app bundle that a host/deploy layer can run"** — NOT "Igniter
installs a daemon". `igniter app bundle` owns **assembly** of `{runner + app dir + run script + checks +
manifest}` and nothing else. Bind/exposure policy, systemd enablement, TLS, DB, and secrets stay
host/operator-owned (the deployment-models app/host split). The command is **orchestration** (P5's
xtask/shell verdict) over the proven per-crate `igweb-serve` build — it adds no resolver, no daemon, no new
authority.

---

## 1. Home-lab precedent (exact boundaries)

**Model B / E — "release bundle + systemd"**, proven active on pi5-lab (P14), smoke on pi5-lab2 (P18). The
deployed bundle shape (`deploy/igniter-stack-deployment-models.md`):

```
artifact/
  bin/igweb-serve                                  # the runner, COPIED into the bundle
  app/<appname>/{igweb.toml, routes.igweb, *.ig}   # author-owned app dir
  run/run-<appname>-loopback.sh                    # loopback runner script (ExecStart target)
  systemd/igweb-<appname>-loopback.service         # unit (referenced by the host, not installed by Igniter)
  checks/check.sh
  manifest.txt
```
Lifecycle: `…/releases/<app>/<UTC-stamp>/` + `…/current/<app>` → symlink; rollback = symlink swap +
`daemon-reload` + restart (a **host** action).

**What it proved:** a self-contained `{runner + app + run + checks + unit}` directory runs an IgWeb app on
loopback under systemd, with versioned rollback. **What it did NOT prove / left host-owned:** the
`systemctl enable`, the `current` symlink swap, bind exposure, TLS, DB, and any secret. The runner script
reads `IGNITER_<APP>_PORT` / `IGNITER_<APP>_MAX_REQUESTS` / `IGNITER_<APP>_LOG_DIR`; the unit carries only
`Environment=` var NAMES; **no secret lives in the bundle**.

The `deploy/pi5-lab` check script (`check_bundle`) is the precedent gate: runner is `-x`, `igweb.toml`
present, `routes.igweb` present, and `igweb-serve check <app_dir>` passes — then a loopback-only smoke.

---

## 2. Q1 — Files in an Igniter app bundle v0

Generalize Model B to a stable, app-agnostic layout. `<version>` is a caller-supplied stamp (no clock in
the tool itself — provenance time is passed in, mirroring the home-lab UTC-stamp dir):

```
<appname>-<version>/
  bin/igweb-serve                  # COPIED runner, sha256-pinned in the manifest (see Q2)
  app/<appname>/                   # author-owned, verbatim: igweb.toml + routes.igweb + *.ig (+ *.igweb)
  run/run-<appname>.sh             # loopback runner script: igweb-serve --addr 127.0.0.1:$PORT
                                   #   --max-requests $N  app/<appname>   (reads IGNITER_<APP>_* env)
  checks/check.sh                  # the Q5 pre-run gate (re-runnable on the host before first start)
  systemd/<appname>.service.example  # TEMPLATE only — NEVER installed by Igniter (host owns enablement)
  host.toml.example                # ONLY for machine-mode apps; env-NAMES only, commit-safe (Q4)
  manifest.json                    # provenance (Q3)
```

Rules: **no `host.toml`** (only `*.example`), **no secrets**, **no `current` symlink**, **no bind address
baked beyond the loopback default**. For a pure observed (non-machine) app, `host.toml.example` is omitted.

---

## 3. Q2 — Runner: copied, symlinked, or path-referenced?

**COPIED into `bin/igweb-serve`, sha256-pinned in `manifest.json`.**

- **Copied (chosen):** self-contained and portable across hosts; immune to source-checkout drift; enables an
  atomic versioned-dir + symlink rollback. This is exactly what the proven mesh-status bundle does
  (`$release_root/bin/igweb-serve`).
- **Symlink — rejected:** breaks portability (a bundle shipped to another host dangles) and atomic rollback.
- **Path-reference — rejected:** the `run-todo-loopback.sh` dev shortcut references
  `$base/target/release/igweb-serve`; that is the **non-bundle** developer path and drifts with the checkout.

The runner is resolved at bundle time via the P8 staging order (co-located staged → repo target); the
bundle records its `sha256`, `version`, and `target_triple` so a host can verify integrity. (Cross-arch
bundles need a per-target runner — out of v0; v0 bundles the host-arch runner and records the triple.)

---

## 4. Q3 — Manifest / provenance fields (`manifest.json`)

Generalizes the tbackend P3 tarball manifest + the home-lab inline fields (`app`, `entry`, `runner_sha256`,
`bind_policy`, `unit`). All values are non-secret:

```jsonc
{
  "bundle_format_version": "1",
  "tool": "igniter app bundle",
  "app": "<appname>",
  "entry": "<from igweb.toml [app] entry>",
  "created_utc": "<caller-supplied stamp>",      // no clock in the tool (determinism/replay)
  "runner": {
    "path": "bin/igweb-serve",
    "sha256": "<hex>",
    "version": "<igweb-serve --version>",
    "target_triple": "<host triple>",
    "source_git_commit": "<short sha, if available>"
  },
  "app_sources": [                                // every author file, hashed
    { "path": "app/<appname>/igweb.toml",   "sha256": "<hex>" },
    { "path": "app/<appname>/routes.igweb", "sha256": "<hex>" },
    { "path": "app/<appname>/<name>.ig",    "sha256": "<hex>" }
  ],
  "bind_policy": "loopback",                      // declared; enforced by igweb-serve, not the bundle
  "requires_machine": false,                      // true ⇢ host.toml.example present, needs --features machine
  "stdlib_version": "<igc STDLIB_VERSION>",       // compiler-owned constant
  "checks": { "ran": ["check", "manifest", "loopback-only"], "result": "ok" },
  "public_release": false
}
```

Explicitly **absent**: any DSN, password, token, passport, api_key, or host.toml contents.

---

## 5. Q4 — `host.toml.example`, env names, and the secret boundary

- **`host.toml.example` lives in the bundle ONLY for machine-mode apps** (those using `ReadThen` / effects /
  Postgres). It is **commit-safe**: env-var **NAMES** only (`dsn_env`, `passport_env`, …), `[host] mode =
  "loopback"`, and the read/write allowlists — exactly the shape of
  `examples/todo_postgres_app/host.example.toml`. The **real** `host.toml` is **never** bundled; the operator
  authors it on the host and exports the secret values into the environment.
- **Env-name surface in the bundle:** the runner script names `IGNITER_<APP>_PORT`,
  `IGNITER_<APP>_MAX_REQUESTS`, `IGNITER_<APP>_LOG_DIR`; `host.toml.example` names `*_env` keys. **Values
  live in the host environment, never in any bundled file.**
- **Reused gate, not a new one:** `igniter app bundle` reuses the existing `load_host_config` validator,
  which already rejects inline secret keys (`dsn`, `password`, `secret`, `token`, `passport`, `api_key`),
  `*_env` template syntax, and unknown sections/keys. The bundler **refuses to package a file named
  `host.toml`** and refuses any candidate host config that does not pass the secret-rejecting parse → a
  secret can never enter a bundle.

---

## 6. Q5 — Checks `igniter app bundle` runs before emitting

Reuse the live `igweb-serve` validation + the home-lab `check_bundle` gate, run at **bundle time**
(fail-closed — no bundle is written if any fails):

1. **`igweb-serve check <app_dir>`** passes — entry resolves, sources compile, no socket opened
   (reuses `check_app_dir`).
2. **`igweb.toml` present and parses** with author-owned `[app]` fields only; `[server] mode` is `loopback`.
3. **Route/source resolution** is non-empty (the deterministic `*.ig` + `*.igweb` discovery, or the explicit
   `[app] sources`).
4. **Runner present + executable**; record its `sha256`/version/triple.
5. **Secret gate:** any bundled host config must be `*.example` and pass `load_host_config` (no inline
   secrets, no `host.toml`).
6. **Loopback gate:** refuse to emit if the app's `[server] mode` (or any declared bind) is non-loopback.
7. **Self-check copy:** the emitted `checks/check.sh` re-runs 1–4 on the host before first start.

---

## 7. Q6 — How the bundle preserves loopback / public-bind safety

The bundle **bakes no bind authority**:
- the runner script defaults `--addr 127.0.0.1:$PORT`;
- **`igweb-serve` itself REFUSES a non-loopback address** — the single-source safety gate is in the runner
  binary, and the bundle merely carries that binary, so it **cannot widen** the policy;
- `manifest.json` *declares* `bind_policy: loopback` (a statement, not an enforcement point);
- the bundler refuses to emit when `[server] mode` ≠ `loopback` (Q5 #6).

Public exposure (reverse proxy, `0.0.0.0`, TLS termination) is a **host** concern, entirely outside the
bundle. There is no flag, file, or manifest field by which a bundle can request a public bind.

---

## 8. Q7 — What stays OUTSIDE the bundle (host/operator-owned)

- **systemd install/enable** — the bundle ships a `*.service.example` **template** only; `systemctl
  enable/start`, `daemon-reload`, and the `current` symlink swap are host actions.
- **Bind exposure / reverse proxy / public listener** — host.
- **TLS / certificates** — host (`tls` is an igniter-machine opt-in feature, not a bundle concern).
- **DB creation / migration / seeding** — host; the bundle is "Postgres-shaped" `.ig` only, opens no DB.
- **Secrets / DSNs / tokens / real `host.toml`** — host environment; never bundled.
- **Docker images / Compose** — deferred (closed surface).
- **Rollback execution** — host swaps the `current` symlink; the bundle only provides the versioned dir.

---

## 9. Q8 — First implementation card

**`LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14`** — implement `igniter app bundle <app_dir> --out <dir>
[--version <stamp>]` as **orchestration** (P5 xtask/shell model; no workspace, no daemon):

- resolve `igweb-serve` via the P8 staging order; run the §6 checks (fail-closed);
- copy `{bin/igweb-serve, app/<appname>/…, run/run-<appname>.sh, checks/check.sh,
  systemd/<appname>.service.example, host.toml.example?}` into a versioned dir;
- write `manifest.json` (§4) with caller-supplied `--version`/stamp (no clock in the tool);
- emit nothing else — **no systemd, no symlink, no secret, no bind authority**.
- **Tests:** bundle layout matches §2; manifest fields present + runner sha256 matches the copied binary;
  secret-refusal (a `host.toml` or an inline-secret host config is rejected, no bundle written); loopback-only
  (non-loopback `[server] mode` refused); the `check` gate runs and a clean app bundles green; the emitted
  `checks/check.sh` passes on the produced bundle.

Wire `igniter app …` from its current fail-closed placeholder to this command (mirrors the P12 `package`→
`igc` delegation pattern) once P14 lands.

---

## Acceptance trace

- [x] Home-lab release-bundle/systemd precedent summarized with exact boundaries (§1).
- [x] Bundle file layout specified (§2).
- [x] Manifest/provenance fields specified (§4).
- [x] Host-owned surfaces explicitly excluded (§8, plus §7 bind safety).
- [x] Loopback/secret safety model preserved (§5 #5–6, §7, §4 secret gate).
- [x] First implementation card named (§9: `LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14`).
- [x] No code changes (design only).
