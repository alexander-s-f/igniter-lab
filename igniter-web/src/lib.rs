//! `igniter-web` — lab home for the IgWeb package builder (LAB-IGNITER-WEB-CRATE-P8).
//!
//! Extracted from the P5/P7 test seam. `build_igweb_app` is the IgWeb packaging contract:
//!
//! ```text
//! explicit sources (.igweb + support .ig) + entry
//!   → lower_igweb (igniter_compiler)                 → generated .ig
//!   → IgniterMachine::load_program(..., entry)       → loaded capsule
//!   → Arc<dyn igniter_server::protocol::ServerApp + Send + Sync>   (the only thing the host sees)
//! ```
//!
//! This crate carries the compiler + machine dependency weight so `igniter-server` stays serde-only by
//! default. It owns NO route table, NO effect authority (`InvokeEffect` names a logical `target` only;
//! `target → EffectBridgeConfig` is host config), and NO serving loop / sockets. Not canon; lab-only.

use igniter_compiler::igweb::lower_igweb;
use igniter_machine::machine::IgniterMachine;
use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

static NEXT_BUILD_ID: AtomicUsize = AtomicUsize::new(0);

/// Explicit package inputs (the P6 v0 shape — paths + entry, never a manifest).
pub struct IgWebBuildInput {
    /// authored sources: support `.ig` modules + one (or more) `.igweb` route files.
    pub sources: Vec<PathBuf>,
    /// the route-entry contract name (e.g. "Serve").
    pub entry: String,
}

/// Structured, developer-facing build failure (never a panic).
#[derive(Debug)]
pub enum IgWebBuildError {
    Io(String),
    /// `.igweb` lowering failure — carries the `.igweb` source line.
    Lower { line: usize, message: String },
    /// generated/support `.ig` compile/load failure.
    Load(String),
}

/// Build an IgWeb app from explicit authored paths. Lowers every `.igweb` to generated `.ig`, then
/// `IgniterMachine::load_program` over the combined module set; returns an erased `ServerApp`.
pub fn build_igweb_app(input: IgWebBuildInput) -> Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError> {
    let build_id = NEXT_BUILD_ID.fetch_add(1, Ordering::Relaxed);
    let build_dir = std::env::temp_dir().join(format!("igweb_build_{}_{}_{}", std::process::id(), input.entry, build_id));
    std::fs::create_dir_all(&build_dir).map_err(|e| IgWebBuildError::Io(e.to_string()))?;

    let mut ig_paths: Vec<String> = Vec::new();
    for (idx, src) in input.sources.iter().enumerate() {
        if src.extension().and_then(|e| e.to_str()) == Some("igweb") {
            let text = std::fs::read_to_string(src).map_err(|e| IgWebBuildError::Io(e.to_string()))?;
            let generated = lower_igweb(&text).map_err(|e| IgWebBuildError::Lower { line: e.line, message: e.message })?;
            let stem = src.file_stem().and_then(|s| s.to_str()).unwrap_or("routes");
            let gen_path = build_dir.join(format!("{idx}_{stem}.generated.ig"));
            std::fs::write(&gen_path, &generated).map_err(|e| IgWebBuildError::Io(e.to_string()))?;
            ig_paths.push(gen_path.to_string_lossy().to_string());
        } else {
            ig_paths.push(src.to_string_lossy().to_string());
        }
    }

    // P10: inject the shared IgWeb prelude (Request/Decision) so apps no longer author `web_types.ig`.
    let prelude_path = build_dir.join("igweb_prelude.ig");
    std::fs::write(&prelude_path, igniter_compiler::igweb::PRELUDE_SOURCE).map_err(|e| IgWebBuildError::Io(e.to_string()))?;
    ig_paths.push(prelude_path.to_string_lossy().to_string());

    let machine = IgniterMachine::new(None, "in_memory").map_err(|e| IgWebBuildError::Load(format!("{e:?}")))?;
    machine
        .load_program(&ig_paths, &input.entry)
        .map_err(|e| IgWebBuildError::Load(format!("{e:?}")))?;
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|e| IgWebBuildError::Io(e.to_string()))?;
    Ok(Arc::new(IgWebServerApp { machine, rt, entry: input.entry }))
}

/// The erased IgWeb app: dispatches the entry contract through the loaded machine and maps the
/// returned `Decision` variant into a `ServerDecision`. `Send + Sync` (machine + runtime are).
struct IgWebServerApp {
    machine: IgniterMachine,
    rt: tokio::runtime::Runtime,
    entry: String,
}

impl ServerApp for IgWebServerApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        let input = json!({ "req": {
            "method": req.method,
            "path": req.path,
            "body": if req.body.is_null() { Value::String(String::new()) } else { Value::String(req.body.to_string()) },
            "correlation_id": req.correlation_id.clone().unwrap_or_default(),
            "idempotency_key": req.idempotency_key.clone().unwrap_or_default(),
        }});
        match self.rt.block_on(self.machine.dispatch(&self.entry, input)) {
            Ok(decision) => map_decision(&decision, req.correlation_id),
            Err(e) => ServerDecision::Respond { response: ServerResponse::json(500, json!({ "error": format!("{e:?}") })) },
        }
    }
}

/// The VM encodes a variant value as an internally-tagged object:
/// `{ "__arm": "Respond", "__variant": "Decision", <fields...> }`.
fn variant_of(v: &Value) -> Option<(String, Value)> {
    let obj = v.as_object()?;
    for key in ["__arm", "kind", "variant", "tag"] {
        if let Some(t) = obj.get(key).and_then(|x| x.as_str()) {
            return Some((t.to_string(), v.clone()));
        }
    }
    if obj.len() == 1 {
        let (k, inner) = obj.iter().next().unwrap();
        return Some((k.clone(), inner.clone()));
    }
    None
}

fn map_decision(decision: &Value, correlation_id: Option<String>) -> ServerDecision {
    let (tag, fields) = match variant_of(decision) {
        Some(t) => t,
        None => return ServerDecision::Respond { response: ServerResponse::json(500, json!({ "error": "unmapped decision", "raw": decision })) },
    };
    let get_str = |k: &str| fields.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    let get_i = |k: &str| fields.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
    match tag.as_str() {
        "Respond" => ServerDecision::Respond { response: ServerResponse::json(get_i("status") as u16, json!({ "body": get_str("body") })) },
        "InvokeEffect" => ServerDecision::InvokeEffect {
            target: get_str("target"),
            input: json!({ "input": get_str("input") }),
            correlation_id,
            idempotency_key: { let k = get_str("idempotency_key"); if k.is_empty() { None } else { Some(k) } },
        },
        other => ServerDecision::Respond { response: ServerResponse::json(500, json!({ "error": format!("unknown decision tag: {other}"), "raw": decision })) },
    }
}

/// Test fixtures + loopback helpers shared by `igniter-web` and `igniter-server` proofs. Lab/test only.
pub mod testkit {
    use super::*;
    use igniter_server::host;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::thread;

    pub const HANDLERS: &str = "\
module TodoHandlers
import IgWebPrelude
pure contract Health {
  input req : Request
  compute d : Decision = Respond { status: 200, body: \"ok\" }
  output d : Decision
}
pure contract TodoIndex {
  input req : Request
  compute d : Decision = Respond { status: 200, body: \"[]\" }
  output d : Decision
}
pure contract TodoCreate {
  input req : Request
  compute d : Decision = InvokeEffect { target: \"todo-create\", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}
pure contract TodoShow {
  input req : Request
  input id : Option[String]
  compute d : Decision = Respond { status: 200, body: or_else(id, \"none\") }
  output d : Decision
}
pure contract TodoDone {
  input req : Request
  input id : Option[String]
  compute d : Decision = InvokeEffect { target: \"todo-done\", input: or_else(id, \"none\"), idempotency_key: req.idempotency_key }
  output d : Decision
}
";

    pub const IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers TodoHandlers
  route GET  \"/health\"          -> Health
  route GET  \"/todos\"           -> TodoIndex
  route POST \"/todos\"           -> TodoCreate requires idempotency
  route GET  \"/todos/:id\"       -> TodoShow
  route POST \"/todos/:id/done\"  -> TodoDone requires idempotency
}
";

    /// Write the canonical Todo fixture sources into a fresh dir; return their paths. P10: no
    /// `web_types.ig` — the builder injects the shared `IgWebPrelude`.
    pub fn write_todo_fixtures(tag: &str) -> Vec<PathBuf> {
        let dir = std::env::temp_dir().join(format!("igweb_fix_{}_{}", std::process::id(), tag));
        std::fs::create_dir_all(&dir).unwrap();
        let hd = dir.join("handlers.ig");
        let rt = dir.join("routes.igweb");
        std::fs::write(&hd, HANDLERS).unwrap();
        std::fs::write(&rt, IGWEB).unwrap();
        vec![hd, rt]
    }

    /// Build the canonical Todo app via the builder (no hand-assembly).
    pub fn build_todo_app(tag: &str) -> Arc<dyn ServerApp + Send + Sync> {
        build_igweb_app(IgWebBuildInput { sources: write_todo_fixtures(tag), entry: "Serve".into() }).expect("build todo app")
    }

    /// One raw loopback HTTP request through `host::serve_once(&listener, app)` → (status, body json).
    pub fn roundtrip(app: &dyn ServerApp, method: &str, path: &str, headers: &[(&str, &str)], body: &str) -> (u16, Value) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let addr = listener.local_addr().unwrap().to_string();
        let (m, p, b) = (method.to_string(), path.to_string(), body.to_string());
        let hs: Vec<(String, String)> = headers.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        let client = thread::spawn(move || {
            let mut s = TcpStream::connect(&addr).unwrap();
            let mut req = format!("{m} {p} HTTP/1.1\r\nHost: x\r\n");
            for (k, v) in &hs {
                req.push_str(&format!("{k}: {v}\r\n"));
            }
            req.push_str(&format!("Content-Length: {}\r\n\r\n{}", b.len(), b));
            s.write_all(req.as_bytes()).unwrap();
            s.flush().unwrap();
            let mut raw = Vec::new();
            s.read_to_end(&mut raw).unwrap();
            let text = String::from_utf8_lossy(&raw).to_string();
            let status: u16 = text.split_whitespace().nth(1).and_then(|x| x.parse().ok()).unwrap_or(0);
            let bs = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
            let bj: Value = serde_json::from_str(text[bs..].trim()).unwrap_or(Value::Null);
            (status, bj)
        });
        host::serve_once(&listener, app).unwrap();
        client.join().unwrap()
    }

    /// Minimal loopback GET → status (for reload proofs).
    pub fn http_get(addr: &str, path: &str) -> u16 {
        let mut s = TcpStream::connect(addr).unwrap();
        s.write_all(format!("GET {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n").as_bytes()).unwrap();
        s.flush().unwrap();
        let mut raw = Vec::new();
        s.read_to_end(&mut raw).unwrap();
        String::from_utf8_lossy(&raw).split_whitespace().nth(1).and_then(|x| x.parse().ok()).unwrap_or(0)
    }
}
