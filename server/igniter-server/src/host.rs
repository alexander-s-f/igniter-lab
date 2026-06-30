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

use crate::protocol::{
    PROTOCOL_VERSION, ResponseBody, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::io::{Error, ErrorKind, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

pub const DEFAULT_MAX_HEADER_BYTES: usize = 16 * 1024;
pub const DEFAULT_MAX_BODY_BYTES: usize = 1024 * 1024;
pub const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HardenedReadPolicy {
    pub max_header_bytes: usize,
    pub max_body_bytes: usize,
    pub read_timeout: Duration,
}

impl Default for HardenedReadPolicy {
    fn default() -> Self {
        Self {
            max_header_bytes: DEFAULT_MAX_HEADER_BYTES,
            max_body_bytes: DEFAULT_MAX_BODY_BYTES,
            read_timeout: DEFAULT_READ_TIMEOUT,
        }
    }
}

impl HardenedReadPolicy {
    pub fn new(max_body_bytes: usize, read_timeout: Duration) -> Self {
        Self {
            max_body_bytes,
            read_timeout,
            ..Self::default()
        }
    }
}

/// Execute an app decision into a response. Pure: no IO, no machine, no route knowledge.
///
/// `Respond` passes through. `Invoke` / `InvokeEffect` become an observable 202 protocol record
/// (execution deferred to P3). This function NEVER looks at a path or a route table — by the time a
/// decision reaches it, routing already happened in `app.call`.
pub fn execute(decision: ServerDecision) -> ServerResponse {
    match decision {
        ServerDecision::Respond { response } => response,
        ServerDecision::Invoke {
            target,
            correlation_id,
            idempotency_key,
            ..
        } => observed("invoke", &target, correlation_id, idempotency_key),
        ServerDecision::InvokeEffect {
            target,
            correlation_id,
            idempotency_key,
            ..
        } => observed("invoke_effect", &target, correlation_id, idempotency_key),
    }
}

/// A decision the host observed but does not execute in P2. 202 = accepted-for-processing; the body
/// names the decision kind + logical target so a test (or P3 executor) can read exactly what the app
/// decided. It deliberately carries no effect identity — there is none in the protocol to leak.
fn observed(
    kind: &str,
    target: &str,
    correlation_id: Option<String>,
    idempotency_key: Option<String>,
) -> ServerResponse {
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
    let req = match read_request(&mut stream) {
        Ok(req) => req,
        Err(e) => return write_response(&mut stream, &read_error_response(&e)),
    };
    let decision = app.call(req);
    let resp = execute(decision);
    write_response(&mut stream, &resp)
}

/// Serve a bounded number of connections, then return. The ONLY exit is the count — there is no
/// daemon and no unbounded loop.
pub fn serve_bounded(
    listener: &TcpListener,
    app: &dyn ServerApp,
    max_requests: usize,
) -> std::io::Result<usize> {
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
pub fn serve_once_reloadable(
    listener: &TcpListener,
    app: &crate::reload::ReloadableApp,
) -> std::io::Result<()> {
    serve_once_reloadable_observed(listener, app).map(|_| ())
}

/// Same as `serve_once_reloadable`, but returns the `AppIdentity` of the snapshotted app that served
/// the request — observation only (the serving loop records it). The snapshot is taken AFTER `accept`
/// (request-start pinning): the request that actually arrived is bound to the app active at that
/// moment, and a later swap cannot change it.
pub fn serve_once_reloadable_observed(
    listener: &TcpListener,
    app: &crate::reload::ReloadableApp,
) -> std::io::Result<crate::protocol::AppIdentity> {
    let (mut stream, _) = listener.accept()?;
    let current = app.current(); // snapshot — request keeps this instance even if a swap follows.
    let identity = current.identity();
    let req = match read_request(&mut stream) {
        Ok(req) => req,
        Err(e) => {
            write_response(&mut stream, &read_error_response(&e))?;
            return Ok(identity);
        }
    };
    let decision = current.call(req);
    let resp = execute(decision);
    write_response(&mut stream, &resp)?;
    Ok(identity)
}

/// Reloadable variant of `serve_bounded`. Each served request re-snapshots, so a swap performed
/// between two requests on the same listener takes effect for the later request.
pub fn serve_bounded_reloadable(
    listener: &TcpListener,
    app: &crate::reload::ReloadableApp,
    max_requests: usize,
) -> std::io::Result<usize> {
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
/// Split a raw request target into (path, query map). `/a/b?k=v&x=y` → (`/a/b`, {k:v, x:y}). No
/// percent-decoding in v0 (the keyset cursor is `[0-9a-f_]` and limits are digits); a bare `k` (no `=`)
/// maps to an empty value. Keeps `path` query-free so the route regexes still anchor (P47).
fn split_query(target: &str) -> (String, std::collections::BTreeMap<String, String>) {
    let mut query = std::collections::BTreeMap::new();
    let (path, qs) = match target.split_once('?') {
        Some((p, q)) => (p, q),
        None => (target, ""),
    };
    for pair in qs.split('&').filter(|s| !s.is_empty()) {
        match pair.split_once('=') {
            Some((k, v)) => query.insert(k.to_string(), v.to_string()),
            None => query.insert(pair.to_string(), String::new()),
        };
    }
    (path.to_string(), query)
}

pub(crate) fn parse_request(buf: &[u8]) -> ServerRequest {
    let header_end = find_subslice(buf, b"\r\n\r\n").unwrap_or(buf.len());
    let head = String::from_utf8_lossy(&buf[..header_end]);
    let mut lines = head.split("\r\n");
    let request_line = lines.next().unwrap_or("");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("GET").to_string();
    let (path, query) = split_query(parts.next().unwrap_or("/"));
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
        query,
    }
}

fn read_request(stream: &mut TcpStream) -> std::io::Result<ServerRequest> {
    read_request_with_policy(stream, HardenedReadPolicy::default())
}

pub fn read_request_with_policy(
    stream: &mut TcpStream,
    policy: HardenedReadPolicy,
) -> std::io::Result<ServerRequest> {
    stream.set_read_timeout(Some(policy.read_timeout))?;
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    loop {
        let n = stream.read(&mut tmp)?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
        if buf.len() > policy.max_header_bytes && find_subslice(&buf, b"\r\n\r\n").is_none() {
            return Err(Error::new(
                ErrorKind::InvalidData,
                "request headers too large",
            ));
        }
        if let Some(pos) = find_subslice(&buf, b"\r\n\r\n") {
            let body_len = content_length(&buf[..pos]);
            if body_len > policy.max_body_bytes {
                return Err(Error::new(ErrorKind::InvalidData, "payload too large"));
            }
            let need = pos + 4 + body_len;
            while buf.len() < need {
                let n = stream.read(&mut tmp)?;
                if n == 0 {
                    break;
                }
                buf.extend_from_slice(&tmp[..n]);
                if buf.len() > need {
                    buf.truncate(need);
                }
            }
            break;
        }
    }
    Ok(parse_request(&buf))
}

pub fn read_error_response(err: &std::io::Error) -> ServerResponse {
    match err.kind() {
        ErrorKind::TimedOut | ErrorKind::WouldBlock => {
            ServerResponse::json(408, json!({ "error": "request timeout" }))
        }
        ErrorKind::InvalidData if err.to_string().contains("payload too large") => {
            ServerResponse::json(413, json!({ "error": "payload too large" }))
        }
        ErrorKind::InvalidData if err.to_string().contains("headers too large") => {
            ServerResponse::json(431, json!({ "error": "request headers too large" }))
        }
        _ => ServerResponse::json(400, json!({ "error": "bad request" })),
    }
}

pub(crate) fn status_text(status: u16) -> &'static str {
    match status {
        200 => "OK",
        202 => "Accepted",
        400 => "Bad Request",
        408 => "Request Timeout",
        404 => "Not Found",
        413 => "Payload Too Large",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        _ => "Status",
    }
}

/// Encode a `ServerResponse` to raw HTTP/1.1 bytes. Shared by the sync loopback writer and the
/// (feature-gated) async machine-effect writer so both wire formats are identical.
pub fn encode_response(resp: &ServerResponse) -> Vec<u8> {
    let mut head = format!("HTTP/1.1 {} {}\r\n", resp.status, status_text(resp.status));
    for (k, v) in &resp.headers {
        head.push_str(&format!("{}: {}\r\n", k, v));
    }
    // JSON bodies are serialized (content-type comes from `headers`, set by `ServerResponse::json`);
    // raw bodies are written VERBATIM with their own content-type — no quoting/wrapping/reserialization.
    let body: Vec<u8> = match &resp.body {
        ResponseBody::Json(v) => serde_json::to_vec(v).unwrap_or_default(),
        ResponseBody::Raw {
            bytes,
            content_type,
        } => {
            head.push_str(&format!("content-type: {}\r\n", content_type));
            bytes.clone()
        }
    };
    head.push_str(&format!("Content-Length: {}\r\n\r\n", body.len()));
    let mut out = head.into_bytes();
    out.extend_from_slice(&body);
    out
}

fn write_response(stream: &mut TcpStream, resp: &ServerResponse) -> std::io::Result<()> {
    stream.write_all(&encode_response(resp))?;
    stream.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Split raw HTTP/1.1 bytes into (head string, body bytes) at the `\r\n\r\n` separator.
    fn split(wire: &[u8]) -> (String, Vec<u8>) {
        let pos = wire
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .expect("header/body separator");
        (
            String::from_utf8_lossy(&wire[..pos]).to_string(),
            wire[pos + 4..].to_vec(),
        )
    }

    #[test]
    fn json_response_encodes_unchanged() {
        let wire = encode_response(&ServerResponse::json(200, json!({"ok": true})));
        let (head, body) = split(&wire);
        assert!(head.contains("HTTP/1.1 200"));
        assert!(head.contains("content-type: application/json"));
        assert_eq!(
            body,
            br#"{"ok":true}"#.to_vec(),
            "JSON body, not double-wrapped"
        );
        assert!(head.contains(&format!("Content-Length: {}", body.len())));
    }

    #[test]
    fn parse_request_splits_query_from_path() {
        // P47: the host strips `?query` off the path (so route regexes still anchor `…/todos$`) and
        // parses it into `query`. Before this, the query rode in `path` and broke route matching.
        let req = parse_request(
            b"GET /accounts/7/todos?after=todo_abc&limit=2 HTTP/1.1\r\nHost: x\r\n\r\n",
        );
        assert_eq!(
            req.path, "/accounts/7/todos",
            "path is query-free for route matching"
        );
        assert_eq!(req.query.get("after").map(String::as_str), Some("todo_abc"));
        assert_eq!(req.query.get("limit").map(String::as_str), Some("2"));
        // a query-free request still parses, with an empty query map.
        let plain = parse_request(b"GET /health HTTP/1.1\r\nHost: x\r\n\r\n");
        assert_eq!(plain.path, "/health");
        assert!(plain.query.is_empty());
    }

    #[test]
    fn raw_html_is_written_verbatim() {
        let wire = encode_response(&ServerResponse::raw(
            200,
            b"<h1>Hello</h1>".to_vec(),
            "text/html; charset=utf-8",
        ));
        let (head, body) = split(&wire);
        assert_eq!(
            body,
            b"<h1>Hello</h1>".to_vec(),
            "verbatim bytes — no quotes, escaping, or {{\"body\":...}} wrap"
        );
        assert!(head.contains("content-type: text/html; charset=utf-8"));
        assert!(head.contains("Content-Length: 14"));
        assert!(!head.contains("application/json"));
    }

    #[test]
    fn raw_preserves_binary_bytes_including_nul_and_non_utf8() {
        let bytes = vec![0u8, 0xFF, 0x42, 0xFE, b'\n'];
        let wire = encode_response(&ServerResponse::raw(
            200,
            bytes.clone(),
            "application/octet-stream",
        ));
        let (head, body) = split(&wire);
        assert_eq!(body, bytes, "0x00 and non-UTF8 bytes preserved exactly");
        assert!(head.contains(&format!("Content-Length: {}", bytes.len())));
    }

    #[test]
    fn raw_carries_content_disposition_as_a_normal_header() {
        let mut resp = ServerResponse::raw(200, b"col1,col2\n1,2\n".to_vec(), "text/csv");
        resp.headers.insert(
            "content-disposition".to_string(),
            "attachment; filename=\"report.csv\"".to_string(),
        );
        let (head, _) = split(&encode_response(&resp));
        assert!(head.contains("content-disposition: attachment; filename=\"report.csv\""));
        assert!(head.contains("content-type: text/csv"));
    }
}
