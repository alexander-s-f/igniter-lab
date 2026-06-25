// igniter_agent_mcp_smoke_tests.rs — LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24
//
// Hermetic stdio smoke of the command-center MCP surface reached via `igniter agent`. Drives the server with
// `initialize` → `tools/list` → `tools/call` and asserts the responses. No network, no DB, no public socket,
// no mutation: every tool shell-delegates to `bin/igniter` (doctor/toolchain list/check are read-only/dry).
//
// `igniter agent` is pinned to the test-built `igniter-agent` (IGNITER_AGENT_BIN) and `check_app` is pinned to
// the test-built `igweb-serve` (IGNITER_IGWEB_SERVE_BIN), so nothing shells out to a nested cargo build.

use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};

use serde_json::Value;

/// Fresh temp dir for a test.
fn tmp(tag: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("agentbundle_{}_{}", tag, std::process::id()));
    fs::create_dir_all(&d).unwrap();
    d
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

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn todo_app() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}

/// Send the given JSON-RPC request lines to `igniter agent` over stdin; collect parsed response objects.
fn drive_agent(requests: &[&str]) -> Vec<Value> {
    let mut child = Command::new(wrapper())
        .arg("agent")
        .env("IGNITER_AGENT_BIN", env!("CARGO_BIN_EXE_igniter-agent"))
        .env("IGNITER_IGWEB_SERVE_BIN", env!("CARGO_BIN_EXE_igweb-serve"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn igniter agent");

    {
        let mut stdin = child.stdin.take().unwrap();
        for r in requests {
            writeln!(stdin, "{}", r).unwrap();
        }
        // drop stdin → EOF → the agent's read loop ends and it exits
    }

    let mut out = String::new();
    child.stdout.take().unwrap().read_to_string(&mut out).unwrap();
    let _ = child.wait();

    out.lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str::<Value>(l).expect("each response line is JSON"))
        .collect()
}

fn by_id(responses: &[Value], id: i64) -> &Value {
    responses
        .iter()
        .find(|m| m.get("id").and_then(|v| v.as_i64()) == Some(id))
        .unwrap_or_else(|| panic!("no response with id {id}"))
}

/// `tools/call` result text + isError flag.
fn tool_text(resp: &Value) -> (String, bool) {
    let result = resp.get("result").expect("tool result");
    let text = result["content"][0]["text"].as_str().unwrap_or("").to_string();
    let is_error = result.get("isError").and_then(|v| v.as_bool()).unwrap_or(false);
    (text, is_error)
}

#[test]
fn agent_initialize_and_lists_only_safe_tools() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
        r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
    ]);

    // initialize → serverInfo identifies the command-center agent
    let init = by_id(&r, 1);
    assert_eq!(init["result"]["serverInfo"]["name"], "igniter-agent", "initialize names the agent: {init}");

    // tools/list → exactly the v0 safe set; NO deploy/public-bind/secret/systemd tools
    let tools: Vec<String> = by_id(&r, 2)["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].as_str().unwrap().to_string())
        .collect();
    for want in ["doctor", "toolchain_list", "check_app", "package_verify", "serve_app_bounded", "app_bundle"] {
        assert!(tools.contains(&want.to_string()), "tools/list must include `{want}`: {tools:?}");
    }
    // `serve_app_bounded` is the ONLY serve-shaped tool and is bounded/loopback by construction; nothing
    // deploy/install/systemd/secret/daemon-like exists in v0.
    for forbidden in ["deploy", "install", "systemd", "secret", "apply", "daemon", "restart", "bind", "upload"] {
        assert!(!tools.iter().any(|t| t.contains(forbidden)), "no `{forbidden}`-like tool in v0: {tools:?}");
    }
}

#[test]
fn agent_doctor_and_toolchain_list_tools_return_local_reports() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"toolchain_list","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"doctor","arguments":{}}}"#,
    ]);

    let (tl, tl_err) = tool_text(by_id(&r, 3));
    assert!(!tl_err, "toolchain_list must succeed: {tl}");
    assert!(tl.contains("5 default binaries"), "names the default fleet: {tl}");
    assert!(tl.contains("igniter-repl") && tl.contains("optional"), "names optional repl: {tl}");

    let (doc, doc_err) = tool_text(by_id(&r, 4));
    assert!(!doc_err, "doctor must succeed: {doc}");
    assert!(doc.contains("exit_code: 0"), "doctor reports exit 0: {doc}");
}

#[test]
fn agent_check_app_succeeds_and_opens_no_socket() {
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{{"name":"check_app","arguments":{{"app_dir":"{}"}}}}}}"#,
        app
    );
    let r = drive_agent(&[&req]);
    let (text, is_err) = tool_text(by_id(&r, 5));
    assert!(!is_err, "check_app on a real app must succeed: {text}");
    assert!(text.contains("check ok"), "delegated check ok: {text}");
    assert!(text.contains("no socket opened"), "opens no socket: {text}");
}

#[test]
fn agent_bad_check_app_and_unknown_tool_error_without_panicking() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"check_app","arguments":{"app_dir":"/nonexistent/app"}}}"#,
        r#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"check_app","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"frobnicate","arguments":{}}}"#,
    ]);

    let (_t6, e6) = tool_text(by_id(&r, 6));
    assert!(e6, "a bad app path is a tool error (isError), not a panic");

    let (t7, e7) = tool_text(by_id(&r, 7));
    assert!(e7 && t7.contains("missing required argument"), "missing app_dir is a clean tool error: {t7}");

    let (t8, e8) = tool_text(by_id(&r, 8));
    assert!(e8 && t8.contains("unknown tool"), "unknown tool is a clean error: {t8}");
}

// ── serve_app_bounded (P25): bounded, loopback, no daemon ───────────────────────────────────────────────

#[test]
fn agent_serve_app_bounded_serves_health_200_and_exits_clean() {
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{{"name":"serve_app_bounded","arguments":{{"app_dir":"{}","max_requests":1,"path":"/health"}}}}}}"#,
        app
    );
    let r = drive_agent(&[&req]);
    let (text, is_err) = tool_text(by_id(&r, 9));
    assert!(!is_err, "bounded serve of a real app must succeed: {text}");
    assert!(text.contains("listen: 127.0.0.1:"), "MUST bind loopback (no public bind param exists): {text}");
    assert!(text.contains("HTTP/1.1 200"), "GET /health is 200: {text}");
    assert!(text.contains("all_200: true"), "the bounded request succeeded: {text}");
    // exit_code present + 0 proves the child was reaped (no long-running/daemon child left behind).
    assert!(text.contains("exit_code: 0"), "bounded child exited cleanly (reaped, no daemon): {text}");
}

#[test]
fn agent_serve_app_bounded_clamps_max_requests() {
    // 99 must clamp to the v0 max of 5 — the tool never starts an unbounded or large run.
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{{"name":"serve_app_bounded","arguments":{{"app_dir":"{}","max_requests":99}}}}}}"#,
        app
    );
    let r = drive_agent(&[&req]);
    let (text, is_err) = tool_text(by_id(&r, 10));
    assert!(!is_err, "clamped bounded serve must still succeed: {text}");
    assert!(text.contains("clamped 99") && text.contains("requests_issued: 5"),
        "max_requests 99 must clamp to 5: {text}");
}

#[test]
fn agent_serve_app_bounded_bad_path_errors_cleanly() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"serve_app_bounded","arguments":{"app_dir":"/nonexistent/app"}}}"#,
        r#"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"serve_app_bounded","arguments":{}}}"#,
    ]);
    let (t11, e11) = tool_text(by_id(&r, 11));
    assert!(e11, "a bad app path is a controlled tool error, not a hang/panic: {t11}");
    assert!(t11.contains("never bound"), "reports the app never bound: {t11}");

    let (t12, e12) = tool_text(by_id(&r, 12));
    assert!(e12 && t12.contains("missing required argument"), "missing app_dir is a clean error: {t12}");
}

// ── app_bundle (P26): shell-delegate to `igniter app bundle`; bundler owns all safety ────────────────────

#[test]
fn agent_app_bundle_builds_todo_bundle() {
    let out = tmp("ok_out");
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}","out_dir":"{}","version":"V1"}}}}}}"#,
        app,
        out.display()
    );
    let r = drive_agent(&[&req]);
    let (text, is_err) = tool_text(by_id(&r, 13));
    assert!(!is_err, "app_bundle of a real app must succeed: {text}");
    assert!(text.contains("app bundle ok"), "result carries the destination summary: {text}");

    // the produced bundle exists and has the P14 layout
    let b = out.join("todo_app-V1");
    for rel in [
        "bin/igweb-serve",
        "app/todo_app/igweb.toml",
        "run/run-todo_app.sh",
        "checks/check.sh",
        "systemd/todo_app.service.example",
        "manifest.json",
    ] {
        assert!(b.join(rel).exists(), "bundle missing {rel}:\n{text}");
    }

    // manifest parses + carries provenance/safety fields
    let manifest = fs::read_to_string(b.join("manifest.json")).unwrap();
    let mv: Value = serde_json::from_str(&manifest).expect("manifest.json is valid JSON");
    assert_eq!(mv["bind_policy"], "loopback", "manifest bind_policy: {manifest}");
    assert_eq!(mv["public_release"], false, "manifest public_release: {manifest}");
    assert!(mv["runner"]["sha256"].as_str().is_some(), "runner sha present: {manifest}");
    assert!(mv["app_sources"].as_array().map(|a| !a.is_empty()).unwrap_or(false), "app sources hashed: {manifest}");

    // the emitted check.sh passes on the produced bundle
    let chk = Command::new("bash").arg(b.join("checks/check.sh")).output().expect("run check.sh");
    assert!(chk.status.success(), "emitted check.sh must pass: {chk:?}");
}

#[test]
fn agent_app_bundle_missing_args_are_tool_errors() {
    let out = tmp("missing_out");
    let app = todo_app();
    // missing version
    let req_a = format!(
        r#"{{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}","out_dir":"{}"}}}}}}"#,
        app,
        out.display()
    );
    // missing out_dir AND version
    let req_b = format!(
        r#"{{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}"}}}}}}"#,
        app
    );
    let r = drive_agent(&[&req_a, &req_b]);
    for id in [14, 15] {
        let (t, e) = tool_text(by_id(&r, id));
        assert!(e && t.contains("missing required argument"), "id{id}: missing arg → clean tool error: {t}");
    }
}

#[test]
fn agent_app_bundle_refuses_host_toml_and_inline_secret_without_leak() {
    // real host.toml → refused, no partial bundle
    let app1 = writable_app_copy("host", "hostapp");
    fs::write(app1.join("host.toml"), "[host]\nmode=\"loopback\"\n").unwrap();
    let out1 = tmp("host_out");
    let req1 = format!(
        r#"{{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}","out_dir":"{}","version":"V1"}}}}}}"#,
        app1.display(),
        out1.display()
    );

    // inline secret in host.example.toml → refused, value never leaked
    let app2 = writable_app_copy("secret", "secapp");
    fs::write(
        app2.join("host.example.toml"),
        "[host]\nmode=\"loopback\"\n[postgres.read]\ndsn = \"host=db password=SUPERSECRET123\"\n",
    )
    .unwrap();
    let out2 = tmp("secret_out");
    let req2 = format!(
        r#"{{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}","out_dir":"{}","version":"V1"}}}}}}"#,
        app2.display(),
        out2.display()
    );

    let r = drive_agent(&[&req1, &req2]);

    let (t16, e16) = tool_text(by_id(&r, 16));
    assert!(e16, "real host.toml must be refused through MCP: {t16}");
    assert!(!out1.join("hostapp-V1").exists(), "no partial bundle after host.toml refusal");

    let (t17, e17) = tool_text(by_id(&r, 17));
    assert!(e17, "inline secret must be refused through MCP: {t17}");
    assert!(!t17.contains("SUPERSECRET123"), "the secret value must NEVER appear in the tool text: {t17}");
    assert!(!out2.join("secapp-V1").exists(), "no partial bundle after secret refusal");
}
