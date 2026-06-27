// src/pure_core.rs
// FFI-free Pure Rust Bitemporal Ledger Core Engine

use parking_lot::{Condvar, Mutex, RwLock};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::collections::{HashMap, HashSet};
use std::fs::{File, OpenOptions};
use std::hash::{Hash, Hasher};
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering as AtomicOrdering};
use std::time::{Duration, Instant};

const SHARD_COUNT: usize = 128;

// ── Fact Domain Model ───────────────────────────────────────────────────────

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct FactData {
    pub id: String,
    pub store: String,
    pub key: String,
    pub value: serde_json::Value,
    // LAB-TBACKEND-SERVER-CANONICAL-HASH-P4: the server is the authority for this
    // field. Clients MAY omit it (server computes the canonical hash) or supply
    // one for cross-checking. `#[serde(default)]` lets producers send no hash at
    // all; the daemon stamps the canonical value before the fact enters the log.
    #[serde(default)]
    pub value_hash: String,
    pub causation: Option<String>,
    pub transaction_time: f64,
    pub valid_time: Option<f64>,
    pub schema_version: u32,
    pub producer: Option<String>,
    pub derivation: Option<String>,
    // LAB-TBACKEND-SEQID-PER-STORE-P9: server-assigned, per-store, monotonic
    // ordering authority. `transaction_time` stays client/app evidence. Assigned
    // ONLY by the daemon on first insert (never on replay/conflict) and excluded
    // from the canonical value hash. `#[serde(default)]` keeps pre-P9 WAL frames
    // loadable (legacy `seq_id == 0`, backfilled by append order on replay); a
    // non-zero `seq_id` marks a seq-authoritative frame.
    #[serde(default)]
    pub seq_id: u64,
    // Reserved for the future mesh version-vector `{origin_node -> origin_seq}`
    // (LAB-TBACKEND-SERVER-AUTHORITY-SEQID-READINESS-P8). Not populated here; kept
    // additive so the mesh slice needs no second WAL-format change.
    #[serde(default)]
    pub origin_node: Option<String>,
}

// ── Canonical Server-Authoritative Content Hash ─────────────────────────────
// LAB-TBACKEND-SERVER-CANONICAL-HASH-P4.
//
// The server — not the client — is the authority for a fact's content hash. A
// client-supplied `value_hash` the server never checks is metadata, not
// integrity. Both daemon write paths (`write_fact`, `write_fact_once`) recompute
// this hash before a fact enters the ledger.
//
// Canonical rule: object keys sorted recursively; JSON scalars (numbers, strings,
// bools, null) preserved exactly as serde renders them; serialized compactly with
// no insignificant whitespace. The serializer is written explicitly so the result
// does not depend on serde_json's Map backend (BTreeMap today, but a future
// `preserve_order` feature would otherwise silently change the bytes).
//
// Algorithm: blake3 (hex). It is already the daemon's native hash — the profile
// fingerprint (kernel.rs), bearer-token storage (packs/auth.rs) and the FFI fact
// builder (fact.rs) all use blake3. CRC32 (used by the Ruby mirror) is a 32-bit
// checksum, trivially collidable, and unfit for audit content-addressing.

/// Canonical UTF-8 serialization of a fact `value` (sorted keys, preserved
/// scalars, compact). This is the exact preimage that gets hashed.
pub fn canonical_value_bytes(value: &serde_json::Value) -> String {
    let mut out = String::new();
    write_canonical(value, &mut out);
    out
}

/// blake3 hex of the canonical serialization. This is the authoritative
/// `value_hash` the server stamps onto every accepted fact.
pub fn canonical_value_hash(value: &serde_json::Value) -> String {
    blake3::hash(canonical_value_bytes(value).as_bytes())
        .to_hex()
        .to_string()
}

fn write_canonical(value: &serde_json::Value, out: &mut String) {
    use serde_json::Value;
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            out.push('{');
            for (i, k) in keys.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                // serde renders the key as a properly escaped JSON string.
                out.push_str(&serde_json::to_string(k).unwrap_or_else(|_| format!("{k:?}")));
                out.push(':');
                write_canonical(&map[*k], out);
            }
            out.push('}');
        }
        Value::Array(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_canonical(item, out);
            }
            out.push(']');
        }
        // Scalars: delegate to serde so number/string/bool/null rendering is
        // exactly the JSON canonical form. Preserves scalar values verbatim.
        scalar => out.push_str(&serde_json::to_string(scalar).unwrap_or_default()),
    }
}

// ── Sharded FactLog Memory Index ────────────────────────────────────────────

struct ShardInner {
    by_key: HashMap<(String, String), Vec<FactData>>,
    by_id: HashMap<String, (String, String, usize)>,
}

pub struct ShardedFactLog {
    shards: Vec<RwLock<ShardInner>>,
    write_once_lock: Mutex<()>,
    // LAB-TBACKEND-SEQID-PER-STORE-P9: next per-store seq to assign. 1-based, so
    // an assigned seq is never 0 (which marks a legacy/unassigned fact). Restored
    // to `max(replayed seq) + 1` on boot by `load_replayed`.
    next_seq: AtomicU64,
}

#[derive(Clone, Debug)]
pub enum WriteOnceResult {
    Inserted { seq_id: u64 },
    Replay { seq_id: u64 },
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
            next_seq: AtomicU64::new(1),
        }
    }

    /// Assign the next per-store `seq_id` (server ordering authority). Monotonic
    /// and atomic across both write paths; gap-free on the success path (a write
    /// whose WAL append fails consumes its seq — acceptable for an error path).
    pub fn assign_seq(&self) -> u64 {
        self.next_seq.fetch_add(1, AtomicOrdering::AcqRel)
    }

    /// Load WAL-replayed facts at boot: backfill legacy (`seq_id == 0`) facts by
    /// append order — placed ABOVE any real assigned seq — and set the counter to
    /// `max(seq) + 1`. Legacy seq is therefore deterministic across restarts
    /// (append order is stable) and never collides with a previously assigned seq.
    /// The WAL file is not rewritten (no destructive migration).
    pub fn load_replayed(&self, facts: Vec<FactData>) {
        let max_assigned = facts.iter().map(|f| f.seq_id).max().unwrap_or(0);
        let mut counter = max_assigned;
        for mut fact in facts {
            if fact.seq_id == 0 {
                counter += 1;
                fact.seq_id = counter;
            }
            self.push(fact);
        }
        self.next_seq.store(counter + 1, AtomicOrdering::Release);
    }

    /// Server-order ("by seq") read: every fact whose `seq_id` is in
    /// `(after_seq, until_seq]`, sorted by `seq_id`. Clock-free — it never touches
    /// `transaction_time`. Correct regardless of arrival order (scan + filter,
    /// matching the P2 correctness-first stance for tt reads). Per-key timelines
    /// are already seq-sorted on the serialized `write_fact_once` path, so a
    /// `partition_point` O(log N) refinement is a safe later optimization.
    pub fn facts_by_seq(
        &self,
        store: &str,
        after_seq: u64,
        until_seq: Option<u64>,
    ) -> Vec<FactData> {
        let mut results = Vec::new();
        for shard_lock in &self.shards {
            let shard = shard_lock.read();
            for ((s, _), timeline) in &shard.by_key {
                if s == store {
                    results.extend(
                        timeline
                            .iter()
                            .filter(|f| {
                                f.seq_id > after_seq && until_seq.map_or(true, |u| f.seq_id <= u)
                            })
                            .cloned(),
                    );
                }
            }
        }
        results.sort_by(|a, b| a.seq_id.cmp(&b.seq_id));
        results
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
                // Replay returns the ORIGINAL seq_id — never a new one. Identity is
                // id + canonical hash + value; seq_id is not compared.
                return Ok(WriteOnceResult::Replay {
                    seq_id: existing.seq_id,
                });
            }
            return Ok(WriteOnceResult::Conflict { existing });
        }

        // First insert: assign the server seq_id BEFORE the WAL append so the
        // durable frame carries it (and frame order == seq order on this path,
        // since the whole insert runs under `write_once_lock`).
        let mut data = data;
        let seq_id = self.assign_seq();
        data.seq_id = seq_id;
        before_append(&data)?;
        self.push(data);
        Ok(WriteOnceResult::Inserted { seq_id })
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

        // Scan + filter the [since, as_of] transaction_time window, then sort by
        // transaction_time. `push` stores arrival order, which is not necessarily
        // transaction_time order (backfills, corrections, replays), so a
        // partition_point window over the raw vector silently drops out-of-order
        // facts. Correctness first: a full scan is order-independent (mirrors
        // `latest_for`). O(N) per key — see docs/technical_architecture.md §B.
        let mut window: Vec<FactData> = timeline
            .iter()
            .filter(|fact| {
                since.map_or(true, |s| fact.transaction_time >= s)
                    && as_of.map_or(true, |a| fact.transaction_time <= a)
            })
            .cloned()
            .collect();
        window.sort_by(|a, b| {
            a.transaction_time
                .partial_cmp(&b.transaction_time)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        window
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
                    // Scan + filter the window per key — order-independent. A
                    // partition_point window assumes a tt-sorted vector and would
                    // both drop in-window facts and leak out-of-window ones when the
                    // timeline arrived out of transaction_time order.
                    results.extend(
                        timeline
                            .iter()
                            .filter(|fact| {
                                since.map_or(true, |s| fact.transaction_time >= s)
                                    && as_of.map_or(true, |a| fact.transaction_time <= a)
                            })
                            .cloned(),
                    );
                }
            }
        }
        // Stable chronological output across keys.
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
                // Resolve the latest fact at or before `as_of` by scanning for the
                // greatest in-window transaction_time (mirrors `latest_for`). A
                // partition_point + timeline[pos-1] assumes a tt-sorted vector and
                // can pick the wrong fact — or skip a match — for out-of-order
                // timelines (and `timeline.last()` returns last-arrived, not latest).
                let cmp = |a: &&FactData, b: &&FactData| {
                    a.transaction_time
                        .partial_cmp(&b.transaction_time)
                        .unwrap_or(std::cmp::Ordering::Equal)
                };
                let latest = match as_of {
                    Some(as_of) => timeline
                        .iter()
                        .filter(|fact| fact.transaction_time <= as_of)
                        .max_by(cmp),
                    None => timeline.iter().max_by(cmp),
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

// Group-commit coordinator for `durable` acks (LAB-TBACKEND-DURABLE-ACK-GROUP-COMMIT-P6).
// One fdatasync amortized across all writers in a bounded window. The fsync runs
// OUTSIDE the global `write_once_lock` and outside the append mutex (it uses a
// dup'd fd, `sync_handle`), so durable writes do not serialize appends.
struct CommitInner {
    synced_seq: u64,     // highest write_seq known durable on the device
    leader_active: bool, // exactly one writer drives each group fsync
    generation: u64,     // bumps after every sync attempt (followers re-check)
    last_err: Option<String>,
    last_attempt_seq: u64, // write_seq the most recent (failed) attempt tried to cover
}

pub struct FileBackend {
    inner: Mutex<FileBackendInner>,
    // Separate fd (dup of the WAL file) used only for fdatasync, so syncing never
    // contends the append `inner` mutex.
    sync_handle: File,
    // Monotonic count of appended frames this process lifetime; the durability barrier.
    write_seq: AtomicU64,
    // Test seam: number of fdatasync syscalls actually issued (proves the durable path ran).
    sync_count: AtomicU64,
    // Test seam: when armed, the next group fsync fails instead of calling the syscall.
    sync_fault: AtomicBool,
    commit: Mutex<CommitInner>,
    commit_cond: Condvar,
}

impl FileBackend {
    pub fn new_pure(path: &str) -> Result<Self, std::io::Error> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        let sync_handle = file.try_clone()?;
        Ok(FileBackend {
            inner: Mutex::new(FileBackendInner {
                path: path.to_string(),
                writer: BufWriter::new(file),
            }),
            sync_handle,
            write_seq: AtomicU64::new(0),
            sync_count: AtomicU64::new(0),
            sync_fault: AtomicBool::new(false),
            commit: Mutex::new(CommitInner {
                synced_seq: 0,
                leader_active: false,
                generation: 0,
                last_err: None,
                last_attempt_seq: 0,
            }),
            commit_cond: Condvar::new(),
        })
    }

    pub fn write_fact_data(&self, data: &FactData) -> Result<(), String> {
        let body = rmp_serde::to_vec_named(data).map_err(|e| e.to_string())?;
        let crc = crc32fast::hash(&body);
        {
            let mut inner = self.inner.lock();
            inner
                .writer
                .write_all(&(body.len() as u32).to_be_bytes())
                .and_then(|_| inner.writer.write_all(&body))
                .and_then(|_| inner.writer.write_all(&crc.to_be_bytes()))
                .and_then(|_| inner.writer.flush())
                .map_err(|e| e.to_string())?;
        }
        // The frame is now in the OS page cache (`accepted`). Publish the barrier
        // so a `durable` caller can wait for an fdatasync that covers it.
        self.write_seq.fetch_add(1, AtomicOrdering::AcqRel);
        Ok(())
    }

    /// Current append barrier — the seq a `durable` caller waits to see synced.
    pub fn current_seq(&self) -> u64 {
        self.write_seq.load(AtomicOrdering::Acquire)
    }

    /// fdatasync syscalls actually issued (test seam for the group-commit proof).
    pub fn sync_count(&self) -> u64 {
        self.sync_count.load(AtomicOrdering::Acquire)
    }

    pub fn synced_seq(&self) -> u64 {
        self.commit.lock().synced_seq
    }

    /// Test-only: arm/disarm an injected fdatasync failure.
    pub fn arm_sync_fault(&self, on: bool) {
        self.sync_fault.store(on, AtomicOrdering::Release);
    }

    /// Block until an fdatasync covering `barrier` has succeeded (the `durable`
    /// ack boundary). Coalesces concurrent durable writers: the first becomes the
    /// leader, waits a bounded window (`interval_ms`, cut short when the pending
    /// batch reaches `max_batch`), issues ONE fdatasync, and releases all
    /// followers it covered. Returns Err (retryable upstream) if the sync that
    /// would have covered `barrier` failed — never a silent downgrade.
    pub fn commit_durable(
        &self,
        barrier: u64,
        interval_ms: u64,
        max_batch: u64,
    ) -> Result<(), String> {
        let mut g = self.commit.lock();
        loop {
            if g.synced_seq >= barrier {
                return Ok(());
            }
            if !g.leader_active {
                // Become leader and drive one fresh fdatasync attempt. `last_err`
                // is attempt-scoped: cleared at the start so a retry after a
                // disarmed/transient fault is never blocked by a stale error.
                g.leader_active = true;
                g.last_err = None;
                drop(g);

                // Batch window: let other durable writers arrive and append so one
                // fsync covers them all. Cut short once the pending batch is large.
                let deadline = Instant::now() + Duration::from_millis(interval_ms);
                loop {
                    let pending = self
                        .write_seq
                        .load(AtomicOrdering::Acquire)
                        .saturating_sub(self.commit.lock().synced_seq);
                    if pending >= max_batch.max(1) || Instant::now() >= deadline {
                        break;
                    }
                    std::thread::sleep(Duration::from_micros(200));
                }

                let seq_to_sync = self.write_seq.load(AtomicOrdering::Acquire);
                let res = if self.sync_fault.load(AtomicOrdering::Acquire) {
                    Err("injected fdatasync fault".to_string())
                } else {
                    self.sync_handle.sync_data().map_err(|e| e.to_string())
                };

                let mut g2 = self.commit.lock();
                g2.last_attempt_seq = seq_to_sync;
                match res {
                    Ok(()) => {
                        if g2.synced_seq < seq_to_sync {
                            g2.synced_seq = seq_to_sync;
                        }
                        self.sync_count.fetch_add(1, AtomicOrdering::AcqRel);
                        g2.last_err = None;
                    }
                    Err(e) => {
                        g2.last_err = Some(e);
                    }
                }
                g2.leader_active = false;
                g2.generation = g2.generation.wrapping_add(1);
                self.commit_cond.notify_all();

                // Decide my outcome from THIS attempt.
                if g2.synced_seq >= barrier {
                    return Ok(());
                }
                if g2.last_err.is_some() && g2.last_attempt_seq >= barrier {
                    return Err(g2.last_err.clone().unwrap());
                }
                // My barrier wasn't covered (a later append raised it); retry.
                g = g2;
                continue;
            } else {
                // Follower: wait for the in-flight attempt to complete, then judge
                // by that attempt's result.
                let gen = g.generation;
                self.commit_cond
                    .wait_for(&mut g, Duration::from_millis(interval_ms.max(1) * 4 + 50));
                if g.synced_seq >= barrier {
                    return Ok(());
                }
                if g.generation != gen && g.last_err.is_some() && g.last_attempt_seq >= barrier {
                    return Err(g.last_err.clone().unwrap());
                }
                continue;
            }
        }
    }

    pub fn replay_pure(&self) -> Result<Vec<FactData>, std::io::Error> {
        let path = self.inner.lock().path.clone();
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
        self.inner.lock().writer.flush()
    }
}

// ── Windowed-read correctness tests ─────────────────────────────────────────
// LAB-TBACKEND-TEMPORAL-RANGE-CORRECTNESS-P2: facts can arrive out of
// transaction_time order (retries, backfills, corrections). The in-memory
// timeline stores arrival order, so any windowed read that assumes a tt-sorted
// vector (partition_point) silently drops or mis-resolves facts. These tests pin
// the correct, order-independent behavior.

#[cfg(test)]
mod tests {
    use super::*;

    fn fact(store: &str, key: &str, id: &str, tt: f64, value: serde_json::Value) -> FactData {
        FactData {
            id: id.to_string(),
            store: store.to_string(),
            key: key.to_string(),
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: tt,
            valid_time: None,
            schema_version: 1,
            producer: None,
            derivation: None,
            seq_id: 0,
            origin_node: None,
        }
    }

    // Three facts for the same key appended out of transaction_time order: 100, 300, 200.
    fn out_of_order_log() -> ShardedFactLog {
        let log = ShardedFactLog::new();
        log.push(fact("s", "k", "f100", 100.0, serde_json::json!({ "v": 1 })));
        log.push(fact("s", "k", "f300", 300.0, serde_json::json!({ "v": 3 })));
        log.push(fact("s", "k", "f200", 200.0, serde_json::json!({ "v": 2 })));
        log
    }

    #[test]
    fn latest_for_is_correct_for_out_of_order() {
        // Already correct (scans) — pin it so a future "optimization" cannot regress it.
        let log = out_of_order_log();
        let got = log.latest_for("s", "k", Some(250.0)).unwrap();
        assert_eq!(
            got.id, "f200",
            "as_of=250 must resolve the greatest tt <= 250"
        );
    }

    #[test]
    fn facts_for_key_window_includes_out_of_order_fact() {
        let log = out_of_order_log();
        // Window [150, 250] contains only the tt=200 fact. The old partition_point
        // implementation returned an EMPTY slice here (start_idx == end_idx == 1).
        let got = log.facts_for_key("s", "k", Some(150.0), Some(250.0));
        let ids: Vec<&str> = got.iter().map(|f| f.id.as_str()).collect();
        assert_eq!(ids, vec!["f200"]);
    }

    #[test]
    fn facts_for_key_returns_full_window_sorted() {
        let log = out_of_order_log();
        let got = log.facts_for_key("s", "k", None, None);
        let ids: Vec<&str> = got.iter().map(|f| f.id.as_str()).collect();
        assert_eq!(
            ids,
            vec!["f100", "f200", "f300"],
            "full window, sorted by transaction_time"
        );
    }

    #[test]
    fn facts_for_store_window_across_keys_sorted() {
        let log = ShardedFactLog::new();
        log.push(fact("s", "a", "a100", 100.0, serde_json::json!({})));
        log.push(fact("s", "b", "b300", 300.0, serde_json::json!({})));
        log.push(fact("s", "a", "a250", 250.0, serde_json::json!({})));
        log.push(fact("s", "b", "b150", 150.0, serde_json::json!({})));
        // Window [120, 260]: a250 and b150 (a100 below, b300 above), sorted by tt.
        let got = log.facts_for_store("s", Some(120.0), Some(260.0));
        let ids: Vec<&str> = got.iter().map(|f| f.id.as_str()).collect();
        assert_eq!(
            ids,
            vec!["b150", "a250"],
            "every in-window fact, sorted by tt"
        );
    }

    #[test]
    fn query_scope_resolves_out_of_order_latest() {
        let log = ShardedFactLog::new();
        // An early "open" fact, a later "closed" correction, then a backfilled "open"
        // with a tt between them appended last (arrival order != tt order).
        log.push(fact(
            "s",
            "k",
            "f100",
            100.0,
            serde_json::json!({ "status": "open" }),
        ));
        log.push(fact(
            "s",
            "k",
            "f300",
            300.0,
            serde_json::json!({ "status": "closed" }),
        ));
        log.push(fact(
            "s",
            "k",
            "f200",
            200.0,
            serde_json::json!({ "status": "open" }),
        ));

        // as_of=250 -> latest in-window is tt=200 (status open). Must match the filter.
        let got = log.query_scope("s", &serde_json::json!({ "status": "open" }), Some(250.0));
        assert_eq!(
            got.len(),
            1,
            "out-of-order timeline must not skip the match"
        );
        assert_eq!(got[0].id, "f200");

        // The tt=300 "closed" state is not yet visible at as_of=250.
        let none = log.query_scope("s", &serde_json::json!({ "status": "closed" }), Some(250.0));
        assert!(none.is_empty(), "as_of must not leak a future correction");
    }

    // ── Canonical hash tests (LAB-TBACKEND-SERVER-CANONICAL-HASH-P4) ────────

    #[test]
    fn canonical_hash_is_key_order_independent() {
        // Same logical value, different key insertion order → identical hash.
        let a = serde_json::json!({ "b": 2, "a": 1, "nested": { "y": 0, "x": 9 } });
        let mut obj = serde_json::Map::new();
        obj.insert("a".into(), serde_json::json!(1));
        obj.insert("b".into(), serde_json::json!(2));
        let mut nested = serde_json::Map::new();
        nested.insert("x".into(), serde_json::json!(9));
        nested.insert("y".into(), serde_json::json!(0));
        obj.insert("nested".into(), serde_json::Value::Object(nested));
        let b = serde_json::Value::Object(obj);
        assert_eq!(canonical_value_hash(&a), canonical_value_hash(&b));
        // And the canonical bytes are the sorted, compact form.
        assert_eq!(
            canonical_value_bytes(&a),
            r#"{"a":1,"b":2,"nested":{"x":9,"y":0}}"#
        );
    }

    #[test]
    fn canonical_hash_distinguishes_values() {
        let a = serde_json::json!({ "state": "open" });
        let b = serde_json::json!({ "state": "closed" });
        assert_ne!(canonical_value_hash(&a), canonical_value_hash(&b));
    }

    #[test]
    fn canonical_hash_preserves_scalars_and_arrays() {
        // Array order is significant; scalars preserved verbatim.
        let v = serde_json::json!({ "xs": [3, 1, 2], "f": 1.5, "n": null, "t": true });
        assert_eq!(
            canonical_value_bytes(&v),
            r#"{"f":1.5,"n":null,"t":true,"xs":[3,1,2]}"#
        );
    }

    #[test]
    fn canonical_hash_known_vector() {
        // Pinned cross-language reference vector. Any reimplementation (Ruby,
        // Python) hashing the canonical bytes of this value with blake3 must
        // produce this exact hex, or the meanings have diverged.
        let v = serde_json::json!({ "key": "k", "payload": "p15" });
        assert_eq!(canonical_value_bytes(&v), r#"{"key":"k","payload":"p15"}"#);
        assert_eq!(
            canonical_value_hash(&v),
            blake3::hash(r#"{"key":"k","payload":"p15"}"#.as_bytes())
                .to_hex()
                .to_string()
        );
    }

    #[test]
    fn in_order_behavior_unchanged() {
        let log = ShardedFactLog::new();
        log.push(fact("s", "k", "f100", 100.0, serde_json::json!({ "v": 1 })));
        log.push(fact("s", "k", "f200", 200.0, serde_json::json!({ "v": 2 })));
        log.push(fact("s", "k", "f300", 300.0, serde_json::json!({ "v": 3 })));
        assert_eq!(log.latest_for("s", "k", Some(250.0)).unwrap().id, "f200");
        let win = log.facts_for_key("s", "k", Some(150.0), Some(250.0));
        assert_eq!(
            win.iter().map(|f| f.id.as_str()).collect::<Vec<_>>(),
            vec!["f200"]
        );
        let all = log.facts_for_store("s", None, None);
        assert_eq!(
            all.iter().map(|f| f.id.as_str()).collect::<Vec<_>>(),
            vec!["f100", "f200", "f300"]
        );
    }

    // ── LAB-TBACKEND-SEQID-PER-STORE-P9 ─────────────────────────────────────

    fn noop_append(_: &FactData) -> Result<(), String> {
        Ok(())
    }

    #[test]
    fn seqid_assigned_monotonic_and_gap_free() {
        let log = ShardedFactLog::new();
        for (i, id) in ["a", "b", "c"].iter().enumerate() {
            let r = log
                .push_once(fact("s", "k", id, 100.0, serde_json::json!({"n": i})), noop_append)
                .unwrap();
            match r {
                WriteOnceResult::Inserted { seq_id } => assert_eq!(seq_id, (i as u64) + 1),
                other => panic!("expected Inserted, got {other:?}"),
            }
        }
    }

    #[test]
    fn replay_returns_original_seq_and_does_not_increment() {
        let log = ShardedFactLog::new();
        // Insert -> seq 1.
        let ins = log
            .push_once(fact("s", "k", "x", 100.0, serde_json::json!({"v": 1})), noop_append)
            .unwrap();
        assert!(matches!(ins, WriteOnceResult::Inserted { seq_id: 1 }));
        // Replay the SAME content but as a client would send it (seq_id 0) ->
        // returns the ORIGINAL seq, proving seq is excluded from identity.
        let mut same = fact("s", "k", "x", 999.0, serde_json::json!({"v": 1}));
        same.seq_id = 0;
        let rep = log.push_once(same, noop_append).unwrap();
        assert!(matches!(rep, WriteOnceResult::Replay { seq_id: 1 }));
        // A new insert is seq 2 — the replay did NOT consume a seq.
        let next = log
            .push_once(fact("s", "k", "y", 100.0, serde_json::json!({"v": 2})), noop_append)
            .unwrap();
        assert!(matches!(next, WriteOnceResult::Inserted { seq_id: 2 }));
    }

    #[test]
    fn conflict_allocates_no_seq() {
        let log = ShardedFactLog::new();
        log.push_once(fact("s", "k", "x", 100.0, serde_json::json!({"v": 1})), noop_append)
            .unwrap();
        // Same id, different payload -> Conflict, no seq minted.
        let c = log
            .push_once(fact("s", "k", "x", 100.0, serde_json::json!({"v": 2})), noop_append)
            .unwrap();
        assert!(matches!(c, WriteOnceResult::Conflict { .. }));
        // Next insert is seq 2 — the conflict did not advance the counter past it.
        let n = log
            .push_once(fact("s", "k", "z", 100.0, serde_json::json!({"v": 3})), noop_append)
            .unwrap();
        assert!(matches!(n, WriteOnceResult::Inserted { seq_id: 2 }));
    }

    #[test]
    fn factdata_without_seqid_deserializes_to_zero() {
        // A pre-P9 frame has no seq_id/origin_node keys. serde(default) loads them.
        let legacy = serde_json::json!({
            "id": "f1", "store": "s", "key": "k", "value": {"v": 1},
            "transaction_time": 1.0, "schema_version": 1
        });
        let f: FactData = serde_json::from_value(legacy).unwrap();
        assert_eq!(f.seq_id, 0);
        assert_eq!(f.origin_node, None);
    }

    #[test]
    fn load_replayed_backfills_legacy_by_append_order_and_recovers_counter() {
        let log = ShardedFactLog::new();
        // Three legacy facts (seq 0) replayed in file order.
        let facts = vec![
            fact("s", "k", "f1", 100.0, serde_json::json!({"v": 1})),
            fact("s", "k", "f2", 100.0, serde_json::json!({"v": 2})),
            fact("s", "k", "f3", 100.0, serde_json::json!({"v": 3})),
        ];
        log.load_replayed(facts);
        let got = log.facts_by_seq("s", 0, None);
        assert_eq!(
            got.iter().map(|f| (f.id.as_str(), f.seq_id)).collect::<Vec<_>>(),
            vec![("f1", 1), ("f2", 2), ("f3", 3)]
        );
        // Counter continues above the backfilled max.
        let n = log
            .push_once(fact("s", "k", "f4", 100.0, serde_json::json!({"v": 4})), noop_append)
            .unwrap();
        assert!(matches!(n, WriteOnceResult::Inserted { seq_id: 4 }));
    }

    #[test]
    fn load_replayed_recovers_counter_from_assigned_seqs() {
        let log = ShardedFactLog::new();
        let mut f1 = fact("s", "k", "f1", 100.0, serde_json::json!({"v": 1}));
        f1.seq_id = 7;
        let mut f2 = fact("s", "k", "f2", 100.0, serde_json::json!({"v": 2}));
        f2.seq_id = 8;
        log.load_replayed(vec![f1, f2]);
        // next_seq = max(7,8)+1 = 9.
        let n = log
            .push_once(fact("s", "k", "f3", 100.0, serde_json::json!({"v": 3})), noop_append)
            .unwrap();
        assert!(matches!(n, WriteOnceResult::Inserted { seq_id: 9 }));
    }

    #[test]
    fn facts_by_seq_window_is_clock_free() {
        let log = ShardedFactLog::new();
        // Assign seq 1..4 with DECREASING transaction_time — seq must ignore tt.
        for (i, id) in ["a", "b", "c", "d"].iter().enumerate() {
            log.push_once(
                fact("s", "k", id, 1000.0 - i as f64, serde_json::json!({"n": i})),
                noop_append,
            )
            .unwrap();
        }
        // (after_seq=1, until=3] -> seq 2,3.
        let win = log.facts_by_seq("s", 1, Some(3));
        assert_eq!(
            win.iter().map(|f| f.seq_id).collect::<Vec<_>>(),
            vec![2, 3]
        );
        // after_seq only.
        let tail = log.facts_by_seq("s", 2, None);
        assert_eq!(tail.iter().map(|f| f.seq_id).collect::<Vec<_>>(), vec![3, 4]);
    }
}
