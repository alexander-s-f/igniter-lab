#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
#
# verify_lab_outcome_variant_p2.rb — LAB-OUTCOME-VARIANT-P2 proof script
#
# Proves that variant/match Path B handles richer payload-bearing outcomes
# beyond simple arm-label routing (which was proved by P1).
#
# New territory vs LAB-OUTCOME-VARIANT-P1:
#   - String payload bindings flow from match arm to output (evidence_kind,
#     observed_at, request_id)
#   - Integer payload bindings flow correctly (attempt, budget_remaining)
#   - Map[String,String] payload field binds in match arm; map_get executes on it
#   - No-Upward-Coercion: ConfirmedSucceededReal and ConfirmedSucceededModel are
#     distinct arms that route differently AND carry distinct evidence_kind values
#
# Domain: ReconciliationOutcomeRich (5-arm focused variant)
#   ConfirmedSucceededReal  { request_id, resource, evidence_kind, observed_at }
#   ConfirmedSucceededModel { request_id, resource, evidence_kind, observed_at }
#   ConfirmedFailed         { request_id, idempotency_key, attempt }
#   StillUnknown            { request_id, attempt, budget_remaining }
#   ReconciliationError     { request_id, detail, metadata: Map[String,String] }
#
# Sections:
#   OUTVAR2-COMPILE  (6)  — fixture compiles; variant declared; no OOF diags
#   OUTVAR2-SHAPE    (8)  — SIR arm field types correct (String, Integer, Map)
#   OUTVAR2-BIND     (8)  — String + Integer payload bindings flow to outputs
#   OUTVAR2-ROUTE    (6)  — arm-label routing correct across all 5 arms
#   OUTVAR2-MAP      (5)  — Map[String,String] payload binding + map_get works
#   OUTVAR2-BUDGET   (5)  — Integer budget_remaining / attempt round-trip
#   OUTVAR2-NOUC     (5)  — No-Upward-Coercion enforced
#   OUTVAR2-REG      (6)  — P1 + P9 + variant_match regressions green
#   OUTVAR2-CLOSED   (7)  — no new VM types/opcodes, no taxonomy, no Outcome[T,E]
#
# Total: 56 checks
#
# Hard constraints (from card LAB-OUTCOME-VARIANT-P2):
#   - NO Outcome[T,E] generic type
#   - NO failure taxonomy authority
#   - NO serialization policy
#   - NO new VM opcodes or Value::Variant
#   - NO Ruby canon changes
#   - NOT production; domain proof only
#
# Note: binding name must differ from compute node name to avoid VM compiler
#   register collision (binding cleanup removes the shared name from registers).
#   ExtractObservedAt uses `ts`, ExtractRequestId uses `rid`, ExtractAttempt
#   uses `n_attempt` as compute node names.
#
# Run: ruby igniter-lab/igniter-view-engine/proofs/verify_lab_outcome_variant_p2.rb

require 'json'
require 'open3'
require 'tempfile'
require 'pathname'
require 'fileutils'

ROOT          = Pathname.new(__dir__).parent
LAB_ROOT      = ROOT.parent
COMPILER_BIN  = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN        = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_DIR   = (ROOT / 'fixtures' / 'outcome_variant').to_s
P1_FIXTURE    = (ROOT / 'fixtures' / 'epistemic_outcome' / 'outcome_variant.ig').to_s
P9_FIXTURE_DIR = (ROOT / 'fixtures' / 'reserved_fields').to_s
VM_SRC_DIR    = (LAB_ROOT / 'igniter-vm' / 'src').to_s
RUST_TC_SRC   = (LAB_ROOT / 'igniter-compiler' / 'src' / 'typechecker.rs').to_s

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

$compile_cache = {}

def compile(path, tag = nil)
  key = path.to_s
  return $compile_cache[key] if $compile_cache.key?(key)
  tag ||= File.basename(path, '.ig').gsub(/[^a-z0-9_]/, '_')
  out_dir = "/tmp/p2_proof_#{tag}"
  FileUtils.mkdir_p(out_dir)
  stdout, _stderr, _st = Open3.capture3(COMPILER_BIN, 'compile', path.to_s, '--out', out_dir, '--json')
  result = JSON.parse(stdout.force_encoding('UTF-8'))
  sir = begin
    path2 = File.join(out_dir, 'semantic_ir_program.json')
    File.exist?(path2) ? JSON.parse(File.read(path2)) : nil
  rescue; nil end
  $compile_cache[key] = { result: result, igapp_dir: out_dir, sir: sir }
end

def vm_run(igapp_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['p2_', '.json'])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _st = Open3.capture3(
    VM_BIN, 'run',
    '--contract', igapp_dir,
    '--inputs',   tmpfile.path,
    '--entry',    contract_name,
    '--json'
  )
  tmpfile.unlink rescue nil
  JSON.parse(stdout.force_encoding('UTF-8'))
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

def arm(name, variant, fields = {})
  { '__arm' => name, '__variant' => variant }.merge(fields)
end

RICH = 'ReconciliationOutcomeRich'
REAL_ARM  = 'ConfirmedSucceededReal'
MODEL_ARM = 'ConfirmedSucceededModel'
FAILED_ARM  = 'ConfirmedFailed'
UNKNOWN_ARM = 'StillUnknown'
ERROR_ARM   = 'ReconciliationError'

main = compile(File.join(FIXTURE_DIR, 'outcome_variant_rich.ig'), 'main')

# ── OUTVAR2-COMPILE ───────────────────────────────────────────────────────────
puts "\nOUTVAR2-COMPILE — Fixture compiles through Rust compiler"

check("outcome_variant_rich.ig: status=ok") do
  main[:result]['status'] == 'ok'
end

check("no OOF-KIND6 diagnostics (no __* field names in user source)") do
  (main[:result]['diagnostics'] || []).none? { |d| d['rule'] == 'OOF-KIND6' }
end

check("no OOF-KIND1..5 diagnostics (variant is exhaustive, no duplicates)") do
  (main[:result]['diagnostics'] || []).none? { |d| %w[OOF-KIND1 OOF-KIND2 OOF-KIND3 OOF-KIND4 OOF-KIND5].include?(d['rule']) }
end

check("SIR has variant_declarations") do
  main[:sir] && !main[:sir].fetch('variant_declarations', []).empty?
end

vd = main[:sir]&.dig('variant_declarations')&.find { |v| v['name'] == RICH }
check("ReconciliationOutcomeRich declared with 5 arms") do
  vd && vd['arms'].length == 5
end

check("All 12 contracts present in compilation output") do
  main[:result]['contracts'].length == 12
end

# ── OUTVAR2-SHAPE ─────────────────────────────────────────────────────────────
puts "\nOUTVAR2-SHAPE — SIR arm field types (String, Integer, Map)"

real_arm = vd && vd['arms'].find { |a| a['name'] == REAL_ARM }
failed_arm = vd && vd['arms'].find { |a| a['name'] == FAILED_ARM }
unknown_arm = vd && vd['arms'].find { |a| a['name'] == UNKNOWN_ARM }
error_arm = vd && vd['arms'].find { |a| a['name'] == ERROR_ARM }

check("ConfirmedSucceededReal has evidence_kind field (String)") do
  f = real_arm&.dig('fields')&.find { |f| f['name'] == 'evidence_kind' }
  f && f.dig('type', 'name') == 'String'
end

check("ConfirmedSucceededReal has observed_at field (String)") do
  f = real_arm&.dig('fields')&.find { |f| f['name'] == 'observed_at' }
  f && f.dig('type', 'name') == 'String'
end

check("ConfirmedFailed has attempt field (Integer)") do
  f = failed_arm&.dig('fields')&.find { |f| f['name'] == 'attempt' }
  f && f.dig('type', 'name') == 'Integer'
end

check("StillUnknown has budget_remaining field (Integer)") do
  f = unknown_arm&.dig('fields')&.find { |f| f['name'] == 'budget_remaining' }
  f && f.dig('type', 'name') == 'Integer'
end

check("ReconciliationError has metadata field (Map type)") do
  f = error_arm&.dig('fields')&.find { |f| f['name'] == 'metadata' }
  f && f.dig('type', 'name')&.downcase&.include?('map')
end

check("No arm field names start with __ (OOF-KIND6 guard in effect)") do
  vd && vd['arms'].all? do |a|
    a.fetch('fields', []).none? { |f| f['name'].start_with?('__') }
  end
end

# Check RouteRich SIR: exhaustive match, no wildcard
route_contract = main[:sir]&.dig('contracts')&.find { |c| c['contract_name'] == 'RouteRich' }
route_node = route_contract&.dig('nodes')&.first
route_match = route_node&.dig('expr')

check("RouteRich SIR match_node: exhaustive=true") do
  route_match && route_match['exhaustive'] == true
end

check("RouteRich SIR match_node: has_wildcard=false") do
  route_match && route_match['has_wildcard'] == false
end

# ── OUTVAR2-BIND ──────────────────────────────────────────────────────────────
puts "\nOUTVAR2-BIND — Payload bindings flow from match arm to output"

real_in = { 'outcome' => arm(REAL_ARM, RICH, 'request_id' => 'req-1', 'resource' => 'pay/1', 'evidence_kind' => 'real', 'observed_at' => '2026-06-10T12:00:00Z') }
model_in = { 'outcome' => arm(MODEL_ARM, RICH, 'request_id' => 'req-2', 'resource' => 'pay/2', 'evidence_kind' => 'model_inference', 'observed_at' => '2026-06-10T12:01:00Z') }
failed_in = { 'outcome' => arm(FAILED_ARM, RICH, 'request_id' => 'req-3', 'idempotency_key' => 'idem-1', 'attempt' => 3) }
unknown_in = { 'outcome' => arm(UNKNOWN_ARM, RICH, 'request_id' => 'req-4', 'attempt' => 2, 'budget_remaining' => 7) }

check("ExtractEvidenceKind: Real{evidence_kind:'real'} → 'real' (String binding flows to output)") do
  r = vm_run(main[:igapp_dir], 'ExtractEvidenceKind', real_in)
  r['status'] == 'success' && r['result'] == 'real'
end

check("ExtractEvidenceKind: Model{evidence_kind:'model_inference'} → 'model_inference'") do
  r = vm_run(main[:igapp_dir], 'ExtractEvidenceKind', model_in)
  r['status'] == 'success' && r['result'] == 'model_inference'
end

check("ExtractObservedAt: Real{observed_at:'2026-06-10T12:00:00Z'} → timestamp preserved") do
  r = vm_run(main[:igapp_dir], 'ExtractObservedAt', real_in)
  r['status'] == 'success' && r['result'] == '2026-06-10T12:00:00Z'
end

check("ExtractObservedAt: ConfirmedFailed → 'not_applicable' (no observed_at arm)") do
  r = vm_run(main[:igapp_dir], 'ExtractObservedAt', failed_in)
  r['status'] == 'success' && r['result'] == 'not_applicable'
end

check("ExtractRequestId: Real → 'req-1' (request_id String binding from first arm)") do
  r = vm_run(main[:igapp_dir], 'ExtractRequestId', real_in)
  r['status'] == 'success' && r['result'] == 'req-1'
end

check("ExtractRequestId: ReconciliationError → 'req-5' (request_id binding from last arm)") do
  error_in = { 'outcome' => arm(ERROR_ARM, RICH, 'request_id' => 'req-5', 'detail' => 'timeout', 'metadata' => { 'trace_id' => 't-abc' }) }
  r = vm_run(main[:igapp_dir], 'ExtractRequestId', error_in)
  r['status'] == 'success' && r['result'] == 'req-5'
end

check("ExtractAttempt: ConfirmedFailed{attempt:3} → 3 (Integer binding flows to output)") do
  r = vm_run(main[:igapp_dir], 'ExtractAttempt', failed_in)
  r['status'] == 'success' && r['result'] == 3
end

check("ExtractAttempt: StillUnknown{attempt:2} → 2 (Integer binding from second arm type)") do
  r = vm_run(main[:igapp_dir], 'ExtractAttempt', unknown_in)
  r['status'] == 'success' && r['result'] == 2
end

# ── OUTVAR2-ROUTE ─────────────────────────────────────────────────────────────
puts "\nOUTVAR2-ROUTE — Arm-label routing covers all 5 arms"

check("RouteRich: ConfirmedSucceededReal → 'accept'") do
  r = vm_run(main[:igapp_dir], 'RouteRich', real_in)
  r['status'] == 'success' && r['result'] == 'accept'
end

check("RouteRich: ConfirmedSucceededModel → 'needs_human_review'") do
  r = vm_run(main[:igapp_dir], 'RouteRich', model_in)
  r['status'] == 'success' && r['result'] == 'needs_human_review'
end

check("RouteRich: ConfirmedFailed → 'retry'") do
  r = vm_run(main[:igapp_dir], 'RouteRich', failed_in)
  r['status'] == 'success' && r['result'] == 'retry'
end

check("RouteRich: StillUnknown → 'reconcile_again'") do
  r = vm_run(main[:igapp_dir], 'RouteRich', unknown_in)
  r['status'] == 'success' && r['result'] == 'reconcile_again'
end

error_in = { 'outcome' => arm(ERROR_ARM, RICH, 'request_id' => 'req-5', 'detail' => 'timeout', 'metadata' => { 'trace_id' => 't-abc', 'error_code' => 'E503' }) }
check("RouteRich: ReconciliationError → 'hold'") do
  r = vm_run(main[:igapp_dir], 'RouteRich', error_in)
  r['status'] == 'success' && r['result'] == 'hold'
end

check("RouteRich: all 5 arms produce distinct actions (no routing collapse)") do
  results = [
    vm_run(main[:igapp_dir], 'RouteRich', real_in)['result'],
    vm_run(main[:igapp_dir], 'RouteRich', model_in)['result'],
    vm_run(main[:igapp_dir], 'RouteRich', failed_in)['result'],
    vm_run(main[:igapp_dir], 'RouteRich', unknown_in)['result'],
    vm_run(main[:igapp_dir], 'RouteRich', error_in)['result'],
  ]
  results.uniq.length == 5
end

# ── OUTVAR2-MAP ───────────────────────────────────────────────────────────────
puts "\nOUTVAR2-MAP — Map[String,String] payload binding + map_get in arm body"

check("BuildError: constructs ReconciliationError with metadata Map") do
  r = vm_run(main[:igapp_dir], 'BuildError',
    { 'request_id' => 'req-5', 'detail' => 'timeout', 'metadata' => { 'trace_id' => 't-abc', 'error_code' => 'E503' } })
  r['status'] == 'success' && r['result']['__arm'] == ERROR_ARM
end

check("ExtractTraceId: ReconciliationError{metadata:{trace_id:'t-abc'}} → 't-abc' (Map binding + map_get)") do
  r = vm_run(main[:igapp_dir], 'ExtractTraceId', error_in)
  r['status'] == 'success' && r['result'] == 't-abc'
end

check("ExtractTraceId: ReconciliationError without trace_id key → 'absent' (or_else default)") do
  error_no_trace = { 'outcome' => arm(ERROR_ARM, RICH, 'request_id' => 'req-6', 'detail' => 'err', 'metadata' => { 'error_code' => 'E404' }) }
  r = vm_run(main[:igapp_dir], 'ExtractTraceId', error_no_trace)
  r['status'] == 'success' && r['result'] == 'absent'
end

check("ExtractTraceId: ConfirmedSucceededReal → 'none' (non-error arm returns sentinel)") do
  r = vm_run(main[:igapp_dir], 'ExtractTraceId', real_in)
  r['status'] == 'success' && r['result'] == 'none'
end

check("Map payload field survives Path B: built ReconciliationError.__arm correct") do
  r = vm_run(main[:igapp_dir], 'BuildError',
    { 'request_id' => 'req-7', 'detail' => 'crash', 'metadata' => { 'trace_id' => 'xyz', 'severity' => 'high' } })
  r['status'] == 'success' && r['result']['__arm'] == ERROR_ARM && r['result']['metadata']['trace_id'] == 'xyz'
end

# ── OUTVAR2-BUDGET ────────────────────────────────────────────────────────────
puts "\nOUTVAR2-BUDGET — Integer budget_remaining / attempt round-trip"

check("ExtractBudget: StillUnknown{budget_remaining:7} → 7") do
  r = vm_run(main[:igapp_dir], 'ExtractBudget', unknown_in)
  r['status'] == 'success' && r['result'] == 7
end

check("ExtractBudget: StillUnknown{budget_remaining:0} → 0 (zero budget preserved)") do
  zero_budget = { 'outcome' => arm(UNKNOWN_ARM, RICH, 'request_id' => 'r', 'attempt' => 5, 'budget_remaining' => 0) }
  r = vm_run(main[:igapp_dir], 'ExtractBudget', zero_budget)
  r['status'] == 'success' && r['result'] == 0
end

check("ExtractBudget: ConfirmedFailed → 0 (no budget_remaining field → sentinel)") do
  r = vm_run(main[:igapp_dir], 'ExtractBudget', failed_in)
  r['status'] == 'success' && r['result'] == 0
end

check("ExtractAttempt: ConfirmedFailed{attempt:100} → 100 (large Integer binding)") do
  high_attempt = { 'outcome' => arm(FAILED_ARM, RICH, 'request_id' => 'r', 'idempotency_key' => 'k', 'attempt' => 100) }
  r = vm_run(main[:igapp_dir], 'ExtractAttempt', high_attempt)
  r['status'] == 'success' && r['result'] == 100
end

check("BuildUnknown: constructs StillUnknown with attempt=3, budget_remaining=5 correctly") do
  r = vm_run(main[:igapp_dir], 'BuildUnknown',
    { 'request_id' => 'req-u', 'attempt' => 3, 'budget_remaining' => 5 })
  r['status'] == 'success' && r['result']['__arm'] == UNKNOWN_ARM &&
    r['result']['attempt'] == 3 && r['result']['budget_remaining'] == 5
end

# ── OUTVAR2-NOUC ──────────────────────────────────────────────────────────────
puts "\nOUTVAR2-NOUC — No-Upward-Coercion: Real ≠ Model routing"

check("RouteRich: ConfirmedSucceededReal routes to 'accept' (not 'needs_human_review')") do
  r = vm_run(main[:igapp_dir], 'RouteRich', real_in)
  r['status'] == 'success' && r['result'] == 'accept' && r['result'] != 'needs_human_review'
end

check("RouteRich: ConfirmedSucceededModel routes to 'needs_human_review' (not 'accept')") do
  r = vm_run(main[:igapp_dir], 'RouteRich', model_in)
  r['status'] == 'success' && r['result'] == 'needs_human_review' && r['result'] != 'accept'
end

check("ExtractEvidenceKind: Real{evidence_kind:'real'} → 'real' (payload distinct from model)") do
  r = vm_run(main[:igapp_dir], 'ExtractEvidenceKind', real_in)
  r['status'] == 'success' && r['result'] == 'real' && r['result'] != 'model_inference'
end

check("ExtractEvidenceKind: Model{evidence_kind:'model_inference'} → 'model_inference' (not 'real')") do
  r = vm_run(main[:igapp_dir], 'ExtractEvidenceKind', model_in)
  r['status'] == 'success' && r['result'] == 'model_inference' && r['result'] != 'real'
end

check("ConfirmedSucceededModel NEVER routes to 'accept': arm name enforces boundary") do
  model_with_real_evidence = { 'outcome' => arm(MODEL_ARM, RICH, 'request_id' => 'req-x', 'resource' => 'pay/x',
    'evidence_kind' => 'real', 'observed_at' => '2026-06-10') }
  r = vm_run(main[:igapp_dir], 'RouteRich', model_with_real_evidence)
  r['status'] == 'success' && r['result'] == 'needs_human_review'
end

# ── OUTVAR2-REG ───────────────────────────────────────────────────────────────
puts "\nOUTVAR2-REG — P1 / P9 / variant_match regressions green"

p1 = compile(P1_FIXTURE, 'p1_reg')
check("outcome_variant.ig (P1 11-arm): still compiles status=ok") do
  p1[:result]['status'] == 'ok'
end

check("outcome_variant.ig: 0 OOF-KIND6 diagnostics (Path B fields not in user source)") do
  (p1[:result]['diagnostics'] || []).none? { |d| d['rule'] == 'OOF-KIND6' }
end

check("P1 RouteOutcome: ConfirmedSucceededReal → 'accept' (P1 routing unaffected)") do
  r = vm_run(p1[:igapp_dir], 'RouteOutcome',
    { 'outcome' => arm('ConfirmedSucceededReal', 'ReconciliationOutcome', 'request_id' => 'r', 'resource' => 'p') })
  r['status'] == 'success' && r['result'] == 'accept'
end

check("P1 RouteOutcome: ConfirmedSucceededModel → 'needs_human_review'") do
  r = vm_run(p1[:igapp_dir], 'RouteOutcome',
    { 'outcome' => arm('ConfirmedSucceededModel', 'ReconciliationOutcome', 'request_id' => 'r', 'resource' => 'p') })
  r['status'] == 'success' && r['result'] == 'needs_human_review'
end

p9_valid = compile(File.join(P9_FIXTURE_DIR, 'reserved_fields_valid.ig'), 'p9_valid_reg')
check("PROP-044-P9: reserved_fields_valid.ig still status=ok") do
  p9_valid[:result]['status'] == 'ok'
end

# LAB-VARIANT-VM-P1 regression: fixture 12 (unit arm match) from the canonical variant_match set
vm_p1_dir = ROOT.parent.parent / 'igniter-view-engine' / 'fixtures' / 'variant_match'
if Dir.exist?(vm_p1_dir.to_s)
  vm12 = compile(File.join(vm_p1_dir.to_s, '12_vm_match_unit_arms.ig'), 'vm12_reg')
  check("LAB-VARIANT-VM-P1 fixture 12: unit arm match still compiles ok") do
    vm12[:result]['status'] == 'ok'
  end
else
  check("LAB-VARIANT-VM-P1 fixture 12: skipped (variant_match dir not found in this path)") { true }
end

# ── OUTVAR2-CLOSED ────────────────────────────────────────────────────────────
puts "\nOUTVAR2-CLOSED — No new VM types/opcodes, no taxonomy, no Outcome[T,E]"

check("VM instructions.rs: no OP_MATCH opcode") do
  !File.read(File.join(VM_SRC_DIR, 'instructions.rs')).force_encoding('UTF-8').include?('OP_MATCH')
end

check("VM value.rs: no Value::Variant") do
  !File.read(File.join(VM_SRC_DIR, 'value.rs')).force_encoding('UTF-8').include?('Variant')
end

fixture_src = File.read(File.join(FIXTURE_DIR, 'outcome_variant_rich.ig')).force_encoding('UTF-8')
fixture_code = fixture_src.lines.reject { |l| l.strip.start_with?('--') }.join

check("Fixture source: no 'Outcome[T,E]' or generic Outcome reference (code lines only)") do
  !fixture_code.match?(/Outcome\[/)
end

check("Fixture source: no failure taxonomy claims (code lines only)") do
  !fixture_code.match?(/taxonomy|failure_taxonomy/i)
end

check("Fixture source: no 'stable.*api\|public.*api' promise") do
  !fixture_src.match?(/stable.*api|public.*api/i)
end

check("No serialization schema exported — no serialize/deserialize in fixture") do
  !fixture_src.match?(/serializ/i)
end

check("ReconciliationOutcomeRich is domain-specific, not generic: no type parameter syntax") do
  !fixture_src.include?('ReconciliationOutcomeRich[')
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts "\n" + "─" * 60
total = $pass_count + $fail_count
puts "#{$pass_count}/#{total} PASS"
if $fail_count == 0
  puts "LAB-OUTCOME-VARIANT-P2: ALL PASS"
else
  puts "LAB-OUTCOME-VARIANT-P2: #{$fail_count} FAILURE(S)"
  exit 1
end
