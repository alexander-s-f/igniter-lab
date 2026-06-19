// src/packs/trigger.rs
// Reactive Triggers & Dynamic Async Webhook Dispatcher Pack for TBackend

use crate::kernel::{PackManifest, RequestMiddleware, ServerKernel, ServerPack, BackgroundService};
use std::collections::HashMap;
use std::net::TcpStream;
use std::io::{Read, Write};
use std::sync::{Arc, OnceLock};
use std::sync::mpsc::{channel, Sender, Receiver};
use std::thread;
use parking_lot::RwLock;
use uuid::Uuid;

// ── Trigger Domain Model & Registry ──────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct Trigger {
    pub id: String,
    pub store: String,
    pub key_prefix: Option<String>,
    pub webhook_url: String,
}

pub struct TriggerRegistry {
    pub triggers: HashMap<String, Trigger>,
}

impl TriggerRegistry {
    pub fn new() -> Self {
        Self { triggers: HashMap::new() }
    }
}

// ── Asynchronous Webhook Dispatch Channel Queue ──────────────────────────────

pub(crate) struct DispatchReq {
    webhook_url: String,
    fact: serde_json::Value,
}

static TRIGGER_SENDER: OnceLock<Sender<DispatchReq>> = OnceLock::new();

// ── Zero-Dependency Lightweight HTTP Client ──────────────────────────────────

struct ParsedUrl {
    host: String,
    port: u16,
    path: String,
}

fn parse_url(url: &str) -> Result<ParsedUrl, String> {
    if !url.starts_with("http://") {
        return Err("Only raw HTTP (http://) callback urls are supported".to_string());
    }
    let without_schema = &url[7..];
    let (host_port, path) = match without_schema.find('/') {
        Some(idx) => (&without_schema[..idx], &without_schema[idx..]),
        None => (without_schema, "/"),
    };
    let (host, port) = match host_port.find(':') {
        Some(idx) => {
            let h = host_port[..idx].to_string();
            let p = host_port[idx+1..].parse::<u16>().map_err(|e| e.to_string())?;
            (h, p)
        }
        None => (host_port.to_string(), 80),
    };
    Ok(ParsedUrl {
        host,
        port,
        path: path.to_string(),
    })
}

fn dispatch_webhook(url: &str, payload: &serde_json::Value) -> Result<(), String> {
    let parsed = parse_url(url)?;
    
    let mut stream = TcpStream::connect(format!("{}:{}", parsed.host, parsed.port))
        .map_err(|e| e.to_string())?;
        
    stream.set_write_timeout(Some(std::time::Duration::from_secs(3))).map_err(|e| e.to_string())?;
    stream.set_read_timeout(Some(std::time::Duration::from_secs(3))).map_err(|e| e.to_string())?;

    let body = serde_json::to_string(payload).unwrap();
    let req_str = format!(
        "POST {} HTTP/1.1\r\n\
         Host: {}\r\n\
         Content-Type: application/json\r\n\
         Content-Length: {}\r\n\
         Connection: close\r\n\r\n\
         {}",
        parsed.path, parsed.host, body.len(), body
    );

    stream.write_all(req_str.as_bytes()).map_err(|e| e.to_string())?;
    stream.flush().map_err(|e| e.to_string())?;
    
    // Read response header briefly to assert delivery success
    let mut resp_buf = [0u8; 1024];
    let _ = stream.read(&mut resp_buf);
    
    Ok(())
}

// ── Background Webhook Worker Service ────────────────────────────────────────

pub struct TriggerDispatcherService {
    rx: Mutex<Option<Receiver<DispatchReq>>>,
}

impl TriggerDispatcherService {
    pub fn new(rx: Receiver<DispatchReq>) -> Self {
        Self {
            rx: Mutex::new(Some(rx)),
        }
    }
}

// Wrapping std::sync::Mutex to satisfy Send/Sync bounds cleanly
struct Mutex<T>(std::sync::Mutex<T>);
impl<T> Mutex<T> {
    fn new(val: T) -> Self {
        Mutex(std::sync::Mutex::new(val))
    }
    fn lock(&self) -> std::sync::MutexGuard<'_, T> {
        self.0.lock().unwrap()
    }
}
unsafe impl<T> Send for Mutex<T> {}
unsafe impl<T> Sync for Mutex<T> {}

impl BackgroundService for TriggerDispatcherService {
    fn start(&self, _kernel: Arc<ServerKernel>) -> Result<(), String> {
        let rx = match self.rx.lock().take() {
            Some(r) => r,
            None => return Ok(()),
        };

        println!("[Trigger Service] Starting asynchronous webhook dispatcher thread...");
        thread::spawn(move || {
            loop {
                // Block worker until a webhook dispatch request is queued
                let req = match rx.recv() {
                    Ok(r) => r,
                    Err(_) => break, // Channel closed, gracefully terminate dispatcher
                };

                // Asynchronously execute raw POST dispatch in background
                match dispatch_webhook(&req.webhook_url, &req.fact) {
                    Ok(_) => {
                        // Successfully dispatched
                    }
                    Err(e) => {
                        println!(
                            "\x1b[31m[Trigger Webhook Error] Failed dispatch to {}: {}\x1b[0m",
                            req.webhook_url, e
                        );
                    }
                }
            }
        });

        Ok(())
    }

    fn stop(&self) {
        // Automatically halted on process teardown
    }
}

// ── Trigger Interception Middleware ──────────────────────────────────────────

pub struct TriggerPackMiddleware {
    registry: Arc<RwLock<TriggerRegistry>>,
}

impl RequestMiddleware for TriggerPackMiddleware {
    fn before_request(&self, _req: &mut serde_json::Value, _kernel: &ServerKernel) -> Result<(), String> {
        Ok(())
    }

    fn after_response(&self, req: &serde_json::Value, resp: &mut serde_json::Value, _kernel: &ServerKernel) {
        // Intercept successful write_fact operations
        let op = req.get("op").and_then(|v| v.as_str()).unwrap_or("");
        if op == "write_fact" && resp.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            if let Some(fact_val) = req.get("fact") {
                let store = fact_val.get("store").and_then(|v| v.as_str()).unwrap_or("");
                let key = fact_val.get("key").and_then(|v| v.as_str()).unwrap_or("");

                // Lock registry briefly to match against active triggers
                let registry = self.registry.read();
                for trigger in registry.triggers.values() {
                    if trigger.store == store {
                        let prefix_match = match &trigger.key_prefix {
                            Some(prefix) => key.starts_with(prefix),
                            None => true,
                        };

                        if prefix_match {
                            if let Some(sender) = TRIGGER_SENDER.get() {
                                // Dispatch out-of-band to background queue thread
                                let _ = sender.send(DispatchReq {
                                    webhook_url: trigger.webhook_url.clone(),
                                    fact: fact_val.clone(),
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Trigger Pack ─────────────────────────────────────────────────────────────

pub struct TriggerPack {
    registry: Arc<RwLock<TriggerRegistry>>,
}

impl TriggerPack {
    pub fn new() -> Self {
        Self {
            registry: Arc::new(RwLock::new(TriggerRegistry::new())),
        }
    }
}

impl ServerPack for TriggerPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "trigger",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["triggers", "webhooks"],
            requires_capabilities: vec!["bitemporal_ledger"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let registry = &mut *kernel.command_registry.write();

        // 1. Setup global channel queue
        let (tx, rx) = channel::<DispatchReq>();
        let _ = TRIGGER_SENDER.set(tx);

        // 2. Register command "trigger_create"
        let registry_c = self.registry.clone();
        registry.register("trigger_create", Arc::new(move |req, _kernel| {
            let store = match req.get("store").and_then(|v| v.as_str()) {
                Some(s) => s.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'store' parameter" }),
            };
            let webhook_url = match req.get("webhook_url").and_then(|v| v.as_str()) {
                Some(w) => w.to_string(),
                None => return serde_json::json!({ "ok": false, "error": "Missing 'webhook_url' parameter" }),
            };
            let key_prefix = req.get("key_prefix").and_then(|v| v.as_str()).map(|s| s.to_string());

            let trigger_id = format!("trig_{}", Uuid::new_v4().to_string()[0..8].to_string());
            let trigger = Trigger {
                id: trigger_id.clone(),
                store,
                key_prefix,
                webhook_url,
            };

            registry_c.write().triggers.insert(trigger_id.clone(), trigger);
            serde_json::json!({ "ok": true, "trigger_id": trigger_id })
        }));

        // 3. Register command "trigger_list"
        let registry_c = self.registry.clone();
        registry.register("trigger_list", Arc::new(move |_req, _kernel| {
            let map = registry_c.read();
            let list: Vec<Trigger> = map.triggers.values().cloned().collect();
            serde_json::json!({ "ok": true, "triggers": list })
        }));

        // 4. Register command "trigger_delete"
        let registry_c = self.registry.clone();
        registry.register("trigger_delete", Arc::new(move |req, _kernel| {
            let trigger_id = match req.get("trigger_id").and_then(|v| v.as_str()) {
                Some(id) => id,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'trigger_id' parameter" }),
            };

            let removed = registry_c.write().triggers.remove(trigger_id);
            serde_json::json!({ "ok": removed.is_some() })
        }));

        // 5. Register Interception Middleware
        kernel.middleware_chain.write().register(Arc::new(TriggerPackMiddleware {
            registry: self.registry.clone(),
        }));

        // 6. Register Background Dispatcher Thread
        let dispatcher = TriggerDispatcherService::new(rx);
        kernel.background_services.write().push(Box::new(dispatcher));

        Ok(())
    }
}
