// LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2
//
// A workspace `igniter.toml` can declare LOCAL path dependencies; each dependency's source roots are
// folded into the SAME project module index, so cross-package `import Foo.Bar` resolves and duplicate
// module ownership across packages is caught by the existing OOF-IMP4 check. Direct dependencies only.

use igniter_compiler::project::{
    self, LockDrift, LockedDependency, ProjectError, Toolchain, WorkspaceLock,
};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

const FIX: &str = "tests/fixtures/project_mode";

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn module_files(paths: &[PathBuf]) -> Vec<String> {
    let mut names: Vec<String> = paths
        .iter()
        .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
        .collect();
    names.sort();
    names
}

/// Cross-package: `App.Main` imports `Lib.Util` from a declared local path dependency. The resolved
/// closure must include BOTH the app file and the dependency file.
#[test]
fn cross_package_import_resolves() {
    let paths =
        project::resolve_entry(Path::new(&format!("{FIX}/workspace/app")), "App.Main").unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "app file present: {names:?}");
    assert!(
        names.contains(&"util.ig".to_string()),
        "dependency file pulled into the closure: {names:?}"
    );
}

/// The combined cross-package project compiles clean through the real multifile compiler (the dependency's
/// `Widget` type links into the app contract). No error diagnostics.
#[test]
fn cross_package_project_compiles_clean() {
    let out = std::env::temp_dir().join(format!("igc_ws_{}.igapp", std::process::id()));
    let output = Command::new(bin())
        .args([
            "compile",
            "--project-root",
            &format!("{FIX}/workspace/app"),
            "--entry",
            "App.Main",
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: Value = serde_json::from_str(&stdout).unwrap_or(Value::Null);
    let errors: Vec<&Value> = v
        .get("diagnostics")
        .and_then(|d| d.as_array())
        .map(|a| a.iter().filter(|d| d.get("severity").and_then(|s| s.as_str()) == Some("error")).collect())
        .unwrap_or_default();
    assert!(
        errors.is_empty(),
        "cross-package project must compile clean; errors: {errors:?}\n--- stdout ---\n{stdout}"
    );
}

/// Bare-string shorthand (`dep = "../pathlib"`) is supported too, including paths that contain the
/// substring "path" inside the quoted value.
#[test]
fn bare_string_dependency_path_resolves() {
    let paths =
        project::resolve_entry(Path::new(&format!("{FIX}/workspace_barepath/app")), "App.Main")
            .unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "app file present: {names:?}");
    assert!(
        names.contains(&"util.ig".to_string()),
        "bare-string dependency path pulled into the closure: {names:?}"
    );
}

/// Duplicate module ownership ACROSS packages (app and dependency both declare `App.Main`) is caught by
/// the existing OOF-IMP4 check — reused, not new.
#[test]
fn duplicate_module_across_packages_is_oof_imp4() {
    let err = project::resolve_entry(Path::new(&format!("{FIX}/workspace_dup/app")), "App.Main")
        .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP4", "duplicate across packages → OOF-IMP4");
            assert_eq!(d.module_path.as_deref(), Some("App.Main"));
            assert_eq!(d.source_paths.len(), 2, "both declaring files reported");
        }
        other => panic!("expected OOF-IMP4 diagnostic, got {other:?}"),
    }
}

/// LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14 (migrated from `direct_dependencies_only`): `app → mid → deep`.
/// `mid` declares `deep` and imports `Deep.D`; the transitive graph now assembles `deep`, so the closure
/// reaches it through the declared `mid → deep` edge (app + mid + deep).
#[test]
fn transitive_dependency_is_assembled() {
    let paths =
        project::resolve_entry(Path::new(&format!("{FIX}/workspace_direct/app")), "App.Main")
            .unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "app present: {names:?}");
    assert!(names.contains(&"x.ig".to_string()), "direct dep `mid` present: {names:?}");
    assert!(
        names.contains(&"d.ig".to_string()),
        "transitive dep `deep` is now assembled through the declared mid->deep edge: {names:?}"
    );
}

/// P1 parity: a project with NO `[dependencies]` resolves exactly as before (existing transitive fixture).
#[test]
fn no_dependencies_parity() {
    let paths = project::resolve_entry(Path::new(&format!("{FIX}/transitive")), "Chain.A").unwrap();
    let names = module_files(&paths);
    // unchanged P1 closure: a/b/c chain, no dependency folding.
    assert!(names.contains(&"a.ig".to_string()) && names.contains(&"c.ig".to_string()), "{names:?}");
}

// ── LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7 ───────────────────────────────────────────────────────────

/// Phantom import: `lib1` imports `Lib2.B`, but `lib1` never declared `lib2` (it is folded only because the
/// root app also depends on it). Out-of-scope → `OOF-IMP6`.
#[test]
fn phantom_sibling_import_is_oof_imp6() {
    let err = project::resolve_entry(Path::new(&format!("{FIX}/workspace_phantom/app")), "App.Main")
        .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP6", "phantom import → OOF-IMP6: {d:?}");
            assert_eq!(d.module_path.as_deref(), Some("Lib1.A"), "importer module");
            assert!(
                d.message.contains("Lib2.B") && d.message.contains("lib1") && d.message.contains("lib2"),
                "message names importer/imported + packages: {}",
                d.message
            );
            assert_eq!(d.source_paths.len(), 1, "importer source path reported");
        }
        other => panic!("expected OOF-IMP6 diagnostic, got {other:?}"),
    }
}

/// Intra-package: a dependency's `Lib.A` imports its own `Lib.B` (both package `lib`) — same package, in
/// scope. Resolves clean (no OOF-IMP6); the closure contains all three files.
#[test]
fn intra_package_import_is_allowed() {
    let paths = project::resolve_entry(Path::new(&format!("{FIX}/workspace_intra/app")), "App.Main")
        .unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "{names:?}");
    assert!(names.contains(&"a.ig".to_string()) && names.contains(&"b.ig".to_string()), "{names:?}");
}

/// A declared root→dependency import (`app` imports `Lib.Util`, lib is declared) is in scope — no OOF-IMP6.
#[test]
fn declared_cross_package_import_is_allowed() {
    // Reuses the P2 `workspace` fixture; resolving it must NOT raise a scope diagnostic.
    let res = project::resolve_entry(Path::new(&format!("{FIX}/workspace/app")), "App.Main");
    assert!(res.is_ok(), "declared cross-package import must be in scope: {res:?}");
}

// ── LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8 (entry-free integrity gate) ────────────────────────────

/// `check_workspace_integrity` flags a phantom import (entry-independent) with the same OOF-IMP6 diagnostic.
#[test]
fn check_workspace_integrity_flags_phantom() {
    let err = project::check_workspace_integrity(&app("workspace_phantom")).unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-IMP6", "{d:?}"),
        other => panic!("expected OOF-IMP6, got {other:?}"),
    }
}

/// `check_workspace_integrity` returns Ok for a clean workspace.
#[test]
fn check_workspace_integrity_ok_on_clean() {
    assert!(project::check_workspace_integrity(&app("workspace")).is_ok());
}

// ── LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10 ──────────────────────────────────────────────────────────

/// An exported dependency module is importable; an intra-package import of a private module (inside the
/// dependency) is unrestricted. `workspace_exports_ok` resolves clean with all three files.
#[test]
fn exported_module_import_is_allowed() {
    let paths =
        project::resolve_entry(Path::new(&format!("{FIX}/workspace_exports_ok/app")), "App.Main")
            .unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "{names:?}");
    assert!(
        names.contains(&"public.ig".to_string()) && names.contains(&"private.ig".to_string()),
        "intra-package import of the private module is allowed: {names:?}"
    );
}

/// Importing a NON-exported dependency module is `OOF-IMP7`.
#[test]
fn non_exported_module_import_is_oof_imp7() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_exports_private/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP7", "non-exported import → OOF-IMP7: {d:?}");
            assert_eq!(d.module_path.as_deref(), Some("App.Main"), "importer module");
            assert!(
                d.message.contains("Lib.Private") && d.message.contains("lib"),
                "message names imported module + package: {}",
                d.message
            );
            assert_eq!(d.source_paths.len(), 1, "importer source path reported");
        }
        other => panic!("expected OOF-IMP7, got {other:?}"),
    }
}

/// A dependency with NO `[exports]` block stays open (the P2 `workspace` fixture's `lib` declares none).
#[test]
fn no_exports_block_is_open() {
    let res = project::resolve_entry(Path::new(&format!("{FIX}/workspace/app")), "App.Main");
    assert!(res.is_ok(), "no [exports] block ⇒ open: {res:?}");
}

/// P7 phantom sibling edge is still `OOF-IMP6`, not reclassified by the export pass (OOF-IMP6 runs first).
#[test]
fn phantom_sibling_still_oof_imp6_after_exports() {
    let err = project::resolve_entry(Path::new(&format!("{FIX}/workspace_phantom/app")), "App.Main")
        .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-IMP6", "{d:?}"),
        other => panic!("expected OOF-IMP6, got {other:?}"),
    }
}

/// `check_workspace_integrity` reports `OOF-IMP7` entry-free (so `verify --strict` catches it).
#[test]
fn check_workspace_integrity_flags_non_export() {
    let err = project::check_workspace_integrity(&app("workspace_exports_private")).unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-IMP7", "{d:?}"),
        other => panic!("expected OOF-IMP7, got {other:?}"),
    }
}

// ── LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12 ──────────────────────────────────────────────────

/// Under the root `[package] exports = "closed"` policy, a dependency that declares NO `[exports]` block is
/// sealed: importing any of its modules is `OOF-IMP7` (message names the closed-default policy).
#[test]
fn closed_default_seals_undeclared_dependency() {
    let err =
        project::resolve_entry(Path::new(&format!("{FIX}/workspace_closed_default/app")), "App.Main")
            .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP7", "{d:?}");
            assert_eq!(d.module_path.as_deref(), Some("App.Main"));
            assert!(
                d.message.contains("Lib.A") && d.message.contains("closed"),
                "message names the import + closed policy: {}",
                d.message
            );
        }
        other => panic!("expected OOF-IMP7, got {other:?}"),
    }
}

/// Under closed policy, a dependency that DOES declare `[exports]` is honored: the exported module imports,
/// and its same-package private import is unrestricted. Resolves clean.
#[test]
fn closed_default_honors_declared_exports_and_same_package() {
    let paths = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_closed_declared/app")),
        "App.Main",
    )
    .unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "{names:?}");
    assert!(
        names.contains(&"public.ig".to_string()) && names.contains(&"private.ig".to_string()),
        "declared export + same-package private import both allowed under closed: {names:?}"
    );
}

/// The default policy stays Open: an undeclared dependency (no `[package]`/`[exports]`) remains importable
/// (the existing `workspace` fixture; backward-compatible).
#[test]
fn open_default_leaves_undeclared_open() {
    assert!(
        project::resolve_entry(Path::new(&format!("{FIX}/workspace/app")), "App.Main").is_ok(),
        "open default unchanged"
    );
}

/// `check_workspace_integrity` reports the closed-default `OOF-IMP7` entry-free (so `verify --strict` sees it).
#[test]
fn check_workspace_integrity_flags_closed_default() {
    let err = project::check_workspace_integrity(&app("workspace_closed_default")).unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-IMP7", "{d:?}"),
        other => panic!("expected OOF-IMP7, got {other:?}"),
    }
}

// ── LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14 ────────────────────────────────────────────────────────

/// A package may import its own declared dependency transitively: `app→mid→leaf`, `Mid.Public` imports the
/// exported `Leaf.Public`. The closure assembles all three packages.
#[test]
fn transitive_declared_edge_resolves() {
    let paths = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_transitive_ok/app")),
        "App.Main",
    )
    .unwrap();
    let names = module_files(&paths);
    assert!(
        names.contains(&"main.ig".to_string()) && names.contains(&"public.ig".to_string()),
        "app + mid present: {names:?}"
    );
    // leaf's public.ig is the third file (two files named public.ig → assert ≥2 distinct package files)
    assert!(paths.len() >= 3, "transitive leaf folded too: {names:?}");
}

/// The root may NOT import a transitive package it did not declare directly → `OOF-IMP6`.
#[test]
fn root_cannot_import_transitive_dep() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_transitive_root_phantom/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP6", "{d:?}");
            assert_eq!(d.module_path.as_deref(), Some("App.Main"));
        }
        other => panic!("expected OOF-IMP6, got {other:?}"),
    }
}

/// A dependency may not import a sibling it did not declare (even though the root folded it) → `OOF-IMP6`.
#[test]
fn dependency_cannot_import_undeclared_sibling() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_transitive_dep_phantom/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP6", "{d:?}");
            assert_eq!(d.module_path.as_deref(), Some("Mid.M"));
        }
        other => panic!("expected OOF-IMP6, got {other:?}"),
    }
}

/// Exports are enforced on a transitive consumer→provider edge: `mid` declares `leaf` but imports the
/// non-exported `Leaf.Private` → `OOF-IMP7`.
#[test]
fn transitive_non_exported_import_is_oof_imp7() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_transitive_non_export/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP7", "{d:?}");
            assert_eq!(d.module_path.as_deref(), Some("Mid.M"));
            assert!(d.message.contains("Leaf.Private"), "{}", d.message);
        }
        other => panic!("expected OOF-IMP7, got {other:?}"),
    }
}

/// A cycle in the local package graph is a deterministic `OOF-IMP8`.
#[test]
fn package_graph_cycle_is_oof_imp8() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_transitive_cycle/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP8", "{d:?}");
            assert!(d.message.contains("cycle"), "{}", d.message);
        }
        other => panic!("expected OOF-IMP8, got {other:?}"),
    }
}

/// A diamond (`app→a,b`; `a→c`, `b→c`) resolves to ONE `c` node — no duplicate-module fault, c folded once.
#[test]
fn diamond_same_package_dedups() {
    let paths = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_transitive_diamond/app")),
        "App.Main",
    )
    .unwrap();
    let names = module_files(&paths);
    let c_count = names.iter().filter(|n| *n == "c.ig").count();
    assert_eq!(c_count, 1, "shared package `c` folded exactly once: {names:?}");
    assert!(names.contains(&"a.ig".to_string()) && names.contains(&"b.ig".to_string()), "{names:?}");
}

/// The lock records the FULL reachable graph: `workspace_transitive_ok` locks `mid` AND `leaf`.
#[test]
fn lock_records_full_transitive_graph() {
    let lock = project::workspace_lock(&app("workspace_transitive_ok")).unwrap();
    let paths: Vec<&str> = lock.dependencies.iter().map(|d| d.path.as_str()).collect();
    assert_eq!(lock.dependencies.len(), 2, "mid + leaf locked: {paths:?}");
    assert!(paths.iter().any(|p| p.contains("mid")), "mid in lock: {paths:?}");
    assert!(paths.iter().any(|p| p.contains("leaf")), "leaf (transitive) in lock: {paths:?}");
}

// ── LAB-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16 ──────────────────────────────────────────────────

/// A root-declared dependency whose path does not exist is `OOF-IMP9` at assembly time (not a delayed
/// `OOF-IMP2`), naming the declaring package, the dependency edge, and the missing path.
#[test]
fn missing_root_dependency_is_oof_imp9() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_missing_root_dep/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP9", "{d:?}");
            assert_eq!(d.module_path, None, "graph fault, not a module fault");
            assert_eq!(d.node, "dependency:<root>->ghost", "stable edge node: {}", d.node);
            assert!(
                d.message.contains("ghost") && d.message.contains("does not exist"),
                "names dep + missing path: {}",
                d.message
            );
            assert_eq!(d.source_paths.len(), 2, "declaring root + missing path");
        }
        other => panic!("expected OOF-IMP9, got {other:?}"),
    }
}

/// A TRANSITIVE package declaring a missing dependency path is `OOF-IMP9` naming that package's edge.
#[test]
fn missing_transitive_dependency_is_oof_imp9() {
    let err = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_missing_transitive_dep/app")),
        "App.Main",
    )
    .unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => {
            assert_eq!(d.rule, "OOF-IMP9", "{d:?}");
            assert_eq!(d.node, "dependency:mid->ghost", "declaring package is `mid`: {}", d.node);
        }
        other => panic!("expected OOF-IMP9, got {other:?}"),
    }
}

/// `check_workspace_integrity` (the `verify --strict` path) also fails with `OOF-IMP9` — graph assembly
/// itself returns the diagnostic, before integrity checks run.
#[test]
fn check_workspace_integrity_reports_missing_dep() {
    let err = project::check_workspace_integrity(&app("workspace_missing_root_dep")).unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-IMP9", "{d:?}"),
        other => panic!("expected OOF-IMP9, got {other:?}"),
    }
}

/// `workspace_lock` fails with `OOF-IMP9` even though no module imports the missing package — a lock over a
/// broken graph is meaningless.
#[test]
fn workspace_lock_fails_on_missing_dep() {
    let err = project::workspace_lock(&app("workspace_missing_root_dep")).unwrap_err();
    match err {
        ProjectError::Diagnostic(d) => assert_eq!(d.rule, "OOF-IMP9", "{d:?}"),
        other => panic!("expected OOF-IMP9, got {other:?}"),
    }
}

/// A directory dependency WITHOUT an `igniter.toml` is ALLOWED — it loads as a package with defaults
/// (`source_roots = ["."]`), not `OOF-IMP9`. "Missing" is gated on directory existence, not manifest
/// presence. `workspace_dep_no_manifest/lib` has no manifest yet resolves through the declared edge.
#[test]
fn existing_dir_without_manifest_is_not_missing() {
    let paths = project::resolve_entry(
        Path::new(&format!("{FIX}/workspace_dep_no_manifest/app")),
        "App.Main",
    )
    .unwrap();
    let names = module_files(&paths);
    assert!(
        names.contains(&"main.ig".to_string()) && names.contains(&"x.ig".to_string()),
        "manifest-less dependency dir loads with defaults: {names:?}"
    );
}

// ── LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19 ──────────────────────────────────────────────────────

fn diagnostic_for(fixture: &str) -> project::ProjectDiagnostic {
    match project::resolve_entry(Path::new(&format!("{FIX}/{fixture}/app")), "App.Main").unwrap_err() {
        ProjectError::Diagnostic(d) => d,
        other => panic!("expected a diagnostic, got {other:?}"),
    }
}

/// `OOF-IMP6` carries machine-actionable `details.kind = "import_scope"` with importer/provider {module,
/// package,path}, `declared_edge: false`, and a `[dependencies]` fix.
#[test]
fn oof_imp6_has_import_scope_details() {
    let d = diagnostic_for("workspace_phantom");
    assert_eq!(d.rule, "OOF-IMP6");
    let det = d.details.expect("OOF-IMP6 has details");
    assert_eq!(det["kind"], serde_json::json!("import_scope"));
    assert_eq!(det["declared_edge"], serde_json::json!(false));
    assert_eq!(det["importer"]["module"], serde_json::json!("Lib1.A"));
    assert_eq!(det["importer"]["package"], serde_json::json!("lib1"));
    assert_eq!(det["provider"]["module"], serde_json::json!("Lib2.B"));
    assert_eq!(det["provider"]["package"], serde_json::json!("lib2"));
    assert!(det["importer"]["path"].as_str().is_some(), "importer path present");
    assert!(
        det["fix"].as_str().is_some_and(|f| f.contains("[dependencies]") && f.contains("lib2")),
        "fix advises declaring the provider: {det}"
    );
}

/// `OOF-IMP7` allowlist miss carries `details.kind = "import_export"`, `declared_edge: true`,
/// `provider_exports.modules`, `exports_default: "open"`, and an `[exports]` fix.
#[test]
fn oof_imp7_allowlist_has_import_export_details() {
    let d = diagnostic_for("workspace_exports_private");
    assert_eq!(d.rule, "OOF-IMP7");
    let det = d.details.expect("OOF-IMP7 has details");
    assert_eq!(det["kind"], serde_json::json!("import_export"));
    assert_eq!(det["declared_edge"], serde_json::json!(true));
    assert_eq!(det["exports_default"], serde_json::json!("open"));
    assert_eq!(det["provider_exports"]["mode"], serde_json::json!("allowlist"));
    assert_eq!(det["provider_exports"]["modules"][0], serde_json::json!("Lib.Public"));
    assert!(
        det["fix"].as_str().is_some_and(|f| f.contains("[exports]")),
        "fix advises [exports]: {det}"
    );
}

/// `OOF-IMP7` closed-default seal distinguishes the policy: `exports_default: "closed"`, `provider_exports`
/// mode `open` (no declared `[exports]`), and a seal-specific fix.
#[test]
fn oof_imp7_closed_seal_details_distinguish_policy() {
    let d = diagnostic_for("workspace_closed_default");
    assert_eq!(d.rule, "OOF-IMP7");
    let det = d.details.expect("OOF-IMP7 seal has details");
    assert_eq!(det["exports_default"], serde_json::json!("closed"));
    assert_eq!(det["provider_exports"]["mode"], serde_json::json!("open"));
    assert!(
        det["fix"].as_str().is_some_and(|f| f.contains("closed")),
        "seal fix mentions the closed policy: {det}"
    );
}

/// Non-package diagnostics (here the `OOF-IMP8` cycle) carry NO `details` — byte-shape unchanged.
#[test]
fn non_package_diagnostic_has_no_details() {
    let d = diagnostic_for("workspace_transitive_cycle");
    assert_eq!(d.rule, "OOF-IMP8");
    assert!(d.details.is_none(), "OOF-IMP8 must not carry details");
}

// ── LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3 ──────────────────────────────────────────────────────────

fn app(fixture: &str) -> PathBuf {
    PathBuf::from(format!("{FIX}/{fixture}/app"))
}

/// The workspace lock is deterministic: computed twice it is byte-equal, and pins each declared
/// dependency by name + path + a sha256 content digest.
#[test]
fn lock_is_deterministic_and_pins_each_dependency() {
    let a = project::workspace_lock(&app("workspace")).unwrap();
    let b = project::workspace_lock(&app("workspace")).unwrap();
    assert_eq!(a, b, "lock must be deterministic");
    assert_eq!(a.dependencies.len(), 1, "one declared dependency");
    let lib = &a.dependencies[0];
    assert_eq!(lib.name, "lib");
    assert_eq!(lib.path, "../lib");
    assert!(lib.digest.starts_with("sha256:"), "sha256 digest: {}", lib.digest);
    assert!(lib.digest.len() > "sha256:".len() + 16, "non-empty hex");
}

/// A freshly-computed lock verifies clean (no drift) against itself.
#[test]
fn clean_verify_has_no_drift() {
    let root = app("workspace");
    let lock = project::workspace_lock(&root).unwrap();
    let drift = project::verify_lock(&root, &lock).unwrap();
    assert!(drift.is_empty(), "clean workspace must verify with no drift: {drift:?}");
}

/// A tampered lock digest is detected as `Changed` drift (the dependency content differs from the lock).
#[test]
fn tampered_digest_is_changed_drift() {
    let root = app("workspace");
    let mut lock = project::workspace_lock(&root).unwrap();
    lock.dependencies[0].digest = "sha256:deadbeef".to_string();
    let drift = project::verify_lock(&root, &lock).unwrap();
    assert_eq!(drift.len(), 1, "exactly one drift");
    match &drift[0] {
        LockDrift::Changed { name, locked, actual } => {
            assert_eq!(name, "lib");
            assert_eq!(locked, "sha256:deadbeef");
            assert!(actual.starts_with("sha256:") && actual != "sha256:deadbeef");
        }
        other => panic!("expected Changed drift, got {other:?}"),
    }
}

/// Content-addressed: two dependencies named `lib` with DIFFERENT content (the `workspace` lib vs the
/// `workspace_dup` lib) produce DIFFERENT digests — the digest tracks content, not just the name/path.
#[test]
fn digest_is_content_addressed() {
    let a = project::workspace_lock(&app("workspace")).unwrap();
    let b = project::workspace_lock(&app("workspace_dup")).unwrap();
    let da = &a.dependencies[0].digest;
    let db = &b.dependencies[0].digest;
    assert_eq!(a.dependencies[0].name, b.dependencies[0].name, "both named lib");
    assert_ne!(da, db, "different content → different digest");
}

/// A project with no `[dependencies]` yields an empty lock that verifies clean.
#[test]
fn no_dependencies_empty_lock() {
    let root = PathBuf::from(format!("{FIX}/transitive"));
    let lock = project::workspace_lock(&root).unwrap();
    assert!(lock.dependencies.is_empty(), "no deps → empty lock");
    assert!(project::verify_lock(&root, &lock).unwrap().is_empty());
}

/// The lock round-trips through its deterministic JSON form.
#[test]
fn lock_json_roundtrips() {
    let lock = WorkspaceLock {
        toolchain: Toolchain {
            compiler: "9.9.9".to_string(),
            stdlib: "8.8.8".to_string(),
        },
        dependencies: vec![LockedDependency {
            name: "lib".to_string(),
            path: "../lib".to_string(),
            digest: "sha256:abc123".to_string(),
        }],
    };
    let parsed = WorkspaceLock::from_value(&lock.to_value()).unwrap();
    assert_eq!(lock, parsed);
}

// ── LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6 ──────────────────────────────────────────────────

/// The lock stamps the stdlib surface version (`STDLIB_VERSION`).
#[test]
fn lock_stamps_stdlib_version() {
    let lock = project::workspace_lock(&app("workspace")).unwrap();
    assert_eq!(lock.toolchain.stdlib, igniter_compiler::STDLIB_VERSION);
    assert!(!lock.toolchain.stdlib.is_empty(), "stdlib version stamped");
}

/// A lock pinned to a different stdlib version verifies as a `Toolchain{field:"stdlib"}` drift.
#[test]
fn stdlib_drift_detected() {
    let root = app("workspace");
    let mut lock = project::workspace_lock(&root).unwrap();
    lock.toolchain.stdlib = "0.0.0-old-stdlib".to_string();
    let drift = project::verify_lock(&root, &lock).unwrap();
    let tc: Vec<&LockDrift> = drift
        .iter()
        .filter(|d| matches!(d, LockDrift::Toolchain { field, .. } if field == "stdlib"))
        .collect();
    assert_eq!(tc.len(), 1, "one stdlib drift: {drift:?}");
    match tc[0] {
        LockDrift::Toolchain {
            field,
            locked,
            actual,
        } => {
            assert_eq!(field, "stdlib");
            assert_eq!(locked, "0.0.0-old-stdlib");
            assert_eq!(actual, igniter_compiler::STDLIB_VERSION);
        }
        _ => unreachable!(),
    }
}

/// Backward-compat: a P5-style lock with an empty stdlib field yields no stdlib drift (the compiler field
/// is still checked independently).
#[test]
fn unpinned_stdlib_has_no_stdlib_drift() {
    let root = app("workspace");
    let mut lock = project::workspace_lock(&root).unwrap();
    lock.toolchain.stdlib = String::new(); // pre-P6 lock: no stdlib pin
    let drift = project::verify_lock(&root, &lock).unwrap();
    assert!(
        !drift
            .iter()
            .any(|d| matches!(d, LockDrift::Toolchain { field, .. } if field == "stdlib")),
        "unpinned stdlib must not drift: {drift:?}"
    );
}

/// Guard: the compiler-owned `STDLIB_VERSION` mirrors `igniter-stdlib/Cargo.toml`. If the sibling crate is
/// reachable, the versions must match (catches silent divergence); otherwise the check is skipped so the
/// test is isolation-safe.
#[test]
fn stdlib_version_mirrors_crate() {
    let manifest = Path::new("../igniter-stdlib/Cargo.toml");
    let Ok(content) = std::fs::read_to_string(manifest) else {
        eprintln!("skip: ../igniter-stdlib/Cargo.toml not reachable");
        return;
    };
    // Read the `[package]` version (first `version = "..."` line).
    let crate_version = content
        .lines()
        .find_map(|l| {
            let l = l.trim();
            l.strip_prefix("version")
                .and_then(|r| r.trim_start().strip_prefix('='))
                .map(|r| r.trim().trim_matches('"').to_string())
        })
        .expect("igniter-stdlib version line");
    assert_eq!(
        igniter_compiler::STDLIB_VERSION, crate_version,
        "STDLIB_VERSION must mirror igniter-stdlib/Cargo.toml (bump the constant when stdlib changes)"
    );
}

// ── LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5 ───────────────────────────────────────────────────────

/// The lock stamps the producing compiler version (`env!("CARGO_PKG_VERSION")`).
#[test]
fn lock_stamps_compiler_version() {
    let lock = project::workspace_lock(&app("workspace")).unwrap();
    assert_eq!(lock.toolchain.compiler, env!("CARGO_PKG_VERSION"));
    assert!(!lock.toolchain.compiler.is_empty(), "compiler version stamped");
}

/// A lock pinned to a different compiler version verifies as `Toolchain` drift.
#[test]
fn toolchain_drift_detected() {
    let root = app("workspace");
    let mut lock = project::workspace_lock(&root).unwrap();
    lock.toolchain.compiler = "0.0.0-old".to_string();
    let drift = project::verify_lock(&root, &lock).unwrap();
    let tc: Vec<&LockDrift> = drift
        .iter()
        .filter(|d| matches!(d, LockDrift::Toolchain { .. }))
        .collect();
    assert_eq!(tc.len(), 1, "one toolchain drift: {drift:?}");
    match tc[0] {
        LockDrift::Toolchain {
            field,
            locked,
            actual,
        } => {
            assert_eq!(field, "compiler");
            assert_eq!(locked, "0.0.0-old");
            assert_eq!(actual, env!("CARGO_PKG_VERSION"));
        }
        _ => unreachable!(),
    }
}

/// Backward-compat: an unpinned (pre-P5) lock — `toolchain.compiler` empty — yields **no** toolchain drift,
/// so old locks still verify clean on dependency digests.
#[test]
fn unpinned_lock_has_no_toolchain_drift() {
    let root = app("workspace");
    let mut lock = project::workspace_lock(&root).unwrap();
    lock.toolchain.compiler = String::new(); // simulate a pre-P5 lock with no toolchain block
    let drift = project::verify_lock(&root, &lock).unwrap();
    assert!(
        !drift.iter().any(|d| matches!(d, LockDrift::Toolchain { .. })),
        "unpinned lock must not report toolchain drift: {drift:?}"
    );
}

/// A pre-P5 lock JSON literally has no `toolchain` block; `from_value` parses it as unpinned.
#[test]
fn pre_p5_lock_json_parses_unpinned() {
    let json = serde_json::json!({
        "version": 1,
        "dependencies": [{ "name": "lib", "path": "../lib", "digest": "sha256:abc" }],
    });
    let lock = WorkspaceLock::from_value(&json).unwrap();
    assert_eq!(lock.toolchain.compiler, "", "no toolchain block → unpinned");
    assert_eq!(lock.dependencies.len(), 1);
}
