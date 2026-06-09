# verify_sidekiq_p4_jobreceipt_schema.rb
#
# LAB-SIDEKIQ-P4: JobReceipt Schema Proof
#
# Purpose: Prove that a Sidekiq-like job execution surface can return a structured
# single-output JobReceipt record using P13 nominal record typechecking, replacing
# raw Integer retry/job outputs with a typed receipt that is validated at compile time.
#
# Implementation:
#   igniter-view-engine/fixtures/sidekiq_core/jobreceipt_schema.ig
#     Three contracts + one type declaration:
#       type JobReceipt         — 5-field schema (job_class, job_id, attempt, budget_remaining, status)
#       ReceiptJob              — pure job with RecordLiteral output; P13 upgrades to JobReceipt
#       ReceiptDispatcher       — literal call_contract("ReceiptJob",...); P11 Tier 1 → JobReceipt
#       DynamicReceiptDispatcher — variable callee; P11 Tier 2 → Unknown (no P13 upgrade)
#   igniter-compiler/src/typechecker.rs
#     check_record_literal_shape  — validates RecordLiteral against type_shapes
#     output_type_hints           — pre-scan maps compute-node-name → expected record type
#     build_contract_registry     — Tier 1 literal callee lookup → single_output_type
#
# Proof scope:
#   SJOB4-COMPILE  — jobreceipt_schema.ig compiles; 3 contracts accepted
#   SJOB4-SOURCE   — typechecker mechanisms present in compiler source
#   SJOB4-TYPES    — SemanticIR compute node types match expected resolution
#   SJOB4-FC       — fail-closed: missing/extra/wrong-type fields and unknown callee → OOF-TY0
#   SJOB4-REG      — P2 and P3 regressions still green
#   SJOB4-CLOSED   — closed-surface scan (no Redis, no queue, no clock, no claims)
#   SJOB4-GAP      — gap packet: VM record construction and enum type deferred
#
# Check count: 46
#
# CLOSED: lab-only, no Redis, no queue storage, no worker daemon, no scheduler,
#         no ServiceLoop, no Sidekiq compatibility claim, no canon grammar edits,
#         no public API stability, no production runtime claims.
#         TypeChecker/SemanticIR proof only; VM record construction is deferred (P14).
#         call_contract is explicitly lab-only; no canon claim.
#
# Authority: lab-only evidence — no canon claim, no public API stability.
# Card: LAB-SIDEKIQ-P4
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT           = Pathname.new(__dir__).parent
FIXTURE_DIR    = ROOT / 'fixtures/sidekiq_core'
OUT_DIR        = ROOT / 'out/p4_jobreceipt_schema'
COMPILER_BIN   = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST    = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC         = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
TYPECHECKER_SRC = File.expand_path('../../igniter-compiler/src/typechecker.rs', __dir__)
FIXTURE_SRC    = File.expand_path('fixtures/sidekiq_core/jobreceipt_schema.ig', ROOT.to_s)

FileUtils.mkdir_p(OUT_DIR)

# Read the proof source for closed-surface scans
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

# ── Compile fixtures ───────────────────────────────────────────────────────────

P4_IGAPP   = (OUT_DIR / 'jobreceipt_schema').to_s
P4_RESULT  = compile_fixture(
  FIXTURE_DIR / 'jobreceipt_schema.ig',
  P4_IGAPP
)
P4_SIR     = load_sir(P4_RESULT)

P3_IGAPP   = (OUT_DIR / 'p3_reg').to_s
P3_RESULT  = compile_fixture(
  FIXTURE_DIR / 'retry_policy.ig',
  P3_IGAPP
)

P2_IGAPP   = (OUT_DIR / 'p2_reg').to_s
P2_RESULT  = compile_fixture(
  FIXTURE_DIR / 'job_dispatch_table.ig',
  P2_IGAPP
)

FIXTURE_SRC_TEXT = File.read(FIXTURE_SRC) rescue ''
TYPECHECKER_TEXT = File.read(TYPECHECKER_SRC, encoding: 'UTF-8') rescue ''

# ── Inline FC fixtures ─────────────────────────────────────────────────────────

TYPE_DECL = <<~IG
  type JobReceipt {
    job_class        : String,
    job_id           : String,
    attempt          : Integer,
    budget_remaining : Integer,
    status           : String
  }
IG

MISSING_FIELD_SRC = <<~IG
  module Test.P4.MissingField

  #{TYPE_DECL}
  pure contract MissingFieldJob {
    input job_class : String
    input job_id    : String
    compute receipt = { job_class: job_class, job_id: job_id, attempt: 1, budget_remaining: 4 }
    output receipt : JobReceipt
  }
IG

EXTRA_FIELD_SRC = <<~IG
  module Test.P4.ExtraField

  #{TYPE_DECL}
  pure contract ExtraFieldJob {
    input job_class : String
    input job_id    : String
    compute receipt = {
      job_class: job_class, job_id: job_id, attempt: 1,
      budget_remaining: 4, status: "ok", queue_name: "default"
    }
    output receipt : JobReceipt
  }
IG

WRONG_JOB_ID_SRC = <<~IG
  module Test.P4.WrongJobId

  #{TYPE_DECL}
  pure contract WrongJobIdJob {
    input job_class : String
    compute job_id_val = 99
    compute receipt = {
      job_class: job_class, job_id: job_id_val, attempt: 1,
      budget_remaining: 4, status: "ok"
    }
    output receipt : JobReceipt
  }
IG

WRONG_ATTEMPT_SRC = <<~IG
  module Test.P4.WrongAttempt

  #{TYPE_DECL}
  pure contract WrongAttemptJob {
    input job_class : String
    compute attempt_val = "one"
    compute receipt = {
      job_class: job_class, job_id: "j1", attempt: attempt_val,
      budget_remaining: 4, status: "ok"
    }
    output receipt : JobReceipt
  }
IG

WRONG_STATUS_SRC = <<~IG
  module Test.P4.WrongStatus

  #{TYPE_DECL}
  pure contract WrongStatusJob {
    input job_class : String
    compute status_val = 999
    compute receipt = {
      job_class: job_class, job_id: "j1", attempt: 1,
      budget_remaining: 4, status: status_val
    }
    output receipt : JobReceipt
  }
IG

UNKNOWN_CALLEE_SRC = <<~IG
  module Test.P4.UnknownCallee

  #{TYPE_DECL}
  pure contract UnknownCalleeDispatcher {
    input job_class    : String
    input job_id       : String
    input attempt      : Integer
    input max_attempts : Integer
    compute receipt = call_contract("GhostReceiptJob", job_class, job_id, attempt, max_attempts)
    output receipt : JobReceipt
  }
IG

FC_MISSING_FIELD  = compile_inline(MISSING_FIELD_SRC,  'missing_field')
FC_EXTRA_FIELD    = compile_inline(EXTRA_FIELD_SRC,    'extra_field')
FC_WRONG_JOB_ID   = compile_inline(WRONG_JOB_ID_SRC,   'wrong_job_id')
FC_WRONG_ATTEMPT  = compile_inline(WRONG_ATTEMPT_SRC,  'wrong_attempt')
FC_WRONG_STATUS   = compile_inline(WRONG_STATUS_SRC,   'wrong_status')
FC_UNKNOWN_CALLEE = compile_inline(UNKNOWN_CALLEE_SRC, 'unknown_callee')

# ── VM regression runs ─────────────────────────────────────────────────────────

# P3 regression VM runs
P3_REG01 = run_vm(P3_IGAPP, { 'attempt' => 2, 'max_attempts' => 5 }, entry_name: 'RetryPolicy')
P3_REG02 = run_vm(P3_IGAPP, { 'outcomes' => [1, 2, 3] },             entry_name: 'RetrySimulator')

# P2 regression VM run
P2_REG01 = run_vm(P2_IGAPP,
  { 'job_class' => 'ProcessOrderJob', 'job_id' => 'j-r', 'arg1' => 21, 'arg2' => 1 },
  entry_name: 'JobDispatcher')

puts "LAB-SIDEKIQ-P4: JobReceipt Schema"
puts "═" * 72

# ── SJOB4-COMPILE ──────────────────────────────────────────────────────────────
section 'SJOB4-COMPILE: jobreceipt_schema.ig compiles (3 contracts accepted)'

check('SJOB4-COMPILE-01: fixture compiles with status=ok') do
  P4_RESULT['status'] == 'ok'
end

check('SJOB4-COMPILE-02: all 3 contracts present (ReceiptJob, ReceiptDispatcher, DynamicReceiptDispatcher)') do
  contracts = P4_RESULT['contracts'] || []
  %w[ReceiptJob ReceiptDispatcher DynamicReceiptDispatcher].all? { |c| contracts.include?(c) }
end

check('SJOB4-COMPILE-03: no diagnostics in jobreceipt_schema.ig') do
  (P4_RESULT['diagnostics'] || []).empty?
end

check('SJOB4-COMPILE-04: all stages ok (parse, classify, typecheck, emit, assemble)') do
  stages = P4_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

check('SJOB4-COMPILE-05: ReceiptJob.receipt compute node → JobReceipt (P13 RecordLiteral upgrade)') do
  sir_node_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

check('SJOB4-COMPILE-06: ReceiptDispatcher.receipt compute node → JobReceipt (P11 Tier 1 literal callee)') do
  sir_node_type(P4_SIR, 'ReceiptDispatcher', 'receipt') == 'JobReceipt'
end

# ── SJOB4-SOURCE ───────────────────────────────────────────────────────────────
section 'SJOB4-SOURCE: typechecker mechanisms present in compiler source'

check('SJOB4-SOURCE-01: fixture source declares type JobReceipt') do
  FIXTURE_SRC_TEXT.include?('type JobReceipt')
end

check('SJOB4-SOURCE-02: fixture source declares all 5 required JobReceipt fields') do
  %w[job_class job_id attempt budget_remaining status].all? do |f|
    FIXTURE_SRC_TEXT.include?(f)
  end
end

check('SJOB4-SOURCE-03: typechecker.rs contains check_record_literal_shape (P13 validation mechanism)') do
  TYPECHECKER_TEXT.include?('check_record_literal_shape')
end

check('SJOB4-SOURCE-04: typechecker.rs contains output_type_hints (P13 pre-scan mechanism)') do
  TYPECHECKER_TEXT.include?('output_type_hints')
end

check('SJOB4-SOURCE-05: typechecker.rs contains build_contract_registry (P11 Tier 1 mechanism)') do
  TYPECHECKER_TEXT.include?('build_contract_registry')
end

# ── SJOB4-TYPES ────────────────────────────────────────────────────────────────
section 'SJOB4-TYPES: SemanticIR compute node type resolution'

check('SJOB4-TYPES-01: ReceiptJob.receipt compute → JobReceipt (P13 RecordLiteral upgrade from Unknown)') do
  sir_node_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

check('SJOB4-TYPES-02: ReceiptJob.budget_remaining compute → Integer (pure arithmetic)') do
  sir_node_type(P4_SIR, 'ReceiptJob', 'budget_remaining') == 'Integer'
end

check('SJOB4-TYPES-03: ReceiptJob.status_val compute → String (string literal)') do
  sir_node_type(P4_SIR, 'ReceiptJob', 'status_val') == 'String'
end

check('SJOB4-TYPES-04: ReceiptDispatcher.receipt compute → JobReceipt (P11 Tier 1 static resolution)') do
  sir_node_type(P4_SIR, 'ReceiptDispatcher', 'receipt') == 'JobReceipt'
end

check('SJOB4-TYPES-05: DynamicReceiptDispatcher.receipt compute → Unknown (P11 Tier 2; P13 does not upgrade call_contract)') do
  sir_node_type(P4_SIR, 'DynamicReceiptDispatcher', 'receipt') == 'Unknown'
end

check('SJOB4-TYPES-06: ReceiptJob SemanticIR output receipt declared as JobReceipt') do
  sir_output_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

# ── SJOB4-FC ───────────────────────────────────────────────────────────────────
section 'SJOB4-FC: fail-closed — RecordLiteral shape violations and unknown callee → OOF-TY0'

# FC-01: missing required field (status omitted)
check('SJOB4-FC-01: missing field → compile fails') do
  FC_MISSING_FIELD['status'] != 'ok'
end

check('SJOB4-FC-02: missing field → OOF-TY0 in diagnostics') do
  diags = FC_MISSING_FIELD['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('SJOB4-FC-03: missing field error names the expected record type') do
  diags = FC_MISSING_FIELD['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('JobReceipt') }
end

# FC-02: unexpected extra field (queue_name)
check('SJOB4-FC-04: extra field → compile fails') do
  FC_EXTRA_FIELD['status'] != 'ok'
end

check('SJOB4-FC-05: extra field → OOF-TY0 naming the unexpected field') do
  diags = FC_EXTRA_FIELD['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' && d['message'].to_s.include?('queue_name') }
end

# FC-03: wrong type on job_id field (Integer provided, String expected)
check('SJOB4-FC-06: wrong job_id type → compile fails') do
  FC_WRONG_JOB_ID['status'] != 'ok'
end

check('SJOB4-FC-07: wrong job_id type → OOF-TY0 naming job_id field') do
  diags = FC_WRONG_JOB_ID['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' && d['message'].to_s.include?('job_id') }
end

check('SJOB4-FC-08: wrong job_id type → error mentions expected String type') do
  diags = FC_WRONG_JOB_ID['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('String') }
end

# FC-04: wrong type on attempt field (String provided, Integer expected)
check('SJOB4-FC-09: wrong attempt type → compile fails') do
  FC_WRONG_ATTEMPT['status'] != 'ok'
end

check('SJOB4-FC-10: wrong attempt type → OOF-TY0 naming attempt field') do
  diags = FC_WRONG_ATTEMPT['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' && d['message'].to_s.include?('attempt') }
end

# FC-05: wrong type on status field (Integer provided, String expected)
check('SJOB4-FC-11: wrong status type → compile fails') do
  FC_WRONG_STATUS['status'] != 'ok'
end

check('SJOB4-FC-12: wrong status type → OOF-TY0 naming status field') do
  diags = FC_WRONG_STATUS['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' && d['message'].to_s.include?('status') }
end

# FC-06: unknown literal callee (P11 Tier 1 enforcement still active)
check('SJOB4-FC-13: unknown literal callee → compile fails with OOF-TY0') do
  FC_UNKNOWN_CALLEE['status'] != 'ok' &&
    (FC_UNKNOWN_CALLEE['diagnostics'] || []).any? { |d| d['rule'] == 'OOF-TY0' }
end

check('SJOB4-FC-14: unknown callee error mentions callee name (GhostReceiptJob)') do
  diags = FC_UNKNOWN_CALLEE['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('GhostReceiptJob') }
end

# ── SJOB4-REG ──────────────────────────────────────────────────────────────────
section 'SJOB4-REG: P2 and P3 regression checks still green'

check('SJOB4-REG-01: P3 retry_policy.ig compiles ok') do
  P3_RESULT['status'] == 'ok'
end

check('SJOB4-REG-02: P3 RetryPolicy(attempt=2, max_attempts=5) → budget_remaining=3') do
  P3_REG01['status'] == 'success' && P3_REG01['result'] == 3
end

check('SJOB4-REG-03: P3 RetrySimulator(outcomes=[1,2,3]) → total_attempts=3') do
  P3_REG02['status'] == 'success' && P3_REG02['result'] == 3
end

check('SJOB4-REG-04: P2 job_dispatch_table.ig compiles ok') do
  P2_RESULT['status'] == 'ok'
end

check('SJOB4-REG-05: P2 JobDispatcher(ProcessOrderJob, arg1=21) → result=42 (P2 dispatch unchanged)') do
  P2_REG01['status'] == 'success' && P2_REG01['result'] == 42
end

# ── SJOB4-CLOSED ───────────────────────────────────────────────────────────────
section 'SJOB4-CLOSED: closed-surface scan'

check('SJOB4-CLOSED-01: no TCP/UDP socket use in proof source') do
  # Split strings so check expressions do not trigger self-match
  !SOURCE.include?("TC" + "PSocket") &&
  !SOURCE.include?("UDP" + "Socket") &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('SJOB4-CLOSED-02: no Redis connection in proof source') do
  !SOURCE.include?("Re" + "dis.new") &&
  !SOURCE.include?("redis" + "://") &&
  !SOURCE.include?("require 're" + "dis'")
end

check('SJOB4-CLOSED-03: no ServiceLoop invocation in proof source') do
  !SOURCE.include?("require 'ser" + "vice_loop'") &&
  !SOURCE.include?("Servi" + "ceLoop.new") &&
  !SOURCE.include?("Servi" + "ceLoop.start")
end

check('SJOB4-CLOSED-04: no clock/time access in proof or fixture source (OOF-L6 boundary)') do
  # Split strings to prevent self-match via SOURCE.include?
  !SOURCE.include?("Ti" + "me.now") &&
  !SOURCE.include?("Date" + "Ti" + "me.now") &&
  !FIXTURE_SRC_TEXT.include?("now()") &&
  !FIXTURE_SRC_TEXT.include?("tick.time")
end

check('SJOB4-CLOSED-05: no Sidekiq compatibility or production/canon claim in proof source') do
  !SOURCE.include?("Si" + "dekiq-compat" + "ible") &&
  !SOURCE.include?("produc" + "tion-ready") &&
  !SOURCE.include?("stab" + "le API surface")
end

# ── SJOB4-GAP ──────────────────────────────────────────────────────────────────
section 'SJOB4-GAP: gap packet'

GAP_PACKET = {
  proof:        'lab-sidekiq-p4-jobreceipt-schema',
  version:      'v0',
  closed_by_p4: %w[
    job_receipt_schema_declaration
    record_literal_typechecking_for_receipt
    tier1_literal_callee_resolves_to_jobreceipt
    tier2_dynamic_callee_stays_unknown
    all_5_field_shape_violations_fail_closed
  ],
  v0_policy: {
    status_is_string_vocabulary: 'enforced',
    no_timestamps_or_queue_ids: 'enforced',
    typechecker_semir_only: 'enforced'
  },
  still_open: %w[
    vm_record_construction
    enum_status_type
    async_retry
    queue_storage
    effect_dispatch
    multi_output_callee
    nested_record_types
    job_receipt_field_order_serialization
  ],
  sidekiq_compatibility: 'permanently_closed',
  p5_recommendation: 'VM record construction — execute a contract with JobReceipt output end-to-end through the VM; prove field values are accessible at runtime'
}

check('SJOB4-GAP-01: gap packet closed_by_p4 contains job_receipt_schema_declaration') do
  GAP_PACKET[:closed_by_p4].include?('job_receipt_schema_declaration')
end

check('SJOB4-GAP-02: gap packet still_open contains vm_record_construction (deferred to P5/P14)') do
  GAP_PACKET[:still_open].include?('vm_record_construction')
end

check('SJOB4-GAP-03: gap packet still_open contains enum_status_type (deferred)') do
  GAP_PACKET[:still_open].include?('enum_status_type')
end

check('SJOB4-GAP-04: gap packet still_open contains async_retry (permanently closed for P4)') do
  GAP_PACKET[:still_open].include?('async_retry')
end

check('SJOB4-GAP-05: gap packet sidekiq_compatibility is permanently_closed') do
  GAP_PACKET[:sidekiq_compatibility] == 'permanently_closed'
end

# ── Summary ────────────────────────────────────────────────────────────────────

passed = RESULTS.count { |r| r[:passed] }
total  = RESULTS.size

puts "\n#{"═" * 72}"
puts "  LAB-SIDEKIQ-P4: JobReceipt Schema"
if FAILURES.empty?
  puts "  #{passed}/#{total} PASS"
else
  puts "  #{passed}/#{total} PASS — FAILURES: #{FAILURES.join(', ')}"
end
puts "═" * 72

exit(FAILURES.empty? ? 0 : 1)
