// src/packs/auth.rs
// Security, Role-Based Access Control (RBAC) & Store Isolation (ACLs) Pack for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack};
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

// ── Security Data Models ─────────────────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct TokenConfig {
    // LAB-TBACKEND-AUTH-STORAGE-HARDENING-P9: storage holds NO plaintext token. `id` and `token_hash`
    // have no serde default, so a legacy P6A/P8 file (which carries `token` and lacks these) fails to
    // deserialize and is refused at load (fail-closed). The bearer token never lands on disk.
    /// Opaque short id (first 16 hex of `token_hash`) — safe to expose in list/delete responses.
    pub id: String,
    /// blake3 hex of the bearer token. Preimage-resistant: neither the filename (`<token_hash>.json`)
    /// nor this body reveal the plaintext token.
    pub token_hash: String,
    pub role: String,                // admin, read_only, write_only, peer
    pub allowed_stores: Vec<String>, // e.g. ["*"] or specific whitelists
    #[serde(default)]
    pub persist: bool,
    /// Optional human label (never secret).
    #[serde(default)]
    pub label: Option<String>,
}

// ── P9 token hashing / generation ────────────────────────────────────────────
// Storage holds only blake3(token), never the bearer token. Generated tokens are high-entropy
// (256 bits from two UUIDv4), so a fast hash is sufficient here — no password KDF (card P9 §2).

fn token_hash(token: &str) -> String {
    blake3::hash(token.as_bytes()).to_hex().to_string()
}

/// Short opaque id derived from the full hash: 16 hex (64 bits). Collision-safe for a lab token set and
/// safe to expose; the on-disk file still uses the full hash, so there is no filename collision.
fn short_id(hash: &str) -> String {
    hash[..16].to_string()
}

/// Generate a high-entropy bearer token (256 bits). Returned to the caller exactly once.
fn generate_token() -> String {
    format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    )
}

/// Build a stored config from a plaintext token without retaining the token itself.
fn make_token_config(
    token: &str,
    role: String,
    allowed_stores: Vec<String>,
    persist: bool,
    label: Option<String>,
) -> TokenConfig {
    let h = token_hash(token);
    let id = short_id(&h);
    TokenConfig {
        id,
        token_hash: h,
        role,
        allowed_stores,
        persist,
        label,
    }
}

pub struct TokenRegistry {
    pub tokens: HashMap<String, TokenConfig>,
}

impl TokenRegistry {
    pub fn new() -> Self {
        Self {
            tokens: HashMap::new(),
        }
    }
}

// ── Store Access Check Helper ────────────────────────────────────────────────

fn has_store_access(store: &str, config: &TokenConfig) -> bool {
    config.allowed_stores.iter().any(|s| s == "*" || s == store)
}

// ── Auth Middleware Interceptor (ROP Flow Control) ───────────────────────────

pub struct AuthMiddleware {
    registry: Arc<RwLock<TokenRegistry>>,
}

impl crate::kernel::RequestMiddleware for AuthMiddleware {
    fn before_request(
        &self,
        req: &mut serde_json::Value,
        _kernel: &ServerKernel,
    ) -> Result<(), String> {
        if !_kernel.auth_enabled {
            return Ok(());
        }

        let op = req.get("op").and_then(|v| v.as_str()).unwrap_or("");

        // Every request must supply a valid token
        let token_val = match req.get("token").and_then(|v| v.as_str()) {
            Some(t) => t,
            None => return Err("Authentication failed: missing 'token' parameter".to_string()),
        };

        // P9: look up by blake3(presented token); the plaintext token is never stored or compared.
        let reg = self.registry.read();
        let config = reg
            .tokens
            .get(&token_hash(token_val))
            .ok_or_else(|| "Authentication failed: invalid token".to_string())?;

        // 1. Verify Role Permissions (RBAC)
        match config.role.as_str() {
            "admin" => {
                // Admin role has unrestricted access to all operations
            }
            "read_only" => {
                let allowed_ops = [
                    "ping",
                    "latest_for",
                    "facts_for",
                    "query_scope",
                    "size",
                    "stores",
                    "diagnostics_summary",
                    "diagnostics_stores",
                    "query_slice",
                    "analytics_aggregate",
                    "analytics_calculate",
                    "analytics_metrics",
                    "cross_store_query",
                    "cross_store_join",
                ];
                if !allowed_ops.contains(&op) {
                    return Err(format!(
                        "Access denied: role 'read_only' cannot execute operation '{}'",
                        op
                    ));
                }
            }
            "write_only" => {
                let allowed_ops = ["ping", "write_fact", "write_fact_once"];
                if !allowed_ops.contains(&op) {
                    return Err(format!(
                        "Access denied: role 'write_only' cannot execute operation '{}'",
                        op
                    ));
                }
            }
            "peer" => {
                let allowed_ops = ["ping", "mesh_ping", "mesh_gossip", "mesh_sync_pull"];
                if !allowed_ops.contains(&op) {
                    return Err(format!(
                        "Access denied: role 'peer' cannot execute operation '{}'",
                        op
                    ));
                }
            }
            _ => return Err(format!("Access denied: unknown role '{}'", config.role)),
        }

        // 2. Verify Store Access Control Lists (ACLs)
        let target_store = if let Some(s) = req.get("store").and_then(|v| v.as_str()) {
            Some(s)
        } else if let Some(f) = req.get("fact") {
            f.get("store").and_then(|v| v.as_str())
        } else if let Some(qs) = req.get("queries").and_then(|v| v.as_array()) {
            // Check every query in a cross-store query
            for q in qs {
                if let Some(s) = q.get("store").and_then(|v| v.as_str()) {
                    if !has_store_access(s, config) {
                        return Err(format!(
                            "Access denied: token not authorized for store '{}'",
                            s
                        ));
                    }
                }
            }
            None
        } else if let (Some(ls), Some(rs)) = (
            req.get("left_store").and_then(|v| v.as_str()),
            req.get("right_store").and_then(|v| v.as_str()),
        ) {
            // Check both stores in a cross-store join
            if !has_store_access(ls, config) {
                return Err(format!(
                    "Access denied: token not authorized for left store '{}'",
                    ls
                ));
            }
            if !has_store_access(rs, config) {
                return Err(format!(
                    "Access denied: token not authorized for right store '{}'",
                    rs
                ));
            }
            None
        } else {
            None
        };

        if let Some(store) = target_store {
            if !has_store_access(store, config) {
                return Err(format!(
                    "Access denied: token not authorized for store '{}'",
                    store
                ));
            }
        }

        Ok(())
    }

    fn after_response(
        &self,
        _req: &serde_json::Value,
        _resp: &mut serde_json::Value,
        _kernel: &ServerKernel,
    ) {
    }
}

// ── Persistent Preloading Scanner ────────────────────────────────────────────

// ── LAB-TBACKEND-AUTH-REDACTION-P8: token-file permission hardening ──────────────────────────────────
// The persistent token store is secret material (the filename IS the bearer token until P9 reworks storage).
// Lock `security/` to 0700 and every token file to 0600 so the daemon never leaves token material readable.
// macOS + Linux are both `unix`; non-unix is a documented no-op (dev only).

#[cfg(unix)]
fn set_mode(path: &std::path::Path, mode: u32) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
}
#[cfg(not(unix))]
fn set_mode(_path: &std::path::Path, _mode: u32) -> std::io::Result<()> {
    Ok(()) // permissions are a Unix concern; no-op on other platforms (dev only)
}

/// Write a token JSON file `0600` (creating the parent `security/` dir `0700`). On Unix the file is created
/// `0600` and re-`chmod`ed in case it pre-existed with looser perms. Permission failures surface as a warning
/// rather than silently claiming hardening.
fn secure_write_token(path: &std::path::Path, content: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
        if let Err(e) = set_mode(parent, 0o700) {
            eprintln!(
                "[Security] WARNING: could not set 0700 on {:?}: {}",
                parent, e
            );
        }
    }
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)?;
        f.write_all(content.as_bytes())?;
    }
    #[cfg(not(unix))]
    {
        std::fs::write(path, content)?;
    }
    if let Err(e) = set_mode(path, 0o600) {
        eprintln!(
            "[Security] WARNING: could not set 0600 on {:?}: {}",
            path, e
        );
    }
    Ok(())
}

fn load_persistent_tokens(dir_path: &str) -> HashMap<String, TokenConfig> {
    let mut map = HashMap::new();
    let sec_dir = format!("{}/security", dir_path);
    let _ = std::fs::create_dir_all(&sec_dir);
    // P8: lock the security directory to 0700 on every startup.
    if let Err(e) = set_mode(std::path::Path::new(&sec_dir), 0o700) {
        eprintln!(
            "[Security] WARNING: could not set 0700 on {}: {}",
            sec_dir, e
        );
    }

    if let Ok(entries) = std::fs::read_dir(&sec_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            // P9: only new-format token files (`<token_hash>.json`, hash-only body) are accepted.
            // Legacy P6A/P8 files (named by the bearer token, body carrying `token`) lack `id`/`token_hash`
            // and fail to deserialize here — they are skipped (fail-closed), never loaded as credentials.
            if path.extension().map_or(false, |ext| ext == "json") {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    match serde_json::from_str::<TokenConfig>(&content) {
                        Ok(mut config) => {
                            // Never log token material; report the role only.
                            println!("[Security Preloader] Preloaded a '{}' token.", config.role);
                            // P8: repair perms of pre-existing token files to 0600.
                            if let Err(e) = set_mode(&path, 0o600) {
                                eprintln!(
                                    "[Security] WARNING: could not repair 0600 on a token file: {}",
                                    e
                                );
                            }
                            config.persist = true;
                            map.insert(config.token_hash.clone(), config);
                        }
                        Err(_) => {
                            // P9: refuse to load a token file that is not in the hash/id format.
                            eprintln!(
                                "[Security] WARNING: ignoring a token file not in the P9 hash/id format (fail-closed; re-create it with auth_token_create)."
                            );
                        }
                    }
                }
            }
        }
    }

    if map.is_empty() {
        // P9 bootstrap: no valid new-format tokens → mint a RANDOM one-time admin token (retires the
        // constant `admin_default`). Persist only its hash/id; write the plaintext exactly once to a
        // 0600 handoff file the operator reads, uses, then deletes.
        let token = generate_token();
        let config = make_token_config(
            &token,
            "admin".to_string(),
            vec!["*".to_string()],
            true,
            Some("bootstrap".to_string()),
        );
        let file_path = format!("{}/{}.json", sec_dir, config.token_hash);
        if let Ok(content) = serde_json::to_string_pretty(&config) {
            if let Err(e) = secure_write_token(std::path::Path::new(&file_path), &content) {
                eprintln!(
                    "[Security] WARNING: could not write bootstrap admin token metadata: {}",
                    e
                );
            }
        }
        let handoff = format!("{}/BOOTSTRAP_ADMIN_TOKEN", sec_dir);
        if let Err(e) = secure_write_token(std::path::Path::new(&handoff), &token) {
            eprintln!(
                "[Security] WARNING: could not write bootstrap handoff file: {}",
                e
            );
        }
        // Log the PATH and opaque id only — never the token value.
        println!(
            "[Security Preloader] Minted a random bootstrap admin token (id {}). Plaintext written once to {} — read it, use it, then delete it.",
            config.id, handoff
        );
        map.insert(config.token_hash.clone(), config);
    }

    map
}

// ── Auth Pack Mount ──────────────────────────────────────────────────────────

pub struct AuthPack {
    registry: Arc<RwLock<TokenRegistry>>,
}

impl AuthPack {
    pub fn new() -> Self {
        Self {
            registry: Arc::new(RwLock::new(TokenRegistry::new())),
        }
    }
}

impl ServerPack for AuthPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "auth",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["access_control", "rbac_enforcement"],
            requires_capabilities: vec!["audit"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        // 1. Scan and preload tokens only when auth is enabled. Auth-off dev and
        // Docker configs should not create `security/` or bootstrap handoff state.
        if kernel.auth_enabled {
            if let Some(ref dir) = kernel.data_dir {
                let loaded = load_persistent_tokens(dir);
                self.registry.write().tokens.extend(loaded);
            } else {
                // P9 Ephemeral Mode (no --data-dir): in-memory dev/test admin only. NOT production auth —
                // tokens cannot persist, so this uses a known dev constant CONFINED to the no-data-dir path
                // (never written to disk, gone on restart). Real auth must run with --data-dir (P9 bootstrap).
                let config = make_token_config(
                    "ephemeral_dev_admin",
                    "admin".to_string(),
                    vec!["*".to_string()],
                    false,
                    Some("ephemeral-dev".to_string()),
                );
                self.registry
                    .write()
                    .tokens
                    .insert(config.token_hash.clone(), config);
                eprintln!("[Security] WARNING: auth enabled without --data-dir; using an in-memory dev admin token (not for production — run with --data-dir for persistent P9 token storage).");
            }
        }

        let command_reg = &mut *kernel.command_registry.write();

        // 2. Register "auth_token_create" Route
        let registry_c = self.registry.clone();
        let data_dir_c = kernel.data_dir.clone();
        command_reg.register("auth_token_create", Arc::new(move |req, _kernel| {
            // P9: tokens are generated server-side. Reject legacy caller-supplied token material.
            if req.get("target_token").is_some() {
                return serde_json::json!({ "ok": false, "error": "'target_token' is no longer accepted: tokens are generated server-side and returned once (P9)" });
            }
            let role = match req.get("target_role").and_then(|v| v.as_str()) {
                Some(r) => r.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'target_role' parameter" }),
            };
            let allowed_stores_arr: Vec<String> = match req.get("allowed_stores").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'allowed_stores' array" }),
            };
            let persist = req.get("persist").and_then(|v| v.as_bool()).unwrap_or(false);
            let label = req.get("label").and_then(|v| v.as_str()).map(|s| s.to_string());

            // High-entropy server-generated token — shown to the caller exactly once.
            let token = generate_token();
            let config = make_token_config(&token, role.clone(), allowed_stores_arr.clone(), persist, label);

            if persist {
                if let Some(ref dir) = data_dir_c {
                    // P9: filename is the opaque hash, not the token value.
                    let file_path = format!("{}/security/{}.json", dir, config.token_hash);
                    if let Ok(content) = serde_json::to_string_pretty(&config) {
                        if let Err(e) =
                            secure_write_token(std::path::Path::new(&file_path), &content)
                        {
                            eprintln!("[Security] WARNING: could not persist token file: {}", e);
                        }
                    }
                }
            }

            let id = config.id.clone();
            registry_c.write().tokens.insert(config.token_hash.clone(), config);
            // The ONLY place the plaintext token is returned (shown once).
            serde_json::json!({
                "ok": true,
                "token": token,
                "id": id,
                "role": role,
                "allowed_stores": allowed_stores_arr,
                "persist": persist
            })
        }));

        // 3. Register "auth_token_list" Route
        let registry_c = self.registry.clone();
        command_reg.register(
            "auth_token_list",
            Arc::new(move |_req, _kernel| {
                // LAB-TBACKEND-AUTH-REDACTION-P8: inventory-only — never return the bearer token value
                // (nor a hash/prefix/filename). Metadata only: role, allowed_stores, persist + a count.
                let map = registry_c.read();
                let list: Vec<serde_json::Value> = map
                    .tokens
                    .values()
                    .map(|c| {
                        // P9: expose the opaque short id (for delete), never the token or full hash.
                        serde_json::json!({
                            "id": c.id,
                            "role": c.role,
                            "allowed_stores": c.allowed_stores,
                            "persist": c.persist,
                        })
                    })
                    .collect();
                serde_json::json!({ "ok": true, "count": list.len(), "tokens": list })
            }),
        );

        // 4. Register "auth_token_delete" Route
        let registry_c = self.registry.clone();
        let data_dir_c = kernel.data_dir.clone();
        command_reg.register("auth_token_delete", Arc::new(move |req, _kernel| {
            let mut map = registry_c.write();

            // P9: resolve the target token_hash from an opaque id (preferred). A deprecated plaintext
            // `target_token` is accepted only to derive its hash — it is never stored or echoed.
            let target_hash: String = if let Some(id) = req.get("target_id").and_then(|v| v.as_str()) {
                let matches: Vec<String> = map
                    .tokens
                    .values()
                    .filter(|c| c.id == id || c.token_hash.starts_with(id))
                    .map(|c| c.token_hash.clone())
                    .collect();
                match matches.len() {
                    1 => matches[0].clone(),
                    0 => return serde_json::json!({ "ok": false, "error": "Token not found" }),
                    _ => return serde_json::json!({ "ok": false, "error": "Ambiguous id: matches more than one token" }),
                }
            } else if let Some(t) = req.get("target_token").and_then(|v| v.as_str()) {
                token_hash(t)
            } else {
                return serde_json::json!({ "ok": false, "error": "Missing 'target_id' parameter" });
            };

            let config = match map.tokens.get(&target_hash) {
                Some(c) => c.clone(),
                None => return serde_json::json!({ "ok": false, "error": "Token not found" }),
            };

            // P9 last-admin guard: never delete the final admin token (lockout prevention).
            if config.role == "admin" {
                let admin_count = map.tokens.values().filter(|c| c.role == "admin").count();
                if admin_count <= 1 {
                    return serde_json::json!({ "ok": false, "error": "Cannot delete the last remaining admin token (Lockout Prevention)" });
                }
            }

            map.tokens.remove(&target_hash);
            if config.persist {
                if let Some(ref dir) = data_dir_c {
                    let file_path = format!("{}/security/{}.json", dir, config.token_hash);
                    let _ = std::fs::remove_file(file_path);
                }
            }
            serde_json::json!({ "ok": true, "id": config.id })
        }));

        // 5. Mount AuthMiddleware at the FRONT of the middleware chain
        kernel
            .middleware_chain
            .write()
            .register(Arc::new(AuthMiddleware {
                registry: self.registry.clone(),
            }));

        Ok(())
    }
}
