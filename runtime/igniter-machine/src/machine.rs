use crate::backend::{InMemoryBackend, RemoteTcpBackend, RocksDBBackend, TBackend};
use crate::bridge::MachineVMBackendAdapter;
use crate::errors::EngineError;
use crate::fact::{Fact, Observation};
use crate::registry::ContractRegistry;
use crate::wal::WALWriter;

use parking_lot::RwLock;
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use igniter_compiler::assembler::Assembler;
use igniter_compiler::classifier::Classifier;
use igniter_compiler::emitter::Emitter;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::monomorphizer::monomorphize_program;
use igniter_compiler::multifile;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

use igniter_vm::compiler::Compiler as VMCompiler;
use igniter_vm::value::Value as VMValue;
use igniter_vm::vm::VM;

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
struct SemanticImage {
    magic: String,
    version: String,
    // BTreeMap (not HashMap) so a capsule serializes deterministically → byte-identical
    // roundtrip (a capsule is an immutable frame; same content = same bytes).
    contracts: BTreeMap<String, serde_json::Value>,
    facts: Vec<Fact>,
    observations: Vec<Observation>,
}

pub struct IgniterMachine {
    pub storage: Arc<dyn TBackend>,
    pub wal: Option<Arc<WALWriter>>,
    pub registry: Arc<RwLock<ContractRegistry>>,
    pub observations: Arc<RwLock<Vec<Observation>>>,
    pub backend_label: String,
}

impl IgniterMachine {
    pub fn new(data_dir: Option<PathBuf>, backend_type: &str) -> Result<Self, EngineError> {
        let registry = Arc::new(RwLock::new(ContractRegistry::new()));
        let observations = Arc::new(RwLock::new(Vec::new()));

        let storage: Arc<dyn TBackend> = match backend_type {
            "in_memory" => Arc::new(InMemoryBackend::new()),
            "rocksdb" => {
                let path = data_dir.clone().unwrap_or_else(|| PathBuf::from("./data"));
                Arc::new(RocksDBBackend::new(path)?)
            }
            "remote_tcp" => {
                let addr = "127.0.0.1:7419".to_string();
                Arc::new(RemoteTcpBackend::new(addr))
            }
            other if other.starts_with("remote_tcp:") => {
                let addr = other.trim_start_matches("remote_tcp:").to_string();
                Arc::new(RemoteTcpBackend::new(addr))
            }
            _ => {
                return Err(EngineError::StorageError(format!(
                    "Unknown backend type: {}",
                    backend_type
                )))
            }
        };

        let wal = if let Some(dir) = &data_dir {
            let wal_path = dir.join("machine.wal");
            let wal_writer = Arc::new(WALWriter::new(&wal_path)?);
            let replayed_facts = wal_writer.replay()?;
            for fact in replayed_facts {
                futures::executor::block_on(storage.write_fact(fact))?;
            }
            Some(wal_writer)
        } else {
            None
        };

        Ok(Self {
            storage,
            wal,
            registry,
            observations,
            backend_label: backend_type.to_string(),
        })
    }

    pub fn backend_type(&self) -> &str {
        &self.backend_label
    }

    pub fn load_contract_source(
        &self,
        source_code: &str,
        contract_name: &str,
    ) -> Result<(), EngineError> {
        let mut lexer = Lexer::new(source_code);
        let tokens = lexer.tokenize();

        let mut parser = Parser::new(tokens);
        let mut parsed = parser.parse();
        if !parsed.parse_errors.is_empty() {
            return Err(EngineError::CompilationError(format!(
                "Parse errors: {:?}",
                parsed.parse_errors
            )));
        }

        monomorphize_program(&mut parsed);

        let classifier = Classifier::new();
        let sample_input = serde_json::json!({});
        let classified = classifier.classify(&parsed, &sample_input);
        if classified.pass_result != "ok" {
            return Err(EngineError::CompilationError(format!(
                "Classification failed: {:?}",
                classified.oof_log
            )));
        }

        let typechecker = TypeChecker::new();
        let typed = typechecker.typecheck(&classified, &parsed.functions);
        if typed.pass_result != "ok" {
            return Err(EngineError::CompilationError(format!(
                "Typechecking failed: {:?}",
                typed.type_errors
            )));
        }

        // Persist the user-defined type shapes the typechecker computed (LAB-IGNITER-DATA-PROJECTION-
        // BOOT-RECONCILIATION-P7). `type_env` maps a type name → `{ field: type_ir }`; the assembler does
        // not carry it into the registered contract JSON, so host code that needs to reconcile a
        // continuation's `Collection[<AppRow>]` row type against a read policy could not otherwise recover
        // the row's field types without re-parsing `.ig`. Purely additive metadata — no compile semantics.
        {
            let mut reg = self.registry.write();
            for (type_name, fields) in &typed.type_env {
                let fields_json = serde_json::to_value(fields).unwrap_or(serde_json::Value::Null);
                reg.register_type_def(type_name.clone(), fields_json);
            }
        }

        let emitter = Emitter::new();
        let emit_res = emitter.emit_typed(&typed);

        let assembler = Assembler::new();
        let temp_dir =
            std::env::temp_dir().join(format!("igniter_compile_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&temp_dir).map_err(|e| EngineError::IOError(e.to_string()))?;

        let _manifest = assembler
            .assemble(&emit_res, temp_dir.to_str().unwrap())
            .map_err(|e| EngineError::CompilationError(e.to_string()))?;

        // Register EVERY contract compiled from this source (not just the named one),
        // so cross-contract callees are available for dispatch's dispatch_table.
        let contracts_dir = temp_dir.join("contracts");
        let mut registered_named = false;
        if let Ok(entries) = std::fs::read_dir(&contracts_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) != Some("json") {
                    continue;
                }
                let content = std::fs::read_to_string(&path)
                    .map_err(|e| EngineError::IOError(e.to_string()))?;
                let contract_json: serde_json::Value = serde_json::from_str(&content)
                    .map_err(|e| EngineError::SerializationError(e.to_string()))?;
                // Register by the authoritative contract_name field (the file is
                // snake_cased by the assembler, e.g. `add.json`, but call_contract and
                // dispatch use the declared name, e.g. `Add`).
                let key = contract_json
                    .get("contract_name")
                    .or_else(|| contract_json.get("name"))
                    .and_then(|n| n.as_str())
                    .map(|s| s.to_string())
                    .unwrap_or_default();
                if key.is_empty() {
                    continue;
                }
                if key == contract_name {
                    registered_named = true;
                }
                self.registry.write().register(key, contract_json);
            }
        }

        let _ = std::fs::remove_dir_all(&temp_dir);

        if !registered_named {
            return Err(EngineError::CompilationError(format!(
                "Compiled contract file not found for {}",
                contract_name
            )));
        }
        Ok(())
    }

    /// Multi-file load: resolve a set of `.ig` source files (module decls + imports)
    /// into one merged program, then compile + register all its contracts. Lets the
    /// machine run real multi-file apps, not just single-source contracts.
    pub fn load_program(
        &self,
        source_paths: &[String],
        contract_name: &str,
    ) -> Result<(), EngineError> {
        let merged = match multifile::compile_units(source_paths)
            .map_err(|e| EngineError::IOError(e.to_string()))?
        {
            Ok(m) => m,
            Err(diags) => {
                let msgs: Vec<String> = diags.iter().map(|d| d.message.clone()).collect();
                return Err(EngineError::CompilationError(format!(
                    "Multifile resolve errors: {:?}",
                    msgs
                )));
            }
        };
        // The merged source is a single self-contained program string; reuse the
        // existing single-source pipeline (which registers every contract).
        self.load_contract_source(&merged.source, contract_name)
    }

    /// Compile source for diagnostics only — does NOT register the contract.
    /// Returns list of (rule, message, severity, line, col) tuples.
    pub fn check_source(
        source_code: &str,
    ) -> Vec<(String, String, String, Option<u32>, Option<u32>)> {
        let mut lexer = Lexer::new(source_code);
        let tokens = lexer.tokenize();

        let mut parser = Parser::new(tokens);
        let mut parsed = parser.parse();

        let mut diags: Vec<(String, String, String, Option<u32>, Option<u32>)> = Vec::new();

        // Parse errors
        for e in &parsed.parse_errors {
            let severity = if e.severity == "error" {
                "error"
            } else {
                "warning"
            };
            diags.push((
                e.rule.clone(),
                e.message.clone(),
                severity.to_string(),
                Some(e.line as u32),
                Some(e.col as u32),
            ));
        }

        if parsed.parse_errors.iter().any(|e| e.severity == "error") {
            return diags;
        }

        monomorphize_program(&mut parsed);

        let classifier = Classifier::new();
        let classified = classifier.classify(&parsed, &serde_json::json!({}));

        // OOF log from classifier (ClassifierDiagnostic: rule, message, node, line — no col, no severity)
        for oof in &classified.oof_log {
            diags.push((
                oof.rule.clone(),
                oof.message.clone(),
                "error".to_string(),
                oof.line.map(|l| l as u32),
                None,
            ));
        }

        let typechecker = TypeChecker::new();
        let typed = typechecker.typecheck(&classified, &parsed.functions);

        // Type errors (ClassifierDiagnostic: rule, message, node, line — no col, no severity)
        for e in &typed.type_errors {
            diags.push((
                e.rule.clone(),
                e.message.clone(),
                if e.rule.starts_with("OOF-") {
                    "error"
                } else {
                    "warning"
                }
                .to_string(),
                e.line.map(|l| l as u32),
                None,
            ));
        }

        diags
    }

    pub async fn dispatch(
        &self,
        contract_name: &str,
        inputs: serde_json::Value,
    ) -> Result<serde_json::Value, EngineError> {
        let contract_json = {
            let registry_lock = self.registry.read();
            registry_lock.get(contract_name).cloned()
        };

        let contract_json = match contract_json {
            Some(c) => c,
            None => return Err(EngineError::NotFound),
        };

        let mut vm_compiler = VMCompiler::new();
        let compiled_contract = vm_compiler
            .compile(&contract_json)
            .map_err(|e| EngineError::VMExecutionError(e))?;

        let adapter = Arc::new(MachineVMBackendAdapter::new(
            self.storage.clone(),
            self.observations.clone(),
        ));
        let mut vm = VM::new(Some(adapter));

        // Populate the VM dispatch table from all registered contracts so
        // call_contract resolves cross-contract callees (mirrors the CLI's main.rs).
        {
            let registry_lock = self.registry.read();
            let mut entry_compiler = VMCompiler::new();
            for (name, cj) in registry_lock.all() {
                if let Ok(entry) = entry_compiler.build_dispatch_entry(cj, name) {
                    vm.dispatch_table.insert(name.clone(), entry);
                }
            }
        }

        let mut vm_inputs = HashMap::new();
        if let Some(obj) = inputs.as_object() {
            for (k, v) in obj {
                vm_inputs.insert(k.clone(), VMValue::from_json(v));
            }
        }

        let mut temporal_context = HashMap::new();
        // Setup contract modifier inside inputs/temporal_context
        let modifier = contract_json
            .get("modifier")
            .and_then(|m| m.as_str())
            .unwrap_or("pure");
        temporal_context.insert(
            "contract_modifier".to_string(),
            VMValue::String(Arc::from(modifier)),
        );

        let output_val = vm
            .execute(&compiled_contract, &vm_inputs, &temporal_context)
            .await
            .map_err(|e| EngineError::VMExecutionError(e))?;

        Ok(output_val.to_json())
    }

    pub async fn write_fact(&self, fact: Fact) -> Result<(), EngineError> {
        if let Some(ref wal) = self.wal {
            wal.append(&fact)?;
        }
        self.storage.write_fact(fact).await
    }

    pub async fn read_fact(
        &self,
        store: &str,
        key: &str,
        as_of: f64,
    ) -> Result<Option<Fact>, EngineError> {
        self.storage.read_as_of(store, key, as_of).await
    }

    /// Bitemporal point query — `valid_at` (effective axis) + `known_at` (audit axis).
    /// See `TBackend::read_bitemporal`. `read_fact`/`read_as_of` stay transaction-time only.
    pub async fn read_bitemporal(
        &self,
        store: &str,
        key: &str,
        valid_at: Option<f64>,
        known_at: Option<f64>,
    ) -> Result<Option<Fact>, EngineError> {
        self.storage
            .read_bitemporal(store, key, valid_at, known_at)
            .await
    }

    /// Serialize the full machine state (contracts + facts + observations) into a
    /// capsule (`.igm`) byte image. Deterministic: contracts via BTreeMap, facts sorted
    /// by (store, key, transaction_time, id), so the same frame yields the same bytes.
    pub async fn checkpoint_bytes(&self) -> Result<Vec<u8>, EngineError> {
        let contracts: BTreeMap<String, serde_json::Value> = self
            .registry
            .read()
            .contracts
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        let observations = self.observations.read().clone();
        let mut facts = self.storage.all_facts().await?;
        facts.sort_by(|a, b| {
            (
                a.store.as_str(),
                a.key.as_str(),
                a.transaction_time,
                a.id.as_str(),
            )
                .partial_cmp(&(
                    b.store.as_str(),
                    b.key.as_str(),
                    b.transaction_time,
                    b.id.as_str(),
                ))
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        let image = SemanticImage {
            magic: "IGM\x01".to_string(),
            version: "0.1.0".to_string(),
            contracts,
            facts,
            observations,
        };
        rmp_serde::to_vec(&image).map_err(|e| EngineError::SerializationError(e.to_string()))
    }

    pub async fn checkpoint(&self, path: &Path) -> Result<(), EngineError> {
        let bytes = self.checkpoint_bytes().await?;
        std::fs::write(path, bytes).map_err(|e| EngineError::IOError(e.to_string()))
    }

    /// Rebuild a machine from a capsule byte image (in-memory; no file needed).
    pub async fn resume_bytes(
        bytes: &[u8],
        data_dir: Option<PathBuf>,
        backend_type: &str,
    ) -> Result<Self, EngineError> {
        let image: SemanticImage = rmp_serde::from_slice(bytes)
            .map_err(|e| EngineError::SerializationError(e.to_string()))?;

        if image.magic != "IGM\x01" {
            return Err(EngineError::SerializationError(
                "Invalid magic bytes in image".to_string(),
            ));
        }

        let machine = Self::new(data_dir, backend_type)?;

        // Restore registry
        {
            let mut reg = machine.registry.write();
            for (k, v) in image.contracts {
                reg.register(k, v);
            }
        }

        // Restore observations
        {
            let mut obs = machine.observations.write();
            *obs = image.observations;
        }

        // Restore facts into storage
        for fact in image.facts {
            machine.storage.write_fact(fact).await?;
        }

        Ok(machine)
    }

    /// Resume from a capsule file on disk (thin wrapper over `resume_bytes`).
    pub async fn resume(
        path: &Path,
        data_dir: Option<PathBuf>,
        backend_type: &str,
    ) -> Result<Self, EngineError> {
        let bytes = std::fs::read(path).map_err(|e| EngineError::IOError(e.to_string()))?;
        Self::resume_bytes(&bytes, data_dir, backend_type).await
    }
}
