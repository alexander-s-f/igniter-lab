//! Secret providers (LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22).
//!
//! Credentials are host-injected via the `SecretProvider` trait (defined in `http`): a request
//! carries a `{{secret:name}}` REFERENCE, never the value; the host resolves it at the boundary
//! and the resolved value is redacted from every receipt/audit/result. P10/P11 proved redaction
//! with a map-only provider. P22 hardens the SOURCE: read from allowlisted env, or from a
//! traversal-safe file root, and layer/override them.
//!
//! `SecretProvider` IS the adapter interface a real external vault would implement (caching its
//! resolved secrets). P22 deliberately does NOT fake a vault — there is no external service in the
//! glass box; the env/file providers are the local, dependency-free implementations.

use crate::http::SecretProvider;
use std::collections::HashMap;
use std::path::PathBuf;

/// Reads secrets from process environment, but ONLY for allowlisted names. `resolve("api_token")`
/// returns `std::env::var` of the mapped env key iff `api_token` is allowlisted. A name not on the
/// allowlist returns `None` — a contract cannot pull arbitrary environment.
#[derive(Default)]
pub struct EnvSecretProvider {
    allow: HashMap<String, String>, // secret name -> env var name
}

impl EnvSecretProvider {
    pub fn new() -> Self {
        Self::default()
    }
    /// Allow secret `name`, sourced from environment variable `env_key`.
    pub fn allow(mut self, name: &str, env_key: &str) -> Self {
        self.allow.insert(name.to_string(), env_key.to_string());
        self
    }
}

impl SecretProvider for EnvSecretProvider {
    fn resolve(&self, name: &str) -> Option<String> {
        let env_key = self.allow.get(name)?;
        std::env::var(env_key).ok()
    }
}

/// Reads secrets from files under a configured root: `resolve("api_token")` → the trimmed contents
/// of `root/api_token`. **Path-traversal-safe**: a name with anything other than
/// `[A-Za-z0-9_-]` (so no `/`, `\`, `..`, or leading `.`) is rejected (`None`) — a contract cannot
/// read outside the root.
pub struct FileSecretProvider {
    root: PathBuf,
}

impl FileSecretProvider {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
    fn safe_name(name: &str) -> bool {
        !name.is_empty()
            && name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    }
}

impl SecretProvider for FileSecretProvider {
    fn resolve(&self, name: &str) -> Option<String> {
        if !Self::safe_name(name) {
            return None;
        }
        std::fs::read_to_string(self.root.join(name))
            .ok()
            .map(|s| s.trim().to_string())
    }
}

/// Tries layered providers in order; the first to resolve wins. Lets a deployment layer env over
/// file (or a test override a real source with a map). The adapter point for a future vault: add
/// it as another layer.
#[derive(Default)]
pub struct LayeredSecretProvider {
    layers: Vec<Box<dyn SecretProvider>>,
}

impl LayeredSecretProvider {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn layer(mut self, provider: Box<dyn SecretProvider>) -> Self {
        self.layers.push(provider);
        self
    }
}

impl SecretProvider for LayeredSecretProvider {
    fn resolve(&self, name: &str) -> Option<String> {
        self.layers.iter().find_map(|p| p.resolve(name))
    }
}
