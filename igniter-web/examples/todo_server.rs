//! `cargo run --example todo_server` — the first real IgWeb app (LAB-IGNITER-WEB-EXAMPLE-APP-P9).
//!
//! A developer authors plain files — `examples/todo_app/{web_types.ig, todo_handlers.ig, routes.igweb}`
//! — and a tiny Rust runner builds them into a `ServerApp` via `igniter_web::build_igweb_app` and serves
//! a bounded loopback run through `igniter_server::host::serve_bounded`. No domain code in
//! `igniter-server`; routing lives in `routes.igweb`; effect authority stays host-side.

use igniter_web::{build_igweb_app, IgWebBuildInput};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::thread;

fn src(rel: &str) -> PathBuf {
    PathBuf::from(format!("{}/examples/todo_app/{}", env!("CARGO_MANIFEST_DIR"), rel))
}

/// One loopback request → (status, body text).
fn http_call(addr: &str, method: &str, path: &str, idem: Option<&str>, body: &str) -> (u16, String) {
    let mut s = TcpStream::connect(addr).unwrap();
    let idem_h = idem.map(|k| format!("Idempotency-Key: {k}\r\n")).unwrap_or_default();
    let req = format!("{method} {path} HTTP/1.1\r\nHost: x\r\n{idem_h}Content-Length: {}\r\n\r\n{}", body.len(), body);
    s.write_all(req.as_bytes()).unwrap();
    s.flush().unwrap();
    let mut raw = Vec::new();
    s.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();
    let status: u16 = text.split_whitespace().nth(1).and_then(|x| x.parse().ok()).unwrap_or(0);
    let bs = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
    (status, text[bs..].trim().to_string())
}

fn main() -> std::io::Result<()> {
    let app = build_igweb_app(IgWebBuildInput {
        sources: vec![src("todo_handlers.ig"), src("routes.igweb")],
        entry: "Serve".into(),
    })
    .expect("build the IgWeb todo app from authored files");

    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    let addr = listener.local_addr()?.to_string();
    println!("todo_server on http://{addr} (loopback, bounded; built from examples/todo_app/*.ig + routes.igweb)");

    // The request script — exercises every route + refusals, deterministically.
    let script: Vec<(&str, &str, Option<&str>, &str)> = vec![
        ("GET", "/health", None, ""),
        ("GET", "/todos", None, ""),
        ("GET", "/todos/42", None, ""),
        ("POST", "/todos/42/done", None, ""),         // keyless → 400
        ("POST", "/todos/42/done", Some("evt-1"), "{}"), // keyed → InvokeEffect (202)
        ("GET", "/missing", None, ""),                // 404
        ("POST", "/health", None, ""),                // 405
    ];
    let n = script.len();
    let addr_c = addr.clone();
    let client = thread::spawn(move || {
        script
            .into_iter()
            .map(|(m, p, idem, body)| (m, p, http_call(&addr_c, m, p, idem, body)))
            .collect::<Vec<_>>()
    });

    igniter_server::host::serve_bounded(&listener, &*app, n).unwrap();

    for (m, p, (status, body)) in client.join().unwrap() {
        println!("{m:<4} {p:<20} -> {status}  {body}");
    }
    println!("served {n} bounded requests; exiting");
    Ok(())
}
