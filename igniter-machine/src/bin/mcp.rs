// src/bin/mcp.rs
// Igniter Machine MCP Server — JSON-RPC 2.0 over stdio
//
// Register in Claude Desktop:
//   ~/Library/Application Support/Claude/claude_desktop_config.json
//   { "mcpServers": { "igniter": { "command": "/path/to/igniter-mcp" } } }

use igniter_machine::fact::Fact;
use igniter_machine::machine::IgniterMachine;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::sync::Mutex;

// ── Helpers ──────────────────────────────────────────────────────────────────

fn respond(out: &mut impl Write, id: Value, result: Value) {
    let msg = json!({ "jsonrpc": "2.0", "id": id, "result": result });
    let _ = writeln!(out, "{}", msg);
    let _ = out.flush();
}

fn respond_err(out: &mut impl Write, id: Value, code: i64, message: &str) {
    let msg = json!({
        "jsonrpc": "2.0", "id": id,
        "error": { "code": code, "message": message }
    });
    let _ = writeln!(out, "{}", msg);
    let _ = out.flush();
}

fn tool_ok(out: &mut impl Write, id: Value, text: String) {
    respond(
        out,
        id,
        json!({
            "content": [{ "type": "text", "text": text }]
        }),
    );
}

fn tool_err(out: &mut impl Write, id: Value, text: String) {
    respond(
        out,
        id,
        json!({
            "content": [{ "type": "text", "text": text }],
            "isError": true
        }),
    );
}

// ── Tool schemas ─────────────────────────────────────────────────────────────

fn tools_list() -> Value {
    json!([
        {
            "name": "igniter_compile",
            "description": "Compile Igniter (.ig) source code and return OOF diagnostics. Does NOT load into the machine. Use this to check a contract for errors before loading.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "source_code": { "type": "string", "description": "The .ig source code to compile" },
                    "contract_name": { "type": "string", "description": "Name for the contract (used as identifier)" }
                },
                "required": ["source_code", "contract_name"]
            }
        },
        {
            "name": "igniter_load_contract",
            "description": "Compile and load an Igniter contract into the machine registry. After loading, it can be dispatched. Returns fragment class and any compilation errors.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "source_code": { "type": "string", "description": "The .ig source code" },
                    "contract_name": { "type": "string", "description": "Contract identifier" }
                },
                "required": ["source_code", "contract_name"]
            }
        },
        {
            "name": "igniter_dispatch",
            "description": "Execute a loaded Igniter contract with given inputs. Returns the contract output and all observations emitted during execution.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "contract_name": { "type": "string", "description": "Name of the loaded contract to execute" },
                    "inputs": { "type": "object", "description": "Input values matching the contract's input declarations" }
                },
                "required": ["contract_name"]
            }
        },
        {
            "name": "igniter_list_contracts",
            "description": "List all contracts currently loaded in the Igniter Machine registry with their fragment classes (core/escape/temporal/oof).",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        },
        {
            "name": "igniter_get_contract_ir",
            "description": "Get the full Semantic IR (intermediate representation) of a loaded contract as JSON. Shows nodes, types, fragment classes, dependencies.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "contract_name": { "type": "string", "description": "Name of the loaded contract" }
                },
                "required": ["contract_name"]
            }
        },
        {
            "name": "igniter_write_fact",
            "description": "Write a bitemporal fact to the TBackend store. Optionally provide valid_time for backdating (assertion about when something was logically true).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "store": { "type": "string", "description": "Store partition name (e.g. 'leads', 'vendors', 'bids')" },
                    "key":   { "type": "string", "description": "Entity key within the store" },
                    "value": { "type": "object", "description": "Fact payload as JSON object" },
                    "valid_time": { "type": "number", "description": "Optional Unix timestamp for valid-time backdating" },
                    "causation": { "type": "string", "description": "Optional UUID of the fact this causally follows" }
                },
                "required": ["store", "key", "value"]
            }
        },
        {
            "name": "igniter_query_facts",
            "description": "Query facts from TBackend. If key is provided, returns the fact active as_of a given time (time-travel). Without as_of, returns current state.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "store": { "type": "string", "description": "Store partition name" },
                    "key":   { "type": "string", "description": "Entity key (leave empty for all keys)" },
                    "as_of": { "type": "number", "description": "Unix timestamp for time-travel query (optional, defaults to now)" }
                },
                "required": ["store"]
            }
        },
        {
            "name": "igniter_time_travel",
            "description": "Reconstruct the exact state of an entity at a specific moment in the past. Returns what the system knew about store/key at transaction_time=as_of.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "store": { "type": "string" },
                    "key":   { "type": "string" },
                    "as_of": { "type": "number", "description": "Unix timestamp to travel to" }
                },
                "required": ["store", "key", "as_of"]
            }
        },
        {
            "name": "igniter_checkpoint",
            "description": "Save the complete machine state (contracts + facts + observations) to a .igm image file. Can be restored later with resume.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "File path for the .igm image (e.g. './state.igm')" }
                },
                "required": ["path"]
            }
        },
        {
            "name": "igniter_status",
            "description": "Get current machine status: backend type, number of loaded contracts, observations count.",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        }
    ])
}

// ── Tool handlers ─────────────────────────────────────────────────────────────

fn handle_compile(out: &mut impl Write, id: Value, args: &Value) {
    let source = match args["source_code"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing source_code".into()),
    };
    let name = args["contract_name"].as_str().unwrap_or("Contract");

    let diags = IgniterMachine::check_source(source);

    let errors: Vec<_> = diags.iter().filter(|d| d.2 == "error").collect();
    let warnings: Vec<_> = diags.iter().filter(|d| d.2 == "warning").collect();

    let mut lines = vec![
        format!("## Compilation: `{}`\n", name),
        format!(
            "**{}** error(s), **{}** warning(s)\n",
            errors.len(),
            warnings.len()
        ),
    ];

    if diags.is_empty() {
        lines.push("✅ No issues found.".into());
    } else {
        for (rule, msg, sev, line, col) in &diags {
            let loc = match (line, col) {
                (Some(l), Some(c)) => format!(" (line {}, col {})", l, c),
                (Some(l), None) => format!(" (line {})", l),
                _ => String::new(),
            };
            let icon = if sev == "error" { "🔴" } else { "🟡" };
            lines.push(format!("{} **{}**{}: {}", icon, rule, loc, msg));
        }
    }

    tool_ok(out, id, lines.join("\n"));
}

fn handle_load_contract(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
) {
    let source = match args["source_code"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing source_code".into()),
    };
    let name = args["contract_name"].as_str().unwrap_or("Contract");

    let m = machine.lock().unwrap();
    match m.load_contract_source(source, name) {
        Ok(()) => {
            // Get fragment class from registry
            let frag = m
                .registry
                .read()
                .get(name)
                .and_then(|v| v.get("fragment_class").or_else(|| v.get("modifier")))
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string();

            let icon = match frag.as_str() {
                "core" => "🟢",
                "escape" => "🟡",
                "temporal" => "🔵",
                "oof" => "🔴",
                _ => "⚪",
            };

            tool_ok(out, id, format!(
                "## Contract Loaded: `{}`\n\n{} Fragment class: **{}**\n\n✅ Contract is ready. Use `igniter_dispatch` to execute it.",
                name, icon, frag
            ));
        }
        Err(e) => tool_err(
            out,
            id,
            format!(
            "## Compilation Failed: `{}`\n\n```\n{}\n```\n\nFix the errors above and try again.",
            name, e
        ),
        ),
    }
}

fn handle_dispatch(out: &mut impl Write, id: Value, args: &Value, machine: &Mutex<IgniterMachine>) {
    let name = match args["contract_name"].as_str() {
        Some(n) => n,
        None => return tool_err(out, id, "Missing contract_name".into()),
    };
    let inputs = if args["inputs"].is_null() {
        json!({})
    } else {
        args["inputs"].clone()
    };

    let m = machine.lock().unwrap();
    match futures::executor::block_on(m.dispatch(name, inputs.clone())) {
        Ok(result) => {
            let obs = m.observations.read();
            let recent: Vec<_> = obs.iter().rev().take(5).collect();

            let mut lines = vec![
                format!("## Dispatch: `{}`\n", name),
                format!("**Inputs:** `{}`\n", inputs),
                "### Result\n".into(),
                format!(
                    "```json\n{}\n```",
                    serde_json::to_string_pretty(&result).unwrap_or_default()
                ),
            ];

            if !recent.is_empty() {
                lines.push("\n### Observations".into());
                for obs in recent.iter().rev() {
                    lines.push(format!("- **{}**: `{}`", obs.kind, obs.value));
                }
            }

            tool_ok(out, id, lines.join("\n"));
        }
        Err(e) => tool_err(
            out,
            id,
            format!("## Dispatch Failed: `{}`\n\n```\n{}\n```", name, e),
        ),
    }
}

fn handle_list_contracts(out: &mut impl Write, id: Value, machine: &Mutex<IgniterMachine>) {
    let m = machine.lock().unwrap();
    let reg = m.registry.read();
    let contracts: Vec<(String, String)> = reg
        .all()
        .map(|(name, val)| {
            let frag = val
                .get("fragment_class")
                .or_else(|| val.get("modifier"))
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string();
            (name.clone(), frag)
        })
        .collect();

    if contracts.is_empty() {
        return tool_ok(out, id,
            "## Loaded Contracts\n\nNo contracts loaded yet. Use `igniter_load_contract` to load one.".into());
    }

    let mut lines = vec![format!("## Loaded Contracts ({})\n", contracts.len())];
    for (name, frag) in &contracts {
        let icon = match frag.as_str() {
            "core" => "🟢",
            "escape" => "🟡",
            "temporal" => "🔵",
            "oof" => "🔴",
            _ => "⚪",
        };
        lines.push(format!("{} **{}** — `{}`", icon, name, frag));
    }
    tool_ok(out, id, lines.join("\n"));
}

fn handle_get_contract_ir(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
) {
    let name = match args["contract_name"].as_str() {
        Some(n) => n,
        None => return tool_err(out, id, "Missing contract_name".into()),
    };
    let m = machine.lock().unwrap();
    let reg = m.registry.read();
    match reg.get(name) {
        Some(ir) => tool_ok(
            out,
            id,
            format!(
                "## Semantic IR: `{}`\n\n```json\n{}\n```",
                name,
                serde_json::to_string_pretty(ir).unwrap_or_default()
            ),
        ),
        None => tool_err(
            out,
            id,
            format!("Contract '{}' not found in registry.", name),
        ),
    }
}

fn handle_write_fact(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
) {
    let store = match args["store"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing store".into()),
    };
    let key = match args["key"].as_str() {
        Some(k) => k,
        None => return tool_err(out, id, "Missing key".into()),
    };
    let value = match args.get("value") {
        Some(v) => v.clone(),
        None => return tool_err(out, id, "Missing value".into()),
    };

    let fact_id = uuid::Uuid::new_v4().to_string();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs_f64();
    let val_str = serde_json::to_string(&value).unwrap_or_default();
    let val_hash = blake3::hash(val_str.as_bytes()).to_hex().to_string();

    let fact = Fact {
        id: fact_id.clone(),
        store: store.to_string(),
        key: key.to_string(),
        value,
        value_hash: val_hash,
        causation: args["causation"].as_str().map(|s| s.to_string()),
        transaction_time: now,
        valid_time: args["valid_time"].as_f64(),
        schema_version: 1,
        producer: Some(json!("igniter-mcp")),
        derivation: None,
    };

    let m = machine.lock().unwrap();
    match futures::executor::block_on(m.write_fact(fact)) {
        Ok(()) => {
            let vt_note = if args["valid_time"].is_number() {
                format!(" (backdated valid_time: {})", args["valid_time"])
            } else {
                String::new()
            };
            tool_ok(out, id, format!(
                "## Fact Written ✅\n\n- **Store:** `{}`\n- **Key:** `{}`\n- **ID:** `{}`\n- **tx_time:** `{:.0}`{}\n\nUse `igniter_query_facts` to retrieve it.",
                store, key, &fact_id[..8], now, vt_note
            ));
        }
        Err(e) => tool_err(out, id, format!("Failed to write fact: {}", e)),
    }
}

fn handle_query_facts(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
) {
    let store = match args["store"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing store".into()),
    };
    let key = args["key"].as_str().unwrap_or("global");
    let as_of = args["as_of"].as_f64().unwrap_or_else(|| {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs_f64()
    });

    let m = machine.lock().unwrap();
    match futures::executor::block_on(m.storage.facts_for(store, key, None, Some(as_of))) {
        Ok(facts) => {
            if facts.is_empty() {
                return tool_ok(out, id, format!(
                    "## Facts: `{}/{}`\n\nNo facts found. Use `igniter_write_fact` to add data.", store, key));
            }
            let mut lines = vec![format!(
                "## Facts: `{}/{}` ({} total)\n",
                store,
                key,
                facts.len()
            )];
            for f in facts.iter().rev().take(10) {
                let vt = f
                    .valid_time
                    .map(|v| format!("valid: {:.0} | ", v))
                    .unwrap_or_default();
                lines.push(format!(
                    "- `{}` tx: {:.0} | {}value: `{}`",
                    &f.id[..8],
                    f.transaction_time,
                    vt,
                    f.value
                ));
            }
            if facts.len() > 10 {
                lines.push(format!("\n_… {} more facts not shown_", facts.len() - 10));
            }
            tool_ok(out, id, lines.join("\n"));
        }
        Err(e) => tool_err(out, id, format!("Query failed: {}", e)),
    }
}

fn handle_time_travel(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
) {
    let store = match args["store"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing store".into()),
    };
    let key = match args["key"].as_str() {
        Some(k) => k,
        None => return tool_err(out, id, "Missing key".into()),
    };
    let as_of = match args["as_of"].as_f64() {
        Some(t) => t,
        None => return tool_err(out, id, "Missing as_of timestamp".into()),
    };

    let dt = chrono::DateTime::from_timestamp(as_of as i64, 0)
        .map(|d| d.format("%Y-%m-%d %H:%M:%S UTC").to_string())
        .unwrap_or_else(|| format!("{:.0}", as_of));

    let m = machine.lock().unwrap();
    match futures::executor::block_on(m.read_fact(store, key, as_of)) {
        Ok(Some(fact)) => {
            let vt = fact.valid_time.map(|v| format!("\n- **Valid time:** `{:.0}`", v)).unwrap_or_default();
            tool_ok(out, id, format!(
                "## Time Travel: `{}/{}` @ `{}`\n\n- **Fact ID:** `{}`\n- **tx_time:** `{:.0}`{}\n\n### Value\n```json\n{}\n```",
                store, key, dt,
                &fact.id[..8], fact.transaction_time, vt,
                serde_json::to_string_pretty(&fact.value).unwrap_or_default()
            ));
        }
        Ok(None) => tool_ok(out, id, format!(
            "## Time Travel: `{}/{}` @ `{}`\n\nNo fact found at this timestamp. The entity either didn't exist yet or has no record before this point.",
            store, key, dt
        )),
        Err(e) => tool_err(out, id, format!("Time travel query failed: {}", e)),
    }
}

fn handle_checkpoint(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
) {
    let path = match args["path"].as_str() {
        Some(p) => std::path::Path::new(p),
        None => return tool_err(out, id, "Missing path".into()),
    };
    let m = machine.lock().unwrap();
    match m.checkpoint(path) {
        Ok(()) => tool_ok(out, id, format!(
            "## Checkpoint Saved ✅\n\n**Path:** `{}`\n\nMachine state (contracts + facts + observations) has been saved. Use `igniter-mcp --resume {}` to restore.",
            path.display(), path.display()
        )),
        Err(e) => tool_err(out, id, format!("Checkpoint failed: {}", e)),
    }
}

fn handle_status(out: &mut impl Write, id: Value, machine: &Mutex<IgniterMachine>) {
    let m = machine.lock().unwrap();
    let contract_count = m.registry.read().len();
    let obs_count = m.observations.read().len();
    let backend_type = m.backend_type();

    tool_ok(out, id, format!(
        "## Igniter Machine Status\n\n- **Backend:** `{}`\n- **Contracts loaded:** {}\n- **Observations:** {}\n\n### Available Tools\nUse `igniter_load_contract` to load a contract, `igniter_dispatch` to run it, `igniter_write_fact` / `igniter_query_facts` for bitemporal data.",
        backend_type, contract_count, obs_count
    ));
}

// ── Main ─────────────────────────────────────────────────────────────────────

fn main() {
    // Parse --resume flag
    let args: Vec<String> = std::env::args().collect();
    let resume_path = args
        .windows(2)
        .find(|w| w[0] == "--resume")
        .map(|w| std::path::PathBuf::from(&w[1]));

    // Parse --backend flag
    let backend = args
        .windows(2)
        .find(|w| w[0] == "--backend")
        .map(|w| w[1].clone())
        .unwrap_or_else(|| "in_memory".to_string());

    let machine = if let Some(ref path) = resume_path {
        eprintln!("[igniter-mcp] Resuming from: {}", path.display());
        match IgniterMachine::resume(path, None, &backend) {
            Ok(m) => m,
            Err(e) => {
                eprintln!("[igniter-mcp] Resume failed: {}. Starting fresh.", e);
                IgniterMachine::new(None, &backend).expect("Failed to create machine")
            }
        }
    } else {
        IgniterMachine::new(None, &backend).expect("Failed to create machine")
    };

    let machine = Mutex::new(machine);
    let mut stdout = std::io::stdout();
    let stdin = std::io::stdin();
    let reader = BufReader::new(stdin.lock());

    eprintln!(
        "[igniter-mcp] MCP server ready. Backend: {}. Listening on stdio.",
        backend
    );

    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let request: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(e) => {
                respond_err(
                    &mut stdout,
                    Value::Null,
                    -32700,
                    &format!("Parse error: {}", e),
                );
                continue;
            }
        };

        let id = request["id"].clone();
        let method = request["method"].as_str().unwrap_or("");
        let params = &request["params"];
        let args = params.get("arguments").unwrap_or(&Value::Null);

        match method {
            "initialize" => respond(
                &mut stdout,
                id,
                json!({
                    "protocolVersion": "2024-11-05",
                    "capabilities": { "tools": {} },
                    "serverInfo": {
                        "name": "igniter-machine",
                        "version": "0.1.0"
                    }
                }),
            ),

            "notifications/initialized" => { /* no response */ }

            "ping" => respond(&mut stdout, id, json!({})),

            "tools/list" => respond(&mut stdout, id, json!({ "tools": tools_list() })),

            "tools/call" => {
                let tool = params.get("name").and_then(|v| v.as_str()).unwrap_or("");
                match tool {
                    "igniter_compile" => handle_compile(&mut stdout, id, args),
                    "igniter_load_contract" => {
                        handle_load_contract(&mut stdout, id, args, &machine)
                    }
                    "igniter_dispatch" => handle_dispatch(&mut stdout, id, args, &machine),
                    "igniter_list_contracts" => handle_list_contracts(&mut stdout, id, &machine),
                    "igniter_get_contract_ir" => {
                        handle_get_contract_ir(&mut stdout, id, args, &machine)
                    }
                    "igniter_write_fact" => handle_write_fact(&mut stdout, id, args, &machine),
                    "igniter_query_facts" => handle_query_facts(&mut stdout, id, args, &machine),
                    "igniter_time_travel" => handle_time_travel(&mut stdout, id, args, &machine),
                    "igniter_checkpoint" => handle_checkpoint(&mut stdout, id, args, &machine),
                    "igniter_status" => handle_status(&mut stdout, id, &machine),
                    _ => tool_err(&mut stdout, id, format!("Unknown tool: `{}`", tool)),
                }
            }

            _ => respond_err(
                &mut stdout,
                id,
                -32601,
                &format!("Method not found: {}", method),
            ),
        }
    }

    eprintln!("[igniter-mcp] EOF. Shutting down.");
}
