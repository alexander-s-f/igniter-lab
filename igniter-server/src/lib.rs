//! Lab-only Igniter server shell.
//!
//! This crate intentionally starts with the app protocol only. The listener, machine wiring,
//! executor registry, RocksDB backend, orchestrator tick, and hot-reload machinery are later slices.
//! Keep product routing in the app protocol, not in server config.

#[cfg(feature = "machine")]
pub mod effect_host;
pub mod fixture;
pub mod host;
pub mod protocol;
