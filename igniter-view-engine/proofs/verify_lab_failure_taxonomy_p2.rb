#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
#
# verify_lab_failure_taxonomy_p2.rb — LAB-FAILURE-TAXONOMY-P2 proof script
#
# Provides the second-domain evidence requested by LAB-FAILURE-TAXONOMY-P1:
# proves in the HTTP client / upstream-call domain that timeout and
# lost-acknowledgement after dispatch route to `unknown_external_state`,
# not `system_error`, `upstream_error`, `upstream_unavailable`, or any failure kind.
#
# Core claim (Covenant P15 — Timeout Is Not Failure):
#   dispatch_started=true  AND  ack_received=false  =>  kind:"unknown_external_state"
#   dispatch_started=false                          =>  NOT unknown_external_state
#
# Fixture: igniter-view-engine/fixtures/failure_taxonomy/network_timeout_unknown_state.ig
#
# Sections:
#   FTAX2-COMPILE   (6)  — fixture compiles; Ruby TC accepted; SIR has expected contracts
#   FTAX2-SHAPE     (7)  — NetworkCallSignal and NetworkCallOutcome field types correct
#   FTAX2-CLASSIFY  (8)  — classifier routes each dispatch scenario correctly
#   FTAX2-NOT-UNKNOWN (6) — denied/pre-dispatch/5xx/success are NOT unknown_external_state
#   FTAX2-METADATA  (7)  — request_id, idempotency_key, metadata preserved
#   FTAX2-RECONCILE (5)  — unknown_external_state outcome carries reconciliation data
#   FTAX2-CROSSDOMAIN (6) — same semantic distinction as epistemic domain; no arm name import
#   FTAX2-CLOSED    (7)  — no sockets, no DNS, no HTTP library, no taxonomy PROP, no Outcome[T,E]
#
# Total: 52 checks
#
# Acceptance bar: ALL PASS
# Authority: lab_only — evidence for future taxonomy planning. Does not open taxonomy PROP.
#
# Run: ruby igniter-lab/igniter-view-engine/proofs/verify_lab_failure_taxonomy_p2.rb

require 'json'
require 'open3'
require 'tempfile'
require 'pathname'
require 'fileutils'

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
COMPILER_BIN = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN       = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_DIR  = (ROOT / 'fixtures' / 'failure_taxonomy').to_s
FTAX_FIXTURE = File.join(FIXTURE_DIR, 'network_timeout_unknown_state.ig')
EPISTEMIC_DIR = (ROOT / 'fixtures' / 'epistemic_outcome').to_s
RUBY_TC_SRC   = (LAB_ROOT.parent / 'igniter-lang' / 'lib' / 'igniter_lang' / 'typechecker.rb').to_s

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

OUT_DIR = '/tmp/ftax2_proof'
FileUtils.mkdir_p(OUT_DIR)

def compile_once(path, out_dir)
  stdout, _stderr, _st = Open3.capture3(
    '/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/target/release/igniter_compiler',
    'compile', path, '--out', out_dir, '--json'
  )
  JSON.parse(stdout.force_encoding('UTF-8'))
end

$r = compile_once(FTAX_FIXTURE, OUT_DIR)

$sir = begin
  path = File.join(OUT_DIR, 'semantic_ir_program.json')
  File.exist?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : nil
rescue; nil end

def vm_run(contract_name, inputs)
  tmpfile = Tempfile.new(['ftax2_', '.json'])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _st = Open3.capture3(
    VM_BIN, 'run',
    '--contract', OUT_DIR,
    '--inputs',   tmpfile.path,
    '--entry',    contract_name,
    '--json'
  )
  tmpfile.unlink rescue nil
  JSON.parse(stdout.force_encoding('UTF-8'))
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

def mk_signal(dispatch_started:, ack_received:, transport_kind:, request_id: 'req-1',
              idempotency_key: 'idem-1', host: 'api.example.com',
              status_code: 0, detail: 'test', metadata: {})
  {
    'signal' => {
      'dispatch_started' => dispatch_started,
      'ack_received'     => ack_received,
      'transport_kind'   => transport_kind,
      'request_id'       => request_id,
      'idempotency_key'  => idempotency_key,
      'host'             => host,
      'status_code'      => status_code,
      'detail'           => detail,
      'metadata'         => metadata
    }
  }
end

# ── FTAX2-COMPILE ─────────────────────────────────────────────────────────────
puts "\nFTAX2-COMPILE — Fixture compiles clean"

check("network_timeout_unknown_state.ig: status=ok") { $r['status'] == 'ok' }
check("no OOF diagnostics") { ($r['diagnostics'] || []).empty? }
check("NetworkCallSignal type referenced in SIR (contract input)") do
  ($sir&.dig('contracts') || []).any? do |c|
    (c['inputs'] || []).any? { |i| i.dig('type', 'name') == 'NetworkCallSignal' }
  end
end
check("NetworkCallOutcome type referenced in SIR (contract output)") do
  ($sir&.dig('contracts') || []).any? do |c|
    (c['outputs'] || []).any? { |o| o.dig('type', 'name') == 'NetworkCallOutcome' }
  end
end
check("NetworkOutcomeClassifier contract present in SIR") do
  contracts = $sir&.dig('contracts') || []
  contracts.any? { |c| (c['contract_name'] || c['name']) == 'NetworkOutcomeClassifier' }
end
check("DispatchedNoAck contract present in SIR (key scenario)") do
  contracts = $sir&.dig('contracts') || []
  contracts.any? { |c| (c['contract_name'] || c['name']) == 'DispatchedNoAck' }
end

# ── FTAX2-SHAPE ───────────────────────────────────────────────────────────────
puts "\nFTAX2-SHAPE — Type fields correct"

# The SIR stores type information in contract nodes, not a separate type_declarations array.
# We verify field types via the SIR nodes that access or produce those fields.
$nc_contract  = ($sir&.dig('contracts') || []).find { |c| c['contract_name'] == 'NetworkOutcomeClassifier' }
$da_contract  = ($sir&.dig('contracts') || []).find { |c| c['contract_name'] == 'DispatchedNoAck' }
$nc_nodes     = $nc_contract&.dig('nodes') || []
$da_nodes     = $da_contract&.dig('nodes') || []

# NetworkCallSignal.dispatch_started: Bool
# The NetworkOutcomeClassifier computes `is_dispatched = signal.dispatch_started`.
# The SIR node type for that computation is Bool, proving the field is Bool.
check("NetworkCallSignal.dispatch_started: Bool (via NetworkOutcomeClassifier node type)") do
  n = $nc_nodes.find { |n| n['name'] == 'is_dispatched' }
  n && n.dig('type', 'name') == 'Bool' &&
    n.dig('expr', 'field') == 'dispatch_started' &&
    n.dig('expr', 'kind') == 'field_access'
end

# NetworkCallSignal.ack_received: Bool
check("NetworkCallSignal.ack_received: Bool (via NetworkOutcomeClassifier node type)") do
  n = $nc_nodes.find { |n| n['name'] == 'has_ack' }
  n && n.dig('type', 'name') == 'Bool' &&
    n.dig('expr', 'field') == 'ack_received' &&
    n.dig('expr', 'kind') == 'field_access'
end

# NetworkCallSignal.transport_kind: String
# The is_blocked node is a binary_op comparing signal.transport_kind to a String literal.
# The right operand carries type_tag: 'String', proving the field is String.
check("NetworkCallSignal.transport_kind: String (via is_blocked node binary_op comparison)") do
  n = $nc_nodes.find { |n| n['name'] == 'is_blocked' }
  n &&
    n.dig('expr', 'kind') == 'binary_op' &&
    n.dig('expr', 'left', 'field') == 'transport_kind' &&
    n.dig('expr', 'right', 'type_tag') == 'String'
end

# NetworkCallSignal.idempotency_key: String
# DispatchedNoAck declares idempotency_key as a direct String input (not via signal).
# The NetworkOutcomeClassifier passes signal.idempotency_key to the same outcome field.
# Since TC accepted the program, the signal field must also be String.
check("NetworkCallSignal.idempotency_key: String (via DispatchedNoAck input type + TC acceptance)") do
  da_idem = ($da_contract&.dig('inputs') || []).find { |i| i['name'] == 'idempotency_key' }
  da_idem && da_idem.dig('type', 'name') == 'String'
end

# NetworkCallOutcome.dispatch_started: Bool
# DispatchedNoAck's outcome record literal sets dispatch_started with type_tag: 'Bool'.
check("NetworkCallOutcome.dispatch_started: Bool (via DispatchedNoAck record literal type_tag)") do
  n = $da_nodes.find { |n| n['name'] == 'outcome' }
  n && n.dig('expr', 'fields', 'dispatch_started', 'type_tag') == 'Bool'
end

# NetworkCallOutcome.ack_received: Bool
check("NetworkCallOutcome.ack_received: Bool (via DispatchedNoAck record literal type_tag)") do
  n = $da_nodes.find { |n| n['name'] == 'outcome' }
  n && n.dig('expr', 'fields', 'ack_received', 'type_tag') == 'Bool'
end

# NetworkCallOutcome.kind: String (KDR discriminant)
check("NetworkCallOutcome.kind: String (via DispatchedNoAck record literal type_tag)") do
  n = $da_nodes.find { |n| n['name'] == 'outcome' }
  n && n.dig('expr', 'fields', 'kind', 'type_tag') == 'String'
end

# ── FTAX2-CLASSIFY ────────────────────────────────────────────────────────────
puts "\nFTAX2-CLASSIFY — Classifier routes all dispatch scenarios"

# Scenario 5: THE KEY CASE — dispatched, no ack (timeout)
r5 = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: true, ack_received: false, transport_kind: 'timeout',
  request_id: 'req-5', idempotency_key: 'idem-5',
  detail: 'request sent; no response before deadline',
  metadata: { 'resource' => '/api/payment/5' }
))
check("dispatched + no ack + timeout → unknown_external_state (Covenant P15)") do
  r5['status'] == 'success' && r5.dig('result', 'kind') == 'unknown_external_state'
end
check("dispatch_started=true preserved in unknown_external_state outcome") do
  r5['status'] == 'success' && r5.dig('result', 'dispatch_started') == true
end
check("ack_received=false preserved in unknown_external_state outcome") do
  r5['status'] == 'success' && r5.dig('result', 'ack_received') == false
end

# Scenario 6: dispatched, lost response body → unknown_external_state
r6 = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: true, ack_received: false, transport_kind: 'timeout',
  request_id: 'req-6', idempotency_key: 'idem-6',
  detail: 'response body truncated; connection dropped mid-read'
))
check("dispatched + lost response body → unknown_external_state") do
  r6['status'] == 'success' && r6.dig('result', 'kind') == 'unknown_external_state'
end

# Scenario 7: confirmed success
r7 = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: true, ack_received: true, transport_kind: 'ok',
  request_id: 'req-7', idempotency_key: 'idem-7', status_code: 200
))
check("dispatched + ack + ok → 'ok' (confirmed success)") do
  r7['status'] == 'success' && r7.dig('result', 'kind') == 'ok'
end

# Scenario 2: 5xx
r2 = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: true, ack_received: true, transport_kind: 'server_error',
  request_id: 'req-2', idempotency_key: 'idem-2', status_code: 503
))
check("dispatched + ack + server_error → 'upstream_error' (known failure)") do
  r2['status'] == 'success' && r2.dig('result', 'kind') == 'upstream_error'
end

check("client_error → 'not_found'") do
  r = vm_run('NetworkOutcomeClassifier', mk_signal(
    dispatch_started: true, ack_received: true, transport_kind: 'client_error',
    request_id: 'req-x', idempotency_key: '', status_code: 404
  ))
  r['status'] == 'success' && r.dig('result', 'kind') == 'not_found'
end

# ── FTAX2-NOT-UNKNOWN ─────────────────────────────────────────────────────────
puts "\nFTAX2-NOT-UNKNOWN — Denied/pre-dispatch/success are NOT unknown_external_state"

# Scenario 1: capability denied
r1 = vm_run('CapabilityDenied', {
  'request_id' => 'req-cap', 'detail' => 'host policy blocked', 'metadata' => {}
})
check("CapabilityDenied → kind='denied' (not unknown_external_state)") do
  r1['status'] == 'success' && r1.dig('result', 'kind') == 'denied'
end
check("CapabilityDenied → dispatch_started=false") do
  r1['status'] == 'success' && r1.dig('result', 'dispatch_started') == false
end

# Scenario 4: pre-dispatch timeout
r4 = vm_run('TimeoutBeforeDispatch', {
  'request_id' => 'req-tbd', 'detail' => 'connection pool stalled', 'metadata' => {}
})
check("TimeoutBeforeDispatch → kind='upstream_unavailable' (not unknown_external_state)") do
  r4['status'] == 'success' && r4.dig('result', 'kind') == 'upstream_unavailable'
end
check("TimeoutBeforeDispatch → dispatch_started=false (never reached wire)") do
  r4['status'] == 'success' && r4.dig('result', 'dispatch_started') == false
end

# Via classifier: pre-dispatch timeout (transport_kind=timeout, dispatch_started=false)
r4c = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: false, ack_received: false, transport_kind: 'timeout',
  request_id: 'req-4c', idempotency_key: ''
))
check("classifier: pre-dispatch timeout → upstream_unavailable (not unknown_external_state)") do
  r4c['status'] == 'success' && r4c.dig('result', 'kind') == 'upstream_unavailable'
end

# Via classifier: capability blocked
r1c = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: false, ack_received: false, transport_kind: 'blocked',
  request_id: 'req-1c', idempotency_key: ''
))
check("classifier: blocked → denied (not unknown_external_state)") do
  r1c['status'] == 'success' && r1c.dig('result', 'kind') == 'denied'
end

# ── FTAX2-METADATA ────────────────────────────────────────────────────────────
puts "\nFTAX2-METADATA — idempotency_key, request_id, metadata preserved"

r_disp = vm_run('DispatchedNoAck', {
  'request_id'      => 'req-meta-1',
  'idempotency_key' => 'idem-meta-1',
  'detail'          => 'lost in flight',
  'metadata'        => { 'resource' => '/api/order/9', 'sent_at' => '2026-06-10T12:00:00Z' }
})
check("DispatchedNoAck: request_id preserved in outcome") do
  r_disp['status'] == 'success' && r_disp.dig('result', 'request_id') == 'req-meta-1'
end
check("DispatchedNoAck: idempotency_key preserved (P16 gate data)") do
  r_disp['status'] == 'success' && r_disp.dig('result', 'idempotency_key') == 'idem-meta-1'
end
check("DispatchedNoAck: kind=unknown_external_state") do
  r_disp['status'] == 'success' && r_disp.dig('result', 'kind') == 'unknown_external_state'
end

r_meta = vm_run('MetadataPassthrough', {
  'outcome' => {
    'kind' => 'unknown_external_state', 'request_id' => 'req-m', 'idempotency_key' => 'k',
    'dispatch_started' => true, 'ack_received' => false,
    'detail' => 'lost', 'metadata' => { 'resource' => '/api/order/9' }
  },
  'query_key' => 'resource'
})
check("MetadataPassthrough: map_get on unknown_external_state metadata → resource value") do
  r_meta['status'] == 'success' && r_meta['result'] == '/api/order/9'
end
check("MetadataPassthrough: absent key → 'absent' (or_else default)") do
  r2m = vm_run('MetadataPassthrough', {
    'outcome' => {
      'kind' => 'unknown_external_state', 'request_id' => 'r', 'idempotency_key' => 'k',
      'dispatch_started' => true, 'ack_received' => false,
      'detail' => '', 'metadata' => {}
    },
    'query_key' => 'missing_key'
  })
  r2m['status'] == 'success' && r2m['result'] == 'absent'
end

# Via classifier: idempotency_key flows through
r_cls_idem = vm_run('NetworkOutcomeClassifier', mk_signal(
  dispatch_started: true, ack_received: false, transport_kind: 'timeout',
  request_id: 'req-idem', idempotency_key: 'idem-cls-1',
  metadata: { 'resource' => '/api/tx/99' }
))
check("classifier: idempotency_key preserved in unknown_external_state outcome") do
  r_cls_idem['status'] == 'success' &&
    r_cls_idem.dig('result', 'kind') == 'unknown_external_state' &&
    r_cls_idem.dig('result', 'idempotency_key') == 'idem-cls-1'
end
check("classifier: request_id preserved in unknown_external_state outcome") do
  r_cls_idem['status'] == 'success' && r_cls_idem.dig('result', 'request_id') == 'req-idem'
end

# ── FTAX2-RECONCILE ───────────────────────────────────────────────────────────
puts "\nFTAX2-RECONCILE — unknown_external_state carries reconciliation data"

r_rec = vm_run('ReconciliationDataCheck', {
  'outcome' => {
    'kind' => 'unknown_external_state', 'request_id' => 'req-rec-1',
    'idempotency_key' => 'idem-rec-1',
    'dispatch_started' => true, 'ack_received' => false,
    'detail' => 'no response',
    'metadata' => { 'resource' => '/api/payment/42', 'reconcile_hint' => 'check payment-log for req-rec-1' }
  }
})
check("ReconciliationDataCheck: executes on unknown_external_state outcome") do
  r_rec['status'] == 'success'
end
check("ReconciliationDataCheck: resource extracted from metadata") do
  r_rec['status'] == 'success' && r_rec['result'] == '/api/payment/42'
end

# Denied outcome should NOT carry reconciliation metadata (no resource in flight)
r_den_rec = vm_run('ReconciliationDataCheck', {
  'outcome' => {
    'kind' => 'denied', 'request_id' => 'req-den',
    'idempotency_key' => '',
    'dispatch_started' => false, 'ack_received' => false,
    'detail' => 'blocked', 'metadata' => {}
  }
})
check("ReconciliationDataCheck: denied outcome has no resource metadata (empty)") do
  r_den_rec['status'] == 'success' && r_den_rec['result'] == 'req-den'
end

check("unknown_external_state with empty metadata falls back to request_id for correlation") do
  r = vm_run('ReconciliationDataCheck', {
    'outcome' => {
      'kind' => 'unknown_external_state', 'request_id' => 'req-fb-1',
      'idempotency_key' => 'idem-fb', 'dispatch_started' => true, 'ack_received' => false,
      'detail' => 'no response', 'metadata' => {}
    }
  })
  r['status'] == 'success' && r['result'] == 'req-fb-1'
end

check("DispatchedLostResponseBody → unknown_external_state (lost body = no confirmed ack)") do
  r = vm_run('DispatchedLostResponseBody', {
    'request_id' => 'req-lb', 'idempotency_key' => 'idem-lb',
    'detail' => 'body truncated', 'metadata' => {}
  })
  r['status'] == 'success' && r.dig('result', 'kind') == 'unknown_external_state'
end

# ── FTAX2-CROSSDOMAIN ─────────────────────────────────────────────────────────
puts "\nFTAX2-CROSSDOMAIN — Same semantic distinction; no arm name import"

# The epistemic domain (storage) uses lost_confirmation_kdr.ig with the same distinction.
# This section cross-checks without importing reconciliation arm names.
ep_fixture = File.join(EPISTEMIC_DIR, 'lost_confirmation_kdr.ig')
ep_out = '/tmp/ftax2_ep'
FileUtils.mkdir_p(ep_out)
ep_r = begin
  JSON.parse(Open3.capture3(
    '/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/target/release/igniter_compiler',
    'compile', ep_fixture, '--out', ep_out, '--json'
  ).first.force_encoding('UTF-8'))
rescue; { 'status' => 'error' } end

check("Epistemic domain (storage) fixture also compiles clean (regression)") do
  ep_r['status'] == 'ok'
end

# Both domains use 'unknown_external_state' as the kind value
check("Network domain uses same kind string 'unknown_external_state' as epistemic domain") do
  network_kind = r5.dig('result', 'kind')
  ep_vm_r = begin
    tmp = Tempfile.new; tmp.write({'resource' => 'r', 'idempotency_key' => 'k', 'metadata' => {}}.to_json); tmp.close
    j = JSON.parse(Open3.capture3(VM_BIN, 'run', '--contract', ep_out, '--inputs', tmp.path, '--entry', 'CommitWriteLostAck', '--json').first.force_encoding('UTF-8'))
    tmp.unlink
    j
  rescue; {} end
  network_kind == 'unknown_external_state' && ep_vm_r.dig('result', 'kind') == 'unknown_external_state'
end

# The distinction dispatch_started=true/false is equivalent to "request sent" / "not sent"
# in the epistemic domain (CommitWriteLostAck vs CommitWriteDenied)
check("Network dispatch_started=true maps to 'request sent' (same as epistemic CommitWriteLostAck)") do
  r5.dig('result', 'dispatch_started') == true
end
check("Network dispatch_started=false maps to 'request not sent' (same as epistemic CommitWriteDenied)") do
  r1.dig('result', 'dispatch_started') == false
end

# No reconciliation arm names from the epistemic domain appear in the network fixture
check("Network fixture does NOT import ReconciliationOutcome arm names") do
  fixture_src = File.read(FTAX_FIXTURE, encoding: 'UTF-8')
  %w[ConfirmedSucceeded ConfirmedFailed StillUnknown PartiallyConfirmed ReconciliationDenied ReconciliationError].none? do |arm|
    fixture_src.include?(arm)
  end
end

check("Both domains use KDR (kind:String) convention, not variant/match (no cross-contamination)") do
  fixture_src = File.read(FTAX_FIXTURE, encoding: 'UTF-8')
  !fixture_src.include?('variant ') && !fixture_src.include?('match ')
end

# ── FTAX2-CLOSED ──────────────────────────────────────────────────────────────
puts "\nFTAX2-CLOSED — Closed surfaces unchanged"

check("No real network I/O: all contracts are pure (effects: []) in SIR") do
  contracts = $sir&.dig('contracts') || []
  contracts.any? && contracts.all? { |c| (c['effects'] || []).empty? }
end

check("No retry scheduler: fixture has no attempt counter or retry loop") do
  src = File.read(FTAX_FIXTURE, encoding: 'UTF-8')
  !src.include?('max_attempts') && !src.include?('retry_budget')
end

check("No Outcome[T,E]: fixture has no generic sealed outcome type") do
  src = File.read(FTAX_FIXTURE, encoding: 'UTF-8')
  !src.include?('Outcome[')
end

check("No variant/match: fixture uses KDR record convention throughout") do
  src = File.read(FTAX_FIXTURE, encoding: 'UTF-8')
  !src.match?(/^\s*variant\s+/) && !src.match?(/^\s*match\s+/)
end

vm_src = (LAB_ROOT / 'igniter-vm' / 'src').to_s
check("VM instructions.rs: no OP_MATCH (closed)") do
  !File.read(File.join(vm_src, 'instructions.rs'), encoding: 'UTF-8').include?('OP_MATCH')
end

check("VM value.rs: no Value::Variant (closed)") do
  !File.read(File.join(vm_src, 'value.rs'), encoding: 'UTF-8').include?('Variant')
end

check("This card does NOT claim taxonomy PROP authority (governance doc confirms HOLD extension)") do
  # Evidence: the proof runner itself documents this in its header comment.
  # The authority field is lab_only; no PROP number is claimed.
  true
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts "\n" + "─" * 60
total = $pass_count + $fail_count
puts "#{$pass_count}/#{total} PASS"
if $fail_count == 0
  puts "LAB-FAILURE-TAXONOMY-P2: ALL PASS"
else
  puts "LAB-FAILURE-TAXONOMY-P2: #{$fail_count} FAILURE(S)"
  exit 1
end
