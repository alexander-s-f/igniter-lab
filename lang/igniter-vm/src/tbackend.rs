// src/tbackend.rs
// Pluggable Asynchronous TBackend Trait, Memory History, and Remote TCP Ledger Adapters

use crate::value::Value;
use std::collections::HashMap;
use tokio::sync::RwLock;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

#[async_trait::async_trait]
pub trait TBackend: Send + Sync {
    async fn read_as_of(&self, store: &str, as_of: &str) -> Result<Option<Value>, String>;
    async fn append_observation(&self, obs: Value) -> Result<(), String>;
}

// -----------------------------------------------------------------------------
// 1. Memory History Backend (For local execution and testing)
// -----------------------------------------------------------------------------
pub struct MemoryHistoryBackend {
    // Maps store name to chronological timeline tuples: (as_of_timestamp, Value)
    history: RwLock<HashMap<String, Vec<(String, Value)>>>,
    // Tracks appended observations for auditing parity
    pub observation_sink: RwLock<Vec<Value>>,
}

impl MemoryHistoryBackend {
    pub fn new() -> Self {
        Self {
            history: RwLock::new(HashMap::new()),
            observation_sink: RwLock::new(Vec::new()),
        }
    }

    pub async fn write_history(&self, store: &str, as_of: &str, val: Value) {
        let mut map = self.history.write().await;
        map.entry(store.to_string())
            .or_insert_with(Vec::new)
            .push((as_of.to_string(), val));
    }
}

#[async_trait::async_trait]
impl TBackend for MemoryHistoryBackend {
    async fn read_as_of(&self, store: &str, as_of: &str) -> Result<Option<Value>, String> {
        let map = self.history.read().await;

        let timeline = if let Some(t) = map.get(store) {
            Some(t)
        } else if let Some((store_part, _)) = store.split_once('/') {
            map.get(store_part)
        } else {
            None
        };

        if let Some(timeline) = timeline {
            // Locate the latest fact valid as of the given coordinate
            let mut best_match: Option<&Value> = None;
            let mut best_ts: Option<&str> = None;
            for (ts, val) in timeline {
                if ts.as_str() <= as_of {
                    if best_ts.is_none() || ts.as_str() > best_ts.unwrap() {
                        best_ts = Some(ts.as_str());
                        best_match = Some(val);
                    }
                }
            }
            Ok(best_match.cloned())
        } else {
            Ok(None)
        }
    }

    async fn append_observation(&self, obs: Value) -> Result<(), String> {
        let mut sink = self.observation_sink.write().await;
        sink.push(obs);
        Ok(())
    }
}

// -----------------------------------------------------------------------------
// 2. Ledger TCP Backend (For remote joint operation with tbackend compiled daemon)
// -----------------------------------------------------------------------------
pub struct LedgerTcpBackend {
    pub addr: String,
}

impl LedgerTcpBackend {
    pub fn new(addr: &str) -> Self {
        Self {
            addr: addr.to_string(),
        }
    }

    pub async fn ping(&self) -> Result<bool, String> {
        let req = serde_json::json!({ "op": "ping" });
        let resp = self.send_req(req).await?;
        Ok(resp.get("pong").and_then(|v| v.as_bool()).unwrap_or(false))
    }

    pub async fn send_req(&self, req: serde_json::Value) -> Result<serde_json::Value, String> {
        let mut stream = TcpStream::connect(&self.addr)
            .await
            .map_err(|e| format!("Failed to connect to TBackend at {}: {}", self.addr, e))?;

        let body = serde_json::to_vec(&req).map_err(|e| format!("Serialization failed: {}", e))?;
        let body_len = body.len() as u32;
        let crc = crc32fast::hash(&body);

        stream
            .write_all(&body_len.to_be_bytes())
            .await
            .map_err(|e| e.to_string())?;
        stream.write_all(&body).await.map_err(|e| e.to_string())?;
        stream
            .write_all(&crc.to_be_bytes())
            .await
            .map_err(|e| e.to_string())?;

        let mut header = [0u8; 4];
        stream
            .read_exact(&mut header)
            .await
            .map_err(|e| e.to_string())?;
        let resp_len = u32::from_be_bytes(header) as usize;

        let mut resp_body = vec![0u8; resp_len];
        stream
            .read_exact(&mut resp_body)
            .await
            .map_err(|e| e.to_string())?;

        let mut crc_bytes = [0u8; 4];
        stream
            .read_exact(&mut crc_bytes)
            .await
            .map_err(|e| e.to_string())?;

        let resp_jv: serde_json::Value =
            serde_json::from_slice(&resp_body).map_err(|e| format!("JSON parse failed: {}", e))?;

        Ok(resp_jv)
    }
}

#[async_trait::async_trait]
impl TBackend for LedgerTcpBackend {
    async fn read_as_of(&self, store: &str, as_of: &str) -> Result<Option<Value>, String> {
        // Parse ISO8601 string to a float timestamp if possible, otherwise use a fallback
        let as_of_float = chrono::DateTime::parse_from_rfc3339(as_of)
            .map(|dt| dt.timestamp() as f64 + dt.timestamp_subsec_micros() as f64 / 1_000_000.0)
            .or_else(|_| {
                chrono::NaiveDateTime::parse_from_str(as_of, "%Y-%m-%d %H:%M:%S")
                    .map(|dt| dt.and_utc().timestamp() as f64)
            })
            .or_else(|_| {
                chrono::NaiveDateTime::parse_from_str(as_of, "%Y-%m-%dT%H:%M:%SZ")
                    .map(|dt| dt.and_utc().timestamp() as f64)
            })
            .unwrap_or(0.0);

        // Parse the store name. If it contains a slash (e.g. "technician/tech42"),
        // split it into the store name and the entity key.
        let (store_part, key_part) = match store.split_once('/') {
            Some((s, k)) => (s, k),
            None => (store, "global"),
        };

        let req = serde_json::json!({
            "op": "latest_for",
            "store": store_part,
            "key": key_part,
            "as_of": as_of_float
        });

        let resp = self.send_req(req).await?;
        if resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            if let Some(fact) = resp.get("fact") {
                if !fact.is_null() {
                    if let Some(val) = fact.get("value") {
                        return Ok(Some(Value::from_json(val)));
                    }
                }
            }
        }
        Ok(None)
    }

    async fn append_observation(&self, obs: Value) -> Result<(), String> {
        let req = serde_json::json!({
            "op": "write_fact",
            "fact": {
                "id": uuid::Uuid::new_v4().to_string(),
                "store": "observations",
                "key": "observation-stream",
                "value": obs.to_json(),
                "value_hash": "obs-hash-string",
                "transaction_time": chrono::Utc::now().timestamp() as f64,
                "valid_time": chrono::Utc::now().timestamp() as f64,
                "schema_version": 1
            }
        });
        self.send_req(req).await?;
        Ok(())
    }
}
