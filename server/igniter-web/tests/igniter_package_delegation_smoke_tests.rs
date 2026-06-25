// igniter_package_delegation_smoke_tests.rs — LAB-DISTRIBUTION-PACKAGE-DELEGATION-P12
//
// Proves `igniter package <sub>` is a 1:1 argv alias to `igc` (the package authority) through the repo-local
// `bin/igniter` wrapper. ROUTING ONLY: these tests assert the wrapper maps each subcommand to the right igc
// argv prefix, preserves trailing args, preserves the exit code, prefers a co-located staged `igc`, and fails
// closed (with a build/install suggestion) when igc is missing. They do NOT reimplement igc's package tests —
// igc is replaced by a stub that echoes its argv, so the wrapper's routing is the only thing under test.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::Command;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

/// Write an executable stub `igc` into a fresh temp dir. The stub prints `IGC-STUB argv: <joined args>` and
/// exits with `${STUB_EXIT:-0}`, so a test can assert both the routed argv and exit-code passthrough.
fn make_stub_igc(tag: &str) -> (PathBuf, PathBuf) {
    let dir = std::env::temp_dir().join(format!("igpkg_{}_{}", tag, std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let stub = dir.join("igc");
    fs::write(
        &stub,
        "#!/usr/bin/env bash\nprintf 'IGC-STUB argv: %s\\n' \"$*\"\nexit \"${STUB_EXIT:-0}\"\n",
    )
    .unwrap();
    fs::set_permissions(&stub, fs::Permissions::from_mode(0o755)).unwrap();
    (dir, stub)
}

/// Run `bin/igniter package <args...>` with IGNITER_IGC_BIN pointed at `stub`; returns (stdout, exit_code).
fn run_package_with_stub(stub: &PathBuf, exit_env: Option<&str>, args: &[&str]) -> (String, i32) {
    let mut cmd = Command::new(wrapper());
    cmd.arg("package").args(args).env("IGNITER_IGC_BIN", stub);
    if let Some(code) = exit_env {
        cmd.env("STUB_EXIT", code);
    }
    let out = cmd.output().expect("run igniter package");
    (
        String::from_utf8_lossy(&out.stdout).to_string(),
        out.status.code().unwrap_or(-1),
    )
}

// ── routing: each subcommand maps to the correct igc argv prefix, trailing args preserved ──────────────

#[test]
fn package_lock_routes_to_igc_lock() {
    let (_d, stub) = make_stub_igc("lock");
    let (out, code) = run_package_with_stub(&stub, None, &["lock", "--frozen"]);
    assert_eq!(code, 0);
    assert!(out.contains("IGC-STUB argv: lock --frozen"), "→ igc lock --frozen: {out}");
}

#[test]
fn package_verify_routes_to_workspace_verify() {
    let (_d, stub) = make_stub_igc("verify");
    let (out, _) = run_package_with_stub(&stub, None, &["verify", "--strict"]);
    // bare `verify` is the WORKSPACE check: `igc verify` (NOT `igc package verify`).
    assert!(out.contains("IGC-STUB argv: verify --strict"), "→ igc verify --strict: {out}");
    assert!(!out.contains("package verify"), "must not route to archive verify: {out}");
}

#[test]
fn package_verify_archive_routes_to_igc_package_verify() {
    let (_d, stub) = make_stub_igc("verifyarch");
    let (out, _) = run_package_with_stub(&stub, None, &["verify-archive", "thing.igpkg"]);
    // the one explicit disambiguation: .igpkg archive verify is `igc package verify`.
    assert!(out.contains("IGC-STUB argv: package verify thing.igpkg"), "→ igc package verify <file>: {out}");
}

#[test]
fn package_graph_pack_admit_route_under_igc_package() {
    for (sub, tail, expect) in [
        ("graph", "--project-root .", "package graph --project-root ."),
        ("pack", "--out a.igpkg", "package pack --out a.igpkg"),
        ("admit", "b.igpkg", "package admit b.igpkg"),
    ] {
        let (_d, stub) = make_stub_igc(&format!("pkg_{sub}"));
        let args: Vec<&str> = std::iter::once(sub).chain(tail.split(' ')).collect();
        let (out, code) = run_package_with_stub(&stub, None, &args);
        assert_eq!(code, 0, "{sub} exits 0");
        assert!(out.contains(&format!("IGC-STUB argv: {expect}")), "{sub} → igc {expect}: {out}");
    }
}

// ── exit-code passthrough ──────────────────────────────────────────────────────────────────────────────

#[test]
fn package_preserves_igc_exit_code() {
    let (_d, stub) = make_stub_igc("exit");
    let (_out, code) = run_package_with_stub(&stub, Some("7"), &["lock"]);
    assert_eq!(code, 7, "the igc exit code must pass through the wrapper verbatim");
}

// ── co-located staged igc is preferred (installed-prefix mode) ───────────────────────────────────────────

#[test]
fn package_prefers_colocated_staged_igc() {
    // Stage a self-contained prefix: a COPY of the wrapper next to a stub `igc` (what bin/igniter-install
    // produces). With NO IGNITER_IGC_BIN override, the wrapper must pick the co-located `igc`, not build.
    let dir = std::env::temp_dir().join(format!("igpkg_colo_{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let staged_wrapper = dir.join("igniter");
    fs::copy(wrapper(), &staged_wrapper).unwrap();
    fs::set_permissions(&staged_wrapper, fs::Permissions::from_mode(0o755)).unwrap();
    let stub = dir.join("igc");
    fs::write(&stub, "#!/usr/bin/env bash\nprintf 'COLOCATED argv: %s\\n' \"$*\"\nexit 0\n").unwrap();
    fs::set_permissions(&stub, fs::Permissions::from_mode(0o755)).unwrap();

    let out = Command::new(&staged_wrapper)
        .args(["package", "lock"])
        .env_remove("IGNITER_IGC_BIN")
        .output()
        .expect("run staged igniter package lock");
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(out.status.success(), "co-located delegation exits 0: {out:?}");
    assert!(s.contains("COLOCATED argv: lock"), "must use the co-located staged igc: {s}");
}

// ── help names the owner and warns it is not a second resolver ──────────────────────────────────────────

#[test]
fn package_help_names_igc_and_warns_not_a_resolver() {
    let out = Command::new(wrapper())
        .args(["package", "--help"])
        .output()
        .expect("run igniter package --help");
    assert!(out.status.success(), "--help exits 0");
    let h = String::from_utf8_lossy(&out.stdout);
    assert!(h.contains("igc"), "names the owner igc: {h}");
    assert!(h.to_lowercase().contains("no second resolver") || h.to_lowercase().contains("routing only"),
        "warns this is not a second resolver: {h}");
    // documents the verify vs verify-archive disambiguation
    assert!(h.contains("verify-archive"), "documents the .igpkg disambiguation: {h}");
}

// ── fail-closed: missing igc never silently succeeds ────────────────────────────────────────────────────

#[test]
fn package_fails_clearly_when_igc_missing() {
    let out = Command::new(wrapper())
        .args(["package", "lock"])
        .env("IGNITER_IGC_BIN", "/nonexistent/path/to/igc")
        .output()
        .expect("run igniter package lock with bad igc");
    assert!(!out.status.success(), "missing igc must fail (non-zero)");
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("cargo build --release") || err.contains("igniter-install"),
        "prints a useful build/install suggestion: {err}");
}

// ── unknown subcommand fails with the supported list (no igc invoked) ───────────────────────────────────

#[test]
fn package_unknown_subcommand_fails_with_help() {
    let out = Command::new(wrapper())
        .args(["package", "frobnicate"])
        .output()
        .expect("run igniter package frobnicate");
    assert_eq!(out.status.code(), Some(2), "unknown subcommand → exit 2");
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("lock") && err.contains("verify-archive"),
        "lists the supported subcommands: {err}");
}
