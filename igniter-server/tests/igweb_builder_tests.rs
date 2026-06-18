// tests/igweb_builder_tests.rs — LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7
// Proves the reusable `build_igweb_app` builder: build-from-paths, route params, logical InvokeEffect,
// structured lowering/compile errors, ReloadableApp swap of whole built apps, and middleware composition.
#![cfg(feature = "machine")]

use igniter_server::middleware::ServerAppExt;
use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use serde_json::json;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::thread;

#[path = "support/igweb_build.rs"]
mod igweb_build;
use igweb_build::{build_igweb_app, build_todo_app, roundtrip, IgWebBuildError, IgWebBuildInput, HANDLERS, WEB_TYPES};

fn write_dir(tag: &str, files: &[(&str, &str)]) -> Vec<PathBuf> {
    let dir = std::env::temp_dir().join(format!("igweb_btest_{}_{}", std::process::id(), tag));
    std::fs::create_dir_all(&dir).unwrap();
    files
        .iter()
        .map(|(name, content)| {
            let p = dir.join(name);
            std::fs::write(&p, content).unwrap();
            p
        })
        .collect()
}

#[test]
fn builder_builds_health_app() {
    let app = build_todo_app("b_health");
    assert_eq!(roundtrip(&*app, "GET", "/health", &[], "").0, 200);
}

#[test]
fn builder_preserves_route_params() {
    let app = build_todo_app("b_param");
    let (status, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["body"], json!("42"), "id flows via generated regexp/capture, not a Rust match");
}

#[test]
fn builder_emits_logical_invoke_effect() {
    let app = build_todo_app("b_effect");
    let (status, body) = roundtrip(&*app, "POST", "/todos/42/done", &[("idempotency-key", "k-7")], "{}");
    assert_eq!(status, 202);
    assert_eq!(body["decision"], json!("invoke_effect"));
    assert_eq!(body["target"], json!("todo-done"));
    assert_eq!(body["idempotency_key"], json!("k-7"));
    assert!(body.get("capability_id").is_none(), "no privileged effect identity");
    assert!(body.get("scope").is_none());
}

#[test]
fn builder_reports_lowering_error() {
    // malformed route line (missing quotes) → structured Lower error pointing at the `.igweb` line.
    let bad = "app X entry Serve {\n  route GET /todos -> Health\n}\n";
    let paths = write_dir("b_lowerr", &[("web_types.ig", WEB_TYPES), ("handlers.ig", HANDLERS), ("routes.igweb", bad)]);
    match build_igweb_app(IgWebBuildInput { sources: paths, entry: "Serve".into() }) {
        Err(IgWebBuildError::Lower { line, .. }) => assert_eq!(line, 2),
        Err(e) => panic!("expected Lower error at line 2, got {e:?}"),
        Ok(_) => panic!("expected Lower error, got Ok"),
    }
}

#[test]
fn builder_reports_compile_error() {
    // a broken support `.ig` (nameless contract = parse error) → structured Load error, not a panic.
    // The `.igweb` lowering itself is valid; the failure is in compile/load of the support module.
    let broken_handlers = format!("{HANDLERS}\npure contract {{ input req : Request }}\n");
    let valid_igweb = "app X entry Serve {\n  route GET \"/health\" -> Health\n}\n";
    let paths = write_dir("b_comperr", &[("web_types.ig", WEB_TYPES), ("handlers.ig", &broken_handlers), ("routes.igweb", valid_igweb)]);
    match build_igweb_app(IgWebBuildInput { sources: paths, entry: "Serve".into() }) {
        Err(IgWebBuildError::Load(msg)) => assert!(!msg.is_empty(), "compile/load error is structured"),
        Err(e) => panic!("expected Load error, got {e:?}"),
        Ok(_) => panic!("expected Load error, got Ok"),
    }
}

#[test]
fn builder_reload_swaps_whole_loaded_app() {
    // app A = canonical Todo (/health → 200). app B = a different built app (/health unknown → 404).
    let app_a = build_todo_app("b_reload_a");
    let b_igweb = "app W entry Serve {\n  route GET \"/other\" -> Health\n}\n";
    let b_paths = write_dir("b_reload_b", &[("web_types.ig", WEB_TYPES), ("handlers.ig", HANDLERS), ("routes_b.igweb", b_igweb)]);
    let app_b = build_igweb_app(IgWebBuildInput { sources: b_paths, entry: "Serve".into() }).expect("build app B");

    let reloadable = ReloadableApp::new(app_a);
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let reload_srv = reloadable.clone();
    let server = thread::spawn(move || serve_loop(&listener, &reload_srv, &ServingPolicy::new(2).loopback_only()).unwrap());

    // A serves /health → 200.
    assert_eq!(http_get(&addr, "/health"), 200);
    // swap the WHOLE built app to B; B has no /health → 404.
    reloadable.swap(app_b);
    assert_eq!(http_get(&addr, "/health"), 404, "reload swapped the whole loaded IgWeb app");

    let report = server.join().unwrap();
    assert_eq!(report.requests_served, 2);
}

#[test]
fn builder_composes_with_middleware() {
    // the erased built app composes under P8 wrappers (blanket `impl ServerApp for Arc<A>`).
    let app = build_todo_app("b_mw");
    let stack = app.with_trace().with_auth("tok");
    assert_eq!(roundtrip(&stack, "GET", "/health", &[], "").0, 401, "auth short-circuits before the IgWeb app");
    assert_eq!(roundtrip(&stack, "GET", "/health", &[("authorization", "Bearer tok")], "").0, 200, "valid token reaches the IgWeb app");
}

fn http_get(addr: &str, path: &str) -> u16 {
    let mut s = TcpStream::connect(addr).unwrap();
    s.write_all(format!("GET {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n").as_bytes()).unwrap();
    s.flush().unwrap();
    let mut raw = Vec::new();
    s.read_to_end(&mut raw).unwrap();
    String::from_utf8_lossy(&raw).split_whitespace().nth(1).and_then(|x| x.parse().ok()).unwrap_or(0)
}
