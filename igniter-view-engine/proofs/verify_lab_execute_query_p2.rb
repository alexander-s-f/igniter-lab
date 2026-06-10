#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_execute_query_p2.rb
# LAB-EXECUTE-QUERY-P2 — 73 checks
#
# First complete mocked ExecuteQuery pipeline:
#   StorageCapability gates + filter evaluation + order/limit semantics + QueryExecutionReceipt.
#
# Core formula:
#   ExecuteQueryMock v0 = QueryPlan + StorageCapability-shaped policy + mocked rows
#                       → gated / filtered / ordered / limited QueryResult + QueryExecutionReceipt
#   ExecuteQueryMock v0 ≠ SQL execution ≠ DB runtime ≠ ORM ≠ production StorageCapability execution
#   ExecuteQueryMock v0 ≠ query optimizer
#
# Three-layer proof:
#   Layer A — Ruby TypeChecker: 8 contracts accepted; all record types correct;
#             QueryPlan.filters: Collection[FilterPredicate]; QueryPlan.order: OrderBy.
#   Layer B — Lab Rust compiler + VM: fixture compiles; Rust SIR:
#             BuildIntegratedPlan.filters = Collection[FilterPredicate] (record-field-context
#             mechanism — 5th confirmation); all 8 contracts VM-executable.
#   Layer C — Proof-local IntegratedQuerySim:
#             G1–G6 gate sequence; filter (eq/neq/contains/prefix); asc/desc lexicographic sort;
#             stable sort; limit-after-order; all gate failures short-circuit before evaluation.
#
# Pipeline order (Layer C):
#   G1: source allowlist → denied
#   G2: op allowlist → denied
#   G3: read_allowed → denied
#   G4: row-limit clamp → effective_limit (NOT denial)
#   G5: include_all policy → query_error (NOT denied)
#   G6a: filter → rows/empty/query_error
#   G6b: order → rows/empty/query_error
#   G6c: limit → rows/empty/query_error
#
# Denial-as-data invariant:
#   G1/G2/G3 → kind:"denied"
#   G5 → kind:"query_error" (NOT denied)
#   G6-filter/order/negative-limit → kind:"query_error" (NOT denied)
#   All failures return typed data; no exceptions raised.
#
# Sections:
#   EXECQ2-COMPILE       (5)  — fixture compiles; 8 contracts; Ruby TC accepted
#   EXECQ2-SHAPE         (8)  — record types; Collection[FilterPredicate]; OrderBy; receipt 15 fields
#   EXECQ2-GATES         (6)  — G1–G5 denial/query_error; G4 clamp ≠ denial; G6 route distinct
#   EXECQ2-FILTER        (8)  — eq/neq/contains/prefix; AND; empty; missing field; bad op
#   EXECQ2-ORDER-LIMIT   (8)  — asc/desc; stable sort; empty dir; unknown dir; limit 0/-/order-then-limit
#   EXECQ2-INTEGRATED    (7)  — full pipeline; empty; bad op; bad dir; denied short-circuits; clamp; qe≠denied
#   EXECQ2-RECEIPT       (7)  — cap_checked; cap_granted; denial_gate; effective_limit; clamped; returned; kind
#   EXECQ2-VM            (8)  — Layer B: all 8 contracts VM-executed; filters array; receipt fields
#   EXECQ2-CLOSED        (9)  — no SQL/DB/ORM/optimizer/joins/writes/transactions/capability/public API
#   EXECQ2-GAP           (7)  — complete? YES; production? NO; SQL? NO; Layer C? YES; row-limit distinct; etc.
#
# Total: 73 checks
#
# Depends on:
#   LAB-EXECUTE-QUERY-P1  (StorageCapability gate sequence — 57/57)
#   LAB-FILTER-EVAL-P1    (filter predicate evaluation — 50/50)
#   LAB-QUERY-ORDER-LIMIT-P1 (order/limit semantics — 54/54)
#   LAB-STORAGE-CAPABILITY-P2 (gate receipts proof — 51/51)
#   LAB-QUERY-P3          (QueryPlan v1 — 44/44)
#   LAB-TC-ARRAY-P2       (Collection[FilterPredicate] from record-field context — 19/19)
#   PROP-043-P5           (Map[String,String] production TypeChecker — 55/55)
#   LAB-VM-MAP-P1         (VM map_get/or_else — 48/48)
#   LAB-RECORD-VM-P3      (nested record field access — 49/49)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_execute_query_p2.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_execution' / 'execute_query_integrated.ig').to_s

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

def compile_path(path, tag = 'execq2')
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
  tmpfile = Tempfile.new(['execq2_inputs', '.json'])
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

# ── Layer C: Proof-local integrated query execution simulator ─────────────────
#
# IntegratedQuerySim: combines G1–G6 gate sequence + filter evaluation +
# order/limit semantics in a single proof-local execution path.
#
# Pipeline:
#   G1: source allowlist          → denied
#   G2: op allowlist              → denied
#   G3: read_allowed master       → denied
#   G4: row-limit clamp           → effective_limit (NOT denial)
#   G5: include_all policy        → query_error (NOT denied)
#   G6a: apply filters            → rows (matched) or query_error (bad op)
#   G6b: apply order              → sorted rows or query_error (bad direction/missing field)
#   G6c: apply effective limit    → limited rows or empty or query_error (negative)
#
# Gate failures (G1/G2/G3) short-circuit before filter/order/limit evaluation.
# G4 clamp does NOT deny — cap_granted stays true after clamp.
# G5 → query_error (NOT denied): malformed plan field, not access denial.
# G6 failures → query_error (NOT denied): malformed plan field.
#
# Row model: Array of Hash[String => String] (in-memory only; no DB; no sql)
# All comparisons are lexicographic String comparisons in v0.
#
# IntegratedQuerySim is PROOF-LOCAL ONLY — not a production integrated query runtime.

module IntegratedQuerySim
  KNOWN_OPS        = %w[eq neq contains prefix].freeze
  KNOWN_DIRECTIONS = %w[asc desc].freeze

  KDR_ROUTES = {
    'rows'         => { action: 'process', summary: 'ordered/limited rows returned; iterate and transform' },
    'empty'        => { action: 'empty',   summary: 'zero rows after pipeline; show empty state' },
    'denied'       => { action: 'deny',    summary: 'capability gate denied; do not retry same plan+cap' },
    'query_error'  => { action: 'invalid', summary: 'malformed plan field; fix before retry' },
    'system_error' => { action: 'error',   summary: 'infrastructure failure; retry later' }
  }.freeze

  def self.execute(cap, plan, mocked_rows)
    source_table  = plan.dig('source', 'table') || ''
    include_all   = plan.dig('projection', 'include_all') || false
    plan_limit    = plan.fetch('limit', 0)
    row_limit     = cap.fetch('row_limit', 0)
    cap_id        = cap.fetch('cap_id', '')
    deny_reason   = cap.fetch('deny_reason', '')
    filters       = plan.fetch('filters', [])
    order_by      = plan.fetch('order', { 'field' => '', 'direction' => '' })
    metadata      = plan.fetch('metadata', {})

    # G1: source allowlist
    unless cap.fetch('allowed_sources', []).include?(source_table)
      msg = deny_reason.empty? ? 'source not in allowed_sources' : deny_reason
      return gate_denial('G1', msg, cap_id, source_table, plan_limit, row_limit, plan, metadata)
    end

    # G2: op allowlist
    unless cap.fetch('allowed_ops', []).include?('read')
      return gate_denial('G2', 'op not in allowed_ops', cap_id, source_table, plan_limit, row_limit, plan, metadata)
    end

    # G3: read master switch
    unless cap.fetch('read_allowed', false)
      return gate_denial('G3', 'read_allowed is false', cap_id, source_table, plan_limit, row_limit, plan, metadata)
    end

    # G4: row-limit clamp (NOT denial — cap_granted stays true)
    effective_limit = [plan_limit, row_limit].min
    clamped         = effective_limit < plan_limit

    # G5: include_all policy → query_error (NOT denied)
    if include_all && !cap.fetch('allow_include_all', false)
      receipt = build_receipt(
        cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
        op_requested: 'read', cap_checked: true, cap_granted: false,
        denial_gate: 'G5', deny_reason: 'include_all not permitted by capability',
        plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: effective_limit,
        row_limit_clamped: clamped, rows_returned: 0, result_kind: 'query_error', metadata: metadata
      )
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => 'include_all not permitted by capability', 'metadata' => metadata }
      return { result: result, receipt: receipt, rows: [] }
    end

    # Check for negative effective_limit (negative plan_limit → query_error)
    if effective_limit < 0
      receipt = build_receipt(
        cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
        op_requested: 'read', cap_checked: true, cap_granted: false,
        denial_gate: 'G6-limit', deny_reason: 'negative limit',
        plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: effective_limit,
        row_limit_clamped: clamped, rows_returned: 0, result_kind: 'query_error', metadata: metadata
      )
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => 'negative limit', 'metadata' => metadata }
      return { result: result, receipt: receipt, rows: [] }
    end

    # G6a: filter evaluation
    filter_out = apply_filters(mocked_rows, filters)
    if filter_out[:kind] == 'query_error'
      receipt = build_receipt(
        cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
        op_requested: 'read', cap_checked: true, cap_granted: false,
        denial_gate: 'G6-filter', deny_reason: filter_out[:message],
        plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: effective_limit,
        row_limit_clamped: clamped, rows_returned: 0, result_kind: 'query_error', metadata: metadata
      )
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => filter_out[:message], 'metadata' => metadata }
      return { result: result, receipt: receipt, rows: [] }
    end

    # G6b: order semantics (lexicographic; stable sort)
    order_out = apply_order(filter_out[:rows], order_by)
    if order_out[:kind] == 'query_error'
      receipt = build_receipt(
        cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
        op_requested: 'read', cap_checked: true, cap_granted: false,
        denial_gate: 'G6-order', deny_reason: order_out[:message],
        plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: effective_limit,
        row_limit_clamped: clamped, rows_returned: 0, result_kind: 'query_error', metadata: metadata
      )
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => order_out[:message], 'metadata' => metadata }
      return { result: result, receipt: receipt, rows: [] }
    end

    # G6c: apply effective_limit (after order)
    if effective_limit == 0
      receipt = build_receipt(
        cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
        op_requested: 'read', cap_checked: true, cap_granted: true,
        denial_gate: '', deny_reason: '',
        plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: effective_limit,
        row_limit_clamped: clamped, rows_returned: 0, result_kind: 'empty', metadata: metadata
      )
      result = { 'kind' => 'empty', 'count' => 0, 'message' => 'limit zero', 'metadata' => metadata }
      return { result: result, receipt: receipt, rows: [] }
    end

    limited_rows = order_out[:rows].first(effective_limit)
    result_kind  = limited_rows.empty? ? 'empty' : 'rows'
    receipt = build_receipt(
      cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
      op_requested: 'read', cap_checked: true, cap_granted: true,
      denial_gate: '', deny_reason: '',
      plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: effective_limit,
      row_limit_clamped: clamped, rows_returned: limited_rows.length,
      result_kind: result_kind, metadata: metadata
    )
    result = { 'kind' => result_kind, 'count' => limited_rows.length,
               'message' => '', 'metadata' => metadata }
    { result: result, receipt: receipt, rows: limited_rows }
  end

  def self.route(result)
    kind = result.is_a?(Hash) ? result.fetch('kind', 'unknown') : result.to_s
    KDR_ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  private_class_method def self.apply_filters(rows, filters)
    bad_op = filters.find { |f| !KNOWN_OPS.include?(f['op']) }
    if bad_op
      return { kind: 'query_error', message: "unknown operator: #{bad_op['op']}", rows: [] }
    end
    matched = rows.select { |row| filters.all? { |f| row_matches?(row, f) } }
    { kind: matched.empty? ? 'empty' : 'rows', message: '', rows: matched }
  end

  private_class_method def self.apply_order(rows, order_by)
    field     = order_by['field']     || ''
    direction = order_by['direction'] || ''
    unless direction.empty?
      unless KNOWN_DIRECTIONS.include?(direction)
        return { kind: 'query_error', message: "unknown direction: #{direction}", rows: [] }
      end
      unless field.empty?
        missing = rows.find { |r| !r.key?(field) }
        if missing
          return { kind: 'query_error', message: "order field absent in row: #{field}", rows: [] }
        end
        rows = rows.each_with_index.sort_by { |r, i| [r[field], i] }.map(&:first)
        rows = rows.reverse if direction == 'desc'
      end
    end
    { kind: 'ok', message: '', rows: rows }
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

  private_class_method def self.gate_denial(gate, reason, cap_id, source_table,
                                             plan_limit, row_limit, plan, metadata)
    receipt = build_receipt(
      cap_id: cap_id, plan_kind: plan.fetch('kind', 'select'), source_table: source_table,
      op_requested: 'read', cap_checked: true, cap_granted: false,
      denial_gate: gate, deny_reason: reason,
      plan_limit: plan_limit, row_limit_cap: row_limit, effective_limit: 0,
      row_limit_clamped: false, rows_returned: 0, result_kind: 'denied', metadata: metadata
    )
    result = { 'kind' => 'denied', 'count' => 0, 'message' => reason, 'metadata' => metadata }
    { result: result, receipt: receipt, rows: [] }
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

# ── Test data ─────────────────────────────────────────────────────────────────
#
# MOCKED_ROWS: 5 rows for the deterministic test dataset.
# Fields: name, score, status, created_at, role

MOCKED_ROWS = [
  { 'name' => 'carol', 'score' => '30', 'status' => 'active',   'created_at' => '2024-01-03', 'role' => 'user' },
  { 'name' => 'alice', 'score' => '10', 'status' => 'active',   'created_at' => '2024-01-01', 'role' => 'admin' },
  { 'name' => 'eve',   'score' => '50', 'status' => 'inactive', 'created_at' => '2024-01-05', 'role' => 'user' },
  { 'name' => 'bob',   'score' => '20', 'status' => 'active',   'created_at' => '2024-01-02', 'role' => 'user' },
  { 'name' => 'dave',  'score' => '40', 'status' => 'active',   'created_at' => '2024-01-04', 'role' => 'admin' },
].freeze

# DUPE_ROWS: 4 rows with duplicate name values for stable sort verification.
DUPE_ROWS = [
  { 'name' => 'bob',   'score' => '20', 'status' => 'active', 'tier' => 'silver' },
  { 'name' => 'alice', 'score' => '30', 'status' => 'active', 'tier' => 'gold' },
  { 'name' => 'bob',   'score' => '10', 'status' => 'active', 'tier' => 'bronze' },
  { 'name' => 'alice', 'score' => '40', 'status' => 'active', 'tier' => 'platinum' },
].freeze

BASE_CAP = {
  'cap_id'            => 'cap-integ-v0',
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
  'projection' => { 'fields' => 'name,status', 'include_all' => false },
  'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
  'order'      => { 'field' => 'name', 'direction' => 'asc' },
  'limit'      => 10,
  'metadata'   => { 'trace_id' => 'integ-base' }
}.freeze

NO_ORDER_PLAN = BASE_PLAN.merge(
  'order'  => { 'field' => '', 'direction' => '' },
  'limit'  => 100,
  'metadata' => { 'trace_id' => 'integ-no-order' }
).freeze

ALL_CONTRACTS = %w[
  BuildIntegratedPlan BuildIntegratedCapability
  BuildIntegratedRowsResult BuildIntegratedEmptyResult
  BuildIntegratedDeniedResult BuildIntegratedQueryErrorResult
  BuildIntegratedReceipt IntegratedMetadataReader
].freeze

# ── Compile fixture and run TypeChecker ───────────────────────────────────────

INTEG_SIR = compile_path(FIXTURE_PATH, 'execq2')
INTEG_TC  = run_fixture(FIXTURE_PATH)
INTEG_SRC = File.read(FIXTURE_PATH).force_encoding('UTF-8').freeze
INTEG_OUT = INTEG_SIR[:out_dir]

# ── Pre-compute Layer C results ───────────────────────────────────────────────

# Baseline: allowed cap + active filter + name asc + limit 10
# Expected: carol, alice, bob, dave (active) → sorted: alice, bob, carol, dave → limit 10 → all 4
C_INTEG_ROWS = IntegratedQuerySim.execute(BASE_CAP, BASE_PLAN, MOCKED_ROWS)

# No-match filter: name nobody
C_INTEG_EMPTY = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('filters' => [{ 'field' => 'name', 'op' => 'eq', 'value' => 'nobody' }]),
  MOCKED_ROWS
)

# Bad filter operator
C_INTEG_BAD_OP = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('filters' => [{ 'field' => 'status', 'op' => 'regex', 'value' => 'active' }]),
  MOCKED_ROWS
)

# Bad order direction
C_INTEG_BAD_DIR = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('order' => { 'field' => 'name', 'direction' => 'backwards' }),
  MOCKED_ROWS
)

# G1: source not in allowed_sources → denied
C_INTEG_DENIED = IntegratedQuerySim.execute(
  BASE_CAP.merge('allowed_sources' => ['posts']),
  BASE_PLAN,
  MOCKED_ROWS
)

# G4 row-limit clamp: cap.row_limit=2, plan.limit=10 → effective_limit=2
# Expected: alice, bob (first 2 after filter active + sort asc)
C_INTEG_CLAMPED = IntegratedQuerySim.execute(
  BASE_CAP.merge('row_limit' => 2),
  BASE_PLAN,
  MOCKED_ROWS
)

# Negative plan_limit → query_error
C_INTEG_NEG_LIMIT = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('limit' => -1),
  MOCKED_ROWS
)

# Filter tests (no ordering, high limit to isolate filter semantics)
C_FILTER_EQ = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }]),
  MOCKED_ROWS
)
C_FILTER_NEQ = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [{ 'field' => 'status', 'op' => 'neq', 'value' => 'inactive' }]),
  MOCKED_ROWS
)
C_FILTER_CONTAINS = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [{ 'field' => 'name', 'op' => 'contains', 'value' => 'a' }]),
  MOCKED_ROWS
)
C_FILTER_PREFIX = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [{ 'field' => 'name', 'op' => 'prefix', 'value' => 'a' }]),
  MOCKED_ROWS
)
C_FILTER_AND = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [
    { 'field' => 'status', 'op' => 'eq',     'value' => 'active' },
    { 'field' => 'name',   'op' => 'prefix',  'value' => 'a' }
  ]),
  MOCKED_ROWS
)
C_FILTER_EMPTY_LIST = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => []),
  MOCKED_ROWS
)
C_FILTER_MISSING_FIELD = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [{ 'field' => 'department', 'op' => 'eq', 'value' => 'engineering' }]),
  MOCKED_ROWS
)
C_FILTER_BAD_OP = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [{ 'field' => 'status', 'op' => 'regex', 'value' => 'active' }]),
  MOCKED_ROWS
)

# Order/limit tests (empty filter list to isolate order/limit semantics)
C_ORDER_ASC = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [], 'order' => { 'field' => 'name', 'direction' => 'asc' }),
  MOCKED_ROWS
)
C_ORDER_DESC = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [], 'order' => { 'field' => 'name', 'direction' => 'desc' }),
  MOCKED_ROWS
)
# Stable sort: DUPE_ROWS with name asc
# Expected order: alice(gold), alice(platinum), bob(silver), bob(bronze)
C_STABLE = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [], 'order' => { 'field' => 'name', 'direction' => 'asc' }),
  DUPE_ROWS
)
C_ORDER_EMPTY_DIR = IntegratedQuerySim.execute(
  BASE_CAP,
  NO_ORDER_PLAN.merge('filters' => [], 'order' => { 'field' => 'name', 'direction' => '' }),
  MOCKED_ROWS
)
C_ORDER_BAD_DIR = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('order' => { 'field' => 'name', 'direction' => 'backwards' }),
  MOCKED_ROWS
)
C_LIM_ZERO = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('filters' => [], 'order' => { 'field' => '', 'direction' => '' }, 'limit' => 0),
  MOCKED_ROWS
)
C_LIM_NEG = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('limit' => -5),
  MOCKED_ROWS
)
# Order-then-limit: active rows, desc, limit 2 → dave, carol
C_ORDER_THEN_LIMIT = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge(
    'filters' => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
    'order'   => { 'field' => 'name', 'direction' => 'desc' },
    'limit'   => 2
  ),
  MOCKED_ROWS
)

# G2: read not in allowed_ops
C_G2 = IntegratedQuerySim.execute(
  BASE_CAP.merge('allowed_ops' => ['write']),
  BASE_PLAN,
  MOCKED_ROWS
)
# G3: read_allowed false
C_G3 = IntegratedQuerySim.execute(
  BASE_CAP.merge('read_allowed' => false),
  BASE_PLAN,
  MOCKED_ROWS
)
# G5: include_all + !allow_include_all
C_G5 = IntegratedQuerySim.execute(
  BASE_CAP,
  BASE_PLAN.merge('projection' => { 'fields' => '*', 'include_all' => true }),
  MOCKED_ROWS
)

# ── VM inputs ──────────────────────────────────────────────────────────────────

VM_PLAN_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'name,status', 'include_all' => false },
  'order'      => { 'field' => 'name', 'direction' => 'asc' },
  'limit'      => 10,
  'metadata'   => { 'trace_id' => 'integ-plan' }
}.freeze

VM_CAP_INPUTS = {
  'cap_id'            => 'cap-integ-v0',
  'allowed_sources'   => ['users', 'posts'],
  'allowed_ops'       => ['read'],
  'row_limit'         => 100,
  'allow_include_all' => false,
  'read_allowed'      => true,
  'write_allowed'     => false,
  'deny_reason'       => ''
}.freeze

VM_ROWS_INPUTS    = { 'row_count' => 4, 'metadata' => { 'trace_id' => 'integ-rows' } }.freeze
VM_EMPTY_INPUTS   = { 'metadata' => { 'trace_id' => 'integ-empty' } }.freeze
VM_DENIED_INPUTS  = { 'deny_reason' => 'source not in allowed_sources',
                      'metadata'    => { 'gate' => 'G1' } }.freeze
VM_QERR_INPUTS    = { 'reason'   => 'unknown filter operator',
                      'metadata' => { 'gate' => 'G6-filter' } }.freeze
VM_RECEIPT_INPUTS = {
  'cap_id'          => 'cap-integ-v0',
  'source_table'    => 'users',
  'plan_limit'      => 10,
  'row_limit_cap'   => 100,
  'effective_limit' => 10,
  'rows_returned'   => 4,
  'metadata'        => { 'trace_id' => 'integ-receipt' }
}.freeze
VM_META_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 4, 'message' => '',
                   'metadata' => { 'trace_id' => 'integ-meta', 'source' => 'api' } },
  'query_key' => 'source'
}.freeze
VM_META_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 0, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_PLAN_R    = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedPlan',            VM_PLAN_INPUTS)    : {}
VM_CAP_R     = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedCapability',      VM_CAP_INPUTS)     : {}
VM_ROWS_R    = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedRowsResult',       VM_ROWS_INPUTS)    : {}
VM_EMPTY_R   = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedEmptyResult',      VM_EMPTY_INPUTS)   : {}
VM_DENIED_R  = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedDeniedResult',     VM_DENIED_INPUTS)  : {}
VM_QERR_R    = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedQueryErrorResult', VM_QERR_INPUTS)    : {}
VM_RECEIPT_R = INTEG_OUT ? vm_run(INTEG_OUT, 'BuildIntegratedReceipt',          VM_RECEIPT_INPUTS) : {}
VM_META_HIT  = INTEG_OUT ? vm_run(INTEG_OUT, 'IntegratedMetadataReader',        VM_META_HIT_INPUTS)  : {}
VM_META_MISS = INTEG_OUT ? vm_run(INTEG_OUT, 'IntegratedMetadataReader',        VM_META_MISS_INPUTS) : {}

# ── EXECQ2-COMPILE ────────────────────────────────────────────────────────────
puts "\n── EXECQ2-COMPILE (5) — fixture compiles; 8 contracts; Ruby TC accepted ──"

check("EXECQ2-COMPILE-01: Rust compiler: fixture compiles without error") do
  INTEG_SIR[:error].nil? && INTEG_SIR[:report] != nil
end

check("EXECQ2-COMPILE-02: Ruby TypeChecker: fixture parses without error") do
  INTEG_TC[:error].nil?
end

check("EXECQ2-COMPILE-03: Ruby TypeChecker: 8 contracts present") do
  contracts = INTEG_TC[:typed]&.fetch('contracts', []) || []
  contracts.length == 8
end

check("EXECQ2-COMPILE-04: Ruby TypeChecker: all 8 contracts accepted") do
  ALL_CONTRACTS.all? { |n| contract_accepted?(INTEG_TC, n) }
end

check("EXECQ2-COMPILE-05: Ruby TypeChecker: zero type_errors across all 8 contracts") do
  ALL_CONTRACTS.all? { |n| type_errors_for(INTEG_TC, n).empty? }
end

# ── EXECQ2-SHAPE ──────────────────────────────────────────────────────────────
puts "\n── EXECQ2-SHAPE (8) — record types; Collection[FilterPredicate]; OrderBy; receipt 15 fields ──"

check("EXECQ2-SHAPE-01: QueryPlan.filters type = Collection[FilterPredicate] (Ruby TC type_env)") do
  type_name_str(type_env_field(INTEG_TC, 'QueryPlan', 'filters')) == 'Collection[FilterPredicate]'
end

check("EXECQ2-SHAPE-02: QueryPlan.order type = OrderBy (Ruby TC type_env)") do
  type_name_str(type_env_field(INTEG_TC, 'QueryPlan', 'order')) == 'OrderBy'
end

check("EXECQ2-SHAPE-03: QueryPlan.limit type = Integer (Ruby TC type_env)") do
  type_name_str(type_env_field(INTEG_TC, 'QueryPlan', 'limit')) == 'Integer'
end

check("EXECQ2-SHAPE-04: QueryResult 4 fields: kind/count/message/metadata") do
  qr = INTEG_TC[:typed]&.fetch('type_env', {})&.fetch('QueryResult', {}) || {}
  %w[kind count message metadata].all? { |f| qr.key?(f) }
end

check("EXECQ2-SHAPE-05: StorageCapability.row_limit = Integer; read_allowed = Bool") do
  type_name_str(type_env_field(INTEG_TC, 'StorageCapability', 'row_limit'))    == 'Integer' &&
    type_name_str(type_env_field(INTEG_TC, 'StorageCapability', 'read_allowed')) == 'Bool'
end

check("EXECQ2-SHAPE-06: QueryExecutionReceipt has 15 fields") do
  receipt_fields = INTEG_TC[:typed]&.fetch('type_env', {})&.fetch('QueryExecutionReceipt', {}) || {}
  receipt_fields.length == 15
end

check("EXECQ2-SHAPE-07: OrderBy has 2 fields: field and direction") do
  ob = INTEG_TC[:typed]&.fetch('type_env', {})&.fetch('OrderBy', {}) || {}
  ob.length == 2 && ob.key?('field') && ob.key?('direction')
end

check("EXECQ2-SHAPE-08: Rust SIR: BuildIntegratedPlan.filters compute_type_tag = Collection[FilterPredicate]") do
  compute_type_tag(INTEG_SIR, 'BuildIntegratedPlan', 'filters') == 'Collection[FilterPredicate]'
end

# ── EXECQ2-GATES ──────────────────────────────────────────────────────────────
puts "\n── EXECQ2-GATES (6) — G1–G5 gate denial/query_error; G4 clamp; G6 routes ──"

check("EXECQ2-GATES-01: G1: source not in allowed_sources → kind:\"denied\"; denial_gate:\"G1\"") do
  C_INTEG_DENIED[:result]['kind']   == 'denied' &&
    C_INTEG_DENIED[:receipt]['denial_gate'] == 'G1'
end

check("EXECQ2-GATES-02: G2: op not in allowed_ops → kind:\"denied\"; denial_gate:\"G2\"") do
  C_G2[:result]['kind']   == 'denied' &&
    C_G2[:receipt]['denial_gate'] == 'G2'
end

check("EXECQ2-GATES-03: G3: read_allowed:false → kind:\"denied\"; denial_gate:\"G3\"") do
  C_G3[:result]['kind']   == 'denied' &&
    C_G3[:receipt]['denial_gate'] == 'G3'
end

check("EXECQ2-GATES-04: G4: plan.limit(10) > row_limit(2) → effective_limit:2; result != \"denied\"") do
  C_INTEG_CLAMPED[:receipt]['effective_limit']   == 2 &&
    C_INTEG_CLAMPED[:receipt]['row_limit_clamped'] == true &&
    C_INTEG_CLAMPED[:result]['kind'] != 'denied'
end

check("EXECQ2-GATES-05: G5: include_all:true + !allow_include_all → kind:\"query_error\" (NOT \"denied\")") do
  C_G5[:result]['kind']           == 'query_error' &&
    C_G5[:receipt]['denial_gate'] == 'G5' &&
    C_G5[:result]['kind'] != 'denied'
end

check("EXECQ2-GATES-06: G6 system_error route is distinct from denied and query_error") do
  IntegratedQuerySim.route({ 'kind' => 'system_error' })[:action] == 'error' &&
    IntegratedQuerySim.route({ 'kind' => 'denied' })[:action]       == 'deny' &&
    IntegratedQuerySim.route({ 'kind' => 'query_error' })[:action]  == 'invalid'
end

# ── EXECQ2-FILTER ─────────────────────────────────────────────────────────────
puts "\n── EXECQ2-FILTER (8) — eq/neq/contains/prefix; AND; empty list; missing field; bad op ──"

check("EXECQ2-FILTER-01: eq(status:active) → 4 rows (carol/alice/bob/dave; eve=inactive excluded)") do
  C_FILTER_EQ[:result]['kind']  == 'rows' &&
    C_FILTER_EQ[:result]['count'] == 4
end

check("EXECQ2-FILTER-02: neq(status:inactive) → 4 rows (same 4 active rows)") do
  C_FILTER_NEQ[:result]['kind']  == 'rows' &&
    C_FILTER_NEQ[:result]['count'] == 4
end

check("EXECQ2-FILTER-03: contains(name:\"a\") → 3 rows (alice/carol/dave all contain \"a\")") do
  C_FILTER_CONTAINS[:result]['kind']  == 'rows' &&
    C_FILTER_CONTAINS[:result]['count'] == 3
end

check("EXECQ2-FILTER-04: prefix(name:\"a\") → 1 row (only alice starts with \"a\")") do
  C_FILTER_PREFIX[:result]['kind']  == 'rows' &&
    C_FILTER_PREFIX[:result]['count'] == 1 &&
    C_FILTER_PREFIX[:rows][0]['name'] == 'alice'
end

check("EXECQ2-FILTER-05: AND [status:eq:active, name:prefix:a] → 1 row (only alice)") do
  C_FILTER_AND[:result]['kind']  == 'rows' &&
    C_FILTER_AND[:result]['count'] == 1 &&
    C_FILTER_AND[:rows][0]['name'] == 'alice'
end

check("EXECQ2-FILTER-06: empty filter list → all 5 rows (vacuous conjunction = true)") do
  C_FILTER_EMPTY_LIST[:result]['kind']  == 'rows' &&
    C_FILTER_EMPTY_LIST[:result]['count'] == 5
end

check("EXECQ2-FILTER-07: unknown field in row → no match (kind:\"empty\", not query_error)") do
  C_FILTER_MISSING_FIELD[:result]['kind']  == 'empty' &&
    C_FILTER_MISSING_FIELD[:result]['kind'] != 'query_error'
end

check("EXECQ2-FILTER-08: unknown operator → kind:\"query_error\" (NOT \"denied\")") do
  C_FILTER_BAD_OP[:result]['kind'] == 'query_error' &&
    C_FILTER_BAD_OP[:result]['kind'] != 'denied'
end

# ── EXECQ2-ORDER-LIMIT ────────────────────────────────────────────────────────
puts "\n── EXECQ2-ORDER-LIMIT (8) — asc/desc; stable sort; empty dir; bad dir; limit 0/-; order-then-limit ──"

check("EXECQ2-ORDER-LIMIT-01: asc sort over all 5 rows → alice first, eve last") do
  rows = C_ORDER_ASC[:rows]
  C_ORDER_ASC[:result]['kind'] == 'rows' &&
    rows.length == 5 &&
    rows.first['name'] == 'alice' &&
    rows.last['name']  == 'eve'
end

check("EXECQ2-ORDER-LIMIT-02: desc sort over all 5 rows → eve first, alice last") do
  rows = C_ORDER_DESC[:rows]
  C_ORDER_DESC[:result]['kind'] == 'rows' &&
    rows.length == 5 &&
    rows.first['name'] == 'eve' &&
    rows.last['name']  == 'alice'
end

check("EXECQ2-ORDER-LIMIT-03: stable sort — equal name keys preserve input order") do
  rows = C_STABLE[:rows]
  rows.length == 4 &&
    rows[0]['tier'] == 'gold' &&     # first alice (input idx 1)
    rows[1]['tier'] == 'platinum' && # second alice (input idx 3)
    rows[2]['tier'] == 'silver' &&   # first bob (input idx 0)
    rows[3]['tier'] == 'bronze'      # second bob (input idx 2)
end

check("EXECQ2-ORDER-LIMIT-04: empty direction string → preserve input order (no sort applied)") do
  C_ORDER_EMPTY_DIR[:result]['kind']  == 'rows' &&
    C_ORDER_EMPTY_DIR[:rows].length     == 5 &&
    C_ORDER_EMPTY_DIR[:rows][0]['name'] == 'carol'  # original input order preserved
end

check("EXECQ2-ORDER-LIMIT-05: unknown direction → kind:\"query_error\" (NOT \"denied\")") do
  C_ORDER_BAD_DIR[:result]['kind'] == 'query_error' &&
    C_ORDER_BAD_DIR[:result]['kind'] != 'denied'
end

check("EXECQ2-ORDER-LIMIT-06: limit == 0 → kind:\"empty\"; count:0") do
  C_LIM_ZERO[:result]['kind']  == 'empty' &&
    C_LIM_ZERO[:result]['count'] == 0
end

check("EXECQ2-ORDER-LIMIT-07: negative limit → kind:\"query_error\" (NOT \"denied\")") do
  C_LIM_NEG[:result]['kind'] == 'query_error' &&
    C_LIM_NEG[:result]['kind'] != 'denied'
end

check("EXECQ2-ORDER-LIMIT-08: order-then-limit invariant — desc+limit2 of active rows gives top-2 desc") do
  # active rows sorted desc: dave, carol, bob, alice → limit 2 → dave, carol
  C_ORDER_THEN_LIMIT[:result]['kind'] == 'rows' &&
    C_ORDER_THEN_LIMIT[:rows].length  == 2 &&
    C_ORDER_THEN_LIMIT[:rows][0]['name'] == 'dave' &&
    C_ORDER_THEN_LIMIT[:rows][1]['name'] == 'carol'
end

# ── EXECQ2-INTEGRATED ─────────────────────────────────────────────────────────
puts "\n── EXECQ2-INTEGRATED (7) — full pipeline; empty; bad op; bad dir; denied; clamp; qe≠denied ──"

check("EXECQ2-INTEGRATED-01: allowed cap + filter(active) + order(asc) + limit(10) → rows; count:4") do
  C_INTEG_ROWS[:result]['kind']  == 'rows' &&
    C_INTEG_ROWS[:result]['count'] == 4 &&
    C_INTEG_ROWS[:rows].map { |r| r['name'] } == %w[alice bob carol dave]
end

check("EXECQ2-INTEGRATED-02: allowed cap + no-match filter → kind:\"empty\"; count:0") do
  C_INTEG_EMPTY[:result]['kind']  == 'empty' &&
    C_INTEG_EMPTY[:result]['count'] == 0
end

check("EXECQ2-INTEGRATED-03: allowed cap + bad filter op → kind:\"query_error\" (NOT \"denied\")") do
  C_INTEG_BAD_OP[:result]['kind'] == 'query_error' &&
    C_INTEG_BAD_OP[:receipt]['denial_gate'].start_with?('G6')
end

check("EXECQ2-INTEGRATED-04: allowed cap + bad order direction → kind:\"query_error\" (NOT \"denied\")") do
  C_INTEG_BAD_DIR[:result]['kind'] == 'query_error' &&
    C_INTEG_BAD_DIR[:receipt]['denial_gate'].start_with?('G6')
end

check("EXECQ2-INTEGRATED-05: denied cap (G1) + valid plan → kind:\"denied\"; rows is empty") do
  C_INTEG_DENIED[:result]['kind'] == 'denied' &&
    C_INTEG_DENIED[:rows] == []
end

check("EXECQ2-INTEGRATED-06: G4 row-limit clamp: plan.limit(10), cap.row_limit(2) → 2 rows returned") do
  C_INTEG_CLAMPED[:result]['kind']           == 'rows' &&
    C_INTEG_CLAMPED[:result]['count']          == 2 &&
    C_INTEG_CLAMPED[:receipt]['effective_limit'] == 2 &&
    C_INTEG_CLAMPED[:rows].map { |r| r['name'] } == %w[alice bob]
end

check("EXECQ2-INTEGRATED-07: query_error ≠ denied throughout pipeline") do
  # G1/G2/G3 → denied; G5/G6-filter/G6-order/negative-limit → query_error
  [C_INTEG_DENIED, C_G2, C_G3].all? { |r| r[:result]['kind'] == 'denied' } &&
    [C_INTEG_BAD_OP, C_INTEG_BAD_DIR, C_G5, C_LIM_NEG].all? { |r| r[:result]['kind'] == 'query_error' } &&
    [C_INTEG_DENIED, C_G2, C_G3].none? { |r| r[:result]['kind'] == 'query_error' }
end

# ── EXECQ2-RECEIPT ────────────────────────────────────────────────────────────
puts "\n── EXECQ2-RECEIPT (7) — receipt fields; invariants; determinism ──"

check("EXECQ2-RECEIPT-01: receipt records cap_checked:true in all cases") do
  [C_INTEG_ROWS, C_INTEG_DENIED, C_INTEG_BAD_OP, C_INTEG_CLAMPED, C_G5].all? do |r|
    r[:receipt]['cap_checked'] == true
  end
end

check("EXECQ2-RECEIPT-02: cap_granted:false iff result_kind in {denied, query_error}") do
  denied_results = [C_INTEG_DENIED, C_G2, C_G3, C_G5, C_INTEG_BAD_OP, C_INTEG_BAD_DIR, C_LIM_NEG]
  allowed_results = [C_INTEG_ROWS, C_INTEG_EMPTY, C_INTEG_CLAMPED]
  denied_results.all? { |r| r[:receipt]['cap_granted'] == false } &&
    allowed_results.all? { |r| r[:receipt]['cap_granted'] == true }
end

check("EXECQ2-RECEIPT-03: receipt records denial_gate:\"G1\" for source denial") do
  C_INTEG_DENIED[:receipt]['denial_gate']  == 'G1' &&
    C_INTEG_DENIED[:receipt]['cap_granted']  == false &&
    C_INTEG_DENIED[:receipt]['rows_returned'] == 0
end

check("EXECQ2-RECEIPT-04: receipt records effective_limit = min(plan.limit, cap.row_limit)") do
  # Base: plan=10, cap=100 → effective=10
  # Clamped: plan=10, cap=2 → effective=2
  C_INTEG_ROWS[:receipt]['effective_limit']    == 10 &&
    C_INTEG_CLAMPED[:receipt]['effective_limit'] == 2
end

check("EXECQ2-RECEIPT-05: receipt records row_limit_clamped:true when cap clamps plan limit") do
  C_INTEG_CLAMPED[:receipt]['row_limit_clamped'] == true &&
    C_INTEG_ROWS[:receipt]['row_limit_clamped']    == false
end

check("EXECQ2-RECEIPT-06: receipt records rows_returned matching actual returned row count") do
  C_INTEG_ROWS[:receipt]['rows_returned']    == C_INTEG_ROWS[:rows].length &&
    C_INTEG_CLAMPED[:receipt]['rows_returned'] == C_INTEG_CLAMPED[:rows].length &&
    C_INTEG_DENIED[:receipt]['rows_returned']  == 0
end

check("EXECQ2-RECEIPT-07: receipt result_kind mirrors QueryResult.kind") do
  [C_INTEG_ROWS, C_INTEG_EMPTY, C_INTEG_DENIED, C_INTEG_BAD_OP].all? do |r|
    r[:receipt]['result_kind'] == r[:result]['kind']
  end
end

# ── EXECQ2-VM ─────────────────────────────────────────────────────────────────
puts "\n── EXECQ2-VM (8) — Layer B: all 8 contracts VM-executed ──"

check("EXECQ2-VM-01: VM BuildIntegratedPlan → kind:\"select\"; order.direction:\"asc\"; limit:10; filters array") do
  filters = VM_PLAN_R.dig('result', 'filters')
  VM_PLAN_R['status'] == 'success' &&
    VM_PLAN_R.dig('result', 'kind')               == 'select' &&
    VM_PLAN_R.dig('result', 'order', 'direction')  == 'asc' &&
    VM_PLAN_R.dig('result', 'limit')               == 10 &&
    filters.is_a?(Array) && filters.length == 2 &&
    filters[0]['field'] == 'status' && filters[1]['field'] == 'role'
end

check("EXECQ2-VM-02: VM BuildIntegratedCapability → cap_id:\"cap-integ-v0\"; row_limit:100; read_allowed:true") do
  VM_CAP_R['status'] == 'success' &&
    VM_CAP_R.dig('result', 'cap_id')       == 'cap-integ-v0' &&
    VM_CAP_R.dig('result', 'row_limit')    == 100 &&
    VM_CAP_R.dig('result', 'read_allowed') == true
end

check("EXECQ2-VM-03: VM BuildIntegratedRowsResult(row_count:4) → kind:\"rows\"; count:4") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind')  == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 4
end

check("EXECQ2-VM-04: VM BuildIntegratedEmptyResult → kind:\"empty\"; count:0") do
  VM_EMPTY_R['status'] == 'success' &&
    VM_EMPTY_R.dig('result', 'kind')  == 'empty' &&
    VM_EMPTY_R.dig('result', 'count') == 0
end

check("EXECQ2-VM-05: VM BuildIntegratedDeniedResult → kind:\"denied\"; count:0; message non-empty") do
  VM_DENIED_R['status'] == 'success' &&
    VM_DENIED_R.dig('result', 'kind')    == 'denied' &&
    VM_DENIED_R.dig('result', 'count')   == 0 &&
    !VM_DENIED_R.dig('result', 'message').to_s.empty?
end

check("EXECQ2-VM-06: VM BuildIntegratedQueryErrorResult → kind:\"query_error\"; count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind')  == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("EXECQ2-VM-07: VM BuildIntegratedReceipt → cap_granted:true; effective_limit:10; denial_gate:\"\"") do
  VM_RECEIPT_R['status'] == 'success' &&
    VM_RECEIPT_R.dig('result', 'cap_granted')     == true &&
    VM_RECEIPT_R.dig('result', 'effective_limit')  == 10 &&
    VM_RECEIPT_R.dig('result', 'denial_gate')      == '' &&
    VM_RECEIPT_R.dig('result', 'rows_returned')    == 4
end

check("EXECQ2-VM-08: VM IntegratedMetadataReader — map_get hit:\"api\"; miss:\"not-found\"") do
  VM_META_HIT['status']  == 'success' && VM_META_HIT['result']  == 'api' &&
    VM_META_MISS['status'] == 'success' && VM_META_MISS['result'] == 'not-found'
end

# ── EXECQ2-CLOSED ─────────────────────────────────────────────────────────────
puts "\n── EXECQ2-CLOSED (9) — closed surfaces ──"

check("EXECQ2-CLOSED-01: no SQL execution in fixture source") do
  !INTEG_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+|CREATE\s+TABLE/i) &&
    !INTEG_SRC.include?('execute_sql') && !INTEG_SRC.include?('.sql')
end

check("EXECQ2-CLOSED-02: no database connection in fixture source") do
  !INTEG_SRC.include?('establish_connection') && !INTEG_SRC.include?('database_url') &&
    !INTEG_SRC.include?('connect_to(')
end

check("EXECQ2-CLOSED-03: no ORM / ActiveRecord / Arel in fixture source") do
  !INTEG_SRC.include?('ActiveRecord') && !INTEG_SRC.include?('Arel') &&
    !INTEG_SRC.include?('has_many') && !INTEG_SRC.include?('belongs_to')
end

check("EXECQ2-CLOSED-04: no index or optimizer usage in fixture source") do
  !INTEG_SRC.include?('optimizer_hint') && !INTEG_SRC.include?('use_index') &&
    !INTEG_SRC.include?('index_scan') && !INTEG_SRC.include?('force_index')
end

check("EXECQ2-CLOSED-05: no joins or aggregates in fixture source") do
  !INTEG_SRC.include?('JOIN') && !INTEG_SRC.match?(/GROUP\s+BY/i) &&
    !INTEG_SRC.match?(/HAVING\s/i) && !INTEG_SRC.include?('AGGREGATE')
end

check("EXECQ2-CLOSED-06: no write operations in fixture source") do
  !INTEG_SRC.include?('write_file') && !INTEG_SRC.include?('write_json') &&
    !INTEG_SRC.match?(/INSERT\s+INTO/i)
end

check("EXECQ2-CLOSED-07: no transactions in fixture source") do
  !INTEG_SRC.include?('transaction') && !INTEG_SRC.match?(/\bBEGIN\b/) &&
    !INTEG_SRC.match?(/\bCOMMIT\b/) && !INTEG_SRC.match?(/\bROLLBACK\b/)
end

check("EXECQ2-CLOSED-08: no StorageCapability live execution in fixture (plain Record only)") do
  !INTEG_SRC.include?('IO.StorageCapability') &&
    !INTEG_SRC.include?('effect contract')
end

check("EXECQ2-CLOSED-09: no persistence runtime in proof runner source") do
  !SOURCE.include?('Base.establish_' + 'connection') &&
    !SOURCE.include?('DATABASE_URL' + '=') &&
    !SOURCE.include?('Sequ' + 'el.connect(') &&
    !SOURCE.include?('execute_' + 'sql(') &&
    !SOURCE.include?('Active' + 'Record::Base')
end

# ── EXECQ2-GAP ────────────────────────────────────────────────────────────────
puts "\n── EXECQ2-GAP (7) — boundary findings ──"

check("EXECQ2-GAP-01: complete mocked pipeline — receipt has all gate, filter, order, limit fields") do
  r = C_INTEG_ROWS[:receipt]
  r['cap_checked']      == true &&
    r['cap_granted']    == true &&
    r['denial_gate']    == '' &&
    r['effective_limit'] == 10 &&
    r['rows_returned']  == 4 &&
    r['result_kind']    == 'rows' &&
    C_INTEG_ROWS[:rows].all? { |row| row['status'] == 'active' }
end

check("EXECQ2-GAP-02: not production query execution — no IO.StorageCapability in fixture; no effect contract") do
  !INTEG_SRC.include?('IO.StorageCapability') &&
    !INTEG_SRC.include?('effect contract') &&
    INTEG_SRC.include?('LAB-ONLY')
end

check("EXECQ2-GAP-03: does not execute SQL — no sql pattern in fixture") do
  !INTEG_SRC.match?(/SELECT\s+FROM\s/i) &&
    !INTEG_SRC.match?(/ORDER\s+BY/i) &&
    !INTEG_SRC.match?(/WHERE\s+/i)
end

check("EXECQ2-GAP-04: filter/order/limit semantics are Layer C proof-local IntegratedQuerySim only") do
  SOURCE.include?('IntegratedQuerySim') &&
    SOURCE.include?('PROOF-LOCAL') &&
    INTEG_SRC.include?('LAB-ONLY')
end

check("EXECQ2-GAP-05: QueryPlan.limit and StorageCapability row_limit are orthogonal — clamp without denial") do
  C_INTEG_CLAMPED[:receipt]['effective_limit']   == 2 &&
    C_INTEG_CLAMPED[:receipt]['row_limit_clamped'] == true &&
    C_INTEG_CLAMPED[:receipt]['cap_granted']       == true &&
    C_INTEG_CLAMPED[:result]['kind']               != 'denied' &&
    C_INTEG_CLAMPED[:result]['count']              < 10
end

check("EXECQ2-GAP-06: joins/aggregates/writes deferred — not in fixture") do
  !INTEG_SRC.include?('JOIN') && !INTEG_SRC.include?('AGGREGATE') &&
    !INTEG_SRC.include?('write_file') && !INTEG_SRC.include?('write_json')
end

check("EXECQ2-GAP-07: gate failures short-circuit before filter/order/limit evaluation") do
  # G1/G2/G3 denied results have rows:[] (no filter/order/limit was applied)
  [C_INTEG_DENIED, C_G2, C_G3].all? do |r|
    r[:result]['kind'] == 'denied' &&
      r[:rows] == [] &&
      r[:receipt]['rows_returned'] == 0
  end
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-EXECUTE-QUERY-P2: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  - First complete mocked ExecuteQuery pipeline: gates + filter + order + limit + receipt"
  puts "  - G1/G2/G3 gate failures short-circuit before filter/order/limit evaluation"
  puts "  - G4 row-limit clamp: effective_limit = min(plan.limit, cap.row_limit); NOT denial"
  puts "  - G5 include_all → kind:\"query_error\" (NOT \"denied\")"
  puts "  - Filter: eq/neq/contains/prefix; AND-only; unknown op → query_error; missing field → empty"
  puts "  - Order: asc/desc lexicographic; stable sort; unknown direction → query_error"
  puts "  - Limit: applied AFTER filter+order; limit==0 → empty; negative → query_error"
  puts "  - BuildIntegratedPlan.filters typed Collection[FilterPredicate] in Rust SIR (5th P2 confirmation)"
  puts "  - All 8 contracts VM-executed; receipt 15-field shape verified"
  puts "  - query_error ≠ denied throughout integrated pipeline"
  puts "  - QueryPlan.limit ≠ StorageCapability row_limit gate (orthogonal)"
  puts "  - IntegratedQuerySim is PROOF-LOCAL ONLY — not production query runtime"
  puts "  - No SQL / DB / ORM / StorageCapability live execution at any layer"
else
  puts "LAB-EXECUTE-QUERY-P2: #{$fail_count} check(s) failed"
  exit 1
end
