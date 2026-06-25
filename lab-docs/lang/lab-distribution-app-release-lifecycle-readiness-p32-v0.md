# lab-distribution-app-release-lifecycle-readiness-p32-v0 — bundle admission, release dirs, rollback

Card: `LAB-DISTRIBUTION-APP-RELEASE-LIFECYCLE-READINESS-P32`
Status: CLOSED (2026-06-25)
Authority: lab readiness — a recommendation, not an activation. Closed surfaces honored: no code, no systemd
install/restart, no remote copy, no public bind, no TLS, no DB migration, no Docker, no secrets, no deploy.

## Verify-first basis (live)

- **`igniter app bundle` (P14)** produces `<out>/<app>-<version>/` = `{bin/igweb-serve, app/<app>/…,
  run/run-<app>.sh, checks/check.sh, systemd/<app>.service.example, host.toml.example?, manifest.json}`.
  A real `manifest.json` carries: `bundle_format_version, tool, app, entry, version, created_utc,
  runner{path,sha256,target_triple,source_git_commit}, app_sources[], bind_policy:"loopback",
  requires_machine, public_release:false`. Assembly-only — it does **not** install or activate.
- **Home-lab Model B/E** (`deploy/igniter-stack-deployment-models.md`) is the host precedent:
  `releases/<app>/<version>/` + `current/<app> -> releases/<app>/<version>`; the flow is *rsync bundle →
  update `current` symlink → `daemon-reload` + restart*; rollback = "keep previous bundle, swap symlink,
  restart". The restart and symlink swap are **host** actions.
- **`igc package admit <file.igpkg>` (P12)** is a *different* admission: it trusts a source-package
  **archive** (package graph / lockfile / toolchain match), not a runnable app bundle.

## Vocabulary (the contract this packet fixes)

| Term | Definition | Authority |
|---|---|---|
| **bundle** | a P14 `<app>-<version>/` directory — a portable assembly artifact, not installed | Igniter (assembly) |
| **admitted release** | a bundle that PASSED the admission gates and was **copied** into `releases/<app>/<version>/` under a release root | Igniter (validate + place) |
| **current** | a pointer `current/<app> -> releases/<app>/<version>` selecting which admitted release is "the one" | **host/operator** (activation) |
| **active service** | the running process (e.g. systemd user unit) executing `current/<app>/run/…` | **host/operator** (never Igniter) |

**Admission ≠ deploy.** Admission is *local, validating, non-activating placement*: it copies a verified
bundle into a release root and stops. It does **not** touch `current`, does not install/restart a service,
and does not expose anything. Deploy = admit **+** activate (`current`) **+** restart **+** expose — a
bundle of authorities we deliberately do not take in one step.

## Alternatives compared

| # | Option | Verdict |
|---|---|---|
| **A** | Do nothing; keep bundle only | Reject — home-lab proves the release-root pattern is the real next rung; leaving it to ad-hoc scripts loses the hash/check gates. |
| **B** | **`igniter app admit <bundle_dir> --release-root <dir>`** — copy a validated bundle into `releases/<app>/<version>/`; do NOT touch `current` | **★ Recommended next rung.** Smallest safe step: pure validate+place, fully testable in temp dirs, no host authority taken. |
| **C** | `app activate` — update the `current` symlink (no restart) | **Defer.** `current` is the *selection authority* (which release is live). Keep it a separate, later, host-adjacent step — not bundled into admission. |
| **D** | `app rollback` — point `current` at a previously-admitted release | **Defer.** Rollback is just a `current` re-point → it presupposes C. Out of the first rung. |
| **E** | `deploy local` — admit + activate + systemd restart | **Reject for v0.** Mixes assembly, selection, service-management, and exposure authority in one command — exactly the failure mode P31 warns against. |
| **F** | Reuse `igc package admit` semantics directly | **Reject.** Different domain: `.igpkg` *source-package* trust (graph/lock/toolchain) vs app-*bundle* placement (runner-sha / app-source-hash / `check.sh`). Reuse the *discipline* (hash-verify before admit), not the command — and **name them distinctly** to avoid "admit" overloading. |
| **G** | Keep all lifecycle in host scripts | **Status quo fallback.** B improves on it by giving the admission gates a single, tested owner; G stays valid for activation/restart (host-owned). |

## Recommendation — **B: `igniter app admit <bundle_dir> --release-root <dir>`**

The one next implementation rung after `app bundle`: **admit = validate + copy into a release root, nothing
more.** `current`, systemd, restart, and exposure stay out (C/D/E deferred or host-owned).

### Admission gates (all must pass; fail-closed, no partial release)

1. `manifest.json` parses and is a known `bundle_format_version`.
2. **runner sha** in the manifest matches the actual `bin/igweb-serve` (re-hash the copied binary).
3. **app source hashes** in `app_sources[]` match the copied `app/<app>/…` files (re-hash each).
4. `checks/check.sh` passes on the placed release (re-runs `igweb-serve check`, opens no socket).
5. `bind_policy == "loopback"`.
6. **No real `host.toml`** in the bundle; `requires_machine` bundles carry only `host.toml.example`
   (env-var names only — reuse the existing secret-key reject-set; never read/print values).
7. Destination `releases/<app>/<version>/` must not already exist (refuse, or require an explicit
   `--force`); admission is idempotent-or-explicit, never silently overwriting an admitted release.

### Copy semantics (Q3)

**Copy** the bundle into `releases/<app>/<version>/` — a self-contained, immutable release independent of
the source bundle (matches the home-lab rsync model). Reject symlink/hardlink (a release must not depend on
the source persisting or mutating) and move (must not destroy the source artifact).

### `current` (Q4) and rollback (Q5)

`current` is **out of the first implementation**. Admission never creates/updates it. Activation (pointing
`current` at an admitted release) and rollback (re-pointing `current` to a previously-admitted version) are
**`current`-pointer operations** that restart nothing — but they are the *selection authority* and belong to
a later, explicitly-scoped card (or stay host-owned). Rollback "without restarting anything" = it only moves
the pointer; the host decides when to restart.

### Namespace (Q6)

Live under **`igniter app …`** (`app admit`, later `app releases` / `app current`), NOT `igniter deploy`.
`deploy` implies activation/exposure authority we are not taking; keep it reserved until P31's ladder
decides (per P31, deploy stays unbuilt until authority is clear).

## MCP agent boundary (Q7)

A future `app_admit` MCP tool may shell-delegate to `igniter app admit` exactly like `app_bundle` does —
**inspect / admit / check only**. The agent NEVER activates, updates `current`, restarts a service, or
exposes anything (no such verb exists for it to call). Admission is local, validating, non-activating, and
secret-free, so it is safe to expose with the same bounded envelope shape as the other agent tools (P28).
Activation/rollback/deploy remain off the agent surface entirely.

## Local proof shape (Q9) — for the impl card

All in temp dirs, no systemd/DB/socket: bundle `todo_app` → `app admit` into a temp `--release-root` →
assert `releases/todo_app/V1/` exists with the copied files; manifest re-validates; runner sha + app-source
hashes re-match; `checks/check.sh` passes; `bind_policy` loopback; `current` is **untouched**. Negative:
a tampered bundle (mutated binary → sha mismatch) and a bundle with a real `host.toml` are **refused with no
partial release left**. `todo_postgres_app` (requires_machine) admits with only `host.toml.example`.

## Next implementation card

**`LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35`** — implement `igniter app admit <bundle_dir> --release-root <dir>`
(copy + the 7 admission gates; **no** `current`, **no** systemd, **no** restart, **no** exposure). Acceptance
outline: admit a todo_app bundle into a temp release root → `releases/<app>/<version>/` created + re-validated
(manifest/sha/hashes/check/bind_policy); tamper / real-`host.toml` / inline-secret refused with no partial
release and no leaked values; `current` untouched; `requires_machine` bundle admits with only
`host.toml.example`; `bash -n bin/igniter` + `git diff --check` clean; agent suite + app-bundle suite stay
green. Activation (`current`) and rollback are explicitly deferred to a later card.

## Reporting

1. **Recommended vocabulary + family:** bundle → **admitted release** (`releases/<app>/<version>/`) →
   `current` (host) → active service (host). Family lives under `igniter app …`; first command is
   **`app admit`** (validate + copy into a release root).
2. **`current` symlink:** **OUT** of the first implementation — admission never touches it; `current`
   selection/activation and rollback are a separate, later (or host-owned) step.
3. **Admission gates:** manifest parse + runner-sha + app-source-hashes + `checks/check.sh` + loopback
   bind-policy + no-real-`host.toml`/secrets + no-overwrite (fail-closed, no partial release).
4. **Vs deploy:** admit is local validate-and-place with zero activation/restart/exposure; deploy would add
   `current`+restart+exposure (rejected as one step, E).
5. **Next card:** `LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35` (acceptance outlined above).

## Acceptance trace

- [x] Readiness packet written (`lab-docs/lang/lab-distribution-app-release-lifecycle-readiness-p32-v0.md`).
- [x] Bundle / admitted-release / current / active-service vocabulary defined.
- [x] ≥5 alternatives compared (A–G).
- [x] Manifest/hash/check admission gates specified (7 gates).
- [x] Systemd restart + public exposure explicitly kept OUT of v0.
- [x] MCP agent permissions bounded (inspect/admit/check only; never activate/restart/expose).
- [x] One next implementation card named (`LAB-DISTRIBUTION-APP-ADMIT-IMPL-P35`) — `app admit`, `current` deferred.
- [x] No code changes; `git diff --check` clean.
