use serde_json::Value;
use std::collections::HashMap;

pub struct ContractRegistry {
    pub contracts: HashMap<String, Value>,
    /// User-defined record type shapes from the compiled program's `type_env`
    /// (LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILIATION-P7). Keyed by type name → a JSON object of
    /// `{ field_name: type_ir }`, where `type_ir` is the typechecker's `{ "name": "...", "params": [...] }`
    /// shape. This is metadata the typechecker ALREADY computes (`TypedProgram.type_env`) but the assembler
    /// previously discarded — persisting it here lets host code reconcile a continuation's declared
    /// `Collection[<AppRow>]` row type against its read policy without re-parsing authored `.ig` source.
    pub type_defs: HashMap<String, Value>,
}

impl ContractRegistry {
    pub fn new() -> Self {
        Self {
            contracts: HashMap::new(),
            type_defs: HashMap::new(),
        }
    }

    pub fn register(&mut self, name: String, bytecode: Value) {
        self.contracts.insert(name, bytecode);
    }

    pub fn get(&self, name: &str) -> Option<&Value> {
        self.contracts.get(name)
    }

    pub fn len(&self) -> usize {
        self.contracts.len()
    }

    pub fn all(&self) -> impl Iterator<Item = (&String, &Value)> {
        self.contracts.iter()
    }

    /// Persist one user-defined type's field shape (`{ field_name: type_ir }`). Idempotent per name.
    pub fn register_type_def(&mut self, name: String, fields: Value) {
        self.type_defs.insert(name, fields);
    }

    /// The field shape of a user-defined type (`{ field_name: { "name": ..., "params": [...] } }`), if known.
    pub fn type_def(&self, name: &str) -> Option<&Value> {
        self.type_defs.get(name)
    }
}
