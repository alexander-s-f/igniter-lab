// igniter_serve_wrapper_smoke_tests.rs — LAB-DISTRIBUTION-RAILS-SERVE-DX-P2
//
// Proves the Rails-`s`-style DX contour through the repo-local `bin/igniter` wrapper (shape decided by
// LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1 §5, wrapper "C"):
//
//   * `igniter serve <app> --addr 127.0.0.1:0 --max-requests 1`  → serve a real app over loopback,
//     issue ONE HTTP request, get a 200 response — NO live DB, NO machine feature (sync path).
//   * `igniter serve --check <app>`                              → dry build, opens NO socket.
//   * `igniter serve <app> --addr 0.0.0.0:PORT`                  → public bind REFUSED end-to-end
//     (the safety gate lives in igweb-serve and is preserved through the wrapper).
//
// The wrapper is told which binary to run via IGNITER_IGWEB_SERVE_BIN = CARGO_BIN_EXE_igweb-serve, so the
// test never shells out to a nested cargo build. App: examples/todo_app (the sync, DB-free example).

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

fn wrapper() -> PathBuf {
    // CARGO_MANIFEST_DIR = .../server/igniter-web ; the wrapper lives at the repo root `bin/igniter`.
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn app_dir() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}

fn igweb_serve_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igweb-serve")
}

/// `igniter serve <app> --addr 127.0.0.1:0 --max-requests 1` → real loopback serve → GET /health → 200.
#[test]
fn igniter_serve_app_returns_health_200_no_db() {
    let mut child = Command::new(wrapper())
        .args(["serve", &app_dir(), "--addr", "127.0.0.1:0", "--max-requests", "1"])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn igniter serve");

    // Read stdout until the machine-readable `listening http://127.0.0.1:PORT …` line, then parse the addr.
    let stdout = child.stdout.take().expect("child stdout");
    let mut reader = BufReader::new(stdout);
    let mut captured = String::new();
    let addr = loop {
        let mut line = String::new();
        let n = reader.read_line(&mut line).expect("read stdout");
        if n == 0 {
            panic!("igniter serve exited before listening; stdout so far:\n{captured}");
        }
        captured.push_str(&line);
        if let Some(rest) = line.split("listening http://").nth(1) {
            break rest.split_whitespace().next().unwrap_or("").to_string();
        }
    };
    assert!(
        addr.starts_with("127.0.0.1:"),
        "must bind loopback, got `{addr}` from:\n{captured}"
    );

    // One real HTTP/1.1 request on the parsed socket; the runner is bounded to this single request.
    let mut stream = TcpStream::connect(&addr).expect("connect to served app");
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    stream
        .write_all(b"GET /health HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n")
        .expect("send GET /health");
    let mut resp = String::new();
    stream.read_to_string(&mut resp).expect("read response");
    assert!(
        resp.starts_with("HTTP/1.1 200"),
        "GET /health must be 200, got:\n{resp}"
    );

    let status = child.wait().expect("wait child");
    assert!(status.success(), "igniter serve must exit cleanly after its bounded run");
}

/// `igniter serve --check <app>` → dry build, no socket opened.
#[test]
fn igniter_serve_check_opens_no_socket() {
    let out = Command::new(wrapper())
        .args(["serve", "--check", &app_dir()])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter serve --check");
    assert!(out.status.success(), "check must succeed: {out:?}");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("check ok"), "check ok line: {stdout}");
    assert!(stdout.contains("(no socket opened)"), "must not bind: {stdout}");
}

/// `igniter serve <app> --addr 0.0.0.0:PORT` → public bind REFUSED end-to-end (gate preserved by wrapper).
#[test]
fn igniter_serve_refuses_public_bind() {
    let out = Command::new(wrapper())
        .args(["serve", &app_dir(), "--addr", "0.0.0.0:8080"])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter serve --addr public");
    assert!(!out.status.success(), "public bind must fail");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("loopback-only"),
        "must refuse non-loopback bind: {stderr}"
    );
}

/// `igniter serve --help` prints the wrapper usage naming app dir, bind default, --host-config, safety.
#[test]
fn igniter_serve_help_names_contract() {
    let out = Command::new(wrapper())
        .args(["serve", "--help"])
        .output()
        .expect("run igniter serve --help");
    assert!(out.status.success());
    let help = String::from_utf8_lossy(&out.stdout);
    for needle in ["<app_dir>", "127.0.0.1:0", "--host-config", "loopback-only", "--check"] {
        assert!(help.contains(needle), "help must name `{needle}`:\n{help}");
    }
}
