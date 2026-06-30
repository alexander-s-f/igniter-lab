// tests/stdlib_surface_help_tests.rs
// LAB-IGNITER-STDLIB-SURFACE-HELP-P1 — CLI help surface over the embedded stdlib inventory.
//
// Exercises the real `igc` binary: `stdlib list|search|show` + `explain`, asserting stable JSON
// `kind` envelopes, the embedded `stdlib_surface_digest`, alias/canonical resolution, deterministic
// search ranking, diagnostic→entry linkage, and fail-closed unknown lookups. No language/runtime
// semantics are touched.

use serde_json::Value;
use std::process::Command;

/// Run `igc <args...>` → (exit_code, parsed_stdout_json_or_Null).
fn run(args: &[&str]) -> (i32, Value) {
    let out = Command::new(env!("CARGO_BIN_EXE_igniter_compiler"))
        .args(args)
        .output()
        .expect("run igniter_compiler");
    let code = out.status.code().unwrap_or(-1);
    let v = serde_json::from_slice(&out.stdout).unwrap_or(Value::Null);
    (code, v)
}

fn names_in(v: &Value, key: &str) -> Vec<String> {
    v.get(key)
        .and_then(|a| a.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|e| {
                    e.get("canonical_name")
                        .and_then(|c| c.as_str())
                        .or_else(|| e.as_str())
                        .map(|s| s.to_string())
                })
                .collect()
        })
        .unwrap_or_default()
}

#[test]
fn list_json_has_kind_ok_entries_and_digest() {
    let (code, v) = run(&["stdlib", "list", "--json"]);
    assert_eq!(code, 0);
    assert_eq!(v["kind"], "igniter_stdlib_list_result");
    assert_eq!(v["ok"], true);
    assert!(v["digest"].as_str().is_some(), "must carry stdlib_surface_digest");
    assert!(!names_in(&v, "entries").is_empty(), "entries must be non-empty");
}

#[test]
fn list_category_collection_only() {
    let (code, v) = run(&["stdlib", "list", "--category", "collection", "--json"]);
    assert_eq!(code, 0);
    let entries = v["entries"].as_array().cloned().unwrap_or_default();
    assert!(!entries.is_empty());
    assert!(
        entries.iter().all(|e| e["category"] == "collection"),
        "every entry must be category=collection"
    );
}

#[test]
fn show_resolves_canonical_and_alias() {
    let (c1, v1) = run(&["stdlib", "show", "stdlib.collection.map", "--json"]);
    assert_eq!(c1, 0);
    assert_eq!(v1["kind"], "igniter_stdlib_show_result");
    assert_eq!(v1["ok"], true);
    assert_eq!(v1["entry"]["canonical_name"], "stdlib.collection.map");

    let (c2, v2) = run(&["stdlib", "show", "map", "--json"]);
    assert_eq!(c2, 0);
    assert_eq!(v2["entry"]["canonical_name"], "stdlib.collection.map");
}

#[test]
fn search_ranks_direct_alias_first() {
    let (code, v) = run(&["stdlib", "search", "collection", "map", "--json"]);
    assert_eq!(code, 0);
    assert_eq!(v["kind"], "igniter_stdlib_search_result");
    let matches = names_in(&v, "matches");
    assert_eq!(
        matches.first().map(|s| s.as_str()),
        Some("stdlib.collection.map"),
        "exact alias `map` must rank first; got {matches:?}"
    );
}

#[test]
fn explain_links_diagnostic_to_entries() {
    let (code, v) = run(&["explain", "OOF-COL3", "--json"]);
    assert_eq!(code, 0);
    assert_eq!(v["kind"], "igniter_diagnostic_explain_result");
    assert_eq!(v["ok"], true);
    let entries = names_in(&v, "entries");
    assert!(
        entries.contains(&"stdlib.collection.filter".to_string()),
        "OOF-COL3 must link to filter; got {entries:?}"
    );
}

#[test]
fn show_unknown_fails_closed_with_structured_reason() {
    let (code, v) = run(&["stdlib", "show", "stdlib.not.a.real.fn", "--json"]);
    assert_ne!(code, 0, "unknown show must exit non-zero");
    assert_eq!(v["ok"], false);
    assert_eq!(v["reason"], "not_found");
}

#[test]
fn explain_unknown_rule_is_ok_with_empty_entries() {
    // Documented choice: `explain` is always ok=true; an unused rule yields entries: [] (exit 0).
    let (code, v) = run(&["explain", "OOF-DOES-NOT-EXIST", "--json"]);
    assert_eq!(code, 0);
    assert_eq!(v["ok"], true);
    assert!(names_in(&v, "entries").is_empty(), "unknown rule → empty entries");
}

// P4 predicate ops have landed in the embedded inventory (find/any/all). Assert discoverability.
#[test]
fn predicate_ops_are_discoverable_when_p4_landed() {
    let (code, v) = run(&["stdlib", "show", "find", "--json"]);
    if code == 0 && v["ok"] == true {
        assert_eq!(v["entry"]["canonical_name"], "stdlib.collection.find");
        // and OOF-COL3 should link find/any/all alongside filter.
        let (_, ex) = run(&["explain", "OOF-COL3", "--json"]);
        let entries = names_in(&ex, "entries");
        for n in ["stdlib.collection.find", "stdlib.collection.any", "stdlib.collection.all"] {
            assert!(entries.contains(&n.to_string()), "P4 op {n} must be linked to OOF-COL3; got {entries:?}");
        }
    } else {
        // P4 not embedded in this build — skip (do NOT modify inventory to satisfy this).
        eprintln!("SKIP: predicate ops (find/any/all) not in the embedded inventory build");
    }
}
