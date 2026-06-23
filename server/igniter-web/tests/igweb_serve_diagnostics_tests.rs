//! igweb_serve_diagnostics_tests.rs — LAB-IGNITER-WEB-RUNNER-FAILURE-TAXONOMY-P29
//!
//! Subprocess tests of the real `igweb-serve` binary. Each drives a high-value operator failure and
//! asserts:
//!   - a STABLE taxonomy code on stderr (`[CONFIG_PARSE]`, `[CONFIG_RESOLVE]`, …),
//!   - a non-zero, non-generic exit code,
//!   - no socket opened (stdout never reaches `listening http://`),
//!   - no secret value leaked into stdout or stderr.
//!
//! Gated `--features machine` (the `--host-config` path requires it). No live Postgres.
#![cfg(feature = "machine")]

use std::process::Command;

const BIN: &str = env!("CARGO_BIN_EXE_igweb-serve");

fn app_dir() -> String {
    format!("{}/examples/todo_postgres_app", env!("CARGO_MANIFEST_DIR"))
}

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

/// Write `toml` to a fresh temp host.toml and return its path.
fn write_host_toml(tag: &str, toml: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "igweb_p29_{tag}_{}_{}",
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

fn run_serve(args: &[&str]) -> Run {
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

// ── 1: missing DSN env → CONFIG_RESOLVE, before socket bind ───────────────────────────────────────

#[test]
fn missing_dsn_env_fails_config_resolve_before_bind() {
    let var = format!("IGWEB_P29_UNSET_{}", stamp());
    std::env::remove_var(&var); // belt-and-braces; the random name is already unset
    let host = write_host_toml(
        "resolve",
        &format!("[postgres.read]\ndsn_env = \"{var}\"\n"),
    );

    let r = run_serve(&["--host-config", host.to_str().unwrap(), &app_dir()]);

    assert_ne!(r.code, 0, "must exit non-zero; stderr={}", r.stderr);
    assert_ne!(r.code, 1, "must use a taxonomy exit code, not generic 1");
    assert!(
        r.stderr.contains("[CONFIG_RESOLVE]"),
        "stderr must carry the CONFIG_RESOLVE code; stderr={}",
        r.stderr
    );
    assert!(
        r.stderr.contains(&var),
        "diag must name the missing env var; stderr={}",
        r.stderr
    );
    assert!(
        !r.stdout.contains("listening http"),
        "must fail before socket bind; stdout={}",
        r.stdout
    );
}

// ── 2: inline secret → CONFIG_PARSE, value never echoed ───────────────────────────────────────────

#[test]
fn inline_secret_fails_config_parse_without_leaking_value() {
    let secret_dsn = "postgres://user:hunter2supersecret@db.internal/prod";
    let host = write_host_toml(
        "inline",
        &format!("[postgres.write]\ndsn = \"{secret_dsn}\"\n"),
    );

    let r = run_serve(&["--host-config", host.to_str().unwrap(), &app_dir()]);

    assert_ne!(r.code, 0, "must exit non-zero");
    assert!(
        r.stderr.contains("[CONFIG_PARSE]"),
        "stderr must carry the CONFIG_PARSE code; stderr={}",
        r.stderr
    );
    let combined = format!("{}{}", r.stdout, r.stderr);
    assert!(
        !combined.contains("hunter2supersecret"),
        "the inline secret value must never appear in output; combined={combined}"
    );
    assert!(
        !combined.contains(secret_dsn),
        "the full DSN must never appear in output"
    );
    assert!(
        !r.stdout.contains("listening http"),
        "must fail before socket bind"
    );
}

// ── 3: unknown section → CONFIG_PARSE ─────────────────────────────────────────────────────────────

#[test]
fn unknown_section_fails_config_parse() {
    let host = write_host_toml("unknown", "[vault]\npath = \"secret\"\n");

    let r = run_serve(&["--host-config", host.to_str().unwrap(), &app_dir()]);

    assert_ne!(r.code, 0, "must exit non-zero");
    assert!(
        r.stderr.contains("[CONFIG_PARSE]"),
        "stderr must carry CONFIG_PARSE; stderr={}",
        r.stderr
    );
    assert!(
        !r.stdout.contains("listening http"),
        "must fail before bind"
    );
}

// ── 4: non-loopback bind refused (bad public bind fails closed) ───────────────────────────────────

#[test]
fn non_loopback_addr_fails_closed() {
    let host = write_host_toml("bind", "[host]\nmode = \"loopback\"\n");

    let r = run_serve(&[
        "--host-config",
        host.to_str().unwrap(),
        "--addr",
        "0.0.0.0:0",
        &app_dir(),
    ]);

    assert_ne!(r.code, 0, "non-loopback bind must fail closed");
    assert!(
        r.stderr.contains("[CONFIG_PARSE]") && r.stderr.contains("loopback"),
        "stderr must carry a coded loopback refusal; stderr={}",
        r.stderr
    );
    assert!(
        !r.stdout.contains("listening http"),
        "must never open a public socket; stdout={}",
        r.stdout
    );
}

// ── 5: happy-path minimal host.toml still serves (P12/P22 parity) ──────────────────────────────────

#[test]
fn minimal_host_config_serves_one_request_and_exits_zero() {
    let host = write_host_toml("happy", "[host]\nmode = \"loopback\"\n");

    // max-requests 0 is rejected, so use 1 and let the bounded loop exit after we never connect?
    // Instead: bind ephemeral, serve a bounded single request is impossible without a client here.
    // Use `check`-style proof: the binary must at least reach "listening http://" then we kill it.
    // Simpler and deterministic: spawn, give it a moment, confirm it bound, then drop (kill).
    let mut child = Command::new(BIN)
        .args([
            "--host-config",
            host.to_str().unwrap(),
            "--max-requests",
            "1",
            "--addr",
            "127.0.0.1:0",
            &app_dir(),
        ])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .expect("spawn igweb-serve");

    // Read the bound address line from stdout, then connect once to satisfy the bounded loop.
    use std::io::{BufRead, BufReader, Read, Write};
    let stdout = child.stdout.take().unwrap();
    let mut reader = BufReader::new(stdout);
    let mut addr = String::new();
    let mut listening_line = String::new();
    for _ in 0..10 {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        if let Some(idx) = line.find("http://") {
            listening_line = line.clone();
            let rest = &line[idx + "http://".len()..];
            addr = rest.split_whitespace().next().unwrap_or("").to_string();
            break;
        }
    }
    assert!(
        listening_line.contains("listening http"),
        "binary must reach the listening line; got `{listening_line}`"
    );
    assert!(
        !addr.is_empty(),
        "must parse a bound addr from `{listening_line}`"
    );

    // Connect + send one request so the bounded (max-requests=1) loop completes and the process exits 0.
    if let Ok(mut sock) = std::net::TcpStream::connect(&addr) {
        let _ = sock.write_all(b"GET /health HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n");
        let _ = sock.flush();
        let mut buf = Vec::new();
        let _ = sock.read_to_end(&mut buf);
    }

    let status = child.wait().expect("wait igweb-serve");
    assert!(
        status.success(),
        "happy path must exit 0; status={status:?}"
    );
}
