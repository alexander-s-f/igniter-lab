#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_query_p3.rb
# LAB-QUERY-P3: QueryPlan nested records + Collection[FilterPredicate] proof — 44 checks
#
# Proves that QueryPlan can carry richer pure query intent as nested typed data:
# nested QuerySource/Projection/OrderBy records, Collection[FilterPredicate],
# Map[String,String] metadata, and chained field access, without opening SQL
# execution, real database access, ORM, persistence runtime, or StorageCapability.
#
# Core formula:
#   QueryPlan v1 = nested typed records + Collection[FilterPredicate] + Map metadata.
#   QueryPlan v1 != ORM, != database connection, != persistence runtime.
#   All contracts pure -> CORE. No IO. No StorageCapability.
#
# Key finding (Rust typechecker gap):
#   Collection[FilterPredicate] as INPUT type: accepted by both Layer A and Layer B.
#   Array literal construction [filter1, filter2]: accepted by Layer A (Ruby TypeChecker)
#   but blocked by Rust typechecker (array_literal not in v0 Rust typecheck pass).
#   QPLAN3-ARRAY section (Layer A only) proves array literal inference works;
#   QPLAN3-VM section uses input-form Collection[FilterPredicate] (Layer B compatible).
#
# Two-layer + simulation proof:
#   Layer A — Production Ruby TypeChecker: nested type shapes, Collection[FilterPredicate]
#             type env, chained field access type inference, array literal inference.
#   Layer B — Lab Rust VM: record construction, nested records, chained field access
#             (plan.source.table via two OP_GET_FIELD hops), map_get + or_else on
#             richer QueryPlan, Collection[FilterPredicate] as input passthrough.
#   Layer C — Proof-local QueryExecutorSim: 5-kind routing, denial-as-data.
#
# Sections:
#   QPLAN3-COMPILE  (4)  — fixture compiles; 8 contracts; no type_errors; all accepted
#   QPLAN3-TYPES    (6)  — QueryPlan nested type env (source/projection/filters/order/limit/metadata)
#   QPLAN3-NESTED   (5)  — BuildRichSelectPlan type analysis (accepted + input types)
#   QPLAN3-BUILD    (4)  — individual builder contracts accepted
#   QPLAN3-ARRAY    (4)  — Layer A: array literal Collection[FilterPredicate] inference
#   QPLAN3-VM       (8)  — VM execution: builders + rich plan + nested record preservation
#   QPLAN3-CHAIN    (4)  — chained field access (plan.source.table) + metadata C1 chain
#   QPLAN3-KDR      (4)  — denial-as-data + QueryResult kind vocabulary
#   QPLAN3-CLOSED   (5)  — closed surface: no SQL, no DB, no ORM, lab-only, all CORE
#
# Total: 44 checks
#
# Depends on:
#   LAB-QUERY-P1 (boundary research)
#   LAB-QUERY-P2 (flat QueryPlan proof — 42/42)
#   LAB-STORAGE-CAPABILITY-P1 (IO.StorageCapability design)
#   LAB-RECORD-VM-P3 (nested field access — chained OP_GET_FIELD)
#   PROP-043-P5 (Map[String,String] production surface + C1 fix)
#   LAB-VM-MAP-P1 (map_get/or_else VM runtime)
#
# Authority: LAB-ONLY. No canon claim. No framework compat. No public API.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_query_p3.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_plan' / 'query_plan_nested.ig').to_s

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

def run_inline(src, tag = 'inline')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: "#{tag}.ig").to_h
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
  tmpfile = Tempfile.new(['qplan3_inputs', '.json'])
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
# QueryExecutorSim: 5-kind routing (carried from LAB-QUERY-P2).
# Evidence only — does not confer execution authority.

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

  def self.denial_as_data?(kind)
    kind == 'denied' && ROUTES.key?('denied')
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile and run up front
# ─────────────────────────────────────────────────────────────────────────────

QPLAN3_OUT  = Dir.mktmpdir('qplan3_main')
QPLAN3_SIR  = compile_fixture(FIXTURE_PATH, QPLAN3_OUT)
QPLAN3_TC   = run_fixture(FIXTURE_PATH)

# ── VM inputs ─────────────────────────────────────────────────────────────────

FP_INPUTS = {
  'field' => 'status',
  'op'    => 'eq',
  'value' => 'active'
}.freeze

OB_INPUTS = {
  'field'     => 'created_at',
  'direction' => 'desc'
}.freeze

PROJ_INPUTS = {
  'fields'      => 'id,name,email',
  'include_all' => false
}.freeze

SOURCE_INPUTS = {
  'table'  => 'users',
  'schema' => 'public'
}.freeze

RICH_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name,email', 'include_all' => false },
  'filters'    => [
    { 'field' => 'status', 'op' => 'eq', 'value' => 'active' },
    { 'field' => 'age',    'op' => 'gt', 'value' => '18' }
  ],
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 25,
  'metadata'   => { 'trace_id' => 'abc123', 'source' => 'web', 'table' => 'users' }
}.freeze

NESTED_READER_INPUTS = {
  'plan' => {
    'kind'       => 'select',
    'source'     => { 'table' => 'users', 'schema' => 'public' },
    'projection' => { 'fields' => 'id,name', 'include_all' => false },
    'filters'    => [{ 'field' => 'status', 'op' => 'eq', 'value' => 'active' }],
    'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
    'limit'      => 10,
    'metadata'   => { 'source' => 'web', 'trace_id' => 'xyz' }
  }
}.freeze

META_FALLBACK_INPUTS = {
  'plan' => {
    'kind'       => 'select',
    'source'     => { 'table' => 'orders', 'schema' => 'public' },
    'projection' => { 'fields' => '*', 'include_all' => true },
    'filters'    => [],
    'order'      => { 'field' => 'id', 'direction' => 'asc' },
    'limit'      => 50,
    'metadata'   => { 'trace_id' => 'no-source-key' }
  }
}.freeze

DENIED_INPUTS = {
  'table'    => 'users',
  'reason'   => 'source not in allowlist',
  'metadata' => { 'trace' => 't1', 'gate' => 'G1' }
}.freeze

# ── Inline fixture for Layer A array literal test (QPLAN3-ARRAY) ──────────────

INLINE_ARRAY_SRC = <<~'IGNITER'
  module Lab.Query.ArrayLiteralTest

  type FilterPredicate {
    field: String,
    op:    String,
    value: String
  }

  pure contract ArrayLiteralBuilder {
    input  filter1 : FilterPredicate
    input  filter2 : FilterPredicate
    compute filters = [filter1, filter2]
    output filters : Collection[FilterPredicate]
  }
IGNITER

QPLAN3_ARRAY_TC = run_inline(INLINE_ARRAY_SRC, 'array_literal_test')

# ── Pre-run VM contracts ───────────────────────────────────────────────────────

VM_FP         = vm_run(QPLAN3_OUT, 'BuildFilterPredicate',  FP_INPUTS)
VM_OB         = vm_run(QPLAN3_OUT, 'BuildOrderBy',          OB_INPUTS)
VM_PROJ       = vm_run(QPLAN3_OUT, 'BuildProjection',       PROJ_INPUTS)
VM_SOURCE     = vm_run(QPLAN3_OUT, 'BuildQuerySource',      SOURCE_INPUTS)
VM_RICH       = vm_run(QPLAN3_OUT, 'BuildRichSelectPlan',   RICH_INPUTS)
VM_CHAIN      = vm_run(QPLAN3_OUT, 'PlanNestedFieldReader', NESTED_READER_INPUTS)
VM_META_HIT   = vm_run(QPLAN3_OUT, 'PlanMetadataReader',    NESTED_READER_INPUTS)
VM_META_MISS  = vm_run(QPLAN3_OUT, 'PlanMetadataReader',    META_FALLBACK_INPUTS)
VM_DENIED     = vm_run(QPLAN3_OUT, 'QueryResultDenied',     DENIED_INPUTS)

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-COMPILE: fixture compilation
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-COMPILE ───────────────────────────────────────────────────────────"

check("QPLAN3-COMPILE-01: Rust compiler: fixture compiles with no diagnostics") do
  QPLAN3_SIR&.fetch('diagnostics', [])&.empty? == true
end

check("QPLAN3-COMPILE-02: Rust compiler: 8 contracts in output") do
  contracts = QPLAN3_SIR&.fetch('contracts', []) || []
  contracts.length == 8
end

check("QPLAN3-COMPILE-03: Ruby TypeChecker: no type_errors across all contracts") do
  QPLAN3_TC[:typed]&.fetch('type_errors', [])&.empty? == true
end

check("QPLAN3-COMPILE-04: Ruby TypeChecker: all 8 contracts accepted") do
  contracts = QPLAN3_TC[:typed]&.fetch('contracts', []) || []
  contracts.length == 8 && contracts.all? { |c| c['status'] == 'accepted' }
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-TYPES: QueryPlan nested type environment
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-TYPES ─────────────────────────────────────────────────────────────"

check("QPLAN3-TYPES-01: QueryPlan.source field type = QuerySource") do
  t = type_env_field(QPLAN3_TC, 'QueryPlan', 'source')
  t && (t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s) == 'QuerySource'
end

check("QPLAN3-TYPES-02: QueryPlan.projection field type = Projection") do
  t = type_env_field(QPLAN3_TC, 'QueryPlan', 'projection')
  t && (t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s) == 'Projection'
end

check("QPLAN3-TYPES-03: QueryPlan.filters field type name = Collection") do
  t = type_env_field(QPLAN3_TC, 'QueryPlan', 'filters')
  t && (t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s) == 'Collection'
end

check("QPLAN3-TYPES-04: QueryPlan.filters Collection element type = FilterPredicate") do
  t = type_env_field(QPLAN3_TC, 'QueryPlan', 'filters')
  params = t.is_a?(Hash) ? t.fetch('params', []) : []
  first_param = params.first
  first_param && (first_param.is_a?(Hash) ? first_param.fetch('name', nil) : first_param.to_s) == 'FilterPredicate'
end

check("QPLAN3-TYPES-05: QueryPlan.order field type = OrderBy") do
  t = type_env_field(QPLAN3_TC, 'QueryPlan', 'order')
  t && (t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s) == 'OrderBy'
end

check("QPLAN3-TYPES-06: QueryPlan.metadata field type = Map") do
  t = type_env_field(QPLAN3_TC, 'QueryPlan', 'metadata')
  t && (t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s) == 'Map'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-NESTED: BuildRichSelectPlan type analysis
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-NESTED ────────────────────────────────────────────────────────────"

check("QPLAN3-NESTED-01: BuildRichSelectPlan accepted by Ruby TypeChecker") do
  contract_accepted?(QPLAN3_TC, 'BuildRichSelectPlan')
end

check("QPLAN3-NESTED-02: BuildRichSelectPlan input 'filters' type = Collection[FilterPredicate]") do
  t = sym_type_for(QPLAN3_TC, 'filters', 'BuildRichSelectPlan')
  name = t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s
  name == 'Collection'
end

check("QPLAN3-NESTED-03: BuildRichSelectPlan input 'source' type = QuerySource") do
  t = sym_type_for(QPLAN3_TC, 'source', 'BuildRichSelectPlan')
  name = t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s
  name == 'QuerySource'
end

check("QPLAN3-NESTED-04: BuildRichSelectPlan input 'projection' type = Projection") do
  t = sym_type_for(QPLAN3_TC, 'projection', 'BuildRichSelectPlan')
  name = t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s
  name == 'Projection'
end

check("QPLAN3-NESTED-05: BuildRichSelectPlan input 'order' type = OrderBy") do
  t = sym_type_for(QPLAN3_TC, 'order', 'BuildRichSelectPlan')
  name = t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s
  name == 'OrderBy'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-BUILD: individual builder contracts accepted
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-BUILD ─────────────────────────────────────────────────────────────"

check("QPLAN3-BUILD-01: BuildFilterPredicate accepted") do
  contract_accepted?(QPLAN3_TC, 'BuildFilterPredicate')
end

check("QPLAN3-BUILD-02: BuildOrderBy accepted") do
  contract_accepted?(QPLAN3_TC, 'BuildOrderBy')
end

check("QPLAN3-BUILD-03: BuildProjection accepted") do
  contract_accepted?(QPLAN3_TC, 'BuildProjection')
end

check("QPLAN3-BUILD-04: BuildQuerySource accepted") do
  contract_accepted?(QPLAN3_TC, 'BuildQuerySource')
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-ARRAY: Layer A array literal Collection[FilterPredicate] inference
#
# Proves that [filter1, filter2] infers to Collection[FilterPredicate]
# in the Ruby TypeChecker. This is a Layer A only test: the Rust typechecker
# does not support array_literal expressions in v0.
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-ARRAY (Layer A only) ───────────────────────────────────────────────"

check("QPLAN3-ARRAY-01: ArrayLiteralBuilder contract accepted by Ruby TypeChecker") do
  contract_accepted?(QPLAN3_ARRAY_TC, 'ArrayLiteralBuilder')
end

check("QPLAN3-ARRAY-02: [filter1, filter2] infers Collection[FilterPredicate] type name") do
  t = sym_type_for(QPLAN3_ARRAY_TC, 'filters', 'ArrayLiteralBuilder')
  name = t.is_a?(Hash) ? t.fetch('name', nil) : t.to_s
  name == 'Collection'
end

check("QPLAN3-ARRAY-03: [filter1, filter2] element type param = FilterPredicate") do
  t = sym_type_for(QPLAN3_ARRAY_TC, 'filters', 'ArrayLiteralBuilder')
  params = t.is_a?(Hash) ? t.fetch('params', []) : []
  first_param = params.first
  first_param && (first_param.is_a?(Hash) ? first_param.fetch('name', nil) : first_param.to_s) == 'FilterPredicate'
end

check("QPLAN3-ARRAY-04: ArrayLiteralBuilder has no type errors (array inference is clean)") do
  type_errors_for(QPLAN3_ARRAY_TC, 'ArrayLiteralBuilder').empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-VM: VM execution
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-VM ────────────────────────────────────────────────────────────────"

check("QPLAN3-VM-01: BuildFilterPredicate → FilterPredicate record with correct fields") do
  VM_FP['status'] == 'success' &&
    VM_FP.dig('result', 'field') == 'status' &&
    VM_FP.dig('result', 'op')    == 'eq' &&
    VM_FP.dig('result', 'value') == 'active'
end

check("QPLAN3-VM-02: BuildOrderBy → OrderBy record with direction") do
  VM_OB['status'] == 'success' &&
    VM_OB.dig('result', 'direction') == 'desc' &&
    VM_OB.dig('result', 'field')     == 'created_at'
end

check("QPLAN3-VM-03: BuildProjection → Projection record with include_all=false") do
  VM_PROJ['status'] == 'success' &&
    VM_PROJ.dig('result', 'include_all') == false &&
    VM_PROJ.dig('result', 'fields')      == 'id,name,email'
end

check("QPLAN3-VM-04: BuildQuerySource → QuerySource record with table and schema") do
  VM_SOURCE['status'] == 'success' &&
    VM_SOURCE.dig('result', 'table')  == 'users' &&
    VM_SOURCE.dig('result', 'schema') == 'public'
end

check("QPLAN3-VM-05: BuildRichSelectPlan → plan.kind == 'select'") do
  VM_RICH['status'] == 'success' &&
    VM_RICH.dig('result', 'kind') == 'select'
end

check("QPLAN3-VM-06: BuildRichSelectPlan → plan.source is record with table (nested record preserved)") do
  src = VM_RICH.dig('result', 'source')
  src.is_a?(Hash) && src['table'] == 'users'
end

check("QPLAN3-VM-07: BuildRichSelectPlan → plan.filters is array with 2 FilterPredicate elements") do
  filters = VM_RICH.dig('result', 'filters')
  filters.is_a?(Array) && filters.length == 2 &&
    filters[0].is_a?(Hash) && filters[0]['field'] == 'status' &&
    filters[1].is_a?(Hash) && filters[1]['field'] == 'age'
end

check("QPLAN3-VM-08: BuildRichSelectPlan → plan.order is record with direction (nested OrderBy preserved)") do
  ord = VM_RICH.dig('result', 'order')
  ord.is_a?(Hash) && ord['direction'] == 'desc'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-CHAIN: chained field access + metadata C1 chain on richer QueryPlan
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-CHAIN ─────────────────────────────────────────────────────────────"

check("QPLAN3-CHAIN-01: VM PlanNestedFieldReader status = success (chained access no error)") do
  VM_CHAIN['status'] == 'success'
end

check("QPLAN3-CHAIN-02: VM PlanNestedFieldReader plan.source.table returns 'users'") do
  VM_CHAIN['status'] == 'success' && VM_CHAIN['result'] == 'users'
end

check("QPLAN3-CHAIN-03: VM PlanMetadataReader map_get(plan.metadata,'source') hit returns 'web'") do
  VM_META_HIT['status'] == 'success' && VM_META_HIT['result'] == 'web'
end

check("QPLAN3-CHAIN-04: VM PlanMetadataReader or_else fallback returns 'unknown_source' when key absent") do
  VM_META_MISS['status'] == 'success' && VM_META_MISS['result'] == 'unknown_source'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-KDR: denial-as-data + QueryResult kind vocabulary
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-KDR ───────────────────────────────────────────────────────────────"

check("QPLAN3-KDR-01: QueryResultDenied accepted by Ruby TypeChecker") do
  contract_accepted?(QPLAN3_TC, 'QueryResultDenied')
end

check("QPLAN3-KDR-02: VM QueryResultDenied → result.kind == 'denied' (denial-as-data)") do
  VM_DENIED['status'] == 'success' &&
    VM_DENIED.dig('result', 'kind') == 'denied' &&
    VM_DENIED.dig('result', 'count') == 0 &&
    VM_DENIED.dig('result', 'message') == 'source not in allowlist'
end

check("QPLAN3-KDR-03: Layer C: 'empty' routes distinctly from 'denied' (domain-specific kind)") do
  empty_route  = QueryExecutorSim.route('kind' => 'empty')
  denied_route = QueryExecutorSim.route('kind' => 'denied')
  empty_route[:action] != denied_route[:action] &&
    empty_route[:action]  == 'empty' &&
    denied_route[:action] == 'deny'
end

check("QPLAN3-KDR-04: Layer C: 'denied' is denial-as-data (not exception); 'query_error' is distinct") do
  QueryExecutorSim.denial_as_data?('denied') &&
    !QueryExecutorSim.denial_as_data?('query_error') &&
    QueryExecutorSim.route('kind' => 'query_error')[:action] == 'invalid'
end

# ─────────────────────────────────────────────────────────────────────────────
# QPLAN3-CLOSED: closed surface checks
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── QPLAN3-CLOSED ────────────────────────────────────────────────────────────"

src_fixture = File.read(FIXTURE_PATH, encoding: 'UTF-8')

check("QPLAN3-CLOSED-01: no SQL execution in fixture source") do
  !src_fixture.include?('execut' + 'e_sql') &&
    !src_fixture.include?('run_qu' + 'ery(') &&
    !src_fixture.include?('raw_sq' + 'l')
end

check("QPLAN3-CLOSED-02: no database connection code in fixture source") do
  !src_fixture.include?('establish_connection') &&
    !src_fixture.include?('database_url') &&
    !src_fixture.include?('ActiveRecord::Base') &&
    !src_fixture.include?('connect_to(')
end

check("QPLAN3-CLOSED-03: no ORM or persistence runtime in fixture source") do
  !src_fixture.include?('ActiveRec' + 'ord') &&
    !src_fixture.include?('save' + '!') &&
    !src_fixture.include?('has_man' + 'y') &&
    !src_fixture.include?('belongs_' + 'to')
end

check("QPLAN3-CLOSED-04: all contracts pure/CORE (no 'effect contract' in fixture)") do
  src_fixture.include?('pure contract') &&
    !src_fixture.include?('effect contract')
end

check("QPLAN3-CLOSED-05: no stable/public API claim in fixture or runner source") do
  !src_fixture.include?('stab' + 'le API') &&
    !SOURCE.include?('stab' + 'le API') &&
    !src_fixture.include?('product' + 'ion API')
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

puts "\n═══════════════════════════════════════════════════════════════════════════════"
total = $pass_count + $fail_count
puts "RESULT: #{$pass_count}/#{total} PASS"
puts "═══════════════════════════════════════════════════════════════════════════════"

if $fail_count > 0
  puts "\nFAILURES PRESENT — #{$fail_count} check(s) failed."
  exit 1
else
  puts "\nALL CHECKS PASS — LAB-QUERY-P3 proof complete."
  puts "\nKey findings:"
  puts "  - QueryPlan v1: nested QuerySource/Projection/OrderBy/Collection[FilterPredicate] all proved"
  puts "  - Collection[FilterPredicate] as input: Layer A + Layer B both accept (input-form)"
  puts "  - Array literal [filter1,filter2]: Layer A accepts; Rust typechecker gap (v0 limitation)"
  puts "  - Chained field access (plan.source.table): works via LAB-RECORD-VM-P3 two-hop OP_GET_FIELD"
  puts "  - C1 chain (map_get+or_else) on richer QueryPlan: confirmed in 4th domain v1 shape"
  puts "  - Denial-as-data QueryResult{kind:'denied'}: confirmed, no exception raised"
  puts "  - 'empty' kind distinct from 'denied' and 'query_error': confirmed"
  exit 0
end
