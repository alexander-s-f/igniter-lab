// tests/igweb_adapter_tests.rs — LAB-IGNITER-WEB-ROUTING-ADAPTER-P5
// Prove `.igweb` live behind igniter-server: lower (P4) → compile/load/dispatch the generated `.ig`
// through IgniterMachine → map Decision → ServerDecision, served over real loopback HTTP via
// host::serve_once. The server owns NO route table; routing lives in the generated Serve capsule.
#![cfg(feature = "machine")]

use igniter_compiler::igweb::lower_igweb;
use igniter_machine::machine::IgniterMachine;
use igniter_server::host;
use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

static NEXT_BUILD_ID: AtomicUsize = AtomicUsize::new(0);

const WEB_TYPES: &str = "\
module WebTypes
type Request {
  method          : String
  path            : String
  body            : String
  correlation_id  : String
  idempotency_key : String
}
variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : String, idempotency_key : String }
}
";

const HANDLERS: &str = "\
module TodoHandlers
import WebTypes
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

const IGWEB: &str = "\
app TodoWeb entry Serve {
  route GET  \"/health\"          -> Health
  route GET  \"/todos\"           -> TodoIndex
  route POST \"/todos\"           -> TodoCreate requires idempotency
  route GET  \"/todos/:id\"       -> TodoShow
  route POST \"/todos/:id/done\"  -> TodoDone requires idempotency
}
";

/// The IgWeb adapter: holds a machine with the loaded generated app + a runtime for the async
/// dispatch. `call` serializes the ServerRequest into the Serve `Request` input, dispatches the
/// generated `Serve` contract, and maps the returned `Decision` variant into a `ServerDecision`.
struct IgWebServerApp {
    machine: IgniterMachine,
    rt: tokio::runtime::Runtime,
}

impl IgWebServerApp {
    fn build() -> Self {
        let routes_ig = lower_igweb(IGWEB).expect("lower .igweb");
        let build_id = NEXT_BUILD_ID.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("igweb_adapter_{}_{}", std::process::id(), build_id));
        std::fs::create_dir_all(&dir).unwrap();
        let wt = dir.join("web_types.ig");
        let hd = dir.join("handlers.ig");
        let rt = dir.join("routes.ig");
        std::fs::write(&wt, WEB_TYPES).unwrap();
        std::fs::write(&hd, HANDLERS).unwrap();
        std::fs::write(&rt, &routes_ig).unwrap();
        let machine = IgniterMachine::new(None, "in_memory").expect("machine");
        machine
            .load_program(
                &[
                    wt.to_string_lossy().to_string(),
                    hd.to_string_lossy().to_string(),
                    rt.to_string_lossy().to_string(),
                ],
                "Serve",
            )
            .expect("load_program (generated AppRoutes + handlers + types)");
        let rt_async = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        IgWebServerApp { machine, rt: rt_async }
    }
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
        match self.rt.block_on(self.machine.dispatch("Serve", input)) {
            Ok(decision) => map_decision(&decision, req.correlation_id),
            Err(e) => ServerDecision::Respond { response: ServerResponse::json(500, json!({ "error": format!("{:?}", e) })) },
        }
    }
}

/// Extract a variant `(arm, fields)` from the dispatch output. The VM encodes a variant value as an
/// internally-tagged object: `{ "__arm": "Respond", "__variant": "Decision", <fields...> }`.
fn variant_of(v: &Value) -> Option<(String, Value)> {
    let obj = v.as_object()?;
    // `__arm` is the constructor name (the arm); fields are flat on the same object.
    for key in ["__arm", "kind", "variant", "tag"] {
        if let Some(t) = obj.get(key).and_then(|x| x.as_str()) {
            return Some((t.to_string(), v.clone()));
        }
    }
    // fallback: externally tagged `{ "Respond": { ...fields } }`.
    if obj.len() == 1 {
        let (k, inner) = obj.iter().next().unwrap();
        return Some((k.clone(), inner.clone()));
    }
    None
}

fn map_decision(decision: &Value, correlation_id: Option<String>) -> ServerDecision {
    // first-run aid: surface the raw shape if it doesn't map.
    let (tag, fields) = match variant_of(decision) {
        Some(t) => t,
        None => {
            return ServerDecision::Respond {
                response: ServerResponse::json(500, json!({ "error": "unmapped decision", "raw": decision })),
            }
        }
    };
    let get_str = |k: &str| fields.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    let get_i = |k: &str| fields.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
    match tag.as_str() {
        "Respond" => ServerDecision::Respond {
            response: ServerResponse::json(get_i("status") as u16, json!({ "body": get_str("body") })),
        },
        "InvokeEffect" => ServerDecision::InvokeEffect {
            target: get_str("target"),
            input: json!({ "input": get_str("input") }),
            correlation_id,
            idempotency_key: {
                let k = get_str("idempotency_key");
                if k.is_empty() { None } else { Some(k) }
            },
        },
        other => ServerDecision::Respond {
            response: ServerResponse::json(500, json!({ "error": format!("unknown decision tag: {}", other), "raw": decision })),
        },
    }
}

/// One raw loopback HTTP request → (status, body json). Runs the client on a thread; the server
/// (host::serve_once) runs on the calling thread so the app need not be Send.
fn roundtrip(app: &dyn ServerApp, method: &str, path: &str, headers: &[(&str, &str)], body: &str) -> (u16, Value) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let m = method.to_string();
    let p = path.to_string();
    let hs: Vec<(String, String)> = headers.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    let b = body.to_string();
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
        let body_json: Value = serde_json::from_str(text[bs..].trim()).unwrap_or(Value::Null);
        (status, body_json)
    });
    host::serve_once(&listener, app).unwrap();
    client.join().unwrap()
}

#[test]
fn igweb_app_health_roundtrip() {
    let app = IgWebServerApp::build();
    let (status, body) = roundtrip(&app, "GET", "/health", &[], "");
    assert_eq!(status, 200, "GET /health → 200 through the server host. body={body}");
}

#[test]
fn igweb_app_route_param_roundtrip() {
    let app = IgWebServerApp::build();
    let (status, body) = roundtrip(&app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["body"], json!("42"), "captured id=42 flowed through the generated regexp");
}

#[test]
fn igweb_app_mutation_requires_idempotency_key() {
    let app = IgWebServerApp::build();
    let (status, _body) = roundtrip(&app, "POST", "/todos/42/done", &[], "");
    assert_eq!(status, 400, "keyless mutating route → 400 before any effect");
}

#[test]
fn igweb_app_mutation_emits_invoke_effect() {
    let app = IgWebServerApp::build();
    // with an idempotency key, the keyed mutating route produces an InvokeEffect (observed 202 via host::execute).
    let (status, body) = roundtrip(&app, "POST", "/todos/42/done", &[("idempotency-key", "k-9")], "{}");
    assert_eq!(status, 202, "InvokeEffect observed as 202 deferred (P2 host::execute)");
    assert_eq!(body["decision"], json!("invoke_effect"));
    assert_eq!(body["target"], json!("todo-done"));
    assert_eq!(body["idempotency_key"], json!("k-9"));
    // no effect identity leaks through the app decision.
    assert!(body.get("capability_id").is_none());
    assert!(body.get("scope").is_none());
}

#[test]
fn igweb_app_unknown_and_method_refusals() {
    let app = IgWebServerApp::build();
    assert_eq!(roundtrip(&app, "GET", "/missing", &[], "").0, 404, "unknown path → 404");
    assert_eq!(roundtrip(&app, "POST", "/health", &[], "").0, 405, "wrong method → 405");
}

/// The host has no route table: a totally different app on the same host routes differently.
#[test]
fn server_host_has_no_route_table() {
    struct OtherApp;
    impl ServerApp for OtherApp {
        fn call(&self, req: ServerRequest) -> ServerDecision {
            let status = if req.path == "/only-here" { 200 } else { 404 };
            ServerDecision::Respond { response: ServerResponse::json(status, json!({})) }
        }
    }
    let other = OtherApp;
    assert_eq!(roundtrip(&other, "GET", "/health", &[], "").0, 404, "/health is unknown to OtherApp — host holds no routes");
    assert_eq!(roundtrip(&other, "GET", "/only-here", &[], "").0, 200);
}
