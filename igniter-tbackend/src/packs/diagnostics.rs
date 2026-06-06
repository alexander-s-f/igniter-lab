// src/packs/diagnostics.rs
// Diagnostics, System Observability & Statistics Pack for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack};
use crate::pure_core::FactData;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::Instant;

static BOOT_TIME: OnceLock<Instant> = OnceLock::new();

// ── In-Memory Footprint Calculators ──────────────────────────────────────────

fn estimate_json_bytes(val: &serde_json::Value) -> usize {
    match val {
        serde_json::Value::Null => 1,
        serde_json::Value::Bool(_) => 1,
        serde_json::Value::Number(_) => 8,
        serde_json::Value::String(s) => 24 + s.len(),
        serde_json::Value::Array(arr) => {
            let mut total = 24; // Vec struct allocator overhead
            for v in arr {
                total += estimate_json_bytes(v);
            }
            total
        }
        serde_json::Value::Object(obj) => {
            let mut total = 48; // Map allocator overhead approximation
            for (k, v) in obj {
                total += 24 + k.len(); // key String bytes
                total += estimate_json_bytes(v); // value bytes
            }
            total
        }
    }
}

fn estimate_fact_bytes(fact: &FactData) -> usize {
    let mut total = 0;
    total += 24 + fact.id.len();
    total += 24 + fact.store.len();
    total += 24 + fact.key.len();
    total += estimate_json_bytes(&fact.value);
    total += 24 + fact.value_hash.len();
    total += fact.causation.as_ref().map(|c| 24 + c.len()).unwrap_or(0);
    total += 8; // transaction_time f64
    total += fact.valid_time.map(|_| 8).unwrap_or(0); // valid_time f64
    total += 8; // schema_version u32
    total += fact.producer.as_ref().map(|p| 24 + p.len()).unwrap_or(0);
    total += fact.derivation.as_ref().map(|d| 24 + d.len()).unwrap_or(0);
    total
}

// ── Diagnostics Pack Implementation ──────────────────────────────────────────

pub struct DiagnosticsPack;

impl DiagnosticsPack {
    pub fn new() -> Self {
        BOOT_TIME.get_or_init(Instant::now);
        Self
    }
}

impl ServerPack for DiagnosticsPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "diagnostics",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["diagnostics_monitoring"],
            requires_capabilities: vec!["audit"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let command_reg = &mut *kernel.command_registry.write();

        // 1. Register "diagnostics_summary" Route
        command_reg.register("diagnostics_summary", Arc::new(move |_req, kernel| {
            let elapsed = BOOT_TIME.get().map(|t| t.elapsed().as_secs_f64()).unwrap_or(0.0);
            let engines_map = kernel.engines.read();
            let stores_list: Vec<String> = engines_map.keys().cloned().collect();
            let total_facts: usize = engines_map.values().map(|e| e.log.size()).sum();

            let base_telemetry = crate::packs::base_audit::AUDIT_METRICS
                .get()
                .map(|m| m.to_json())
                .unwrap_or(serde_json::json!({}));

            let registered_routes: Vec<String> = kernel.command_registry.read().routes.keys().cloned().collect();
            let background_count = kernel.background_services.read().len();
            let middlewares_count = kernel.middleware_chain.read().middlewares.len();

            serde_json::json!({
                "ok": true,
                "summary": {
                    "host": kernel.host,
                    "port": kernel.port,
                    "data_dir": kernel.data_dir.as_deref().unwrap_or("ephemeral"),
                    "pool_size": kernel.pool_size,
                    "uptime_seconds": elapsed,
                    "total_stores": stores_list.len(),
                    "registered_stores": stores_list,
                    "total_facts_across_stores": total_facts,
                    "registered_operations": registered_routes,
                    "background_services_count": background_count,
                    "middlewares_count": middlewares_count,
                },
                "telemetry": base_telemetry
            })
        }));

        // 2. Register "diagnostics_stores" Route
        command_reg.register("diagnostics_stores", Arc::new(move |req, kernel| {
            let target_store = req.get("store").and_then(|v| v.as_str());

            let get_store_metrics = |store_name: &str, kernel: &ServerKernel| -> Option<serde_json::Value> {
                let engine = kernel.get_or_create_engine(store_name)?;
                let facts = engine.log.facts_for_store(store_name, None, None);

                let in_memory_facts = facts.len();
                let mut unique_keys = HashSet::new();
                let mut key_counts = HashMap::new();
                let mut estimated_memory_bytes = 0;

                for fact in &facts {
                    unique_keys.insert(fact.key.clone());
                    *key_counts.entry(fact.key.clone()).or_insert(0) += 1;
                    estimated_memory_bytes += estimate_fact_bytes(fact);
                }

                let max_version_depth = key_counts.values().cloned().max().unwrap_or(0);
                
                let mut wal_disk_bytes = 0;
                let has_persistence = engine.wal.is_some();
                if let Some(ref dir) = kernel.data_dir {
                    let path = format!("{}/{}.wal", dir, store_name);
                    if let Ok(metadata) = std::fs::metadata(&path) {
                        wal_disk_bytes = metadata.len();
                    }
                }

                Some(serde_json::json!({
                    "store_name": store_name,
                    "in_memory_facts": in_memory_facts,
                    "key_cardinality": unique_keys.len(),
                    "max_version_depth": max_version_depth,
                    "estimated_memory_bytes": estimated_memory_bytes,
                    "wal_disk_bytes": wal_disk_bytes,
                    "has_persistence": has_persistence,
                }))
            };

            if let Some(store) = target_store {
                match get_store_metrics(store, kernel) {
                    Some(metrics) => serde_json::json!({ "ok": true, "store": metrics }),
                    None => serde_json::json!({ "ok": false, "error": format!("Store '{}' is invalid or could not be loaded", store) }),
                }
            } else {
                let engines_map = kernel.engines.read();
                let mut list = Vec::new();
                for store_name in engines_map.keys() {
                    if let Some(metrics) = get_store_metrics(store_name, kernel) {
                        list.push(metrics);
                    }
                }
                serde_json::json!({ "ok": true, "stores": list })
            }
        }));

        Ok(())
    }
}
