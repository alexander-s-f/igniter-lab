#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_tc_array_p2.rb
# LAB-TC-ARRAY-P2: Array literal typed from a nominal record-field context
#
# Closes the non-blocking gap left open by LAB-TC-ARRAY-P1: an intermediate
# array-literal compute that feeds a typed record field receives contextual
# Collection[T] type information from that field position.
#
#   compute filters = [...]
#   compute plan = { ..., filters: filters, ... }
#   output plan : QueryPlan          -- QueryPlan.filters : Collection[FilterPredicate]
#
# In LAB-TC-ARRAY-P1 the intermediate `filters` node typed Unknown (data
# preserved, type metadata lost). P2 pre-scans RecordLiteral computes whose
# declared output type is a named record; for each field that is a bare Ref to
# another compute node declared as Collection[T] in the record type, the
# referenced compute receives element hint T. Local, fail-closed, no global
# unification, no retroactive symbol mutation (the referenced compute is
# processed first in dependency order).
#
# Sections:
#   TCARR2-COMPILE   (3) — main fixture compiles clean; 2 contracts; Ruby TC no errors
#   TCARR2-FIELDTYPE (3) — intermediate `filters` now types Collection[FilterPredicate]
#                          (the closed gap); plan = QueryPlan; empty-filters typed too
#   TCARR2-VM        (2) — VM round-trip: plan.filters preserved (2 elems) and empty []
#   TCARR2-NEG       (4) — bad elements via field context still fail closed (OOF-TY0)
#   TCARR2-PRESERVE  (3) — P1 output-context still types; free-standing stays Unknown
#   TCARR2-CLOSED    (4) — closed surface: no SQL/DB/ORM, pure CORE, no new grammar
#
# Total: 19 checks
#
# Depends on: LAB-TC-ARRAY-P1, LAB-QUERY-P3, LAB-RACK-P13, LAB-RECORD-VM-P3,
#             LAB-MAP-RUST-P1, PROP-043-P5, LAB-STORAGE-CAPABILITY-P2
#
# Authority: LAB-ONLY. No canon claim. No framework compat. No public API.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_tc_array_p2.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'query_plan' / 'query_plan_array_record_field_context.ig').to_s

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

# ── Lab Rust compiler helpers ──────────────────────────────────────────────────

def compile_path(path)
  out_dir = Dir.mktmpdir('tcarr2')
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

def compile_inline(src, tag = 'tcarr2_inline')
  file = Tempfile.new([tag, '.ig'])
  file.write(src)
  file.close
  res = compile_path(file.path)
  file.unlink rescue nil
  res
end

def diagnostics(res); res[:report]&.fetch('diagnostics', []) || []; end
def diag_rules(res);  diagnostics(res).map { |d| d['rule'] }; end
def status(res);      res[:report]&.fetch('status', nil); end

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
  tmpfile = Tempfile.new(['tcarr2_inputs', '.json'])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _status = Open3.capture3(
    VM_BIN, 'run', '--contract', out_dir.to_s, '--inputs', tmpfile.path,
    '--entry', contract_name, '--json'
  )
  tmpfile.unlink rescue nil
  stdout = stdout.force_encoding('UTF-8') if stdout
  return { 'status' => 'vm_error' } if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

def run_ruby(src, tag = 'inline')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: "#{tag}.ig").to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { typed: typed }
rescue => e
  { error: e.message }
end

# ── Compile main fixture (Layer B) + Layer A ────────────────────────────────────

MAIN      = compile_path(FIXTURE_PATH)
MAIN_RUBY = run_ruby(File.read(FIXTURE_PATH, encoding: 'UTF-8'), 'array_record_field')

PLAN_INPUTS = {
  'source'     => { 'table' => 'users', 'schema' => 'public' },
  'projection' => { 'fields' => 'id,name', 'include_all' => false },
  'order'      => { 'field' => 'created_at', 'direction' => 'desc' },
  'limit'      => 25,
  'metadata'   => { 'trace_id' => 'abc' }
}.freeze

VM_PLAN  = (MAIN[:out_dir] && status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'BuildInlineSelectPlan', PLAN_INPUTS) : {}
VM_EMPTY = (MAIN[:out_dir] && status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'BuildEmptyFilterPlan', PLAN_INPUTS) : {}

# ── Negative inline sources (must FAIL closed) ──────────────────────────────────

NEG_HEAD = <<~'IG'
  module Lab.Neg
  type FilterPredicate { field: String, op: String, value: String }
  type OrderBy { field: String, direction: String }
  type Box { filters: Collection[FilterPredicate], note: String }
IG

NEG_MISSING = NEG_HEAD + <<~'IG'
  pure contract NegMissing {
    input note : String
    compute filters = [ { field: "status", op: "eq" } ]
    compute b = { filters: filters, note: note }
    output b : Box
  }
IG

NEG_EXTRA = NEG_HEAD + <<~'IG'
  pure contract NegExtra {
    input note : String
    compute filters = [ { field: "s", op: "eq", value: "a", bogus: "z" } ]
    compute b = { filters: filters, note: note }
    output b : Box
  }
IG

NEG_WRONG = NEG_HEAD + <<~'IG'
  pure contract NegWrong {
    input note : String
    input n : Integer
    compute filters = [ { field: "s", op: "eq", value: n } ]
    compute b = { filters: filters, note: note }
    output b : Box
  }
IG

NEG_MIXED = NEG_HEAD + <<~'IG'
  pure contract NegMixed {
    input note : String
    input ob : OrderBy
    compute filters = [ { field: "s", op: "eq", value: "a" }, ob ]
    compute b = { filters: filters, note: note }
    output b : Box
  }
IG

NEG_MISSING_RES = compile_inline(NEG_MISSING, 'neg2_missing')
NEG_EXTRA_RES   = compile_inline(NEG_EXTRA, 'neg2_extra')
NEG_WRONG_RES   = compile_inline(NEG_WRONG, 'neg2_wrong')
NEG_MIXED_RES   = compile_inline(NEG_MIXED, 'neg2_mixed')

# ── P1-preservation sources ─────────────────────────────────────────────────────

P1_OUTPUT_SRC = <<~'IG'
  module Lab.P1Out
  type FilterPredicate { field: String, op: String, value: String }
  pure contract OutputContext {
    compute filters = [ { field: "status", op: "eq", value: "active" } ]
    output filters : Collection[FilterPredicate]
  }
IG

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

P1_OUTPUT_RES = compile_inline(P1_OUTPUT_SRC, 'p1_output')
FREE_RES      = compile_inline(FREE_SRC, 'free_standing2')

# ─────────────────────────────────────────────────────────────────────────────
# TCARR2-COMPILE
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR2-COMPILE ───────────────────────────────────────────────────────────"

check("TCARR2-COMPILE-01: Rust compiler: main fixture compiles, status ok") do
  status(MAIN) == 'ok'
end

check("TCARR2-COMPILE-02: Rust compiler: zero diagnostics, 2 contracts") do
  diagnostics(MAIN).empty? && (MAIN[:report]&.fetch('contracts', []) || []).length == 2
end

check("TCARR2-COMPILE-03: Ruby TypeChecker: main fixture has no type_errors") do
  (MAIN_RUBY[:typed]&.fetch('type_errors', []) || []).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR2-FIELDTYPE — the closed gap
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR2-FIELDTYPE ─────────────────────────────────────────────────────────"

check("TCARR2-FIELDTYPE-01: intermediate 'filters' types Collection[FilterPredicate] from record-field context (gap closed)") do
  compute_type_tag(MAIN, 'BuildInlineSelectPlan', 'filters') == 'Collection[FilterPredicate]'
end

check("TCARR2-FIELDTYPE-02: enclosing 'plan' types QueryPlan; output port QueryPlan") do
  compute_type_tag(MAIN, 'BuildInlineSelectPlan', 'plan') == 'QueryPlan' &&
    output_type_tag(MAIN, 'BuildInlineSelectPlan', 'plan') == 'QueryPlan'
end

check("TCARR2-FIELDTYPE-03: empty intermediate 'filters' types Collection[FilterPredicate] from field context") do
  compute_type_tag(MAIN, 'BuildEmptyFilterPlan', 'filters') == 'Collection[FilterPredicate]'
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR2-VM
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR2-VM ────────────────────────────────────────────────────────────────"

check("TCARR2-VM-01: BuildInlineSelectPlan → plan.filters preserved (2 records)") do
  f = VM_PLAN.dig('result', 'filters')
  VM_PLAN['status'] == 'success' && VM_PLAN.dig('result', 'kind') == 'select' &&
    f.is_a?(Array) && f.length == 2 &&
    f[0]['field'] == 'status' && f[1]['field'] == 'role'
end

check("TCARR2-VM-02: BuildEmptyFilterPlan → plan.filters is empty array") do
  VM_EMPTY['status'] == 'success' && VM_EMPTY.dig('result', 'filters') == []
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR2-NEG — fail closed via field context
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR2-NEG ───────────────────────────────────────────────────────────────"

check("TCARR2-NEG-01: missing field via field context → oof + OOF-TY0") do
  status(NEG_MISSING_RES) == 'oof' && diag_rules(NEG_MISSING_RES).include?('OOF-TY0') &&
    diagnostics(NEG_MISSING_RES).any? { |d| d['message'].include?("required field 'value' is missing") }
end

check("TCARR2-NEG-02: extra field via field context → oof + OOF-TY0") do
  status(NEG_EXTRA_RES) == 'oof' && diag_rules(NEG_EXTRA_RES).include?('OOF-TY0') &&
    diagnostics(NEG_EXTRA_RES).any? { |d| d['message'].include?("unexpected field 'bogus'") }
end

check("TCARR2-NEG-03: wrong field value type via field context → oof + OOF-TY0") do
  status(NEG_WRONG_RES) == 'oof' && diag_rules(NEG_WRONG_RES).include?('OOF-TY0') &&
    diagnostics(NEG_WRONG_RES).any? { |d| d['message'].include?("expects String, got Integer") }
end

check("TCARR2-NEG-04: mixed element shapes via field context → oof + OOF-TY0") do
  status(NEG_MIXED_RES) == 'oof' && diag_rules(NEG_MIXED_RES).include?('OOF-TY0') &&
    diagnostics(NEG_MIXED_RES).any? { |d| d['message'].include?('expected FilterPredicate, got OrderBy') }
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR2-PRESERVE — P1 behavior intact
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR2-PRESERVE ──────────────────────────────────────────────────────────"

check("TCARR2-PRESERVE-01: P1 output-context still types Collection[FilterPredicate]") do
  status(P1_OUTPUT_RES) == 'ok' &&
    compute_type_tag(P1_OUTPUT_RES, 'OutputContext', 'filters') == 'Collection[FilterPredicate]'
end

check("TCARR2-PRESERVE-02: free-standing array literal (no output, no record-field) stays Unknown") do
  status(FREE_RES) == 'ok' &&
    compute_type_tag(FREE_RES, 'FreeStanding', 'filters') == 'Unknown'
end

check("TCARR2-PRESERVE-03: free-standing array compiles with no 'Unsupported expression kind'") do
  diagnostics(FREE_RES).none? { |d| d['message'].to_s.include?('Unsupported expression kind') }
end

# ─────────────────────────────────────────────────────────────────────────────
# TCARR2-CLOSED
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── TCARR2-CLOSED ────────────────────────────────────────────────────────────"

fixture_src = File.read(FIXTURE_PATH, encoding: 'UTF-8')

check("TCARR2-CLOSED-01: no SQL execution in fixture") do
  !fixture_src.include?('execut' + 'e_sql') && !fixture_src.include?('raw_sq' + 'l') &&
    !fixture_src.include?('run_qu' + 'ery(')
end

check("TCARR2-CLOSED-02: no DB connection / ORM in fixture") do
  !fixture_src.include?('establish_connection') && !fixture_src.include?('ActiveRec' + 'ord') &&
    !fixture_src.include?('has_man' + 'y') && !fixture_src.include?('save' + '!')
end

check("TCARR2-CLOSED-03: pure CORE; no effect contract; no capability/StorageCapability declaration") do
  fixture_src.include?('pure contract') && !fixture_src.include?('effect contract') &&
    !fixture_src.match?(/^\s*capability\s/) && !fixture_src.include?('IO.StorageCapability')
end

check("TCARR2-CLOSED-04: no new grammar; no stable/public API claim") do
  fixture_src.include?('Collection[FilterPredicate]') &&
    !fixture_src.include?('macro ') && !fixture_src.include?('syntax ') &&
    !fixture_src.include?('stab' + 'le API') && !SOURCE.include?('stab' + 'le API')
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
  puts "\nALL CHECKS PASS — LAB-TC-ARRAY-P2 proof complete."
  puts "\nKey findings:"
  puts "  - Record-field context types an intermediate array-literal compute as Collection[T]"
  puts "  - No retroactive symbol mutation (referenced compute processed first); no global inference"
  puts "  - Empty intermediate array typed from field context iff expected field type known"
  puts "  - Bad/mixed record elements still fail closed (OOF-TY0)"
  puts "  - P1 output-context typing preserved; free-standing arrays remain Unknown"
  puts "  - VM round-trips plan.filters; LAB-TC-ARRAY-P1 remaining gap closed"
  exit 0
end
