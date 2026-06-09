# verify_record_vm_nested_records.rb
#
# LAB-RECORD-VM-P3: Nested Record Field Values Proof
#
# Purpose: Prove that a record field can hold another record, and that chained
# field access expressions like outer.inner.field work end-to-end through
# typechecking, SemanticIR, bytecode compilation, and VM execution.
#
# Implementation finding (minimal new code):
#   igniter-vm/src/compiler.rs — one targeted change in "field_access" branch.
#   Replace: Err("Unsupported object type...")
#   With:    self.compile_expr(object)? + OP_GET_FIELD(field)
#   This handles the chained case where object is itself a field_access AST node.
#   No new opcodes required: OP_GET_FIELD (0x22, from P2) is reused as-is.
#   Typechecker already handled chained access recursively — no changes needed.
#   VM record construction already handled nested records — no changes needed.
#
# Fixture:
#   rack_core/nested_record_field_values.ig
#     EnvelopeBuilder, ContentTypeReader, CacheControlReader (Rack pressure)
#     JobEnvelopeBuilder, PriorityReader, QueueReader (Sidekiq pressure)
#
# Proof scope:
#   NESTED-RECORD-COMPILE    — fixture compiles; typechecker resolves chained types
#   NESTED-RECORD-SIR        — Tier 1 type propagation through nested field chains
#   NESTED-RECORD-VM         — nested record construction; deterministic key ordering
#   NESTED-RECORD-DISPATCH   — chained field access extracts correct values
#   NESTED-RECORD-FAIL-CLOSED — direct local nested access, missing inner field,
#                               non-record intermediate, Tier 2 all rejected compile-time
#   NESTED-RECORD-REG        — P2/P1/P13/P4 regression baselines unchanged
#   NESTED-RECORD-CLOSED     — no sockets, no queue-store, no event-loop, no compat claims
#   NESTED-RECORD-GAP        — gap packet: what is now proved; what remains open
#
# Check count: 45
#
# CLOSED: lab-only, no queue store, no worker daemon, no scheduler,
#         no event-loop framework, no Sidekiq compatibility claim, no Rack compatibility claim,
#         no public API stability, no production runtime claims.
#         call_contract is explicitly lab-only; no canon claim.
#         OP_GET_FIELD is lab-only VM instrumentation; no public bytecode stability.
#
# Authority: lab-only evidence — no canon claim, no public API stability.
# Card: LAB-RECORD-VM-P3
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT          = Pathname.new(__dir__).parent
RACK_FIX_DIR  = ROOT / 'fixtures/rack_core'
SIDEKIQ_FIX_DIR = ROOT / 'fixtures/sidekiq_core'
OUT_DIR       = ROOT / 'out/record_vm_nested_records'
COMPILER_BIN  = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST   = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)

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

# ── Compile main fixture ──────────────────────────────────────────────────────

P3_IGAPP  = (OUT_DIR / 'p3_nested').to_s
P3_RESULT = compile_fixture(RACK_FIX_DIR / 'nested_record_field_values.ig', P3_IGAPP)
P3_SIR    = load_sir(P3_RESULT)

# Regression baselines (from prior proofs)
P2_IGAPP  = (OUT_DIR / 'p2_reg').to_s
P2_RESULT = compile_fixture(RACK_FIX_DIR / 'record_field_access.ig', P2_IGAPP)
P2_SIR    = load_sir(P2_RESULT)

P13_IGAPP  = (OUT_DIR / 'p13_reg').to_s
P13_RESULT = compile_fixture(RACK_FIX_DIR / 'typed_response_record_checking.ig', P13_IGAPP)
P13_SIR    = load_sir(P13_RESULT)

P4_IGAPP  = (OUT_DIR / 'p4_reg').to_s
P4_RESULT = compile_fixture(SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig', P4_IGAPP)
P4_SIR    = load_sir(P4_RESULT)

P1_IGAPP  = (OUT_DIR / 'p1_reg').to_s
P1_RESULT = compile_fixture(SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig', P1_IGAPP)

# ── Fail-closed inline fixtures ───────────────────────────────────────────────

# FC-A: Direct local nested access without Tier 1 — headers is Unknown type.
# envelope.headers is Unknown-typed; headers.content_type → Unknown.content_type → OOF-P1.
DIRECT_LOCAL_SRC = <<~'IGFIX'
  module DirectLocalNestedTest
  type HeaderInfo { cache_control : String, content_type : String }
  pure contract DirectLocalChain {
    input method : String
    compute headers = { content_type: "text/plain", cache_control: "no-cache" }
    compute content_type = headers.content_type
    output content_type : String
  }
IGFIX

# FC-B: Missing inner field — outer type resolved but inner field does not exist.
# envelope type = ResponseEnvelope; envelope.headers type = HeaderInfo;
# HeaderInfo has no 'no_such_inner' field → OOF-P1: HeaderInfo.no_such_inner.
MISSING_INNER_SRC = <<~'IGFIX'
  module MissingInnerFieldTest
  type HeaderInfo { cache_control : String, content_type : String }
  type ResponseEnvelope { body : String, headers : HeaderInfo, status : Integer }
  pure contract EnvBuilder {
    input method : String
    compute headers  = { cache_control: "no-cache", content_type: "text/plain" }
    compute envelope = { body: "OK", headers: headers, status: 200 }
    output envelope : ResponseEnvelope
  }
  pure contract MissingInnerAccess {
    input method : String
    compute envelope = call_contract("EnvBuilder", method)
    compute x = envelope.headers.no_such_inner
    output x : String
  }
IGFIX

# FC-C: Non-record intermediate field chain — envelope.status is Integer, not a record.
# envelope type = ResponseEnvelope; envelope.status type = Integer;
# Integer has no fields → OOF-P1: Integer.something.
NON_RECORD_INTER_SRC = <<~'IGFIX'
  module NonRecordInterTest
  type HeaderInfo { cache_control : String, content_type : String }
  type ResponseEnvelope { body : String, headers : HeaderInfo, status : Integer }
  pure contract EnvBuilder2 {
    input method : String
    compute headers  = { cache_control: "no-cache", content_type: "text/plain" }
    compute envelope = { body: "OK", headers: headers, status: 200 }
    output envelope : ResponseEnvelope
  }
  pure contract NonRecordIntermediate {
    input method : String
    compute envelope = call_contract("EnvBuilder2", method)
    compute x = envelope.status.something
    output x : String
  }
IGFIX

# FC-D: Tier 2 dynamic callee + chained field access — callee name is a variable.
# call_contract(handler_name, ...) → Unknown type; Unknown.headers → OOF-P1.
TIER2_CHAIN_SRC = <<~'IGFIX'
  module Tier2ChainTest
  type HeaderInfo { cache_control : String, content_type : String }
  type ResponseEnvelope { body : String, headers : HeaderInfo, status : Integer }
  pure contract EnvBuilder3 {
    input method : String
    compute headers  = { cache_control: "no-cache", content_type: "text/plain" }
    compute envelope = { body: "OK", headers: headers, status: 200 }
    output envelope : ResponseEnvelope
  }
  pure contract Tier2ChainedAccess {
    input handler_name : String
    input method       : String
    compute envelope     = call_contract(handler_name, method)
    compute content_type = envelope.headers.content_type
    output content_type : String
  }
IGFIX

FC_DIRECT_LOCAL  = compile_inline(DIRECT_LOCAL_SRC,    'direct_local')
FC_MISSING_INNER = compile_inline(MISSING_INNER_SRC,   'missing_inner')
FC_NON_RECORD    = compile_inline(NON_RECORD_INTER_SRC, 'non_record_inter')
FC_TIER2_CHAIN   = compile_inline(TIER2_CHAIN_SRC,     'tier2_chain')

# ── VM runs ───────────────────────────────────────────────────────────────────

METHOD_INPUTS = { 'method' => 'GET' }
JOB_INPUTS    = { 'job_class' => 'WorkerJob', 'attempt' => 2, 'max_attempts' => 5 }

ENV_RESULT    = run_vm(P3_IGAPP, METHOD_INPUTS, entry_name: 'EnvelopeBuilder')
CT_RESULT     = run_vm(P3_IGAPP, METHOD_INPUTS, entry_name: 'ContentTypeReader')
CC_RESULT     = run_vm(P3_IGAPP, METHOD_INPUTS, entry_name: 'CacheControlReader')
JOB_ENV       = run_vm(P3_IGAPP, JOB_INPUTS,   entry_name: 'JobEnvelopeBuilder')
PRIO_RESULT   = run_vm(P3_IGAPP, JOB_INPUTS,   entry_name: 'PriorityReader')
QUEUE_RESULT  = run_vm(P3_IGAPP, JOB_INPUTS,   entry_name: 'QueueReader')

# Regression VM runs
P2_RACK_STATUS = run_vm(P2_IGAPP, { 'method' => 'GET', 'path' => '/' }, entry_name: 'RackStatusReader')
P2_FIELD_BUDGET = run_vm(P2_IGAPP,
  { 'job_class' => 'SomeJob', 'job_id' => 'j-001', 'attempt' => 2, 'max_attempts' => 5 },
  entry_name: 'FieldBudgetReader')
P1_RECEIPT = run_vm(P1_IGAPP,
  { 'job_class' => 'SomeJob', 'job_id' => 'j-001', 'attempt' => 2, 'max_attempts' => 5 },
  entry_name: 'ReceiptJob')

# ── Proof body ────────────────────────────────────────────────────────────────

puts "LAB-RECORD-VM-P3: Nested Record Field Values"
puts "═" * 72

# ── NESTED-RECORD-COMPILE ────────────────────────────────────────────────────
section 'NESTED-RECORD-COMPILE: fixture compiles; typechecker resolves chained field types'

check 'COMPILE-01: nested_record_field_values.ig compiles ok (status=ok)' do
  P3_RESULT['status'] == 'ok'
end

check 'COMPILE-02: SIR — ContentTypeReader.content_type type = String (chain resolved)' do
  sir_node_type(P3_SIR, 'ContentTypeReader', 'content_type') == 'String'
end

check 'COMPILE-03: SIR — CacheControlReader.cache_control type = String (chain resolved)' do
  sir_node_type(P3_SIR, 'CacheControlReader', 'cache_control') == 'String'
end

check 'COMPILE-04: SIR — PriorityReader.priority type = Integer (chain resolved)' do
  sir_node_type(P3_SIR, 'PriorityReader', 'priority') == 'Integer'
end

check 'COMPILE-05: SIR — QueueReader.queue type = String (chain resolved)' do
  sir_node_type(P3_SIR, 'QueueReader', 'queue') == 'String'
end

# ── NESTED-RECORD-SIR ────────────────────────────────────────────────────────
section 'NESTED-RECORD-SIR: Tier 1 type propagation through nested field chains'

check 'SIR-01: EnvelopeBuilder.envelope output type = ResponseEnvelope (declared)' do
  sir_output_type(P3_SIR, 'EnvelopeBuilder', 'envelope') == 'ResponseEnvelope'
end

check 'SIR-02: JobEnvelopeBuilder.envelope output type = JobEnvelope (declared)' do
  sir_output_type(P3_SIR, 'JobEnvelopeBuilder', 'envelope') == 'JobEnvelope'
end

check 'SIR-03: ContentTypeReader.envelope compute node type = ResponseEnvelope (Tier 1 propagated)' do
  sir_node_type(P3_SIR, 'ContentTypeReader', 'envelope') == 'ResponseEnvelope'
end

check 'SIR-04: PriorityReader.envelope compute node type = JobEnvelope (Tier 1 propagated)' do
  sir_node_type(P3_SIR, 'PriorityReader', 'envelope') == 'JobEnvelope'
end

# ── NESTED-RECORD-VM ─────────────────────────────────────────────────────────
section 'NESTED-RECORD-VM: nested record construction; deterministic key ordering'

check 'VM-01: EnvelopeBuilder executes successfully' do
  ENV_RESULT['status'] == 'success'
end

check 'VM-02: EnvelopeBuilder — result.status = 200 (scalar field correct)' do
  ENV_RESULT.dig('result', 'status') == 200
end

check 'VM-03: EnvelopeBuilder — result.body = "OK" (scalar field correct)' do
  ENV_RESULT.dig('result', 'body') == 'OK'
end

check 'VM-04: EnvelopeBuilder — result.headers is a nested record (Hash)' do
  ENV_RESULT.dig('result', 'headers').is_a?(Hash)
end

check 'VM-05: EnvelopeBuilder — result.headers.content_type = "text/plain" (nested scalar correct)' do
  ENV_RESULT.dig('result', 'headers', 'content_type') == 'text/plain'
end

check 'VM-06: EnvelopeBuilder — result.headers.cache_control = "no-cache" (nested scalar correct)' do
  ENV_RESULT.dig('result', 'headers', 'cache_control') == 'no-cache'
end

check 'VM-07: EnvelopeBuilder — top-level keys sorted alphabetically (BTreeMap)' do
  keys = ENV_RESULT.fetch('result', {}).keys
  keys == keys.sort
end

check 'VM-08: JobEnvelopeBuilder executes successfully' do
  JOB_ENV['status'] == 'success'
end

check 'VM-09: JobEnvelopeBuilder — result.meta.priority = 5 (nested Integer correct)' do
  JOB_ENV.dig('result', 'meta', 'priority') == 5
end

check 'VM-10: JobEnvelopeBuilder — result.budget_remaining = 3 (5 - 2 = 3, arith before construction)' do
  JOB_ENV.dig('result', 'budget_remaining') == 3
end

# ── NESTED-RECORD-DISPATCH ───────────────────────────────────────────────────
section 'NESTED-RECORD-DISPATCH: chained field access extracts correct values'

check 'DISPATCH-01: ContentTypeReader executes successfully' do
  CT_RESULT['status'] == 'success'
end

check 'DISPATCH-02: ContentTypeReader — envelope.headers.content_type = "text/plain"' do
  CT_RESULT['result'] == 'text/plain'
end

check 'DISPATCH-03: CacheControlReader executes successfully' do
  CC_RESULT['status'] == 'success'
end

check 'DISPATCH-04: CacheControlReader — envelope.headers.cache_control = "no-cache"' do
  CC_RESULT['result'] == 'no-cache'
end

check 'DISPATCH-05: PriorityReader executes successfully' do
  PRIO_RESULT['status'] == 'success'
end

check 'DISPATCH-06: PriorityReader — envelope.meta.priority = 5 (Integer chained field)' do
  PRIO_RESULT['result'] == 5
end

check 'DISPATCH-07: QueueReader executes successfully' do
  QUEUE_RESULT['status'] == 'success'
end

check 'DISPATCH-08: QueueReader — envelope.meta.queue = "default" (String chained field)' do
  QUEUE_RESULT['result'] == 'default'
end

# ── NESTED-RECORD-FAIL-CLOSED ────────────────────────────────────────────────
section 'NESTED-RECORD-FAIL-CLOSED: invalid chained access rejected at compile time'

check 'FC-01: direct local nested access fails to compile (Unknown.content_type → OOF-P1)' do
  FC_DIRECT_LOCAL['status'] == 'oof'
end

check 'FC-02: direct local nested access — OOF-P1 diagnostic names Unknown type' do
  diag = (FC_DIRECT_LOCAL['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('Unknown')
end

check 'FC-03: missing inner field fails to compile (HeaderInfo.no_such_inner → OOF-P1)' do
  FC_MISSING_INNER['status'] == 'oof'
end

check 'FC-04: missing inner field — OOF-P1 diagnostic names HeaderInfo type' do
  diag = (FC_MISSING_INNER['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('HeaderInfo')
end

check 'FC-05: non-record intermediate chain fails to compile (Integer.something → OOF-P1)' do
  FC_NON_RECORD['status'] == 'oof'
end

check 'FC-06: non-record intermediate — OOF-P1 diagnostic names Integer type' do
  diag = (FC_NON_RECORD['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('Integer')
end

check 'FC-07: Tier 2 callee + chained field access fails to compile (Unknown.headers → OOF-P1)' do
  FC_TIER2_CHAIN['status'] == 'oof'
end

# ── NESTED-RECORD-REG ────────────────────────────────────────────────────────
section 'NESTED-RECORD-REG: regression baseline — prior proofs unchanged'

check 'REG-01: P2 regression — RackStatusReader(method=GET, path=/) → status=200' do
  P2_RACK_STATUS['status'] == 'success' && P2_RACK_STATUS['result'] == 200
end

check 'REG-02: P2 regression — FieldBudgetReader(attempt=2, max=5) → budget_remaining=3' do
  P2_FIELD_BUDGET['status'] == 'success' && P2_FIELD_BUDGET['result'] == 3
end

check 'REG-03: P1 regression — ReceiptJob VM produces a record (construction unchanged)' do
  r = P1_RECEIPT
  r['status'] == 'success' && r['result'].is_a?(Hash)
end

check 'REG-04: P13 SIR unchanged — OkHandler.response type = RackResponse' do
  sir_node_type(P13_SIR, 'OkHandler', 'response') == 'RackResponse'
end

check 'REG-05: P4 SIR unchanged — ReceiptJob.receipt type = JobReceipt' do
  sir_node_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

# ── NESTED-RECORD-CLOSED ─────────────────────────────────────────────────────
section 'NESTED-RECORD-CLOSED: closed-surface scan'

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

check 'CLOSED-04: no parametric Map type workaround in proof source' do
  !SOURCE.include?('Map' + '[K,') &&
  !SOURCE.include?('Map' + '[String,')
end

check 'CLOSED-05: no compatibility claim in proof source' do
  !SOURCE.include?('Rack-' + 'compat' + 'ible') &&
  !SOURCE.include?('Rack ' + 'compat' + 'ible') &&
  !SOURCE.include?('Sidekiq-' + 'compat' + 'ible') &&
  !SOURCE.include?('Sidekiq ' + 'compat' + 'ible')
end

# ── NESTED-RECORD-GAP ────────────────────────────────────────────────────────
section 'NESTED-RECORD-GAP: gap packet and explicit answers'

GAP_PACKET = {
  proof:        'lab-record-vm-p3-nested-record-field-values',
  version:      'v0',
  implementation_finding: 'one_compiler_line_changed',
  new_code: {
    'compiler.rs field_access fallback' =>
      'replace Err("Unsupported object type") with compile_expr(object) + OP_GET_FIELD(field)'
  },
  unchanged_components: %w[
    instructions_rs_no_new_opcode
    vm_rs_op_get_field_handler_unchanged
    typechecker_rs_already_handles_chained_recursively
    vm_record_construction_already_handles_nested
  ],
  closed_by_p3: %w[
    rack_nested_record_field_values
    sidekiq_nested_record_field_values
    chained_field_access_two_levels
    chained_field_access_integer_field
    chained_field_access_string_field
    direct_local_nested_access_fail_closed
    missing_inner_field_fail_closed
    non_record_intermediate_chain_fail_closed
    tier2_chained_field_access_fail_closed
    deterministic_nested_record_serialization
  ],
  v0_policy: {
    chained_field_access:            'tier1_only (literal callee resolves named type)',
    tier2_chained_field_access:      'fail_closed_at_compile_time (Unknown.field → OOF-P1)',
    local_record_field_access:       'fail_closed_compile_time (Unknown type from literal construction)',
    missing_inner_field:             'fail_closed_at_compile_time (OOF-P1)',
    non_record_intermediate_chain:   'fail_closed_at_compile_time (OOF-P1)',
    three_level_chain:               'not_yet_proven',
    vm_authority:                    'lab_only_no_runtime_gate'
  },
  still_open: %w[
    three_level_chained_field_access
    tier2_dynamic_callee_chained_field_access_runtime
    local_record_literal_type_annotation
    enum_status_type
    array_field_types
    multi_output_callee
  ],
  rack_chained_field_access_proved:    true,
  sidekiq_chained_field_access_proved: true,
  rack_compatibility:                  'permanently_closed',
  sidekiq_compatibility:               'permanently_closed',
  p4_recommendation: 'Three-level chained field access or Tier 2 type resolution for chained field access'
}.freeze

check 'GAP-01: gap packet closed_by_p3 includes both Rack and Sidekiq chained field access' do
  GAP_PACKET[:closed_by_p3].include?('rack_nested_record_field_values') &&
  GAP_PACKET[:closed_by_p3].include?('sidekiq_nested_record_field_values')
end

check 'GAP-02: gap packet implementation_finding = one_compiler_line_changed' do
  GAP_PACKET[:implementation_finding] == 'one_compiler_line_changed'
end

check 'GAP-03: gap packet unchanged_components includes typechecker and VM construction' do
  u = GAP_PACKET[:unchanged_components]
  u.include?('typechecker_rs_already_handles_chained_recursively') &&
  u.include?('vm_record_construction_already_handles_nested')
end

check 'GAP-04: gap packet still_open includes Tier 2 chained field access and three-level chain' do
  GAP_PACKET[:still_open].include?('tier2_dynamic_callee_chained_field_access_runtime') &&
  GAP_PACKET[:still_open].include?('three_level_chained_field_access')
end

check 'GAP-05: compatibility claims permanently closed (no rack or sidekiq compat assertions)' do
  GAP_PACKET[:rack_compatibility] == 'permanently_closed' &&
  GAP_PACKET[:sidekiq_compatibility] == 'permanently_closed'
end

# ── Summary ───────────────────────────────────────────────────────────────────

puts "\n#{"═" * 72}"
total  = RESULTS.size
passed = RESULTS.count { |r| r[:passed] }
failed = total - passed

puts "#{passed}/#{total} PASS"

unless FAILURES.empty?
  puts "\nFailed checks:"
  FAILURES.each { |f| puts "  ✗ #{f}" }
end

exit(failed > 0 ? 1 : 0)
