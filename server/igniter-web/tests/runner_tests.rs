// igniter-web/tests/runner_tests.rs — LAB-IGNITER-WEB-RUNNER-P12
// Proves the generic runner: tiny igweb.toml parse, default source discovery, and that the P10 Todo app
// runs from `todo_handlers.ig + routes.igweb + igweb.toml` with ZERO authored Rust.

use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use igniter_web::runner::{
    build_app_from_dir, check_app_dir, parse_cli_args, parse_manifest, resolve_sources,
    RunnerCliCommand, RunnerError,
};
use igniter_web::testkit::{http_get, roundtrip, HANDLERS, IGWEB};
use serde_json::json;
use std::net::TcpListener;
use std::path::PathBuf;
use std::thread;

fn example_dir() -> PathBuf {
    PathBuf::from(format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR")))
}

/// Write a throwaway app dir with the given igweb.toml + the canonical handlers/routes.
fn write_app(tag: &str, toml: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("igweb_runner_{}_{}", std::process::id(), tag));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("handlers.ig"), HANDLERS).unwrap();
    std::fs::write(dir.join("routes.igweb"), IGWEB).unwrap();
    std::fs::write(dir.join("igweb.toml"), toml).unwrap();
    dir
}

// ── manifest parsing ──────────────────────────────────────────────────────────────────────────────

#[test]
fn parses_full_manifest() {
    let m = parse_manifest(
        "[app]\nentry = \"Serve\"\nsources = [\"a.ig\", \"b.igweb\"]\n[server]\nmode = \"loopback\"\nmax_requests = 7\n[middleware]\ntrace = true\nbody_limit_bytes = 65536\nauth_token_env = \"TOK\"\n",
    )
    .unwrap();
    assert_eq!(m.entry, "Serve");
    assert_eq!(m.sources, Some(vec!["a.ig".into(), "b.igweb".into()]));
    assert_eq!(m.server_mode.as_deref(), Some("loopback"));
    assert_eq!(m.max_requests, Some(7));
    assert!(m.trace);
    assert_eq!(m.body_limit_bytes, Some(65536));
    assert_eq!(m.auth_token_env.as_deref(), Some("TOK"));
}

#[test]
fn rejects_missing_entry_effects_inline_secret_and_bad_mode() {
    assert!(
        matches!(
            parse_manifest("[server]\nmode=\"loopback\"\n"),
            Err(RunnerError::Manifest(_))
        ),
        "missing entry"
    );
    assert!(
        matches!(
            parse_manifest("[app]\nentry=\"S\"\n[effects]\nx=\"y\"\n"),
            Err(RunnerError::Manifest(_))
        ),
        "[effects] unsupported"
    );
    assert!(
        matches!(
            parse_manifest("[app]\nentry=\"S\"\n[middleware]\nauth_token=\"hunter2\"\n"),
            Err(RunnerError::Manifest(_))
        ),
        "inline secret forbidden"
    );
    assert!(
        matches!(
            parse_manifest("[app]\nentry=\"S\"\n[server]\nmode=\"public\"\n"),
            Err(RunnerError::Manifest(_))
        ),
        "non-loopback mode"
    );
    assert!(
        matches!(
            parse_manifest("[app]\nentry=\"S\"\nbogus=\"x\"\n"),
            Err(RunnerError::Manifest(_))
        ),
        "unknown key"
    );
}

// ── CLI polish ────────────────────────────────────────────────────────────────────────────────────

#[test]
fn cli_help_is_available_without_app_dir() {
    let parsed = parse_cli_args(["--help"]).unwrap();
    match parsed {
        RunnerCliCommand::Help(text) => {
            assert!(text.contains("igweb-serve"));
            assert!(text.contains("run [--addr"));
            assert!(text.contains("check <app_dir>"));
            assert!(text.contains("live-bind-proof"));
            assert!(text.contains("IGNITER_LIVE_BIND_HUMAN_ACK"));
            assert!(text.contains("Commands:"));
            assert!(text.contains("--addr"));
            assert!(text.contains("--max-requests"));
            assert!(text.contains("Loopback only"));
        }
        other => panic!("expected help, got {other:?}"),
    }
}

#[test]
fn cli_defaults_to_loopback_ephemeral_addr() {
    let parsed = parse_cli_args(["examples/todo_app"]).unwrap();
    match parsed {
        RunnerCliCommand::Run(opts) => {
            assert_eq!(opts.app_dir, PathBuf::from("examples/todo_app"));
            assert_eq!(opts.addr.to_string(), "127.0.0.1:0");
            assert_eq!(opts.max_requests, None);
        }
        other => panic!("expected run, got {other:?}"),
    }
}

#[test]
fn cli_explicit_run_parses_like_default_run() {
    let parsed = parse_cli_args([
        "run",
        "--addr",
        "127.0.0.1:39555",
        "--max-requests",
        "2",
        "examples/todo_app",
    ])
    .unwrap();
    match parsed {
        RunnerCliCommand::Run(opts) => {
            assert_eq!(opts.addr.to_string(), "127.0.0.1:39555");
            assert_eq!(opts.max_requests, Some(2));
            assert_eq!(opts.app_dir, PathBuf::from("examples/todo_app"));
        }
        other => panic!("expected run, got {other:?}"),
    }
}

#[test]
fn cli_check_parses_as_dry_build_command() {
    let parsed = parse_cli_args(["check", "examples/todo_app"]).unwrap();
    match parsed {
        RunnerCliCommand::Check(opts) => {
            assert_eq!(opts.app_dir, PathBuf::from("examples/todo_app"));
        }
        other => panic!("expected check, got {other:?}"),
    }
}

#[test]
fn cli_check_rejects_missing_and_extra_app_dir() {
    assert!(
        matches!(parse_cli_args(["check"]), Err(RunnerError::Cli(_))),
        "missing check app dir rejected"
    );
    assert!(
        matches!(
            parse_cli_args(["check", "--help"]),
            Ok(RunnerCliCommand::Help(_))
        ),
        "check --help returns command help"
    );
    assert!(
        matches!(
            parse_cli_args(["check", "one", "two"]),
            Err(RunnerError::Cli(_))
        ),
        "extra check argument rejected"
    );
}

#[test]
fn cli_live_bind_proof_parses_as_human_gated_command() {
    let parsed = parse_cli_args([
        "live-bind-proof",
        "--host-config",
        "/tmp/host.toml",
        "--addr",
        "0.0.0.0:8443",
    ])
    .unwrap();
    match parsed {
        RunnerCliCommand::LiveBindProof(opts) => {
            assert_eq!(opts.host_config_path, PathBuf::from("/tmp/host.toml"));
            assert_eq!(opts.addr.to_string(), "0.0.0.0:8443");
        }
        other => panic!("expected live-bind-proof, got {other:?}"),
    }

    let parsed_default =
        parse_cli_args(["live-bind-proof", "--host-config", "/tmp/host.toml"]).unwrap();
    match parsed_default {
        RunnerCliCommand::LiveBindProof(opts) => {
            assert_eq!(opts.addr.to_string(), "0.0.0.0:8080");
        }
        other => panic!("expected live-bind-proof, got {other:?}"),
    }

    assert!(
        matches!(
            parse_cli_args(["live-bind-proof", "--addr", "0.0.0.0:8080"]),
            Err(RunnerError::Cli(_))
        ),
        "missing proof host config rejected"
    );
}

#[test]
fn cli_accepts_loopback_addr_and_max_override() {
    let parsed = parse_cli_args([
        "--addr",
        "127.0.0.1:39555",
        "--max-requests",
        "2",
        "examples/todo_app",
    ])
    .unwrap();
    match parsed {
        RunnerCliCommand::Run(opts) => {
            assert_eq!(opts.addr.to_string(), "127.0.0.1:39555");
            assert_eq!(opts.max_requests, Some(2));
            assert_eq!(opts.app_dir, PathBuf::from("examples/todo_app"));
        }
        other => panic!("expected run, got {other:?}"),
    }
}

#[test]
fn cli_parses_public_addr_for_server_gate_and_rejects_other_bad_args() {
    match parse_cli_args(["--addr", "0.0.0.0:8080", "examples/todo_app"]).unwrap() {
        RunnerCliCommand::Run(opts) => {
            assert_eq!(opts.addr.to_string(), "0.0.0.0:8080");
        }
        other => panic!("expected run, got {other:?}"),
    }
    assert!(
        matches!(
            parse_cli_args(["--max-requests", "0", "examples/todo_app"]),
            Err(RunnerError::Cli(_))
        ),
        "zero max rejected"
    );
    assert!(
        matches!(
            parse_cli_args(["--wat", "examples/todo_app"]),
            Err(RunnerError::Cli(_))
        ),
        "unknown option rejected"
    );
    assert!(
        matches!(parse_cli_args(["one", "two"]), Err(RunnerError::Cli(_))),
        "extra app dir rejected"
    );
}

// ── check command ──────────────────────────────────────────────────────────────────────────────────

#[test]
fn check_app_dir_builds_without_serving() {
    let report = check_app_dir(&example_dir()).unwrap();
    assert_eq!(report.entry, "Serve");
    assert_eq!(report.source_count, 2);
}

#[test]
fn check_app_dir_reports_build_errors_without_panicking() {
    let dir = write_app("check_bad", "[app]\nentry = \"MissingEntry\"\n");
    assert!(matches!(check_app_dir(&dir), Err(RunnerError::Build(_))));
}

#[test]
fn missing_manifest_is_structured_error() {
    let dir = std::env::temp_dir().join(format!("igweb_runner_nomanifest_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    assert!(matches!(build_app_from_dir(&dir), Err(RunnerError::Io(_))));
}

// ── default source discovery ──────────────────────────────────────────────────────────────────────

#[test]
fn default_source_discovery_is_deterministic_and_excludes_toml() {
    let m = igniter_web::runner::load_manifest(&example_dir()).unwrap();
    let srcs = resolve_sources(&example_dir(), &m).unwrap();
    let names: Vec<String> = srcs
        .iter()
        .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
        .collect();
    assert!(names.contains(&"todo_handlers.ig".to_string()));
    assert!(names.contains(&"routes.igweb".to_string()));
    assert!(
        !names.iter().any(|n| n.ends_with(".toml")),
        "toml is not a source"
    );
    let mut sorted = names.clone();
    sorted.sort();
    assert_eq!(names, sorted, "deterministic (sorted) order");
}

// ── the P10 Todo app runs from manifest, no authored Rust, no web_types.ig ──────────────────────────

fn build_example() -> std::sync::Arc<dyn igniter_server::protocol::ServerApp + Send + Sync> {
    build_app_from_dir(&example_dir())
        .expect("build from examples/todo_app/igweb.toml")
        .0
}

#[test]
fn runner_serves_p10_todo_behavior() {
    let app = build_example();
    assert_eq!(roundtrip(&*app, "GET", "/health", &[], "").0, 200);
    let (s, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(s, 200);
    assert_eq!(
        body["body"],
        json!("42"),
        "path param via generated regexp/capture"
    );
    assert_eq!(
        roundtrip(&*app, "POST", "/todos/42/done", &[], "").0,
        400,
        "keyless → 400"
    );
    let (se, be) = roundtrip(
        &*app,
        "POST",
        "/todos/42/done",
        &[("idempotency-key", "evt-1")],
        "{}",
    );
    assert_eq!(se, 202);
    assert_eq!(be["target"], json!("todo-done"));
    assert_eq!(be["idempotency_key"], json!("evt-1"));
    assert!(
        be.get("capability_id").is_none(),
        "manifest cannot smuggle effect identity"
    );
    assert!(be.get("scope").is_none());
    assert_eq!(roundtrip(&*app, "GET", "/missing", &[], "").0, 404);
    assert_eq!(roundtrip(&*app, "POST", "/health", &[], "").0, 405);
}

// ── middleware from manifest ────────────────────────────────────────────────────────────────────────

#[test]
fn manifest_body_limit_rejects_oversized() {
    let dir = write_app(
        "bodylimit",
        "[app]\nentry = \"Serve\"\n[middleware]\nbody_limit_bytes = 10\n",
    );
    let (app, _m) = build_app_from_dir(&dir).unwrap();
    let big = "{\"x\":\"this is definitely longer than ten bytes\"}";
    assert_eq!(
        roundtrip(&*app, "POST", "/todos", &[("idempotency-key", "k")], big).0,
        413,
        "body limit from manifest applied before app"
    );
}

#[test]
fn manifest_auth_env_short_circuits_then_passes() {
    std::env::set_var("RUNNER_TEST_TOK", "s3cret");
    let dir = write_app(
        "auth",
        "[app]\nentry = \"Serve\"\n[middleware]\nauth_token_env = \"RUNNER_TEST_TOK\"\n",
    );
    let (app, _m) = build_app_from_dir(&dir).unwrap();
    assert_eq!(
        roundtrip(&*app, "GET", "/health", &[], "").0,
        401,
        "no token → auth short-circuits"
    );
    assert_eq!(
        roundtrip(
            &*app,
            "GET",
            "/health",
            &[("authorization", "Bearer s3cret")],
            ""
        )
        .0,
        200,
        "valid token passes"
    );
    std::env::remove_var("RUNNER_TEST_TOK");
}

// ── full runner path: build_app_from_dir → ReloadableApp → serve_loop (bounded) ──────────────────────

#[test]
fn runner_full_path_over_serve_loop() {
    let (app, manifest) = build_app_from_dir(&example_dir()).unwrap();
    assert_eq!(manifest.entry, "Serve");
    let reloadable = ReloadableApp::new(app);
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let reload_srv = reloadable.clone();
    let server = thread::spawn(move || {
        serve_loop(
            &listener,
            &reload_srv,
            &ServingPolicy::new(1).loopback_only(),
        )
        .unwrap()
    });
    assert_eq!(http_get(&addr, "/health"), 200);
    let report = server.join().unwrap();
    assert_eq!(report.requests_served, 1);
}
