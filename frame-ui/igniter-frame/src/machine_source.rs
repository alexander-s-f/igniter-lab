//! Adapter binding the projection ports to the igniter-machine substrate (feature `machine`).
//!
//! The machine is a CONSUMER target here: `TBackendFrameSource` reads world facts from a
//! `TBackend`; `TBackendFrameSink` records the frame as a `__frames__` fact. The machine itself
//! knows nothing about `Frame`/`Camera`/`RenderHost` — that boundary is the whole point of P2.

use crate::{
    Frame, FrameError, FrameSink, FrameSource, InputEvent, Intent, IntentReducer, IntentSink,
};
use async_trait::async_trait;
use igniter_machine::backend::TBackend;
use igniter_machine::fact::Fact;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

/// World facts live in `__world__` (key = entity id, value = `{ "x", "y", "z", ... }`); frame
/// receipts in `__frames__`; input events in `__input__`; intent effects in `__effect__`.
pub const WORLD_STORE: &str = "__world__";
pub const FRAMES_STORE: &str = "__frames__";
pub const INPUT_STORE: &str = "__input__";
pub const EFFECT_STORE: &str = "__effect__";

/// The latest fact value per key in `store`, from a `TBackend`.
async fn latest_per_key(
    backend: &Arc<dyn TBackend>,
    store: &str,
) -> Result<Vec<(String, Value)>, FrameError> {
    let facts = backend
        .all_facts()
        .await
        .map_err(|e| FrameError::Source(format!("{e:?}")))?;
    let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
    for f in facts {
        if f.store != store {
            continue;
        }
        let e = latest
            .entry(f.key.clone())
            .or_insert((f64::NEG_INFINITY, Value::Null));
        if f.transaction_time >= e.0 {
            *e = (f.transaction_time, f.value.clone());
        }
    }
    Ok(latest.into_iter().map(|(k, (_, v))| (k, v)).collect())
}

async fn write_fact(
    backend: &Arc<dyn TBackend>,
    id: &str,
    store: &str,
    key: &str,
    value: Value,
    now: f64,
    causation: Option<String>,
) -> Result<(), FrameError> {
    let fact = Fact {
        id: id.to_string(),
        store: store.to_string(),
        key: key.to_string(),
        value,
        value_hash: String::new(),
        causation,
        transaction_time: now,
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("frame-input")),
        derivation: None,
    };
    backend
        .write_fact(fact)
        .await
        .map_err(|e| FrameError::Source(format!("{e:?}")))
}

/// An `IntentSink` over a machine `TBackend`: applies an intent by REDUCING it to new `__world__`
/// facts (the state effect) and recording `__input__` / `__effect__` receipts (lineage). The
/// intent never touches the `Frame` — only the state.
pub struct TBackendIntentSink {
    pub backend: Arc<dyn TBackend>,
    pub world_store: String,
    pub reducer: IntentReducer,
}

impl TBackendIntentSink {
    pub fn new(backend: Arc<dyn TBackend>, reducer: IntentReducer) -> Self {
        Self {
            backend,
            world_store: WORLD_STORE.to_string(),
            reducer,
        }
    }
}

#[async_trait]
impl IntentSink for TBackendIntentSink {
    async fn record_input(
        &self,
        input: &InputEvent,
        input_receipt_id: &str,
        now: f64,
    ) -> Result<(), FrameError> {
        let value =
            json!({ "kind": input.kind, "x": input.x, "y": input.y, "payload": input.payload });
        write_fact(
            &self.backend,
            input_receipt_id,
            INPUT_STORE,
            input_receipt_id,
            value,
            now,
            None,
        )
        .await
    }

    async fn apply(
        &self,
        intent: &Intent,
        input_receipt_id: &str,
        effect_receipt_id: &str,
        now: f64,
    ) -> Result<(), FrameError> {
        // reduce the intent against the current world → state deltas (the EFFECT).
        let world = latest_per_key(&self.backend, &self.world_store).await?;
        let deltas = (self.reducer)(intent, &world);
        for (id, val) in &deltas {
            // a new __world__ fact: state change, caused by the input (later tt → wins re-projection).
            write_fact(
                &self.backend,
                &format!("{}:{}", id, now),
                &self.world_store,
                id,
                val.clone(),
                now,
                Some(input_receipt_id.to_string()),
            )
            .await?;
        }
        // an effect receipt linking input → effect (lineage).
        let value =
            json!({ "action": intent.action, "target": intent.target, "deltas": deltas.len() });
        write_fact(
            &self.backend,
            effect_receipt_id,
            EFFECT_STORE,
            effect_receipt_id,
            value,
            now,
            Some(input_receipt_id.to_string()),
        )
        .await
    }
}

/// A `FrameSource` over a machine `TBackend`: the latest fact per key in `store` is the world.
pub struct TBackendFrameSource {
    pub backend: Arc<dyn TBackend>,
    pub store: String,
}

impl TBackendFrameSource {
    pub fn world_store(backend: Arc<dyn TBackend>) -> Self {
        Self {
            backend,
            store: WORLD_STORE.to_string(),
        }
    }
}

#[async_trait]
impl FrameSource for TBackendFrameSource {
    async fn world(&self) -> Result<Vec<(String, Value)>, FrameError> {
        latest_per_key(&self.backend, &self.store).await
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
        self.backend
            .write_fact(fact)
            .await
            .map_err(|e| FrameError::Source(format!("{e:?}")))
    }
}
