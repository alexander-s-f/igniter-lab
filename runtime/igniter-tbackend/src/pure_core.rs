// src/pure_core.rs
// FFI-free Pure Rust Bitemporal Ledger Core Engine

use parking_lot::{Mutex, RwLock};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::collections::{HashMap, HashSet};
use std::fs::{File, OpenOptions};
use std::hash::{Hash, Hasher};
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};

const SHARD_COUNT: usize = 128;

// ── Fact Domain Model ───────────────────────────────────────────────────────

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct FactData {
    pub id: String,
    pub store: String,
    pub key: String,
    pub value: serde_json::Value,
    pub value_hash: String,
    pub causation: Option<String>,
    pub transaction_time: f64,
    pub valid_time: Option<f64>,
    pub schema_version: u32,
    pub producer: Option<String>,
    pub derivation: Option<String>,
}

// ── Sharded FactLog Memory Index ────────────────────────────────────────────

struct ShardInner {
    by_key: HashMap<(String, String), Vec<FactData>>,
    by_id: HashMap<String, (String, String, usize)>,
}

pub struct ShardedFactLog {
    shards: Vec<RwLock<ShardInner>>,
    write_once_lock: Mutex<()>,
}

#[derive(Clone, Debug)]
pub enum WriteOnceResult {
    Inserted,
    Replay,
    Conflict { existing: FactData },
}

impl ShardedFactLog {
    pub fn new() -> Self {
        let mut shards = Vec::with_capacity(SHARD_COUNT);
        for _ in 0..SHARD_COUNT {
            shards.push(RwLock::new(ShardInner {
                by_key: HashMap::new(),
                by_id: HashMap::new(),
            }));
        }
        ShardedFactLog {
            shards,
            write_once_lock: Mutex::new(()),
        }
    }

    fn get_shard_index(&self, store: &str, key: &str) -> usize {
        let mut hasher = DefaultHasher::new();
        store.hash(&mut hasher);
        key.hash(&mut hasher);
        (hasher.finish() as usize) % SHARD_COUNT
    }

    pub fn contains_fact(&self, store: &str, key: &str, id: &str) -> bool {
        let idx = self.get_shard_index(store, key);
        let shard = self.shards[idx].read();
        let k = (store.to_string(), key.to_string());
        if let Some(timeline) = shard.by_key.get(&k) {
            timeline.iter().any(|f| f.id == id)
        } else {
            false
        }
    }

    pub fn find_by_store_id(&self, store: &str, id: &str) -> Option<FactData> {
        for shard_lock in &self.shards {
            let shard = shard_lock.read();
            if let Some((existing_store, existing_key, idx)) = shard.by_id.get(id) {
                if existing_store != store {
                    continue;
                }
                let k = (existing_store.clone(), existing_key.clone());
                if let Some(timeline) = shard.by_key.get(&k) {
                    if let Some(fact) = timeline.get(*idx) {
                        return Some(fact.clone());
                    }
                }
            }
        }
        None
    }

    pub fn push(&self, data: FactData) {
        let idx = self.get_shard_index(&data.store, &data.key);
        let mut shard = self.shards[idx].write();
        let k = (data.store.clone(), data.key.clone());

        let list_idx = shard.by_key.entry(k.clone()).or_default().len();
        shard
            .by_id
            .insert(data.id.clone(), (k.0.clone(), k.1.clone(), list_idx));

        shard.by_key.get_mut(&k).unwrap().push(data);
    }

    pub fn push_once<F>(&self, data: FactData, before_append: F) -> Result<WriteOnceResult, String>
    where
        F: FnOnce(&FactData) -> Result<(), String>,
    {
        let _guard = self.write_once_lock.lock();
        if let Some(existing) = self.find_by_store_id(&data.store, &data.id) {
            if existing.key == data.key
                && existing.value_hash == data.value_hash
                && existing.value == data.value
            {
                return Ok(WriteOnceResult::Replay);
            }
            return Ok(WriteOnceResult::Conflict { existing });
        }

        before_append(&data)?;
        self.push(data);
        Ok(WriteOnceResult::Inserted)
    }

    pub fn latest_for(&self, store: &str, key: &str, as_of: Option<f64>) -> Option<FactData> {
        let idx = self.get_shard_index(store, key);
        let shard = self.shards[idx].read();
        let k = (store.to_string(), key.to_string());
        let timeline = shard.by_key.get(&k)?;

        // Pick the fact with the greatest transaction_time at or before `as_of`
        // (or the greatest overall when `as_of` is None). A linear scan is correct
        // regardless of insertion order — `push` appends in arrival order, which is
        // not necessarily transaction_time order (backfills, corrections, replays),
        // so partition_point (which assumes a sorted slice) would mis-resolve.
        let cmp = |a: &&FactData, b: &&FactData| {
            a.transaction_time
                .partial_cmp(&b.transaction_time)
                .unwrap_or(std::cmp::Ordering::Equal)
        };
        match as_of {
            Some(as_of) => timeline
                .iter()
                .filter(|fact| fact.transaction_time <= as_of)
                .max_by(cmp)
                .cloned(),
            None => timeline.iter().max_by(cmp).cloned(),
        }
    }

    pub fn facts_for_key(
        &self,
        store: &str,
        key: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Vec<FactData> {
        let idx = self.get_shard_index(store, key);
        let shard = self.shards[idx].read();
        let k = (store.to_string(), key.to_string());
        let timeline = match shard.by_key.get(&k) {
            Some(t) => t,
            None => return Vec::new(),
        };

        let start_idx = since.map_or(0, |s| {
            timeline.partition_point(|fact| fact.transaction_time < s)
        });
        let end_idx = as_of.map_or(timeline.len(), |a| {
            timeline.partition_point(|fact| fact.transaction_time <= a)
        });

        if start_idx < end_idx {
            timeline[start_idx..end_idx].to_vec()
        } else {
            Vec::new()
        }
    }

    pub fn facts_for_store(
        &self,
        store: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Vec<FactData> {
        let mut results = Vec::new();
        for shard_lock in &self.shards {
            let shard = shard_lock.read();
            for ((s, _), timeline) in &shard.by_key {
                if s == store {
                    let start_idx = since.map_or(0, |s| {
                        timeline.partition_point(|fact| fact.transaction_time < s)
                    });
                    let end_idx = as_of.map_or(timeline.len(), |a| {
                        timeline.partition_point(|fact| fact.transaction_time <= a)
                    });
                    if start_idx < end_idx {
                        results.extend(timeline[start_idx..end_idx].iter().cloned());
                    }
                }
            }
        }
        results.sort_by(|a, b| {
            a.transaction_time
                .partial_cmp(&b.transaction_time)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results
    }

    pub fn query_scope(
        &self,
        store: &str,
        filters: &serde_json::Value,
        as_of: Option<f64>,
    ) -> Vec<FactData> {
        let mut results = Vec::new();
        for shard_lock in &self.shards {
            let shard = shard_lock.read();
            for ((s, _k), timeline) in &shard.by_key {
                if s != store {
                    continue;
                }
                let latest = if let Some(as_of) = as_of {
                    let pos = timeline.partition_point(|fact| fact.transaction_time <= as_of);
                    if pos > 0 {
                        Some(&timeline[pos - 1])
                    } else {
                        None
                    }
                } else {
                    timeline.last()
                };
                if let Some(fact) = latest {
                    if matches_filters(&fact.value, filters) {
                        results.push(fact.clone());
                    }
                }
            }
        }
        results
    }

    pub fn size(&self) -> usize {
        let mut total = 0;
        for shard_lock in &self.shards {
            let shard = shard_lock.read();
            for timeline in shard.by_key.values() {
                total += timeline.len();
            }
        }
        total
    }

    #[allow(dead_code)]
    pub fn stores(&self) -> Vec<String> {
        let mut results = HashSet::new();
        for shard_lock in &self.shards {
            let shard = shard_lock.read();
            for (s, _) in shard.by_key.keys() {
                results.insert(s.clone());
            }
        }
        let mut list: Vec<String> = results.into_iter().collect();
        list.sort();
        list
    }
}

fn matches_filters(value: &serde_json::Value, filters: &serde_json::Value) -> bool {
    match (value, filters) {
        (serde_json::Value::Object(v), serde_json::Value::Object(f)) => f
            .iter()
            .all(|(k, fv)| v.get(k).map_or(false, |vv| vv == fv)),
        _ => false,
    }
}

// ── Durable Write-Ahead-Log (WAL) ───────────────────────────────────────────

struct FileBackendInner {
    path: String,
    writer: BufWriter<File>,
}

pub struct FileBackend(Mutex<FileBackendInner>);

impl FileBackend {
    pub fn new_pure(path: &str) -> Result<Self, std::io::Error> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        Ok(FileBackend(Mutex::new(FileBackendInner {
            path: path.to_string(),
            writer: BufWriter::new(file),
        })))
    }

    pub fn write_fact_data(&self, data: &FactData) -> Result<(), String> {
        let body = rmp_serde::to_vec_named(data).map_err(|e| e.to_string())?;
        let crc = crc32fast::hash(&body);
        let mut inner = self.0.lock();
        inner
            .writer
            .write_all(&(body.len() as u32).to_be_bytes())
            .and_then(|_| inner.writer.write_all(&body))
            .and_then(|_| inner.writer.write_all(&crc.to_be_bytes()))
            .and_then(|_| inner.writer.flush())
            .map_err(|e| e.to_string())
    }

    pub fn replay_pure(&self) -> Result<Vec<FactData>, std::io::Error> {
        let path = self.0.lock().path.clone();
        let mut file = File::open(&path)?;
        file.seek(SeekFrom::Start(0))?;

        let mut results = Vec::new();
        loop {
            let mut len_buf = [0u8; 4];
            match file.read_exact(&mut len_buf) {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
                Err(e) => return Err(e),
            }
            let body_len = u32::from_be_bytes(len_buf) as usize;

            let mut body = vec![0u8; body_len];
            if file.read_exact(&mut body).is_err() {
                break;
            }

            let mut crc_buf = [0u8; 4];
            if file.read_exact(&mut crc_buf).is_err() {
                break;
            }
            if u32::from_be_bytes(crc_buf) != crc32fast::hash(&body) {
                break;
            }

            let data: FactData = match rmp_serde::from_slice(&body) {
                Ok(d) => d,
                Err(_) => continue,
            };
            results.push(data);
        }
        Ok(results)
    }

    pub fn flush_pure(&self) -> Result<(), std::io::Error> {
        self.0.lock().writer.flush()
    }
}
