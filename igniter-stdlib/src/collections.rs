// src/collections.rs
// Collection helper candidates for lab compiler and VM proofs

use serde_json::Value;

// Generates an exclusive range [start..end)
pub fn range(start: i64, end: i64) -> Vec<Value> {
    (start..end).map(|v| Value::Number(v.into())).collect()
}

// Filters a collection using a predicate function
pub fn filter<F>(coll: &[Value], predicate: F) -> Vec<Value>
where
    F: Fn(&Value) -> bool,
{
    coll.iter().filter(|&v| predicate(v)).cloned().collect()
}

// Maps a collection using a mapper function
pub fn map<F>(coll: &[Value], mapper: F) -> Vec<Value>
where
    F: Fn(&Value) -> Value,
{
    coll.iter().map(|v| mapper(v)).collect()
}

// Folds a collection into a single value using an accumulator
pub fn fold<F>(coll: &[Value], initial: Value, accumulator: F) -> Value
where
    F: Fn(&Value, &Value) -> Value,
{
    coll.iter().fold(initial, |acc, v| accumulator(&acc, v))
}

// Returns the first element of a collection, if present
pub fn first(coll: &[Value]) -> Option<Value> {
    coll.first().cloned()
}

// Returns the count of elements in a collection
pub fn count(coll: &[Value]) -> usize {
    coll.len()
}
