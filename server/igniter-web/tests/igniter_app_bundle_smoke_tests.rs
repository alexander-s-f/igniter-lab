// igniter_app_bundle_smoke_tests.rs — LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14
//
// Proves `igniter app bundle <app_dir> --out <dir> --version <stamp>` assembles a versioned, self-contained
// IgWeb app bundle per the P13 contract — ASSEMBLY ONLY. The wrapper is told which runner to copy via
// IGNITER_IGWEB_SERVE_BIN = CARGO_BIN_EXE_igweb-serve, so the test never shells out to a nested cargo build.
//
// Covered: happy-path layout + manifest (runner sha256 matches the copied binary, app sources hashed), the
// emitted checks/check.sh passes, and the fail-closed refusals — real host.toml, inline secret (value never
// printed), missing --version — each leaving NO partial bundle, plus help naming host-owned surfaces.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn todo_app() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}

fn igweb_serve_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igweb-serve")
}

fn tmp(tag: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("appbundle_{}_{}", tag, std::process::id()));
    fs::create_dir_all(&d).unwrap();
    d
}

/// Run `bin/igniter app bundle <args...>` with the runner pinned; returns (stdout, stderr, exit_code).
fn run_bundle(args: &[&str]) -> (String, String, i32) {
    let out = Command::new(wrapper())
        .arg("app")
        .arg("bundle")
        .args(args)
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter app bundle");
    (
        String::from_utf8_lossy(&out.stdout).to_string(),
        String::from_utf8_lossy(&out.stderr).to_string(),
        out.status.code().unwrap_or(-1),
    )
}

fn sha256_hex(p: &Path) -> String {
    let out = Command::new("shasum").args(["-a", "256"]).arg(p).output().expect("shasum");
    String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string()
}

/// Copy todo_app into a writable temp app dir so a test can add an offending file (host.toml / secret).
fn writable_app_copy(tag: &str, name: &str) -> PathBuf {
    let app = tmp(tag).join(name);
    fs::create_dir_all(&app).unwrap();
    for entry in fs::read_dir(todo_app()).unwrap() {
        let p = entry.unwrap().path();
        if p.is_file() {
            fs::copy(&p, app.join(p.file_name().unwrap())).unwrap();
        }
    }
    app
}

// ── happy path: layout + manifest + runner sha + emitted check ──────────────────────────────────────────

#[test]
fn bundle_todo_app_produces_valid_layout_and_manifest() {
    let out = tmp("happy");
    let (stdout, stderr, code) = run_bundle(&[&todo_app(), "--out", out.to_str().unwrap(), "--version", "V1"]);
    assert_eq!(code, 0, "bundle must succeed: {stdout}{stderr}");

    let b = out.join("todo_app-V1");
    for rel in [
        "bin/igweb-serve",
        "app/todo_app/igweb.toml",
        "run/run-todo_app.sh",
        "checks/check.sh",
        "systemd/todo_app.service.example",
        "manifest.json",
    ] {
        assert!(b.join(rel).exists(), "missing bundle file: {rel}");
    }

    let manifest = fs::read_to_string(b.join("manifest.json")).unwrap();
    // runner sha256 in the manifest must match the actually-copied binary
    let copied_sha = sha256_hex(&b.join("bin/igweb-serve"));
    assert!(!copied_sha.is_empty());
    assert!(manifest.contains(&copied_sha), "manifest runner sha256 must match copied binary:\n{manifest}");
    // provenance shape
    for needle in ["\"bind_policy\": \"loopback\"", "\"public_release\": false", "\"app_sources\"", "\"entry\": \"Serve\""] {
        assert!(manifest.contains(needle), "manifest missing `{needle}`:\n{manifest}");
    }
    // every app source is hashed
    assert!(manifest.contains("app/todo_app/igweb.toml"), "igweb.toml hashed: {manifest}");
    assert!(manifest.contains("app/todo_app/routes.igweb"), "routes.igweb hashed: {manifest}");

    // emitted check.sh passes on the produced bundle
    let chk = Command::new("bash").arg(b.join("checks/check.sh")).output().expect("run check.sh");
    assert!(chk.status.success(), "emitted check.sh must pass: {:?}", chk);
    // run script defaults to loopback
    let run = fs::read_to_string(b.join("run/run-todo_app.sh")).unwrap();
    assert!(run.contains("127.0.0.1:"), "run script binds loopback: {run}");
}

// ── fail-closed: real host.toml is refused, no partial bundle ────────────────────────────────────────────

#[test]
fn bundle_refuses_real_host_toml_no_partial() {
    let app = writable_app_copy("realhost", "myapp");
    fs::write(app.join("host.toml"), "[host]\nmode=\"loopback\"\n").unwrap();
    let out = tmp("realhost_out");
    let (_o, err, code) = run_bundle(&[app.to_str().unwrap(), "--out", out.to_str().unwrap(), "--version", "V1"]);
    assert_ne!(code, 0, "real host.toml must be refused");
    assert!(err.contains("host.toml"), "names the offending file: {err}");
    assert!(!out.join("myapp-V1").exists(), "no partial bundle may be left behind");
}

// ── fail-closed: inline secret is refused, the value is NEVER printed ────────────────────────────────────

#[test]
fn bundle_refuses_inline_secret_without_printing_value() {
    let app = writable_app_copy("secret", "secapp");
    fs::write(
        app.join("host.example.toml"),
        "[host]\nmode=\"loopback\"\n[postgres.read]\ndsn = \"host=db password=SUPERSECRET123\"\n",
    )
    .unwrap();
    let out = tmp("secret_out");
    let (stdout, stderr, code) = run_bundle(&[app.to_str().unwrap(), "--out", out.to_str().unwrap(), "--version", "V1"]);
    assert_ne!(code, 0, "inline secret must be refused");
    assert!(stderr.contains("inline secret"), "explains the refusal: {stderr}");
    assert!(
        !stdout.contains("SUPERSECRET123") && !stderr.contains("SUPERSECRET123"),
        "the secret value must NEVER be printed:\nSTDOUT:{stdout}\nSTDERR:{stderr}"
    );
    assert!(!out.join("secapp-V1").exists(), "no partial bundle");
}

// ── fail-closed: --version is mandatory (no clock in the tool) ───────────────────────────────────────────

#[test]
fn bundle_requires_version_stamp() {
    let out = tmp("nover");
    let (_o, err, code) = run_bundle(&[&todo_app(), "--out", out.to_str().unwrap()]);
    assert_ne!(code, 0, "missing --version must be refused");
    assert!(err.contains("--version"), "names the missing flag: {err}");
}

// ── help names the host-owned surfaces ──────────────────────────────────────────────────────────────────

#[test]
fn app_help_names_host_owned_surfaces() {
    let out = Command::new(wrapper()).args(["app", "--help"]).output().expect("app --help");
    assert!(out.status.success(), "app --help exits 0");
    let h = String::from_utf8_lossy(&out.stdout);
    assert!(h.contains("ASSEMBLY ONLY") || h.to_lowercase().contains("assembly only"), "states assembly-only: {h}");
    for needle in ["systemd", "TLS", "secrets"] {
        assert!(h.contains(needle), "help must name host-owned surface `{needle}`:\n{h}");
    }
}
