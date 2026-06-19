// src/packs/auth.rs
// Security, Role-Based Access Control (RBAC) & Store Isolation (ACLs) Pack for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack};
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

// ── Security Data Models ─────────────────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct TokenConfig {
    pub token: String,
    pub role: String,                // admin, read_only, write_only, peer
    pub allowed_stores: Vec<String>, // e.g. ["*"] or specific whitelists
    #[serde(default)]
    pub persist: bool,
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

        let reg = self.registry.read();
        let config = reg
            .tokens
            .get(token_val)
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
                let allowed_ops = ["ping", "write_fact"];
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

fn load_persistent_tokens(dir_path: &str) -> HashMap<String, TokenConfig> {
    let mut map = HashMap::new();
    let sec_dir = format!("{}/security", dir_path);
    let _ = std::fs::create_dir_all(&sec_dir);

    if let Ok(entries) = std::fs::read_dir(&sec_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map_or(false, |ext| ext == "json") {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(mut config) = serde_json::from_str::<TokenConfig>(&content) {
                        println!(
                            "[Security Preloader] Preloaded token '{}' (role: {})",
                            config.token, config.role
                        );
                        config.persist = true;
                        map.insert(config.token.clone(), config);
                    }
                }
            }
        }
    }

    if map.is_empty() {
        // Ephemeral/First boot: populate default admin token
        let default_admin = TokenConfig {
            token: "admin_default".to_string(),
            role: "admin".to_string(),
            allowed_stores: vec!["*".to_string()],
            persist: true,
        };
        let file_path = format!("{}/admin_default.json", sec_dir);
        if let Ok(content) = serde_json::to_string_pretty(&default_admin) {
            let _ = std::fs::write(&file_path, content);
        }
        println!(
            "[Security Preloader] Generated default administrator token 'admin_default' at: {}",
            file_path
        );
        map.insert(default_admin.token.clone(), default_admin);
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
        // 1. Scan and preload tokens
        if let Some(ref dir) = kernel.data_dir {
            let loaded = load_persistent_tokens(dir);
            self.registry.write().tokens.extend(loaded);
        } else {
            // Ephemeral Mode: preload admin_default strictly in-memory
            let default_admin = TokenConfig {
                token: "admin_default".to_string(),
                role: "admin".to_string(),
                allowed_stores: vec!["*".to_string()],
                persist: false,
            };
            self.registry
                .write()
                .tokens
                .insert(default_admin.token.clone(), default_admin);
            println!("[Security Preloader] Ephemeral in-memory default administrator token 'admin_default' generated.");
        }

        let command_reg = &mut *kernel.command_registry.write();

        // 2. Register "auth_token_create" Route
        let registry_c = self.registry.clone();
        let data_dir_c = kernel.data_dir.clone();
        command_reg.register("auth_token_create", Arc::new(move |req, _kernel| {
            let token = match req.get("target_token").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'target_token' parameter" }),
            };
            let role = match req.get("target_role").and_then(|v| v.as_str()) {
                Some(r) => r.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'target_role' parameter" }),
            };
            let allowed_stores_arr = match req.get("allowed_stores").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'allowed_stores' array" }),
            };

            let persist = req.get("persist").and_then(|v| v.as_bool()).unwrap_or(false);

            let config = TokenConfig {
                token: token.clone(),
                role,
                allowed_stores: allowed_stores_arr,
                persist,
            };

            if persist {
                if let Some(ref dir) = data_dir_c {
                    let file_path = format!("{}/security/{}.json", dir, token);
                    if let Ok(content) = serde_json::to_string_pretty(&config) {
                        let _ = std::fs::write(file_path, content);
                    }
                }
            }

            registry_c.write().tokens.insert(token.clone(), config);
            serde_json::json!({ "ok": true })
        }));

        // 3. Register "auth_token_list" Route
        let registry_c = self.registry.clone();
        command_reg.register(
            "auth_token_list",
            Arc::new(move |_req, _kernel| {
                let map = registry_c.read();
                let list: Vec<TokenConfig> = map.tokens.values().cloned().collect();
                serde_json::json!({ "ok": true, "tokens": list })
            }),
        );

        // 4. Register "auth_token_delete" Route
        let registry_c = self.registry.clone();
        let data_dir_c = kernel.data_dir.clone();
        command_reg.register("auth_token_delete", Arc::new(move |req, _kernel| {
            let token = match req.get("target_token").and_then(|v| v.as_str()) {
                Some(t) => t,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'target_token' parameter" }),
            };

            // Prevent deleting the last admin token to avoid lockout
            {
                let map = registry_c.read();
                if map.tokens.len() <= 1 && map.tokens.contains_key(token) {
                    return serde_json::json!({ "ok": false, "error": "Cannot delete the last remaining active token (Lockout Prevention)" });
                }
            }

            let mut map = registry_c.write();
            if let Some(config) = map.tokens.remove(token) {
                if config.persist {
                    if let Some(ref dir) = data_dir_c {
                        let file_path = format!("{}/security/{}.json", dir, token);
                        let _ = std::fs::remove_file(file_path);
                    }
                }
                serde_json::json!({ "ok": true })
            } else {
                serde_json::json!({ "ok": false, "error": "Token not found" })
            }
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
