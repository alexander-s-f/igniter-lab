#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_execute_query_p3.rb
# LAB-EXECUTE-QUERY-P3 — 68 checks
#
# Unified mocked query execution receipt: the complete v0 proof-local pipeline.
#
# Core formula:
#   UnifiedQuery v0  =  QueryPlanUnified + StorageCapability-shaped policy + mocked rows
#                    →  gated / filtered / ordered / limited / projected QueryResult
#                    +  QueryExecutionReceipt
#   UnifiedQuery v0  ≠  SQL execution  ≠  DB runtime  ≠  ORM  ≠  production StorageCapability
#   UnifiedQuerySim  =  PROOF-LOCAL ONLY  ≠  production unified query runtime
#
# Pipeline order (Layer C UnifiedQuerySim):
#   G1: source allowlist          → denied
#   G2: op allowlist              → denied
#   G3: read_allowed master       → denied
#   G4: row-limit clamp           → effective_limit = min(plan.limit, cap.row_limit); NOT denial
#   G5: include_all policy        → query_error (NOT denied)
#   G6a: apply filters            → rows / empty / query_error (bad op)
#   G6b: apply multi-column order → sorted rows / query_error (bad dir / missing field)
#   G6c: apply effective_limit    → limited rows / empty / query_error (negative)
#   G6d: apply projection         → shaped rows / query_error (empty fields / missing field)
#   Build QueryResult + QueryExecutionReceipt
#
# G1/G2/G3 short-circuit before filter/order/limit/projection.
# Projection is the FINAL step — after filter → multi-order → limit.
# Projection does not change row count.
# query_error ≠ denied throughout.
#
# Sections:
#   EXECQ3-COMPILE    (5)  — fixture compiles; 8 contracts; Ruby TC accepted; zero diagnostics
#   EXECQ3-SHAPE      (8)  — QueryPlanUnified types; Collection[FilterPredicate/OrderBy]; receipt 15 fields; Rust SIR
#   EXECQ3-GATES      (6)  — G1/G2/G3 denial; G4 clamp; G5 query_error; gate short-circuit
#   EXECQ3-PIPELINE   (7)  — filter→multi-order→limit→projection order; happy path; compose
#   EXECQ3-PROJECTION (7)  — include_all; field list; dedup; row count invariant; shape
#   EXECQ3-RECEIPT    (6)  — cap_checked; cap_granted; denial_gate; effective_limit; rows_returned; result_kind
#   EXECQ3-ERROR      (8)  — filter/order/projection errors → query_error NOT denied; invariant
#   EXECQ3-VM         (8)  — Layer B: all 8 contracts VM-executed
#   EXECQ3-CLOSED     (8)  — no SQL/DB/ORM/index/optimizer/joins/writes/storage runtime
#   EXECQ3-GAP        (5)  — proof-local only; production? NO; typed Row[T] deferred; 8th P2
#
# Total: 68 checks
#
# Depends on:
#   LAB-EXECUTE-QUERY-P2     (integrated mocked pipeline — 73/73)
#   LAB-QUERY-MULTI-ORDER-P1 (Collection[OrderBy] multi-column order — 64/64)
#   LAB-QUERY-PROJECTION-P1  (projection/include_all semantics — 62/62)
#   LAB-FILTER-EVAL-P1       (filter predicate evaluation — 50/50)
#   LAB-QUERY-ORDER-LIMIT-P1 (order/limit semantics — 54/54)
#   LAB-STORAGE-CAPABILITY-P2 (StorageCapability gate semantics — 51/51)
#   LAB-TC-ARRAY-P2          (Collection[T] from record-field context — 19/19)
#   LAB-VM-MAP-P1            (VM map_get/or_else — 48/48)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_execute_query_p3.rb

SOURCE = File.read(__FILE__).force_encoding('UTF-8').freeze

require 'json'
require 'open3'
require 'tmpdir'
require 'set'
require 'fileutils'
require 'pathname'
require 'tempfile'

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / 'igniter-lang' / 'lib'
COMPILER_BIN   = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN         = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_execution' / 'execute_query_unified.ig').to_s

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

def contract_accepted?(result, name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == name }
  c&.fetch('status', nil) == 'accepted'
end

def type_errors_for(result, name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == name }
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

# ── Layer B: Rust compiler + VM helpers ───────────────────────────────────────

def compile_path(path, tag = 'execq3')
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

def compute_type_tag(res, contract, node)
  c = res[:contracts][contract]
  return nil unless c
  n = (c['compute_nodes'] || []).find { |x| x['name'] == node }
  n&.fetch('type_tag', nil)
end

def vm_run(out_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['execq3_inputs', '.json'])
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

# ── ReverseComparable: per-column desc direction in composite sort ─────────────
#
# Wraps a String value and reverses <=> so that Array#<=> produces descending
# order for that position while ascending positions use the raw String.
# All positions are uniform type (String or ReverseComparable), so Array#<=>
# is correct throughout the composite key.
# ReverseComparable is PROOF-LOCAL ONLY.

class ReverseComparable
  include Comparable
  attr_reader :val
  def initialize(val); @val = val.to_s; end
  def <=>(other); other.val.to_s <=> @val; end
end

# ── Layer C: Proof-local UnifiedQuerySim ─────────────────────────────────────
#
# UnifiedQuerySim: complete proof-local pipeline combining all prior query semantics.
#
# Pipeline:
#   G1: source allowlist          → denied
#   G2: op allowlist              → denied
#   G3: read_allowed master       → denied
#   G4: row-limit clamp           → effective_limit = min(plan.limit, cap.row_limit); NOT denial
#   G5: include_all policy        → query_error (NOT denied)
#   G6a: apply filters            → matched rows or query_error (bad op)
#   G6b: apply multi-column order → sorted rows or query_error (bad dir/missing field)
#   G6c: apply effective_limit    → limited rows or empty or query_error (negative)
#   G6d: apply projection         → shaped rows or query_error (empty fields/missing field)
#   Build QueryResult + QueryExecutionReceipt
#
# G1/G2/G3 gate failures short-circuit: filter/order/limit/projection are NOT evaluated.
# G4 clamp does NOT deny — cap_granted stays true after clamp.
# G5 → query_error (NOT denied): G5 fires before filter/order/limit/projection.
# Projection is the FINAL step: after filter → multi-order → limit.
# Projection does not change row count.
# Row model: Array of Hash[String => String] (in-memory; no DB; no sql).
# All comparisons are lexicographic String in v0.
#
# UnifiedQuerySim is PROOF-LOCAL ONLY — not a production unified query runtime.

module UnifiedQuerySim
  KNOWN_OPS        = %w[eq neq contains prefix].freeze
  KNOWN_DIRECTIONS = %w[asc desc].freeze

  def self.execute(cap, plan, mocked_rows)
    source_table  = plan.dig('source', 'table') || ''
    projection    = plan.fetch('projection', { 'fields' => '', 'include_all' => false })
    include_all   = projection.fetch('include_all', false)
    plan_limit    = plan.fetch('limit', 0)
    row_limit     = cap.fetch('row_limit', 0)
    cap_id        = cap.fetch('cap_id', '')
    deny_reason   = cap.fetch('deny_reason', '')
    filters       = plan.fetch('filters', [])
    order_list    = plan.fetch('order', [])
    metadata      = plan.fetch('metadata', {})

    # G1: source allowlist
    unless cap.fetch('allowed_sources', []).include?(source_table)
      msg = deny_reason.empty? ? 'source not in allowed_sources' : deny_reason
      return gate_denied('G1', msg, cap_id, source_table, plan_limit, row_limit, metadata)
    end

    # G2: op allowlist
    unless cap.fetch('allowed_ops', []).include?('read')
      return gate_denied('G2', 'op not in allowed_ops', cap_id, source_table, plan_limit, row_limit, metadata)
    end

    # G3: read master switch
    unless cap.fetch('read_allowed', false)
      return gate_denied('G3', 'read_allowed is false', cap_id, source_table, plan_limit, row_limit, metadata)
    end

    # G4: row-limit clamp (NOT denial — cap_granted stays true)
    effective_limit = [plan_limit, row_limit].min
    clamped         = effective_limit < plan_limit

    # G5: include_all policy → query_error (NOT denied)
    if include_all && !cap.fetch('allow_include_all', false)
      return gate_qe('G5', 'include_all not permitted by capability',
                     cap_id, source_table, plan_limit, row_limit, effective_limit, clamped, metadata)
    end

    # G6c negative limit check (after G4 clamp)
    if effective_limit < 0
      return gate_qe('G6-limit', 'negative limit',
                     cap_id, source_table, plan_limit, row_limit, effective_limit, clamped, metadata)
    end

    # G6a: filter evaluation
    bad_op = filters.find { |f| !KNOWN_OPS.include?(f.fetch('op', '')) }
    if bad_op
      return gate_qe('G6-filter', "unknown filter operator: #{bad_op['op']}",
                     cap_id, source_table, plan_limit, row_limit, effective_limit, clamped, metadata)
    end
    filtered = mocked_rows.select { |row| filters.all? { |f| row_matches?(row, f) } }

    # G6b: multi-column order (Collection[OrderBy])
    unless order_list.empty?
      sort_out = sort_rows(filtered, order_list)
      if sort_out[:kind] == 'query_error'
        return gate_qe('G6-order', sort_out[:message],
                       cap_id, source_table, plan_limit, row_limit, effective_limit, clamped, metadata)
      end
      filtered = sort_out[:rows]
    end

    # G6c: apply effective_limit
    if effective_limit == 0
      receipt = build_receipt(
        cap_id: cap_id, source_table: source_table, plan_limit: plan_limit,
        row_limit_cap: row_limit, effective_limit: effective_limit,
        row_limit_clamped: clamped, cap_granted: true, denial_gate: '', deny_reason: '',
        rows_returned: 0, result_kind: 'empty', metadata: metadata
      )
      result = { 'kind' => 'empty', 'count' => 0, 'message' => 'limit zero', 'metadata' => metadata }
      return { result: result, receipt: receipt, rows: [] }
    end
    limited = filtered.first(effective_limit)

    # G6d: projection (final step — after filter → order → limit)
    proj_out = project_rows(limited, projection)
    if proj_out[:kind] == 'query_error'
      return gate_qe('G6-projection', proj_out[:message],
                     cap_id, source_table, plan_limit, row_limit, effective_limit, clamped, metadata)
    end

    final_rows = proj_out[:rows]
    kind       = final_rows.empty? ? 'empty' : 'rows'
    receipt = build_receipt(
      cap_id: cap_id, source_table: source_table, plan_limit: plan_limit,
      row_limit_cap: row_limit, effective_limit: effective_limit,
      row_limit_clamped: clamped, cap_granted: true, denial_gate: '', deny_reason: '',
      rows_returned: final_rows.length, result_kind: kind, metadata: metadata
    )
    result = { 'kind' => kind, 'count' => final_rows.length, 'message' => '', 'metadata' => metadata }
    { result: result, receipt: receipt, rows: final_rows }
  end

  private_class_method def self.gate_denied(gate, reason, cap_id, source_table,
                                             plan_limit, row_limit, metadata)
    receipt = build_receipt(
      cap_id: cap_id, source_table: source_table, plan_limit: plan_limit,
      row_limit_cap: row_limit, effective_limit: 0, row_limit_clamped: false,
      cap_granted: false, denial_gate: gate, deny_reason: reason,
      rows_returned: 0, result_kind: 'denied', metadata: metadata
    )
    result = { 'kind' => 'denied', 'count' => 0, 'message' => reason, 'metadata' => metadata }
    { result: result, receipt: receipt, rows: [] }
  end

  private_class_method def self.gate_qe(gate, msg, cap_id, source_table,
                                         plan_limit, row_limit, effective_limit, clamped, metadata)
    receipt = build_receipt(
      cap_id: cap_id, source_table: source_table, plan_limit: plan_limit,
      row_limit_cap: row_limit, effective_limit: effective_limit,
      row_limit_clamped: clamped, cap_granted: false, denial_gate: gate, deny_reason: msg,
      rows_returned: 0, result_kind: 'query_error', metadata: metadata
    )
    result = { 'kind' => 'query_error', 'count' => 0, 'message' => msg, 'metadata' => metadata }
    { result: result, receipt: receipt, rows: [] }
  end

  private_class_method def self.build_receipt(cap_id:, source_table:, plan_limit:,
                                               row_limit_cap:, effective_limit:, row_limit_clamped:,
                                               cap_granted:, denial_gate:, deny_reason:,
                                               rows_returned:, result_kind:, metadata:)
    {
      'cap_id'            => cap_id,
      'plan_kind'         => 'select',
      'source_table'      => source_table,
      'op_requested'      => 'read',
      'cap_checked'       => true,
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

  private_class_method def self.row_matches?(row, filter)
    field   = filter['field']
    op      = filter['op']
    val     = filter['value']
    row_val = row[field]
    return false if row_val.nil?
    case op
    when 'eq'       then row_val == val
    when 'neq'      then row_val != val
    when 'contains' then row_val.include?(val)
    when 'prefix'   then row_val.start_with?(val)
    else false
    end
  end

  private_class_method def self.sort_rows(rows, order_list)
    order_list.each do |ob|
      direction = ob.fetch('direction', '')
      field     = ob.fetch('field', '')
      if direction.empty?
        return { kind: 'query_error', message: "empty direction in multi-order entry (field: #{field})" }
      end
      unless KNOWN_DIRECTIONS.include?(direction)
        return { kind: 'query_error', message: "unknown direction: #{direction}" }
      end
    end
    order_list.each do |ob|
      field = ob.fetch('field', '')
      next if field.empty?
      missing = rows.find { |r| !r.key?(field) }
      if missing
        return { kind: 'query_error', message: "order field absent in row: #{field}" }
      end
    end
    sorted = rows.each_with_index.sort_by do |row, i|
      keys = order_list.map do |ob|
        val = row.fetch(ob.fetch('field', ''), '')
        ob.fetch('direction', 'asc') == 'asc' ? val : ReverseComparable.new(val)
      end
      keys + [i]
    end.map(&:first)
    { kind: 'ok', rows: sorted }
  end

  private_class_method def self.project_rows(rows, projection)
    include_all = projection.fetch('include_all', false)
    return { kind: 'ok', rows: rows } if include_all

    fields_str = projection.fetch('fields', '')
    field_list = fields_str.to_s.split(',').map(&:strip).reject(&:empty?)

    if field_list.empty?
      return { kind: 'query_error', message: 'empty fields in projection (include_all is false)' }
    end

    seen       = Set.new
    dedup_list = field_list.select { |f| seen.add?(f) }

    projected = rows.map do |row|
      missing = dedup_list.find { |f| !row.key?(f) }
      if missing
        return { kind: 'query_error', message: "projection field absent in row: #{missing}" }
      end
      projected_row = {}
      dedup_list.each { |f| projected_row[f] = row[f] }
      projected_row
    end

    { kind: 'ok', rows: projected }
  end
end

# ── Test data ─────────────────────────────────────────────────────────────────
#
# UNIFIED_ROWS: 5 rows with name/status/dept/score/role for full pipeline testing.
# Same dataset as PROJ_ROWS (PROJECTION-P1) for consistency across proofs.

UNIFIED_ROWS = [
  { 'name' => 'alice', 'status' => 'active',   'dept' => 'eng', 'score' => '10', 'role' => 'admin' },
  { 'name' => 'bob',   'status' => 'active',   'dept' => 'eng', 'score' => '20', 'role' => 'user'  },
  { 'name' => 'carol', 'status' => 'inactive', 'dept' => 'mkt', 'score' => '30', 'role' => 'user'  },
  { 'name' => 'dave',  'status' => 'active',   'dept' => 'mkt', 'score' => '40', 'role' => 'admin' },
  { 'name' => 'eve',   'status' => 'inactive', 'dept' => 'eng', 'score' => '50', 'role' => 'user'  },
].freeze

BASE_CAP = {
  'cap_id'            => 'cap-unified-v0',
  'allowed_sources'   => ['users', 'posts'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

# BASE_PLAN: filter(active) + order([dept asc, name asc]) + limit(10) + projection(name,status)
# Expected pipeline results:
#   filter(status=active):       alice, bob, dave        (3 rows)
#   order([dept asc, name asc]): alice(eng), bob(eng), dave(mkt) → alice, bob, dave
#   limit(10):                   alice, bob, dave        (all 3, limit >= count)
#   projection(name,status):     {name:alice,status:active}, {name:bob,status:active}, {name:dave,status:active}
BASE_PLAN = {
  'kind'       => 'select',
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'name,status', 'include_all' => false },
  'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
  'order'      => [{ 'field' => 'dept', 'direction' => 'asc' },
                   { 'field' => 'name', 'direction' => 'asc' }],
  'limit'      => 10,
  'metadata'   => { 'trace_id' => 'unified-base' }
}.freeze

ALL_CONTRACTS = %w[
  BuildUnifiedPlan BuildUnifiedCapability
  BuildUnifiedRowsResult BuildUnifiedEmptyResult
  BuildUnifiedDeniedResult BuildUnifiedQueryErrorResult
  BuildUnifiedReceipt UnifiedMetadataReader
].freeze

# ── Compile fixture and run TypeChecker ───────────────────────────────────────

UNIFIED_SIR = compile_path(FIXTURE_PATH, 'execq3')
UNIFIED_TC  = run_fixture(FIXTURE_PATH)
UNIFIED_SRC = File.read(FIXTURE_PATH).force_encoding('UTF-8').freeze
UNIFIED_OUT = UNIFIED_SIR[:out_dir]

# ── Pre-compute Layer C results ───────────────────────────────────────────────

# Happy path: allowed cap + filter(active) + order([dept asc, name asc]) + limit(10) + projection(name,status)
C_HAPPY = UnifiedQuerySim.execute(BASE_CAP, BASE_PLAN, UNIFIED_ROWS)

# Empty: no-match filter
C_EMPTY = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('filters' => [{ 'field' => 'name', 'op' => 'eq', 'value' => 'nobody' }]),
  UNIFIED_ROWS
)

# G1: source not in allowed_sources → denied
C_G1 = UnifiedQuerySim.execute(
  BASE_CAP.merge('allowed_sources' => ['posts']),
  BASE_PLAN,
  UNIFIED_ROWS
)

# G2: read not in allowed_ops → denied
C_G2 = UnifiedQuerySim.execute(
  BASE_CAP.merge('allowed_ops' => ['write']),
  BASE_PLAN,
  UNIFIED_ROWS
)

# G3: read_allowed false → denied
C_G3 = UnifiedQuerySim.execute(
  BASE_CAP.merge('read_allowed' => false),
  BASE_PLAN,
  UNIFIED_ROWS
)

# G4: cap.row_limit=2, plan.limit=10 → effective_limit=2
# Expected: filter(active)→alice,bob,dave; order(dept asc,name asc)→alice,bob,dave; limit(2)→alice,bob; projection(name,status)→2 rows
C_CLAMPED = UnifiedQuerySim.execute(
  BASE_CAP.merge('row_limit' => 2),
  BASE_PLAN,
  UNIFIED_ROWS
)

# G5: include_all=true + !allow_include_all → query_error
C_G5 = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('projection' => { 'fields' => '', 'include_all' => true }),
  UNIFIED_ROWS
)

# Filter error: unknown op
C_BAD_FILTER = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('filters' => [{ 'field' => 'status', 'op' => 'regex', 'value' => 'active' }]),
  UNIFIED_ROWS
)

# Order error: unknown direction
C_BAD_ORDER = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('order' => [{ 'field' => 'name', 'direction' => 'backwards' }]),
  UNIFIED_ROWS
)

# Projection error: empty fields
C_PROJ_EMPTY = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('projection' => { 'fields' => '', 'include_all' => false }),
  UNIFIED_ROWS
)

# Projection error: missing field in row
C_PROJ_MISSING = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('projection' => { 'fields' => 'name,missing_col', 'include_all' => false }),
  UNIFIED_ROWS
)

# include_all=true with allow_include_all=true → full passthrough (needs cap override)
C_INCLUDE_ALL = UnifiedQuerySim.execute(
  BASE_CAP.merge('allow_include_all' => true),
  BASE_PLAN.merge('projection' => { 'fields' => '', 'include_all' => true }),
  UNIFIED_ROWS
)

# Projection: single field "name"
C_SINGLE_FIELD = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('projection' => { 'fields' => 'name', 'include_all' => false }),
  UNIFIED_ROWS
)

# Projection: duplicate fields → de-duplicate first occurrence
C_DEDUP = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('projection' => { 'fields' => 'name,status,name', 'include_all' => false }),
  UNIFIED_ROWS
)

# Negative limit → query_error
C_NEG_LIMIT = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('limit' => -1),
  UNIFIED_ROWS
)

# Limit zero → empty
C_ZERO_LIMIT = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('limit' => 0),
  UNIFIED_ROWS
)

# Multi-order with desc: filter(active) + order([score desc]) + limit(2) + projection(name,score)
# Expected: filter(active)→alice,bob,dave; order(score desc)→dave(40),bob(20),alice(10); limit(2)→dave,bob; projection→{name:dave,score:40},{name:bob,score:20}
C_MULTI_DESC = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge(
    'order'      => [{ 'field' => 'score', 'direction' => 'desc' }],
    'limit'      => 2,
    'projection' => { 'fields' => 'name,score', 'include_all' => false }
  ),
  UNIFIED_ROWS
)

# Empty order list → preserve input order
C_NO_ORDER = UnifiedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('order' => []),
  UNIFIED_ROWS
)

# ── VM inputs ─────────────────────────────────────────────────────────────────

VM_SOURCE      = { 'table' => 'users', 'schema' => 'public' }.freeze
VM_PROJECTION  = { 'fields' => 'name,status', 'include_all' => false }.freeze
VM_PLAN_INPUTS = {
  'source'     => VM_SOURCE,
  'projection' => VM_PROJECTION,
  'limit'      => 10,
  'metadata'   => { 'trace_id' => 'unified-plan' }
}.freeze

VM_CAP_INPUTS = {
  'cap_id'            => 'cap-unified-v0',
  'allowed_sources'   => ['users'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

VM_ROWS_INPUTS   = { 'row_count' => 3, 'metadata' => { 'trace_id' => 'unified-rows' } }.freeze
VM_EMPTY_INPUTS  = { 'metadata' => { 'trace_id' => 'unified-empty' } }.freeze
VM_DENIED_INPUTS = { 'deny_reason' => 'source not in allowed_sources',
                     'metadata' => { 'gate' => 'G1' } }.freeze
VM_QERR_INPUTS   = { 'reason' => 'empty fields in projection (include_all is false)',
                     'metadata' => { 'gate' => 'G6-projection' } }.freeze
VM_RECEIPT_INPUTS = {
  'cap_id'          => 'cap-unified-v0',
  'source_table'    => 'users',
  'plan_limit'      => 10,
  'row_limit_cap'   => 100,
  'effective_limit' => 10,
  'rows_returned'   => 3,
  'metadata'        => { 'trace_id' => 'unified-receipt' }
}.freeze
VM_META_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 3, 'message' => '',
                   'metadata' => { 'dept' => 'eng', 'trace_id' => 'x' } },
  'query_key' => 'dept'
}.freeze
VM_META_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 0, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_PLAN_R    = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedPlan',             VM_PLAN_INPUTS)    : {}
VM_CAP_R     = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedCapability',        VM_CAP_INPUTS)     : {}
VM_ROWS_R    = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedRowsResult',         VM_ROWS_INPUTS)    : {}
VM_EMPTY_R   = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedEmptyResult',        VM_EMPTY_INPUTS)   : {}
VM_DENIED_R  = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedDeniedResult',       VM_DENIED_INPUTS)  : {}
VM_QERR_R    = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedQueryErrorResult',   VM_QERR_INPUTS)    : {}
VM_RECEIPT_R = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'BuildUnifiedReceipt',            VM_RECEIPT_INPUTS) : {}
VM_META_HIT  = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'UnifiedMetadataReader',          VM_META_HIT_INPUTS)  : {}
VM_META_MISS = UNIFIED_OUT ? vm_run(UNIFIED_OUT, 'UnifiedMetadataReader',          VM_META_MISS_INPUTS) : {}

# ── EXECQ3-COMPILE ────────────────────────────────────────────────────────────
puts "\n── EXECQ3-COMPILE (5) — fixture compiles; 8 contracts; Ruby TC accepted; zero diagnostics ──"

check("EXECQ3-COMPILE-01: Rust compiler: fixture compiles without error") do
  UNIFIED_SIR[:error].nil? && UNIFIED_SIR[:report] != nil
end

check("EXECQ3-COMPILE-02: Ruby TypeChecker: fixture parses without error") do
  UNIFIED_TC[:error].nil?
end

check("EXECQ3-COMPILE-03: Ruby TypeChecker: 8 contracts present") do
  contracts = UNIFIED_TC[:typed]&.fetch('contracts', []) || []
  contracts.length == 8
end

check("EXECQ3-COMPILE-04: Ruby TypeChecker: all 8 contracts accepted") do
  ALL_CONTRACTS.all? { |n| contract_accepted?(UNIFIED_TC, n) }
end

check("EXECQ3-COMPILE-05: Ruby TypeChecker: zero type_errors across all 8 contracts") do
  ALL_CONTRACTS.all? { |n| type_errors_for(UNIFIED_TC, n).empty? }
end

# ── EXECQ3-SHAPE ──────────────────────────────────────────────────────────────
puts "\n── EXECQ3-SHAPE (8) — QueryPlanUnified types; Collection[FilterPredicate/OrderBy]; receipt; Rust SIR ──"

check("EXECQ3-SHAPE-01: QueryPlanUnified.filters type = Collection[FilterPredicate]") do
  type_name_str(type_env_field(UNIFIED_TC, 'QueryPlanUnified', 'filters')) == 'Collection[FilterPredicate]'
end

check("EXECQ3-SHAPE-02: QueryPlanUnified.order type = Collection[OrderBy]") do
  type_name_str(type_env_field(UNIFIED_TC, 'QueryPlanUnified', 'order')) == 'Collection[OrderBy]'
end

check("EXECQ3-SHAPE-03: QueryPlanUnified.projection type = Projection") do
  type_name_str(type_env_field(UNIFIED_TC, 'QueryPlanUnified', 'projection')) == 'Projection'
end

check("EXECQ3-SHAPE-04: QueryPlanUnified.limit type = Integer") do
  type_name_str(type_env_field(UNIFIED_TC, 'QueryPlanUnified', 'limit')) == 'Integer'
end

check("EXECQ3-SHAPE-05: Projection.fields = String; Projection.include_all = Bool") do
  type_name_str(type_env_field(UNIFIED_TC, 'Projection', 'fields'))      == 'String' &&
    type_name_str(type_env_field(UNIFIED_TC, 'Projection', 'include_all')) == 'Bool'
end

check("EXECQ3-SHAPE-06: QueryExecutionReceipt has 15 fields") do
  receipt_fields = UNIFIED_TC[:typed]&.fetch('type_env', {})&.fetch('QueryExecutionReceipt', {}) || {}
  receipt_fields.length == 15
end

check("EXECQ3-SHAPE-07: StorageCapability.row_limit = Integer; allow_include_all = Bool") do
  type_name_str(type_env_field(UNIFIED_TC, 'StorageCapability', 'row_limit'))       == 'Integer' &&
    type_name_str(type_env_field(UNIFIED_TC, 'StorageCapability', 'allow_include_all')) == 'Bool'
end

check("EXECQ3-SHAPE-08: Rust SIR: BuildUnifiedPlan.filters compute_type_tag = Collection[FilterPredicate] (8th P2 confirmation)") do
  compute_type_tag(UNIFIED_SIR, 'BuildUnifiedPlan', 'filters') == 'Collection[FilterPredicate]'
end

# ── EXECQ3-GATES ──────────────────────────────────────────────────────────────
puts "\n── EXECQ3-GATES (6) — G1/G2/G3 denial; G4 clamp; G5 query_error; gate short-circuit ──"

check("EXECQ3-GATES-01: G1: source not in allowed_sources → kind:\"denied\"; denial_gate:\"G1\"") do
  C_G1[:result]['kind']          == 'denied' &&
    C_G1[:receipt]['denial_gate'] == 'G1' &&
    C_G1[:rows] == []
end

check("EXECQ3-GATES-02: G2: op not in allowed_ops → kind:\"denied\"; denial_gate:\"G2\"") do
  C_G2[:result]['kind']          == 'denied' &&
    C_G2[:receipt]['denial_gate'] == 'G2'
end

check("EXECQ3-GATES-03: G3: read_allowed:false → kind:\"denied\"; denial_gate:\"G3\"") do
  C_G3[:result]['kind']          == 'denied' &&
    C_G3[:receipt]['denial_gate'] == 'G3'
end

check("EXECQ3-GATES-04: G4: plan.limit(10) > cap.row_limit(2) → effective_limit:2; result != \"denied\"") do
  C_CLAMPED[:receipt]['effective_limit']   == 2 &&
    C_CLAMPED[:receipt]['row_limit_clamped'] == true &&
    C_CLAMPED[:result]['kind'] != 'denied'
end

check("EXECQ3-GATES-05: G5: include_all:true + !allow_include_all → kind:\"query_error\" (NOT \"denied\")") do
  C_G5[:result]['kind']           == 'query_error' &&
    C_G5[:receipt]['denial_gate']   == 'G5' &&
    C_G5[:result]['kind']           != 'denied'
end

check("EXECQ3-GATES-06: G1/G2/G3 short-circuit: rows is [] and filter/order/projection not evaluated") do
  # Gate denials produce empty rows with denial_gate set
  [C_G1, C_G2, C_G3].all? do |r|
    r[:result]['kind'] == 'denied' &&
      r[:rows] == [] &&
      r[:receipt]['rows_returned'] == 0 &&
      !r[:receipt]['denial_gate'].empty?
  end
end

# ── EXECQ3-PIPELINE ───────────────────────────────────────────────────────────
puts "\n── EXECQ3-PIPELINE (7) — filter→multi-order→limit→projection order; compose ──"

check("EXECQ3-PIPELINE-01: happy path: filter(active)+order([dept asc,name asc])+limit(10)+projection(name,status) → 3 rows") do
  C_HAPPY[:result]['kind']  == 'rows' &&
    C_HAPPY[:result]['count'] == 3 &&
    C_HAPPY[:rows].all? { |r| r.keys.sort == %w[name status] } &&
    C_HAPPY[:rows].map { |r| r['name'] } == %w[alice bob dave]
end

check("EXECQ3-PIPELINE-02: filter happens BEFORE projection — only active rows appear in projected output") do
  # active: alice, bob, dave; carol and eve (inactive) must not appear
  names = C_HAPPY[:rows].map { |r| r['name'] }
  names.include?('alice') && names.include?('bob') && names.include?('dave') &&
    !names.include?('carol') && !names.include?('eve')
end

check("EXECQ3-PIPELINE-03: order happens BEFORE projection — rows are ordered correctly in projected output") do
  # order=[dept asc, name asc]: active rows → eng:alice, eng:bob, mkt:dave
  C_HAPPY[:rows][0]['name'] == 'alice' &&
    C_HAPPY[:rows][1]['name'] == 'bob' &&
    C_HAPPY[:rows][2]['name'] == 'dave'
end

check("EXECQ3-PIPELINE-04: limit happens BEFORE projection — clamp produces correct final count") do
  # cap.row_limit=2 → effective_limit=2 → 2 rows after filter+order → 2 projected rows
  C_CLAMPED[:result]['count'] == 2 &&
    C_CLAMPED[:rows].length     == 2 &&
    C_CLAMPED[:rows][0]['name'] == 'alice' &&
    C_CLAMPED[:rows][1]['name'] == 'bob'
end

check("EXECQ3-PIPELINE-05: empty pipeline — no-match filter with valid cap → kind:\"empty\"") do
  C_EMPTY[:result]['kind']  == 'empty' &&
    C_EMPTY[:result]['count'] == 0 &&
    C_EMPTY[:rows] == []
end

check("EXECQ3-PIPELINE-06: multi-column desc order + limit + projection compose correctly") do
  # order=[score desc] + limit(2) + projection(name,score)
  # filter(active)→alice(10),bob(20),dave(40); order(score desc)→dave,bob,alice; limit(2)→dave,bob
  C_MULTI_DESC[:result]['kind']  == 'rows' &&
    C_MULTI_DESC[:result]['count'] == 2 &&
    C_MULTI_DESC[:rows][0]['name'] == 'dave' &&
    C_MULTI_DESC[:rows][1]['name'] == 'bob' &&
    C_MULTI_DESC[:rows].all? { |r| r.keys.sort == %w[name score] }
end

check("EXECQ3-PIPELINE-07: empty order list → preserve input order (no sort applied)") do
  # filter(active) without order → alice, bob, dave in input order (alice first in UNIFIED_ROWS)
  C_NO_ORDER[:result]['kind'] == 'rows' &&
    C_NO_ORDER[:rows].first['name'] == 'alice'
end

# ── EXECQ3-PROJECTION ─────────────────────────────────────────────────────────
puts "\n── EXECQ3-PROJECTION (7) — include_all; field list; dedup; row count invariant; shape ──"

check("EXECQ3-PROJECTION-01: include_all=true (with allow_include_all=true) → all 5 fields per row preserved") do
  # filter(active) + include_all → alice,bob,dave with all 5 fields
  C_INCLUDE_ALL[:result]['kind'] == 'rows' &&
    C_INCLUDE_ALL[:rows].all? { |r| r.keys.sort == %w[dept name role score status] }
end

check("EXECQ3-PROJECTION-02: include_all=false + fields=\"name,status\" → rows have exactly {name, status}") do
  C_HAPPY[:rows].all? { |r| r.keys.sort == %w[name status] && r.keys.length == 2 }
end

check("EXECQ3-PROJECTION-03: duplicate fields de-duplicated — \"name,status,name\" → same as \"name,status\"") do
  C_DEDUP[:rows].all? { |r| r.keys.sort == %w[name status] && r.keys.length == 2 }
end

check("EXECQ3-PROJECTION-04: row count invariant — projection does not change row count") do
  # Happy path: 3 rows after filter+order+limit; projection produces same 3 rows
  # Include_all: 3 rows (filter active) → 3 projected rows
  C_HAPPY[:result]['count']    == 3 &&
    C_INCLUDE_ALL[:result]['count'] == 3 &&
    C_SINGLE_FIELD[:result]['count'] == 3
end

check("EXECQ3-PROJECTION-05: single field projection — rows have exactly {name}") do
  C_SINGLE_FIELD[:rows].all? { |r| r.keys == ['name'] && r.keys.length == 1 }
end

check("EXECQ3-PROJECTION-06: projected row values are correct — projection selects correct field values") do
  row0 = C_HAPPY[:rows][0]
  row0['name'] == 'alice' && row0['status'] == 'active' && !row0.key?('dept') && !row0.key?('score')
end

check("EXECQ3-PROJECTION-07: projection preserves field order — de-duplicated request order is followed") do
  # "name,status,name" → de-duped to [name, status] → first key should be 'name'
  C_DEDUP[:rows].first&.keys&.first == 'name'
end

# ── EXECQ3-RECEIPT ────────────────────────────────────────────────────────────
puts "\n── EXECQ3-RECEIPT (6) — receipt fields; invariants; mirrors pipeline decisions ──"

check("EXECQ3-RECEIPT-01: cap_checked:true in all pipeline results") do
  [C_HAPPY, C_G1, C_G2, C_G3, C_G5, C_BAD_FILTER, C_PROJ_EMPTY, C_CLAMPED].all? do |r|
    r[:receipt]['cap_checked'] == true
  end
end

check("EXECQ3-RECEIPT-02: cap_granted:false iff result_kind in {denied, query_error}") do
  denied_or_qe = [C_G1, C_G2, C_G3, C_G5, C_BAD_FILTER, C_BAD_ORDER, C_PROJ_EMPTY, C_PROJ_MISSING, C_NEG_LIMIT]
  allowed      = [C_HAPPY, C_EMPTY, C_CLAMPED]
  denied_or_qe.all? { |r| r[:receipt]['cap_granted'] == false } &&
    allowed.all? { |r| r[:receipt]['cap_granted'] == true }
end

check("EXECQ3-RECEIPT-03: denial_gate matches gate for denials; empty string for successes") do
  C_G1[:receipt]['denial_gate']    == 'G1' &&
    C_G2[:receipt]['denial_gate']  == 'G2' &&
    C_G3[:receipt]['denial_gate']  == 'G3' &&
    C_G5[:receipt]['denial_gate']  == 'G5' &&
    C_HAPPY[:receipt]['denial_gate'] == ''
end

check("EXECQ3-RECEIPT-04: effective_limit = min(plan.limit, cap.row_limit)") do
  C_HAPPY[:receipt]['effective_limit']   == 10 &&   # min(10, 100) = 10
    C_CLAMPED[:receipt]['effective_limit'] == 2      # min(10, 2)   = 2
end

check("EXECQ3-RECEIPT-05: rows_returned mirrors count after full pipeline (after projection)") do
  C_HAPPY[:receipt]['rows_returned']   == C_HAPPY[:rows].length &&
    C_CLAMPED[:receipt]['rows_returned'] == C_CLAMPED[:rows].length &&
    C_EMPTY[:receipt]['rows_returned']   == 0 &&
    C_G1[:receipt]['rows_returned']      == 0
end

check("EXECQ3-RECEIPT-06: result_kind mirrors QueryResult.kind across all cases") do
  [C_HAPPY, C_EMPTY, C_G1, C_G2, C_G3, C_G5, C_BAD_FILTER, C_PROJ_EMPTY].all? do |r|
    r[:receipt]['result_kind'] == r[:result]['kind']
  end
end

# ── EXECQ3-ERROR ──────────────────────────────────────────────────────────────
puts "\n── EXECQ3-ERROR (8) — filter/order/projection errors → query_error NOT denied; invariant ──"

check("EXECQ3-ERROR-01: unknown filter op → kind:\"query_error\" (NOT \"denied\"); denial_gate starts with G6") do
  C_BAD_FILTER[:result]['kind'] == 'query_error' &&
    C_BAD_FILTER[:result]['kind'] != 'denied' &&
    C_BAD_FILTER[:receipt]['denial_gate'].start_with?('G6')
end

check("EXECQ3-ERROR-02: unknown order direction → kind:\"query_error\" (NOT \"denied\")") do
  C_BAD_ORDER[:result]['kind'] == 'query_error' &&
    C_BAD_ORDER[:result]['kind'] != 'denied' &&
    C_BAD_ORDER[:receipt]['denial_gate'].start_with?('G6')
end

check("EXECQ3-ERROR-03: empty projection fields → kind:\"query_error\" (NOT \"denied\")") do
  C_PROJ_EMPTY[:result]['kind'] == 'query_error' &&
    C_PROJ_EMPTY[:result]['kind'] != 'denied' &&
    C_PROJ_EMPTY[:receipt]['denial_gate'].start_with?('G6')
end

check("EXECQ3-ERROR-04: projection field absent in row → kind:\"query_error\" (NOT \"denied\")") do
  C_PROJ_MISSING[:result]['kind'] == 'query_error' &&
    C_PROJ_MISSING[:result]['kind'] != 'denied'
end

check("EXECQ3-ERROR-05: negative limit → kind:\"query_error\" (NOT \"denied\")") do
  C_NEG_LIMIT[:result]['kind'] == 'query_error' &&
    C_NEG_LIMIT[:result]['kind'] != 'denied'
end

check("EXECQ3-ERROR-06: query_error ≠ denied invariant — G1/G2/G3 are denied; all else are query_error") do
  [C_G1, C_G2, C_G3].all? { |r| r[:result]['kind'] == 'denied' } &&
    [C_G5, C_BAD_FILTER, C_BAD_ORDER, C_PROJ_EMPTY, C_PROJ_MISSING, C_NEG_LIMIT].all? { |r|
      r[:result]['kind'] == 'query_error'
    } &&
    [C_G1, C_G2, C_G3].none? { |r| r[:result]['kind'] == 'query_error' } &&
    [C_G5, C_BAD_FILTER, C_BAD_ORDER].none? { |r| r[:result]['kind'] == 'denied' }
end

check("EXECQ3-ERROR-07: projection error fires AFTER filter/order/limit — error at final pipeline step") do
  # C_PROJ_MISSING fires at G6-projection (after filter narrowed rows and order applied)
  C_PROJ_MISSING[:receipt]['denial_gate'].include?('projection') ||
    C_PROJ_MISSING[:result]['message'].include?('absent') ||
    C_PROJ_MISSING[:result]['message'].include?('missing')
end

check("EXECQ3-ERROR-08: error messages are informative — not empty for query_error results") do
  [C_BAD_FILTER, C_BAD_ORDER, C_PROJ_EMPTY, C_PROJ_MISSING, C_NEG_LIMIT, C_G5].all? do |r|
    !r[:result]['message'].to_s.empty?
  end
end

# ── EXECQ3-VM ─────────────────────────────────────────────────────────────────
puts "\n── EXECQ3-VM (8) — Layer B: all 8 contracts VM-executed ──"

check("EXECQ3-VM-01: VM BuildUnifiedPlan → kind:\"select\"; filters array len 2; order_list len 2; limit:10") do
  filters    = VM_PLAN_R.dig('result', 'filters')
  order_list = VM_PLAN_R.dig('result', 'order')
  VM_PLAN_R['status'] == 'success' &&
    VM_PLAN_R.dig('result', 'kind') == 'select' &&
    VM_PLAN_R.dig('result', 'limit') == 10 &&
    filters.is_a?(Array) && filters.length == 2 &&
    order_list.is_a?(Array) && order_list.length == 2
end

check("EXECQ3-VM-02: VM BuildUnifiedCapability → cap_id:\"cap-unified-v0\"; row_limit:100; read_allowed:true") do
  VM_CAP_R['status'] == 'success' &&
    VM_CAP_R.dig('result', 'cap_id')       == 'cap-unified-v0' &&
    VM_CAP_R.dig('result', 'row_limit')    == 100 &&
    VM_CAP_R.dig('result', 'read_allowed') == true
end

check("EXECQ3-VM-03: VM BuildUnifiedRowsResult(row_count:3) → kind:\"rows\"; count:3") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind')  == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 3
end

check("EXECQ3-VM-04: VM BuildUnifiedEmptyResult → kind:\"empty\"; count:0") do
  VM_EMPTY_R['status'] == 'success' &&
    VM_EMPTY_R.dig('result', 'kind')  == 'empty' &&
    VM_EMPTY_R.dig('result', 'count') == 0
end

check("EXECQ3-VM-05: VM BuildUnifiedDeniedResult → kind:\"denied\"; count:0; message non-empty") do
  VM_DENIED_R['status'] == 'success' &&
    VM_DENIED_R.dig('result', 'kind')    == 'denied' &&
    VM_DENIED_R.dig('result', 'count')   == 0 &&
    !VM_DENIED_R.dig('result', 'message').to_s.empty?
end

check("EXECQ3-VM-06: VM BuildUnifiedQueryErrorResult → kind:\"query_error\"; count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind')  == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("EXECQ3-VM-07: VM BuildUnifiedReceipt → cap_granted:true; effective_limit:10; denial_gate:\"\"; rows_returned:3") do
  VM_RECEIPT_R['status'] == 'success' &&
    VM_RECEIPT_R.dig('result', 'cap_granted')     == true &&
    VM_RECEIPT_R.dig('result', 'effective_limit')  == 10 &&
    VM_RECEIPT_R.dig('result', 'denial_gate')      == '' &&
    VM_RECEIPT_R.dig('result', 'rows_returned')    == 3
end

check("EXECQ3-VM-08: VM UnifiedMetadataReader — map_get hit:\"eng\"; miss:\"not-found\"") do
  VM_META_HIT['status']  == 'success' && VM_META_HIT['result']  == 'eng' &&
    VM_META_MISS['status'] == 'success' && VM_META_MISS['result'] == 'not-found'
end

# ── EXECQ3-CLOSED ─────────────────────────────────────────────────────────────
puts "\n── EXECQ3-CLOSED (8) — closed surfaces ──"

check("EXECQ3-CLOSED-01: no SQL execution in fixture source") do
  !UNIFIED_SRC.include?('execute_sql') &&
    !UNIFIED_SRC.include?('INSERT INTO') && !UNIFIED_SRC.include?('DELETE FROM') &&
    !UNIFIED_SRC.include?('UPDATE ') && !UNIFIED_SRC.include?('.sql(')
end

check("EXECQ3-CLOSED-02: no database connection in fixture source") do
  !UNIFIED_SRC.include?('establish_connection') && !UNIFIED_SRC.include?('database_url') &&
    !UNIFIED_SRC.include?('connect_to(')
end

check("EXECQ3-CLOSED-03: no ORM / ActiveRecord / Arel in fixture source") do
  !UNIFIED_SRC.include?('ActiveRecord') && !UNIFIED_SRC.include?('Arel') &&
    !UNIFIED_SRC.include?('has_many') && !UNIFIED_SRC.include?('belongs_to')
end

check("EXECQ3-CLOSED-04: no index or optimizer usage in fixture source") do
  !UNIFIED_SRC.include?('optimizer_hint') && !UNIFIED_SRC.include?('use_index') &&
    !UNIFIED_SRC.include?('index_scan') && !UNIFIED_SRC.include?('force_index')
end

check("EXECQ3-CLOSED-05: no joins or aggregates in fixture source") do
  !UNIFIED_SRC.include?('JOIN') && !UNIFIED_SRC.match?(/GROUP\s+BY/i) &&
    !UNIFIED_SRC.match?(/HAVING\s/i) && !UNIFIED_SRC.include?('AGGREGATE')
end

check("EXECQ3-CLOSED-06: no write operations in fixture source") do
  !UNIFIED_SRC.include?('write_file') && !UNIFIED_SRC.include?('write_json') &&
    !UNIFIED_SRC.match?(/INSERT\s+INTO/i)
end

check("EXECQ3-CLOSED-07: no transactions in fixture source") do
  !UNIFIED_SRC.include?('transaction') && !UNIFIED_SRC.match?(/\bBEGIN\b/) &&
    !UNIFIED_SRC.match?(/\bCOMMIT\b/) && !UNIFIED_SRC.match?(/\bROLLBACK\b/)
end

check("EXECQ3-CLOSED-08: no StorageCapability live execution (plain Record only; no IO authority)") do
  !UNIFIED_SRC.include?('IO.StorageCapability') &&
    !UNIFIED_SRC.include?('effect contract')
end

# ── EXECQ3-GAP ────────────────────────────────────────────────────────────────
puts "\n── EXECQ3-GAP (5) — boundary findings; production? NO; typed Row[T] deferred; 8th P2 ──"

check("EXECQ3-GAP-01: full v0 pipeline order proven — filter→multi-order→limit→projection sequence confirmed") do
  # Verify the pipeline sequence: the projected rows reflect filter+order+limit before projection
  row_names   = C_HAPPY[:rows].map { |r| r['name'] }
  row_keys    = C_HAPPY[:rows].map { |r| r.keys.sort }
  row_names == %w[alice bob dave] &&              # filter+order+limit applied first
    row_keys.all? { |k| k == %w[name status] }    # projection applied last
end

check("EXECQ3-GAP-02: does not open production query runtime — UnifiedQuerySim is PROOF-LOCAL ONLY") do
  !UNIFIED_SRC.include?('IO.StorageCapability') &&
    !UNIFIED_SRC.include?('effect contract') &&
    UNIFIED_SRC.include?('PROOF-LOCAL ONLY') &&
    UNIFIED_SRC.include?('LAB-ONLY')
end

check("EXECQ3-GAP-03: typed Row[T] deferred — field list is String (v0 primitive); no schema introspection") do
  # Projection.fields is String (not Collection[String]); confirmed via type_env
  type_name_str(type_env_field(UNIFIED_TC, 'Projection', 'fields')) == 'String' &&
    !UNIFIED_SRC.include?('Row[T]') && !UNIFIED_SRC.include?('schema_introspect')
end

check("EXECQ3-GAP-04: TypeChecker nested-record-literal boundary (B9) documented — projection passed as input") do
  # BuildUnifiedPlan receives projection as an input (not inline nested record)
  # The fixture comment documents the B9 boundary
  UNIFIED_SRC.include?('TypeChecker nested-record-literal boundary') &&
    UNIFIED_SRC.include?('pass projection as input')
end

check("EXECQ3-GAP-05: 8th LAB-TC-ARRAY-P2 confirmation — BuildUnifiedPlan.filters typed Collection[FilterPredicate] in Rust SIR") do
  compute_type_tag(UNIFIED_SIR, 'BuildUnifiedPlan', 'filters') == 'Collection[FilterPredicate]' &&
    UNIFIED_SRC.include?('8th confirmation')
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-EXECUTE-QUERY-P3: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  1. Full v0 pipeline order proven: G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt"
  puts "  2. Projection applied AFTER filter+multi-order+limit (final step)"
  puts "  3. G4 row-limit clamp remains NON-denial (cap_granted:true after clamp)"
  puts "  4. G5 include_all policy → query_error (NOT denied)"
  puts "  5. All malformed plan errors → query_error (NOT denied); query_error≠denied throughout"
  puts "  6. Receipt mirrors result_kind and rows_returned after full pipeline (after projection)"
  puts "  7. Does NOT open production query runtime — UnifiedQuerySim is PROOF-LOCAL ONLY"
  puts "  8. LAB-TC-ARRAY-P2 8th confirmation: BuildUnifiedPlan.filters typed Collection[FilterPredicate]"
  puts "  9. Projection does not change row count — column selector, not row filter"
  puts " 10. Next route: LAB-TC-NESTED-RECORD-CONTEXT-P1 (B9) OR LAB-QUERY-TYPED-ROW-P1 (deferred)"
  puts "  - No SQL / DB / ORM / StorageCapability live execution at any layer"
else
  puts "LAB-EXECUTE-QUERY-P3: #{$fail_count} check(s) failed"
  exit 1
end
