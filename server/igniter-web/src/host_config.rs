//! Operator-owned host configuration parser (LAB-IGNITER-HOST-CONFIG-SCHEMA-P3 / P24).
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
//!
//! P24 adds policy fields (not secrets — no `*_env` wrapping required):
//! - `[postgres.read]`:  `source`, `fields` (comma-list), `row_limit`, `capability`
//! - `[postgres.read.<source>.fields]`: per-field decode kinds (`bool`, `decimal:<scale>`, etc.)
//! - `[postgres.write]`: `targets` (comma-list), `ops` (comma-list), `capability`

use igniter_machine::postgres_read::PostgresReadValueKind;
use std::collections::BTreeMap;

// ── parsed config (env-var names; no secret values) ──────────────────────────────────────────────

#[derive(Debug, Clone, Default)]
pub struct HostConfig {
    /// `[host] mode` — only "loopback" is valid in v0.
    pub host_mode: Option<String>,
    /// `[effects.<target>]` — one entry per logical effect target.
    pub effects: BTreeMap<String, EffectConfig>,
    /// `[postgres.write]`
    pub postgres_write: Option<PostgresWriteConfig>,
    /// `[postgres.read]`
    pub postgres_read: Option<PostgresReadConfig>,
}

#[derive(Debug, Clone, Default)]
pub struct EffectConfig {
    /// Machine ingress route (e.g. "/w"). Required.
    pub route: String,
    /// Env-var name for the effect bearer passport. Optional.
    pub passport_env: Option<String>,
}

/// `[postgres.write]` section: env-var ref + write allowlist policy (P24) + adapter schema (P26).
#[derive(Debug, Clone, Default)]
pub struct PostgresWriteConfig {
    /// Env-var name for the Postgres write DSN. Required.
    pub dsn_env: String,
    /// Allowed write targets (e.g. `["todos"]`). Empty = deny all writes.
    pub targets: Vec<String>,
    /// Allowed write ops (e.g. `["insert", "upsert"]`). Empty = deny all writes.
    pub ops: Vec<String>,
    /// Host capability id for the write executor (e.g. `"IO.TodoWrite"`). Optional.
    pub capability_id: Option<String>,
    /// Primary-key column for the write adapter (v0 single-target). Defaults to `"id"` if absent.
    pub key_column: Option<String>,
    /// Writable value columns for the write adapter (e.g. `["account_id", "title", "done"]`).
    /// If empty, the adapter is built with no value columns (only the key is inserted).
    pub columns: Vec<String>,
}

/// `[postgres.read]` section: env-var ref + read allowlist policy (P24).
#[derive(Debug, Clone)]
pub struct PostgresReadConfig {
    /// Env-var name for the Postgres read DSN. Required.
    pub dsn_env: String,
    /// Primary allowlisted source name (e.g. `"todos"`). None = no primary source configured.
    pub source: Option<String>,
    /// Allowlisted fields for the primary source. Empty = not configured.
    pub fields: Vec<String>,
    /// Additional allowlisted `(source, fields)` from `[postgres.read.<name>]` sections
    /// (LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38). A two-stage read (e.g. prove `accounts` exists, then list
    /// `todos`) needs more than one allowlisted table. The read adapter is already source-generic; only
    /// the policy must allow each table.
    pub extra_sources: Vec<(String, Vec<String>)>,
    /// Per-source typed field decode kinds from `[postgres.read.<source>.fields]`.
    /// Fields absent from this map decode as `Text` for backwards compatibility.
    pub field_kinds: BTreeMap<String, BTreeMap<String, PostgresReadValueKind>>,
    /// Max-row clamp. Default 100.
    pub row_limit: u32,
    /// Host capability id for the read executor (e.g. `"IO.PostgresRead"`). Optional.
    pub capability_id: Option<String>,
}

impl Default for PostgresReadConfig {
    fn default() -> Self {
        Self {
            dsn_env: String::new(),
            source: None,
            fields: Vec::new(),
            extra_sources: Vec::new(),
            field_kinds: BTreeMap::new(),
            row_limit: 100,
            capability_id: None,
        }
    }
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
    UnknownKey {
        section: String,
        key: String,
    },
    /// A raw-secret key was used instead of a `*_env` reference.
    InlineSecret {
        key: String,
    },
    /// `[effects.<target>]` appeared but `route` was not provided.
    MissingRoute {
        target: String,
    },
    /// `[postgres.*]` appeared but `dsn_env` was not provided.
    MissingDsnEnv {
        section: String,
    },
    EmptyEnvName {
        key: String,
    },
    /// Env-var name contains template syntax (`$`, `{`, `}`).
    TemplateEnvName {
        key: String,
    },
    /// `route` value does not begin with `/`.
    InvalidRoute {
        target: String,
        route: String,
    },
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
                write!(
                    f,
                    "host.toml: `[effects.{target}]` is missing required `route`"
                )
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
            Self::EnvVar {
                var_name,
                key,
                section,
            } => write!(
                f,
                "host.toml: env var \"{var_name}\" (from [{section}].{key}) is not set or is empty"
            ),
            Self::Parse(m) => write!(f, "host.toml: {m}"),
        }
    }
}
impl std::error::Error for HostConfigError {}

// ── parser ────────────────────────────────────────────────────────────────────────────────────────

const INLINE_SECRET_KEYS: &[&str] = &["dsn", "password", "secret", "token", "passport", "api_key"];

enum Section {
    None,
    Host,
    Effect(String),
    PostgresWrite,
    PostgresRead,
    /// `[postgres.read.<name>]` — an additional allowlisted read source (P38).
    PostgresReadSource(String),
    /// `[postgres.read.<source>.fields]` — per-field decode kind map (P33).
    PostgresReadSourceFields(String),
}

fn section_label(s: &Section) -> String {
    match s {
        Section::None => String::new(),
        Section::PostgresReadSource(name) => format!("postgres.read.{name}"),
        Section::PostgresReadSourceFields(name) => format!("postgres.read.{name}.fields"),
        Section::Host => "host".to_string(),
        Section::Effect(t) => format!("effects.{t}"),
        Section::PostgresWrite => "postgres.write".to_string(),
        Section::PostgresRead => "postgres.read".to_string(),
    }
}

fn check_env_name(key: &str, val: &str) -> Result<(), HostConfigError> {
    if val.is_empty() {
        return Err(HostConfigError::EmptyEnvName {
            key: key.to_string(),
        });
    }
    if val.contains('$') || val.contains('{') || val.contains('}') {
        return Err(HostConfigError::TemplateEnvName {
            key: key.to_string(),
        });
    }
    Ok(())
}

/// Parse a non-empty, comma-separated list of non-empty trimmed identifiers.
fn parse_comma_list(val: &str, key: &str) -> Result<Vec<String>, HostConfigError> {
    if val.is_empty() {
        return Err(HostConfigError::Parse(format!(
            "`{key}` must be a non-empty comma-separated list"
        )));
    }
    let items: Vec<String> = val.split(',').map(|s| s.trim().to_string()).collect();
    if items.iter().any(|s| s.is_empty()) {
        return Err(HostConfigError::Parse(format!(
            "`{key}` contains an empty item (trailing comma or double-comma?)"
        )));
    }
    Ok(items)
}

/// Parse a non-negative integer from a quoted string value.
fn parse_u32(val: &str, key: &str) -> Result<u32, HostConfigError> {
    val.parse::<u32>().map_err(|_| {
        HostConfigError::Parse(format!("`{key}` must be a positive integer, got `{val}`"))
    })
}

fn parse_read_field_kind(
    section: &str,
    key: &str,
    val: &str,
) -> Result<PostgresReadValueKind, HostConfigError> {
    match val {
        "text" => Ok(PostgresReadValueKind::Text),
        "integer" => Ok(PostgresReadValueKind::Integer),
        "bool" => Ok(PostgresReadValueKind::Boolean),
        _ => {
            if let Some(scale) = val.strip_prefix("decimal:") {
                if scale.is_empty() {
                    return Err(HostConfigError::Parse(format!(
                        "`[{section}].{key}` decimal kind requires an explicit scale (`decimal:<scale>`)"
                    )));
                }
                return scale
                    .parse::<u32>()
                    .map(|scale| PostgresReadValueKind::Decimal { scale })
                    .map_err(|_| {
                        HostConfigError::Parse(format!(
                            "`[{section}].{key}` has invalid decimal scale in `{val}`"
                        ))
                    });
            }
            Err(HostConfigError::Parse(format!(
                "`[{section}].{key}` has unsupported field kind `{val}` (supported: text, integer, bool, decimal:<scale>)"
            )))
        }
    }
}

fn validate_read_field_kinds(
    primary_source: Option<&String>,
    primary_fields: &[String],
    extra_sources: &[(String, Vec<String>)],
    field_kinds: &BTreeMap<String, BTreeMap<String, PostgresReadValueKind>>,
) -> Result<(), HostConfigError> {
    for (source, kinds) in field_kinds {
        let allowed_fields: Option<&[String]> = if primary_source == Some(source) {
            Some(primary_fields)
        } else {
            extra_sources
                .iter()
                .find(|(name, _)| name == source)
                .map(|(_, fields)| fields.as_slice())
        };
        let Some(allowed_fields) = allowed_fields else {
            return Err(HostConfigError::Parse(format!(
                "`[postgres.read.{source}.fields]` has no matching `[postgres.read]` source or `[postgres.read.{source}]` section"
            )));
        };
        for field in kinds.keys() {
            if !allowed_fields.contains(field) {
                return Err(HostConfigError::Parse(format!(
                    "`[postgres.read.{source}.fields]` declares kind for non-allowlisted field `{field}`"
                )));
            }
        }
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
    let mut pg_write_targets: Vec<String> = Vec::new();
    let mut pg_write_ops: Vec<String> = Vec::new();
    let mut pg_write_capability: Option<String> = None;
    let mut pg_write_key_column: Option<String> = None;
    let mut pg_write_columns: Vec<String> = Vec::new();
    let mut pg_write_seen = false;

    let mut pg_read_dsn_env: Option<String> = None;
    let mut pg_read_source: Option<String> = None;
    let mut pg_read_fields: Vec<String> = Vec::new();
    let mut pg_read_row_limit: Option<u32> = None;
    let mut pg_read_capability: Option<String> = None;
    let mut pg_read_seen = false;
    // Extra `[postgres.read.<name>]` sources → fields (P38). Ordered, insertion-preserving.
    let mut pg_read_extra: Vec<(String, Vec<String>)> = Vec::new();
    let mut pg_read_field_kinds: BTreeMap<String, BTreeMap<String, PostgresReadValueKind>> =
        BTreeMap::new();

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
            } else if let Some(src) = s
                .strip_prefix("postgres.read.")
                .and_then(|rest| rest.strip_suffix(".fields"))
            {
                let src = src.trim();
                if src.is_empty() || src.contains('.') {
                    return Err(HostConfigError::UnknownSection(s.to_string()));
                }
                pg_read_seen = true;
                Section::PostgresReadSourceFields(src.to_string())
            } else if let Some(src) = s.strip_prefix("postgres.read.") {
                // Additional read source `[postgres.read.<name>]` (P38). The trailing dot means the exact
                // `postgres.read` header below never matches here.
                let src = src.trim();
                if src.is_empty() {
                    return Err(HostConfigError::UnknownSection(
                        "postgres.read.".to_string(),
                    ));
                }
                pg_read_seen = true;
                Section::PostgresReadSource(src.to_string())
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
                "targets" => {
                    pg_write_targets = parse_comma_list(&val, key)?;
                }
                "ops" => {
                    pg_write_ops = parse_comma_list(&val, key)?;
                }
                "capability" => {
                    if val.is_empty() {
                        return Err(HostConfigError::Parse(
                            "`capability` must not be empty".to_string(),
                        ));
                    }
                    pg_write_capability = Some(val);
                }
                "key_column" => {
                    if val.is_empty() {
                        return Err(HostConfigError::Parse(
                            "`key_column` must not be empty".to_string(),
                        ));
                    }
                    pg_write_key_column = Some(val);
                }
                "columns" => {
                    pg_write_columns = parse_comma_list(&val, key)?;
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
                "source" => {
                    if val.is_empty() {
                        return Err(HostConfigError::Parse(
                            "`source` must not be empty".to_string(),
                        ));
                    }
                    pg_read_source = Some(val);
                }
                "fields" => {
                    pg_read_fields = parse_comma_list(&val, key)?;
                }
                "row_limit" => {
                    pg_read_row_limit = Some(parse_u32(&val, key)?);
                }
                "capability" => {
                    if val.is_empty() {
                        return Err(HostConfigError::Parse(
                            "`capability` must not be empty".to_string(),
                        ));
                    }
                    pg_read_capability = Some(val);
                }
                _ => {
                    return Err(HostConfigError::UnknownKey {
                        section: label,
                        key: key.to_string(),
                    })
                }
            },
            Section::PostgresReadSource(name) => match key {
                "fields" => {
                    let fields = parse_comma_list(&val, key)?;
                    // Last write wins per source name (a repeated section overrides its fields).
                    pg_read_extra.retain(|(n, _)| n != name);
                    pg_read_extra.push((name.clone(), fields));
                }
                _ => {
                    return Err(HostConfigError::UnknownKey {
                        section: label,
                        key: key.to_string(),
                    })
                }
            },
            Section::PostgresReadSourceFields(source) => {
                let kind = parse_read_field_kind(&label, key, &val)?;
                pg_read_field_kinds
                    .entry(source.clone())
                    .or_default()
                    .insert(key.to_string(), kind);
            }
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
        config.postgres_write = Some(PostgresWriteConfig {
            dsn_env,
            targets: pg_write_targets,
            ops: pg_write_ops,
            capability_id: pg_write_capability,
            key_column: pg_write_key_column,
            columns: pg_write_columns,
        });
    }
    if pg_read_seen {
        let dsn_env = pg_read_dsn_env.ok_or_else(|| HostConfigError::MissingDsnEnv {
            section: "postgres.read".to_string(),
        })?;
        validate_read_field_kinds(
            pg_read_source.as_ref(),
            &pg_read_fields,
            &pg_read_extra,
            &pg_read_field_kinds,
        )?;
        config.postgres_read = Some(PostgresReadConfig {
            dsn_env,
            source: pg_read_source,
            fields: pg_read_fields,
            extra_sources: pg_read_extra,
            field_kinds: pg_read_field_kinds,
            row_limit: pg_read_row_limit.unwrap_or(100),
            capability_id: pg_read_capability,
        });
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
        host_mode: cfg
            .host_mode
            .clone()
            .unwrap_or_else(|| "loopback".to_string()),
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
        for bad in &[
            "[vault]",
            "[capabilities]",
            "[secrets]",
            "[database]",
            "[effects]",
        ] {
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
        let err = parse_host_config("[effects.x]\nroute = \"/w\"\nextra = \"y\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownKey { .. }));
    }

    #[test]
    fn unknown_key_in_postgres_write_fails_closed() {
        let err = parse_host_config("[postgres.write]\ndsn_env = \"V\"\npool = \"5\"").unwrap_err();
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
        let err = parse_host_config("[effects.x]\nroute = \"/w\"\npassport = \"raw\"").unwrap_err();
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

    // ── P24: read/write policy keys ──────────────────────────────────────────────────────────────

    #[test]
    fn postgres_write_policy_keys_round_trip() {
        let text = r#"
[postgres.write]
dsn_env = "PG_WRITE"
targets = "todos"
ops = "insert,upsert"
capability = "IO.TodoWrite"
"#;
        let cfg = parse_host_config(text).expect("valid");
        let wc = cfg.postgres_write.unwrap();
        assert_eq!(wc.dsn_env, "PG_WRITE");
        assert_eq!(wc.targets, vec!["todos"]);
        assert_eq!(wc.ops, vec!["insert", "upsert"]);
        assert_eq!(wc.capability_id.as_deref(), Some("IO.TodoWrite"));
    }

    #[test]
    fn postgres_write_without_policy_keys_still_valid() {
        let text = "[postgres.write]\ndsn_env = \"PG_W\"\n";
        let cfg = parse_host_config(text).expect("valid");
        let wc = cfg.postgres_write.unwrap();
        assert_eq!(wc.dsn_env, "PG_W");
        assert!(wc.targets.is_empty());
        assert!(wc.ops.is_empty());
        assert!(wc.capability_id.is_none());
    }

    #[test]
    fn postgres_read_policy_keys_round_trip() {
        let text = r#"
[postgres.read]
dsn_env = "PG_READ"
source = "todos"
fields = "id,account_id,title,done"
row_limit = "50"
capability = "IO.PostgresRead"
"#;
        let cfg = parse_host_config(text).expect("valid");
        let rc = cfg.postgres_read.unwrap();
        assert_eq!(rc.dsn_env, "PG_READ");
        assert_eq!(rc.source.as_deref(), Some("todos"));
        assert_eq!(rc.fields, vec!["id", "account_id", "title", "done"]);
        assert_eq!(rc.row_limit, 50);
        assert_eq!(rc.capability_id.as_deref(), Some("IO.PostgresRead"));
    }

    #[test]
    fn postgres_read_defaults_row_limit_to_100() {
        let text = "[postgres.read]\ndsn_env = \"PG_R\"\n";
        let cfg = parse_host_config(text).expect("valid");
        assert_eq!(cfg.postgres_read.unwrap().row_limit, 100);
    }

    #[test]
    fn postgres_read_extra_sources_parse() {
        // P38: a primary `[postgres.read]` source plus an extra `[postgres.read.accounts]` source.
        let text = r#"
[postgres.read]
dsn_env = "PG_READ"
source = "todos"
fields = "id,account_id,title,done"
capability = "IO.PostgresRead"

[postgres.read.accounts]
fields = "id,name"
"#;
        let cfg = parse_host_config(text).expect("valid");
        let rc = cfg.postgres_read.unwrap();
        assert_eq!(rc.source.as_deref(), Some("todos"));
        assert_eq!(
            rc.extra_sources,
            vec![(
                "accounts".to_string(),
                vec!["id".to_string(), "name".to_string()]
            )]
        );
    }

    #[test]
    fn postgres_read_field_kinds_parse_for_primary_and_extra_sources() {
        let text = r#"
[postgres.read]
dsn_env = "PG_READ"
source = "todos"
fields = "id,title,done,amount"

[postgres.read.todos.fields]
done = "bool"
amount = "decimal:2"

[postgres.read.accounts]
fields = "id,rank"

[postgres.read.accounts.fields]
rank = "integer"
"#;
        let cfg = parse_host_config(text).expect("valid typed read config");
        let rc = cfg.postgres_read.unwrap();
        assert_eq!(
            rc.field_kinds["todos"]["done"],
            PostgresReadValueKind::Boolean
        );
        assert_eq!(
            rc.field_kinds["todos"]["amount"],
            PostgresReadValueKind::Decimal { scale: 2 }
        );
        assert_eq!(
            rc.field_kinds["accounts"]["rank"],
            PostgresReadValueKind::Integer
        );
    }

    #[test]
    fn postgres_read_field_kind_missing_scale_fails_closed() {
        let err = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\nfields = \"amount\"\n\
             [postgres.read.todos.fields]\namount = \"decimal\"\n",
        )
        .unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn postgres_read_unknown_field_kind_fails_closed() {
        let err = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\nfields = \"done\"\n\
             [postgres.read.todos.fields]\ndone = \"timestamp\"\n",
        )
        .unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn postgres_read_field_kind_for_unallowlisted_field_fails_closed() {
        let err = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\nfields = \"id\"\n\
             [postgres.read.todos.fields]\ndone = \"bool\"\n",
        )
        .unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn postgres_read_field_kind_for_unknown_source_fails_closed() {
        let err = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\nfields = \"id\"\n\
             [postgres.read.accounts.fields]\nid = \"text\"\n",
        )
        .unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn postgres_read_extra_source_empty_name_rejected() {
        let err = parse_host_config("[postgres.read.]\nfields = \"x\"\n").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownSection(_)));
    }

    #[test]
    fn unknown_key_in_postgres_write_p24_fails_closed() {
        let err = parse_host_config("[postgres.write]\ndsn_env = \"V\"\ncpu = \"4\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownKey { .. }));
    }

    #[test]
    fn unknown_key_in_postgres_read_p24_fails_closed() {
        let err =
            parse_host_config("[postgres.read]\ndsn_env = \"V\"\nindex = \"btree\"").unwrap_err();
        assert!(matches!(err, HostConfigError::UnknownKey { .. }));
    }

    #[test]
    fn empty_targets_value_fails_closed() {
        let err =
            parse_host_config("[postgres.write]\ndsn_env = \"V\"\ntargets = \"\"").unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn trailing_comma_in_ops_fails_closed() {
        let err =
            parse_host_config("[postgres.write]\ndsn_env = \"V\"\nops = \"insert,\"").unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn empty_source_fails_closed() {
        let err = parse_host_config("[postgres.read]\ndsn_env = \"V\"\nsource = \"\"").unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn non_integer_row_limit_fails_closed() {
        let err = parse_host_config("[postgres.read]\ndsn_env = \"V\"\nrow_limit = \"many\"")
            .unwrap_err();
        assert!(matches!(err, HostConfigError::Parse(_)));
    }

    #[test]
    fn empty_capability_fails_closed() {
        for text in &[
            "[postgres.write]\ndsn_env = \"V\"\ncapability = \"\"",
            "[postgres.read]\ndsn_env = \"V\"\ncapability = \"\"",
        ] {
            let err = parse_host_config(text).unwrap_err();
            assert!(
                matches!(err, HostConfigError::Parse(_)),
                "empty capability must fail closed; text={text}"
            );
        }
    }

    #[test]
    fn comma_list_whitespace_trimmed() {
        let text = "[postgres.write]\ndsn_env = \"V\"\ntargets = \" todos , users \"\n";
        let cfg = parse_host_config(text).expect("valid");
        assert_eq!(cfg.postgres_write.unwrap().targets, vec!["todos", "users"]);
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

    /// P28: the committed operator example must always parse, carry both Postgres sections and both
    /// Todo effect targets, and remain secret-free (parser already rejects inline secrets, so a
    /// successful parse proves the example holds env-var NAMES only).
    #[test]
    fn committed_host_example_toml_parses() {
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("examples/todo_postgres_app/host.example.toml");
        let cfg = load_host_config(&path).expect("host.example.toml must parse");
        assert_eq!(cfg.host_mode.as_deref(), Some("loopback"));

        let rc = cfg.postgres_read.expect("[postgres.read] present");
        assert_eq!(rc.dsn_env, "IGNITER_TODO_PG_DSN");
        assert_eq!(rc.source.as_deref(), Some("todos"));
        assert_eq!(rc.fields, vec!["id", "account_id", "title", "done"]);
        assert_eq!(rc.row_limit, 100);
        assert_eq!(rc.capability_id.as_deref(), Some("IO.PostgresRead"));

        let wc = cfg.postgres_write.expect("[postgres.write] present");
        assert_eq!(wc.dsn_env, "IGNITER_TODO_PG_DSN");
        assert_eq!(wc.targets, vec!["todos"]);
        assert_eq!(wc.ops, vec!["insert", "upsert", "delete"]);
        assert_eq!(wc.capability_id.as_deref(), Some("IO.TodoWrite"));
        assert_eq!(wc.key_column.as_deref(), Some("id"));
        assert_eq!(wc.columns, vec!["account_id", "title", "done"]);

        for target in ["todo-create", "todo-done", "todo-delete"] {
            let ec = cfg.effects.get(target).expect("effect target present");
            assert_eq!(ec.route, "/w");
            assert_eq!(
                ec.passport_env.as_deref(),
                Some("IGNITER_TODO_EFFECT_TOKEN")
            );
        }
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
        let cfg = parse_host_config("[postgres.read]\ndsn_env = \"MISSING_VAR\"\n").unwrap();
        let err = resolve_with_env(&cfg, |_| None).unwrap_err();
        assert!(
            matches!(&err, HostConfigError::EnvVar { var_name, .. } if var_name == "MISSING_VAR")
        );
    }

    #[test]
    fn resolve_empty_env_var_returns_error() {
        let cfg = parse_host_config("[effects.x]\nroute = \"/w\"\npassport_env = \"EMPTY_VAR\"\n")
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
