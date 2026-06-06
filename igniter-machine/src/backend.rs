use crate::errors::EngineError;
use crate::fact::Fact;
use async_trait::async_trait;
use igniter_tbackend_playground::fact::FactData;
use igniter_tbackend_playground::timeline::ShardedFactLog;
use std::path::PathBuf;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

#[async_trait]
pub trait TBackend: Send + Sync {
    async fn read_as_of(
        &self,
        store: &str,
        key: &str,
        as_of: f64,
    ) -> Result<Option<Fact>, EngineError>;
    async fn write_fact(&self, fact: Fact) -> Result<(), EngineError>;
    async fn facts_for(
        &self,
        store: &str,
        key: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Result<Vec<Fact>, EngineError>;
    async fn all_facts(&self) -> Result<Vec<Fact>, EngineError>;
}

// Helper conversions
pub fn to_fact_data(fact: Fact) -> FactData {
    FactData {
        id: fact.id,
        store: fact.store,
        key: fact.key,
        value: fact.value,
        value_hash: fact.value_hash,
        causation: fact.causation,
        transaction_time: fact.transaction_time,
        valid_time: fact.valid_time,
        schema_version: fact.schema_version,
        producer: fact.producer,
        derivation: fact.derivation,
    }
}

pub fn from_fact_data(data: FactData) -> Fact {
    Fact {
        id: data.id,
        store: data.store,
        key: data.key,
        value: data.value,
        value_hash: data.value_hash,
        causation: data.causation,
        transaction_time: data.transaction_time,
        valid_time: data.valid_time,
        schema_version: data.schema_version,
        producer: data.producer,
        derivation: data.derivation,
    }
}

// ── InMemoryBackend ──────────────────────────────────────────────────────────
pub struct InMemoryBackend {
    log: ShardedFactLog,
}

impl InMemoryBackend {
    pub fn new() -> Self {
        Self {
            log: ShardedFactLog::new(),
        }
    }
}

#[async_trait]
impl TBackend for InMemoryBackend {
    async fn read_as_of(
        &self,
        store: &str,
        key: &str,
        as_of: f64,
    ) -> Result<Option<Fact>, EngineError> {
        let opt_data = self.log.latest_for(store, key, Some(as_of));
        Ok(opt_data.map(from_fact_data))
    }

    async fn write_fact(&self, fact: Fact) -> Result<(), EngineError> {
        let data = to_fact_data(fact);
        self.log.push(data);
        Ok(())
    }

    async fn facts_for(
        &self,
        store: &str,
        key: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Result<Vec<Fact>, EngineError> {
        let list = self.log.facts_for_key(store, key, since, as_of);
        Ok(list.into_iter().map(from_fact_data).collect())
    }

    async fn all_facts(&self) -> Result<Vec<Fact>, EngineError> {
        let mut results = Vec::new();
        for store in self.log.stores() {
            let facts = self.log.facts_for_store(&store, None, None);
            results.extend(facts.into_iter().map(from_fact_data));
        }
        Ok(results)
    }
}

// ── RocksDBBackend (Pure-Rust Filesystem-Backed Persistent Storage) ──────────
pub struct RocksDBBackend {
    data_dir: PathBuf,
    log: ShardedFactLog,
}

impl RocksDBBackend {
    pub fn new(data_dir: PathBuf) -> Result<Self, EngineError> {
        std::fs::create_dir_all(&data_dir).map_err(|e| EngineError::IOError(e.to_string()))?;
        let log = ShardedFactLog::new();

        // Preload any stored facts from *.mpk files
        if let Ok(entries) = std::fs::read_dir(&data_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    if let Ok(sub_entries) = std::fs::read_dir(&path) {
                        for sub_entry in sub_entries.flatten() {
                            let sub_path = sub_entry.path();
                            if sub_path.is_file()
                                && sub_path.extension().and_then(|e| e.to_str()) == Some("mpk")
                            {
                                if let Ok(bytes) = std::fs::read(&sub_path) {
                                    if let Ok(facts) = rmp_serde::from_slice::<Vec<Fact>>(&bytes) {
                                        for fact in facts {
                                            log.push(to_fact_data(fact));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(Self { data_dir, log })
    }
}

#[async_trait]
impl TBackend for RocksDBBackend {
    async fn read_as_of(
        &self,
        store: &str,
        key: &str,
        as_of: f64,
    ) -> Result<Option<Fact>, EngineError> {
        let opt_data = self.log.latest_for(store, key, Some(as_of));
        Ok(opt_data.map(from_fact_data))
    }

    async fn write_fact(&self, fact: Fact) -> Result<(), EngineError> {
        // Push to in-memory sharded timeline for fast reads
        let data = to_fact_data(fact.clone());
        self.log.push(data);

        // Persist fact to disk in store-sharded MessagePack file
        let store_dir = self.data_dir.join(&fact.store);
        std::fs::create_dir_all(&store_dir).map_err(|e| EngineError::IOError(e.to_string()))?;

        let file_path = store_dir.join(format!("{}.mpk", fact.key));
        let mut facts = if file_path.exists() {
            let bytes =
                std::fs::read(&file_path).map_err(|e| EngineError::IOError(e.to_string()))?;
            rmp_serde::from_slice::<Vec<Fact>>(&bytes).unwrap_or_default()
        } else {
            Vec::new()
        };

        facts.push(fact);
        let bytes = rmp_serde::to_vec(&facts)
            .map_err(|e| EngineError::SerializationError(e.to_string()))?;
        std::fs::write(&file_path, bytes).map_err(|e| EngineError::IOError(e.to_string()))?;

        Ok(())
    }

    async fn facts_for(
        &self,
        store: &str,
        key: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Result<Vec<Fact>, EngineError> {
        let list = self.log.facts_for_key(store, key, since, as_of);
        Ok(list.into_iter().map(from_fact_data).collect())
    }

    async fn all_facts(&self) -> Result<Vec<Fact>, EngineError> {
        let mut results = Vec::new();
        for store in self.log.stores() {
            let facts = self.log.facts_for_store(&store, None, None);
            results.extend(facts.into_iter().map(from_fact_data));
        }
        Ok(results)
    }
}

// ── RemoteTcpBackend (Fuses network loopback dynamically via TCP frames) ──────
pub struct RemoteTcpBackend {
    addr: String,
}

impl RemoteTcpBackend {
    pub fn new(addr: String) -> Self {
        Self { addr }
    }

    async fn send_req(&self, req: serde_json::Value) -> Result<serde_json::Value, EngineError> {
        let mut stream = TcpStream::connect(&self.addr)
            .await
            .map_err(|e| EngineError::StorageError(format!("TCP connection failed: {}", e)))?;

        let body =
            serde_json::to_vec(&req).map_err(|e| EngineError::SerializationError(e.to_string()))?;
        let body_len = body.len() as u32;
        let crc = crc32fast::hash(&body);

        stream
            .write_all(&body_len.to_be_bytes())
            .await
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        stream
            .write_all(&body)
            .await
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        stream
            .write_all(&crc.to_be_bytes())
            .await
            .map_err(|e| EngineError::IOError(e.to_string()))?;

        let mut header = [0u8; 4];
        stream
            .read_exact(&mut header)
            .await
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        let resp_len = u32::from_be_bytes(header) as usize;

        let mut resp_body = vec![0u8; resp_len];
        stream
            .read_exact(&mut resp_body)
            .await
            .map_err(|e| EngineError::IOError(e.to_string()))?;

        let mut crc_bytes = [0u8; 4];
        stream
            .read_exact(&mut crc_bytes)
            .await
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        if u32::from_be_bytes(crc_bytes) != crc32fast::hash(&resp_body) {
            return Err(EngineError::StorageError(
                "TCP frame CRC mismatch".to_string(),
            ));
        }

        let resp_jv = serde_json::from_slice(&resp_body)
            .map_err(|e| EngineError::SerializationError(e.to_string()))?;
        Ok(resp_jv)
    }
}

#[async_trait]
impl TBackend for RemoteTcpBackend {
    async fn read_as_of(
        &self,
        store: &str,
        key: &str,
        as_of: f64,
    ) -> Result<Option<Fact>, EngineError> {
        let req = serde_json::json!({
            "op": "latest_for",
            "store": store,
            "key": key,
            "as_of": as_of
        });
        let resp = self.send_req(req).await?;
        if resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            if let Some(fact_val) = resp.get("fact") {
                if !fact_val.is_null() {
                    let fact: Fact = serde_json::from_value(fact_val.clone())
                        .map_err(|e| EngineError::SerializationError(e.to_string()))?;
                    return Ok(Some(fact));
                }
            }
        }
        Ok(None)
    }

    async fn write_fact(&self, fact: Fact) -> Result<(), EngineError> {
        let data = to_fact_data(fact);
        let req = serde_json::json!({
            "op": "write_fact",
            "fact": data
        });
        let resp = self.send_req(req).await?;
        if resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            Ok(())
        } else {
            let err_msg = resp
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("Unknown error");
            Err(EngineError::StorageError(err_msg.to_string()))
        }
    }

    async fn facts_for(
        &self,
        store: &str,
        key: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Result<Vec<Fact>, EngineError> {
        let req = serde_json::json!({
            "op": "facts_for",
            "store": store,
            "key": key,
            "since": since,
            "as_of": as_of
        });
        let resp = self.send_req(req).await?;
        if resp.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            if let Some(facts_arr) = resp.get("facts").and_then(|v| v.as_array()) {
                let mut results = Vec::new();
                for val in facts_arr {
                    let fact: Fact = serde_json::from_value(val.clone())
                        .map_err(|e| EngineError::SerializationError(e.to_string()))?;
                    results.push(fact);
                }
                return Ok(results);
            }
        }
        Ok(Vec::new())
    }

    async fn all_facts(&self) -> Result<Vec<Fact>, EngineError> {
        Ok(Vec::new())
    }
}
