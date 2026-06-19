module Lab.Editor.AppState

-- LAB-APP-STATE-P2: Proof-local code-editor app-state model.
-- Track: lab-code-editor-app-state-model-proof-local-v0
--
-- Tests the B⊕E path from LAB-APP-STATE-P1 using EXISTING Igniter concepts only:
--   - state VALUES   = named typed records
--   - transitions    = pure contracts: snapshot + event -> next snapshot
--   - lifetimes      = existing lifecycle vocabulary on `output` (:local/:session/:window/:durable)
--   - durable edge   = effect/observed contract + IO.StorageCapability (NO storage execution)
--   - holder         = HOST-owned (the language holds nothing; every output is a fresh value)
--
-- No new keyword. No `state {}`. No service/actor. No module-as-instance.
-- No storage execution. No parser/compiler/VM change. LAB-ONLY. No canon claim.
--
-- The six P1 terms are kept visibly separate (see lab doc):
--   state-value | state-instance | state-holder | transition | module-boundary | external-capability
-- Instance identity and the public/internal + app-assembly wiring are carried in a
-- proof-local sidecar (editor_app_state.registry.json), NOT in the language — that
-- separation is the evidence the proof is designed to surface.
--
-- Depends: LAB-APP-STATE-P1 (design boundary), LAB-QUERY-P3 (record shapes),
--          LAB-STORAGE-CAPABILITY-P2 (effect/capability boundary, denial-as-data),
--          PROP-031/Ch10 (modifiers), PROP-035/Ch12 (effect surface), Ch2 (lifecycle vocab).

-- ── State VALUES (typed records; identity is NOT the type name) ──────────────────

type DocumentState  { uri: String, text: String, version: Integer }
type CursorState    { line: Integer, col: Integer }
type SelectionState { anchor: Integer, head: Integer, active: Bool }
type ClipboardState { text: String, source_uri: String }
type Diagnostic     { severity: String, message: String, line: Integer }
type DiagnosticSet  { uri: String, count: Integer, worst: String }
type EditHistory    { depth: Integer, top: String, can_undo: Bool }
type BufferRef      { uri: String, open: Bool, dirty: Bool }

-- Composite snapshot — the per-view editor state at one instant.
type EditorSnapshot {
  doc:       DocumentState,
  cursor:    CursorState,
  selection: SelectionState,
  dirty:     Bool
}

-- An incoming UI/session event. Transient input; the host routes it.
type EditEvent { kind: String, text: String, at: Integer }

-- Evidence of a transition. Evidence-only; confers no authority.
type TransitionReceipt { op: String, from_version: Integer, to_version: Integer, ok: Bool }

-- ─────────────────────────────────────────────────────────────────────────────
-- TRANSITIONS — pure: (snapshot + event) -> next snapshot.
-- Each output carries the lifecycle class of the fact it produces (E path).
-- No capability on hot/session transitions. No mutable holder: outputs are values.
-- ─────────────────────────────────────────────────────────────────────────────

-- document text fact — :session
pure contract InsertText {
  input  doc   : DocumentState
  input  ev    : EditEvent
  compute bumped = doc.version
  compute next   = { uri: doc.uri, text: ev.text, version: bumped }
  output next : DocumentState lifecycle :session
}

-- cursor fact — :local (hot, per-view)
pure contract MoveCursor {
  input  cur : CursorState
  input  ev  : EditEvent
  compute next = { line: cur.line, col: ev.at }
  output next : CursorState lifecycle :local
}

-- selection fact — :local
pure contract SelectRange {
  input  sel : SelectionState
  input  ev  : EditEvent
  compute next = { anchor: sel.anchor, head: ev.at, active: true }
  output next : SelectionState lifecycle :local
}

-- clipboard fact — :session
pure contract CopySelection {
  input  doc : DocumentState
  input  sel : SelectionState
  compute snippet = { text: doc.text, source_uri: doc.uri }
  output snippet : ClipboardState lifecycle :session
}

-- composite reducer — :session. Sub-values arrive as inputs (host-held); ApplyEdit
-- only composes the next snapshot value. No nested literal construction needed.
pure contract ApplyEdit {
  input  snap   : EditorSnapshot
  input  doc    : DocumentState
  input  cursor : CursorState
  compute next = {
    doc:       doc,
    cursor:    cursor,
    selection: snap.selection,
    dirty:     true
  }
  output next : EditorSnapshot lifecycle :session
}

-- derived diagnostics fact — :window (recomputed within an analysis window)
pure contract RecomputeDiagnostics {
  input  doc   : DocumentState
  input  count : Integer
  compute set = { uri: doc.uri, count: count, worst: "warning" }
  output set : DiagnosticSet lifecycle :window
}

-- undo/redo history fact — :session
pure contract PushHistory {
  input  hist : EditHistory
  input  ev   : EditEvent
  compute next = { depth: hist.depth, top: ev.kind, can_undo: true }
  output next : EditHistory lifecycle :session
}

-- transition receipt (evidence-only)
pure contract BuildTransitionReceipt {
  input  op           : String
  input  from_version : Integer
  input  to_version   : Integer
  compute receipt = { op: op, from_version: from_version, to_version: to_version, ok: true }
  output receipt : TransitionReceipt lifecycle :audit
}

-- ─────────────────────────────────────────────────────────────────────────────
-- DURABLE BOUNDARY: see editor_app_state_durable.ig.
-- The durable save/load contracts are effect/observed and require a capability
-- passport; the VM rejects an igapp load when an unbound capability is present, so
-- (per the LAB-STORAGE-CAPABILITY-P2 two-fixture pattern) they live in a separate
-- compile-proof fixture and are NOT mixed with the VM-runnable pure transitions here.
-- ─────────────────────────────────────────────────────────────────────────────
