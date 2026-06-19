//! HTTP capability executor — readiness/design + fake-transport proof
//! (LAB-MACHINE-CAPABILITY-HTTP-P10).
//!
//! HTTP is a new RISK surface, not just another executor. This module fixes the policy (status
//! taxonomy, idempotency, redaction, credentials, rate limits, body limits, transport-error
//! classification, replay) and proves it against a FAKE transport — no real network, TLS, or
//! DNS. A real loopback transport is P11.
//!
//! The executor maps HTTP outcomes onto the existing `EffectOutcome` taxonomy, so the whole
//! P1–P9 machinery (receipts, idempotency, reconciliation, retry, durable queue) applies
//! unchanged. Credentials come from an injected host `SecretProvider` (never contract input);
//! secret headers are redacted from anything recorded.

use crate::capability::{CapabilityExecutor, EffectOutcome, EffectRequest};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum HttpMethod {
    Get,
    Head,
    Put,
    Delete,
    Post,
    Patch,
}

impl HttpMethod {
    pub fn as_str(&self) -> &'static str {
        match self {
            HttpMethod::Get => "GET",
            HttpMethod::Head => "HEAD",
            HttpMethod::Put => "PUT",
            HttpMethod::Delete => "DELETE",
            HttpMethod::Post => "POST",
            HttpMethod::Patch => "PATCH",
        }
    }
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_ascii_uppercase().as_str() {
            "GET" => Some(HttpMethod::Get),
            "HEAD" => Some(HttpMethod::Head),
            "PUT" => Some(HttpMethod::Put),
            "DELETE" => Some(HttpMethod::Delete),
            "POST" => Some(HttpMethod::Post),
            "PATCH" => Some(HttpMethod::Patch),
            _ => None,
        }
    }
    /// Idempotent methods may be safely retried after a timeout (no mutation guarantee).
    pub fn idempotent(&self) -> bool {
        matches!(self, HttpMethod::Get | HttpMethod::Head | HttpMethod::Put | HttpMethod::Delete)
    }
}

#[derive(Clone, Debug)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: String,
    pub correlation_id: String,
}

#[derive(Clone, Debug)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

/// Where a transport failure happened — determines whether a mutation could have occurred.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum HttpTransportError {
    /// Failed to resolve the host — request never sent.
    Dns,
    /// TCP connect failed — request never sent.
    Connect,
    /// TLS handshake failed transiently — request never sent.
    Tls,
    /// Certificate validation failed (untrusted/expired/wrong host) — a security policy failure,
    /// not transient. (P14.)
    CertInvalid,
    /// Sent, but no response within the deadline — mutation status unknown.
    Timeout,
}

#[async_trait]
pub trait HttpTransport: Send + Sync {
    async fn send(&self, req: &HttpRequest) -> Result<HttpResponse, HttpTransportError>;
}

/// Resolves host-held secrets by name. Credentials are injected here, never via contract input.
pub trait SecretProvider: Send + Sync {
    fn resolve(&self, name: &str) -> Option<String>;
}

fn header_get<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_str())
}

/// Default redaction set — header names whose VALUES must never be recorded.
pub fn default_redaction() -> Vec<String> {
    ["authorization", "cookie", "set-cookie", "x-api-key", "proxy-authorization"]
        .iter()
        .map(|s| s.to_string())
        .collect()
}

fn is_redacted(redact: &[String], name: &str) -> bool {
    redact.iter().any(|r| r.eq_ignore_ascii_case(name))
}

/// Request identity digest (the HTTP analog of P6b's forced-identity digest): method + URL +
/// body digest + the canonical NON-redacted headers. Secret headers are excluded (they are
/// credentials, not identity).
pub fn http_request_digest(req: &HttpRequest, redact: &[String]) -> String {
    let mut pairs: Vec<String> = req
        .headers
        .iter()
        .filter(|(k, _)| !is_redacted(redact, k))
        .map(|(k, v)| format!("{}:{}", k.to_ascii_lowercase(), v))
        .collect();
    pairs.sort();
    let body_digest = blake3::hash(req.body.as_bytes()).to_hex().to_string();
    let material = format!("{}\n{}\n{}\n{}", req.method.as_str(), req.url, body_digest, pairs.join("\n"));
    blake3::hash(material.as_bytes()).to_hex().to_string()
}

const SECRET_PREFIX: &str = "{{secret:";

/// Resolve `{{secret:NAME}}` references in header values via the provider. Returns an error
/// naming the first unresolved secret. Raw secrets only ever live in the resolved headers that
/// go to the transport — never in the digest or the recorded result.
fn resolve_secrets(
    headers: &[(String, String)],
    secrets: &dyn SecretProvider,
) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::with_capacity(headers.len());
    for (k, v) in headers {
        if let Some(rest) = v.strip_prefix(SECRET_PREFIX) {
            let name = rest.strip_suffix("}}").unwrap_or(rest);
            match secrets.resolve(name) {
                Some(secret) => out.push((k.clone(), secret)),
                None => return Err(format!("missing credential: {name}")),
            }
        } else {
            out.push((k.clone(), v.clone()));
        }
    }
    Ok(out)
}

/// Extract the host from a URL (`scheme://[user@]host[:port]/path`), lowercased identity.
pub fn url_host(url: &str) -> Option<String> {
    let after_scheme = url.split("://").nth(1).unwrap_or(url);
    let authority = after_scheme.split('/').next().unwrap_or("");
    let authority = authority.rsplit('@').next().unwrap_or(authority); // strip userinfo
    let host = authority.split(':').next().unwrap_or(authority); // strip port
    if host.is_empty() {
        None
    } else {
        Some(host.to_string())
    }
}

/// An HTTP capability executor over an injected transport + secret provider.
pub struct HttpCapabilityExecutor {
    capability_id: String,
    transport: std::sync::Arc<dyn HttpTransport>,
    secrets: std::sync::Arc<dyn SecretProvider>,
    redact: Vec<String>,
    max_body_bytes: usize,
    /// `None` = any host allowed (P10). `Some` = only these hosts (P11 loopback / P14 allowlist).
    allowed_hosts: Option<Vec<String>>,
    /// P14 external profile: require `https://` (refuse plain http before send).
    require_https: bool,
    /// P14 external profile: refuse non-idempotent methods (no external mutation) before send.
    forbid_mutations: bool,
    sends: AtomicU64,
}

impl HttpCapabilityExecutor {
    pub fn new(
        capability_id: &str,
        transport: std::sync::Arc<dyn HttpTransport>,
        secrets: std::sync::Arc<dyn SecretProvider>,
    ) -> Self {
        Self {
            capability_id: capability_id.to_string(),
            transport,
            secrets,
            redact: default_redaction(),
            max_body_bytes: 1 << 20, // 1 MiB
            allowed_hosts: None,
            require_https: false,
            forbid_mutations: false,
            sends: AtomicU64::new(0),
        }
    }
    pub fn with_max_body(mut self, n: usize) -> Self {
        self.max_body_bytes = n;
        self
    }
    /// Restrict to an explicit host allowlist (refused before send otherwise). P11 uses
    /// loopback-only; P14 widens to a vetted external allowlist.
    pub fn with_allowed_hosts(mut self, hosts: &[&str]) -> Self {
        self.allowed_hosts = Some(hosts.iter().map(|h| h.to_string()).collect());
        self
    }
    /// Loopback-only convenience (P11): `127.0.0.1` / `localhost` / `::1`.
    pub fn loopback_only(self) -> Self {
        self.with_allowed_hosts(&["127.0.0.1", "localhost", "::1"])
    }
    pub fn require_https(mut self) -> Self {
        self.require_https = true;
        self
    }
    pub fn forbid_mutations(mut self) -> Self {
        self.forbid_mutations = true;
        self
    }
    /// P14 external-substrate profile: a vetted host allowlist + https-only + read-only (no
    /// external mutation). The constrained first step past the loopback glass box.
    pub fn external_profile(self, hosts: &[&str]) -> Self {
        self.with_allowed_hosts(hosts).require_https().forbid_mutations()
    }
    /// How many times the transport was actually invoked (a replay must not increment this).
    pub fn sends(&self) -> u64 {
        self.sends.load(Ordering::SeqCst)
    }

    fn base_result(&self, req: &HttpRequest, status: Option<u16>, content_type: Option<&str>) -> Value {
        // Records identity + correlation + status only — NEVER request secrets/header values.
        let redacted: Vec<&String> = req
            .headers
            .iter()
            .map(|(k, _)| k)
            .filter(|k| is_redacted(&self.redact, k))
            .collect();
        json!({
            "request_digest": http_request_digest(req, &self.redact),
            "correlation_id": req.correlation_id,
            "status": status,
            "content_type": content_type,
            "redacted_headers": redacted,
        })
    }

    fn map_response(&self, req: &HttpRequest, resp: &HttpResponse) -> EffectOutcome {
        if resp.body.len() > self.max_body_bytes {
            return EffectOutcome::permanent("response body exceeds limit");
        }
        let content_type = header_get(&resp.headers, "content-type");
        let base = self.base_result(req, Some(resp.status), content_type);
        let mut with = |extra: Value| {
            let mut b = base.clone();
            if let (Some(o), Some(e)) = (b.as_object_mut(), extra.as_object()) {
                for (k, v) in e {
                    o.insert(k.clone(), v.clone());
                }
            }
            b
        };
        match resp.status {
            200..=299 => EffectOutcome::succeeded(with(json!({ "body": resp.body }))),
            // P14: redirects are NOT auto-followed (could escape the allowlist or leak creds).
            300..=399 => {
                let mut o = EffectOutcome::permanent("redirect not followed (auto-follow disabled)");
                o.result = base;
                o
            }
            429 => {
                let retry_after = header_get(&resp.headers, "retry-after").map(|s| s.to_string());
                let mut o = EffectOutcome::retryable("rate limited (429)");
                o.result = with(json!({ "retry_after": retry_after }));
                o
            }
            400..=499 => {
                let mut o = EffectOutcome::permanent(&format!("client error {}", resp.status));
                o.result = base;
                o
            }
            500..=599 => {
                let mut o = if req.method.idempotent() {
                    EffectOutcome::retryable(&format!("server error {} (idempotent)", resp.status))
                } else {
                    EffectOutcome::unknown(&format!(
                        "server error {} (non-idempotent) — mutation unknown",
                        resp.status
                    ))
                };
                o.result = base;
                o
            }
            other => {
                let mut o = EffectOutcome::unknown(&format!("unexpected status {other}"));
                o.result = base;
                o
            }
        }
    }

    fn map_error(&self, req: &HttpRequest, err: HttpTransportError) -> EffectOutcome {
        let mut o = match err {
            // never reached the server → no mutation → safe to retry for any method
            HttpTransportError::Dns | HttpTransportError::Connect | HttpTransportError::Tls => {
                EffectOutcome::retryable(&format!("{err:?}: request did not reach the server"))
            }
            // a bad certificate is a security policy failure, not transient → do not retry
            HttpTransportError::CertInvalid => {
                EffectOutcome::permanent("certificate validation failed")
            }
            // sent but no response → idempotent can retry, otherwise the mutation is unknown
            HttpTransportError::Timeout => {
                if req.method.idempotent() {
                    EffectOutcome::retryable("timeout on idempotent method")
                } else {
                    EffectOutcome::unknown("timeout after sending non-idempotent request — mutation unknown")
                }
            }
        };
        o.result = self.base_result(req, None, None);
        o
    }
}

#[async_trait]
impl CapabilityExecutor for HttpCapabilityExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }

    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        // parse the HTTP request out of the effect args
        let method = match req.args.get("method").and_then(|m| m.as_str()).and_then(HttpMethod::from_str) {
            Some(m) => m,
            None => return EffectOutcome::permanent("malformed HTTP request: missing/invalid method"),
        };
        let url = match req.args.get("url").and_then(|u| u.as_str()) {
            Some(u) if !u.is_empty() => u.to_string(),
            _ => return EffectOutcome::permanent("malformed HTTP request: missing url"),
        };
        let headers: Vec<(String, String)> = req
            .args
            .get("headers")
            .and_then(|h| h.as_object())
            .map(|o| o.iter().map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string())).collect())
            .unwrap_or_default();
        let body = req
            .args
            .get("body")
            .map(|b| if let Some(s) = b.as_str() { s.to_string() } else { b.to_string() })
            .unwrap_or_default();
        let correlation_id = req
            .args
            .get("correlation_id")
            .and_then(|c| c.as_str())
            .unwrap_or("")
            .to_string();

        // POLICY: host allowlist (P11 loopback / P14 external) — refused BEFORE DNS/connect/send.
        if let Some(allow) = &self.allowed_hosts {
            let host = url_host(&url).unwrap_or_default();
            if !allow.iter().any(|h| h.eq_ignore_ascii_case(&host)) {
                return EffectOutcome::permanent(&format!("host not allowed by policy: {host}"));
            }
        }

        // P14 external profile: https-only — refused before send.
        if self.require_https && !url.to_ascii_lowercase().starts_with("https://") {
            return EffectOutcome::permanent("external profile requires https");
        }

        // P14 external profile: no external mutation — non-idempotent methods refused before send.
        if self.forbid_mutations && !method.idempotent() {
            return EffectOutcome::permanent("external mutation not permitted by policy");
        }

        // POLICY: non-idempotent methods require an idempotency key.
        if !method.idempotent() && req.idempotency_key.is_empty() {
            return EffectOutcome::permanent("non-idempotent method requires an idempotency key");
        }

        // resolve injected credentials; refuse (do NOT send) if a secret is missing.
        let resolved = match resolve_secrets(&headers, self.secrets.as_ref()) {
            Ok(h) => h,
            Err(e) => return EffectOutcome::permanent(&e),
        };

        let http_req = HttpRequest { method, url, headers: resolved, body, correlation_id };

        self.sends.fetch_add(1, Ordering::SeqCst);
        match self.transport.send(&http_req).await {
            Ok(resp) => self.map_response(&http_req, &resp),
            Err(err) => self.map_error(&http_req, err),
        }
    }
}

// ── Fake transport + secret provider (proof only — no real network) ────────────

/// A fake transport: returns a programmed result and captures the last request actually sent
/// (so tests can assert correlation headers / resolved secrets / no re-send on replay).
pub struct FakeHttpTransport {
    programmed: Mutex<Result<HttpResponse, HttpTransportError>>,
    last: Mutex<Option<HttpRequest>>,
    sends: AtomicU64,
}

impl FakeHttpTransport {
    pub fn new(programmed: Result<HttpResponse, HttpTransportError>) -> Self {
        Self { programmed: Mutex::new(programmed), last: Mutex::new(None), sends: AtomicU64::new(0) }
    }
    pub fn ok(status: u16, body: &str, headers: Vec<(&str, &str)>) -> Self {
        Self::new(Ok(HttpResponse {
            status,
            headers: headers.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
            body: body.to_string(),
        }))
    }
    pub fn err(e: HttpTransportError) -> Self {
        Self::new(Err(e))
    }
    pub fn sends(&self) -> u64 {
        self.sends.load(Ordering::SeqCst)
    }
    pub fn last_request(&self) -> Option<HttpRequest> {
        self.last.lock().unwrap().clone()
    }
}

#[async_trait]
impl HttpTransport for FakeHttpTransport {
    async fn send(&self, req: &HttpRequest) -> Result<HttpResponse, HttpTransportError> {
        self.sends.fetch_add(1, Ordering::SeqCst);
        *self.last.lock().unwrap() = Some(req.clone());
        self.programmed.lock().unwrap().clone()
    }
}

/// A fake in-memory secret provider.
pub struct MapSecretProvider {
    map: std::collections::HashMap<String, String>,
}

impl MapSecretProvider {
    pub fn new(pairs: &[(&str, &str)]) -> Self {
        Self { map: pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect() }
    }
}

impl SecretProvider for MapSecretProvider {
    fn resolve(&self, name: &str) -> Option<String> {
        self.map.get(name).cloned()
    }
}

// ── Real loopback transport (LAB-MACHINE-CAPABILITY-HTTP-P11) ───────────────────

fn parse_url(url: &str) -> Option<(String, u16, String)> {
    let after = url.split("://").nth(1)?;
    let (authority, path) = match after.find('/') {
        Some(i) => (&after[..i], after[i..].to_string()),
        None => (after, "/".to_string()),
    };
    let authority = authority.rsplit('@').next().unwrap_or(authority);
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) => (h.to_string(), p.parse().ok()?),
        None => (authority.to_string(), 80u16),
    };
    Some((host, port, path))
}

fn parse_response(buf: &[u8]) -> Option<HttpResponse> {
    if buf.is_empty() {
        return None;
    }
    let text = String::from_utf8_lossy(buf);
    let split = text.find("\r\n\r\n")?;
    let head = &text[..split];
    let body = text[split + 4..].to_string();
    let mut lines = head.split("\r\n");
    let status_line = lines.next()?;
    let status: u16 = status_line.split_whitespace().nth(1)?.parse().ok()?;
    let headers = lines
        .filter_map(|l| l.split_once(": ").map(|(k, v)| (k.to_string(), v.to_string())))
        .collect();
    Some(HttpResponse { status, headers, body })
}

/// A REAL HTTP/1.1 transport over a TCP socket — used only against a loopback test server in
/// P11 (the executor's host allowlist enforces loopback). Minimal by design: no TLS, no
/// keep-alive, no chunked encoding. This proves the P10 policy transfers to a real transport
/// boundary. The `correlation_id` is sent as an `X-Correlation-Id` header.
#[derive(Default)]
pub struct LoopbackHttpTransport;

impl LoopbackHttpTransport {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl HttpTransport for LoopbackHttpTransport {
    async fn send(&self, req: &HttpRequest) -> Result<HttpResponse, HttpTransportError> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio::net::TcpStream;

        let (host, port, path) = parse_url(&req.url).ok_or(HttpTransportError::Dns)?;
        let mut stream = TcpStream::connect((host.as_str(), port))
            .await
            .map_err(|_| HttpTransportError::Connect)?;

        let mut head = format!(
            "{} {} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n",
            req.method.as_str(),
            path,
            host
        );
        if !req.correlation_id.is_empty() {
            head.push_str(&format!("X-Correlation-Id: {}\r\n", req.correlation_id));
        }
        for (k, v) in &req.headers {
            head.push_str(&format!("{k}: {v}\r\n"));
        }
        head.push_str(&format!("Content-Length: {}\r\n\r\n", req.body.len()));

        stream.write_all(head.as_bytes()).await.map_err(|_| HttpTransportError::Connect)?;
        stream.write_all(req.body.as_bytes()).await.map_err(|_| HttpTransportError::Connect)?;

        let mut buf = Vec::new();
        // server closes the connection after responding (Connection: close); an empty read =
        // no response (lost response) → Timeout.
        stream.read_to_end(&mut buf).await.map_err(|_| HttpTransportError::Timeout)?;
        parse_response(&buf).ok_or(HttpTransportError::Timeout)
    }
}

// ── Real TLS transport (LAB-MACHINE-CAPABILITY-HTTP-TLS-P14-IMPL, feature = "tls") ──

/// Build the HTTP/1.1 request bytes (shared by loopback + TLS transports).
fn serialize_request(req: &HttpRequest, host: &str, path: &str) -> Vec<u8> {
    let mut head = format!(
        "{} {} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n",
        req.method.as_str(),
        path,
        host
    );
    if !req.correlation_id.is_empty() {
        head.push_str(&format!("X-Correlation-Id: {}\r\n", req.correlation_id));
    }
    for (k, v) in &req.headers {
        head.push_str(&format!("{k}: {v}\r\n"));
    }
    head.push_str(&format!("Content-Length: {}\r\n\r\n", req.body.len()));
    let mut bytes = head.into_bytes();
    bytes.extend_from_slice(req.body.as_bytes());
    bytes
}

/// A REAL HTTPS/1.1 transport over rustls. Used only against a local TLS server in P14-impl (the
/// executor's host allowlist + https-only profile fences it). Cert-validation failures map to
/// `CertInvalid` (→ permanent), other handshake failures to `Tls` (→ retryable) — exactly the
/// P14 policy, now on a real handshake.
#[cfg(feature = "tls")]
pub struct TlsLoopbackHttpTransport {
    config: std::sync::Arc<tokio_rustls::rustls::ClientConfig>,
}

#[cfg(feature = "tls")]
impl TlsLoopbackHttpTransport {
    /// Trust ONLY the given PEM cert(s) — a local self-signed test CA. Any other server cert →
    /// `CertInvalid`.
    pub fn trusting_pem(ca_pem: &[u8]) -> Self {
        use tokio_rustls::rustls::{Certificate, ClientConfig, RootCertStore};
        let mut roots = RootCertStore::empty();
        if let Ok(certs) = rustls_pemfile::certs(&mut &ca_pem[..]) {
            for c in certs {
                let _ = roots.add(&Certificate(c));
            }
        }
        let config = ClientConfig::builder()
            .with_safe_defaults()
            .with_root_certificates(roots)
            .with_no_client_auth();
        Self { config: std::sync::Arc::new(config) }
    }

    /// Trust nothing extra (empty roots) — a self-signed server cert → `CertInvalid`
    /// (UnknownIssuer). Proves the invalid-cert path on a real handshake.
    pub fn untrusting() -> Self {
        use tokio_rustls::rustls::{ClientConfig, RootCertStore};
        let config = ClientConfig::builder()
            .with_safe_defaults()
            .with_root_certificates(RootCertStore::empty())
            .with_no_client_auth();
        Self { config: std::sync::Arc::new(config) }
    }
}

#[cfg(feature = "tls")]
fn classify_tls_io_error(e: &std::io::Error) -> HttpTransportError {
    if let Some(inner) = e.get_ref() {
        if let Some(rustls_err) = inner.downcast_ref::<tokio_rustls::rustls::Error>() {
            if matches!(rustls_err, tokio_rustls::rustls::Error::InvalidCertificate(_)) {
                return HttpTransportError::CertInvalid;
            }
        }
    }
    HttpTransportError::Tls
}

#[cfg(feature = "tls")]
#[async_trait]
impl HttpTransport for TlsLoopbackHttpTransport {
    async fn send(&self, req: &HttpRequest) -> Result<HttpResponse, HttpTransportError> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio::net::TcpStream;
        use tokio_rustls::{rustls::ServerName, TlsConnector};

        let (host, port, path) = parse_url(&req.url).ok_or(HttpTransportError::Dns)?;
        let tcp = TcpStream::connect((host.as_str(), port))
            .await
            .map_err(|_| HttpTransportError::Connect)?;
        let server_name = ServerName::try_from(host.as_str()).map_err(|_| HttpTransportError::Tls)?;
        let connector = TlsConnector::from(self.config.clone());
        let mut stream = match connector.connect(server_name, tcp).await {
            Ok(s) => s,
            Err(e) => return Err(classify_tls_io_error(&e)), // cert vs transient handshake
        };

        let bytes = serialize_request(req, &host, &path);
        stream.write_all(&bytes).await.map_err(|_| HttpTransportError::Tls)?;
        let mut buf = Vec::new();
        stream.read_to_end(&mut buf).await.map_err(|_| HttpTransportError::Timeout)?;
        parse_response(&buf).ok_or(HttpTransportError::Timeout)
    }
}
