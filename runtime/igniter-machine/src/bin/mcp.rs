// src/bin/mcp.rs
// Igniter Machine MCP Server — JSON-RPC 2.0 over stdio
//
// Register in Claude Desktop:
//   ~/Library/Application Support/Claude/claude_desktop_config.json
//   { "mcpServers": { "igniter": { "command": "/path/to/igniter-mcp" } } }

use igniter_machine::capability::RECEIPTS_STORE;
use igniter_machine::capsule::CapsuleManager;
use igniter_machine::coordination::{
    COORD_AUDIT_STORE, INGRESS_DEDUP_STORE, MESSENGER_STORE, RECIPES_STORE, TRANSFERS_STORE,
};
use igniter_machine::fact::Fact;
use igniter_machine::machine::IgniterMachine;
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::Mutex;

// ── Helpers ──────────────────────────────────────────────────────────────────

const MCP_AUTH_TOKEN_ENV: &str = "IGNITER_MCP_AUTH_TOKEN";
const MCP_CHECKPOINT_ROOT_ENV: &str = "IGNITER_MCP_CHECKPOINT_ROOT";
const MCP_AUTH_REFUSED: &str = "MCP authority refused: missing or invalid local authority";

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

fn token_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    let mut diff = a.len() ^ b.len();
    for i in 0..a.len().max(b.len()) {
        let av = *a.get(i).unwrap_or(&0);
        let bv = *b.get(i).unwrap_or(&0);
        diff |= (av ^ bv) as usize;
    }
    diff == 0
}

fn authorize_tool_call(args: &Value) -> Result<(), String> {
    let expected = std::env::var(MCP_AUTH_TOKEN_ENV)
        .ok()
        .filter(|token| !token.is_empty())
        .ok_or_else(|| MCP_AUTH_REFUSED.to_string())?;
    let presented = args
        .get("authority_token")
        .and_then(Value::as_str)
        .filter(|token| !token.is_empty())
        .ok_or_else(|| MCP_AUTH_REFUSED.to_string())?;

    if token_eq(&expected, presented) {
        Ok(())
    } else {
        Err(MCP_AUTH_REFUSED.to_string())
    }
}

fn add_authority_token_schema(mut tools: Value) -> Value {
    let Some(items) = tools.as_array_mut() else {
        return tools;
    };
    for tool in items {
        let Some(schema) = tool.get_mut("inputSchema") else {
            continue;
        };
        if let Some(props) = schema.get_mut("properties").and_then(Value::as_object_mut) {
            props.insert(
                "authority_token".to_string(),
                json!({
                    "type": "string",
                    "description": "Process-local MCP authority token from IGNITER_MCP_AUTH_TOKEN"
                }),
            );
        }
        match schema.get_mut("required") {
            Some(Value::Array(required)) => {
                if !required
                    .iter()
                    .any(|item| item.as_str() == Some("authority_token"))
                {
                    required.push(json!("authority_token"));
                }
            }
            _ => {
                schema["required"] = json!(["authority_token"]);
            }
        }
    }
    tools
}

fn mcp_checkpoint_root() -> Result<PathBuf, String> {
    let root = match std::env::var(MCP_CHECKPOINT_ROOT_ENV) {
        Ok(raw) if !raw.trim().is_empty() => PathBuf::from(raw),
        _ => PathBuf::from(".igniter-mcp").join("checkpoints"),
    };

    std::fs::create_dir_all(&root).map_err(|e| format!("Checkpoint root unavailable: {}", e))?;
    root.canonicalize()
        .map_err(|e| format!("Checkpoint root unavailable: {}", e))
}

fn normalize_lexical(path: &Path) -> Result<PathBuf, String> {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(_) => {
                return Err("Checkpoint path refused: unsupported path prefix".to_string());
            }
            Component::RootDir => normalized.push(Path::new("/")),
            Component::CurDir => {}
            Component::ParentDir => {
                if !normalized.pop() {
                    return Err("Checkpoint path refused: path escapes checkpoint root".to_string());
                }
            }
            Component::Normal(part) => normalized.push(part),
        }
    }
    Ok(normalized)
}

fn resolve_checkpoint_path(raw: &str) -> Result<PathBuf, String> {
    if raw.trim().is_empty() {
        return Err("Checkpoint path refused: missing path".to_string());
    }

    let root = mcp_checkpoint_root()?;
    let requested = Path::new(raw);
    let candidate = if requested.is_absolute() {
        requested.to_path_buf()
    } else {
        root.join(requested)
    };
    let resolved = normalize_lexical(&candidate)?;

    if !resolved.starts_with(&root) || resolved == root {
        return Err("Checkpoint path refused: outside MCP checkpoint root".to_string());
    }
    if resolved
        .symlink_metadata()
        .map(|meta| meta.file_type().is_symlink())
        .unwrap_or(false)
    {
        return Err("Checkpoint path refused: checkpoint target is a symlink".to_string());
    }

    let Some(parent) = resolved.parent() else {
        return Err("Checkpoint path refused: missing parent directory".to_string());
    };
    if !parent.starts_with(&root) {
        return Err("Checkpoint path refused: outside MCP checkpoint root".to_string());
    }
    std::fs::create_dir_all(parent)
        .map_err(|e| format!("Checkpoint path refused: cannot create parent: {}", e))?;
    let parent = parent
        .canonicalize()
        .map_err(|e| format!("Checkpoint path refused: cannot verify parent: {}", e))?;
    if !parent.starts_with(&root) {
        return Err("Checkpoint path refused: outside MCP checkpoint root".to_string());
    }

    Ok(resolved)
}

fn is_reserved_store(store: &str) -> bool {
    const RESERVED_STORES: &[&str] = &[
        RECEIPTS_STORE,
        COORD_AUDIT_STORE,
        MESSENGER_STORE,
        TRANSFERS_STORE,
        RECIPES_STORE,
        INGRESS_DEDUP_STORE,
    ];

    store.starts_with("__") || RESERVED_STORES.contains(&store)
}

// ── Tool schemas ─────────────────────────────────────────────────────────────

fn tools_list() -> Value {
    add_authority_token_schema(json!([
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
            "description": "Reconstruct an entity's state. `as_of` = known_at (audit/transaction-time): what we knew as of T. Optional `valid_at` = effective/valid-time: the state true as of that domain time, as best known by `as_of`. Both axes are explicit; facts without a valid_time are excluded from valid_at queries.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "store": { "type": "string" },
                    "key":   { "type": "string" },
                    "as_of": { "type": "number", "description": "known_at: transaction-time to travel to (what we knew at T)" },
                    "valid_at": { "type": "number", "description": "Optional valid-time: the domain time the state was true at (effective axis)" }
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
        },
        {
            "name": "capsule_snapshot",
            "description": "Freeze the current machine state (contracts + facts + observations) into a named, immutable capsule frame. Build many and cycle them like a filmstrip.",
            "inputSchema": {
                "type": "object",
                "properties": { "name": { "type": "string", "description": "Capsule name" } },
                "required": ["name"]
            }
        },
        {
            "name": "capsule_list",
            "description": "List all capsule frames currently held.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "capsule_activate",
            "description": "Activation: dispatch a contract against a capsule's frame (read-only — the frame is not mutated). Returns the result for that frame.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "name": { "type": "string", "description": "Capsule to activate" },
                    "contract_name": { "type": "string", "description": "Contract to dispatch" },
                    "inputs": { "type": "object", "description": "Dispatch inputs" }
                },
                "required": ["name", "contract_name"]
            }
        },
        {
            "name": "capsule_fork",
            "description": "Branch a NEW immutable capsule from an existing one, optionally writing extra facts into the fork (a what-if). The source frame is untouched.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "from": { "type": "string", "description": "Source capsule" },
                    "new_name": { "type": "string", "description": "Name of the forked capsule" },
                    "facts": { "type": "array", "description": "Optional facts to write into the fork: [{store,key,value,valid_time?}]" }
                },
                "required": ["from", "new_name"]
            }
        },
        {
            "name": "capsule_diff",
            "description": "Diff two capsule frames by their facts: what was added/removed between A and B (the debugger lens).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "a": { "type": "string" },
                    "b": { "type": "string" }
                },
                "required": ["a", "b"]
            }
        },
        {
            "name": "capsule_activate_many",
            "description": "Filmstrip: run ONE activation (a dispatch) across many capsule frames at once and return a result table [{capsule, output|error}]. Divergent frames give divergent outputs. Set parallel=true to run them concurrently.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "capsules": { "type": "array", "description": "Capsule names (omit = all capsules)" },
                    "contract_name": { "type": "string", "description": "Contract to dispatch in each frame" },
                    "inputs": { "type": "object", "description": "Dispatch inputs (same for every frame)" },
                    "parallel": { "type": "boolean", "description": "Run frames concurrently (default false)" }
                },
                "required": ["contract_name"]
            }
        }
    ]))
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

            tool_ok(
                out,
                id,
                format!(
                    "## Contract Loaded: `{}`\n\n{} Fragment class: **{}**\n\n✅ Contract is ready. Use `igniter_dispatch` to execute it.",
                    name, icon, frag
                ),
            );
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
    if is_reserved_store(store) {
        return tool_err(
            out,
            id,
            format!(
                "Reserved store writes are refused through igniter_write_fact: `{}`",
                store
            ),
        );
    }
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
            tool_ok(
                out,
                id,
                format!(
                    "## Fact Written ✅\n\n- **Store:** `{}`\n- **Key:** `{}`\n- **ID:** `{}`\n- **tx_time:** `{:.0}`{}\n\nUse `igniter_query_facts` to retrieve it.",
                    store,
                    key,
                    &fact_id[..8],
                    now,
                    vt_note
                ),
            );
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
                return tool_ok(
                    out,
                    id,
                    format!(
                        "## Facts: `{}/{}`\n\nNo facts found. Use `igniter_write_fact` to add data.",
                        store, key
                    ),
                );
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
    // `as_of` is the audit axis (known_at / transaction_time). Optional `valid_at` adds
    // the effective axis → full bitemporal query (LAB-MACHINE-BITEMPORAL-AXIS-P1).
    let result = match args["valid_at"].as_f64() {
        Some(va) => {
            futures::executor::block_on(m.read_bitemporal(store, key, Some(va), Some(as_of)))
        }
        None => futures::executor::block_on(m.read_fact(store, key, as_of)),
    };
    match result {
        Ok(Some(fact)) => {
            let vt = fact
                .valid_time
                .map(|v| format!("\n- **Valid time:** `{:.0}`", v))
                .unwrap_or_default();
            tool_ok(
                out,
                id,
                format!(
                    "## Time Travel: `{}/{}` @ `{}`\n\n- **Fact ID:** `{}`\n- **tx_time:** `{:.0}`{}\n\n### Value\n```json\n{}\n```",
                    store,
                    key,
                    dt,
                    &fact.id[..8],
                    fact.transaction_time,
                    vt,
                    serde_json::to_string_pretty(&fact.value).unwrap_or_default()
                ),
            );
        }
        Ok(None) => tool_ok(
            out,
            id,
            format!(
                "## Time Travel: `{}/{}` @ `{}`\n\nNo fact found at this timestamp. The entity either didn't exist yet or has no record before this point.",
                store, key, dt
            ),
        ),
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
        Some(p) => match resolve_checkpoint_path(p) {
            Ok(path) => path,
            Err(e) => return tool_err(out, id, e),
        },
        None => return tool_err(out, id, "Missing path".into()),
    };
    let m = machine.lock().unwrap();
    match futures::executor::block_on(m.checkpoint(&path)) {
        Ok(()) => tool_ok(
            out,
            id,
            format!(
                "## Checkpoint Saved ✅\n\n**Path:** `{}`\n\nMachine state (contracts + facts + observations) has been saved. Use `igniter-mcp --resume {}` to restore.",
                path.display(),
                path.display()
            ),
        ),
        Err(e) => tool_err(out, id, format!("Checkpoint failed: {}", e)),
    }
}

fn handle_status(out: &mut impl Write, id: Value, machine: &Mutex<IgniterMachine>) {
    let m = machine.lock().unwrap();
    let contract_count = m.registry.read().len();
    let obs_count = m.observations.read().len();
    let backend_type = m.backend_type();

    tool_ok(
        out,
        id,
        format!(
            "## Igniter Machine Status\n\n- **Backend:** `{}`\n- **Contracts loaded:** {}\n- **Observations:** {}\n\n### Available Tools\nUse `igniter_load_contract` to load a contract, `igniter_dispatch` to run it, `igniter_write_fact` / `igniter_query_facts` for bitemporal data.",
            backend_type, contract_count, obs_count
        ),
    );
}

// ── Capsule tools (LAB-MACHINE-CAPSULE-MANAGER-P1) ────────────────────────────

fn handle_capsule_snapshot(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
    capsules: &Mutex<CapsuleManager>,
) {
    let name = match args["name"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing name".into()),
    };
    let m = machine.lock().unwrap();
    let mut caps = capsules.lock().unwrap();
    match futures::executor::block_on(caps.snapshot(name, &m)) {
        Ok(()) => tool_ok(
            out,
            id,
            format!(
                "## Capsule snapshot ✅\n\n- **Name:** `{}`\n\nFrame frozen (immutable). Use `capsule_fork` for what-ifs, `capsule_activate` to run it, `capsule_diff` to compare.",
                name
            ),
        ),
        Err(e) => tool_err(out, id, format!("Snapshot failed: {}", e)),
    }
}

fn handle_capsule_list(out: &mut impl Write, id: Value, capsules: &Mutex<CapsuleManager>) {
    let caps = capsules.lock().unwrap();
    let names = caps.list();
    if names.is_empty() {
        return tool_ok(
            out,
            id,
            "## Capsules\n\nNone yet. Use `capsule_snapshot` to freeze the current state.".into(),
        );
    }
    let body = names
        .iter()
        .map(|n| format!("- `{}`", n))
        .collect::<Vec<_>>()
        .join("\n");
    tool_ok(
        out,
        id,
        format!("## Capsules ({})\n\n{}", names.len(), body),
    );
}

fn handle_capsule_activate(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    capsules: &Mutex<CapsuleManager>,
) {
    let name = match args["name"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing name".into()),
    };
    let contract = match args["contract_name"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing contract_name".into()),
    };
    let inputs = args.get("inputs").cloned().unwrap_or_else(|| json!({}));
    let caps = capsules.lock().unwrap();
    match futures::executor::block_on(caps.activate(name, contract, inputs.clone())) {
        Ok(result) => tool_ok(
            out,
            id,
            format!(
                "## Activate: `{}` @ capsule `{}`\n\n**Inputs:** `{}`\n\n### Result\n```json\n{}\n```",
                contract,
                name,
                inputs,
                serde_json::to_string_pretty(&result).unwrap_or_default()
            ),
        ),
        Err(e) => tool_err(out, id, format!("Activation failed: {}", e)),
    }
}

fn handle_capsule_fork(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    capsules: &Mutex<CapsuleManager>,
) {
    let from = match args["from"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing from".into()),
    };
    let new_name = match args["new_name"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing new_name".into()),
    };
    let mut facts: Vec<Fact> = Vec::new();
    if let Some(arr) = args["facts"].as_array() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs_f64();
        for f in arr {
            if let (Some(s), Some(k), Some(v)) =
                (f["store"].as_str(), f["key"].as_str(), f.get("value"))
            {
                let val_str = serde_json::to_string(v).unwrap_or_default();
                facts.push(Fact {
                    id: uuid::Uuid::new_v4().to_string(),
                    store: s.to_string(),
                    key: k.to_string(),
                    value: v.clone(),
                    value_hash: blake3::hash(val_str.as_bytes()).to_hex().to_string(),
                    causation: None,
                    transaction_time: now,
                    valid_time: f["valid_time"].as_f64(),
                    schema_version: 1,
                    producer: Some(json!("igniter-mcp")),
                    derivation: None,
                });
            }
        }
    }
    let mut caps = capsules.lock().unwrap();
    match futures::executor::block_on(caps.fork(from, new_name, &facts)) {
        Ok(()) => tool_ok(
            out,
            id,
            format!(
                "## Capsule fork ✅\n\n- **From:** `{}` (untouched)\n- **New:** `{}`\n- **Patched facts:** {}\n\nA new immutable frame.",
                from,
                new_name,
                facts.len()
            ),
        ),
        Err(e) => tool_err(out, id, format!("Fork failed: {}", e)),
    }
}

fn handle_capsule_diff(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    capsules: &Mutex<CapsuleManager>,
) {
    let a = match args["a"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing a".into()),
    };
    let b = match args["b"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing b".into()),
    };
    let caps = capsules.lock().unwrap();
    match futures::executor::block_on(caps.diff(a, b)) {
        Ok(d) => tool_ok(
            out,
            id,
            format!(
                "## Capsule diff: `{}` → `{}`\n\n```json\n{}\n```",
                a,
                b,
                serde_json::to_string_pretty(&d).unwrap_or_default()
            ),
        ),
        Err(e) => tool_err(out, id, format!("Diff failed: {}", e)),
    }
}

fn handle_capsule_activate_many(
    out: &mut impl Write,
    id: Value,
    args: &Value,
    capsules: &Mutex<CapsuleManager>,
) {
    let contract = match args["contract_name"].as_str() {
        Some(s) => s,
        None => return tool_err(out, id, "Missing contract_name".into()),
    };
    let inputs = args.get("inputs").cloned().unwrap_or_else(|| json!({}));
    let parallel = args["parallel"].as_bool().unwrap_or(false);
    let caps = capsules.lock().unwrap();
    let names: Vec<String> = match args["capsules"].as_array() {
        Some(arr) => arr
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
        None => caps.list(),
    };
    if names.is_empty() {
        return tool_ok(out, id, "## Filmstrip\n\nNo capsules to activate.".into());
    }
    let table =
        futures::executor::block_on(caps.activate_many(&names, contract, inputs.clone(), parallel));
    let rows: Vec<String> = table
        .iter()
        .map(|r| {
            let cap = r["capsule"].as_str().unwrap_or("?");
            if let Some(o) = r.get("output") {
                format!(
                    "| `{}` | `{}` |",
                    cap,
                    serde_json::to_string(o).unwrap_or_default()
                )
            } else {
                format!(
                    "| `{}` | ⛔ {} |",
                    cap,
                    r["error"].as_str().unwrap_or("error")
                )
            }
        })
        .collect();
    tool_ok(
        out,
        id,
        format!(
            "## Filmstrip: `{}` over {} capsule(s){}\n\n**Inputs:** `{}`\n\n| capsule | output / error |\n|---|---|\n{}",
            contract,
            names.len(),
            if parallel { " (parallel)" } else { "" },
            inputs,
            rows.join("\n")
        ),
    );
}

fn dispatch_tool_call(
    out: &mut impl Write,
    id: Value,
    tool: &str,
    args: &Value,
    machine: &Mutex<IgniterMachine>,
    capsules: &Mutex<CapsuleManager>,
) {
    if let Err(message) = authorize_tool_call(args) {
        return tool_err(out, id, message);
    }

    match tool {
        "igniter_compile" => handle_compile(out, id, args),
        "igniter_load_contract" => handle_load_contract(out, id, args, machine),
        "igniter_dispatch" => handle_dispatch(out, id, args, machine),
        "igniter_list_contracts" => handle_list_contracts(out, id, machine),
        "igniter_get_contract_ir" => handle_get_contract_ir(out, id, args, machine),
        "igniter_write_fact" => handle_write_fact(out, id, args, machine),
        "igniter_query_facts" => handle_query_facts(out, id, args, machine),
        "igniter_time_travel" => handle_time_travel(out, id, args, machine),
        "igniter_checkpoint" => handle_checkpoint(out, id, args, machine),
        "igniter_status" => handle_status(out, id, machine),
        "capsule_snapshot" => handle_capsule_snapshot(out, id, args, machine, capsules),
        "capsule_list" => handle_capsule_list(out, id, capsules),
        "capsule_activate" => handle_capsule_activate(out, id, args, capsules),
        "capsule_fork" => handle_capsule_fork(out, id, args, capsules),
        "capsule_diff" => handle_capsule_diff(out, id, args, capsules),
        "capsule_activate_many" => handle_capsule_activate_many(out, id, args, capsules),
        _ => tool_err(out, id, format!("Unknown tool: `{}`", tool)),
    }
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
        match futures::executor::block_on(IgniterMachine::resume(path, None, &backend)) {
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
    let capsules = Mutex::new(CapsuleManager::new(&backend));
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
                dispatch_tool_call(&mut stdout, id, tool, args, &machine, &capsules);
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn temp_path(tag: &str) -> PathBuf {
        std::env::temp_dir().join(format!("igniter_mcp_p30_{}_{}", tag, uuid::Uuid::new_v4()))
    }

    fn parse_response(bytes: &[u8]) -> Value {
        serde_json::from_slice(bytes).expect("valid json-rpc response")
    }

    #[test]
    fn tools_call_requires_local_authority_and_allows_valid_token() {
        let _guard = ENV_LOCK.lock().unwrap();
        std::env::remove_var(MCP_AUTH_TOKEN_ENV);

        let machine = Mutex::new(IgniterMachine::new(None, "in_memory").unwrap());
        let capsules = Mutex::new(CapsuleManager::new("in_memory"));

        let mut unauthorized = Vec::new();
        dispatch_tool_call(
            &mut unauthorized,
            json!(1),
            "igniter_status",
            &json!({}),
            &machine,
            &capsules,
        );
        let response = parse_response(&unauthorized);
        assert_eq!(response["result"]["isError"].as_bool(), Some(true));
        assert!(
            response["result"]["content"][0]["text"]
                .as_str()
                .unwrap()
                .contains("authority refused")
        );

        std::env::set_var(MCP_AUTH_TOKEN_ENV, "p30-local-token");
        let mut authorized = Vec::new();
        dispatch_tool_call(
            &mut authorized,
            json!(2),
            "igniter_status",
            &json!({ "authority_token": "p30-local-token" }),
            &machine,
            &capsules,
        );
        let response = parse_response(&authorized);
        assert!(response["result"]["isError"].is_null());
        assert!(
            response["result"]["content"][0]["text"]
                .as_str()
                .unwrap()
                .contains("Igniter Machine Status")
        );

        std::env::remove_var(MCP_AUTH_TOKEN_ENV);
    }

    #[test]
    fn checkpoint_paths_are_confined_to_mcp_root() {
        let _guard = ENV_LOCK.lock().unwrap();
        let root = temp_path("root");
        std::fs::create_dir_all(&root).unwrap();
        std::env::set_var(MCP_CHECKPOINT_ROOT_ENV, &root);

        let safe = resolve_checkpoint_path("nested/state.igm").unwrap();
        assert!(safe.starts_with(root.canonicalize().unwrap()));
        assert!(safe.parent().unwrap().exists());

        assert!(resolve_checkpoint_path("../escape.igm").is_err());
        let outside = temp_path("outside").join("state.igm");
        assert!(resolve_checkpoint_path(outside.to_str().unwrap()).is_err());

        std::env::remove_var(MCP_CHECKPOINT_ROOT_ENV);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn public_write_edge_refuses_reserved_stores() {
        let machine = Mutex::new(IgniterMachine::new(None, "in_memory").unwrap());
        let mut out = Vec::new();
        handle_write_fact(
            &mut out,
            json!(1),
            &json!({
                "store": RECEIPTS_STORE,
                "key": "receipt-1",
                "value": { "status": "internal" }
            }),
            &machine,
        );

        let response = parse_response(&out);
        assert_eq!(response["result"]["isError"].as_bool(), Some(true));
        assert!(
            response["result"]["content"][0]["text"]
                .as_str()
                .unwrap()
                .contains("Reserved store writes are refused")
        );
        assert!(is_reserved_store("__messenger__"));
        assert!(!is_reserved_store("leads"));
    }

    #[test]
    fn tool_schemas_require_authority_token() {
        let tools = tools_list();
        for tool in tools.as_array().unwrap() {
            let required = tool["inputSchema"]["required"].as_array().unwrap();
            assert!(
                required
                    .iter()
                    .any(|item| item.as_str() == Some("authority_token"))
            );
            assert!(tool["inputSchema"]["properties"]["authority_token"].is_object());
        }
    }
}
