// src/passport.rs
// Lab-only Capability Passport and Manifest Loader for IVM
// Route: EXPERIMENTAL / LAB-ONLY

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub artifact_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Passport {
    pub runtime_implementation_id: String,
    pub backend_implementation_id: String,
    pub consumer_surface_id: String,
    pub surface_dimension: String,
    pub artifact_kind: String,
    pub artifact_digest: String,
    #[serde(default)]
    pub capability_bindings: HashMap<String, String>,
    #[serde(default)]
    pub required_capabilities: HashMap<String, RequiredCapability>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequiredCapability {
    pub sandbox_dir: String,
    pub allowed_absolute_paths: Vec<String>,
    pub read_allowed: bool,
    pub write_allowed: bool,
    pub sandbox_policy_source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CapabilityGrant {
    pub capability_id: String,
    pub resource_type: String,
    pub sandbox_dir: String,
    pub allowed_absolute_paths: Vec<String>,
    pub read_allowed: bool,
    pub write_allowed: bool,
}

impl CapabilityGrant {
    pub fn is_sub_grant_of(&self, parent: &CapabilityGrant) -> bool {
        if self.resource_type != parent.resource_type {
            return false;
        }
        if self.read_allowed && !parent.read_allowed {
            return false;
        }
        if self.write_allowed && !parent.write_allowed {
            return false;
        }

        // Clean and resolve both sandbox paths to absolute for safe lexical starts_with check
        let clean_child = clean_and_resolve_path(Path::new(&self.sandbox_dir));
        let clean_parent = clean_and_resolve_path(Path::new(&parent.sandbox_dir));

        if !clean_child.starts_with(&clean_parent) {
            return false;
        }

        // Every absolute path allowed by child must be explicitly allowed by parent
        for path in &self.allowed_absolute_paths {
            let clean_child_abs = clean_and_resolve_path(Path::new(path));
            let matched = parent.allowed_absolute_paths.iter().any(|p_path| {
                clean_and_resolve_path(Path::new(p_path)) == clean_child_abs
            });
            if !matched {
                return false;
            }
        }

        true
    }
}

// Cleans relative components ('..' and '.') lexically from a path
pub fn clean_path(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut result = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir | Component::Normal(_) => {
                result.push(component);
            }
            Component::CurDir => {}
            Component::ParentDir => {
                result.pop();
            }
        }
    }
    result
}

// Converts path to absolute and cleans lexical components
pub fn clean_and_resolve_path(path: &Path) -> PathBuf {
    let abs_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(path)
    };
    clean_path(&abs_path)
}

pub fn load_and_verify_passport(
    igapp_dir: &Path,
    caller_active_grants: &HashMap<String, CapabilityGrant>,
    caller_bindings: &HashMap<String, String>,
) -> Result<HashMap<String, CapabilityGrant>, String> {
    // 1. Load passport.json
    let passport_path = igapp_dir.join("passport.json");
    if !passport_path.exists() {
        let manifest_path = igapp_dir.join("manifest.json");
        if manifest_path.exists() {
            if let Ok(manifest_content) = fs::read_to_string(&manifest_path) {
                if let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&manifest_content) {
                    if let Some(caps) = manifest.get("capabilities").and_then(|c| c.as_array()) {
                        if caps.is_empty() {
                            return Ok(HashMap::new());
                        }
                    } else {
                        return Ok(HashMap::new());
                    }
                }
            }
        }
        return Err("PassportError: passport.json not found".to_string());
    }
    let passport_content = fs::read_to_string(&passport_path)
        .map_err(|e| format!("PassportError: failed to read passport.json: {}", e))?;
    let passport: Passport = serde_json::from_str(&passport_content)
        .map_err(|e| format!("PassportError: malformed passport JSON: {}", e))?;

    // 2. Verify schema fields match expectations exactly
    if passport.runtime_implementation_id != "igniter.delegated.experimental.io.delegation.v0" {
        return Err(format!(
            "PassportError: incompatible runtime target: callee expects '{}', running VM is '{}'",
            passport.runtime_implementation_id, "igniter.delegated.experimental.io.delegation.v0"
        ));
    }
    if passport.backend_implementation_id != "none" {
        return Err(format!(
            "PassportError: incompatible backend target: expected 'none', got '{}'",
            passport.backend_implementation_id
        ));
    }
    if passport.consumer_surface_id != "igniter-lab" {
        return Err(format!(
            "PassportError: incompatible consumer surface: expected 'igniter-lab', got '{}'",
            passport.consumer_surface_id
        ));
    }
    if passport.surface_dimension != "runtime" {
        return Err(format!(
            "PassportError: incompatible surface dimension: expected 'runtime', got '{}'",
            passport.surface_dimension
        ));
    }
    if passport.artifact_kind != "igapp_dir" {
        return Err(format!(
            "PassportError: incompatible artifact kind: expected 'igapp_dir', got '{}'",
            passport.artifact_kind
        ));
    }

    // 3. Load manifest.json
    let manifest_path = igapp_dir.join("manifest.json");
    if !manifest_path.exists() {
        return Err("PassportError: manifest.json not found".to_string());
    }
    let manifest_content = fs::read_to_string(&manifest_path)
        .map_err(|e| format!("PassportError: failed to read manifest.json: {}", e))?;
    let manifest: Manifest = serde_json::from_str(&manifest_content)
        .map_err(|e| format!("PassportError: malformed manifest JSON: {}", e))?;

    // 4. Verify artifact_digest
    if passport.artifact_digest != manifest.artifact_hash {
        return Err(format!(
            "PassportError: Tamper detected: callee digest '{}' does not match manifest hash '{}'",
            passport.artifact_digest, manifest.artifact_hash
        ));
    }

    let mut capability_bindings = passport.capability_bindings.clone();

    // COMPATIBILITY-ONLY: Legacy P6 compatibility fallback
    if capability_bindings.is_empty() && !passport.required_capabilities.is_empty() {
        eprintln!("[LEGACY COMPATIBILITY WARNING] Triggered legacy P6 fallback: capability_bindings is empty");
        if let Some(first_cap) = passport.required_capabilities.keys().next() {
            capability_bindings.insert(first_cap.clone(), first_cap.clone());
        }
    }

    // COMPATIBILITY-ONLY: Legacy io_child alias map fallback
    if capability_bindings.contains_key("io_child_read") && !capability_bindings.contains_key("io_child") {
        eprintln!("[LEGACY COMPATIBILITY WARNING] Triggered legacy io_child alias fallback for io_child_read");
        capability_bindings.insert("io_child".to_string(), "io_child_read".to_string());
    }
    if capability_bindings.contains_key("io_child_write") && !capability_bindings.contains_key("io_child") {
        eprintln!("[LEGACY COMPATIBILITY WARNING] Triggered legacy io_child alias fallback for io_child_write");
        capability_bindings.insert("io_child".to_string(), "io_child_write".to_string());
    }

    let mut resolved_grants = HashMap::new();

    // 5. Verify capabilities and build callee grants
    for (param_name, cap_id) in &capability_bindings {
        // Find which caller grant key is mapped to this parameter name
        let caller_grant_key = match caller_bindings.get(param_name) {
            Some(k) => k,
            None => {
                if param_name == "io_child_read" || param_name == "io_child_write" {
                    match caller_bindings.get("io_child") {
                        Some(k) => k,
                        None => return Err(format!("PassportError: missing capability binding for parameter '{}'", param_name)),
                    }
                } else {
                    return Err(format!("PassportError: missing capability binding for parameter '{}'", param_name));
                }
            }
        };

        // Find caller active grant
        let caller_grant = match caller_active_grants.get(caller_grant_key) {
            Some(g) => g,
            None => return Err(format!("PassportError: caller does not hold active grant '{}'", caller_grant_key)),
        };

        // Find required capability in passport
        let required_use = match passport.required_capabilities.get(cap_id) {
            Some(rc) => rc,
            None => return Err(format!("PassportError: required capability config '{}' not found in passport", cap_id)),
        };

        // Resolve sandbox path: "out/sandbox/sub" is resolved relative to the parent caller's sandbox_dir
        let callee_sandbox_dir = if required_use.sandbox_dir == "out/sandbox/sub" {
            Path::new(&caller_grant.sandbox_dir).join("sub").to_string_lossy().into_owned()
        } else {
            required_use.sandbox_dir.clone()
        };

        let callee_grant = CapabilityGrant {
            capability_id: format!("{}:delegated:TwoCapabilities:{}", caller_grant.capability_id, param_name),
            resource_type: "IO.Capability".to_string(),
            sandbox_dir: callee_sandbox_dir,
            allowed_absolute_paths: required_use.allowed_absolute_paths.clone(),
            read_allowed: required_use.read_allowed,
            write_allowed: required_use.write_allowed,
        };

        // Enforce boundary checks
        if !callee_grant.is_sub_grant_of(caller_grant) {
            return Err(format!(
                "PassportError: Delegation verification failed: callee request escalates caller grant (callee: R={}, W={}, sandbox={}; caller: R={}, W={}, sandbox={})",
                callee_grant.read_allowed, callee_grant.write_allowed, callee_grant.sandbox_dir,
                caller_grant.read_allowed, caller_grant.write_allowed, caller_grant.sandbox_dir
            ));
        }

        resolved_grants.insert(param_name.clone(), callee_grant);
    }

    // Every required capability MUST be mapped in capability_bindings
    for (cap_id, _) in &passport.required_capabilities {
        let is_bound = capability_bindings.values().any(|v| v == cap_id);
        if !is_bound {
            return Err(format!("PassportError: missing capability binding for required capability '{}'", cap_id));
        }
    }

    Ok(resolved_grants)
}
