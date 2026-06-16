use crate::errors::EngineError;
use crate::fact::Fact;
use async_trait::async_trait;
use igniter_tbackend_playground::fact::FactData;
use igniter_tbackend_playground::timeline::ShardedFactLog;
use parking_lot::Mutex;
use std::fs::File;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
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

    /// Bitemporal point query (LAB-MACHINE-BITEMPORAL-AXIS-P1, route B).
    /// `known_at`  filters `transaction_time` — "what we knew as of T" (audit axis).
    /// `valid_at`  filters `valid_time`       — "the state true as of T" (effective axis).
    /// Strict: facts with NO `valid_time` are EXCLUDED from valid-axis queries — no silent
    /// `valid := transaction` inference (audit safety). When `valid_at` is None this reduces
    /// to the transaction-time `read_as_of` semantics (latest knowledge ≤ known_at).
    /// Default impl over `facts_for`, so every backend gets it for free.
    async fn read_bitemporal(
        &self,
        store: &str,
        key: &str,
        valid_at: Option<f64>,
        known_at: Option<f64>,
    ) -> Result<Option<Fact>, EngineError> {
        use std::cmp::Ordering;
        let facts = self.facts_for(store, key, None, known_at).await?;
        let pick = if let Some(va) = valid_at {
            facts
                .into_iter()
                .filter(|f| matches!(f.valid_time, Some(vt) if vt <= va))
                // version effective at valid_at = max valid_time, tie-break by latest knowledge
                .max_by(|a, b| {
                    a.valid_time
                        .partial_cmp(&b.valid_time)
                        .unwrap_or(Ordering::Equal)
                        .then(
                            a.transaction_time
                                .partial_cmp(&b.transaction_time)
                                .unwrap_or(Ordering::Equal),
                        )
                })
        } else {
            facts.into_iter().max_by(|a, b| {
                a.transaction_time
                    .partial_cmp(&b.transaction_time)
                    .unwrap_or(Ordering::Equal)
            })
        };
        Ok(pick)
    }
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

// ── MpkFileBackend (Pure-Rust Filesystem-Backed Persistent Storage) ──────────
//
// NOT RocksDB (there is no `rocksdb` crate dependency) — a store-sharded MessagePack (`.mpk`) file
// store. `RocksDBBackend` is kept as a back-compat ALIAS below; new code should say `MpkFileBackend`
// so the name stops implying LSM/WAL/fsync guarantees it never had. (LAB-MACHINE-FACTSTORE-
// DURABILITY-HARDENING-P3, closing the LAB-MACHINE-ROCKSDB-DURABILITY-P2 hole.)
//
// Durability hardening (P3):
//   * writes are ATOMIC — temp file in the same dir → fsync the data file → atomic `rename` → a
//     best-effort parent-dir fsync. A crash mid-write leaves either the old complete file or the new
//     complete file, never a torn one. A failed temp write leaves the prior valid file intact.
//   * corruption is OBSERVABLE, never silent — a `.mpk` that fails to decode is recorded in
//     `corrupt_files()` and makes a write to that key fail with `EngineError::Corruption` instead of
//     `unwrap_or_default()` silently dropping the key's history.
//   * fsync semantics are explicit: `File::sync_all()` (= `fsync`) is invoked on the data file and
//     (best-effort) the parent directory. NOTE: on macOS `fsync` does not flush the drive's own write
//     cache (that needs `F_FULLFSYNC`, which Rust std does not expose), so FULL power-loss durability
//     is NOT claimed on macOS — only crash/torn-write atomicity + fsync-to-OS. See the P3 doc.
pub struct MpkFileBackend {
    data_dir: PathBuf,
    log: ShardedFactLog,
    /// `.mpk` files that failed to decode on open (observable corruption, not silent loss).
    corrupt_files: Mutex<Vec<PathBuf>>,
    /// Serializes the read-modify-write critical section so a same-file append is never lost and
    /// temp names never collide.
    write_lock: Mutex<()>,
    tmp_counter: AtomicU64,
}

/// Atomic-replace `file_path` with `bytes`: write a sibling temp → fsync → rename → best-effort
/// parent-dir fsync. On any pre-rename failure the temp is removed and the prior file is untouched.
fn atomic_write(file_path: &Path, tmp_path: &Path, bytes: &[u8]) -> Result<(), EngineError> {
    let res = (|| -> std::io::Result<()> {
        let mut f = File::create(tmp_path)?;
        f.write_all(bytes)?;
        f.sync_all()?; // fsync the data file before it is made visible under the final name
        Ok(())
    })();
    if let Err(e) = res {
        let _ = std::fs::remove_file(tmp_path); // leave the previous file intact
        return Err(EngineError::IOError(e.to_string()));
    }
    std::fs::rename(tmp_path, file_path).map_err(|e| {
        let _ = std::fs::remove_file(tmp_path);
        EngineError::IOError(e.to_string())
    })?;
    // Best-effort directory fsync so the rename itself is durable (platform-permitting).
    if let Some(parent) = file_path.parent() {
        if let Ok(d) = File::open(parent) {
            let _ = d.sync_all();
        }
    }
    Ok(())
}

impl MpkFileBackend {
    pub fn new(data_dir: PathBuf) -> Result<Self, EngineError> {
        std::fs::create_dir_all(&data_dir).map_err(|e| EngineError::IOError(e.to_string()))?;
        let log = ShardedFactLog::new();
        let mut corrupt: Vec<PathBuf> = Vec::new();

        // Preload stored facts from *.mpk files. A file that fails to decode is RECORDED as corrupt
        // and left on disk (forensics) — it is NOT silently skipped into an empty key.
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
                                match std::fs::read(&sub_path) {
                                    Ok(bytes) => match rmp_serde::from_slice::<Vec<Fact>>(&bytes) {
                                        Ok(facts) => {
                                            for fact in facts {
                                                log.push(to_fact_data(fact));
                                            }
                                        }
                                        Err(_) => corrupt.push(sub_path.clone()),
                                    },
                                    Err(_) => corrupt.push(sub_path.clone()),
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(Self {
            data_dir,
            log,
            corrupt_files: Mutex::new(corrupt),
            write_lock: Mutex::new(()),
            tmp_counter: AtomicU64::new(0),
        })
    }

    /// `.mpk` files that failed to decode on open (or were hit as corrupt during a write). Lets an
    /// operator/orchestrator SEE corruption instead of it presenting as silently-lost history.
    pub fn corrupt_files(&self) -> Vec<PathBuf> {
        self.corrupt_files.lock().clone()
    }
}

#[async_trait]
impl TBackend for MpkFileBackend {
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
        let store_dir = self.data_dir.join(&fact.store);
        std::fs::create_dir_all(&store_dir).map_err(|e| EngineError::IOError(e.to_string()))?;
        let file_path = store_dir.join(format!("{}.mpk", fact.key));

        // Persist FIRST (durable), then publish to the in-memory log — so a refused write never
        // leaves the in-memory view ahead of disk.
        {
            let _guard = self.write_lock.lock();
            let mut facts: Vec<Fact> = if file_path.exists() {
                let bytes =
                    std::fs::read(&file_path).map_err(|e| EngineError::IOError(e.to_string()))?;
                match rmp_serde::from_slice::<Vec<Fact>>(&bytes) {
                    Ok(f) => f,
                    Err(e) => {
                        // Do NOT unwrap_or_default — that would silently drop the key's history and
                        // then persist only the new fact (compounding the loss). Refuse loudly and
                        // record the corruption so it is observable.
                        self.corrupt_files.lock().push(file_path.clone());
                        return Err(EngineError::Corruption(format!(
                            "{}: {}",
                            file_path.display(),
                            e
                        )));
                    }
                }
            } else {
                Vec::new()
            };

            facts.push(fact.clone());
            let bytes = rmp_serde::to_vec(&facts)
                .map_err(|e| EngineError::SerializationError(e.to_string()))?;
            let n = self.tmp_counter.fetch_add(1, Ordering::Relaxed);
            let tmp_path = store_dir.join(format!(".{}.mpk.{}.tmp", fact.key, n));
            atomic_write(&file_path, &tmp_path, &bytes)?;
        }

        self.log.push(to_fact_data(fact));
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

/// Back-compat alias. The backend was historically (mis)named `RocksDBBackend`; it is a pure-Rust
/// `.mpk` file store, not RocksDB. Prefer [`MpkFileBackend`] in new code. (P3 naming/front-door.)
pub type RocksDBBackend = MpkFileBackend;

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
