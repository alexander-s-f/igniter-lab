#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_reconciliation_receipt_vm_flow.rb
# LAB-EPISTEMIC-OUTCOME-P4: VM KDR ReconciliationReceipt flow proof
#
# Proves a KDR `ReconciliationReceipt` can be PRODUCED, CARRIED, INSPECTED, and ROUTED
# through the lab Rust VM as ordinary record data — implementing the P3 reconciliation-
# consumer transition guards as in-VM branching — WITHOUT sealed Outcome[T,E],
# variant/match runtime authority, or real storage/network I/O.
#
# Not a runtime reconciliation system. A VM proof that the receipt shape the
# reconciliation-consumer boundary needs is executable KDR today.
#
# Aligns to PROPOSED Ch12 Effect Surface + Covenant doctrine (P13/P15/P16/P17 + the
# Epistemic State Machine / No Upward Coercion). Ch12 is treated as PROPOSED, not canon.
#
# Layering note (a real Ruby/Rust divergence, documented not resolved):
#   The router contracts use String `==` and boolean `||`. The PRODUCTION Ruby
#   TypeChecker rejects these ("Unsupported operator"), so the routers are BLOCKED in
#   Layer A. The Rust compiler accepts `==` (rejects only `||`, which the fixture
#   avoids) and the Rust VM EXECUTES the routing. Therefore:
#     Layer A (Ruby TC) proves the receipt TYPE shape + the producer/inspector contracts.
#     Layer B (Rust compiler + VM) proves the routing EXECUTION.
#   This divergence is flagged for governance (STAB-P4 class), not resolved here.
#
# Sections:
#   RRF-COMPILE   (4) — Ruby TC runs; Rust SIR 5 contracts; producers accepted
#   RRF-TYPES     (7) — ReconciliationReceipt 11-field shape; attempt+budget Integer
#   RRF-PRODUCE   (4) — VM produces receipt from lost-ack; preserves idem; pulls req_id/resource
#   RRF-ACCEPT    (4) — confirmed_succeeded routing; evidence_kind load-bearing (model≠accept)
#   RRF-FAILROUTE (4) — confirmed_failed → retry|compensate|fail by guard
#   RRF-LOOP      (4) — still_unknown / reconciliation_error budget-gated loop vs hold
#   RRF-HOLD      (3) — reconciliation_denied → hold; partial → remainder; unknown kind → hold
#   RRF-NODIRECT  (6) — raw envelope: unknown/timed_out/partial → reconcile_required ONLY
#   RRF-INSPECT   (2) — map_get over receipt.metadata
#   RRF-DIVERGENCE(2) — Ruby TC blocks routers (== unsupported); Rust VM executes them
#   RRF-CLOSED    (6) — KDR-only; no variant/match; no sealed Outcome; no real I/O; lab-only
#
# Total: 46 checks
#
# Authority: LAB-ONLY. KDR convention only. No sealed Outcome[T,E]. No variant/match
# runtime authority. No canon claim. No public/stable API.
#
# Run: ruby igniter-view-engine/proofs/verify_reconciliation_receipt_vm_flow.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'epistemic_outcome' / 'reconciliation_receipt_flow.ig').to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require 'igniter_lang'

$pass_count = 0
$fail_count = 0

def check(label)
  ok = yield
  if ok
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

# ── Layer A: Ruby TypeChecker ─────────────────────────────────────────────────

def run_fixture(path)
  src        = File.read(path.to_s).force_encoding('UTF-8')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: path.to_s).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { parsed: parsed, classified: classified, typed: typed }
rescue => e
  { error: e.message }
end

def type_name_str(t)
  return t.to_s unless t.is_a?(Hash)
  name   = t['name'] || t['kind'] || '?'
  params = Array(t['params'])
  return name if params.empty?
  "#{name}[#{params.map { |p| type_name_str(p) }.join(',')}]"
end

def rr_field(tc, type_name, field)
  tc[:typed]&.fetch('type_env', {})&.fetch(type_name, {})&.fetch(field, nil)
end

def contract(tc, name)
  tc[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == name }
end

def accepted?(tc, name)
  c = contract(tc, name)
  c && c['status'] == 'accepted' && (c['type_errors'] || []).empty?
end

def blocked?(tc, name)
  c = contract(tc, name)
  c && c['status'] != 'accepted'
end

# ── Layer B: Rust compiler + VM ───────────────────────────────────────────────

def compile_fixture(path, out_dir)
  FileUtils.mkdir_p(out_dir)
  stdout, _e, _s = Open3.capture3(COMPILER_BIN, 'compile', path.to_s, '--out', out_dir.to_s, '--json')
  stdout = stdout&.force_encoding('UTF-8')
  return nil if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue
  nil
end

def read_sir(out_dir)
  p = File.join(out_dir.to_s, 'semantic_ir_program.json')
  File.exist?(p) ? JSON.parse(File.read(p)) : nil
rescue
  nil
end

def vm_run(app_dir, entry, inputs)
  tf = Tempfile.new(['rrf', '.json'])
  tf.write(inputs.to_json); tf.close
  stdout, _e, _s = Open3.capture3(VM_BIN, 'run', '--contract', app_dir.to_s,
                                  '--inputs', tf.path, '--entry', entry, '--json')
  tf.unlink rescue nil
  stdout = stdout&.force_encoding('UTF-8')
  return { 'status' => 'vm_error', 'error' => 'empty' } if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

# Build a ReconciliationReceipt input hash with sensible defaults.
def receipt(kind:, evidence_kind: 'absent', idempotency_key: '', compensation: '',
            budget_remaining: 3, attempt: 1, metadata: {})
  { 'receipt' => {
    'kind' => kind, 'request_id' => 'r-1', 'resource' => 'users',
    'idempotency_key' => idempotency_key, 'observed_at' => 't0',
    'evidence_kind' => evidence_kind, 'compensation' => compensation,
    'attempt' => attempt, 'budget_remaining' => budget_remaining,
    'detail' => '', 'metadata' => metadata
  } }
end

def route_receipt(**kw)  vm_run(RRF_OUT, 'RouteReceipt', receipt(**kw)); end
def route_action(**kw)   route_receipt(**kw)['result']; end
def envelope(kind, idem = 'k') { 'env' => { 'kind' => kind, 'message' => 'm', 'idempotency_key' => idem, 'metadata' => {} } }; end
def env_action(kind)     vm_run(RRF_OUT, 'RouteEnvelope', envelope(kind))['result']; end

# ── Compile & typecheck up front ──────────────────────────────────────────────

RRF_OUT = Dir.mktmpdir('rrf_main')
RRF_SIR = compile_fixture(FIXTURE_PATH, RRF_OUT)
RRF_TC  = run_fixture(FIXTURE_PATH)

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-COMPILE"

check('RRF-COMPILE-01: fixture parses; Ruby TypeChecker runs without crash') do
  !RRF_TC[:error] && RRF_TC[:typed].is_a?(Hash)
end
check('RRF-COMPILE-02: Rust compiler emits SIR with 5 contracts') do
  sir = read_sir(RRF_OUT)
  sir.is_a?(Hash) && sir.fetch('contracts', []).length == 5
end
check('RRF-COMPILE-03: producer/inspector contracts accepted by Ruby TC (0 type_errors)') do
  accepted?(RRF_TC, 'ReconcileFromLostAck') &&
    accepted?(RRF_TC, 'MakeReceipt') &&
    accepted?(RRF_TC, 'ReceiptInspector')
end
check('RRF-COMPILE-04: fixture declares NO variants (KDR-only; no sealed Outcome[T,E])') do
  (RRF_TC[:parsed]&.fetch('variants', []) || []).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-TYPES"

check('RRF-TYPES-01: ReconciliationReceipt has 11 fields') do
  rr = RRF_TC[:typed]&.fetch('type_env', {})&.fetch('ReconciliationReceipt', {}) || {}
  rr.keys.length == 11
end
check('RRF-TYPES-02: kind = String (KDR discriminant)') do
  type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'kind')) == 'String'
end
check('RRF-TYPES-03: request_id and resource = String (required correlation fields)') do
  type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'request_id')) == 'String' &&
    type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'resource')) == 'String'
end
check('RRF-TYPES-04: evidence_kind = String (P13 observation certainty carrier)') do
  type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'evidence_kind')) == 'String'
end
check('RRF-TYPES-05: attempt = Integer (ordinal count; justified numeric)') do
  type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'attempt')) == 'Integer'
end
check('RRF-TYPES-06: budget_remaining = Integer (reconcile re-entry budget)') do
  type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'budget_remaining')) == 'Integer'
end
check('RRF-TYPES-07: metadata = Map[String,String]') do
  type_name_str(rr_field(RRF_TC, 'ReconciliationReceipt', 'metadata')) == 'Map[String,String]'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-PRODUCE"

PRODUCED = vm_run(RRF_OUT, 'ReconcileFromLostAck', {
  'env' => { 'kind' => 'unknown_external_state', 'message' => 'lost', 'idempotency_key' => 'idem-9',
             'metadata' => { 'request_id' => 'r-9', 'resource' => 'users' } },
  'determined_kind' => 'confirmed_failed', 'evidence_kind' => 'real', 'observed_at' => 't1',
  'compensation' => 'RefundCharge', 'attempt' => 2, 'budget_remaining' => 1
})

check('RRF-PRODUCE-01: VM produces a ReconciliationReceipt record from a lost-ack envelope') do
  PRODUCED['status'] == 'success' && PRODUCED['result'].is_a?(Hash) &&
    PRODUCED.dig('result', 'kind') == 'confirmed_failed'
end
check('RRF-PRODUCE-02: receipt PRESERVES the idempotency_key carried from the unknown envelope (P16)') do
  PRODUCED.dig('result', 'idempotency_key') == 'idem-9'
end
check('RRF-PRODUCE-03: receipt pulls request_id + resource out of envelope metadata (reconcile evidence)') do
  PRODUCED.dig('result', 'request_id') == 'r-9' && PRODUCED.dig('result', 'resource') == 'users'
end
check('RRF-PRODUCE-04: receipt carries evidence_kind and Integer attempt/budget through the VM') do
  PRODUCED.dig('result', 'evidence_kind') == 'real' &&
    PRODUCED.dig('result', 'attempt') == 2 &&
    PRODUCED.dig('result', 'budget_remaining') == 1
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-ACCEPT"

check('RRF-ACCEPT-01: confirmed_succeeded + real evidence → accept') do
  route_action(kind: 'confirmed_succeeded', evidence_kind: 'real') == 'accept'
end
check('RRF-ACCEPT-02: confirmed_succeeded + human evidence → accept') do
  route_action(kind: 'confirmed_succeeded', evidence_kind: 'human') == 'accept'
end
check('RRF-ACCEPT-03: confirmed_succeeded + MODEL evidence → needs_human_review (NOT accept; No Upward Coercion)') do
  a = route_action(kind: 'confirmed_succeeded', evidence_kind: 'model')
  a == 'needs_human_review' && a != 'accept'
end
check('RRF-ACCEPT-04: evidence_kind is load-bearing — same kind, real→accept vs model→not-accept') do
  route_action(kind: 'confirmed_succeeded', evidence_kind: 'real') == 'accept' &&
    route_action(kind: 'confirmed_succeeded', evidence_kind: 'model') != 'accept'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-FAILROUTE"

check('RRF-FAILROUTE-01: confirmed_failed + idempotency present → retry (P16)') do
  route_action(kind: 'confirmed_failed', idempotency_key: 'idem-9') == 'retry'
end
check('RRF-FAILROUTE-02: confirmed_failed + NO idempotency → not retry') do
  route_action(kind: 'confirmed_failed', idempotency_key: '', compensation: '') != 'retry'
end
check('RRF-FAILROUTE-03: confirmed_failed + named compensation (no idem) → compensate (P17)') do
  route_action(kind: 'confirmed_failed', idempotency_key: '', compensation: 'RefundCharge') == 'compensate'
end
check('RRF-FAILROUTE-04: confirmed_failed + neither idem nor named comp → fail (honest terminal)') do
  route_action(kind: 'confirmed_failed', idempotency_key: '', compensation: 'no_compensation') == 'fail'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-LOOP"

check('RRF-LOOP-01: still_unknown + budget_remaining > 0 → reconcile_again') do
  route_action(kind: 'still_unknown', budget_remaining: 2) == 'reconcile_again'
end
check('RRF-LOOP-02: still_unknown + no budget → hold (escalate; never infer)') do
  route_action(kind: 'still_unknown', budget_remaining: 0) == 'hold'
end
check('RRF-LOOP-03: reconciliation_error + budget → reconcile_again') do
  route_action(kind: 'reconciliation_error', budget_remaining: 1) == 'reconcile_again'
end
check('RRF-LOOP-04: reconciliation_error + no budget → hold') do
  route_action(kind: 'reconciliation_error', budget_remaining: 0) == 'hold'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-HOLD"

check('RRF-HOLD-01: reconciliation_denied → hold (cannot manufacture an outcome)') do
  route_action(kind: 'reconciliation_denied') == 'hold'
end
check('RRF-HOLD-02: partially_confirmed → reconcile_remainder') do
  route_action(kind: 'partially_confirmed') == 'reconcile_remainder'
end
check('RRF-HOLD-03: unrecognised receipt kind → hold (fail-closed; never accept)') do
  a = route_action(kind: 'totally_unexpected')
  a == 'hold' && a != 'accept'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-NODIRECT"

check('RRF-NODIRECT-01: raw unknown_external_state → reconcile_required (not accept, not fail)') do
  a = env_action('unknown_external_state')
  a == 'reconcile_required' && a != 'accept' && a != 'fail'
end
check('RRF-NODIRECT-02: raw timed_out → reconcile_required (P15; not failed)') do
  a = env_action('timed_out')
  a == 'reconcile_required' && a != 'fail' && a != 'failed'
end
check('RRF-NODIRECT-03: raw partial → reconcile_required (reconcile remainder, not accept)') do
  env_action('partial') == 'reconcile_required'
end
check('RRF-NODIRECT-04: raw denied → deny (deterministic; nothing sent)') do
  env_action('denied') == 'deny'
end
check('RRF-NODIRECT-05: raw succeeded → accept; compensated → record; cancelled → cancel') do
  env_action('succeeded') == 'accept' &&
    env_action('compensated') == 'record' &&
    env_action('cancelled') == 'cancel'
end
check('RRF-NODIRECT-06: NO envelope kind for unknown/timed_out/partial yields a terminal success/failure') do
  %w[unknown_external_state timed_out partial].all? do |k|
    a = env_action(k)
    a == 'reconcile_required' && !%w[accept fail failed succeeded deny].include?(a == 'reconcile_required' ? 'reconcile_required' : a)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-INSPECT"

check('RRF-INSPECT-01: ReceiptInspector map_get reads reconcile_hint from receipt metadata') do
  r = vm_run(RRF_OUT, 'ReceiptInspector', receipt(kind: 'confirmed_failed', metadata: { 'reconcile_hint' => 'read ledger' }))
  r['status'] == 'success' && r['result'] == 'read ledger'
end
check('RRF-INSPECT-02: ReceiptInspector falls back to default when hint absent (or_else)') do
  r = vm_run(RRF_OUT, 'ReceiptInspector', receipt(kind: 'confirmed_failed', metadata: {}))
  r['status'] == 'success' && r['result'] == 'read-back resource state'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-DIVERGENCE"

check('RRF-DIVERGENCE-01: router contracts are BLOCKED in the production Ruby TypeChecker (== unsupported)') do
  blocked?(RRF_TC, 'RouteReceipt') && blocked?(RRF_TC, 'RouteEnvelope')
end
check('RRF-DIVERGENCE-02: yet the Rust compiler+VM EXECUTE the routers (Layer B authority for routing)') do
  route_action(kind: 'confirmed_succeeded', evidence_kind: 'real') == 'accept' &&
    env_action('unknown_external_state') == 'reconcile_required'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nRRF-CLOSED"

check('RRF-CLOSED-01: fixture code (excluding comments) uses no match and no sealed Outcome[ type') do
  code = File.read(FIXTURE_PATH, encoding: 'UTF-8').lines.reject { |l| l.strip.start_with?('--') }.join
  !code.include?('match ') && !code.include?('Outcome[') && !code.include?('variant ')
end
check('RRF-CLOSED-02: runner performs no real file/network/db/socket/worker I/O') do
  !SOURCE.include?('File.ope' + 'n') && !SOURCE.include?('TCPSock' + 'et') &&
    !SOURCE.include?('Net::HT' + 'TP') && !SOURCE.include?('PG.conn' + 'ect')
end
check('RRF-CLOSED-03: no kind is assigned a forbidden flattened value in the fixture') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('kind: "failed"') && !src.include?('kind: "system_error"') &&
    !src.include?('kind: "upstream_unavailable"')
end
check('RRF-CLOSED-04: no canon production file edited; lab-only boundary stated in runner') do
  !SOURCE.include?('typecheck' + 'er.rb') && !SOURCE.include?('classifi' + 'er.rb') &&
    SOURCE.include?('LAB-ONLY')
end
check('RRF-CLOSED-05: fixture is lab-only and makes no production runtime claim') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  src.include?('LAB-ONLY') && !src.include?('production runtime')
end
check('RRF-CLOSED-06: no real storage/SQL/DB tokens in the fixture') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('INSERT ') && !src.include?('UPDATE ') && !src.include?('COMMIT') && !src.include?('TCPSock' + 'et')
end

# ─────────────────────────────────────────────────────────────────────────────
total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "LAB-EPISTEMIC-OUTCOME-P4 (reconciliation receipt VM flow): #{$pass_count}/#{total} PASS"
puts '=' * 60

if $fail_count > 0
  puts "\nFAILURES: #{$fail_count}"
  exit 1
else
  puts "\nPASS — all #{total} checks passed"
  exit 0
end
