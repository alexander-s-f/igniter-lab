// src/packs/base_audit.rs
// Base Audit & Telemetry Pack for TBackend

use crate::kernel::{PackManifest, RequestMiddleware, ServerKernel, ServerPack};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};

// ── Global Telemetry Singlet ──────────────────────────────────────────────────

pub static AUDIT_METRICS: OnceLock<Arc<MetricsTracker>> = OnceLock::new();

// ── MetricsTracker Implementation ────────────────────────────────────────────

pub struct MetricsTracker {
    pub total_requests: AtomicU64,
    pub active_connections: AtomicU64,
    pub errors_encountered: AtomicU64,
    pub bytes_read: AtomicU64,
    pub bytes_written: AtomicU64,
    pub ping_ops: AtomicU64,
    pub write_fact_ops: AtomicU64,
    pub latest_for_ops: AtomicU64,
    pub facts_for_ops: AtomicU64,
    pub query_scope_ops: AtomicU64,
    pub size_ops: AtomicU64,
    pub metrics_ops: AtomicU64,
    pub total_latency_us: AtomicU64,
}

impl MetricsTracker {
    pub fn new() -> Self {
        Self {
            total_requests: AtomicU64::new(0),
            active_connections: AtomicU64::new(0),
            errors_encountered: AtomicU64::new(0),
            bytes_read: AtomicU64::new(0),
            bytes_written: AtomicU64::new(0),
            ping_ops: AtomicU64::new(0),
            write_fact_ops: AtomicU64::new(0),
            latest_for_ops: AtomicU64::new(0),
            facts_for_ops: AtomicU64::new(0),
            query_scope_ops: AtomicU64::new(0),
            size_ops: AtomicU64::new(0),
            metrics_ops: AtomicU64::new(0),
            total_latency_us: AtomicU64::new(0),
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        let reqs = self.total_requests.load(Ordering::Relaxed);
        let lat = self.total_latency_us.load(Ordering::Relaxed);
        let avg_lat = if reqs > 0 {
            lat as f64 / reqs as f64
        } else {
            0.0
        };

        serde_json::json!({
            "total_requests": reqs,
            "active_connections": self.active_connections.load(Ordering::Relaxed),
            "errors_encountered": self.errors_encountered.load(Ordering::Relaxed),
            "bytes_read": self.bytes_read.load(Ordering::Relaxed),
            "bytes_written": self.bytes_written.load(Ordering::Relaxed),
            "ops": {
                "ping": self.ping_ops.load(Ordering::Relaxed),
                "write_fact": self.write_fact_ops.load(Ordering::Relaxed),
                "latest_for": self.latest_for_ops.load(Ordering::Relaxed),
                "facts_for": self.facts_for_ops.load(Ordering::Relaxed),
                "query_scope": self.query_scope_ops.load(Ordering::Relaxed),
                "size": self.size_ops.load(Ordering::Relaxed),
                "metrics": self.metrics_ops.load(Ordering::Relaxed),
            },
            "total_latency_us": lat,
            "average_latency_us": avg_lat,
        })
    }
}

// ── Base Audit Middleware ────────────────────────────────────────────────────

pub struct AuditMiddleware {
    metrics: Arc<MetricsTracker>,
}

impl RequestMiddleware for AuditMiddleware {
    fn before_request(
        &self,
        req: &mut serde_json::Value,
        _kernel: &ServerKernel,
    ) -> Result<(), String> {
        self.metrics.total_requests.fetch_add(1, Ordering::Relaxed);

        if let Some(op) = req.get("op").and_then(|v| v.as_str()) {
            match op {
                "ping" => self.metrics.ping_ops.fetch_add(1, Ordering::Relaxed),
                "write_fact" => self.metrics.write_fact_ops.fetch_add(1, Ordering::Relaxed),
                "latest_for" => self.metrics.latest_for_ops.fetch_add(1, Ordering::Relaxed),
                "facts_for" => self.metrics.facts_for_ops.fetch_add(1, Ordering::Relaxed),
                "query_scope" => self.metrics.query_scope_ops.fetch_add(1, Ordering::Relaxed),
                "size" => self.metrics.size_ops.fetch_add(1, Ordering::Relaxed),
                "metrics" => self.metrics.metrics_ops.fetch_add(1, Ordering::Relaxed),
                _ => 0,
            };
        }

        Ok(())
    }

    fn after_response(
        &self,
        _req: &serde_json::Value,
        resp: &mut serde_json::Value,
        _kernel: &ServerKernel,
    ) {
        if let Some(ok) = resp.get("ok").and_then(|v| v.as_bool()) {
            if !ok {
                self.metrics
                    .errors_encountered
                    .fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}

// ── Base Audit Pack ─────────────────────────────────────────────────────────

pub struct BaseAuditPack {
    metrics: Arc<MetricsTracker>,
}

impl BaseAuditPack {
    pub fn new() -> Self {
        Self {
            metrics: Arc::new(MetricsTracker::new()),
        }
    }
}

impl ServerPack for BaseAuditPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "base_audit",
            requires_packs: vec![],
            provides_capabilities: vec!["audit", "telemetry"],
            requires_capabilities: vec![],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        // 1. Initialize static singlet for frame bytes / latency updates from connection loops
        let _ = AUDIT_METRICS.set(self.metrics.clone());

        // 2. Register Middleware to count operations and trace success/failures
        kernel
            .middleware_chain
            .write()
            .register(Arc::new(AuditMiddleware {
                metrics: self.metrics.clone(),
            }));

        // 3. Register Custom Command "/metrics" returning the serialized trackers
        let metrics_c = self.metrics.clone();
        kernel.command_registry.write().register(
            "metrics",
            Arc::new(move |_req, _kernel| metrics_c.to_json()),
        );

        Ok(())
    }
}
