//! Capsule control panel (LAB-MACHINE-CAPSULE-MANAGER-P1).
//!
//! Model: a **capsule is an immutable frame** — a deterministic byte image of full
//! machine state (contracts + facts + observations). An **activation** is a pure pass
//! over a frame: `(capsule, request) -> result`, or `-> result + forked capsule`.
//! Frames are never mutated in place; a fork is a new frame. This makes the "filmstrip"
//! deterministic and parallel-safe (immutable inputs → no data races).

use crate::errors::EngineError;
use crate::fact::Fact;
use crate::machine::IgniterMachine;
use std::collections::HashMap;

/// A named registry of immutable capsule frames (in-memory byte images).
pub struct CapsuleManager {
    capsules: HashMap<String, Vec<u8>>,
    backend: String,
}

impl CapsuleManager {
    pub fn new(backend: &str) -> Self {
        Self {
            capsules: HashMap::new(),
            backend: backend.to_string(),
        }
    }

    /// Freeze a live machine's current state into a named immutable capsule.
    pub async fn snapshot(&mut self, name: &str, machine: &IgniterMachine) -> Result<(), EngineError> {
        let bytes = machine.checkpoint_bytes().await?;
        self.capsules.insert(name.to_string(), bytes);
        Ok(())
    }

    /// Store raw capsule bytes (e.g. a loaded `.igm`) under a name.
    pub fn put(&mut self, name: &str, bytes: Vec<u8>) {
        self.capsules.insert(name.to_string(), bytes);
    }

    /// Sorted capsule names.
    pub fn list(&self) -> Vec<String> {
        let mut v: Vec<String> = self.capsules.keys().cloned().collect();
        v.sort();
        v
    }

    pub fn contains(&self, name: &str) -> bool {
        self.capsules.contains_key(name)
    }

    pub fn bytes(&self, name: &str) -> Option<&[u8]> {
        self.capsules.get(name).map(|v| v.as_slice())
    }

    pub fn drop(&mut self, name: &str) -> bool {
        self.capsules.remove(name).is_some()
    }

    /// Materialize a capsule into a fresh, independent live machine. Parallel-safe:
    /// frames are immutable, each instance is its own machine.
    pub async fn instantiate(&self, name: &str) -> Result<IgniterMachine, EngineError> {
        let bytes = self.capsules.get(name).ok_or(EngineError::NotFound)?;
        IgniterMachine::resume_bytes(bytes, None, &self.backend).await
    }

    /// Activation: dispatch a contract against a capsule's frame. Read-only — the frame
    /// is not mutated; the instantiated machine is ephemeral.
    pub async fn activate(
        &self,
        name: &str,
        contract: &str,
        inputs: serde_json::Value,
    ) -> Result<serde_json::Value, EngineError> {
        let m = self.instantiate(name).await?;
        m.dispatch(contract, inputs).await
    }

    /// Filmstrip: run the SAME activation across N capsule frames and collect a result
    /// table `[{capsule, output} | {capsule, error}]`. `parallel` runs them concurrently
    /// (frames are immutable → no data races). The proof of "one request, many frames":
    /// divergent frames give divergent outputs.
    pub async fn activate_many(
        &self,
        names: &[String],
        contract: &str,
        inputs: serde_json::Value,
        parallel: bool,
    ) -> Vec<serde_json::Value> {
        let run = |name: String| {
            let inputs = inputs.clone();
            async move {
                match self.activate(&name, contract, inputs).await {
                    Ok(output) => serde_json::json!({ "capsule": name, "output": output }),
                    Err(e) => serde_json::json!({ "capsule": name, "error": e.to_string() }),
                }
            }
        };
        if parallel {
            futures::future::join_all(names.iter().cloned().map(run)).await
        } else {
            let mut out = Vec::with_capacity(names.len());
            for name in names {
                out.push(run(name.clone()).await);
            }
            out
        }
    }

    /// Diff two capsule frames by their facts (the debugger lens): what facts are in
    /// `b` but not `a` (added) and in `a` but not `b` (removed), keyed by fact id.
    pub async fn diff(&self, a: &str, b: &str) -> Result<serde_json::Value, EngineError> {
        let ma = self.instantiate(a).await?;
        let fa = ma.storage.all_facts().await?;
        let mb = self.instantiate(b).await?;
        let fb = mb.storage.all_facts().await?;
        use std::collections::HashSet;
        let ida: HashSet<&str> = fa.iter().map(|f| f.id.as_str()).collect();
        let idb: HashSet<&str> = fb.iter().map(|f| f.id.as_str()).collect();
        let summarize = |f: &Fact| {
            serde_json::json!({ "store": f.store, "key": f.key, "value": f.value })
        };
        let added: Vec<_> = fb.iter().filter(|f| !ida.contains(f.id.as_str())).map(summarize).collect();
        let removed: Vec<_> = fa.iter().filter(|f| !idb.contains(f.id.as_str())).map(summarize).collect();
        Ok(serde_json::json!({
            "a": a, "b": b,
            "a_facts": fa.len(), "b_facts": fb.len(),
            "added": added, "removed": removed,
        }))
    }

    /// Fork: branch a new immutable capsule from an existing one, applying a patch
    /// (extra facts written into the fork) before freezing it. The source frame is
    /// untouched — a fork is a new fact/branch, never a mutation of the past.
    pub async fn fork(
        &mut self,
        from: &str,
        new_name: &str,
        extra_facts: &[Fact],
    ) -> Result<(), EngineError> {
        let m = self.instantiate(from).await?;
        for f in extra_facts {
            m.write_fact(f.clone()).await?;
        }
        let bytes = m.checkpoint_bytes().await?;
        self.capsules.insert(new_name.to_string(), bytes);
        Ok(())
    }
}
