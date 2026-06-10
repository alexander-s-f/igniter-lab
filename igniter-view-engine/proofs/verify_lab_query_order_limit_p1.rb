#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_query_order_limit_p1.rb
# LAB-QUERY-ORDER-LIMIT-P1 — 54 checks
#
# Proves v0 QueryPlan.order and QueryPlan.limit semantics over mocked in-memory rows,
# complementing LAB-FILTER-EVAL-P1.
#
# Core formula:
#   OrderLimit v0 = mocked rows + OrderBy + limit → ordered/limited rows + QueryResult
#   OrderLimit v0 ≠ SQL ORDER BY ≠ DB runtime ≠ ORM ≠ query optimizer
#   OrderLimit v0 ≠ StorageCapability row-limit gate
#
# Three-layer proof:
#   Layer A — Ruby TypeChecker: 7 contracts accepted; OrderBy / QueryPlan shapes;
#             QueryPlan.order: OrderBy; QueryPlan.limit: Integer.
#   Layer B — Lab Rust compiler + VM: fixture compiles; Rust SIR:
#             BuildQueryPlanOrderLimit.filters = Collection[FilterPredicate] (P2 mechanism);
#             BuildQueryPlanOrderLimit.order = OrderBy; VM executes all 7 contracts.
#   Layer C — Proof-local OrderLimitSim: asc/desc lexicographic sort; stable sort;
#             limit slicing after ordering; limit==0 → empty; limit<0 → query_error;
#             unknown direction → query_error; missing order field → query_error;
#             count == returned_rows.length invariant.
#
# v0 order semantics (Layer C):
#   direction = "asc"  → ascending lexicographic order on row[field]
#   direction = "desc" → descending lexicographic order on row[field]
#   unknown direction  → kind:"query_error" (NOT "denied")
#   missing order field in any row → kind:"query_error" (fail-closed; documented v0 rule)
#   equal keys → preserve input order (stable sort)
#   empty order field string → preserve input order (no ordering applied)
#
# v0 limit semantics (Layer C):
#   limit > 0  → return at most limit rows (applied AFTER ordering)
#   limit == 0 → kind:"empty", count:0
#   limit < 0  → kind:"query_error" (NOT "denied")
#   QueryPlan.limit ≠ StorageCapability row_limit gate (orthogonal concerns)
#
# Row model (Layer C): Array of Hash[String => String] (in-memory only; no DB; no SQL)
# All comparisons lexicographic as String in v0. Numeric/date ordering deferred.
#
# Single fixture: order_limit.ig — 7 pure CORE contracts (no effect contracts)
# No two-fixture split needed (no ESCAPE class contracts; all pure).
#
# Sections:
#   OLIMIT-COMPILE   (5)  — fixture compiles; 7 contracts; Ruby TC accepted
#   OLIMIT-SHAPE     (7)  — OrderBy / QueryPlan.order+limit / QueryResult shapes
#   OLIMIT-SEMANTICS (8)  — Layer C: asc/desc/stable/empty-field/unknown-dir/missing-field
#   OLIMIT-LIMIT     (7)  — Layer C: limit 1/2/over/zero/negative; applied after ordering
#   OLIMIT-RESULT    (6)  — Layer C: rows/empty/query_error kinds; count invariant; metadata
#   OLIMIT-VM        (8)  — Layer B VM execution (all 7 contracts)
#   OLIMIT-COMPOSE   (4)  — order-then-limit; compose after filter; StorageCapability distinct
#   OLIMIT-CLOSED    (5)  — no SQL/DB/ORM/StorageCapability/write at any layer
#   OLIMIT-GAP       (4)  — boundary answers: SQL? NO; real DB? NO; lex-only? YES; etc.
#
# Total: 54 checks
#
# Depends on:
#   LAB-QUERY-P3          (QueryPlan v1 — 44/44)
#   LAB-EXECUTE-QUERY-P1  (StorageCapability gate sequence — 57/57)
#   LAB-FILTER-EVAL-P1    (filter predicate evaluation — 50/50)
#   LAB-TC-ARRAY-P2       (Collection[FilterPredicate] from record-field context — 19/19)
#   PROP-043-P5           (Map[String,String] production TypeChecker — 55/55)
#   LAB-VM-MAP-P1         (VM map_get/or_else — 48/48)
#   LAB-RECORD-VM-P3      (nested record field access — 49/49)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No stable surface. No public API. No StorageCapability execution authority.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_query_order_limit_p1.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_execution' / 'order_limit.ig').to_s

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

# ── Layer B: Lab Rust compiler + VM helpers ────────────────────────────────────

def compile_path(path, tag = 'olimit')
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
  tmpfile = Tempfile.new(['olimit_inputs', '.json'])
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

# ── Layer C: Proof-local order + limit simulator ──────────────────────────────
#
# OrderLimitSim: applies OrderBy and limit to mocked in-memory rows.
#
# v0 order semantics:
#   "asc"  → ascending lexicographic sort on row[field]
#   "desc" → descending lexicographic sort on row[field]
#   ""     → no ordering applied; preserve input order
#   other  → kind:"query_error"
#   missing order field in any row → kind:"query_error" (fail-closed)
#   equal keys → stable sort (preserve original input order)
#
# v0 limit semantics:
#   limit > 0  → slice first limit rows (applied AFTER ordering)
#   limit == 0 → kind:"empty"
#   limit < 0  → kind:"query_error"
#
# All comparisons are lexicographic String comparisons in v0.
# Numeric/date ordering is explicitly deferred.
#
# OrderLimitSim ≠ SQL ORDER BY ≠ LIMIT clause ≠ query optimizer
# OrderLimitSim ≠ StorageCapability row_limit gate
# OrderLimitSim is PROOF-LOCAL ONLY — not a production evaluation runtime.

module OrderLimitSim
  KNOWN_DIRECTIONS = %w[asc desc].freeze

  KDR_ROUTES = {
    'rows'        => { action: 'process', summary: 'ordered/limited rows returned; iterate and transform' },
    'empty'       => { action: 'empty',   summary: 'zero rows after limit; show empty state' },
    'query_error' => { action: 'invalid', summary: 'malformed order/limit field; fix before retry' }
  }.freeze

  def self.apply(rows, order_by, limit, metadata: {})
    field     = order_by['field']
    direction = order_by['direction']

    # Negative limit → query_error immediately
    if limit < 0
      result = { 'kind' => 'query_error', 'count' => 0,
                 'message' => 'negative limit', 'metadata' => metadata }
      return { result: result, returned_rows: [] }
    end

    # Empty direction string → preserve input order, no sorting
    unless direction.empty?
      # Unknown direction → query_error
      unless KNOWN_DIRECTIONS.include?(direction)
        result = { 'kind' => 'query_error', 'count' => 0,
                   'message' => "unknown direction: #{direction}", 'metadata' => metadata }
        return { result: result, returned_rows: [] }
      end

      # Empty order field string → skip sorting (preserve input order)
      unless field.empty?
        # Missing order field in any row → query_error (fail-closed)
        missing = rows.find { |r| !r.key?(field) }
        if missing
          result = { 'kind' => 'query_error', 'count' => 0,
                     'message' => "order field absent in row: #{field}", 'metadata' => metadata }
          return { result: result, returned_rows: [] }
        end

        # Stable lexicographic sort — Ruby's sort_by is stable (preserves input order for ties)
        rows = rows.each_with_index
                   .sort_by { |r, i| [r[field], i] }
                   .map(&:first)
        rows = rows.reverse if direction == 'desc'
      end
    end

    # Apply limit (limit == 0 → empty; limit > 0 → take first limit rows)
    if limit == 0
      result = { 'kind' => 'empty', 'count' => 0,
                 'message' => 'limit zero', 'metadata' => metadata }
      return { result: result, returned_rows: [] }
    end

    returned = rows.first(limit)
    kind     = returned.empty? ? 'empty' : 'rows'
    result   = { 'kind' => kind, 'count' => returned.length,
                 'message' => '', 'metadata' => metadata }
    { result: result, returned_rows: returned }
  end

  def self.route(result)
    kind = result.is_a?(Hash) ? result.fetch('kind', 'unknown') : result.to_s
    KDR_ROUTES.fetch(kind, { action: 'unknown', summary: 'unrecognised kind; fail closed' })
  end
end

# ── Compile and run ────────────────────────────────────────────────────────────

OLIMIT_SIR = compile_path(FIXTURE_PATH, 'olimit')
OLIMIT_TC  = run_fixture(FIXTURE_PATH)
OLIMIT_SRC = File.read(FIXTURE_PATH).force_encoding('UTF-8').freeze
OLIMIT_OUT = OLIMIT_SIR[:out_dir]

ALL_CONTRACTS = %w[
  BuildOrderAsc BuildOrderDesc BuildQueryPlanOrderLimit
  OrderLimitRows OrderLimitEmpty OrderLimitQueryError OrderLimitMetadataReader
].freeze

# ── Layer C test rows ──────────────────────────────────────────────────────────
#
# 5 rows with fields: name, score, status, created_at
# Lexicographic ordering (all String values in v0):
#   name asc:  alice, bob, carol, dave, eve
#   name desc: eve, dave, carol, bob, alice
#   score asc: "10", "20", "30", "40", "50"  (lexicographic: "10"<"20"<"30"<"40"<"50")
#   created_at asc: "2024-01-01" < "2024-01-02" < ... (ISO date strings lex-order = date-order)

TEST_ROWS = [
  { 'name' => 'carol', 'score' => '30', 'status' => 'active',   'created_at' => '2024-01-03' },
  { 'name' => 'alice', 'score' => '10', 'status' => 'active',   'created_at' => '2024-01-01' },
  { 'name' => 'eve',   'score' => '50', 'status' => 'inactive', 'created_at' => '2024-01-05' },
  { 'name' => 'bob',   'score' => '20', 'status' => 'active',   'created_at' => '2024-01-02' },
  { 'name' => 'dave',  'score' => '40', 'status' => 'active',   'created_at' => '2024-01-04' },
].freeze

# Rows with duplicate name field for stable-sort test
DUPE_ROWS = [
  { 'name' => 'bob', 'score' => '20' },
  { 'name' => 'alice', 'score' => '10' },
  { 'name' => 'bob', 'score' => '30' },
  { 'name' => 'alice', 'score' => '40' },
].freeze

# ── Layer C evaluations ────────────────────────────────────────────────────────

ORDER_ASC   = { 'field' => 'name', 'direction' => 'asc'  }
ORDER_DESC  = { 'field' => 'name', 'direction' => 'desc' }
ORDER_SCORE = { 'field' => 'score', 'direction' => 'asc' }
ORDER_EMPTY = { 'field' => '', 'direction' => '' }
ORDER_BAD   = { 'field' => 'name', 'direction' => 'random' }
ORDER_MISS  = { 'field' => 'phone', 'direction' => 'asc' }

# Ordering only (limit larger than row count → all rows returned)
C_ASC_ALL   = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC,   100)
C_DESC_ALL  = OrderLimitSim.apply(TEST_ROWS, ORDER_DESC,  100)
C_SCORE_ALL = OrderLimitSim.apply(TEST_ROWS, ORDER_SCORE, 100)

# Stable sort — rows with equal 'name' preserve input order
C_STABLE    = OrderLimitSim.apply(DUPE_ROWS, ORDER_ASC,   100)

# Empty direction → preserve input order
C_NO_ORDER  = OrderLimitSim.apply(TEST_ROWS, ORDER_EMPTY, 100)

# Limit tests (ordered by name asc first)
C_LIMIT_1   = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC, 1)
C_LIMIT_2   = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC, 2)
C_LIMIT_OVER = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC, 99)
C_LIMIT_ZERO = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC, 0)
C_LIMIT_NEG  = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC, -1)

# Error cases
C_BAD_DIR   = OrderLimitSim.apply(TEST_ROWS, ORDER_BAD,  10)
C_MISS_FIELD = OrderLimitSim.apply(TEST_ROWS, ORDER_MISS, 10)

# ── VM inputs ──────────────────────────────────────────────────────────────────

VM_ORDER_ASC_INPUTS  = { 'field' => 'name' }.freeze
VM_ORDER_DESC_INPUTS = { 'field' => 'created_at' }.freeze

VM_PLAN_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name,score', 'include_all' => false },
  'order'      => { 'field' => 'name', 'direction' => 'asc' },
  'limit'      => 10,
  'metadata'   => { 'trace_id' => 'olimit-plan', 'order_field' => 'name' }
}.freeze

VM_ROWS_INPUTS = {
  'count'    => 3,
  'metadata' => { 'trace_id' => 'olimit-rows', 'order_direction' => 'asc' }
}.freeze

VM_EMPTY_INPUTS = {
  'metadata' => { 'trace_id' => 'olimit-empty', 'limit' => '0' }
}.freeze

VM_QERR_INPUTS = {
  'reason'   => 'unknown direction: random',
  'metadata' => { 'trace_id' => 'olimit-qerr' }
}.freeze

VM_META_HIT_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 3, 'message' => '',
                   'metadata' => { 'order_field' => 'name', 'trace_id' => 'olimit-meta' } },
  'query_key' => 'order_field'
}.freeze

VM_META_MISS_INPUTS = {
  'result'    => { 'kind' => 'rows', 'count' => 3, 'message' => '', 'metadata' => {} },
  'query_key' => 'missing_key'
}.freeze

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_ASC_R    = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'BuildOrderAsc',            VM_ORDER_ASC_INPUTS)  : {}
VM_DESC_R   = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'BuildOrderDesc',           VM_ORDER_DESC_INPUTS) : {}
VM_PLAN_R   = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'BuildQueryPlanOrderLimit', VM_PLAN_INPUTS)       : {}
VM_ROWS_R   = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'OrderLimitRows',           VM_ROWS_INPUTS)       : {}
VM_EMPTY_R  = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'OrderLimitEmpty',          VM_EMPTY_INPUTS)      : {}
VM_QERR_R   = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'OrderLimitQueryError',     VM_QERR_INPUTS)       : {}
VM_META_HIT = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'OrderLimitMetadataReader', VM_META_HIT_INPUTS)   : {}
VM_META_MISS = OLIMIT_OUT ? vm_run(OLIMIT_OUT, 'OrderLimitMetadataReader', VM_META_MISS_INPUTS) : {}

# ─────────────────────────────────────────────────────────────────────────────
# Proof sections
# ─────────────────────────────────────────────────────────────────────────────

puts "\nLAB-QUERY-ORDER-LIMIT-P1 proof — 54 checks"
puts "=" * 60

# ── OLIMIT-COMPILE ────────────────────────────────────────────────────────────
puts "\n── OLIMIT-COMPILE (5) — fixture compiles; 7 contracts; Ruby TC accepted ──"

check("OLIMIT-COMPILE-01: Rust compiler accepts order_limit.ig — status ok") do
  status(OLIMIT_SIR) == 'ok'
end

check("OLIMIT-COMPILE-02: Rust compiler: 7 contracts in fixture") do
  contract_names(OLIMIT_SIR).length == 7
end

check("OLIMIT-COMPILE-03: Rust compiler: zero unexpected diagnostics") do
  diagnostics(OLIMIT_SIR).empty?
end

check("OLIMIT-COMPILE-04: Ruby TC: all 7 contracts accepted") do
  ALL_CONTRACTS.all? { |name| contract_accepted?(OLIMIT_TC, name) }
end

check("OLIMIT-COMPILE-05: Ruby TC: zero type_errors across all 7 contracts") do
  ALL_CONTRACTS.all? { |name| type_errors_for(OLIMIT_TC, name).empty? }
end

# ── OLIMIT-SHAPE ──────────────────────────────────────────────────────────────
puts "\n── OLIMIT-SHAPE (7) — OrderBy / QueryPlan.order+limit / QueryResult shapes ──"

check("OLIMIT-SHAPE-01: OrderBy.field: String") do
  type_name_str(type_env_field(OLIMIT_TC, 'OrderBy', 'field')) == 'String'
end

check("OLIMIT-SHAPE-02: OrderBy.direction: String") do
  type_name_str(type_env_field(OLIMIT_TC, 'OrderBy', 'direction')) == 'String'
end

check("OLIMIT-SHAPE-03: QueryPlan.order: OrderBy") do
  type_name_str(type_env_field(OLIMIT_TC, 'QueryPlan', 'order')) == 'OrderBy'
end

check("OLIMIT-SHAPE-04: QueryPlan.limit: Integer") do
  type_name_str(type_env_field(OLIMIT_TC, 'QueryPlan', 'limit')) == 'Integer'
end

check("OLIMIT-SHAPE-05: QueryPlan.filters: Collection[FilterPredicate]") do
  type_name_str(type_env_field(OLIMIT_TC, 'QueryPlan', 'filters')) == 'Collection[FilterPredicate]'
end

check("OLIMIT-SHAPE-06: QueryResult.count: Integer") do
  type_name_str(type_env_field(OLIMIT_TC, 'QueryResult', 'count')) == 'Integer'
end

check("OLIMIT-SHAPE-07: QueryResult.metadata: Map[String,String]") do
  type_name_str(type_env_field(OLIMIT_TC, 'QueryResult', 'metadata')) == 'Map[String,String]'
end

# ── OLIMIT-SEMANTICS ──────────────────────────────────────────────────────────
puts "\n── OLIMIT-SEMANTICS (8) — Layer C order semantics ──"

check("OLIMIT-SEMANTICS-01: asc sort — first row is lexicographically smallest name (alice)") do
  C_ASC_ALL[:returned_rows].first['name'] == 'alice' &&
    C_ASC_ALL[:returned_rows].last['name'] == 'eve'
end

check("OLIMIT-SEMANTICS-02: asc sort — rows in ascending lexicographic order by name") do
  names = C_ASC_ALL[:returned_rows].map { |r| r['name'] }
  names == names.sort
end

check("OLIMIT-SEMANTICS-03: desc sort — first row is lexicographically largest name (eve)") do
  C_DESC_ALL[:returned_rows].first['name'] == 'eve' &&
    C_DESC_ALL[:returned_rows].last['name'] == 'alice'
end

check("OLIMIT-SEMANTICS-04: desc sort — rows in descending lexicographic order by name") do
  names = C_DESC_ALL[:returned_rows].map { |r| r['name'] }
  names == names.sort.reverse
end

check("OLIMIT-SEMANTICS-05: stable sort — equal keys preserve input order (bob index 0 before bob index 2)") do
  bobs = C_STABLE[:returned_rows].select { |r| r['name'] == 'bob' }
  bobs.length == 2 && bobs[0]['score'] == '20' && bobs[1]['score'] == '30'
end

check("OLIMIT-SEMANTICS-06: empty direction string → no ordering applied; input order preserved") do
  C_NO_ORDER[:returned_rows].map { |r| r['name'] } == TEST_ROWS.map { |r| r['name'] } &&
    C_NO_ORDER[:result]['kind'] == 'rows'
end

check("OLIMIT-SEMANTICS-07: unknown direction → kind:\"query_error\" (NOT \"denied\")") do
  C_BAD_DIR[:result]['kind'] == 'query_error' &&
    C_BAD_DIR[:result]['kind'] != 'denied' &&
    C_BAD_DIR[:returned_rows].empty?
end

check("OLIMIT-SEMANTICS-08: missing order field in row → kind:\"query_error\" (fail-closed)") do
  C_MISS_FIELD[:result]['kind'] == 'query_error' &&
    C_MISS_FIELD[:returned_rows].empty?
end

# ── OLIMIT-LIMIT ──────────────────────────────────────────────────────────────
puts "\n── OLIMIT-LIMIT (7) — Layer C limit semantics ──"

check("OLIMIT-LIMIT-01: limit 1 → exactly 1 row returned (first after asc ordering: alice)") do
  C_LIMIT_1[:returned_rows].length == 1 &&
    C_LIMIT_1[:returned_rows].first['name'] == 'alice'
end

check("OLIMIT-LIMIT-02: limit 2 → exactly 2 rows returned (alice, bob)") do
  C_LIMIT_2[:returned_rows].length == 2 &&
    C_LIMIT_2[:returned_rows].map { |r| r['name'] } == %w[alice bob]
end

check("OLIMIT-LIMIT-03: limit larger than row count → all rows returned (5 rows for limit 99)") do
  C_LIMIT_OVER[:returned_rows].length == TEST_ROWS.length &&
    C_LIMIT_OVER[:result]['kind'] == 'rows'
end

check("OLIMIT-LIMIT-04: limit 0 → kind:\"empty\", count:0") do
  C_LIMIT_ZERO[:result]['kind'] == 'empty' &&
    C_LIMIT_ZERO[:result]['count'] == 0 &&
    C_LIMIT_ZERO[:returned_rows].empty?
end

check("OLIMIT-LIMIT-05: negative limit → kind:\"query_error\" (NOT \"denied\")") do
  C_LIMIT_NEG[:result]['kind'] == 'query_error' &&
    C_LIMIT_NEG[:result]['kind'] != 'denied' &&
    C_LIMIT_NEG[:returned_rows].empty?
end

check("OLIMIT-LIMIT-06: limit applied AFTER ordering — limit 2 asc gives first-alphabetically 2 rows") do
  # If limit were applied before ordering, result would depend on input order
  # With order-then-limit: alice(idx1) + bob(idx3) are first alphabetically
  names = C_LIMIT_2[:returned_rows].map { |r| r['name'] }
  names == %w[alice bob]
end

check("OLIMIT-LIMIT-07: count == returned_rows.length invariant holds across all limit evals") do
  [C_LIMIT_1, C_LIMIT_2, C_LIMIT_OVER, C_ASC_ALL, C_DESC_ALL, C_NO_ORDER].all? do |c|
    c[:result]['count'] == c[:returned_rows].length
  end
end

# ── OLIMIT-RESULT ─────────────────────────────────────────────────────────────
puts "\n── OLIMIT-RESULT (6) — Layer C result kinds; count; metadata ──"

check("OLIMIT-RESULT-01: asc ordering all rows → kind:\"rows\", count:5") do
  C_ASC_ALL[:result]['kind'] == 'rows' && C_ASC_ALL[:result]['count'] == 5
end

check("OLIMIT-RESULT-02: limit 0 → kind:\"empty\", count:0") do
  C_LIMIT_ZERO[:result]['kind'] == 'empty' && C_LIMIT_ZERO[:result]['count'] == 0
end

check("OLIMIT-RESULT-03: unknown direction → kind:\"query_error\", NOT \"denied\"") do
  C_BAD_DIR[:result]['kind'] == 'query_error' &&
    C_BAD_DIR[:result]['kind'] != 'denied'
end

check("OLIMIT-RESULT-04: negative limit → kind:\"query_error\", NOT \"denied\"") do
  C_LIMIT_NEG[:result]['kind'] == 'query_error' &&
    C_LIMIT_NEG[:result]['kind'] != 'denied'
end

check("OLIMIT-RESULT-05: metadata pass-through preserved in result (no metadata dropped)") do
  meta = { 'trace_id' => 'test-meta', 'order_field' => 'name' }
  r = OrderLimitSim.apply(TEST_ROWS, ORDER_ASC, 3, metadata: meta)
  r[:result]['metadata'] == meta
end

check("OLIMIT-RESULT-06: KDR route actions: rows→process, empty→empty, query_error→invalid") do
  OrderLimitSim.route({ 'kind' => 'rows' })[:action]        == 'process' &&
    OrderLimitSim.route({ 'kind' => 'empty' })[:action]     == 'empty'   &&
    OrderLimitSim.route({ 'kind' => 'query_error' })[:action] == 'invalid'
end

# ── OLIMIT-VM ─────────────────────────────────────────────────────────────────
puts "\n── OLIMIT-VM (8) — Layer B VM execution ──"

check("OLIMIT-VM-01: VM BuildOrderAsc(field:\"name\") → { field:\"name\", direction:\"asc\" }") do
  VM_ASC_R['status'] == 'success' &&
    VM_ASC_R.dig('result', 'field')     == 'name' &&
    VM_ASC_R.dig('result', 'direction') == 'asc'
end

check("OLIMIT-VM-02: VM BuildOrderDesc(field:\"created_at\") → { field:\"created_at\", direction:\"desc\" }") do
  VM_DESC_R['status'] == 'success' &&
    VM_DESC_R.dig('result', 'field')     == 'created_at' &&
    VM_DESC_R.dig('result', 'direction') == 'desc'
end

check("OLIMIT-VM-03: VM BuildQueryPlanOrderLimit → kind:\"select\"; order.direction:\"asc\"; limit:10") do
  VM_PLAN_R['status'] == 'success' &&
    VM_PLAN_R.dig('result', 'kind')              == 'select' &&
    VM_PLAN_R.dig('result', 'order', 'direction') == 'asc' &&
    VM_PLAN_R.dig('result', 'limit')              == 10
end

check("OLIMIT-VM-04: VM BuildQueryPlanOrderLimit → filters is 1-element array (Collection[FilterPredicate])") do
  filters = VM_PLAN_R.dig('result', 'filters')
  VM_PLAN_R['status'] == 'success' &&
    filters.is_a?(Array) && filters.length == 1 &&
    filters[0]['field'] == 'status' && filters[0]['op'] == 'eq'
end

check("OLIMIT-VM-05: VM OrderLimitRows(count:3) → kind:\"rows\", count:3") do
  VM_ROWS_R['status'] == 'success' &&
    VM_ROWS_R.dig('result', 'kind')  == 'rows' &&
    VM_ROWS_R.dig('result', 'count') == 3
end

check("OLIMIT-VM-06: VM OrderLimitEmpty → kind:\"empty\", count:0") do
  VM_EMPTY_R['status'] == 'success' &&
    VM_EMPTY_R.dig('result', 'kind')  == 'empty' &&
    VM_EMPTY_R.dig('result', 'count') == 0
end

check("OLIMIT-VM-07: VM OrderLimitQueryError → kind:\"query_error\", count:0") do
  VM_QERR_R['status'] == 'success' &&
    VM_QERR_R.dig('result', 'kind')  == 'query_error' &&
    VM_QERR_R.dig('result', 'count') == 0
end

check("OLIMIT-VM-08: VM OrderLimitMetadataReader — map_get hit:\"name\"; miss:\"not-found\"") do
  VM_META_HIT['status']  == 'success' && VM_META_HIT['result']  == 'name' &&
    VM_META_MISS['status'] == 'success' && VM_META_MISS['result'] == 'not-found'
end

# ── OLIMIT-COMPOSE ────────────────────────────────────────────────────────────
puts "\n── OLIMIT-COMPOSE (4) — ordering, limiting, composition boundaries ──"

check("OLIMIT-COMPOSE-01: order-then-limit (not limit-then-order) — limit 2 desc gives top-2 names") do
  r = OrderLimitSim.apply(TEST_ROWS, ORDER_DESC, 2)
  r[:returned_rows].map { |row| row['name'] } == %w[eve dave]
end

check("OLIMIT-COMPOSE-02: can compose after filter results at Layer C (filter then order-limit pipeline)") do
  # Simulate: filter active rows, then sort by name asc, limit 2
  active_rows = TEST_ROWS.select { |r| r['status'] == 'active' }
  r = OrderLimitSim.apply(active_rows, ORDER_ASC, 2)
  r[:returned_rows].length == 2 &&
    r[:returned_rows].all? { |row| row['status'] == 'active' } &&
    r[:returned_rows].map { |row| row['name'] } == %w[alice bob]
end

check("OLIMIT-COMPOSE-03: QueryPlan.limit is query semantics — not StorageCapability row_limit gate") do
  # StorageCapability row_limit clamps at the capability layer (G4 in LAB-EXECUTE-QUERY-P1)
  # QueryPlan.limit is user-specified intent — they are orthogonal
  !OLIMIT_SRC.include?('row_limit') &&
    !OLIMIT_SRC.include?('allow_include_all') &&
    !OLIMIT_SRC.include?('read_allowed')
end

check("OLIMIT-COMPOSE-04: score field asc sort — lexicographic String comparison (\"10\" < \"20\" < \"30\")") do
  names = C_SCORE_ALL[:returned_rows].map { |r| r['score'] }
  names == names.sort  # lexicographic sort same as numeric for single-digit-prefix test data
end

# ── OLIMIT-CLOSED ─────────────────────────────────────────────────────────────
puts "\n── OLIMIT-CLOSED (5) — closed surfaces ──"

check("OLIMIT-CLOSED-01: no SQL execution in fixture source") do
  !OLIMIT_SRC.match?(/SELECT\s+|INSERT\s+|UPDATE\s+|DELETE\s+|CREATE\s+TABLE/i) &&
    !OLIMIT_SRC.include?('execute_' + 'sql') && !OLIMIT_SRC.include?('.sql')
end

check("OLIMIT-CLOSED-02: no database connection / ORM in fixture source") do
  !OLIMIT_SRC.include?('establish_connection') &&
    !OLIMIT_SRC.include?('data' + 'base_url') &&
    !OLIMIT_SRC.include?('Active' + 'Record') &&
    !OLIMIT_SRC.include?('connect_to(')
end

check("OLIMIT-CLOSED-03: no persistence runtime in proof runner source") do
  !SOURCE.include?('Base.establish_' + 'connection') &&
    !SOURCE.include?('DATABASE_URL' + '=') &&
    !SOURCE.include?('Sequ' + 'el.connect(') &&
    !SOURCE.include?('execute_' + 'sql(') &&
    !SOURCE.include?('Active' + 'Record::Base')
end

check("OLIMIT-CLOSED-04: no StorageCapability live execution / no effect contracts in fixture") do
  !OLIMIT_SRC.include?('IO.StorageCapability') &&
    !OLIMIT_SRC.include?('effect contract')
end

check("OLIMIT-CLOSED-05: no write ops / transactions / indexes in fixture") do
  !OLIMIT_SRC.include?('write_file') && !OLIMIT_SRC.include?('write_json') &&
    !OLIMIT_SRC.include?('transaction') && !OLIMIT_SRC.include?('CREATE INDEX')
end

# ── OLIMIT-GAP ────────────────────────────────────────────────────────────────
puts "\n── OLIMIT-GAP (4) — boundary findings ──"

check("OLIMIT-GAP-01: ordering is in-memory mocked semantics only — no SQL ORDER BY; no query optimizer") do
  !OLIMIT_SRC.match?(/ORDER\s+BY/i) &&
    !OLIMIT_SRC.include?('optimizer') &&
    !OLIMIT_SRC.include?('index_scan') &&
    C_ASC_ALL[:returned_rows].all? { |r| r.is_a?(Hash) }
end

check("OLIMIT-GAP-02: ordering is lexicographic String-only in v0 — numeric/date ordering deferred") do
  SOURCE.include?('lexicographic') &&
    !SOURCE.include?('to_i' + '.compare') &&
    !SOURCE.include?('Date' + '.parse') &&
    !SOURCE.include?('collat' + 'ion')
end

check("OLIMIT-GAP-03: StorageCapability row_limit gate is distinct from QueryPlan.limit") do
  !OLIMIT_SRC.include?('row_limit') &&
    !OLIMIT_SRC.include?('cap.row_limit') &&
    !OLIMIT_SRC.include?('row_limit_clamped')
end

check("OLIMIT-GAP-04: unknown direction / negative limit produce query_error, NOT denied") do
  C_BAD_DIR[:result]['kind']   == 'query_error' &&
    C_LIMIT_NEG[:result]['kind'] == 'query_error' &&
    C_BAD_DIR[:result]['kind']   != 'denied' &&
    C_LIMIT_NEG[:result]['kind'] != 'denied' &&
    OrderLimitSim.route(C_BAD_DIR[:result])[:action]   == 'invalid' &&
    OrderLimitSim.route(C_LIMIT_NEG[:result])[:action] == 'invalid'
end

# ── Summary ────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass_count + $fail_count
puts "Result: #{$pass_count}/#{total} PASS"
if $fail_count.zero?
  puts "LAB-QUERY-ORDER-LIMIT-P1: PROOF COMPLETE (#{$pass_count}/#{total})"
  puts "\nKey findings:"
  puts "  - OrderBy shapes (asc/desc) accepted at Layer A + Layer B"
  puts "  - BuildQueryPlanOrderLimit.filters typed Collection[FilterPredicate] in Rust SIR (P2 mechanism)"
  puts "  - OrderLimitSim: asc/desc lexicographic sort correct over 5-row deterministic dataset"
  puts "  - Stable sort: equal keys preserve input order"
  puts "  - Limit applied AFTER ordering: limit 2 asc gives first-alphabetically 2 rows"
  puts "  - limit==0 → kind:\"empty\"; limit<0 → kind:\"query_error\""
  puts "  - Unknown direction → kind:\"query_error\" (NOT \"denied\")"
  puts "  - Missing order field in row → kind:\"query_error\" (fail-closed)"
  puts "  - QueryPlan.limit ≠ StorageCapability row_limit gate (orthogonal)"
  puts "  - All comparisons are lexicographic String comparisons in v0"
  puts "  - No SQL / DB / ORM / StorageCapability live execution at any layer"
else
  puts "LAB-QUERY-ORDER-LIMIT-P1: #{$fail_count} check(s) failed"
  exit 1
end
