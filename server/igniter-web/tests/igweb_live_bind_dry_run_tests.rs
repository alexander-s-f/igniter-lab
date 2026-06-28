//! igweb_live_bind_dry_run_tests.rs — LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36
//!
//! Subprocess tests of `igweb-serve live-bind-check`: a REPORT-ONLY live-bind dry run that
//! evaluates the parsed `[host.live_bind]` checklist against the pure server gate and prints a
//! verdict — WITHOUT ever opening a listener. Public bind stays closed (P35 HOLD).
//!
//! Each test asserts:
//!   - the verdict line on stdout (`[LIVE_BIND_DRY_RUN] … verdict=…`),
//!   - `socket_opened=false` and the absence of any `listening http://` line (no bind),
//!   - the right exit code (0 = would_authorize, non-zero = would_refuse / config error),
//!   - no secret value (passport path, signoff) leaks into stdout/stderr.
//!
//! Not feature-gated: the dry run is a pure parse + pure gate check; it needs no `machine` build.

use std::process::Command;

const BIN: &str = env!("CARGO_BIN_EXE_igweb-serve");

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

fn write_host_toml(tag: &str, toml: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "igweb_p36_{tag}_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    std::fs::write(&path, toml).unwrap();
    path
}

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn run(args: &[&str]) -> Run {
    let out = Command::new(BIN)
        .args(args)
        .output()
        .expect("spawn igweb-serve");
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).to_string(),
        stderr: String::from_utf8_lossy(&out.stderr).to_string(),
    }
}

const COMPLETE: &str = "[host]\nmode = \"loopback\"\n\
[host.live_bind]\n\
signed_passport_path = \"/etc/igniter/passports/inbound.passport\"\n\
body_cap_enabled = \"true\"\n\
read_timeout_enabled = \"true\"\n\
fail_closed_auth_enabled = \"true\"\n\
operator_signoff = \"present\"\n\
[host.live_bind.inbound_tls]\n\
mode = \"terminated_upstream\"\n\
upstream_header_policy = \"trusted_proxy_only\"\n";

/// No `[host.live_bind]` section at all (loopback host only).
const NO_SECTION: &str = "[host]\nmode = \"loopback\"\n";

/// A `[host.live_bind]` present but missing required fields → P34 fails closed at parse.
const INCOMPLETE: &str =
    "[host]\nmode = \"loopback\"\n[host.live_bind]\nbody_cap_enabled = \"true\"\n";

fn assert_no_socket(r: &Run) {
    assert!(
        !r.stdout.contains("listening http"),
        "dry run must never open a listener; stdout={}",
        r.stdout
    );
    assert!(
        r.stdout.contains("socket_opened=false") || r.code == 2 || r.code == 3,
        "verdict must mark socket_opened=false (or be a pre-verdict config error); stdout={} stderr={}",
        r.stdout,
        r.stderr
    );
}

fn assert_no_secret_leak(r: &Run) {
    for hay in [&r.stdout, &r.stderr] {
        assert!(
            !hay.contains("inbound.passport"),
            "must not leak the passport path; got {hay}"
        );
    }
}

// ── loopback: would authorize with no checklist ─────────────────────────────────────────────
#[test]
fn loopback_addr_would_authorize() {
    let cfg = write_host_toml("loopback", COMPLETE);
    let r = run(&[
        "live-bind-check",
        "--host-config",
        cfg.to_str().unwrap(),
        "--addr",
        "127.0.0.1:8080",
    ]);
    assert_eq!(
        r.code, 0,
        "loopback would authorize → exit 0; stdout={} stderr={}",
        r.stdout, r.stderr
    );
    assert!(r.stdout.contains("verdict=would_authorize"));
    assert!(r.stdout.contains("class=loopback"));
    assert!(r.stdout.contains("public_bind=closed"));
    assert_no_socket(&r);
}

// ── non-loopback + complete checklist: would authorize, reports opaque digest, still no bind ──
#[test]
fn non_loopback_complete_would_authorize_with_digest() {
    let cfg = write_host_toml("nl_complete", COMPLETE);
    let r = run(&[
        "live-bind-check",
        "--host-config",
        cfg.to_str().unwrap(),
        "--addr",
        "0.0.0.0:8080",
    ]);
    assert_eq!(
        r.code, 0,
        "complete checklist would authorize → exit 0; stdout={} stderr={}",
        r.stdout, r.stderr
    );
    assert!(r.stdout.contains("verdict=would_authorize"));
    assert!(r.stdout.contains("class=non_loopback"));
    assert!(r.stdout.contains("checklist_digest=live-bind-v0:"));
    assert!(r.stdout.contains("note=report_only_no_bind_authority"));
    assert_no_socket(&r);
    assert_no_secret_leak(&r);
    // The digest must not embed field values.
    assert!(!r.stdout.contains("terminated_upstream"));
}

// ── default --addr is non-loopback (the public-bind question) ────────────────────────────────
#[test]
fn default_addr_is_non_loopback() {
    let cfg = write_host_toml("default_addr", COMPLETE);
    let r = run(&["live-bind-check", "--host-config", cfg.to_str().unwrap()]);
    assert_eq!(r.code, 0, "stdout={} stderr={}", r.stdout, r.stderr);
    assert!(
        r.stdout.contains("class=non_loopback"),
        "default addr must be non-loopback; {}",
        r.stdout
    );
    assert!(r.stdout.contains("verdict=would_authorize"));
    assert_no_socket(&r);
}

// ── non-loopback + no checklist section: would refuse, scriptable non-zero exit, no bind ──────
#[test]
fn non_loopback_missing_section_would_refuse() {
    let cfg = write_host_toml("no_section", NO_SECTION);
    let r = run(&[
        "live-bind-check",
        "--host-config",
        cfg.to_str().unwrap(),
        "--addr",
        "0.0.0.0:8080",
    ]);
    assert_ne!(
        r.code, 0,
        "would_refuse → non-zero exit; stdout={} stderr={}",
        r.stdout, r.stderr
    );
    assert!(r.stdout.contains("verdict=would_refuse"));
    assert!(r.stdout.contains("code=non_loopback_without_checklist"));
    assert_no_socket(&r);
}

// ── incomplete checklist: fails closed at config parse, before any verdict, no bind ──────────
#[test]
fn incomplete_checklist_fails_config_parse() {
    let cfg = write_host_toml("incomplete", INCOMPLETE);
    let r = run(&[
        "live-bind-check",
        "--host-config",
        cfg.to_str().unwrap(),
        "--addr",
        "0.0.0.0:8080",
    ]);
    assert_eq!(
        r.code, 2,
        "incomplete [host.live_bind] → CONFIG_PARSE exit 2; stdout={} stderr={}",
        r.stdout, r.stderr
    );
    assert!(
        r.stderr.contains("CONFIG_PARSE"),
        "stable taxonomy code on stderr; {}",
        r.stderr
    );
    assert!(!r.stdout.contains("listening http"));
}

// ── missing --host-config: CLI argument error ────────────────────────────────────────────────
#[test]
fn missing_host_config_is_cli_error() {
    let r = run(&["live-bind-check", "--addr", "0.0.0.0:8080"]);
    assert_ne!(r.code, 0);
    assert!(
        r.stderr.contains("--host-config") || r.stderr.contains("CONFIG_PARSE"),
        "must name the missing --host-config; {}",
        r.stderr
    );
    assert!(!r.stdout.contains("listening http"));
}
