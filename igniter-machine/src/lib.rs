pub mod backend;
pub mod bridge;
pub mod bridge_effect;
pub mod capability;
pub mod capsule;
pub mod clock;
pub mod compensation;
pub mod coordination;
pub mod correlation;
pub mod errors;
pub mod executors;
pub mod fact;
pub mod frame_binding;
pub mod frame_binding_effect;
pub mod http;
pub mod ingress;
pub mod machine;
pub mod observability;
pub mod orchestrator;
pub mod postgres_read;
#[cfg(feature = "postgres")]
pub mod postgres_real;
pub mod postgres_write;
pub mod reconcile;
pub mod recovery;
pub mod registry;
pub mod secrets;
pub mod retry;
pub mod retry_queue;
pub mod service_loop;
pub mod serving_loop;
pub mod single_flight;
pub mod sparkcrm;
pub mod write;
pub mod wal;

// NOTE: the Ruby/magnus FFI (`Igniter::Machine`) was removed 2026-06-17 as a dead rudiment — it
// no longer compiled, had no gem/extconf build harness, and in-process embedding is explicitly NOT
// the architecture. Igniter and host apps (e.g. SparkCRM) run as SEPARATE processes over HTTP (the
// ingress + serving loop), never as a native extension inside another runtime.
