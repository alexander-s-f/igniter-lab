use serde_json::Value;
use std::collections::HashMap;

pub struct ContractRegistry {
    pub contracts: HashMap<String, Value>,
}

impl ContractRegistry {
    pub fn new() -> Self {
        Self {
            contracts: HashMap::new(),
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
}
