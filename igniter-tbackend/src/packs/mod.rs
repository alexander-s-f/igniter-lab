// src/packs/mod.rs
// Modular extension packs for TBackend server

pub mod analytics;
pub mod auth;
pub mod base_audit;
pub mod cross_store;
pub mod diagnostics;
pub mod mcp;
pub mod mesh_cluster;
pub mod multitenant_scanner;
pub mod pipeline;
pub mod query;
pub mod snapshot;
pub mod trigger;

pub use analytics::AnalyticsPack;
pub use auth::AuthPack;
pub use base_audit::BaseAuditPack;
pub use cross_store::CrossStorePack;
pub use diagnostics::DiagnosticsPack;
pub use mcp::McpPack;
pub use mesh_cluster::MeshClusterPack;
pub use multitenant_scanner::MultiTenantScannerPack;
pub use pipeline::PipelinePack;
pub use query::QueryPack;
pub use snapshot::SnapshotPack;
pub use trigger::TriggerPack;
