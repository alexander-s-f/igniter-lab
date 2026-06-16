//! Adapter binding the projection ports to the igniter-machine substrate (feature `machine`).
//!
//! The machine is a CONSUMER target here: `TBackendFrameSource` reads world facts from a
//! `TBackend`; `TBackendFrameSink` records the frame as a `__frames__` fact. The machine itself
//! knows nothing about `Frame`/`Camera`/`RenderHost` — that boundary is the whole point of P2.

use crate::{Frame, FrameError, FrameSink, FrameSource};
use async_trait::async_trait;
use igniter_machine::backend::TBackend;
use igniter_machine::fact::Fact;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

/// World facts live in `__world__` (key = entity id, value = `{ "x", "y", "z", ... }`); frame
/// receipts in `__frames__`.
pub const WORLD_STORE: &str = "__world__";
pub const FRAMES_STORE: &str = "__frames__";

/// A `FrameSource` over a machine `TBackend`: the latest fact per key in `store` is the world.
pub struct TBackendFrameSource {
    pub backend: Arc<dyn TBackend>,
    pub store: String,
}

impl TBackendFrameSource {
    pub fn world_store(backend: Arc<dyn TBackend>) -> Self {
        Self { backend, store: WORLD_STORE.to_string() }
    }
}

#[async_trait]
impl FrameSource for TBackendFrameSource {
    async fn world(&self) -> Result<Vec<(String, Value)>, FrameError> {
        let facts = self.backend.all_facts().await.map_err(|e| FrameError::Source(format!("{e:?}")))?;
        let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
        for f in facts {
            if f.store != self.store {
                continue;
            }
            let e = latest.entry(f.key.clone()).or_insert((f64::NEG_INFINITY, Value::Null));
            if f.transaction_time >= e.0 {
                *e = (f.transaction_time, f.value.clone());
            }
        }
        Ok(latest.into_iter().map(|(k, (_, v))| (k, v)).collect())
    }
}

/// A `FrameSink` over a machine `TBackend`: a frame becomes a bitemporal `__frames__` fact
/// (causation = `source_receipt_id` lineage) → replayable/auditable frame history.
pub struct TBackendFrameSink {
    pub backend: Arc<dyn TBackend>,
    pub now: f64,
}

#[async_trait]
impl FrameSink for TBackendFrameSink {
    async fn record(&self, frame: &Frame) -> Result<(), FrameError> {
        let value = json!({
            "frame_index": frame.frame_index,
            "world_digest": frame.world_digest,
            "render_digest": frame.render_digest(),
            "source_receipt_id": frame.source_receipt_id,
            "node_count": frame.nodes.len(),
        });
        let fact = Fact {
            id: format!("frame:{}", frame.frame_index),
            store: FRAMES_STORE.to_string(),
            key: format!("frame:{}", frame.frame_index),
            value,
            value_hash: String::new(),
            causation: frame.source_receipt_id.clone(),
            transaction_time: self.now,
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("frame-projection")),
            derivation: None,
        };
        self.backend.write_fact(fact).await.map_err(|e| FrameError::Source(format!("{e:?}")))
    }
}
