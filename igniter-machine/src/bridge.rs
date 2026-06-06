use crate::backend::TBackend as MachineBackend;
use crate::fact::Observation;
use async_trait::async_trait;
use igniter_vm::tbackend::TBackend as VMBackend;
use igniter_vm::value::Value as VMValue;
use parking_lot::RwLock;
use std::sync::Arc;

pub struct MachineVMBackendAdapter {
    machine_storage: Arc<dyn MachineBackend>,
    observation_sink: Arc<RwLock<Vec<Observation>>>,
}

impl MachineVMBackendAdapter {
    pub fn new(
        machine_storage: Arc<dyn MachineBackend>,
        observation_sink: Arc<RwLock<Vec<Observation>>>,
    ) -> Self {
        Self {
            machine_storage,
            observation_sink,
        }
    }
}

#[async_trait]
impl VMBackend for MachineVMBackendAdapter {
    async fn read_as_of(&self, store: &str, as_of: &str) -> Result<Option<VMValue>, String> {
        let as_of_float = chrono::DateTime::parse_from_rfc3339(as_of)
            .map(|dt| dt.timestamp() as f64 + dt.timestamp_subsec_micros() as f64 / 1_000_000.0)
            .or_else(|_| {
                chrono::NaiveDateTime::parse_from_str(as_of, "%Y-%m-%d %H:%M:%S")
                    .map(|dt| dt.and_utc().timestamp() as f64)
            })
            .or_else(|_| {
                chrono::NaiveDateTime::parse_from_str(as_of, "%Y-%m-%dT%H:%M:%SZ")
                    .map(|dt| dt.and_utc().timestamp() as f64)
            })
            .or_else(|_| as_of.parse::<f64>())
            .unwrap_or(0.0);

        let (store_part, key_part) = match store.split_once('/') {
            Some((s, k)) => (s, k),
            None => (store, "global"),
        };

        match self
            .machine_storage
            .read_as_of(store_part, key_part, as_of_float)
            .await
        {
            Ok(Some(fact)) => Ok(Some(VMValue::from_json(&fact.value))),
            Ok(None) => Ok(None),
            Err(e) => Err(format!("Storage error: {:?}", e)),
        }
    }

    async fn append_observation(&self, obs: VMValue) -> Result<(), String> {
        let obs_json = obs.to_json();

        let observation = Observation {
            id: uuid::Uuid::new_v4().to_string(),
            kind: obs_json
                .get("observation_kind")
                .and_then(|k| k.as_str())
                .unwrap_or("generic")
                .to_string(),
            value: obs_json,
            timestamp: chrono::Utc::now().timestamp() as f64,
        };

        self.observation_sink.write().push(observation);
        Ok(())
    }
}
