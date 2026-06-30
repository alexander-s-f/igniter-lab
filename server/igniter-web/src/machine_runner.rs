//! Async machine-backed IgWeb serving helpers (LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2).
//!
//! `serve_once_loaded` / `serve_loop_loaded` dispatch through `IgWebLoadedApp::dispatch`.
//! `serve_once_loaded_with_read` / `serve_loop_loaded_with_read` dispatch through
//! `IgWebLoadedApp::dispatch_with_read` (LAB-IGNITER-WEB-READTHEN-SOCKET-RUNNER-P12).
//!
//! Both paths route final `InvokeEffect` decisions through `MachineEffectHost`.
//! This module never calls `ServerApp::call`.
//!
//! Feature `machine` only.

use crate::IgWebLoadedApp;
use crate::read_dispatch::StagedReadHost;
use crate::runner::IgwebManifest;
use igniter_server::effect_host::{
    MachineEffectHost, dispatch as effect_dispatch, read_server_request,
};
use igniter_server::host::encode_response;
use igniter_server::protocol::{ServerDecision, ServerRequest, ServerResponse};
use igniter_server::serving_loop::{ServingPolicy, ServingReport};
use serde_json::json;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;

/// Host middleware plan for the loaded async runner. Mirrors the sync runner's manifest policy while
/// keeping this path off `ServerApp::call`.
#[derive(Clone, Debug, Default)]
pub struct LoadedMiddleware {
    trace: bool,
    body_limit_bytes: Option<usize>,
    auth_token: Option<String>,
}

impl LoadedMiddleware {
    pub fn from_manifest(manifest: &IgwebManifest) -> Self {
        Self {
            trace: manifest.trace,
            body_limit_bytes: manifest.body_limit_bytes,
            auth_token: manifest
                .auth_token_env
                .as_ref()
                .map(|env_name| std::env::var(env_name).unwrap_or_default()),
        }
    }

    fn prepare_request(&self, mut req: ServerRequest) -> Result<ServerRequest, ServerResponse> {
        if let Some(max_bytes) = self.body_limit_bytes {
            let body_len = serde_json::to_vec(&req.body).map(|v| v.len()).unwrap_or(0);
            if body_len > max_bytes {
                return Err(ServerResponse::json(
                    413,
                    json!({ "error": "payload too large" }),
                ));
            }
        }

        if let Some(token) = &self.auth_token {
            req.headers.remove("x-auth-ok");
            let expected = token.trim();
            let ok = req
                .headers
                .get("authorization")
                .map(|h| !expected.is_empty() && h.strip_prefix("Bearer ").unwrap_or(h) == expected)
                .unwrap_or(false);
            if !ok {
                return Err(ServerResponse::json(
                    401,
                    json!({ "error": "unauthorized" }),
                ));
            }
            req.headers
                .insert("x-auth-ok".to_string(), "true".to_string());
        }

        if self.trace {
            // A CLIENT-supplied (non-empty) x-correlation-id is the read-replay opt-in signal (P23) and
            // is preserved verbatim. When the client sends none we DERIVE one for observability (response
            // echo + write/effect correlation), but MARK it `x-correlation-source: trace` so the read host
            // does not mistake it for an explicit replay request and stale-replay identical GETs
            // (LAB-IGNITER-WEB-TRACE-CORRELATION-READ-FRESHNESS-P58).
            let client = req
                .correlation_id
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string);
            match client {
                Some(c) => {
                    req.correlation_id = Some(c.clone());
                    req.headers.insert("x-correlation-id".to_string(), c);
                    req.headers.remove(crate::read_dispatch::CORRELATION_SOURCE_HEADER);
                }
                None => {
                    let derived = deterministic_correlation(&req);
                    req.correlation_id = Some(derived.clone());
                    req.headers.insert("x-correlation-id".to_string(), derived);
                    req.headers.insert(
                        crate::read_dispatch::CORRELATION_SOURCE_HEADER.to_string(),
                        crate::read_dispatch::CORRELATION_SOURCE_TRACE.to_string(),
                    );
                }
            }
        }

        Ok(req)
    }

    fn decorate_response(
        &self,
        mut response: ServerResponse,
        req: &ServerRequest,
    ) -> ServerResponse {
        if self.trace {
            if let Some(correlation_id) = &req.correlation_id {
                response
                    .headers
                    .insert("x-correlation-id".to_string(), correlation_id.clone());
            }
        }
        response
    }
}

fn deterministic_correlation(req: &ServerRequest) -> String {
    let mut h = DefaultHasher::new();
    req.method.hash(&mut h);
    req.path.hash(&mut h);
    serde_json::to_vec(&req.body)
        .unwrap_or_default()
        .hash(&mut h);
    format!("corr-{:016x}", h.finish())
}

/// Serve exactly ONE inbound connection through the async loaded-app + machine-effect path.
/// Awaits `IgWebLoadedApp::dispatch` — no nested `block_on`.
pub async fn serve_once_loaded(
    listener: &TcpListener,
    app: &IgWebLoadedApp,
    effect_host: &MachineEffectHost<'_>,
) -> std::io::Result<()> {
    serve_once_loaded_with_middleware(listener, app, effect_host, &LoadedMiddleware::default())
        .await
}

pub async fn serve_once_loaded_with_middleware(
    listener: &TcpListener,
    app: &IgWebLoadedApp,
    effect_host: &MachineEffectHost<'_>,
    middleware: &LoadedMiddleware,
) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept().await?;
    let req = read_server_request(&mut stream).await?;
    let req = match middleware.prepare_request(req) {
        Ok(req) => req,
        Err(response) => {
            stream.write_all(&encode_response(&response)).await?;
            return stream.flush().await;
        }
    };
    let decision = app.dispatch(req.clone()).await;
    let resp = effect_dispatch(&req, decision, effect_host).await;
    let resp = middleware.decorate_response(resp, &req);
    stream.write_all(&encode_response(&resp)).await?;
    stream.flush().await
}

/// Serve `policy.max_requests` connections through the async loaded-app + machine-effect path, then
/// return. No `tokio::spawn`; no daemon; no unbounded loop.
pub async fn serve_loop_loaded(
    listener: &TcpListener,
    app: &Arc<IgWebLoadedApp>,
    effect_host: &MachineEffectHost<'_>,
    policy: &ServingPolicy,
) -> std::io::Result<ServingReport> {
    serve_loop_loaded_with_middleware(
        listener,
        app,
        effect_host,
        policy,
        &LoadedMiddleware::default(),
    )
    .await
}

pub async fn serve_loop_loaded_with_middleware(
    listener: &TcpListener,
    app: &Arc<IgWebLoadedApp>,
    effect_host: &MachineEffectHost<'_>,
    policy: &ServingPolicy,
    middleware: &LoadedMiddleware,
) -> std::io::Result<ServingReport> {
    let addr = listener.local_addr()?;
    if policy.loopback_only && !addr.ip().is_loopback() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "serve_loop_loaded: loopback_only refused a non-loopback listener",
        ));
    }
    let mut requests_served = 0;
    let mut app_versions_seen = Vec::with_capacity(policy.max_requests);
    while requests_served < policy.max_requests {
        serve_once_loaded_with_middleware(listener, app, effect_host, middleware).await?;
        requests_served += 1;
        app_versions_seen.push(format!("loaded:{}", requests_served));
    }
    Ok(ServingReport {
        requests_served,
        app_versions_seen,
        bound_addr: addr.to_string(),
        is_loopback: addr.ip().is_loopback(),
    })
}

// ── Staged-read socket helpers (LAB-IGNITER-WEB-READTHEN-SOCKET-RUNNER-P12) ─────

/// Serve ONE connection with staged-read support (ReadThen → StagedReadHost → continuation).
/// Final `InvokeEffect` decisions from the continuation still route through `effect_host`.
/// No nested `block_on`.
pub async fn serve_once_loaded_with_read(
    listener: &TcpListener,
    app: &IgWebLoadedApp,
    effect_host: &MachineEffectHost<'_>,
    read_host: &StagedReadHost,
) -> std::io::Result<()> {
    serve_once_loaded_with_read_and_middleware(
        listener,
        app,
        effect_host,
        read_host,
        &LoadedMiddleware::default(),
    )
    .await
}

pub async fn serve_once_loaded_with_read_and_middleware(
    listener: &TcpListener,
    app: &IgWebLoadedApp,
    effect_host: &MachineEffectHost<'_>,
    read_host: &StagedReadHost,
    middleware: &LoadedMiddleware,
) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept().await?;
    let req = read_server_request(&mut stream).await?;
    let req = match middleware.prepare_request(req) {
        Ok(req) => req,
        Err(response) => {
            stream.write_all(&encode_response(&response)).await?;
            return stream.flush().await;
        }
    };
    let decision = app.dispatch_with_read(req.clone(), read_host).await;
    let resp = match decision {
        ServerDecision::Respond { response } => middleware.decorate_response(response, &req),
        other => {
            let resp = effect_dispatch(&req, other, effect_host).await;
            middleware.decorate_response(resp, &req)
        }
    };
    stream.write_all(&encode_response(&resp)).await?;
    stream.flush().await
}

/// Serve `policy.max_requests` connections with staged-read support, then return.
/// Keeps the loopback-only guard. No `tokio::spawn`; no daemon; no unbounded loop.
pub async fn serve_loop_loaded_with_read(
    listener: &TcpListener,
    app: &Arc<IgWebLoadedApp>,
    effect_host: &MachineEffectHost<'_>,
    read_host: &StagedReadHost,
    policy: &ServingPolicy,
) -> std::io::Result<ServingReport> {
    serve_loop_loaded_with_read_and_middleware(
        listener,
        app,
        effect_host,
        read_host,
        policy,
        &LoadedMiddleware::default(),
    )
    .await
}

pub async fn serve_loop_loaded_with_read_and_middleware(
    listener: &TcpListener,
    app: &Arc<IgWebLoadedApp>,
    effect_host: &MachineEffectHost<'_>,
    read_host: &StagedReadHost,
    policy: &ServingPolicy,
    middleware: &LoadedMiddleware,
) -> std::io::Result<ServingReport> {
    let addr = listener.local_addr()?;
    if policy.loopback_only && !addr.ip().is_loopback() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "serve_loop_loaded_with_read: loopback_only refused a non-loopback listener",
        ));
    }
    let mut requests_served = 0;
    let mut app_versions_seen = Vec::with_capacity(policy.max_requests);
    while requests_served < policy.max_requests {
        serve_once_loaded_with_read_and_middleware(
            listener,
            app,
            effect_host,
            read_host,
            middleware,
        )
        .await?;
        requests_served += 1;
        app_versions_seen.push(format!("loaded:{}", requests_served));
    }
    Ok(ServingReport {
        requests_served,
        app_versions_seen,
        bound_addr: addr.to_string(),
        is_loopback: addr.ip().is_loopback(),
    })
}

#[cfg(test)]
mod trace_correlation_provenance_tests {
    //! LAB-IGNITER-WEB-TRACE-CORRELATION-READ-FRESHNESS-P58 — the trace middleware must mark a
    //! DERIVED correlation as `x-correlation-source: trace` (so the read host runs it fresh) while
    //! leaving a CLIENT-supplied correlation unmarked (so it still opts into replay). This proves the
    //! provenance signal is produced at the request path, complementing the read-host unit test in
    //! `tests/readthen_dispatch_tests.rs`.
    use super::*;
    use crate::read_dispatch::{CORRELATION_SOURCE_HEADER, CORRELATION_SOURCE_TRACE};
    use igniter_server::protocol::ServerRequest;

    fn trace_mw() -> LoadedMiddleware {
        LoadedMiddleware { trace: true, body_limit_bytes: None, auth_token: None }
    }

    #[test]
    fn derived_correlation_is_marked_trace_source() {
        let req = ServerRequest::new("GET", "/accounts/a/todos", serde_json::Value::Null);
        let out = trace_mw().prepare_request(req).expect("trace middleware ok");
        assert!(
            out.correlation_id.as_deref().map(|s| !s.is_empty()).unwrap_or(false),
            "a correlation id is derived for observability"
        );
        assert_eq!(
            out.headers.get(CORRELATION_SOURCE_HEADER).map(String::as_str),
            Some(CORRELATION_SOURCE_TRACE),
            "a derived correlation is marked trace-source (read host runs it fresh)"
        );
    }

    #[test]
    fn client_correlation_is_not_marked() {
        let mut req = ServerRequest::new("GET", "/accounts/a/todos", serde_json::Value::Null);
        req.correlation_id = Some("client-corr-1".to_string());
        let out = trace_mw().prepare_request(req).expect("trace middleware ok");
        assert_eq!(out.correlation_id.as_deref(), Some("client-corr-1"), "client correlation preserved");
        assert_eq!(
            out.headers.get("x-correlation-id").map(String::as_str),
            Some("client-corr-1"),
            "client correlation echoed verbatim"
        );
        assert!(
            out.headers.get(CORRELATION_SOURCE_HEADER).is_none(),
            "a client correlation is NOT marked trace-source (it still opts into replay)"
        );
    }
}
