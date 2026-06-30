// igniter-agent — LAB-DISTRIBUTION-AGENT-CHECK-DOCTOR-MCP-P24
//
// The command-center MCP surface (P23 shape B+C): a minimal stdio JSON-RPC server whose tools SHELL-DELEGATE
// to `bin/igniter`. It adds NO authority of its own — every tool runs the same control-center verb a human
// uses, so the loopback/bounded/secret-free/fail-closed guarantees all live in `bin/igniter` and its owners.
// This is a DISTINCT surface from `igniter-mcp` (the language/machine MCP), which is left untouched.
//
// v0 tools (read-only / non-mutating): doctor, toolchain_list, check_app, package_verify.
// No deploy, no public bind, no systemd, no secrets, no process supervisor.
//
// Launched by `igniter agent`, which passes IGNITER_BIN=<abs path to bin/igniter> in the environment.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::process::{Command, Stdio};
use std::time::Duration;

use serde_json::{json, Value};

/// Path to the control-center front door. The `igniter agent` launcher sets IGNITER_BIN to its own absolute
/// path; tests set it to the repo `bin/igniter`. Falls back to `igniter` on PATH.
fn igniter_bin() -> String {
    std::env::var("IGNITER_BIN").unwrap_or_else(|_| "igniter".to_string())
}

/// Run `igniter <args...>` and capture (exit_code, stdout, stderr). Never panics on launch failure.
fn run_igniter(args: &[&str]) -> (i32, String, String) {
    match Command::new(igniter_bin()).args(args).output() {
        Ok(o) => (
            o.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&o.stdout).to_string(),
            String::from_utf8_lossy(&o.stderr).to_string(),
        ),
        Err(e) => (-1, String::new(), format!("failed to launch igniter: {e}")),
    }
}

/// Machine-readable text body for a delegated command (the P24-specified shape).
fn tool_body(exit_code: i32, stdout: &str, stderr: &str) -> String {
    format!("exit_code: {exit_code}\nstdout:\n{stdout}\nstderr:\n{stderr}")
}

fn tools_list() -> Value {
    json!([
        {
            "name": "doctor",
            "description": "Local, non-mutating environment + fleet report (delegates to `igniter doctor`). Opens no socket; builds nothing.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "app_dir": { "type": "string", "description": "Optional app dir for app-shape checks" },
                    "json": { "type": "boolean", "description": "Return the structured --json report" }
                }
            }
        },
        {
            "name": "toolchain_list",
            "description": "List the v0 binary fleet and whether each is built (delegates to `igniter toolchain list`). Non-mutating.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "check_app",
            "description": "Dry build/verify an IgWeb app (delegates to `igniter check <app_dir>`). Opens NO socket; no public bind.",
            "inputSchema": {
                "type": "object",
                "properties": { "app_dir": { "type": "string", "description": "Path to the IgWeb app directory" } },
                "required": ["app_dir"]
            }
        },
        {
            "name": "package_verify",
            "description": "Verify a package workspace (delegates to `igniter package verify` → `igc verify`). Argv routing only; no new verifier.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "workspace": { "type": "string", "description": "Optional project-root path" },
                    "strict": { "type": "boolean", "description": "Pass --strict" }
                }
            }
        },
        {
            "name": "app_bundle",
            "description": "Assemble a versioned, host-runnable app bundle (delegates to `igniter app bundle <app_dir> --out <dir> --version <stamp>`). ASSEMBLY ONLY — the bundler owns all safety (refuses real host.toml / inline secrets, runs `igweb-serve check`, stages atomically, emits loopback runner + example systemd). No deploy/public-bind/systemd-install/secrets here.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "app_dir": { "type": "string", "description": "Path to the IgWeb app directory" },
                    "out_dir": { "type": "string", "description": "Parent dir to write <app>-<version>/ into" },
                    "version": { "type": "string", "description": "Caller-supplied provenance stamp (no clock in the tool)" }
                },
                "required": ["app_dir", "out_dir", "version"]
            }
        },
        {
            "name": "serve_app_bounded",
            "description": "Start an IgWeb app via `igniter serve` on LOOPBACK 127.0.0.1:0, bounded to max_requests (v0 max 5), issue ONE GET, and wait for the bounded run to exit. NOT a daemon: no public bind, no background handle, no restart. Returns listen address, HTTP status, and child exit.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "app_dir": { "type": "string", "description": "Path to the IgWeb app directory" },
                    "max_requests": { "type": "integer", "description": "Bounded request count (1–5; clamped). Default 1." },
                    "path": { "type": "string", "description": "Request path (default /health)" }
                },
                "required": ["app_dir"]
            }
        },
        {
            "name": "env_doctor",
            "description": "Report the machine-mode env-var NAMES an app/bundle needs + their set/unset/empty status (delegates to `igniter env doctor`). Reads the commit-safe host.example.toml / host.toml.example catalogue. Report-only. NEVER reads or prints env values.",
            "inputSchema": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "App dir or produced bundle dir" } },
                "required": ["path"]
            }
        },
        {
            "name": "env_check",
            "description": "GATE: non-zero (isError) if any required env var is unset/empty or the catalogue is invalid (delegates to `igniter env check`). NEVER reads or prints env values.",
            "inputSchema": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "App dir or produced bundle dir" } },
                "required": ["path"]
            }
        },
        {
            "name": "stdlib_list",
            "description": "List the implemented stdlib surface (delegates to `igniter stdlib list --json`). Read-only; `igc` owns the stdlib JSON contract.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "category": { "type": "string", "description": "Optional exact category filter, passed to --category" }
                }
            }
        },
        {
            "name": "stdlib_search",
            "description": "Search the implemented stdlib surface (delegates to `igniter stdlib search QUERY --json`). Read-only; no inventory parsing in the agent.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": { "type": "string", "description": "Required non-empty search query" }
                },
                "required": ["query"]
            }
        },
        {
            "name": "stdlib_show",
            "description": "Show one stdlib entry by canonical name, semantic IR name, or source alias (delegates to `igniter stdlib show NAME --json`).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "name": { "type": "string", "description": "Required stdlib canonical name, semantic IR name, or source alias" }
                },
                "required": ["name"]
            }
        },
        {
            "name": "diagnostic_explain",
            "description": "Explain which stdlib entries are linked to a diagnostic rule (delegates to `igniter explain RULE --json`).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "rule": { "type": "string", "description": "Required diagnostic rule id, for example OOF-COL3" }
                },
                "required": ["rule"]
            }
        }
    ])
}

/// Bound a short, single-line snippet of command output (char-safe truncation).
fn snippet(s: &str) -> String {
    let s = s.trim();
    if s.chars().count() > 1500 {
        format!("{}…(truncated)", s.chars().take(1500).collect::<String>())
    } else {
        s.to_string()
    }
}

/// One raw HTTP/1.1 GET on a loopback socket; returns the status line (e.g. "HTTP/1.1 200 OK").
fn http_get_status(addr: &str, path: &str) -> String {
    match TcpStream::connect(addr) {
        Ok(mut stream) => {
            let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
            let req = format!("GET {path} HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n");
            if stream.write_all(req.as_bytes()).is_err() {
                return "(request write failed)".to_string();
            }
            let mut resp = String::new();
            let _ = stream.read_to_string(&mut resp); // server is bounded → closes socket → returns
            resp.lines().next().unwrap_or("").to_string()
        }
        Err(e) => format!("(connect failed: {e})"),
    }
}

/// Structured outcome of a bounded serve, used to build both the human text and the JSON envelope (P28).
struct ServeOut {
    human: String,
    is_error: bool,
    exit_code: i64,
    stdout: String,
    stderr: String,
    parsed: Value,
}

/// Run `igniter serve <app> --addr 127.0.0.1:0 --max-requests <max>` as a CHILD, parse the listening line,
/// issue ONE GET <path>, then wait for the bounded child to exit. Loopback is forced (no addr/public param);
/// `max` is already clamped to [1,5]. Never daemonizes; no background handle is retained.
fn serve_app_bounded(app_dir: &str, max: i64, requested: i64, path: &str) -> ServeOut {
    let max_s = max.to_string();
    let mut child = match Command::new(igniter_bin())
        .args([
            "serve",
            app_dir,
            "--addr",
            "127.0.0.1:0",
            "--max-requests",
            &max_s,
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            return ServeOut {
                human: format!("failed to launch igniter serve: {e}"),
                is_error: true,
                exit_code: -1,
                stdout: String::new(),
                stderr: e.to_string(),
                parsed: Value::Null,
            }
        }
    };

    let mut reader = BufReader::new(child.stdout.take().unwrap());
    let mut captured = String::new();
    let mut addr = String::new();
    loop {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => break, // EOF — child exited before/without binding
            Ok(_) => {
                captured.push_str(&line);
                if let Some(rest) = line.split("listening http://").nth(1) {
                    addr = rest.split_whitespace().next().unwrap_or("").to_string();
                    break;
                }
            }
            Err(_) => break,
        }
    }

    // Hold the stderr handle but DON'T read it yet: reading to EOF blocks until the child exits, and in the
    // bound path the child won't exit until we issue the requests below (reading stderr first = deadlock).
    let mut stderr_handle = child.stderr.take();
    let mut stderr_buf = String::new();

    if addr.is_empty() {
        // never bound → the child has already exited (EOF on stdout); reading stderr now is safe.
        if let Some(mut e) = stderr_handle.take() {
            let _ = e.read_to_string(&mut stderr_buf);
        }
        let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(-1);
        return ServeOut {
            human: format!(
                "exit_code: {code}\nlisten: (never bound)\npath: {path}\nhttp_status: (not attempted)\nstdout:\n{}\nstderr:\n{}",
                snippet(&captured),
                snippet(&stderr_buf)
            ),
            is_error: true,
            exit_code: code as i64,
            stdout: captured,
            stderr: stderr_buf,
            parsed: Value::Null,
        };
    }

    // Issue EXACTLY `max` GETs so a server bounded to `max` requests serves them all and exits cleanly. We
    // never send fewer than `max` (an early bail would leave the bounded server waiting → a hang); a failed
    // connect after the server has exited returns immediately, so looping the full count is safe.
    let mut first_status = String::new();
    let mut all_200 = true;
    for i in 0..max {
        let s = http_get_status(&addr, path);
        if i == 0 {
            first_status = s.clone();
        }
        if !s.contains(" 200") {
            all_200 = false;
        }
    }

    // requests issued → the bounded child is exiting; now drain remaining stdout + stderr, then reap (no
    // kill, no daemon, no background handle).
    let mut rest_out = String::new();
    let _ = reader.read_to_string(&mut rest_out);
    captured.push_str(&rest_out);
    if let Some(mut e) = stderr_handle.take() {
        let _ = e.read_to_string(&mut stderr_buf);
    }
    let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(-1);

    let clamp_note = if requested != max {
        format!("  (max_requests clamped {requested}→{max})")
    } else {
        String::new()
    };
    let is_error = code != 0 || !all_200;
    let parsed = json!({
        "listen": addr,
        "path": path,
        "requests_issued": max,
        "http_status": first_status,
        "all_200": all_200,
        "exit_code": code,
    });
    ServeOut {
        human: format!(
            "exit_code: {code}\nlisten: {addr}{clamp_note}\npath: {path}\nrequests_issued: {max}\nhttp_status: {first_status}\nall_200: {all_200}\nstdout:\n{}\nstderr:\n{}",
            snippet(&captured),
            snippet(&stderr_buf)
        ),
        is_error,
        exit_code: code as i64,
        stdout: captured,
        stderr: stderr_buf,
        parsed,
    }
}

fn respond(out: &mut impl Write, id: Value, result: Value) {
    let msg = json!({ "jsonrpc": "2.0", "id": id, "result": result });
    let _ = writeln!(out, "{}", msg);
    let _ = out.flush();
}

fn respond_error(out: &mut impl Write, id: Value, code: i64, message: &str) {
    let msg = json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } });
    let _ = writeln!(out, "{}", msg);
    let _ = out.flush();
}

/// P28: a tool result with an ADDITIVE JSON envelope. `content[0]` is the existing human text (kept
/// byte-compatible for older assertions); `content[1]` is a bounded JSON envelope. `exit_code` is `None`
/// only for argument-validation errors that never launched a command. `parsed` is tool-specific (or null).
#[allow(clippy::too_many_arguments)]
fn tool_enveloped(
    out: &mut impl Write,
    id: Value,
    tool: &str,
    human_text: String,
    is_error: bool,
    exit_code: Option<i64>,
    stdout: &str,
    stderr: &str,
    parsed: Value,
) {
    let envelope = json!({
        "tool": tool,
        "ok": !is_error,
        "exit_code": exit_code,
        "stdout": snippet(stdout),
        "stderr": snippet(stderr),
        "parsed": parsed,
    });
    let envelope_text = serde_json::to_string(&envelope).unwrap_or_else(|_| "{}".to_string());
    respond(
        out,
        id,
        json!({
            "content": [
                { "type": "text", "text": human_text },
                { "type": "text", "text": envelope_text }
            ],
            "isError": is_error
        }),
    );
}

/// Convenience for a command-backed tool: builds the human `tool_body` and the envelope from one (code, out,
/// err) result. `is_error` is explicit (some tools fail on more than a non-zero code, e.g. serve on !all_200).
fn tool_command_result(
    out: &mut impl Write,
    id: Value,
    tool: &str,
    code: i32,
    stdout: &str,
    stderr: &str,
    is_error: bool,
    parsed: Value,
) {
    tool_enveloped(
        out,
        id,
        tool,
        tool_body(code, stdout, stderr),
        is_error,
        Some(code as i64),
        stdout,
        stderr,
        parsed,
    );
}

/// Argument-validation error: no command launched → `exit_code:null`, `parsed:null`, `isError:true`.
fn tool_arg_error(out: &mut impl Write, id: Value, tool: &str, message: &str) {
    tool_enveloped(
        out,
        id,
        tool,
        message.to_string(),
        true,
        None,
        "",
        "",
        Value::Null,
    );
}

fn required_nonblank_arg<'a>(args: &'a Value, key: &str) -> Option<&'a str> {
    args.get(key)
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
}

/// Run a JSON-producing control-center command and place parsed stdout into the additive MCP envelope.
/// The delegated CLI owns semantics and exit status; parse failure only leaves `parsed:null`.
fn run_json_igniter_tool(out: &mut impl Write, id: Value, tool: &str, argv: &[&str]) {
    let (code, so, se) = run_igniter(argv);
    let parsed = serde_json::from_str::<Value>(&so).unwrap_or(Value::Null);
    tool_command_result(out, id, tool, code, &so, &se, code != 0, parsed);
}

/// Extract the whitespace-delimited token following `key` in a line (e.g. `entry=Serve` → `Serve`).
fn field_after(line: &str, key: &str) -> Option<String> {
    line.split(key)
        .nth(1)
        .and_then(|r| r.split_whitespace().next())
        .map(|s| s.to_string())
}

/// Parse the `igweb-serve: check ok app_dir=… entry=Serve sources=N (no socket opened)` line. Null if absent.
fn parse_check_ok(stdout: &str) -> Value {
    for line in stdout.lines() {
        if line.contains("check ok") {
            let entry = field_after(line, "entry=");
            let sources = field_after(line, "sources=").and_then(|s| s.parse::<i64>().ok());
            return json!({
                "ok": true,
                "entry": entry,
                "sources": sources,
                "no_socket_opened": line.contains("no socket opened"),
            });
        }
    }
    Value::Null
}

/// Parse the `…: app bundle ok → <dest>` line, then read+parse `<dest>/manifest.json`. Null if absent.
fn parse_bundle(stdout: &str) -> Value {
    for line in stdout.lines() {
        if let Some(rest) = line.split("app bundle ok → ").nth(1) {
            let dest = rest.trim().to_string();
            let manifest = std::fs::read_to_string(format!("{dest}/manifest.json"))
                .ok()
                .and_then(|s| serde_json::from_str::<Value>(&s).ok())
                .unwrap_or(Value::Null);
            return json!({ "bundle_path": dest, "manifest": manifest });
        }
    }
    Value::Null
}

/// Parse `igniter env doctor|check` output (`  [status] NAME  (ctx)` lines) into a structured catalogue.
/// Names + statuses only — values are never present in the CLI output, so none can leak here.
fn parse_env_report(stdout: &str, path: &str, ok: bool) -> Value {
    let mut required = Vec::new();
    for line in stdout.lines() {
        let t = line.trim_start();
        if let Some(rest) = t.strip_prefix('[') {
            if let Some(close) = rest.find(']') {
                let status = rest[..close].trim().to_string();
                if matches!(status.as_str(), "set" | "unset" | "empty") {
                    let name = rest[close + 1..]
                        .split_whitespace()
                        .next()
                        .unwrap_or("")
                        .to_string();
                    if !name.is_empty() {
                        required.push(json!({ "name": name, "status": status }));
                    }
                }
            }
        }
    }
    json!({ "path": path, "required_env": required, "ok": ok })
}

fn handle_tool_call(out: &mut impl Write, id: Value, params: &Value) {
    let name = params.get("name").and_then(|v| v.as_str()).unwrap_or("");
    let args = params
        .get("arguments")
        .cloned()
        .unwrap_or_else(|| json!({}));

    match name {
        "doctor" => {
            // content[0] keeps the caller-requested shape (`json:true` still returns doctor --json as before);
            // envelope `parsed` is always filled from `igniter doctor [app_dir] --json` (P28). Doctor redaction
            // is inherited — no secret/env values are printed.
            let app = args.get("app_dir").and_then(|v| v.as_str());
            let wants_json = args.get("json").and_then(|v| v.as_bool()).unwrap_or(false);
            let mut human_argv = vec!["doctor"];
            if let Some(a) = app {
                human_argv.push(a);
            }
            if wants_json {
                human_argv.push("--json");
            }
            let (code, so, se) = run_igniter(&human_argv);

            let mut json_argv = vec!["doctor"];
            if let Some(a) = app {
                json_argv.push(a);
            }
            json_argv.push("--json");
            let parsed = if wants_json {
                serde_json::from_str::<Value>(&so).unwrap_or(Value::Null)
            } else {
                let (_jc, jso, _jse) = run_igniter(&json_argv);
                serde_json::from_str::<Value>(&jso).unwrap_or(Value::Null)
            };

            tool_command_result(out, id, "doctor", code, &so, &se, code != 0, parsed);
        }
        "toolchain_list" => {
            let (code, so, se) = run_igniter(&["toolchain", "list"]);
            tool_command_result(
                out,
                id,
                "toolchain_list",
                code,
                &so,
                &se,
                code != 0,
                Value::Null,
            );
        }
        "check_app" => match args.get("app_dir").and_then(|v| v.as_str()) {
            Some(app) => {
                let (code, so, se) = run_igniter(&["check", app]);
                let parsed = if code == 0 {
                    parse_check_ok(&so)
                } else {
                    Value::Null
                };
                tool_command_result(out, id, "check_app", code, &so, &se, code != 0, parsed);
            }
            None => tool_arg_error(out, id, "check_app", "missing required argument: app_dir"),
        },
        "package_verify" => {
            let mut argv: Vec<String> = vec!["package".to_string(), "verify".to_string()];
            if let Some(ws) = args.get("workspace").and_then(|v| v.as_str()) {
                argv.push("--project-root".to_string());
                argv.push(ws.to_string());
            }
            if args
                .get("strict")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                argv.push("--strict".to_string());
            }
            let refs: Vec<&str> = argv.iter().map(|s| s.as_str()).collect();
            let (code, so, se) = run_igniter(&refs);
            tool_command_result(
                out,
                id,
                "package_verify",
                code,
                &so,
                &se,
                code != 0,
                Value::Null,
            );
        }
        "app_bundle" => {
            // shell-delegate to `igniter app bundle` — the bundler owns ALL safety (host.toml/secret refusal,
            // `igweb-serve check`, atomic staging). IGNITER_IGWEB_SERVE_BIN is inherited from our env.
            let app_dir = args.get("app_dir").and_then(|v| v.as_str());
            let out_dir = args.get("out_dir").and_then(|v| v.as_str());
            let version = args.get("version").and_then(|v| v.as_str());
            match (app_dir, out_dir, version) {
                (Some(a), Some(o), Some(v)) => {
                    let (code, so, se) =
                        run_igniter(&["app", "bundle", a, "--out", o, "--version", v]);
                    let parsed = if code == 0 {
                        parse_bundle(&so)
                    } else {
                        Value::Null
                    };
                    tool_command_result(out, id, "app_bundle", code, &so, &se, code != 0, parsed);
                }
                _ => tool_arg_error(
                    out,
                    id,
                    "app_bundle",
                    "missing required argument(s): app_dir, out_dir, version",
                ),
            }
        }
        "serve_app_bounded" => match args.get("app_dir").and_then(|v| v.as_str()) {
            Some(app) => {
                // bounded run: loopback forced (no addr/public param exists); clamp max_requests to [1,5].
                let requested = args
                    .get("max_requests")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(1);
                let max = requested.clamp(1, 5);
                let path = args
                    .get("path")
                    .and_then(|v| v.as_str())
                    .unwrap_or("/health");
                let s = serve_app_bounded(app, max, requested, path);
                tool_enveloped(
                    out,
                    id,
                    "serve_app_bounded",
                    s.human,
                    s.is_error,
                    Some(s.exit_code),
                    &s.stdout,
                    &s.stderr,
                    s.parsed,
                );
            }
            None => tool_arg_error(
                out,
                id,
                "serve_app_bounded",
                "missing required argument: app_dir",
            ),
        },
        "env_doctor" => match args.get("path").and_then(|v| v.as_str()) {
            Some(p) => {
                let (code, so, se) = run_igniter(&["env", "doctor", p]);
                let parsed = parse_env_report(&so, p, code == 0);
                tool_command_result(out, id, "env_doctor", code, &so, &se, code != 0, parsed);
            }
            None => tool_arg_error(out, id, "env_doctor", "missing required argument: path"),
        },
        "env_check" => match args.get("path").and_then(|v| v.as_str()) {
            Some(p) => {
                // env check is a GATE: non-zero exit → isError:true mirrors the CLI.
                let (code, so, se) = run_igniter(&["env", "check", p]);
                let parsed = parse_env_report(&so, p, code == 0);
                tool_command_result(out, id, "env_check", code, &so, &se, code != 0, parsed);
            }
            None => tool_arg_error(out, id, "env_check", "missing required argument: path"),
        },
        "stdlib_list" => {
            if let Some(category) = required_nonblank_arg(&args, "category") {
                run_json_igniter_tool(
                    out,
                    id,
                    "stdlib_list",
                    &["stdlib", "list", "--category", category, "--json"],
                );
            } else {
                run_json_igniter_tool(out, id, "stdlib_list", &["stdlib", "list", "--json"]);
            }
        }
        "stdlib_search" => match required_nonblank_arg(&args, "query") {
            Some(query) => run_json_igniter_tool(
                out,
                id,
                "stdlib_search",
                &["stdlib", "search", query, "--json"],
            ),
            None => tool_arg_error(out, id, "stdlib_search", "missing required argument: query"),
        },
        "stdlib_show" => match required_nonblank_arg(&args, "name") {
            Some(name) => {
                run_json_igniter_tool(out, id, "stdlib_show", &["stdlib", "show", name, "--json"])
            }
            None => tool_arg_error(out, id, "stdlib_show", "missing required argument: name"),
        },
        "diagnostic_explain" => match required_nonblank_arg(&args, "rule") {
            Some(rule) => {
                run_json_igniter_tool(out, id, "diagnostic_explain", &["explain", rule, "--json"])
            }
            None => tool_arg_error(
                out,
                id,
                "diagnostic_explain",
                "missing required argument: rule",
            ),
        },
        other => tool_enveloped(
            out,
            id,
            "unknown",
            format!("unknown tool: {other}"),
            true,
            None,
            "",
            "",
            Value::Null,
        ),
    }
}

fn main() {
    let mut stdout = std::io::stdout();
    let stdin = std::io::stdin();
    let reader = BufReader::new(stdin.lock());

    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        if line.trim().is_empty() {
            continue;
        }
        let request: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(_) => continue, // ignore non-JSON lines
        };
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        let method = request.get("method").and_then(|v| v.as_str()).unwrap_or("");

        match method {
            "initialize" => respond(
                &mut stdout,
                id,
                json!({
                    "protocolVersion": "2024-11-05",
                    "serverInfo": { "name": "igniter-agent", "version": "0.1.0" },
                    "capabilities": { "tools": {} }
                }),
            ),
            "notifications/initialized" => { /* no response */ }
            "ping" => respond(&mut stdout, id, json!({})),
            "tools/list" => respond(&mut stdout, id, json!({ "tools": tools_list() })),
            "tools/call" => {
                let params = request.get("params").cloned().unwrap_or_else(|| json!({}));
                handle_tool_call(&mut stdout, id, &params);
            }
            "" => { /* malformed: ignore */ }
            other => respond_error(
                &mut stdout,
                id,
                -32601,
                &format!("method not found: {other}"),
            ),
        }
    }
}
