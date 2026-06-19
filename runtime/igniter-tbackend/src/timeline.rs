use crate::fact::FactData;
#[cfg(feature = "ffi")]
use crate::fact::{ruby_hash_to_json_sorted, Fact};
#[cfg(feature = "ffi")]
use magnus::{prelude::*, Error, IntoValue, RArray, RHash, Ruby, Value};
use parking_lot::RwLock;
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

const SHARD_COUNT: usize = 128;

struct ShardInner {
    // Map of (store, key) -> Sorted timeline of FactData (sorted by transaction_time)
    by_key: HashMap<(String, String), Vec<FactData>>,
    // Map of fact_id -> (store, key, index) for fast O(1) id lookup
    by_id: HashMap<String, (String, String, usize)>,
}

pub struct ShardedFactLog {
    shards: Vec<RwLock<ShardInner>>,
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
        ShardedFactLog { shards }
    }

    fn get_shard_index(&self, store: &str, key: &str) -> usize {
        let mut hasher = DefaultHasher::new();
        store.hash(&mut hasher);
        key.hash(&mut hasher);
        (hasher.finish() as usize) % SHARD_COUNT
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

        // Filter by transaction_time window [since, as_of] with a scan — order-independent
        // (the timeline is in arrival order, not sorted by transaction_time). Callers that
        // need ordering sort the result (e.g. backend `facts_for`).
        timeline
            .iter()
            .filter(|fact| {
                since.map_or(true, |s| fact.transaction_time >= s)
                    && as_of.map_or(true, |a| fact.transaction_time <= a)
            })
            .cloned()
            .collect()
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
        // Ensure strictly sorted chronological order across different keys
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

    pub fn stores(&self) -> Vec<String> {
        let mut results = std::collections::HashSet::new();
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

#[cfg(feature = "ffi")]
#[magnus::wrap(class = "Igniter::TBackendPlayground::FactLog", free_immediately, size)]
pub struct FactLog(pub Arc<ShardedFactLog>);

#[cfg(feature = "ffi")]
impl FactLog {
    pub fn rb_new() -> Self {
        FactLog(Arc::new(ShardedFactLog::new()))
    }

    pub fn rb_append(&self, rb_fact: &Fact) -> Value {
        self.0.push(rb_fact.0.clone());
        let ruby = unsafe { Ruby::get_unchecked() };
        ruby.qnil().as_value()
    }

    pub fn rb_replay_fact(&self, rb_fact: &Fact) {
        self.0.push(rb_fact.0.clone());
    }

    pub fn rb_latest_for_native(&self, store: String, key: String, as_of: Option<f64>) -> Value {
        let ruby = unsafe { Ruby::get_unchecked() };
        match self.0.latest_for(&store, &key, as_of) {
            Some(data) => Fact(data).into_value_with(&ruby),
            None => ruby.qnil().as_value(),
        }
    }

    pub fn rb_facts_for_native(
        &self,
        store: String,
        key: Option<String>,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let facts = if let Some(k) = key {
            self.0.facts_for_key(&store, &k, since, as_of)
        } else {
            self.0.facts_for_store(&store, since, as_of)
        };

        let arr = RArray::new();
        for data in facts {
            arr.push(Fact(data).into_value_with(&ruby))?;
        }
        Ok(arr)
    }

    pub fn rb_query_scope_native(
        &self,
        store: String,
        filters: RHash,
        as_of: Option<f64>,
    ) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let filter_json = ruby_hash_to_json_sorted(filters.as_value());
        let facts = self.0.query_scope(&store, &filter_json, as_of);

        let arr = RArray::new();
        for data in facts {
            arr.push(Fact(data).into_value_with(&ruby))?;
        }
        Ok(arr)
    }

    pub fn rb_size(&self) -> usize {
        self.0.size()
    }
}
