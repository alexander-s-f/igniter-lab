use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Fact {
    pub id: String,
    pub store: String,
    pub key: String,
    pub value: serde_json::Value,
    pub value_hash: String,
    pub causation: Option<String>,
    pub transaction_time: f64,
    pub valid_time: Option<f64>,
    pub schema_version: i64,
    pub producer: Option<serde_json::Value>,
    pub derivation: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Observation {
    pub id: String,
    pub kind: String,
    pub value: serde_json::Value,
    pub timestamp: f64,
}
