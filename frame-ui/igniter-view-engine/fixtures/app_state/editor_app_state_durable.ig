module Lab.Editor.AppState.Durable

-- LAB-APP-STATE-P2: durable save/load boundary for the code-editor app-state model.
-- Track: lab-code-editor-app-state-model-proof-local-v0
--
-- Companion to editor_app_state.ig. These contracts model the DURABLE boundary as
-- effect/observed contracts gated by IO.StorageCapability — capability/effect-shaped,
-- with NO storage execution (compute is a pure stub). They are split into this
-- separate fixture because an effect contract carries an unbound capability passport
-- that the VM rejects at igapp load time; the pure transitions in editor_app_state.ig
-- must stay VM-runnable. This mirrors the LAB-STORAGE-CAPABILITY-P2 two-fixture pattern.
--
-- Compile-proof only (Layer A Ruby TypeChecker + Layer B Rust compiler). No VM run.
-- No real DB/SQL/ORM/persistence. No storage execution. LAB-ONLY. No canon claim.

-- Types re-declared locally for lab independence (structural typing).
type DocumentState { uri: String, text: String, version: Integer }
type SaveRequest   { uri: String, text: String, version: Integer, mode: String }

-- Save = effect contract. The capability marks the durable edge; the contract only
-- BUILDS the request value. compute is a pure stub — no real write happens in v0.
-- modifier=effect -> fragment ESCAPE. Hot/session transitions need NO capability;
-- only this durable boundary does.
effect contract BuildSaveRequest {
  capability storage : IO.StorageCapability
  effect read_file using storage
  input  doc : DocumentState
  compute req = { uri: doc.uri, text: doc.text, version: doc.version, mode: "save" }
  output req : SaveRequest lifecycle :durable
}

-- Load = observed contract reading the durable holder BY NAME. The `from` string
-- names the external/durable store (the holder lives outside the language); the
-- produced doc re-enters the :session lifetime. modifier=observed -> fragment ESCAPE.
observed contract LoadDocument {
  read   stored : DocumentState from "editor.workspace" lifecycle :durable
  compute doc = stored
  output doc : DocumentState lifecycle :session
}
