#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_filter_eval_p1.rb
# LAB-FILTER-EVAL-P1 — 50 checks
#
# Proves the first semantic evaluation layer for QueryPlan.filters:
# a Collection[FilterPredicate] can be applied to mocked in-memory rows and
# produce deterministic QueryResult data, without SQL, database access, ORM,
# or storage runtime authority.
#
# Core formula:
#   FilterEval v0 = Collection[FilterPredicate] + mocked rows → QueryResult
#   FilterEval v0 ≠ SQL execution ≠ DB runtime ≠ ORM ≠ StorageCapability execution
#   QueryPlan.filters is no longer just shape — it has a v0 meaning over mocked rows.
#
# Three-layer proof:
#   Layer A — Ruby TypeChecker: 9 contracts accepted; FilterPredicate / QueryPlan shapes;
#             QueryPlan.filters: Collection[FilterPredicate]; QueryResult metadata chain.
#   Layer B — Lab Rust compiler: fixture compiles; Rust SIR: BuildQueryPlanWithFilters.filters
#             typed Collection[FilterPredicate] from record-field context (P2 pattern);
#             inline empty filter array also types correctly.
#   Layer C — Proof-local FilterEvalSim: eq/neq/contains/prefix operators; AND composition;
#             empty-filter-list returns all rows; unknown field → no match (not error);
#             unknown operator → query_error (NOT denied); denial-as-data invariant.
#
# v0 semantics:
#   - Operators: eq (==), neq (!=), contains (substring), prefix (starts_with)
#   - Composition: AND only (all predicates must pass; v0 does not support OR/NOT/JOIN)
#   - Empty filter list → all rows returned (vacuous conjunction = true)
#   - Unknown field in row → no match for that row (row fails predicate; not query_error)
#   - Unknown operator → kind:"query_error" (malformed predicate; NOT access denial)
#   - Zero matches → kind:"empty"; at least one match → kind:"rows"
#
# Row model (Layer C): Array of Hash[String → String] (in-memory only; no DB, no ORM)
#
# Single fixture: filter_eval.ig — 9 pure CORE contracts (no effect contracts)
# No two-fixture split needed (no ESCAPE class contracts; all pure).
#
# Sections:
#   FEVAL-COMPILE   (5)  — fixture compiles; 9 contracts; Ruby TC accepted
#   FEVAL-SHAPE     (7)  — FilterPredicate / QueryPlan.filters / QueryResult shapes
#   FEVAL-ARRAY     (4)  — inline filter array Collection[FilterPredicate] (Rust SIR)
#   FEVAL-SEMANTICS (7)  — Layer C: eq/neq/contains/prefix/AND/empty-list/missing-field
#   FEVAL-RESULT    (6)  — Layer C: rows/empty/query_error results; count invariants
#   FEVAL-VM        (8)  — Layer B VM execution (6 contracts)
#   FEVAL-CLOSED    (5)  — no SQL/DB/ORM/StorageCapability/write at any layer
#   FEVAL-GAP       (8)  — boundary findings: in-memory only; AND-only; OR/NOT deferred
#
# Total: 50 checks
#
# Depends on:
#   LAB-QUERY-P3 (QueryPlan v1 — 44/44)
#   LAB-TC-ARRAY-P2 (Collection[FilterPredicate] from record-field context — 19/19)
#   LAB-EXECUTE-QUERY-P1 (ExecuteQuery gate sequence — 57/57)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_filter_eval_p1.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_execution' / 'filter_eval.ig').to_s

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
# compile_path: compiles a fixture, reads per-contract JSON files from
# out_dir/contracts/*.json for compute_nodes[].type_tag and output_ports[].type_tag
# (Rust SIR). Returns { report:, out_dir:, contracts: {name => data} }.

def compile_path(path, tag = 'feval')
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

def compile_inline(src, tag = 'inline')
  f = Tempfile.new([tag, '.ig'])
  f.write(src)
  f.close
  result = compile_path(f.path, tag)
  f.unlink rescue nil
  result
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
  tmpfile = Tempfile.new(['feval_inputs', '.json'])
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

# ── Layer C: Proof-local filter evaluation simulator ─────────────────────────
#
# FilterEvalSim: applies Collection[FilterPredicate] to mocked in-memory rows.
#
# v0 operators: eq (==), neq (!=), contains (substring), prefix (starts_with)
# v0 composition: AND only — all predicates must pass for a row to match
# Empty filter list → all rows (vacuous conjunction = true)
# Unknown field in row → row fails that predicate (no match; not query_error)
# Unknown operator → kind:"query_error" (NOT kind:"denied")
# Zero matches → kind:"empty"; one or more → kind:"rows"
#
# Row model: Array of Hash[String => String] (in-memory Ruby; no DB; no SQL)
#
# FilterEvalSim ≠ DB execution ≠ SQL engine ≠ Arel ≠ ORM
# FilterEvalSim ≠ StorageCapability live execution
# FilterEvalSim is PROOF-LOCAL ONLY — not a production evaluation runtime.

module FilterEvalSim
  KNOWN_OPS = %w[eq neq contains prefix].freeze

  KDR_ROUTES = {
    'rows'        => { action: 'process', summary: 'matched rows returned; iterate and transform' },
    'empty'       => { action: 'empty',   summary: 'zero rows matched; show empty state' },
    'query_error' => { action: 'invalid', summary: 'malformed predicate; fix op name before retry' }
  }.freeze

  def self.evaluate(rows, filters, metadata: {})
    # Check for unknown operator first — any bad op → query_error (fail-closed on predicate shape)
    bad_op = filters.find { |f| !KNOWN_OPS.include?(f['op']) }
    if bad_op
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => "unknown operator: #{bad_op['op']}", 'metadata' => metadata }
      return { result: result, matched_rows: [] }
    end

    # Apply AND composition: row passes only if ALL predicates match
    matched = rows.select { |row| filters.all? { |f| row_matches?(row, f) } }

    kind   = matched.empty? ? 'empty' : 'rows'
    result = { 'kind' => kind, 'count' => matched.length, 'message' => '', 'metadata' => metadata }
    { result: result, matched_rows: matched }
  end

  def self.route(result)
    kind = result.is_a?(Hash) ? result.fetch('kind', 'unknown') : result.to_s
    KDR_ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end

  private_class_method def self.row_matches?(row, filter)
    field   = filter['field']
    op      = filter['op']
    val     = filter['value']
    row_val = row[field]

    # Unknown field in row → no match for that row (not a query_error — row just fails predicate)
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

# ── Compile and run ────────────────────────────────────────────────────────────

FEVAL_SIR = compile_path(FIXTURE_PATH, 'feval')
FEVAL_TC  = run_fixture(FIXTURE_PATH)
FEVAL_SRC = File.read(FIXTURE_PATH).force_encoding('UTF-8').freeze
FEVAL_OUT = FEVAL_SIR[:out_dir]

ALL_CONTRACTS = %w[
  BuildFilterEq BuildFilterNeq BuildFilterContains BuildFilterPrefix
  BuildQueryPlanWithFilters FilterResultRows FilterResultEmpty
  FilterResultQueryError FilterResultMetadataReader
].freeze

# ── Inline fixture for empty filter array (FEVAL-ARRAY-04) ─────────────────────
# Confirms that compute filters = [] in a QueryPlan record-field context
# types as Collection[FilterPredicate] in the Rust SIR (same P2 mechanism).

EMPTY_FILTER_SRC = <<~'IG'
  module Lab.FEval.EmptyFilter
  type FilterPredicate { field: String, op: String, value: String }
  type QuerySource { table: String, schema: String }
  type Projection { fields: String, include_all: Bool }
  type OrderBy { field: String, direction: String }
  type QueryPlan {
    kind:       String,
    source:     QuerySource,
    projection: Projection,
    filters:    Collection[FilterPredicate],
    order:      OrderBy,
    limit:      Integer,
    metadata:   Map[String, String]
  }
  pure contract BuildEmptyFilterPlan {
    input source     : QuerySource
    input projection : Projection
    input order      : OrderBy
    input limit      : Integer
    input metadata   : Map[String, String]
    compute filters = []
    compute plan = {
      kind:       "select",
      source:     source,
      projection: projection,
      filters:    filters,
      order:      order,
      limit:      limit,
      metadata:   metadata
    }
    output plan : QueryPlan
  }
IG

EMPTY_FILTER_SIR = compile_inline(EMPTY_FILTER_SRC, 'feval_empty')

# ── VM inputs ──────────────────────────────────────────────────────────────────

VM_FILTER_EQ_INPUTS = { 'field' => 'status', 'value' => 'active' }.freeze
VM_FILTER_CON_INPUTS = { 'field' => 'name', 'value' => 'alex' }.freeze

VM_PLAN_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name,status,role,email', 'include_all' => false },
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 50,
  'metadata'   => { 'trace_id' => 'feval-plan', 'filter_count' => '2' }
}.freeze

VM_ROWS_INPUTS = {
  'count'    => 5,
  'metadata' => { 'trace_id' => 'feval-rows', 'filter_count' => '2' }
}.freeze

VM_EMPTY_INPUTS = {
  'metadata' => { 'trace_id' => 'feval-empty', 'filter_count' => '1' }
}.freeze

VM_QERR_INPUTS = {
  'metadata' => { 'trace_id' => 'feval-qerr', 'op' => 'like' }
}.freeze

VM_META_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 5, 'message' => '',
                   'metadata' => { 'filter_count' => '2', 'trace_id' => 'feval-meta' } },
  'query_key' => 'filter_count'
}.freeze

VM_META_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 5, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_FILTER_EQ  = FEVAL_OUT ? vm_run(FEVAL_OUT, 'BuildFilterEq',              VM_FILTER_EQ_INPUTS)  : {}
VM_FILTER_CON = FEVAL_OUT ? vm_run(FEVAL_OUT, 'BuildFilterContains',        VM_FILTER_CON_INPUTS) : {}
VM_PLAN_R     = FEVAL_OUT ? vm_run(FEVAL_OUT, 'BuildQueryPlanWithFilters',  VM_PLAN_INPUTS)       : {}
VM_ROWS_R     = FEVAL_OUT ? vm_run(FEVAL_OUT, 'FilterResultRows',           VM_ROWS_INPUTS)       : {}
VM_EMPTY_R    = FEVAL_OUT ? vm_run(FEVAL_OUT, 'FilterResultEmpty',          VM_EMPTY_INPUTS)      : {}
VM_QERR_R     = FEVAL_OUT ? vm_run(FEVAL_OUT, 'FilterResultQueryError',     VM_QERR_INPUTS)       : {}
VM_META_HIT   = FEVAL_OUT ? vm_run(FEVAL_OUT, 'FilterResultMetadataReader', VM_META_HIT_INPUTS)   : {}
VM_META_MISS  = FEVAL_OUT ? vm_run(FEVAL_OUT, 'FilterResultMetadataReader', VM_META_MISS_INPUTS)  : {}

# ── Layer C test rows ──────────────────────────────────────────────────────────
#
# 5 rows with fields: status, role, name, email
# Deterministic dataset for all semantic checks.
#
# eq(status="active")   → rows 0,1,3,4 (4 matches)
# neq(role!="guest")    → rows 0,1,2,4 (4 matches)
# contains(name,"alex") → rows 0,1      (2 matches: "alex", "alexia")
# prefix(email,"admin") → rows 0,2      (2 matches: "admin@…", "admin2@…")
# AND(status=active, role!=guest) → rows 0,1,4 (3 matches)
# empty filters         → all 5 rows
# field "phone" absent  → 0 matches → kind:"empty"

TEST_ROWS = [
  { 'status' => 'active',   'role' => 'admin', 'name' => 'alex',   'email' => 'admin@example.com'  },
  { 'status' => 'active',   'role' => 'user',  'name' => 'alexia', 'email' => 'user@example.com'   },
  { 'status' => 'inactive', 'role' => 'admin', 'name' => 'bob',    'email' => 'admin2@example.com' },
  { 'status' => 'active',   'role' => 'guest', 'name' => 'carol',  'email' => 'guest@example.com'  },
  { 'status' => 'active',   'role' => 'user',  'name' => 'dave',   'email' => 'dev@example.com'    },
].freeze

# ── Layer C evaluations ────────────────────────────────────────────────────────

C_EQ       = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }])
C_NEQ      = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'role', 'op' => 'neq', 'value' => 'guest' }])
C_CONTAINS = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'name', 'op' => 'contains', 'value' => 'alex' }])
C_PREFIX   = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'email', 'op' => 'prefix', 'value' => 'admin' }])
C_AND      = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'status', 'op' => 'eq',  'value' => 'active' },
                { 'field' => 'role',   'op' => 'neq', 'value' => 'guest'  }])
C_EMPTY_F  = FilterEvalSim.evaluate(TEST_ROWS, [])
C_MISSING  = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'phone', 'op' => 'eq', 'value' => '555' }])
C_UNKNOWN  = FilterEvalSim.evaluate(TEST_ROWS,
               [{ 'field' => 'status', 'op' => 'like', 'value' => 'act' }])
C_ZERO     = FilterEvalSim.evaluate([],
               [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }])

# ─────────────────────────────────────────────────────────────────────────────
# Proof sections
# ─────────────────────────────────────────────────────────────────────────────

puts "\nLAB-FILTER-EVAL-P1 proof — 50 checks"
puts "=" * 60

# ── FEVAL-COMPILE ─────────────────────────────────────────────────────────────
puts "\n── FEVAL-COMPILE (5) — fixture compiles; 9 contracts; Ruby TC accepted ──"

check("FEVAL-COMPILE-01: Rust compiler accepts filter_eval.ig — status ok") do
  status(FEVAL_SIR) == 'ok'
end

check("FEVAL-COMPILE-02: Rust compiler: 9 contracts in fixture") do
  contract_names(FEVAL_SIR).length == 9
end

check("FEVAL-COMPILE-03: Rust compiler: zero unexpected diagnostics") do
  diagnostics(FEVAL_SIR).empty?
end

check("FEVAL-COMPILE-04: Ruby TC: all 9 contracts accepted (status == 'accepted')") do
  ALL_CONTRACTS.all? { |name| contract_accepted?(FEVAL_TC, name) }
end

check("FEVAL-COMPILE-05: Ruby TC: zero type_errors across all 9 contracts") do
  ALL_CONTRACTS.all? { |name| type_errors_for(FEVAL_TC, name).empty? }
end

# ── FEVAL-SHAPE ───────────────────────────────────────────────────────────────
puts "\n── FEVAL-SHAPE (7) — FilterPredicate / QueryPlan.filters / QueryResult shapes ──"

check("FEVAL-SHAPE-01: FilterPredicate.field: String") do
  type_name_str(type_env_field(FEVAL_TC, 'FilterPredicate', 'field')) == 'String'
end

check("FEVAL-SHAPE-02: FilterPredicate.op: String") do
  type_name_str(type_env_field(FEVAL_TC, 'FilterPredicate', 'op')) == 'String'
end

check("FEVAL-SHAPE-03: FilterPredicate.value: String") do
  type_name_str(type_env_field(FEVAL_TC, 'FilterPredicate', 'value')) == 'String'
end

check("FEVAL-SHAPE-04: QueryPlan.filters: Collection[FilterPredicate]") do
  type_name_str(type_env_field(FEVAL_TC, 'QueryPlan', 'filters')) == 'Collection[FilterPredicate]'
end

check("FEVAL-SHAPE-05: QueryResult.count: Integer") do
  type_name_str(type_env_field(FEVAL_TC, 'QueryResult', 'count')) == 'Integer'
end

check("FEVAL-SHAPE-06: QueryResult.kind: String") do
  type_name_str(type_env_field(FEVAL_TC, 'QueryResult', 'kind')) == 'String'
end

check("FEVAL-SHAPE-07: QueryResult.metadata: Map[String,String]") do
  type_name_str(type_env_field(FEVAL_TC, 'QueryResult', 'metadata')) == 'Map[String,String]'
end

# ── FEVAL-ARRAY ───────────────────────────────────────────────────────────────
puts "\n── FEVAL-ARRAY (4) — inline filter array Collection[FilterPredicate] (Rust SIR) ──"

check("FEVAL-ARRAY-01: Rust SIR: BuildQueryPlanWithFilters.filters compute_type_tag = Collection[FilterPredicate]") do
  compute_type_tag(FEVAL_SIR, 'BuildQueryPlanWithFilters', 'filters') == 'Collection[FilterPredicate]'
end

check("FEVAL-ARRAY-02: Rust SIR: BuildQueryPlanWithFilters.plan compute_type_tag = QueryPlan") do
  compute_type_tag(FEVAL_SIR, 'BuildQueryPlanWithFilters', 'plan') == 'QueryPlan'
end

check("FEVAL-ARRAY-03: Rust SIR: BuildQueryPlanWithFilters plan output_port type_tag = QueryPlan") do
  output_type_tag(FEVAL_SIR, 'BuildQueryPlanWithFilters', 'plan') == 'QueryPlan'
end

check("FEVAL-ARRAY-04: Inline: empty filter array types Collection[FilterPredicate] from record-field context") do
  status(EMPTY_FILTER_SIR) == 'ok' &&
    compute_type_tag(EMPTY_FILTER_SIR, 'BuildEmptyFilterPlan', 'filters') == 'Collection[FilterPredicate]'
end

# ── FEVAL-SEMANTICS ───────────────────────────────────────────────────────────
puts "\n── FEVAL-SEMANTICS (7) — Layer C predicate evaluation semantics ──"

check("FEVAL-SEMANTICS-01: Layer C: eq(status=\"active\") → 4 matched rows (rows 0,1,3,4)") do
  C_EQ[:matched_rows].length == 4 &&
    C_EQ[:matched_rows].all? { |r| r['status'] == 'active' }
end

check("FEVAL-SEMANTICS-02: Layer C: neq(role!=\"guest\") → 4 matched rows (excludes row 3)") do
  C_NEQ[:matched_rows].length == 4 &&
    C_NEQ[:matched_rows].none? { |r| r['role'] == 'guest' }
end

check("FEVAL-SEMANTICS-03: Layer C: contains(name,\"alex\") → 2 matched rows (\"alex\", \"alexia\")") do
  C_CONTAINS[:matched_rows].length == 2 &&
    C_CONTAINS[:matched_rows].all? { |r| r['name'].include?('alex') }
end

check("FEVAL-SEMANTICS-04: Layer C: prefix(email,\"admin\") → 2 matched rows (admin@…, admin2@…)") do
  C_PREFIX[:matched_rows].length == 2 &&
    C_PREFIX[:matched_rows].all? { |r| r['email'].start_with?('admin') }
end

check("FEVAL-SEMANTICS-05: Layer C: AND(status=active, role!=guest) → 3 matched rows") do
  C_AND[:matched_rows].length == 3 &&
    C_AND[:matched_rows].all? { |r| r['status'] == 'active' && r['role'] != 'guest' }
end

check("FEVAL-SEMANTICS-06: Layer C: empty filter list → all 5 rows returned (vacuous conjunction)") do
  C_EMPTY_F[:matched_rows].length == TEST_ROWS.length &&
    C_EMPTY_F[:result]['kind'] == 'rows'
end

check("FEVAL-SEMANTICS-07: Layer C: missing field \"phone\" → 0 matched rows (field absence ≠ query_error)") do
  C_MISSING[:matched_rows].empty? &&
    C_MISSING[:result]['kind'] == 'empty' &&
    C_MISSING[:result]['kind'] != 'query_error'
end

# ── FEVAL-RESULT ──────────────────────────────────────────────────────────────
puts "\n── FEVAL-RESULT (6) — Layer C result kinds; count invariants ──"

check("FEVAL-RESULT-01: Layer C: eq result → kind:\"rows\", count:4") do
  C_EQ[:result]['kind'] == 'rows' && C_EQ[:result]['count'] == 4
end

check("FEVAL-RESULT-02: Layer C: zero input rows → kind:\"empty\", count:0") do
  C_ZERO[:result]['kind'] == 'empty' && C_ZERO[:result]['count'] == 0
end

check("FEVAL-RESULT-03: Layer C: unknown operator \"like\" → kind:\"query_error\" (NOT \"denied\")") do
  C_UNKNOWN[:result]['kind'] == 'query_error' &&
    C_UNKNOWN[:result]['kind'] != 'denied'
end

check("FEVAL-RESULT-04: Layer C: count == matched_rows.length (invariant holds across all evals)") do
  [C_EQ, C_NEQ, C_CONTAINS, C_PREFIX, C_AND, C_EMPTY_F, C_MISSING].all? do |c|
    c[:result]['count'] == c[:matched_rows].length
  end
end

check("FEVAL-RESULT-05: Layer C: missing field → kind:\"empty\" (not \"query_error\") — field absence ≠ bad op") do
  C_MISSING[:result]['kind'] == 'empty' &&
    C_MISSING[:result]['kind'] != 'query_error' &&
    C_MISSING[:matched_rows].empty?
end

check("FEVAL-RESULT-06: Layer C: AND narrows count below individual filter counts (3 < 4)") do
  C_AND[:result]['count'] < C_EQ[:result]['count'] &&
    C_AND[:result]['count'] < C_NEQ[:result]['count'] &&
    C_AND[:result]['count'] == 3
end

# ── FEVAL-VM ──────────────────────────────────────────────────────────────────
puts "\n── FEVAL-VM (8) — Layer B VM execution ──"

check("FEVAL-VM-01: VM BuildFilterEq(field:\"status\", value:\"active\") → { op:\"eq\", field:\"status\", value:\"active\" }") do
  VM_FILTER_EQ['status'] == 'success' &&
    VM_FILTER_EQ.dig('result', 'op')    == 'eq'     &&
    VM_FILTER_EQ.dig('result', 'field') == 'status' &&
    VM_FILTER_EQ.dig('result', 'value') == 'active'
end

check("FEVAL-VM-02: VM BuildFilterContains(field:\"name\", value:\"alex\") → { op:\"contains\" }") do
  VM_FILTER_CON['status'] == 'success' &&
    VM_FILTER_CON.dig('result', 'op')    == 'contains' &&
    VM_FILTER_CON.dig('result', 'field') == 'name'     &&
    VM_FILTER_CON.dig('result', 'value') == 'alex'
end

check("FEVAL-VM-03: VM BuildQueryPlanWithFilters → kind:\"select\"; filters is 2-element array") do
  filters = VM_PLAN_R.dig('result', 'filters')
  VM_PLAN_R['status'] == 'success' &&
    VM_PLAN_R.dig('result', 'kind') == 'select' &&
    filters.is_a?(Array) && filters.length == 2 &&
    filters[0]['field'] == 'status' && filters[1]['field'] == 'role'
end

check("FEVAL-VM-04: VM FilterResultRows(count:5) → kind:\"rows\", count:5") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind')  == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 5
end

check("FEVAL-VM-05: VM FilterResultEmpty → kind:\"empty\", count:0") do
  VM_EMPTY_R['status'] == 'success' &&
    VM_EMPTY_R.dig('result', 'kind')  == 'empty' &&
    VM_EMPTY_R.dig('result', 'count') == 0
end

check("FEVAL-VM-06: VM FilterResultQueryError → kind:\"query_error\", count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind')  == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("FEVAL-VM-07: VM FilterResultMetadataReader(key=\"filter_count\") → \"2\" (map_get hit)") do
  VM_META_HIT['status'] == 'success' && VM_META_HIT['result'] == '2'
end

check("FEVAL-VM-08: VM FilterResultMetadataReader(key=\"missing\") → \"not-found\" (or_else default)") do
  VM_META_MISS['status'] == 'success' && VM_META_MISS['result'] == 'not-found'
end

# ── FEVAL-CLOSED ──────────────────────────────────────────────────────────────
puts "\n── FEVAL-CLOSED (5) — closed surfaces ──"

check("FEVAL-CLOSED-01: no SQL execution in fixture source") do
  !FEVAL_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+|CREATE\s+TABLE/i) &&
    !FEVAL_SRC.include?('execute_' + 'sql') && !FEVAL_SRC.include?('.sql')
end

check("FEVAL-CLOSED-02: no database connection / ORM in fixture source") do
  !FEVAL_SRC.include?('establish_connection') && !FEVAL_SRC.include?('data' + 'base_url') &&
    !FEVAL_SRC.include?('Active' + 'Record') && !FEVAL_SRC.include?('connect_to(')
end

check("FEVAL-CLOSED-03: no persistence runtime in proof runner source") do
  !SOURCE.include?('Base.establish_' + 'connection') &&
    !SOURCE.include?('DATABASE_URL' + '=') &&
    !SOURCE.include?('Sequ' + 'el.connect(') &&
    !SOURCE.include?('execute_' + 'sql(') &&
    !SOURCE.include?('Active' + 'Record::Base')
end

check("FEVAL-CLOSED-04: no StorageCapability live execution / no effect contracts in fixture") do
  !FEVAL_SRC.include?('IO.StorageCapability') &&
    !FEVAL_SRC.include?('effect contract')
end

check("FEVAL-CLOSED-05: no write ops / transactions in fixture") do
  !FEVAL_SRC.include?('write_file') && !FEVAL_SRC.include?('write_json') &&
    !FEVAL_SRC.include?('transaction') && !FEVAL_SRC.include?('write_allowed')
end

# ── FEVAL-GAP ─────────────────────────────────────────────────────────────────
puts "\n── FEVAL-GAP (8) — boundary findings ──"

check("FEVAL-GAP-01: SQL execution absent — no sql_exec / raw_sql / SELECT FROM in fixture") do
  !FEVAL_SRC.include?('execute_' + 'sql') && !FEVAL_SRC.include?('raw_sql') &&
    !FEVAL_SRC.match?(/SELECT\s+FROM/i)
end

check("FEVAL-GAP-02: Real DB connection absent — no establish_connection / db_url in fixture") do
  !FEVAL_SRC.include?('establish_connection') && !FEVAL_SRC.include?('data' + 'base_url')
end

check("FEVAL-GAP-03: Filtered rows are in-memory Ruby hashes — not DB rows; not ORM records") do
  C_EQ[:matched_rows].all? { |r| r.is_a?(Hash) } &&
    C_AND[:matched_rows].all? { |r| r.is_a?(Hash) }
end

check("FEVAL-GAP-04: FilterEvalSim uses AND-only composition in v0 (filters.all? not any?)") do
  SOURCE.include?('filters.all?') && !SOURCE.include?('filters.an' + 'y?')
end

check("FEVAL-GAP-05: OR / NOT / JOIN / aggregate operators NOT in FilterEvalSim::KNOWN_OPS") do
  !FilterEvalSim::KNOWN_OPS.include?('or') &&
    !FilterEvalSim::KNOWN_OPS.include?('not') &&
    !FilterEvalSim::KNOWN_OPS.include?('join') &&
    !FilterEvalSim::KNOWN_OPS.include?('count') &&
    !FilterEvalSim::KNOWN_OPS.include?('sum')
end

check("FEVAL-GAP-06: Unknown operator → kind:\"query_error\" NOT \"denied\" (C_UNKNOWN)") do
  C_UNKNOWN[:result]['kind'] == 'query_error' &&
    C_UNKNOWN[:result]['kind'] != 'denied' &&
    FilterEvalSim.route(C_UNKNOWN[:result])[:action] == 'invalid'
end

check("FEVAL-GAP-07: G1–G6 StorageCapability gate sequence absent — filter_eval.ig is gate-independent") do
  !FEVAL_SRC.include?('allow_include_all') &&
    !FEVAL_SRC.include?('read_allowed') &&
    !FEVAL_SRC.include?('denial_gate') &&
    !FEVAL_SRC.include?('row_limit')
end

check("FEVAL-GAP-08: query_error ≠ denied — distinct kinds; distinct consumer actions") do
  C_UNKNOWN[:result]['kind'] != 'denied' &&
    FilterEvalSim.route(C_UNKNOWN[:result])[:action] != 'deny' &&
    FilterEvalSim.route({ 'kind' => 'query_error' })[:action] == 'invalid' &&
    FilterEvalSim.route({ 'kind' => 'rows' })[:action] == 'process'
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-FILTER-EVAL-P1: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  - FilterPredicate shapes (eq/neq/contains/prefix) accepted at Layer A + Layer B"
  puts "  - BuildQueryPlanWithFilters.filters typed Collection[FilterPredicate] in Rust SIR (P2 mechanism)"
  puts "  - Empty filter array also types Collection[FilterPredicate] from record-field context"
  puts "  - FilterEvalSim: eq/neq/contains/prefix correct over 5-row deterministic dataset"
  puts "  - AND composition: 3 matches < 4 (individual eq/neq counts); vacuous list → all 5"
  puts "  - Unknown field → kind:\"empty\" (no match, not error); unknown op → kind:\"query_error\""
  puts "  - query_error ≠ denied: distinct consumer action (invalid vs deny)"
  puts "  - No SQL / DB / ORM / StorageCapability live execution at any layer"
else
  puts "LAB-FILTER-EVAL-P1: #{$fail_count} check(s) failed"
  exit 1
end
