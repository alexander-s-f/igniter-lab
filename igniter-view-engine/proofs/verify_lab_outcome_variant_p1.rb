#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
#
# verify_lab_outcome_variant_p1.rb — LAB-OUTCOME-VARIANT-P1 proof script
#
# Proves that the epistemic outcome / reconciliation routing model can be
# expressed as real `variant` + `match` Igniter source and executed through
# the full Rust lab path: source → TypeChecker OOF-KIND enforcement →
# SemanticIR match_node → VM Path B lowering → executed routing result.
#
# This is the first proof that Igniter can move from KDR convention
# (kind: String) to enforced variant surface for outcome routing.
#
# Core formula:
#   ReconciliationOutcome variant (11 arms)
#   + exhaustive match RouteOutcome
#   + build contracts (payload-carrying arms)
#   + RouteBuiltOutcome (construct + route in one contract)
#   → VM-executed action strings
#
# Sections:
#   OUTVAR-COMPILE  (6)  — fixture compiles, no OOF-KIND, SIR has variant_declarations + match_node
#   OUTVAR-SIR      (6)  — SIR shape: 11 arms, payload fields, exhaustive, no wildcard, String result
#   OUTVAR-VM       (16) — all 11 arms route correctly; payload fields survive; RouteBuiltOutcome works
#   OUTVAR-OOF      (10) — OOF-KIND1..5 all fire; OOF fixtures produce no valid SIR
#   OUTVAR-KDR-EQUIV (8) — compare against P4 KDR routing table (representative equivalence)
#   OUTVAR-NO-UPWARD (5) — No-Upward-Coercion: model→not accept; unknown→not retry; denied→not success
#   OUTVAR-CLOSED   (7)  — closed surfaces: no Outcome[T,E], no taxonomy, no new opcodes, etc.
#
# Total: 58 checks
#
# Depends on:
#   LAB-EPISTEMIC-OUTCOME-P1..P4
#   PROP-044-P1..P6 + P7-READINESS
#   LAB-VARIANT-RUST-P1 (39/39)
#   LAB-VARIANT-VM-P1   (42/42)
#
# Hard constraints (from card LAB-OUTCOME-VARIANT-P1):
#   - NO generic sealed Outcome[T,E]
#   - NO failure taxonomy proposal
#   - NO Ruby canon changes
#   - NO new VM opcodes, NO Value::Variant
#   - NO production runtime claim
#   - NO real storage/network/DB I/O
#   - NO automatic retry/compensation execution
#   - NO upward coercion (model→accept, unknown→retry, denied→success)
#
# Run: ruby igniter-lab/igniter-view-engine/proofs/verify_lab_outcome_variant_p1.rb
#
# Authority: lab_only — not canon, not production.

require 'json'
require 'open3'
require 'tempfile'
require 'pathname'
require 'fileutils'

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
COMPILER_BIN = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN       = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_DIR  = (ROOT / 'fixtures' / 'epistemic_outcome').to_s
VM_SRC_DIR   = (LAB_ROOT / 'igniter-vm' / 'src').to_s

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

$igapp_cache = {}

def compile(fixture_path, out_suffix = nil)
  key = fixture_path
  return $igapp_cache[key] if $igapp_cache.key?(key)
  tag = out_suffix || File.basename(fixture_path, '.ig').gsub(/[^a-z0-9_]/, '_')
  out_dir = "/tmp/outvar_p1_#{tag}"
  FileUtils.mkdir_p(out_dir)
  stdout, _stderr, _st = Open3.capture3(COMPILER_BIN, 'compile', fixture_path.to_s, '--out', out_dir, '--json')
  result = JSON.parse(stdout.force_encoding('UTF-8'))
  sir = begin
    path = File.join(out_dir, 'semantic_ir_program.json')
    File.exist?(path) ? JSON.parse(File.read(path)) : nil
  rescue; nil end
  entry = { result: result, igapp_dir: out_dir, sir: sir }
  $igapp_cache[key] = entry
end

def vm_run(igapp_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['outvar_p1_', '.json'])
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

def variant_input(arm, variant = 'ReconciliationOutcome', fields = {})
  { '__arm' => arm, '__variant' => variant }.merge(fields)
end

FileUtils.mkdir_p('/tmp/outvar_p1_compile')

MAIN_FIXTURE = File.join(FIXTURE_DIR, 'outcome_variant.ig')

# Pre-compile the main fixture once
main = compile(MAIN_FIXTURE, 'main')

# ── OUTVAR-COMPILE ────────────────────────────────────────────────────────────
puts "\nOUTVAR-COMPILE — Main fixture compiles through Rust compiler"

check("outcome_variant.ig compiles → status=ok") do
  main[:result]['status'] == 'ok'
end

check("no OOF-G1 diagnostic (variant/match keywords recognized)") do
  diags = main[:result]['diagnostics'] || []
  diags.none? { |d| d['rule'] == 'OOF-G1' }
end

check("no OOF-KIND diagnostics in valid fixture") do
  diags = main[:result]['diagnostics'] || []
  diags.none? { |d| d['rule']&.start_with?('OOF-KIND') }
end

check("SemanticIR contains variant_declarations at top level") do
  sir = main[:sir]
  sir && sir.key?('variant_declarations') && !sir['variant_declarations'].empty?
end

check("SemanticIR contains contracts with match_node") do
  sir = main[:sir]
  sir && sir['contracts']&.any? do |c|
    nodes = c['compute_nodes'] || c['nodes'] || []
    nodes.any? do |n|
      e = n['expression'] || n['expr']
      e && e['kind'] == 'match_node'
    end
  end
end

check("all 11 contracts compile (RouteOutcome + 9 build + RouteBuiltOutcome)") do
  sir = main[:sir]
  sir && sir['contracts']&.length == 11
end

# ── OUTVAR-SIR ────────────────────────────────────────────────────────────────
puts "\nOUTVAR-SIR — SemanticIR shape: variant_decl, payload fields, match_node"

check("ReconciliationOutcome variant_decl has 11 arms") do
  sir = main[:sir]
  vd = sir&.dig('variant_declarations')&.find { |v| v['name'] == 'ReconciliationOutcome' }
  vd && vd['arms']&.length == 11
end

check("ConfirmedSucceededReal arm declares request_id and resource fields") do
  sir = main[:sir]
  vd = sir&.dig('variant_declarations')&.find { |v| v['name'] == 'ReconciliationOutcome' }
  arm = vd&.dig('arms')&.find { |a| a['name'] == 'ConfirmedSucceededReal' }
  field_names = arm&.dig('fields')&.map { |f| f['name'] } || []
  field_names.include?('request_id') && field_names.include?('resource')
end

check("StillUnknownWithBudget arm declares Integer budget_remaining field") do
  sir = main[:sir]
  vd = sir&.dig('variant_declarations')&.find { |v| v['name'] == 'ReconciliationOutcome' }
  arm = vd&.dig('arms')&.find { |a| a['name'] == 'StillUnknownWithBudget' }
  br_field = arm&.dig('fields')&.find { |f| f['name'] == 'budget_remaining' }
  br_field && br_field.dig('type', 'name') == 'Integer'
end

check("RouteOutcome match_node is exhaustive") do
  sir = main[:sir]
  route_contract = sir&.dig('contracts')&.find { |c| c['contract_name'] == 'RouteOutcome' || c['name'] == 'RouteOutcome' }
  nodes = route_contract&.dig('compute_nodes') || route_contract&.dig('nodes') || []
  mn = nodes.find { |n| (n['expression'] || n['expr'])&.dig('kind') == 'match_node' }
  (mn&.dig('expression') || mn&.dig('expr'))&.dig('exhaustive') == true
end

check("RouteOutcome match_node has_wildcard = false") do
  sir = main[:sir]
  route_contract = sir&.dig('contracts')&.find { |c| c['contract_name'] == 'RouteOutcome' || c['name'] == 'RouteOutcome' }
  nodes = route_contract&.dig('compute_nodes') || route_contract&.dig('nodes') || []
  mn = nodes.find { |n| (n['expression'] || n['expr'])&.dig('kind') == 'match_node' }
  (mn&.dig('expression') || mn&.dig('expr'))&.dig('has_wildcard') == false
end

check("RouteOutcome match_node resolved_type is String") do
  sir = main[:sir]
  route_contract = sir&.dig('contracts')&.find { |c| c['contract_name'] == 'RouteOutcome' || c['name'] == 'RouteOutcome' }
  nodes = route_contract&.dig('compute_nodes') || route_contract&.dig('nodes') || []
  mn = nodes.find { |n| (n['expression'] || n['expr'])&.dig('kind') == 'match_node' }
  (mn&.dig('expression') || mn&.dig('expr'))&.dig('resolved_type', 'name') == 'String'
end

# ── OUTVAR-VM ─────────────────────────────────────────────────────────────────
puts "\nOUTVAR-VM — VM routes all 11 arms; payload fields survive; RouteBuiltOutcome works"

EXPECTED_ROUTES = {
  'ConfirmedSucceededReal'       => 'accept',
  'ConfirmedSucceededHuman'      => 'accept',
  'ConfirmedSucceededModel'      => 'needs_human_review',
  'ConfirmedFailedRetryable'     => 'retry',
  'ConfirmedFailedCompensatable' => 'compensate',
  'ConfirmedFailedTerminal'      => 'fail',
  'StillUnknownWithBudget'       => 'reconcile_again',
  'StillUnknownNoBudget'         => 'hold',
  'PartiallyConfirmed'           => 'reconcile_remainder',
  'ReconciliationDenied'         => 'hold',
  'ReconciliationError'          => 'hold'
}.freeze

EXPECTED_ROUTES.each do |arm, expected_action|
  check("#{arm} → #{expected_action}") do
    r = vm_run(main[:igapp_dir], 'RouteOutcome', { 'outcome' => variant_input(arm) })
    r['status'] == 'success' && r['result'] == expected_action
  end
end

check("BuildSucceededReal: payload fields request_id + resource in output record") do
  r = vm_run(main[:igapp_dir], 'BuildSucceededReal',
             { 'request_id' => 'req-001', 'resource' => 'payment/123' })
  r['status'] == 'success' &&
    r['result']['__arm'] == 'ConfirmedSucceededReal' &&
    r['result']['request_id'] == 'req-001' &&
    r['result']['resource'] == 'payment/123'
end

check("BuildStillUnknownWithBudget: Integer fields attempt + budget_remaining survive VM") do
  r = vm_run(main[:igapp_dir], 'BuildStillUnknownWithBudget',
             { 'request_id' => 'req-007', 'attempt' => 3, 'budget_remaining' => 5 })
  r['status'] == 'success' &&
    r['result']['__arm'] == 'StillUnknownWithBudget' &&
    r['result']['attempt'] == 3 &&
    r['result']['budget_remaining'] == 5
end

check("BuildFailedRetryable: idempotency_key field survives VM lowering") do
  r = vm_run(main[:igapp_dir], 'BuildFailedRetryable',
             { 'request_id' => 'req-003', 'idempotency_key' => 'idem-abc' })
  r['status'] == 'success' &&
    r['result']['__arm'] == 'ConfirmedFailedRetryable' &&
    r['result']['idempotency_key'] == 'idem-abc'
end

check("RouteBuiltOutcome constructs ConfirmedSucceededReal in-contract → action=accept") do
  r = vm_run(main[:igapp_dir], 'RouteBuiltOutcome',
             { 'request_id' => 'req-rbo', 'resource' => 'item/999' })
  r['status'] == 'success' && r['result'] == 'accept'
end

check("all 11 arms return non-nil String (no silent nil routing)") do
  EXPECTED_ROUTES.keys.all? do |arm|
    r = vm_run(main[:igapp_dir], 'RouteOutcome', { 'outcome' => variant_input(arm) })
    r['status'] == 'success' && r['result'].is_a?(String) && !r['result'].nil?
  end
end

# ── OUTVAR-OOF ────────────────────────────────────────────────────────────────
puts "\nOUTVAR-OOF — OOF-KIND1..5 all fire; OOF fixtures emit no valid SIR"

OOF_FIXTURES = {
  1 => { file: 'outcome_variant_oof_kind1.ig', rule: 'OOF-KIND1', desc: 'non-exhaustive match' },
  2 => { file: 'outcome_variant_oof_kind2.ig', rule: 'OOF-KIND2', desc: 'unknown arm NonExistent' },
  3 => { file: 'outcome_variant_oof_kind3.ig', rule: 'OOF-KIND3', desc: 'duplicate arm Succeeded' },
  4 => { file: 'outcome_variant_oof_kind4.ig', rule: 'OOF-KIND4', desc: 'non-variant String subject' },
  5 => { file: 'outcome_variant_oof_kind5.ig', rule: 'OOF-KIND5', desc: 'divergent arm types' }
}.freeze

OOF_FIXTURES.each do |n, spec|
  fixture_path = File.join(FIXTURE_DIR, spec[:file])
  oof = compile(fixture_path, "oof#{n}")

  check("OOF-KIND#{n} (#{spec[:desc]}) diagnostic fires") do
    diags = oof[:result]['diagnostics'] || []
    diags.any? { |d| d['rule'] == spec[:rule] }
  end

  check("OOF-KIND#{n} fixture produces no valid SemanticIR (status != ok)") do
    oof[:result]['status'] != 'ok'
  end
end

# ── OUTVAR-KDR-EQUIV ──────────────────────────────────────────────────────────
puts "\nOUTVAR-KDR-EQUIV — Representative equivalence to P4 KDR routing table"

# P4 KDR (LAB-EPISTEMIC-OUTCOME-P4) used kind: String comparison to route.
# This proof re-expresses the same routing as exhaustive variant match.
# The following checks confirm that representative P4 routing actions are
# reproduced exactly by the variant match. (This is representative, not
# full dual-implementation: the P4 fixture uses String kind, this uses variant.)

KDR_EQUIV_CASES = [
  ['ConfirmedSucceededReal',       'accept',            'confirmed_succeeded real → accept'],
  ['ConfirmedSucceededHuman',      'accept',            'confirmed_succeeded human → accept'],
  ['ConfirmedSucceededModel',      'needs_human_review','confirmed_succeeded model → needs_human_review'],
  ['ConfirmedFailedRetryable',     'retry',             'confirmed_failed retryable → retry'],
  ['ConfirmedFailedCompensatable', 'compensate',        'confirmed_failed compensatable → compensate'],
  ['StillUnknownWithBudget',       'reconcile_again',   'still_unknown + budget → reconcile_again'],
  ['ReconciliationDenied',         'hold',              'reconciliation_denied → hold'],
  ['ReconciliationError',          'hold',              'reconciliation_error → hold'],
].freeze

KDR_EQUIV_CASES.each do |arm, expected_action, desc|
  check("KDR equiv: #{desc}") do
    r = vm_run(main[:igapp_dir], 'RouteOutcome', { 'outcome' => variant_input(arm) })
    r['status'] == 'success' && r['result'] == expected_action
  end
end

# ── OUTVAR-NO-UPWARD ──────────────────────────────────────────────────────────
puts "\nOUTVAR-NO-UPWARD — No-Upward-Coercion: forbidden transitions are absent arm names"

check("ConfirmedSucceededModel routes to needs_human_review, NOT accept") do
  r = vm_run(main[:igapp_dir], 'RouteOutcome',
             { 'outcome' => variant_input('ConfirmedSucceededModel') })
  r['status'] == 'success' && r['result'] == 'needs_human_review' && r['result'] != 'accept'
end

check("StillUnknownWithBudget routes to reconcile_again, NOT retry or compensate") do
  r = vm_run(main[:igapp_dir], 'RouteOutcome',
             { 'outcome' => variant_input('StillUnknownWithBudget') })
  r['status'] == 'success' &&
    r['result'] == 'reconcile_again' &&
    r['result'] != 'retry' &&
    r['result'] != 'compensate'
end

check("ReconciliationDenied routes to hold, NOT accept or retry or compensate") do
  r = vm_run(main[:igapp_dir], 'RouteOutcome',
             { 'outcome' => variant_input('ReconciliationDenied') })
  r['status'] == 'success' &&
    r['result'] == 'hold' &&
    r['result'] != 'accept' &&
    r['result'] != 'retry' &&
    r['result'] != 'compensate'
end

check("ReconciliationError routes to hold, NOT accept (error is not success)") do
  r = vm_run(main[:igapp_dir], 'RouteOutcome',
             { 'outcome' => variant_input('ReconciliationError') })
  r['status'] == 'success' && r['result'] == 'hold' && r['result'] != 'accept'
end

check("ConfirmedSucceededModel and ConfirmedSucceededReal are distinct arms (no string collapse)") do
  # Enforce: model evidence cannot be an alias for real evidence.
  # These are separate named arms, not hidden behind a shared string check.
  sir = main[:sir]
  vd = sir&.dig('variant_declarations')&.find { |v| v['name'] == 'ReconciliationOutcome' }
  arm_names = vd&.dig('arms')&.map { |a| a['name'] } || []
  arm_names.include?('ConfirmedSucceededModel') && arm_names.include?('ConfirmedSucceededReal')
end

# ── OUTVAR-CLOSED ─────────────────────────────────────────────────────────────
puts "\nOUTVAR-CLOSED — Closed surfaces"

instructions_src = File.read(File.join(VM_SRC_DIR, 'instructions.rs')).force_encoding('UTF-8') rescue ''
vm_src           = File.read(File.join(VM_SRC_DIR, 'vm.rs')).force_encoding('UTF-8')           rescue ''
value_src        = File.read(File.join(VM_SRC_DIR, 'value.rs')).force_encoding('UTF-8')        rescue ''
main_fixture_src = File.read(MAIN_FIXTURE).force_encoding('UTF-8')                             rescue ''

check("no generic Outcome[T,E] defined as variant or type in fixture") do
  # Comments stating 'No sealed Outcome[T,E]' are correct docstring practice — only
  # flag actual type/variant definitions that would introduce the sealed type.
  !main_fixture_src.match?(/^\s*(variant|type)\s+Outcome\s*\[/)
end

check("no failure taxonomy declaration in fixture source") do
  !main_fixture_src.match?(/failure_taxonomy|FailureTaxonomy|failure taxonomy/i)
end

check("no OP_MATCH or OP_PUSH_VARIANT in instructions.rs") do
  !instructions_src.match?(/OP_MATCH\s*=|OP_PUSH_VARIANT\s*=/)
end

check("no Value::Variant in value.rs") do
  !value_src.match?(/Variant\s*[({]/)
end

check("no real storage/network/DB keywords in fixture source") do
  bad = /\bDB\b|\bSQL\b|\bORM\b|\bHTTP\b|\bTCP\b|\bdatabase\b/i
  !main_fixture_src.match?(bad)
end

check("no automatic retry/compensation execution in fixture source") do
  bad = /exec_retry|exec_compensate|run_retry|apply_compensation/i
  !main_fixture_src.match?(bad)
end

check("no affirmative 'sealed Outcome[T,E]' claim (deny-comment is correct)") do
  # The fixture comment 'No sealed Outcome[T,E]' is correct docstring practice.
  # Flag only affirmative usage: a sentence that asserts the type is sealed.
  !main_fixture_src.match?(/this is.*sealed.*Outcome|Outcome\[T,E\].*is.*sealed/i)
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts "\n" + ("─" * 60)
total = $pass_count + $fail_count
puts "#{$pass_count}/#{total} PASS"

if $fail_count.zero?
  puts "LAB-OUTCOME-VARIANT-P1: ALL PASS"
else
  puts "LAB-OUTCOME-VARIANT-P1: #{$fail_count} FAIL"
  exit 1
end
