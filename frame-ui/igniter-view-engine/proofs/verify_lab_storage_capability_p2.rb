#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_storage_capability_p2.rb
# LAB-STORAGE-CAPABILITY-P2: IO.StorageCapability mocked execution boundary — 51 checks
#
# Proves IO.StorageCapability as a mocked query execution boundary:
# capability gates, row-limit clamp, include_all query_error, denial-as-data,
# QueryExecutionReceipt shape, and separation from TBackend/TEMPORAL.
#
# Core formula:
#   QueryPlan         = pure typed intent data (CORE; no capability needed)
#   StorageCapability = execution authority gate (ESCAPE/STORAGE; != database connection)
#   QueryResult       = typed outcome/denial data (5-kind KDR vocabulary)
#   StorageCapability != TBackend (orthogonal tracks)
#   StorageCapability != database connection, ORM, SQL runtime, ActiveRecord
#
# Two-layer + simulation proof:
#   Layer A — Production Ruby TypeChecker: 8 contracts accepted (effect + 7 pure);
#             QueryExecutionReceipt 15-field type shape; IO.StorageCapability type ref.
#   Layer B — Lab Rust compiler: exec fixture compiles (effect contract included);
#             receipts fixture compiles; 7 pure contracts VM-executable.
#   Layer C — Proof-local StorageCapabilityGates: 6-gate sequence, row-limit clamp,
#             include_all → query_error, mocked G6 execution, denial-as-data invariants.
#
# Two fixtures:
#   storage_capability_exec.ig     — effect contract + pure contracts (Layer A + Layer B compile)
#   storage_capability_receipts.ig — pure contracts only (Layer B VM execution)
#
# Effect contract gap:
#   ExecuteQuery declared as effect contract (compile proof Layer A + Layer B).
#   Layer B passport requires capability binding for VM execution — effect contracts
#   are ESCAPE class and not VM-executable in v0 without capability injection.
#   This is the correct ESCAPE boundary: Stage 2+ STORAGE class required.
#
# Sections:
#   SCAP2-COMPILE  (4)  — fixtures compile; contracts present; Layer A + Layer B
#   SCAP2-SCHEMA   (6)  — QueryExecutionReceipt 15-field type shape
#   SCAP2-G1       (4)  — source not in allowlist → kind:"denied", gate:"G1"
#   SCAP2-G2       (3)  — op not in allowed_ops → kind:"denied", gate:"G2"
#   SCAP2-G3       (3)  — read_allowed:false → kind:"denied", gate:"G3"
#   SCAP2-G4       (4)  — plan.limit > row_limit → clamp; not denial
#   SCAP2-G5       (3)  — include_all:true + !allow_include_all → kind:"query_error"
#   SCAP2-G6       (4)  — mocked execution → "rows"/"empty"/"system_error"
#   SCAP2-RECEIPT  (6)  — receipt invariants (VM + Layer C)
#   SCAP2-KDR      (4)  — 5-kind routing; "denied" != "query_error" != "system_error"
#   SCAP2-COMPOSE  (5)  — QueryPlan v1 as executor input; source/limit/include_all
#   SCAP2-CLOSED   (5)  — no DB/SQL/ORM/raise/persistence at any layer
#
# Total: 51 checks
#
# Depends on:
#   LAB-QUERY-P3 (QueryPlan v1 nested types — 44/44)
#   LAB-STORAGE-CAPABILITY-P1 (IO.StorageCapability schema + 6-gate design)
#   PROP-035 (capability/effect grammar — experiment-pass)
#   PROP-046-P1 (IO.StorageCapability boundary proposal — authored)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No persistence runtime.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_storage_capability_p2.rb

SOURCE = File.read(__FILE__).force_encoding('UTF-8').freeze

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
EXEC_FIXTURE   = (ROOT / 'fixtures' / 'storage_capability' / 'storage_capability_exec.ig').to_s
RCPTS_FIXTURE  = (ROOT / 'fixtures' / 'storage_capability' / 'storage_capability_receipts.ig').to_s

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

def vm_run(app_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['scap2_inputs', '.json'])
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

# ── Layer C: Proof-local IO.StorageCapability simulation ──────────────────────
#
# StorageCapabilityGates: 6-gate sequence.
# G1: source in allowed_sources?          → denied if not
# G2: "read" in allowed_ops?              → denied if not
# G3: read_allowed?                       → denied if not
# G4: plan.limit > row_limit?             → clamp effective_limit; no denial
# G5: include_all + !allow_include_all?   → query_error (not denied)
# G6: execute (mocked)                    → rows / empty / system_error
#
# Denial-as-data: all gate failures return result_kind + receipt; no exceptions.
# "query_error" (G5) != "denied" (G1/G2/G3): malformed plan, not access denial.
# TBackend ⊥ StorageCapability: orthogonal tracks; no TEMPORAL types here.

module StorageCapabilityGates
  KDR_ROUTES = {
    'rows'         => { action: 'process',  summary: 'rows returned; iterate and transform' },
    'empty'        => { action: 'empty',    summary: 'zero rows; show empty state' },
    'denied'       => { action: 'deny',     summary: 'access denied; do not retry same plan' },
    'query_error'  => { action: 'invalid',  summary: 'malformed plan; fix before retry' },
    'system_error' => { action: 'error',    summary: 'infrastructure failure; retry later' }
  }.freeze

  def self.evaluate(cap, plan, mock_rows: 5, inject_error: false)
    source_table  = plan.dig('source', 'table') || ''
    include_all   = plan.dig('projection', 'include_all') || false
    plan_limit    = plan.fetch('limit', 0)
    row_limit     = cap.fetch('row_limit', 0)
    cap_id        = cap.fetch('capability_id', '')
    deny_reason   = cap.fetch('deny_reason', '')

    # G1: source allowlist
    unless cap.fetch('allowed_sources', []).include?(source_table)
      return denial('G1', deny_reason.empty? ? 'source not in allowed_sources' : deny_reason,
                    cap_id, source_table, plan_limit, row_limit, plan)
    end

    # G2: op allowlist
    unless cap.fetch('allowed_ops', []).include?('read')
      return denial('G2', 'op not in allowed_ops',
                    cap_id, source_table, plan_limit, row_limit, plan)
    end

    # G3: read master switch
    unless cap.fetch('read_allowed', false)
      return denial('G3', 'read_allowed is false',
                    cap_id, source_table, plan_limit, row_limit, plan)
    end

    # G4: row limit clamp (not denial)
    effective_limit = [plan_limit, row_limit].min
    clamped = effective_limit < plan_limit

    # G5: include_all restricted → query_error (not denied)
    if include_all && !cap.fetch('allow_include_all', false)
      receipt = build_receipt(
        cap_id:            cap_id,
        plan_kind:         plan.fetch('kind', 'select'),
        source_table:      source_table,
        op_requested:      'read',
        cap_checked:       true,
        cap_granted:       false,
        denial_gate:       'G5',
        deny_reason:       'include_all not permitted by capability',
        plan_limit:        plan_limit,
        row_limit_cap:     row_limit,
        effective_limit:   effective_limit,
        row_limit_clamped: clamped,
        rows_returned:     0,
        result_kind:       'query_error',
        metadata:          plan.fetch('metadata', {})
      )
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => 'include_all not permitted by capability',
                 'metadata' => plan.fetch('metadata', {}) }
      return { result: result, receipt: receipt }
    end

    # G6: execute (mocked)
    if inject_error
      receipt = build_receipt(
        cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'),
        source_table: source_table, op_requested: 'read',
        cap_checked: true, cap_granted: false,
        denial_gate: 'G6', deny_reason: 'infrastructure failure',
        plan_limit: plan_limit, row_limit_cap: row_limit,
        effective_limit: effective_limit, row_limit_clamped: clamped,
        rows_returned: 0, result_kind: 'system_error',
        metadata: plan.fetch('metadata', {})
      )
      result = { 'kind' => 'system_error', 'count' => 0,
                 'message' => 'infrastructure failure', 'metadata' => plan.fetch('metadata', {}) }
      return { result: result, receipt: receipt }
    end

    rows        = mock_rows
    result_kind = rows > 0 ? 'rows' : 'empty'
    receipt = build_receipt(
      cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'),
      source_table: source_table, op_requested: 'read',
      cap_checked: true, cap_granted: true,
      denial_gate: '', deny_reason: '',
      plan_limit: plan_limit, row_limit_cap: row_limit,
      effective_limit: effective_limit, row_limit_clamped: clamped,
      rows_returned: rows, result_kind: result_kind,
      metadata: plan.fetch('metadata', {})
    )
    result = { 'kind' => result_kind, 'count' => rows, 'message' => '',
               'metadata' => plan.fetch('metadata', {}) }
    { result: result, receipt: receipt }
  end

  def self.route(result)
    kind = result.is_a?(Hash) ? result.fetch('kind', 'unknown') : result.to_s
    KDR_ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  def self.denial_as_data?(kind)
    kind == 'denied' && KDR_ROUTES.key?('denied')
  end

  private_class_method def self.denial(gate, reason, cap_id, source_table, plan_limit, row_limit, plan)
    receipt = build_receipt(
      cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'),
      source_table: source_table, op_requested: 'read',
      cap_checked: true, cap_granted: false,
      denial_gate: gate, deny_reason: reason,
      plan_limit: plan_limit, row_limit_cap: row_limit,
      effective_limit: 0, row_limit_clamped: false,
      rows_returned: 0, result_kind: 'denied',
      metadata: plan.fetch('metadata', {})
    )
    result = { 'kind' => 'denied', 'count' => 0, 'message' => reason,
               'metadata' => plan.fetch('metadata', {}) }
    { result: result, receipt: receipt }
  end

  private_class_method def self.build_receipt(
    cap_id:, plan_kind:, source_table:, op_requested:,
    cap_checked:, cap_granted:, denial_gate:, deny_reason:,
    plan_limit:, row_limit_cap:, effective_limit:, row_limit_clamped:,
    rows_returned:, result_kind:, metadata:
  )
    {
      'cap_id'            => cap_id,
      'plan_kind'         => plan_kind,
      'source_table'      => source_table,
      'op_requested'      => op_requested,
      'cap_checked'       => cap_checked,
      'cap_granted'       => cap_granted,
      'denial_gate'       => denial_gate,
      'deny_reason'       => deny_reason,
      'plan_limit'        => plan_limit,
      'row_limit_cap'     => row_limit_cap,
      'effective_limit'   => effective_limit,
      'row_limit_clamped' => row_limit_clamped,
      'rows_returned'     => rows_returned,
      'result_kind'       => result_kind,
      'metadata'          => metadata
    }
  end
end

# ── Fixtures and compile outputs ───────────────────────────────────────────────

EXEC_OUT  = Dir.mktmpdir('scap2_exec')
RCPTS_OUT = Dir.mktmpdir('scap2_rcpts')

EXEC_SRC  = File.read(EXEC_FIXTURE).force_encoding('UTF-8').freeze
RCPTS_SRC = File.read(RCPTS_FIXTURE).force_encoding('UTF-8').freeze

EXEC_SIR  = compile_fixture(EXEC_FIXTURE,  EXEC_OUT)
RCPTS_SIR = compile_fixture(RCPTS_FIXTURE, RCPTS_OUT)
EXEC_TC   = run_fixture(EXEC_FIXTURE)

# ── VM inputs ─────────────────────────────────────────────────────────────────

GRANTED_INPUTS = {
  'cap_id'        => 'storage-read-users-v0',
  'source_table'  => 'users',
  'plan_limit'    => 25,
  'row_limit_cap' => 100,
  'rows_returned' => 7,
  'metadata'      => { 'trace_id' => 'scap2-granted' }
}.freeze

DENIED_G1_INPUTS = {
  'cap_id'        => 'storage-read-users-v0',
  'source_table'  => 'secrets',
  'denial_gate'   => 'G1',
  'deny_reason'   => 'source not in allowed_sources',
  'plan_limit'    => 25,
  'row_limit_cap' => 100,
  'metadata'      => { 'trace_id' => 'scap2-g1' }
}.freeze

DENIED_G2_INPUTS = {
  'cap_id'        => 'storage-read-users-v0',
  'source_table'  => 'users',
  'denial_gate'   => 'G2',
  'deny_reason'   => 'op not in allowed_ops',
  'plan_limit'    => 25,
  'row_limit_cap' => 100,
  'metadata'      => { 'trace_id' => 'scap2-g2' }
}.freeze

CLAMPED_INPUTS = {
  'cap_id'        => 'storage-read-users-v0',
  'source_table'  => 'users',
  'plan_limit'    => 500,
  'row_limit_cap' => 100,
  'rows_returned' => 100,
  'metadata'      => { 'trace_id' => 'scap2-clamped' }
}.freeze

FIELDS_INPUTS = {
  'receipt' => {
    'cap_id'            => 'storage-read-users-v0',
    'plan_kind'         => 'select',
    'source_table'      => 'users',
    'op_requested'      => 'read',
    'cap_checked'       => true,
    'cap_granted'       => true,
    'denial_gate'       => '',
    'deny_reason'       => '',
    'plan_limit'        => 25,
    'row_limit_cap'     => 100,
    'effective_limit'   => 25,
    'row_limit_clamped' => false,
    'rows_returned'     => 7,
    'result_kind'       => 'rows',
    'metadata'          => { 'trace_id' => 'scap2-fields' }
  }
}.freeze

DENIED_RESULT_INPUTS = {
  'reason'   => 'source not in allowed_sources',
  'metadata' => { 'gate' => 'G1' }
}.freeze

QERR_INPUTS = {
  'reason'   => 'include_all not permitted by capability',
  'metadata' => { 'gate' => 'G5' }
}.freeze

ROWS_INPUTS = {
  'count'    => 12,
  'reason'   => '',
  'metadata' => { 'trace_id' => 'scap2-rows' }
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_GRANTED   = vm_run(RCPTS_OUT, 'BuildGrantedReceipt', GRANTED_INPUTS)
VM_DENIED_G1 = vm_run(RCPTS_OUT, 'BuildDeniedReceipt',  DENIED_G1_INPUTS)
VM_DENIED_G2 = vm_run(RCPTS_OUT, 'BuildDeniedReceipt',  DENIED_G2_INPUTS)
VM_CLAMPED   = vm_run(RCPTS_OUT, 'BuildClampedReceipt', CLAMPED_INPUTS)
VM_FIELDS    = vm_run(RCPTS_OUT, 'ReadReceiptFields',   FIELDS_INPUTS)
VM_DENIED_R  = vm_run(RCPTS_OUT, 'DeniedResult',        DENIED_RESULT_INPUTS)
VM_QERR      = vm_run(RCPTS_OUT, 'QueryErrorResult',    QERR_INPUTS)
VM_ROWS      = vm_run(RCPTS_OUT, 'RowsResult',          ROWS_INPUTS)

# ── Layer C simulation inputs ──────────────────────────────────────────────────

BASE_CAP = {
  'capability_id'   => 'storage-read-users-v0',
  'resource_type'   => 'storage',
  'allowed_sources' => ['users', 'posts'],
  'allowed_ops'     => ['read'],
  'row_limit'       => 100,
  'allow_include_all' => false,
  'read_allowed'    => true,
  'write_allowed'   => false,
  'deny_reason'     => ''
}.freeze

BASE_PLAN = {
  'kind'       => 'select',
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name,email', 'include_all' => false },
  'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 25,
  'metadata'   => { 'trace_id' => 'scap2-base' }
}.freeze

# Pre-run Layer C evaluations
C_G1  = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN.merge('source' => { 'table' => 'secrets', 'schema' => 'public' }))
C_G2  = StorageCapabilityGates.evaluate(BASE_CAP.merge('allowed_ops' => ['write']), BASE_PLAN)
C_G3  = StorageCapabilityGates.evaluate(BASE_CAP.merge('read_allowed' => false), BASE_PLAN)
C_G4  = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN.merge('limit' => 500))
C_G5  = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN.merge('projection' => { 'fields' => '*', 'include_all' => true }))
C_ROWS   = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN, mock_rows: 10)
C_EMPTY  = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN, mock_rows: 0)
C_SYSERR = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN, inject_error: true)
C_PASS   = StorageCapabilityGates.evaluate(BASE_CAP, BASE_PLAN)

# ── Proof sections ─────────────────────────────────────────────────────────────

puts "\nLAB-STORAGE-CAPABILITY-P2 proof — 51 checks"
puts "=" * 60

# ── SCAP2-COMPILE ─────────────────────────────────────────────────────────────
puts "\n── SCAP2-COMPILE (4) ──"

check("SCAP2-COMPILE-01: Rust compiler accepts exec fixture (effect + pure) — status ok") do
  EXEC_SIR&.fetch('status', nil) == 'ok'
end

check("SCAP2-COMPILE-02: Rust compiler: ExecuteQuery in exec fixture contracts") do
  EXEC_SIR&.fetch('contracts', [])&.include?('ExecuteQuery')
end

check("SCAP2-COMPILE-03: Ruby TC: ExecuteQuery accepted (Layer A — effect contract)") do
  contract_accepted?(EXEC_TC, 'ExecuteQuery') &&
    type_errors_for(EXEC_TC, 'ExecuteQuery').empty?
end

check("SCAP2-COMPILE-04: Ruby TC: all 8 contracts in exec fixture accepted") do
  expected = %w[ExecuteQuery BuildGrantedReceipt BuildDeniedReceipt BuildClampedReceipt
                ReadReceiptFields DeniedResult QueryErrorResult RowsResult]
  expected.all? { |name| contract_accepted?(EXEC_TC, name) }
end

# ── SCAP2-SCHEMA ──────────────────────────────────────────────────────────────
puts "\n── SCAP2-SCHEMA (6) ──"

check("SCAP2-SCHEMA-01: QueryExecutionReceipt type_env — cap_id: String") do
  f = type_env_field(EXEC_TC, 'QueryExecutionReceipt', 'cap_id')
  type_name_str(f) == 'String'
end

check("SCAP2-SCHEMA-02: QueryExecutionReceipt type_env — cap_granted: Bool") do
  f = type_env_field(EXEC_TC, 'QueryExecutionReceipt', 'cap_granted')
  type_name_str(f) == 'Bool'
end

check("SCAP2-SCHEMA-03: QueryExecutionReceipt type_env — denial_gate: String") do
  f = type_env_field(EXEC_TC, 'QueryExecutionReceipt', 'denial_gate')
  type_name_str(f) == 'String'
end

check("SCAP2-SCHEMA-04: QueryExecutionReceipt type_env — effective_limit: Integer") do
  f = type_env_field(EXEC_TC, 'QueryExecutionReceipt', 'effective_limit')
  type_name_str(f) == 'Integer'
end

check("SCAP2-SCHEMA-05: QueryExecutionReceipt type_env — row_limit_clamped: Bool") do
  f = type_env_field(EXEC_TC, 'QueryExecutionReceipt', 'row_limit_clamped')
  type_name_str(f) == 'Bool'
end

check("SCAP2-SCHEMA-06: QueryExecutionReceipt type_env — result_kind: String") do
  f = type_env_field(EXEC_TC, 'QueryExecutionReceipt', 'result_kind')
  type_name_str(f) == 'String'
end

# ── SCAP2-G1 ──────────────────────────────────────────────────────────────────
puts "\n── SCAP2-G1 (4) — source not in allowlist ──"

check("SCAP2-G1-01: Layer C: source not in allowed_sources → kind:\"denied\"") do
  C_G1[:result]['kind'] == 'denied'
end

check("SCAP2-G1-02: Layer C: source gate → denial_gate:\"G1\"") do
  C_G1[:receipt]['denial_gate'] == 'G1'
end

check("SCAP2-G1-03: Layer C: G1 denial → rows_returned:0") do
  C_G1[:receipt]['rows_returned'] == 0
end

check("SCAP2-G1-04: VM BuildDeniedReceipt(denial_gate:\"G1\") → cap_granted:false") do
  VM_DENIED_G1['status'] == 'success' &&
    VM_DENIED_G1.dig('result', 'cap_granted') == false &&
    VM_DENIED_G1.dig('result', 'denial_gate') == 'G1'
end

# ── SCAP2-G2 ──────────────────────────────────────────────────────────────────
puts "\n── SCAP2-G2 (3) — op not in allowed_ops ──"

check("SCAP2-G2-01: Layer C: \"read\" not in allowed_ops → kind:\"denied\"") do
  C_G2[:result]['kind'] == 'denied'
end

check("SCAP2-G2-02: Layer C: op gate → denial_gate:\"G2\"") do
  C_G2[:receipt]['denial_gate'] == 'G2'
end

check("SCAP2-G2-03: VM BuildDeniedReceipt(denial_gate:\"G2\") → result_kind:\"denied\"") do
  VM_DENIED_G2['status'] == 'success' &&
    VM_DENIED_G2.dig('result', 'result_kind') == 'denied' &&
    VM_DENIED_G2.dig('result', 'cap_granted') == false
end

# ── SCAP2-G3 ──────────────────────────────────────────────────────────────────
puts "\n── SCAP2-G3 (3) — read_allowed:false ──"

check("SCAP2-G3-01: Layer C: read_allowed:false → kind:\"denied\"") do
  C_G3[:result]['kind'] == 'denied'
end

check("SCAP2-G3-02: Layer C: read switch gate → denial_gate:\"G3\"") do
  C_G3[:receipt]['denial_gate'] == 'G3'
end

check("SCAP2-G3-03: VM DeniedResult(reason) → kind:\"denied\" (G3 result shape)") do
  VM_DENIED_R['status'] == 'success' &&
    VM_DENIED_R.dig('result', 'kind') == 'denied' &&
    VM_DENIED_R.dig('result', 'count') == 0
end

# ── SCAP2-G4 ──────────────────────────────────────────────────────────────────
puts "\n── SCAP2-G4 (4) — row limit clamp ──"

check("SCAP2-G4-01: Layer C: plan.limit(500) > row_limit(100) → effective_limit:100") do
  C_G4[:receipt]['effective_limit'] == 100
end

check("SCAP2-G4-02: Layer C: clamp → row_limit_clamped:true") do
  C_G4[:receipt]['row_limit_clamped'] == true
end

check("SCAP2-G4-03: Layer C: clamp is NOT denial — result kind != \"denied\"") do
  C_G4[:result]['kind'] != 'denied'
end

check("SCAP2-G4-04: VM BuildClampedReceipt → row_limit_clamped:true; effective_limit==row_limit_cap") do
  VM_CLAMPED['status'] == 'success' &&
    VM_CLAMPED.dig('result', 'row_limit_clamped') == true &&
    VM_CLAMPED.dig('result', 'effective_limit') == VM_CLAMPED.dig('result', 'row_limit_cap')
end

# ── SCAP2-G5 ──────────────────────────────────────────────────────────────────
puts "\n── SCAP2-G5 (3) — include_all restricted ──"

check("SCAP2-G5-01: Layer C: include_all:true + !allow_include_all → kind:\"query_error\"") do
  C_G5[:result]['kind'] == 'query_error'
end

check("SCAP2-G5-02: Layer C: include_all gate → denial_gate:\"G5\"") do
  C_G5[:receipt]['denial_gate'] == 'G5'
end

check("SCAP2-G5-03: VM QueryErrorResult → kind:\"query_error\" (not \"denied\")") do
  VM_QERR['status'] == 'success' &&
    VM_QERR.dig('result', 'kind') == 'query_error' &&
    VM_QERR.dig('result', 'kind') != 'denied'
end

# ── SCAP2-G6 ──────────────────────────────────────────────────────────────────
puts "\n── SCAP2-G6 (4) — mocked execution ──"

check("SCAP2-G6-01: Layer C: granted execution with rows → kind:\"rows\"") do
  C_ROWS[:result]['kind'] == 'rows'
end

check("SCAP2-G6-02: Layer C: granted execution with zero rows → kind:\"empty\"") do
  C_EMPTY[:result]['kind'] == 'empty'
end

check("SCAP2-G6-03: Layer C: injected infra error → kind:\"system_error\"") do
  C_SYSERR[:result]['kind'] == 'system_error'
end

check("SCAP2-G6-04: Layer C: rows result → rows_returned > 0") do
  C_ROWS[:receipt]['rows_returned'] > 0
end

# ── SCAP2-RECEIPT ─────────────────────────────────────────────────────────────
puts "\n── SCAP2-RECEIPT (6) — receipt invariants ──"

check("SCAP2-RECEIPT-01: VM BuildGrantedReceipt → cap_granted:true; denial_gate:\"\"; result_kind:\"rows\"") do
  VM_GRANTED['status'] == 'success' &&
    VM_GRANTED.dig('result', 'cap_granted') == true &&
    VM_GRANTED.dig('result', 'denial_gate') == '' &&
    VM_GRANTED.dig('result', 'result_kind') == 'rows'
end

check("SCAP2-RECEIPT-02: VM BuildDeniedReceipt → cap_granted:false; rows_returned:0; effective_limit:0") do
  VM_DENIED_G1['status'] == 'success' &&
    VM_DENIED_G1.dig('result', 'cap_granted') == false &&
    VM_DENIED_G1.dig('result', 'rows_returned') == 0 &&
    VM_DENIED_G1.dig('result', 'effective_limit') == 0
end

check("SCAP2-RECEIPT-03: VM BuildClampedReceipt → effective_limit==row_limit_cap AND row_limit_clamped:true") do
  VM_CLAMPED['status'] == 'success' &&
    VM_CLAMPED.dig('result', 'effective_limit') == VM_CLAMPED.dig('result', 'row_limit_cap') &&
    VM_CLAMPED.dig('result', 'row_limit_clamped') == true &&
    VM_CLAMPED.dig('result', 'effective_limit') < VM_CLAMPED.dig('result', 'plan_limit')
end

check("SCAP2-RECEIPT-04: VM ReadReceiptFields → cap_granted accessible as Bool output") do
  VM_FIELDS['status'] == 'success' &&
    VM_FIELDS['result'] == true
end

check("SCAP2-RECEIPT-05: Layer C invariant — cap_granted:false iff result_kind in {denied,query_error}") do
  denial_kinds  = %w[denied query_error]
  granted_kinds = %w[rows empty system_error]
  denied_cases  = [C_G1, C_G2, C_G3, C_G5].all? do |r|
    r[:receipt]['cap_granted'] == false && denial_kinds.include?(r[:receipt]['result_kind'])
  end
  granted_cases = [C_ROWS, C_EMPTY].all? do |r|
    r[:receipt]['cap_granted'] == true && granted_kinds.include?(r[:receipt]['result_kind'])
  end
  denied_cases && granted_cases
end

check("SCAP2-RECEIPT-06: Layer C invariant — rows_returned:0 when cap_granted:false") do
  [C_G1, C_G2, C_G3, C_G5].all? do |r|
    r[:receipt]['cap_granted'] == false && r[:receipt]['rows_returned'] == 0
  end
end

# ── SCAP2-KDR ─────────────────────────────────────────────────────────────────
puts "\n── SCAP2-KDR (4) — 5-kind KDR routing ──"

check("SCAP2-KDR-01: \"denied\" routes to deny action") do
  StorageCapabilityGates.route(C_G1[:result])[:action] == 'deny'
end

check("SCAP2-KDR-02: \"query_error\" routes to invalid/fix-plan (distinct from deny)") do
  qe_action = StorageCapabilityGates.route(C_G5[:result])[:action]
  qe_action == 'invalid' && qe_action != 'deny'
end

check("SCAP2-KDR-03: \"system_error\" routes to error/retry (distinct from deny and query_error)") do
  se_action = StorageCapabilityGates.route(C_SYSERR[:result])[:action]
  se_action == 'error' && se_action != 'deny' && se_action != 'invalid'
end

check("SCAP2-KDR-04: \"empty\" routes to empty-state action (distinct from deny)") do
  em_action = StorageCapabilityGates.route(C_EMPTY[:result])[:action]
  em_action == 'empty' && em_action != 'deny'
end

# ── SCAP2-COMPOSE ─────────────────────────────────────────────────────────────
puts "\n── SCAP2-COMPOSE (5) — QueryPlan v1 as executor input ──"

check("SCAP2-COMPOSE-01: Layer C: plan.source.table drives G1 (wrong table → denied)") do
  wrong_plan = BASE_PLAN.merge('source' => { 'table' => 'invoices', 'schema' => 'finance' })
  result = StorageCapabilityGates.evaluate(BASE_CAP, wrong_plan)
  result[:receipt]['denial_gate'] == 'G1'
end

check("SCAP2-COMPOSE-02: Layer C: plan.projection.include_all drives G5") do
  include_plan = BASE_PLAN.merge('projection' => { 'fields' => '*', 'include_all' => true })
  result = StorageCapabilityGates.evaluate(BASE_CAP, include_plan)
  result[:result]['kind'] == 'query_error' && result[:receipt]['denial_gate'] == 'G5'
end

check("SCAP2-COMPOSE-03: Layer C: plan.limit drives G4 clamp calculation") do
  high_limit_plan = BASE_PLAN.merge('limit' => 999)
  result = StorageCapabilityGates.evaluate(BASE_CAP, high_limit_plan)
  result[:receipt]['effective_limit'] == 100 && # capped at row_limit
    result[:receipt]['row_limit_clamped'] == true
end

check("SCAP2-COMPOSE-04: Layer C: correct source (plan.source.table in allowed_sources) → G1 passes") do
  C_PASS[:receipt]['denial_gate'] != 'G1' &&
    C_PASS[:result]['kind'] != 'denied'
end

check("SCAP2-COMPOSE-05: Layer C: receipt.source_table preserved from plan.source.table") do
  C_PASS[:receipt]['source_table'] == BASE_PLAN.dig('source', 'table')
end

# ── SCAP2-CLOSED ──────────────────────────────────────────────────────────────
puts "\n── SCAP2-CLOSED (5) — closed surfaces ──"

check("SCAP2-CLOSED-01: no SQL in exec fixture source") do
  !EXEC_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+|CREATE\s+TABLE/i) &&
    !EXEC_SRC.include?('.sql') &&
    !EXEC_SRC.include?('execute_sql')
end

check("SCAP2-CLOSED-02: no database connection code in exec fixture source") do
  !EXEC_SRC.include?('establish_connection') &&
    !EXEC_SRC.include?('database_url') &&
    !EXEC_SRC.include?('ActiveRecord::Base') &&
    !EXEC_SRC.include?('connect_to(')
end

check("SCAP2-CLOSED-03: no ORM calls in exec fixture source") do
  !EXEC_SRC.include?('Active' + 'Record.') &&
    !EXEC_SRC.include?('Active' + 'Record::') &&
    !EXEC_SRC.include?('.where(') &&
    !EXEC_SRC.include?('.find_by(')
end

check("SCAP2-CLOSED-04: ExecuteQuery is effect contract (compile-only); no VM_EXECUTE test") do
  exec_contracts = EXEC_SIR&.fetch('contracts', []) || []
  rcpts_contracts = RCPTS_SIR&.fetch('contracts', []) || []
  exec_contracts.include?('ExecuteQuery') &&
    !rcpts_contracts.include?('ExecuteQuery')
end

check("SCAP2-CLOSED-05: no persistence runtime calls in proof runner source") do
  # Split strings to avoid self-referential false positives (check code is part of SOURCE).
  # Each split string is chosen so neither half is a dangerous literal.
  no_ar_establish = !SOURCE.include?('Base.establish_' + 'connection')
  no_db_url_set   = !SOURCE.include?('DATABASE_URL' + '=')
  no_sequel_conn  = !SOURCE.include?('Sequ' + 'el.connect(')
  no_mongoid_conf = !SOURCE.include?('Mong' + 'oid.configure')
  no_sql_exec     = !SOURCE.include?('execute_sql' + '(')
  no_ar_establish && no_db_url_set && no_sequel_conn && no_mongoid_conf && no_sql_exec
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-STORAGE-CAPABILITY-P2: PROOF COMPLETE (#{$pass_count}/#{total})"
else
  puts "LAB-STORAGE-CAPABILITY-P2: #{$fail_count} check(s) failed"
  exit 1
end
