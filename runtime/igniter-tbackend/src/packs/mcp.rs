// src/packs/mcp.rs
// Zero-dependency native stdio Model Context Protocol (MCP) server for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack, ServerProfile};
use serde_json::json;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::io::FromRawFd;
use std::sync::Arc;

pub struct McpPack;

impl McpPack {
    pub fn new() -> Self {
        McpPack
    }
}

impl ServerPack for McpPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "mcp",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["mcp_interface"],
            requires_capabilities: vec!["bitemporal_ledger"],
        }
    }

    fn install_into(&self, _kernel: &mut ServerKernel) -> Result<(), String> {
        // MCP loop runs out-of-band via raw stdio, no custom command routes needed in registry
        Ok(())
    }
}

pub fn run_mcp_loop(
    kernel: Arc<ServerKernel>,
    profile: ServerProfile,
    original_stdout_fd: std::os::raw::c_int,
) {
    // 3. Create BufReader for stdin and Write for duplicated stdout
    let stdin = std::io::stdin();
    let stdin_lock = stdin.lock();
    let mut reader = BufReader::new(stdin_lock);
    let mut writer = unsafe { File::from_raw_fd(original_stdout_fd) };

    eprintln!("[MCP Server] Native MCP stdio loop spawned. Stdin reading online.");

    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => {
                eprintln!("[MCP Server] EOF received on stdin. Exiting.");
                break;
            }
            Ok(_) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }

                // Process JSON-RPC 2.0 Message
                let request: serde_json::Value = match serde_json::from_str(trimmed) {
                    Ok(v) => v,
                    Err(e) => {
                        let err_resp = json!({
                            "jsonrpc": "2.0",
                            "error": { "code": -32700, "message": format!("Parse error: {}", e) },
                            "id": null
                        });
                        let _ = writeln!(writer, "{}", err_resp.to_string());
                        let _ = writer.flush();
                        continue;
                    }
                };

                let method = request.get("method").and_then(|v| v.as_str()).unwrap_or("");
                let id = request
                    .get("id")
                    .cloned()
                    .unwrap_or(serde_json::Value::Null);

                match method {
                    "tools/list" => {
                        let tools_list = json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": {
                                "tools": [
                                    {
                                        "name": "tbackend_write_fact",
                                        "description": "Commits a new bitemporal fact to the database partition",
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "token": { "type": "string", "description": "Security token if auth-enabled" },
                                                "store": { "type": "string", "description": "Target store name" },
                                                "key": { "type": "string", "description": "Lookup key" },
                                                "value": { "type": "object", "description": "Fact payload object" },
                                                "valid_time": { "type": "number", "description": "Optional valid-time timestamp" },
                                                "producer": { "type": "string", "description": "Optional producer name" },
                                                "causation": { "type": "string", "description": "Optional causation event UUID" }
                                            },
                                            "required": ["store", "key", "value"]
                                        }
                                    },
                                    {
                                        "name": "tbackend_latest_for",
                                        "description": "Looks up the pointwise active state of a key at a specific transaction time (time-travel)",
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "token": { "type": "string", "description": "Security token" },
                                                "store": { "type": "string" },
                                                "key": { "type": "string" },
                                                "as_of": { "type": "number", "description": "Optional transaction-time coordinate" }
                                            },
                                            "required": ["store", "key"]
                                        }
                                    },
                                    {
                                        "name": "tbackend_query_slice",
                                        "description": "Performs temporal slicing with server-side ROP pushdown rules filtration",
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "token": { "type": "string" },
                                                "store": { "type": "string" },
                                                "since_val": { "type": "number" },
                                                "as_of_val": { "type": "number" },
                                                "key_prefix": { "type": "string" },
                                                "rules": {
                                                    "type": "array",
                                                    "items": {
                                                        "type": "object",
                                                        "properties": {
                                                            "left_path": { "type": "string" },
                                                            "op": { "type": "string", "enum": ["eq", "ne", "gt", "lt", "ge", "le", "contains"] },
                                                            "right_val": {}
                                                        },
                                                        "required": ["left_path", "op", "right_val"]
                                                    }
                                                }
                                            },
                                            "required": ["store"]
                                        }
                                    },
                                    {
                                        "name": "tbackend_analytics_aggregate",
                                        "description": "Calculates grouped aggregations (count, sum, avg, min, max, cardinality)",
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "token": { "type": "string" },
                                                "store": { "type": "string" },
                                                "group_by": { "type": "string" },
                                                "aggregates": {
                                                    "type": "array",
                                                    "items": {
                                                        "type": "object",
                                                        "properties": {
                                                            "field": { "type": "string" },
                                                            "op": { "type": "string", "enum": ["count", "sum", "avg", "min", "max", "cardinality"] }
                                                        },
                                                        "required": ["op"]
                                                    }
                                                },
                                                "rules": { "type": "array" },
                                                "since_val": { "type": "number" },
                                                "as_of_val": { "type": "number" }
                                            },
                                            "required": ["store", "aggregates"]
                                        }
                                    },
                                    {
                                        "name": "tbackend_pipeline_create",
                                        "description": "Creates an out-of-band reactive event pipeline",
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "token": { "type": "string" },
                                                "trigger_store": { "type": "string" },
                                                "action_webhook_url": { "type": "string" },
                                                "action_target_store": { "type": "string" },
                                                "persist": { "type": "boolean" }
                                            },
                                            "required": ["trigger_store"]
                                        }
                                    },
                                    {
                                        "name": "tbackend_diagnostics_summary",
                                        "description": "Retrieves partition diagnostic metrics and RAM footprint allocations",
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "token": { "type": "string" }
                                            }
                                        }
                                    }
                                ]
                            }
                        });
                        let _ = writeln!(writer, "{}", tools_list.to_string());
                        let _ = writer.flush();
                    }
                    "tools/call" => {
                        let params = request.get("params");
                        let tool_name = params
                            .and_then(|p| p.get("name"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let arguments = params
                            .and_then(|p| p.get("arguments"))
                            .cloned()
                            .unwrap_or(json!({}));

                        // Translate Tool Call to standard TCP operation payload
                        let mut op_req = match tool_name {
                            "tbackend_write_fact" => {
                                let store = arguments
                                    .get("store")
                                    .cloned()
                                    .unwrap_or(serde_json::Value::Null);
                                let key = arguments
                                    .get("key")
                                    .cloned()
                                    .unwrap_or(serde_json::Value::Null);
                                let value = arguments
                                    .get("value")
                                    .cloned()
                                    .unwrap_or(serde_json::Value::Null);
                                let valid_time = arguments
                                    .get("valid_time")
                                    .cloned()
                                    .unwrap_or(serde_json::Value::Null);
                                let producer = arguments
                                    .get("producer")
                                    .cloned()
                                    .unwrap_or(serde_json::Value::Null);
                                let causation = arguments
                                    .get("causation")
                                    .cloned()
                                    .unwrap_or(serde_json::Value::Null);

                                let id = arguments.get("id").cloned().unwrap_or_else(|| {
                                    serde_json::Value::String(uuid::Uuid::new_v4().to_string())
                                });

                                let tx_time = arguments
                                    .get("transaction_time")
                                    .cloned()
                                    .unwrap_or_else(|| {
                                        let now = std::time::SystemTime::now()
                                            .duration_since(std::time::UNIX_EPOCH)
                                            .unwrap()
                                            .as_secs_f64();
                                        serde_json::json!(now)
                                    });

                                let val_hash =
                                    arguments.get("value_hash").cloned().unwrap_or_else(|| {
                                        let val_str =
                                            serde_json::to_string(&value).unwrap_or_default();
                                        serde_json::Value::String(
                                            blake3::hash(val_str.as_bytes()).to_hex().to_string(),
                                        )
                                    });

                                let mut fact = json!({
                                    "id": id,
                                    "store": store,
                                    "key": key,
                                    "value": value,
                                    "value_hash": val_hash,
                                    "transaction_time": tx_time,
                                    "schema_version": 1
                                });
                                if !valid_time.is_null() {
                                    fact["valid_time"] = valid_time;
                                }
                                if !producer.is_null() {
                                    fact["producer"] = producer;
                                }
                                if !causation.is_null() {
                                    fact["causation"] = causation;
                                }

                                json!({
                                    "op": "write_fact",
                                    "token": arguments.get("token"),
                                    "fact": fact
                                })
                            }
                            "tbackend_latest_for" => {
                                let mut r = arguments.clone();
                                r["op"] = json!("latest_for");
                                r
                            }
                            "tbackend_query_slice" => {
                                let mut r = arguments.clone();
                                r["op"] = json!("query_slice");
                                r
                            }
                            "tbackend_analytics_aggregate" => {
                                let mut r = arguments.clone();
                                r["op"] = json!("analytics_aggregate");
                                r
                            }
                            "tbackend_pipeline_create" => {
                                let mut r = arguments.clone();
                                r["op"] = json!("pipeline_create");
                                r
                            }
                            "tbackend_diagnostics_summary" => {
                                let mut r = arguments.clone();
                                r["op"] = json!("diagnostics_summary");
                                r
                            }
                            _ => json!({ "error": format!("Unsupported tool: {}", tool_name) }),
                        };

                        if op_req.get("error").is_some() {
                            let err_resp = json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "error": { "code": -32601, "message": format!("Tool not found: {}", tool_name) }
                            });
                            let _ = writeln!(writer, "{}", err_resp.to_string());
                            let _ = writer.flush();
                            continue;
                        }

                        // Run request through kernel middlewares and execute standard handler
                        let resp = {
                            let mut middleware_err = None;
                            for mw in &profile.middleware_chain.middlewares {
                                if let Err(e) = mw.before_request(&mut op_req, &kernel) {
                                    middleware_err = Some(e);
                                    break;
                                }
                            }

                            let mut resp_val = if let Some(err) = middleware_err {
                                json!({ "ok": false, "error": err })
                            } else {
                                let op = op_req.get("op").and_then(|v| v.as_str()).unwrap_or("");
                                match profile.command_registry.call(op, &op_req, &kernel) {
                                    Some(res) => res,
                                    None => {
                                        json!({ "ok": false, "error": format!("Unknown operation: {}", op) })
                                    }
                                }
                            };

                            for mw in &profile.middleware_chain.middlewares {
                                mw.after_response(&op_req, &mut resp_val, &kernel);
                            }

                            resp_val
                        };

                        // Return response formatted in standard MCP call schema
                        let mcp_call_resp = json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": {
                                "content": [
                                    {
                                        "type": "text",
                                        "text": resp.to_string()
                                    }
                                ]
                            }
                        });

                        let _ = writeln!(writer, "{}", mcp_call_resp.to_string());
                        let _ = writer.flush();
                    }
                    _ => {
                        // Return standard JSON-RPC 2.0 method not found
                        let err_resp = json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "error": { "code": -32601, "message": format!("Method not found: {}", method) }
                        });
                        let _ = writeln!(writer, "{}", err_resp.to_string());
                        let _ = writer.flush();
                    }
                }
            }
            Err(e) => {
                eprintln!("[MCP Server] Read error: {}. Shutting down stdio loop.", e);
                break;
            }
        }
    }
}
