// src/packs/pipeline.rs
// Reactive Event-Driven Pipelines, State Combines & ROP Rules Engine Pack for TBackend

use crate::kernel::{BackgroundService, PackManifest, ServerKernel, ServerPack};
use crate::pure_core::FactData;
use parking_lot::{Mutex, RwLock};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::Arc;
use std::sync::OnceLock;
use std::thread;

// ── Pipeline Schema Domain Model ─────────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct CombineStoreDef {
    pub store: String,
    pub key_path: String, // Path in trigger fact to resolve lookup key (e.g. "value.partner_id"). Empty = trigger's key
    pub alias: String,    // Query context alias (e.g. "availabilities")
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct PipelineRule {
    pub left_path: String, // Context query path (e.g. "availabilities.value.count")
    pub op: String,        // eq, gt, lt, contains
    pub right_val: serde_json::Value,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct PipelineDef {
    pub id: String,
    pub trigger_store: String,
    pub filter_prefix: Option<String>,
    pub combines: Vec<CombineStoreDef>,
    pub rules: Vec<PipelineRule>,
    pub transform_template: serde_json::Value,
    pub action_target_store: Option<String>,
    pub action_webhook_url: Option<String>,
    #[serde(default)]
    pub persist: bool,
}

pub struct PipelineRegistry {
    pub pipelines: HashMap<String, PipelineDef>,
}

impl PipelineRegistry {
    pub fn new() -> Self {
        Self {
            pipelines: HashMap::new(),
        }
    }
}

// ── Global OS-Native Channel Queue Singlet ───────────────────────────────────

pub static PIPELINE_SENDER: OnceLock<std::sync::mpsc::Sender<FactData>> = OnceLock::new();

// ── Context Evaluator & Template Render Engines ──────────────────────────────

fn resolve_context_value(
    context: &HashMap<String, FactData>,
    path: &str,
) -> Option<serde_json::Value> {
    let parts: Vec<&str> = path.split('.').collect();
    if parts.is_empty() {
        return None;
    }

    let alias = parts[0];
    let fact = context.get(alias)?;

    if parts.len() == 1 {
        return serde_json::to_value(fact).ok();
    }

    let sub_field = parts[1];
    match sub_field {
        "id" => return Some(serde_json::Value::String(fact.id.clone())),
        "key" => return Some(serde_json::Value::String(fact.key.clone())),
        "transaction_time" => return Some(serde_json::json!(fact.transaction_time)),
        "valid_time" => return fact.valid_time.map(|vt| serde_json::json!(vt)),
        "producer" => {
            return fact
                .producer
                .as_ref()
                .map(|p| serde_json::Value::String(p.clone()))
        }
        "causation" => {
            return fact
                .causation
                .as_ref()
                .map(|c| serde_json::Value::String(c.clone()))
        }
        "value" => {
            let mut current = &fact.value;
            for part in &parts[2..] {
                current = current.get(*part)?;
            }
            return Some(current.clone());
        }
        _ => {}
    }

    // Fallback: direct check inside value
    if let Some(val) = fact.value.get(sub_field) {
        let mut current = val;
        for part in &parts[2..] {
            current = current.get(*part)?;
        }
        return Some(current.clone());
    }

    None
}

fn render_template(
    template: &serde_json::Value,
    context: &HashMap<String, FactData>,
) -> serde_json::Value {
    match template {
        serde_json::Value::String(s) => {
            let trimmed = s.trim();
            if trimmed.starts_with("{{") && trimmed.ends_with("}}") {
                let path = &trimmed[2..trimmed.len() - 2].trim();
                if let Some(val) = resolve_context_value(context, path) {
                    return val;
                }
            }

            // Inline placeholder loop
            let mut result = s.clone();
            while let Some(start_idx) = result.find("{{") {
                if let Some(end_offset) = result[start_idx..].find("}}") {
                    let end_idx = start_idx + end_offset;
                    let path = &result[start_idx + 2..end_idx].trim();
                    let val_str = match resolve_context_value(context, path) {
                        Some(serde_json::Value::String(sv)) => sv,
                        Some(other) => other.to_string(),
                        None => "".to_string(),
                    };
                    result.replace_range(start_idx..end_idx + 2, &val_str);
                } else {
                    break;
                }
            }
            serde_json::Value::String(result)
        }
        serde_json::Value::Array(arr) => {
            let rendered: Vec<serde_json::Value> = arr
                .iter()
                .map(|item| render_template(item, context))
                .collect();
            serde_json::Value::Array(rendered)
        }
        serde_json::Value::Object(obj) => {
            let mut rendered = serde_json::Map::new();
            for (k, v) in obj {
                rendered.insert(k.clone(), render_template(v, context));
            }
            serde_json::Value::Object(rendered)
        }
        other => other.clone(),
    }
}

fn evaluate_rule(rule: &PipelineRule, context: &HashMap<String, FactData>) -> bool {
    let val = match resolve_context_value(context, &rule.left_path) {
        Some(v) => v,
        None => return false, // ROP Short-circuit failure
    };

    match rule.op.as_str() {
        "eq" => val == rule.right_val,
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

// ── Webhook Out-Of-Band Socket Client ────────────────────────────────────────

fn dispatch_webhook_payload(url_str: &str, payload: &serde_json::Value) -> Result<(), String> {
    if !url_str.starts_with("http://") {
        return Err("Only raw HTTP webhooks are supported in raw socket dispatcher".to_string());
    }
    let without_prefix = &url_str[7..];
    let slash_idx = without_prefix.find('/').unwrap_or(without_prefix.len());
    let host_port = &without_prefix[..slash_idx];
    let path = &without_prefix[slash_idx..];
    let path = if path.is_empty() { "/" } else { path };

    let (host, port) = if let Some(colon_idx) = host_port.find(':') {
        let h = &host_port[..colon_idx];
        let p = host_port[colon_idx + 1..]
            .parse::<u16>()
            .map_err(|e| e.to_string())?;
        (h, p)
    } else {
        (host_port, 80)
    };

    let mut stream = std::net::TcpStream::connect(format!("{}:{}", host, port))
        .map_err(|e| format!("Failed to connect to webhook host {}:{}: {}", host, port, e))?;

    let body = serde_json::to_string(payload).unwrap_or_default();
    let request = format!(
        "POST {} HTTP/1.1\r\n\
         Host: {}\r\n\
         Content-Type: application/json\r\n\
         Content-Length: {}\r\n\
         Connection: close\r\n\r\n\
         {}",
        path,
        host_port,
        body.len(),
        body
    );

    stream
        .write_all(request.as_bytes())
        .map_err(|e| e.to_string())?;
    stream.flush().map_err(|e| e.to_string())?;

    let mut response = String::new();
    let _ = stream.read_to_string(&mut response);

    Ok(())
}

// ── Asynchronous Pipeline Executor ───────────────────────────────────────────

fn execute_pipeline(
    pipeline: &PipelineDef,
    triggering_fact: &FactData,
    kernel: &ServerKernel,
) -> Result<(), String> {
    // 1. Combine stage
    let mut context = HashMap::new();
    context.insert(triggering_fact.store.clone(), triggering_fact.clone());
    context.insert("trigger".to_string(), triggering_fact.clone());

    for comb in &pipeline.combines {
        let key = if comb.key_path.is_empty() {
            triggering_fact.key.clone()
        } else {
            match resolve_context_value(&context, &comb.key_path) {
                Some(serde_json::Value::String(s)) => s,
                Some(other) => other.to_string(),
                None => return Err(format!("Could not resolve key path '{}'", comb.key_path)),
            }
        };

        let engine = kernel
            .get_or_create_engine(&comb.store)
            .ok_or_else(|| format!("Combine store '{}' not found", comb.store))?;

        let latest = engine
            .log
            .latest_for(&comb.store, &key, None)
            .ok_or_else(|| {
                format!(
                    "No active fact found for combine store '{}', key '{}' (Short-circuit ROP)",
                    comb.store, key
                )
            })?;

        context.insert(comb.alias.clone(), latest);
    }

    // 2. Rules Evaluation stage
    for rule in &pipeline.rules {
        if !evaluate_rule(rule, &context) {
            return Err(format!(
                "Rule predicate failed: {} {:?} {:?}",
                rule.left_path, rule.op, rule.right_val
            ));
        }
    }

    // 3. Transform stage
    let transformed_val = render_template(&pipeline.transform_template, &context);

    // 4a. Action Target Store (Stream)
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);

    if let Some(ref target_store) = pipeline.action_target_store {
        let engine = kernel
            .get_or_create_engine(target_store)
            .ok_or_else(|| format!("Action target store '{}' invalid", target_store))?;

        let out_fact = FactData {
            id: uuid::Uuid::new_v4().to_string(),
            store: target_store.clone(),
            key: format!("stream-{}-{}", pipeline.id, triggering_fact.key),
            value: transformed_val.clone(),
            value_hash: "pipeline-transformed-hash".to_string(),
            causation: Some(triggering_fact.id.clone()),
            transaction_time: now,
            valid_time: Some(now),
            schema_version: 1,
            producer: Some(format!("PipelinePack:{}", pipeline.id)),
            derivation: Some(format!(
                "Reactive pipeline transformation of {} key {}",
                triggering_fact.store, triggering_fact.key
            )),
        };

        if let Some(ref fb) = engine.wal {
            fb.write_fact_data(&out_fact)
                .map_err(|e| format!("WAL write failed: {}", e))?;
        }
        engine.log.push(out_fact);
    }

    // 4b. Action Webhook Dispatch
    if let Some(ref url) = pipeline.action_webhook_url {
        dispatch_webhook_payload(url, &transformed_val)?;
    }

    Ok(())
}

// ── Background Execution Service ─────────────────────────────────────────────

pub struct PipelineService {
    registry: Arc<RwLock<PipelineRegistry>>,
    receiver: Mutex<Option<std::sync::mpsc::Receiver<FactData>>>,
}

impl BackgroundService for PipelineService {
    fn start(&self, kernel: Arc<ServerKernel>) -> Result<(), String> {
        let rx = match self.receiver.lock().take() {
            Some(r) => r,
            None => return Err("PipelineService receiver already started".to_string()),
        };
        let registry = self.registry.clone();

        println!("[Pipeline Service] Starting asynchronous event pipeline dispatch thread...");
        thread::spawn(move || {
            loop {
                let fact = match rx.recv() {
                    Ok(f) => f,
                    Err(_) => break, // Channel disconnected
                };

                let pipelines: Vec<PipelineDef> = {
                    let r = registry.read();
                    r.pipelines
                        .values()
                        .filter(|p| {
                            if p.trigger_store != fact.store {
                                return false;
                            }
                            if let Some(ref prefix) = p.filter_prefix {
                                fact.key.starts_with(prefix)
                            } else {
                                true
                            }
                        })
                        .cloned()
                        .collect()
                };

                for pipeline in pipelines {
                    let kernel_c = kernel.clone();
                    let fact_c = fact.clone();

                    // Spawn out-of-band execution thread per matched pipeline
                    thread::spawn(move || {
                        if let Err(e) = execute_pipeline(&pipeline, &fact_c, &kernel_c) {
                            eprintln!("[Pipeline Error] Aborted pipeline {}: {}", pipeline.id, e);
                        }
                    });
                }
            }
        });

        Ok(())
    }

    fn stop(&self) {}
}

// ── Persistent Preloading Scanner ────────────────────────────────────────────

fn load_persistent_pipelines(dir_path: &str) -> HashMap<String, PipelineDef> {
    let mut map = HashMap::new();
    let pipelines_dir = format!("{}/pipelines", dir_path);

    // Ensure dir exists
    let _ = std::fs::create_dir_all(&pipelines_dir);

    if let Ok(entries) = std::fs::read_dir(&pipelines_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map_or(false, |ext| ext == "json") {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(mut pipeline) = serde_json::from_str::<PipelineDef>(&content) {
                        println!(
                            "[Pipeline Preloader] Preloaded persistent pipeline {} from storage",
                            pipeline.id
                        );
                        pipeline.persist = true; // Ensure persist flag remains true
                        map.insert(pipeline.id.clone(), pipeline);
                    }
                }
            }
        }
    }
    map
}

// ── Pipeline Middleware Interception ─────────────────────────────────────────

pub struct PipelineMiddleware;

impl crate::kernel::RequestMiddleware for PipelineMiddleware {
    fn before_request(
        &self,
        _req: &mut serde_json::Value,
        _kernel: &ServerKernel,
    ) -> Result<(), String> {
        Ok(())
    }

    fn after_response(
        &self,
        req: &serde_json::Value,
        resp: &mut serde_json::Value,
        kernel: &ServerKernel,
    ) {
        // Intercept successful write_fact operations
        let op = req.get("op").and_then(|v| v.as_str()).unwrap_or("");
        if op != "write_fact" {
            return;
        }

        let is_ok = resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
        if !is_ok {
            return;
        }

        let fact_val = match req.get("fact") {
            Some(f) => f,
            None => return,
        };

        let fact: FactData = match serde_json::from_value(fact_val.clone()) {
            Ok(d) => d,
            Err(_) => return,
        };

        // Query dynamic engines cache warming to make sure it exists
        let _ = kernel.get_or_create_engine(&fact.store);

        // Queue onto asynchronous dispatch queue
        if let Some(sender) = PIPELINE_SENDER.get() {
            let _ = sender.send(fact);
        }
    }
}

// ── Pipeline Pack Mount ──────────────────────────────────────────────────────

pub struct PipelinePack {
    registry: Arc<RwLock<PipelineRegistry>>,
    receiver: Mutex<Option<std::sync::mpsc::Receiver<FactData>>>,
}

impl PipelinePack {
    pub fn new() -> Self {
        let (tx, rx) = std::sync::mpsc::channel();
        let _ = PIPELINE_SENDER.set(tx);

        Self {
            registry: Arc::new(RwLock::new(PipelineRegistry::new())),
            receiver: Mutex::new(Some(rx)),
        }
    }
}

impl ServerPack for PipelinePack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "pipeline",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["reactive_pipelines", "event_gossip"],
            requires_capabilities: vec!["audit", "bitemporal_ledger"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        // 1. Scan and preload any persistent pipelines on boot
        if let Some(ref dir) = kernel.data_dir {
            let loaded = load_persistent_pipelines(dir);
            self.registry.write().pipelines.extend(loaded);
        }

        let command_reg = &mut *kernel.command_registry.write();

        // 2. Register "pipeline_create" Command Route
        let registry_c = self.registry.clone();
        let data_dir_c = kernel.data_dir.clone();
        command_reg.register("pipeline_create", Arc::new(move |req, _kernel| {
            let trigger_store = match req.get("trigger_store").and_then(|v| v.as_str()) {
                Some(s) => s.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'trigger_store' parameter" }),
            };

            let filter_prefix = req.get("filter_prefix").and_then(|v| v.as_str()).map(|s| s.to_string());
            let persist = req.get("persist").and_then(|v| v.as_bool()).unwrap_or(false);

            let combines_arr = match req.get("combines").and_then(|v| v.as_array()) {
                Some(arr) => arr,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'combines' array" }),
            };

            let mut combines = Vec::new();
            for item in combines_arr {
                let store = match item.get("store").and_then(|v| v.as_str()) {
                    Some(s) => s.to_string(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'store' in combines item" }),
                };
                let key_path = item.get("key_path").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let alias = match item.get("alias").and_then(|v| v.as_str()) {
                    Some(a) => a.to_string(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'alias' in combines item" }),
                };
                combines.push(CombineStoreDef { store, key_path, alias });
            }

            let rules_arr = match req.get("rules").and_then(|v| v.as_array()) {
                Some(arr) => arr,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'rules' array" }),
            };

            let mut rules = Vec::new();
            for item in rules_arr {
                let left_path = match item.get("left_path").and_then(|v| v.as_str()) {
                    Some(lp) => lp.to_string(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'left_path' in rules item" }),
                };
                let op = match item.get("op").and_then(|v| v.as_str()) {
                    Some(o) => o.to_string(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'op' in rules item" }),
                };
                let right_val = match item.get("right_val") {
                    Some(rv) => rv.clone(),
                    None => return serde_json::json!({ "ok": false, "error": "Missing 'right_val' in rules item" }),
                };
                rules.push(PipelineRule { left_path, op, right_val });
            }

            let transform_template = match req.get("transform_template") {
                Some(t) => t.clone(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'transform_template'" }),
            };

            let action_target_store = req.get("action_target_store").and_then(|v| v.as_str()).map(|s| s.to_string());
            let action_webhook_url = req.get("action_webhook_url").and_then(|v| v.as_str()).map(|s| s.to_string());

            let pipeline_id = format!("pipe_{}", uuid::Uuid::new_v4().to_string()[0..8].to_string());
            let pipeline = PipelineDef {
                id: pipeline_id.clone(),
                trigger_store,
                filter_prefix,
                combines,
                rules,
                transform_template,
                action_target_store,
                action_webhook_url,
                persist,
            };

            // Save to disk if persistence is requested
            if persist {
                if let Some(ref dir) = data_dir_c {
                    let file_path = format!("{}/pipelines/{}.json", dir, pipeline_id);
                    if let Ok(content) = serde_json::to_string_pretty(&pipeline) {
                        let _ = std::fs::write(&file_path, content);
                    }
                }
            }

            registry_c.write().pipelines.insert(pipeline_id.clone(), pipeline);
            serde_json::json!({ "ok": true, "pipeline_id": pipeline_id })
        }));

        // 3. Register "pipeline_list" Command Route
        let registry_c = self.registry.clone();
        command_reg.register(
            "pipeline_list",
            Arc::new(move |_req, _kernel| {
                let map = registry_c.read();
                let list: Vec<PipelineDef> = map.pipelines.values().cloned().collect();
                serde_json::json!({ "ok": true, "pipelines": list })
            }),
        );

        // 4. Register "pipeline_delete" Command Route
        let registry_c = self.registry.clone();
        let data_dir_c = kernel.data_dir.clone();
        command_reg.register("pipeline_delete", Arc::new(move |req, _kernel| {
            let pipeline_id = match req.get("pipeline_id").and_then(|v| v.as_str()) {
                Some(id) => id,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'pipeline_id' parameter" }),
            };

            let mut map = registry_c.write();
            if let Some(pipeline) = map.pipelines.remove(pipeline_id) {
                if pipeline.persist {
                    if let Some(ref dir) = data_dir_c {
                        let file_path = format!("{}/pipelines/{}.json", dir, pipeline_id);
                        let _ = std::fs::remove_file(file_path);
                    }
                }
                serde_json::json!({ "ok": true })
            } else {
                serde_json::json!({ "ok": false, "error": format!("Pipeline '{}' not found", pipeline_id) })
            }
        }));

        // 5. Mount Pipeline Middleware into Chain
        kernel
            .middleware_chain
            .write()
            .register(Arc::new(PipelineMiddleware));

        // 6. Register Background Dispatch Service
        let rx = self
            .receiver
            .lock()
            .take()
            .expect("Receiver missing during PipelinePack mount!");
        let service = PipelineService {
            registry: self.registry.clone(),
            receiver: Mutex::new(Some(rx)),
        };
        kernel.background_services.write().push(Box::new(service));

        Ok(())
    }
}
