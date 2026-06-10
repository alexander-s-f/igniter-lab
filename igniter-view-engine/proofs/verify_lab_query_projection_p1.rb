#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_query_projection_p1.rb
# LAB-QUERY-PROJECTION-P1 — 62 checks
#
# Defines and proves proof-local projection semantics for QueryPlan.projection
# over mocked rows. Answers: given a filtered/ordered/limited row set, what
# does Projection do to each row?
#
# Core formula:
#   Projection v0  =  mocked rows  +  Projection{fields,include_all}
#                  →  shaped rows (field-subset or full row) + QueryResult
#   Projection v0  ≠  SQL SELECT column list  ≠  DB schema introspection
#   Projection v0  ≠  typed Row[T]  ≠  Collection[String] field list (deferred)
#   ProjectionSim  =  PROOF-LOCAL ONLY  ≠  production projection evaluation runtime
#
# v0 projection semantics (Layer C):
#   include_all == true  → all row fields unchanged (full passthrough)
#     subject to G5 policy gate: allow_include_all==false → query_error before projection
#   include_all == false → fields parsed as comma-separated string
#     parse: split(",").map(&:strip).reject(&:empty?)
#     empty after parsing      → query_error (malformed plan)
#     field absent in row      → query_error (fail-closed)
#     duplicate field requests → de-duplicate preserving first occurrence
#     field order              → follows request order (v0 best-effort;
#                                 Ruby Hash preserves insertion order in >= 1.9)
#   projection does not change row count
#   projection applied AFTER filter → multi-order → limit
#   query_error ≠ denied throughout pipeline
#
# Pipeline position:
#   G1/G2/G3 denial → G4 clamp → G5 include_all policy → G6 filter+order+limit → projection
#
# Sections:
#   PROJ-COMPILE     (5)  — fixture compiles; 7 contracts; Ruby TC accepted
#   PROJ-SHAPE       (7)  — Projection fields/include_all; QueryPlanProjection types; Rust SIR
#   PROJ-INCLUDE-ALL (5)  — include_all true: full passthrough, all fields, row count unchanged
#   PROJ-FIELDS      (8)  — single field; multiple fields; field order; no extras; whitespace; dedup
#   PROJ-PIPELINE    (6)  — projection after filter/order/limit; row count preserved; composes
#   PROJ-POLICY      (5)  — include_all + allow_include_all=false → query_error; not denied
#   PROJ-ERROR       (6)  — empty fields, missing field, query_error≠denied, messages distinct
#   PROJ-VM          (7)  — Layer B: all 7 contracts VM-executed
#   PROJ-CLOSED      (8)  — no SQL/DB/ORM/optimizer/joins/writes/storage/persistence
#   PROJ-GAP         (5)  — deferred: typed row, Collection[String], schema introspection
#
# Total: 62 checks
#
# Depends on:
#   LAB-EXECUTE-QUERY-P2      (integrated mocked pipeline — 73/73)
#   LAB-QUERY-MULTI-ORDER-P1  (Collection[OrderBy] — 64/64)
#   LAB-FILTER-EVAL-P1        (filter predicate evaluation — 50/50)
#   LAB-QUERY-ORDER-LIMIT-P1  (order/limit semantics — 54/54)
#   LAB-TC-ARRAY-P2           (Collection[T] from record-field context — 19/19)
#   LAB-TC-ARRAY-P1           (empty array in Collection context — 27/27)
#   PROP-043-P5               (Map[String,String] production TypeChecker — 55/55)
#   LAB-VM-MAP-P1             (VM map_get/or_else — 48/48)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_query_projection_p1.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_execution' / 'projection_query.ig').to_s

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

def compile_path(path, tag = 'proj')
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
  tmpfile = Tempfile.new(['proj_inputs', '.json'])
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

# ── Layer C: Proof-local projection simulator ──────────────────────────────────
#
# ProjectionSim: proof-local semantics evaluator for Projection row-shaping.
#
# Semantics:
#   include_all == true  → return all row fields unchanged (full passthrough).
#   include_all == false → parse fields as comma-separated string.
#     Empty field list after parsing → query_error.
#     Field absent in row → query_error (fail-closed).
#     Duplicate fields → de-duplicate preserving first occurrence.
#     Field order → projected row keys follow de-duplicated request order.
#   Projection does not change row count.
#   Projection applied AFTER filter → multi-order → limit.
#   query_error ≠ denied throughout.
#
# ProjectionSim is PROOF-LOCAL ONLY — not a production projection evaluation runtime.

module ProjectionSim
  def self.parse_fields(fields_str)
    fields_str.to_s.split(',').map(&:strip).reject(&:empty?)
  end

  def self.project_rows(rows, projection)
    include_all = projection.fetch('include_all', false)
    return { kind: 'ok', rows: rows } if include_all

    fields_str = projection.fetch('fields', '')
    field_list = parse_fields(fields_str)

    if field_list.empty?
      return { kind: 'query_error', message: 'empty fields in projection (include_all is false)' }
    end

    # De-duplicate preserving first occurrence
    seen       = Set.new
    dedup_list = field_list.select { |f| seen.add?(f) }

    projected_rows = rows.map do |row|
      missing = dedup_list.find { |f| !row.key?(f) }
      if missing
        return { kind: 'query_error', message: "projection field absent in row: #{missing}" }
      end
      projected = {}
      dedup_list.each { |f| projected[f] = row[f] }
      projected
    end

    { kind: 'ok', rows: projected_rows }
  end
end

# ProjectionQuerySim: integrated pipeline with gates + filter + multi-order + limit + projection.
# Gate/filter/sort logic mirrors MultiOrderQuerySim from LAB-QUERY-MULTI-ORDER-P1.
# Projection step added as final row-shaping stage.
# ProjectionQuerySim is PROOF-LOCAL ONLY — not a production integrated query runtime.

module ProjectionQuerySim
  KNOWN_DIRECTIONS  = %w[asc desc].freeze
  KNOWN_FILTER_OPS  = %w[eq neq contains prefix].freeze

  def self.execute(cap, plan, mocked_rows)
    source_table  = plan.dig('source', 'table') || ''
    projection    = plan.fetch('projection', { 'fields' => '', 'include_all' => false })
    include_all   = projection.fetch('include_all', false)
    plan_limit    = plan.fetch('limit', 0)
    row_limit     = cap.fetch('row_limit', 0)
    deny_reason   = cap.fetch('deny_reason', '')
    filters       = plan.fetch('filters', [])
    order_list    = plan.fetch('order', [])
    metadata      = plan.fetch('metadata', {})

    # G1: source allowlist
    unless cap.fetch('allowed_sources', []).include?(source_table)
      msg = deny_reason.empty? ? 'source not in allowed_sources' : deny_reason
      return denial('G1', msg, metadata)
    end

    # G2: op allowlist
    unless cap.fetch('allowed_ops', []).include?('read')
      return denial('G2', 'op not in allowed_ops', metadata)
    end

    # G3: read master switch
    unless cap.fetch('read_allowed', false)
      return denial('G3', 'read_allowed is false', metadata)
    end

    # G4: row-limit clamp (NOT denial)
    effective_limit = [plan_limit, row_limit].min
    clamped         = effective_limit < plan_limit

    # G5: include_all policy → query_error (NOT denied)
    if include_all && !cap.fetch('allow_include_all', false)
      return {
        result: qe('include_all not permitted', metadata),
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    # Negative effective_limit
    if effective_limit < 0
      return {
        result: qe('negative limit', metadata),
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    # G6a: filter
    bad_op = filters.find { |f| !KNOWN_FILTER_OPS.include?(f.fetch('op', '')) }
    if bad_op
      return {
        result: qe("unknown filter operator: #{bad_op['op']}", metadata),
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end
    filtered = mocked_rows.select { |row| filters.all? { |f| row_matches?(row, f) } }

    # G6b: multi-order
    unless order_list.empty?
      sort_out = sort_rows(filtered, order_list)
      if sort_out[:kind] == 'query_error'
        return {
          result: qe(sort_out[:message], metadata),
          rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
        }
      end
      filtered = sort_out[:rows]
    end

    # G6c: limit
    if effective_limit == 0
      return {
        result: { 'kind' => 'empty', 'count' => 0, 'message' => 'limit zero', 'metadata' => metadata },
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end
    limited = filtered.first(effective_limit)

    # Projection step (after limit)
    proj_out = ProjectionSim.project_rows(limited, projection)
    if proj_out[:kind] == 'query_error'
      return {
        result: qe(proj_out[:message], metadata),
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    final_rows = proj_out[:rows]
    kind       = final_rows.empty? ? 'empty' : 'rows'
    {
      result: { 'kind' => kind, 'count' => final_rows.length, 'message' => '', 'metadata' => metadata },
      rows: final_rows, denial_gate: '', clamped: clamped, effective_limit: effective_limit
    }
  end

  private_class_method def self.denial(gate, reason, metadata)
    {
      result: { 'kind' => 'denied', 'count' => 0, 'message' => reason, 'metadata' => metadata },
      rows: [], denial_gate: gate, clamped: false, effective_limit: 0
    }
  end

  private_class_method def self.qe(msg, metadata)
    { 'kind' => 'query_error', 'count' => 0, 'message' => msg, 'metadata' => metadata }
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
      return { kind: 'query_error', message: "empty direction in multi-order (field: #{field})" } if direction.empty?
      return { kind: 'query_error', message: "unknown direction: #{direction}" } unless KNOWN_DIRECTIONS.include?(direction)
    end
    order_list.each do |ob|
      field = ob.fetch('field', '')
      next if field.empty?
      missing = rows.find { |r| !r.key?(field) }
      return { kind: 'query_error', message: "order field absent: #{field}" } if missing
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
end

class ReverseComparable
  include Comparable
  attr_reader :val
  def initialize(val); @val = val.to_s; end
  def <=>(other); other.val.to_s <=> @val; end
end

# ── Test data ─────────────────────────────────────────────────────────────────
#
# PROJ_ROWS: 5 rows with name/status/dept/score/role for full pipeline testing.

PROJ_ROWS = [
  { 'name' => 'alice', 'status' => 'active',   'dept' => 'eng', 'score' => '10', 'role' => 'admin' },
  { 'name' => 'bob',   'status' => 'active',   'dept' => 'eng', 'score' => '20', 'role' => 'user'  },
  { 'name' => 'carol', 'status' => 'inactive', 'dept' => 'mkt', 'score' => '30', 'role' => 'user'  },
  { 'name' => 'dave',  'status' => 'active',   'dept' => 'mkt', 'score' => '40', 'role' => 'admin' },
  { 'name' => 'eve',   'status' => 'inactive', 'dept' => 'eng', 'score' => '50', 'role' => 'user'  },
].freeze

PROJ_META  = { 'trace_id' => 'proj-test' }.freeze
NO_FILTERS = [].freeze
HIGH_LIMIT = 100

PROJ_INCLUDE_ALL = { 'fields' => '', 'include_all' => true  }.freeze
PROJ_NAME_STATUS = { 'fields' => 'name,status', 'include_all' => false }.freeze
PROJ_NAME_ONLY   = { 'fields' => 'name',         'include_all' => false }.freeze
PROJ_THREE_FIELD = { 'fields' => 'name,dept,role', 'include_all' => false }.freeze
PROJ_EMPTY       = { 'fields' => '',              'include_all' => false }.freeze
PROJ_WHITESPACE  = { 'fields' => ' name , status ', 'include_all' => false }.freeze
PROJ_DEDUP       = { 'fields' => 'name,status,name', 'include_all' => false }.freeze
PROJ_MISSING     = { 'fields' => 'name,missing_col', 'include_all' => false }.freeze

BASE_CAP = {
  'cap_id'            => 'cap-proj-v0',
  'allowed_sources'   => ['users'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

CAP_ALLOW_ALL = BASE_CAP.merge('allow_include_all' => true).freeze

BASE_PLAN = {
  'kind'       => 'select',
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => PROJ_NAME_STATUS,
  'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
  'order'      => [{ 'field' => 'name', 'direction' => 'asc' }],
  'limit'      => HIGH_LIMIT,
  'metadata'   => { 'trace_id' => 'integ-proj' }
}.freeze

ALL_CONTRACTS = %w[
  BuildIncludeAllPlan BuildFieldsProjectionPlan BuildSingleFieldPlan
  BuildProjectionRowsResult BuildProjectionEmptyResult
  BuildProjectionQueryErrorResult ProjectionMetadataReader
].freeze

# ── Compile fixture and run TypeChecker ───────────────────────────────────────

PROJ_SIR = compile_path(FIXTURE_PATH, 'proj')
PROJ_TC  = run_fixture(FIXTURE_PATH)
PROJ_SRC = File.read(FIXTURE_PATH).force_encoding('UTF-8').freeze
PROJ_OUT = PROJ_SIR[:out_dir]

# ── Pre-compute Layer C results ───────────────────────────────────────────────

# include_all: all 5 rows, all fields unchanged
C_INCLUDE_ALL = ProjectionSim.project_rows(PROJ_ROWS, PROJ_INCLUDE_ALL)

# name,status: project to 2 fields
C_NAME_STATUS = ProjectionSim.project_rows(PROJ_ROWS, PROJ_NAME_STATUS)

# name only: single field
C_NAME_ONLY = ProjectionSim.project_rows(PROJ_ROWS, PROJ_NAME_ONLY)

# three fields
C_THREE_FIELD = ProjectionSim.project_rows(PROJ_ROWS, PROJ_THREE_FIELD)

# empty fields
C_EMPTY_FIELDS = ProjectionSim.project_rows(PROJ_ROWS, PROJ_EMPTY)

# whitespace in fields string
C_WHITESPACE = ProjectionSim.project_rows(PROJ_ROWS, PROJ_WHITESPACE)

# duplicate fields: name,status,name → de-dup to name,status
C_DEDUP = ProjectionSim.project_rows(PROJ_ROWS, PROJ_DEDUP)

# missing field: query_error
C_MISSING = ProjectionSim.project_rows(PROJ_ROWS, PROJ_MISSING)

# Empty row set — projection on empty input = no-op
C_EMPTY_ROWS = ProjectionSim.project_rows([], PROJ_NAME_STATUS)

# Integrated: active rows + name asc + name/status projection
C_INTEG = ProjectionQuerySim.execute(CAP_ALLOW_ALL, BASE_PLAN, PROJ_ROWS)

# Integrated: include_all=true with allow_include_all=true
C_INTEG_INCLUDE_ALL = ProjectionQuerySim.execute(
  CAP_ALLOW_ALL,
  BASE_PLAN.merge('projection' => PROJ_INCLUDE_ALL, 'filters' => [], 'order' => []),
  PROJ_ROWS
)

# Integrated: include_all=true with allow_include_all=false → G5 query_error
C_INTEG_POLICY = ProjectionQuerySim.execute(
  BASE_CAP,   # allow_include_all=false
  BASE_PLAN.merge('projection' => PROJ_INCLUDE_ALL),
  PROJ_ROWS
)

# Integrated: missing field in projection → query_error
C_INTEG_MISSING = ProjectionQuerySim.execute(
  CAP_ALLOW_ALL,
  BASE_PLAN.merge('projection' => PROJ_MISSING, 'filters' => []),
  PROJ_ROWS
)

# Integrated: G1 denial (source not allowed) → short-circuits before projection
C_INTEG_DENIED = ProjectionQuerySim.execute(
  BASE_CAP.merge('allowed_sources' => ['posts']),
  BASE_PLAN,
  PROJ_ROWS
)

# ── VM inputs ─────────────────────────────────────────────────────────────────

VM_SOURCE     = { 'table' => 'users', 'schema' => 'public' }.freeze
VM_FILTERS    = [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }].freeze
VM_LIMIT      = 10
VM_META       = { 'trace_id' => 'proj-vm' }.freeze

VM_INCL_ALL_PROJ = { 'fields' => '', 'include_all' => true  }.freeze
VM_FIELDS_PROJ   = { 'fields' => 'name,status', 'include_all' => false }.freeze
VM_SINGLE_PROJ   = { 'fields' => 'name', 'include_all' => false }.freeze

VM_PLAN_BASE = { 'source' => VM_SOURCE, 'filters' => VM_FILTERS, 'limit' => VM_LIMIT, 'metadata' => VM_META }.freeze

VM_INCL_ALL_PLAN_INPUTS = VM_PLAN_BASE.merge('projection' => VM_INCL_ALL_PROJ).freeze
VM_FIELDS_PLAN_INPUTS   = VM_PLAN_BASE.merge('projection' => VM_FIELDS_PROJ).freeze
VM_SINGLE_PLAN_INPUTS   = VM_PLAN_BASE.merge('projection' => VM_SINGLE_PROJ).freeze

VM_ROWS_INPUTS   = { 'row_count' => 3, 'metadata' => VM_META }.freeze
VM_EMPTY_INPUTS  = { 'metadata' => VM_META }.freeze
VM_QERR_INPUTS   = { 'reason' => 'empty fields in projection', 'metadata' => VM_META }.freeze
VM_META_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 3, 'message' => '',
                   'metadata' => { 'trace_id' => 'proj-vm', 'dept' => 'eng' } },
  'query_key' => 'dept'
}.freeze
VM_META_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 0, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_INCL_ALL_R  = PROJ_OUT ? vm_run(PROJ_OUT, 'BuildIncludeAllPlan',            VM_INCL_ALL_PLAN_INPUTS) : {}
VM_FIELDS_R    = PROJ_OUT ? vm_run(PROJ_OUT, 'BuildFieldsProjectionPlan',       VM_FIELDS_PLAN_INPUTS)   : {}
VM_SINGLE_R    = PROJ_OUT ? vm_run(PROJ_OUT, 'BuildSingleFieldPlan',            VM_SINGLE_PLAN_INPUTS)   : {}
VM_ROWS_R      = PROJ_OUT ? vm_run(PROJ_OUT, 'BuildProjectionRowsResult',       VM_ROWS_INPUTS)    : {}
VM_EMPTY_RES_R = PROJ_OUT ? vm_run(PROJ_OUT, 'BuildProjectionEmptyResult',      VM_EMPTY_INPUTS)   : {}
VM_QERR_R      = PROJ_OUT ? vm_run(PROJ_OUT, 'BuildProjectionQueryErrorResult', VM_QERR_INPUTS)    : {}
VM_META_HIT_R  = PROJ_OUT ? vm_run(PROJ_OUT, 'ProjectionMetadataReader',        VM_META_HIT_INPUTS)  : {}
VM_META_MISS_R = PROJ_OUT ? vm_run(PROJ_OUT, 'ProjectionMetadataReader',        VM_META_MISS_INPUTS) : {}

# ── PROJ-COMPILE ──────────────────────────────────────────────────────────────
puts "\n── PROJ-COMPILE (5) — fixture compiles; 7 contracts; Ruby TC accepted ──"

check("PROJ-COMPILE-01: Rust compiler: fixture compiles without error") do
  PROJ_SIR[:error].nil? && PROJ_SIR[:report] != nil
end

check("PROJ-COMPILE-02: Ruby TypeChecker: fixture parses without error") do
  PROJ_TC[:error].nil?
end

check("PROJ-COMPILE-03: Ruby TypeChecker: 7 contracts present") do
  contracts = PROJ_TC[:typed]&.fetch('contracts', []) || []
  contracts.length == 7
end

check("PROJ-COMPILE-04: Ruby TypeChecker: all 7 contracts accepted") do
  ALL_CONTRACTS.all? { |n| contract_accepted?(PROJ_TC, n) }
end

check("PROJ-COMPILE-05: Ruby TypeChecker: zero type_errors across all 7 contracts") do
  ALL_CONTRACTS.all? { |n| type_errors_for(PROJ_TC, n).empty? }
end

# ── PROJ-SHAPE ────────────────────────────────────────────────────────────────
puts "\n── PROJ-SHAPE (7) — Projection types; QueryPlanProjection; Rust SIR ──"

check("PROJ-SHAPE-01: Projection has 2 fields: fields and include_all") do
  proj = PROJ_TC[:typed]&.fetch('type_env', {})&.fetch('Projection', {}) || {}
  proj.length == 2 && proj.key?('fields') && proj.key?('include_all')
end

check("PROJ-SHAPE-02: Projection.fields type = String") do
  type_name_str(type_env_field(PROJ_TC, 'Projection', 'fields')) == 'String'
end

check("PROJ-SHAPE-03: Projection.include_all type = Bool") do
  type_name_str(type_env_field(PROJ_TC, 'Projection', 'include_all')) == 'Bool'
end

check("PROJ-SHAPE-04: QueryPlanProjection.projection type = Projection") do
  type_name_str(type_env_field(PROJ_TC, 'QueryPlanProjection', 'projection')) == 'Projection'
end

check("PROJ-SHAPE-05: QueryPlanProjection.filters type = Collection[FilterPredicate]") do
  type_name_str(type_env_field(PROJ_TC, 'QueryPlanProjection', 'filters')) == 'Collection[FilterPredicate]'
end

check("PROJ-SHAPE-06: QueryPlanProjection.order type = Collection[OrderBy]") do
  type_name_str(type_env_field(PROJ_TC, 'QueryPlanProjection', 'order')) == 'Collection[OrderBy]'
end

check("PROJ-SHAPE-07: Rust SIR: BuildFieldsProjectionPlan.order_list type_tag = Collection[OrderBy] (7th P2 confirmation)") do
  compute_type_tag(PROJ_SIR, 'BuildFieldsProjectionPlan', 'order_list') == 'Collection[OrderBy]'
end

# ── PROJ-INCLUDE-ALL ──────────────────────────────────────────────────────────
puts "\n── PROJ-INCLUDE-ALL (5) — include_all true: full passthrough ──"

check("PROJ-INCLUDE-ALL-01: include_all true returns all row fields unchanged") do
  C_INCLUDE_ALL[:kind] == 'ok' &&
    C_INCLUDE_ALL[:rows].length == 5 &&
    C_INCLUDE_ALL[:rows].first.keys.sort == %w[dept name role score status].sort
end

check("PROJ-INCLUDE-ALL-02: include_all true preserves all 5 fields per row") do
  C_INCLUDE_ALL[:rows].all? { |r| r.keys.length == 5 }
end

check("PROJ-INCLUDE-ALL-03: include_all true does not change row count") do
  C_INCLUDE_ALL[:rows].length == PROJ_ROWS.length
end

check("PROJ-INCLUDE-ALL-04: include_all true returns exact row values (spot check: alice.name)") do
  C_INCLUDE_ALL[:rows].first['name'] == 'alice'
end

check("PROJ-INCLUDE-ALL-05: include_all true is same as returning original rows (identity projection)") do
  C_INCLUDE_ALL[:rows] == PROJ_ROWS.to_a
end

# ── PROJ-FIELDS ───────────────────────────────────────────────────────────────
puts "\n── PROJ-FIELDS (8) — single field; multiple fields; whitespace; dedup ──"

check("PROJ-FIELDS-01: single field 'name' → each row has exactly one field") do
  C_NAME_ONLY[:kind] == 'ok' &&
    C_NAME_ONLY[:rows].all? { |r| r.keys == ['name'] }
end

check("PROJ-FIELDS-02: single field 'name' → correct values preserved") do
  C_NAME_ONLY[:rows].map { |r| r['name'] } == %w[alice bob carol dave eve]
end

check("PROJ-FIELDS-03: two fields 'name,status' → each row has exactly those 2 fields") do
  C_NAME_STATUS[:kind] == 'ok' &&
    C_NAME_STATUS[:rows].all? { |r| r.keys.sort == %w[name status].sort }
end

check("PROJ-FIELDS-04: two-field projection excludes non-requested fields (no dept/score/role)") do
  C_NAME_STATUS[:rows].all? { |r| !r.key?('dept') && !r.key?('score') && !r.key?('role') }
end

check("PROJ-FIELDS-05: three-field projection includes exactly name/dept/role") do
  C_THREE_FIELD[:kind] == 'ok' &&
    C_THREE_FIELD[:rows].all? { |r| r.keys.sort == %w[dept name role].sort }
end

check("PROJ-FIELDS-06: whitespace in fields string is stripped ('\ name\ ,\ status\ ')") do
  C_WHITESPACE[:kind] == 'ok' &&
    C_WHITESPACE[:rows].all? { |r| r.keys.sort == %w[name status].sort }
end

check("PROJ-FIELDS-07: duplicate field 'name,status,name' de-duplicated to 2 unique fields") do
  C_DEDUP[:kind] == 'ok' &&
    C_DEDUP[:rows].all? { |r| r.keys.length == 2 && r.keys.sort == %w[name status].sort }
end

check("PROJ-FIELDS-08: projection does not change row count (all 5 rows projected)") do
  [C_NAME_STATUS, C_NAME_ONLY, C_THREE_FIELD, C_DEDUP].all? { |r| r[:rows].length == 5 }
end

# ── PROJ-PIPELINE ─────────────────────────────────────────────────────────────
puts "\n── PROJ-PIPELINE (6) — projection after filter/order/limit; composes ──"

check("PROJ-PIPELINE-01: integrated pipeline (filter active + name asc + name/status proj) → 3 rows: alice,bob,dave") do
  C_INTEG[:result]['kind']  == 'rows' &&
    C_INTEG[:result]['count'] == 3 &&
    C_INTEG[:rows].map { |r| r['name'] } == %w[alice bob dave]
end

check("PROJ-PIPELINE-02: projected rows have only name/status (no dept/score/role)") do
  C_INTEG[:rows].all? { |r| r.keys.sort == %w[name status].sort }
end

check("PROJ-PIPELINE-03: projection after filter — inactive rows excluded before projection") do
  C_INTEG[:rows].all? { |r| r['status'] == 'active' }
end

check("PROJ-PIPELINE-04: projection applied AFTER order — sorted order preserved in projected rows") do
  C_INTEG[:rows].map { |r| r['name'] } == %w[alice bob dave]
end

check("PROJ-PIPELINE-05: projection on empty input returns ok with empty rows") do
  C_EMPTY_ROWS[:kind] == 'ok' && C_EMPTY_ROWS[:rows] == []
end

check("PROJ-PIPELINE-06: include_all=true in integrated pipeline returns all fields for all rows") do
  C_INTEG_INCLUDE_ALL[:result]['kind'] == 'rows' &&
    C_INTEG_INCLUDE_ALL[:result]['count'] == 5 &&
    C_INTEG_INCLUDE_ALL[:rows].all? { |r| r.keys.length == 5 }
end

# ── PROJ-POLICY ───────────────────────────────────────────────────────────────
puts "\n── PROJ-POLICY (5) — include_all policy gate; query_error not denied ──"

check("PROJ-POLICY-01: include_all=true + allow_include_all=false → kind:\"query_error\" (NOT \"denied\")") do
  C_INTEG_POLICY[:result]['kind'] == 'query_error' &&
    C_INTEG_POLICY[:result]['kind'] != 'denied'
end

check("PROJ-POLICY-02: include_all policy fires BEFORE projection (G5 gate, not projection step)") do
  # G5 denial_gate is '' (not a denial gate), result is query_error
  C_INTEG_POLICY[:result]['kind']  == 'query_error' &&
    C_INTEG_POLICY[:denial_gate]   == '' &&
    C_INTEG_POLICY[:rows]          == []
end

check("PROJ-POLICY-03: include_all=true + allow_include_all=true → proceeds to projection") do
  C_INTEG_INCLUDE_ALL[:result]['kind'] == 'rows' ||
    C_INTEG_INCLUDE_ALL[:result]['kind'] == 'empty'
end

check("PROJ-POLICY-04: G1 denial short-circuits before projection (rows=[], denial_gate=G1)") do
  C_INTEG_DENIED[:result]['kind']  == 'denied' &&
    C_INTEG_DENIED[:denial_gate]   == 'G1' &&
    C_INTEG_DENIED[:rows]          == []
end

check("PROJ-POLICY-05: query_error from policy is distinct from denied (different kind values)") do
  C_INTEG_POLICY[:result]['kind']  == 'query_error' &&
    C_INTEG_DENIED[:result]['kind'] == 'denied' &&
    C_INTEG_POLICY[:result]['kind'] != C_INTEG_DENIED[:result]['kind']
end

# ── PROJ-ERROR ────────────────────────────────────────────────────────────────
puts "\n── PROJ-ERROR (6) — empty fields; missing field; query_error≠denied ──"

check("PROJ-ERROR-01: empty fields string (include_all=false) → kind:\"query_error\"") do
  C_EMPTY_FIELDS[:kind] == 'query_error'
end

check("PROJ-ERROR-02: missing requested field → kind:\"query_error\" (NOT \"denied\")") do
  C_MISSING[:kind] == 'query_error' &&
    C_MISSING[:kind] != 'denied'
end

check("PROJ-ERROR-03: missing field in integrated pipeline → kind:\"query_error\" (NOT \"denied\")") do
  C_INTEG_MISSING[:result]['kind'] == 'query_error' &&
    C_INTEG_MISSING[:result]['kind'] != 'denied'
end

check("PROJ-ERROR-04: query_error ≠ denied: empty fields, missing field → query_error; G1 denial → denied") do
  [C_EMPTY_FIELDS, C_MISSING].all? { |r| r[:kind] == 'query_error' } &&
    C_INTEG_DENIED[:result]['kind'] == 'denied'
end

check("PROJ-ERROR-05: empty fields message mentions 'empty fields' or 'include_all'") do
  msg = C_EMPTY_FIELDS[:message] || ''
  msg.include?('empty') || msg.include?('fields')
end

check("PROJ-ERROR-06: missing field message mentions the absent field name") do
  msg = C_MISSING[:message] || ''
  msg.include?('missing_col')
end

# ── PROJ-VM ───────────────────────────────────────────────────────────────────
puts "\n── PROJ-VM (7) — Layer B: all 7 contracts VM-executed ──"

check("PROJ-VM-01: VM BuildIncludeAllPlan → kind:\"select\"; projection.include_all=true; projection.fields=\"\"") do
  proj = VM_INCL_ALL_R.dig('result', 'projection')
  VM_INCL_ALL_R['status'] == 'success' &&
    VM_INCL_ALL_R.dig('result', 'kind') == 'select' &&
    proj.is_a?(Hash) && proj['include_all'] == true && proj['fields'] == ''
end

check("PROJ-VM-02: VM BuildFieldsProjectionPlan → projection.fields=\"name,status\"; include_all=false; order 2-key") do
  proj  = VM_FIELDS_R.dig('result', 'projection')
  order = VM_FIELDS_R.dig('result', 'order')
  VM_FIELDS_R['status'] == 'success' &&
    proj.is_a?(Hash) && proj['fields'] == 'name,status' && proj['include_all'] == false &&
    order.is_a?(Array) && order.length == 2
end

check("PROJ-VM-03: VM BuildSingleFieldPlan → projection.fields=\"name\"; include_all=false; empty order") do
  proj  = VM_SINGLE_R.dig('result', 'projection')
  order = VM_SINGLE_R.dig('result', 'order')
  VM_SINGLE_R['status'] == 'success' &&
    proj.is_a?(Hash) && proj['fields'] == 'name' && proj['include_all'] == false &&
    order.is_a?(Array) && order.empty?
end

check("PROJ-VM-04: VM BuildProjectionRowsResult(row_count:3) → kind:\"rows\"; count:3") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind')  == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 3
end

check("PROJ-VM-05: VM BuildProjectionEmptyResult → kind:\"empty\"; count:0") do
  VM_EMPTY_RES_R['status'] == 'success' &&
    VM_EMPTY_RES_R.dig('result', 'kind')  == 'empty' &&
    VM_EMPTY_RES_R.dig('result', 'count') == 0
end

check("PROJ-VM-06: VM BuildProjectionQueryErrorResult → kind:\"query_error\"; count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind')  == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("PROJ-VM-07: VM ProjectionMetadataReader — map_get hit:\"eng\"; miss:\"not-found\"") do
  VM_META_HIT_R['status']  == 'success' && VM_META_HIT_R['result']  == 'eng' &&
    VM_META_MISS_R['status'] == 'success' && VM_META_MISS_R['result'] == 'not-found'
end

# ── PROJ-CLOSED ───────────────────────────────────────────────────────────────
puts "\n── PROJ-CLOSED (8) — closed surfaces ──"

check("PROJ-CLOSED-01: no SQL execution in fixture source") do
  !PROJ_SRC.include?('execute_sql') &&
    !PROJ_SRC.include?('INSERT INTO') && !PROJ_SRC.include?('DELETE FROM') &&
    !PROJ_SRC.include?('UPDATE ') && !PROJ_SRC.include?('.sql(')
end

check("PROJ-CLOSED-02: no database connection in fixture source") do
  !PROJ_SRC.include?('establish_connection') && !PROJ_SRC.include?('database_url') &&
    !PROJ_SRC.include?('connect_to(')
end

check("PROJ-CLOSED-03: no ORM / ActiveRecord / Arel in fixture source") do
  !PROJ_SRC.include?('ActiveRecord') && !PROJ_SRC.include?('Arel') &&
    !PROJ_SRC.include?('has_many') && !PROJ_SRC.include?('belongs_to')
end

check("PROJ-CLOSED-04: no index or optimizer usage in fixture source") do
  !PROJ_SRC.include?('optimizer_hint') && !PROJ_SRC.include?('use_index') &&
    !PROJ_SRC.include?('index_scan') && !PROJ_SRC.include?('force_index')
end

check("PROJ-CLOSED-05: no joins or aggregates in fixture source") do
  !PROJ_SRC.include?('JOIN') && !PROJ_SRC.match?(/GROUP\s+BY/i) &&
    !PROJ_SRC.match?(/HAVING\s/i)
end

check("PROJ-CLOSED-06: no write operations in fixture source") do
  !PROJ_SRC.include?('write_file') && !PROJ_SRC.include?('write_json') &&
    !PROJ_SRC.match?(/INSERT\s+INTO/i)
end

check("PROJ-CLOSED-07: no StorageCapability execution in fixture source") do
  !PROJ_SRC.include?('IO.StorageCapability') &&
    !PROJ_SRC.include?('effect contract')
end

check("PROJ-CLOSED-08: no persistence runtime in proof runner source") do
  !SOURCE.include?('Base.establish_' + 'connection') &&
    !SOURCE.include?('Active' + 'Record::Base') &&
    !SOURCE.include?('execute_' + 'sql(') &&
    !SOURCE.include?('data' + 'base_url =')
end

# ── PROJ-GAP ──────────────────────────────────────────────────────────────────
puts "\n── PROJ-GAP (5) — boundary findings ──"

check("PROJ-GAP-01: ProjectionSim is PROOF-LOCAL ONLY — not a production runtime") do
  SOURCE.include?('PROOF-LOCAL ONLY') && PROJ_SRC.include?('PROOF-LOCAL ONLY')
end

check("PROJ-GAP-02: fields is String in v0; Collection[String] projection grammar deferred; nested-record TypeChecker boundary documented") do
  PROJ_SRC.include?('Collection[String]') && PROJ_SRC.include?('deferred') &&
    PROJ_SRC.include?('nested record literals')
end

check("PROJ-GAP-03: typed Row[T] schema-aware projection deferred in v0") do
  PROJ_SRC.include?('typed Row[T]') && PROJ_SRC.include?('deferred')
end

check("PROJ-GAP-04: Collection[OrderBy] 7th P2 confirmation: BuildFieldsProjectionPlan.order_list") do
  compute_type_tag(PROJ_SIR, 'BuildFieldsProjectionPlan', 'order_list') == 'Collection[OrderBy]'
end

check("PROJ-GAP-05: does not open production query runtime — no IO.StorageCapability authority used") do
  !PROJ_SRC.include?('IO.StorageCapability') &&
    !PROJ_SRC.include?('effect contract') &&
    PROJ_SRC.include?('LAB-ONLY')
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-QUERY-PROJECTION-P1: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  - Projection.include_all=true → full row passthrough (identity projection)"
  puts "  - Projection.include_all=false → comma-split field list; whitespace stripped"
  puts "  - Empty fields after parsing → query_error (malformed plan)"
  puts "  - Field absent in row → query_error (fail-closed)"
  puts "  - Duplicate fields → de-duplicate preserving first occurrence"
  puts "  - Projection does not change row count"
  puts "  - Projection applied AFTER filter → multi-order → limit"
  puts "  - include_all policy (G5): allow_include_all=false → query_error (NOT denied)"
  puts "  - query_error ≠ denied invariant preserved throughout pipeline"
  puts "  - Collection[OrderBy] from record-field context (LAB-TC-ARRAY-P2 — 7th confirmation)"
  puts "  - All 7 contracts VM-executed at Layer B"
  puts "  - ProjectionSim is PROOF-LOCAL ONLY — not a production projection runtime"
  puts "  - Collection[String] fields deferred; typed Row[T] deferred"
  puts "  - No SQL / DB / ORM / StorageCapability execution at any layer"
else
  puts "LAB-QUERY-PROJECTION-P1: #{$fail_count} check(s) failed"
  exit 1
end
