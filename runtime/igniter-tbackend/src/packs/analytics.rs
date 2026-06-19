// src/packs/analytics.rs
// Bitemporal Analytics, Grouped Aggregations, Time-Series Calculations & Ledger Metrics Pack for TBackend

use super::query::{evaluate_slice_rule, SliceRule};
use crate::kernel::{PackManifest, ServerKernel, ServerPack};
use crate::pure_core::FactData;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

// ── JSON Filter Helpers ──────────────────────────────────────────────────────

fn matches_filters(value: &serde_json::Value, filters: &serde_json::Value) -> bool {
    match (value, filters) {
        (serde_json::Value::Object(v), serde_json::Value::Object(f)) => f
            .iter()
            .all(|(k, fv)| v.get(k).map_or(false, |vv| vv == fv)),
        _ => false,
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

// ── Analytics Pack ───────────────────────────────────────────────────────────

pub struct AnalyticsPack;

impl AnalyticsPack {
    pub fn new() -> Self {
        AnalyticsPack
    }
}

impl ServerPack for AnalyticsPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "analytics",
            requires_packs: vec!["base_audit", "query"],
            provides_capabilities: vec!["aggregations", "time_series_calculations"],
            requires_capabilities: vec!["bitemporal_ledger", "temporal_query"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let registry = &mut *kernel.command_registry.write();

        // 1. Register "analytics_aggregate" Command Route
        registry.register("analytics_aggregate", Arc::new(|req, kernel| {
            let store = match req.get("store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'store' parameter" }),
            };

            let key_prefix = req.get("key_prefix").and_then(|v| v.as_str());
            let since_tx = req.get("since_tx").and_then(|v| v.as_f64());
            let as_of_tx = req.get("as_of_tx").and_then(|v| v.as_f64());
            let since_val = req.get("since_val").and_then(|v| v.as_f64());
            let as_of_val = req.get("as_of_val").and_then(|v| v.as_f64());
            let filters = req.get("filters");
            let group_by_path = req.get("group_by").and_then(|v| v.as_str());
            let rules_val = req.get("rules");
            let parsed_rules: Option<Vec<SliceRule>> = if let Some(rv) = rules_val {
                serde_json::from_value(rv.clone()).ok()
            } else {
                None
            };

            let aggregates_arr = match req.get("aggregates").and_then(|v| v.as_array()) {
                Some(arr) => arr,
                None => return serde_json::json!({ "ok": false, "error": "Missing or invalid 'aggregates' array" }),
            };

            struct AggRequest {
                field: String,
                op: String,
            }
            let mut aggs = Vec::new();
            for item in aggregates_arr {
                let field = item.get("field").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let op = match item.get("op").and_then(|v| v.as_str()) {
                    Some(o) => o.to_string(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'op' field in aggregates item" }),
                };
                aggs.push(AggRequest { field, op });
            }

            let engine = match kernel.get_or_create_engine(store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };

            let raw_facts = engine.log.facts_for_store(store, since_tx, as_of_tx);
            let filtered: Vec<FactData> = raw_facts.into_iter()
                .filter(|fact| {
                    if let Some(prefix) = key_prefix {
                        if !fact.key.starts_with(prefix) {
                            return false;
                        }
                    }
                    if let Some(since_v) = since_val {
                        let vt = fact.valid_time.unwrap_or(fact.transaction_time);
                        if vt < since_v {
                            return false;
                        }
                    }
                    if let Some(as_of_v) = as_of_val {
                        let vt = fact.valid_time.unwrap_or(fact.transaction_time);
                        if vt > as_of_v {
                            return false;
                        }
                    }
                    if let Some(f) = filters {
                        if !matches_filters(&fact.value, f) {
                            return false;
                        }
                    }
                    if let Some(ref r_list) = parsed_rules {
                        for rule in r_list {
                            if !evaluate_slice_rule(rule, fact) {
                                return false;
                            }
                        }
                    }
                    true
                })
                .collect();

            // Grouping
            let mut groups: HashMap<serde_json::Value, Vec<&FactData>> = HashMap::new();
            for fact in &filtered {
                let group_key = match group_by_path {
                    Some(path) => resolve_field_as_value(fact, path).unwrap_or(serde_json::Value::Null),
                    None => serde_json::Value::Null,
                };
                groups.entry(group_key).or_default().push(fact);
            }

            // Execute aggregations per group
            let mut results = Vec::new();
            for (group_val, group_facts) in groups {
                let mut computed = HashMap::new();

                for agg in &aggs {
                    let key_name = format!("{}_{}", agg.op, if agg.field.is_empty() { "fact" } else { &agg.field });

                    match agg.op.as_str() {
                        "count" => {
                            computed.insert(key_name, group_facts.len() as f64);
                        }
                        "sum" => {
                            let mut sum_val = 0.0;
                            for f in &group_facts {
                                sum_val += resolve_field_as_f64(f, &agg.field).unwrap_or(0.0);
                            }
                            computed.insert(key_name, sum_val);
                        }
                        "avg" => {
                            let mut sum_val = 0.0;
                            let mut count = 0;
                            for f in &group_facts {
                                if let Some(v) = resolve_field_as_f64(f, &agg.field) {
                                    sum_val += v;
                                    count += 1;
                                }
                            }
                            let avg_val = if count > 0 { sum_val / count as f64 } else { 0.0 };
                            computed.insert(key_name, avg_val);
                        }
                        "min" => {
                            let mut min_val = f64::INFINITY;
                            let mut found = false;
                            for f in &group_facts {
                                if let Some(v) = resolve_field_as_f64(f, &agg.field) {
                                    if v < min_val {
                                        min_val = v;
                                        found = true;
                                    }
                                }
                            }
                            computed.insert(key_name, if found { min_val } else { 0.0 });
                        }
                        "max" => {
                            let mut max_val = f64::NEG_INFINITY;
                            let mut found = false;
                            for f in &group_facts {
                                if let Some(v) = resolve_field_as_f64(f, &agg.field) {
                                    if v > max_val {
                                        max_val = v;
                                        found = true;
                                    }
                                }
                            }
                            computed.insert(key_name, if found { max_val } else { 0.0 });
                        }
                        "cardinality" => {
                            let mut unique_vals = HashSet::new();
                            for f in &group_facts {
                                if let Some(v) = resolve_field_as_value(f, &agg.field) {
                                    unique_vals.insert(serde_json::to_string(&v).unwrap_or_default());
                                }
                            }
                            computed.insert(key_name, unique_vals.len() as f64);
                        }
                        _ => {}
                    }
                }

                results.push(serde_json::json!({
                    "group_value": group_val,
                    "aggregates": computed
                }));
            }

            serde_json::json!({ "ok": true, "results": results })
        }));

        // 3. Register "analytics_calculate" Command Route
        registry.register("analytics_calculate", Arc::new(|req, kernel| {
            let store = match req.get("store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'store' parameter" }),
            };

            let key = match req.get("key").and_then(|v| v.as_str()) {
                Some(k) => k,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'key' parameter" }),
            };

            let field = match req.get("field").and_then(|v| v.as_str()) {
                Some(f) => f,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'field' parameter" }),
            };

            let calculation = match req.get("calculation").and_then(|v| v.as_str()) {
                Some(c) => c,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'calculation' parameter" }),
            };

            let window_size = req.get("window_size").and_then(|v| v.as_u64()).unwrap_or(5) as usize;
            let since_tx = req.get("since_tx").and_then(|v| v.as_f64());
            let as_of_tx = req.get("as_of_tx").and_then(|v| v.as_f64());

            let engine = match kernel.get_or_create_engine(store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };

            let raw_facts = engine.log.facts_for_key(store, key, since_tx, as_of_tx);
            if raw_facts.is_empty() {
                return serde_json::json!({ "ok": true, "series": [] });
            }

            let mut points = Vec::new();
            let mut values_history = Vec::new();

            for fact in &raw_facts {
                let current_val = resolve_field_as_f64(fact, field);
                if let Some(val) = current_val {
                    values_history.push(val);
                }

                let calculated_val = match calculation {
                    "sma" => {
                        if values_history.is_empty() {
                            0.0
                        } else {
                            let start = if values_history.len() > window_size { values_history.len() - window_size } else { 0 };
                            let slice = &values_history[start..];
                            let sum: f64 = slice.iter().sum();
                            sum / slice.len() as f64
                        }
                    }
                    "variance" => {
                        if values_history.len() < 2 {
                            0.0
                        } else {
                            let mean = values_history.iter().sum::<f64>() / values_history.len() as f64;
                            let variance = values_history.iter().map(|&x| (x - mean).powi(2)).sum::<f64>() / (values_history.len() - 1) as f64;
                            variance
                        }
                    }
                    "stddev" => {
                        if values_history.len() < 2 {
                            0.0
                        } else {
                            let mean = values_history.iter().sum::<f64>() / values_history.len() as f64;
                            let variance = values_history.iter().map(|&x| (x - mean).powi(2)).sum::<f64>() / (values_history.len() - 1) as f64;
                            variance.sqrt()
                        }
                    }
                    "delta" => {
                        if values_history.len() < 2 {
                            current_val.unwrap_or(0.0)
                        } else {
                            let prev = values_history[values_history.len() - 2];
                            let curr = values_history[values_history.len() - 1];
                            curr - prev
                        }
                    }
                    _ => 0.0,
                };

                points.push(serde_json::json!({
                    "transaction_time": fact.transaction_time,
                    "valid_time": fact.valid_time,
                    "raw_value": current_val,
                    "calculated_value": calculated_val
                }));
            }

            serde_json::json!({ "ok": true, "series": points })
        }));

        // 4. Register "analytics_metrics" Command Route
        registry.register(
            "analytics_metrics",
            Arc::new(|req, kernel| {
                let filter_store = req.get("store").and_then(|v| v.as_str());

                let mut stores_stats = HashMap::new();
                let map = kernel.engines.read();

                for (name, engine) in map.iter() {
                    if let Some(filter) = filter_store {
                        if filter != name {
                            continue;
                        }
                    }

                    let facts = engine.log.facts_for_store(name, None, None);
                    let total_facts = facts.len();

                    let mut key_versions: HashMap<String, usize> = HashMap::new();
                    let mut min_tx = f64::INFINITY;
                    let mut max_tx = f64::NEG_INFINITY;

                    for f in &facts {
                        *key_versions.entry(f.key.clone()).or_default() += 1;
                        if f.transaction_time < min_tx {
                            min_tx = f.transaction_time;
                        }
                        if f.transaction_time > max_tx {
                            max_tx = f.transaction_time;
                        }
                    }

                    let unique_keys = key_versions.len();
                    let avg_versions = if unique_keys > 0 {
                        total_facts as f64 / unique_keys as f64
                    } else {
                        0.0
                    };
                    let max_versions = key_versions.values().cloned().max().unwrap_or(0);
                    let time_span = if total_facts > 0 && max_tx >= min_tx {
                        Some(max_tx - min_tx)
                    } else {
                        None
                    };

                    let mut estimated_size = 0;
                    for f in &facts {
                        estimated_size += f.id.len() + f.store.len() + f.key.len();
                        estimated_size += serde_json::to_string(&f.value).unwrap_or_default().len();
                        if let Some(ref c) = f.causation {
                            estimated_size += c.len();
                        }
                        if let Some(ref p) = f.producer {
                            estimated_size += p.len();
                        }
                        if let Some(ref d) = f.derivation {
                            estimated_size += d.len();
                        }
                        estimated_size += 24;
                    }

                    stores_stats.insert(
                        name.clone(),
                        serde_json::json!({
                            "total_facts": total_facts,
                            "unique_keys": unique_keys,
                            "avg_versions_per_key": avg_versions,
                            "max_versions_per_key": max_versions,
                            "transaction_time_span": time_span,
                            "size_bytes": estimated_size
                        }),
                    );
                }

                serde_json::json!({ "ok": true, "stores": stores_stats })
            }),
        );

        Ok(())
    }
}
