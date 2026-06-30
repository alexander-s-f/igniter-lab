//! LAB-IGNITER-STDLIB-SURFACE-HELP-P1 — a queryable view over the canon stdlib inventory.
//!
//! DX / knowledge surface only: it reads the SAME embedded `stdlib-inventory.json` that import
//! resolution uses (`multifile.rs`), and exposes `list`/`search`/`show`/`explain` for the `igc` CLI.
//! It changes NO language/typecheck/lowering/VM/package semantics and maintains NO second docs table —
//! the inventory schema remains the canonical contract.

use serde::Serialize;
use serde_json::{json, Value};

/// The canon stdlib inventory, embedded at build time (same source as `multifile.rs`).
const INVENTORY_JSON: &str = include_str!("../../../igniter-lang/docs/spec/stdlib-inventory.json");

/// Parse the embedded inventory. Returns `Value::Null` only if the embedded file is unparseable
/// (a build-time invariant; never expected at runtime).
pub fn inventory_value() -> Value {
    serde_json::from_str(INVENTORY_JSON).unwrap_or(Value::Null)
}

/// The recorded `stdlib_surface_digest`, if present.
pub fn surface_digest() -> Option<String> {
    inventory_value()
        .get("stdlib_surface_digest")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// A narrow, agent-stable projection of one inventory entry. The full inventory schema stays
/// authoritative; this is the help-surface view.
#[derive(Debug, Clone, Serialize)]
pub struct SurfaceEntry {
    pub canonical_name: String,
    pub aliases: Vec<String>,
    pub category: String,
    pub signature: String,
    pub diagnostics: Vec<String>,
    pub lifecycle_status: String,
    pub lowering_status: String,
    pub proof_lineage: Vec<String>,
}

fn str_field(e: &Value, key: &str) -> String {
    e.get(key).and_then(|v| v.as_str()).unwrap_or("").to_string()
}

fn str_array(e: &Value, key: &str) -> Vec<String> {
    e.get(key)
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect())
        .unwrap_or_default()
}

fn alias_names(e: &Value) -> Vec<String> {
    e.get("aliases")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|al| al.get("name").and_then(|n| n.as_str()).map(|s| s.to_string())).collect())
        .unwrap_or_default()
}

/// Build a human-readable signature, e.g. `find(Collection[T], (T) -> Bool) -> Option[T]`.
fn signature_of(e: &Value) -> String {
    let aliases = alias_names(e);
    let head = aliases
        .first()
        .cloned()
        .unwrap_or_else(|| str_field(e, "canonical_name"));
    let inputs = str_array(e, "input_signature").join(", ");
    let output = str_field(e, "output_signature");
    if output.is_empty() {
        format!("{head}({inputs})")
    } else {
        format!("{head}({inputs}) -> {output}")
    }
}

fn entry_of(e: &Value) -> SurfaceEntry {
    SurfaceEntry {
        canonical_name: str_field(e, "canonical_name"),
        aliases: alias_names(e),
        category: str_field(e, "category"),
        signature: signature_of(e),
        diagnostics: str_array(e, "diagnostics"),
        lifecycle_status: str_field(e, "lifecycle_status"),
        lowering_status: str_field(e, "lowering_status"),
        proof_lineage: str_array(e, "proof_lineage"),
    }
}

fn raw_entries() -> Vec<Value> {
    inventory_value()
        .get("entries")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
}

/// All entries, sorted by canonical_name (deterministic).
pub fn list_entries() -> Vec<SurfaceEntry> {
    let mut v: Vec<SurfaceEntry> = raw_entries().iter().map(entry_of).collect();
    v.sort_by(|a, b| a.canonical_name.cmp(&b.canonical_name));
    v
}

/// Entries in a single category, sorted by canonical_name.
pub fn list_by_category(category: &str) -> Vec<SurfaceEntry> {
    list_entries()
        .into_iter()
        .filter(|e| e.category == category)
        .collect()
}

/// Resolve an entry by canonical_name, semantic_ir_name, or a source alias.
pub fn show_entry(name_or_alias: &str) -> Option<SurfaceEntry> {
    raw_entries()
        .iter()
        .find(|e| {
            str_field(e, "canonical_name") == name_or_alias
                || str_field(e, "semantic_ir_name") == name_or_alias
                || alias_names(e).iter().any(|a| a == name_or_alias)
        })
        .map(entry_of)
}

/// Entries whose `diagnostics` include the given rule (e.g. `OOF-COL3`).
pub fn explain_diagnostic(rule: &str) -> Vec<SurfaceEntry> {
    list_entries()
        .into_iter()
        .filter(|e| e.diagnostics.iter().any(|d| d == rule))
        .collect()
}

/// A ranked search hit (lower `score` = better; ties broken by canonical_name).
#[derive(Debug, Clone, Serialize)]
pub struct SearchHit {
    #[serde(flatten)]
    pub entry: SurfaceEntry,
    pub score: i64,
}

/// The best field-rank at which `token` matches `e` (0=name/alias exact, 1=name/alias substring,
/// 2=category/diagnostics/signature, 3=examples/proof_lineage), or `None` if it matches nothing.
fn token_rank(e: &Value, token: &str) -> Option<i64> {
    let canonical = str_field(e, "canonical_name").to_lowercase();
    let last_seg = canonical.rsplit('.').next().unwrap_or("").to_string();
    let aliases: Vec<String> = alias_names(e).iter().map(|a| a.to_lowercase()).collect();

    if aliases.iter().any(|a| a == token) || last_seg == token {
        return Some(0);
    }
    if canonical.contains(token) || aliases.iter().any(|a| a.contains(token)) {
        return Some(1);
    }
    let mid = [str_field(e, "category"), signature_of(e)]
        .into_iter()
        .chain(str_array(e, "diagnostics"))
        .any(|f| f.to_lowercase().contains(token));
    if mid {
        return Some(2);
    }
    let lo = str_array(e, "examples")
        .into_iter()
        .chain(str_array(e, "proof_lineage"))
        .chain(str_array(e, "input_signature"))
        .chain([str_field(e, "output_signature")])
        .any(|f| f.to_lowercase().contains(token));
    if lo {
        return Some(3);
    }
    None
}

/// Deterministic, OR-semantics substring search. An entry is a hit if it matches ≥1 query token;
/// hits are ranked by (more tokens matched first, then best field-rank, then canonical_name) so
/// direct name/alias matches sort ahead of incidental field matches.
pub fn search_entries(query: &str) -> Vec<SearchHit> {
    let tokens: Vec<String> = query
        .split_whitespace()
        .map(|t| t.to_lowercase())
        .filter(|t| !t.is_empty())
        .collect();
    if tokens.is_empty() {
        return Vec::new();
    }

    let mut hits: Vec<(i64, i64, SurfaceEntry)> = Vec::new(); // (matched_count, best_rank, entry)
    for e in raw_entries() {
        let ranks: Vec<i64> = tokens.iter().filter_map(|t| token_rank(&e, t)).collect();
        if ranks.is_empty() {
            continue;
        }
        let matched = ranks.len() as i64;
        let best = *ranks.iter().min().unwrap();
        hits.push((matched, best, entry_of(&e)));
    }
    // more tokens matched first; then better (lower) field rank; then canonical_name asc.
    hits.sort_by(|a, b| {
        b.0.cmp(&a.0)
            .then(a.1.cmp(&b.1))
            .then(a.2.canonical_name.cmp(&b.2.canonical_name))
    });
    hits.into_iter()
        .map(|(matched, best, entry)| SearchHit {
            entry,
            // composite score: lower is better. fewer-matched penalized, worse field-rank penalized.
            score: (tokens.len() as i64 - matched) * 10 + best,
        })
        .collect()
}

// ── CLI JSON builders (stable `kind` envelopes for agents) ───────────────────────────────────────

fn digest_value() -> Value {
    surface_digest().map(Value::String).unwrap_or(Value::Null)
}

pub fn list_result_json(category: Option<&str>) -> Value {
    let entries = match category {
        Some(c) => list_by_category(c),
        None => list_entries(),
    };
    json!({
        "kind": "igniter_stdlib_list_result",
        "ok": true,
        "digest": digest_value(),
        "category": category,
        "count": entries.len(),
        "entries": entries,
    })
}

pub fn search_result_json(query: &str) -> Value {
    let matches = search_entries(query);
    json!({
        "kind": "igniter_stdlib_search_result",
        "ok": true,
        "digest": digest_value(),
        "query": query,
        "count": matches.len(),
        "matches": matches,
    })
}

/// `(json, ok)` — `ok=false` (not_found) when the name/alias resolves to nothing.
pub fn show_result_json(name_or_alias: &str) -> (Value, bool) {
    match show_entry(name_or_alias) {
        Some(entry) => (
            json!({
                "kind": "igniter_stdlib_show_result",
                "ok": true,
                "digest": digest_value(),
                "query": name_or_alias,
                "entry": entry,
            }),
            true,
        ),
        None => (
            json!({
                "kind": "igniter_stdlib_show_result",
                "ok": false,
                "digest": digest_value(),
                "query": name_or_alias,
                "reason": "not_found",
            }),
            false,
        ),
    }
}

/// `explain` is always `ok=true`; an unknown/unused rule yields `entries: []` (a valid empty query,
/// not an error). Exit code stays 0 even when empty.
pub fn explain_result_json(rule: &str) -> Value {
    let entries = explain_diagnostic(rule);
    json!({
        "kind": "igniter_diagnostic_explain_result",
        "ok": true,
        "digest": digest_value(),
        "rule": rule,
        "count": entries.len(),
        "entries": entries.iter().map(|e| e.canonical_name.clone()).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inventory_parses_and_has_digest() {
        assert!(inventory_value().is_object());
        assert!(surface_digest().is_some());
        assert!(!list_entries().is_empty());
    }

    #[test]
    fn show_resolves_canonical_and_alias() {
        assert_eq!(
            show_entry("stdlib.collection.map").map(|e| e.canonical_name),
            Some("stdlib.collection.map".to_string())
        );
        assert_eq!(
            show_entry("map").map(|e| e.canonical_name),
            Some("stdlib.collection.map".to_string())
        );
        assert!(show_entry("definitely.not.a.real.stdlib.fn").is_none());
    }

    #[test]
    fn search_puts_direct_alias_match_first() {
        let hits = search_entries("collection map");
        let first = &hits.first().expect("a hit").entry.canonical_name;
        assert_eq!(first, "stdlib.collection.map", "exact alias `map` must rank first; got {first}");
    }

    #[test]
    fn category_filter_is_collection_only() {
        let coll = list_by_category("collection");
        assert!(!coll.is_empty());
        assert!(coll.iter().all(|e| e.category == "collection"));
    }
}
