//! Operator-owned host configuration parser (LAB-IGNITER-HOST-CONFIG-SCHEMA-P3).
//!
//! host.toml stores env-var NAME references — never raw secret values:
//!
//! ```toml
//! [host]
//! mode = "loopback"
//!
//! [effects.todo-create]
//! route = "/w"
//! passport_env = "IGNITER_EFFECT_PASSPORT"
//!
//! [postgres.write]
//! dsn_env = "IGNITER_PG_WRITE_DSN"
//! ```
//!
//! Enforcement:
//! - `*_env` values are env-var names, not interpolated templates.
//! - Unknown top-level sections fail closed.
//! - Unknown keys within a section fail closed.
//! - Inline raw-secret keys (`dsn`, `password`, `secret`, `token`, `passport`, `api_key`) fail closed.
//! - Empty env-var names fail closed.
//! - Template syntax in env-var names (`$`, `{`, `}`) fails closed.
//! - `route` must start with `/`.
//! - `[host] mode` only accepts `"loopback"` in v0.
//! - `[effects.<target>]` without `route` fails closed.
//! - `[postgres.*]` without `dsn_env` fails closed.

use std::collections::BTreeMap;

// ── parsed config (env-var names; no secret values) ──────────────────────────────────────────────

#[derive(Debug, Clone, Default)]
pub struct HostConfig {
    /// `[host] mode` — only "loopback" is valid in v0.
    pub host_mode: Option<String>,
    /// `[effects.<target>]` — one entry per logical effect target.
    pub effects: BTreeMap<String, EffectConfig>,
    /// `[postgres.write]`
    pub postgres_write: Option<PostgresConfig>,
    /// `[postgres.read]`
    pub postgres_read: Option<PostgresConfig>,
}

#[derive(Debug, Clone, Default)]
pub struct EffectConfig {
    /// Machine ingress route (e.g. "/w"). Required.
    pub route: String,
    /// Env-var name for the effect bearer passport. Optional.
    pub passport_env: Option<String>,
}

#[derive(Debug, Clone)]
pub struct PostgresConfig {
    /// Env-var name for the Postgres DSN. Required when section is present.
    pub dsn_env: String,
}

// ── resolved config (actual values; never log these fields) ──────────────────────────────────────

/// All `*_env` references resolved to their actual values.
/// Produced by `resolve_host_config`. Never log or serialize `passport` / `*_dsn` fields.
#[derive(Debug)]
pub struct ResolvedHostConfig {
    pub host_mode: String,
    pub effects: BTreeMap<String, ResolvedEffectTarget>,
    /// Resolved DSN for the postgres read adapter (never log).
    pub postgres_read_dsn: Option<String>,
    /// Resolved DSN for the postgres write adapter (never log).
    pub postgres_write_dsn: Option<String>,
}

#[derive(Debug)]
pub struct ResolvedEffectTarget {
    pub route: String,
    /// Resolved passport value (never log).
    pub passport: Option<String>,
}

// ── errors ────────────────────────────────────────────────────────────────────────────────────────

#[derive(Debug)]
pub enum HostConfigError {
    /// File could not be read.
    Io(String),
    UnknownSection(String),
    UnknownKey { section: String, key: String },
    /// A raw-secret key was used instead of a `*_env` reference.
    InlineSecret { key: String },
    /// `[effects.<target>]` appeared but `route` was not provided.
    MissingRoute { target: String },
    /// `[postgres.*]` appeared but `dsn_env` was not provided.
    MissingDsnEnv { section: String },
    EmptyEnvName { key: String },
    /// Env-var name contains template syntax (`$`, `{`, `}`).
    TemplateEnvName { key: String },
    /// `route` value does not begin with `/`.
    InvalidRoute { target: String, route: String },
    /// `[host] mode` is not a supported value.
    UnsupportedMode(String),
    /// Env-var named by a `*_env` key is missing or empty at runtime.
    EnvVar {
        var_name: String,
        key: String,
        section: String,
    },
    Parse(String),
}

impl std::fmt::Display for HostConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(m) => write!(f, "host.toml: io error: {m}"),
            Self::UnknownSection(s) => write!(f, "host.toml: unknown section `[{s}]`"),
            Self::UnknownKey { section, key } => {
                write!(f, "host.toml: unknown key `{key}` in `[{section}]`")
            }
            Self::InlineSecret { key } => write!(
                f,
                "host.toml: `{key}` stores a raw secret — use `{key}_env = \"VAR_NAME\"` instead"
            ),
            Self::MissingRoute { target } => {
                write!(f, "host.toml: `[effects.{target}]` is missing required `route`")
            }
            Self::MissingDsnEnv { section } => {
                write!(f, "host.toml: `[{section}]` is missing required `dsn_env`")
            }
            Self::EmptyEnvName { key } => {
                write!(f, "host.toml: env-var name for `{key}` must not be empty")
            }
            Self::TemplateEnvName { key } => write!(
                f,
                "host.toml: `{key}` must be a plain env-var name, not a template (no `$`/`{{`/`}}`)"
            ),
            Self::InvalidRoute { target, route } => write!(
                f,
                "host.toml: `[effects.{target}]` route must start with `/` (got `{route}`)"
            ),
            Self::UnsupportedMode(m) => write!(
                f,
                "host.toml: `[host] mode = \"{m}\"` is unsupported in v0 (only \"loopback\")"
            ),
            Self::EnvVar { var_name, key, section } => write!(
                f,
                "host.toml: env var \"{var_name}\" (from [{section}].{key}) is not set or is empty"
            ),
            Self::Parse(m) => write!(f, "host.toml: {m}"),
        }
    }
}
impl std::error::Error for HostConfigError {}

// ── parser ────────────────────────────────────────────────────────────────────────────────────────

const INLINE_SECRET_KEYS: &[&str] = &[
    "dsn", "password", "secret", "token", "passport", "api_key",
];

enum Section {
    None,
    Host,
    Effect(String),
    PostgresWrite,
    PostgresRead,
}

fn section_label(s: &Section) -> String {
    match s {
        Section::None => String::new(),
        Section::Host => "host".to_string(),
        Section::Effect(t) => format!("effects.{t}"),
        Section::PostgresWrite => "postgres.write".to_string(),
        Section::PostgresRead => "postgres.read".to_string(),
    }
}

fn check_env_name(key: &str, val: &str) -> Result<(), HostConfigError> {
    if val.is_empty() {
        return Err(HostConfigError::EmptyEnvName { key: key.to_string() });
    }
    if val.contains('$') || val.contains('{') || val.contains('}') {
        return Err(HostConfigError::TemplateEnvName { key: key.to_string() });
    }
    Ok(())
}

/// Parse `host.toml` text. Pure; no IO, no env-var access.
pub fn parse_host_config(text: &str) -> Result<HostConfig, HostConfigError> {
    let mut config = HostConfig::default();
    let mut section = Section::None;

    let mut effect_routes: BTreeMap<String, String> = BTreeMap::new();
    let mut effect_passport_envs: BTreeMap<String, String> = BTreeMap::new();
    let mut pg_write_dsn_env: Option<String> = None;
    let mut pg_read_dsn_env: Option<String> = None;
    let mut pg_write_seen = false;
    let mut pg_read_seen = false;

    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        // Section header: [<section>]
        if let Some(inner) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            let s = inner.trim();
            section = if s == "host" {
                Section::Host
            } else if let Some(target) = s.strip_prefix("effects.") {
                let target = target.trim();
                if target.is_empty() {
                    return Err(HostConfigError::UnknownSection("effects.".to_string()));
                }
                Section::Effect(target.to_string())
            } else if s == "postgres.write" {
                pg_write_seen = true;
                Section::PostgresWrite
            } else if s == "postgres.read" {
                pg_read_seen = true;
                Section::PostgresRead
            } else {
                return Err(HostConfigError::UnknownSection(s.to_string()));
            };
            continue;
        }

        // Key-value pair
        let (key, val) = line.split_once('=').ok_or_else(|| {
            HostConfigError::Parse(format!("expected `key = value`, got `{line}`"))
        })?;
        let key = key.trim();
        let val = parse_quoted(val.trim())?;

        // Reject inline raw-secret keys in any section.
        if INLINE_SECRET_KEYS.contains(&key) {
            return Err(HostConfigError::InlineSecret {
                key: key.to_string(),
            });
        }

        let label = section_label(&section);

        match &section {
            Section::None => {
                return Err(HostConfigError::Parse(format!(
                    "key `{key}` appears before any section header"
                )));
            }
            Section::Host => match key {
                "mode" => {
                    if val != "loopback" {
                        return Err(HostConfigError::UnsupportedMode(val));
                    }
                    config.host_mode = Some(val);
                }
                _ => {
                    return Err(HostConfigError::UnknownKey {
                        section: label,
                        key: key.to_string(),
                    })
                }
            },
            Section::Effect(target) => {
                let t = target.clone();
                match key {
                    "route" => {
                        if !val.starts_with('/') {
                            return Err(HostConfigError::InvalidRoute {
                                target: t,
                                route: val,
                            });
                        }
                        effect_routes.insert(t, val);
                    }
                    "passport_env" => {
                        check_env_name(key, &val)?;
                        effect_passport_envs.insert(t, val);
                    }
                    _ => {
                        return Err(HostConfigError::UnknownKey {
                            section: label,
                            key: key.to_string(),
                        })
                    }
                }
            }
            Section::PostgresWrite => match key {
                "dsn_env" => {
                    check_env_name(key, &val)?;
                    pg_write_dsn_env = Some(val);
                }
                _ => {
                    return Err(HostConfigError::UnknownKey {
                        section: label,
                        key: key.to_string(),
                    })
                }
            },
            Section::PostgresRead => match key {
                "dsn_env" => {
                    check_env_name(key, &val)?;
                    pg_read_dsn_env = Some(val);
                }
                _ => {
                    return Err(HostConfigError::UnknownKey {
                        section: label,
                        key: key.to_string(),
                    })
                }
            },
        }
    }

    // Merge effects: route is required; passport_env is optional.
    for (target, route) in &effect_routes {
        config.effects.insert(
            target.clone(),
            EffectConfig {
                route: route.clone(),
                passport_env: effect_passport_envs.remove(target),
            },
        );
    }
    // passport_env with no corresponding route is an error.
    if let Some(target) = effect_passport_envs.keys().next() {
        return Err(HostConfigError::MissingRoute {
            target: target.clone(),
        });
    }

    // Postgres sections: dsn_env is required when the section header appeared.
    if pg_write_seen {
        let dsn_env = pg_write_dsn_env.ok_or_else(|| HostConfigError::MissingDsnEnv {
            section: "postgres.write".to_string(),
        })?;
        config.postgres_write = Some(PostgresConfig { dsn_env });
    }
    if pg_read_seen {
        let dsn_env = pg_read_dsn_env.ok_or_else(|| HostConfigError::MissingDsnEnv {
            section: "postgres.read".to_string(),
        })?;
        config.postgres_read = Some(PostgresConfig { dsn_env });
    }

    Ok(config)
}

fn parse_quoted(v: &str) -> Result<String, HostConfigError> {
    if v.len() >= 2 && v.starts_with('"') && v.ends_with('"') {
        Ok(v[1..v.len() - 1].to_string())
    } else {
        Err(HostConfigError::Parse(format!(
            "expected a quoted string, got `{v}`"
        )))
    }
}

/// Load and parse `host.toml` at the given path.
pub fn load_host_config(path: &std::path::Path) -> Result<HostConfig, HostConfigError> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| HostConfigError::Io(format!("{}: {e}", path.display())))?;
    parse_host_config(&text)
}

// ── env-var resolution ────────────────────────────────────────────────────────────────────────────

/// Resolve all `*_env` references to their actual values from the environment.
/// Call once at runner startup, before binding any socket.
/// Returns an error for the first missing or empty env var.
pub fn resolve_host_config(cfg: &HostConfig) -> Result<ResolvedHostConfig, HostConfigError> {
    resolve_with_env(cfg, |name| std::env::var(name).ok())
}

fn resolve_with_env<F>(cfg: &HostConfig, get_env: F) -> Result<ResolvedHostConfig, HostConfigError>
where
    F: Fn(&str) -> Option<String>,
{
    let mut effects = BTreeMap::new();
    for (target, ec) in &cfg.effects {
        let passport = if let Some(env_name) = &ec.passport_env {
            let val = get_env(env_name).filter(|v| !v.is_empty()).ok_or_else(|| {
                HostConfigError::EnvVar {
                    var_name: env_name.clone(),
                    key: "passport_env".to_string(),
                    section: format!("effects.{target}"),
                }
            })?;
            Some(val)
        } else {
            None
        };
        effects.insert(
            target.clone(),
            ResolvedEffectTarget {
                route: ec.route.clone(),
                passport,
            },
        );
    }

    let postgres_read_dsn = if let Some(pg) = &cfg.postgres_read {
        let val = get_env(&pg.dsn_env)
            .filter(|v| !v.is_empty())
            .ok_or_else(|| HostConfigError::EnvVar {
                var_name: pg.dsn_env.clone(),
                key: "dsn_env".to_string(),
                section: "postgres.read".to_string(),
            })?;
        Some(val)
    } else {
        None
    };

    let postgres_write_dsn = if let Some(pg) = &cfg.postgres_write {
        let val = get_env(&pg.dsn_env)
            .filter(|v| !v.is_empty())
            .ok_or_else(|| HostConfigError::EnvVar {
                var_name: pg.dsn_env.clone(),
                key: "dsn_env".to_string(),
                section: "postgres.write".to_string(),
            })?;
        Some(val)
    } else {
        None
    };

    Ok(ResolvedHostConfig {
        host_mode: cfg.host_mode.clone().unwrap_or_else(|| "loopback".to_string()),
        effects,
        postgres_read_dsn,
        postgres_write_dsn,
    })
}

// ── tests ─────────────────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── parse: round-trip ─────────────────────────────────────────────────────────────────────────

    #[test]
    fn full_config_round_trips() {
        let text = r#"
# lab host config
[host]
mode = "loopback"

[effects.todo-create]
route = "/w"
passport_env = "IGNITER_EFFECT_PASSPORT"

[effects.todo-done]
route = "/w"

[postgres.write]
dsn_env = "IGNITER_PG_WRITE_DSN"

[postgres.read]
dsn_env = "IGNITER_PG_READ_DSN"
"#;
        let cfg = parse_host_config(text).expect("valid config");
        assert_eq!(cfg.host_mode.as_deref(), Some("loopback"));
        let create = cfg.effects.get("todo-create").expect("todo-create");
        assert_eq!(create.route, "/w");
        assert_eq!(
            create.passport_env.as_deref(),
            Some("IGNITER_EFFECT_PASSPORT")
        );
        let done = cfg.effects.get("todo-done").expect("todo-done");
        assert_eq!(done.route, "/w");
        assert!(done.passport_env.is_none());
        assert_eq!(
            cfg.postgres_write.as_ref().unwrap().dsn_env,
            "IGNITER_PG_WRITE_DSN"
        );
        assert_eq!(
            cfg.postgres_read.as_ref().unwrap().dsn_env,
            "IGNITER_PG_READ_DSN"
        );
    }

    #[test]
    fn minimal_effects_only_config() {
        let text = "[effects.submit]\nroute = \"/w\"\n";
        let cfg = parse_host_config(text).expect("valid");
        assert!(cfg.host_mode.is_none());
        assert_eq!(cfg.effects["submit"].route, "/w");
        assert!(cfg.postgres_write.is_none());
    }

    #[test]
    fn comments_and_blank_lines_ignored() {
        let text = "# top comment\n\n[effects.x]\n# inline comment\nroute = \"/ep\"\n";
        let cfg = parse_host_config(text).expect("valid");
        assert_eq!(cfg.effects["x"].route, "/ep");
    }

    #[test]
    fn multiple_effect_targets() {
        let text = "[effects.a]\nroute = \"/a\"\n[effects.b]\nroute = \"/b\"\n";
        let cfg = parse_host_config(text).expect("valid");
        assert_eq!(cfg.effects.len(), 2);
    }

    // ── parse: unknown sections / keys ────────────────────────────────────────────────────────────

    #[test]
    fn unknown_section_fails_closed() {
        for bad in &["[vault]", "[capabilities]", "[secrets]", "[database]", "[effects]"] {
            let err = parse_host_config(&format!("{}\nkey = \"val\"", bad)).unwrap_err();
            assert!(
                matches!(err, HostConfigError::UnknownSection(_)),
                "should reject section: {bad}"
            );
        }
    }

    #[test]
    fn app_server_middleware_sections_rejected() {
        for bad in &["[app]", "[server]", "[middleware]"] {
            let err = parse_host_config(&format!("{}\nentry = \"Serve\"", bad)).unwrap_err();
            assert!(
                matches!(err, HostConfigError::UnknownSection(_)),
                "igweb.toml section must be rejected: {bad}"
            );
        }
    }

    #[test]
    fn unknown_key_in_host_fails_closed() {
        let err = parse_host_config("[host]\nfoo = \"bar\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownKey { .. }));
    }

    #[test]
    fn unknown_key_in_effects_fails_closed() {
        let err =
            parse_host_config("[effects.x]\nroute = \"/w\"\nextra = \"y\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownKey { .. }));
    }

    #[test]
    fn unknown_key_in_postgres_write_fails_closed() {
        let err =
            parse_host_config("[postgres.write]\ndsn_env = \"V\"\npool = \"5\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownKey { .. }));
    }

    // ── parse: inline secret rejection ───────────────────────────────────────────────────────────

    #[test]
    fn inline_dsn_fails_closed() {
        let text = "[postgres.write]\ndsn = \"postgres://localhost/db\"";
        let err = parse_host_config(text).unwrap_err();
        assert!(matches!(err, HostConfigError::InlineSecret { .. }));
    }

    #[test]
    fn inline_password_fails_closed() {
        let err = parse_host_config("[host]\npassword = \"hunter2\"").unwrap_err();
        assert!(matches!(err, HostConfigError::InlineSecret { .. }));
    }

    #[test]
    fn inline_token_fails_closed() {
        let err = parse_host_config("[effects.x]\nroute = \"/w\"\ntoken = \"abc\"").unwrap_err();
        assert!(matches!(err, HostConfigError::InlineSecret { .. }));
    }

    #[test]
    fn inline_passport_fails_closed() {
        let err =
            parse_host_config("[effects.x]\nroute = \"/w\"\npassport = \"raw\"").unwrap_err();
        assert!(matches!(err, HostConfigError::InlineSecret { .. }));
    }

    #[test]
    fn inline_secret_fails_closed() {
        let err = parse_host_config("[host]\nsecret = \"xyz\"").unwrap_err();
        assert!(matches!(err, HostConfigError::InlineSecret { .. }));
    }

    #[test]
    fn inline_api_key_fails_closed() {
        let err = parse_host_config("[host]\napi_key = \"xyz\"").unwrap_err();
        assert!(matches!(err, HostConfigError::InlineSecret { .. }));
    }

    // ── parse: env-name validation ────────────────────────────────────────────────────────────────

    #[test]
    fn empty_env_name_fails_closed() {
        let err = parse_host_config("[postgres.write]\ndsn_env = \"\"").unwrap_err();
        assert!(matches!(err, HostConfigError::EmptyEnvName { .. }));
    }

    #[test]
    fn empty_passport_env_fails_closed() {
        let err =
            parse_host_config("[effects.x]\nroute = \"/w\"\npassport_env = \"\"").unwrap_err();
        assert!(matches!(err, HostConfigError::EmptyEnvName { .. }));
    }

    #[test]
    fn template_in_passport_env_fails_closed() {
        for tmpl in &["${MY_VAR}", "${VAR}", "{VAR}"] {
            let text = format!("[effects.x]\nroute = \"/w\"\npassport_env = \"{tmpl}\"");
            let err = parse_host_config(&text).unwrap_err();
            assert!(
                matches!(err, HostConfigError::TemplateEnvName { .. }),
                "template `{tmpl}` should be rejected"
            );
        }
    }

    #[test]
    fn template_in_dsn_env_fails_closed() {
        for tmpl in &["${PG_DSN}", "$PG_DSN"] {
            let text = format!("[postgres.write]\ndsn_env = \"{tmpl}\"");
            let err = parse_host_config(&text).unwrap_err();
            assert!(
                matches!(err, HostConfigError::TemplateEnvName { .. }),
                "template `{tmpl}` should be rejected"
            );
        }
    }

    // ── parse: route / mode validation ───────────────────────────────────────────────────────────

    #[test]
    fn route_without_slash_fails_closed() {
        let err = parse_host_config("[effects.x]\nroute = \"w\"").unwrap_err();
        assert!(
            matches!(err, HostConfigError::InvalidRoute { .. }),
            "route without leading / must fail"
        );
    }

    #[test]
    fn route_empty_fails_closed() {
        let err = parse_host_config("[effects.x]\nroute = \"\"").unwrap_err();
        assert!(matches!(err, HostConfigError::InvalidRoute { .. }));
    }

    #[test]
    fn unsupported_mode_fails_closed() {
        let err = parse_host_config("[host]\nmode = \"public\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnsupportedMode(_)));
    }

    // ── parse: structural errors ──────────────────────────────────────────────────────────────────

    #[test]
    fn missing_route_in_effects_fails_closed() {
        let err = parse_host_config("[effects.x]\npassport_env = \"MY_VAR\"").unwrap_err();
        assert!(matches!(err, HostConfigError::MissingRoute { .. }));
    }

    #[test]
    fn missing_dsn_env_in_postgres_write_fails_closed() {
        let err = parse_host_config("[postgres.write]\n").unwrap_err();
        assert!(matches!(err, HostConfigError::MissingDsnEnv { .. }));
    }

    #[test]
    fn missing_dsn_env_in_postgres_read_fails_closed() {
        let err = parse_host_config("[postgres.read]\n").unwrap_err();
        assert!(matches!(err, HostConfigError::MissingDsnEnv { .. }));
    }

    #[test]
    fn key_before_section_fails_closed() {
        let err = parse_host_config("mode = \"loopback\"").unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    // ── load_host_config ─────────────────────────────────────────────────────────────────────────

    #[test]
    fn load_nonexistent_file_returns_io_error() {
        let err = load_host_config(std::path::Path::new("/no/such/host.toml")).unwrap_err();
        assert!(matches!(err, HostConfigError::Io(_)));
    }

    #[test]
    fn load_and_parse_temp_file() {
        let dir = std::env::temp_dir();
        let path = dir.join("igniter_test_host_config_p3.toml");
        std::fs::write(&path, "[effects.x]\nroute = \"/ep\"\n").unwrap();
        let cfg = load_host_config(&path).expect("valid");
        assert_eq!(cfg.effects["x"].route, "/ep");
        let _ = std::fs::remove_file(&path);
    }

    // ── resolve_with_env ─────────────────────────────────────────────────────────────────────────

    #[test]
    fn resolve_success() {
        let cfg = parse_host_config(
            "[effects.x]\nroute = \"/w\"\npassport_env = \"MY_PASSPORT\"\n\
             [postgres.write]\ndsn_env = \"MY_DSN\"\n",
        )
        .unwrap();
        let resolved = resolve_with_env(&cfg, |name| match name {
            "MY_PASSPORT" => Some("secret-passport-value".to_string()),
            "MY_DSN" => Some("postgres://localhost/db".to_string()),
            _ => None,
        })
        .expect("resolve ok");
        assert_eq!(resolved.host_mode, "loopback");
        assert_eq!(
            resolved.effects["x"].passport.as_deref(),
            Some("secret-passport-value")
        );
        assert_eq!(
            resolved.postgres_write_dsn.as_deref(),
            Some("postgres://localhost/db")
        );
        assert!(resolved.postgres_read_dsn.is_none());
    }

    #[test]
    fn resolve_missing_env_var_returns_error() {
        let cfg = parse_host_config(
            "[postgres.read]\ndsn_env = \"MISSING_VAR\"\n",
        )
        .unwrap();
        let err = resolve_with_env(&cfg, |_| None).unwrap_err();
        assert!(
            matches!(&err, HostConfigError::EnvVar { var_name, .. } if var_name == "MISSING_VAR")
        );
    }

    #[test]
    fn resolve_empty_env_var_returns_error() {
        let cfg = parse_host_config(
            "[effects.x]\nroute = \"/w\"\npassport_env = \"EMPTY_VAR\"\n",
        )
        .unwrap();
        let err = resolve_with_env(&cfg, |_| Some(String::new())).unwrap_err();
        assert!(
            matches!(&err, HostConfigError::EnvVar { var_name, .. } if var_name == "EMPTY_VAR")
        );
    }

    #[test]
    fn resolve_no_passport_env_needs_no_var() {
        let cfg = parse_host_config("[effects.x]\nroute = \"/w\"\n").unwrap();
        let resolved = resolve_with_env(&cfg, |_| None).expect("no env var needed");
        assert!(resolved.effects["x"].passport.is_none());
    }

    #[test]
    fn resolve_default_mode_is_loopback() {
        let cfg = parse_host_config("[effects.x]\nroute = \"/w\"\n").unwrap();
        let resolved = resolve_with_env(&cfg, |_| None).unwrap();
        assert_eq!(resolved.host_mode, "loopback");
    }
}
