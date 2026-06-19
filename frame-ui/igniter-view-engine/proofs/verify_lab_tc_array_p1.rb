#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_tc_array_p1.rb
# LAB-TC-ARRAY-P1: Rust TypeChecker array-literal-in-Collection-context proof
#
# Closes LAB-QUERY-P3 boundary finding B1: the Rust TypeChecker rejected direct
# array literal construction with
#   OOF-TY0 "Unsupported expression kind: array_literal"
# forcing `filters: Collection[FilterPredicate]` to be passed as an external
# input. This proof shows the Rust pipeline (compiler + VM) now accepts inline
# array literal construction in a typed Collection[T] output context.
#
# Behavior is CONTEXTUAL (mirrors the RecordLiteral nominal upgrade, LAB-RACK-P13):
#   - array literal in a declared `output x : Collection[T]` position is typed by
#     checking each element against the element type T, then upgrading the node
#     to Collection[T];
#   - missing/extra/wrong-typed record fields and mixed element shapes fail closed
#     with OOF-TY0;
#   - an empty array is accepted ONLY with the contextual Collection[T] type;
#   - a free-standing array literal with no Collection output hint resolves to
#     Unknown (no fabricated type) and no longer emits the OOF-TY0 gap error.
#
# Layers:
#   Layer B — Lab Rust compiler + VM (the gap surface). Primary evidence:
#             diagnostics, SIR type_tag metadata, VM round-trip of the collection.
#   Layer A — Production Ruby TypeChecker. Regression anchor: `[f1, f2]` still
#             infers Collection[FilterPredicate] (parity with LAB-QUERY-P3).
#
# Sections:
#   TCARR-COMPILE (4) — main fixture compiles clean in both layers; 4 contracts
#   TCARR-TYPES   (4) — SIR type metadata: Collection[FilterPredicate] survives
#   TCARR-VM      (4) — VM execution: inline/empty/refs/full-plan round-trip
#   TCARR-NEG     (5) — fail-closed: missing/extra/wrong-type/mixed/scalar-element
#   TCARR-EMPTY   (2) — empty-with-context accepted; free-standing gap closed
#   TCARR-LAYERA  (3) — Ruby TypeChecker parity: [f1,f2] -> Collection[FilterPredicate]
#   TCARR-CLOSED  (5) — closed surface: no SQL/DB/ORM, pure CORE, no new grammar
#
# Total: 27 checks
#
# Depends on: LAB-QUERY-P3, PROP-043-P5, LAB-MAP-RUST-P1, LAB-RECORD-VM-P3,
#             LAB-STORAGE-CAPABILITY-P2
#
# Authority: LAB-ONLY. No canon claim. No framework compat. No public API.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_tc_array_p1.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_plan' / 'query_plan_array_filters.ig').to_s

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

# ── Layer B: Lab Rust compiler helpers ─────────────────────────────────────────

# Compile a source path, return { report:, out_dir:, contracts: {name => sir_hash} }.
def compile_path(path)
  out_dir = Dir.mktmpdir('tcarr')
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

# Compile an inline source string (written to a temp .ig file).
def compile_inline(src, tag = 'tcarr_inline')
  file = Tempfile.new([tag, '.ig'])
  file.write(src)
  file.close
  res = compile_path(file.path)
  file.unlink rescue nil
  res
end

def diagnostics(res)
  res[:report]&.fetch('diagnostics', []) || []
end

def diag_rules(res)
  diagnostics(res).map { |d| d['rule'] }
end

def status(res)
  res[:report]&.fetch('status', nil)
end

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
  tmpfile = Tempfile.new(['tcarr_inputs', '.json'])
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

# ── Layer A: Ruby TypeChecker helpers ─────────────────────────────────────────

def run_inline_ruby(src, tag = 'inline')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: "#{tag}.ig").to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { parsed: parsed, classified: classified, typed: typed }
rescue => e
  { error: e.message }
end

def ruby_sym_type(result, sym_name, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  s = c&.fetch('symbols', [])&.find { |s| s['name'] == sym_name }
  s&.fetch('type', nil)
end

def ruby_contract_accepted?(result, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  c&.fetch('status', nil) == 'accepted'
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile main fixture up front (Layer B) + Layer A
# ─────────────────────────────────────────────────────────────────────────────

MAIN = compile_path(FIXTURE_PATH)

MAIN_RUBY_SRC = File.read(FIXTURE_PATH, encoding: 'UTF-8')
MAIN_RUBY     = run_inline_ruby(MAIN_RUBY_SRC, 'array_filters')

# ── VM inputs ─────────────────────────────────────────────────────────────────

REFS_INPUTS = {
  'f1' => { 'field' => 'status', 'op' => 'eq', 'value' => 'active' },
  'f2' => { 'field' => 'role',   'op' => 'eq', 'value' => 'admin'  }
}.freeze

PLAN_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name', 'include_all' => false },
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 25,
  'metadata'   => { 'trace_id' => 'abc123' }
}.freeze

VM_INLINE = (MAIN[:out_dir] && status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'InlineFilterCollection', {}) : {}
VM_EMPTY  = (MAIN[:out_dir] && status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'EmptyFilterCollection', {}) : {}
VM_REFS   = (MAIN[:out_dir] && status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'InlineFilterRefs', REFS_INPUTS) : {}
VM_PLAN   = (MAIN[:out_dir] && status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'BuildInlineSelectPlan', PLAN_INPUTS) : {}

# ── Negative-case inline sources (must FAIL closed) ────────────────────────────

NEG_HEAD = <<~'IG'
  module Lab.Neg
  type FilterPredicate { field: String, op: String, value: String }
  type OrderBy { field: String, direction: String }
IG

NEG_MISSING = NEG_HEAD + <<~'IG'
  pure contract NegMissing {
    compute filters = [ { field: "status", op: "eq" } ]
    output filters : Collection[FilterPredicate]
  }
IG

NEG_EXTRA = NEG_HEAD + <<~'IG'
  pure contract NegExtra {
    compute filters = [ { field: "s", op: "eq", value: "a", bogus: "z" } ]
    output filters : Collection[FilterPredicate]
  }
IG

NEG_WRONGTYPE = NEG_HEAD + <<~'IG'
  pure contract NegWrongType {
    input n : Integer
    compute filters = [ { field: "s", op: "eq", value: n } ]
    output filters : Collection[FilterPredicate]
  }
IG

NEG_MIXED = NEG_HEAD + <<~'IG'
  pure contract NegMixed {
    input ob : OrderBy
    compute filters = [ { field: "s", op: "eq", value: "a" }, ob ]
    output filters : Collection[FilterPredicate]
  }
IG

NEG_SCALAR_ELEM = <<~'IG'
  module Lab.NegScalar
  pure contract NegScalar {
    compute names = [ { field: "x" } ]
    output names : Collection[String]
  }
IG

NEG_MISSING_RES = compile_inline(NEG_MISSING, 'neg_missing')
NEG_EXTRA_RES   = compile_inline(NEG_EXTRA, 'neg_extra')
NEG_WRONG_RES   = compile_inline(NEG_WRONGTYPE, 'neg_wrong')
NEG_MIXED_RES   = compile_inline(NEG_MIXED, 'neg_mixed')
NEG_SCALAR_RES  = compile_inline(NEG_SCALAR_ELEM, 'neg_scalar')

# ── Free-standing array literal (no Collection output) — gap-closed source ─────

FREE_SRC = <<~'IG'
  module Lab.Free
  type FilterPredicate { field: String, op: String, value: String }
  pure contract FreeStanding {
    input f1 : FilterPredicate
    compute filters = [f1]
    compute n = 1
    output n : Integer
  }
IG

FREE_RES = compile_inline(FREE_SRC, 'free_standing')

# ── Layer A parity inline (refs) ───────────────────────────────────────────────

LAYERA_SRC = <<~'IG'
  module Lab.Query.ArrayLiteralTest
  type FilterPredicate { field: String, op: String, value: String }
  pure contract ArrayLiteralBuilder {
    input  filter1 : FilterPredicate
    input  filter2 : FilterPredicate
    compute filters = [filter1, filter2]
    output filters : Collection[FilterPredicate]
  }
IG

LAYERA = run_inline_ruby(LAYERA_SRC, 'array_literal_test')

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-COMPILE
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-COMPILE ────────────────────────────────────────────────────────────"

check("TCARR-COMPILE-01: Rust compiler: main fixture compiles, status ok") do
  status(MAIN) == 'ok'
end

check("TCARR-COMPILE-02: Rust compiler: zero diagnostics on main fixture") do
  diagnostics(MAIN).empty?
end

check("TCARR-COMPILE-03: Rust compiler: 4 contracts emitted") do
  (MAIN[:report]&.fetch('contracts', []) || []).length == 4
end

check("TCARR-COMPILE-04: Ruby TypeChecker: main fixture has no type_errors") do
  (MAIN_RUBY[:typed]&.fetch('type_errors', []) || []).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-TYPES — Collection[FilterPredicate] survives into SIR type metadata
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-TYPES ──────────────────────────────────────────────────────────────"

check("TCARR-TYPES-01: InlineFilterCollection compute 'filters' type_tag = Collection[FilterPredicate]") do
  compute_type_tag(MAIN, 'InlineFilterCollection', 'filters') == 'Collection[FilterPredicate]'
end

check("TCARR-TYPES-02: InlineFilterCollection output port 'filters' type_tag = Collection[FilterPredicate]") do
  output_type_tag(MAIN, 'InlineFilterCollection', 'filters') == 'Collection[FilterPredicate]'
end

check("TCARR-TYPES-03: InlineFilterRefs compute 'filters' type_tag = Collection[FilterPredicate]") do
  compute_type_tag(MAIN, 'InlineFilterRefs', 'filters') == 'Collection[FilterPredicate]'
end

check("TCARR-TYPES-04: EmptyFilterCollection compute 'filters' type_tag = Collection[FilterPredicate] (contextual)") do
  compute_type_tag(MAIN, 'EmptyFilterCollection', 'filters') == 'Collection[FilterPredicate]'
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-VM — VM round-trips the constructed collection (Layer B execution)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-VM ─────────────────────────────────────────────────────────────────"

check("TCARR-VM-01: InlineFilterCollection → 2 FilterPredicate records with correct fields") do
  r = VM_INLINE['result']
  VM_INLINE['status'] == 'success' && r.is_a?(Array) && r.length == 2 &&
    r[0]['field'] == 'status' && r[0]['op'] == 'eq' && r[0]['value'] == 'active' &&
    r[1]['field'] == 'role'   && r[1]['value'] == 'admin'
end

check("TCARR-VM-02: EmptyFilterCollection → empty array") do
  VM_EMPTY['status'] == 'success' && VM_EMPTY['result'] == []
end

check("TCARR-VM-03: InlineFilterRefs → 2 records round-tripped from inputs") do
  r = VM_REFS['result']
  VM_REFS['status'] == 'success' && r.is_a?(Array) && r.length == 2 &&
    r[0]['field'] == 'status' && r[1]['field'] == 'role'
end

check("TCARR-VM-04: BuildInlineSelectPlan → plan.filters is array of 2 (inline construction)") do
  f = VM_PLAN.dig('result', 'filters')
  VM_PLAN['status'] == 'success' &&
    VM_PLAN.dig('result', 'kind') == 'select' &&
    f.is_a?(Array) && f.length == 2 &&
    f[0]['field'] == 'status' && f[1]['field'] == 'age'
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-NEG — fail closed
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-NEG ────────────────────────────────────────────────────────────────"

check("TCARR-NEG-01: missing record field → oof + OOF-TY0") do
  status(NEG_MISSING_RES) == 'oof' && diag_rules(NEG_MISSING_RES).include?('OOF-TY0') &&
    diagnostics(NEG_MISSING_RES).any? { |d| d['message'].include?("required field 'value' is missing") }
end

check("TCARR-NEG-02: extra record field → oof + OOF-TY0") do
  status(NEG_EXTRA_RES) == 'oof' && diag_rules(NEG_EXTRA_RES).include?('OOF-TY0') &&
    diagnostics(NEG_EXTRA_RES).any? { |d| d['message'].include?("unexpected field 'bogus'") }
end

check("TCARR-NEG-03: wrong field value type (Integer where String) → oof + OOF-TY0") do
  status(NEG_WRONG_RES) == 'oof' && diag_rules(NEG_WRONG_RES).include?('OOF-TY0') &&
    diagnostics(NEG_WRONG_RES).any? { |d| d['message'].include?("expects String, got Integer") }
end

check("TCARR-NEG-04: mixed element shapes (OrderBy in FilterPredicate collection) → oof + OOF-TY0") do
  status(NEG_MIXED_RES) == 'oof' && diag_rules(NEG_MIXED_RES).include?('OOF-TY0') &&
    diagnostics(NEG_MIXED_RES).any? { |d| d['message'].include?('expected FilterPredicate, got OrderBy') }
end

check("TCARR-NEG-05: record literal element in scalar Collection[String] → oof + OOF-TY0") do
  status(NEG_SCALAR_RES) == 'oof' && diag_rules(NEG_SCALAR_RES).include?('OOF-TY0') &&
    diagnostics(NEG_SCALAR_RES).any? { |d| d['message'].include?("does not match element type 'String'") }
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-EMPTY — empty-with-context accepted; free-standing gap closed
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-EMPTY ──────────────────────────────────────────────────────────────"

check("TCARR-EMPTY-01: empty array accepted with contextual Collection type (no diagnostics)") do
  # EmptyFilterCollection is part of the clean main fixture; its node typed above.
  status(MAIN) == 'ok' &&
    compute_type_tag(MAIN, 'EmptyFilterCollection', 'filters') == 'Collection[FilterPredicate]'
end

check("TCARR-EMPTY-02: free-standing array literal compiles ok, no 'Unsupported expression kind' (gap closed)") do
  status(FREE_RES) == 'ok' &&
    diagnostics(FREE_RES).none? { |d| d['message'].to_s.include?('Unsupported expression kind') } &&
    # free-standing (no Collection output hint) → stays Unknown, not fabricated
    compute_type_tag(FREE_RES, 'FreeStanding', 'filters') == 'Unknown'
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-LAYERA — Ruby TypeChecker parity (regression anchor with LAB-QUERY-P3)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-LAYERA ─────────────────────────────────────────────────────────────"

check("TCARR-LAYERA-01: Ruby TC: ArrayLiteralBuilder accepted") do
  ruby_contract_accepted?(LAYERA, 'ArrayLiteralBuilder')
end

check("TCARR-LAYERA-02: Ruby TC: [f1,f2] infers Collection element type name = Collection") do
  t = ruby_sym_type(LAYERA, 'filters', 'ArrayLiteralBuilder')
  (t.is_a?(Hash) ? t['name'] : t.to_s) == 'Collection'
end

check("TCARR-LAYERA-03: Two-layer parity: Rust + Ruby both type [f1,f2] as Collection[FilterPredicate]") do
  rust = compute_type_tag(MAIN, 'InlineFilterRefs', 'filters') == 'Collection[FilterPredicate]'
  t = ruby_sym_type(LAYERA, 'filters', 'ArrayLiteralBuilder')
  params = t.is_a?(Hash) ? Array(t['params']) : []
  fp = params.first
  ruby = fp && (fp.is_a?(Hash) ? fp['name'] : fp.to_s) == 'FilterPredicate'
  rust && ruby
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR-CLOSED — closed surface
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR-CLOSED ─────────────────────────────────────────────────────────────"

fixture_src = File.read(FIXTURE_PATH, encoding: 'UTF-8')

check("TCARR-CLOSED-01: no SQL execution in fixture") do
  !fixture_src.include?('execut' + 'e_sql') &&
    !fixture_src.include?('run_qu' + 'ery(') &&
    !fixture_src.include?('raw_sq' + 'l')
end

check("TCARR-CLOSED-02: no database connection / ORM in fixture") do
  !fixture_src.include?('establish_connection') &&
    !fixture_src.include?('ActiveRec' + 'ord') &&
    !fixture_src.include?('has_man' + 'y') &&
    !fixture_src.include?('save' + '!')
end

check("TCARR-CLOSED-03: all contracts pure/CORE; no effect contract; no capability/StorageCapability declaration") do
  # The authority disclaimer comment names StorageCapability to say it is NOT
  # opened; guard against an actual capability/effect declaration, not the word.
  fixture_src.include?('pure contract') &&
    !fixture_src.include?('effect contract') &&
    !fixture_src.match?(/^\s*capability\s/) &&
    !fixture_src.include?('require StorageCapability') &&
    !fixture_src.include?('IO.StorageCapability')
end

check("TCARR-CLOSED-04: no new grammar — only existing [..] array / {..} record / Collection[T] syntax") do
  # fixture uses only constructs already present in LAB-QUERY-P3 fixtures.
  fixture_src.include?('Collection[FilterPredicate]') &&
    fixture_src.include?('compute filters = [') &&
    !fixture_src.include?('macro ') &&
    !fixture_src.include?('syntax ')
end

check("TCARR-CLOSED-05: no stable/public API claim in fixture or runner") do
  !fixture_src.include?('stab' + 'le API') &&
    !fixture_src.include?('product' + 'ion API') &&
    !SOURCE.include?('stab' + 'le API')
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
  puts "\nALL CHECKS PASS — LAB-TC-ARRAY-P1 proof complete."
  puts "\nKey findings:"
  puts "  - Rust TypeChecker now types array literals in Collection[T] output contexts (contextual)"
  puts "  - [{...},{...}] and [f1,f2] both -> Collection[FilterPredicate] (compute + output SIR metadata)"
  puts "  - Empty array accepted ONLY with contextual type; free-standing stays Unknown (gap closed, no OOF-TY0)"
  puts "  - Missing/extra/wrong-typed fields and mixed element shapes fail closed (OOF-TY0)"
  puts "  - VM round-trips inline-constructed collections; full QueryPlan with inline filters compiles + runs"
  puts "  - LAB-QUERY-P3 workaround closed: filters can be constructed inline instead of passed as input"
  exit 0
end
