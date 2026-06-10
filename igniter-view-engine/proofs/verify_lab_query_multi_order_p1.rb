#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_query_multi_order_p1.rb
# LAB-QUERY-MULTI-ORDER-P1 — 64 checks
#
# Extends single-key ordering (LAB-QUERY-ORDER-LIMIT-P1) to Collection[OrderBy]:
# proves deterministic stable multi-column ordering over mocked rows.
#
# Core formula:
#   MultiOrder v0  =  mocked rows  +  Collection[OrderBy]  +  limit
#                  →  deterministic stable multi-column ordered rows + QueryResult
#   MultiOrder v0  ≠  sql order-by clause  ≠  DB runtime  ≠  ORM  ≠  index-backed sorting
#   MultiOrderSim  =  PROOF-LOCAL ONLY  ≠  production multi-order evaluation runtime
#
# Three-layer proof:
#   Layer A — Ruby TypeChecker: 7 contracts accepted; Collection[OrderBy] in type_env;
#             QueryPlanMultiOrder.order: Collection[OrderBy].
#   Layer B — Rust compiler + VM: fixture compiles; Rust SIR:
#             BuildMultiOrderPlan.order_list = Collection[OrderBy] from record-field context
#             (LAB-TC-ARRAY-P2 mechanism — 6th confirmation); all 7 contracts VM-executable.
#   Layer C — Proof-local MultiOrderSim: composite stable sort; per-key asc/desc;
#             empty list → preserve input order; multi-key tiebreaker resolution.
#
# v0 multi-order semantics (Layer C):
#   Empty list             → preserve input order (no-op)
#   Empty direction entry  → query_error (multi-order entries are explicit steps — must have direction)
#   Unknown direction      → query_error (NOT denied)
#   Missing order field    → query_error (NOT denied)
#   Sort keys: priority order (first = primary, second = secondary, ...)
#   All comparisons: lexicographic String in v0
#   Stable sort: equal keys preserve input order (index tiebreaker)
#   Limit: applied AFTER all ordering
#   query_error ≠ denied throughout integrated pipeline
#
# Sections:
#   MORDER-COMPILE       (5)  — fixture compiles; 7 contracts; Ruby TC accepted
#   MORDER-SHAPE         (6)  — Collection[OrderBy]; OrderBy 2 fields; Rust SIR type tag
#   MORDER-SINGLE        (5)  — single-key asc/desc; empty list; P1 backward compat
#   MORDER-MULTI         (8)  — 2-key and 3-key ordering; asc/desc/desc combos
#   MORDER-STABLE        (5)  — equal keys preserve input order; stable sort invariant
#   MORDER-LIMIT         (4)  — limit after multi-order; limit 0/negative; all rows
#   MORDER-ERROR         (5)  — unknown direction; missing field; empty direction; qe≠denied
#   MORDER-INTEGRATED    (6)  — gates + filter + multi-order + limit compose
#   MORDER-VM            (7)  — Layer B: all 7 contracts VM-executed
#   MORDER-CLOSED        (8)  — no SQL/DB/ORM/index/joins/writes/storage runtime
#   MORDER-GAP           (5)  — deferred semantics; production runtime? NO; P1 compat
#
# Total: 64 checks
#
# Depends on:
#   LAB-QUERY-ORDER-LIMIT-P1  (single-key order/limit semantics — 54/54)
#   LAB-EXECUTE-QUERY-P2      (integrated mocked pipeline — 73/73)
#   LAB-FILTER-EVAL-P1        (filter predicate evaluation — 50/50)
#   LAB-TC-ARRAY-P2           (Collection[T] from record-field context — 19/19)
#   LAB-TC-ARRAY-P1           (empty array in Collection context — 27/27)
#   PROP-043-P5               (Map[String,String] production TypeChecker — 55/55)
#   LAB-VM-MAP-P1             (VM map_get/or_else — 48/48)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_query_multi_order_p1.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_execution' / 'multi_order_query.ig').to_s

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

def compile_path(path, tag = 'morder')
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
  tmpfile = Tempfile.new(['morder_inputs', '.json'])
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

# ── Layer C: Proof-local multi-order simulator ────────────────────────────────
#
# ReverseComparable: wraps a String value and reverses the comparison.
# Used to express desc sort keys within a composite sort_by key array.
# sort_by sees all positions of a given column as the same type (either all
# String for asc, or all ReverseComparable for desc), so Array#<=> is safe.

class ReverseComparable
  include Comparable
  attr_reader :val
  def initialize(val); @val = val.to_s; end
  def <=>(other); other.val.to_s <=> @val; end
end

# MultiOrderSim: proof-local semantics evaluator for Collection[OrderBy].
#
# Semantics:
#   Empty list → preserve input order (no-op).
#   Each entry: { field, direction } — applied in order (first = primary key).
#   Empty direction in entry → query_error (unlike single-order P1 where empty = no sort;
#     in multi-order, each entry is an explicit sort step and must have a direction).
#   Unknown direction → query_error (NOT denied).
#   Missing order field in any row → query_error (NOT denied).
#   Stable sort: equal keys preserve input order (index as final tiebreaker).
#   All comparisons: lexicographic String in v0.
#   Limit applied AFTER all ordering.
#
# MultiOrderSim is PROOF-LOCAL ONLY — not a production multi-order evaluation runtime.

module MultiOrderSim
  KNOWN_DIRECTIONS  = %w[asc desc].freeze
  KNOWN_FILTER_OPS  = %w[eq neq contains prefix].freeze

  def self.sort_rows(rows, order_list)
    return { kind: 'ok', message: '', rows: rows } if order_list.empty?

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
        field     = ob.fetch('field', '')
        direction = ob.fetch('direction', 'asc')
        val       = row.fetch(field, '')
        direction == 'asc' ? val : ReverseComparable.new(val)
      end
      keys + [i]
    end.map(&:first)

    { kind: 'ok', message: '', rows: sorted }
  end

  def self.apply_filters(rows, filters)
    bad = filters.find { |f| !KNOWN_FILTER_OPS.include?(f.fetch('op', '')) }
    if bad
      return { kind: 'query_error', message: "unknown filter operator: #{bad['op']}", rows: [] }
    end
    matched = rows.select { |row| filters.all? { |f| row_matches?(row, f) } }
    { kind: 'ok', rows: matched }
  end

  def self.execute_semantics(rows, order_list, limit, metadata)
    sort_out = sort_rows(rows, order_list)
    if sort_out[:kind] == 'query_error'
      return { result: build_qe(sort_out[:message], metadata), rows: [] }
    end

    if limit < 0
      return { result: build_qe('negative limit', metadata), rows: [] }
    end

    if limit == 0
      return { result: { 'kind' => 'empty', 'count' => 0, 'message' => 'limit zero', 'metadata' => metadata }, rows: [] }
    end

    limited = sort_out[:rows].first(limit)
    kind    = limited.empty? ? 'empty' : 'rows'
    { result: { 'kind' => kind, 'count' => limited.length, 'message' => '', 'metadata' => metadata }, rows: limited }
  end

  private_class_method def self.build_qe(msg, metadata)
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
end

# MultiOrderQuerySim: integrated pipeline with gates + filter + Collection[OrderBy] + limit.
# Gate logic mirrors IntegratedQuerySim from LAB-EXECUTE-QUERY-P2; order step uses MultiOrderSim.
# MultiOrderQuerySim is PROOF-LOCAL ONLY — not a production integrated query runtime.

module MultiOrderQuerySim
  def self.execute(cap, plan, mocked_rows)
    source_table  = plan.dig('source', 'table') || ''
    include_all   = plan.dig('projection', 'include_all') || false
    plan_limit    = plan.fetch('limit', 0)
    row_limit     = cap.fetch('row_limit', 0)
    deny_reason   = cap.fetch('deny_reason', '')
    filters       = plan.fetch('filters', [])
    order_list    = plan.fetch('order', [])
    metadata      = plan.fetch('metadata', {})

    # G1: source allowlist
    unless cap.fetch('allowed_sources', []).include?(source_table)
      msg = deny_reason.empty? ? 'source not in allowed_sources' : deny_reason
      return denial('G1', msg, plan_limit, row_limit, metadata)
    end

    # G2: op allowlist
    unless cap.fetch('allowed_ops', []).include?('read')
      return denial('G2', 'op not in allowed_ops', plan_limit, row_limit, metadata)
    end

    # G3: read master switch
    unless cap.fetch('read_allowed', false)
      return denial('G3', 'read_allowed is false', plan_limit, row_limit, metadata)
    end

    # G4: row-limit clamp (NOT denial)
    effective_limit = [plan_limit, row_limit].min
    clamped         = effective_limit < plan_limit

    # G5: include_all policy → query_error (NOT denied)
    if include_all && !cap.fetch('allow_include_all', false)
      return {
        result: { 'kind' => 'query_error', 'count' => 0,
                  'message' => 'include_all not permitted', 'metadata' => metadata },
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    # Negative effective_limit
    if effective_limit < 0
      return {
        result: { 'kind' => 'query_error', 'count' => 0, 'message' => 'negative limit', 'metadata' => metadata },
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    # G6a: filter
    filter_out = MultiOrderSim.apply_filters(mocked_rows, filters)
    if filter_out[:kind] == 'query_error'
      return {
        result: { 'kind' => 'query_error', 'count' => 0,
                  'message' => filter_out[:message], 'metadata' => metadata },
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    # G6b: multi-order
    sort_out = MultiOrderSim.sort_rows(filter_out[:rows], order_list)
    if sort_out[:kind] == 'query_error'
      return {
        result: { 'kind' => 'query_error', 'count' => 0,
                  'message' => sort_out[:message], 'metadata' => metadata },
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    # G6c: limit
    if effective_limit == 0
      return {
        result: { 'kind' => 'empty', 'count' => 0, 'message' => 'limit zero', 'metadata' => metadata },
        rows: [], denial_gate: '', clamped: clamped, effective_limit: effective_limit
      }
    end

    limited = sort_out[:rows].first(effective_limit)
    kind    = limited.empty? ? 'empty' : 'rows'
    {
      result: { 'kind' => kind, 'count' => limited.length, 'message' => '', 'metadata' => metadata },
      rows: limited, denial_gate: '', clamped: clamped, effective_limit: effective_limit
    }
  end

  private_class_method def self.denial(gate, reason, _plan_limit, _row_limit, metadata)
    {
      result: { 'kind' => 'denied', 'count' => 0, 'message' => reason, 'metadata' => metadata },
      rows: [], denial_gate: gate, clamped: false, effective_limit: 0
    }
  end
end

# ── Test data ─────────────────────────────────────────────────────────────────
#
# MULTI_ROWS: 5 rows with dept/level/name/score/status for multi-key ordering.
# Input order indices: charlie=0, alice=1, dave=2, bob=3, eve=4

MULTI_ROWS = [
  { 'dept' => 'eng',  'level' => 'senior', 'name' => 'charlie', 'score' => '30', 'status' => 'active'   },
  { 'dept' => 'eng',  'level' => 'junior', 'name' => 'alice',   'score' => '10', 'status' => 'active'   },
  { 'dept' => 'mkt',  'level' => 'senior', 'name' => 'dave',    'score' => '40', 'status' => 'inactive' },
  { 'dept' => 'eng',  'level' => 'senior', 'name' => 'bob',     'score' => '20', 'status' => 'active'   },
  { 'dept' => 'mkt',  'level' => 'junior', 'name' => 'eve',     'score' => '50', 'status' => 'inactive' },
].freeze

# EQUAL_KEY_ROWS: 3 rows with identical sort-key values for stable sort testing.
EQUAL_KEY_ROWS = [
  { 'dept' => 'eng', 'level' => 'senior', 'name' => 'zoe', 'idx' => '0' },
  { 'dept' => 'eng', 'level' => 'senior', 'name' => 'zoe', 'idx' => '1' },
  { 'dept' => 'eng', 'level' => 'senior', 'name' => 'zoe', 'idx' => '2' },
].freeze

MORDER_META  = { 'trace_id' => 'morder-test' }.freeze
NO_FILTERS   = [].freeze
HIGH_LIMIT   = 100

BASE_CAP = {
  'cap_id'            => 'cap-multi-v0',
  'allowed_sources'   => ['users'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

# Base integrated plan: filter active + dept/name asc + limit 5
BASE_MULTI_PLAN = {
  'kind'       => 'select',
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'name,dept', 'include_all' => false },
  'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
  'order'      => [
    { 'field' => 'dept', 'direction' => 'asc' },
    { 'field' => 'name', 'direction' => 'asc' }
  ],
  'limit'    => 5,
  'metadata' => { 'trace_id' => 'integ-multi' }
}.freeze

ALL_CONTRACTS = %w[
  BuildMultiOrderPlan BuildEmptyOrderPlan BuildThreeKeyOrderPlan
  BuildMultiOrderRowsResult BuildMultiOrderEmptyResult
  BuildMultiOrderQueryErrorResult MultiOrderMetadataReader
].freeze

# ── Compile fixture and run TypeChecker ───────────────────────────────────────

MORDER_SIR = compile_path(FIXTURE_PATH, 'morder')
MORDER_TC  = run_fixture(FIXTURE_PATH)
MORDER_SRC = File.read(FIXTURE_PATH).force_encoding('UTF-8').freeze
MORDER_OUT = MORDER_SIR[:out_dir]

# ── Pre-compute Layer C results ───────────────────────────────────────────────
#
# MULTI_ROWS input order: charlie(0), alice(1), dave(2), bob(3), eve(4)
#
# dept groups: eng = {charlie(0), alice(1), bob(3)}, mkt = {dave(2), eve(4)}
# level groups: senior = {charlie(0), dave(2), bob(3)}, junior = {alice(1), eve(4)}
#
# Expected sort results:
#   name asc:           alice, bob, charlie, dave, eve
#   name desc:          eve, dave, charlie, bob, alice
#   dept+name asc/asc:  alice, bob, charlie (eng, name asc) + dave, eve (mkt, name asc)
#   dept+level asc/desc: eng/senior(charlie,bob stable), eng/junior(alice), mkt/senior(dave), mkt/junior(eve)
#                       → charlie, bob, alice, dave, eve
#   dept+level desc/asc: mkt/junior(eve), mkt/senior(dave), eng/junior(alice), eng/senior(charlie,bob stable)
#                       → eve, dave, alice, charlie, bob
#   dept+level+name (asc,desc,asc): eng/senior: bob,charlie (name asc resolves tie)
#                       → bob, charlie, alice, dave, eve
#   dept+level asc/asc: alice (eng/junior), charlie, bob (eng/senior stable), eve (mkt/junior), dave (mkt/senior)
#                       → alice, charlie, bob, eve, dave
#   EQUAL_KEY_ROWS dept+level+name (all equal): idx=0,1,2 (input order)

C_EMPTY_ORDER   = MultiOrderSim.execute_semantics(MULTI_ROWS, [], HIGH_LIMIT, MORDER_META)
C_NAME_ASC      = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'name','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_NAME_DESC     = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'name','direction'=>'desc'}], HIGH_LIMIT, MORDER_META)
C_DEPT_NAME_ASC = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'dept','direction'=>'asc'},{'field'=>'name','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_DEPT_ASC_LEVEL_DESC = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'dept','direction'=>'asc'},{'field'=>'level','direction'=>'desc'}], HIGH_LIMIT, MORDER_META)
C_DEPT_DESC_LEVEL_ASC = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'dept','direction'=>'desc'},{'field'=>'level','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_THREE_KEY     = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'dept','direction'=>'asc'},{'field'=>'level','direction'=>'desc'},{'field'=>'name','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_DEPT_LEVEL_ASC = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'dept','direction'=>'asc'},{'field'=>'level','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_ALL_EQUAL     = MultiOrderSim.execute_semantics(EQUAL_KEY_ROWS, [{'field'=>'dept','direction'=>'asc'},{'field'=>'level','direction'=>'asc'},{'field'=>'name','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_LIM_AFTER     = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'dept','direction'=>'asc'},{'field'=>'level','direction'=>'desc'},{'field'=>'name','direction'=>'asc'}], 2, MORDER_META)
C_LIM_ZERO      = MultiOrderSim.execute_semantics(MULTI_ROWS, [], 0, MORDER_META)
C_LIM_NEG       = MultiOrderSim.execute_semantics(MULTI_ROWS, [], -1, MORDER_META)
C_LIM_ALL       = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'name','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_UNKNOWN_DIR   = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'name','direction'=>'sideways'}], HIGH_LIMIT, MORDER_META)
C_MISSING_FIELD = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'missing_col','direction'=>'asc'}], HIGH_LIMIT, MORDER_META)
C_EMPTY_DIR     = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'name','direction'=>''}], HIGH_LIMIT, MORDER_META)

# Integrated results (gates + filter + multi-order)
# active rows: charlie(0), alice(1), bob(3); dept+name asc → alice, bob, charlie
C_INTEG_ROWS   = MultiOrderQuerySim.execute(BASE_CAP, BASE_MULTI_PLAN, MULTI_ROWS)
# G1 denial: source not in allowed_sources
C_INTEG_DENIED = MultiOrderQuerySim.execute(BASE_CAP.merge('allowed_sources' => ['posts']), BASE_MULTI_PLAN, MULTI_ROWS)
# G4 clamp: cap.row_limit=2, plan.limit=5 → effective_limit=2 → alice, bob
C_INTEG_CLAMPED = MultiOrderQuerySim.execute(BASE_CAP.merge('row_limit' => 2), BASE_MULTI_PLAN, MULTI_ROWS)
# Bad direction in integrated pipeline → query_error (not denied)
C_INTEG_BAD_DIR = MultiOrderQuerySim.execute(
  BASE_CAP,
  BASE_MULTI_PLAN.merge('order' => [{'field' => 'name', 'direction' => 'sideways'}]),
  MULTI_ROWS
)
# Filter-only, no order: preserve filtered input order
C_INTEG_FILTER_ORDER = MultiOrderQuerySim.execute(
  BASE_CAP,
  BASE_MULTI_PLAN.merge('order' => [], 'limit' => 10),
  MULTI_ROWS
)

# ── VM inputs ─────────────────────────────────────────────────────────────────

VM_SOURCE     = { 'table' => 'users', 'schema' => 'public' }.freeze
VM_PROJ       = { 'fields' => 'name,dept', 'include_all' => false }.freeze
VM_FILTERS    = [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }].freeze
VM_LIMIT      = 10
VM_META       = { 'trace_id' => 'morder-vm' }.freeze

VM_PLAN_INPUTS = {
  'source' => VM_SOURCE, 'projection' => VM_PROJ,
  'filters' => VM_FILTERS, 'limit' => VM_LIMIT, 'metadata' => VM_META
}.freeze

VM_ROWS_INPUTS  = { 'row_count' => 3, 'metadata' => VM_META }.freeze
VM_EMPTY_INPUTS = { 'metadata' => VM_META }.freeze
VM_QERR_INPUTS  = { 'reason' => 'unknown direction: sideways', 'metadata' => VM_META }.freeze
VM_META_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 3, 'message' => '',
                   'metadata' => { 'trace_id' => 'morder-vm', 'dept' => 'eng' } },
  'query_key' => 'dept'
}.freeze
VM_META_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 0, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_PLAN_R      = MORDER_OUT ? vm_run(MORDER_OUT, 'BuildMultiOrderPlan',            VM_PLAN_INPUTS)    : {}
VM_EMPTY_PLAN  = MORDER_OUT ? vm_run(MORDER_OUT, 'BuildEmptyOrderPlan',            VM_PLAN_INPUTS)    : {}
VM_THREE_PLAN  = MORDER_OUT ? vm_run(MORDER_OUT, 'BuildThreeKeyOrderPlan',         VM_PLAN_INPUTS)    : {}
VM_ROWS_R      = MORDER_OUT ? vm_run(MORDER_OUT, 'BuildMultiOrderRowsResult',      VM_ROWS_INPUTS)    : {}
VM_EMPTY_RES_R = MORDER_OUT ? vm_run(MORDER_OUT, 'BuildMultiOrderEmptyResult',     VM_EMPTY_INPUTS)   : {}
VM_QERR_R      = MORDER_OUT ? vm_run(MORDER_OUT, 'BuildMultiOrderQueryErrorResult', VM_QERR_INPUTS)   : {}
VM_META_HIT_R  = MORDER_OUT ? vm_run(MORDER_OUT, 'MultiOrderMetadataReader',       VM_META_HIT_INPUTS)  : {}
VM_META_MISS_R = MORDER_OUT ? vm_run(MORDER_OUT, 'MultiOrderMetadataReader',       VM_META_MISS_INPUTS) : {}

# ── MORDER-COMPILE ────────────────────────────────────────────────────────────
puts "\n── MORDER-COMPILE (5) — fixture compiles; 7 contracts; Ruby TC accepted ──"

check("MORDER-COMPILE-01: Rust compiler: fixture compiles without error") do
  MORDER_SIR[:error].nil? && MORDER_SIR[:report] != nil
end

check("MORDER-COMPILE-02: Ruby TypeChecker: fixture parses without error") do
  MORDER_TC[:error].nil?
end

check("MORDER-COMPILE-03: Ruby TypeChecker: 7 contracts present") do
  contracts = MORDER_TC[:typed]&.fetch('contracts', []) || []
  contracts.length == 7
end

check("MORDER-COMPILE-04: Ruby TypeChecker: all 7 contracts accepted") do
  ALL_CONTRACTS.all? { |n| contract_accepted?(MORDER_TC, n) }
end

check("MORDER-COMPILE-05: Ruby TypeChecker: zero type_errors across all 7 contracts") do
  ALL_CONTRACTS.all? { |n| type_errors_for(MORDER_TC, n).empty? }
end

# ── MORDER-SHAPE ──────────────────────────────────────────────────────────────
puts "\n── MORDER-SHAPE (6) — Collection[OrderBy]; type shapes; Rust SIR type tag ──"

check("MORDER-SHAPE-01: QueryPlanMultiOrder.order type = Collection[OrderBy] (Ruby TC type_env)") do
  type_name_str(type_env_field(MORDER_TC, 'QueryPlanMultiOrder', 'order')) == 'Collection[OrderBy]'
end

check("MORDER-SHAPE-02: QueryPlanMultiOrder.filters type = Collection[FilterPredicate]") do
  type_name_str(type_env_field(MORDER_TC, 'QueryPlanMultiOrder', 'filters')) == 'Collection[FilterPredicate]'
end

check("MORDER-SHAPE-03: QueryPlanMultiOrder.limit type = Integer") do
  type_name_str(type_env_field(MORDER_TC, 'QueryPlanMultiOrder', 'limit')) == 'Integer'
end

check("MORDER-SHAPE-04: OrderBy has 2 fields: field and direction") do
  ob = MORDER_TC[:typed]&.fetch('type_env', {})&.fetch('OrderBy', {}) || {}
  ob.length == 2 && ob.key?('field') && ob.key?('direction')
end

check("MORDER-SHAPE-05: QueryResult 4 fields: kind/count/message/metadata") do
  qr = MORDER_TC[:typed]&.fetch('type_env', {})&.fetch('QueryResult', {}) || {}
  %w[kind count message metadata].all? { |f| qr.key?(f) }
end

check("MORDER-SHAPE-06: Rust SIR: BuildMultiOrderPlan.order_list type_tag = Collection[OrderBy] (6th P2 confirmation)") do
  compute_type_tag(MORDER_SIR, 'BuildMultiOrderPlan', 'order_list') == 'Collection[OrderBy]'
end

# ── MORDER-SINGLE ─────────────────────────────────────────────────────────────
puts "\n── MORDER-SINGLE (5) — single-key asc/desc; empty list; P1 backward compat ──"

check("MORDER-SINGLE-01: empty order list preserves input order") do
  C_EMPTY_ORDER[:result]['kind'] == 'rows' &&
    C_EMPTY_ORDER[:rows].map { |r| r['name'] } == %w[charlie alice dave bob eve]
end

check("MORDER-SINGLE-02: single key name asc → alice, bob, charlie, dave, eve") do
  C_NAME_ASC[:result]['kind'] == 'rows' &&
    C_NAME_ASC[:rows].map { |r| r['name'] } == %w[alice bob charlie dave eve]
end

check("MORDER-SINGLE-03: single key name desc → eve, dave, charlie, bob, alice") do
  C_NAME_DESC[:result]['kind'] == 'rows' &&
    C_NAME_DESC[:rows].map { |r| r['name'] } == %w[eve dave charlie bob alice]
end

check("MORDER-SINGLE-04: single-key asc + limit matches P1 order-then-limit invariant") do
  # name asc + limit 2 → alice, bob (same behavior as P1 would produce)
  r = MultiOrderSim.execute_semantics(MULTI_ROWS, [{'field'=>'name','direction'=>'asc'}], 2, MORDER_META)
  r[:result]['kind'] == 'rows' &&
    r[:rows].map { |row| row['name'] } == %w[alice bob]
end

check("MORDER-SINGLE-05: empty list count equals total rows (no filtering, all rows present)") do
  C_EMPTY_ORDER[:result]['count'] == 5
end

# ── MORDER-MULTI ──────────────────────────────────────────────────────────────
puts "\n── MORDER-MULTI (8) — 2-key and 3-key ordering; mixed asc/desc ──"

check("MORDER-MULTI-01: two-key asc/asc (dept+name): alice, bob, charlie, dave, eve") do
  C_DEPT_NAME_ASC[:result]['kind'] == 'rows' &&
    C_DEPT_NAME_ASC[:rows].map { |r| r['name'] } == %w[alice bob charlie dave eve]
end

check("MORDER-MULTI-02: two-key asc/desc (dept asc, level desc): charlie, bob, alice, dave, eve") do
  # eng: senior(charlie,bob stable) before junior(alice); mkt: senior(dave) before junior(eve)
  C_DEPT_ASC_LEVEL_DESC[:result]['kind'] == 'rows' &&
    C_DEPT_ASC_LEVEL_DESC[:rows].map { |r| r['name'] } == %w[charlie bob alice dave eve]
end

check("MORDER-MULTI-03: two-key desc/asc (dept desc, level asc): eve, dave, alice, charlie, bob") do
  # mkt first: junior(eve), senior(dave); eng: junior(alice), senior(charlie,bob stable)
  C_DEPT_DESC_LEVEL_ASC[:result]['kind'] == 'rows' &&
    C_DEPT_DESC_LEVEL_ASC[:rows].map { |r| r['name'] } == %w[eve dave alice charlie bob]
end

check("MORDER-MULTI-04: three-key (dept asc, level desc, name asc): bob, charlie, alice, dave, eve") do
  # eng/senior: bob,charlie (name asc resolves tie); eng/junior: alice; mkt/senior: dave; mkt/junior: eve
  C_THREE_KEY[:result]['kind'] == 'rows' &&
    C_THREE_KEY[:rows].map { |r| r['name'] } == %w[bob charlie alice dave eve]
end

check("MORDER-MULTI-05: primary key determines group boundary (dept separates eng/mkt correctly)") do
  eng_names = C_DEPT_NAME_ASC[:rows].select { |r| r['dept'] == 'eng' }.map { |r| r['name'] }
  mkt_names = C_DEPT_NAME_ASC[:rows].select { |r| r['dept'] == 'mkt' }.map { |r| r['name'] }
  eng_names == %w[alice bob charlie] && mkt_names == %w[dave eve] &&
    C_DEPT_NAME_ASC[:rows].index { |r| r['dept'] == 'mkt' } > C_DEPT_NAME_ASC[:rows].rindex { |r| r['dept'] == 'eng' }
end

check("MORDER-MULTI-06: secondary key resolves primary-key ties (level sorts within dept groups)") do
  # With dept+level asc/asc: alice(eng/junior) before charlie,bob(eng/senior)
  C_DEPT_LEVEL_ASC[:rows].map { |r| r['name'] } == %w[alice charlie bob eve dave]
end

check("MORDER-MULTI-07: tertiary key resolves secondary-key ties (name resolves eng/senior tie)") do
  # Without tertiary: dept+level asc/desc gives charlie,bob (stable by input index)
  # With tertiary name asc: bob before charlie
  two_key_names = C_DEPT_ASC_LEVEL_DESC[:rows].map { |r| r['name'] }
  three_key_names = C_THREE_KEY[:rows].map { |r| r['name'] }
  two_key_names[0] == 'charlie' && two_key_names[1] == 'bob' &&  # stable order without name key
    three_key_names[0] == 'bob' && three_key_names[1] == 'charlie' # name asc resolves tie
end

check("MORDER-MULTI-08: three-key count invariant: all 5 rows returned (no filtering)") do
  C_THREE_KEY[:result]['count'] == 5 &&
    C_THREE_KEY[:rows].length == 5
end

# ── MORDER-STABLE ─────────────────────────────────────────────────────────────
puts "\n── MORDER-STABLE (5) — equal keys preserve input order; stable sort invariant ──"

check("MORDER-STABLE-01: all-equal sort keys → input order preserved (idx sequence: 0, 1, 2)") do
  C_ALL_EQUAL[:result]['kind'] == 'rows' &&
    C_ALL_EQUAL[:rows].map { |r| r['idx'] } == %w[0 1 2]
end

check("MORDER-STABLE-02: equal primary key → secondary key resolves correctly") do
  # dept+level asc/asc: within eng/senior, charlie(idx0) before bob(idx3) by stable sort
  eng_senior = C_DEPT_LEVEL_ASC[:rows].select { |r| r['dept'] == 'eng' && r['level'] == 'senior' }
  eng_senior.map { |r| r['name'] } == %w[charlie bob]
end

check("MORDER-STABLE-03: equal primary+secondary keys → tertiary key resolves correctly") do
  # dept+level+name (asc,desc,asc): within eng/senior, name asc gives bob before charlie
  eng_senior = C_THREE_KEY[:rows].select { |r| r['dept'] == 'eng' && r['level'] == 'senior' }
  eng_senior.map { |r| r['name'] } == %w[bob charlie]
end

check("MORDER-STABLE-04: equal all specified keys → input order preserved (index tiebreaker)") do
  # EQUAL_KEY_ROWS: dept=eng, level=senior, name=zoe for all → input order = idx 0,1,2
  rows = C_ALL_EQUAL[:rows]
  rows.length == 3 && rows[0]['idx'] == '0' && rows[1]['idx'] == '1' && rows[2]['idx'] == '2'
end

check("MORDER-STABLE-05: two-key desc/asc eng/senior stable: charlie(input idx 0) before bob(input idx 3)") do
  # dept desc, level asc: eng group has alice(junior), charlie(senior,idx0), bob(senior,idx3)
  eng_senior = C_DEPT_DESC_LEVEL_ASC[:rows].select { |r| r['dept'] == 'eng' && r['level'] == 'senior' }
  eng_senior.length == 2 &&
    eng_senior[0]['name'] == 'charlie' &&
    eng_senior[1]['name'] == 'bob'
end

# ── MORDER-LIMIT ──────────────────────────────────────────────────────────────
puts "\n── MORDER-LIMIT (4) — limit after multi-order; limit 0/negative; all rows ──"

check("MORDER-LIMIT-01: limit 2 after three-key order → first 2 of sorted result (bob, charlie)") do
  C_LIM_AFTER[:result]['kind']  == 'rows' &&
    C_LIM_AFTER[:result]['count'] == 2 &&
    C_LIM_AFTER[:rows].map { |r| r['name'] } == %w[bob charlie]
end

check("MORDER-LIMIT-02: limit == 0 → kind:\"empty\"; count:0") do
  C_LIM_ZERO[:result]['kind']  == 'empty' &&
    C_LIM_ZERO[:result]['count'] == 0
end

check("MORDER-LIMIT-03: negative limit → kind:\"query_error\" (NOT \"denied\")") do
  C_LIM_NEG[:result]['kind'] == 'query_error' &&
    C_LIM_NEG[:result]['kind'] != 'denied'
end

check("MORDER-LIMIT-04: limit > rows.length → all sorted rows returned") do
  C_LIM_ALL[:result]['kind']  == 'rows' &&
    C_LIM_ALL[:result]['count'] == 5 &&
    C_LIM_ALL[:rows].map { |r| r['name'] } == %w[alice bob charlie dave eve]
end

# ── MORDER-ERROR ──────────────────────────────────────────────────────────────
puts "\n── MORDER-ERROR (5) — unknown direction; missing field; empty direction; qe≠denied ──"

check("MORDER-ERROR-01: unknown direction → kind:\"query_error\" (NOT \"denied\")") do
  C_UNKNOWN_DIR[:result]['kind'] == 'query_error' &&
    C_UNKNOWN_DIR[:result]['kind'] != 'denied'
end

check("MORDER-ERROR-02: missing order field in row → kind:\"query_error\" (NOT \"denied\")") do
  C_MISSING_FIELD[:result]['kind'] == 'query_error' &&
    C_MISSING_FIELD[:result]['kind'] != 'denied'
end

check("MORDER-ERROR-03: empty direction in multi-order entry → kind:\"query_error\"") do
  # Unlike single-order P1 where empty direction = preserve input order,
  # in multi-order each entry is an explicit step and must have a direction.
  C_EMPTY_DIR[:result]['kind'] == 'query_error'
end

check("MORDER-ERROR-04: query_error ≠ denied: unknown direction gives query_error, not denied") do
  [C_UNKNOWN_DIR, C_MISSING_FIELD, C_EMPTY_DIR].all? { |r| r[:result]['kind'] == 'query_error' } &&
    [C_UNKNOWN_DIR, C_MISSING_FIELD, C_EMPTY_DIR].none? { |r| r[:result]['kind'] == 'denied' }
end

check("MORDER-ERROR-05: empty direction is distinct from unknown direction (both query_error, different messages)") do
  empty_msg   = C_EMPTY_DIR[:result]['message']
  unknown_msg = C_UNKNOWN_DIR[:result]['message']
  !empty_msg.empty? && !unknown_msg.empty? && empty_msg != unknown_msg
end

# ── MORDER-INTEGRATED ─────────────────────────────────────────────────────────
puts "\n── MORDER-INTEGRATED (6) — gates + filter + multi-order + limit compose ──"

check("MORDER-INTEGRATED-01: allowed cap + filter(active) + order(dept+name asc) + limit(5) → 3 rows: alice, bob, charlie") do
  C_INTEG_ROWS[:result]['kind']  == 'rows' &&
    C_INTEG_ROWS[:result]['count'] == 3 &&
    C_INTEG_ROWS[:rows].map { |r| r['name'] } == %w[alice bob charlie]
end

check("MORDER-INTEGRATED-02: gate denial (G1) short-circuits before multi-order evaluation") do
  C_INTEG_DENIED[:result]['kind']   == 'denied' &&
    C_INTEG_DENIED[:denial_gate]    == 'G1' &&
    C_INTEG_DENIED[:rows]           == []
end

check("MORDER-INTEGRATED-03: filter reduces rows before multi-order (inactive rows excluded)") do
  # Filtered rows (active): charlie, alice, bob → multi-order gives alice, bob, charlie
  C_INTEG_ROWS[:rows].none? { |r| r['status'] == 'inactive' } &&
    C_INTEG_ROWS[:rows].all? { |r| r['status'] == 'active' }
end

check("MORDER-INTEGRATED-04: empty order list in integrated pipeline preserves filtered row order") do
  # Filter active → charlie, alice, bob (input order); empty order → same order
  C_INTEG_FILTER_ORDER[:result]['kind'] == 'rows' &&
    C_INTEG_FILTER_ORDER[:rows].map { |r| r['name'] } == %w[charlie alice bob]
end

check("MORDER-INTEGRATED-05: limit applied after multi-order (limit 2 → alice, bob)") do
  C_INTEG_CLAMPED[:rows].map { |r| r['name'] } == %w[alice bob] &&
    C_INTEG_CLAMPED[:result]['count'] == 2
end

check("MORDER-INTEGRATED-06: G4 row-limit clamp with multi-order: effective_limit=2; clamped=true; rows=alice,bob") do
  C_INTEG_CLAMPED[:clamped]         == true &&
    C_INTEG_CLAMPED[:effective_limit] == 2 &&
    C_INTEG_CLAMPED[:result]['kind']  == 'rows' &&
    C_INTEG_CLAMPED[:result]['kind']  != 'denied'
end

# ── MORDER-VM ─────────────────────────────────────────────────────────────────
puts "\n── MORDER-VM (7) — Layer B: all 7 contracts VM-executed ──"

check("MORDER-VM-01: VM BuildMultiOrderPlan → kind:\"select\"; order is array of 2 entries; first field:\"dept\"") do
  order = VM_PLAN_R.dig('result', 'order')
  VM_PLAN_R['status'] == 'success' &&
    VM_PLAN_R.dig('result', 'kind') == 'select' &&
    order.is_a?(Array) && order.length == 2 &&
    order[0].is_a?(Hash) && order[0]['field'] == 'dept'
end

check("MORDER-VM-02: VM BuildEmptyOrderPlan → kind:\"select\"; order is empty array") do
  order = VM_EMPTY_PLAN.dig('result', 'order')
  VM_EMPTY_PLAN['status'] == 'success' &&
    order.is_a?(Array) && order.empty?
end

check("MORDER-VM-03: VM BuildThreeKeyOrderPlan → order is array of 3 entries; first field:\"dept\"; second direction:\"desc\"") do
  order = VM_THREE_PLAN.dig('result', 'order')
  VM_THREE_PLAN['status'] == 'success' &&
    order.is_a?(Array) && order.length == 3 &&
    order[0]['field'] == 'dept' &&
    order[1]['direction'] == 'desc'
end

check("MORDER-VM-04: VM BuildMultiOrderRowsResult(row_count:3) → kind:\"rows\"; count:3") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind')  == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 3
end

check("MORDER-VM-05: VM BuildMultiOrderEmptyResult → kind:\"empty\"; count:0") do
  VM_EMPTY_RES_R['status'] == 'success' &&
    VM_EMPTY_RES_R.dig('result', 'kind')  == 'empty' &&
    VM_EMPTY_RES_R.dig('result', 'count') == 0
end

check("MORDER-VM-06: VM BuildMultiOrderQueryErrorResult → kind:\"query_error\"; count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind')  == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("MORDER-VM-07: VM MultiOrderMetadataReader — map_get hit:\"eng\"; miss:\"not-found\"") do
  VM_META_HIT_R['status']  == 'success' && VM_META_HIT_R['result']  == 'eng' &&
    VM_META_MISS_R['status'] == 'success' && VM_META_MISS_R['result'] == 'not-found'
end

# ── MORDER-CLOSED ─────────────────────────────────────────────────────────────
puts "\n── MORDER-CLOSED (8) — closed surfaces ──"

check("MORDER-CLOSED-01: no SQL execution in fixture source") do
  !MORDER_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+FROM/i) &&
    !MORDER_SRC.include?('execute_sql') && !MORDER_SRC.include?('.sql')
end

check("MORDER-CLOSED-02: no database connection in fixture source") do
  !MORDER_SRC.include?('establish_connection') && !MORDER_SRC.include?('database_url') &&
    !MORDER_SRC.include?('connect_to(')
end

check("MORDER-CLOSED-03: no ORM / ActiveRecord / Arel in fixture source") do
  !MORDER_SRC.include?('ActiveRecord') && !MORDER_SRC.include?('Arel') &&
    !MORDER_SRC.include?('has_many') && !MORDER_SRC.include?('belongs_to')
end

check("MORDER-CLOSED-04: no index or optimizer usage in fixture source") do
  !MORDER_SRC.include?('optimizer_hint') && !MORDER_SRC.include?('use_index') &&
    !MORDER_SRC.include?('index_scan') && !MORDER_SRC.include?('force_index')
end

check("MORDER-CLOSED-05: no joins or aggregates in fixture source") do
  !MORDER_SRC.include?('JOIN') && !MORDER_SRC.match?(/GROUP\s+BY/i) &&
    !MORDER_SRC.match?(/HAVING\s/i) && !MORDER_SRC.include?('AGGREGATE')
end

check("MORDER-CLOSED-06: no write operations in fixture source") do
  !MORDER_SRC.include?('write_file') && !MORDER_SRC.include?('write_json') &&
    !MORDER_SRC.match?(/INSERT\s+INTO/i)
end

check("MORDER-CLOSED-07: no StorageCapability execution in fixture source") do
  !MORDER_SRC.include?('IO.StorageCapability') &&
    !MORDER_SRC.include?('effect contract')
end

check("MORDER-CLOSED-08: no persistence runtime in proof runner source") do
  !SOURCE.include?('Base.establish_' + 'connection') &&
    !SOURCE.include?('Active' + 'Record::Base') &&
    !SOURCE.include?('execute_' + 'sql(') &&
    !SOURCE.include?('data' + 'base_url =')
end

# ── MORDER-GAP ────────────────────────────────────────────────────────────────
puts "\n── MORDER-GAP (5) — boundary findings ──"

check("MORDER-GAP-01: MultiOrderSim is PROOF-LOCAL ONLY — not a production runtime") do
  SOURCE.include?('PROOF-LOCAL ONLY') && MORDER_SRC.include?('PROOF-LOCAL ONLY')
end

check("MORDER-GAP-02: numeric/date/locale-aware ordering deferred — all comparisons lexicographic String in v0") do
  MORDER_SRC.include?('lexicographic String in v0') &&
    !MORDER_SRC.include?('to_i') && !MORDER_SRC.include?('Date.parse')
end

check("MORDER-GAP-03: single-order backward compat — name asc matches P1 behavior; empty list = no-op") do
  # P1: asc gives alice,bob,charlie,dave,eve; empty = preserve input order
  C_NAME_ASC[:rows].map { |r| r['name'] } == %w[alice bob charlie dave eve] &&
    C_EMPTY_ORDER[:rows].map { |r| r['name'] } == %w[charlie alice dave bob eve]
end

check("MORDER-GAP-04: Collection[OrderBy] types correctly (6th P2 confirmation); multi-hop deferred") do
  compute_type_tag(MORDER_SIR, 'BuildMultiOrderPlan', 'order_list') == 'Collection[OrderBy]'
end

check("MORDER-GAP-05: does not open production query runtime — no IO.StorageCapability authority used") do
  !MORDER_SRC.include?('IO.StorageCapability') &&
    !MORDER_SRC.include?('effect contract') &&
    MORDER_SRC.include?('LAB-ONLY')
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-QUERY-MULTI-ORDER-P1: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  - Collection[OrderBy] types correctly in Ruby TC and Rust SIR (6th P2 confirmation)"
  puts "  - Two-key and three-key stable ordering proved over 5-row deterministic dataset"
  puts "  - Primary/secondary/tertiary key priority order confirmed"
  puts "  - Empty Collection[OrderBy] → preserve input order (no-op)"
  puts "  - Empty direction in multi-order entry → query_error (explicit step must have direction)"
  puts "  - Stable sort: equal keys preserve input order (index tiebreaker)"
  puts "  - Limit applied AFTER all ordering (order-then-limit invariant preserved)"
  puts "  - query_error ≠ denied: unknown direction / missing field / empty direction → query_error"
  puts "  - Gates + filter + multi-order + limit compose correctly in integrated pipeline"
  puts "  - All 7 contracts VM-executed at Layer B"
  puts "  - All comparisons lexicographic String in v0; numeric/date ordering deferred"
  puts "  - MultiOrderSim is PROOF-LOCAL ONLY — not a production multi-order runtime"
  puts "  - No SQL / DB / ORM / StorageCapability execution at any layer"
else
  puts "LAB-QUERY-MULTI-ORDER-P1: #{$fail_count} check(s) failed"
  exit 1
end
