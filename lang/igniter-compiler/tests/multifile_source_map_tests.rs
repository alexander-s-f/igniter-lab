// LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3
//
// Per-file source mapping for multifile / project-mode builds. The merged
// `Lab.Multifile.Universe` program emits a `source_line_map` (merged_line ->
// {source_path, module_path, original_line}); diagnostics that carry a merged
// line are enriched with that origin. Typecheck OOF diagnostics currently carry
// `line: null` and therefore cannot be enriched yet (documented).

use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;

const FIX: &str = "tests/fixtures/source_map";

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Run an explicit multifile `compile a.ig b.ig --out OUT`; return (result_json, report_json).
fn compile_multifile(files: &[&str], out_name: &str) -> (Value, Value) {
    let out = std::env::temp_dir().join(format!("igc_slm_{}.igapp", out_name));
    let mut args: Vec<String> = vec!["compile".into()];
    for f in files {
        args.push(format!("{}/{}", FIX, f));
    }
    args.push("--out".into());
    args.push(out.to_string_lossy().to_string());

    let output = Command::new(bin()).args(&args).output().expect("run binary");
    let result: Value =
        serde_json::from_slice(&output.stdout).expect("result json");
    let report = read_report(&out, out_name);
    (result, report)
}

/// Read the compilation report from whichever layout was produced.
fn read_report(out_igapp: &PathBuf, out_name: &str) -> Value {
    let inside = out_igapp.join("compilation_report.json");
    let sibling = std::env::temp_dir().join(format!("igc_slm_{}.compilation_report.json", out_name));
    for p in [inside, sibling] {
        if let Ok(s) = std::fs::read_to_string(&p) {
            return serde_json::from_str(&s).unwrap();
        }
    }
    Value::Null
}

fn line_map(report: &Value) -> Vec<Value> {
    report
        .get("source_line_map")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
}

// ── Acceptance 4 + 5: map back to source unit; original lines stay original ──

#[test]
fn valid_multifile_maps_lines_back_to_units() {
    let (result, report) = compile_multifile(&["a.ig", "b.ig"], "valid");
    assert_eq!(result["status"], "ok", "result: {result}");
    let map = line_map(&report);
    assert!(!map.is_empty(), "source_line_map must be emitted");

    // `pure contract C {` is original line 4 of b.ig (after module/import header).
    let contract = map
        .iter()
        .find(|e| {
            e["source_path"].as_str().unwrap_or("").ends_with("b.ig")
                && e["original_line"].as_u64() == Some(4)
        })
        .expect("contract line of b.ig mapped");
    assert_eq!(contract["module_path"], "Map.B");

    // `type Rec {` is original line 3 of a.ig (line 1 = module, line 2 = blank).
    let typ = map
        .iter()
        .find(|e| {
            e["source_path"].as_str().unwrap_or("").ends_with("a.ig")
                && e["original_line"].as_u64() == Some(3)
        })
        .expect("type line of a.ig mapped");
    assert_eq!(typ["module_path"], "Map.A");

    // Acceptance 5: b.ig's FIRST emitted line is original 3 (the blank after the
    // 2-line header), NOT compacted to 1 — stripped header lines still advance.
    let min_b = map
        .iter()
        .filter(|e| e["source_path"].as_str().unwrap_or("").ends_with("b.ig"))
        .filter_map(|e| e["original_line"].as_u64())
        .min()
        .unwrap();
    assert_eq!(min_b, 3, "header lines must not compact original line numbers");
}

#[test]
fn line_map_present_in_semantic_ir() {
    let out = std::env::temp_dir().join("igc_slm_ir.igapp");
    Command::new(bin())
        .args([
            "compile",
            &format!("{FIX}/a.ig"),
            &format!("{FIX}/b.ig"),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    let ir: Value = serde_json::from_str(
        &std::fs::read_to_string(out.join("semantic_ir_program.json")).unwrap(),
    )
    .unwrap();
    assert!(ir.get("source_line_map").and_then(|v| v.as_array()).is_some());
}

// ── Acceptance 7 (positive): parse diagnostics carry a merged line → enriched ─

#[test]
fn parse_error_diagnostic_is_enriched_with_origin() {
    let (result, report) = compile_multifile(&["a.ig", "b_parse_error.ig"], "parse");
    assert_eq!(result["status"], "error", "result: {result}");
    assert!(report.get("source_line_map").is_some(), "map attached on parse-error path");

    let diags = result["diagnostics"].as_array().unwrap();
    let enriched = diags
        .iter()
        .find(|d| d.get("original_line").is_some())
        .expect("a parse diagnostic enriched with origin");
    assert!(enriched["source_path"].as_str().unwrap().ends_with("b_parse_error.ig"));
    assert_eq!(enriched["module_path"], "Map.B");
    // `input @@@ bad` is original line 5 of b_parse_error.ig.
    assert_eq!(enriched["original_line"].as_u64(), Some(5));
    // The existing merged `line` field is left untouched (still a number).
    assert!(enriched["line"].as_u64().is_some());
}

// ── Acceptance 7 (conditional): typecheck OOF carries line:null → not enriched ─

#[test]
fn typecheck_oof_has_null_line_and_is_not_enriched() {
    let (result, report) = compile_multifile(&["a.ig", "b_typecheck_oof.ig"], "tc");
    assert_eq!(result["status"], "oof", "result: {result}");
    // The map is still emitted as evidence...
    assert!(!line_map(&report).is_empty(), "source_line_map emitted even when diags can't be enriched");
    // ...but the OOF-P1 diagnostic has line:null and therefore no origin fields.
    let diags = result["diagnostics"].as_array().unwrap();
    let oof = diags.iter().find(|d| d["rule"] == "OOF-P1").expect("OOF-P1 present");
    assert!(oof["line"].is_null(), "merged typecheck diag currently has line:null");
    assert!(oof.get("original_line").is_none(), "cannot enrich a null-line diagnostic");
}

// ── Acceptance 8: single-file builds have no line map (no regression) ────────

#[test]
fn single_file_has_no_source_line_map() {
    let out = std::env::temp_dir().join("igc_slm_single.igapp");
    let output = Command::new(bin())
        .args(["compile", &format!("{FIX}/a.ig"), "--out", out.to_str().unwrap()])
        .output()
        .unwrap();
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["status"], "ok");
    let report: Value = serde_json::from_str(
        &std::fs::read_to_string(out.join("compilation_report.json")).unwrap(),
    )
    .unwrap();
    assert!(report.get("source_line_map").is_none(), "single-file must not emit a line map");
}

// ── Acceptance 6: overlay honesty — map source_path is the overlay buffer path ─

#[test]
fn overlay_line_map_uses_buffer_path() {
    // Project mode + overlay: the overlaid unit's map entries carry the overlay
    // buffer path (matching P2 source_units), not the on-disk original.
    let base = "tests/fixtures/project_overlay/base";
    let buffer = "tests/fixtures/project_overlay/buffers/main_add_extra.ig";
    let out = std::env::temp_dir().join("igc_slm_overlay.igapp");
    let output = Command::new(bin())
        .args([
            "compile",
            "--project-root",
            base,
            "--entry",
            "Over.Main",
            "--overlay",
            &format!("{base}/main.ig={buffer}"),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["status"], "ok", "result: {result}");
    let report: Value = serde_json::from_str(
        &std::fs::read_to_string(out.join("compilation_report.json")).unwrap(),
    )
    .unwrap();
    let map = line_map(&report);
    let over_main: Vec<&Value> = map.iter().filter(|e| e["module_path"] == "Over.Main").collect();
    assert!(!over_main.is_empty(), "Over.Main lines mapped");
    for e in over_main {
        assert!(
            e["source_path"].as_str().unwrap().ends_with("buffers/main_add_extra.ig"),
            "overlaid unit must carry the overlay buffer path, got {}",
            e["source_path"]
        );
    }
}
