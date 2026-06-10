#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_execute_query_p1.rb
# LAB-EXECUTE-QUERY-P1 — 57 checks
#
# Proves the first executable Stage 2+ query path: an ExecuteQuery effect
# contract receives a QueryPlan plus an IO.StorageCapability-shaped authority
# object, applies the 6-gate sequence, and returns a typed QueryResult +
# QueryExecutionReceipt using mocked storage data only.
#
# Core formula:
#   ExecuteQuery v0 = QueryPlan + IO.StorageCapability authority → QueryResult
#   ExecuteQuery v0 ≠ SQL execution / ORM / database runtime
#   IO.StorageCapability (ESCAPE class) requires capability injection for VM.
#   Stage 2+ STORAGE class required for live execution.
#
# Three-layer proof:
#   Layer A — Ruby TypeChecker: 5 contracts in capability fixture (effect + pure);
#             12 contracts in receipts fixture (pure only); all accepted, zero type_errors.
#             QueryExecutionReceipt 15-field shape; StorageCapability 8-field shape.
#   Layer B — Lab Rust compiler: capability fixture compiles (effect contract included);
#             receipts fixture compiles; 12 pure contracts VM-executable.
#             Rust SIR: BuildQueryPlanInline.filters typed Collection[FilterPredicate].
#   Layer C — Proof-local ExecuteQuerySim: 6-gate sequence, row-limit clamp,
#             include_all → query_error, mocked G6 execution, denial-as-data.
#
# Two fixtures:
#   execute_query_capability.ig  — effect contract + 4 pure (Layer A + Layer B compile)
#   execute_query_receipts.ig    — 12 pure contracts (Layer B VM; SIR type checks)
#
# Effect contract gap (B1):
#   ExecuteQuery declared as effect contract (Layer A + Layer B compile proof).
#   VM requires capability passport injection — effect contracts are ESCAPE class
#   and not VM-executable in v0 without capability binding.
#   This is the correct boundary: Stage 2+ STORAGE class required.
#
# Sections:
#   EXECQ-COMPILE  (5)  — fixtures compile; contracts present; Layer A accepted
#   EXECQ-SHAPE    (8)  — QueryExecutionReceipt / QueryPlan / StorageCapability shapes
#   EXECQ-GATES    (6)  — Layer C gate simulation (G1–G6)
#   EXECQ-RECEIPT  (7)  — receipt invariants (VM + Layer C)
#   EXECQ-VM       (8)  — Layer B VM execution (12 contracts)
#   EXECQ-MAP      (4)  — map_get + or_else chain on result.metadata
#   EXECQ-ARRAY    (4)  — inline array Collection[FilterPredicate] (Rust SIR)
#   EXECQ-COMPOSE  (5)  — plan field → gate input composition
#   EXECQ-CLOSED   (5)  — no DB/SQL/ORM/raise/persistence at any layer
#   EXECQ-GAP      (5)  — boundary findings (ESCAPE gap, TBackend, KDR, write CLOSED)
#
# Total: 57 checks
#
# Depends on:
#   LAB-QUERY-P3 (QueryPlan v1 — 44/44)
#   LAB-STORAGE-CAPABILITY-P1 (IO.StorageCapability schema + 6-gate design)
#   LAB-STORAGE-CAPABILITY-P2 (gate receipts proof — 51/51)
#   LAB-TC-ARRAY-P2 (Collection[FilterPredicate] from record-field context)
#   PROP-035 (capability/effect grammar), PROP-046-P1 (boundary proposal)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_execute_query_p1.rb

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
CAP_FIXTURE    = (ROOT / 'fixtures' / 'query_execution' / 'execute_query_capability.ig').to_s
RCPTS_FIXTURE  = (ROOT / 'fixtures' / 'query_execution' / 'execute_query_receipts.ig').to_s

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

def contract_accepted?(result, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  c&.fetch('status', nil) == 'accepted'
end

def type_errors_for(result, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  c&.fetch('type_errors', []) || []
end

def type_env_field(result, type_name, field_name)
  result[:typed]&.fetch('type_env', {})
                &.fetch(type_name, {})
                &.fetch(field_name, nil)
end

def type_name_str(t)
  return t.to_s unless t.is_a?(Hash)
  name   = t['name'] || t['kind'] || '?'
  params = Array(t['params'])
  return name if params.empty?
  "#{name}[#{params.map { |p| type_name_str(p) }.join(',')}]"
end

def sym_type_for(result, sym_name, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  s = c&.fetch('symbols', [])&.find { |s| s['name'] == sym_name }
  s&.fetch('type', nil)
end

# ── Layer B: Lab Rust compiler + VM helpers ────────────────────────────────────
#
# compile_path: compiles a fixture and reads per-contract JSON files from
# out_dir/contracts/*.json, giving access to compute_nodes[].type_tag and
# output_ports[].type_tag (Rust SIR). Also returns the top-level report and
# out_dir for VM execution.

def compile_path(path, tag = 'execq')
  out_dir = Dir.mktmpdir(tag)
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN, 'compile', path.to_s, '--out', out_dir.to_s, '--json'
  )
  stdout = stdout.force_encoding('UTF-8') if stdout
  report = (stdout && !stdout.strip.empty?) ? JSON.parse(stdout.strip) : nil
  contracts = {}
  Dir.glob(File.join(out_dir, 'contracts', '*.json')).each do |f|
    c = JSON.parse(File.read(f, encoding: 'UTF-8'))
    contracts[c['name']] = c if c.is_a?(Hash) && c['name']
  end
  { report: report, out_dir: out_dir, contracts: contracts }
rescue => e
  { report: nil, out_dir: nil, contracts: {}, error: e.message }
end

def diagnostics(res); res[:report]&.fetch('diagnostics', []) || []; end
def status(res);      res[:report]&.fetch('status', nil); end
def contract_names(res); res[:report]&.fetch('contracts', []) || []; end

def compute_type_tag(res, contract, node)
  c = res[:contracts][contract]
  return nil unless c
  n = (c['compute_nodes'] || []).find { |x| x['name'] == node }
  n&.fetch('type_tag', nil)
end

def output_type_tag(res, contract, port)
  c = res[:contracts][contract]
  return nil unless c
  p = (c['output_ports'] || []).find { |x| x['name'] == port }
  p&.fetch('type_tag', nil)
end

def vm_run(out_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['execq_inputs', '.json'])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _status = Open3.capture3(
    VM_BIN, 'run',
    '--contract', out_dir.to_s,
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
# ExecuteQuerySim: 6-gate sequence.
# G1: plan.source.table in cap.allowed_sources?   → denied if not
# G2: "read"           in cap.allowed_ops?         → denied if not
# G3: cap.read_allowed == true?                    → denied if not
# G4: plan.limit > cap.row_limit?                  → clamp effective_limit; NOT denial
# G5: include_all + !cap.allow_include_all?        → query_error (NOT denied)
# G6: execute (mocked)                             → rows / empty / system_error
#
# Denial-as-data: all gate failures return typed result; no exceptions raised.
# "query_error" (G5) != "denied" (G1/G2/G3): malformed plan, not access denial.
# G4 clamp ≠ denial: cap_granted stays true after clamp.
# TBackend ⊥ StorageCapability: orthogonal tracks; no TEMPORAL types involved.

module ExecuteQuerySim
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
    cap_id        = cap.fetch('cap_id', '')
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
        cap_id:            cap_id,
        plan_kind:         plan.fetch('kind', 'select'),
        source_table:      source_table,
        op_requested:      'read',
        cap_checked:       true,
        cap_granted:       false,
        denial_gate:       'G6',
        deny_reason:       'infrastructure failure',
        plan_limit:        plan_limit,
        row_limit_cap:     row_limit,
        effective_limit:   effective_limit,
        row_limit_clamped: clamped,
        rows_returned:     0,
        result_kind:       'system_error',
        metadata:          plan.fetch('metadata', {})
      )
      result = { 'kind' => 'system_error', 'count' => 0,
                 'message' => 'infrastructure failure',
                 'metadata' => plan.fetch('metadata', {}) }
      return { result: result, receipt: receipt }
    end

    rows        = mock_rows
    result_kind = rows > 0 ? 'rows' : 'empty'
    receipt = build_receipt(
      cap_id:            cap_id,
      plan_kind:         plan.fetch('kind', 'select'),
      source_table:      source_table,
      op_requested:      'read',
      cap_checked:       true,
      cap_granted:       true,
      denial_gate:       '',
      deny_reason:       '',
      plan_limit:        plan_limit,
      row_limit_cap:     row_limit,
      effective_limit:   effective_limit,
      row_limit_clamped: clamped,
      rows_returned:     rows,
      result_kind:       result_kind,
      metadata:          plan.fetch('metadata', {})
    )
    result = { 'kind' => result_kind, 'count' => rows, 'message' => '',
               'metadata' => plan.fetch('metadata', {}) }
    { result: result, receipt: receipt }
  end

  def self.route(result)
    kind = result.is_a?(Hash) ? result.fetch('kind', 'unknown') : result.to_s
    KDR_ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  private_class_method def self.denial(gate, reason, cap_id, source_table, plan_limit, row_limit, plan)
    receipt = build_receipt(
      cap_id:            cap_id,
      plan_kind:         plan.fetch('kind', 'select'),
      source_table:      source_table,
      op_requested:      'read',
      cap_checked:       true,
      cap_granted:       false,
      denial_gate:       gate,
      deny_reason:       reason,
      plan_limit:        plan_limit,
      row_limit_cap:     row_limit,
      effective_limit:   0,
      row_limit_clamped: false,
      rows_returned:     0,
      result_kind:       'denied',
      metadata:          plan.fetch('metadata', {})
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

# ── Compile fixtures ───────────────────────────────────────────────────────────

CAP_SIR   = compile_path(CAP_FIXTURE,   'execq_cap')
RCPTS_SIR = compile_path(RCPTS_FIXTURE, 'execq_rcpts')
CAP_TC    = run_fixture(CAP_FIXTURE)
RCPTS_TC  = run_fixture(RCPTS_FIXTURE)

CAP_SRC   = File.read(CAP_FIXTURE).force_encoding('UTF-8').freeze
RCPTS_SRC = File.read(RCPTS_FIXTURE).force_encoding('UTF-8').freeze

# ── VM inputs ──────────────────────────────────────────────────────────────────

PLAN_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name', 'include_all' => false },
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 50,
  'metadata'   => { 'source' => 'api', 'trace_id' => 'execq-plan' }
}.freeze

CAP_INPUTS = {
  'cap_id'            => 'cap-execq-v0',
  'allowed_sources'   => ['users', 'posts'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

ALLOWED_RECEIPT_INPUTS = {
  'cap_id'        => 'cap-execq-v0',
  'source_table'  => 'users',
  'plan_limit'    => 50,
  'row_limit_cap' => 100,
  'rows_returned' => 5,
  'metadata'      => { 'trace_id' => 'execq-allowed' }
}.freeze

DENIED_G1_RECEIPT_INPUTS = {
  'cap_id'        => 'cap-execq-v0',
  'source_table'  => 'secrets',
  'denial_gate'   => 'G1',
  'deny_reason'   => 'source not in allowed_sources',
  'plan_limit'    => 50,
  'row_limit_cap' => 100,
  'metadata'      => { 'trace_id' => 'execq-g1' }
}.freeze

CLAMPED_RECEIPT_INPUTS = {
  'cap_id'        => 'cap-execq-v0',
  'source_table'  => 'users',
  'plan_limit'    => 200,
  'row_limit_cap' => 100,
  'rows_returned' => 100,
  'metadata'      => { 'trace_id' => 'execq-clamped' }
}.freeze

RECEIPT_READER_INPUTS = {
  'receipt' => {
    'cap_id'            => 'cap-execq-v0',
    'plan_kind'         => 'select',
    'source_table'      => 'users',
    'op_requested'      => 'read',
    'cap_checked'       => true,
    'cap_granted'       => true,
    'denial_gate'       => '',
    'deny_reason'       => '',
    'plan_limit'        => 50,
    'row_limit_cap'     => 100,
    'effective_limit'   => 50,
    'row_limit_clamped' => false,
    'rows_returned'     => 5,
    'result_kind'       => 'rows',
    'metadata'          => { 'trace_id' => 'execq-fields' }
  }
}.freeze

METADATA_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 5, 'message' => '',
                   'metadata' => { 'source' => 'api', 'trace_id' => 'execq-meta' } },
  'query_key' => 'source'
}.freeze

METADATA_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 0, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

RCPTS_OUT = RCPTS_SIR[:out_dir]

VM_ROWS_R    = RCPTS_OUT ? vm_run(RCPTS_OUT, 'ExecuteQueryRows',
                             { 'row_count' => 5, 'metadata' => { 'trace_id' => 'execq-rows' } }) : {}
VM_EMPTY_R   = RCPTS_OUT ? vm_run(RCPTS_OUT, 'ExecuteQueryEmpty',
                             { 'metadata' => { 'trace_id' => 'execq-empty' } }) : {}
VM_DENIED_R  = RCPTS_OUT ? vm_run(RCPTS_OUT, 'ExecuteQueryDeniedSource',
                             { 'deny_reason' => 'source not in allowed_sources',
                               'metadata' => { 'gate' => 'G1' } }) : {}
VM_QERR_R    = RCPTS_OUT ? vm_run(RCPTS_OUT, 'ExecuteQueryQueryError',
                             { 'metadata' => { 'gate' => 'G5' } }) : {}
VM_SYSERR_R  = RCPTS_OUT ? vm_run(RCPTS_OUT, 'ExecuteQuerySystemError',
                             { 'metadata' => { 'gate' => 'G6' } }) : {}
VM_CAP_R     = RCPTS_OUT ? vm_run(RCPTS_OUT, 'BuildStorageCapability', CAP_INPUTS) : {}
VM_PLAN_R    = RCPTS_OUT ? vm_run(RCPTS_OUT, 'BuildQueryPlanInline', PLAN_INPUTS) : {}
VM_ALLOWED_R = RCPTS_OUT ? vm_run(RCPTS_OUT, 'BuildAllowedReceipt',  ALLOWED_RECEIPT_INPUTS) : {}
VM_DENIED_G1 = RCPTS_OUT ? vm_run(RCPTS_OUT, 'BuildDeniedGateReceipt', DENIED_G1_RECEIPT_INPUTS) : {}
VM_CLAMPED_R = RCPTS_OUT ? vm_run(RCPTS_OUT, 'BuildClampedReceipt',  CLAMPED_RECEIPT_INPUTS) : {}
VM_FIELDS_R  = RCPTS_OUT ? vm_run(RCPTS_OUT, 'QueryReceiptReader',   RECEIPT_READER_INPUTS) : {}
VM_META_HIT  = RCPTS_OUT ? vm_run(RCPTS_OUT, 'QueryMetadataChain',  METADATA_HIT_INPUTS) : {}
VM_META_MISS = RCPTS_OUT ? vm_run(RCPTS_OUT, 'QueryMetadataChain',  METADATA_MISS_INPUTS) : {}

# ── Layer C simulation inputs ──────────────────────────────────────────────────

BASE_CAP = {
  'cap_id'            => 'cap-execq-v0',
  'allowed_sources'   => ['users', 'posts'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

BASE_PLAN = {
  'kind'       => 'select',
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name', 'include_all' => false },
  'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 25,
  'metadata'   => { 'trace_id' => 'execq-c-base' }
}.freeze

C_G1     = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN.merge('source' => { 'table' => 'secrets', 'schema' => 'public' }))
C_G2     = ExecuteQuerySim.evaluate(BASE_CAP.merge('allowed_ops' => ['write']), BASE_PLAN)
C_G3     = ExecuteQuerySim.evaluate(BASE_CAP.merge('read_allowed' => false), BASE_PLAN)
C_G4     = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN.merge('limit' => 500))
C_G5     = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN.merge('projection' => { 'fields' => '*', 'include_all' => true }))
C_ROWS   = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN, mock_rows: 10)
C_EMPTY  = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN, mock_rows: 0)
C_SYSERR = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN, inject_error: true)
C_PASS   = ExecuteQuerySim.evaluate(BASE_CAP, BASE_PLAN)

# ─────────────────────────────────────────────────────────────────────────────
# Proof sections
# ─────────────────────────────────────────────────────────────────────────────

puts "\nLAB-EXECUTE-QUERY-P1 proof — 57 checks"
puts "=" * 60

# ── EXECQ-COMPILE ─────────────────────────────────────────────────────────────
puts "\n── EXECQ-COMPILE (5) — fixtures compile; Layer A accepted ──"

check("EXECQ-COMPILE-01: Rust compiler accepts capability fixture (effect + pure) — status ok") do
  status(CAP_SIR) == 'ok'
end

check("EXECQ-COMPILE-02: Rust compiler: 5 contracts in capability fixture") do
  contract_names(CAP_SIR).length == 5
end

check("EXECQ-COMPILE-03: Rust compiler accepts receipts fixture (pure only) — status ok") do
  status(RCPTS_SIR) == 'ok'
end

check("EXECQ-COMPILE-04: Rust compiler: 12 contracts in receipts fixture") do
  contract_names(RCPTS_SIR).length == 12
end

check("EXECQ-COMPILE-05: Ruby TC: all 5 contracts in capability fixture accepted") do
  %w[ExecuteQuery ReadPlanSource ReadPlanProjection BuildDeniedResult ReadPlanMeta].all? do |name|
    contract_accepted?(CAP_TC, name) && type_errors_for(CAP_TC, name).empty?
  end
end

# ── EXECQ-SHAPE ───────────────────────────────────────────────────────────────
puts "\n── EXECQ-SHAPE (8) — type shapes ──"

check("EXECQ-SHAPE-01: QueryExecutionReceipt.cap_id: String") do
  type_name_str(type_env_field(CAP_TC, 'QueryExecutionReceipt', 'cap_id')) == 'String'
end

check("EXECQ-SHAPE-02: QueryExecutionReceipt.cap_granted: Bool") do
  type_name_str(type_env_field(CAP_TC, 'QueryExecutionReceipt', 'cap_granted')) == 'Bool'
end

check("EXECQ-SHAPE-03: QueryExecutionReceipt.denial_gate: String") do
  type_name_str(type_env_field(CAP_TC, 'QueryExecutionReceipt', 'denial_gate')) == 'String'
end

check("EXECQ-SHAPE-04: QueryExecutionReceipt.effective_limit: Integer") do
  type_name_str(type_env_field(CAP_TC, 'QueryExecutionReceipt', 'effective_limit')) == 'Integer'
end

check("EXECQ-SHAPE-05: QueryExecutionReceipt.row_limit_clamped: Bool") do
  type_name_str(type_env_field(CAP_TC, 'QueryExecutionReceipt', 'row_limit_clamped')) == 'Bool'
end

check("EXECQ-SHAPE-06: QueryExecutionReceipt.result_kind: String") do
  type_name_str(type_env_field(CAP_TC, 'QueryExecutionReceipt', 'result_kind')) == 'String'
end

check("EXECQ-SHAPE-07: QueryPlan.filters: Collection[FilterPredicate]") do
  type_name_str(type_env_field(CAP_TC, 'QueryPlan', 'filters')) == 'Collection[FilterPredicate]'
end

check("EXECQ-SHAPE-08: StorageCapability.allowed_sources: Collection[String]") do
  type_name_str(type_env_field(RCPTS_TC, 'StorageCapability', 'allowed_sources')) == 'Collection[String]'
end

# ── EXECQ-GATES ───────────────────────────────────────────────────────────────
puts "\n── EXECQ-GATES (6) — Layer C gate simulation ──"

check("EXECQ-GATES-01: G1: source not in allowed_sources → kind:\"denied\"") do
  C_G1[:result]['kind'] == 'denied' && C_G1[:receipt]['denial_gate'] == 'G1'
end

check("EXECQ-GATES-02: G2: \"read\" not in allowed_ops → kind:\"denied\"; denial_gate:\"G2\"") do
  C_G2[:result]['kind'] == 'denied' && C_G2[:receipt]['denial_gate'] == 'G2'
end

check("EXECQ-GATES-03: G3: read_allowed:false → kind:\"denied\"; denial_gate:\"G3\"") do
  C_G3[:result]['kind'] == 'denied' && C_G3[:receipt]['denial_gate'] == 'G3'
end

check("EXECQ-GATES-04: G4: plan.limit(500) > row_limit(100) → clamp; result != \"denied\"") do
  C_G4[:receipt]['effective_limit'] == 100 &&
    C_G4[:receipt]['row_limit_clamped'] == true &&
    C_G4[:result]['kind'] != 'denied'
end

check("EXECQ-GATES-05: G5: include_all:true + !allow_include_all → kind:\"query_error\" (not \"denied\")") do
  C_G5[:result]['kind'] == 'query_error' &&
    C_G5[:receipt]['denial_gate'] == 'G5' &&
    C_G5[:result]['kind'] != 'denied'
end

check("EXECQ-GATES-06: G6: inject_error:true → kind:\"system_error\"") do
  C_SYSERR[:result]['kind'] == 'system_error' &&
    C_SYSERR[:receipt]['denial_gate'] == 'G6'
end

# ── EXECQ-RECEIPT ─────────────────────────────────────────────────────────────
puts "\n── EXECQ-RECEIPT (7) — receipt invariants ──"

check("EXECQ-RECEIPT-01: VM BuildAllowedReceipt → cap_granted:true; denial_gate:\"\"; result_kind:\"rows\"") do
  VM_ALLOWED_R['status'] == 'success' &&
    VM_ALLOWED_R.dig('result', 'cap_granted') == true &&
    VM_ALLOWED_R.dig('result', 'denial_gate') == '' &&
    VM_ALLOWED_R.dig('result', 'result_kind') == 'rows'
end

check("EXECQ-RECEIPT-02: VM BuildDeniedGateReceipt(G1) → cap_granted:false; rows_returned:0; effective_limit:0") do
  VM_DENIED_G1['status'] == 'success' &&
    VM_DENIED_G1.dig('result', 'cap_granted') == false &&
    VM_DENIED_G1.dig('result', 'rows_returned') == 0 &&
    VM_DENIED_G1.dig('result', 'effective_limit') == 0
end

check("EXECQ-RECEIPT-03: VM BuildClampedReceipt → row_limit_clamped:true; effective_limit == row_limit_cap") do
  VM_CLAMPED_R['status'] == 'success' &&
    VM_CLAMPED_R.dig('result', 'row_limit_clamped') == true &&
    VM_CLAMPED_R.dig('result', 'effective_limit') == VM_CLAMPED_R.dig('result', 'row_limit_cap') &&
    VM_CLAMPED_R.dig('result', 'effective_limit') < VM_CLAMPED_R.dig('result', 'plan_limit')
end

check("EXECQ-RECEIPT-04: VM QueryReceiptReader → result true (cap_granted field access → Bool)") do
  VM_FIELDS_R['status'] == 'success' && VM_FIELDS_R['result'] == true
end

check("EXECQ-RECEIPT-05: Layer C invariant — cap_granted:false iff result_kind in {denied, query_error}") do
  denial_kinds  = %w[denied query_error]
  granted_kinds = %w[rows empty system_error]
  [C_G1, C_G2, C_G3, C_G5].all? do |r|
    r[:receipt]['cap_granted'] == false && denial_kinds.include?(r[:receipt]['result_kind'])
  end &&
  [C_ROWS, C_EMPTY].all? do |r|
    r[:receipt]['cap_granted'] == true && granted_kinds.include?(r[:receipt]['result_kind'])
  end
end

check("EXECQ-RECEIPT-06: Layer C invariant — rows_returned:0 when cap_granted:false") do
  [C_G1, C_G2, C_G3, C_G5].all? { |r| r[:receipt]['rows_returned'] == 0 }
end

check("EXECQ-RECEIPT-07: Layer C G4 clamp ≠ denial — cap_granted:true when clamped") do
  C_G4[:receipt]['cap_granted'] == true &&
    C_G4[:receipt]['row_limit_clamped'] == true &&
    C_G4[:result]['kind'] != 'denied'
end

# ── EXECQ-VM ──────────────────────────────────────────────────────────────────
puts "\n── EXECQ-VM (8) — Layer B VM execution ──"

check("EXECQ-VM-01: VM ExecuteQueryRows(row_count:5) → kind:\"rows\"; count:5") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind') == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 5
end

check("EXECQ-VM-02: VM ExecuteQueryEmpty → kind:\"empty\"; count:0") do
  VM_EMPTY_R['status'] == 'success' &&
    VM_EMPTY_R.dig('result', 'kind') == 'empty' &&
    VM_EMPTY_R.dig('result', 'count') == 0
end

check("EXECQ-VM-03: VM ExecuteQueryDeniedSource → kind:\"denied\"; count:0; message non-empty") do
  VM_DENIED_R['status'] == 'success' &&
    VM_DENIED_R.dig('result', 'kind') == 'denied' &&
    VM_DENIED_R.dig('result', 'count') == 0 &&
    !VM_DENIED_R.dig('result', 'message').to_s.empty?
end

check("EXECQ-VM-04: VM ExecuteQueryQueryError → kind:\"query_error\"; count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind') == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("EXECQ-VM-05: VM ExecuteQuerySystemError → kind:\"system_error\"; count:0") do
  VM_SYSERR_R['status'] == 'success' &&
    VM_SYSERR_R.dig('result', 'kind') == 'system_error' &&
    VM_SYSERR_R.dig('result', 'count') == 0
end

check("EXECQ-VM-06: VM BuildStorageCapability → cap_id correct; row_limit:100; read_allowed:true") do
  VM_CAP_R['status'] == 'success' &&
    VM_CAP_R.dig('result', 'cap_id') == 'cap-execq-v0' &&
    VM_CAP_R.dig('result', 'row_limit') == 100 &&
    VM_CAP_R.dig('result', 'read_allowed') == true
end

check("EXECQ-VM-07: VM BuildQueryPlanInline → kind:\"select\"; source.table:\"users\"; filters is array") do
  VM_PLAN_R['status'] == 'success' &&
    VM_PLAN_R.dig('result', 'kind') == 'select' &&
    VM_PLAN_R.dig('result', 'source', 'table') == 'users' &&
    VM_PLAN_R.dig('result', 'filters').is_a?(Array)
end

check("EXECQ-VM-08: VM BuildClampedReceipt(plan_limit:200 > row_limit_cap:100) → effective_limit:100") do
  VM_CLAMPED_R['status'] == 'success' &&
    VM_CLAMPED_R.dig('result', 'effective_limit') == 100 &&
    VM_CLAMPED_R.dig('result', 'plan_limit') == 200 &&
    VM_CLAMPED_R.dig('result', 'row_limit_cap') == 100
end

# ── EXECQ-MAP ─────────────────────────────────────────────────────────────────
puts "\n── EXECQ-MAP (4) — map_get + or_else chain ──"

check("EXECQ-MAP-01: VM QueryMetadataChain(key=\"source\", metadata={source:\"api\"}) → \"api\"") do
  VM_META_HIT['status'] == 'success' && VM_META_HIT['result'] == 'api'
end

check("EXECQ-MAP-02: VM QueryMetadataChain(key=\"missing\", metadata={}) → \"not-found\" (or_else)") do
  VM_META_MISS['status'] == 'success' && VM_META_MISS['result'] == 'not-found'
end

check("EXECQ-MAP-03: Layer A: ReadPlanMeta — zero type_errors (map_get + or_else chain accepted)") do
  type_errors_for(CAP_TC, 'ReadPlanMeta').empty? && contract_accepted?(CAP_TC, 'ReadPlanMeta')
end

check("EXECQ-MAP-04: Layer A: ReadPlanMeta output meta_str type = String") do
  t = sym_type_for(CAP_TC, 'meta_str', 'ReadPlanMeta')
  type_name_str(t) == 'String'
end

# ── EXECQ-ARRAY ───────────────────────────────────────────────────────────────
puts "\n── EXECQ-ARRAY (4) — inline array Collection[FilterPredicate] (Rust SIR) ──"

check("EXECQ-ARRAY-01: Rust SIR: BuildQueryPlanInline.filters compute_type_tag = Collection[FilterPredicate]") do
  compute_type_tag(RCPTS_SIR, 'BuildQueryPlanInline', 'filters') == 'Collection[FilterPredicate]'
end

check("EXECQ-ARRAY-02: Rust SIR: BuildQueryPlanInline.plan compute_type_tag = QueryPlan") do
  compute_type_tag(RCPTS_SIR, 'BuildQueryPlanInline', 'plan') == 'QueryPlan'
end

check("EXECQ-ARRAY-03: Rust SIR: BuildQueryPlanInline plan output_port type_tag = QueryPlan") do
  output_type_tag(RCPTS_SIR, 'BuildQueryPlanInline', 'plan') == 'QueryPlan'
end

check("EXECQ-ARRAY-04: VM BuildQueryPlanInline → filters 2-element array (field:status, field:role)") do
  filters = VM_PLAN_R.dig('result', 'filters')
  VM_PLAN_R['status'] == 'success' &&
    filters.is_a?(Array) && filters.length == 2 &&
    filters[0]['field'] == 'status' && filters[1]['field'] == 'role'
end

# ── EXECQ-COMPOSE ─────────────────────────────────────────────────────────────
puts "\n── EXECQ-COMPOSE (5) — plan field → gate input composition ──"

check("EXECQ-COMPOSE-01: Layer C: plan.source.table drives G1 (wrong table → denied)") do
  wrong_plan = BASE_PLAN.merge('source' => { 'table' => 'invoices', 'schema' => 'finance' })
  result = ExecuteQuerySim.evaluate(BASE_CAP, wrong_plan)
  result[:receipt]['denial_gate'] == 'G1' && result[:result]['kind'] == 'denied'
end

check("EXECQ-COMPOSE-02: Layer C: plan.projection.include_all drives G5 (query_error)") do
  incl_plan = BASE_PLAN.merge('projection' => { 'fields' => '*', 'include_all' => true })
  result = ExecuteQuerySim.evaluate(BASE_CAP, incl_plan)
  result[:result]['kind'] == 'query_error' && result[:receipt]['denial_gate'] == 'G5'
end

check("EXECQ-COMPOSE-03: Layer C: plan.limit drives G4 clamp (limit:999 → effective_limit:100)") do
  high_plan = BASE_PLAN.merge('limit' => 999)
  result = ExecuteQuerySim.evaluate(BASE_CAP, high_plan)
  result[:receipt]['effective_limit'] == 100 && result[:receipt]['row_limit_clamped'] == true
end

check("EXECQ-COMPOSE-04: Layer C: correct source passes G1; receipt.source_table preserved") do
  C_PASS[:receipt]['denial_gate'] != 'G1' &&
    C_PASS[:result]['kind'] != 'denied' &&
    C_PASS[:receipt]['source_table'] == BASE_PLAN.dig('source', 'table')
end

check("EXECQ-COMPOSE-05: Layer C: G5 result_kind=\"query_error\"; cap_granted:false; NOT \"denied\"") do
  C_G5[:result]['kind'] == 'query_error' &&
    C_G5[:receipt]['cap_granted'] == false &&
    C_G5[:result]['kind'] != 'denied'
end

# ── EXECQ-CLOSED ──────────────────────────────────────────────────────────────
puts "\n── EXECQ-CLOSED (5) — closed surfaces ──"

check("EXECQ-CLOSED-01: no SQL execution in capability fixture source") do
  !CAP_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+|CREATE\s+TABLE/i) &&
    !CAP_SRC.include?('execute_sql') && !CAP_SRC.include?('.sql')
end

check("EXECQ-CLOSED-02: no database connection / ORM in capability fixture source") do
  !CAP_SRC.include?('establish_connection') && !CAP_SRC.include?('database_url') &&
    !CAP_SRC.include?('ActiveRecord') && !CAP_SRC.include?('connect_to(')
end

check("EXECQ-CLOSED-03: no SQL execution in receipts fixture source") do
  !RCPTS_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+|CREATE\s+TABLE/i) &&
    !RCPTS_SRC.include?('execute_sql') && !RCPTS_SRC.include?('.sql')
end

check("EXECQ-CLOSED-04: ExecuteQuery is effect contract (compile-only); not in receipts contracts") do
  cap_contracts = contract_names(CAP_SIR)
  rcpts_contracts = contract_names(RCPTS_SIR)
  cap_contracts.include?('ExecuteQuery') && !rcpts_contracts.include?('ExecuteQuery')
end

check("EXECQ-CLOSED-05: no persistence runtime in proof runner source") do
  !SOURCE.include?('Base.establish_' + 'connection') &&
    !SOURCE.include?('DATABASE_URL' + '=') &&
    !SOURCE.include?('Sequ' + 'el.connect(') &&
    !SOURCE.include?('execute_sql' + '(') &&
    !SOURCE.include?('Active' + 'Record::Base')
end

# ── EXECQ-GAP ─────────────────────────────────────────────────────────────────
puts "\n── EXECQ-GAP (5) — boundary findings ──"

check("EXECQ-GAP-01: Effect contract gap — ExecuteQuery in cap fixture; not in VM-executable receipts") do
  contract_names(CAP_SIR).include?('ExecuteQuery') &&
    !contract_names(RCPTS_SIR).include?('ExecuteQuery') &&
    CAP_SRC.include?('effect contract ExecuteQuery') &&
    !RCPTS_SRC.include?('effect contract')
end

check("EXECQ-GAP-02: No TBackend/TEMPORAL types in either fixture") do
  !CAP_SRC.include?('TBackend') && !CAP_SRC.include?('TEMPORAL') &&
    !RCPTS_SRC.include?('TBackend') && !RCPTS_SRC.include?('TEMPORAL')
end

check("EXECQ-GAP-03: KDR routing — \"denied\" → deny; \"query_error\" → invalid (distinct from deny)") do
  deny_action = ExecuteQuerySim.route(C_G1[:result])[:action]
  qerr_action = ExecuteQuerySim.route(C_G5[:result])[:action]
  deny_action == 'deny' && qerr_action == 'invalid' && qerr_action != 'deny'
end

check("EXECQ-GAP-04: KDR routing — \"system_error\" → error (distinct from deny and invalid)") do
  se_action = ExecuteQuerySim.route(C_SYSERR[:result])[:action]
  se_action == 'error' && se_action != 'deny' && se_action != 'invalid'
end

check("EXECQ-GAP-05: Write ops CLOSED in v0 — write_allowed field declared; no write effect contract") do
  RCPTS_SRC.include?('write_allowed') &&
    !CAP_SRC.include?('effect write') && !RCPTS_SRC.include?('effect write') &&
    !CAP_SRC.match?(/write\s+contract/) && !RCPTS_SRC.match?(/write\s+contract/)
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-EXECUTE-QUERY-P1: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  - ExecuteQuery effect contract: Layer A + Layer B accepted; VM requires capability injection (ESCAPE gap)"
  puts "  - 6-gate StorageCapability sequence: G1-G3 denial-as-data; G4 clamp ≠ denial; G5 query_error ≠ denied"
  puts "  - QueryExecutionReceipt 15-field shape: VM-verified; cap_granted/rows_returned invariants hold"
  puts "  - BuildQueryPlanInline filters typed Collection[FilterPredicate] (Rust SIR; LAB-TC-ARRAY-P2 pattern)"
  puts "  - 5-kind KDR vocabulary routed correctly; system_error / query_error / denied all distinct"
  puts "  - TBackend/TEMPORAL orthogonal; write ops CLOSED in v0; no DB/SQL/ORM at any layer"
else
  puts "LAB-EXECUTE-QUERY-P1: #{$fail_count} check(s) failed"
  exit 1
end
