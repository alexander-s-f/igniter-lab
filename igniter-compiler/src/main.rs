use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::classifier::Classifier;
use igniter_compiler::typechecker::TypeChecker;
use igniter_compiler::form_registry::FormRegistry;
use igniter_compiler::form_resolver::FormResolver;
use igniter_compiler::emitter::Emitter;
use igniter_compiler::assembler::Assembler;
use igniter_compiler::multifile;

use serde_json::{json, Value, Map};
use sha2::{Sha256, Digest};
use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: igc compile SOURCE [SOURCE ...] --out OUT.igapp");
        std::process::exit(1);
    }

    let command = &args[1];
    if command != "compile" {
        eprintln!("Unsupported command: {}", command);
        std::process::exit(1);
    }

    // LAB-COMPILER-PROJECT-MODE-COMPILE-P1: canonical project-root compile mode.
    // `compile --project-root ROOT --entry MODULE --out OUT`
    // Resolves the transitive import closure for the entry module from the
    // project source roots, then reuses the existing multi-file pipeline.
    if args.iter().any(|a| a == "--project-root") {
        run_project_mode(&args);
        return;
    }

    let Some(out_index) = args.iter().position(|arg| arg == "--out") else {
        eprintln!("Usage: igc compile SOURCE [SOURCE ...] --out OUT.igapp");
        std::process::exit(1);
    };
    if out_index <= 2 || out_index + 1 >= args.len() {
        eprintln!("Usage: igc compile SOURCE [SOURCE ...] --out OUT.igapp");
        std::process::exit(1);
    }

    let source_paths: Vec<String> = args[2..out_index].to_vec();
    let out_path = &args[out_index + 1];

    // Optional --compiler-profile-source
    let mut profile_source = None;
    let mut i = out_index + 2;
    while i < args.len() {
        if args[i] == "--compiler-profile-source" {
            if i + 1 < args.len() {
                let p = &args[i + 1];
                if let Ok(content) = fs::read_to_string(p) {
                    if let Ok(val) = serde_json::from_str(&content) {
                        profile_source = Some(val);
                    }
                }
                i += 2;
            } else {
                eprintln!("--compiler-profile-source requires a path");
                std::process::exit(1);
            }
        } else {
            i += 1;
        }
    }

    let run_result = if source_paths.len() == 1 {
        run_compiler(&source_paths[0], out_path, profile_source)
    } else {
        run_multifile_compiler(&source_paths, out_path, profile_source)
    };

    match run_result {
        Ok(ok) => {
            if !ok {
                std::process::exit(1);
            }
        }
        Err(err) => {
            eprintln!("Internal compiler error: {}", err);
            std::process::exit(1);
        }
    }
}

/// LAB-COMPILER-PROJECT-MODE-COMPILE-P1
/// Parse the project-mode flags, resolve the entry module's import closure, and
/// hand the resolved source files to the existing multi-file pipeline.
fn run_project_mode(args: &[String]) {
    let flag_value = |flag: &str| -> Option<String> {
        args.iter()
            .position(|a| a == flag)
            .and_then(|i| args.get(i + 1).cloned())
    };

    let (Some(root), Some(entry), Some(out_path)) = (
        flag_value("--project-root"),
        flag_value("--entry"),
        flag_value("--out"),
    ) else {
        eprintln!(
            "Usage: igc compile --project-root ROOT --entry MODULE \
             [--overlay PROJECT_PATH=OVERLAY_PATH ...] --out OUT.igapp"
        );
        std::process::exit(1);
    };

    // LAB-COMPILER-PROJECT-OVERLAY-P2: collect zero or more `--overlay a=b`.
    let mut overlays = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--overlay" {
            let Some(spec) = args.get(i + 1) else {
                eprintln!("--overlay requires PROJECT_PATH=OVERLAY_PATH");
                std::process::exit(1);
            };
            let Some((original, overlay)) = spec.split_once('=') else {
                eprintln!(
                    "--overlay expects PROJECT_PATH=OVERLAY_PATH, got '{}'",
                    spec
                );
                std::process::exit(1);
            };
            overlays.push(igniter_compiler::project::ProjectOverlay {
                original_path: Path::new(original).to_path_buf(),
                overlay_path: Path::new(overlay).to_path_buf(),
            });
            i += 2;
        } else {
            i += 1;
        }
    }

    match igniter_compiler::project::resolve_entry_with_overlays(
        Path::new(&root),
        &entry,
        &overlays,
    ) {
        Ok(paths) => {
            let source_paths: Vec<String> =
                paths.iter().map(|p| p.to_string_lossy().to_string()).collect();
            // A single resolved file still goes through the multi-file path so
            // that source_units evidence is always emitted in project mode.
            match run_multifile_compiler(&source_paths, &out_path, None) {
                Ok(true) => {}
                Ok(false) => std::process::exit(1),
                Err(err) => {
                    eprintln!("Internal compiler error: {}", err);
                    std::process::exit(1);
                }
            }
        }
        Err(igniter_compiler::project::ProjectError::Diagnostic(diag)) => {
            emit_project_diagnostic(&diag, &out_path);
            std::process::exit(1);
        }
        Err(igniter_compiler::project::ProjectError::Io(err)) => {
            eprintln!("Internal compiler error (project scan): {}", err);
            std::process::exit(1);
        }
    }
}

/// Render a project-assembly diagnostic as a compiler_result + compilation
/// report, mirroring the multi-file error path so tooling sees a consistent
/// shape.
fn emit_project_diagnostic(diag: &igniter_compiler::project::ProjectDiagnostic, out_path: &str) {
    let diagnostics_json = vec![diag.to_value()];
    let report_path = report_path_for(out_path);
    if let Some(parent) = Path::new(&report_path).parent() {
        let _ = fs::create_dir_all(parent);
    }
    let report = json!({
        "kind": "compilation_report",
        "format_version": "0.1.0",
        "program_id": Value::Null,
        "grammar_version": "igniter-v0",
        "source_hash": Value::Null,
        "source_path": "project:error",
        "pass_result": "oof",
        "stages": {
            "parse": "skipped",
            "project_resolve": "oof",
            "multifile_resolve": "skipped",
            "classify": "skipped",
            "typecheck": "skipped",
            "emit": "skipped"
        },
        "diagnostics": diagnostics_json,
        "semantic_ir_ref": Value::Null
    });
    let _ = fs::write(
        &report_path,
        serde_json::to_string_pretty(&report).unwrap_or_default() + "\n",
    );

    let result = json!({
        "kind": "compiler_result",
        "format_version": "0.1.0",
        "status": "oof",
        "program_id": Value::Null,
        "source_path": "project:error",
        "source_hash": Value::Null,
        "grammar_version": "igniter-v0",
        "stages": {
            "parse": "skipped",
            "project_resolve": "oof",
            "multifile_resolve": "skipped",
            "classify": "skipped",
            "typecheck": "skipped",
            "emit": "skipped",
            "assemble": "skipped"
        },
        "igapp_path": Value::Null,
        "contracts": [],
        "compilation_report_path": report_path,
        "diagnostics": diagnostics_json,
        "warnings": []
    });
    println!("{}", serde_json::to_string_pretty(&result).unwrap_or_default());
}

fn run_compiler(source_path: &str, out_path: &str, _profile_source: Option<Value>) -> std::io::Result<bool> {
    let source_content = fs::read_to_string(source_path)?;
    let mut hasher = Sha256::new();
    hasher.update(source_content.as_bytes());
    let source_hash = format!("sha256:{:x}", hasher.finalize());

    run_compiler_source(source_path, &source_content, &source_hash, out_path, None)
}

fn run_multifile_compiler(source_paths: &[String], out_path: &str, _profile_source: Option<Value>) -> std::io::Result<bool> {
    match multifile::compile_units(source_paths)? {
        Ok(merged) => run_compiler_source(
            &merged.source_path,
            &merged.source,
            &merged.source_hash,
            out_path,
            Some(merged.source_units),
        ),
        Err(diagnostics) => {
            let source_hash = multifile_error_source_hash(source_paths);
            let source_path = "multifile:error";
            let diagnostics_json: Vec<Value> = diagnostics.iter().map(|d| d.to_value()).collect();
            let report_path = report_path_for(out_path);
            fs::create_dir_all(Path::new(&report_path).parent().unwrap())?;
            let report = json!({
                "kind": "compilation_report",
                "format_version": "0.1.0",
                "program_id": Value::Null,
                "grammar_version": "igniter-v0",
                "source_hash": source_hash,
                "source_path": source_path,
                "pass_result": "oof",
                "stages": {
                    "parse": "ok",
                    "multifile_resolve": "oof",
                    "classify": "skipped",
                    "typecheck": "skipped",
                    "emit": "skipped"
                },
                "diagnostics": diagnostics_json,
                "semantic_ir_ref": Value::Null
            });
            fs::write(&report_path, serde_json::to_string_pretty(&report)? + "\n")?;

            let result = json!({
                "kind": "compiler_result",
                "format_version": "0.1.0",
                "status": "oof",
                "program_id": Value::Null,
                "source_path": source_path,
                "source_hash": source_hash,
                "grammar_version": "igniter-v0",
                "stages": {
                    "parse": "ok",
                    "multifile_resolve": "oof",
                    "classify": "skipped",
                    "typecheck": "skipped",
                    "emit": "skipped",
                    "assemble": "skipped"
                },
                "igapp_path": Value::Null,
                "contracts": [],
                "compilation_report_path": report_path,
                "diagnostics": diagnostics_json,
                "warnings": []
            });
            println!("{}", serde_json::to_string_pretty(&result)?);
            Ok(false)
        }
    }
}

fn run_compiler_source(
    source_path: &str,
    source_content: &str,
    source_hash: &str,
    out_path: &str,
    source_units: Option<Vec<Value>>,
) -> std::io::Result<bool> {
    let source_hash = source_hash.to_string();

    // 0. Lex
    let mut lexer = Lexer::new(&source_content);
    let tokens = lexer.tokenize();

    // 1. Parse
    let mut parser = Parser::new(tokens);
    let mut parsed = parser.parse();
    parsed.source_path = Some(source_path.to_string());
    parsed.source_hash = Some(source_hash.clone());
    // LAB-SRCMAP-P1: extract span table before parser is dropped
    let span_table = std::mem::take(&mut parser.span_table);

    // 1.5 Monomorphize
    igniter_compiler::monomorphizer::monomorphize_program(&mut parsed);

    if !parsed.parse_errors.is_empty() {
        // Parse failure
        let mut report = Map::new();
        report.insert("kind".to_string(), Value::String("compilation_report".to_string()));
        report.insert("format_version".to_string(), Value::String("0.1.0".to_string()));
        
        let report_id = format!("compilation_report/{}", &source_hash.trim_start_matches("sha256:")[0..16]);
        report.insert("program_id".to_string(), Value::String(report_id));
        report.insert("grammar_version".to_string(), Value::String(parsed.grammar_version.clone()));
        report.insert("source_hash".to_string(), Value::String(source_hash.clone()));
        report.insert("source_path".to_string(), Value::String(source_path.to_string()));
        report.insert("pass_result".to_string(), Value::String("error".to_string()));

        let mut stages = Map::new();
        stages.insert("parse".to_string(), Value::String("error".to_string()));
        stages.insert("classify".to_string(), Value::String("skipped".to_string()));
        stages.insert("typecheck".to_string(), Value::String("skipped".to_string()));
        stages.insert("emit".to_string(), Value::String("skipped".to_string()));
        report.insert("stages".to_string(), Value::Object(stages));

        let diag_vals: Vec<Value> = parsed.parse_errors.iter().map(|d| {
            let mut m = Map::new();
            m.insert("rule".to_string(), Value::String(d.rule.clone()));
            m.insert("severity".to_string(), Value::String("error".to_string()));
            m.insert("message".to_string(), Value::String(d.message.clone()));
            m.insert("node".to_string(), Value::String("parse".to_string()));
            m.insert("line".to_string(), Value::Number(d.line.into()));
            Value::Object(m)
        }).collect();
        report.insert("diagnostics".to_string(), Value::Array(diag_vals));
        report.insert("semantic_ir_ref".to_string(), Value::Null);

        let report_val = Value::Object(report);
        let report_path = report_path_for(out_path);
        fs::create_dir_all(Path::new(&report_path).parent().unwrap())?;
        fs::write(&report_path, serde_json::to_string_pretty(&report_val)? + "\n")?;

        let result = json!({
            "kind": "compiler_result",
            "format_version": "0.1.0",
            "status": "error",
            "program_id": Value::Null,
            "source_path": source_path,
            "source_hash": source_hash,
            "grammar_version": parsed.grammar_version,
            "stages": {
                "parse": "error",
                "classify": "skipped",
                "typecheck": "skipped",
                "emit": "skipped",
                "assemble": "skipped"
            },
            "igapp_path": Value::Null,
            "contracts": [],
            "compilation_report_path": report_path,
            "diagnostics": report_val.get("diagnostics").unwrap(),
            "warnings": []
        });

        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(false);
    }

    // 2. Classify
    let classifier = Classifier::new();
    let sample_input = json!({});
    let classified = classifier.classify(&parsed, &sample_input);

    // 3. TypeCheck
    let typechecker = TypeChecker::new();
    let typed = typechecker.typecheck(&classified, &parsed.functions);

    // 3.5 Form resolution pass
    let form_registry = FormRegistry::build_from_program(&parsed);
    let resolved_program = FormResolver::resolve(&typed, &form_registry);

    // Collect ALL form diagnostics (errors + warnings) for injection
    let form_all_diags: Vec<serde_json::Value> = resolved_program.diagnostics
        .iter()
        .chain(form_registry.diagnostics.iter())
        .map(|fd| serde_json::json!({
            "rule":     fd.code,
            "severity": fd.severity,
            "message":  fd.message,
            "node":     format!("form_resolver/{}", fd.contract),
        }))
        .collect();
    let form_error_diags: Vec<serde_json::Value> = form_all_diags.iter()
        .filter(|d| d.get("severity").and_then(|s| s.as_str()) == Some("error"))
        .cloned()
        .collect();

    let form_table = form_registry.to_form_table(parsed.module.as_deref());
    let resolved_json = serde_json::to_value(&resolved_program).ok();

    // 4. Emit
    let emitter = Emitter::new();
    let mut emit_res = emitter.emit_typed(&typed);
    emit_res.form_table = Some(form_table);
    emit_res.resolved_program = resolved_json;
    emitter.apply_form_lowering(&mut emit_res);
    attach_source_units(&mut emit_res, &source_units);

    // LAB-COMPILER-LIVENESS-P2/P3: collect instrumentation stats after all passes complete
    let liveness_stats = igniter_compiler::liveness::collect_stats();

    // LAB-COMPILER-LIVENESS-P3: E-COMPILER-BUDGET — check before ok/oof evaluation.
    // Budget breach is a compiler-internal condition; it is NOT a source-language OOF.
    // Reported as status:"compiler_error" with E-COMPILER-BUDGET diagnostics.
    // Authority: lab-only per CR-002; E-COMPILER-* codes do not enter canon.
    if liveness_stats.has_budget_breach() {
        let breach_diags: Vec<Value> = liveness_stats.budget_breaches.iter().map(|b| {
            json!({
                "rule":     "E-COMPILER-BUDGET",
                "severity": "error",
                "message":  format!(
                    "Compiler internal recursion budget exceeded: {} reached depth {} (limit {}). \
                     This is a compiler-internal diagnostic — not a source-language OOF. \
                     The source program may be semantically valid; the compiler cannot \
                     safely complete this traversal within the configured depth budget. \
                     To raise the limit: set {} (current: {}).",
                    b.counter, b.depth, b.limit,
                    match b.counter.as_str() {
                        "typechecker.infer_expr.max_depth"  => "IGNITER_LIVENESS_BUDGET_TC_INFER",
                        "form_resolver.walk_expr.max_depth" => "IGNITER_LIVENESS_BUDGET_FR_WALK",
                        _ => "IGNITER_LIVENESS_BUDGET_*",
                    },
                    b.limit
                ),
                "node":                  "liveness_budget",
                "is_compiler_internal":  true,
                "is_source_program_fault": false,
                "authority":             "lab_only_e_compiler_budget"
            })
        }).collect();

        let mut result = json!({
            "kind":           "compiler_result",
            "format_version": "0.1.0",
            "status":         "compiler_error",
            "program_id":     Value::Null,
            "source_path":    source_path,
            "source_hash":    source_hash,
            "grammar_version": parsed.grammar_version,
            "stages": {
                "parse":    "ok",
                "classify": "ok",
                "typecheck": "compiler_budget_exceeded",
                "emit":     "skipped",
                "assemble": "skipped"
            },
            "igapp_path":     Value::Null,
            "diagnostics":    breach_diags,
            "warnings":       []
        });
        result.as_object_mut().unwrap().insert(
            "liveness_instrumentation".to_string(),
            liveness_stats.to_json(),
        );
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(false);
    }

    // Inject all form diagnostics into compilation report (P7/P9 fail-closed evidence)
    if !form_all_diags.is_empty() {
        if let Some(report) = emit_res.compilation_report.as_object_mut() {
            let mut all_diags = report.get("diagnostics")
                .and_then(|d| d.as_array()).cloned().unwrap_or_default();
            all_diags.extend(form_all_diags.iter().cloned());
            report.insert("diagnostics".to_string(), serde_json::Value::Array(all_diags));
            if !form_error_diags.is_empty() {
                if report.get("pass_result").and_then(|p| p.as_str()) == Some("ok") {
                    report.insert("pass_result".to_string(), serde_json::Value::String("oof".to_string()));
                }
            }
        }
    }

    // ok includes form errors (injected above)
    let has_form_errors = !form_error_diags.is_empty();
    let ok = typed.pass_result == "ok" && classified.pass_result == "ok"
          && parsed.parse_errors.is_empty() && !has_form_errors;

    if !ok {
        // Refusal / OOF case
        let report_path = report_path_for(out_path);
        fs::create_dir_all(Path::new(&report_path).parent().unwrap())?;
        fs::write(&report_path, serde_json::to_string_pretty(&emit_res.compilation_report)? + "\n")?;

        // Always write form_table and resolution trace even on oof (sidecar evidence)
        if let Some(ft) = &emit_res.form_table {
            let ft_path = report_path.replace(".compilation_report.json", ".form_table.json");
            let _ = fs::write(&ft_path, serde_json::to_string_pretty(ft)? + "\n");
        }
        if let Some(rt) = &emit_res.resolved_program {
            let rt_path = report_path.replace(".compilation_report.json", ".form_resolution_trace.json");
            let _ = fs::write(&rt_path, serde_json::to_string_pretty(rt)? + "\n");
        }

        let errors: Vec<Value> = emit_res.compilation_report.get("diagnostics").unwrap().as_array().unwrap()
            .iter().filter(|d| d.get("severity").and_then(|s| s.as_str()) != Some("warning")).cloned().collect();
        let warnings: Vec<Value> = emit_res.compilation_report.get("diagnostics").unwrap().as_array().unwrap()
            .iter().filter(|d| d.get("severity").and_then(|s| s.as_str()) == Some("warning")).cloned().collect();

        let mut result = json!({
            "kind": "compiler_result",
            "format_version": "0.1.0",
            "status": "oof",
            "program_id": Value::Null,
            "source_path": source_path,
            "source_hash": source_hash,
            "grammar_version": parsed.grammar_version,
            "stages": {
                "parse": "ok",
                "classify": "ok",
                "typecheck": "oof",
                "emit": "skipped",
                "assemble": "skipped"
            },
            "igapp_path": Value::Null,
            "contracts": [],
            "compilation_report_path": report_path,
            "diagnostics": errors,
            "warnings": warnings
        });
        // LAB-COMPILER-LIVENESS-P2: inject instrumentation receipt
        result.as_object_mut().unwrap().insert(
            "liveness_instrumentation".to_string(),
            liveness_stats.to_json(),
        );

        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(false);
    }

    // LAB-SRCMAP-P1: build source map from parser span table and attach to emit result
    emit_res.source_map = Some(emitter.build_sourcemap(&typed, &span_table));

    // 5. Assemble
    let assembler = Assembler::new();
    let manifest = assembler.assemble(&emit_res, out_path)?;

    let contract_ids = manifest.get("contracts").unwrap().as_array().unwrap();
    let program_id = manifest.get("program_id").unwrap().as_str().unwrap().to_string();
    let comp_report_ref = manifest.get("compilation_report_ref").unwrap().as_str().unwrap().to_string();
    let sem_ir_ref = manifest.get("semantic_ir_ref").unwrap().as_str().unwrap().to_string();

    let mut result = json!({
        "kind": "compiler_result",
        "format_version": "0.1.0",
        "status": "ok",
        "program_id": program_id,
        "source_path": source_path,
        "source_hash": source_hash,
        "grammar_version": parsed.grammar_version,
        "stages": {
            "parse": "ok",
            "classify": "ok",
            "typecheck": "ok",
            "emit": "ok",
            "assemble": "ok"
        },
        "igapp_path": out_path,
        "compilation_report_ref": comp_report_ref,
        "semantic_ir_ref": sem_ir_ref,
        "contracts": contract_ids,
        "diagnostics": [],
        "warnings": form_all_diags.iter()
            .filter(|d| d.get("severity").and_then(|s| s.as_str()) == Some("warning"))
            .cloned()
            .collect::<Vec<_>>(),
        "runtime_smoke": Value::Null
    });
    // LAB-COMPILER-LIVENESS-P2: inject instrumentation receipt
    result.as_object_mut().unwrap().insert(
        "liveness_instrumentation".to_string(),
        liveness_stats.to_json(),
    );

    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(true)
}

fn attach_source_units(emit_res: &mut igniter_compiler::emitter::EmitResult, source_units: &Option<Vec<Value>>) {
    let Some(source_units) = source_units else {
        return;
    };
    if let Some(semantic_ir_value) = emit_res.semantic_ir.as_mut() {
        if let Some(semantic_ir) = semantic_ir_value.as_object_mut() {
            semantic_ir.insert("source_units".to_string(), Value::Array(source_units.clone()));
        }
    }
    if let Some(report) = emit_res.compilation_report.as_object_mut() {
        report.insert("source_units".to_string(), Value::Array(source_units.clone()));
    }
}

fn multifile_error_source_hash(source_paths: &[String]) -> String {
    let mut hasher = Sha256::new();
    let mut sorted = source_paths.to_vec();
    sorted.sort();
    for path in sorted {
        hasher.update(path.as_bytes());
        if let Ok(source) = fs::read_to_string(&path) {
            hasher.update(source.as_bytes());
        }
    }
    format!("sha256:{:x}", hasher.finalize())
}

fn report_path_for(out_path: &str) -> String {
    if out_path.ends_with(".igapp") {
        let prefix = &out_path[0..out_path.len() - 6];
        format!("{}.compilation_report.json", prefix)
    } else {
        format!("{}.compilation_report.json", out_path)
    }
}
