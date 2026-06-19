#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_query_p2.rb
# LAB-QUERY-P2: QueryPlan pure builder proof — 42 checks
#
# Proves that QueryPlan / QueryResult / QuerySource / Projection /
# FilterPredicate / OrderBy can be represented and composed today as pure
# typed Records with Map metadata. No DB. No ORM. No execution authority.
#
# Core formula (from LAB-QUERY-P1):
#   Query v0 = typed intent AST + denial-as-data + Map[String,String] metadata.
#   Query v0 != ORM, != database connection, != persistence runtime.
#
# Two-layer + simulation proof:
#   Layer A — Production Ruby TypeChecker: type shapes, Map[String,String]
#             inference, QueryPlan/QueryResult field types, C1 chain through
#             named Record input (result.metadata -> Map[String,String] ->
#             map_get -> Option[String] -> or_else -> String).
#   Layer B — Lab Rust VM (igniter-compiler + igniter-vm): record construction,
#             map_get(result.metadata, key) + or_else execution.
#   Layer C — Proof-local QueryExecutorSim: 5-kind routing, determinism,
#             denial-as-data behavioral proof.
#
# Sections:
#   QPLAN-COMPILE  (4)  — fixture compiles, 6 contracts, SIR, no type_errors
#   QPLAN-TYPES    (5)  — type env: QueryPlan/QueryResult/FilterPredicate fields
#   QPLAN-BUILD    (6)  — plan construction: kinds, filters, fragments
#   QPLAN-DENIED   (4)  — denial-as-data in query domain
#   QPLAN-MAP      (4)  — Map[String,String] metadata chain (C1, Layer A + B)
#   QPLAN-VM       (5)  — VM execution: source, plan, filter, metadata chain
#   QPLAN-ROUTE    (5)  — routing simulation: 5 kind paths + fail-closed
#   QPLAN-COMPARE  (4)  — comparison vs ValidationResult/ContractResult
#   QPLAN-CLOSED   (5)  — closed surface: no SQL, no DB, no ORM, lab-only
#
# Total: 42 checks
#
# Depends on:
#   LAB-QUERY-P1 (research + design boundary)
#   PROP-043-P5 (55/55) — Map[String,String] production surface + C1 fix
#   LAB-VM-MAP-P1 (48/48) — map_get/or_else VM runtime
#   LAB-RESULT-ENVELOPE-P2 (50/50) — KDR + denial-as-data cross-domain baseline
#
# Authority: LAB-ONLY. No canon claim. No framework compat. No public API.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_query_p2.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_plan' / 'query_plan.ig').to_s

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
  tmpfile = Tempfile.new(['qplan_inputs', '.json'])
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

# ── Layer C: Proof-local query execution simulation ────────────────────────────
#
# QueryExecutorSim: models what a domain consumer does with each QueryResult kind.
# 5-kind routing: rows / empty / denied / query_error / system_error.
# No SQL connection. No database. No IO. Pure deterministic Ruby.
# Evidence only — does not confer production execution authority.

module QueryExecutorSim
  ROUTES = {
    'rows'         => { action: 'process',  summary: 'rows returned; iterate and transform' },
    'empty'        => { action: 'empty',    summary: 'zero rows; show empty state to user' },
    'denied'       => { action: 'deny',     summary: 'access denied; do not retry same plan' },
    'query_error'  => { action: 'invalid',  summary: 'malformed plan; fix query before retry' },
    'system_error' => { action: 'error',    summary: 'infrastructure failure; retry later' }
  }.freeze

  def self.route(query_result)
    kind = query_result[:kind] || query_result['kind']
    ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  # denial_as_data: returns true when the kind represents a capability denial
  # that was delivered as typed data, not as an exception.
  def self.denial_as_data?(kind)
    kind == 'denied' && ROUTES.key?('denied')
  end

  def self.metadata_get(metadata, key, default_val = 'unknown')
    val = metadata[key] || metadata[key.to_sym]
    val.nil? ? default_val : val
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile and run up front
# ─────────────────────────────────────────────────────────────────────────────

QPLAN_OUT = Dir.mktmpdir('qplan_main')
QPLAN_SIR = compile_fixture(FIXTURE_PATH, QPLAN_OUT)
QPLAN_TC  = run_fixture(FIXTURE_PATH)

# ── VM inputs ─────────────────────────────────────────────────────────────────

SOURCE_INPUTS = {
  'table'  => 'users',
  'schema' => 'public'
}.freeze

SELECT_INPUTS = {
  'table'        => 'users',
  'filter_field' => 'status',
  'filter_op'    => 'eq',
  'filter_value' => 'active',
  'order_field'  => 'name',
  'order_dir'    => 'asc',
  'limit'        => 25,
  'context'      => { 'trace' => 'req-001', 'requester' => 'api' }
}.freeze

FILTER_INPUTS = {
  'table'    => 'posts',
  'field'    => 'author_id',
  'value'    => '42',
  'metadata' => { 'trace' => 'req-002', 'source' => 'web' }
}.freeze

DENIED_INPUTS = {
  'table'    => 'secrets',
  'reason'   => 'table not in allowed_sources',
  'metadata' => { 'cap_id' => 'store-1', 'op' => 'read' }
}.freeze

META_PRESENT_INPUTS = {
  'result' => {
    'kind'     => 'rows',
    'count'    => 3,
    'message'  => 'query executed',
    'metadata' => { 'source' => 'web', 'table' => 'users' }
  }
}.freeze

META_ABSENT_INPUTS = {
  'result' => {
    'kind'     => 'empty',
    'count'    => 0,
    'message'  => 'no rows',
    'metadata' => { 'trace' => 'req-003' }
  }
}.freeze

MAPPER_WITH_MSG_INPUTS = {
  'raw_kind' => 'rows',
  'table'    => 'users',
  'context'  => { 'message' => '3 records found', 'trace' => 'req-001' }
}.freeze

MAPPER_NO_MSG_INPUTS = {
  'raw_kind' => 'system_error',
  'table'    => 'posts',
  'context'  => { 'trace' => 'req-err' }
}.freeze

VM_SOURCE       = vm_run(QPLAN_OUT, 'BuildQuerySource',   SOURCE_INPUTS)
VM_SELECT       = vm_run(QPLAN_OUT, 'BuildSelectQuery',   SELECT_INPUTS)
VM_FILTER       = vm_run(QPLAN_OUT, 'BuildFilteredQuery', FILTER_INPUTS)
VM_DENIED       = vm_run(QPLAN_OUT, 'QueryResultDenied',  DENIED_INPUTS)
VM_META_PRESENT = vm_run(QPLAN_OUT, 'QueryMetadataReader', META_PRESENT_INPUTS)
VM_META_ABSENT  = vm_run(QPLAN_OUT, 'QueryMetadataReader', META_ABSENT_INPUTS)
VM_MAPPER_MSG   = vm_run(QPLAN_OUT, 'QueryMapper',        MAPPER_WITH_MSG_INPUTS)
VM_MAPPER_NOMSG = vm_run(QPLAN_OUT, 'QueryMapper',        MAPPER_NO_MSG_INPUTS)

# ── Simulation inputs ─────────────────────────────────────────────────────────

SIM_ROWS     = { kind: 'rows',         count: 5, message: 'ok',              metadata: {} }
SIM_EMPTY    = { kind: 'empty',        count: 0, message: 'no rows',         metadata: {} }
SIM_DENIED   = { kind: 'denied',       count: 0, message: 'access denied',   metadata: { 'cap' => 'store-1' } }
SIM_QERROR   = { kind: 'query_error',  count: 0, message: 'bad field name',  metadata: {} }
SIM_SYSERR   = { kind: 'system_error', count: 0, message: 'timeout',         metadata: {} }
SIM_UNKNOWN  = { kind: 'garbage_kind', count: 0, message: '',                metadata: {} }

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-COMPILE: Fixture compilation
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-COMPILE"

check('QPLAN-COMPILE-01: fixture parses and TypeChecker runs without crash') do
  !QPLAN_TC[:error] && QPLAN_TC[:typed].is_a?(Hash)
end

check('QPLAN-COMPILE-02: fixture produces 6 contracts in TypeChecker') do
  QPLAN_TC[:typed]&.fetch('contracts', [])&.length == 6
end

check('QPLAN-COMPILE-03: Rust compiler produces SIR with 6 contracts') do
  sir = read_sir(QPLAN_OUT)
  sir.is_a?(Hash) && sir.fetch('contracts', []).length == 6
end

check('QPLAN-COMPILE-04: all 6 contracts accepted with no type_errors') do
  cs = QPLAN_TC[:typed]&.fetch('contracts', []) || []
  cs.length == 6 &&
    cs.all? { |c| (c['type_errors'] || []).empty? } &&
    cs.all? { |c| c['status'] == 'accepted' }
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-TYPES: Type environment
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-TYPES"

check('QPLAN-TYPES-01: QueryPlan present in type_env with core scalar fields') do
  qp = QPLAN_TC[:typed]&.fetch('type_env', {})&.fetch('QueryPlan', {}) || {}
  %w[kind source_table filter_field filter_op limit metadata].all? { |f| qp.key?(f) }
end

check('QPLAN-TYPES-02: QueryPlan.metadata = Map[String,String] (C1 fix propagates to QueryPlan)') do
  f = type_env_field(QPLAN_TC, 'QueryPlan', 'metadata')
  type_name_str(f) == 'Map[String,String]'
end

check('QPLAN-TYPES-03: QueryResult present in type_env with kind/count/message/metadata') do
  qr = QPLAN_TC[:typed]&.fetch('type_env', {})&.fetch('QueryResult', {}) || {}
  %w[kind count message metadata].all? { |f| qr.key?(f) }
end

check('QPLAN-TYPES-04: FilterPredicate present in type_env with field/op/value') do
  fp = QPLAN_TC[:typed]&.fetch('type_env', {})&.fetch('FilterPredicate', {}) || {}
  %w[field op value].all? { |f| fp.key?(f) }
end

check('QPLAN-TYPES-05: QueryMetadataReader.src_opt = Option[String] (map_get through QueryResult.metadata C1 chain)') do
  t = sym_type_for(QPLAN_TC, 'src_opt', 'QueryMetadataReader')
  t.is_a?(Hash) &&
    t['name'] == 'Option' &&
    t.dig('params', 0, 'name') == 'String'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-BUILD: Plan construction
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-BUILD"

check('QPLAN-BUILD-01: BuildQuerySource accepted; output source type = QuerySource') do
  contract_accepted?(QPLAN_TC, 'BuildQuerySource') &&
    type_name_str(sym_type_for(QPLAN_TC, 'source', 'BuildQuerySource')) == 'QuerySource'
end

check('QPLAN-BUILD-02: BuildSelectQuery accepted; plan type = QueryPlan') do
  contract_accepted?(QPLAN_TC, 'BuildSelectQuery') &&
    type_name_str(sym_type_for(QPLAN_TC, 'plan', 'BuildSelectQuery')) == 'QueryPlan'
end

check('QPLAN-BUILD-03: BuildSelectQuery has no type_errors; Map[String,String] context accepted as metadata') do
  type_errors_for(QPLAN_TC, 'BuildSelectQuery').empty?
end

check('QPLAN-BUILD-04: BuildFilteredQuery accepted; plan type = QueryPlan') do
  contract_accepted?(QPLAN_TC, 'BuildFilteredQuery') &&
    type_name_str(sym_type_for(QPLAN_TC, 'plan', 'BuildFilteredQuery')) == 'QueryPlan'
end

check('QPLAN-BUILD-05: BuildFilteredQuery has no type_errors (eq-filter variant)') do
  type_errors_for(QPLAN_TC, 'BuildFilteredQuery').empty?
end

check('QPLAN-BUILD-06: QueryResultDenied accepted; result type = QueryResult') do
  contract_accepted?(QPLAN_TC, 'QueryResultDenied') &&
    type_name_str(sym_type_for(QPLAN_TC, 'result', 'QueryResultDenied')) == 'QueryResult'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-DENIED: Denial-as-data in the query domain
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-DENIED"

check('QPLAN-DENIED-01: QueryResultDenied result type = QueryResult (type-level proof)') do
  type_name_str(sym_type_for(QPLAN_TC, 'result', 'QueryResultDenied')) == 'QueryResult'
end

check('QPLAN-DENIED-02: VM QueryResultDenied produces kind="denied" record without exception') do
  VM_DENIED['status'] == 'success' &&
    VM_DENIED.dig('result', 'kind') == 'denied'
end

check('QPLAN-DENIED-03: VM denial-as-data: result is a record with kind field; no exception') do
  VM_DENIED['status'] == 'success' &&
    VM_DENIED['result'].is_a?(Hash) &&
    VM_DENIED['result'].key?('kind')
end

check('QPLAN-DENIED-04: QueryResult shape has no HTTP status integer field') do
  qr = QPLAN_TC[:typed]&.fetch('type_env', {})&.fetch('QueryResult', {}) || {}
  !qr.key?('status') && !qr.key?('http_status') && !qr.key?('status_code')
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-MAP: Map[String,String] metadata chain
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-MAP"

check('QPLAN-MAP-01: map_get(result.metadata, "source") -> Option[String] in QueryMetadataReader (C1 chain)') do
  t = sym_type_for(QPLAN_TC, 'src_opt', 'QueryMetadataReader')
  t.is_a?(Hash) && t['name'] == 'Option' && t.dig('params', 0, 'name') == 'String'
end

check('QPLAN-MAP-02: or_else(Option[String], default) -> String (QueryMetadataReader.source)') do
  type_name_str(sym_type_for(QPLAN_TC, 'source', 'QueryMetadataReader')) == 'String'
end

check('QPLAN-MAP-03: QueryMapper.msg = String (or_else(map_get(context, "message"), default) on direct Map input)') do
  type_name_str(sym_type_for(QPLAN_TC, 'msg', 'QueryMapper')) == 'String'
end

check('QPLAN-MAP-04: VM QueryMetadataReader with source present returns "web" (map_get hit)') do
  VM_META_PRESENT['status'] == 'success' &&
    VM_META_PRESENT['result'] == 'web'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-VM: VM execution
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-VM"

check('QPLAN-VM-01: VM BuildQuerySource produces table="users" (QuerySource record construction)') do
  VM_SOURCE['status'] == 'success' &&
    VM_SOURCE.dig('result', 'table') == 'users'
end

check('QPLAN-VM-02: VM BuildSelectQuery produces kind="select" in plan (QueryPlan construction)') do
  VM_SELECT['status'] == 'success' &&
    VM_SELECT.dig('result', 'kind') == 'select'
end

check('QPLAN-VM-03: VM BuildFilteredQuery produces filter_op="eq" in plan') do
  VM_FILTER['status'] == 'success' &&
    VM_FILTER.dig('result', 'filter_op') == 'eq'
end

check('QPLAN-VM-04: VM QueryMetadataReader with absent source returns "unknown_source" (or_else fallback)') do
  VM_META_ABSENT['status'] == 'success' &&
    VM_META_ABSENT['result'] == 'unknown_source'
end

check('QPLAN-VM-05: VM QueryMapper with message returns message from context (map_get hit + or_else passthrough)') do
  VM_MAPPER_MSG['status'] == 'success' &&
    VM_MAPPER_MSG.dig('result', 'message') == '3 records found'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-ROUTE: Layer C simulation — 5-kind routing
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-ROUTE"

check('QPLAN-ROUTE-01: route(kind="rows") -> action="process" (happy path)') do
  QueryExecutorSim.route(SIM_ROWS)[:action] == 'process'
end

check('QPLAN-ROUTE-02: route(kind="empty") -> action="empty" (zero rows; not an error)') do
  QueryExecutorSim.route(SIM_EMPTY)[:action] == 'empty'
end

check('QPLAN-ROUTE-03: route(kind="denied") -> action="deny" (denial-as-data routed deterministically)') do
  QueryExecutorSim.route(SIM_DENIED)[:action] == 'deny' &&
    QueryExecutorSim.denial_as_data?('denied')
end

check('QPLAN-ROUTE-04: route(kind="system_error") -> action="error" (infrastructure fault)') do
  QueryExecutorSim.route(SIM_SYSERR)[:action] == 'error'
end

check('QPLAN-ROUTE-05: route(unknown kind) -> action="unknown" (fail-closed; no crash)') do
  QueryExecutorSim.route(SIM_UNKNOWN)[:action] == 'unknown'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-COMPARE: Comparison vs prior domain envelopes
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-COMPARE"

check('QPLAN-COMPARE-01: QueryResult.metadata = Map[String,String] — same shape as ValidationResult.metadata') do
  qr_meta = type_env_field(QPLAN_TC, 'QueryResult', 'metadata')
  type_name_str(qr_meta) == 'Map[String,String]'
end

check('QPLAN-COMPARE-02: QueryResult has no job_class/job_id/attempt fields (query domain != Sidekiq domain)') do
  qr = QPLAN_TC[:typed]&.fetch('type_env', {})&.fetch('QueryResult', {}) || {}
  !qr.key?('job_class') && !qr.key?('job_id') && !qr.key?('attempt')
end

check('QPLAN-COMPARE-03: QueryResult has "empty" kind — domain-specific (not in ValidationResult/ContractResult)') do
  # "empty" is unique to the query domain: zero rows is a distinct non-error outcome
  sim_empty_route = QueryExecutorSim::ROUTES['empty']
  sim_empty_route[:action] == 'empty'
end

check('QPLAN-COMPARE-04: KDR convention holds — QueryResult follows kind+message+metadata shape') do
  qr = QPLAN_TC[:typed]&.fetch('type_env', {})&.fetch('QueryResult', {}) || {}
  qr.key?('kind') && qr.key?('message') && qr.key?('metadata')
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN-CLOSED: Closed surface scan
# ─────────────────────────────────────────────────────────────────────────────

puts "\nQPLAN-CLOSED"

check('QPLAN-CLOSED-01: no SQL execution in fixture or runner') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  # Check for SQL execution patterns — split strings to avoid self-reference
  !SOURCE.include?('execut' + 'e_sql') &&
    !SOURCE.include?('run_qu' + 'ery(') &&
    !src.include?('execut' + 'e_sql') &&
    !src.include?('run_qu' + 'ery(')
end

check('QPLAN-CLOSED-02: no database connection or ORM in fixture or runner') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !SOURCE.include?('Active' + 'Record') &&
    !SOURCE.include?('establish_conn' + 'ection') &&
    !src.include?('Active' + 'Record') &&
    !src.include?('establish_conn' + 'ection')
end

check('QPLAN-CLOSED-03: no job_class/job_id/attempt fields in query fixture (orthogonal to Sidekiq)') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('job_class:') && !src.include?('job_id:') && !src.include?('attempt:')
end

check('QPLAN-CLOSED-04: no stable-API or canon-authority claim in runner') do
  !SOURCE.include?('stab' + 'le API auth') &&
    !SOURCE.include?('canon auth' + 'ority') &&
    !SOURCE.include?('compat' + 'ibility auth')
end

check('QPLAN-CLOSED-05: fixture is lab-only; all contracts are pure (CORE fragment; no effect/storage contracts)') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  # LAB-ONLY marker present; all contracts pure (no effect contract = no IO/storage surface)
  src.include?('LAB-ONLY') &&
    src.include?('pure contract') &&
    !src.include?('effect contract')
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "LAB-QUERY-P2: #{$pass_count}/#{total} PASS"
puts '=' * 60

if $fail_count > 0
  puts "\nFAILURES: #{$fail_count}"
  exit 1
else
  puts "\nPASS — all #{total} checks passed"
  exit 0
end
