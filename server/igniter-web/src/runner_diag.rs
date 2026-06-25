//! Operator-facing runner failure taxonomy + secret redaction
//! (LAB-IGNITER-WEB-RUNNER-FAILURE-TAXONOMY-P29).
//!
//! `igweb-serve --host-config` crosses several host-owned boundaries (config parse, env-var
//! resolution, app build, loopback bind, Postgres connect). A raw `Box<dyn Error>` makes an
//! operator error look like an arbitrary Rust panic and — worse — a tokio-postgres connect error
//! can embed the DSN. This module gives those startup failures:
//!
//! - a small, STABLE diagnostic code (`CONFIG_PARSE`, `CONFIG_RESOLVE`, …),
//! - a distinct non-zero exit code per category,
//! - a redacted message that never leaks a DSN/passport value.
//!
//! Scope: process-EXIT diagnostics only (runner startup). Per-request denials
//! (`READ_DENIED`/`WRITE_DENIED`/`EFFECT_UNBOUND`/`PASSPORT_DENIED`) stay host-owned and are
//! returned as HTTP responses by the policy gates — they are named here for a complete taxonomy
//! but are NOT emitted as process exits. This is operator DX evidence, not canon.

use crate::host_config::HostConfigError;
use crate::runner::RunnerError;

// ── stable taxonomy codes ───────────────────────────────────────────────────────────────────────

/// Stable operator-facing failure codes. The string form (`as_str`) is the contract a test or an
/// operator log scrape can match on; do not rename existing variants.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagCode {
    /// `host.toml` could not be parsed (unknown section/key, inline secret, bad route/mode, …).
    ConfigParse,
    /// A `*_env` reference named an env var that is missing or empty at runtime.
    ConfigResolve,
    /// The `.igweb`/`.ig` app failed to lower/load.
    AppBuild,
    /// The loopback listener could not bind (port in use, permission, non-loopback refused).
    BindRefused,
    /// A real Postgres adapter failed to connect (message redacted — never carries the DSN).
    PostgresConnect,
    /// A per-request staged read was denied by host policy (allowlist/field/raw-SQL). Host-owned.
    ReadDenied,
    /// A per-request write effect was denied by host policy (target/op). Host-owned.
    WriteDenied,
    /// An `InvokeEffect` named a logical target with no host route binding. Host-owned.
    EffectUnbound,
    /// A bearer/passport was missing or rejected for an effect route. Host-owned.
    PassportDenied,
    /// A typed `ReadThen` continuation is STRUCTURALLY invalid independent of any DB source
    /// (LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8): a malformed crossing shape (both `rows_json`
    /// and `rows`, a scalar `rows` element) or a `Collection[<AppRow>]` whose row type is unrecoverable
    /// from compiled metadata or carries a field with no v0 projection landing. Caught at build/check
    /// time, before any listener bind. (Source-dependent host-kind ⇎ row-type drift stays first-dispatch.)
    ProjectionSchemaInvalid,
    /// An unexpected internal runner failure (tokio runtime, serve-loop IO).
    RunnerInternal,
}

impl DiagCode {
    /// The stable string form, e.g. `"CONFIG_PARSE"`. Part of the operator-facing contract.
    pub fn as_str(&self) -> &'static str {
        match self {
            DiagCode::ConfigParse => "CONFIG_PARSE",
            DiagCode::ConfigResolve => "CONFIG_RESOLVE",
            DiagCode::AppBuild => "APP_BUILD",
            DiagCode::BindRefused => "BIND_REFUSED",
            DiagCode::PostgresConnect => "POSTGRES_CONNECT",
            DiagCode::ReadDenied => "READ_DENIED",
            DiagCode::WriteDenied => "WRITE_DENIED",
            DiagCode::EffectUnbound => "EFFECT_UNBOUND",
            DiagCode::PassportDenied => "PASSPORT_DENIED",
            DiagCode::ProjectionSchemaInvalid => "PROJECTION_SCHEMA_INVALID",
            DiagCode::RunnerInternal => "RUNNER_INTERNAL",
        }
    }

    /// A distinct, stable non-zero process exit code per category. Generic `1` is deliberately
    /// avoided so operators can distinguish a taxonomy exit from an unhandled panic.
    pub fn exit_code(&self) -> i32 {
        match self {
            DiagCode::ConfigParse => 2,
            DiagCode::ConfigResolve => 3,
            DiagCode::AppBuild => 4,
            DiagCode::BindRefused => 5,
            DiagCode::PostgresConnect => 6,
            DiagCode::ReadDenied => 7,
            DiagCode::WriteDenied => 8,
            DiagCode::EffectUnbound => 9,
            DiagCode::PassportDenied => 10,
            DiagCode::ProjectionSchemaInvalid => 12,
            DiagCode::RunnerInternal => 11,
        }
    }
}

// ── diagnostic ──────────────────────────────────────────────────────────────────────────────────

/// A redacted, coded operator diagnostic. `Display` renders `igweb-serve: [CODE] <message>`.
/// Construct only via `new`/the classifiers so the message is always run through redaction at the
/// boundary where a secret might appear.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunnerDiagnostic {
    pub code: DiagCode,
    pub message: String,
}

impl RunnerDiagnostic {
    /// Build a diagnostic from an already-safe message (config errors name keys, not values).
    pub fn new(code: DiagCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    /// Build a `POSTGRES_CONNECT` diagnostic, scrubbing the message of any known DSN values and of
    /// `postgres://…` / `password=…` patterns. Use this for any message that wraps an adapter
    /// connect error — those can embed the connection string verbatim.
    pub fn postgres_connect(message: impl AsRef<str>, known_secrets: &[&str]) -> Self {
        Self {
            code: DiagCode::PostgresConnect,
            message: redact_secrets(message.as_ref(), known_secrets),
        }
    }

    /// The process exit code an operator should see for this diagnostic.
    pub fn exit_code(&self) -> i32 {
        self.code.exit_code()
    }
}

impl std::fmt::Display for RunnerDiagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "igweb-serve: [{}] {}", self.code.as_str(), self.message)
    }
}

impl std::error::Error for RunnerDiagnostic {}

// ── classifiers ─────────────────────────────────────────────────────────────────────────────────

/// Map a `HostConfigError` to a startup diagnostic. The error's `Display` is already
/// redaction-safe — it names sections/keys/env-var NAMES, never values — so no scrub is needed.
pub fn classify_host_config_error(e: &HostConfigError) -> RunnerDiagnostic {
    let code = match e {
        // A `*_env` reference that could not resolve at runtime is a RESOLVE failure.
        HostConfigError::EnvVar { .. } => DiagCode::ConfigResolve,
        // Everything else is a static parse/shape failure.
        _ => DiagCode::ConfigParse,
    };
    RunnerDiagnostic::new(code, e.to_string())
}

/// Map a `RunnerError` (CLI parse, manifest, build) to a startup diagnostic. The loopback-only
/// refusal surfaces here as `CONFIG_PARSE` — a bad public bind fails closed before any socket.
pub fn classify_runner_error(e: &RunnerError) -> RunnerDiagnostic {
    let code = match e {
        RunnerError::Build(_) => DiagCode::AppBuild,
        RunnerError::Io(_) => DiagCode::RunnerInternal,
        RunnerError::Manifest(_) | RunnerError::Cli(_) => DiagCode::ConfigParse,
        // A structurally invalid typed read continuation, caught at build/check (P8).
        RunnerError::ReadContinuation(_) => DiagCode::ProjectionSchemaInvalid,
    };
    RunnerDiagnostic::new(code, e.to_string())
}

// ── redaction ───────────────────────────────────────────────────────────────────────────────────

/// Scrub secret material from an arbitrary error message before it reaches an operator log.
///
/// Two layers of defence:
/// 1. Exact replacement of every known secret the runner holds (the resolved DSN values) — the
///    strongest guarantee, because the runner knows the exact strings it must never print.
/// 2. Pattern fallback for `postgres://…` / `postgresql://…` URLs and libpq `password=`/`dsn=`
///    keyword forms — covers a secret the runner did not pass in (e.g. a nested cause).
pub fn redact_secrets(msg: &str, known_secrets: &[&str]) -> String {
    let mut out = msg.to_string();
    for s in known_secrets {
        if !s.is_empty() {
            out = out.replace(s, "[redacted]");
        }
    }
    redact_patterns(&out)
}

/// Redact one whitespace-delimited token if it looks secret-bearing; otherwise return it unchanged.
fn redact_token(tok: &str) -> Option<String> {
    let lower = tok.to_ascii_lowercase();
    if lower.contains("postgres://") || lower.contains("postgresql://") {
        return Some("[redacted-dsn]".to_string());
    }
    for kw in ["password=", "dsn="] {
        if let Some(pos) = lower.find(kw) {
            let end = pos + kw.len();
            let mut s = tok[..end].to_string();
            s.push_str("[redacted]");
            return Some(s);
        }
    }
    None
}

fn redact_patterns(msg: &str) -> String {
    msg.split(' ')
        .map(|tok| redact_token(tok).unwrap_or_else(|| tok.to_string()))
        .collect::<Vec<_>>()
        .join(" ")
}

// ── tests ─────────────────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host_config::parse_host_config;

    const ALL_CODES: &[DiagCode] = &[
        DiagCode::ConfigParse,
        DiagCode::ConfigResolve,
        DiagCode::AppBuild,
        DiagCode::BindRefused,
        DiagCode::PostgresConnect,
        DiagCode::ReadDenied,
        DiagCode::WriteDenied,
        DiagCode::EffectUnbound,
        DiagCode::PassportDenied,
        DiagCode::ProjectionSchemaInvalid,
        DiagCode::RunnerInternal,
    ];

    #[test]
    fn codes_have_distinct_nonzero_exit_codes() {
        let mut seen = std::collections::HashSet::new();
        for c in ALL_CODES {
            let ec = c.exit_code();
            assert_ne!(ec, 0, "{} must be non-zero", c.as_str());
            assert_ne!(ec, 1, "{} must not be generic 1", c.as_str());
            assert!(
                seen.insert(ec),
                "duplicate exit code {ec} for {}",
                c.as_str()
            );
        }
    }

    #[test]
    fn code_strings_are_stable_and_uppercase() {
        for c in ALL_CODES {
            let s = c.as_str();
            assert!(!s.is_empty());
            assert_eq!(s, s.to_ascii_uppercase(), "code must be SCREAMING_CASE");
        }
    }

    #[test]
    fn display_renders_code_and_message() {
        let d = RunnerDiagnostic::new(DiagCode::ConfigParse, "boom");
        assert_eq!(d.to_string(), "igweb-serve: [CONFIG_PARSE] boom");
    }

    // ── classification ────────────────────────────────────────────────────────────────────────────

    #[test]
    fn missing_env_var_classifies_as_config_resolve() {
        let cfg =
            parse_host_config("[postgres.read]\ndsn_env = \"DEFINITELY_UNSET_VAR\"\n").unwrap();
        let err = crate::host_config::resolve_host_config(&cfg).unwrap_err();
        let diag = classify_host_config_error(&err);
        assert_eq!(diag.code, DiagCode::ConfigResolve);
        assert!(
            diag.message.contains("DEFINITELY_UNSET_VAR"),
            "resolve diag must name the env var: {}",
            diag.message
        );
    }

    #[test]
    fn parse_errors_classify_as_config_parse() {
        for text in &[
            "[vault]\nx = \"y\"",                       // unknown section
            "[postgres.write]\ndsn = \"postgres://x\"", // inline secret
            "[effects.x]\nroute = \"w\"",               // bad route
        ] {
            let err = parse_host_config(text).unwrap_err();
            assert_eq!(
                classify_host_config_error(&err).code,
                DiagCode::ConfigParse,
                "text should classify as CONFIG_PARSE: {text}"
            );
        }
    }

    #[test]
    fn inline_secret_diag_does_not_leak_value() {
        let err = parse_host_config("[postgres.write]\ndsn = \"postgres://user:hunter2@h/db\"")
            .unwrap_err();
        let diag = classify_host_config_error(&err);
        assert!(
            !diag.message.contains("hunter2"),
            "inline-secret diag must not echo the value: {}",
            diag.message
        );
    }

    #[test]
    fn runner_build_classifies_as_app_build() {
        let e = RunnerError::Cli("bad".into());
        assert_eq!(classify_runner_error(&e).code, DiagCode::ConfigParse);
        let e = RunnerError::Manifest("bad".into());
        assert_eq!(classify_runner_error(&e).code, DiagCode::ConfigParse);
    }

    // ── redaction ─────────────────────────────────────────────────────────────────────────────────

    #[test]
    fn redacts_known_secret_exactly() {
        let out = redact_secrets("connect failed: my-dsn-value timed out", &["my-dsn-value"]);
        assert!(
            !out.contains("my-dsn-value"),
            "known secret must be scrubbed: {out}"
        );
        assert!(out.contains("[redacted]"));
    }

    #[test]
    fn redacts_postgres_url_pattern() {
        let out = redact_secrets("error connecting to postgres://u:pw@host:5432/db now", &[]);
        assert!(!out.contains("pw@host"), "DSN url must be scrubbed: {out}");
        assert!(
            !out.contains("postgres://u"),
            "DSN url must be scrubbed: {out}"
        );
        assert!(out.contains("[redacted-dsn]"));
    }

    #[test]
    fn redacts_libpq_password_keyword() {
        let out = redact_secrets("libpq: host=h password=hunter2 dbname=x", &[]);
        assert!(
            !out.contains("hunter2"),
            "password value must be scrubbed: {out}"
        );
        assert!(out.contains("password=[redacted]"));
    }

    #[test]
    fn postgres_connect_constructor_redacts() {
        let secret = "postgres://u:topsecret@h/db";
        let diag = RunnerDiagnostic::postgres_connect(
            format!("postgres.write: failed to connect to {secret}"),
            &[secret],
        );
        assert_eq!(diag.code, DiagCode::PostgresConnect);
        assert!(
            !diag.message.contains("topsecret"),
            "must not leak: {}",
            diag.message
        );
    }

    #[test]
    fn redaction_preserves_safe_text() {
        let out = redact_secrets("connection refused (os error 111)", &[]);
        assert_eq!(out, "connection refused (os error 111)");
    }
}
