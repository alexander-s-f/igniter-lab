//! Host side of the Rack-like server (LAB-MACHINE-IGNITER-SERVER-BINARY-P2).
//!
//! The host owns **transport/runtime only**: it reads a loopback HTTP/1.1 request, builds a durable
//! `ServerRequest`, hands it to `app.call`, and executes the returned `ServerDecision`. It holds NO
//! route table and never inspects `(method, path)` — all routing/product meaning lives in the
//! `ServerApp`. That is the whole proof of this card.
//!
//! Transport is the std blocking `TcpListener` bound by the caller to `127.0.0.1` only. There is no
//! async runtime, no web framework, no daemon: `serve_once` handles exactly one connection and
//! returns. `serve_bounded` loops a fixed count, then returns. Nothing survives the call.
//!
//! Execution scope for P2:
//! - `Respond` is executed fully (the response goes back over the socket).
//! - `Invoke` / `InvokeEffect` are returned as **observed protocol decisions** (HTTP 202, body names
//!   the decision + target). Running them through the proven `igniter-machine` ingress / P7 atomic
//!   effect path is the next slice, `LAB-MACHINE-IGNITER-SERVER-EFFECT-P3`. Wiring the machine here
//!   would pull a tokio runtime + RocksDB backend into this crate — out of scope for a small,
//!   protocol-first proof, and it would risk DB/live. The decision is faithfully observable so P3 can
//!   execute it without changing the protocol.

use crate::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse, PROTOCOL_VERSION};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};

/// Execute an app decision into a response. Pure: no IO, no machine, no route knowledge.
///
/// `Respond` passes through. `Invoke` / `InvokeEffect` become an observable 202 protocol record
/// (execution deferred to P3). This function NEVER looks at a path or a route table — by the time a
/// decision reaches it, routing already happened in `app.call`.
pub fn execute(decision: ServerDecision) -> ServerResponse {
    match decision {
        ServerDecision::Respond { response } => response,
        ServerDecision::Invoke { target, correlation_id, idempotency_key, .. } => {
            observed("invoke", &target, correlation_id, idempotency_key)
        }
        ServerDecision::InvokeEffect { target, correlation_id, idempotency_key, .. } => {
            observed("invoke_effect", &target, correlation_id, idempotency_key)
        }
    }
}

/// A decision the host observed but does not execute in P2. 202 = accepted-for-processing; the body
/// names the decision kind + logical target so a test (or P3 executor) can read exactly what the app
/// decided. It deliberately carries no effect identity — there is none in the protocol to leak.
fn observed(kind: &str, target: &str, correlation_id: Option<String>, idempotency_key: Option<String>) -> ServerResponse {
    ServerResponse::json(
        202,
        json!({
            "decision": kind,
            "target": target,
            "execution": "deferred_to_p3",
            "correlation_id": correlation_id,
            "idempotency_key": idempotency_key,
        }),
    )
}

/// Serve exactly ONE inbound loopback connection through `app`. Parses HTTP/1.1, calls `app.call`,
/// executes the decision, writes the HTTP/1.1 response. No background worker; returns when done.
pub fn serve_once(listener: &TcpListener, app: &dyn ServerApp) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept()?;
    let req = read_request(&mut stream)?;
    let decision = app.call(req);
    let resp = execute(decision);
    write_response(&mut stream, &resp)
}

/// Serve a bounded number of connections, then return. The ONLY exit is the count — there is no
/// daemon and no unbounded loop.
pub fn serve_bounded(listener: &TcpListener, app: &dyn ServerApp, max_requests: usize) -> std::io::Result<usize> {
    let mut served = 0;
    while served < max_requests {
        serve_once(listener, app)?;
        served += 1;
    }
    Ok(served)
}

/// Reloadable variant of `serve_once`: SNAPSHOT the active app at request start (`app.current()`),
/// then serve that exact instance. A `swap` between requests is picked up by the next snapshot; an
/// in-flight request keeps the instance it snapshotted. The host still never inspects `(method, path)`
/// — routing is entirely the snapshotted app's `call`.
pub fn serve_once_reloadable(listener: &TcpListener, app: &crate::reload::ReloadableApp) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept()?;
    let current = app.current(); // snapshot — request keeps this instance even if a swap follows.
    let req = read_request(&mut stream)?;
    let decision = current.call(req);
    let resp = execute(decision);
    write_response(&mut stream, &resp)
}

/// Reloadable variant of `serve_bounded`. Each served request re-snapshots, so a swap performed
/// between two requests on the same listener takes effect for the later request.
pub fn serve_bounded_reloadable(listener: &TcpListener, app: &crate::reload::ReloadableApp, max_requests: usize) -> std::io::Result<usize> {
    let mut served = 0;
    while served < max_requests {
        serve_once_reloadable(listener, app)?;
        served += 1;
    }
    Ok(served)
}

// ── minimal loopback HTTP/1.1 (std blocking, no framework) ───────────────────────────────────────

pub(crate) fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

pub(crate) fn content_length(head: &[u8]) -> usize {
    let t = String::from_utf8_lossy(head).to_lowercase();
    for line in t.split("\r\n") {
        if let Some(v) = line.strip_prefix("content-length:") {
            return v.trim().parse().unwrap_or(0);
        }
    }
    0
}

/// Parse a raw HTTP/1.1 request buffer into a durable `ServerRequest`. Header names are lower-cased
/// and stored in a `BTreeMap` (deterministic). `correlation_id` / `idempotency_key` are promoted
/// from their headers to typed fields (P1 Q1) while remaining present in `headers`.
pub(crate) fn parse_request(buf: &[u8]) -> ServerRequest {
    let header_end = find_subslice(buf, b"\r\n\r\n").unwrap_or(buf.len());
    let head = String::from_utf8_lossy(&buf[..header_end]);
    let mut lines = head.split("\r\n");
    let request_line = lines.next().unwrap_or("");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("GET").to_string();
    let path = parts.next().unwrap_or("/").to_string();
    let mut headers = BTreeMap::new();
    for line in lines {
        if let Some((k, v)) = line.split_once(": ") {
            headers.insert(k.to_lowercase(), v.to_string());
        }
    }
    let body_start = header_end + 4;
    let body: Value = if body_start <= buf.len() {
        serde_json::from_slice(&buf[body_start..]).unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    let correlation_id = headers.get("x-correlation-id").cloned();
    let idempotency_key = headers.get("idempotency-key").cloned();
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method,
        path,
        headers,
        body,
        correlation_id,
        idempotency_key,
    }
}

fn read_request(stream: &mut TcpStream) -> std::io::Result<ServerRequest> {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    loop {
        let n = stream.read(&mut tmp)?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
        if let Some(pos) = find_subslice(&buf, b"\r\n\r\n") {
            let need = pos + 4 + content_length(&buf[..pos]);
            while buf.len() < need {
                let n = stream.read(&mut tmp)?;
                if n == 0 {
                    break;
                }
                buf.extend_from_slice(&tmp[..n]);
            }
            break;
        }
    }
    Ok(parse_request(&buf))
}

pub(crate) fn status_text(status: u16) -> &'static str {
    match status {
        200 => "OK",
        202 => "Accepted",
        400 => "Bad Request",
        404 => "Not Found",
        500 => "Internal Server Error",
        _ => "Status",
    }
}

/// Encode a `ServerResponse` to raw HTTP/1.1 bytes. Shared by the sync loopback writer and the
/// (feature-gated) async machine-effect writer so both wire formats are identical.
pub(crate) fn encode_response(resp: &ServerResponse) -> Vec<u8> {
    let body = serde_json::to_vec(&resp.body).unwrap_or_default();
    let mut head = format!("HTTP/1.1 {} {}\r\n", resp.status, status_text(resp.status));
    for (k, v) in &resp.headers {
        head.push_str(&format!("{}: {}\r\n", k, v));
    }
    head.push_str(&format!("Content-Length: {}\r\n\r\n", body.len()));
    let mut out = head.into_bytes();
    out.extend_from_slice(&body);
    out
}

fn write_response(stream: &mut TcpStream, resp: &ServerResponse) -> std::io::Result<()> {
    stream.write_all(&encode_response(resp))?;
    stream.flush()
}
