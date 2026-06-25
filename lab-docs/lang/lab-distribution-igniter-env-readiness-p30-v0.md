# lab-distribution-igniter-env-readiness-p30-v0 — `igniter env` and environment authority

Card: `LAB-DISTRIBUTION-IGNITER-ENV-READINESS-P30`
Status: CLOSED (2026-06-25)
Authority: lab readiness — a recommendation, not an implementation. Closed surfaces honored: no code, no
secret-value reading (presence/empty only), no deploy, no Docker/Compose/systemd generation, no DB.

## Verify-first basis (live, cited)

- **`server/igniter-web/src/host_config.rs`** — the env authority. `host.toml` stores **env-var NAME
  references only**: `dsn_env` (`[postgres.read]`/`[postgres.write]`), `passport_env` (`[effects.*]`), plus
  non-secret policy fields (P24). `INLINE_SECRET_KEYS = [dsn, password, secret, token, passport, api_key]`
  fail closed; `[postgres.*]` without `dsn_env` fails closed; `*_env` values are names, not templates.
  `HostConfigError::EnvMissing` fires when a named var is **missing or empty at runtime**. The resolved
  struct is explicitly "never log / serialize `passport`/`*_dsn`".
- **`bin/igniter` `cmd_doctor`** — `igniter doctor <app_dir>` ALREADY has an app-shape env section, but it
  reads only the **real `host.toml`**: it greps `*_env = "NAME"`, reports `env:NAME ok(set)/warn(unset)`
  ("value never read by doctor"), and flags inline-secret keys. It does **not** read `host.example.toml`, so
  it is silent before an operator creates `host.toml`.
- **`igweb-serve`** resolves host config before bind and fails `[CONFIG_RESOLVE]` (exit 3) naming the env var,
  never its value, before the socket binds (per the RUNBOOK).
- **`examples/todo_postgres_app/host.example.toml`** — the committed, commit-safe env-NAME catalogue:
  `dsn_env="IGNITER_TODO_PG_DSN"` (read+write), `passport_env="IGNITER_TODO_EFFECT_TOKEN"` (3 effects),
  `[host] mode="loopback"`.
- **`examples/todo_postgres_app/RUNBOOK.md`** — operator flow: copy example → `export IGNITER_TODO_PG_DSN=…` /
  `IGNITER_TODO_EFFECT_TOKEN=…`; the smoke refuses (exit 2) when those are unset, naming the var, never the
  value.
- **`igniter app bundle`** copies `host.example.toml` → `host.toml.example` and sets
  `manifest.requires_machine:true`; never bundles a real `host.toml`.
- **`igniter-agent` (P28)** returns secret-safe MCP envelopes (`{tool, ok, exit_code, stdout, stderr,
  parsed}`); the bundler/serve already prove no secret leaks through it.

**Key gap this card addresses:** the env-NAME catalogue that is **always present** is `host.example.toml`
(app) / `host.toml.example` (bundle). `doctor` only inspects the *real* `host.toml`, which by design does not
exist until the operator creates it — so there is no secret-safe way today to answer *"which env vars must I
set before I can run this app?"* from the committed source. `igniter env` fills exactly that.

## Alternatives compared (A–H)

| # | Option | Verdict |
|---|---|---|
| **A** | No `igniter env`; keep env checks inside `doctor` | **Partial.** `doctor` already reports env present/unset from the *real* `host.toml` — keep that. But it can't answer "what must I set" pre-setup (no `host.example.toml` reading). Insufficient alone. |
| **B** | `igniter env doctor` — read-only present/missing report | **★ Adopt (core).** Reads the committed `host.example.toml` catalogue + reports present/unset/empty of each named var in the process env. Secret-safe, works pre-setup. |
| **C** | `igniter env template` — redacted operator checklist from `host.example.toml` | **★ Adopt (core).** Emits a neutral checklist + a copy-paste `export NAME=` skeleton with **blank** values. The missing ergonomic piece; no values, no generation of deploy artifacts. |
| **D** | dotenv `.env` reader/injector | **Reject for v0.** Becoming dotenv smuggles a second config authority and tempts value-in-file. v0 reads only the env-NAME catalogue + the live process env. (Future: optional read-only `.env` *presence* check, never injection.) |
| **E** | direnv / nix-shell external env | **Reject (out of scope).** External tools; Igniter should not own the shell environment. Document as compatible, not built. |
| **F** | Docker/Compose `env_file` generation | **Defer (future design only).** A bundle→compose path is a separate deploy card; v0 emits no container config. |
| **G** | systemd `EnvironmentFile=` generation | **Defer (future design only).** The bundle already ships a `*.service.example` with `Environment=` name examples (P29); generating a real `EnvironmentFile` edges toward deploy/secret authority. Out of v0. |
| **H** | MCP-only env diagnostics via `igniter-agent` | **Adopt as a LAYER, not the base.** Build the CLI first (B+C), then expose `env_doctor`/`env_check` as agent tools that shell-delegate — same secret-safe output, no agent secret access. |

## Recommendation — **B + C as a new `igniter env` subcommand; doctor keeps its inline section; H layers on top**

`igniter env` is a **new front-door subcommand** (answer to Q1: *a dedicated subcommand AND doctor keeps its
existing lightweight section* — layered, not duplicated; both obey `host_config.rs` rules):

- **`igniter env doctor <app_or_bundle>`** — secret-safe report. Reads the env-NAME catalogue from
  `host.example.toml` (app dir) or `host.toml.example` (bundle), lists each var with its source key
  (`dsn_env`/`passport_env`) and a **present / unset / empty** status from the current process env. Values
  are never read or printed. Exit 0 (a report) in v0.
- **`igniter env template <app_or_bundle>`** — a neutral redacted checklist plus a copy-paste shell skeleton
  (`export IGNITER_TODO_PG_DSN=   # required by [postgres.read].dsn_env`), all values **blank**. No systemd /
  Docker / Compose / EnvironmentFile generation in v0.
- **`igniter env check <app_or_bundle> [--host-config PATH]`** — the *gate*: validate the host config through
  the SAME `load_host_config` rules (reject inline secrets, missing `dsn_env`) and report which `*_env` vars
  are unset/empty. Opens no DB/socket. **Exit non-zero** if the config is invalid or a required var is unset
  (this is the only env verb that fails — `env doctor` is a report).

This reuses `doctor`'s secret-safe present/unset discipline and `host_config.rs`'s authority; it invents no
new env semantics.

## Questions answered

1. **Subcommand or doctor section?** Both, layered: a dedicated `igniter env` (catalogue + template + gate)
   plus `doctor`'s existing inline env section for a quick glance.
2. **v0 source of truth for required env vars:** `host.example.toml` (app) / `host.toml.example` (bundle),
   parsed by the `host_config.rs` rules; `manifest.requires_machine` gates whether env applies. NOT the run
   script or systemd template (those are emitted artifacts, not source); the real `host.toml` is an operator
   binding, not the catalogue.
3. **`.env` in v0?** **Out.** No reading, no injection. (Future: optional read-only presence note only.)
4. **Avoiding Rails-credentials/dotenv/direnv/Compose sprawl:** v0 only *reports* names + present/empty and
   *templates* blank exports. It never stores values, never injects, never generates deploy artifacts.
5. **Secret-safe output:** env var NAMES yes; **values never**; present / unset / empty statuses yes. Mirrors
   `doctor` ("value never read") and `igweb-serve` `[CONFIG_RESOLVE]` (names the var, not the value).
6. **`env template` output:** a **neutral report + blank shell `export` skeleton** in v0. systemd
   `Environment=` / Docker `env_file` / EnvironmentFile generation are deferred (future design only).
7. **MCP exposure:** `igniter-agent` adds `env_doctor` / `env_check` tools that shell-delegate to `igniter
   env` and return the secret-safe report in the P28 envelope (`parsed` = the catalogue + statuses). Agents
   get names + present/empty, never values — the CLI's redaction is inherited.
8. **Pure observed apps (no `host.example.toml`):** `igniter env doctor` reports "no machine-mode env
   required" and exits 0; `env check` is a clean pass.
9. **App-dir vs bundle:** identical logic; the catalogue file is `host.example.toml` in an app dir and
   `host.toml.example` in a produced bundle; `manifest.requires_machine` corroborates for bundles.
10. **Smallest first impl card:** `LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33` (see below).

## First implementation card — P33

**`LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33`** — implement `igniter env doctor` + `igniter env template`
(the `env check` gate and the agent `env_*` tools are a follow-on slice):

- `bin/igniter`: a `cmd_env` dispatch (`doctor` / `template`), resolving the catalogue file
  (`host.example.toml` | bundle `host.toml.example`), extracting `*_env` names exactly as `doctor` does, and
  reporting present/unset/empty from the process env. `template` prints a blank `export` skeleton.
- **Acceptance matrix:** (a) `env doctor examples/todo_postgres_app` names `IGNITER_TODO_PG_DSN` +
  `IGNITER_TODO_EFFECT_TOKEN` with unset status, exit 0; (b) values never printed (assert a fake exported
  value is absent from output); (c) `env doctor examples/todo_app` (no example) → "no machine-mode env
  required", exit 0; (d) `env template` emits blank `export NAME=` lines, no values; (e) bundle dir input
  reads `host.toml.example`; (f) `bash -n bin/igniter`, `git diff --check` clean.
- **Follow-on (P34):** `igniter env check` gate (reuse `load_host_config` semantics; exit non-zero on
  invalid/unset) + `igniter-agent` `env_doctor`/`env_check` MCP tools with the P28 envelope.

## Reporting

1. **Recommended v0 command shape:** `igniter env doctor|template <app_or_bundle>` now (P33); `igniter env
   check [--host-config PATH]` + agent `env_*` tools next (P34). A new subcommand, with `doctor` keeping its
   inline env section.
2. **`.env`:** OUT of v0 (no read, no inject).
3. **Files deciding required env names:** `host.example.toml` (app) / `host.toml.example` (bundle), under the
   `host_config.rs` authority; `manifest.requires_machine` gates applicability.
4. **Safe MCP consumption:** agent `env_doctor`/`env_check` shell-delegate to `igniter env`; the envelope
   carries names + present/empty statuses only — values are never read, so agents cannot obtain secrets.
5. **Next card:** `LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33` (doctor+template) — acceptance matrix above; then
   `…-ENV-CHECK-AND-AGENT-P34`.

## Acceptance trace

- [x] Readiness packet written under `lab-docs/lang/`.
- [x] Live source/docs inspected + cited by path (host_config.rs, cmd_doctor, igweb-serve, host.example.toml,
      RUNBOOK, app bundle manifest, P28 agent).
- [x] ≥6 alternatives compared (A–H).
- [x] Secret boundary explicit: env var names reported; values never; present/unset/empty allowed.
- [x] App-dir vs bundle behavior decided (`host.example.toml` vs `host.toml.example`; `requires_machine`).
- [x] `host.toml` vs `host.toml.example` authority split decided (example = always-present catalogue; real
      host.toml = operator binding, never required for the catalogue, never bundled).
- [x] First implementation card named with a bounded acceptance matrix (P33).
- [x] No production code changes; `git diff --check` clean.
