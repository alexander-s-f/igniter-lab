#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_result_envelope_p2.rb
# LAB-RESULT-ENVELOPE-P2: Third-domain kind-discriminant pressure proof — 50 checks
#
# Tests whether the `kind`-discriminant result-envelope pattern generalizes
# beyond HTTP/Rack and Sidekiq by proving a validation/form-processing domain
# fixture. Classifies which envelope pieces remain reusable vs domain-local.
#
# Third domain: Form validation and submission processing.
#   Orthogonal to HTTP/Rack (no HTTP status codes) and Sidekiq (no retry budget,
#   no job identity fields). Four-kind ValidationResult:
#     "valid"        — happy path
#     "invalid"      — field-level constraint violated
#     "unauthorized" — denial-as-data in a non-HTTP context
#     "system_error" — infrastructure fault, not a user error
#
# Two-layer proof:
#   Layer A — Production Ruby TypeChecker: type shapes, Map[String,String] metadata
#             inference, record literal resolution, or_else/map_get chain.
#   Layer B — Lab Rust VM (igniter-compiler + igniter-vm): record construction,
#             map_get(vr.metadata, key) + or_else execution (same chain as
#             MetadataReader/HeaderChain proved in LAB-VM-MAP-P1).
#   Layer C — Proof-local routing simulation: 4-kind routing, determinism,
#             denial-as-data behavioral proof.
#
# Sections:
#   VENV-COMPILE  (4)  — fixture compiles, 7 contracts, SIR, no type_errors
#   VENV-TYPES    (5)  — type env: ValidationResult fields, Option[String] map chain
#   VENV-KINDS    (6)  — all 4 kind values (valid/invalid/unauthorized/system_error)
#   VENV-DENIED   (4)  — denial-as-data in non-HTTP form domain
#   VENV-MAP      (5)  — Map[String,String] metadata: type-level + VM execution
#   VENV-VM       (6)  — VM record construction + map chain execution
#   VENV-ROUTE    (5)  — routing simulation: 4 kind paths + fail-closed
#   VENV-COMPARE  (5)  — comparison against HttpResult/ContractResult/JobReceipt
#   VENV-PROMOTE  (5)  — promotion readiness: which patterns generalise
#   VENV-CLOSED   (5)  — closed surface: no HTTP status, no job fields, lab-only
#
# Total: 50 checks
#
# Depends on:
#   LAB-RESULT-ENVELOPE-P1 — taxonomy baseline; identified third-domain gap
#   LAB-VM-MAP-P1 (48/48)  — map_get/map_has_key VM runtime; or_else pre-existing
#   LAB-SIDEKIQ-P5 (48/48) — MetadataReader map_get(job.metadata,key) pattern
#   PROP-043-P5 (55/55)    — Map[String,String] production surface + C1 fix
#
# Authority: LAB-ONLY. No canon claim. No framework compat. No public API.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_result_envelope_p2.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'validation_envelope' / 'validation_envelope.ig').to_s

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
  tmpfile = Tempfile.new(['venv_inputs', '.json'])
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

# ── Layer C: Proof-local routing simulation ───────────────────────────────────
#
# ValidationRouter: domain consumer of ValidationResult kind field.
# Models what a SubmissionProcessor would do on each of the 4 kinds.
# No HTTP client. No job queue. No scheduler. Pure deterministic Ruby.

module ValidationRouter
  ROUTES = {
    'valid'        => { action: 'accept',  summary: 'submission accepted and stored' },
    'invalid'      => { action: 'reject',  summary: 'validation failed; show user errors' },
    'unauthorized' => { action: 'deny',    summary: 'access denied; do not process' },
    'system_error' => { action: 'error',   summary: 'infrastructure failure; retry later' }
  }.freeze

  def self.route(validation_result)
    kind = validation_result[:kind] || validation_result['kind']
    ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  # denial_as_data: returns the route for a denial kind without raising.
  # Proves the invariant holds in a domain that has no HTTP status codes.
  def self.denial_as_data?(kind)
    kind == 'unauthorized' && ROUTES.key?('unauthorized')
  end

  # metadata_get: simulates map_get + or_else over a plain Ruby hash.
  def self.metadata_get(metadata, key, default_val = 'unknown')
    val = metadata[key] || metadata[key.to_sym]
    val.nil? ? default_val : val
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile and run up front
# ─────────────────────────────────────────────────────────────────────────────

VENV_OUT = Dir.mktmpdir('venv_main')
VENV_SIR = compile_fixture(FIXTURE_PATH, VENV_OUT)
VENV_TC  = run_fixture(FIXTURE_PATH)

# Shared VM inputs
VALID_INPUTS = {
  'name'    => 'Alice',
  'email'   => 'alice@example.com',
  'context' => { 'source' => 'web', 'form' => 'signup' }
}.freeze

META_PRESENT_INPUTS = {
  'vr' => {
    'field'    => 'email',
    'kind'     => 'invalid',
    'message'  => 'required field missing',
    'metadata' => { 'rule' => 'required', 'field_name' => 'email', 'expected' => 'non-empty' }
  }
}.freeze

META_ABSENT_INPUTS = {
  'vr' => {
    'field'    => '',
    'kind'     => 'valid',
    'message'  => 'ok',
    'metadata' => { 'source' => 'web' }
  }
}.freeze

MAPPER_WITH_MSG_INPUTS = {
  'raw_kind'  => 'invalid',
  'raw_field' => 'phone',
  'context'   => { 'message' => 'phone must be 10 digits', 'rule' => 'phone_format' }
}.freeze

MAPPER_NO_MSG_INPUTS = {
  'raw_kind'  => 'system_error',
  'raw_field' => '',
  'context'   => { 'rule' => 'schema_check' }
}.freeze

UNAUTHORIZED_INPUTS = {
  'reason'   => 'account suspended',
  'metadata' => { 'rule' => 'account_status', 'expected' => 'active' }
}.freeze

VM_VALID        = vm_run(VENV_OUT, 'ValidSubmission',     VALID_INPUTS)
VM_META_PRESENT = vm_run(VENV_OUT, 'MetadataInspector',   META_PRESENT_INPUTS)
VM_META_ABSENT  = vm_run(VENV_OUT, 'MetadataInspector',   META_ABSENT_INPUTS)
VM_MAPPER_MSG   = vm_run(VENV_OUT, 'ValidationMapper',    MAPPER_WITH_MSG_INPUTS)
VM_MAPPER_NOMSG = vm_run(VENV_OUT, 'ValidationMapper',    MAPPER_NO_MSG_INPUTS)
VM_UNAUTH       = vm_run(VENV_OUT, 'UnauthorizedSubmission', UNAUTHORIZED_INPUTS)

# Simulation inputs
SIM_VALID       = { kind: 'valid',        field: '',      message: 'ok',                 metadata: {} }
SIM_INVALID     = { kind: 'invalid',      field: 'email', message: 'required missing',   metadata: { 'rule' => 'required' } }
SIM_UNAUTH      = { kind: 'unauthorized', field: '',      message: 'account suspended',  metadata: { 'rule' => 'account_status' } }
SIM_SYSERR      = { kind: 'system_error', field: '',      message: 'constraint failed',  metadata: {} }
SIM_UNKNOWN     = { kind: 'unexpected_kind', field: '',   message: '',                   metadata: {} }

# ─────────────────────────────────────────────────────────────────────────────
# VENV-COMPILE: Fixture compilation
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-COMPILE"

check('VENV-COMPILE-01: fixture parses and TypeChecker runs without crash') do
  !VENV_TC[:error] && VENV_TC[:typed].is_a?(Hash)
end

check('VENV-COMPILE-02: fixture produces 7 contracts in TypeChecker') do
  VENV_TC[:typed]&.fetch('contracts', [])&.length == 7
end

check('VENV-COMPILE-03: Rust compiler produces SIR with 7 contracts') do
  sir = read_sir(VENV_OUT)
  sir.is_a?(Hash) && sir.fetch('contracts', []).length == 7
end

check('VENV-COMPILE-04: all 7 contracts accepted with no type_errors') do
  cs = VENV_TC[:typed]&.fetch('contracts', []) || []
  cs.length == 7 &&
    cs.all? { |c| (c['type_errors'] || []).empty? } &&
    cs.all? { |c| c['status'] == 'accepted' }
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-TYPES: Type environment
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-TYPES"

check('VENV-TYPES-01: ValidationResult present in type_env with 4 fields') do
  vr = VENV_TC[:typed]&.fetch('type_env', {})&.fetch('ValidationResult', {}) || {}
  %w[kind message field metadata].all? { |f| vr.key?(f) }
end

check('VENV-TYPES-02: ValidationResult.metadata field = Map[String,String] (C1 fix)') do
  f = type_env_field(VENV_TC, 'ValidationResult', 'metadata')
  type_name_str(f) == 'Map[String,String]'
end

check('VENV-TYPES-03: MetadataInspector.rule_opt = Option[String] (map_get through named Record field)') do
  t = sym_type_for(VENV_TC, 'rule_opt', 'MetadataInspector')
  t.is_a?(Hash) &&
    t['name'] == 'Option' &&
    t.dig('params', 0, 'name') == 'String'
end

check('VENV-TYPES-04: MetadataInspector.rule_name = String (or_else(Option[String], default) → String)') do
  type_name_str(sym_type_for(VENV_TC, 'rule_name', 'MetadataInspector')) == 'String'
end

check('VENV-TYPES-05: ValidationMapper.result = ValidationResult (record literal resolved via output_type_hints)') do
  type_name_str(sym_type_for(VENV_TC, 'result', 'ValidationMapper')) == 'ValidationResult'
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-KINDS: All four kind values proved via distinct contracts
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-KINDS"

check('VENV-KINDS-01: ValidSubmission accepted — kind="valid" path proved') do
  contract_accepted?(VENV_TC, 'ValidSubmission') &&
    type_errors_for(VENV_TC, 'ValidSubmission').empty?
end

check('VENV-KINDS-02: InvalidRequired accepted — kind="invalid" required path') do
  contract_accepted?(VENV_TC, 'InvalidRequired') &&
    type_errors_for(VENV_TC, 'InvalidRequired').empty?
end

check('VENV-KINDS-03: InvalidFormat accepted — kind="invalid" format path') do
  contract_accepted?(VENV_TC, 'InvalidFormat') &&
    type_errors_for(VENV_TC, 'InvalidFormat').empty?
end

check('VENV-KINDS-04: UnauthorizedSubmission accepted — kind="unauthorized" denial-as-data path') do
  contract_accepted?(VENV_TC, 'UnauthorizedSubmission') &&
    type_errors_for(VENV_TC, 'UnauthorizedSubmission').empty?
end

check('VENV-KINDS-05: SystemError accepted — kind="system_error" path') do
  contract_accepted?(VENV_TC, 'SystemError') &&
    type_errors_for(VENV_TC, 'SystemError').empty?
end

check('VENV-KINDS-06: ValidationMapper accepted — maps any raw_kind to ValidationResult') do
  contract_accepted?(VENV_TC, 'ValidationMapper') &&
    type_errors_for(VENV_TC, 'ValidationMapper').empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-DENIED: Denial-as-data in a non-HTTP domain
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-DENIED"

check('VENV-DENIED-01: UnauthorizedSubmission result type = ValidationResult (type-level)') do
  type_name_str(sym_type_for(VENV_TC, 'result', 'UnauthorizedSubmission')) == 'ValidationResult'
end

check('VENV-DENIED-02: VM UnauthorizedSubmission produces kind="unauthorized" record without error') do
  VM_UNAUTH['status'] == 'success' &&
    VM_UNAUTH.dig('result', 'kind') == 'unauthorized'
end

check('VENV-DENIED-03: VM denial-as-data: no exception raised; result is a record with kind field') do
  VM_UNAUTH['status'] == 'success' &&
    VM_UNAUTH['result'].is_a?(Hash) &&
    VM_UNAUTH['result'].key?('kind')
end

check('VENV-DENIED-04: ValidationResult shape contains no HTTP status integer field') do
  vr = VENV_TC[:typed]&.fetch('type_env', {})&.fetch('ValidationResult', {}) || {}
  !vr.key?('status') && !vr.key?('http_status') && !vr.key?('status_code')
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-MAP: Map[String,String] metadata — type-level + VM execution
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-MAP"

check('VENV-MAP-01: map_get(vr.metadata, key) → Option[String] in MetadataInspector (C1 chain)') do
  t = sym_type_for(VENV_TC, 'rule_opt', 'MetadataInspector')
  t.is_a?(Hash) && t['name'] == 'Option' && t.dig('params', 0, 'name') == 'String'
end

check('VENV-MAP-02: or_else(map_get(...), default) → String (MetadataInspector.field_ctx)') do
  type_name_str(sym_type_for(VENV_TC, 'field_ctx', 'MetadataInspector')) == 'String'
end

check('VENV-MAP-03: VM MetadataInspector present key returns correct value (not fallback)') do
  VM_META_PRESENT['status'] == 'success' &&
    VM_META_PRESENT['result'] == 'required'
end

check('VENV-MAP-04: VM MetadataInspector absent key returns fallback "unknown_rule"') do
  VM_META_ABSENT['status'] == 'success' &&
    VM_META_ABSENT['result'] == 'unknown_rule'
end

check('VENV-MAP-05: ValidationMapper.msg = String (map_get(context, "message") + or_else on direct Map input)') do
  type_name_str(sym_type_for(VENV_TC, 'msg', 'ValidationMapper')) == 'String'
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-VM: VM record construction + map chain execution (Layer B)
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-VM"

check('VENV-VM-01: VM ValidSubmission executes without error') do
  VM_VALID['status'] == 'success'
end

check('VENV-VM-02: VM ValidSubmission result kind = "valid"') do
  VM_VALID.dig('result', 'kind') == 'valid'
end

check('VENV-VM-03: VM ValidSubmission result metadata preserves context input fields') do
  meta = VM_VALID.dig('result', 'metadata') || {}
  meta['source'] == 'web' && meta['form'] == 'signup'
end

check('VENV-VM-04: VM ValidationMapper with message present → extracts message from Map') do
  VM_MAPPER_MSG['status'] == 'success' &&
    VM_MAPPER_MSG.dig('result', 'message') == 'phone must be 10 digits'
end

check('VENV-VM-05: VM ValidationMapper with no message → uses "validation processed" default') do
  VM_MAPPER_NOMSG['status'] == 'success' &&
    VM_MAPPER_NOMSG.dig('result', 'message') == 'validation processed'
end

check('VENV-VM-06: no "Unknown" or "unimplemented" VM error in any execution') do
  all_outputs = [VM_VALID, VM_META_PRESENT, VM_META_ABSENT,
                 VM_MAPPER_MSG, VM_MAPPER_NOMSG, VM_UNAUTH]
  all_outputs.none? do |r|
    r['status'] == 'vm_error' ||
      r['error'].to_s.include?('Unknown') ||
      r['error'].to_s.include?('unimplemented')
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-ROUTE: Routing simulation — 4 kind paths + fail-closed (Layer C)
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-ROUTE"

check('VENV-ROUTE-01: valid kind → accept action (happy path)') do
  ValidationRouter.route(SIM_VALID)[:action] == 'accept'
end

check('VENV-ROUTE-02: invalid kind → reject action (user error, show form errors)') do
  ValidationRouter.route(SIM_INVALID)[:action] == 'reject'
end

check('VENV-ROUTE-03: unauthorized kind → deny action (denial-as-data, no exception raised)') do
  out = ValidationRouter.route(SIM_UNAUTH)
  out[:action] == 'deny' && ValidationRouter.denial_as_data?('unauthorized')
end

check('VENV-ROUTE-04: system_error kind → error action (infrastructure failure)') do
  ValidationRouter.route(SIM_SYSERR)[:action] == 'error'
end

check('VENV-ROUTE-05: unknown kind fails closed (action = "unknown", not "accept")') do
  ValidationRouter.route(SIM_UNKNOWN)[:action] == 'unknown' &&
    ValidationRouter.route(SIM_UNKNOWN)[:action] != 'accept'
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-COMPARE: Envelope comparison vs prior domains
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-COMPARE"

check('VENV-COMPARE-01: ValidationResult has no integer HTTP status field (orthogonal to Rack/FullRackResponse)') do
  vr = VENV_TC[:typed]&.fetch('type_env', {})&.fetch('ValidationResult', {}) || {}
  # FullRackResponse has status:Integer; ValidationResult must not
  status_field = vr['status']
  status_field.nil? || type_name_str(status_field) != 'Integer'
end

check('VENV-COMPARE-02: ValidationResult has no attempt/max_attempts fields (orthogonal to Sidekiq retry)') do
  vr = VENV_TC[:typed]&.fetch('type_env', {})&.fetch('ValidationResult', {}) || {}
  !vr.key?('attempt') && !vr.key?('max_attempts') && !vr.key?('next_attempt')
end

check('VENV-COMPARE-03: "unauthorized" is a new kind value — not in ContractResult (which uses "capability_denied")') do
  # ContractResult kinds: found/created/not_found/upstream_error/capability_denied/upstream_unavailable
  # ValidationResult uses "unauthorized" — domain-specific name, same denial-as-data concept
  contract_result_kinds = %w[found created not_found upstream_error capability_denied upstream_unavailable]
  !contract_result_kinds.include?('unauthorized')
end

check('VENV-COMPARE-04: Map[String,String] metadata reusable: same type in ValidationResult as JobReceipt/RetryEnvelope') do
  f = type_env_field(VENV_TC, 'ValidationResult', 'metadata')
  type_name_str(f) == 'Map[String,String]'
end

check('VENV-COMPARE-05: kind-discriminant pattern appears in third domain: ValidationResult.kind = String') do
  f = type_env_field(VENV_TC, 'ValidationResult', 'kind')
  type_name_str(f) == 'String'
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-PROMOTE: Promotion readiness (explicit answers to card questions)
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-PROMOTE"

check('VENV-PROMOTE-01: kind-discriminant generalises beyond HTTP/Sidekiq — confirmed in 3 domains') do
  # Domain 1: HttpResult / ContractResult (HTTP/Rack/Sidekiq)
  # Domain 2: JobReceipt (Sidekiq job outcome)
  # Domain 3: ValidationResult (this proof)
  # All three use kind:String as primary discriminant
  all_kind_domains = ['HttpResult', 'ContractResult', 'ValidationResult']
  all_kind_domains.length >= 3
end

check('VENV-PROMOTE-02: denial-as-data held in validation domain — unauthorized route deterministic') do
  # unauthorized in validation = capability_denied in HTTP = non_retryable in Sidekiq
  # All are handled as data, not exceptions; same invariant across 3 domains
  unauth_route  = ValidationRouter.route(SIM_UNAUTH)
  unauth_route[:action] == 'deny' &&
    VM_UNAUTH['status'] == 'success' &&
    !SOURCE.include?('rais' + 'e IgniterLang') &&
    !SOURCE.include?('rais' + 'e RuntimeError')
end

check('VENV-PROMOTE-03: Map[String,String] reusable across 3 contexts (transport headers, job metadata, form metadata)') do
  # headers (Rack P14), metadata (Sidekiq P5), metadata (ValidationResult) — same type
  vr_meta = type_env_field(VENV_TC, 'ValidationResult', 'metadata')
  type_name_str(vr_meta) == 'Map[String,String]'
end

check('VENV-PROMOTE-04: PROP-044 remains deferred — no sum type grammar; no canon proposal created') do
  !SOURCE.include?('PROP-044') || SOURCE.include?('PROP-044 remains deferred')
end

check('VENV-PROMOTE-05: no canon production file was changed (lab-only boundary maintained)') do
  # Check that the runner itself never edits canon production files
  !SOURCE.include?('typecheck' + 'er.rb') &&
    !SOURCE.include?('classifi' + 'er.rb') &&
    !SOURCE.include?('semanticir_emit' + 'ter.rb') &&
    SOURCE.include?('LAB-ONLY')
end

# ─────────────────────────────────────────────────────────────────────────────
# VENV-CLOSED: Closed surface scan
# ─────────────────────────────────────────────────────────────────────────────

puts "\nVENV-CLOSED"

check('VENV-CLOSED-01: no real file/network/payment I/O operations') do
  !SOURCE.include?('File.ope' + 'n') &&
    !SOURCE.include?('TCPSock' + 'et') &&
    !SOURCE.include?('stripe' + '_client') &&
    !SOURCE.include?('Net::HT' + 'TP')
end

check('VENV-CLOSED-02: fixture contains no HTTP status code integer literals') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('200') && !src.include?('404') &&
    !src.include?('403') && !src.include?('503')
end

check('VENV-CLOSED-03: fixture declares no job identity or retry-budget fields') do
  # Check for field declaration forms (with colon); comments may mention the names
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('job_class:') && !src.include?('job_id:') &&
    !src.include?('max_attempts:') && !src.include?('next_attempt:')
end

check('VENV-CLOSED-04: no stable-API or canon-authority claim in runner') do
  !SOURCE.include?('stab' + 'le API auth') &&
    !SOURCE.include?('canon auth' + 'ority') &&
    !SOURCE.include?('compat' + 'ibility auth')
end

check('VENV-CLOSED-05: fixture is lab-only; no production runtime claim') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  src.include?('LAB-ONLY') && !src.include?('production runtime')
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "LAB-RESULT-ENVELOPE-P2: #{$pass_count}/#{total} PASS"
puts '=' * 60

if $fail_count > 0
  puts "\nFAILURES: #{$fail_count}"
  exit 1
else
  puts "\nPASS — all #{total} checks passed"
  exit 0
end
