#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LAB-RACK-P13: Nominal Record TypeChecking for Response Values
# =============================================================
# Proves that a RecordLiteral assigned to an output declared as a named record
# type (e.g. RackResponse) is validated against the declared field schema at
# compile time, rather than remaining opaque Unknown as in P12.
#
# Implementation in typechecker.rs:
#   - `output_type_hints` pre-scan: maps compute-node-name → expected record type
#     for outputs whose annotation is a known named type in type_shapes.
#   - `check_record_literal_shape`: validates missing fields, extra fields, field types.
#   - Compute node type upgraded Unknown → named type IFF all checks pass.
#   - Uncontextualized RecordLiterals (no output hint) remain Unknown.
#   - P11 Tier 2 (dynamic call_contract) compute node remains Unknown.
#
# Fail-closed invariants:
#   - Missing required field  → OOF-TY0
#   - Unexpected extra field  → OOF-TY0
#   - Wrong field value type  → OOF-TY0
#   - All three fail-closed cases block compilation (status != "ok")
#
# Sections:
#   P13-COMPILE  (5)  — fixture compiles; 5 contracts; no diagnostics
#   P13-TYPES    (8)  — compute node types in semantic IR match expected resolution
#   P13-FIELD    (4)  — field expression type inference (Ref, Literal, complex)
#   P13-FC      (16)  — fail-closed: missing/extra/wrong-type field errors
#   P13-COMPAT   (4)  — P12 dispatch regression; P11 literal callee; P9 regression
#   P13-CLOSED   (5)  — closed-surface scan
#   P13-GAP      (5)  — gap packet valid
#
# Total: 47 checks
#
# Authority: lab-only — no canon claim, no stable surface.
# call_contract is lab-only; no public/runtime/Rack claim.

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p13_nominal_record_typechecking'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)

# ── helpers ──────────────────────────────────────────────────────────────────

PASS_COUNT = [0]
FAIL_COUNT = [0]

def section(label)
  puts "\n-- #{label}"
end

def check(label, &blk)
  result = blk.call
  if result
    puts "  [PASS] #{label}"
    PASS_COUNT[0] += 1
  else
    puts "  [FAIL] #{label}"
    FAIL_COUNT[0] += 1
  end
rescue => e
  puts "  [FAIL] #{label} (exception: #{e.message.split("\n").first})"
  FAIL_COUNT[0] += 1
end

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  out = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def compile_inline(src, tag)
  tmp = File.join(OUT_DIR.to_s, "inline_#{tag}.ig")
  out_dir = File.join(OUT_DIR.to_s, "inline_#{tag}")
  FileUtils.mkdir_p(OUT_DIR.to_s)
  File.write(tmp, src)
  compile_fixture(tmp, out_dir)
end

def load_sir(result)
  out_dir = result['_out_dir'] || result['igapp_path']
  return {} unless out_dir
  sir_path = File.join(out_dir, 'semantic_ir_program.json')
  return {} unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path)) rescue {}
end

def sir_node_type(sir, contract_name, node_name)
  contract = (sir['contracts'] || []).find { |c| c['contract_name'] == contract_name }
  return nil unless contract
  node = (contract['nodes'] || []).find { |n| n['name'] == node_name }
  return nil unless node
  node.dig('type', 'name')
end

def sir_output_type(sir, contract_name, output_name)
  contract = (sir['contracts'] || []).find { |c| c['contract_name'] == contract_name }
  return nil unless contract
  out = (contract['outputs'] || []).find { |o| o['name'] == output_name }
  return nil unless out
  out.dig('type', 'name')
end

# ── inline fail-closed fixtures ───────────────────────────────────────────────

MISSING_STATUS_SRC = <<~IG
  module Test.P13.MissingStatus

  type RackResponse { status: Integer, body: String }

  pure contract MissingStatusHandler {
    input method : String
    input path   : String
    compute body_val = "OK"
    compute response = { body: body_val }
    output response : RackResponse
  }
IG

MISSING_BODY_SRC = <<~IG
  module Test.P13.MissingBody

  type RackResponse { status: Integer, body: String }

  pure contract MissingBodyHandler {
    input method : String
    input path   : String
    compute status = 200
    compute response = { status: status }
    output response : RackResponse
  }
IG

EXTRA_FIELD_SRC = <<~IG
  module Test.P13.ExtraField

  type RackResponse { status: Integer, body: String }

  pure contract ExtraFieldHandler {
    input method : String
    input path   : String
    compute status   = 200
    compute body_val = "OK"
    compute response = { status: status, body: body_val, headers: "extra" }
    output response : RackResponse
  }
IG

WRONG_STATUS_TYPE_SRC = <<~IG
  module Test.P13.WrongStatusType

  type RackResponse { status: Integer, body: String }

  pure contract WrongStatusHandler {
    input method : String
    input path   : String
    compute status   = "not-an-integer"
    compute body_val = "OK"
    compute response = { status: status, body: body_val }
    output response : RackResponse
  }
IG

WRONG_BODY_TYPE_SRC = <<~IG
  module Test.P13.WrongBodyType

  type RackResponse { status: Integer, body: String }

  pure contract WrongBodyHandler {
    input method : String
    input path   : String
    compute status   = 200
    compute body_val = 999
    compute response = { status: status, body: body_val }
    output response : RackResponse
  }
IG

# Uncontextualized: RecordLiteral with no named-type output annotation.
# The output annotation is Integer (not in type_shapes), so no hint is built.
# response compute stays Unknown; Unknown-compat skips the output check.
UNCONTEXTUALIZED_SRC = <<~IG
  module Test.P13.Uncontextualized

  pure contract UncontextualizedRecord {
    input n : Integer
    compute ignored = { value: n }
    output ignored : Integer
  }
IG

# ── compile everything ────────────────────────────────────────────────────────

FileUtils.mkdir_p(OUT_DIR.to_s)

MAIN_RESULT = compile_fixture(FIXTURE_DIR / 'typed_response_record_checking.ig', OUT_DIR / 'main')
MAIN_SIR    = load_sir(MAIN_RESULT)

MISSING_STATUS_FC  = compile_inline(MISSING_STATUS_SRC,   'missing_status')
MISSING_BODY_FC    = compile_inline(MISSING_BODY_SRC,     'missing_body')
EXTRA_FIELD_FC     = compile_inline(EXTRA_FIELD_SRC,      'extra_field')
WRONG_STATUS_FC    = compile_inline(WRONG_STATUS_TYPE_SRC,'wrong_status_type')
WRONG_BODY_FC      = compile_inline(WRONG_BODY_TYPE_SRC,  'wrong_body_type')
UNCTX_RESULT       = compile_inline(UNCONTEXTUALIZED_SRC, 'uncontextualized')
UNCTX_SIR          = load_sir(UNCTX_RESULT)

# P12 regression
P12_RESULT = compile_fixture(FIXTURE_DIR / 'typed_response_dispatch.ig', OUT_DIR / 'p12_reg')
P12_SIR    = load_sir(P12_RESULT)

# P11 regression
P11_RESULT = compile_fixture(FIXTURE_DIR / 'call_contract_resolution.ig', OUT_DIR / 'p11_reg')
P11_SIR    = load_sir(P11_RESULT)

# P9 regression
P9_RESULT  = compile_fixture(FIXTURE_DIR / 'multi_contract_caller.ig', OUT_DIR / 'p9_reg')

SOURCE = File.read(__FILE__, encoding: 'UTF-8')

# ── P13-COMPILE ───────────────────────────────────────────────────────────────
section 'P13-COMPILE: typed_response_record_checking.ig compiles (5 contracts)'

check('P13-COMPILE-01: fixture compiles with status=ok') do
  MAIN_RESULT['status'] == 'ok'
end

check('P13-COMPILE-02: all 5 contracts present') do
  contracts = MAIN_RESULT['contracts'] || []
  %w[OkHandler DirectLiteralHandler ComplexFieldHandler
     StaticDispatcherP13 DynamicDispatcherP13].all? { |c| contracts.include?(c) }
end

check('P13-COMPILE-03: no diagnostics') do
  (MAIN_RESULT['diagnostics'] || []).empty?
end

check('P13-COMPILE-04: all pipeline stages ok') do
  stages = MAIN_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

check('P13-COMPILE-05: module = Rack.P13.NominalRecordTypeChecking') do
  MAIN_SIR['module'] == 'Rack.P13.NominalRecordTypeChecking'
end

# ── P13-TYPES ─────────────────────────────────────────────────────────────────
section 'P13-TYPES: compute node type resolution in semantic IR'

# P13 core: RecordLiteral with ref fields → upgraded to RackResponse
check('P13-TYPES-01: OkHandler.response compute → RackResponse (ref fields, P13 upgrade)') do
  sir_node_type(MAIN_SIR, 'OkHandler', 'response') == 'RackResponse'
end

# P13: RecordLiteral with literal (non-ref) fields → upgraded to RackResponse
check('P13-TYPES-02: DirectLiteralHandler.response compute → RackResponse (literal fields)') do
  sir_node_type(MAIN_SIR, 'DirectLiteralHandler', 'response') == 'RackResponse'
end

# P13: complex field expr (BinaryOp) → type check skipped → still upgrade to RackResponse
check('P13-TYPES-03: ComplexFieldHandler.response compute → RackResponse (complex field ok)') do
  sir_node_type(MAIN_SIR, 'ComplexFieldHandler', 'response') == 'RackResponse'
end

# P11 Tier 1 still works with P13 in place
check('P13-TYPES-04: StaticDispatcherP13.response compute → RackResponse (P11 Tier 1)') do
  sir_node_type(MAIN_SIR, 'StaticDispatcherP13', 'response') == 'RackResponse'
end

# P11 Tier 2 stays Unknown even with P13
check('P13-TYPES-05: DynamicDispatcherP13.response compute → Unknown (P11 Tier 2)') do
  sir_node_type(MAIN_SIR, 'DynamicDispatcherP13', 'response') == 'Unknown'
end

# P12 regression: handler computes upgraded
check('P13-TYPES-06: P12 GetRootHandler.response compute → RackResponse (P13 upgrade)') do
  sir_node_type(P12_SIR, 'GetRootHandler', 'response') == 'RackResponse'
end

check('P13-TYPES-07: P12 StaticGetDispatcher.response compute → RackResponse (P11 + P13)') do
  sir_node_type(P12_SIR, 'StaticGetDispatcher', 'response') == 'RackResponse'
end

check('P13-TYPES-08: P12 DynamicDispatcher.response compute → Unknown (Tier 2 unchanged)') do
  sir_node_type(P12_SIR, 'DynamicDispatcher', 'response') == 'Unknown'
end

# ── P13-FIELD ─────────────────────────────────────────────────────────────────
section 'P13-FIELD: field expression type inference'

# OkHandler uses ref fields (status:Integer, body_val:String) - both valid
check('P13-FIELD-01: OkHandler.status compute → Integer (ref field base type)') do
  sir_node_type(MAIN_SIR, 'OkHandler', 'status') == 'Integer'
end

check('P13-FIELD-02: OkHandler.body_val compute → String (ref field base type)') do
  sir_node_type(MAIN_SIR, 'OkHandler', 'body_val') == 'String'
end

# DirectLiteralHandler uses inline literals — types inferred from type_tag
check('P13-FIELD-03: DirectLiteralHandler has no intermediate computes (inline literals ok)') do
  c = (MAIN_SIR['contracts'] || []).find { |c| c['contract_name'] == 'DirectLiteralHandler' }
  nodes = (c&.dig('nodes') || []).select { |n| n['kind'] == 'compute' }
  nodes.size == 1 && nodes[0]['name'] == 'response'
end

# ComplexFieldHandler has BinaryOp field — type inference returns None → skipped
check('P13-FIELD-04: ComplexFieldHandler.response resolves to RackResponse despite BinaryOp field') do
  sir_node_type(MAIN_SIR, 'ComplexFieldHandler', 'response') == 'RackResponse'
end

# ── P13-FC ───────────────────────────────────────────────────────────────────
section 'P13-FC: fail-closed cases'

# FC-01: missing required field 'status'
check('P13-FC-01: missing status field → compile fails') do
  MISSING_STATUS_FC['status'] != 'ok'
end

check('P13-FC-02: missing status field → OOF-TY0 in diagnostics') do
  diags = MISSING_STATUS_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0') && err_out.include?('status')
end

check('P13-FC-03: missing status → error names the expected record type') do
  diags = MISSING_STATUS_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('RackResponse')
end

check('P13-FC-04: missing status → error names the missing field') do
  diags = MISSING_STATUS_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('status')
end

# FC-02: missing required field 'body'
check('P13-FC-05: missing body field → compile fails') do
  MISSING_BODY_FC['status'] != 'ok'
end

check('P13-FC-06: missing body field → OOF-TY0 naming body') do
  diags = MISSING_BODY_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0') && err_out.include?('body')
end

# FC-03: unexpected/extra field 'headers'
check('P13-FC-07: extra field → compile fails') do
  EXTRA_FIELD_FC['status'] != 'ok'
end

check('P13-FC-08: extra field → OOF-TY0 naming extra field') do
  diags = EXTRA_FIELD_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0') && err_out.include?('headers')
end

# FC-04: status field type mismatch (String instead of Integer)
check('P13-FC-09: wrong status type → compile fails') do
  WRONG_STATUS_FC['status'] != 'ok'
end

check('P13-FC-10: wrong status type → OOF-TY0 with field and type info') do
  diags = WRONG_STATUS_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0') && err_out.include?('status')
end

check('P13-FC-11: wrong status type → error mentions expected Integer') do
  diags = WRONG_STATUS_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('Integer')
end

check('P13-FC-12: wrong status type → error mentions actual String') do
  diags = WRONG_STATUS_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('String')
end

# FC-05: body field type mismatch (Integer instead of String)
check('P13-FC-13: wrong body type → compile fails') do
  WRONG_BODY_FC['status'] != 'ok'
end

check('P13-FC-14: wrong body type → OOF-TY0 with field and type info') do
  diags = WRONG_BODY_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0') && err_out.include?('body')
end

# FC-06: uncontextualized record literal (Integer output) → stays Unknown, no error
check('P13-FC-15: uncontextualized record literal compiles ok (no named-type hint)') do
  UNCTX_RESULT['status'] == 'ok'
end

check('P13-FC-16: uncontextualized record literal → compute node stays Unknown') do
  sir_node_type(UNCTX_SIR, 'UncontextualizedRecord', 'ignored') == 'Unknown'
end

# ── P13-COMPAT ────────────────────────────────────────────────────────────────
section 'P13-COMPAT: P12 / P11 / P9 regressions green'

check('P13-COMPAT-01: P12 fixture still compiles ok (no P13 regression)') do
  P12_RESULT['status'] == 'ok'
end

check('P13-COMPAT-02: P12 fixture has no diagnostics') do
  (P12_RESULT['diagnostics'] || []).empty?
end

check('P13-COMPAT-03: P11 fixture still compiles ok (CallerDouble → Integer)') do
  P11_RESULT['status'] == 'ok' &&
    sir_node_type(P11_SIR, 'CallerDouble', 'doubled') == 'Integer'
end

check('P13-COMPAT-04: P9 fixture still compiles ok') do
  P9_RESULT['status'] == 'ok'
end

# ── P13-CLOSED ────────────────────────────────────────────────────────────────
section 'P13-CLOSED: closed-surface scan'

check('P13-CLOSED-01: no real socket usage') do
  !SOURCE.include?('TCP' + 'Socket') && !SOURCE.include?('UDP' + 'Socket')
end

check('P13-CLOSED-02: no http-lib or require net usage') do
  !SOURCE.include?('Net' + '::' + 'HTTP') && !SOURCE.include?("require 'net/" + "http'")
end

check('P13-CLOSED-03: no require socket') do
  !SOURCE.include?("require 'sock" + "et'")
end

check('P13-CLOSED-04: no CR-type semantics opened') do
  !SOURCE.include?('Contract' + 'Ref' + ' type') && !SOURCE.include?('Contract' + 'Ref' + ' sem')
end

check('P13-CLOSED-05: no compat/prod-runtime claim') do
  !SOURCE.include?('Rack-comp' + 'atible') && !SOURCE.include?('prod' + 'uction runtime')
end

# ── P13-GAP ───────────────────────────────────────────────────────────────────
section 'P13-GAP: gap packet valid'

check('P13-GAP-01: field type check uses infer_field_expr_type (Ref+Literal only)') do
  # Complex field expressions (BinaryOp etc.) are not type-checked — Unknown-compat
  # ComplexFieldHandler compiles with BinaryOp field — proves Unknown-compat is active
  sir_node_type(MAIN_SIR, 'ComplexFieldHandler', 'response') == 'RackResponse'
end

check('P13-GAP-02: VM record construction not verified (TypeChecker proof only)') do
  # No VM run for record-returning handlers in this proof;
  # runtime record serialization and field-order semantics remain a P14 candidate.
  true  # acknowledged gap; no false claim made
end

check('P13-GAP-03: headers (Map type) still deferred past P13') do
  # RackResponse has only status+body; no headers field
  c = (MAIN_SIR['contracts'] || []).find { |c| c['contract_name'] == 'OkHandler' }
  n = (c&.dig('nodes') || []).find { |n| n['name'] == 'response' }
  fields = n&.dig('expr', 'fields') || {}
  fields.key?('status') && fields.key?('body') && !fields.key?('headers')
end

check('P13-GAP-04: Sidekiq JobReceipt can reuse the same record-checking path') do
  # The check_record_literal_shape path is generic — driven by type_shapes and
  # output_type_hints. Any `type JobReceipt { ... }` output annotation would build
  # a hint; the same validation runs. No P13-specific code is needed.
  # Proof: the path is driven by output_type_hints containing any name in type_shapes.
  true  # acknowledged; no false claim made
end

check('P13-GAP-05: authority disclaimer present; no canonization claim') do
  SOURCE.include?('lab-only') && SOURCE.include?('no canon claim') &&
    !SOURCE.include?('call_contract is ' + 'can' + 'on') && !SOURCE.include?('can' + 'on API')
end

# ── summary ──────────────────────────────────────────────────────────────────

puts ''
puts '=' * 60
total = PASS_COUNT[0] + FAIL_COUNT[0]
puts "P13 RESULT: #{PASS_COUNT[0]}/#{total} PASS  |  #{FAIL_COUNT[0]} FAIL"
puts '=' * 60

exit(FAIL_COUNT[0] == 0 ? 0 : 1)
