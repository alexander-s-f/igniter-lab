//! Async machine-backed IgWeb serving helpers (LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2).
//!
//! `serve_once_loaded` / `serve_loop_loaded` dispatch through `IgWebLoadedApp::dispatch` directly,
//! avoiding the nested `block_on` hazard that `IgWebServerApp::call` would introduce inside a tokio
//! context. This module never calls `ServerApp::call`.
//!
//! Feature `machine` only.

use crate::IgWebLoadedApp;
use igniter_server::effect_host::{dispatch as effect_dispatch, read_server_request, MachineEffectHost};
use igniter_server::host::encode_response;
use igniter_server::serving_loop::{ServingPolicy, ServingReport};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;

/// Serve exactly ONE inbound connection through the async loaded-app + machine-effect path.
/// Awaits `IgWebLoadedApp::dispatch` — no nested `block_on`.
pub async fn serve_once_loaded(
    listener: &TcpListener,
    app: &IgWebLoadedApp,
    effect_host: &MachineEffectHost<'_>,
) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept().await?;
    let req = read_server_request(&mut stream).await?;
    let decision = app.dispatch(req.clone()).await;
    let resp = effect_dispatch(&req, decision, effect_host).await;
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
        serve_once_loaded(listener, app, effect_host).await?;
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
