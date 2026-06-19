// src/pipeline.rs
// Reactive Event-Driven Projection Pipeline Orchestrator

use crate::compiler::Compiler;
use crate::reactive::ReactiveListener;
use crate::tbackend::LedgerTcpBackend;
use crate::value::Value;
use crate::vm::VM;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

// ANSI styling
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const CYAN: &str = "\x1b[36m";
const RESET: &str = "\x1b[0m";

pub struct ProjectionPipeline {
    contract_jv: serde_json::Value,
    tbackend_addr: String,
    listener_port: u16,
    trigger_store: String,
    target_store: String,
    trigger_id: Mutex<Option<String>>,
}

impl ProjectionPipeline {
    pub fn new(
        contract_jv: serde_json::Value,
        tbackend_addr: &str,
        listener_port: u16,
        trigger_store: &str,
        target_store: &str,
    ) -> Self {
        Self {
            contract_jv,
            tbackend_addr: tbackend_addr.to_string(),
            listener_port,
            trigger_store: trigger_store.to_string(),
            target_store: target_store.to_string(),
            trigger_id: Mutex::new(None),
        }
    }

    // Connects to ledger, registers a dynamic webhook, and boots the background listener loop
    pub async fn start(&self, default_inputs: HashMap<String, Value>) -> Result<(), String> {
        let client = LedgerTcpBackend::new(&self.tbackend_addr);

        // 1. Compile contract AST to Bytecode instructions
        let mut compiler = Compiler::new();
        let bytecode = compiler.compile(&self.contract_jv)?;
        let bytecode_arc = Arc::new(bytecode);

        // 2. Register dynamic trigger webhook remotely on tbackend server
        println!(
            "  {} [*] Registering dynamic webhook trigger on Remote Ledger...{}",
            YELLOW, RESET
        );
        let webhook_url = format!("http://127.0.0.1:{}/evaluate", self.listener_port);
        let reg_req = serde_json::json!({
            "op": "trigger_create",
            "store": &self.trigger_store,
            "key_prefix": "", // Matches all keys
            "webhook_url": &webhook_url
        });

        let reg_resp = client.send_req(reg_req).await?;
        if !reg_resp
            .get("ok")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return Err(format!(
                "Failed to register trigger: {:?}",
                reg_resp.get("error")
            ));
        }

        let trig_id = reg_resp
            .get("trigger_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| "Missing trigger_id in response".to_string())?
            .to_string();

        println!(
            "      {}✔ Webhook trigger registered successfully! ID: {}{}",
            GREEN, trig_id, RESET
        );
        {
            let mut guard = self.trigger_id.lock().await;
            *guard = Some(trig_id.clone());
        }

        // 3. Spawns asynchronous VM execution webhook listener
        println!(
            "  {} [*] Booting background HTTP Webhook Listener on port {}...{}",
            YELLOW, self.listener_port, RESET
        );
        let listener = ReactiveListener::new(self.listener_port);

        let tbackend_addr_clone = self.tbackend_addr.clone();
        let target_store_clone = self.target_store.clone();
        let default_inputs_arc = Arc::new(default_inputs);

        let modifier = self
            .contract_jv
            .get("modifier")
            .or_else(|| {
                if let Some(contracts_arr) =
                    self.contract_jv.get("contracts").and_then(|c| c.as_array())
                {
                    contracts_arr.get(0).and_then(|c| c.get("modifier"))
                } else {
                    None
                }
            })
            .and_then(|m| m.as_str())
            .unwrap_or("pure")
            .to_string();

        let modifier_clone = modifier.clone();
        listener
            .listen(move |fact_jv| {
                let bytecode_c = bytecode_arc.clone();
                let addr_c = tbackend_addr_clone.clone();
                let store_c = target_store_clone.clone();
                let inputs_c = default_inputs_arc.clone();
                let modifier_c = modifier_clone.clone();

                async move {
                    let key = fact_jv
                        .get("key")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    println!(
                        "  {} [*] Received reactive trigger event on store key: {}{}",
                        CYAN, key, RESET
                    );

                    // Setup temporal coordinates from the incoming fact or fallback to default
                    let mut inputs = (*inputs_c).clone();
                    let mut temp_ctx = HashMap::new();

                    let vt_str = if let Some(vt) = fact_jv.get("valid_time") {
                        if let Some(vt_f) = vt.as_f64() {
                            // Convert float timestamp back to ISO8601 for VM
                            let dt = chrono::DateTime::from_timestamp(vt_f as i64, 0)
                                .unwrap_or_else(|| chrono::Utc::now());
                            dt.to_rfc3339()
                        } else {
                            chrono::Utc::now().to_rfc3339()
                        }
                    } else {
                        chrono::Utc::now().to_rfc3339()
                    };

                    inputs.insert(
                        "as_of".to_string(),
                        Value::String(Arc::from(vt_str.as_str())),
                    );
                    temp_ctx.insert(
                        "as_of".to_string(),
                        Value::String(Arc::from(vt_str.as_str())),
                    );

                    inputs.insert(
                        "contract_modifier".to_string(),
                        Value::String(Arc::from(modifier_c.as_str())),
                    );
                    temp_ctx.insert(
                        "contract_modifier".to_string(),
                        Value::String(Arc::from(modifier_c.as_str())),
                    );

                    let client = LedgerTcpBackend::new(&addr_c);
                    let vm = VM::new(Some(Arc::new(client)));

                    // Evaluate the projection
                    match vm.execute(&bytecode_c, &inputs, &temp_ctx).await {
                        Ok(result) => {
                            println!(
                                "      {}✔ VM execution success! Output: {:?}",
                                GREEN, result
                            );
                            // Ingest calculated bitemporal projection back to tbackend remotely
                            let client_commit = LedgerTcpBackend::new(&addr_c);
                            let commit_req = serde_json::json!({
                                "op": "write_fact",
                                "fact": {
                                    "id": uuid::Uuid::new_v4().to_string(),
                                    "store": &store_c,
                                    "key": "global",
                                    "value": result.to_json(),
                                    "value_hash": "projection-hash-string",
                                    "transaction_time": chrono::Utc::now().timestamp() as f64,
                                    "valid_time": chrono::Utc::now().timestamp() as f64,
                                    "schema_version": 1
                                }
                            });

                            match client_commit.send_req(commit_req).await {
                                Ok(resp) => {
                                    if resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                                        println!(
                                            "      {}✔ Committed dynamic projection back to: {}{}",
                                            GREEN, store_c, RESET
                                        );
                                    } else {
                                        eprintln!(
                                            "      [!] Failed to commit projection: {:?}",
                                            resp.get("error")
                                        );
                                    }
                                }
                                Err(e) => eprintln!("      [!] Failed to commit projection: {}", e),
                            }
                        }
                        Err(e) => eprintln!("      [!] VM evaluation failed: {}", e),
                    }
                }
            })
            .await?;

        Ok(())
    }

    // Remotely deletes trigger to prevent dangling hooks
    pub async fn shutdown(&self) -> Result<(), String> {
        let mut guard = self.trigger_id.lock().await;
        if let Some(ref trig_id) = *guard {
            println!(
                "  {} [*] Cleaning up remote webhook trigger: {}{}",
                YELLOW, trig_id, RESET
            );
            let client = LedgerTcpBackend::new(&self.tbackend_addr);
            let del_req = serde_json::json!({
                "op": "trigger_delete",
                "trigger_id": trig_id
            });
            let resp = client.send_req(del_req).await?;
            if resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                println!(
                    "      {}✔ Trigger deleted from remote registry.{}",
                    GREEN, RESET
                );
                *guard = None;
            } else {
                return Err(format!("Failed to delete trigger: {:?}", resp.get("error")));
            }
        }
        Ok(())
    }
}
