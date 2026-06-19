//! Safe `ServerApp` hot reload (LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4) — machine-free.
//!
//! The host holds the active app behind `Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>`. Each request
//! takes a SNAPSHOT (`current()`) of the active app at the start of processing; the read lock is held
//! only long enough to clone the inner `Arc`, never across `app.call` or effect execution. A `swap`
//! replaces the active pointer for LATER requests only — an in-flight request keeps the instance it
//! snapshotted, because it holds its own `Arc` clone.
//!
//! This is not a daemon, file watcher, or dynamic code loader: a swap is an explicit in-process call
//! (`swap(new_app)`). How a new app is produced/loaded is out of scope (and deliberately not here).

use crate::protocol::{AppIdentity, ServerApp};
use std::sync::{Arc, RwLock};

/// A reloadable handle to the active `ServerApp`. Cheap to `clone` (shares the same pointer cell), so
/// a serving loop and an operator can hold their own handles to the same active app.
#[derive(Clone)]
pub struct ReloadableApp {
    active: Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>,
}

impl ReloadableApp {
    pub fn new(app: Arc<dyn ServerApp + Send + Sync>) -> Self {
        Self {
            active: Arc::new(RwLock::new(app)),
        }
    }

    /// Snapshot the currently active app. The read lock is dropped at the end of this expression —
    /// the returned `Arc` is independent, so the caller keeps this exact instance even if a `swap`
    /// happens immediately after. This is THE seam that makes in-flight requests stable across reload.
    pub fn current(&self) -> Arc<dyn ServerApp + Send + Sync> {
        Arc::clone(&self.active.read().expect("reload lock poisoned"))
    }

    /// Replace the active app. Affects requests that snapshot AFTER this returns; in-flight requests
    /// (which already snapshotted) are untouched. Write lock held only for the pointer assignment.
    pub fn swap(&self, app: Arc<dyn ServerApp + Send + Sync>) {
        *self.active.write().expect("reload lock poisoned") = app;
    }

    /// Identity of the currently active app (observation only, not authority).
    pub fn identity(&self) -> AppIdentity {
        self.current().identity()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{ServerDecision, ServerRequest, ServerResponse};
    use serde_json::json;

    struct VApp(AppIdentity);
    impl ServerApp for VApp {
        fn call(&self, _req: ServerRequest) -> ServerDecision {
            ServerDecision::Respond {
                response: ServerResponse::json(200, json!({ "v": self.0.version })),
            }
        }
        fn identity(&self) -> AppIdentity {
            self.0.clone()
        }
    }
    fn app(v: &str) -> Arc<dyn ServerApp + Send + Sync> {
        Arc::new(VApp(AppIdentity::new("demo", v, "")))
    }

    #[test]
    fn swap_changes_current_for_later_snapshots() {
        let h = ReloadableApp::new(app("v1"));
        assert_eq!(h.identity().version, "v1");
        h.swap(app("v2"));
        assert_eq!(h.identity().version, "v2");
    }

    #[test]
    fn snapshot_is_stable_across_a_later_swap() {
        let h = ReloadableApp::new(app("v1"));
        let snapshot = h.current(); // request started here
        h.swap(app("v2")); // operator reloads mid-request
                           // the in-flight snapshot still answers v1; the next snapshot would be v2.
        assert_eq!(snapshot.identity().version, "v1");
        assert_eq!(h.current().identity().version, "v2");
    }
}
