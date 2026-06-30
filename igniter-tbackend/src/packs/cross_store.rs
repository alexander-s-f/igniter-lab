// src/packs/cross_store.rs
// Bitemporally Synchronized Cross-Store Time Travel & Relational Joins Pack for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack};
use crate::pure_core::FactData;
use std::collections::HashMap;
use std::sync::Arc;

// ── Nested Payload Field Resolvers ───────────────────────────────────────────

fn resolve_field_as_value(fact: &FactData, path: &str) -> Option<serde_json::Value> {
    if path == "key" {
        return Some(serde_json::Value::String(fact.key.clone()));
    }
    if path == "id" {
        return Some(serde_json::Value::String(fact.id.clone()));
    }
    if path == "transaction_time" {
        return Some(serde_json::json!(fact.transaction_time));
    }
    if path == "valid_time" {
        return fact.valid_time.map(|vt| serde_json::json!(vt));
    }
    if path == "producer" {
        return fact
            .producer
            .as_ref()
            .map(|p| serde_json::Value::String(p.clone()));
    }
    if path == "causation" {
        return fact
            .causation
            .as_ref()
            .map(|c| serde_json::Value::String(c.clone()));
    }
    if path.starts_with("value.") {
        let sub_path = &path[6..];
        let mut current = &fact.value;
        for part in sub_path.split('.') {
            if part.is_empty() {
                continue;
            }
            current = current.get(part)?;
        }
        return Some(current.clone());
    }
    // Fallback: check if path directly matches a field under value
    if let Some(val) = fact.value.get(path) {
        return Some(val.clone());
    }
    None
}

// Reconstructs active store key snapshot state vectors as of a bitemporal transaction coordinate
fn get_store_snapshot(
    engine: &crate::kernel::StoreEngine,
    store: &str,
    as_of: Option<f64>,
) -> HashMap<String, FactData> {
    let facts = engine.log.facts_for_store(store, None, as_of);
    let mut snapshot = HashMap::new();
    for fact in facts {
        snapshot.insert(fact.key.clone(), fact);
    }
    snapshot
}

// ── CrossStore Pack ──────────────────────────────────────────────────────────

pub struct CrossStorePack;

impl CrossStorePack {
    pub fn new() -> Self {
        CrossStorePack
    }
}

impl ServerPack for CrossStorePack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "cross_store",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["cross_store_time_travel", "bitemporal_joins"],
            requires_capabilities: vec!["bitemporal_ledger"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let registry = &mut *kernel.command_registry.write();

        // 1. Register "cross_store_query" Command Route
        registry.register("cross_store_query", Arc::new(|req, kernel| {
            let as_of = req.get("as_of").and_then(|v| v.as_f64());

            let target_stores: Vec<String> = match req.get("stores").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect(),
                None => {
                    // Default to all active stores
                    kernel.engines.read().keys().cloned().collect()
                }
            };

            let target_keys: Vec<String> = match req.get("keys").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'keys' array parameter" }),
            };

            let mut results = HashMap::new();

            for store_name in &target_stores {
                let engine = match kernel.get_or_create_engine(store_name) {
                    Some(e) => e,
                    None => continue,
                };

                let mut store_keys = HashMap::new();
                for key in &target_keys {
                    let found = engine.log.latest_for(store_name, key, as_of);
                    store_keys.insert(key.clone(), found);
                }
                results.insert(store_name.clone(), store_keys);
            }

            serde_json::json!({ "ok": true, "results": results })
        }));

        // 2. Register "cross_store_join" Command Route
        registry.register("cross_store_join", Arc::new(|req, kernel| {
            let left_store = match req.get("left_store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'left_store' parameter" }),
            };

            let right_store = match req.get("right_store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'right_store' parameter" }),
            };

            let join_field = match req.get("join_field").and_then(|v| v.as_str()) {
                Some(jf) => jf,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'join_field' parameter" }),
            };

            let right_key = match req.get("right_key").and_then(|v| v.as_str()) {
                Some(rk) => rk,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'right_key' parameter" }),
            };

            let as_of = req.get("as_of").and_then(|v| v.as_f64());
            let join_type = req.get("join_type").and_then(|v| v.as_str()).unwrap_or("inner");

            // Fetch left & right engines
            let left_engine = match kernel.get_or_create_engine(left_store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": format!("Left store '{}' could not be initialized", left_store) }),
            };

            let right_engine = match kernel.get_or_create_engine(right_store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": format!("Right store '{}' could not be initialized", right_store) }),
            };

            // Reconstruct timeline snapshots as of coordinates
            let left_snapshot = get_store_snapshot(&left_engine, left_store, as_of);
            let right_snapshot = get_store_snapshot(&right_engine, right_store, as_of);

            let mut results = Vec::new();

            // Hash map optimized lookup (O(N) join complexity instead of O(N^2))
            let mut right_by_join_val: HashMap<String, Vec<&FactData>> = HashMap::new();
            for fact in right_snapshot.values() {
                if let Some(val) = resolve_field_as_value(fact, right_key) {
                    let key_str = match &val {
                        serde_json::Value::String(s) => s.clone(),
                        other => serde_json::to_string(other).unwrap_or_default(),
                    };
                    right_by_join_val.entry(key_str).or_default().push(fact);
                }
            }

            // Perform bitemporal dynamic join traversal
            for left_fact in left_snapshot.values() {
                let left_join_val = resolve_field_as_value(left_fact, join_field);
                let left_join_key = match left_join_val {
                    Some(serde_json::Value::String(s)) => s,
                    Some(other) => serde_json::to_string(&other).unwrap_or_default(),
                    None => "".to_string(),
                };

                let mut matched = false;
                if !left_join_key.is_empty() {
                    if let Some(right_facts) = right_by_join_val.get(&left_join_key) {
                        for right_fact in right_facts {
                            results.push(serde_json::json!({
                                "left": left_fact,
                                "right": right_fact
                            }));
                            matched = true;
                        }
                    }
                }

                if !matched && join_type == "left" {
                    results.push(serde_json::json!({
                        "left": left_fact,
                        "right": serde_json::Value::Null
                    }));
                }
            }

            serde_json::json!({ "ok": true, "results": results })
        }));

        Ok(())
    }
}
