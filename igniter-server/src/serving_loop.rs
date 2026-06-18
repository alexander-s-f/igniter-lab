//! Bounded serving loop over a reloadable app (LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5).
//!
//! A loop, not a daemon. It runs a fixed `max_requests` budget over a **pre-bound** `TcpListener` and
//! returns — the host owns the loop, transport, and cadence; the app owns the decision. Key
//! invariants:
//!
//! - **The loop opens no address.** It only ever calls `accept()` on a listener the caller bound.
//!   This (not a public-bind guard) is the structural safety property: the loop cannot turn into a
//!   deployment mechanism because it has no `bind`. An *opt-in* `loopback_only` check is offered for
//!   lab convenience, but it is OFF by default so the loop imposes no deployment policy.
//! - **Bounded exit.** The loop returns the instant `requests_served == max_requests`. No background
//!   thread, no `tokio::spawn`, no timer.
//! - **Request-start pinning.** Each iteration snapshots the active app AFTER `accept` (via
//!   `serve_once_reloadable_observed`); a swap affects only later iterations.
//! - **No route table.** The loop never inspects `(method, path)` — routing stays in the app's `call`.
//! - **Observation-only report.** `ServingReport` is counters + identities seen; it is not a ledger.

use crate::host::serve_once_reloadable_observed;
use crate::reload::ReloadableApp;
use std::net::{SocketAddr, TcpListener};

/// Deterministic loop budget. `loopback_only` is an opt-in lab guard (default OFF — the loop's real
/// safety is that it binds nothing).
#[derive(Clone, Debug)]
pub struct ServingPolicy {
    pub max_requests: usize,
    pub loopback_only: bool,
}

impl ServingPolicy {
    pub fn new(max_requests: usize) -> Self {
        Self { max_requests, loopback_only: false }
    }
    /// Opt in to refusing a non-loopback listener BEFORE accepting (lab convenience, not deployment
    /// policy — the caller chose to bind, the loop merely declines to serve a public one).
    pub fn loopback_only(mut self) -> Self {
        self.loopback_only = true;
        self
    }
}

/// Observation-only summary of a completed loop. Not authority: the only authoritative facts remain
/// receipts / WAL in the machine. `app_versions_seen` is the snapshotted app identity version per
/// request, in order — proof of which app version served each request across a swap.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ServingReport {
    pub requests_served: usize,
    pub app_versions_seen: Vec<String>,
    pub bound_addr: String,
    pub is_loopback: bool,
}

/// The opt-in loopback guard as a pure function so it is testable without ever binding a public
/// address. Narrow: it only maps (addr, flag) → allow/deny; it encodes no deployment policy.
pub(crate) fn enforce_loopback(addr: SocketAddr, loopback_only: bool) -> std::io::Result<()> {
    if loopback_only && !addr.ip().is_loopback() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "serving loop: loopback_only policy refused a non-loopback listener",
        ));
    }
    Ok(())
}

/// Serve exactly `policy.max_requests` requests over a caller-bound `listener`, then return. The loop
/// binds nothing. Each request snapshots the active app (request-start pinning); a `swap` between
/// requests is picked up by the next iteration.
pub fn serve_loop(listener: &TcpListener, app: &ReloadableApp, policy: &ServingPolicy) -> std::io::Result<ServingReport> {
    let addr = listener.local_addr()?;
    enforce_loopback(addr, policy.loopback_only)?;

    let mut app_versions_seen = Vec::with_capacity(policy.max_requests);
    while app_versions_seen.len() < policy.max_requests {
        let identity = serve_once_reloadable_observed(listener, app)?;
        app_versions_seen.push(identity.version);
    }

    Ok(ServingReport {
        requests_served: app_versions_seen.len(),
        app_versions_seen,
        bound_addr: addr.to_string(),
        is_loopback: addr.ip().is_loopback(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loopback_guard_is_a_narrow_pure_check() {
        let loop_addr: SocketAddr = "127.0.0.1:8080".parse().unwrap();
        let public_addr: SocketAddr = "0.0.0.0:8080".parse().unwrap();

        // off by default: anything is allowed (no deployment policy imposed).
        assert!(enforce_loopback(public_addr, false).is_ok());
        // opt-in: loopback allowed, non-loopback refused — without ever binding a socket.
        assert!(enforce_loopback(loop_addr, true).is_ok());
        assert!(enforce_loopback(public_addr, true).is_err());
    }
}
