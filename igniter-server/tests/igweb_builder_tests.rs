// tests/igweb_builder_tests.rs — LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7 (P8: consumes igniter-web)
// Server-integration proofs for an `igniter_web`-built app: ReloadableApp swap of whole built apps +
// P8 middleware composition over the erased app. Pure builder behaviors (params, effect, structured
// errors) live in the `igniter-web` crate's own tests.
#![cfg(feature = "machine")]

use igniter_server::middleware::ServerAppExt;
use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use igniter_web::testkit::{build_todo_app, http_get, roundtrip, HANDLERS, WEB_TYPES};
use igniter_web::{build_igweb_app, IgWebBuildInput};
use std::net::TcpListener;
use std::path::PathBuf;
use std::thread;

fn write_dir(tag: &str, files: &[(&str, &str)]) -> Vec<PathBuf> {
    let dir = std::env::temp_dir().join(format!("igweb_btest_{}_{}", std::process::id(), tag));
    std::fs::create_dir_all(&dir).unwrap();
    files.iter().map(|(name, content)| { let p = dir.join(name); std::fs::write(&p, content).unwrap(); p }).collect()
}

#[test]
fn builder_app_health_smoke() {
    let app = build_todo_app("srv_smoke");
    assert_eq!(roundtrip(&*app, "GET", "/health", &[], "").0, 200);
}

#[test]
fn builder_reload_swaps_whole_loaded_app() {
    // app A = canonical Todo (/health → 200). app B = a different built app (/health unknown → 404).
    let app_a = build_todo_app("srv_reload_a");
    let b_igweb = "app W entry Serve {\n  route GET \"/other\" -> Health\n}\n";
    let b_paths = write_dir("srv_reload_b", &[("web_types.ig", WEB_TYPES), ("handlers.ig", HANDLERS), ("routes_b.igweb", b_igweb)]);
    let app_b = build_igweb_app(IgWebBuildInput { sources: b_paths, entry: "Serve".into() }).expect("build app B");

    let reloadable = ReloadableApp::new(app_a);
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let reload_srv = reloadable.clone();
    let server = thread::spawn(move || serve_loop(&listener, &reload_srv, &ServingPolicy::new(2).loopback_only()).unwrap());

    assert_eq!(http_get(&addr, "/health"), 200);
    reloadable.swap(app_b);
    assert_eq!(http_get(&addr, "/health"), 404, "reload swapped the whole loaded IgWeb app");

    let report = server.join().unwrap();
    assert_eq!(report.requests_served, 2);
}

#[test]
fn builder_composes_with_middleware() {
    // the erased built app composes under P8 wrappers (blanket `impl ServerApp for Arc<A>`).
    let app = build_todo_app("srv_mw");
    let stack = app.with_trace().with_auth("tok");
    assert_eq!(roundtrip(&stack, "GET", "/health", &[], "").0, 401, "auth short-circuits before the IgWeb app");
    assert_eq!(roundtrip(&stack, "GET", "/health", &[("authorization", "Bearer tok")], "").0, 200, "valid token reaches the IgWeb app");
}
