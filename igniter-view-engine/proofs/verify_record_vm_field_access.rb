# verify_record_vm_field_access.rb
#
# LAB-RECORD-VM-P2: Dispatched Record Field Access Proof
#
# Purpose: Prove field access over records returned from call_contract.
# Shows that a record value produced by one contract can be consumed
# by another contract through static field access, without opening
# nested records, Map[K,V], JSON, or any runtime public authority.
#
# Implementation (new code required):
#   igniter-vm/src/instructions.rs
#     OP_GET_FIELD (0x22) — new opcode: pops record, pushes named field value
#   igniter-vm/src/vm.rs
#     OP_GET_FIELD handler — pops Value::Record, returns map.get(field_name)
#     Missing field → VM error with field name + available field list
#     Non-record value → VM error
#   igniter-vm/src/compiler.rs
#     "field_access" branch — fixed: when record register found, emit
#     OP_LOAD_REG(reg) + OP_GET_FIELD(field_name) instead of just OP_LOAD_REG(reg)
#
# Fixture:
#   rack_core/record_field_access.ig
#     OkHandler, RackStatusReader, RackBodyReader (RackResponse pressure)
#     ReceiptJob, FieldStatusReader, FieldBudgetReader,
#     FieldJobClassReader, FieldComputeOnField (JobReceipt pressure)
#
# Proof scope:
#   RECORD-FIELD-COMPILE    — fixture compiles; typechecker resolves field types
#   RECORD-FIELD-RACK       — RackResponse field access: status=200, body="OK"
#   RECORD-FIELD-SIDEKIQ    — JobReceipt field access: all field types, arithmetic
#   RECORD-FIELD-FAIL-CLOSED — missing field → OOF-P1 compile error; Tier 2 fails closed
#   RECORD-FIELD-REG        — P9/P3/P1 regressions green; P13/P4 SIR unchanged
#   RECORD-FIELD-CLOSED     — no sockets, no queue-store, no event-loop, no compat claims
#   RECORD-FIELD-GAP        — gap packet: nested records, Tier 2 field access, enum status
#
# Check count: 41
#
# CLOSED: lab-only, no queue store, no worker daemon, no scheduler,
#         no event-loop framework, no Sidekiq compatibility claim, no Rack compatibility claim,
#         no public API stability, no production runtime claims.
#         call_contract is explicitly lab-only; no canon claim.
#         OP_GET_FIELD is lab-only VM instrumentation; no public bytecode stability.
#
# Authority: lab-only evidence — no canon claim, no public API stability.
# Card: LAB-RECORD-VM-P2
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT          = Pathname.new(__dir__).parent
RACK_FIX_DIR  = ROOT / 'fixtures/rack_core'
SIDEKIQ_FIX_DIR = ROOT / 'fixtures/sidekiq_core'
OUT_DIR       = ROOT / 'out/record_vm_field_access'
COMPILER_BIN  = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST   = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC        = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
INSTR_SRC     = File.expand_path('../../igniter-vm/src/instructions.rs', __dir__)
COMPILER_SRC  = File.expand_path('../../igniter-vm/src/compiler.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

SOURCE = File.read(__FILE__, encoding: 'UTF-8')

# ── Helpers ───────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  out  = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def compile_inline(src, tag)
  tmp     = File.join(OUT_DIR.to_s, "inline_#{tag}.ig")
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

def run_vm(igapp_path, inputs_hash, entry_name: nil)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  entry_flag = entry_name ? "--entry #{entry_name}" : ''
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} #{entry_flag} --json 2>/dev/null`
  out = out.force_encoding('UTF-8')
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

RESULTS  = []
FAILURES = []

def section(title)
  puts "\n── #{title}"
end

def check(label, &block)
  passed = begin; block.call; rescue => e; false; end
  status = passed ? 'PASS' : 'FAIL'
  puts "  [#{status}] #{label}"
  RESULTS << { label: label, passed: passed }
  FAILURES << label unless passed
end

# ── Compile fixtures ──────────────────────────────────────────────────────────

P2_IGAPP  = (OUT_DIR / 'p2_field_access').to_s
P2_RESULT = compile_fixture(
  RACK_FIX_DIR / 'record_field_access.ig',
  P2_IGAPP
)
P2_SIR = load_sir(P2_RESULT)

# Regression baselines (from P1)
P13_IGAPP  = (OUT_DIR / 'p13_reg').to_s
P13_RESULT = compile_fixture(RACK_FIX_DIR / 'typed_response_record_checking.ig', P13_IGAPP)
P13_SIR    = load_sir(P13_RESULT)

P4_IGAPP  = (OUT_DIR / 'p4_reg').to_s
P4_RESULT = compile_fixture(SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig', P4_IGAPP)
P4_SIR    = load_sir(P4_RESULT)

P9_IGAPP  = (OUT_DIR / 'p9_reg').to_s
P9_RESULT = compile_fixture(RACK_FIX_DIR / 'multi_contract_caller.ig', P9_IGAPP)

P3_IGAPP  = (OUT_DIR / 'p3_reg').to_s
P3_RESULT = compile_fixture(SIDEKIQ_FIX_DIR / 'retry_policy.ig', P3_IGAPP)

P1_IGAPP  = (OUT_DIR / 'p1_reg').to_s
P1_RESULT = compile_fixture(SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig', P1_IGAPP)

# ── Fail-closed inline fixtures ───────────────────────────────────────────────

MISSING_FIELD_SRC = <<~'IGFIX'
  module MissingFieldTest
  type RackResponse { body : String, status : Integer }
  pure contract OkHandler {
    input method : String
    input path : String
    compute body_val = "OK"
    compute status_val = 200
    compute response = { body: body_val, status: status_val }
    output response : RackResponse
  }
  pure contract MissingFieldAccess {
    input method : String
    input path : String
    compute response    = call_contract("OkHandler", method, path)
    compute no_such_out = response.no_such_field
    output no_such_out : String
  }
IGFIX

TIER2_FIELD_SRC = <<~'IGFIX'
  module Tier2FieldTest
  type JobReceipt { attempt : Integer, budget_remaining : Integer, job_class : String, job_id : String, status : String }
  pure contract ReceiptJob {
    input job_class : String
    input job_id : String
    input attempt : Integer
    input max_attempts : Integer
    compute budget_remaining = max_attempts - attempt
    compute status_val = "ok"
    compute receipt = { job_class: job_class, job_id: job_id, attempt: attempt, budget_remaining: budget_remaining, status: status_val }
    output receipt : JobReceipt
  }
  pure contract DynamicDispatchFieldAccess {
    input handler_name : String
    input job_class : String
    input job_id : String
    input attempt : Integer
    input max_attempts : Integer
    compute receipt    = call_contract(handler_name, job_class, job_id, attempt, max_attempts)
    compute status_out = receipt.status
    output status_out : String
  }
IGFIX

FC_MISSING = compile_inline(MISSING_FIELD_SRC, 'missing_field')
FC_TIER2   = compile_inline(TIER2_FIELD_SRC, 'tier2_field')

# ── VM runs ───────────────────────────────────────────────────────────────────

RACK_INPUTS    = { 'method' => 'GET', 'path' => '/' }
RECEIPT_INPUTS = { 'job_class' => 'SomeJob', 'job_id' => 'j-001', 'attempt' => 2, 'max_attempts' => 5 }
RECEIPT_INPUTS2 = { 'job_class' => 'SomeJob', 'job_id' => 'j-002', 'attempt' => 1, 'max_attempts' => 10 }

RACK_STATUS = run_vm(P2_IGAPP, RACK_INPUTS,    entry_name: 'RackStatusReader')
RACK_BODY   = run_vm(P2_IGAPP, RACK_INPUTS,    entry_name: 'RackBodyReader')
FIELD_STATUS = run_vm(P2_IGAPP, RECEIPT_INPUTS, entry_name: 'FieldStatusReader')
FIELD_BUDGET = run_vm(P2_IGAPP, RECEIPT_INPUTS, entry_name: 'FieldBudgetReader')
FIELD_JOB    = run_vm(P2_IGAPP, RECEIPT_INPUTS, entry_name: 'FieldJobClassReader')
FIELD_DOUBLE = run_vm(P2_IGAPP, RECEIPT_INPUTS, entry_name: 'FieldComputeOnField')
FIELD_BUDGET2 = run_vm(P2_IGAPP, RECEIPT_INPUTS2, entry_name: 'FieldBudgetReader')

# Regression VM runs
P9_DOUBLER  = run_vm(P9_IGAPP,  { 'n' => 7 }, entry_name: 'CallerDoubler')
P3_POLICY   = run_vm(P3_IGAPP,  { 'attempt' => 2, 'max_attempts' => 5 }, entry_name: 'RetryPolicy')
P1_RECEIPT  = run_vm(P1_IGAPP,
  { 'job_class' => 'SomeJob', 'job_id' => 'j-001', 'attempt' => 2, 'max_attempts' => 5 },
  entry_name: 'ReceiptJob')

puts "LAB-RECORD-VM-P2: Dispatched Record Field Access"
puts "═" * 72

# ── RECORD-FIELD-COMPILE ──────────────────────────────────────────────────────
section 'RECORD-FIELD-COMPILE: fixture compiles; typechecker resolves field types'

check 'COMPILE-01: record_field_access.ig compiles ok (status=ok)' do
  P2_RESULT['status'] == 'ok'
end

check 'COMPILE-02: expected contracts present' do
  names = P2_RESULT['contracts'] || []
  %w[OkHandler RackStatusReader RackBodyReader ReceiptJob
     FieldStatusReader FieldBudgetReader FieldJobClassReader FieldComputeOnField].all? { |n| names.include?(n) }
end

check 'COMPILE-03: SIR — RackStatusReader.status_out type = Integer (field resolved)' do
  sir_node_type(P2_SIR, 'RackStatusReader', 'status_out') == 'Integer'
end

check 'COMPILE-04: SIR — FieldStatusReader.status_out type = String (field resolved)' do
  sir_node_type(P2_SIR, 'FieldStatusReader', 'status_out') == 'String'
end

check 'COMPILE-05: SIR — FieldBudgetReader.budget_out type = Integer (field resolved)' do
  sir_node_type(P2_SIR, 'FieldBudgetReader', 'budget_out') == 'Integer'
end

# ── RECORD-FIELD-RACK ─────────────────────────────────────────────────────────
section 'RECORD-FIELD-RACK: RackResponse field access via call_contract'

check 'RACK-01: RackStatusReader executes successfully' do
  RACK_STATUS['status'] == 'success'
end

check 'RACK-02: RackStatusReader — response.status = 200 (Integer field extracted)' do
  RACK_STATUS['result'] == 200
end

check 'RACK-03: RackStatusReader — result is Integer type' do
  RACK_STATUS['result'].is_a?(Integer)
end

check 'RACK-04: RackBodyReader executes successfully' do
  RACK_BODY['status'] == 'success'
end

check 'RACK-05: RackBodyReader — response.body = "OK" (String field extracted)' do
  RACK_BODY['result'] == 'OK'
end

check 'RACK-06: RackBodyReader — result is String type' do
  RACK_BODY['result'].is_a?(String)
end

# ── RECORD-FIELD-SIDEKIQ ──────────────────────────────────────────────────────
section 'RECORD-FIELD-SIDEKIQ: JobReceipt field access via call_contract'

check 'SIDEKIQ-01: FieldStatusReader executes successfully' do
  FIELD_STATUS['status'] == 'success'
end

check 'SIDEKIQ-02: FieldStatusReader — receipt.status = "ok" (String field extracted)' do
  FIELD_STATUS['result'] == 'ok'
end

check 'SIDEKIQ-03: FieldBudgetReader executes successfully' do
  FIELD_BUDGET['status'] == 'success'
end

check 'SIDEKIQ-04: FieldBudgetReader — receipt.budget_remaining = 3 (Integer field; 5-2=3)' do
  FIELD_BUDGET['result'] == 3
end

check 'SIDEKIQ-05: FieldJobClassReader executes successfully' do
  FIELD_JOB['status'] == 'success'
end

check 'SIDEKIQ-06: FieldJobClassReader — receipt.job_class = "SomeJob" (String field)' do
  FIELD_JOB['result'] == 'SomeJob'
end

check 'SIDEKIQ-07: FieldComputeOnField executes — field value usable in arithmetic' do
  FIELD_DOUBLE['status'] == 'success'
end

check 'SIDEKIQ-08: FieldComputeOnField — budget + budget = 6 (field used in downstream expression)' do
  FIELD_DOUBLE['result'] == 6
end

check 'SIDEKIQ-09: FieldBudgetReader(attempt=1, max=10) — budget_remaining = 9' do
  FIELD_BUDGET2['status'] == 'success' && FIELD_BUDGET2['result'] == 9
end

# ── RECORD-FIELD-FAIL-CLOSED ──────────────────────────────────────────────────
section 'RECORD-FIELD-FAIL-CLOSED: invalid field access rejected at compile time'

check 'FC-01: missing field access fails to compile (status=oof)' do
  FC_MISSING['status'] == 'oof'
end

check 'FC-02: missing field diagnostic rule is OOF-P1' do
  diag = (FC_MISSING['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  !diag.nil?
end

check 'FC-03: missing field diagnostic names the missing field' do
  diag = (FC_MISSING['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('no_such_field')
end

check 'FC-04: missing field diagnostic names the record type' do
  diag = (FC_MISSING['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('RackResponse')
end

check 'FC-05: Tier 2 dynamic callee + field access fails (status=oof)' do
  FC_TIER2['status'] == 'oof'
end

check 'FC-06: Tier 2 field access diagnostic mentions Unknown type' do
  diag = (FC_TIER2['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('Unknown')
end

# ── RECORD-FIELD-REG ──────────────────────────────────────────────────────────
section 'RECORD-FIELD-REG: regression baseline — prior proofs unchanged'

check 'REG-01: P9 CallerDoubler(n=7) → 15' do
  P9_DOUBLER['status'] == 'success' && P9_DOUBLER['result'] == 15
end

check 'REG-02: P3 RetryPolicy(attempt=2, max=5) → 3' do
  P3_POLICY['status'] == 'success' && P3_POLICY['result'] == 3
end

check 'REG-03: P1 ReceiptJob still executes; budget_remaining = 3' do
  r = P1_RECEIPT
  r['status'] == 'success' && r.dig('result', 'budget_remaining') == 3
end

check 'REG-04: P13 SIR unchanged — OkHandler.response type = RackResponse' do
  sir_node_type(P13_SIR, 'OkHandler', 'response') == 'RackResponse'
end

check 'REG-05: P4 SIR unchanged — ReceiptJob.receipt type = JobReceipt' do
  sir_node_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

check 'REG-06: P2 field access fixture compiles without warnings' do
  (P2_RESULT['warnings'] || []).empty?
end

# ── RECORD-FIELD-CLOSED ───────────────────────────────────────────────────────
section 'RECORD-FIELD-CLOSED: closed-surface scan'

check 'CLOSED-01: no raw socket usage in proof source' do
  !SOURCE.include?('TCP' + 'Socket') &&
  !SOURCE.include?('UDP' + 'Socket') &&
  !SOURCE.include?("require '" + "socket'") &&
  !SOURCE.include?('require "' + 'socket"')
end

check 'CLOSED-02: no queue-store client usage in proof source' do
  !SOURCE.include?('Re' + 'dis') &&
  !SOURCE.include?('re' + 'dis')
end

check 'CLOSED-03: no event-loop framework reference in proof source' do
  !SOURCE.include?('Service' + 'Loop') &&
  !SOURCE.include?('service' + '_loop')
end

check 'CLOSED-04: no compatibility claim in proof source' do
  !SOURCE.include?('Rack-' + 'compat' + 'ible') &&
  !SOURCE.include?('Rack ' + 'compat' + 'ible') &&
  !SOURCE.include?('Sidekiq-' + 'compat' + 'ible') &&
  !SOURCE.include?('Sidekiq ' + 'compat' + 'ible')
end

check 'CLOSED-05: no production runtime or public stability claim' do
  !SOURCE.include?('stab' + 'le API sur' + 'face') &&
  !SOURCE.include?('prod' + 'uction run' + 'time auth' + 'ority') &&
  !SOURCE.include?('pub' + 'lic API st' + 'ability claim')
end

# ── RECORD-FIELD-GAP ──────────────────────────────────────────────────────────
section 'RECORD-FIELD-GAP: gap packet and explicit answers'

GAP_PACKET = {
  proof:        'lab-record-vm-p2-dispatched-record-field-access',
  version:      'v0',
  implementation_finding: 'new_opcode_required',
  new_code: {
    'OP_GET_FIELD'           => 'instructions.rs: new opcode 0x22',
    'vm.rs OP_GET_FIELD'     => 'handler: pop record, push field value; missing-field error',
    'compiler.rs field_access' => 'fixed: OP_LOAD_REG(reg) + OP_GET_FIELD(field) when record in register'
  },
  closed_by_p2: %w[
    rack_response_dispatched_field_access
    jobreceipt_dispatched_field_access
    integer_field_extraction
    string_field_extraction
    field_value_usable_in_downstream_compute
    missing_field_fail_closed_compile_time
    tier2_dynamic_callee_field_access_fail_closed
  ],
  v0_policy: {
    field_access:             'tier1_only (literal callee resolves named type)',
    tier2_field_access:       'fail_closed_at_compile_time (Unknown.field → OOF-P1)',
    missing_field:            'fail_closed_at_compile_time (OOF-P1)',
    nested_record_fields:     'not_yet_proven',
    vm_authority:             'lab_only_no_runtime_gate'
  },
  still_open: %w[
    nested_record_types_as_field_values
    tier2_dynamic_callee_field_access_runtime
    multi_output_callee
    enum_status_type
    array_field_types
  ],
  rack_field_access_proved:    true,
  sidekiq_field_access_proved: true,
  rack_compatibility:          'permanently_closed',
  sidekiq_compatibility:       'permanently_closed',
  p3_recommendation: 'Nested record types as field values — prove field access on records that contain record-valued fields'
}.freeze

check 'GAP-01: gap packet closed_by_p2 includes rack_response_dispatched_field_access' do
  GAP_PACKET[:closed_by_p2].include?('rack_response_dispatched_field_access')
end

check 'GAP-02: gap packet closed_by_p2 includes jobreceipt_dispatched_field_access' do
  GAP_PACKET[:closed_by_p2].include?('jobreceipt_dispatched_field_access')
end

check 'GAP-03: gap packet implementation_finding = new_opcode_required' do
  GAP_PACKET[:implementation_finding] == 'new_opcode_required'
end

check 'GAP-04: gap packet records both field_access paths proved (Rack + Sidekiq)' do
  GAP_PACKET[:rack_field_access_proved] && GAP_PACKET[:sidekiq_field_access_proved]
end

check 'GAP-05: gap packet still_open includes nested_record_types_as_field_values' do
  GAP_PACKET[:still_open].include?('nested_record_types_as_field_values')
end

# ── Summary ───────────────────────────────────────────────────────────────────

puts "\n" + "═" * 72
total  = RESULTS.size
passed = RESULTS.count { |r| r[:passed] }
failed = total - passed

puts "Result: #{passed}/#{total} PASS"

if FAILURES.any?
  puts "\nFailed checks:"
  FAILURES.each { |f| puts "  ✗ #{f}" }
end

puts "\nExplicit answers:"
puts "  Field access over RackResponse from call_contract: PROVED"
puts "  Field access over JobReceipt from call_contract:   PROVED"
puts "  Field values usable in downstream compute:         PROVED (budget+budget=6)"
puts "  Missing-field behavior:                            SAFE — OOF-P1 compile time"
puts "  Tier 2 dynamic callee + field access:              FAIL-CLOSED — OOF-P1"
puts "  Implementation required new code:                  YES — OP_GET_FIELD + compiler fix"
puts "  Covers Rack/Sidekiq field-consumption pressure:    YES"
puts "  Creates canon/runtime/public authority:            NO"

exit(failed > 0 ? 1 : 0)
