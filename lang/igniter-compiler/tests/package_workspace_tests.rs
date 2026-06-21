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

/// Direct dependencies only: `app` depends on `mid`; `mid` declares its own dependency on `deep`, which is
/// NOT traversed in v0. The resolved closure includes app + mid, never deep.
#[test]
fn direct_dependencies_only() {
    let paths =
        project::resolve_entry(Path::new(&format!("{FIX}/workspace_direct/app")), "App.Main")
            .unwrap();
    let names = module_files(&paths);
    assert!(names.contains(&"main.ig".to_string()), "app present: {names:?}");
    assert!(names.contains(&"x.ig".to_string()), "direct dep `mid` present: {names:?}");
    assert!(
        !names.contains(&"d.ig".to_string()),
        "transitive dep `deep` must NOT be pulled (direct-only v0): {names:?}"
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
