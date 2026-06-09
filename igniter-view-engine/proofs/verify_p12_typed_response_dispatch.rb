#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LAB-RACK-P12: Typed Response Single-Output Dispatch
# ====================================================
# Proves that Rack-like handler contracts can return a structured single-output
# response value (`RackResponse`) through literal `call_contract("Handler", ...)`,
# using the P11 TypeChecker module contract registry to resolve the handler output
# type statically (RackResponse, not Unknown).
#
# Key design properties verified:
#   - `type RackResponse { status: Integer, body: String }` declared in module
#   - Three handler contracts (GetRootHandler, NotFoundHandler,
#     MethodNotAllowedHandler) each output a single `RackResponse`
#   - Handler bodies use `{ status: ..., body: ... }` RecordLiteral — TypeChecker
#     returns Unknown for the compute node (nominal record type matching deferred)
#   - Dispatcher contracts (StaticGetDispatcher, StaticNotFoundDispatcher) use
#     literal call_contract("HandlerName", ...) → P11 Tier 1 resolves compute node
#     to RackResponse (not Unknown)
#   - DynamicDispatcher uses a variable callee (Tier 2) → compute node stays Unknown
#
# Sections:
#   P12-COMPILE  (5)  — fixture compiles; 6 contracts; no diagnostics
#   P12-STATIC   (8)  — compute node types match tier policy in semantic IR
#   P12-TYPE     (4)  — RackResponse annotation visible in output declarations
#   P12-TIER2    (4)  — dynamic callee → Unknown; compiles cleanly
#   P12-FC       (8)  — fail-closed inline cases (unknown/arity/self-rec)
#   P12-REG      (6)  — P11 + P9 regressions green
#   P12-CLOSED   (5)  — closed-surface scan
#   P12-GAP      (5)  — gap packet valid
#
# Total: 45 checks
#
# Authority: lab-only — no canon claim, no stable API surface.
# call_contract is explicitly lab-only; no public/stable/runtime claim.

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p12_typed_response_dispatch'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)

# ── helpers ──────────────────────────────────────────────────────────────────

PASS_COUNT = [0]
FAIL_COUNT = [0]

def section(label)
  puts "\n── #{label}"
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

# ── inline fixtures for fail-closed tests ────────────────────────────────────

# FC-01: literal callee that does not exist in the module → OOF-TY0
UNKNOWN_HANDLER_SRC = <<~IG
  module Test.P12.UnknownHandler

  type FakeResponse { code: Integer }

  pure contract CallerOfGhost {
    input method : String
    input path   : String
    compute response = call_contract("GhostHandler", method, path)
    output response : FakeResponse
  }
IG

# FC-02: literal callee with arity mismatch — handler needs 2 inputs, caller passes 1
ARITY_MISMATCH_SRC = <<~IG
  module Test.P12.ArityMismatch

  type SimpleResponse { status: Integer }

  pure contract TwoInputHandler {
    input method : String
    input path   : String
    compute status = 200
    compute response = { status: status }
    output response : SimpleResponse
  }

  pure contract WrongArityCaller {
    input method : String
    compute response = call_contract("TwoInputHandler", method)
    output response : SimpleResponse
  }
IG

# FC-03: self-recursion via literal callee → OOF-TY0
SELF_REC_SRC = <<~IG
  module Test.P12.SelfRecursiveDispatcher

  type LoopResponse { step: Integer }

  pure contract LoopingDispatcher {
    input method : String
    input path   : String
    compute response = call_contract("LoopingDispatcher", method, path)
    output response : LoopResponse
  }
IG

# FC-04: inline fixture proving a correct literal dispatch still works —
# dispatch to a same-module pure handler → resolves to SimpleResponse (not Unknown)
CORRECT_INLINE_SRC = <<~IG
  module Test.P12.CorrectInlineDispatch

  type SimpleResponse { code: Integer }

  pure contract EchoHandler {
    input method : String
    input path   : String
    compute code     = 200
    compute response = { code: code }
    output response : SimpleResponse
  }

  pure contract EchoDispatcher {
    input method : String
    input path   : String
    compute response = call_contract("EchoHandler", method, path)
    output response : SimpleResponse
  }
IG

# ── compile everything ───────────────────────────────────────────────────────

FileUtils.mkdir_p(OUT_DIR.to_s)

MAIN_RESULT = compile_fixture(FIXTURE_DIR / 'typed_response_dispatch.ig', OUT_DIR / 'main')
MAIN_SIR    = load_sir(MAIN_RESULT)

UNKNOWN_FC  = compile_inline(UNKNOWN_HANDLER_SRC,  'unknown_handler')
ARITY_FC    = compile_inline(ARITY_MISMATCH_SRC,   'arity_mismatch')
SELF_REC_FC = compile_inline(SELF_REC_SRC,         'self_rec')
CORRECT_FC  = compile_inline(CORRECT_INLINE_SRC,   'correct_inline')

CORRECT_SIR = load_sir(CORRECT_FC)

# P11 and P9 regression fixtures
P11_RESULT = compile_fixture(FIXTURE_DIR / 'call_contract_resolution.ig', OUT_DIR / 'p11_reg')
P11_SIR    = load_sir(P11_RESULT)
P9_RESULT  = compile_fixture(FIXTURE_DIR / 'multi_contract_caller.ig', OUT_DIR / 'p9_reg')

SOURCE = File.read(__FILE__, encoding: 'UTF-8')

# ── P12-COMPILE ───────────────────────────────────────────────────────────────
section 'P12-COMPILE: typed_response_dispatch.ig compiles (6 contracts)'

check('P12-COMPILE-01: fixture compiles with status=ok') do
  MAIN_RESULT['status'] == 'ok'
end

check('P12-COMPILE-02: all 6 contracts present') do
  contracts = MAIN_RESULT['contracts'] || []
  %w[
    GetRootHandler NotFoundHandler MethodNotAllowedHandler
    StaticGetDispatcher StaticNotFoundDispatcher DynamicDispatcher
  ].all? { |c| contracts.include?(c) }
end

check('P12-COMPILE-03: no diagnostics') do
  (MAIN_RESULT['diagnostics'] || []).empty?
end

check('P12-COMPILE-04: all pipeline stages ok') do
  stages = MAIN_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

check('P12-COMPILE-05: module = Rack.P12.TypedResponseDispatch') do
  MAIN_SIR['module'] == 'Rack.P12.TypedResponseDispatch'
end

# ── P12-STATIC ────────────────────────────────────────────────────────────────
section 'P12-STATIC: compute node types verify tier policy'

# Tier 1 resolution: literal callees → callee output type
check('P12-STATIC-01: StaticGetDispatcher.response compute → RackResponse (Tier 1)') do
  sir_node_type(MAIN_SIR, 'StaticGetDispatcher', 'response') == 'RackResponse'
end

check('P12-STATIC-02: StaticNotFoundDispatcher.response compute → RackResponse (Tier 1)') do
  sir_node_type(MAIN_SIR, 'StaticNotFoundDispatcher', 'response') == 'RackResponse'
end

# RecordLiteral compute nodes — upgraded to RackResponse by P13 nominal record checking.
# (P12 original: these were Unknown; P13 closes the gap by validating fields against
# the declared output type annotation and upgrading the compute node type.)
check('P12-STATIC-03: GetRootHandler.response compute → RackResponse (P13 upgraded)') do
  sir_node_type(MAIN_SIR, 'GetRootHandler', 'response') == 'RackResponse'
end

check('P12-STATIC-04: NotFoundHandler.response compute → RackResponse (P13 upgraded)') do
  sir_node_type(MAIN_SIR, 'NotFoundHandler', 'response') == 'RackResponse'
end

check('P12-STATIC-05: MethodNotAllowedHandler.response compute → RackResponse (P13 upgraded)') do
  sir_node_type(MAIN_SIR, 'MethodNotAllowedHandler', 'response') == 'RackResponse'
end

# Handler compute: status and body_val still get concrete types (non-record)
check('P12-STATIC-06: GetRootHandler.status compute → Integer') do
  sir_node_type(MAIN_SIR, 'GetRootHandler', 'status') == 'Integer'
end

check('P12-STATIC-07: GetRootHandler.body_val compute → String') do
  sir_node_type(MAIN_SIR, 'GetRootHandler', 'body_val') == 'String'
end

# response expr in handler is record_literal kind
check('P12-STATIC-08: GetRootHandler.response expr kind = record_literal') do
  c = (MAIN_SIR['contracts'] || []).find { |c| c['contract_name'] == 'GetRootHandler' }
  n = (c&.dig('nodes') || []).find { |n| n['name'] == 'response' }
  n&.dig('expr', 'kind') == 'record_literal'
end

# ── P12-TYPE ──────────────────────────────────────────────────────────────────
section 'P12-TYPE: RackResponse annotation visible in output declarations'

check('P12-TYPE-01: GetRootHandler output declared type = RackResponse') do
  sir_output_type(MAIN_SIR, 'GetRootHandler', 'response') == 'RackResponse'
end

check('P12-TYPE-02: StaticGetDispatcher output declared type = RackResponse') do
  sir_output_type(MAIN_SIR, 'StaticGetDispatcher', 'response') == 'RackResponse'
end

check('P12-TYPE-03: DynamicDispatcher output declared type = RackResponse') do
  sir_output_type(MAIN_SIR, 'DynamicDispatcher', 'response') == 'RackResponse'
end

check('P12-TYPE-04: all 6 contracts declare response output as RackResponse') do
  contracts = MAIN_SIR['contracts'] || []
  contracts.all? do |c|
    sir_output_type(MAIN_SIR, c['contract_name'], 'response') == 'RackResponse'
  end
end

# ── P12-TIER2 ─────────────────────────────────────────────────────────────────
section 'P12-TIER2: dynamic callee stays Unknown; no OOF-TY0 emitted'

check('P12-TIER2-01: DynamicDispatcher.response compute → Unknown (Tier 2)') do
  sir_node_type(MAIN_SIR, 'DynamicDispatcher', 'response') == 'Unknown'
end

check('P12-TIER2-02: DynamicDispatcher compiles without error') do
  MAIN_RESULT['status'] == 'ok'
end

check('P12-TIER2-03: no OOF-TY0 in main fixture diagnostics') do
  diags = MAIN_RESULT['diagnostics'] || []
  diags.none? { |d| d.to_s.include?('OOF-TY0') }
end

check('P12-TIER2-04: Tier 1 resolves to RackResponse, Tier 2 to Unknown (contrast)') do
  tier1 = sir_node_type(MAIN_SIR, 'StaticGetDispatcher',  'response')
  tier2 = sir_node_type(MAIN_SIR, 'DynamicDispatcher',    'response')
  tier1 == 'RackResponse' && tier2 == 'Unknown'
end

# ── P12-FC ───────────────────────────────────────────────────────────────────
section 'P12-FC: fail-closed inline cases'

# FC-01: literal callee not in module → OOF-TY0
check('P12-FC-01: unknown literal handler → compile fails') do
  UNKNOWN_FC['status'] != 'ok'
end

check('P12-FC-02: unknown literal handler → OOF-TY0 in diagnostics') do
  diags = UNKNOWN_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0') || err_out.include?('GhostHandler')
end

# FC-02: arity mismatch on literal handler call → OOF-TY0
check('P12-FC-03: arity mismatch on literal handler call → compile fails') do
  ARITY_FC['status'] != 'ok'
end

check('P12-FC-04: arity mismatch → OOF-TY0 in diagnostics') do
  diags = ARITY_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0')
end

# FC-03: self-recursion via literal callee → OOF-TY0
check('P12-FC-05: self-recursion via literal callee → compile fails') do
  SELF_REC_FC['status'] != 'ok'
end

check('P12-FC-06: self-recursion → OOF-TY0 in diagnostics') do
  diags = SELF_REC_FC['diagnostics'] || []
  err_out = diags.map { |d| d.to_s }.join(' ')
  err_out.include?('OOF-TY0')
end

# FC-04: correct inline dispatch → compiles + resolves to declared type
check('P12-FC-07: correct inline literal dispatch compiles ok') do
  CORRECT_FC['status'] == 'ok'
end

check('P12-FC-08: EchoDispatcher.response → SimpleResponse in inline fixture') do
  sir_node_type(CORRECT_SIR, 'EchoDispatcher', 'response') == 'SimpleResponse'
end

# ── P12-REG ───────────────────────────────────────────────────────────────────
section 'P12-REG: P11 and P9 regressions green'

check('P12-REG-01: P11 fixture (call_contract_resolution.ig) still compiles ok') do
  P11_RESULT['status'] == 'ok'
end

check('P12-REG-02: P11 fixture has no diagnostics') do
  (P11_RESULT['diagnostics'] || []).empty?
end

check('P12-REG-03: P11 CallerDouble.doubled compute → Integer') do
  sir_node_type(P11_SIR, 'CallerDouble', 'doubled') == 'Integer'
end

check('P12-REG-04: P9 fixture (multi_contract_caller.ig) still compiles ok') do
  P9_RESULT['status'] == 'ok'
end

check('P12-REG-05: P9 fixture has no diagnostics') do
  (P9_RESULT['diagnostics'] || []).empty?
end

check('P12-REG-06: P9 SelfRecurseDyn contract still present (Tier 2 pattern)') do
  contracts = P9_RESULT['contracts'] || []
  contracts.include?('SelfRecurseDyn')
end

# ── P12-CLOSED ───────────────────────────────────────────────────────────────
section 'P12-CLOSED: closed-surface scan'

check('P12-CLOSED-01: no real socket usage (' + 'TCP' + 'Socket / ' + 'UDP' + 'Socket)') do
  !SOURCE.include?('TCP' + 'Socket') && !SOURCE.include?('UDP' + 'Socket')
end

check('P12-CLOSED-02: no ' + 'Net::' + 'HTTP or require net/http') do
  !SOURCE.include?('Net::' + 'HTTP') && !SOURCE.include?("require 'net/" + "http'")
end

check('P12-CLOSED-03: no require socket') do
  !SOURCE.include?("require 'sock" + "et'")
end

check('P12-CLOSED-04: no CR-type semantics claim opened') do
  # split to avoid self-match: concatenation evaluates to CR-type string at runtime
  !SOURCE.include?('Contract' + 'Ref' + ' type') && !SOURCE.include?('Contract' + 'Ref' + ' sem')
end

check('P12-CLOSED-05: no compat/prod-runtime claim') do
  !SOURCE.include?('Rack-comp' + 'atible') && !SOURCE.include?('prod' + 'uction runtime') &&
    !SOURCE.include?('stab' + 'le public')
end

# ── P12-GAP ───────────────────────────────────────────────────────────────────
section 'P12-GAP: gap packet valid'

check('P12-GAP-01: RecordLiteral nominal checking now implemented in P13') do
  # P12 documented the gap: RecordLiteral → Unknown (structural→named matching deferred).
  # P13 closed this gap: check_record_literal_shape validates fields and upgrades to named type.
  # Verify P13 upgrade is in effect: handler response nodes now resolve to RackResponse.
  sir_node_type(MAIN_SIR, 'GetRootHandler', 'response') == 'RackResponse' &&
    sir_node_type(MAIN_SIR, 'NotFoundHandler', 'response') == 'RackResponse'
end

check('P12-GAP-02: TypeChecker proof only — VM record construction not verified in P12') do
  # No VM run for record-returning contract in this proof;
  # runtime record construction (field order, serialization) is a P13+ work item
  true  # acknowledged gap; no false claim made
end

check('P12-GAP-03: headers deferred — RackResponse has status+body only') do
  # type RackResponse { status: Integer, body: String } — no headers field
  # Map/Collection semantics for header pairs require stronger type support (P13)
  c = (MAIN_SIR['contracts'] || []).find { |c| c['contract_name'] == 'GetRootHandler' }
  n = (c&.dig('nodes') || []).find { |n| n['name'] == 'response' }
  fields = n&.dig('expr', 'fields') || {}
  fields.key?('status') && fields.key?('body') && !fields.key?('headers')
end

check('P12-GAP-04: multi-output callee dispatch not opened in P12') do
  # All handler contracts have exactly 1 output declaration (single-output only)
  contracts = MAIN_SIR['contracts'] || []
  contracts.all? { |c| (c['outputs'] || []).size == 1 }
end

check('P12-GAP-05: authority disclaimer present; no canonization claim') do
  # split strings to avoid self-match; 'can'+'on' evaluates to 'canon' at runtime
  SOURCE.include?('lab-only') && SOURCE.include?('no ' + 'can' + 'on claim') &&
    !SOURCE.include?('call_contract is ' + 'can' + 'on') && !SOURCE.include?('can' + 'on API')
end

# ── summary ───────────────────────────────────────────────────────────────────

puts "\n" + "═" * 60
total  = PASS_COUNT[0] + FAIL_COUNT[0]
puts "P12 RESULT: #{PASS_COUNT[0]}/#{total} PASS  |  #{FAIL_COUNT[0]} FAIL"
puts "═" * 60

exit(FAIL_COUNT[0] == 0 ? 0 : 1)
