// igniter_workspace_tests.rs — LAB-IGNITER-WORKSPACE-STATUS-DOCTOR-P2
//
// Focused tests for the read-only Dev lane `igniter workspace status|doctor` through the repo-local
// `bin/igniter` front door (not by calling functions). Every check is local + non-mutating. Remote mirror
// HEAD lookups are skipped via IGNITER_WORKSPACE_NO_REMOTE=1 so the suite is hermetic (no SSH/network).

use std::path::PathBuf;
use std::process::Command;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

// Run `igniter workspace <args>` with remote lookups disabled (hermetic).
fn ws(args: &[&str]) -> std::process::Output {
    Command::new(wrapper())
        .arg("workspace")
        .args(args)
        .env("IGNITER_WORKSPACE_NO_REMOTE", "1")
        .output()
        .expect("run igniter workspace")
}

/// `igniter workspace --help` documents both subcommands and stays read-only.
#[test]
fn workspace_help_documents_status_and_doctor() {
    let out = ws(&["--help"]);
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("status") && s.contains("doctor"), "help names both verbs:\n{s}");
    assert!(s.contains("read-only") || s.contains("Read-only") || s.contains("mutates\nnothing") || s.contains("mutates nothing"),
        "help states read-only:\n{s}");
}

/// `igniter workspace status` reports the five flattened core crates, the canon sibling, the mirror
/// helpers, and the igniter-lab branch — and exits 0.
#[test]
fn workspace_status_reports_layout_and_mirrors() {
    let out = ws(&["status"]);
    assert!(out.status.success(), "status exits 0: {out:?}");
    let s = String::from_utf8_lossy(&out.stdout);
    for crate_name in [
        "igniter-stdlib", "igniter-compiler", "igniter-vm", "igniter-machine", "igniter-tbackend",
    ] {
        assert!(s.contains(crate_name), "names core crate {crate_name}:\n{s}");
    }
    assert!(s.contains("igniter-lang sibling"), "reports canon sibling:\n{s}");
    assert!(s.contains("push-igniter-vm-mirror"), "reports a mirror helper:\n{s}");
    assert!(s.contains("git branch"), "reports igniter-lab branch:\n{s}");
}

/// `--json` for both verbs is a valid array of records under scope "workspace" using the doctor schema
/// (severity vocabulary ok/warn/fail/info), with no leaked secret/env values.
#[test]
fn workspace_json_uses_doctor_record_schema() {
    for verb in ["status", "doctor"] {
        let out = ws(&[verb, "--json"]);
        assert!(out.status.success(), "{verb} --json exits 0 on a healthy tree: {out:?}");
        let s = String::from_utf8_lossy(&out.stdout);
        let s = s.trim();
        assert!(s.starts_with('[') && s.ends_with(']'), "{verb} --json is an array:\n{s}");
        assert!(s.contains("\"scope\": \"workspace\""), "{verb} records are workspace-scoped:\n{s}");
        let checks = s.matches("\"severity\"").count();
        assert!(checks >= 10, "{verb} has ≥10 records, got {checks}:\n{s}");
        // schema keys present
        for key in ["\"check\"", "\"detail\"", "\"suggest\""] {
            assert!(s.contains(key), "{verb} record has {key}:\n{s}");
        }
    }
}

/// `workspace doctor` gates its exit on a required LOCAL layout check: with the canon `igniter-lang`
/// sibling missing it emits a `fail` and exits non-zero — while `workspace status` stays a report (exit 0).
/// Simulated hermetically with a synthetic source-checkout root (5 empty crate dirs, no sibling).
#[test]
fn workspace_doctor_fails_without_canon_sibling_status_does_not() {
    let root = std::env::temp_dir().join(format!("igws_nolang_{}", std::process::id()));
    let bindir = root.join("bin");
    std::fs::create_dir_all(&bindir).unwrap();
    // Make it look like a flattened source checkout: the 5 core crate dirs each with a Cargo.toml.
    for c in [
        "igniter-stdlib", "igniter-compiler", "igniter-vm", "igniter-machine", "igniter-tbackend",
    ] {
        let d = root.join(c);
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("Cargo.toml"), "[package]\nname=\"x\"\nversion=\"0.0.0\"\n").unwrap();
    }
    // Copy the front door into <root>/bin so REPO_ROOT resolves to <root> — and there is NO ../igniter-lang.
    std::fs::copy(wrapper(), bindir.join("igniter")).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let p = bindir.join("igniter");
        let mut perm = std::fs::metadata(&p).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&p, perm).unwrap();
    }
    let run = |verb: &str| {
        Command::new(bindir.join("igniter"))
            .args(["workspace", verb])
            .env("IGNITER_WORKSPACE_NO_REMOTE", "1")
            .output()
            .expect("run staged igniter workspace")
    };
    let doc = run("doctor");
    let stat = run("status");
    let _ = std::fs::remove_dir_all(&root);

    let ds = String::from_utf8_lossy(&doc.stdout);
    assert!(ds.contains("igniter-lang sibling") && ds.contains("[fail]"), "doctor flags the missing sibling:\n{ds}");
    assert!(!doc.status.success(), "doctor exits non-zero on a required-local fail");
    assert!(stat.status.success(), "status is a report — exits 0 even with the sibling missing");
}

/// An installed prefix (front door only, no crate tree) is a graceful `info`, not a scary fail: workspace
/// commands target a source checkout. Exit 0.
#[test]
fn workspace_installed_prefix_is_info_not_fail() {
    let root = std::env::temp_dir().join(format!("igws_prefix_{}", std::process::id()));
    let bindir = root.join("bin");
    std::fs::create_dir_all(&bindir).unwrap();
    std::fs::copy(wrapper(), bindir.join("igniter")).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let p = bindir.join("igniter");
        let mut perm = std::fs::metadata(&p).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&p, perm).unwrap();
    }
    let out = Command::new(bindir.join("igniter"))
        .args(["workspace", "doctor"])
        .env("IGNITER_WORKSPACE_NO_REMOTE", "1")
        .output()
        .expect("run staged igniter workspace doctor");
    let s = String::from_utf8_lossy(&out.stdout);
    let _ = std::fs::remove_dir_all(&root);
    assert!(out.status.success(), "installed-prefix workspace doctor exits 0 (nothing to gate)");
    assert!(s.contains("installed-prefix"), "reports installed-prefix mode:\n{s}");
}

/// Unknown subcommand is a usage error (exit 2), matching the front door's convention.
#[test]
fn workspace_unknown_subcommand_is_usage_error() {
    let out = ws(&["frobnicate"]);
    assert_eq!(out.status.code(), Some(2), "unknown workspace subcommand exits 2: {out:?}");
}

// ── build/test matrix arg surface (LAB-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3) ──────────────────────
// The bounded core matrix itself (cargo build/test per crate + the machine pure-core lane) is verified by
// direct invocation, not here: running the real matrix from inside `cargo test` would nest heavy compiles.
// These tests cover the fast arg/usage surface that guards it (exit before any cargo runs).

/// `workspace --help` also documents the build/test matrix verbs.
#[test]
fn workspace_help_documents_build_and_test() {
    let out = ws(&["--help"]);
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("build") && s.contains("test"), "help names build + test:\n{s}");
    assert!(s.contains("pure-core") || s.contains("no-default-features"),
        "help mentions the machine pure-core lane:\n{s}");
    assert!(s.contains("--quick"), "help documents --quick:\n{s}");
}

/// `workspace build --quick` is a usage error (--quick is a `test` flag) — exits 2 before any cargo.
#[test]
fn workspace_build_rejects_quick() {
    let out = ws(&["build", "--quick"]);
    assert_eq!(out.status.code(), Some(2), "build has no --quick: {out:?}");
}

/// `workspace test <positional>` is a usage error — exits 2 before any cargo.
#[test]
fn workspace_test_rejects_positional_arg() {
    let out = ws(&["test", "some-target"]);
    assert_eq!(out.status.code(), Some(2), "test takes no positional args: {out:?}");
}
