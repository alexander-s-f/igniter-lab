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
    child
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut out)
        .unwrap();
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

/// `tools/call` result text (content[0], human) + isError flag.
fn tool_text(resp: &Value) -> (String, bool) {
    let result = resp.get("result").expect("tool result");
    let text = result["content"][0]["text"]
        .as_str()
        .unwrap_or("")
        .to_string();
    let is_error = result
        .get("isError")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    (text, is_error)
}

/// P28: the additive JSON envelope (content[1]) parsed back into a Value. Panics if it is missing/invalid.
fn envelope(resp: &Value) -> Value {
    let text = resp["result"]["content"][1]["text"]
        .as_str()
        .expect("content[1] must be a text item (the JSON envelope)");
    serde_json::from_str(text).expect("the envelope must be valid JSON")
}

#[test]
fn agent_initialize_and_lists_only_safe_tools() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
        r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
    ]);

    // initialize → serverInfo identifies the command-center agent
    let init = by_id(&r, 1);
    assert_eq!(
        init["result"]["serverInfo"]["name"], "igniter-agent",
        "initialize names the agent: {init}"
    );

    // tools/list → exactly the v0 safe set; NO deploy/public-bind/secret/systemd tools
    let tools: Vec<String> = by_id(&r, 2)["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].as_str().unwrap().to_string())
        .collect();
    for want in [
        "doctor",
        "toolchain_list",
        "check_app",
        "package_verify",
        "serve_app_bounded",
        "app_bundle",
        "env_doctor",
        "env_check",
    ] {
        assert!(
            tools.contains(&want.to_string()),
            "tools/list must include `{want}`: {tools:?}"
        );
    }
    // `serve_app_bounded` is the ONLY serve-shaped tool and is bounded/loopback by construction; nothing
    // deploy/install/systemd/secret/daemon-like exists in v0.
    for forbidden in [
        "deploy", "install", "systemd", "secret", "apply", "daemon", "restart", "bind", "upload",
    ] {
        assert!(
            !tools.iter().any(|t| t.contains(forbidden)),
            "no `{forbidden}`-like tool in v0: {tools:?}"
        );
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
    assert!(
        tl.contains("5 default binaries"),
        "names the default fleet: {tl}"
    );
    assert!(
        tl.contains("igniter-repl") && tl.contains("optional"),
        "names optional repl: {tl}"
    );

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
    assert!(
        e7 && t7.contains("missing required argument"),
        "missing app_dir is a clean tool error: {t7}"
    );

    let (t8, e8) = tool_text(by_id(&r, 8));
    assert!(
        e8 && t8.contains("unknown tool"),
        "unknown tool is a clean error: {t8}"
    );
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
    assert!(
        text.contains("listen: 127.0.0.1:"),
        "MUST bind loopback (no public bind param exists): {text}"
    );
    assert!(text.contains("HTTP/1.1 200"), "GET /health is 200: {text}");
    assert!(
        text.contains("all_200: true"),
        "the bounded request succeeded: {text}"
    );
    // exit_code present + 0 proves the child was reaped (no long-running/daemon child left behind).
    assert!(
        text.contains("exit_code: 0"),
        "bounded child exited cleanly (reaped, no daemon): {text}"
    );
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
    assert!(
        text.contains("clamped 99") && text.contains("requests_issued: 5"),
        "max_requests 99 must clamp to 5: {text}"
    );
}

#[test]
fn agent_serve_app_bounded_bad_path_errors_cleanly() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"serve_app_bounded","arguments":{"app_dir":"/nonexistent/app"}}}"#,
        r#"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"serve_app_bounded","arguments":{}}}"#,
    ]);
    let (t11, e11) = tool_text(by_id(&r, 11));
    assert!(
        e11,
        "a bad app path is a controlled tool error, not a hang/panic: {t11}"
    );
    assert!(
        t11.contains("never bound"),
        "reports the app never bound: {t11}"
    );

    let (t12, e12) = tool_text(by_id(&r, 12));
    assert!(
        e12 && t12.contains("missing required argument"),
        "missing app_dir is a clean error: {t12}"
    );
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
    assert!(
        text.contains("app bundle ok"),
        "result carries the destination summary: {text}"
    );

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
    assert_eq!(
        mv["bind_policy"], "loopback",
        "manifest bind_policy: {manifest}"
    );
    assert_eq!(
        mv["public_release"], false,
        "manifest public_release: {manifest}"
    );
    assert!(
        mv["runner"]["sha256"].as_str().is_some(),
        "runner sha present: {manifest}"
    );
    assert!(
        mv["app_sources"]
            .as_array()
            .map(|a| !a.is_empty())
            .unwrap_or(false),
        "app sources hashed: {manifest}"
    );

    // the emitted check.sh passes on the produced bundle
    let chk = Command::new("bash")
        .arg(b.join("checks/check.sh"))
        .output()
        .expect("run check.sh");
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
        assert!(
            e && t.contains("missing required argument"),
            "id{id}: missing arg → clean tool error: {t}"
        );
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
    assert!(
        !out1.join("hostapp-V1").exists(),
        "no partial bundle after host.toml refusal"
    );

    let (t17, e17) = tool_text(by_id(&r, 17));
    assert!(e17, "inline secret must be refused through MCP: {t17}");
    assert!(
        !t17.contains("SUPERSECRET123"),
        "the secret value must NEVER appear in the tool text: {t17}"
    );
    assert!(
        !out2.join("secapp-V1").exists(),
        "no partial bundle after secret refusal"
    );
}

// ── P28: additive JSON envelopes (content[1]) ───────────────────────────────────────────────────────────

#[test]
fn agent_results_include_json_envelope_for_basic_tools() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"toolchain_list","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"package_verify","arguments":{}}}"#,
    ]);
    for (id, tool) in [(20, "toolchain_list"), (21, "package_verify")] {
        let resp = by_id(&r, id);
        // content[0] human text is still present (back-compat)
        let (_human, is_err) = tool_text(resp);
        assert!(!_human.is_empty(), "id{id}: content[0] human text present");
        let env = envelope(resp);
        assert_eq!(env["tool"], tool, "envelope tool name: {env}");
        // `ok` mirrors `!isError` (package_verify may legitimately fail e.g. no lockfile — still a valid envelope)
        assert_eq!(env["ok"], !is_err, "envelope ok mirrors !isError: {env}");
        assert!(
            env["exit_code"].is_i64(),
            "exit_code present (a command ran): {env}"
        );
        assert!(
            env["parsed"].is_null(),
            "{tool} parsed is null in v0: {env}"
        );
        assert!(
            env["stdout"].is_string() && env["stderr"].is_string(),
            "stdout/stderr strings: {env}"
        );
    }
}

#[test]
fn agent_doctor_envelope_carries_parsed_json_report() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"doctor","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"doctor","arguments":{"json":true}}}"#,
    ]);
    let resp = by_id(&r, 22);
    assert!(
        tool_text(resp).0.contains("exit_code: 0"),
        "content[0] human report preserved"
    );
    let env = envelope(resp);
    assert_eq!(env["tool"], "doctor");
    assert_eq!(env["ok"], true);
    assert_eq!(env["exit_code"], 0);
    let parsed = &env["parsed"];
    let arr = parsed.as_array().expect("doctor parsed is a JSON array");
    assert!(
        !arr.is_empty(),
        "doctor parsed has at least one item: {parsed}"
    );
    let item = &arr[0];
    for k in ["scope", "check", "severity"] {
        assert!(item.get(k).is_some(), "doctor item carries `{k}`: {item}");
    }

    let json_resp = by_id(&r, 30);
    let (human, is_err) = tool_text(json_resp);
    assert!(!is_err, "doctor json:true still succeeds: {human}");
    assert!(
        human.contains("stdout:\n[") || human.contains("stdout:\r\n["),
        "json:true preserves JSON stdout in content[0]: {human}"
    );
    let json_env = envelope(json_resp);
    assert!(
        json_env["parsed"]
            .as_array()
            .map(|a| !a.is_empty())
            .unwrap_or(false),
        "json:true still carries parsed doctor JSON in content[1]: {json_env}"
    );
}

#[test]
fn agent_serve_bounded_envelope_carries_runtime_fields() {
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{{"name":"serve_app_bounded","arguments":{{"app_dir":"{}","max_requests":1}}}}}}"#,
        app
    );
    let r = drive_agent(&[&req]);
    let resp = by_id(&r, 23);
    let env = envelope(resp);
    assert_eq!(env["tool"], "serve_app_bounded");
    let p = &env["parsed"];
    assert!(
        p["listen"].as_str().unwrap_or("").starts_with("127.0.0.1:"),
        "parsed.listen loopback: {p}"
    );
    assert_eq!(p["requests_issued"], 1, "parsed.requests_issued: {p}");
    assert!(
        p["http_status"]
            .as_str()
            .unwrap_or("")
            .contains("HTTP/1.1 200"),
        "parsed.http_status 200: {p}"
    );
}

#[test]
fn agent_app_bundle_envelope_carries_manifest() {
    let out = tmp("env_out");
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}","out_dir":"{}","version":"V1"}}}}}}"#,
        app,
        out.display()
    );
    let r = drive_agent(&[&req]);
    let env = envelope(by_id(&r, 24));
    assert_eq!(env["tool"], "app_bundle");
    let p = &env["parsed"];
    assert!(
        p["bundle_path"]
            .as_str()
            .map(|s| s.contains("todo_app-V1"))
            .unwrap_or(false),
        "parsed.bundle_path: {p}"
    );
    assert_eq!(
        p["manifest"]["bind_policy"], "loopback",
        "parsed.manifest.bind_policy: {p}"
    );
    assert_eq!(
        p["manifest"]["public_release"], false,
        "parsed.manifest.public_release: {p}"
    );
}

#[test]
fn agent_check_app_envelope_carries_check_shape() {
    let app = todo_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":25,"method":"tools/call","params":{{"name":"check_app","arguments":{{"app_dir":"{}"}}}}}}"#,
        app
    );
    let r = drive_agent(&[&req]);
    let env = envelope(by_id(&r, 25));
    assert_eq!(env["tool"], "check_app");
    let p = &env["parsed"];
    assert_eq!(p["entry"], "Serve", "parsed.entry: {p}");
    assert!(p["sources"].is_i64(), "parsed.sources is numeric: {p}");
    assert_eq!(p["no_socket_opened"], true, "parsed.no_socket_opened: {p}");
}

#[test]
fn agent_tool_errors_still_have_valid_envelopes_without_secret_leaks() {
    // missing-arg tool errors → ok:false, exit_code:null, valid envelope
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":26,"method":"tools/call","params":{"name":"check_app","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":27,"method":"tools/call","params":{"name":"serve_app_bounded","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":28,"method":"tools/call","params":{"name":"app_bundle","arguments":{}}}"#,
    ]);
    for id in [26, 27, 28] {
        let env = envelope(by_id(&r, id));
        assert_eq!(env["ok"], false, "id{id} envelope ok:false");
        assert!(
            env["exit_code"].is_null(),
            "id{id} arg-error exit_code:null (no command launched): {env}"
        );
        assert!(env["parsed"].is_null(), "id{id} parsed:null: {env}");
    }

    // an inline-secret refusal: the secret must be absent from BOTH content items (human + envelope)
    let app = writable_app_copy("env_secret", "secapp2");
    fs::write(
        app.join("host.example.toml"),
        "[host]\nmode=\"loopback\"\n[postgres.read]\ndsn = \"host=db password=TOPSECRET999\"\n",
    )
    .unwrap();
    let out = tmp("env_secret_out");
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":29,"method":"tools/call","params":{{"name":"app_bundle","arguments":{{"app_dir":"{}","out_dir":"{}","version":"V1"}}}}}}"#,
        app.display(),
        out.display()
    );
    let r = drive_agent(&[&req]);
    let resp = by_id(&r, 29);
    let (human, is_err) = tool_text(resp);
    let env = envelope(resp);
    assert!(
        is_err && env["ok"] == false,
        "inline secret refused through MCP envelope: {env}"
    );
    let env_text = serde_json::to_string(&env).unwrap();
    assert!(
        !human.contains("TOPSECRET999"),
        "secret absent from content[0]: {human}"
    );
    assert!(
        !env_text.contains("TOPSECRET999"),
        "secret absent from content[1] envelope: {env_text}"
    );
}

// ── env_doctor / env_check (P34): secret-safe env diagnostics over MCP ───────────────────────────────────

fn todo_postgres_app() -> String {
    format!("{}/examples/todo_postgres_app", env!("CARGO_MANIFEST_DIR"))
}

/// Drive `igniter agent` with extra environment (e.g. fake DSN/token) propagated to the delegated commands.
fn drive_agent_env(requests: &[&str], extra: &[(&str, &str)]) -> Vec<Value> {
    let mut cmd = Command::new(wrapper());
    cmd.arg("agent")
        .env("IGNITER_AGENT_BIN", env!("CARGO_BIN_EXE_igniter-agent"))
        .env("IGNITER_IGWEB_SERVE_BIN", env!("CARGO_BIN_EXE_igweb-serve"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    for (k, v) in extra {
        cmd.env(k, v);
    }
    let mut child = cmd.spawn().expect("spawn igniter agent");
    {
        let mut stdin = child.stdin.take().unwrap();
        for r in requests {
            writeln!(stdin, "{}", r).unwrap();
        }
    }
    let mut out = String::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut out)
        .unwrap();
    let _ = child.wait();
    out.lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str::<Value>(l).expect("each response line is JSON"))
        .collect()
}

#[test]
fn agent_env_doctor_envelope_carries_required_env_without_leak() {
    let pg = todo_postgres_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{{"name":"env_doctor","arguments":{{"path":"{}"}}}}}}"#,
        pg
    );
    // export a FAKE value: status flips to set, but the value must never appear anywhere
    let r = drive_agent_env(&[&req], &[("IGNITER_TODO_PG_DSN", "host=LEAKZZZ")]);
    let resp = by_id(&r, 30);
    let (human, _is_err) = tool_text(resp);
    let env = envelope(resp);
    assert_eq!(env["tool"], "env_doctor");
    let p = &env["parsed"];
    let req_env = p["required_env"]
        .as_array()
        .expect("parsed.required_env array");
    assert!(
        req_env.iter().any(|e| e["name"] == "IGNITER_TODO_PG_DSN"),
        "names the DSN var: {p}"
    );
    assert!(
        req_env
            .iter()
            .any(|e| e["name"] == "IGNITER_TODO_EFFECT_TOKEN"),
        "names the token var: {p}"
    );
    let env_text = serde_json::to_string(&env).unwrap();
    assert!(
        !human.contains("LEAKZZZ") && !env_text.contains("LEAKZZZ"),
        "the env VALUE must never appear:\nHUMAN:{human}\nENV:{env_text}"
    );
}

#[test]
fn agent_env_check_mirrors_cli_gate() {
    let pg = todo_postgres_app();
    let req = format!(
        r#"{{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{{"name":"env_check","arguments":{{"path":"{}"}}}}}}"#,
        pg
    );
    // unset → gate fails → isError:true, ok:false
    let r_unset = drive_agent_env(&[&req], &[]);
    let (_h, e_unset) = tool_text(by_id(&r_unset, 31));
    assert!(
        e_unset,
        "env_check with unset vars must be a tool error (isError:true)"
    );
    assert_eq!(
        envelope(by_id(&r_unset, 31))["ok"],
        false,
        "ok:false on gate fail"
    );

    // set to fake non-empty values → gate passes → isError:false
    let r_set = drive_agent_env(
        &[&req],
        &[
            ("IGNITER_TODO_PG_DSN", "x"),
            ("IGNITER_TODO_EFFECT_TOKEN", "y"),
        ],
    );
    let (_h2, e_set) = tool_text(by_id(&r_set, 31));
    assert!(
        !e_set,
        "env_check with all vars set must pass (isError:false)"
    );
    assert_eq!(
        envelope(by_id(&r_set, 31))["ok"],
        true,
        "ok:true on gate pass"
    );
}

#[test]
fn agent_env_tools_missing_path_are_clean_errors() {
    let r = drive_agent(&[
        r#"{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"env_doctor","arguments":{}}}"#,
        r#"{"jsonrpc":"2.0","id":33,"method":"tools/call","params":{"name":"env_check","arguments":{}}}"#,
    ]);
    for id in [32, 33] {
        let env = envelope(by_id(&r, id));
        assert_eq!(env["ok"], false, "id{id} missing path → ok:false");
        assert!(
            env["exit_code"].is_null(),
            "id{id} arg-error exit_code:null: {env}"
        );
        let (t, e) = tool_text(by_id(&r, id));
        assert!(
            e && t.contains("missing required argument"),
            "id{id} clean tool error: {t}"
        );
    }
}
