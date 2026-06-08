// src/main.rs
// High-performance, premium-class CLI for igniter-vm

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::Path;
use std::sync::Arc;
use serde_json::Value as JsonValue;

use igniter_vm::value::Value;
use igniter_vm::instructions::*;
use igniter_vm::compiler::Compiler;
use igniter_vm::tbackend::{TBackend, MemoryHistoryBackend, LedgerTcpBackend};
use igniter_vm::vm::VM;
use igniter_vm::pipeline::ProjectionPipeline;

// ANSI styling
const GREEN: &str  = "\x1b[32m";
const RED: &str    = "\x1b[31m";
const YELLOW: &str = "\x1b[33m";
const CYAN: &str   = "\x1b[36m";
const BOLD: &str   = "\x1b[1m";
const RESET: &str  = "\x1b[0m";

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 || args[1] == "--help" || args[1] == "-h" {
        print_help();
        return;
    }

    let json_mode = args.iter().any(|arg| arg == "--json" || arg == "-j");

    if !json_mode {
        println!("\n{}{}{}┌──────────────────────────────────────────────────────────────┐", BOLD, CYAN, RESET);
        println!("{}{}{}│             IGNITER VIRTUAL MACHINE (IVM) CLIENT             │", BOLD, CYAN, RESET);
        println!("{}{}{}└──────────────────────────────────────────────────────────────┘{}", BOLD, CYAN, RESET, RESET);
    }

    if args.len() >= 2 && args[1] == "reactive" {
        let mut contract_path = None;
        let mut trigger_store = None;
        let mut target_store = None;
        let mut tbackend_addr = None;
        let mut listener_port = 8089;

        let mut i = 2;
        while i < args.len() {
            match args[i].as_str() {
                "--contract" | "-c" => {
                    if i + 1 < args.len() {
                        contract_path = Some(args[i + 1].clone());
                        i += 2;
                    } else {
                        eprintln!("  {}Error: Missing value for --contract option{}", RED, RESET);
                        return;
                    }
                }
                "--trigger-store" => {
                    if i + 1 < args.len() {
                        trigger_store = Some(args[i + 1].clone());
                        i += 2;
                    } else {
                        eprintln!("  {}Error: Missing value for --trigger-store option{}", RED, RESET);
                        return;
                    }
                }
                "--target-store" => {
                    if i + 1 < args.len() {
                        target_store = Some(args[i + 1].clone());
                        i += 2;
                    } else {
                        eprintln!("  {}Error: Missing value for --target-store option{}", RED, RESET);
                        return;
                    }
                }
                "--tbackend" | "-b" => {
                    if i + 1 < args.len() {
                        tbackend_addr = Some(args[i + 1].clone());
                        i += 2;
                    } else {
                        eprintln!("  {}Error: Missing value for --tbackend option{}", RED, RESET);
                        return;
                    }
                }
                "--listener-port" | "-p" => {
                    if i + 1 < args.len() {
                        if let Ok(port) = args[i + 1].parse::<u16>() {
                            listener_port = port;
                        } else {
                            eprintln!("  {}Error: Invalid port number: {}{}", RED, args[i + 1], RESET);
                            return;
                        }
                        i += 2;
                    } else {
                        eprintln!("  {}Error: Missing value for --listener-port option{}", RED, RESET);
                        return;
                    }
                }
                other => {
                    eprintln!("  {}Error: Unknown argument '{}' for reactive mode{}", RED, other, RESET);
                    print_help();
                    return;
                }
            }
        }

        // Validate
        let contract_path = match contract_path {
            Some(p) => p,
            None => {
                eprintln!("  {}Error: --contract parameter is required for reactive mode{}", RED, RESET);
                return;
            }
        };
        let trigger_store = match trigger_store {
            Some(ts) => ts,
            None => {
                eprintln!("  {}Error: --trigger-store parameter is required for reactive mode{}", RED, RESET);
                return;
            }
        };
        let target_store = match target_store {
            Some(ts) => ts,
            None => {
                eprintln!("  {}Error: --target-store parameter is required for reactive mode{}", RED, RESET);
                return;
            }
        };
        let tbackend_addr = match tbackend_addr {
            Some(addr) => addr,
            None => {
                eprintln!("  {}Error: --tbackend parameter is required for reactive mode{}", RED, RESET);
                return;
            }
        };

        // Resolve contract JSON (supporting directory .igapp or file loading)
        let contract_filepath = if Path::new(&contract_path).is_dir() {
            let path_igapp = Path::new(&contract_path).join("semantic_ir_program.json");
            let path_manifest = Path::new(&contract_path).join("manifest.json");
            if path_igapp.exists() {
                path_igapp
            } else if path_manifest.exists() {
                path_manifest
            } else {
                eprintln!("  {}Error: Could not locate semantic_ir_program.json inside directory: {}{}", RED, contract_path, RESET);
                return;
            }
        } else {
            Path::new(&contract_path).to_path_buf()
        };

        println!("  {} [*] Loading Compiled Contract: {}{}", YELLOW, contract_filepath.display(), RESET);
        let contract_content = match fs::read_to_string(&contract_filepath) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("  {}Error: Failed to read contract file: {}{}", RED, e, RESET);
                return;
            }
        };

        let contract_json: JsonValue = match serde_json::from_str(&contract_content) {
            Ok(j) => j,
            Err(e) => {
                eprintln!("  {}Error: Failed to parse contract JSON: {}{}", RED, e, RESET);
                return;
            }
        };

        if let Err(e) = verify_load_capabilities(&contract_path, &contract_json) {
            eprintln!("  {}Error: {}{}", RED, e, RESET);
            return;
        }

        // Boot Projection Pipeline
        println!("  {} [*] Booting Reactive Projection Pipeline Orchestrator...{}", YELLOW, RESET);
        let pipeline = Arc::new(ProjectionPipeline::new(
            contract_json,
            &tbackend_addr,
            listener_port,
            &trigger_store,
            &target_store,
        ));

        // Start pipeline
        let pipeline_clone = pipeline.clone();
        if let Err(e) = pipeline_clone.start(HashMap::new()).await {
            eprintln!("  {}Pipeline Error: {}{}", RED, e, RESET);
            std::process::exit(1);
        }

        // Register shutdown hook (Ctrl-C trapping)
        println!("  {} [*] Webhook listener is running. Press Ctrl-C to shutdown gracefully...{}", YELLOW, RESET);
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                println!("\n  {} [*] Shutting down reactive pipeline...{}", YELLOW, RESET);
                if let Err(e) = pipeline.shutdown().await {
                    eprintln!("  {}Shutdown cleanup failed: {}{}", RED, e, RESET);
                }
                println!("  {}✔ Done. Bye!{}", GREEN, RESET);
            }
        }
        return;
    }

    let mut contract_path = None;
    let mut inputs_path = None;
    let mut as_of = None;
    let mut tbackend_addr = None;
    let mut json_mode = false;
    // LAB-RACK-P7: named entrypoint selector (--entry <contract_name>)
    let mut entry_name: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "run" => { i += 1; }
            "--contract" | "-c" => {
                if i + 1 < args.len() {
                    contract_path = Some(&args[i + 1]);
                    i += 2;
                } else {
                    if json_mode {
                        println!("{}", serde_json::json!({ "status": "error", "error": "Missing value for --contract option" }));
                    } else {
                        eprintln!("  {}Error: Missing value for --contract option{}", RED, RESET);
                    }
                    std::process::exit(1);
                }
            }
            "--inputs" | "-i" => {
                if i + 1 < args.len() {
                    inputs_path = Some(&args[i + 1]);
                    i += 2;
                } else {
                    if json_mode {
                        println!("{}", serde_json::json!({ "status": "error", "error": "Missing value for --inputs option" }));
                    } else {
                        eprintln!("  {}Error: Missing value for --inputs option{}", RED, RESET);
                    }
                    std::process::exit(1);
                }
            }
            "--as-of" | "-t" => {
                if i + 1 < args.len() {
                    as_of = Some(&args[i + 1]);
                    i += 2;
                } else {
                    if json_mode {
                        println!("{}", serde_json::json!({ "status": "error", "error": "Missing value for --as-of option" }));
                    } else {
                        eprintln!("  {}Error: Missing value for --as-of option{}", RED, RESET);
                    }
                    std::process::exit(1);
                }
            }
            "--tbackend" | "-b" => {
                if i + 1 < args.len() {
                    tbackend_addr = Some(&args[i + 1]);
                    i += 2;
                } else {
                    if json_mode {
                        println!("{}", serde_json::json!({ "status": "error", "error": "Missing value for --tbackend option" }));
                    } else {
                        eprintln!("  {}Error: Missing value for --tbackend option{}", RED, RESET);
                    }
                    std::process::exit(1);
                }
            }
            "--json" | "-j" => {
                json_mode = true;
                i += 1;
            }
            // LAB-RACK-P7: named entrypoint selector
            "--entry" | "--entrypoint" | "-e" => {
                if i + 1 < args.len() {
                    entry_name = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    if json_mode {
                        println!("{}", serde_json::json!({ "status": "error", "error": "Missing value for --entry option" }));
                    } else {
                        eprintln!("  {}Error: Missing value for --entry option{}", RED, RESET);
                    }
                    std::process::exit(1);
                }
            }
            other => {
                if json_mode {
                    println!("{}", serde_json::json!({ "status": "error", "error": format!("Unknown argument '{}'", other) }));
                } else {
                    eprintln!("  {}Error: Unknown argument '{}'{}", RED, other, RESET);
                    print_help();
                }
                std::process::exit(1);
            }
        }
    }

    let contract_path = match contract_path {
        Some(p) => p,
        None => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": "--contract parameter is required" }));
            } else {
                eprintln!("  {}Error: --contract parameter is required{}", RED, RESET);
            }
            std::process::exit(1);
        }
    };

    let inputs_path = match inputs_path {
        Some(p) => p,
        None => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": "--inputs parameter is required" }));
            } else {
                eprintln!("  {}Error: --inputs parameter is required{}", RED, RESET);
            }
            std::process::exit(1);
        }
    };

    // 1. Resolve contract JSON (supporting directory .igapp or file loading)
    let contract_filepath = if Path::new(contract_path).is_dir() {
        let path_igapp = Path::new(contract_path).join("semantic_ir_program.json");
        let path_manifest = Path::new(contract_path).join("manifest.json");
        if path_igapp.exists() {
            path_igapp
        } else if path_manifest.exists() {
            path_manifest
        } else {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("Could not locate semantic_ir_program.json inside directory: {}", contract_path) }));
            } else {
                eprintln!("  {}Error: Could not locate semantic_ir_program.json inside directory: {}{}", RED, contract_path, RESET);
            }
            std::process::exit(1);
        }
    } else {
        Path::new(contract_path).to_path_buf()
    };

    if !json_mode {
        println!("  {} [*] Loading Compiled Contract: {}{}", YELLOW, contract_filepath.display(), RESET);
    }
    let contract_content = match fs::read_to_string(&contract_filepath) {
        Ok(c) => c,
        Err(e) => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("Failed to read contract file: {}", e) }));
            } else {
                eprintln!("  {}Error: Failed to read contract file: {}{}", RED, e, RESET);
            }
            std::process::exit(1);
        }
    };

    let contract_json: JsonValue = match serde_json::from_str(&contract_content) {
        Ok(j) => j,
        Err(e) => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("Failed to parse contract JSON: {}", e) }));
            } else {
                eprintln!("  {}Error: Failed to parse contract JSON: {}{}", RED, e, RESET);
            }
            std::process::exit(1);
        }
    };

    if let Err(e) = verify_load_capabilities(&contract_path, &contract_json) {
        if json_mode {
            println!("{}", serde_json::json!({ "status": "error", "error": e }));
        } else {
            eprintln!("  {}Error: {}{}", RED, e, RESET);
        }
        std::process::exit(1);
    }

    // 2. Compile AST graphs to Bytecode instructions
    if !json_mode {
        println!("  {} [*] Compiling Contract AST to Bytecode...{}", YELLOW, RESET);
    }
    let mut compiler = Compiler::new();
    // LAB-RACK-P7: use compile_entry; passes entry_name=None for default (contracts[0]).
    let bytecode = match compiler.compile_entry(&contract_json, entry_name.as_deref()) {
        Ok(bc) => bc,
        Err(e) => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("Compilation Error: {}", e) }));
            } else {
                eprintln!("  {}Compilation Error: {}{}", RED, e, RESET);
            }
            std::process::exit(1);
        }
    };
    if !json_mode {
        println!("      {}✔ Parity compile successful! Generated {} VM instructions.{}", GREEN, bytecode.len(), RESET);

        // 3. Disassemble Bytecode
        println!("\n  {}=== DISASSEMBLED IVM BYTECODE MNEMONICS ==={}", BOLD, RESET);
        println!("  ----------------------------------------------------------------------");
        println!("   OFFSET | OPCODE (HEX) | MNEMONIC         | ARGUMENTS");
        println!("  ----------------------------------------------------------------------");
        for (idx, inst) in bytecode.iter().enumerate() {
            let hex_op = format!("0x{:02X}", inst.opcode);
            let mnemonic = match inst.opcode {
                OP_PUSH_LIT => "PUSH_LIT",
                OP_LOAD_REF => "LOAD_REF",
                OP_STORE_REG => "STORE_REG",
                OP_LOAD_REG => "LOAD_REG",
                OP_ADD => "ADD",
                OP_SUB => "SUB",
                OP_MUL => "MUL",
                OP_DIV => "DIV",
                OP_EQ => "EQ",
                OP_GT => "GT",
                OP_JMP => "JMP",
                OP_JMP_IF => "JMP_IF",
                OP_JMP_UNLESS => "JMP_UNLESS",
                OP_LOAD_AS_OF => "LOAD_AS_OF",
                OP_EMIT_OBS => "EMIT_OBS",
                OP_RET => "RET",
                OP_UNSUPPORTED => "UNSUPPORTED",
                _ => "UNKNOWN",
            };
            let args_str = if inst.args.is_empty() {
                "-".to_string()
            } else {
                inst.args.iter().map(|v| format!("{:?}", v)).collect::<Vec<_>>().join(", ")
            };
            println!("    {:04}  |     {:<8} | {:<16} | {}", idx, hex_op, mnemonic, args_str);
        }
        println!("  ----------------------------------------------------------------------\n");
    }

    // LAB-RACK-P9: Build dispatch table from all contracts in the igapp.
    // Enables call_contract("ContractName", ...) dispatch at VM runtime.
    // Each contract is compiled independently into DispatchEntry { bytecode, input_names, modifier }.
    // Non-fatal: compilation errors for individual contracts are skipped (logged in non-json mode).
    let mut p9_dispatch_table = std::collections::HashMap::new();
    if let Some(contracts_arr) = contract_json.get("contracts").and_then(|c| c.as_array()) {
        for contract_item in contracts_arr {
            let c_name = contract_item.get("contract_name")
                .or_else(|| contract_item.get("name"))
                .and_then(|n| n.as_str())
                .unwrap_or("");
            if !c_name.is_empty() {
                match compiler.build_dispatch_entry(contract_item, c_name) {
                    Ok(entry) => { p9_dispatch_table.insert(c_name.to_string(), entry); }
                    Err(e) => {
                        if !json_mode {
                            eprintln!("  [P9] Note: skipping dispatch entry for '{}': {}", c_name, e);
                        }
                    }
                }
            }
        }
    }

    // 4. Load Inputs and Temporal coordinates
    if !json_mode {
        println!("  {} [*] Loading Inputs from: {}{}", YELLOW, inputs_path, RESET);
    }
    let inputs_content = match fs::read_to_string(inputs_path) {
        Ok(c) => c,
        Err(e) => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("Failed to read inputs file: {}", e) }));
            } else {
                eprintln!("  {}Error: Failed to read inputs file: {}{}", RED, e, RESET);
            }
            std::process::exit(1);
        }
    };

    let inputs_json: JsonValue = match serde_json::from_str(&inputs_content) {
        Ok(j) => j,
        Err(e) => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("Failed to parse inputs JSON: {}", e) }));
            } else {
                eprintln!("  {}Error: Failed to parse inputs JSON: {}{}", RED, e, RESET);
            }
            std::process::exit(1);
        }
    };

    let mut inputs = HashMap::new();
    if let Some(obj) = inputs_json.as_object() {
        for (k, v) in obj {
            inputs.insert(k.clone(), Value::from_json(v));
        }
    }

    let mut resolved_grants = HashMap::new();
    let contract_dir = Path::new(contract_path);
    if contract_dir.is_dir() {
        let mut active_grants = HashMap::new();
        if let Some(grants_val) = inputs_json.get("active_grants") {
            if let Ok(grants_map) = serde_json::from_value::<HashMap<String, igniter_vm::passport::CapabilityGrant>>(grants_val.clone()) {
                active_grants = grants_map;
            }
        }

        let mut caller_bindings = HashMap::new();
        if let Some(bindings_val) = inputs_json.get("caller_bindings") {
            if let Ok(bindings_map) = serde_json::from_value::<HashMap<String, String>>(bindings_val.clone()) {
                caller_bindings = bindings_map;
            }
        }

        match igniter_vm::passport::load_and_verify_passport(contract_dir, &active_grants, &caller_bindings) {
            Ok(resolved) => {
                resolved_grants = resolved;
                if !json_mode {
                    println!("      {}✔ Capability passport validated and callee grants resolved successfully!{}", GREEN, RESET);
                }
            }
            Err(e) => {
                if json_mode {
                    println!("{}", serde_json::json!({ "status": "error", "error": format!("Passport load failed: {}", e) }));
                } else {
                    eprintln!("  {}Error: Passport load failed: {}{}", RED, e, RESET);
                }
                std::process::exit(1);
            }
        }
    }

    let mut temporal_context = HashMap::new();
    if let Some(ref as_of_ts) = as_of {
        temporal_context.insert("as_of".to_string(), Value::String(Arc::from(as_of_ts.as_str())));
    } else if let Some(as_of_val) = inputs.get("as_of") {
        if let Ok(as_of_str) = as_of_val.as_str() {
            temporal_context.insert("as_of".to_string(), Value::String(Arc::from(as_of_str)));
        }
    }

    // LAB-RACK-P7: read modifier from the selected entry (by name if --entry provided, else contracts[0]).
    let modifier = contract_json.get("modifier")
        .or_else(|| {
            if let Some(contracts_arr) = contract_json.get("contracts").and_then(|c| c.as_array()) {
                let selected = if let Some(ref name) = entry_name {
                    contracts_arr.iter().find(|c| {
                        c.get("contract_name").and_then(|n| n.as_str()) == Some(name.as_str())
                            || c.get("name").and_then(|n| n.as_str()) == Some(name.as_str())
                    })
                } else {
                    contracts_arr.get(0)
                };
                selected.and_then(|c| c.get("modifier"))
            } else {
                None
            }
        })
        .and_then(|m| m.as_str())
        .unwrap_or("pure");
    temporal_context.insert("contract_modifier".to_string(), Value::String(Arc::from(modifier)));

    // LAB-RACK-P9: initialize __call_chain__ with the current executing contract name.
    // Prevents the executing contract from calling itself via call_contract (self-recursion).
    let p9_root_name: String = if let Some(ref name) = entry_name {
        name.clone()
    } else {
        contract_json.get("contracts")
            .and_then(|c| c.as_array())
            .and_then(|a| a.get(0))
            .and_then(|c| c.get("contract_name").and_then(|n| n.as_str()))
            .unwrap_or("")
            .to_string()
    };
    temporal_context.insert("__call_chain__".to_string(), Value::String(Arc::from(p9_root_name.as_str())));

    // 5. Bootstrap temporal database backend
    let backend: Option<Arc<dyn TBackend>> = if let Some(addr) = tbackend_addr {
        if !json_mode {
            println!("  {} [*] Connecting to Remote TBackend Ledger at: {}{}", YELLOW, addr, RESET);
        }
        let client = LedgerTcpBackend::new(addr);
        match client.ping().await {
            Ok(true) => {
                if !json_mode {
                    println!("      {}✔ TCP handshake successful! Remote ledger is ONLINE.{}", GREEN, RESET);
                }
                Some(Arc::new(client))
            }
            _ => {
                if json_mode {
                    println!("{}", serde_json::json!({ "status": "error", "error": format!("Remote TBackend at {} is OFFLINE or unreachable", addr) }));
                } else {
                    eprintln!("  {}Error: Remote TBackend at {} is OFFLINE or unreachable.{}", RED, addr, RESET);
                }
                std::process::exit(1);
            }
        }
    } else {
        if !json_mode {
            println!("  {} [*] Bootstrapping Ephemeral Memory Temporal Backend...{}", YELLOW, RESET);
        }
        let mem = MemoryHistoryBackend::new();
        // Check if inputs have pre-loaded history records
        if let Some(hist_arr) = inputs_json.get("history").and_then(|v| v.as_array()) {
            for record in hist_arr {
                if let (Some(store), Some(time), Some(val)) = (
                    record.get("store").and_then(|v| v.as_str()),
                    record.get("valid_time").and_then(|v| v.as_str()),
                    record.get("value")
                ) {
                    mem.write_history(store, time, Value::from_json(val)).await;
                    if !json_mode {
                        println!("      [History Preload] {} valid_time: {} => {:?}", store, time, val);
                    }
                }
            }
        }
        Some(Arc::new(mem))
    };

    // 6. Execute VM bytecode
    if !json_mode {
        println!("  {} [*] Launching Stack VM Evaluator loop...{}", YELLOW, RESET);
    }
    // LAB-RACK-P9: attach pre-built dispatch table for call_contract support.
    let mut vm = VM::new(backend);
    vm.dispatch_table = p9_dispatch_table;

    let start_time = tokio::time::Instant::now();
    let result = vm.execute_with_grants(&bytecode, &inputs, &temporal_context, &resolved_grants).await;
    let elapsed = start_time.elapsed();

    match result {
        Ok(output) => {
            if json_mode {
                let sink = vm.observation_sink.lock().await;
                let response = serde_json::json!({
                    "status": "success",
                    "result": output.to_json(),
                    "latency_us": elapsed.as_micros(),
                    "observations": *sink
                });
                println!("{}", serde_json::to_string(&response).unwrap());
            } else {
                println!("\n  {}================ EVALUATION SUCCESS ================{}", GREEN, RESET);
                println!("   Resulting Output: {:?}", output);
                println!("   Execution Latency: {:.2} microseconds ({:.4} ms)", elapsed.as_micros() as f64, elapsed.as_millis() as f64);
                println!("  ======================================================\n");

                // Display audit observations
                let sink = vm.observation_sink.lock().await;
                if !sink.is_empty() {
                    println!("  {}🔐 Captured Evidence Audit Observations (Total: {}):{}", BOLD, sink.len(), RESET);
                    for (idx, obs) in sink.iter().enumerate() {
                        println!("\n  [Observation #{}] ID: {}", idx + 1, obs["observation_id"].as_str().unwrap_or(""));
                        println!("  ----------------------------------------------------------------------");
                        println!("    Kind:           {}", obs["kind"].as_str().unwrap_or(""));
                        if obs["kind"].as_str() == Some("temporal_live_read_observation") {
                            println!("    Store Query:    {}", obs["store"].as_str().unwrap_or(""));
                            println!("    As Of Time:     {}", obs["as_of"].as_str().unwrap_or(""));
                            println!("    Result Value:   {:?}", obs["result_value"]);
                        } else {
                            println!("    Observed Value: {:?}", obs["value"]);
                        }
                        println!("  ----------------------------------------------------------------------");
                    }
                    println!();
                }
            }
        }
        Err(e) => {
            if json_mode {
                println!("{}", serde_json::json!({ "status": "error", "error": format!("VM evaluation failed: {}", e) }));
            } else {
                eprintln!("\n  {}✘ EVALUATION FAILED: {}{}\n", RED, e, RESET);
            }
            std::process::exit(1);
        }
    }
}

fn print_help() {
    println!("\n{}Usage:{}", BOLD, RESET);
    println!("  igniter-vm run --contract <path> --inputs <path> [options]");
    println!("  igniter-vm reactive --contract <path> --trigger-store <store> --target-store <store> --tbackend <ip:port> [options]");
    println!("\n{}Options:{}", BOLD, RESET);
    println!("  -c, --contract <path>     Path to compiled contract JSON or .igapp directory");
    println!("  -i, --inputs <path>       Path to inputs variable bindings JSON file");
    println!("  -t, --as-of <timestamp>   Override bitemporal valid-time coordinates (ISO8601)");
    println!("  -b, --tbackend <ip:port>  Connect to standalone compiled tbackend TCP server");
    println!("  -j, --json                Output raw JSON response (quiet mode)");
    println!("  --trigger-store <store>   Store name that triggers webhook evaluations");
    println!("  --target-store <store>    Store name where computed projections are committed");
    println!("  -p, --listener-port <port> Port for the webhook listener (default: 8089)");
    println!("  -h, --help                Show this help message\n");
}

fn verify_load_capabilities(contract_path: &str, contract_json: &JsonValue) -> Result<(), String> {
    let contracts_to_check = if let Some(arr) = contract_json.get("contracts").and_then(|a| a.as_array()) {
        arr.clone()
    } else {
        vec![contract_json.clone()]
    };

    for c in &contracts_to_check {
        let modifier = c.get("modifier").and_then(|m| m.as_str()).unwrap_or("pure");
        if modifier == "privileged" {
            let c_name = c.get("name")
                .or_else(|| c.get("contract_id"))
                .and_then(|n| n.as_str())
                .unwrap_or("");
            
            let mut has_token = false;
            if let Some(tokens) = contract_json.get("capability_tokens")
                .or_else(|| c.get("capability_tokens"))
                .and_then(|t| t.as_array())
            {
                if tokens.iter().any(|t| t.as_str() == Some(c_name)) {
                    has_token = true;
                }
            }

            if !has_token && Path::new(contract_path).is_dir() {
                let manifest_path = Path::new(contract_path).join("manifest.json");
                if manifest_path.exists() {
                    if let Ok(manifest_content) = fs::read_to_string(&manifest_path) {
                        if let Ok(manifest_json) = serde_json::from_str::<serde_json::Value>(&manifest_content) {
                            if let Some(tokens) = manifest_json.get("capability_tokens").and_then(|t| t.as_array()) {
                                if tokens.iter().any(|t| t.as_str() == Some(c_name)) {
                                    has_token = true;
                                }
                            }
                        }
                    }
                }
            }

            if !has_token {
                return Err(format!("OOF-M1: privileged contract '{}' requires matching capability token in manifest", c_name));
            }
        }
    }
    Ok(())
}
