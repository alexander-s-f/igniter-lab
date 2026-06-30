// src/packs/snapshot.rs
// Bitemporal Rollups, Memory Index Pruning & Atomic WAL Compaction Pack for TBackend

use crate::kernel::{BackgroundService, PackManifest, ServerKernel, ServerPack, StoreEngine};
use crate::pure_core::FactData;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

// ── Rollup Domain Model ──────────────────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct AggDef {
    pub field: String,
    pub op: String, // sum, avg, count, min, max
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct RollupPolicy {
    pub id: String,
    pub source_store: String,
    pub target_store: String,
    pub retention_period: f64, // seconds
    pub group_by: Vec<String>, // e.g. ["value.vendor_name", "value.zip_code", "value.accepted"]
    pub aggregates: Vec<AggDef>,
    pub interval: String, // hourly, daily
}

pub struct RollupRegistry {
    pub policies: HashMap<String, RollupPolicy>,
}

impl RollupRegistry {
    pub fn new() -> Self {
        Self {
            policies: HashMap::new(),
        }
    }
}

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

fn resolve_field_as_f64(fact: &FactData, path: &str) -> Option<f64> {
    let val = resolve_field_as_value(fact, path)?;
    match val {
        serde_json::Value::Number(n) => n.as_f64(),
        serde_json::Value::String(s) => s.parse::<f64>().ok(),
        _ => None,
    }
}

// ── Rollup & Compaction Sweep Orchestration ─────────────────────────────────

fn run_rollup_and_compaction(
    policy: &RollupPolicy,
    kernel: &ServerKernel,
) -> Result<(usize, usize), String> {
    // LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12.
    // Backstop: never compact unless explicitly enabled (the caller also checks).
    if !kernel.compaction_enabled {
        return Err(
            "compaction disabled; start daemon with --enable-compaction true for safe manual compaction"
                .to_string(),
        );
    }

    // Stop-the-world for THIS store: take the per-store gate exclusively so no
    // write can land on the engine we are about to read→build→swap. Held for the
    // whole operation. Writers hold `gate.read()` (main.rs write paths); this
    // blocks new ones and waits for in-flight ones to drain → B3 eliminated by
    // construction. The guard lives in the kernel (stable across the engine swap).
    let stw_guard = kernel.store_guard(&policy.source_store);
    let _stw = stw_guard.gate.write();

    let source_engine = match kernel.get_or_create_engine(&policy.source_store) {
        Some(e) => e,
        None => return Err(format!("Source store '{}' not found", policy.source_store)),
    };

    let target_engine = match kernel.get_or_create_engine(&policy.target_store) {
        Some(e) => e,
        None => return Err(format!("Target store '{}' not found", policy.target_store)),
    };

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);

    let cut_off = now - policy.retention_period;

    // 1. Gather all historical facts for the source store
    let all_facts = source_engine
        .log
        .facts_for_store(&policy.source_store, None, None);

    let mut cold_facts = Vec::new();
    let mut warm_facts = Vec::new();

    for fact in all_facts {
        if fact.transaction_time < cut_off {
            cold_facts.push(fact);
        } else {
            warm_facts.push(fact);
        }
    }

    if cold_facts.is_empty() {
        return Ok((0, 0));
    }

    // 2. Group the cold facts by the configured criteria
    let mut groups: HashMap<serde_json::Value, Vec<FactData>> = HashMap::new();
    for fact in cold_facts {
        let mut group_key_obj = serde_json::Map::new();
        for path in &policy.group_by {
            let val = resolve_field_as_value(&fact, path).unwrap_or(serde_json::Value::Null);
            let key_name = path.replace(".", "_");
            group_key_obj.insert(key_name, val);
        }
        let group_key = serde_json::Value::Object(group_key_obj);
        groups.entry(group_key).or_default().push(fact);
    }

    // 3. Create aggregated summary facts and write them to the target store
    let mut created_summaries = 0;
    for (group_val, group_facts) in &groups {
        let mut computed = serde_json::Map::new();
        if let serde_json::Value::Object(obj) = group_val {
            for (k, v) in obj {
                computed.insert(k.clone(), v.clone());
            }
        }

        for agg in &policy.aggregates {
            let key_name = format!(
                "{}_{}",
                agg.op,
                if agg.field.is_empty() {
                    "fact"
                } else {
                    &agg.field
                }
            )
            .replace(".", "_");

            match agg.op.as_str() {
                "count" => {
                    computed.insert(key_name, serde_json::json!(group_facts.len()));
                }
                "sum" => {
                    let mut sum_val = 0.0;
                    for f in group_facts {
                        sum_val += resolve_field_as_f64(f, &agg.field).unwrap_or(0.0);
                    }
                    computed.insert(key_name, serde_json::json!(sum_val));
                }
                "avg" => {
                    let mut sum_val = 0.0;
                    let mut count = 0;
                    for f in group_facts {
                        if let Some(v) = resolve_field_as_f64(f, &agg.field) {
                            sum_val += v;
                            count += 1;
                        }
                    }
                    let avg_val = if count > 0 {
                        sum_val / count as f64
                    } else {
                        0.0
                    };
                    computed.insert(key_name, serde_json::json!(avg_val));
                }
                "min" => {
                    let mut min_val = f64::INFINITY;
                    let mut found = false;
                    for f in group_facts {
                        if let Some(v) = resolve_field_as_f64(f, &agg.field) {
                            if v < min_val {
                                min_val = v;
                                found = true;
                            }
                        }
                    }
                    computed.insert(
                        key_name,
                        serde_json::json!(if found { min_val } else { 0.0 }),
                    );
                }
                "max" => {
                    let mut max_val = f64::NEG_INFINITY;
                    let mut found = false;
                    for f in group_facts {
                        if let Some(v) = resolve_field_as_f64(f, &agg.field) {
                            if v > max_val {
                                max_val = v;
                                found = true;
                            }
                        }
                    }
                    computed.insert(
                        key_name,
                        serde_json::json!(if found { max_val } else { 0.0 }),
                    );
                }
                _ => {}
            }
        }

        let summary_key = format!(
            "rollup-{}-{}",
            policy.id,
            uuid::Uuid::new_v4().to_string()[0..8].to_string()
        );
        let mut summary_fact = FactData {
            id: uuid::Uuid::new_v4().to_string(),
            store: policy.target_store.clone(),
            key: summary_key,
            value: serde_json::Value::Object(computed),
            value_hash: "rollup-hash-placeholder".to_string(),
            causation: None,
            transaction_time: now,
            valid_time: Some(now),
            schema_version: 1,
            producer: Some("SnapshotPack".to_string()),
            // P9/P12: a rollup summary is a real fact in the target store — give it
            // a server seq from the target's counter (assigned before the append).
            seq_id: 0,
            origin_node: None,
            derivation: Some(format!(
                "Rollup from {} (Pruned {} raw facts)",
                policy.source_store,
                group_facts.len()
            )),
        };
        summary_fact.seq_id = target_engine.log.assign_seq();

        if let Some(ref fb) = target_engine.wal {
            fb.write_fact_data(&summary_fact)
                .map_err(|e| e.to_string())?;
        }
        target_engine.log.push(summary_fact);
        created_summaries += 1;
    }

    // 4. Build the replacement engine and publish it. We hold the stop-the-world
    //    gate, so `warm_facts` is a complete, stable snapshot — no concurrent
    //    write exists to be lost (B3). The seq high-water mark is carried across
    //    so new inserts never reuse a pruned fact's seq (B5).
    let total_pruned = source_engine.log.size() - warm_facts.len();
    let preserved_next_seq = source_engine.log.peek_next_seq();

    // Seq-preserving rebuild: retained facts keep their seq_id; the counter is
    // restored to the old high-water mark (>= max retained + 1).
    let rebuild_log = || {
        let new_log = Arc::new(crate::pure_core::ShardedFactLog::new());
        new_log.load_replayed(warm_facts.clone());
        new_log.advance_next_seq_to(preserved_next_seq);
        new_log
    };

    if let Some(ref dir) = kernel.data_dir {
        let temp_path = format!("{}/{}.wal.tmp", dir, policy.source_store);
        let real_path = format!("{}/{}.wal", dir, policy.source_store);

        // Write warm facts to a temp WAL, then make it durable BEFORE the rename
        // (B4 fix part 1): fsync the temp file's data+size to the device.
        let temp_wal =
            crate::pure_core::FileBackend::new_pure(&temp_path).map_err(|e| e.to_string())?;
        for fact in &warm_facts {
            temp_wal.write_fact_data(fact).map_err(|e| e.to_string())?;
        }
        temp_wal.sync_all_pure().map_err(|e| e.to_string())?;
        kernel
            .compaction_file_fsyncs
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
        drop(temp_wal); // close the temp file

        // Atomic replace, then fsync the directory so the rename itself is durable
        // (B4 fix part 2). Order: fsync(tmp) -> rename -> fsync(dir) -> swap.
        std::fs::rename(&temp_path, &real_path).map_err(|e| e.to_string())?;
        crate::pure_core::fsync_dir(dir).map_err(|e| e.to_string())?;
        kernel
            .compaction_dir_fsyncs
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel);

        let new_wal =
            crate::pure_core::FileBackend::new_pure(&real_path).map_err(|e| e.to_string())?;

        // Only now (durable on disk) publish the new in-memory engine.
        let mut engines = kernel.engines.write();
        let new_engine = Arc::new(StoreEngine {
            log: rebuild_log(),
            wal: Some(Arc::new(new_wal)),
        });
        engines.insert(policy.source_store.clone(), new_engine);
    } else {
        // Ephemeral in-memory mode: just swap the (seq-preserving) memory index.
        let mut engines = kernel.engines.write();
        let new_engine = Arc::new(StoreEngine {
            log: rebuild_log(),
            wal: None,
        });
        engines.insert(policy.source_store.clone(), new_engine);
    }

    Ok((total_pruned, created_summaries))
}

// ── Background Compaction Service ───────────────────────────────────────────

pub struct CompactorService {
    registry: Arc<RwLock<RollupRegistry>>,
}

impl CompactorService {
    pub fn new(registry: Arc<RwLock<RollupRegistry>>) -> Self {
        Self { registry }
    }
}

impl BackgroundService for CompactorService {
    fn start(&self, _kernel: Arc<ServerKernel>) -> Result<(), String> {
        // LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12: v0 safe compaction is
        // MANUAL-only. The background 5s sweep is NOT spawned in any mode — a
        // stop-the-world pause should be operator-chosen via `snapshot_trigger`,
        // not fired automatically. (Auto-sweep can return as an opt-in once the
        // v1 short-pause delta model lands and soaks.)
        println!(
            "[Compactor Service] Background auto-compaction is DISABLED (manual `snapshot_trigger` \
             only). Enable safe manual compaction with --enable-compaction true."
        );
        Ok(())
    }

    fn stop(&self) {}
}

// ── Snapshot Pack ────────────────────────────────────────────────────────────

pub struct SnapshotPack {
    registry: Arc<RwLock<RollupRegistry>>,
}

impl SnapshotPack {
    pub fn new() -> Self {
        Self {
            registry: Arc::new(RwLock::new(RollupRegistry::new())),
        }
    }
}

impl ServerPack for SnapshotPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "snapshot",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["log_compaction", "declarative_rollups"],
            requires_capabilities: vec!["bitemporal_ledger"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let command_reg = &mut *kernel.command_registry.write();

        // 1. Register "snapshot_policy_create" Command Route
        let registry_c = self.registry.clone();
        command_reg.register("snapshot_policy_create", Arc::new(move |req, _kernel| {
            let source_store = match req.get("source_store").and_then(|v| v.as_str()) {
                Some(s) => s.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'source_store' parameter" }),
            };
            let target_store = match req.get("target_store").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'target_store' parameter" }),
            };
            let retention_period = match req.get("retention_period").and_then(|v| v.as_f64()) {
                Some(r) => r,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'retention_period' parameter" }),
            };
            let interval = req.get("interval").and_then(|v| v.as_str()).unwrap_or("daily").to_string();

            let group_by_arr = match req.get("group_by").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect(),
                None => Vec::new(),
            };

            let aggregates_arr = match req.get("aggregates").and_then(|v| v.as_array()) {
                Some(arr) => arr,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'aggregates' array" }),
            };

            let mut aggregates = Vec::new();
            for item in aggregates_arr {
                let field = item.get("field").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let op = match item.get("op").and_then(|v| v.as_str()) {
                    Some(o) => o.to_string(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'op' field in aggregates item" }),
                };
                aggregates.push(AggDef { field, op });
            }

            let policy_id = format!("pol_{}", uuid::Uuid::new_v4().to_string()[0..8].to_string());
            let policy = RollupPolicy {
                id: policy_id.clone(),
                source_store,
                target_store,
                retention_period,
                group_by: group_by_arr,
                aggregates,
                interval,
            };

            registry_c.write().policies.insert(policy_id.clone(), policy);
            serde_json::json!({ "ok": true, "policy_id": policy_id })
        }));

        // 2. Register "snapshot_policy_list" Command Route
        let registry_c = self.registry.clone();
        command_reg.register(
            "snapshot_policy_list",
            Arc::new(move |_req, _kernel| {
                let map = registry_c.read();
                let list: Vec<RollupPolicy> = map.policies.values().cloned().collect();
                serde_json::json!({ "ok": true, "policies": list })
            }),
        );

        // 3. Register "snapshot_trigger" Command Route
        let registry_c = self.registry.clone();
        command_reg.register("snapshot_trigger", Arc::new(move |req, kernel| {
            // LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12: manual safe path.
            // Gate: compaction must be explicitly enabled.
            if !kernel.compaction_enabled {
                return serde_json::json!({
                    "ok": false,
                    "error": "compaction disabled; start daemon with --enable-compaction true for safe manual compaction",
                    "error_code": "compaction_disabled",
                    "compaction_enabled": false
                });
            }

            let policy_id = match req.get("policy_id").and_then(|v| v.as_str()) {
                Some(id) => id,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'policy_id' parameter" }),
            };

            let policy = {
                let r = registry_c.read();
                match r.policies.get(policy_id) {
                    Some(p) => p.clone(),
                    None => return serde_json::json!({ "ok": false, "error": format!("Policy '{}' not found", policy_id) }),
                }
            };

            // Busy refusal: only one compaction per source store at a time. CAS the
            // per-store flag; if already compacting, refuse rather than double-work.
            let guard = kernel.store_guard(&policy.source_store);
            if guard
                .compacting
                .compare_exchange(
                    false,
                    true,
                    std::sync::atomic::Ordering::AcqRel,
                    std::sync::atomic::Ordering::Acquire,
                )
                .is_err()
            {
                return serde_json::json!({
                    "ok": false,
                    "error": format!("compaction already in progress for store '{}'", policy.source_store),
                    "error_code": "compaction_in_progress",
                    "retryable": true
                });
            }

            // run_rollup_and_compaction takes the per-store stop-the-world gate.
            let result = run_rollup_and_compaction(&policy, kernel);
            guard
                .compacting
                .store(false, std::sync::atomic::Ordering::Release);

            match result {
                Ok((pruned, summaries)) => {
                    serde_json::json!({ "ok": true, "pruned_facts": pruned, "created_summaries": summaries, "durable_rename": kernel.data_dir.is_some() })
                }
                Err(e) => {
                    serde_json::json!({ "ok": false, "error": e })
                }
            }
        }));

        // 4. Register Compactor Service
        let service = CompactorService::new(self.registry.clone());
        kernel.background_services.write().push(Box::new(service));

        Ok(())
    }
}
