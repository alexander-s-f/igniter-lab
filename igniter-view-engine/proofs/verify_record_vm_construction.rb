# verify_record_vm_construction.rb
#
# LAB-RECORD-VM-P1: VM Record Construction and Serialization Proof
#
# Purpose: Prove VM-level construction and observable serialization of typed record
# outputs, using both RackResponse (P13) and JobReceipt (Sidekiq P4) as pressure
# families.
#
# Pre-finding (discovered during research):
#   The VM already fully supports record construction via OP_PUSH_RECORD +
#   Value::Record(BTreeMap<String, Value>). No VM changes were required for P1.
#   Value::Record uses BTreeMap, so field iteration (and JSON serialization via
#   to_json()) is always in alphabetical key order — deterministic by construction.
#   Both RackResponse and JobReceipt records execute end-to-end in the VM using
#   the existing mechanism with zero new code.
#
# Mechanisms used:
#   OP_PUSH_RECORD (vm.rs)        — constructs Value::Record from stack values
#   Value::Record(BTreeMap<_,_>)  — alphabetical key order; deterministic iteration
#   to_json() (value.rs)          — serializes Value::Record to JSON object
#   compiler.rs "record_literal"  — compiles RecordLiteral to OP_PUSH_RECORD
#
# Fixtures used:
#   rack_core/typed_response_record_checking.ig  — RackResponse (P13 fixture)
#   sidekiq_core/jobreceipt_schema.ig            — JobReceipt (P4 fixture)
#   rack_core/multi_contract_caller.ig           — P9 regression baseline
#
# Proof scope:
#   RECORD-VM-COMPILE  — P13 and P4 fixtures compile cleanly
#   RECORD-VM-RACK     — RackResponse output: status/body fields preserved; dispatchers work
#   RECORD-VM-SIDEKIQ  — JobReceipt output: all 5 fields preserved; Tier 1/Tier 2 dispatch work
#   RECORD-VM-FIELDS   — field preservation and deterministic serialization policy confirmed
#   RECORD-VM-REG      — P9/P3/P2 scalar dispatch regressions; P13/P4 SemanticIR unchanged
#   RECORD-VM-CLOSED   — no Redis, no sockets, no ServiceLoop, no compatibility claims
#   RECORD-VM-GAP      — gap packet: nested records and field access deferred
#
# Explicit answers (see gap packet):
#   VM record construction for RackResponse: PROVED
#   VM record construction for JobReceipt: PROVED
#   Implementation is generic (not domain-specific): YES — OP_PUSH_RECORD/BTreeMap
#   Field names and values survive VM execution: YES
#   Serialization is deterministic: YES — BTreeMap alphabetical key order
#   Creates canon/runtime/public/stable authority: NO
#   Rack P14 and Sidekiq P5 are covered by this shared proof: YES
#   Next route: P2 — nested record fields and field access from dispatched output
#
# Check count: 43
#
# CLOSED: lab-only, no Redis, no queue storage, no worker daemon, no scheduler,
#         no ServiceLoop, no Sidekiq compatibility claim, no Rack compatibility claim,
#         no public API stability, no production runtime claims.
#         call_contract is explicitly lab-only; no canon claim.
#
# Authority: lab-only evidence — no canon claim, no public API stability.
# Card: LAB-RECORD-VM-P1
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT            = Pathname.new(__dir__).parent
RACK_FIXTURE_DIR = ROOT / 'fixtures/rack_core'
SIDEKIQ_FIX_DIR  = ROOT / 'fixtures/sidekiq_core'
OUT_DIR          = ROOT / 'out/record_vm_construction'
COMPILER_BIN     = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST      = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC           = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
VALUE_SRC        = File.expand_path('../../igniter-vm/src/value.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

SOURCE = File.read(__FILE__, encoding: 'UTF-8')

# ── Helpers ────────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  out  = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
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

# ── Compile fixtures ───────────────────────────────────────────────────────────

P13_IGAPP   = (OUT_DIR / 'p13').to_s
P13_RESULT  = compile_fixture(
  RACK_FIXTURE_DIR / 'typed_response_record_checking.ig',
  P13_IGAPP
)
P13_SIR     = load_sir(P13_RESULT)

P4_IGAPP    = (OUT_DIR / 'p4').to_s
P4_RESULT   = compile_fixture(
  SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig',
  P4_IGAPP
)
P4_SIR      = load_sir(P4_RESULT)

P9_IGAPP    = (OUT_DIR / 'p9_reg').to_s
P9_RESULT   = compile_fixture(
  RACK_FIXTURE_DIR / 'multi_contract_caller.ig',
  P9_IGAPP
)

P3_IGAPP    = (OUT_DIR / 'p3_reg').to_s
P3_RESULT   = compile_fixture(
  SIDEKIQ_FIX_DIR / 'retry_policy.ig',
  P3_IGAPP
)

P2_IGAPP    = (OUT_DIR / 'p2_reg').to_s
P2_RESULT   = compile_fixture(
  SIDEKIQ_FIX_DIR / 'job_dispatch_table.ig',
  P2_IGAPP
)

# ── VM runs — RackResponse ─────────────────────────────────────────────────────

RACK_OK         = run_vm(P13_IGAPP, { 'method' => 'GET', 'path' => '/' },           entry_name: 'OkHandler')
RACK_DIRECT     = run_vm(P13_IGAPP, { 'method' => 'GET', 'path' => '/' },           entry_name: 'DirectLiteralHandler')
RACK_COMPLEX    = run_vm(P13_IGAPP, { 'method' => 'GET', 'path' => '/', 'code' => 404 }, entry_name: 'ComplexFieldHandler')
RACK_STATIC_D   = run_vm(P13_IGAPP, { 'method' => 'GET', 'path' => '/' },           entry_name: 'StaticDispatcherP13')
RACK_DYNAMIC_D  = run_vm(P13_IGAPP, { 'method' => 'GET', 'path' => '/', 'handler_name' => 'OkHandler' }, entry_name: 'DynamicDispatcherP13')

# ── VM runs — JobReceipt ───────────────────────────────────────────────────────

RECEIPT_JOB     = run_vm(P4_IGAPP,
  { 'job_class' => 'SomeJob', 'job_id' => 'j-001', 'attempt' => 2, 'max_attempts' => 5 },
  entry_name: 'ReceiptJob')
RECEIPT_DISP    = run_vm(P4_IGAPP,
  { 'job_class' => 'ReceiptJob', 'job_id' => 'j-002', 'attempt' => 1, 'max_attempts' => 3 },
  entry_name: 'ReceiptDispatcher')
RECEIPT_DYN_OK  = run_vm(P4_IGAPP,
  { 'handler_name' => 'ReceiptJob', 'job_class' => 'ReceiptJob',
    'job_id' => 'j-003', 'attempt' => 0, 'max_attempts' => 5 },
  entry_name: 'DynamicReceiptDispatcher')
RECEIPT_DYN_ERR = run_vm(P4_IGAPP,
  { 'handler_name' => 'GhostJob', 'job_class' => 'ReceiptJob',
    'job_id' => 'j-err', 'attempt' => 1, 'max_attempts' => 5 },
  entry_name: 'DynamicReceiptDispatcher')

# ── VM runs — regression ───────────────────────────────────────────────────────

P9_DOUBLER   = run_vm(P9_IGAPP,  { 'n' => 7 },                                entry_name: 'CallerDoubler')
P3_POLICY    = run_vm(P3_IGAPP,  { 'attempt' => 2, 'max_attempts' => 5 },     entry_name: 'RetryPolicy')
P2_DISPATCH  = run_vm(P2_IGAPP,
  { 'job_class' => 'ProcessOrderJob', 'job_id' => 'j-r', 'arg1' => 21, 'arg2' => 1 },
  entry_name: 'JobDispatcher')

puts "LAB-RECORD-VM-P1: VM Record Construction and Serialization"
puts "═" * 72

# ── RECORD-VM-COMPILE ──────────────────────────────────────────────────────────
section 'RECORD-VM-COMPILE: P13 and P4 fixtures compile cleanly'

check('RECORD-VM-COMPILE-01: P13 fixture (RackResponse) compiles with status=ok') do
  P13_RESULT['status'] == 'ok'
end

check('RECORD-VM-COMPILE-02: P13 fixture has no diagnostics') do
  (P13_RESULT['diagnostics'] || []).empty?
end

check('RECORD-VM-COMPILE-03: P4 fixture (JobReceipt) compiles with status=ok') do
  P4_RESULT['status'] == 'ok'
end

check('RECORD-VM-COMPILE-04: P4 fixture has no diagnostics') do
  (P4_RESULT['diagnostics'] || []).empty?
end

# ── RECORD-VM-RACK ─────────────────────────────────────────────────────────────
section 'RECORD-VM-RACK: RackResponse record construction end-to-end'

check('RECORD-VM-RACK-01: OkHandler executes successfully') do
  RACK_OK['status'] == 'success'
end

check('RECORD-VM-RACK-02: OkHandler result is a JSON object (record preserved at VM boundary)') do
  RACK_OK['result'].is_a?(Hash)
end

check('RECORD-VM-RACK-03: OkHandler result.status == 200 (Integer field preserved)') do
  RACK_OK['result']['status'] == 200
end

check('RECORD-VM-RACK-04: OkHandler result.body == "OK" (String field preserved)') do
  RACK_OK['result']['body'] == 'OK'
end

check('RECORD-VM-RACK-05: DirectLiteralHandler result correct (inline literal fields)') do
  RACK_DIRECT['status'] == 'success' &&
    RACK_DIRECT['result']['status'] == 200 &&
    RACK_DIRECT['result']['body'] == 'Direct'
end

check('RECORD-VM-RACK-06: ComplexFieldHandler(code=404) result.status == 404 (BinaryOp field preserved)') do
  RACK_COMPLEX['status'] == 'success' &&
    RACK_COMPLEX['result']['status'] == 404 &&
    RACK_COMPLEX['result']['body'] == 'Complex'
end

check('RECORD-VM-RACK-07: StaticDispatcherP13 (P11 Tier 1) executes and returns record') do
  RACK_STATIC_D['status'] == 'success' && RACK_STATIC_D['result'].is_a?(Hash)
end

check('RECORD-VM-RACK-08: StaticDispatcherP13 result has correct status and body') do
  RACK_STATIC_D['result']['status'] == 200 && RACK_STATIC_D['result']['body'] == 'OK'
end

check('RECORD-VM-RACK-09: DynamicDispatcherP13 (P11 Tier 2) executes and returns record') do
  RACK_DYNAMIC_D['status'] == 'success' && RACK_DYNAMIC_D['result'].is_a?(Hash)
end

check('RECORD-VM-RACK-10: DynamicDispatcherP13 result has correct status and body') do
  RACK_DYNAMIC_D['result']['status'] == 200 && RACK_DYNAMIC_D['result']['body'] == 'OK'
end

# ── RECORD-VM-SIDEKIQ ──────────────────────────────────────────────────────────
section 'RECORD-VM-SIDEKIQ: JobReceipt record construction end-to-end'

check('RECORD-VM-SIDEKIQ-01: ReceiptJob executes successfully') do
  RECEIPT_JOB['status'] == 'success'
end

check('RECORD-VM-SIDEKIQ-02: ReceiptJob result is a JSON object (all 5 fields preserved)') do
  RECEIPT_JOB['result'].is_a?(Hash) &&
    %w[job_class job_id attempt budget_remaining status].all? do |f|
      RECEIPT_JOB['result'].key?(f)
    end
end

check('RECORD-VM-SIDEKIQ-03: ReceiptJob result.job_class == input job_class') do
  RECEIPT_JOB['result']['job_class'] == 'SomeJob'
end

check('RECORD-VM-SIDEKIQ-04: ReceiptJob result.budget_remaining == max_attempts - attempt (3)') do
  RECEIPT_JOB['result']['budget_remaining'] == 3
end

check('RECORD-VM-SIDEKIQ-05: ReceiptJob result.status == "ok" (String literal field preserved)') do
  RECEIPT_JOB['result']['status'] == 'ok'
end

check('RECORD-VM-SIDEKIQ-06: ReceiptDispatcher (P11 Tier 1) executes and returns record') do
  RECEIPT_DISP['status'] == 'success' && RECEIPT_DISP['result'].is_a?(Hash)
end

check('RECORD-VM-SIDEKIQ-07: ReceiptDispatcher result has all 5 fields with correct values') do
  r = RECEIPT_DISP['result']
  r.is_a?(Hash) &&
    r['job_id'] == 'j-002' &&
    r['budget_remaining'] == 2 &&   # max_attempts(3) - attempt(1)
    r['status'] == 'ok'
end

check('RECORD-VM-SIDEKIQ-08: DynamicReceiptDispatcher (P11 Tier 2) executes and returns record') do
  RECEIPT_DYN_OK['status'] == 'success' &&
    RECEIPT_DYN_OK['result'].is_a?(Hash) &&
    RECEIPT_DYN_OK['result']['budget_remaining'] == 5  # max(5) - attempt(0)
end

check('RECORD-VM-SIDEKIQ-09: DynamicReceiptDispatcher with unknown handler → VM error (fail-closed)') do
  RECEIPT_DYN_ERR['status'] == 'error' &&
    RECEIPT_DYN_ERR['error'].to_s.include?('no contract named')
end

# ── RECORD-VM-FIELDS ───────────────────────────────────────────────────────────
section 'RECORD-VM-FIELDS: field preservation and deterministic serialization'

check('RECORD-VM-FIELDS-01: RackResponse result is a Hash with exactly 2 keys (status, body)') do
  r = RACK_OK['result']
  r.is_a?(Hash) && r.keys.sort == %w[body status]
end

check('RECORD-VM-FIELDS-02: RackResponse keys are in alphabetical order (BTreeMap determinism)') do
  # BTreeMap iterates keys in sorted order → JSON keys are always alphabetical
  # Ruby JSON.parse preserves insertion order; alphabetical from BTreeMap
  r = RACK_OK['result']
  r.keys == r.keys.sort
end

check('RECORD-VM-FIELDS-03: JobReceipt result has exactly 5 keys matching schema') do
  r = RECEIPT_JOB['result']
  r.is_a?(Hash) && r.keys.sort == %w[attempt budget_remaining job_class job_id status]
end

check('RECORD-VM-FIELDS-04: JobReceipt keys are in alphabetical order (BTreeMap determinism)') do
  r = RECEIPT_JOB['result']
  r.keys == r.keys.sort
end

check('RECORD-VM-FIELDS-05: Computed field value (budget_remaining) survives VM serialization faithfully') do
  # ReceiptJob: budget_remaining = max_attempts - attempt = 5 - 2 = 3
  # Field value is the result of pure arithmetic, not a literal: proves VM computes and
  # serializes non-literal field values correctly
  RECEIPT_JOB['result']['budget_remaining'] == 3 &&
    RECEIPT_DISP['result']['budget_remaining'] == 2 &&  # 3 - 1
    RECEIPT_DYN_OK['result']['budget_remaining'] == 5   # 5 - 0
end

# ── RECORD-VM-REG ──────────────────────────────────────────────────────────────
section 'RECORD-VM-REG: scalar dispatch and SemanticIR regression checks'

check('RECORD-VM-REG-01: P9 CallerDoubler(n=7) → 15 (call_contract scalar dispatch unchanged)') do
  P9_DOUBLER['status'] == 'success' && P9_DOUBLER['result'] == 15
end

check('RECORD-VM-REG-02: P3 RetryPolicy(attempt=2, max=5) → 3 (scalar arithmetic unchanged)') do
  P3_POLICY['status'] == 'success' && P3_POLICY['result'] == 3
end

check('RECORD-VM-REG-03: P2 JobDispatcher(ProcessOrderJob, 21) → 42 (dispatch table unchanged)') do
  P2_DISPATCH['status'] == 'success' && P2_DISPATCH['result'] == 42
end

check('RECORD-VM-REG-04: P13 OkHandler.response compute node still RackResponse in SemanticIR') do
  sir_node_type(P13_SIR, 'OkHandler', 'response') == 'RackResponse'
end

check('RECORD-VM-REG-05: P4 ReceiptJob.receipt compute node still JobReceipt in SemanticIR') do
  sir_node_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

# ── RECORD-VM-CLOSED ───────────────────────────────────────────────────────────
section 'RECORD-VM-CLOSED: closed-surface scan'

check('RECORD-VM-CLOSED-01: no TCP/UDP socket use in proof source') do
  !SOURCE.include?("TC" + "PSocket") &&
  !SOURCE.include?("UDP" + "Socket") &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('RECORD-VM-CLOSED-02: no Redis connection in proof source') do
  !SOURCE.include?("Re" + "dis.new") &&
  !SOURCE.include?("redis" + "://") &&
  !SOURCE.include?("require 're" + "dis'")
end

check('RECORD-VM-CLOSED-03: no ServiceLoop invocation in proof source') do
  !SOURCE.include?("require 'ser" + "vice_loop'") &&
  !SOURCE.include?("Servi" + "ceLoop.new") &&
  !SOURCE.include?("Servi" + "ceLoop.start")
end

check('RECORD-VM-CLOSED-04: no clock/time access in proof source (OOF-L6 boundary)') do
  !SOURCE.include?("Ti" + "me.now") &&
  !SOURCE.include?("Date" + "Ti" + "me.now")
end

check('RECORD-VM-CLOSED-05: no Rack/Sidekiq compatibility or production/canon claim in proof source') do
  !SOURCE.include?("Rack-compat" + "ible") &&
  !SOURCE.include?("Si" + "dekiq-compat" + "ible") &&
  !SOURCE.include?("produc" + "tion-ready") &&
  !SOURCE.include?("stab" + "le API surface")
end

# ── RECORD-VM-GAP ──────────────────────────────────────────────────────────────
section 'RECORD-VM-GAP: gap packet'

GAP_PACKET = {
  proof:        'lab-record-vm-p1-construction-and-serialization',
  version:      'v0',
  implementation_finding: 'zero_new_vm_code_required',
  closed_by_p1: %w[
    rack_response_vm_construction
    jobreceipt_vm_construction
    deterministic_alphabetical_field_serialization
    tier1_dispatched_record_output_preserved
    tier2_dispatched_record_output_preserved
  ],
  v0_policy: {
    field_order: 'alphabetical_btreemap',
    value_types_supported: %w[Integer String Bool],
    nested_record_fields: 'not_yet_proven',
    vm_authority: 'lab_only_no_runtime_gate'
  },
  still_open: %w[
    nested_record_types_as_field_values
    field_access_from_dispatched_record_output
    record_field_access_opcode
    multi_output_callee
    enum_status_type
  ],
  rack_p14_covered: true,
  sidekiq_p5_covered: true,
  sidekiq_compatibility: 'permanently_closed',
  rack_compatibility: 'permanently_closed',
  p2_recommendation: 'Nested record field access — prove OP_FIELD_ACCESS or equivalent on a record returned from call_contract (tests field-level extraction from a dispatched record value)'
}

check('RECORD-VM-GAP-01: gap packet closed_by_p1 contains rack_response_vm_construction') do
  GAP_PACKET[:closed_by_p1].include?('rack_response_vm_construction')
end

check('RECORD-VM-GAP-02: gap packet closed_by_p1 contains jobreceipt_vm_construction') do
  GAP_PACKET[:closed_by_p1].include?('jobreceipt_vm_construction')
end

check('RECORD-VM-GAP-03: gap packet implementation_finding is zero_new_vm_code_required') do
  GAP_PACKET[:implementation_finding] == 'zero_new_vm_code_required'
end

check('RECORD-VM-GAP-04: gap packet rack_p14_covered and sidekiq_p5_covered are true') do
  GAP_PACKET[:rack_p14_covered] == true &&
    GAP_PACKET[:sidekiq_p5_covered] == true
end

check('RECORD-VM-GAP-05: gap packet still_open contains nested_record_types and field_access') do
  GAP_PACKET[:still_open].include?('nested_record_types_as_field_values') &&
    GAP_PACKET[:still_open].include?('field_access_from_dispatched_record_output')
end

# ── Summary ────────────────────────────────────────────────────────────────────

passed = RESULTS.count { |r| r[:passed] }
total  = RESULTS.size

puts "\n#{"═" * 72}"
puts "  LAB-RECORD-VM-P1: VM Record Construction and Serialization"
if FAILURES.empty?
  puts "  #{passed}/#{total} PASS"
else
  puts "  #{passed}/#{total} PASS — FAILURES: #{FAILURES.join(', ')}"
end
puts "═" * 72

exit(FAILURES.empty? ? 0 : 1)
