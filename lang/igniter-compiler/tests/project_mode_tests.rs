// LAB-COMPILER-PROJECT-MODE-COMPILE-P1
//
// Focused tests for canonical project-root compile mode:
//   igniter_compiler compile --project-root ROOT --entry MODULE --out OUT
//
// Resolution-level assertions use `project::resolve_entry` directly.
// End-to-end assertions invoke the compiled binary and inspect its
// compiler_result JSON + emitted .igapp evidence.

use igniter_compiler::project::{self, ProjectError};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

const FIX: &str = "tests/fixtures/project_mode";

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn modules(paths: &[PathBuf]) -> Vec<String> {
    let mut names: Vec<String> = paths
        .iter()
        .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
        .collect();
    names.sort();
    names
}

/// Run project mode against a fixture; return parsed compiler_result JSON.
fn run_project(fixture: &str, entry: &str, out_name: &str) -> Value {
    let out = std::env::temp_dir().join(format!("igc_pm_{}.igapp", out_name));
    let output = Command::new(bin())
        .args([
            "compile",
            "--project-root",
            &format!("{}/{}", FIX, fixture),
            "--entry",
            entry,
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run binary");
    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(&stdout).unwrap_or_else(|e| panic!("bad JSON: {e}\n{stdout}"))
}

fn source_unit_modules(out_name: &str) -> Vec<String> {
    let ir = std::env::temp_dir()
        .join(format!("igc_pm_{}.igapp", out_name))
        .join("semantic_ir_program.json");
    let v: Value = serde_json::from_str(&std::fs::read_to_string(&ir).unwrap()).unwrap();
    let mut mods: Vec<String> = v["source_units"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["module"].as_str().unwrap().to_string())
        .collect();
    mods.sort();
    mods
}

fn diag_rules(result: &Value) -> Vec<String> {
    result["diagnostics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["rule"].as_str().unwrap_or("").to_string())
        .collect()
}

// ── Acceptance 2: project-root compile assembles entry + imported module ─────

#[test]
fn project_mode_resolves_entry_and_imported_module() {
    let paths = project::resolve_entry(
        Path::new(&format!("{}/basic", FIX)),
        "SparkCRM.CallRouter.Webhook",
    )
    .expect("resolve");
    assert_eq!(modules(&paths), vec!["types.ig", "webhook.ig"]);
}

#[test]
fn project_mode_basic_compiles_with_both_source_units() {
    let result = run_project("basic", "SparkCRM.CallRouter.Webhook", "basic");
    assert_eq!(result["status"], "ok", "result: {result}");
    // Both the Webhook and its imported Types module appear as source units;
    // stdlib.collection is NOT a source file.
    let mods = source_unit_modules("basic");
    assert_eq!(
        mods,
        vec!["SparkCRM.CallRouter.Types", "SparkCRM.CallRouter.Webhook"]
    );
    assert!(!mods.iter().any(|m| m.starts_with("stdlib.")));
}

// ── Acceptance 3: transitive A -> B -> C ─────────────────────────────────────

#[test]
fn project_mode_transitive_closure() {
    let paths = project::resolve_entry(Path::new(&format!("{}/transitive", FIX)), "Chain.A")
        .expect("resolve");
    assert_eq!(modules(&paths), vec!["a.ig", "b.ig", "c.ig"]);

    let result = run_project("transitive", "Chain.A", "transitive");
    assert_eq!(result["status"], "ok", "result: {result}");
    assert_eq!(
        source_unit_modules("transitive"),
        vec!["Chain.A", "Chain.B", "Chain.C"]
    );
}

// ── Acceptance 4: missing entry is a deterministic diagnostic, not a panic ───

#[test]
fn project_mode_missing_entry_is_diagnostic() {
    let err = project::resolve_entry(Path::new(&format!("{}/transitive", FIX)), "No.Such.Module")
        .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-PROJ-ENTRY");
            assert_eq!(d.entry_module.as_deref(), Some("No.Such.Module"));
        }
        ProjectError::Io(e) => panic!("expected diagnostic, got io: {e}"),
    }

    let result = run_project("transitive", "No.Such.Module", "missing_entry");
    assert_eq!(result["status"], "oof");
    assert_eq!(diag_rules(&result), vec!["OOF-PROJ-ENTRY"]);
}

// ── Acceptance 5: missing non-stdlib import routes to OOF-IMP2 ───────────────

#[test]
fn project_mode_missing_import_routes_to_oof_imp2() {
    // resolve_entry itself succeeds (it does not report missing imports);
    // the dangling import surfaces in the multi-file pipeline.
    let paths = project::resolve_entry(Path::new(&format!("{}/missing_import", FIX)), "Solo.Entry")
        .expect("resolve");
    assert_eq!(modules(&paths), vec!["entry.ig"]);

    let result = run_project("missing_import", "Solo.Entry", "missing_import");
    assert_eq!(result["status"], "oof");
    assert_eq!(diag_rules(&result), vec!["OOF-IMP2"]);
}

// ── Acceptance 6: duplicate module is deterministic with both source paths ───

#[test]
fn project_mode_duplicate_module_is_deterministic() {
    let err =
        project::resolve_entry(Path::new(&format!("{}/dup_module", FIX)), "Dup.Mod").unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP4");
            assert_eq!(d.module_path.as_deref(), Some("Dup.Mod"));
            assert_eq!(d.source_paths.len(), 2, "both files reported");
            // Deterministic order (sorted).
            let mut sorted = d.source_paths.clone();
            sorted.sort();
            assert_eq!(d.source_paths, sorted);
        }
        ProjectError::Io(e) => panic!("expected diagnostic, got io: {e}"),
    }

    let result = run_project("dup_module", "Dup.Mod", "dup_module");
    assert_eq!(result["status"], "oof");
    assert_eq!(diag_rules(&result), vec!["OOF-IMP4"]);
    let paths = result["diagnostics"][0]["source_paths"].as_array().unwrap();
    assert_eq!(paths.len(), 2);
}

// ── Acceptance 7: directories never define module names ──────────────────────

#[test]
fn project_mode_module_is_from_declaration_not_directory() {
    // A file under deeply/nested/leaf_dir declares `module Flat.Single`.
    let paths =
        project::resolve_entry(Path::new(&format!("{}/nested", FIX)), "Flat.Single").expect("ok");
    assert_eq!(modules(&paths), vec!["leaf.ig"]);

    // The directory path does NOT define an addressable module.
    let err = project::resolve_entry(
        Path::new(&format!("{}/nested", FIX)),
        "deeply.nested.leaf_dir.leaf",
    )
    .unwrap_err();
    assert!(matches!(err, ProjectError::Diagnostic(d) if d.rule == "OOF-PROJ-ENTRY"));
}

// ── Acceptance 9: deterministic file ordering / stable source hash ───────────

#[test]
fn project_mode_repeated_builds_are_deterministic() {
    let r1 = run_project("transitive", "Chain.A", "det1");
    let r2 = run_project("transitive", "Chain.A", "det2");
    assert_eq!(r1["source_hash"], r2["source_hash"]);
    assert_eq!(source_unit_modules("det1"), source_unit_modules("det2"));
}

// ── Acceptance 1: explicit positional multi-file CLI is unchanged ────────────

#[test]
fn explicit_multifile_cli_still_works() {
    let out = std::env::temp_dir().join("igc_pm_explicit.igapp");
    let base = format!("{}/transitive/src", FIX);
    let output = Command::new(bin())
        .args([
            "compile",
            &format!("{}/c.ig", base),
            &format!("{}/b.ig", base),
            &format!("{}/a.ig", base),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run binary");
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["status"], "ok", "result: {result}");
}
