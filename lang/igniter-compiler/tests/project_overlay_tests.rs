// LAB-COMPILER-PROJECT-OVERLAY-P2
//
// Focused tests for IDE overlay support in project-root compile mode:
//   igniter_compiler compile --project-root ROOT --entry MODULE \
//       --overlay PROJECT_PATH=OVERLAY_PATH ... --out OUT.igapp
//
// Resolution-level assertions use `project::resolve_entry_with_overlays`.
// End-to-end assertions invoke the compiled binary and inspect its
// compiler_result JSON + emitted .igapp source_units.

use igniter_compiler::project::{self, ProjectError, ProjectOverlay};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

const BASE: &str = "tests/fixtures/project_overlay/base";
const BUF: &str = "tests/fixtures/project_overlay/buffers";

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn overlay(original: &str, buffer: &str) -> ProjectOverlay {
    ProjectOverlay {
        original_path: PathBuf::from(original),
        overlay_path: PathBuf::from(buffer),
    }
}

fn module_names(paths: &[PathBuf]) -> Vec<String> {
    let mut names: Vec<String> = paths
        .iter()
        .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
        .collect();
    names.sort();
    names
}

/// Invoke the binary in project mode with overlays; return parsed result JSON.
fn run(entry: &str, overlays: &[(&str, &str)], out_name: &str) -> Value {
    let out = std::env::temp_dir().join(format!("igc_ov_{}.igapp", out_name));
    let mut args: Vec<String> = vec![
        "compile".into(),
        "--project-root".into(),
        BASE.into(),
        "--entry".into(),
        entry.into(),
    ];
    for (orig, buf) in overlays {
        args.push("--overlay".into());
        args.push(format!("{}={}", orig, buf));
    }
    args.push("--out".into());
    args.push(out.to_string_lossy().to_string());

    let output = Command::new(bin()).args(&args).output().expect("run binary");
    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(&stdout).unwrap_or_else(|e| panic!("bad JSON: {e}\n{stdout}"))
}

/// (module, source_path) pairs from the emitted semantic_ir source_units.
fn source_units(out_name: &str) -> Vec<(String, String)> {
    let ir = std::env::temp_dir()
        .join(format!("igc_ov_{}.igapp", out_name))
        .join("semantic_ir_program.json");
    let v: Value = serde_json::from_str(&std::fs::read_to_string(&ir).unwrap()).unwrap();
    let mut units: Vec<(String, String)> = v["source_units"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| {
            (
                u["module"].as_str().unwrap().to_string(),
                u["source_path"].as_str().unwrap().to_string(),
            )
        })
        .collect();
    units.sort();
    units
}

fn rules(result: &Value) -> Vec<String> {
    result["diagnostics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["rule"].as_str().unwrap_or("").to_string())
        .collect()
}

// ── Acceptance 1: no overlay → P1 behavior unchanged ─────────────────────────

#[test]
fn no_overlay_matches_p1() {
    // resolve_entry_with_overlays with empty slice == resolve_entry.
    let a = project::resolve_entry(Path::new(BASE), "Over.Main").unwrap();
    let b = project::resolve_entry_with_overlays(Path::new(BASE), "Over.Main", &[]).unwrap();
    assert_eq!(a, b);
    assert_eq!(module_names(&a), vec!["main.ig", "types.ig"]);

    let result = run("Over.Main", &[], "acc1");
    assert_eq!(result["status"], "ok");
    // Disk paths, no overlay temp paths.
    assert!(source_units("acc1").iter().all(|(_, p)| p.contains("/base/")));
}

// ── Acceptance 2: overlay content wins over disk for the mapped file ─────────

#[test]
fn overlay_content_wins() {
    let result = run(
        "Over.Main",
        &[(&format!("{BASE}/main.ig"), &format!("{BUF}/main_add_extra.ig"))],
        "acc2",
    );
    assert_eq!(result["status"], "ok", "result: {result}");
    let units = source_units("acc2");
    // The Over.Main unit's source evidence is the OVERLAY (buffer) path, not disk.
    let main = units.iter().find(|(m, _)| m == "Over.Main").unwrap();
    assert!(
        main.1.contains("/buffers/main_add_extra.ig"),
        "overlaid unit should carry the overlay path, got {}",
        main.1
    );
}

// ── Acceptance 3: overlay can add an import; closure includes new module ─────

#[test]
fn overlay_adds_import_extends_closure() {
    let paths = project::resolve_entry_with_overlays(
        Path::new(BASE),
        "Over.Main",
        &[overlay(&format!("{BASE}/main.ig"), &format!("{BUF}/main_add_extra.ig"))],
    )
    .unwrap();
    // Disk main.ig imports only Types; the overlay adds Extra.
    assert_eq!(module_names(&paths), vec!["extra.ig", "main_add_extra.ig", "types.ig"]);

    let result = run(
        "Over.Main",
        &[(&format!("{BASE}/main.ig"), &format!("{BUF}/main_add_extra.ig"))],
        "acc3",
    );
    assert_eq!(result["status"], "ok");
    let mods: Vec<String> = source_units("acc3").into_iter().map(|(m, _)| m).collect();
    assert!(mods.contains(&"Over.Extra".to_string()));
}

// ── Acceptance 4: overlay can remove an import; stale disk import dropped ────

#[test]
fn overlay_removes_import_shrinks_closure() {
    let paths = project::resolve_entry_with_overlays(
        Path::new(BASE),
        "Over.Main",
        &[overlay(&format!("{BASE}/main.ig"), &format!("{BUF}/main_no_import.ig"))],
    )
    .unwrap();
    // Disk main.ig imports Types; overlay drops it → closure is the single file.
    assert_eq!(module_names(&paths), vec!["main_no_import.ig"]);

    let result = run(
        "Over.Main",
        &[(&format!("{BASE}/main.ig"), &format!("{BUF}/main_no_import.ig"))],
        "acc4",
    );
    assert_eq!(result["status"], "ok");
    let mods: Vec<String> = source_units("acc4").into_iter().map(|(m, _)| m).collect();
    assert!(!mods.contains(&"Over.Types".to_string()));
}

// ── Acceptance 5: overlay body change is reflected in diagnostics ────────────

#[test]
fn overlay_body_change_reflected_in_diagnostics() {
    // Disk main.ig is valid; the overlay references a nonexistent field.
    let result = run(
        "Over.Main",
        &[(&format!("{BASE}/main.ig"), &format!("{BUF}/main_bad_field.ig"))],
        "acc5",
    );
    assert_eq!(result["status"], "oof");
    assert!(rules(&result).contains(&"OOF-P1".to_string()), "result: {result}");
}

// ── Acceptance 6: missing overlay file → deterministic diagnostic, no panic ──

#[test]
fn missing_overlay_file_is_diagnostic() {
    let err = project::resolve_entry_with_overlays(
        Path::new(BASE),
        "Over.Main",
        &[overlay(&format!("{BASE}/main.ig"), "/no/such/buffer.ig")],
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-PROJ-OVERLAY-MISSING"),
        ProjectError::Io(e) => panic!("expected diagnostic, got io: {e}"),
    }

    let result = run(
        "Over.Main",
        &[(&format!("{BASE}/main.ig"), "/no/such/buffer.ig")],
        "acc6",
    );
    assert_eq!(result["status"], "oof");
    assert_eq!(rules(&result), vec!["OOF-PROJ-OVERLAY-MISSING"]);
}

// ── Acceptance 7: overlay original outside source roots is refused ───────────

#[test]
fn overlay_original_outside_roots_refused() {
    let err = project::resolve_entry_with_overlays(
        Path::new(BASE),
        "Over.Main",
        // original lives under buffers/, which is NOT inside the base/ root.
        &[overlay(&format!("{BUF}/main_no_import.ig"), &format!("{BUF}/main_no_import.ig"))],
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-PROJ-OVERLAY-OUTSIDE");
            assert!(d.original_path.is_some());
        }
        ProjectError::Io(e) => panic!("expected diagnostic, got io: {e}"),
    }
}

// ── Acceptance 8: multiple overlays are deterministic ────────────────────────

#[test]
fn multiple_overlays_are_deterministic() {
    let ov = [
        (format!("{BASE}/main.ig"), format!("{BUF}/main_add_extra.ig")),
        (format!("{BASE}/extra.ig"), format!("{BUF}/extra_variant.ig")),
    ];
    let pairs: Vec<(&str, &str)> = ov.iter().map(|(a, b)| (a.as_str(), b.as_str())).collect();

    let r1 = run("Over.Main", &pairs, "acc8a");
    let r2 = run("Over.Main", &pairs, "acc8b");
    assert_eq!(r1["status"], "ok", "result: {r1}");
    assert_eq!(r1["source_hash"], r2["source_hash"]);
    assert_eq!(source_units("acc8a"), source_units("acc8b"));

    // Both overlay buffers are reflected in the evidence.
    let units = source_units("acc8a");
    assert!(units.iter().any(|(m, p)| m == "Over.Main" && p.contains("main_add_extra.ig")));
    assert!(units.iter().any(|(m, p)| m == "Over.Extra" && p.contains("extra_variant.ig")));
}

// ── Acceptance 9: duplicate module via overlay content still detected ────────

#[test]
fn duplicate_module_from_overlay_detected() {
    // Overlay rewrites main.ig to declare `module Over.Types`, colliding with
    // the on-disk types.ig.
    let err = project::resolve_entry_with_overlays(
        Path::new(BASE),
        "Over.Types",
        &[overlay(&format!("{BASE}/main.ig"), &format!("{BUF}/main_as_types_dup.ig"))],
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP4");
            assert_eq!(d.module_path.as_deref(), Some("Over.Types"));
            assert_eq!(d.source_paths.len(), 2);
        }
        ProjectError::Io(e) => panic!("expected diagnostic, got io: {e}"),
    }

    let result = run(
        "Over.Types",
        &[(&format!("{BASE}/main.ig"), &format!("{BUF}/main_as_types_dup.ig"))],
        "acc9",
    );
    assert_eq!(result["status"], "oof");
    assert_eq!(rules(&result), vec!["OOF-IMP4"]);
}

// ── Bonus: overlay an entry file that does not exist on disk (new buffer) ────

#[test]
fn overlay_injects_new_unsaved_file() {
    let paths = project::resolve_entry_with_overlays(
        Path::new(BASE),
        "Over.New",
        // base/new_module.ig is NOT on disk; the overlay injects it.
        &[overlay(&format!("{BASE}/new_module.ig"), &format!("{BUF}/new_module.ig"))],
    )
    .unwrap();
    assert_eq!(module_names(&paths), vec!["new_module.ig"]);

    let result = run(
        "Over.New",
        &[(&format!("{BASE}/new_module.ig"), &format!("{BUF}/new_module.ig"))],
        "accN",
    );
    assert_eq!(result["status"], "ok", "result: {result}");
}
