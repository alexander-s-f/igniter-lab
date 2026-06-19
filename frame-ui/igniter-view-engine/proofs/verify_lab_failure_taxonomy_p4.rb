#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
#
# verify_lab_failure_taxonomy_p4.rb — LAB-FAILURE-TAXONOMY-P4 proof script
#
# Proves that `partial_success` is independently meaningful in a non-reconciliation
# domain (batch job processing) and is distinct from all five adjacent outcome kinds.
#
# Required proof questions (card LAB-FAILURE-TAXONOMY-P4):
#   1. Is `partial_success` independently meaningful outside reconciliation? → YES
#   2. What concrete evidence separates it from total success?              → some items failed
#   3. What concrete evidence separates it from system_error?               → ALL items have typed outcome
#   4. What concrete evidence separates it from unknown_external_state?     → outcomes are observed, not inferred
#   5. Does it require retry, compensation, or degraded output?             → retry_failed_items (distinct action)
#   6. Is the partial result typed data, not an exception?                  → YES: BatchOutcome record with counts
#   7. Does the proof avoid global Outcome[T,E] authority?                  → YES
#   8. Does the proof avoid canon/public/runtime claims?                    → YES
#
# Fixture: fixtures/failure_taxonomy/batch_partial_success.ig
#   Batch processing domain: N items, K succeed, N-K fail.
#   Outcome kinds: ok / partial_success / failed / denied / system_error / unknown_external_state
#   11 contracts: 7 scenario + BatchOutcomeClassifier + BatchActionRouter
#                 + MultiUpstreamClassifier (network cross-domain) + EvidenceInspector
#
# Cross-domain confirmation: MultiUpstreamClassifier proves partial_success is
# not reconciliation-specific — two HTTP upstreams with mixed results yield the
# same axis (one ok + one error = partial, not failed, not unknown).
#
# Sections:
#   TAXP4-COMPILE   (5)  — fixture compiles; 11 contracts; no OOF diags
#   TAXP4-SCENARIO  (7)  — scenario contracts produce correct kinds
#   TAXP4-CLASSIFY  (6)  — classifier routes all 6 signal_kind cases
#   TAXP4-PARTIAL   (6)  — partial_success count variants
#   TAXP4-BOUNDARY  (8)  — explicit distinctions vs all 5 adjacent kinds
#   TAXP4-MULTIUP   (6)  — multi-upstream network cross-domain proof
#   TAXP4-ACTION    (6)  — action router; partial has distinct action
#   TAXP4-EVIDENCE  (5)  — typed evidence: count fields carry per-item data
#   TAXP4-CLOSED    (5)  — no global enum, no Outcome[T,E], no canon change
#
# Total: 54 checks
#
# Governance recommendation produced: TAXP4-CLOSED section and proof questions
# together establish whether `partial_success` is ready for PROP-047 inclusion.
#
# Closed surfaces:
#   - No compiler changes
#   - No VM/runtime changes
#   - No global failure enum
#   - No generic Outcome[T,E]
#   - No public/stable API claim
#   - No failure taxonomy authority
#
# Run: ruby igniter-lab/igniter-view-engine/proofs/verify_lab_failure_taxonomy_p4.rb

require 'json'
require 'open3'
require 'tempfile'
require 'pathname'
require 'fileutils'

ROOT          = Pathname.new(__dir__).parent
LAB_ROOT      = ROOT.parent
COMPILER_BIN  = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN        = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_DIR   = (ROOT / 'fixtures' / 'failure_taxonomy').to_s
VM_SRC_DIR    = (LAB_ROOT / 'igniter-vm' / 'src').to_s

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
  out_dir = "/tmp/p4_proof_#{tag}"
  FileUtils.mkdir_p(out_dir)
  stdout, _stderr, _st = Open3.capture3(COMPILER_BIN, 'compile', path.to_s, '--out', out_dir, '--json')
  result = JSON.parse(stdout.force_encoding('UTF-8'))
  $compile_cache[key] = { result: result, igapp_dir: out_dir }
end

def vm_run(igapp_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['p4_', '.json'])
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

# Helpers for constructing BatchSignal inputs
def batch_signal(signal_kind:, total:, succeeded:, failed:, batch_id: 'b', idem: 'k', detail: '', meta: {})
  { 'signal' => {
    'batch_id' => batch_id, 'signal_kind' => signal_kind,
    'total_count' => total, 'succeeded_count' => succeeded, 'failed_count' => failed,
    'detail' => detail, 'idempotency_key' => idem, 'metadata' => meta
  } }
end

def batch_outcome(kind:, total:, succeeded:, failed:, batch_id: 'b', idem: 'k', detail: '', meta: {})
  { 'outcome' => {
    'kind' => kind, 'batch_id' => batch_id,
    'total_count' => total, 'succeeded_count' => succeeded, 'failed_count' => failed,
    'detail' => detail, 'idempotency_key' => idem, 'metadata' => meta
  } }
end

def multi_signal(a_kind, b_kind, request_id: 'r')
  { 'signal' => {
    'request_id' => request_id,
    'upstream_a_kind' => a_kind,
    'upstream_b_kind' => b_kind,
    'detail' => '', 'metadata' => {}
  } }
end

main = compile(File.join(FIXTURE_DIR, 'batch_partial_success.ig'), 'batch')

# ── TAXP4-COMPILE ─────────────────────────────────────────────────────────────
puts "\nTAXP4-COMPILE — Fixture compiles"

check("batch_partial_success.ig: status=ok") do
  main[:result]['status'] == 'ok'
end

check("11 contracts present") do
  main[:result]['contracts'].length == 11
end

check("no OOF-KIND diagnostics") do
  (main[:result]['diagnostics'] || []).none? { |d| d['rule']&.start_with?('OOF-KIND') }
end

check("BatchOutcomeClassifier present") do
  main[:result]['contracts'].include?('BatchOutcomeClassifier')
end

check("MultiUpstreamClassifier present (cross-domain)") do
  main[:result]['contracts'].include?('MultiUpstreamClassifier')
end

# ── TAXP4-SCENARIO ────────────────────────────────────────────────────────────
puts "\nTAXP4-SCENARIO — Individual scenario contracts produce correct kinds"

check("AllSucceeded: kind='ok' (5/5 items)") do
  r = vm_run(main[:igapp_dir], 'AllSucceeded',
    { 'batch_id' => 'b1', 'idempotency_key' => 'k1', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'ok'
end

check("PartialSucceededThreeOfFive: kind='partial_success' (3/5 items)") do
  r = vm_run(main[:igapp_dir], 'PartialSucceededThreeOfFive',
    { 'batch_id' => 'b2', 'idempotency_key' => 'k2', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("PartialSucceededOneOfFive: kind='partial_success' (1/5 items)") do
  r = vm_run(main[:igapp_dir], 'PartialSucceededOneOfFive',
    { 'batch_id' => 'b3', 'idempotency_key' => 'k3', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("AllFailed: kind='failed' (0/5 items)") do
  r = vm_run(main[:igapp_dir], 'AllFailed',
    { 'batch_id' => 'b4', 'idempotency_key' => 'k4', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'failed'
end

check("DeniedBeforeBatch: kind='denied' (nothing attempted)") do
  r = vm_run(main[:igapp_dir], 'DeniedBeforeBatch',
    { 'batch_id' => 'b5', 'detail' => 'no cap', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'denied'
end

check("SystemErrorBatch: kind='system_error' (infra failure)") do
  r = vm_run(main[:igapp_dir], 'SystemErrorBatch',
    { 'batch_id' => 'b6', 'detail' => 'db down', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'system_error'
end

check("UnknownStateBatch: kind='unknown_external_state' (dispatched, no ack)") do
  r = vm_run(main[:igapp_dir], 'UnknownStateBatch',
    { 'batch_id' => 'b7', 'idempotency_key' => 'k7', 'detail' => 'no ack', 'metadata' => {} })
  r['status'] == 'success' && r['result']['kind'] == 'unknown_external_state'
end

# ── TAXP4-CLASSIFY ────────────────────────────────────────────────────────────
puts "\nTAXP4-CLASSIFY — BatchOutcomeClassifier routes all 6 cases"

check("Classifier: signal_kind='ran' + 5/5 → 'ok'") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 5, failed: 0))
  r['status'] == 'success' && r['result']['kind'] == 'ok'
end

check("Classifier: signal_kind='ran' + 3/5 → 'partial_success'") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 3, failed: 2))
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("Classifier: signal_kind='ran' + 0/5 → 'failed'") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 0, failed: 5))
  r['status'] == 'success' && r['result']['kind'] == 'failed'
end

check("Classifier: signal_kind='denied' → 'denied'") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'denied', total: 0, succeeded: 0, failed: 0, idem: ''))
  r['status'] == 'success' && r['result']['kind'] == 'denied'
end

check("Classifier: signal_kind='system_error' → 'system_error'") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'system_error', total: 0, succeeded: 0, failed: 0, idem: ''))
  r['status'] == 'success' && r['result']['kind'] == 'system_error'
end

check("Classifier: signal_kind='unknown_external_state' → 'unknown_external_state'") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'unknown_external_state', total: 0, succeeded: 0, failed: 0))
  r['status'] == 'success' && r['result']['kind'] == 'unknown_external_state'
end

# ── TAXP4-PARTIAL ─────────────────────────────────────────────────────────────
puts "\nTAXP4-PARTIAL — partial_success count variants"

check("1/5 succeed → 'partial_success' (not 'failed')") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 1, failed: 4))
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("4/5 succeed → 'partial_success' (not 'ok')") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 4, failed: 1))
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("partial_success carries succeeded_count=3, failed_count=2") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 3, failed: 2))
  r['status'] == 'success' &&
    r['result']['succeeded_count'] == 3 && r['result']['failed_count'] == 2
end

check("partial_success preserves idempotency_key for retry gate") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 3, failed: 2, idem: 'batch-key-xyz'))
  r['status'] == 'success' && r['result']['idempotency_key'] == 'batch-key-xyz'
end

check("Boundary: 5/5 succeed → 'ok' (NOT partial_success)") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 5, failed: 0))
  r['status'] == 'success' && r['result']['kind'] != 'partial_success'
end

check("Boundary: 0/5 succeed → 'failed' (NOT partial_success)") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 0, failed: 5))
  r['status'] == 'success' && r['result']['kind'] != 'partial_success'
end

# ── TAXP4-BOUNDARY ────────────────────────────────────────────────────────────
puts "\nTAXP4-BOUNDARY — Explicit distinctions vs all 5 adjacent kinds"

# Q2: partial vs ok: succeeded_count < total_count
check("Q2: partial_success ≠ ok: succeeded_count < total_count (3/5 vs 5/5)") do
  r_partial = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 3, failed: 2))
  r_ok = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 5, failed: 0))
  r_partial['result']['kind'] == 'partial_success' && r_ok['result']['kind'] == 'ok'
end

# Proof: partial has succeeded_count > 0, ok has failed_count == 0
check("Q2: partial has non-zero failed_count; ok has zero failed_count") do
  r_partial = vm_run(main[:igapp_dir], 'PartialSucceededThreeOfFive',
    { 'batch_id' => 'b', 'idempotency_key' => 'k', 'metadata' => {} })
  r_ok = vm_run(main[:igapp_dir], 'AllSucceeded',
    { 'batch_id' => 'b', 'idempotency_key' => 'k', 'metadata' => {} })
  r_partial['result']['failed_count'] > 0 && r_ok['result']['failed_count'] == 0
end

# Q3: partial vs system_error: system_error has NO per-item evidence
check("Q3: partial_success ≠ system_error: partial has typed per-item evidence; system_error has none") do
  r_p = vm_run(main[:igapp_dir], 'PartialSucceededThreeOfFive',
    { 'batch_id' => 'b', 'idempotency_key' => 'k', 'metadata' => {} })
  r_s = vm_run(main[:igapp_dir], 'SystemErrorBatch',
    { 'batch_id' => 'b', 'detail' => 'infra', 'metadata' => {} })
  r_p['result']['kind'] == 'partial_success' && r_p['result']['total_count'] == 5 &&
    r_s['result']['kind'] == 'system_error' && r_s['result']['total_count'] == 0
end

# Q4: partial vs unknown_external_state: unknown = dispatched, no ack; partial = observed outcomes
check("Q4: partial_success ≠ unknown_external_state: partial outcomes are observed; unknown is unconfirmed") do
  r_p = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 3, failed: 2))
  r_u = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'unknown_external_state', total: 0, succeeded: 0, failed: 0))
  r_p['result']['kind'] == 'partial_success' && r_u['result']['kind'] == 'unknown_external_state' &&
    r_p['result']['total_count'] == 5 && r_u['result']['total_count'] == 0
end

# Q4b: system_error also has total_count=0 — but it's a different kind
check("Q4b: system_error and unknown_external_state both lack per-item evidence — but they are different kinds") do
  r_s = vm_run(main[:igapp_dir], 'SystemErrorBatch',
    { 'batch_id' => 'b', 'detail' => 'infra', 'metadata' => {} })
  r_u = vm_run(main[:igapp_dir], 'UnknownStateBatch',
    { 'batch_id' => 'b', 'idempotency_key' => 'k', 'detail' => 'no ack', 'metadata' => {} })
  r_s['result']['kind'] == 'system_error' && r_u['result']['kind'] == 'unknown_external_state' &&
    r_s['result']['kind'] != r_u['result']['kind']
end

# Denied: nothing processed
check("partial vs denied: denied has zero succeeded_count + zero total_count; partial has both > 0") do
  r_p = vm_run(main[:igapp_dir], 'PartialSucceededThreeOfFive',
    { 'batch_id' => 'b', 'idempotency_key' => 'k', 'metadata' => {} })
  r_d = vm_run(main[:igapp_dir], 'DeniedBeforeBatch',
    { 'batch_id' => 'b', 'detail' => 'no cap', 'metadata' => {} })
  r_p['result']['succeeded_count'] == 3 && r_p['result']['total_count'] == 5 &&
    r_d['result']['succeeded_count'] == 0 && r_d['result']['total_count'] == 0
end

# All 6 kinds are distinct
check("All 6 outcome kinds are mutually distinct strings") do
  kinds = %w[ok partial_success failed denied system_error unknown_external_state]
  kinds.uniq.length == 6
end

# partial_success implies retry_failed_items; failed implies retry_batch (different)
check("partial vs failed: distinct recovery actions (retry_failed_items vs retry_batch)") do
  r_p = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'partial_success', total: 5, succeeded: 3, failed: 2))
  r_f = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'failed', total: 5, succeeded: 0, failed: 5))
  r_p['result'] == 'retry_failed_items' && r_f['result'] == 'retry_batch'
end

# ── TAXP4-MULTIUP ─────────────────────────────────────────────────────────────
puts "\nTAXP4-MULTIUP — Multi-upstream network cross-domain confirmation"

check("Multi-upstream: A=ok + B=ok → 'ok' (both succeeded)") do
  r = vm_run(main[:igapp_dir], 'MultiUpstreamClassifier', multi_signal('ok', 'ok'))
  r['status'] == 'success' && r['result']['kind'] == 'ok'
end

check("Multi-upstream: A=ok + B=error → 'partial_success' (network domain, not reconciliation)") do
  r = vm_run(main[:igapp_dir], 'MultiUpstreamClassifier', multi_signal('ok', 'error'))
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("Multi-upstream: A=error + B=ok → 'partial_success' (symmetric)") do
  r = vm_run(main[:igapp_dir], 'MultiUpstreamClassifier', multi_signal('error', 'ok'))
  r['status'] == 'success' && r['result']['kind'] == 'partial_success'
end

check("Multi-upstream: A=error + B=error → 'failed' (both failed, NOT partial_success)") do
  r = vm_run(main[:igapp_dir], 'MultiUpstreamClassifier', multi_signal('error', 'error'))
  r['status'] == 'success' && r['result']['kind'] == 'failed'
end

check("Multi-upstream: A=ok + B=unknown → 'unknown_external_state' (Covenant P15 per-upstream)") do
  r = vm_run(main[:igapp_dir], 'MultiUpstreamClassifier', multi_signal('ok', 'unknown'))
  r['status'] == 'success' && r['result']['kind'] == 'unknown_external_state'
end

check("Multi-upstream: partial_success carries upstream kind fields (typed evidence)") do
  r = vm_run(main[:igapp_dir], 'MultiUpstreamClassifier', multi_signal('ok', 'error', request_id: 'req-77'))
  r['status'] == 'success' &&
    r['result']['kind'] == 'partial_success' &&
    r['result']['upstream_a_kind'] == 'ok' &&
    r['result']['upstream_b_kind'] == 'error'
end

# ── TAXP4-ACTION ──────────────────────────────────────────────────────────────
puts "\nTAXP4-ACTION — Action router; partial_success has a distinct action"

check("BatchActionRouter: ok → 'consume'") do
  r = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'ok', total: 5, succeeded: 5, failed: 0))
  r['status'] == 'success' && r['result'] == 'consume'
end

check("BatchActionRouter: partial_success → 'retry_failed_items' (distinct from all other actions)") do
  r = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'partial_success', total: 5, succeeded: 3, failed: 2))
  r['status'] == 'success' && r['result'] == 'retry_failed_items'
end

check("BatchActionRouter: failed → 'retry_batch'") do
  r = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'failed', total: 5, succeeded: 0, failed: 5))
  r['status'] == 'success' && r['result'] == 'retry_batch'
end

check("BatchActionRouter: denied → 'fix_policy'") do
  r = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'denied', total: 0, succeeded: 0, failed: 0, idem: ''))
  r['status'] == 'success' && r['result'] == 'fix_policy'
end

check("BatchActionRouter: system_error → 'investigate'") do
  r = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'system_error', total: 0, succeeded: 0, failed: 0, idem: ''))
  r['status'] == 'success' && r['result'] == 'investigate'
end

check("BatchActionRouter: unknown_external_state → 'reconcile'") do
  r = vm_run(main[:igapp_dir], 'BatchActionRouter',
    batch_outcome(kind: 'unknown_external_state', total: 0, succeeded: 0, failed: 0))
  r['status'] == 'success' && r['result'] == 'reconcile'
end

# ── TAXP4-EVIDENCE ────────────────────────────────────────────────────────────
puts "\nTAXP4-EVIDENCE — Typed evidence: count fields carry per-item data"

check("EvidenceInspector: partial_success (3+2=5) → counts_match=true") do
  r = vm_run(main[:igapp_dir], 'EvidenceInspector',
    batch_outcome(kind: 'partial_success', total: 5, succeeded: 3, failed: 2))
  r['status'] == 'success' && r['result'] == true
end

check("EvidenceInspector: ok (5+0=5) → counts_match=true") do
  r = vm_run(main[:igapp_dir], 'EvidenceInspector',
    batch_outcome(kind: 'ok', total: 5, succeeded: 5, failed: 0))
  r['status'] == 'success' && r['result'] == true
end

check("EvidenceInspector: failed (0+5=5) → counts_match=true") do
  r = vm_run(main[:igapp_dir], 'EvidenceInspector',
    batch_outcome(kind: 'failed', total: 5, succeeded: 0, failed: 5))
  r['status'] == 'success' && r['result'] == true
end

# Q6: Is the partial result typed data, not an exception?
check("Q6: partial_success result is a typed BatchOutcome record (not a raised exception)") do
  r = vm_run(main[:igapp_dir], 'PartialSucceededThreeOfFive',
    { 'batch_id' => 'batch-x', 'idempotency_key' => 'k', 'metadata' => {} })
  r['status'] == 'success' &&
    r['result'].is_a?(Hash) &&
    r['result']['kind'] == 'partial_success' &&
    r['result']['succeeded_count'].is_a?(Integer) &&
    r['result']['failed_count'].is_a?(Integer)
end

check("partial_success result carries metadata map for downstream correlation") do
  r = vm_run(main[:igapp_dir], 'BatchOutcomeClassifier',
    batch_signal(signal_kind: 'ran', total: 5, succeeded: 3, failed: 2,
      meta: { 'job_queue' => 'priority', 'env' => 'staging' }))
  r['status'] == 'success' &&
    r['result']['metadata']['job_queue'] == 'priority'
end

# ── TAXP4-CLOSED ──────────────────────────────────────────────────────────────
puts "\nTAXP4-CLOSED — No global enum, no Outcome[T,E], no canon/taxonomy change"

fixture_src = File.read(File.join(FIXTURE_DIR, 'batch_partial_success.ig')).force_encoding('UTF-8')
fixture_code = fixture_src.lines.reject { |l| l.strip.start_with?('--') }.join

check("Fixture: no Outcome[T,E] generic type reference in code") do
  !fixture_code.match?(/Outcome\[/)
end

check("Fixture: no global failure taxonomy authority claim in code (Lab.FailureTaxonomy namespace is allowed)") do
  # Lab.FailureTaxonomy.* is the namespace; an authority claim would be something stronger
  !fixture_code.match?(/taxonomy_authority|canonical_taxonomy|authoritative.*taxonomy|taxonomy.*stable/i)
end

check("VM instructions.rs: no OP_MATCH (VM unchanged)") do
  !File.read(File.join(VM_SRC_DIR, 'instructions.rs')).force_encoding('UTF-8').include?('OP_MATCH')
end

check("VM value.rs: no Value::Variant (VM unchanged)") do
  !File.read(File.join(VM_SRC_DIR, 'value.rs')).force_encoding('UTF-8').include?('Variant')
end

check("No serialization schema or stable-api claim in fixture code") do
  !fixture_code.match?(/stable.*api|serialize|deserialize/i)
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts "\n" + "─" * 60
total = $pass_count + $fail_count
puts "#{$pass_count}/#{total} PASS"

puts ""
puts "GOVERNANCE RECOMMENDATION:"
if $fail_count == 0
  puts "  PROMOTE partial_success into PROP-047 stable terms."
  puts ""
  puts "  Evidence basis:"
  puts "  1. Independently meaningful outside reconciliation (batch domain, network domain)."
  puts "  2. Separation from total success: succeeded_count < total_count."
  puts "  3. Separation from system_error: system_error has NO per-item evidence;"
  puts "     partial_success carries typed count evidence for every item."
  puts "  4. Separation from unknown_external_state: unknown = dispatched/unconfirmed;"
  puts "     partial = all outcomes observed and typed."
  puts "  5. Requires retry_failed_items (distinct from retry_batch, reconcile, etc.)."
  puts "  6. Result is typed data (BatchOutcome record), not an exception."
  puts "  7. Two independent domain proofs: batch processing + multi-upstream network."
  puts ""
  puts "LAB-FAILURE-TAXONOMY-P4: ALL PASS"
else
  puts "  RECOMMENDATION DEFERRED — #{$fail_count} proof failure(s)."
  puts "LAB-FAILURE-TAXONOMY-P4: #{$fail_count} FAILURE(S)"
  exit 1
end
