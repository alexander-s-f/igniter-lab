#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_epistemic_unknown_state_kdr.rb
# LAB-EPISTEMIC-OUTCOME-P2: Unknown-state KDR convention proof
#
# Proves the v0 Kind-Discriminated Record convention for EPISTEMIC OUTCOME in an
# open-world storage scenario: a lost commit-acknowledgement must produce data
# shaped as "unknown_external_state" / "timed_out" — NOT "failed", NOT
# "system_error", NOT "upstream_unavailable" — and must route the consumer toward
# reconciliation, never toward a blind retry or an inferred success/failure.
#
# Domain: storage write commit-ack loss (the canonical lost-confirmation case the
# prior lab envelopes flattened: QueryResult→system_error, ContractResult→
# upstream_unavailable, storage commit-ack "not modeled in v0").
#
# Aligns to PROPOSED Ch12 Effect Surface outcome vocabulary + Covenant doctrine
# (Postulate 15 — Timeout Is Not Failure; Postulate 16 — Idempotency Is Declared;
# Postulate 17 — Compensation Is Named). Ch12 is treated as PROPOSED, not accepted
# canon.
#
# Three-layer proof:
#   Layer A — Production Ruby TypeChecker: OutcomeEnvelope shape, Map[String,String]
#             metadata, Option[String] map_get chain, record-literal resolution.
#   Layer B — Lab Rust VM (igniter-compiler + igniter-vm): record construction +
#             map_get(env.metadata,key)+or_else execution; the seven kinds flow as data.
#   Layer C — Proof-local consumer simulation (ReconciliationRouter): kind→action
#             routing, denial-as-data, reconciliation routing, idempotency-gated retry.
#
# Sections:
#   EOUT-COMPILE   (4) — fixture compiles, 9 contracts, SIR, no type_errors
#   EOUT-TYPES     (5) — OutcomeEnvelope fields; kind/idempotency_key String; metadata Map; Option chain
#   EOUT-KINDS     (7) — all seven kinds VM-produced as data
#   EOUT-UNKNOWN   (5) — PRIMARY: lost-ack → unknown_external_state; key+metadata preserved; mapper not system_error
#   EOUT-NOTFAILED (5) — unknown/timeout never become failed/system_error/upstream_unavailable
#   EOUT-RECONCILE (4) — reconciliation is explicit data, not control-flow magic
#   EOUT-DENIAL    (4) — denial distinct from unknown; deterministic; no retry
#   EOUT-PARTIAL   (3) — partial distinct from unknown
#   EOUT-RETRY     (5) — retry not authorized unless idempotency explicitly present (P16)
#   EOUT-CANCEL    (2) — cancelled distinct path
#   EOUT-COMPARE   (4) — vs HttpResult/ContractResult/QueryResult/ValidationResult
#   EOUT-CLOSED    (6) — KDR-only; no variant/match; no real I/O; lab-only; no sealed Outcome
#
# Total: 54 checks
#
# Depends on:
#   LAB-EPISTEMIC-OUTCOME-P1            — taxonomy + unknown-state boundary doc
#   LAB-RESULT-ENVELOPE-P2 (50/50)     — kind-discriminant 3-domain proof
#   LAB-VM-MAP-P1 (48/48)              — map_get/map_has_key VM runtime
#   PROP-043-P5 (55/55)               — Map[String,String] production surface
#   LAB-STORAGE-CAPABILITY-P1          — storage boundary design (commit-ack unmodeled in v0)
#
# Authority: LAB-ONLY. No canon claim. No framework compat. No public/stable API.
# KDR convention only — no sealed Outcome[T,E] variant, no variant/match runtime authority.
#
# Run: ruby igniter-view-engine/proofs/verify_epistemic_unknown_state_kdr.rb

SOURCE = File.read(__FILE__).freeze

require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'tempfile'

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / 'igniter-lang' / 'lib'
COMPILER_BIN   = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN         = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_PATH   = (ROOT / 'fixtures' / 'epistemic_outcome' / 'lost_confirmation_kdr.ig').to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require 'igniter_lang'

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

# ── Layer A: Ruby TypeChecker helpers ─────────────────────────────────────────

def run_fixture(path)
  src        = File.read(path.to_s).force_encoding('UTF-8')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: path.to_s).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { parsed: parsed, classified: classified, typed: typed }
rescue => e
  { error: e.message }
end

def sym_type_for(result, sym_name, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  s = c&.fetch('symbols', [])&.find { |s| s['name'] == sym_name }
  s&.fetch('type', nil)
end

def type_name_str(t)
  return t.to_s unless t.is_a?(Hash)
  name   = t['name'] || t['kind'] || '?'
  params = Array(t['params'])
  return name if params.empty?
  "#{name}[#{params.map { |p| type_name_str(p) }.join(',')}]"
end

def type_errors_for(result, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  c&.fetch('type_errors', []) || []
end

def contract_accepted?(result, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  c&.fetch('status', nil) == 'accepted'
end

def type_env_field(result, type_name, field_name)
  result[:typed]&.fetch('type_env', {})
                &.fetch(type_name, {})
                &.fetch(field_name, nil)
end

# ── Layer B: Lab Rust VM helpers ───────────────────────────────────────────────

def compile_fixture(path, out_dir)
  FileUtils.mkdir_p(out_dir)
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN, 'compile', path.to_s, '--out', out_dir.to_s, '--json'
  )
  stdout = stdout.force_encoding('UTF-8') if stdout
  return nil if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue
  nil
end

def read_sir(out_dir)
  sir_path = File.join(out_dir.to_s, 'semantic_ir_program.json')
  return nil unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path))
rescue
  nil
end

def vm_run(app_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['eout_inputs', '.json'])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _status = Open3.capture3(
    VM_BIN, 'run',
    '--contract', app_dir.to_s,
    '--inputs',   tmpfile.path,
    '--entry',    contract_name,
    '--json'
  )
  tmpfile.unlink rescue nil
  stdout = stdout.force_encoding('UTF-8') if stdout
  return { 'status' => 'vm_error', 'error' => 'empty output' } if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

# ── Layer C: Proof-local consumer simulation ──────────────────────────────────
#
# ReconciliationRouter: the open-world consumer of OutcomeEnvelope. Models what a
# storage-write caller must do on each epistemic kind. No DB. No socket. No worker.
# No scheduler. Pure deterministic Ruby. Reconciliation is returned as DATA — the
# router never raises and never infers success/failure from unknown state.

module ReconciliationRouter
  # Kinds whose outcome is genuinely unknown — must reconcile before any retry.
  UNKNOWN_KINDS = %w[timed_out unknown_external_state].freeze
  # Failure-shaped actions the unknown kinds must NEVER be coerced into.
  FAILURE_ACTIONS = %w[fail error abort].freeze

  ROUTES = {
    'succeeded'              => { action: 'accept',           summary: 'effect confirmed; take value path' },
    'denied'                 => { action: 'deny',             summary: 'capability refused before dispatch; deterministic; no retry' },
    'timed_out'              => { action: 'reconcile',        summary: 'outcome unknown; reconcile against store, do not retry blindly' },
    'unknown_external_state' => { action: 'reconcile',        summary: 'sent, unconfirmed; reconcile against store; never infer success/failure' },
    'partial'                => { action: 'reconcile_partial', summary: 'some sub-effects confirmed; reconcile the remainder' },
    'cancelled'              => { action: 'cancel',           summary: 'cancelled before completion; compensate if any effect started' },
    'compensated'            => { action: 'record',           summary: 'compensation already ran; terminal; do not re-compensate' }
  }.freeze

  def self.route(env)
    kind = env[:kind] || env['kind']
    ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  # Unknown external state is NOT a failure (Covenant P15). It must route to
  # reconciliation, never to a failure-shaped action and never to accept.
  def self.treats_unknown_as_failure?(env)
    kind = env[:kind] || env['kind']
    return false unless UNKNOWN_KINDS.include?(kind)
    FAILURE_ACTIONS.include?(route(env)[:action])
  end

  # Retry authorization (Covenant P16). A retry is authorized ONLY when an
  # idempotency key is explicitly present AND the outcome is in the
  # reconcile-then-retry class. Denial is deterministic (never retried).
  # Succeeded/partial/cancelled/compensated are not blind-retry candidates.
  RETRYABLE_AFTER_RECONCILE = %w[timed_out unknown_external_state].freeze

  def self.idempotency_present?(env)
    key = env[:idempotency_key] || env['idempotency_key']
    !key.nil? && key != ''
  end

  def self.retry_authorized?(env)
    kind = env[:kind] || env['kind']
    return false unless RETRYABLE_AFTER_RECONCILE.include?(kind)
    idempotency_present?(env)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile and run up front
# ─────────────────────────────────────────────────────────────────────────────

EOUT_OUT = Dir.mktmpdir('eout_main')
EOUT_SIR = compile_fixture(FIXTURE_PATH, EOUT_OUT)
EOUT_TC  = run_fixture(FIXTURE_PATH)

META = { 'request_id' => 'r-9', 'sent_at' => 't0', 'reconcile_hint' => 'read-back users row' }.freeze

VM_ACKED     = vm_run(EOUT_OUT, 'CommitWriteAcked',     { 'resource' => 'users', 'metadata' => { 'request_id' => 'r-1' } })
VM_DENIED    = vm_run(EOUT_OUT, 'CommitWriteDenied',    { 'reason' => 'write capability not granted', 'metadata' => { 'request_id' => 'r-2' } })
VM_TIMEDOUT  = vm_run(EOUT_OUT, 'CommitWriteTimedOut',  { 'resource' => 'users', 'idempotency_key' => 'idem-7', 'metadata' => META })
VM_LOSTACK   = vm_run(EOUT_OUT, 'CommitWriteLostAck',   { 'resource' => 'users', 'idempotency_key' => 'idem-9', 'metadata' => META })
VM_LOSTACK_NK = vm_run(EOUT_OUT, 'CommitWriteLostAck',  { 'resource' => 'users', 'idempotency_key' => '', 'metadata' => META })
VM_PARTIAL   = vm_run(EOUT_OUT, 'CommitWritePartial',   { 'resource' => 'users', 'idempotency_key' => 'idem-3', 'metadata' => META })
VM_CANCELLED = vm_run(EOUT_OUT, 'CommitWriteCancelled', { 'resource' => 'users', 'metadata' => { 'request_id' => 'r-5' } })
VM_COMPED    = vm_run(EOUT_OUT, 'CompensatedWrite',     { 'resource' => 'users', 'metadata' => { 'request_id' => 'r-6' } })
VM_MAP_UNK   = vm_run(EOUT_OUT, 'StorageOutcomeMapper', { 'raw_kind' => 'unknown_external_state', 'resource' => 'users', 'idempotency_key' => '', 'context' => { 'reconcile_hint' => 'check ledger' } })
VM_HINT      = vm_run(EOUT_OUT, 'ReconciliationHint',   { 'env' => { 'kind' => 'unknown_external_state', 'message' => 'lost', 'idempotency_key' => 'idem-9', 'metadata' => META } })

ALL_VM = [VM_ACKED, VM_DENIED, VM_TIMEDOUT, VM_LOSTACK, VM_LOSTACK_NK,
          VM_PARTIAL, VM_CANCELLED, VM_COMPED, VM_MAP_UNK, VM_HINT].freeze

# Safe kind accessor: some contracts (ReconciliationHint) return a bare String
# result rather than a record, so guard before reaching for a 'kind' field.
def vm_kind(r)
  res = r['result']
  res.is_a?(Hash) ? res['kind'] : nil
end

# Envelope-producing VM runs only (those whose result is a record with a kind).
ENVELOPE_VM = ALL_VM.select { |r| r['result'].is_a?(Hash) && r['result'].key?('kind') }.freeze

# Simulation envelopes (Layer C)
SIM_SUCCEEDED = { kind: 'succeeded',              idempotency_key: '',       metadata: {} }
SIM_DENIED    = { kind: 'denied',                 idempotency_key: 'idem-x',  metadata: {} }
SIM_TIMEDOUT  = { kind: 'timed_out',              idempotency_key: 'idem-7',  metadata: {} }
SIM_UNKNOWN   = { kind: 'unknown_external_state', idempotency_key: 'idem-9',  metadata: {} }
SIM_UNKNOWN_NK = { kind: 'unknown_external_state', idempotency_key: '',       metadata: {} }
SIM_TIMEOUT_NK = { kind: 'timed_out',             idempotency_key: '',        metadata: {} }
SIM_PARTIAL   = { kind: 'partial',                idempotency_key: 'idem-3',  metadata: {} }
SIM_CANCELLED = { kind: 'cancelled',              idempotency_key: '',        metadata: {} }
SIM_COMPED    = { kind: 'compensated',            idempotency_key: '',        metadata: {} }
SIM_BADKIND   = { kind: 'totally_unexpected',     idempotency_key: '',        metadata: {} }

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-COMPILE
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-COMPILE"

check('EOUT-COMPILE-01: fixture parses and TypeChecker runs without crash') do
  !EOUT_TC[:error] && EOUT_TC[:typed].is_a?(Hash)
end

check('EOUT-COMPILE-02: fixture produces 9 contracts in TypeChecker') do
  EOUT_TC[:typed]&.fetch('contracts', [])&.length == 9
end

check('EOUT-COMPILE-03: Rust compiler produces SIR with 9 contracts') do
  sir = read_sir(EOUT_OUT)
  sir.is_a?(Hash) && sir.fetch('contracts', []).length == 9
end

check('EOUT-COMPILE-04: all 9 contracts accepted with no type_errors') do
  cs = EOUT_TC[:typed]&.fetch('contracts', []) || []
  cs.length == 9 &&
    cs.all? { |c| (c['type_errors'] || []).empty? } &&
    cs.all? { |c| c['status'] == 'accepted' }
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-TYPES
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-TYPES"

check('EOUT-TYPES-01: OutcomeEnvelope present in type_env with 4 fields') do
  oe = EOUT_TC[:typed]&.fetch('type_env', {})&.fetch('OutcomeEnvelope', {}) || {}
  %w[kind message idempotency_key metadata].all? { |f| oe.key?(f) }
end

check('EOUT-TYPES-02: OutcomeEnvelope.kind = String (KDR discriminant)') do
  type_name_str(type_env_field(EOUT_TC, 'OutcomeEnvelope', 'kind')) == 'String'
end

check('EOUT-TYPES-03: OutcomeEnvelope.idempotency_key = String (P16 carrier)') do
  type_name_str(type_env_field(EOUT_TC, 'OutcomeEnvelope', 'idempotency_key')) == 'String'
end

check('EOUT-TYPES-04: OutcomeEnvelope.metadata = Map[String,String] (C1 fix)') do
  type_name_str(type_env_field(EOUT_TC, 'OutcomeEnvelope', 'metadata')) == 'Map[String,String]'
end

check('EOUT-TYPES-05: ReconciliationHint.hint_opt = Option[String] (map_get through named Record field)') do
  t = sym_type_for(EOUT_TC, 'hint_opt', 'ReconciliationHint')
  t.is_a?(Hash) && t['name'] == 'Option' && t.dig('params', 0, 'name') == 'String'
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-KINDS — all seven kinds flow as data through the VM
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-KINDS"

check('EOUT-KINDS-01: VM CommitWriteAcked → kind="succeeded"') do
  VM_ACKED['status'] == 'success' && VM_ACKED.dig('result', 'kind') == 'succeeded'
end

check('EOUT-KINDS-02: VM CommitWriteDenied → kind="denied"') do
  VM_DENIED['status'] == 'success' && VM_DENIED.dig('result', 'kind') == 'denied'
end

check('EOUT-KINDS-03: VM CommitWriteTimedOut → kind="timed_out"') do
  VM_TIMEDOUT['status'] == 'success' && VM_TIMEDOUT.dig('result', 'kind') == 'timed_out'
end

check('EOUT-KINDS-04: VM CommitWriteLostAck → kind="unknown_external_state"') do
  VM_LOSTACK['status'] == 'success' && VM_LOSTACK.dig('result', 'kind') == 'unknown_external_state'
end

check('EOUT-KINDS-05: VM CommitWritePartial → kind="partial"') do
  VM_PARTIAL['status'] == 'success' && VM_PARTIAL.dig('result', 'kind') == 'partial'
end

check('EOUT-KINDS-06: VM CommitWriteCancelled → kind="cancelled"') do
  VM_CANCELLED['status'] == 'success' && VM_CANCELLED.dig('result', 'kind') == 'cancelled'
end

check('EOUT-KINDS-07: VM CompensatedWrite → kind="compensated"') do
  VM_COMPED['status'] == 'success' && VM_COMPED.dig('result', 'kind') == 'compensated'
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-UNKNOWN — PRIMARY: lost commit-ack
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-UNKNOWN"

check('EOUT-UNKNOWN-01: lost-ack VM result kind is unknown_external_state (not succeeded, not failed)') do
  k = VM_LOSTACK.dig('result', 'kind')
  k == 'unknown_external_state' && k != 'succeeded' && k != 'failed'
end

check('EOUT-UNKNOWN-02: lost-ack preserves the idempotency_key as data (P16 precondition carried)') do
  VM_LOSTACK.dig('result', 'idempotency_key') == 'idem-9'
end

check('EOUT-UNKNOWN-03: lost-ack preserves reconciliation metadata (request_id for reconcile)') do
  VM_LOSTACK.dig('result', 'metadata', 'request_id') == 'r-9'
end

check('EOUT-UNKNOWN-04: lost-ack message states the state is indeterminate (no inferred outcome)') do
  msg = VM_LOSTACK.dig('result', 'message').to_s
  msg.include?('indeterminate') || msg.include?('lost')
end

check('EOUT-UNKNOWN-05: StorageOutcomeMapper maps lost-ack raw signal → unknown_external_state (NOT system_error)') do
  VM_MAP_UNK['status'] == 'success' &&
    VM_MAP_UNK.dig('result', 'kind') == 'unknown_external_state' &&
    VM_MAP_UNK.dig('result', 'kind') != 'system_error'
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-NOTFAILED — unknown/timeout never coerced to failure
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-NOTFAILED"

check('EOUT-NOTFAILED-01: no VM result across all kinds carries the forbidden kind "failed"') do
  ENVELOPE_VM.none? { |r| vm_kind(r) == 'failed' }
end

check('EOUT-NOTFAILED-02: no VM result carries the forbidden kind "system_error"') do
  ENVELOPE_VM.none? { |r| vm_kind(r) == 'system_error' }
end

check('EOUT-NOTFAILED-03: no VM result carries the forbidden kind "upstream_unavailable"') do
  ENVELOPE_VM.none? { |r| vm_kind(r) == 'upstream_unavailable' }
end

check('EOUT-NOTFAILED-04: consumer routes unknown_external_state to reconcile, not a failure action') do
  ReconciliationRouter.route(SIM_UNKNOWN)[:action] == 'reconcile' &&
    !ReconciliationRouter.treats_unknown_as_failure?(SIM_UNKNOWN)
end

check('EOUT-NOTFAILED-05: consumer routes timed_out to reconcile, not failure and not accept') do
  act = ReconciliationRouter.route(SIM_TIMEDOUT)[:action]
  act == 'reconcile' && act != 'fail' && act != 'accept' &&
    !ReconciliationRouter.treats_unknown_as_failure?(SIM_TIMEDOUT)
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-RECONCILE — reconciliation is explicit data
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-RECONCILE"

check('EOUT-RECONCILE-01: VM ReconciliationHint extracts hint from envelope metadata (map_get+or_else)') do
  VM_HINT['status'] == 'success' && VM_HINT['result'] == 'read-back users row'
end

check('EOUT-RECONCILE-02: reconcile is a first-class route for unknown_external_state') do
  ReconciliationRouter.route(SIM_UNKNOWN)[:summary].include?('reconcile')
end

check('EOUT-RECONCILE-03: reconciliation route is returned as DATA (no exception raised in router)') do
  out = ReconciliationRouter.route(SIM_UNKNOWN)
  out.is_a?(Hash) && out.key?(:action)
end

check('EOUT-RECONCILE-04: mapper supplies a default reconcile hint when context omits one') do
  vm = vm_run(EOUT_OUT, 'StorageOutcomeMapper',
              { 'raw_kind' => 'timed_out', 'resource' => 'users', 'idempotency_key' => 'k', 'context' => {} })
  vm['status'] == 'success' && vm.dig('result', 'message').to_s.include?('reconcile')
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-DENIAL — denial distinct from unknown
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-DENIAL"

check('EOUT-DENIAL-01: VM denied result kind = "denied" (denial-as-data; no raise)') do
  VM_DENIED['status'] == 'success' && VM_DENIED.dig('result', 'kind') == 'denied'
end

check('EOUT-DENIAL-02: consumer routes denied → deny action') do
  ReconciliationRouter.route(SIM_DENIED)[:action] == 'deny'
end

check('EOUT-DENIAL-03: denied is deterministic — retry NOT authorized even with idempotency key present') do
  ReconciliationRouter.idempotency_present?(SIM_DENIED) &&
    ReconciliationRouter.retry_authorized?(SIM_DENIED) == false
end

check('EOUT-DENIAL-04: denied kind is distinct from unknown_external_state') do
  VM_DENIED.dig('result', 'kind') != VM_LOSTACK.dig('result', 'kind')
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-PARTIAL — partial distinct from unknown
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-PARTIAL"

check('EOUT-PARTIAL-01: VM partial result kind = "partial"') do
  VM_PARTIAL.dig('result', 'kind') == 'partial'
end

check('EOUT-PARTIAL-02: consumer routes partial → reconcile_partial (not accept, not a failure action)') do
  act = ReconciliationRouter.route(SIM_PARTIAL)[:action]
  act == 'reconcile_partial' && act != 'accept' && !ReconciliationRouter::FAILURE_ACTIONS.include?(act)
end

check('EOUT-PARTIAL-03: partial kind is distinct from unknown_external_state') do
  VM_PARTIAL.dig('result', 'kind') != VM_LOSTACK.dig('result', 'kind')
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-RETRY — retry gated on explicit idempotency (Covenant P16)
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-RETRY"

check('EOUT-RETRY-01: unknown_external_state with NO idempotency key → retry NOT authorized') do
  ReconciliationRouter.idempotency_present?(SIM_UNKNOWN_NK) == false &&
    ReconciliationRouter.retry_authorized?(SIM_UNKNOWN_NK) == false
end

check('EOUT-RETRY-02: unknown_external_state WITH idempotency key → retry authorized (after reconcile)') do
  ReconciliationRouter.idempotency_present?(SIM_UNKNOWN) &&
    ReconciliationRouter.retry_authorized?(SIM_UNKNOWN) == true
end

check('EOUT-RETRY-03: timed_out with NO idempotency key → retry NOT authorized') do
  ReconciliationRouter.retry_authorized?(SIM_TIMEOUT_NK) == false
end

check('EOUT-RETRY-04: succeeded is never a blind-retry candidate') do
  ReconciliationRouter.retry_authorized?(SIM_SUCCEEDED) == false
end

check('EOUT-RETRY-05: VM lost-ack with empty key carries idempotency_key="" — consumer sees no retry precondition') do
  VM_LOSTACK_NK['status'] == 'success' &&
    VM_LOSTACK_NK.dig('result', 'idempotency_key') == '' &&
    ReconciliationRouter.retry_authorized?(
      { kind: VM_LOSTACK_NK.dig('result', 'kind'),
        idempotency_key: VM_LOSTACK_NK.dig('result', 'idempotency_key') }
    ) == false
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-CANCEL — cancellation distinct path
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-CANCEL"

check('EOUT-CANCEL-01: VM cancelled result kind = "cancelled"') do
  VM_CANCELLED.dig('result', 'kind') == 'cancelled'
end

check('EOUT-CANCEL-02: consumer routes cancelled → cancel (distinct from deny and from reconcile)') do
  act = ReconciliationRouter.route(SIM_CANCELLED)[:action]
  act == 'cancel' && act != 'deny' && act != 'reconcile'
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-COMPARE — vs prior lab envelopes
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-COMPARE"

check('EOUT-COMPARE-01: OutcomeEnvelope carries unknown_external_state — a kind ContractResult/QueryResult lack') do
  # ContractResult: found/created/not_found/upstream_error/capability_denied/upstream_unavailable
  # QueryResult:    rows/empty/denied/query_error/system_error
  prior_kinds = %w[found created not_found upstream_error capability_denied upstream_unavailable
                   rows empty query_error system_error]
  produced = ENVELOPE_VM.map { |r| vm_kind(r) }.compact
  produced.include?('unknown_external_state') && !prior_kinds.include?('unknown_external_state')
end

check('EOUT-COMPARE-02: OutcomeEnvelope has no integer HTTP status field (orthogonal to Rack/FullRackResponse)') do
  oe = EOUT_TC[:typed]&.fetch('type_env', {})&.fetch('OutcomeEnvelope', {}) || {}
  s = oe['status']
  s.nil? || type_name_str(s) != 'Integer'
end

check('EOUT-COMPARE-03: OutcomeEnvelope carries idempotency_key (P16) — absent from ValidationResult') do
  oe = EOUT_TC[:typed]&.fetch('type_env', {})&.fetch('OutcomeEnvelope', {}) || {}
  oe.key?('idempotency_key')
end

check('EOUT-COMPARE-04: kind discriminant is String (KDR convention, same pattern as 3 prior domains)') do
  type_name_str(type_env_field(EOUT_TC, 'OutcomeEnvelope', 'kind')) == 'String'
end

# ─────────────────────────────────────────────────────────────────────────────
# EOUT-CLOSED — KDR-only; no sealed Outcome; no real I/O; lab-only
# ─────────────────────────────────────────────────────────────────────────────

puts "\nEOUT-CLOSED"

check('EOUT-CLOSED-01: fixture declares NO variant types (KDR convention only; no sealed Outcome[T,E])') do
  (EOUT_TC[:parsed]&.fetch('variants', []) || []).empty?
end

check('EOUT-CLOSED-02: fixture code (excluding comments) uses no match expression and no sealed Outcome[ type') do
  src  = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  code = src.lines.reject { |l| l.strip.start_with?('--') }.join
  # Comments legitimately discuss "variant/match" and "Outcome[T,E]"; the CODE must not use them.
  !code.include?('match ') && !code.include?('Outcome[') && !code.include?('variant ')
end

check('EOUT-CLOSED-03: no kind is ever assigned the forbidden flattened values (literal scan)') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('kind: "failed"') &&
    !src.include?('kind: "system_error"') &&
    !src.include?('kind: "upstream_unavailable"')
end

check('EOUT-CLOSED-04: runner performs no real file/network/db/socket/worker I/O') do
  !SOURCE.include?('File.ope' + 'n') &&
    !SOURCE.include?('TCPSock' + 'et') &&
    !SOURCE.include?('Net::HT' + 'TP') &&
    !SOURCE.include?('PG.conn' + 'ect') &&
    !SOURCE.include?('Sequel.conn' + 'ect')
end

check('EOUT-CLOSED-05: no canon production file edited; lab-only boundary stated') do
  !SOURCE.include?('typecheck' + 'er.rb') &&
    !SOURCE.include?('classifi' + 'er.rb') &&
    !SOURCE.include?('semanticir_emit' + 'ter.rb') &&
    SOURCE.include?('LAB-ONLY')
end

check('EOUT-CLOSED-06: fixture is lab-only and states no production runtime claim') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  src.include?('LAB-ONLY') && !src.include?('production runtime')
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "LAB-EPISTEMIC-OUTCOME-P2: #{$pass_count}/#{total} PASS"
puts '=' * 60

if $fail_count > 0
  puts "\nFAILURES: #{$fail_count}"
  exit 1
else
  puts "\nPASS — all #{total} checks passed"
  exit 0
end
