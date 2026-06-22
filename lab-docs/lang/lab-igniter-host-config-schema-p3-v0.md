# lab-igniter-host-config-schema-p3-v0

**Card:** `LAB-IGNITER-HOST-CONFIG-SCHEMA-P3`
**Status:** CLOSED (implementation proof) — host config parser/resolver landed with P2/P3 wave
**Date:** 2026-06-22
**Lane:** machine / host IO / config hygiene

---

## 1. Live-Code Check

### Final implementation update

This packet began as a readiness/schema specification before the async runner work landed.
The P2/P3 wave then implemented the parser/resolver in
`server/igniter-web/src/host_config.rs` and exported it from `server/igniter-web/src/lib.rs`.

What landed:

- hand-rolled `host.toml` parser/resolver, no `toml` crate
- env-name-only secret references (`dsn_env`, `passport_env`)
- inline-secret key rejection in every section
- structured `HostConfigError` variants for section/key/secret/env failures
- parser/resolver tests in `host_config.rs` (33 tests)

What did **not** land in this card:

- `igweb-serve --host-config` binary wiring
- live Postgres connection opening from `host.toml`
- secret-provider or interpolation support

### P2 landing check

```
rg -n "host.toml|host_config|passport_env|dsn_env|target_routes|bind_target" server runtime lang
```

Initial readiness result before implementation: no `host.toml`, no `host_config`,
no `passport_env`, no `dsn_env` existed. Final result after this wave: `host_config`
exists and is tested; binary wiring remains a follow-up.

### What `igweb.toml` currently guards

`server/igniter-web/src/lib.rs:parse_manifest` (lines 442–489) already enforces:

- `[effects]` section → hard error:
  ```
  [effects] is unsupported in v0 (effect target binding is host-side, not the manifest)
  ```
- `middleware.auth_token` inline → hard error:
  ```
  inline `auth_token` is forbidden — use `auth_token_env = "VAR"` (secret read from the environment)
  ```
- Any unknown section or key → hard error:
  ```
  unknown key `<k>` in section `[<sec>]`
  ```

The `auth_token_env` pattern already exists in `igweb.toml`/`IgwebManifest`. `host.toml` extends this same env-name convention to DSN and effect passports.

### What `igweb.toml` does NOT yet guard explicitly

The inline-secret-key rejection in `igweb.toml` covers `auth_token` (by exact match) but not
`dsn`, `password`, `secret`, `token`, `passport`, `api_key`. These are meaningless in `igweb.toml`
today because the manifest has no sections that would accept them — they'd be caught by the
"unknown key" catch-all. No change needed to `igweb.toml` for this card.

---

## 2. v0 Design Decision: Env-Name Only

### Three alternatives

**Alternative A — env-name only (`dsn_env = "VAR_NAME"`)** ← recommended v0

- `host.toml` stores the NAME of an environment variable; runtime resolves the value.
- Parser rejects any bare-secret keys (`dsn`, `password`, `secret`, `token`, `passport`, `api_key`).
- Pro: simple, no interpolation surface, no template parser, teaching-safe (git-committing the file is fine)
- Con: env var ergonomics differ across deployment targets (Docker, systemd, shell)

**Alternative B — `${VAR}` string interpolation**

- Familiar to shell users; `dsn = "postgres://${PG_USER}:${PG_PASS}@localhost/db"`.
- Pro: expressive; visible at config inspection time which env var is used.
- Con: requires interpolation parser; partial-secret leakage (non-secret parts visible in template);
  makes parser more complex; grep for secrets less reliable.
- Rejected for v0. Can be added later without breaking env-name files.

**Alternative C — external secret provider abstraction**

- `dsn_source = { provider = "vault", path = "igniter/postgres/dsn" }`.
- Pro: enterprise-ready; no secret value ever in env or file.
- Con: requires provider abstraction, network, auth to secret store; major scope increase.
- Deferred explicitly. Not v0.

**Decision: Alternative A.** Simplest, safest to commit, zero parser surface. Operators who need
interpolation can wrap with envsubst at their deployment layer.

---

## 3. v0 Schema Specification

### `host.toml` layout

```toml
# host.toml — operator-owned; safe to read into version control (contains NO secret values).
# All secrets are read from environment variables by name.
# Never reference this file from igweb.toml.

[host]
mode = "loopback"                     # optional; v0 only supports "loopback"

[effects.todo-create]                 # one table per logical target name
route = "/w"                          # machine ingress route (host infra, NOT app routing)
passport_env = "IGNITER_EFFECT_PASSPORT"   # env var NAME (the passport value lives in env)

[effects.todo-done]
route = "/w"
passport_env = "IGNITER_EFFECT_PASSPORT"

[postgres.read]
dsn_env = "IGNITER_PG_DSN"           # env var NAME (DSN value lives in env)

[postgres.write]
dsn_env = "IGNITER_PG_WRITE_DSN"     # separate var for write path (defence in depth)
```

### Section grammar

| Section pattern | Allowed? | Keys |
|----------------|----------|------|
| `[host]` | Yes | `mode` |
| `[effects.<target-name>]` | Yes | `route`, `passport_env` |
| `[postgres.read]` | Yes | `dsn_env` |
| `[postgres.write]` | Yes | `dsn_env` |
| `[effects]` | **Rejected** | same rejection as `igweb.toml` |
| `[app]`, `[server]`, `[middleware]` | **Rejected** | these belong in `igweb.toml` |
| any other `[...]` | **Rejected** | unknown section |

### Key rules

| Key | Section | Type | Rule |
|-----|---------|------|------|
| `mode` | `[host]` | string | must be `"loopback"` in v0 |
| `route` | `[effects.<name>]` | string | must start with `/`; non-empty |
| `passport_env` | `[effects.<name>]` | string | env var name; non-empty; no `$`/`{`/`}` |
| `dsn_env` | `[postgres.read]` or `[postgres.write]` | string | env var name; non-empty; no `$`/`{`/`}` |

### Inline secret-key rejection table

These keys are rejected in **any** section of `host.toml` with an explicit error pointing to the
env-name alternative:

| Rejected key | Error message |
|-------------|---------------|
| `dsn` | `inline \`dsn\` is forbidden — use \`dsn_env = "VAR"\` (DSN read from the environment)` |
| `password` | `inline \`password\` is forbidden — secrets must be read from the environment` |
| `secret` | `inline \`secret\` is forbidden — secrets must be read from the environment` |
| `token` | `inline \`token\` is forbidden — secrets must be read from the environment` |
| `passport` | `inline \`passport\` is forbidden — use \`passport_env = "VAR"\`` |
| `api_key` | `inline \`api_key\` is forbidden — secrets must be read from the environment` |

---

## 4. Parser Error Catalog

The readiness sketch used a coarse `Schema(String)` / `EnvVar(String)` split.
The implementation landed a more structured `HostConfigError` enum:
`Io`, `UnknownSection`, `UnknownKey`, `InlineSecret`, `MissingRoute`,
`MissingDsnEnv`, `EmptyEnvName`, `TemplateEnvName`, `InvalidRoute`,
`UnsupportedMode`, `EnvVar`, and `Parse`.

The table below remains the intended fail-closed behavior and message shape.

### Parse-time errors (`HostConfigError::Schema`)

| Condition | Error text |
|-----------|-----------|
| Unknown top-level section `[foo]` | `unknown section "[foo]" in host.toml` |
| `[effects]` (no target name) | `"[effects]" requires a target name — use "[effects.<name>]"` |
| `[app]`, `[server]`, `[middleware]` | `"[<sec>]" belongs in igweb.toml, not host.toml` |
| Unknown key `k` in `[host]` | `unknown key \`k\` in section "[host]"` |
| Unknown key `k` in `[effects.<name>]` | `unknown key \`k\` in section "[effects.<name>]"` |
| Unknown key `k` in `[postgres.read]` | `unknown key \`k\` in section "[postgres.read]"` |
| Unknown key `k` in `[postgres.write]` | `unknown key \`k\` in section "[postgres.write]"` |
| Inline secret key (any section) | (see table in §3) |
| `mode` value not `"loopback"` | `[host] mode \`<val>\` unsupported in v0 (only "loopback")` |
| `route` empty or missing `/` prefix | `[effects.<name>] route must start with "/" (got "<val>")` |
| `passport_env` empty | `[effects.<name>] passport_env must be a non-empty env var name` |
| `passport_env` contains `$`/`{` | `[effects.<name>] passport_env must be a plain env var name, not a template` |
| `dsn_env` empty | `[postgres.<section>] dsn_env must be a non-empty env var name` |
| `dsn_env` contains `$`/`{` | `[postgres.<section>] dsn_env must be a plain env var name, not a template` |
| Malformed `key = value` line | `host.toml: expected \`key = value\`, got \`<line>\`` |

### Runtime errors (`HostConfigError::EnvVar`)

Checked when the runner starts, before opening any socket or DB connection:

| Condition | Error text |
|-----------|-----------|
| Env var named by `passport_env` not set | `env var "<VAR>" (from [effects.<name>].passport_env) is not set` |
| Env var named by `passport_env` is empty | `env var "<VAR>" (from [effects.<name>].passport_env) is empty` |
| Env var named by `dsn_env` not set | `env var "<VAR>" (from [postgres.read].dsn_env) is not set` |
| Env var named by `dsn_env` is empty | `env var "<VAR>" (from [postgres.read].dsn_env) is empty` |

Runtime env-var resolution is a separate pass from parsing — parse once, resolve at runner startup.

---

## 5. Rust Struct Design

Target file: **`server/igniter-web/src/host_config.rs`** (implemented; `pub mod host_config` in `lib.rs`).

Pattern mirrors `runner::IgwebManifest` and `runner::parse_manifest` in `lib.rs`: hand-rolled line
scanner, no `toml` crate dependency.

```rust
// server/igniter-web/src/host_config.rs

use std::collections::BTreeMap;

#[derive(Debug, Clone, Default)]
pub struct HostConfig {
    /// "loopback" (v0 only)
    pub mode: String,
    /// logical target name → effect binding
    pub effects: BTreeMap<String, HostEffectTarget>,
    /// postgres read config (optional)
    pub postgres_read: Option<HostPostgresConfig>,
    /// postgres write config (optional)
    pub postgres_write: Option<HostPostgresConfig>,
}

#[derive(Debug, Clone)]
pub struct HostEffectTarget {
    /// machine ingress route, e.g. "/w"
    pub route: String,
    /// env var NAME (not the passport value)
    pub passport_env: String,
}

#[derive(Debug, Clone)]
pub struct HostPostgresConfig {
    /// env var NAME (not the DSN value)
    pub dsn_env: String,
}

#[derive(Debug)]
pub enum HostConfigError {
    /// file IO failure
    Io(String),
    /// schema violation (parse-time)
    Schema(String),
    /// env var missing or empty (runtime)
    EnvVar(String),
}

impl std::fmt::Display for HostConfigError { /* ... */ }
impl std::error::Error for HostConfigError {}

/// Parse `host.toml` text. Pure; no IO, no env var access.
pub fn parse_host_config(text: &str) -> Result<HostConfig, HostConfigError> { /* ... */ }

/// Load and parse `<path>`.
pub fn load_host_config(path: &std::path::Path) -> Result<HostConfig, HostConfigError> { /* ... */ }

/// Resolve all `*_env` fields to their values. Returns first missing/empty env var as error.
/// Call once at runner startup, before binding any socket.
pub fn resolve_host_config(cfg: &HostConfig) -> Result<ResolvedHostConfig, HostConfigError> { /* ... */ }

/// All secrets resolved; ready for runner wiring.
#[derive(Debug)]
pub struct ResolvedHostConfig {
    pub mode: String,
    pub effects: BTreeMap<String, ResolvedEffectTarget>,
    pub postgres_read_dsn: Option<String>,
    pub postgres_write_dsn: Option<String>,
}

#[derive(Debug)]
pub struct ResolvedEffectTarget {
    pub route: String,
    pub passport: String,  // resolved value (never log this)
}
```

### Parser implementation pattern

Follow `parse_manifest` exactly: hand-rolled line scanner, section tracking, dotted section key parsing
for `[effects.<name>]` and `[postgres.read]`/`[postgres.write]`.

Dotted section parsing:

```rust
// section = "effects.todo-create"
if let Some(rest) = section.strip_prefix("effects.") {
    let target_name = rest.trim();
    // key dispatch for route / passport_env
} else if section == "postgres.read" {
    // key dispatch for dsn_env
} else if section == "postgres.write" {
    // key dispatch for dsn_env
} else if section == "host" {
    // key dispatch for mode
} else {
    return Err(HostConfigError::Schema(format!(
        "unknown section \"[{section}]\" in host.toml"
    )));
}
```

Inline-secret key check before per-key dispatch:

```rust
const FORBIDDEN_INLINE_KEYS: &[(&str, &str)] = &[
    ("dsn",     "use `dsn_env = \"VAR\"` (DSN read from the environment)"),
    ("password","secrets must be read from the environment"),
    ("secret",  "secrets must be read from the environment"),
    ("token",   "secrets must be read from the environment"),
    ("passport","use `passport_env = \"VAR\"`"),
    ("api_key", "secrets must be read from the environment"),
];

for (forbidden, hint) in FORBIDDEN_INLINE_KEYS {
    if key == *forbidden {
        return Err(HostConfigError::Schema(format!(
            "inline `{key}` is forbidden — {hint}"
        )));
    }
}
```

---

## 6. `igweb-serve` CLI Wiring

Binary target: `server/igniter-web/src/bin/igweb-serve.rs`

Planned flag (not yet wired in the binary by this card):

```
igweb-serve run [--host-config <path>] [--addr ...] [--max-requests N] <app_dir>
```

Rules:
- `--host-config` is optional; omitted → pure-read mode (current default)
- `--host-config` present → machine-backed mode (requires `machine` feature)
- Path is resolved relative to CWD, not `<app_dir>` (operator's choice)
- Parse error or env-var resolution error → print error + exit(1) before binding socket
- `host.toml` contents never logged; only `HostConfigError` messages (no secret values)

Arg parse target in `runner::parse_cli_args`:

```rust
"--host-config" => {
    let path = iter.next().ok_or_else(|| RunnerError::Cli("--host-config requires a path".into()))?;
    host_config_path = Some(PathBuf::from(path));
}
```

---

## 7. Test Matrix

Live tests landed inside `server/igniter-web/src/host_config.rs`. The table below
was the planning matrix; the implementation covers it with 33 parser/resolver tests.

```
#[cfg(feature = "machine")]  // or ungated — no machine logic in parser itself
```

The parser is pure (no IO, no env vars) so tests can be ungated.

| # | Test name | Input | Expected |
|---|-----------|-------|---------|
| 1 | `parse_minimal_effects_config` | `[effects.todo-create]` + route + passport_env | `HostConfig { effects: {"todo-create": {route: "/w", passport_env: "VAR"}} }` |
| 2 | `parse_full_config` | all four sections | all fields populated correctly |
| 3 | `parse_host_mode_only` | `[host]\nmode = "loopback"` | `mode = "loopback"`, empty effects |
| 4 | `reject_unknown_section` | `[logging]` | `Schema("unknown section \"[logging]\" in host.toml")` |
| 5 | `reject_effects_without_target` | `[effects]` | `Schema("\"[effects]\" requires a target name")` |
| 6 | `reject_app_section` | `[app]\nentry = "Serve"` | `Schema("\"[app]\" belongs in igweb.toml, not host.toml")` |
| 7 | `reject_server_section` | `[server]\nmode = "loopback"` | `Schema("\"[server]\" belongs in igweb.toml, not host.toml")` |
| 8 | `reject_inline_dsn` | `[postgres.read]\ndsn = "postgres://..."` | `Schema("inline \`dsn\` is forbidden")` |
| 9 | `reject_inline_password` | any section, `password = "..."` | `Schema("inline \`password\` is forbidden")` |
| 10 | `reject_inline_passport` | any section, `passport = "..."` | `Schema("inline \`passport\` is forbidden")` |
| 11 | `reject_unknown_key_in_host` | `[host]\nport = "8080"` | `Schema("unknown key \`port\` in section \"[host]\"")` |
| 12 | `reject_unknown_key_in_effects` | `[effects.x]\npool = "a"` | `Schema("unknown key \`pool\` in section \"[effects.x]\"")` |
| 13 | `reject_empty_passport_env` | `passport_env = ""` | `Schema("passport_env must be a non-empty env var name")` |
| 14 | `reject_template_in_passport_env` | `passport_env = "${VAR}"` | `Schema("passport_env must be a plain env var name, not a template")` |
| 15 | `reject_empty_dsn_env` | `dsn_env = ""` | `Schema("dsn_env must be a non-empty env var name")` |
| 16 | `reject_template_in_dsn_env` | `dsn_env = "${PG_DSN}"` | `Schema("dsn_env must be a plain env var name, not a template")` |
| 17 | `reject_route_without_slash` | `route = "w"` | `Schema("route must start with \"/\"")` |
| 18 | `reject_unsupported_mode` | `mode = "public"` | `Schema("[host] mode \`public\` unsupported in v0")` |
| 19 | `resolve_env_var_missing` | `passport_env = "DOES_NOT_EXIST"`, env not set | `EnvVar("env var \"DOES_NOT_EXIST\" ... is not set")` |
| 20 | `resolve_env_var_empty` | `passport_env = "EMPTY_VAR"`, env set to `""` | `EnvVar("env var \"EMPTY_VAR\" ... is empty")` |
| 21 | `resolve_success` | valid config, env vars set | `ResolvedHostConfig` with passport/DSN values |
| 22 | `comments_and_blank_lines_ignored` | config with `# comments` | parses correctly |
| 23 | `multiple_effect_targets` | `[effects.a]` + `[effects.b]` | `effects.len() == 2` |

---

## 8. Authority and Secret Hygiene Boundary

```
host.toml (operator file)
  ✓ target name        → logical routing label (no capability identity)
  ✓ route              → machine ingress path (infra topology)
  ✓ passport_env       → ENV VAR NAME (never a passport value)
  ✓ dsn_env            → ENV VAR NAME (never a DSN value)
  ✓ mode               → serving policy word

  ✗ dsn / password / secret / token / passport / api_key  → REJECTED at parse time
  ✗ [app] / [server] / [middleware]                        → REJECTED (igweb.toml only)
  ✗ [effects] without target name                         → REJECTED
  ✗ ${VAR} interpolation                                  → REJECTED (plain name only)

igweb.toml (app/author file)
  ✗ [effects] section           → already rejected (parse_manifest line 452)
  ✗ auth_token inline           → already rejected (parse_manifest line 470)
  ✗ unknown key/section         → already rejected (parse_manifest line 473)
  (no new rejections needed for this card)
```

**Runtime hygiene:**

- `ResolvedHostConfig.passport` and `postgres_*_dsn` values are NEVER logged, never serialized to JSON,
  never included in error messages from the runner.
- `HostConfigError::EnvVar` messages include only the env var NAME (from the config file), not the
  resolved value.
- The host.toml file path may appear in `HostConfigError::Io` messages (it's not a secret).

---

## 9. What Is NOT in This Card

- No registry, cloud secret manager (Vault, AWS Secrets Manager, GCP Secret Manager), or K8s integration.
- No `.ig` or `.igweb` syntax changes.
- No real DB connection (parser + resolver are pure; actual connection is P2/P4).
- No `host.toml` in app manifests — the two files are separate and each parser rejects the other's keys.
- No `${VAR}` template interpolation (Alternative B) — v0 is env-name only.
- No multi-level secret federation, rotation, or TTL.
- No production deployment claim.

---

## 10. Implementation Result

- [x] `server/igniter-web/src/host_config.rs` exists with `parse_host_config`, `load_host_config`, `resolve_host_config`
- [x] `server/igniter-web/src/lib.rs` has `pub mod host_config;`
- [x] `host_config` parser/resolver tests pass in-module (33 tests)
- [x] `igweb.toml` parse is unchanged (no new keys added)
- [x] secrets are referenced by env var name; inline secret keys are rejected
- [x] default suite remains without a `toml` crate dependency
- [x] `git diff --check` clean at close
- [ ] `server/igniter-web/src/bin/igweb-serve.rs` accepts `--host-config <path>` flag — deferred to runner productization
