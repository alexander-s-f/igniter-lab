use igniter_machine::fact::Fact;
use igniter_machine::machine::IgniterMachine;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::collections::HashMap;
use tauri::State;

use sha2::{Sha256, Digest};
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::classifier::Classifier;
use igniter_compiler::typechecker::TypeChecker;
use igniter_compiler::emitter::Emitter;
use igniter_compiler::assembler::Assembler;
use igniter_compiler::monomorphizer::monomorphize_program;

pub struct MachineState(pub Arc<Mutex<IgniterMachine>>);

fn copy_dir_all(src: impl AsRef<Path>, dst: impl AsRef<Path>) -> std::io::Result<()> {
    fs::create_dir_all(&dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_all(entry.path(), dst.as_ref().join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.as_ref().join(entry.file_name()))?;
        }
    }
    Ok(())
}

#[derive(Serialize, Deserialize, Clone)]
pub struct DetailedCompileResult {
    pub success: bool,
    pub message: String,
    pub duration_ms: u64,
    pub source_length: usize,
    pub source_hash: String,
    pub artifact_dir: Option<String>,
    pub diagnostics_count: usize,
    pub error_stage: Option<String>,
}

fn do_compile_contract(
    state: &State<MachineState>,
    source_code: &str,
    contract_name: &str,
    workspace_dir: Option<String>,
) -> DetailedCompileResult {
    let start_time = std::time::Instant::now();
    let source_length = source_code.len();

    // Calculate SHA-256 hash
    let mut hasher = Sha256::new();
    hasher.update(source_code.as_bytes());
    let source_hash = format!("{:x}", hasher.finalize());

    let timestamp = chrono::Utc::now().timestamp_millis();
    let artifact_dir = workspace_dir.map(|dir| {
        Path::new(&dir)
            .join(".igniter")
            .join("artifacts")
            .join(format!("{}_{}", contract_name, timestamp))
    });

    let mut diagnostics_list = Vec::new();
    let mut error_stage: Option<String> = None;

    // Re-implement the compilation loop steps to save intermediate artifacts and capture stages
    let mut run_compile = || -> Result<String, String> {
        let mut lexer = Lexer::new(source_code);
        let tokens = lexer.tokenize();

        let mut parser = Parser::new(tokens);
        let mut parsed = parser.parse();
        if !parsed.parse_errors.is_empty() {
            error_stage = Some("parse".to_string());
            // Collect parse errors for diagnostics.json
            for e in &parsed.parse_errors {
                diagnostics_list.push(serde_json::json!({
                    "rule": e.rule.clone(),
                    "message": e.message.clone(),
                    "severity": if e.severity == "error" { "error" } else { "warning" },
                    "line": e.line,
                    "col": e.col
                }));
            }
            return Err(format!("Parse errors: {:?}", parsed.parse_errors));
        }

        monomorphize_program(&mut parsed);

        let classifier = Classifier::new();
        let sample_input = serde_json::json!({});
        let classified = classifier.classify(&parsed, &sample_input);
        if classified.pass_result != "ok" {
            error_stage = Some("classify".to_string());
            for oof in &classified.oof_log {
                diagnostics_list.push(serde_json::json!({
                    "rule": oof.rule.clone(),
                    "message": oof.message.clone(),
                    "severity": "error",
                    "line": oof.line,
                    "col": null
                }));
            }
            return Err(format!("Classification failed: {:?}", classified.oof_log));
        }

        let typechecker = TypeChecker::new();
        let typed = typechecker.typecheck(&classified, &parsed.functions);
        if typed.pass_result != "ok" {
            error_stage = Some("typecheck".to_string());
            for e in &typed.type_errors {
                diagnostics_list.push(serde_json::json!({
                    "rule": e.rule.clone(),
                    "message": e.message.clone(),
                    "severity": if e.rule.starts_with("OOF-") { "error" } else { "warning" },
                    "line": e.line,
                    "col": null
                }));
            }
            return Err(format!("Typechecking failed: {:?}", typed.type_errors));
        }

        // Add any warnings from typecheck to diagnostics list as well
        for e in &typed.type_errors {
            if !e.rule.starts_with("OOF-") {
                diagnostics_list.push(serde_json::json!({
                    "rule": e.rule.clone(),
                    "message": e.message.clone(),
                    "severity": "warning",
                    "line": e.line,
                    "col": null
                }));
            }
        }

        let emitter = Emitter::new();
        let emit_res = emitter.emit_typed(&typed);

        let assembler = Assembler::new();
        let temp_dir = std::env::temp_dir().join(format!("igniter_compile_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&temp_dir).map_err(|e| format!("Failed to create temp directory: {}", e))?;

        let _manifest_val = assembler.assemble(&emit_res, temp_dir.to_str().unwrap())
            .map_err(|e| {
                error_stage = Some("emit".to_string());
                let _ = fs::remove_dir_all(&temp_dir);
                e.to_string()
            })?;

        let contract_id = contract_name.to_string();
        let contract_file_path = temp_dir.join("contracts").join(format!("{}.json", contract_id));
        if !contract_file_path.exists() {
            error_stage = Some("emit".to_string());
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(format!("Compiled contract file not found for {}", contract_id));
        }

        let content = fs::read_to_string(&contract_file_path).map_err(|e| {
            let _ = fs::remove_dir_all(&temp_dir);
            e.to_string()
        })?;
        let mut contract_json: serde_json::Value = serde_json::from_str(&content).map_err(|e| {
            let _ = fs::remove_dir_all(&temp_dir);
            e.to_string()
        })?;

        // Determine fragment_class
        let fragment_class = contract_json.get("fragment_class")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        // Copy files from temp_dir to workspace artifact_dir
        if let Some(ref dst_path) = artifact_dir {
            let _ = copy_dir_all(&temp_dir, dst_path);
            if let Some(obj) = contract_json.as_object_mut() {
                obj.insert("artifact_dir".to_string(), serde_json::Value::String(dst_path.to_string_lossy().to_string()));
            }
        }

        let _ = fs::remove_dir_all(&temp_dir);

        let machine = state.0.lock();
        machine.registry.write().register(contract_id, contract_json);

        Ok(format!("Compiled: {} [{}]", contract_name, fragment_class))
    };

    let duration_ms = start_time.elapsed().as_millis() as u64;

    let (success, message) = match run_compile() {
        Ok(msg) => (true, msg),
        Err(err) => {
            // If failed, make sure diagnostics_list is populated if it was empty
            if diagnostics_list.is_empty() {
                diagnostics_list.push(serde_json::json!({
                    "rule": "COMPILATION_FAILED",
                    "message": err.clone(),
                    "severity": "error",
                    "line": null,
                    "col": null
                }));
            }
            // Create the artifact directory anyway and write the diagnostics.json and manifest.json
            if let Some(ref dst_path) = artifact_dir {
                let _ = fs::create_dir_all(dst_path);

                let diagnostics_json = serde_json::json!({
                    "diagnostics": diagnostics_list
                });
                let manifest_json = serde_json::json!({
                    "kind": "igapp_manifest",
                    "success": false,
                    "contract": contract_name,
                    "error": err.clone(),
                    "source_hash": source_hash.clone(),
                });
                let report_json = serde_json::json!({
                    "success": false,
                    "stage": error_stage.clone().unwrap_or_else(|| "unknown".to_string()),
                    "error": err.clone(),
                    "diagnostics": diagnostics_list
                });

                let _ = fs::write(dst_path.join("diagnostics.json"), serde_json::to_string_pretty(&diagnostics_json).unwrap_or_default());
                let _ = fs::write(dst_path.join("manifest.json"), serde_json::to_string_pretty(&manifest_json).unwrap_or_default());
                let _ = fs::write(dst_path.join("compilation_report.json"), serde_json::to_string_pretty(&report_json).unwrap_or_default());
            }
            (false, err)
        }
    };

    DetailedCompileResult {
        success,
        message,
        duration_ms,
        source_length,
        source_hash,
        artifact_dir: artifact_dir.map(|p| p.to_string_lossy().to_string()),
        diagnostics_count: diagnostics_list.iter().filter(|d| d.get("severity").and_then(|s| s.as_str()) == Some("error")).count(),
        error_stage,
    }
}

// ������ Response types ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Deserialize, Clone)]
pub struct ContractInfo {
    pub name: String,
    pub fragment_class: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct FactInfo {
    pub id: String,
    pub store: String,
    pub key: String,
    pub value: serde_json::Value,
    pub transaction_time: f64,
    pub valid_time: Option<f64>,
    pub causation: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct ObsInfo {
    pub id: String,
    pub kind: String,
    pub value: serde_json::Value,
    pub timestamp: f64,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct StatusInfo {
    pub backend: String,
    pub facts_count: usize,
    pub contracts_count: usize,
    pub observations_count: usize,
}

// ������ Commands ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

#[tauri::command]
pub fn load_contract(
    state: State<MachineState>,
    source_code: String,
    contract_name: String,
    workspace_dir: Option<String>,
) -> Result<serde_json::Value, String> {
    let res = do_compile_contract(&state, &source_code, &contract_name, workspace_dir);
    serde_json::to_value(res).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn load_contract_from_file(
    state: State<MachineState>,
    path: String,
    contract_name: String,
    workspace_dir: Option<String>,
) -> Result<serde_json::Value, String> {
    let source_code = std::fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read file '{}': {}", path, e))?;

    let res = do_compile_contract(&state, &source_code, &contract_name, workspace_dir);
    serde_json::to_value(res).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn dispatch_contract(
    state: State<MachineState>,
    contract_name: String,
    inputs_json: String,
) -> Result<serde_json::Value, String> {
    let inputs: serde_json::Value = if inputs_json.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&inputs_json)
            .map_err(|e| format!("Invalid JSON inputs: {}", e))?
    };

    let machine = state.0.lock();
    futures::executor::block_on(machine.dispatch(&contract_name, inputs))
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn list_contracts(state: State<MachineState>) -> Result<Vec<ContractInfo>, String> {
    let machine = state.0.lock();
    let registry = machine.registry.read();

    let contracts = registry
        .contracts
        .iter()
        .map(|(name, contract_json)| {
            let fragment_class = contract_json
                .get("fragment_class")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string();
            ContractInfo {
                name: name.clone(),
                fragment_class,
            }
        })
        .collect();

    Ok(contracts)
}

#[tauri::command]
pub fn write_fact(
    state: State<MachineState>,
    store: String,
    key: String,
    value_json: String,
) -> Result<String, String> {
    let value: serde_json::Value = serde_json::from_str(&value_json)
        .unwrap_or(serde_json::json!({}));

    let fact = Fact {
        id: uuid::Uuid::new_v4().to_string(),
        store: store.clone(),
        key: key.clone(),
        value,
        value_hash: "".to_string(),
        causation: None,
        transaction_time: chrono::Utc::now().timestamp() as f64,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    };

    let fact_id = fact.id.clone();
    let machine = state.0.lock();
    futures::executor::block_on(machine.write_fact(fact))
        .map_err(|e| e.to_string())?;

    Ok(format!("Written fact {} to {}/{}", fact_id, store, key))
}

#[tauri::command]
pub fn read_facts(
    state: State<MachineState>,
    store: String,
    key: String,
    as_of: Option<f64>,
) -> Result<Vec<FactInfo>, String> {
    let machine = state.0.lock();
    let facts =
        futures::executor::block_on(machine.storage.facts_for(&store, &key, None, as_of))
            .map_err(|e| e.to_string())?;

    let infos = facts
        .into_iter()
        .map(|f| FactInfo {
            id: f.id,
            store: f.store,
            key: f.key,
            value: f.value,
            transaction_time: f.transaction_time,
            valid_time: f.valid_time,
            causation: f.causation,
        })
        .collect();

    Ok(infos)
}

#[tauri::command]
pub fn list_observations(state: State<MachineState>) -> Result<Vec<ObsInfo>, String> {
    let machine = state.0.lock();
    let observations = machine.observations.read();

    let infos = observations
        .iter()
        .map(|o| ObsInfo {
            id: o.id.clone(),
            kind: o.kind.clone(),
            value: o.value.clone(),
            timestamp: o.timestamp,
        })
        .collect();

    Ok(infos)
}

#[tauri::command]
pub fn checkpoint_machine(state: State<MachineState>, path: String) -> Result<(), String> {
    let machine = state.0.lock();
    machine
        .checkpoint(std::path::Path::new(&path))
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn resume_machine(state: State<MachineState>, path: String) -> Result<String, String> {
    let resumed =
        IgniterMachine::resume(std::path::Path::new(&path), None, "in_memory")
            .map_err(|e| e.to_string())?;

    let facts_count = futures::executor::block_on(resumed.storage.all_facts())
        .map(|f| f.len())
        .unwrap_or(0);

    let contracts_count = resumed.registry.read().contracts.len();

    // Replace existing machine state
    *state.0.lock() = resumed;

    Ok(format!(
        "Resumed: {} facts, {} contracts",
        facts_count, contracts_count
    ))
}

#[tauri::command]
pub fn get_status(state: State<MachineState>) -> Result<StatusInfo, String> {
    let machine = state.0.lock();

    let facts_count = futures::executor::block_on(machine.storage.all_facts())
        .map(|f| f.len())
        .unwrap_or(0);

    let contracts_count = machine.registry.read().contracts.len();
    let observations_count = machine.observations.read().len();

    Ok(StatusInfo {
        backend: "in_memory".to_string(),
        facts_count,
        contracts_count,
        observations_count,
    })
}

#[tauri::command]
pub fn clear_observations(state: State<MachineState>) -> Result<(), String> {
    let machine = state.0.lock();
    machine.observations.write().clear();
    Ok(())
}

#[tauri::command]
pub fn get_contract_ir(
    state: State<'_, MachineState>,
    name: String,
) -> Result<serde_json::Value, String> {
    let machine = state.0.lock();
    let registry = machine.registry.read();
    registry
        .contracts
        .get(&name)
        .cloned()
        .ok_or_else(|| format!("Contract '{}' not found", name))
}

// ������ Workspace types ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct BackendConfig {
    pub backend_type: String,
    pub path: Option<String>,
    pub address: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct WorkspaceConfig {
    pub name: String,
    pub version: String,
    pub backend: BackendConfig,
    pub contracts: Vec<String>,
    pub auto_load: bool,
    pub root_dir: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct WorkspaceLoadResult {
    pub path: String,
    pub contract_name: String,
    pub success: bool,
    pub message: String,
}

// ������ Diagnostic type ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Deserialize, Clone)]
pub struct DiagnosticInfo {
    pub rule: String,
    pub message: String,
    pub severity: String,
    pub line: Option<u32>,
    pub col: Option<u32>,
}

// ������ Workspace commands ������������������������������������������������������������������������������������������������������������������������������������������������������������������������

#[tauri::command]
pub fn open_workspace(dir: String) -> Result<WorkspaceConfig, String> {
    let config_path = Path::new(&dir).join(".igniter").join("workspace.json");
    if !config_path.exists() {
        return Err(format!("No workspace found at {}. Create one first.", config_path.display()));
    }
    let content = fs::read_to_string(&config_path)
        .map_err(|e| format!("Failed to read workspace: {}", e))?;
    let mut config: WorkspaceConfig = serde_json::from_str(&content)
        .map_err(|e| format!("Invalid workspace.json: {}", e))?;
    config.root_dir = dir;
    Ok(config)
}

#[tauri::command]
pub fn create_workspace(dir: String, name: String) -> Result<WorkspaceConfig, String> {
    let igniter_dir = Path::new(&dir).join(".igniter");
    fs::create_dir_all(&igniter_dir)
        .map_err(|e| format!("Failed to create .igniter dir: {}", e))?;

    let config = WorkspaceConfig {
        name: name.clone(),
        version: "0.1".to_string(),
        backend: BackendConfig {
            backend_type: "in_memory".to_string(),
            path: None,
            address: None,
        },
        contracts: Vec::new(),
        auto_load: true,
        root_dir: dir.clone(),
    };

    let json = serde_json::to_string_pretty(&config)
        .map_err(|e| e.to_string())?;
    fs::write(igniter_dir.join("workspace.json"), json)
        .map_err(|e| format!("Failed to write workspace.json: {}", e))?;

    Ok(config)
}

#[tauri::command]
pub fn list_ig_files(dir: String) -> Result<Vec<String>, String> {
    let mut results = Vec::new();
    collect_ig_files(Path::new(&dir), 0, 4, &mut results);
    Ok(results)
}

fn collect_ig_files(dir: &Path, depth: usize, max_depth: usize, out: &mut Vec<String>) {
    if depth > max_depth { return }
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                if name != "target" && name != "node_modules" && !name.starts_with('.') {
                    collect_ig_files(&path, depth + 1, max_depth, out);
                }
            } else if path.extension().and_then(|e| e.to_str()) == Some("ig") {
                if let Some(s) = path.to_str() {
                    out.push(s.to_string());
                }
            }
        }
    }
}

#[tauri::command]
pub fn read_file(path: String) -> Result<String, String> {
    fs::read_to_string(&path).map_err(|e| format!("Failed to read {}: {}", path, e))
}

#[tauri::command]
pub fn write_file(path: String, content: String) -> Result<(), String> {
    fs::write(&path, content).map_err(|e| format!("Failed to write {}: {}", path, e))
}

#[tauri::command]
pub fn load_workspace_contracts(
    state: State<'_, MachineState>,
    config: WorkspaceConfig,
) -> Result<Vec<WorkspaceLoadResult>, String> {
    let mut results = Vec::new();
    for contract_path in &config.contracts {
        let full_path = if Path::new(contract_path).is_absolute() {
            contract_path.clone()
        } else {
            Path::new(&config.root_dir).join(contract_path)
                .to_string_lossy().to_string()
        };

        let contract_name = Path::new(&full_path)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_string();

        match fs::read_to_string(&full_path) {
            Ok(source) => {
                let machine = state.0.lock();
                match machine.load_contract_source(&source, &contract_name) {
                    Ok(()) => results.push(WorkspaceLoadResult {
                        path: full_path,
                        contract_name,
                        success: true,
                        message: "Compiled successfully".to_string(),
                    }),
                    Err(e) => results.push(WorkspaceLoadResult {
                        path: full_path,
                        contract_name,
                        success: false,
                        message: e.to_string(),
                    }),
                }
            }
            Err(e) => results.push(WorkspaceLoadResult {
                path: full_path,
                contract_name,
                success: false,
                message: format!("Cannot read file: {}", e),
            }),
        }
    }
    Ok(results)
}

#[tauri::command]
pub fn check_source(
    source_code: String,
    contract_name: String,
) -> Result<Vec<DiagnosticInfo>, String> {
    let _ = contract_name;
    let raw = IgniterMachine::check_source(&source_code);
    let diags = raw.into_iter().map(|(rule, message, severity, line, col)| DiagnosticInfo {
        rule, message, severity, line, col,
    }).collect();
    Ok(diags)
}

// ������ Feature 1: System Graph ���������������������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Clone)]
pub struct SystemNode {
    pub id: String,
    pub contract_name: String,
    pub fragment_class: String,
    pub inputs: Vec<String>,
    pub outputs: Vec<String>,
    pub node_count: usize,
}

#[derive(Serialize, Clone)]
pub struct SystemEdge {
    pub from: String,
    pub to: String,
    pub label: String,
}

#[derive(Serialize)]
pub struct SystemGraph {
    pub nodes: Vec<SystemNode>,
    pub edges: Vec<SystemEdge>,
}

#[tauri::command]
pub fn get_system_graph(state: State<'_, MachineState>) -> Result<SystemGraph, String> {
    let machine = state.0.lock();
    let registry = machine.registry.read();
    let mut nodes = Vec::new();

    for (name, ir) in registry.contracts.iter() {
        let fragment_class = ir.get("fragment_class")
            .or_else(|| ir.get("modifier"))
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        // input_ports / compute_nodes / output_ports are the real field names
        let inputs: Vec<String> = ir.get("input_ports").or_else(|| ir.get("inputs"))
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter()
                .filter_map(|i| {
                    let t = i.get("type_tag").and_then(|t| t.as_str())
                        .or_else(|| i.get("type").and_then(|t| t.get("name")).and_then(|n| n.as_str()));
                    let n = i.get("name").and_then(|n| n.as_str());
                    n.map(|name| format!("{}:{}", name, t.unwrap_or("?")))
                })
                .collect())
            .unwrap_or_default();

        let outputs: Vec<String> = ir.get("output_ports").or_else(|| ir.get("outputs"))
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter()
                .filter_map(|o| {
                    let t = o.get("type_tag").and_then(|t| t.as_str())
                        .or_else(|| o.get("type").and_then(|t| t.get("name")).and_then(|n| n.as_str()));
                    let n = o.get("name").and_then(|n| n.as_str());
                    n.map(|name| format!("{}:{}", name, t.unwrap_or("?")))
                })
                .collect())
            .unwrap_or_default();

        let node_count = ir.get("compute_nodes").or_else(|| ir.get("nodes"))
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);

        nodes.push(SystemNode {
            id: name.clone(),
            contract_name: name.clone(),
            fragment_class,
            inputs,
            outputs,
            node_count,
        });
    }

    // Find type-based connections between contracts
    let mut edges = Vec::new();
    for i in 0..nodes.len() {
        for j in 0..nodes.len() {
            if i == j { continue }
            let a = &nodes[i];
            let b = &nodes[j];

            let a_out_types: Vec<&str> = a.outputs.iter()
                .filter_map(|s| s.split(':').nth(1))
                .collect();
            let b_in_types: Vec<&str> = b.inputs.iter()
                .filter_map(|s| s.split(':').nth(1))
                .collect();

            for t in &a_out_types {
                if b_in_types.contains(t) && *t != "String" && *t != "Integer" && *t != "Bool" {
                    edges.push(SystemEdge {
                        from: a.id.clone(),
                        to: b.id.clone(),
                        label: t.to_string(),
                    });
                    break;
                }
            }
        }
    }

    Ok(SystemGraph { nodes, edges })
}

// ������ Feature 2: Execution Tracer ���������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Clone)]
pub struct TraceStep {
    pub node: String,
    pub kind: String,
    pub fragment_class: String,
    pub deps: Vec<String>,
    pub order: usize,
    pub value_preview: String,
}

#[derive(Serialize)]
pub struct TracedResult {
    pub result: serde_json::Value,
    pub trace: Vec<TraceStep>,
    pub total_ms: u64,
    pub observations: Vec<String>,
    pub contract_name: String,
    // New fields for P10
    pub success: bool,
    pub boundary_phase: String, // "compiler" | "loader" | "execution" | "none"
    pub error_message: Option<String>,
    pub diagnostics: Vec<DiagnosticInfo>,
    pub passport_summary: Option<serde_json::Value>,
    pub loader_decision: Option<String>,
    pub ffi_observations: Vec<serde_json::Value>,
}

#[tauri::command]
pub fn dispatch_traced(
    state: State<'_, MachineState>,
    contract_name: String,
    inputs: serde_json::Value,
) -> Result<TracedResult, String> {
    let start = std::time::Instant::now();

    // 1. Retrieve contract IR from registry
    let ir = {
        let machine = state.0.lock();
        let registry = machine.registry.read();
        registry.contracts
            .get(&contract_name)
            .cloned()
            .ok_or_else(|| format!("Contract '{}' not found", contract_name))?
    };

    let artifact_dir = ir.get("artifact_dir").and_then(|v| v.as_str()).map(|s| s.to_string());

    // 2. Load static compilation diagnostics if available
    let mut diagnostics = Vec::new();
    if let Some(ref dir_str) = artifact_dir {
        let path = std::path::Path::new(dir_str);
        let diag_path = path.join("diagnostics.json");
        if diag_path.exists() {
            if let Ok(content) = std::fs::read_to_string(diag_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(arr) = val.get("diagnostics").and_then(|a| a.as_array()) {
                        for item in arr {
                            if let Ok(info) = serde_json::from_value::<DiagnosticInfo>(item.clone()) {
                                diagnostics.push(info);
                            }
                        }
                    }
                }
            }
        }
    }

    // 3. Initialize trace steps statically from IR
    let mut steps: Vec<TraceStep> = Vec::new();
    let mut order = 0;

    for inp in ir.get("input_ports").or_else(|| ir.get("inputs"))
        .and_then(|v| v.as_array()).unwrap_or(&vec![])
    {
        let name = inp.get("name").and_then(|n| n.as_str()).unwrap_or("?");
        let preview = inputs.get(name)
            .map(|v| v.to_string())
            .unwrap_or_else(|| "\u{2014}".to_string());
        steps.push(TraceStep {
            node: name.to_string(),
            kind: "input".to_string(),
            fragment_class: ir.get("fragment_class")
                .and_then(|v| v.as_str()).unwrap_or("core").to_string(),
            deps: vec![],
            order,
            value_preview: preview,
        });
        order += 1;
    }

    for node in ir.get("compute_nodes").or_else(|| ir.get("nodes"))
        .and_then(|v| v.as_array()).unwrap_or(&vec![])
    {
        let name = node.get("name").and_then(|n| n.as_str()).unwrap_or("?");
        let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or("compute");
        let frag = node.get("fragment_class")
            .or_else(|| node.get("fragment"))
            .and_then(|f| f.as_str()).unwrap_or("core");
        let deps: Vec<String> = node.get("dependencies")
            .or_else(|| node.get("deps"))
            .and_then(|d| d.as_array())
            .map(|arr| arr.iter()
                .filter_map(|d| d.as_str().map(|s| s.to_string()))
                .collect())
            .unwrap_or_default();

        steps.push(TraceStep {
            node: name.to_string(),
            kind: kind.to_string(),
            fragment_class: frag.to_string(),
            deps,
            order,
            value_preview: "\u{27f3}".to_string(),
        });
        order += 1;
    }

    for out in ir.get("output_ports").or_else(|| ir.get("outputs"))
        .and_then(|v| v.as_array()).unwrap_or(&vec![])
    {
        let name = out.get("name").and_then(|n| n.as_str()).unwrap_or("?");
        steps.push(TraceStep {
            node: name.to_string(),
            kind: "output".to_string(),
            fragment_class: ir.get("fragment_class")
                .and_then(|v| v.as_str()).unwrap_or("core").to_string(),
            deps: vec![name.to_string()],
            order,
            value_preview: "\u{27f3}".to_string(),
        });
        order += 1;
    }

    // 4. Parse capability bindings and active grants from inputs
    let mut active_grants = HashMap::new();
    if let Some(grants_val) = inputs.get("active_grants") {
        if let Ok(grants_map) = serde_json::from_value::<HashMap<String, igniter_vm::passport::CapabilityGrant>>(grants_val.clone()) {
            active_grants = grants_map;
        }
    }

    let mut caller_bindings = HashMap::new();
    if let Some(bindings_val) = inputs.get("caller_bindings") {
        if let Ok(bindings_map) = serde_json::from_value::<HashMap<String, String>>(bindings_val.clone()) {
            caller_bindings = bindings_map;
        }
    }

    let mut resolved_grants = HashMap::new();
    let mut loader_decision = None;
    let mut passport_summary = None;

    if let Some(ref dir_str) = artifact_dir {
        let path = std::path::Path::new(dir_str);
        let passport_path = path.join("passport.json");
        if passport_path.exists() {
            // Load passport content for summary
            if let Ok(passport_content) = std::fs::read_to_string(&passport_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&passport_content) {
                    passport_summary = Some(val);
                }
            }

            match igniter_vm::passport::load_and_verify_passport(path, &active_grants, &caller_bindings) {
                Ok(grants) => {
                    resolved_grants = grants;
                    loader_decision = Some("approved".to_string());
                }
                Err(err) => {
                    let total_ms = start.elapsed().as_millis() as u64;
                    return Ok(TracedResult {
                        result: serde_json::json!({}),
                        trace: steps,
                        total_ms,
                        observations: Vec::new(),
                        contract_name,
                        success: false,
                        boundary_phase: "loader".to_string(),
                        error_message: Some(format!("LoaderError: {}", err)),
                        diagnostics,
                        passport_summary,
                        loader_decision: Some(format!("rejected: {}", err)),
                        ffi_observations: Vec::new(),
                    });
                }
            }
        }
    }

    // 5. Compile to VM Bytecode
    let mut vm_compiler = igniter_vm::compiler::Compiler::new();
    let bytecode = match vm_compiler.compile(&ir) {
        Ok(bc) => bc,
        Err(err) => {
            let total_ms = start.elapsed().as_millis() as u64;
            return Ok(TracedResult {
                result: serde_json::json!({}),
                trace: steps,
                total_ms,
                observations: Vec::new(),
                contract_name,
                success: false,
                boundary_phase: "compiler".to_string(),
                error_message: Some(format!("VMCompilationError: {}", err)),
                diagnostics,
                passport_summary,
                loader_decision,
                ffi_observations: Vec::new(),
            });
        }
    };

    // 6. Setup VM Inputs and Temporal context
    let mut vm_inputs = HashMap::new();
    if let Some(obj) = inputs.as_object() {
        for (k, v) in obj {
            vm_inputs.insert(k.clone(), igniter_vm::value::Value::from_json(v));
        }
    }

    let mut temporal_context = HashMap::new();
    let modifier = ir.get("modifier").and_then(|m| m.as_str()).unwrap_or("pure");
    temporal_context.insert("contract_modifier".to_string(), igniter_vm::value::Value::String(std::sync::Arc::from(modifier)));

    // 7. Get storage and observations from state to build adapter
    let (storage, machine_observations) = {
        let machine = state.0.lock();
        (machine.storage.clone(), machine.observations.clone())
    };
    let adapter = std::sync::Arc::new(igniter_machine::bridge::MachineVMBackendAdapter::new(storage, machine_observations));
    let vm = igniter_vm::vm::VM::new(Some(adapter));

    // 8. Execute VM bytecode
    let result_val = futures::executor::block_on(vm.execute_with_grants(&bytecode, &vm_inputs, &temporal_context, &resolved_grants));

    let total_ms = start.elapsed().as_millis() as u64;

    // Collect VM observations
    let vm_obs = {
        let sink = futures::executor::block_on(vm.observation_sink.lock());
        sink.clone()
    };

    let mut ffi_observations = Vec::new();
    let mut observations = Vec::new();
    for obs in vm_obs {
        ffi_observations.push(obs.clone());
        let kind = obs.get("kind").and_then(|v| v.as_str()).unwrap_or("generic");
        let path = obs.get("path").and_then(|v| v.as_str()).unwrap_or("?");
        if kind == "io_read_observation" {
            let bytes = obs.get("bytes_read").and_then(|v| v.as_u64()).unwrap_or(0);
            observations.push(format!("read_text: read {} bytes from {}", bytes, path));
        } else if kind == "io_write_receipt" {
            let bytes = obs.get("bytes_written").and_then(|v| v.as_u64()).unwrap_or(0);
            observations.push(format!("write_text: wrote {} bytes to {}", bytes, path));
        } else {
            observations.push(format!("{}: {}", kind, path));
        }
    }

    match result_val {
        Ok(output) => {
            let result_json = output.to_json();

            // Update output trace step previews
            for step in steps.iter_mut() {
                if step.kind == "output" {
                    if let Some(val) = result_json.get(&step.node) {
                        step.value_preview = val.to_string();
                    }
                }
            }

            Ok(TracedResult {
                result: result_json,
                trace: steps,
                total_ms,
                observations,
                contract_name,
                success: true,
                boundary_phase: "none".to_string(),
                error_message: None,
                diagnostics,
                passport_summary,
                loader_decision,
                ffi_observations,
            })
        }
        Err(err) => {
            Ok(TracedResult {
                result: serde_json::json!({}),
                trace: steps,
                total_ms,
                observations,
                contract_name,
                success: false,
                boundary_phase: "execution".to_string(),
                error_message: Some(format!("VMExecutionError: {}", err)),
                diagnostics,
                passport_summary,
                loader_decision,
                ffi_observations,
            })
        }
    }
}

// ������ Feature 3: App Generator ������������������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SwarmConfig {
    pub enabled: bool,
    pub instances: u32,
    pub topology: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AppConfig {
    pub name: String,
    pub version: String,
    pub description: String,
    pub contracts_dir: String,
    pub backend: BackendConfig,
    pub swarm: SwarmConfig,
    pub root_dir: String,
}

fn to_pascal_case(s: &str) -> String {
    s.split('-').map(|w| {
        let mut c = w.chars();
        match c.next() {
            None => String::new(),
            Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        }
    }).collect()
}

#[tauri::command]
pub fn create_app(dir: String, name: String, description: String) -> Result<AppConfig, String> {
    let app_dir = std::path::Path::new(&dir).join(&name);
    fs::create_dir_all(app_dir.join("contracts"))
        .map_err(|e| format!("Failed to create app dir: {}", e))?;
    fs::create_dir_all(app_dir.join("schemas"))
        .map_err(|e| format!("Failed to create schemas dir: {}", e))?;

    let config = AppConfig {
        name: name.clone(),
        version: "0.1.0".to_string(),
        description: description.clone(),
        contracts_dir: "contracts".to_string(),
        backend: BackendConfig {
            backend_type: "in_memory".to_string(),
            path: None,
            address: None,
        },
        swarm: SwarmConfig {
            enabled: false,
            instances: 1,
            topology: "single".to_string(),
        },
        root_dir: app_dir.to_string_lossy().to_string(),
    };

    let json = serde_json::to_string_pretty(&config).map_err(|e| e.to_string())?;
    fs::write(app_dir.join("igniter.app.json"), json)
        .map_err(|e| format!("Failed to write igniter.app.json: {}", e))?;

    let starter = format!(
        "-- {}: starter contract\nmodule {}.Core\n\ncontract HelloWorld {{\n  input message: String\n  compute greeting = message\n  output greeting: String\n}}\n",
        name,
        to_pascal_case(&name)
    );
    fs::write(app_dir.join("contracts").join("hello_world.ig"), starter)
        .map_err(|e| format!("Failed to write starter contract: {}", e))?;

    Ok(config)
}

// ������ Feature 4: File Tree ������������������������������������������������������������������������������������������������������������������������������������������������������������������

#[derive(Serialize, Clone)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub entry_type: String,
    pub children: Vec<FileEntry>,
    pub extension: Option<String>,
}

const SKIP_NAMES: &[&str] = &[
    "target", "node_modules", ".git", ".svelte-kit", "build", "dist", "coverage",
];

fn collect_tree(dir: &Path, depth: usize, max_depth: usize, out: &mut Vec<FileEntry>) {
    if depth > max_depth {
        return;
    }
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    let mut items: Vec<_> = entries.flatten().collect();
    items.sort_by(|a, b| {
        let a_dir = a.path().is_dir();
        let b_dir = b.path().is_dir();
        match (a_dir, b_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.file_name().cmp(&b.file_name()),
        }
    });
    for item in items {
        let path = item.path();
        let name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        if name.starts_with('.') || SKIP_NAMES.contains(&name.as_str()) {
            continue;
        }
        if path.is_dir() {
            let mut children = Vec::new();
            collect_tree(&path, depth + 1, max_depth, &mut children);
            out.push(FileEntry {
                name,
                path: path.to_string_lossy().to_string(),
                entry_type: "dir".to_string(),
                children,
                extension: None,
            });
        } else {
            let ext = path.extension().and_then(|e| e.to_str()).map(|s| s.to_string());
            out.push(FileEntry {
                name,
                path: path.to_string_lossy().to_string(),
                entry_type: "file".to_string(),
                children: vec![],
                extension: ext,
            });
        }
    }
}

#[tauri::command]
pub fn list_dir_tree(dir: String) -> Result<Vec<FileEntry>, String> {
    let mut entries = Vec::new();
    collect_tree(Path::new(&dir), 0, 5, &mut entries);
    Ok(entries)
}

#[tauri::command]
pub fn create_file(path: String, content: String) -> Result<(), String> {
    let p = Path::new(&path);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directories: {}", e))?;
    }
    fs::write(&path, &content).map_err(|e| format!("Failed to create '{}': {}", path, e))
}

#[tauri::command]
pub fn delete_file(path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if p.is_dir() {
        fs::remove_dir_all(&path)
            .map_err(|e| format!("Failed to delete directory '{}': {}", path, e))
    } else {
        fs::remove_file(&path).map_err(|e| format!("Failed to delete '{}': {}", path, e))
    }
}

#[tauri::command]
pub fn rename_file(from: String, to: String) -> Result<(), String> {
    fs::rename(&from, &to)
        .map_err(|e| format!("Failed to rename '{}' to '{}': {}", from, to, e))
}

#[tauri::command]
pub fn list_apps(dir: String) -> Result<Vec<AppConfig>, String> {
    let apps_dir = std::path::Path::new(&dir).join("apps");
    if !apps_dir.exists() { return Ok(vec![]) }

    let mut apps = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&apps_dir) {
        for entry in entries.flatten() {
            let config_path = entry.path().join("igniter.app.json");
            if config_path.exists() {
                if let Ok(content) = std::fs::read_to_string(&config_path) {
                    if let Ok(mut config) = serde_json::from_str::<AppConfig>(&content) {
                        config.root_dir = entry.path().to_string_lossy().to_string();
                        apps.push(config);
                    }
                }
            }
        }
    }
    Ok(apps)
}

pub fn resolve_workspace_path(sub_path: &str) -> std::path::PathBuf {
    let mut path = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    if path.ends_with("src-tauri") {
        path.pop();
    }
    path.pop(); // Go up from igniter-ide to igniter-lab
    path.join(sub_path)
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct SlotPayload {
    pub view_id: String,
    pub artifact_digest: String,
    pub slot_values: serde_json::Value,
    pub source_receipt_id: Option<String>,
}

#[derive(Serialize, Clone, Debug)]
pub struct CommandReceipt {
    pub success: bool,
    pub message: String,
    pub view_id: String,
    pub rejected_keys: Vec<String>,
    pub accepted_keys: Vec<String>,
    pub timestamp: String,
    pub receipt_id: String,
    pub source_receipt_id: Option<String>,
}

pub struct LoadedArtifact {
    pub view_id: String,
    pub digest: String,
    pub contracts: Vec<String>,
    pub value: serde_json::Value,
}

pub fn load_all_artifacts() -> Result<Vec<LoadedArtifact>, String> {
    let out_dir = resolve_workspace_path("igniter-view-engine/out");
    let entries = std::fs::read_dir(&out_dir)
        .map_err(|e| format!("Failed to read directory: {}", e))?;

    let mut artifacts = Vec::new();
    let mut seen_view_ids = std::collections::HashSet::new();

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() && path.file_name().and_then(|n| n.to_str()).map_or(false, |s| s.ends_with("_artifact.json")) {
            if let Ok(content) = std::fs::read_to_string(&path) {
                if let Ok(artifact_val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(view_id) = artifact_val.get("view_id").and_then(|v| v.as_str()) {
                        let view_id = view_id.to_string();
                        // Duplicate view_id check (TIVF-P7-4)
                        if !seen_view_ids.insert(view_id.clone()) {
                            return Err(format!("Duplicate view_id '{}' detected in artifacts", view_id));
                        }

                        let digest = artifact_val.get("artifact_digest")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        let mut contracts = Vec::new();
                        if let Some(slots) = artifact_val.get("slots").and_then(|s| s.as_object()) {
                            for slot_def in slots.values() {
                                if let Some(ref_str) = slot_def.get("contract_ref").and_then(|r| r.as_str()) {
                                    let contract_part = ref_str.split('.').next().unwrap_or(ref_str).to_string();
                                    if !contracts.contains(&contract_part) {
                                        contracts.push(contract_part);
                                    }
                                }
                            }
                        }

                        artifacts.push(LoadedArtifact {
                            view_id,
                            digest,
                            contracts,
                            value: artifact_val,
                        });
                    }
                }
            }
        }
    }
    Ok(artifacts)
}

pub fn find_view_artifact(view_id: &str) -> Result<serde_json::Value, String> {
    let artifacts = load_all_artifacts()?;
    for art in artifacts {
        if art.view_id == view_id {
            return Ok(art.value);
        }
    }
    Err(format!("View artifact not found for view_id '{}'", view_id))
}

pub fn resolve_view_id_from_contract(contract_id: &str) -> Result<String, String> {
    let artifacts = load_all_artifacts()?;
    let mut matches = Vec::new();
    for art in &artifacts {
        if art.contracts.contains(&contract_id.to_string()) {
            matches.push(art.view_id.clone());
        }
    }

    if matches.is_empty() {
        return Err(format!("No view artifact found mapping to contract_id '{}'", contract_id));
    }
    if matches.len() > 1 {
        // Ambiguous match (TIVF-P7-5)
        return Err(format!("Ambiguous contract mapping for '{}': maps to multiple views {:?}", contract_id, matches));
    }

    Ok(matches[0].clone())
}

#[tauri::command]
pub fn inject_slot_values(
    app: tauri::AppHandle,
    payload: SlotPayload,
) -> Result<CommandReceipt, String> {
    use tauri::Manager;

    let timestamp = chrono::Local::now().to_rfc3339();
    let receipt_id = uuid::Uuid::new_v4().to_string();

    // Alphanumeric + dot + underscore check on view_id to prevent injection
    if payload.view_id.chars().any(|c| !c.is_alphanumeric() && c != '.' && c != '_') {
        let receipt = CommandReceipt {
            success: false,
            message: "Payload rejected: view_id contains illegal characters".to_string(),
            view_id: payload.view_id.clone(),
            rejected_keys: Vec::new(),
            accepted_keys: Vec::new(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            source_receipt_id: payload.source_receipt_id.clone(),
        };
        let _ = write_telemetry_receipt(&receipt);
        return Ok(receipt);
    }

    // 1. Oversized payload guard
    let payload_str = serde_json::to_string(&payload.slot_values).unwrap_or_default();
    if payload_str.len() > 4096 {
        let receipt = CommandReceipt {
            success: false,
            message: "Payload rejected: size exceeds 4096 bytes limit".to_string(),
            view_id: payload.view_id.clone(),
            rejected_keys: Vec::new(),
            accepted_keys: Vec::new(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            source_receipt_id: payload.source_receipt_id.clone(),
        };
        let _ = write_telemetry_receipt(&receipt);
        return Ok(receipt);
    }

    // 2. Malformed payload guard
    let slot_obj = match payload.slot_values.as_object() {
        Some(obj) => obj,
        None => {
            let receipt = CommandReceipt {
                success: false,
                message: "Payload rejected: slot_values must be a JSON object".to_string(),
                view_id: payload.view_id.clone(),
                rejected_keys: Vec::new(),
                accepted_keys: Vec::new(),
                timestamp: timestamp.clone(),
                receipt_id: receipt_id.clone(),
                source_receipt_id: payload.source_receipt_id.clone(),
            };
            let _ = write_telemetry_receipt(&receipt);
            return Ok(receipt);
        }
    };

    // 3. Load and parse view artifact dynamically
    let artifact = match find_view_artifact(&payload.view_id) {
        Ok(art) => art,
        Err(e) => {
            let receipt = CommandReceipt {
                success: false,
                message: format!("Payload rejected: view_id '{}' is unknown ({})", payload.view_id, e),
                view_id: payload.view_id.clone(),
                rejected_keys: Vec::new(),
                accepted_keys: Vec::new(),
                timestamp: timestamp.clone(),
                receipt_id: receipt_id.clone(),
                source_receipt_id: payload.source_receipt_id.clone(),
            };
            let _ = write_telemetry_receipt(&receipt);
            return Ok(receipt);
        }
    };

    let expected_view_id = artifact.get("view_id").and_then(|v| v.as_str()).unwrap_or_default();
    let expected_digest = artifact.get("artifact_digest").and_then(|v| v.as_str()).unwrap_or_default();

    // 4. Validate view_id
    if payload.view_id != expected_view_id {
        let receipt = CommandReceipt {
            success: false,
            message: format!("Payload rejected: view_id '{}' is unknown", payload.view_id),
            view_id: payload.view_id.clone(),
            rejected_keys: Vec::new(),
            accepted_keys: Vec::new(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            source_receipt_id: payload.source_receipt_id.clone(),
        };
        let _ = write_telemetry_receipt(&receipt);
        return Ok(receipt);
    }

    // 5. Validate artifact_digest (fail-closed)
    if payload.artifact_digest != expected_digest {
        let receipt = CommandReceipt {
            success: false,
            message: format!("Payload rejected: artifact digest mismatch (Expected '{}', Received '{}')", expected_digest, payload.artifact_digest),
            view_id: payload.view_id.clone(),
            rejected_keys: Vec::new(),
            accepted_keys: Vec::new(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            source_receipt_id: payload.source_receipt_id.clone(),
        };
        let _ = write_telemetry_receipt(&receipt);
        return Ok(receipt);
    }

    // 6. Validate declared slot keys
    let declared_slots = match artifact.get("slots").and_then(|s| s.as_object()) {
        Some(slots) => slots,
        None => {
            return Err("View artifact schema has no slots definition".to_string());
        }
    };

    let mut accepted_keys = Vec::new();
    let mut rejected_keys = Vec::new();

    for key in slot_obj.keys() {
        if declared_slots.contains_key(key) {
            accepted_keys.push(key.clone());
        } else {
            rejected_keys.push(key.clone());
        }
    }

    if !rejected_keys.is_empty() {
        let receipt = CommandReceipt {
            success: false,
            message: format!("Payload rejected: contains undeclared slot keys: {:?}", rejected_keys),
            view_id: payload.view_id.clone(),
            rejected_keys,
            accepted_keys: Vec::new(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            source_receipt_id: payload.source_receipt_id.clone(),
        };
        let _ = write_telemetry_receipt(&receipt);
        return Ok(receipt);
    }

    // 7. Inject validated SlotValues via eval inside proof-window
    if let Some(window) = app.get_webview_window("proof-window") {
        let sanitized_slots = serde_json::to_string(&payload.slot_values).unwrap_or_default();
        let view_id_json = serde_json::to_string(&payload.view_id).unwrap_or_default();
        let js = format!(
            "if (window.IgniterView && window.IgniterView.components[{}]) {{ \
               window.IgniterView.components[{}].updateSlots({}); \
             }}",
            view_id_json,
            view_id_json,
            sanitized_slots
        );

        if let Err(e) = window.eval(&js) {
            let receipt = CommandReceipt {
                success: false,
                message: format!("Failed to evaluate JS in window: {}", e),
                view_id: payload.view_id.clone(),
                rejected_keys: Vec::new(),
                accepted_keys: accepted_keys.clone(),
                timestamp: timestamp.clone(),
                receipt_id: receipt_id.clone(),
                source_receipt_id: payload.source_receipt_id.clone(),
            };
            let _ = write_telemetry_receipt(&receipt);
            return Ok(receipt);
        }
    } else {
        let receipt = CommandReceipt {
            success: false,
            message: "Target window 'proof-window' not found".to_string(),
            view_id: payload.view_id.clone(),
            rejected_keys: Vec::new(),
            accepted_keys: accepted_keys.clone(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            source_receipt_id: payload.source_receipt_id.clone(),
        };
        let _ = write_telemetry_receipt(&receipt);
        return Ok(receipt);
    }

    let receipt = CommandReceipt {
        success: true,
        message: "Slot values injected successfully".to_string(),
        view_id: payload.view_id,
        rejected_keys: Vec::new(),
        accepted_keys,
        timestamp,
        receipt_id,
        source_receipt_id: payload.source_receipt_id,
    };
    let _ = write_telemetry_receipt(&receipt);
    Ok(receipt)
}

fn write_telemetry_receipt(receipt: &CommandReceipt) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("tauri_bridge_receipt.json");
    let json = serde_json::to_string_pretty(receipt).unwrap_or_default();
    std::fs::write(path, json)
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct MockObservation {
    pub trace_id: String,
    pub contract_id: String,
    pub status: String,
    pub outputs: serde_json::Value,
    pub diagnostics: serde_json::Value,
    pub slot_values: serde_json::Value,
    pub view_id: Option<String>,
    pub view_ids: Option<Vec<String>>,
}

#[tauri::command]
pub fn simulate_trace_observation(
    app: tauri::AppHandle,
    observation: MockObservation,
    history_state: State<'_, TelemetryHistoryState>,
) -> Result<CommandReceipt, String> {
    // 1. Fail-closed: Validate basic observation fields
    if observation.trace_id.is_empty() || observation.contract_id.is_empty() {
        return Err("Malformed observation: trace_id or contract_id is empty".to_string());
    }

    // 2. Play the observation using play_trace_playback helper
    let playback = play_trace_playback(app, vec![observation], None, history_state)?;
    if !playback.success || playback.steps.is_empty() {
        return Err(format!("Trace observation simulation failed: {}", playback.message));
    }

    // Return the last step receipt
    Ok(playback.steps.last().unwrap().clone())
}

#[derive(Default, Clone, Debug, Serialize, Deserialize)]
pub struct ActiveSession {
    pub session_token: Option<String>,
    pub transaction_id: Option<String>,
    pub created_at: Option<chrono::DateTime<chrono::Local>>,
}

pub struct ActiveSessionState(pub parking_lot::Mutex<ActiveSession>);

pub fn hmac_sha256(key: &[u8], message: &[u8]) -> Vec<u8> {
    use sha2::Digest;
    let mut padded_key = [0u8; 64];
    if key.len() > 64 {
        let mut hasher = Sha256::new();
        hasher.update(key);
        let result = hasher.finalize();
        padded_key[..32].copy_from_slice(&result);
    } else {
        padded_key[..key.len()].copy_from_slice(key);
    }

    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= padded_key[i];
        opad[i] ^= padded_key[i];
    }

    let mut hasher1 = Sha256::new();
    hasher1.update(&ipad);
    hasher1.update(message);
    let inner_hash = hasher1.finalize();

    let mut hasher2 = Sha256::new();
    hasher2.update(&opad);
    hasher2.update(&inner_hash);
    hasher2.finalize().to_vec()
}

pub fn verify_envelope_hmac(envelope: &VmTraceAdapterEnvelopeV0, session_token: &str) -> Result<(), String> {
    let provided_sig = match envelope.passport_signature.as_deref() {
        Some(sig) => sig,
        None => return Err("Missing passport_signature".to_string()),
    };

    let mut env_value = serde_json::to_value(envelope)
        .map_err(|e| format!("Failed to serialize envelope to JSON value: {}", e))?;

    if let serde_json::Value::Object(ref mut map) = env_value {
        map.remove("passport_signature");
    } else {
        return Err("Envelope is not a JSON object".to_string());
    }

    let canonical_json = serde_json::to_string(&env_value)
        .map_err(|e| format!("Failed to serialize canonical JSON: {}", e))?;

    let expected_sig_bytes = hmac_sha256(session_token.as_bytes(), canonical_json.as_bytes());
    let expected_sig = expected_sig_bytes.iter().map(|b| format!("{:02x}", b)).collect::<String>();

    if provided_sig == expected_sig {
        Ok(())
    } else {
        Err(format!("Invalid signature: expected '{}', got '{}'", expected_sig, provided_sig))
    }
}

pub struct TelemetryHistoryState(pub parking_lot::Mutex<Vec<RedactedTraceReceipt>>);

#[derive(Serialize, Clone, Debug)]
pub struct RedactedTraceReceipt {
    pub trace_id: String,
    pub contract_id: String,
    pub status: String,
    pub timestamp: String,
    pub target_views: Option<Vec<String>>,
    pub selected_slot_keys: Vec<String>,
    pub outputs_digest: String,
    pub diagnostics_digest: String,
    pub redaction_policy: String,
    pub receipt_id: Option<String>,
    pub event_type: String,
}

fn write_telemetry_history_summary(history: &[RedactedTraceReceipt]) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("telemetry_history_summary.json");
    let json = serde_json::to_string_pretty(history).unwrap_or_default();
    std::fs::write(path, json)
}

fn write_trace_receipt(
    observation: &MockObservation,
    generate_proof_fixture: Option<bool>,
    history_state: &TelemetryHistoryState,
) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);

    let outputs_str = serde_json::to_string(&observation.outputs).unwrap_or_default();
    let mut hasher_out = Sha256::new();
    hasher_out.update(outputs_str.as_bytes());
    let outputs_digest = format!("sha256:{:x}", hasher_out.finalize());

    let diag_str = serde_json::to_string(&observation.diagnostics).unwrap_or_default();
    let mut hasher_diag = Sha256::new();
    hasher_diag.update(diag_str.as_bytes());
    let diagnostics_digest = format!("sha256:{:x}", hasher_diag.finalize());

    let selected_slot_keys: Vec<String> = match observation.slot_values.as_object() {
        Some(obj) => obj.keys().cloned().collect(),
        None => Vec::new(),
    };

    let target_views = if let Some(ref vids) = observation.view_ids {
        Some(vids.clone())
    } else if let Some(ref vid) = observation.view_id {
        Some(vec![vid.clone()])
    } else {
        None
    };

    let timestamp = chrono::Local::now().to_rfc3339();
    let receipt_id = uuid::Uuid::new_v4().to_string();

    let event_type = if observation.status == "success" {
        "applied_trace_events".to_string()
    } else {
        "attempted_trace_events".to_string()
    };

    let redacted = RedactedTraceReceipt {
        trace_id: observation.trace_id.clone(),
        contract_id: observation.contract_id.clone(),
        status: observation.status.clone(),
        timestamp,
        target_views,
        selected_slot_keys,
        outputs_digest,
        diagnostics_digest,
        redaction_policy: "redacted-trace-receipt-v0".to_string(),
        receipt_id: Some(receipt_id),
        event_type,
    };

    let path = out_path.join("tauri_trace_receipt.json");
    let json = serde_json::to_string_pretty(&redacted).unwrap_or_default();
    std::fs::write(path, json)?;

    // Update circular history buffer (TIVF-P11-6, TIVF-P11-7, TIVF-P11-8)
    // Refactored lock scope: lock is held only for in-memory mutation and clone.
    let history_snapshot = {
        let mut history = history_state.0.lock();
        history.push(redacted);
        while history.len() > 10 {
            history.remove(0); // evict oldest (FIFO)
        }
        history.clone()
    };
    let _ = write_telemetry_history_summary(&history_snapshot);

    if let Some(true) = generate_proof_fixture {
        let fixture_path = resolve_workspace_path("igniter-view-engine/fixtures/raw_trace_receipt.json");
        let raw_json = serde_json::to_string_pretty(observation).unwrap_or_default();
        let _ = std::fs::write(fixture_path, raw_json);
    }

    Ok(())
}

#[derive(Serialize, Clone, Debug)]
pub struct PlaybackReceipt {
    pub playback_id: String,
    pub timestamp: String,
    pub success: bool,
    pub message: String,
    pub steps: Vec<CommandReceipt>,
}

#[tauri::command]
pub fn play_trace_playback(
    app: tauri::AppHandle,
    observations: Vec<MockObservation>,
    generate_proof_fixture: Option<bool>,
    history_state: State<'_, TelemetryHistoryState>,
) -> Result<PlaybackReceipt, String> {
    let timestamp = chrono::Local::now().to_rfc3339();
    let playback_id = uuid::Uuid::new_v4().to_string();

    // 1. Oversized playback payload guard (fail-closed)
    let payload_str = serde_json::to_string(&observations).unwrap_or_default();
    if payload_str.len() > 65536 {
        return Err("Playback payload rejected: total size exceeds 65536 bytes limit".to_string());
    }
    if observations.len() > 50 {
        return Err("Playback payload rejected: exceeds maximum of 50 observations".to_string());
    }

    let mut steps = Vec::new();
    let mut overall_success = true;
    let mut error_msg = String::new();

    for obs in observations {
        // Deterministic check per observation
        if obs.trace_id.is_empty() || obs.contract_id.is_empty() {
            overall_success = false;
            error_msg = "Malformed observation: trace_id or contract_id is empty".to_string();
            break;
        }

        // Determine targets (multi-view routing)
        let targets = if let Some(ref vids) = obs.view_ids {
            vids.clone()
        } else if let Some(ref vid) = obs.view_id {
            vec![vid.clone()]
        } else {
            match resolve_view_id_from_contract(&obs.contract_id) {
                Ok(vid) => vec![vid],
                Err(e) => {
                    overall_success = false;
                    error_msg = format!("Could not resolve view targets: {}", e);
                    break;
                }
            }
        };

        // Write individual trace receipt (TIVF-P10-3, TIVF-P10-4, TIVF-P10-5)
        let _ = write_trace_receipt(&obs, generate_proof_fixture, &history_state);

        // Inject for each target
        for view_id in targets {
            let artifact = match find_view_artifact(&view_id) {
                Ok(art) => art,
                Err(e) => {
                    overall_success = false;
                    error_msg = format!("Could not find view artifact for '{}': {}", view_id, e);
                    break;
                }
            };

            let digest = match artifact.get("artifact_digest").and_then(|v| v.as_str()) {
                Some(d) => d.to_string(),
                None => {
                    overall_success = false;
                    error_msg = format!("Artifact '{}' does not contain artifact_digest", view_id);
                    break;
                }
            };

            // Project slot_values per target view schema (TIVF-P9-3, TIVF-P9-4)
            let mut projected_slot_values = serde_json::Map::new();
            if let Some(slots) = artifact.get("slots").and_then(|s| s.as_object()) {
                for slot_key in slots.keys() {
                    if let Some(val) = obs.slot_values.get(slot_key) {
                        projected_slot_values.insert(slot_key.clone(), val.clone());
                    }
                }
            }

            let payload = SlotPayload {
                view_id: view_id.clone(),
                artifact_digest: digest,
                slot_values: serde_json::Value::Object(projected_slot_values),
                source_receipt_id: Some(obs.trace_id.clone()),
            };

            match inject_slot_values(app.clone(), payload) {
                Ok(receipt) => {
                    let step_success = receipt.success;
                    steps.push(receipt);
                    if !step_success {
                        overall_success = false;
                        error_msg = format!("Step injection failed for view '{}'", view_id);
                        break;
                    }
                }
                Err(e) => {
                    overall_success = false;
                    error_msg = format!("Step injection error for view '{}': {}", view_id, e);
                    break;
                }
            }
        }

        if !overall_success {
            break;
        }
    }

    let receipt = PlaybackReceipt {
        playback_id,
        timestamp,
        success: overall_success,
        message: if overall_success { "Playback successfully applied all steps".to_string() } else { format!("Playback failed: {}", error_msg) },
        steps,
    };

    let _ = write_playback_receipt(&receipt);
    Ok(receipt)
}

fn write_playback_receipt(receipt: &PlaybackReceipt) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("tauri_playback_receipt.json");
    let json = serde_json::to_string_pretty(receipt).unwrap_or_default();
    std::fs::write(path, json)
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct TriggerIntent {
    pub view_id: String,
    pub artifact_digest: String,
    pub element_id: String,
    pub action_id: String,
    pub ui_state: Option<serde_json::Value>,
    pub timestamp: String,
}

#[derive(Serialize, Clone, Debug)]
pub struct TriggerIntentReceipt {
    pub success: bool,
    pub message: String,
    pub view_id: String,
    pub element_id: String,
    pub action_id: String,
    pub timestamp: String,
    pub receipt_id: String,
    pub ui_state_digest: Option<String>,
    pub ui_state_persisted: bool,
}

#[tauri::command]
pub fn record_trigger_intent(
    app: tauri::AppHandle,
    intent: TriggerIntent,
) -> Result<TriggerIntentReceipt, String> {
    let _ = app;
    let timestamp = chrono::Local::now().to_rfc3339();
    let receipt_id = uuid::Uuid::new_v4().to_string();

    let (ui_state_digest, ui_state_persisted) = if let Some(ref state) = intent.ui_state {
        let serialized = serde_json::to_string(state).unwrap_or_default();
        let mut hasher = Sha256::new();
        hasher.update(serialized.as_bytes());
        let digest_str = format!("sha256:{:x}", hasher.finalize());
        (Some(digest_str), false)
    } else {
        (None, false)
    };

    // 1. Oversized intent payload guard
    let intent_str = serde_json::to_string(&intent).unwrap_or_default();
    if intent_str.len() > 4096 {
        let receipt = TriggerIntentReceipt {
            success: false,
            message: "Intent rejected: size exceeds 4096 bytes limit".to_string(),
            view_id: intent.view_id.clone(),
            element_id: intent.element_id.clone(),
            action_id: intent.action_id.clone(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            ui_state_digest,
            ui_state_persisted,
        };
        let _ = write_trigger_intent_receipt(&receipt);
        return Ok(receipt);
    }

    // 2. Validate view_id dynamically (find artifact)
    let artifact = match find_view_artifact(&intent.view_id) {
        Ok(art) => art,
        Err(e) => {
            let receipt = TriggerIntentReceipt {
                success: false,
                message: format!("Intent rejected: view_id '{}' is unknown ({})", intent.view_id, e),
                view_id: intent.view_id.clone(),
                element_id: intent.element_id.clone(),
                action_id: intent.action_id.clone(),
                timestamp: timestamp.clone(),
                receipt_id: receipt_id.clone(),
                ui_state_digest,
                ui_state_persisted,
            };
            let _ = write_trigger_intent_receipt(&receipt);
            return Ok(receipt);
        }
    };

    // 3. Validate artifact_digest (fail-closed)
    let expected_digest = artifact.get("artifact_digest").and_then(|v| v.as_str()).unwrap_or_default();
    if intent.artifact_digest != expected_digest {
        let receipt = TriggerIntentReceipt {
            success: false,
            message: format!("Intent rejected: digest mismatch (Expected '{}', Received '{}')", expected_digest, intent.artifact_digest),
            view_id: intent.view_id.clone(),
            element_id: intent.element_id.clone(),
            action_id: intent.action_id.clone(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            ui_state_digest,
            ui_state_persisted,
        };
        let _ = write_trigger_intent_receipt(&receipt);
        return Ok(receipt);
    }

    // 4. Validate element_id in elements whitelist (fail-closed)
    let elements = match artifact.get("elements").and_then(|e| e.as_array()) {
        Some(elems) => elems,
        None => {
            let receipt = TriggerIntentReceipt {
                success: false,
                message: "Intent rejected: view artifact has no elements".to_string(),
                view_id: intent.view_id.clone(),
                element_id: intent.element_id.clone(),
                action_id: intent.action_id.clone(),
                timestamp: timestamp.clone(),
                receipt_id: receipt_id.clone(),
                ui_state_digest,
                ui_state_persisted,
            };
            let _ = write_trigger_intent_receipt(&receipt);
            return Ok(receipt);
        }
    };

    let mut matched_element = None;
    for elem in elements {
        if elem.get("element_id").and_then(|id| id.as_str()) == Some(&intent.element_id) {
            matched_element = Some(elem);
            break;
        }
    }

    let elem_def = match matched_element {
        Some(e) => e,
        None => {
            let receipt = TriggerIntentReceipt {
                success: false,
                message: format!("Intent rejected: element_id '{}' is not declared in view", intent.element_id),
                view_id: intent.view_id.clone(),
                element_id: intent.element_id.clone(),
                action_id: intent.action_id.clone(),
                timestamp: timestamp.clone(),
                receipt_id: receipt_id.clone(),
                ui_state_digest,
                ui_state_persisted,
            };
            let _ = write_trigger_intent_receipt(&receipt);
            return Ok(receipt);
        }
    };

    // 5. Validate action_id whitelisted under interaction rules (fail-closed)
    let interaction_rules = elem_def.get("interaction_rules").and_then(|r| r.as_array());
    let mut action_valid = false;

    if let Some(rules) = interaction_rules {
        for rule in rules {
            if let Some(rule_arr) = rule.as_array() {
                if rule_arr.len() >= 2 && rule_arr[0].as_str() == Some("on") && rule_arr[1].as_str() == Some(&intent.action_id) {
                    action_valid = true;
                    break;
                }
            }
        }
    }

    if !action_valid {
        let receipt = TriggerIntentReceipt {
            success: false,
            message: format!("Intent rejected: action_id '{}' is not whitelisted for element '{}'", intent.action_id, intent.element_id),
            view_id: intent.view_id.clone(),
            element_id: intent.element_id.clone(),
            action_id: intent.action_id.clone(),
            timestamp: timestamp.clone(),
            receipt_id: receipt_id.clone(),
            ui_state_digest,
            ui_state_persisted,
        };
        let _ = write_trigger_intent_receipt(&receipt);
        return Ok(receipt);
    }

    // 6. Action is valid -> write receipt only (no VM execution)
    let receipt = TriggerIntentReceipt {
        success: true,
        message: "TriggerIntent validated and recorded successfully".to_string(),
        view_id: intent.view_id,
        element_id: intent.element_id,
        action_id: intent.action_id,
        timestamp,
        receipt_id,
        ui_state_digest,
        ui_state_persisted,
    };
    let _ = write_trigger_intent_receipt(&receipt);
    Ok(receipt)
}

fn write_trigger_intent_receipt(receipt: &TriggerIntentReceipt) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("trigger_intent_receipt.json");
    let json = serde_json::to_string_pretty(receipt).unwrap_or_default();
    std::fs::write(path, json)
}

#[tauri::command]
pub fn read_playback_receipt() -> Result<serde_json::Value, String> {
    let path = resolve_workspace_path("igniter-view-engine/out/tauri_playback_receipt.json");
    if !path.exists() {
        return Err("Playback receipt file not found".to_string());
    }
    let content = std::fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read receipt: {}", e))?;
    let json: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse receipt JSON: {}", e))?;
    Ok(json)
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct VmTraceReceipt {
    pub transaction_id: String,
    pub contract_name: String,
    pub status: String,
    pub outputs: serde_json::Value,
    pub diagnostics: serde_json::Value,
    pub timestamp: String,
    pub target_views: Option<Vec<String>>,
}

pub fn adapt_vm_trace(receipt: VmTraceReceipt) -> Result<MockObservation, String> {
    // 1. Validate basic receipt fields
    if receipt.transaction_id.is_empty() || receipt.contract_name.is_empty() {
        return Err("Malformed VM trace receipt: transaction_id or contract_name is empty".to_string());
    }

    // 2. Resolve target views with validation and deduplication (TIVF-P9-6, TIVF-P9-7)
    let view_ids = match &receipt.target_views {
        Some(views) => {
            if views.is_empty() {
                return Err("Malformed VM trace receipt: target_views array is empty".to_string());
            }
            let mut unique_views = Vec::new();
            for v in views {
                if v.trim().is_empty() {
                    return Err("Malformed VM trace receipt: target_views contains empty view ID".to_string());
                }
                if !unique_views.contains(v) {
                    unique_views.push(v.clone());
                }
            }
            unique_views
        }
        None => {
            let resolved = resolve_view_id_from_contract(&receipt.contract_name)?;
            vec![resolved]
        }
    };

    // 3. Extract slot values for each resolved target view from outputs & diagnostics
    let mut resolved_slot_values = serde_json::Map::new();

    for view_id in &view_ids {
        let artifact = find_view_artifact(view_id)?;
        if let Some(slots) = artifact.get("slots").and_then(|s| s.as_object()) {
            for slot_key in slots.keys() {
                if let Some(val) = receipt.outputs.get(slot_key) {
                    resolved_slot_values.insert(slot_key.clone(), val.clone());
                } else if let Some(val) = receipt.diagnostics.get(slot_key) {
                    resolved_slot_values.insert(slot_key.clone(), val.clone());
                }
            }
        }
    }

    Ok(MockObservation {
        trace_id: receipt.transaction_id,
        contract_id: receipt.contract_name,
        status: receipt.status,
        outputs: receipt.outputs,
        diagnostics: receipt.diagnostics,
        slot_values: serde_json::Value::Object(resolved_slot_values),
        view_id: None,
        view_ids: Some(view_ids),
    })
}

#[tauri::command]
pub fn simulate_vm_trace_adapter(
    app: tauri::AppHandle,
    receipt: VmTraceReceipt,
    generate_proof_fixture: Option<bool>,
    history_state: State<'_, TelemetryHistoryState>,
) -> Result<PlaybackReceipt, String> {
    // 1. Bounded size limit on input receipt (limit to 16KB)
    let receipt_str = serde_json::to_string(&receipt).unwrap_or_default();
    if receipt_str.len() > 16384 {
        return Err("VM trace receipt rejected: size exceeds 16384 bytes limit".to_string());
    }

    // 2. Write raw input trace receipt fixture conditionally (TIVF-P9-9)
    if let Some(true) = generate_proof_fixture {
        let _ = write_vm_trace_fixture(&receipt);
    }

    // 3. Compute digests of raw outputs/diagnostics (TIVF-P9-9)
    let outputs_str = serde_json::to_string(&receipt.outputs).unwrap_or_default();
    let mut hasher_out = Sha256::new();
    hasher_out.update(outputs_str.as_bytes());
    let outputs_digest = format!("sha256:{:x}", hasher_out.finalize());

    let diag_str = serde_json::to_string(&receipt.diagnostics).unwrap_or_default();
    let mut hasher_diag = Sha256::new();
    hasher_diag.update(diag_str.as_bytes());
    let diagnostics_digest = format!("sha256:{:x}", hasher_diag.finalize());

    // 4. Run adapter to map VmTraceReceipt -> MockObservation
    let observation = adapt_vm_trace(receipt.clone())?;

    // 5. Gather selected slot keys
    let selected_slot_keys: Vec<String> = match observation.slot_values.as_object() {
        Some(obj) => obj.keys().cloned().collect(),
        None => Vec::new(),
    };

    // 6. Write redacted receipt to out/vm_trace_adapter_input_receipt.json (TIVF-P9-9, TIVF-P9-10)
    let redacted = RedactedVmTraceReceipt {
        transaction_id: receipt.transaction_id.clone(),
        contract_name: receipt.contract_name.clone(),
        status: receipt.status.clone(),
        timestamp: receipt.timestamp.clone(),
        target_views: receipt.target_views.clone(),
        selected_slot_keys,
        outputs_digest: outputs_digest.clone(),
        diagnostics_digest: diagnostics_digest.clone(),
    };
    let _ = write_redacted_receipt(&redacted);

    // 7. Run playback for the normalized observation (TIVF-P10-3, TIVF-P10-4, TIVF-P10-5)
    let playback_res = play_trace_playback(app, vec![observation], generate_proof_fixture, history_state)?;

    // 8. Generate and write out/trace_adapter_projection_summary.json (TIVF-P9-3)
    let projections: Vec<ProjectionSummaryEntry> = playback_res.steps.iter().map(|step| {
        ProjectionSummaryEntry {
            view_id: step.view_id.clone(),
            projected_keys: step.accepted_keys.clone(),
        }
    }).collect();

    let summary = TraceAdapterProjectionSummary {
        playback_id: playback_res.playback_id.clone(),
        transaction_id: receipt.transaction_id.clone(),
        contract_name: receipt.contract_name.clone(),
        timestamp: playback_res.timestamp.clone(),
        success: playback_res.success,
        projections,
    };
    let _ = write_projection_summary(&summary);

    // 9. Generate and write out/trace_adapter_redaction_summary.json (TIVF-P10-6, TIVF-P10-7)
    let redaction_summary = TraceAdapterRedactionSummary {
        transaction_id: receipt.transaction_id.clone(),
        contract_name: receipt.contract_name.clone(),
        timestamp: playback_res.timestamp.clone(),
        outputs_digest: outputs_digest.clone(),
        diagnostics_digest: diagnostics_digest.clone(),
        redaction_policy: "redacted-trace-receipt-v0".to_string(),
        files_written: vec![
            "tauri_playback_receipt.json".to_string(),
            "vm_trace_adapter_input_receipt.json".to_string(),
            "trace_adapter_projection_summary.json".to_string(),
            "tauri_trace_receipt.json".to_string(),
            "trace_adapter_redaction_summary.json".to_string(),
        ],
    };
    let _ = write_redaction_summary(&redaction_summary);

    Ok(playback_res)
}

#[derive(Serialize)]
pub struct RedactedVmTraceReceipt {
    pub transaction_id: String,
    pub contract_name: String,
    pub status: String,
    pub timestamp: String,
    pub target_views: Option<Vec<String>>,
    pub selected_slot_keys: Vec<String>,
    pub outputs_digest: String,
    pub diagnostics_digest: String,
}

fn write_redacted_receipt(receipt: &RedactedVmTraceReceipt) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("vm_trace_adapter_input_receipt.json");
    let json = serde_json::to_string_pretty(receipt).unwrap_or_default();
    std::fs::write(path, json)
}

#[derive(Serialize)]
pub struct ProjectionSummaryEntry {
    pub view_id: String,
    pub projected_keys: Vec<String>,
}

#[derive(Serialize)]
pub struct TraceAdapterProjectionSummary {
    pub playback_id: String,
    pub transaction_id: String,
    pub contract_name: String,
    pub timestamp: String,
    pub success: bool,
    pub projections: Vec<ProjectionSummaryEntry>,
}

fn write_projection_summary(summary: &TraceAdapterProjectionSummary) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("trace_adapter_projection_summary.json");
    let json = serde_json::to_string_pretty(summary).unwrap_or_default();
    std::fs::write(path, json)
}

#[derive(Serialize)]
pub struct TraceAdapterRedactionSummary {
    pub transaction_id: String,
    pub contract_name: String,
    pub timestamp: String,
    pub outputs_digest: String,
    pub diagnostics_digest: String,
    pub redaction_policy: String,
    pub files_written: Vec<String>,
}

fn write_redaction_summary(summary: &TraceAdapterRedactionSummary) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/out");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("trace_adapter_redaction_summary.json");
    let json = serde_json::to_string_pretty(summary).unwrap_or_default();
    std::fs::write(path, json)
}

fn write_vm_trace_fixture(receipt: &VmTraceReceipt) -> std::io::Result<()> {
    let out_path = resolve_workspace_path("igniter-view-engine/fixtures");
    let _ = std::fs::create_dir_all(&out_path);
    let path = out_path.join("vm_execution_trace_receipt.json");
    let json = serde_json::to_string_pretty(receipt).unwrap_or_default();
    std::fs::write(path, json)
}

#[tauri::command]
pub fn get_telemetry_history(
    state: tauri::State<'_, TelemetryHistoryState>,
) -> Result<Vec<RedactedTraceReceipt>, String> {
    let history = state.0.lock();
    Ok(history.clone())
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct ExternalTraceEnvelope {
    pub trace_id: Option<String>,
    pub contract_id: Option<String>,
    pub status: Option<String>,
    pub timestamp: Option<String>,
    pub producer_id: Option<String>,
    pub view_ids: Option<Vec<String>>,
    pub outputs: Option<serde_json::Value>,
    pub diagnostics: Option<serde_json::Value>,
    pub slot_values: Option<serde_json::Value>,
    pub passport_signature: Option<String>,
}

fn push_and_emit_redacted_stub<R: tauri::Runtime>(
    app: &tauri::AppHandle<R>,
    history_state: &TelemetryHistoryState,
    redacted: RedactedTraceReceipt,
) {
    use tauri::Emitter;
    let history_snapshot = {
        let mut history = history_state.0.lock();
        history.push(redacted);
        while history.len() > 10 {
            history.remove(0);
        }
        history.clone()
    };
    let _ = write_telemetry_history_summary(&history_snapshot);
    let _ = app.emit("telemetry-history-updated", &history_snapshot);
}

pub fn ingest_external_trace_event_inner<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    payload_json: String,
    history_state: &TelemetryHistoryState,
) -> Result<RedactedTraceReceipt, String> {
    use tauri::Emitter;

    let timestamp = chrono::Local::now().to_rfc3339();
    let receipt_id = uuid::Uuid::new_v4().to_string();

    // 1. Fail-closed size limit (65536 bytes)
    if payload_json.len() > 65536 {
        let redacted = RedactedTraceReceipt {
            trace_id: "oversized_trace".to_string(),
            contract_id: "unknown_contract".to_string(),
            status: "failed: payload oversized".to_string(),
            timestamp,
            target_views: None,
            selected_slot_keys: vec![],
            outputs_digest: "sha256:rejected_payload".to_string(),
            diagnostics_digest: "sha256:rejected_payload".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            receipt_id: Some(receipt_id),
            event_type: "attempted_trace_events".to_string(),
        };
        push_and_emit_redacted_stub(&app, history_state, redacted);
        return Err("Payload size exceeds 65536 bytes limit".to_string());
    }

    // 2. Parse envelope
    let envelope: ExternalTraceEnvelope = match serde_json::from_str(&payload_json) {
        Ok(env) => env,
        Err(e) => {
            let redacted = RedactedTraceReceipt {
                trace_id: "malformed_trace".to_string(),
                contract_id: "unknown_contract".to_string(),
                status: format!("failed: json parse error: {}", e),
                timestamp,
                target_views: None,
                selected_slot_keys: vec![],
                outputs_digest: "sha256:malformed_payload".to_string(),
                diagnostics_digest: "sha256:malformed_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err(format!("Malformed JSON envelope: {}", e));
        }
    };

    let trace_id = envelope.trace_id.clone().unwrap_or_else(|| "missing_trace_id".to_string());
    let contract_id = envelope.contract_id.clone().unwrap_or_else(|| "missing_contract_id".to_string());
    let status = envelope.status.clone().unwrap_or_else(|| "failed".to_string());

    // 3. Signature & Producer Verification (fail-closed)
    let is_unauthorized_producer = match envelope.producer_id.as_deref() {
        Some("ruby-vm-runner-v1.0") | Some("mock-producer-p14") => false,
        _ => true,
    };

    let is_invalid_signature = match envelope.passport_signature.as_deref() {
        Some("valid-mock-signature") => false,
        _ => true,
    };

    if is_unauthorized_producer || is_invalid_signature {
        let status_msg = if is_unauthorized_producer {
            "failed: unauthorized producer".to_string()
        } else {
            "failed: invalid signature".to_string()
        };

        let redacted = RedactedTraceReceipt {
            trace_id,
            contract_id,
            status: status_msg,
            timestamp,
            target_views: envelope.view_ids.clone(),
            selected_slot_keys: vec![],
            outputs_digest: "sha256:unauthorized_payload".to_string(),
            diagnostics_digest: "sha256:unauthorized_payload".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            receipt_id: Some(receipt_id),
            event_type: "attempted_trace_events".to_string(),
        };

        push_and_emit_redacted_stub(&app, history_state, redacted);
        return Err("Unauthorized ingress: missing or invalid signature or producer".to_string());
    }

    // 4. Redaction of raw data
    let outputs_str = serde_json::to_string(&envelope.outputs.unwrap_or(serde_json::Value::Null)).unwrap_or_default();
    let mut hasher_out = sha2::Sha256::new();
    hasher_out.update(outputs_str.as_bytes());
    let outputs_digest = format!("sha256:{:x}", hasher_out.finalize());

    let diag_str = serde_json::to_string(&envelope.diagnostics.unwrap_or(serde_json::Value::Null)).unwrap_or_default();
    let mut hasher_diag = sha2::Sha256::new();
    hasher_diag.update(diag_str.as_bytes());
    let diagnostics_digest = format!("sha256:{:x}", hasher_diag.finalize());

    let selected_slot_keys: Vec<String> = match envelope.slot_values.as_ref().and_then(|v| v.as_object()) {
        Some(obj) => obj.keys().cloned().collect(),
        None => Vec::new(),
    };

    let event_type = if status == "success" {
        "applied_trace_events".to_string()
    } else {
        "attempted_trace_events".to_string()
    };

    let redacted = RedactedTraceReceipt {
        trace_id: trace_id.clone(),
        contract_id: contract_id.clone(),
        status,
        timestamp,
        target_views: envelope.view_ids.clone(),
        selected_slot_keys,
        outputs_digest,
        diagnostics_digest,
        redaction_policy: "redacted-trace-receipt-v0".to_string(),
        receipt_id: Some(receipt_id),
        event_type,
    };

    push_and_emit_redacted_stub(&app, history_state, redacted.clone());

    Ok(redacted)
}

#[tauri::command]
pub fn ingest_external_trace_event(
    app: tauri::AppHandle,
    payload_json: String,
    history_state: tauri::State<'_, TelemetryHistoryState>,
) -> Result<RedactedTraceReceipt, String> {
    ingest_external_trace_event_inner(app, payload_json, &history_state)
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct VmTraceAdapterEnvelopeV0 {
    pub transaction_id: Option<String>,
    pub contract_name: Option<String>,
    pub status: Option<String>,
    pub timestamp: Option<String>,
    pub producer_id: Option<String>,
    pub target_views: Option<Vec<String>>,
    pub outputs: Option<serde_json::Value>,
    pub diagnostics: Option<serde_json::Value>,
    pub slot_values: Option<serde_json::Value>,
    pub passport_signature: Option<String>,
}

#[tauri::command]
pub fn ingest_adapted_vm_trace(
    app: tauri::AppHandle,
    payload_json: String,
    history_state: tauri::State<'_, TelemetryHistoryState>,
) -> Result<RedactedTraceReceipt, String> {
    ingest_adapted_vm_trace_inner(app, payload_json, &history_state)
}

pub fn ingest_adapted_vm_trace_inner<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    payload_json: String,
    history_state: &TelemetryHistoryState,
) -> Result<RedactedTraceReceipt, String> {
    let timestamp = chrono::Local::now().to_rfc3339();
    let receipt_id = uuid::Uuid::new_v4().to_string();

    // 1. Fail-closed size limit (65536 bytes)
    if payload_json.len() > 65536 {
        let redacted = RedactedTraceReceipt {
            trace_id: "oversized_trace".to_string(),
            contract_id: "unknown_contract".to_string(),
            status: "failed: payload oversized".to_string(),
            timestamp,
            target_views: None,
            selected_slot_keys: vec![],
            outputs_digest: "sha256:rejected_payload".to_string(),
            diagnostics_digest: "sha256:rejected_payload".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            receipt_id: Some(receipt_id),
            event_type: "attempted_trace_events".to_string(),
        };
        push_and_emit_redacted_stub(&app, history_state, redacted);
        return Err("Payload size exceeds 65536 bytes limit".to_string());
    }

    // 2. Parse envelope
    let envelope: VmTraceAdapterEnvelopeV0 = match serde_json::from_str(&payload_json) {
        Ok(env) => env,
        Err(e) => {
            let redacted = RedactedTraceReceipt {
                trace_id: "malformed_trace".to_string(),
                contract_id: "unknown_contract".to_string(),
                status: format!("failed: json parse error: {}", e),
                timestamp,
                target_views: None,
                selected_slot_keys: vec![],
                outputs_digest: "sha256:malformed_payload".to_string(),
                diagnostics_digest: "sha256:malformed_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err(format!("Malformed JSON envelope: {}", e));
        }
    };

    let transaction_id = envelope.transaction_id.clone().unwrap_or_else(|| "missing_transaction_id".to_string());
    let contract_name = envelope.contract_name.clone().unwrap_or_else(|| "missing_contract_name".to_string());
    let incoming_status = envelope.status.clone().unwrap_or_else(|| "unknown".to_string());

    // 3. Status vocabulary check and mapping (fail-closed for ingress_rejected and unknown status)
    let mapped_status = match incoming_status.as_str() {
        "applied" => "success".to_string(),
        "execution_failed" => "failed: execution_failed".to_string(),
        "diagnostic_only" => "failed: diagnostic_only".to_string(),
        "partial" => "failed: partial".to_string(),
        "ingress_rejected" => {
            let redacted = RedactedTraceReceipt {
                trace_id: transaction_id.clone(),
                contract_id: contract_name.clone(),
                status: "failed: ingress_rejected".to_string(),
                timestamp: timestamp.clone(),
                target_views: envelope.target_views.clone(),
                selected_slot_keys: vec![],
                outputs_digest: "sha256:ingress_rejected_payload".to_string(),
                diagnostics_digest: "sha256:ingress_rejected_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err("Ingress rejected: ingress_rejected status vocabulary".to_string());
        }
        unknown_status => {
            let redacted = RedactedTraceReceipt {
                trace_id: transaction_id.clone(),
                contract_id: contract_name.clone(),
                status: format!("failed: unknown_status: {}", unknown_status),
                timestamp: timestamp.clone(),
                target_views: envelope.target_views.clone(),
                selected_slot_keys: vec![],
                outputs_digest: "sha256:invalid_status_payload".to_string(),
                diagnostics_digest: "sha256:invalid_status_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err(format!("Unknown status vocabulary: {}", unknown_status));
        }
    };

    // 4. Map fields into ExternalTraceEnvelope
    let mapped_ext_payload = ExternalTraceEnvelope {
        trace_id: Some(transaction_id),
        contract_id: Some(contract_name),
        status: Some(mapped_status),
        timestamp: envelope.timestamp.clone(),
        producer_id: envelope.producer_id.clone(),
        view_ids: envelope.target_views.clone(),
        outputs: envelope.outputs.clone(),
        diagnostics: envelope.diagnostics.clone(),
        slot_values: envelope.slot_values.clone(),
        passport_signature: envelope.passport_signature.clone(),
    };

    let serialized_ext_payload = serde_json::to_string(&mapped_ext_payload).unwrap_or_default();

    // Delegate verification, size checking, and eviction/redaction to the P14 ingress logic
    ingest_external_trace_event_inner(app, serialized_ext_payload, history_state)
}

// Mock VM runner trace fixture builder
pub fn build_mock_vm_runner_trace_payload(
    transaction_id: &str,
    status: &str,
    producer_id: &str,
    signature: &str,
) -> String {
    serde_json::json!({
        "transaction_id": transaction_id,
        "contract_name": "test_contract",
        "status": status,
        "timestamp": "2026-06-06T13:00:00Z",
        "producer_id": producer_id,
        "target_views": ["test_view"],
        "outputs": { "result": "mock-runner-output" },
        "diagnostics": { "warnings": ["mock-runner-warning"] },
        "slot_values": { "key_a": "value_a", "key_b": "value_b" },
        "passport_signature": signature
    }).to_string()
}

pub fn run_mock_vm_runner_dispatch_inner<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    transaction_id: String,
    status: String,
    producer_id: String,
    signature: String,
    history_state: &TelemetryHistoryState,
) -> Result<RedactedTraceReceipt, String> {
    let payload = build_mock_vm_runner_trace_payload(&transaction_id, &status, &producer_id, &signature);
    ingest_adapted_vm_trace_inner(app, payload, history_state)
}

#[tauri::command]
pub fn run_mock_vm_runner_dispatch(
    app: tauri::AppHandle,
    transaction_id: String,
    status: String,
    producer_id: String,
    signature: String,
    history_state: tauri::State<'_, TelemetryHistoryState>,
) -> Result<RedactedTraceReceipt, String> {
    run_mock_vm_runner_dispatch_inner(app, transaction_id, status, producer_id, signature, &history_state)
}

#[tauri::command]
pub fn run_session_telemetry_dispatch(
    app: tauri::AppHandle,
    status: String,
    history_state: tauri::State<'_, TelemetryHistoryState>,
    session_state: tauri::State<'_, ActiveSessionState>,
) -> Result<RedactedTraceReceipt, String> {
    run_session_telemetry_dispatch_inner(app, status, &history_state, &session_state)
}

pub fn run_session_telemetry_dispatch_inner<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    status: String,
    history_state: &TelemetryHistoryState,
    session_state: &ActiveSessionState,
) -> Result<RedactedTraceReceipt, String> {
    let session_token = uuid::Uuid::new_v4().to_string();
    let transaction_id = format!("tx_session_{}", uuid::Uuid::new_v4());

    // 1. Initialize transient session state
    {
        let mut session = session_state.0.lock();
        session.session_token = Some(session_token.clone());
        session.transaction_id = Some(transaction_id.clone());
        session.created_at = Some(chrono::Local::now());
    }

    // 2. Spawn local Ruby mock runner proof script synchronously
    let ruby_script_path = resolve_workspace_path("igniter-view-engine/run_mock_session_runner_hmac_proof.rb");
    
    // Determine if status is 'oversized' or other flags
    let is_oversized = status == "oversized";
    let status_arg = if is_oversized { "applied" } else { &status };

    let output = std::process::Command::new("ruby")
        .arg(&ruby_script_path)
        .arg(&session_token)
        .arg(&transaction_id)
        .arg(status_arg)
        .arg(if is_oversized { "true" } else { "false" })
        .current_dir(resolve_workspace_path("igniter-view-engine"))
        .output()
        .map_err(|e| format!("Failed to spawn Ruby runner: {}", e))?;

    if !output.status.success() {
        // Clear session state on launch failure
        {
            let mut session = session_state.0.lock();
            *session = ActiveSession::default();
        }
        return Err(format!(
            "Ruby runner exited with error: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    // 3. Read signed envelope output file
    let filename = format!("ruby_session_ingress_envelope_{}.json", transaction_id);
    let envelope_path = resolve_workspace_path("igniter-view-engine/out").join(filename);
    if !envelope_path.exists() {
        {
            let mut session = session_state.0.lock();
            *session = ActiveSession::default();
        }
        return Err("Missing signed telemetry envelope".to_string());
    }

    let payload_json = std::fs::read_to_string(&envelope_path)
        .map_err(|e| format!("Failed to read envelope file: {}", e))?;
    let _ = std::fs::remove_file(envelope_path);

    // 4. Validate and ingest
    let result = validate_and_ingest_session_envelope(app, payload_json, history_state, session_state);
    
    // 5. Invalidate/Clear session state in all code paths (ensured by returning result)
    {
        let mut session = session_state.0.lock();
        *session = ActiveSession::default();
    }

    result
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct IntrospectionBounds {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct IntrospectionNode {
    pub id: String,
    pub r#type: String,
    pub parent: Option<String>,
    pub z_index: i32,
    pub computed_bounds: Option<IntrospectionBounds>,
    pub slot_bound: bool,
    pub referenced_slots: Vec<String>,
    pub scoped_slots: Vec<String>,
    pub containment: String,
    pub overflow_allowance: String,
    pub allow_structural_overwrites: bool,
    pub status: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct IntrospectionReceipt {
    pub view_id: String,
    pub scene_digest: String,
    pub node_count: i64,
    pub nodes: HashMap<String, IntrospectionNode>,
    pub non_claims: Vec<String>,
}

#[tauri::command]
pub fn read_introspection_receipt(
    path: String,
    workspace_dir: String,
) -> Result<IntrospectionReceipt, String> {
    read_introspection_receipt_inner(path, workspace_dir)
}

pub fn read_introspection_receipt_inner(
    path: String,
    workspace_dir: String,
) -> Result<IntrospectionReceipt, String> {
    let ws_path = Path::new(&workspace_dir).canonicalize()
        .map_err(|e| format!("Failed to resolve workspace path '{}': {}", workspace_dir, e))?;
    let file_path = Path::new(&path).canonicalize()
        .map_err(|e| format!("Failed to resolve introspection receipt path '{}': {}", path, e))?;

    if !file_path.starts_with(&ws_path) {
        return Err("Path traversal check failed: receipt file lies outside workspace boundary.".to_string());
    }

    let metadata = fs::metadata(&file_path)
        .map_err(|e| format!("Failed to get receipt file metadata: {}", e))?;
    let size = metadata.len();
    if size > 65536 {
        return Err(format!("Oversized receipt payload ({} > 65536 bytes)", size));
    }

    let content = fs::read_to_string(&file_path)
        .map_err(|e| format!("Failed to read receipt file: {}", e))?;

    let receipt: IntrospectionReceipt = serde_json::from_str(&content)
        .map_err(|e| format!("Malformed receipt JSON structure: {}", e))?;

    for (node_id, node) in &receipt.nodes {
        if node.id != *node_id {
            return Err(format!("Mismatched node ID in metadata keys for '{}'", node_id));
        }
        if !["contained", "overflow", "N/A"].contains(&node.containment.as_str()) {
            return Err(format!("Invalid containment value in '{}': '{}'", node_id, node.containment));
        }
        if !["allow", "clip", "none"].contains(&node.overflow_allowance.as_str()) {
            return Err(format!("Invalid overflow_allowance value in '{}': '{}'", node_id, node.overflow_allowance));
        }
        if !["active", "skip"].contains(&node.status.as_str()) {
            return Err(format!("Invalid status value in '{}': '{}'", node_id, node.status));
        }
    }

    Ok(receipt)
}

pub fn validate_and_ingest_session_envelope<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    payload_json: String,
    history_state: &TelemetryHistoryState,
    session_state: &ActiveSessionState,
) -> Result<RedactedTraceReceipt, String> {
    let timestamp = chrono::Local::now().to_rfc3339();
    let receipt_id = uuid::Uuid::new_v4().to_string();

    // 1. Check size limit
    if payload_json.len() > 65536 {
        let redacted = RedactedTraceReceipt {
            trace_id: "oversized_trace".to_string(),
            contract_id: "unknown_contract".to_string(),
            status: "failed: payload oversized".to_string(),
            timestamp,
            target_views: None,
            selected_slot_keys: vec![],
            outputs_digest: "sha256:rejected_payload".to_string(),
            diagnostics_digest: "sha256:rejected_payload".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            receipt_id: Some(receipt_id),
            event_type: "attempted_trace_events".to_string(),
        };
        push_and_emit_redacted_stub(&app, history_state, redacted);
        return Err("Payload size exceeds 65536 bytes limit".to_string());
    }

    // 2. Parse envelope
    let envelope: VmTraceAdapterEnvelopeV0 = match serde_json::from_str(&payload_json) {
        Ok(env) => env,
        Err(e) => {
            let redacted = RedactedTraceReceipt {
                trace_id: "malformed_trace".to_string(),
                contract_id: "unknown_contract".to_string(),
                status: format!("failed: json parse error: {}", e),
                timestamp,
                target_views: None,
                selected_slot_keys: vec![],
                outputs_digest: "sha256:malformed_payload".to_string(),
                diagnostics_digest: "sha256:malformed_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err(format!("Malformed JSON envelope: {}", e));
        }
    };

    let transaction_id = envelope.transaction_id.clone().unwrap_or_else(|| "missing_transaction_id".to_string());
    let contract_name = envelope.contract_name.clone().unwrap_or_else(|| "missing_contract_name".to_string());
    let incoming_status = envelope.status.clone().unwrap_or_else(|| "unknown".to_string());

    // 3. Verify Session State (existence, transaction_id, timeout)
    let session = session_state.0.lock().clone();
    let session_token = match session.session_token {
        Some(t) => t,
        None => {
            let redacted = RedactedTraceReceipt {
                trace_id: transaction_id.clone(),
                contract_id: contract_name.clone(),
                status: "failed: stale or missing session".to_string(),
                timestamp,
                target_views: envelope.target_views.clone(),
                selected_slot_keys: vec![],
                outputs_digest: "sha256:no_session_payload".to_string(),
                diagnostics_digest: "sha256:no_session_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err("Stale or missing session".to_string());
        }
    };

    // Check transaction_id match
    if session.transaction_id.as_deref() != Some(&transaction_id) {
        let redacted = RedactedTraceReceipt {
            trace_id: transaction_id.clone(),
            contract_id: contract_name.clone(),
            status: "failed: transaction_id mismatch".to_string(),
            timestamp,
            target_views: envelope.target_views.clone(),
            selected_slot_keys: vec![],
            outputs_digest: "sha256:transaction_mismatch_payload".to_string(),
            diagnostics_digest: "sha256:transaction_mismatch_payload".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            receipt_id: Some(receipt_id),
            event_type: "attempted_trace_events".to_string(),
        };
        push_and_emit_redacted_stub(&app, history_state, redacted);
        return Err("Transaction ID mismatch".to_string());
    }

    // Check timeout (5 seconds limit)
    if let Some(created_at) = session.created_at {
        let duration = chrono::Local::now().signed_duration_since(created_at);
        if duration.num_seconds() > 5 {
            let redacted = RedactedTraceReceipt {
                trace_id: transaction_id.clone(),
                contract_id: contract_name.clone(),
                status: "failed: session timed out".to_string(),
                timestamp,
                target_views: envelope.target_views.clone(),
                selected_slot_keys: vec![],
                outputs_digest: "sha256:timeout_payload".to_string(),
                diagnostics_digest: "sha256:timeout_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err("Session timed out".to_string());
        }
    }

    // 4. Verify HMAC-SHA256 Signature
    if let Err(e) = verify_envelope_hmac(&envelope, &session_token) {
        let redacted = RedactedTraceReceipt {
            trace_id: transaction_id.clone(),
            contract_id: contract_name.clone(),
            status: format!("failed: hmac verification failed: {}", e),
            timestamp,
            target_views: envelope.target_views.clone(),
            selected_slot_keys: vec![],
            outputs_digest: "sha256:invalid_signature_payload".to_string(),
            diagnostics_digest: "sha256:invalid_signature_payload".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            receipt_id: Some(receipt_id),
            event_type: "attempted_trace_events".to_string(),
        };
        push_and_emit_redacted_stub(&app, history_state, redacted);
        return Err(format!("Invalid signature: {}", e));
    }

    // 5. Ingress checks on status vocabulary
    let mapped_status = match incoming_status.as_str() {
        "applied" => "success".to_string(),
        "execution_failed" => "failed: execution_failed".to_string(),
        "diagnostic_only" => "failed: diagnostic_only".to_string(),
        "partial" => "failed: partial".to_string(),
        unknown_status => {
            let redacted = RedactedTraceReceipt {
                trace_id: transaction_id.clone(),
                contract_id: contract_name.clone(),
                status: format!("failed: unknown_status: {}", unknown_status),
                timestamp: timestamp.clone(),
                target_views: envelope.target_views.clone(),
                selected_slot_keys: vec![],
                outputs_digest: "sha256:invalid_status_payload".to_string(),
                diagnostics_digest: "sha256:invalid_status_payload".to_string(),
                redaction_policy: "redacted-trace-receipt-v0".to_string(),
                receipt_id: Some(receipt_id),
                event_type: "attempted_trace_events".to_string(),
            };
            push_and_emit_redacted_stub(&app, history_state, redacted);
            return Err(format!("Unknown status vocabulary: {}", unknown_status));
        }
    };

    // 6. Map and delegate verification & redaction to external trace helper
    let mapped_ext_payload = ExternalTraceEnvelope {
        trace_id: Some(transaction_id),
        contract_id: Some(contract_name),
        status: Some(mapped_status),
        timestamp: envelope.timestamp.clone(),
        producer_id: envelope.producer_id.clone(),
        view_ids: envelope.target_views.clone(),
        outputs: envelope.outputs.clone(),
        diagnostics: envelope.diagnostics.clone(),
        slot_values: envelope.slot_values.clone(),
        passport_signature: envelope.passport_signature.clone(),
    };

    // Bypass signature check in ingest_external_trace_event_inner since we just verified it via HMAC-SHA256
    let mut bypass_payload = mapped_ext_payload;
    bypass_payload.passport_signature = Some("valid-mock-signature".to_string());

    let serialized_ext_payload = serde_json::to_string(&bypass_payload).unwrap_or_default();
    ingest_external_trace_event_inner(app, serialized_ext_payload, history_state)
}


#[cfg(test)]
mod tests {
    use super::*;
    use tauri::Manager;

    #[test]
    fn test_telemetry_history_packet_generation_and_eviction() {
        let history_state = TelemetryHistoryState(Mutex::new(Vec::new()));

        // 1. Generate 11 trace events to verify capacity = 10 and FIFO eviction
        for i in 0..11 {
            let status = if i % 2 == 0 { "success".to_string() } else { "failed".to_string() };
            let obs = MockObservation {
                trace_id: format!("tx_mock_trace_{}", i),
                contract_id: "test_contract".to_string(),
                status,
                outputs: serde_json::json!({ "result": i }),
                diagnostics: serde_json::json!({ "warnings": [] }),
                slot_values: serde_json::json!({ "key_a": i, "key_b": "value" }),
                view_id: Some("test_view".to_string()),
                view_ids: None,
            };

            let res = write_trace_receipt(&obs, Some(false), &history_state);
            assert!(res.is_ok());
        }

        // Check history state
        let history = history_state.0.lock();
        assert_eq!(history.len(), 10);
        // The first event (tx_mock_trace_0) should be evicted (FIFO)
        assert_eq!(history[0].trace_id, "tx_mock_trace_1");
        assert_eq!(history[9].trace_id, "tx_mock_trace_10");

        // Verify wording and classification
        // tx_mock_trace_1 had status "failed", so event_type should be attempted_trace_events
        assert_eq!(history[0].event_type, "attempted_trace_events");
        // tx_mock_trace_10 had status "success", so event_type should be applied_trace_events
        assert_eq!(history[9].event_type, "applied_trace_events");

        // Verify redacted-only compliance: no raw outputs, diagnostics, slot_values, local paths, or local file URL links
        for entry in history.iter() {
            let serialized = serde_json::to_string(&entry).unwrap();
            assert!(!serialized.contains("result"));
            assert!(!serialized.contains("warnings"));
            assert!(!serialized.contains("value"));
            assert!(!serialized.contains("Users"));
            assert!(!serialized.contains(&format!("{}://", "file")));
        }

        // 2. Materialize the remaining receipt files under out/ using helper functions
        // Write playback receipt
        let playback = PlaybackReceipt {
            playback_id: "mock_playback_123".to_string(),
            timestamp: chrono::Local::now().to_rfc3339(),
            success: true,
            message: "Playback successfully applied all steps".to_string(),
            steps: vec![CommandReceipt {
                success: true,
                message: "Applied".to_string(),
                view_id: "test_view".to_string(),
                rejected_keys: vec![],
                accepted_keys: vec!["key_a".to_string(), "key_b".to_string()],
                timestamp: chrono::Local::now().to_rfc3339(),
                receipt_id: "rcpt_123".to_string(),
                source_receipt_id: Some("tx_mock_trace_10".to_string()),
            }],
        };
        assert!(write_playback_receipt(&playback).is_ok());

        // Write vm trace adapter input receipt
        let vm_trace_input = RedactedVmTraceReceipt {
            transaction_id: "tx_mock_trace_10".to_string(),
            contract_name: "test_contract".to_string(),
            status: "success".to_string(),
            timestamp: chrono::Local::now().to_rfc3339(),
            target_views: Some(vec!["test_view".to_string()]),
            selected_slot_keys: vec!["key_a".to_string(), "key_b".to_string()],
            outputs_digest: "sha256:mock_outputs_digest".to_string(),
            diagnostics_digest: "sha256:mock_diagnostics_digest".to_string(),
        };
        assert!(write_redacted_receipt(&vm_trace_input).is_ok());

        // Write trace adapter projection summary
        let proj_summary = TraceAdapterProjectionSummary {
            playback_id: "mock_playback_123".to_string(),
            transaction_id: "tx_mock_trace_10".to_string(),
            contract_name: "test_contract".to_string(),
            timestamp: chrono::Local::now().to_rfc3339(),
            success: true,
            projections: vec![ProjectionSummaryEntry {
                view_id: "test_view".to_string(),
                projected_keys: vec!["key_a".to_string(), "key_b".to_string()],
            }],
        };
        assert!(write_projection_summary(&proj_summary).is_ok());

        // Write trace adapter redaction summary
        let redact_summary = TraceAdapterRedactionSummary {
            transaction_id: "tx_mock_trace_10".to_string(),
            contract_name: "test_contract".to_string(),
            timestamp: chrono::Local::now().to_rfc3339(),
            outputs_digest: "sha256:mock_outputs_digest".to_string(),
            diagnostics_digest: "sha256:mock_diagnostics_digest".to_string(),
            redaction_policy: "redacted-trace-receipt-v0".to_string(),
            files_written: vec![
                "tauri_playback_receipt.json".to_string(),
                "vm_trace_adapter_input_receipt.json".to_string(),
                "trace_adapter_projection_summary.json".to_string(),
                "tauri_trace_receipt.json".to_string(),
                "trace_adapter_redaction_summary.json".to_string(),
            ],
        };
        assert!(write_redaction_summary(&redact_summary).is_ok());
    }

    #[test]
    fn test_external_trace_ingress() {
        let app = tauri::test::mock_app();
        app.manage(TelemetryHistoryState(Mutex::new(Vec::new())));
        let handle = app.handle();
        let history_state = handle.state::<TelemetryHistoryState>();

        // TIVF-P14-1: valid signed mock event is accepted and redacted
        let valid_payload = serde_json::json!({
            "trace_id": "tx_valid_123",
            "contract_id": "test_contract",
            "status": "success",
            "producer_id": "ruby-vm-runner-v1.0",
            "passport_signature": "valid-mock-signature",
            "view_ids": ["test_view"],
            "outputs": { "result": "unredacted-outputs-data" },
            "diagnostics": { "warnings": ["unredacted-diagnostics-warnings"] },
            "slot_values": { "key_x": "unredacted-slot-value-x", "key_y": "unredacted-slot-value-y" }
        }).to_string();

        let res = ingest_external_trace_event_inner(handle.clone(), valid_payload, &*history_state);
        assert!(res.is_ok());
        let receipt = res.unwrap();
        assert_eq!(receipt.trace_id, "tx_valid_123");
        assert_eq!(receipt.event_type, "applied_trace_events");

        // TIVF-P14-7: raw outputs/diagnostics/slot_values never appear in receipts
        let serialized = serde_json::to_string(&receipt).unwrap();
        assert!(!serialized.contains("unredacted-outputs-data"));
        assert!(!serialized.contains("unredacted-diagnostics-warnings"));
        assert!(!serialized.contains("unredacted-slot-value-x"));
        assert!(!serialized.contains("unredacted-slot-value-y"));

        // TIVF-P14-8: selected slot keys are retained without raw values
        assert!(receipt.selected_slot_keys.contains(&"key_x".to_string()));
        assert!(receipt.selected_slot_keys.contains(&"key_y".to_string()));

        // TIVF-P14-2: missing signature fails closed
        let missing_sig_payload = serde_json::json!({
            "trace_id": "tx_missing_sig",
            "contract_id": "test_contract",
            "status": "success",
            "producer_id": "ruby-vm-runner-v1.0",
            "view_ids": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {}
        }).to_string();
        let res = ingest_external_trace_event_inner(handle.clone(), missing_sig_payload, &*history_state);
        assert!(res.is_err());

        // TIVF-P14-3: invalid signature fails closed
        let invalid_sig_payload = serde_json::json!({
            "trace_id": "tx_invalid_sig",
            "contract_id": "test_contract",
            "status": "success",
            "producer_id": "ruby-vm-runner-v1.0",
            "passport_signature": "invalid-sig",
            "view_ids": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {}
        }).to_string();
        let res = ingest_external_trace_event_inner(handle.clone(), invalid_sig_payload, &*history_state);
        assert!(res.is_err());

        // TIVF-P14-4: unauthorized producer fails closed
        let unauthorized_prod_payload = serde_json::json!({
            "trace_id": "tx_unauth_prod",
            "contract_id": "test_contract",
            "status": "success",
            "producer_id": "malicious-producer",
            "passport_signature": "valid-mock-signature",
            "view_ids": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {}
        }).to_string();
        let res = ingest_external_trace_event_inner(handle.clone(), unauthorized_prod_payload, &*history_state);
        assert!(res.is_err());

        // TIVF-P14-5: malformed envelope fails closed with no state mutation
        let prev_len = history_state.0.lock().len();
        let malformed_payload = "{ malformed json }".to_string();
        let res = ingest_external_trace_event_inner(handle.clone(), malformed_payload, &*history_state);
        assert!(res.is_err());
        assert_eq!(history_state.0.lock().len(), prev_len + 1);
        assert_eq!(history_state.0.lock().last().unwrap().event_type, "attempted_trace_events");

        // TIVF-P14-6: payload over 65536 bytes fails closed before redaction
        let mut oversized_payload = String::new();
        for _ in 0..70000 {
            oversized_payload.push('a');
        }
        let res = ingest_external_trace_event_inner(handle.clone(), oversized_payload, &*history_state);
        assert!(res.is_err());
        assert_eq!(history_state.0.lock().last().unwrap().event_type, "attempted_trace_events");
        assert_eq!(history_state.0.lock().last().unwrap().trace_id, "oversized_trace");

        // TIVF-P14-10: burst backpressure keeps bounded latest history
        for i in 0..15 {
            let p = serde_json::json!({
                "trace_id": format!("tx_burst_{}", i),
                "contract_id": "test_contract",
                "status": "success",
                "producer_id": "ruby-vm-runner-v1.0",
                "passport_signature": "valid-mock-signature",
                "view_ids": ["test_view"],
                "outputs": {},
                "diagnostics": {},
                "slot_values": {}
            }).to_string();
            let _ = ingest_external_trace_event_inner(handle.clone(), p, &*history_state);
        }
        {
            let history = history_state.0.lock();
            assert_eq!(history.len(), 10);
            assert_eq!(history[0].trace_id, "tx_burst_5");
            assert_eq!(history[9].trace_id, "tx_burst_14");

            // TIVF-P14-11: applied vs attempted classification is correct
            assert_eq!(history[0].event_type, "applied_trace_events");
        }

        // Push an attempted trace (failed status)
        let failed_payload = serde_json::json!({
            "trace_id": "tx_failed_status",
            "contract_id": "test_contract",
            "status": "failed_execution",
            "producer_id": "ruby-vm-runner-v1.0",
            "passport_signature": "valid-mock-signature",
            "view_ids": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {}
        }).to_string();
        let res = ingest_external_trace_event_inner(handle.clone(), failed_payload, &*history_state);
        assert!(res.is_ok());
        let failed_receipt = res.unwrap();
        assert_eq!(failed_receipt.event_type, "attempted_trace_events");

        // TIVF-P14-14: no local absolute paths leak into result packets
        {
            let history = history_state.0.lock();
            for entry in history.iter() {
                let serialized = serde_json::to_string(&entry).unwrap();
                assert!(!serialized.contains("Users"));
                assert!(!serialized.contains(&format!("{}://", "file")));
            }
        }
        println!("test_external_trace_ingress COMPLETE");
    }

    #[test]
    fn test_adapted_vm_trace_ingress() {
        let app = tauri::test::mock_app();
        app.manage(TelemetryHistoryState(Mutex::new(Vec::new())));
        let handle = app.handle();
        let history_state = handle.state::<TelemetryHistoryState>();

        // TIVF-P15-1: Valid adapter envelope payload with 'applied' status is accepted and mapped
        let valid_payload = serde_json::json!({
            "transaction_id": "tx_adapted_applied",
            "contract_name": "test_contract",
            "status": "applied",
            "timestamp": "2026-06-06T12:00:00Z",
            "producer_id": "ruby-vm-runner-v1.0",
            "target_views": ["test_view"],
            "outputs": { "result": "unredacted-applied-outputs" },
            "diagnostics": { "warnings": [] },
            "slot_values": { "key_val": "secret-value" },
            "passport_signature": "valid-mock-signature"
        }).to_string();

        let res = ingest_adapted_vm_trace_inner(handle.clone(), valid_payload, &*history_state);
        assert!(res.is_ok());
        let receipt = res.unwrap();
        assert_eq!(receipt.trace_id, "tx_adapted_applied");
        assert_eq!(receipt.status, "success");
        assert_eq!(receipt.event_type, "applied_trace_events");
        assert!(receipt.selected_slot_keys.contains(&"key_val".to_string()));

        // Verification of redaction-by-default for slot values, outputs, and diagnostics
        let serialized = serde_json::to_string(&receipt).unwrap();
        assert!(!serialized.contains("unredacted-applied-outputs"));
        assert!(!serialized.contains("secret-value"));

        // Status Vocabulary Mappings
        let mappings = vec![
            ("execution_failed", "failed: execution_failed", "attempted_trace_events"),
            ("diagnostic_only", "failed: diagnostic_only", "attempted_trace_events"),
            ("partial", "failed: partial", "attempted_trace_events"),
        ];

        for (incoming, expected_mapped, expected_event_type) in mappings {
            let payload = serde_json::json!({
                "transaction_id": format!("tx_adapted_{}", incoming),
                "contract_name": "test_contract",
                "status": incoming,
                "producer_id": "ruby-vm-runner-v1.0",
                "target_views": ["test_view"],
                "outputs": {},
                "diagnostics": {},
                "slot_values": {},
                "passport_signature": "valid-mock-signature"
            }).to_string();

            let res = ingest_adapted_vm_trace_inner(handle.clone(), payload, &*history_state);
            assert!(res.is_ok());
            let receipt = res.unwrap();
            assert_eq!(receipt.status, expected_mapped);
            assert_eq!(receipt.event_type, expected_event_type);
        }

        // Ingress rejected status fails closed and registers attempted event with status failed: ingress_rejected
        let rejected_payload = serde_json::json!({
            "transaction_id": "tx_adapted_rejected",
            "contract_name": "test_contract",
            "status": "ingress_rejected",
            "producer_id": "ruby-vm-runner-v1.0",
            "target_views": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {},
            "passport_signature": "valid-mock-signature"
        }).to_string();
        let res = ingest_adapted_vm_trace_inner(handle.clone(), rejected_payload, &*history_state);
        assert!(res.is_err());
        {
            let history = history_state.0.lock();
            let last = history.last().unwrap();
            assert_eq!(last.trace_id, "tx_adapted_rejected");
            assert_eq!(last.status, "failed: ingress_rejected");
            assert_eq!(last.event_type, "attempted_trace_events");
        }

        // Unknown status fails closed and registers attempted event with status failed: unknown_status
        let unknown_payload = serde_json::json!({
            "transaction_id": "tx_adapted_unknown",
            "contract_name": "test_contract",
            "status": "crash_and_burn",
            "producer_id": "ruby-vm-runner-v1.0",
            "target_views": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {},
            "passport_signature": "valid-mock-signature"
        }).to_string();
        let res = ingest_adapted_vm_trace_inner(handle.clone(), unknown_payload, &*history_state);
        assert!(res.is_err());

        // Verify that unknown status was pushed to history as attempted
        {
            let history = history_state.0.lock();
            let last = history.last().unwrap();
            assert_eq!(last.trace_id, "tx_adapted_unknown");
            assert_eq!(last.status, "failed: unknown_status: crash_and_burn");
            assert_eq!(last.event_type, "attempted_trace_events");
        }

        // Invalid signature/producer rejection
        let invalid_sig_payload = serde_json::json!({
            "transaction_id": "tx_adapted_invalid_sig",
            "contract_name": "test_contract",
            "status": "applied",
            "producer_id": "ruby-vm-runner-v1.0",
            "target_views": ["test_view"],
            "outputs": {},
            "diagnostics": {},
            "slot_values": {},
            "passport_signature": "invalid-sig"
        }).to_string();
        let res = ingest_adapted_vm_trace_inner(handle.clone(), invalid_sig_payload, &*history_state);
        assert!(res.is_err());

        // Burst backpressure & FIFO capacity-10 eviction
        for i in 0..15 {
            let payload = serde_json::json!({
                "transaction_id": format!("tx_burst_{}", i),
                "contract_name": "test_contract",
                "status": "applied",
                "producer_id": "ruby-vm-runner-v1.0",
                "target_views": ["test_view"],
                "outputs": {},
                "diagnostics": {},
                "slot_values": {},
                "passport_signature": "valid-mock-signature"
            }).to_string();
            let _ = ingest_adapted_vm_trace_inner(handle.clone(), payload, &*history_state);
        }

        {
            let history = history_state.0.lock();
            assert_eq!(history.len(), 10);
            // Verify FIFO behavior: older items evicted, keeping latest 10
            assert_eq!(history[0].trace_id, "tx_burst_5");
            assert_eq!(history[9].trace_id, "tx_burst_14");

            // Verify zero local absolute paths and no local file URL protocols leak
            for entry in history.iter() {
                let serialized = serde_json::to_string(&entry).unwrap();
                assert!(!serialized.contains("Users"));
                assert!(!serialized.contains(&format!("{}://", "file")));
            }
        }
    }

    #[test]
    fn test_mock_vm_runner_trace_ingress() {
        let app = tauri::test::mock_app();
        app.manage(TelemetryHistoryState(Mutex::new(Vec::new())));
        let handle = app.handle();
        let history_state = handle.state::<TelemetryHistoryState>();

        // TIVF-P16-1: Mock runner fixture is accepted and returns Ok
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_applied".to_string(),
            "applied".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "valid-mock-signature".to_string(),
            &history_state,
        );
        assert!(res.is_ok());
        let receipt = res.unwrap();

        // TIVF-P16-2: Applied trace maps to success and applied_trace_events history
        assert_eq!(receipt.trace_id, "tx_p16_applied");
        assert_eq!(receipt.status, "success");
        assert_eq!(receipt.event_type, "applied_trace_events");

        // TIVF-P16-9: Raw outputs, diagnostics, slot values are never persisted
        let serialized = serde_json::to_string(&receipt).unwrap();
        assert!(!serialized.contains("mock-runner-output"));
        assert!(!serialized.contains("mock-runner-warning"));
        assert!(!serialized.contains("value_a"));
        assert!(!serialized.contains("value_b"));
        // Slot values retained as keys only
        assert!(receipt.selected_slot_keys.contains(&"key_a".to_string()));
        assert!(receipt.selected_slot_keys.contains(&"key_b".to_string()));

        // TIVF-P16-3: execution_failed is verified non-applied (returns Ok, attempted)
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_failed".to_string(),
            "execution_failed".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "valid-mock-signature".to_string(),
            &history_state,
        );
        assert!(res.is_ok());
        let receipt = res.unwrap();
        assert_eq!(receipt.status, "failed: execution_failed");
        assert_eq!(receipt.event_type, "attempted_trace_events");

        // TIVF-P16-4: diagnostic_only is verified non-applied (returns Ok, attempted)
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_diag".to_string(),
            "diagnostic_only".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "valid-mock-signature".to_string(),
            &history_state,
        );
        assert!(res.is_ok());
        let receipt = res.unwrap();
        assert_eq!(receipt.status, "failed: diagnostic_only");
        assert_eq!(receipt.event_type, "attempted_trace_events");

        // TIVF-P16-5: partial is verified non-applied (returns Ok, attempted)
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_partial".to_string(),
            "partial".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "valid-mock-signature".to_string(),
            &history_state,
        );
        assert!(res.is_ok());
        let receipt = res.unwrap();
        assert_eq!(receipt.status, "failed: partial");
        assert_eq!(receipt.event_type, "attempted_trace_events");

        // TIVF-P16-6: ingress_rejected is classified as rejected ingress (fails closed, returns Err)
        let prev_len = history_state.0.lock().len();
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_rejected".to_string(),
            "ingress_rejected".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "valid-mock-signature".to_string(),
            &history_state,
        );
        assert!(res.is_err());
        // Check that history logged it as attempted trace event
        {
            let history = history_state.0.lock();
            assert_eq!(history.len(), prev_len + 1);
            let last = history.last().unwrap();
            assert_eq!(last.trace_id, "tx_p16_rejected");
            assert_eq!(last.status, "failed: ingress_rejected");
            assert_eq!(last.event_type, "attempted_trace_events");
        }

        // TIVF-P16-7: Unknown status fails closed (returns Err)
        let prev_len = history_state.0.lock().len();
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_unknown".to_string(),
            "crash_and_burn".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "valid-mock-signature".to_string(),
            &history_state,
        );
        assert!(res.is_err());
        {
            let history = history_state.0.lock();
            assert_eq!(history.len(), prev_len + 1);
            let last = history.last().unwrap();
            assert_eq!(last.trace_id, "tx_p16_unknown");
            assert_eq!(last.status, "failed: unknown_status: crash_and_burn");
            assert_eq!(last.event_type, "attempted_trace_events");
        }

        // TIVF-P16-8: Invalid producer/signature fails closed (returns Err)
        let res = run_mock_vm_runner_dispatch_inner(
            handle.clone(),
            "tx_p16_invalid_sig".to_string(),
            "applied".to_string(),
            "ruby-vm-runner-v1.0".to_string(),
            "invalid-signature".to_string(),
            &history_state,
        );
        assert!(res.is_err());

        // TIVF-P16-10: FIFO history remains bounded at 10
        for i in 0..15 {
            let _ = run_mock_vm_runner_dispatch_inner(
                handle.clone(),
                format!("tx_burst_p16_{}", i),
                "applied".to_string(),
                "ruby-vm-runner-v1.0".to_string(),
                "valid-mock-signature".to_string(),
                &history_state,
            );
        }

        {
            let history = history_state.0.lock();
            assert_eq!(history.len(), 10);
            assert_eq!(history[0].trace_id, "tx_burst_p16_5");
            assert_eq!(history[9].trace_id, "tx_burst_p16_14");

            // TIVF-P16-13: No local home paths or local file URL leaks in result packets
            for entry in history.iter() {
                let serialized = serde_json::to_string(&entry).unwrap();
                assert!(!serialized.contains("Users"));
                assert!(!serialized.contains(&format!("{}://", "file")));
            }
        }
    }

    #[test]
    fn test_ruby_vm_telemetry_preflight_envelope() {
        let app = tauri::test::mock_app();
        app.manage(TelemetryHistoryState(Mutex::new(Vec::new())));
        let handle = app.handle();
        let history_state = handle.state::<TelemetryHistoryState>();

        let envelope_path = resolve_workspace_path("igniter-view-engine/out/ruby_telemetry_ingress_envelope.json");
        assert!(envelope_path.exists(), "Preflight envelope file must exist. Run the ruby script first.");

        let payload_json = std::fs::read_to_string(envelope_path).unwrap();

        let res = ingest_adapted_vm_trace_inner(handle.clone(), payload_json, &history_state);
        assert!(res.is_ok(), "Failed to ingest Ruby preflight envelope");
        let receipt = res.unwrap();

        assert_eq!(receipt.trace_id, "tx_preflight_ruby_18");
        assert_eq!(receipt.status, "success");
        assert_eq!(receipt.event_type, "applied_trace_events");

        // Verify that raw contents are redacted in receipt
        let serialized = serde_json::to_string(&receipt).unwrap();
        assert!(!serialized.contains("VCON-4a"));
        assert!(!serialized.contains("Blocked unsafe/disallowed tag"));
        assert!(!serialized.contains("Users"));
        assert!(!serialized.contains(&format!("{}://", "file")));
    }

    #[test]
    fn test_cross_language_hmac_test_vector() {
        let key = b"test-secret-token-123";
        let message = b"{\"contract_name\":\"test_contract\",\"diagnostics\":{},\"outputs\":{},\"producer_id\":\"ruby-vm-runner-v1.0\",\"slot_values\":{},\"status\":\"applied\",\"target_views\":[\"test_view\"],\"timestamp\":\"2026-06-06T12:00:00Z\",\"transaction_id\":\"tx_test_123\"}";
        let sig_bytes = hmac_sha256(key, message);
        let sig_hex = sig_bytes.iter().map(|b| format!("{:02x}", b)).collect::<String>();
        assert_eq!(sig_hex, "dae26cc34b75477fc3fff817426cd8b7b063bde73cf501749459c5229548df23");
    }

    #[test]
    fn test_mock_session_runner_lifecycle_success() {
        let app = tauri::test::mock_app();
        app.manage(TelemetryHistoryState(Mutex::new(Vec::new())));
        app.manage(ActiveSessionState(Mutex::new(ActiveSession::default())));
        let handle = app.handle();
        let history_state = handle.state::<TelemetryHistoryState>();
        let session_state = handle.state::<ActiveSessionState>();

        // TIVF-P20-1: Successful session execution
        let res = run_session_telemetry_dispatch_inner(handle.clone(), "applied".to_string(), &history_state, &session_state);
        assert!(res.is_ok(), "Session dispatch failed: {:?}", res.err());
        let receipt = res.unwrap();
        
        assert_eq!(receipt.status, "success");
        assert_eq!(receipt.event_type, "applied_trace_events");

        // TIVF-P20-2: Verify session state has been cleaned/invalidated
        let session = session_state.0.lock().clone();
        assert!(session.session_token.is_none());
        assert!(session.transaction_id.is_none());
    }

    #[test]
    fn test_mock_session_runner_rejections() {
        let app = tauri::test::mock_app();
        app.manage(TelemetryHistoryState(Mutex::new(Vec::new())));
        app.manage(ActiveSessionState(Mutex::new(ActiveSession::default())));
        let handle = app.handle();
        let history_state = handle.state::<TelemetryHistoryState>();
        let session_state = handle.state::<ActiveSessionState>();

        // Helper to trigger Ruby runner directly and return the payload json
        let run_ruby = |token: &str, tx_id: &str, status: &str, oversized: bool| -> String {
            let ruby_script_path = resolve_workspace_path("igniter-view-engine/run_mock_session_runner_hmac_proof.rb");
            let output = std::process::Command::new("ruby")
                .arg(&ruby_script_path)
                .arg(token)
                .arg(tx_id)
                .arg(status)
                .arg(if oversized { "true" } else { "false" })
                .current_dir(resolve_workspace_path("igniter-view-engine"))
                .output()
                .unwrap();
            assert!(output.status.success());
            let filename = format!("ruby_session_ingress_envelope_{}.json", tx_id);
            let envelope_path = resolve_workspace_path("igniter-view-engine/out").join(filename);
            let content = std::fs::read_to_string(&envelope_path).unwrap();
            let _ = std::fs::remove_file(envelope_path);
            content
        };

        // 1. Wrong token / Invalid signature rejection
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_1".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                session.created_at = Some(chrono::Local::now());
            }

            // Ruby signs with wrong token
            let payload = run_ruby("wrong-token", &transaction_id, "applied", false);
            let res = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("Invalid signature"));
        }

        // 2. Wrong transaction ID rejection
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_correct".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                session.created_at = Some(chrono::Local::now());
            }

            // Ruby payload contains wrong transaction_id
            let payload = run_ruby(&session_token, "tx_session_wrong", "applied", false);
            let res = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("Transaction ID mismatch"));
        }

        // 3. Stale session (timeout > 5 seconds) rejection
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_timeout".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                // Mock creation time to 10 seconds ago
                session.created_at = Some(chrono::Local::now() - chrono::Duration::seconds(10));
            }

            let payload = run_ruby(&session_token, &transaction_id, "applied", false);
            let res = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("Session timed out"));
        }

        // 4. Replay attack rejection (token removed after first ingest, second ingest fails)
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_replay".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                session.created_at = Some(chrono::Local::now());
            }

            let payload = run_ruby(&session_token, &transaction_id, "applied", false);
            
            // First ingest passes
            let res1 = validate_and_ingest_session_envelope(handle.clone(), payload.clone(), &history_state, &session_state);
            assert!(res1.is_ok());

            // Clear session state
            {
                let mut session = session_state.0.lock();
                *session = ActiveSession::default();
            }

            // Second ingest fails
            let res2 = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res2.is_err());
            assert!(res2.unwrap_err().contains("Stale or missing session"));
        }

        // 5. Oversized payload rejection
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_oversized".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                session.created_at = Some(chrono::Local::now());
            }

            let payload = run_ruby(&session_token, &transaction_id, "applied", true);
            let res = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("Payload size exceeds"));
        }

        // 6. Unknown status rejection
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_unknown_status".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                session.created_at = Some(chrono::Local::now());
            }

            let payload = run_ruby(&session_token, &transaction_id, "crash_and_burn", false);
            let res = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("Unknown status"));
        }

        // 7. Unsigned payload rejection
        {
            let session_token = "correct-token".to_string();
            let transaction_id = "tx_session_unsigned".to_string();
            {
                let mut session = session_state.0.lock();
                session.session_token = Some(session_token.clone());
                session.transaction_id = Some(transaction_id.clone());
                session.created_at = Some(chrono::Local::now());
            }

            let payload = run_ruby(&session_token, &transaction_id, "unsigned", false);
            let res = validate_and_ingest_session_envelope(handle.clone(), payload, &history_state, &session_state);
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("Missing passport_signature"));
        }
    }

    #[test]
    fn test_read_introspection_receipt_all_cases() {
        let ws_dir = resolve_workspace_path("");
        let ws_dir_str = ws_dir.to_string_lossy().to_string();

        // 1. Success path
        let receipt_path = resolve_workspace_path("igniter-gui-engine/out/scene_introspection_receipt.json");
        let receipt_path_str = receipt_path.to_string_lossy().to_string();

        let res = read_introspection_receipt_inner(receipt_path_str, ws_dir_str.clone());
        assert!(res.is_ok(), "Failed to read scene_introspection_receipt: {:?}", res.err());
        let receipt = res.unwrap();
        assert_eq!(receipt.view_id, "igniter.lab.dashboard");
        assert_eq!(receipt.node_count, 7);
        assert!(receipt.nodes.contains_key("root"));
        assert_eq!(receipt.nodes.get("root").unwrap().containment, "N/A");

        // 2. Path traversal rejection
        let temp_dir = std::env::temp_dir();
        let outside_file = temp_dir.join("outside_test.json");
        let _ = fs::write(&outside_file, "{}");
        if let Ok(canon_outside) = outside_file.canonicalize() {
            let res_traversal = read_introspection_receipt_inner(
                canon_outside.to_string_lossy().to_string(),
                ws_dir_str.clone()
            );
            assert!(res_traversal.is_err());
            assert!(res_traversal.unwrap_err().contains("Path traversal check failed"));
        }
        let _ = fs::remove_file(outside_file);

        // 3. Oversized payload rejection (> 65KB)
        let oversized_path = resolve_workspace_path("igniter-gui-engine/out/temp_oversized.json");
        let oversized_path_str = oversized_path.to_string_lossy().to_string();
        let mut large_content = String::new();
        for _ in 0..70000 {
            large_content.push('x');
        }
        let _ = fs::write(&oversized_path, large_content);
        let res_oversized = read_introspection_receipt_inner(oversized_path_str, ws_dir_str.clone());
        assert!(res_oversized.is_err());
        assert!(res_oversized.unwrap_err().contains("Oversized receipt payload"));
        let _ = fs::remove_file(oversized_path);

        // 4. Malformed JSON rejection
        let malformed_path = resolve_workspace_path("igniter-gui-engine/out/temp_malformed.json");
        let malformed_path_str = malformed_path.to_string_lossy().to_string();
        let _ = fs::write(&malformed_path, "{ malformed json }");
        let res_malformed = read_introspection_receipt_inner(malformed_path_str, ws_dir_str.clone());
        assert!(res_malformed.is_err());
        assert!(res_malformed.unwrap_err().contains("Malformed receipt JSON structure"));
        let _ = fs::remove_file(malformed_path);

        // 5. Schema validation rejection
        let invalid_schema_path = resolve_workspace_path("igniter-gui-engine/out/temp_invalid_schema.json");
        let invalid_schema_path_str = invalid_schema_path.to_string_lossy().to_string();
        let invalid_json = serde_json::json!({
            "view_id": "test",
            "scene_digest": "sha256:digest",
            "node_count": 1,
            "nodes": {
                "root": {
                    "id": "root",
                    "type": "container",
                    "parent": null,
                    "z_index": 0,
                    "computed_bounds": null,
                    "slot_bound": false,
                    "referenced_slots": [],
                    "scoped_slots": [],
                    "containment": "invalid_containment_val",
                    "overflow_allowance": "none",
                    "allow_structural_overwrites": false,
                    "status": "active"
                }
            },
            "non_claims": []
        }).to_string();
        let _ = fs::write(&invalid_schema_path, invalid_json);
        let res_schema = read_introspection_receipt_inner(invalid_schema_path_str, ws_dir_str.clone());
        assert!(res_schema.is_err());
        assert!(res_schema.unwrap_err().contains("Invalid containment value"));
        let _ = fs::remove_file(invalid_schema_path);
    }
}

