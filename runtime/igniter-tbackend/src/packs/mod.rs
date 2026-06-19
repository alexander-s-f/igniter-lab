// src/packs/mod.rs
// Modular extension packs for TBackend server

pub mod base_audit;
pub mod multitenant_scanner;
pub mod mesh_cluster;
pub mod trigger;
pub mod analytics;
pub mod cross_store;
pub mod snapshot;
pub mod diagnostics;
pub mod pipeline;
pub mod auth;
pub mod query;
pub mod mcp;

pub use base_audit::BaseAuditPack;
pub use multitenant_scanner::MultiTenantScannerPack;
pub use mesh_cluster::MeshClusterPack;
pub use trigger::TriggerPack;
pub use analytics::AnalyticsPack;
pub use cross_store::CrossStorePack;
pub use snapshot::SnapshotPack;
pub use diagnostics::DiagnosticsPack;
pub use pipeline::PipelinePack;
pub use auth::AuthPack;
pub use query::QueryPack;
pub use mcp::McpPack;

