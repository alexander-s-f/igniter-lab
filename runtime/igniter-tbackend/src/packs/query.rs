// src/packs/query.rs
// Bitemporal Temporal Query, Pushdown Rules Filtration, & Slicing Pack for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack};
use crate::pure_core::FactData;
use std::sync::Arc;

// ── Security & Ingestion Data Models ──────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct SliceRule {
    pub left_path: String,
    pub op: String,
    pub right_val: serde_json::Value,
}

// ── Nested Payload Field Resolvers ───────────────────────────────────────────

pub fn resolve_field_as_value(fact: &FactData, path: &str) -> Option<serde_json::Value> {
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

pub fn evaluate_slice_rule(rule: &SliceRule, fact: &FactData) -> bool {
    let val = match resolve_field_as_value(fact, &rule.left_path) {
        Some(v) => v,
        None => return false,
    };

    match rule.op.as_str() {
        "eq" => val == rule.right_val,
        "ne" => val != rule.right_val,
        "gt" => {
            if let (Some(lf), Some(rf)) = (val.as_f64(), rule.right_val.as_f64()) {
                lf > rf
            } else {
                false
            }
        }
        "lt" => {
            if let (Some(lf), Some(rf)) = (val.as_f64(), rule.right_val.as_f64()) {
                lf < rf
            } else {
                false
            }
        }
        "ge" => {
            if let (Some(lf), Some(rf)) = (val.as_f64(), rule.right_val.as_f64()) {
                lf >= rf
            } else {
                false
            }
        }
        "le" => {
            if let (Some(lf), Some(rf)) = (val.as_f64(), rule.right_val.as_f64()) {
                lf <= rf
            } else {
                false
            }
        }
        "contains" => {
            if let (Some(ls), Some(rs)) = (val.as_str(), rule.right_val.as_str()) {
                ls.contains(rs)
            } else {
                false
            }
        }
        _ => false,
    }
}

fn matches_filters(value: &serde_json::Value, filters: &serde_json::Value) -> bool {
    match (value, filters) {
        (serde_json::Value::Object(v), serde_json::Value::Object(f)) => f
            .iter()
            .all(|(k, fv)| v.get(k).map_or(false, |vv| vv == fv)),
        _ => false,
    }
}

// ── Query Pack Mount ──────────────────────────────────────────────────────────

pub struct QueryPack;

impl QueryPack {
    pub fn new() -> Self {
        QueryPack
    }
}

impl ServerPack for QueryPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "query",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["temporal_query", "pushdown_filtering"],
            requires_capabilities: vec!["bitemporal_ledger"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let registry = &mut *kernel.command_registry.write();

        // 1. Register "query_scope" Command Route (Moved from CorePack)
        registry.register("query_scope", Arc::new(|req, kernel| {
            let store = match req.get("store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'store' parameter" }),
            };
            let filters = match req.get("filters") {
                Some(f) => f,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'filters' parameter" }),
            };
            let as_of = req.get("as_of").and_then(|v| v.as_f64());

            let engine = match kernel.get_or_create_engine(store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };
            let facts = engine.log.query_scope(store, filters, as_of);
            serde_json::json!({ "ok": true, "facts": facts })
        }));

        // 2. Register "query_slice" Command Route
        registry.register("query_slice", Arc::new(|req, kernel| {
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
            let rules_val = req.get("rules");
            let parsed_rules: Option<Vec<SliceRule>> = if let Some(rv) = rules_val {
                serde_json::from_value(rv.clone()).ok()
            } else {
                None
            };

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

            serde_json::json!({ "ok": true, "facts": filtered })
        }));

        Ok(())
    }
}
