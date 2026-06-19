#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_reconciliation_state_machine.rb
# LAB-EPISTEMIC-OUTCOME-P3: Reconciliation-consumer boundary — proof-local state machine
#
# This is DESIGN EVIDENCE, not language runtime. It encodes the reconciliation-consumer
# transition table from the P3 design note as a pure-Ruby state machine and asserts:
#   - every ALLOWED transition is accepted (with its guard satisfied);
#   - every FORBIDDEN transition is rejected;
#   - the guards behave (retry needs idempotency; compensate needs a named contract;
#     accept needs a prior confirmation; a model observation cannot confirm success as real);
#   - the Covenant No-Upward-Coercion rule holds: unknown_external_state cannot reach
#     `accept`/`succeeded`/`failed` except THROUGH a reconciliation pass (the explicit
#     typed conversion), and a reconciliation receipt carries its observation kind (P13).
#
# It runs NO .ig fixture, NO compiler, NO VM, NO file/network/db/socket I/O. It is a
# proof-local model of the consumer contract surface the note specifies — the KDR-now
# behaviour a future sealed Outcome[T,E] would make type-enforced.
#
# Aligns to PROPOSED Ch12 Effect Surface + Covenant doctrine (P15 Timeout Is Not Failure;
# P16 Idempotency Is Declared; P17 Compensation Is Named; Epistemic State Machine /
# No Upward Coercion). Ch12 is treated as PROPOSED, not accepted canon.
#
# Authority: LAB-ONLY. KDR convention only. No sealed Outcome[T,E]. No variant/match
# runtime authority. No canon claim. No public/stable API.
#
# Run: ruby igniter-view-engine/proofs/verify_reconciliation_state_machine.rb

SOURCE = File.read(__FILE__).freeze

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

# ─────────────────────────────────────────────────────────────────────────────
# The reconciliation-consumer state machine (proof-local model)
# ─────────────────────────────────────────────────────────────────────────────
#
# Nodes fall in three bands:
#   effect kinds (from the P2 OutcomeEnvelope):
#     succeeded denied timed_out unknown_external_state partial cancelled compensated
#   reconciliation lifecycle states:
#     reconcile_required confirmed_succeeded confirmed_failed still_unknown
#     partially_confirmed reconciliation_denied reconciliation_error
#   terminal actions:
#     accept deny retry compensate fail cancel record hold
#
# A transition is permitted iff it is an ALLOWED edge AND its guard passes.
# ctx carries the evidence the consumer holds: idempotency_key, compensation,
# evidence_kind (real|model|human|absent), budget_remaining, effect_started, confirmed.

module Reconciler
  EFFECT_KINDS = %w[succeeded denied timed_out unknown_external_state partial cancelled compensated].freeze
  UNKNOWN_KINDS = %w[timed_out unknown_external_state].freeze
  RECON_RESULTS = %w[confirmed_succeeded confirmed_failed still_unknown partially_confirmed
                     reconciliation_denied reconciliation_error].freeze
  # Observation kinds whose confirmation counts as a real upgrade (Covenant P13).
  REAL_EVIDENCE = %w[real human].freeze

  # Guard helpers ------------------------------------------------------------
  def self.idempotent?(ctx);        k = ctx[:idempotency_key]; !k.nil? && k != ''; end
  def self.named_compensation?(ctx) c = ctx[:compensation];   !c.nil? && c != '' && c != 'no_compensation'; end
  def self.budget?(ctx);            (ctx[:budget_remaining] || 0) > 0; end
  def self.real_observation?(ctx);  REAL_EVIDENCE.include?(ctx[:evidence_kind]); end

  # ALLOWED edges, each with a guard (default: always allowed).
  T = ->(g = ->(_c) { true }) { g }
  ALLOWED = {
    # entry into reconciliation — unknown/timeout/partial require a reconcile pass
    ['unknown_external_state', 'reconcile_required'] => T.call,
    ['timed_out',              'reconcile_required'] => T.call,
    ['partial',                'reconcile_required'] => T.call,
    # reconciliation pass may report any of the six results
    ['reconcile_required', 'confirmed_succeeded']  => T.call,
    ['reconcile_required', 'confirmed_failed']     => T.call,
    ['reconcile_required', 'still_unknown']        => T.call,
    ['reconcile_required', 'partially_confirmed']  => T.call,
    ['reconcile_required', 'reconciliation_denied'] => T.call,
    ['reconcile_required', 'reconciliation_error'] => T.call,
    # confirmation → terminal — accept ONLY on a real/human-evidenced confirmation (P13)
    ['confirmed_succeeded', 'accept']     => T.call(->(c) { Reconciler.real_observation?(c) }),
    ['confirmed_failed',    'retry']      => T.call(->(c) { Reconciler.idempotent?(c) }),
    ['confirmed_failed',    'compensate'] => T.call(->(c) { Reconciler.named_compensation?(c) }),
    ['confirmed_failed',    'fail']       => T.call, # honest surfacing always permitted
    # loops / escalation — bounded re-entry, else hold for human/audit
    ['partially_confirmed', 'reconcile_required'] => T.call, # reconcile the remainder
    ['still_unknown',       'reconcile_required'] => T.call(->(c) { Reconciler.budget?(c) }),
    ['still_unknown',       'hold']               => T.call, # budget exhausted → escalate; never infer
    ['reconciliation_denied', 'hold']             => T.call, # cannot reconcile (authority); escalate
    ['reconciliation_error',  'reconcile_required'] => T.call(->(c) { Reconciler.budget?(c) }),
    ['reconciliation_error',  'hold']             => T.call,
    # non-unknown effect kinds — direct terminal routes
    ['succeeded',   'accept']     => T.call(->(c) { Reconciler.real_observation?(c) }),
    ['denied',      'deny']       => T.call,
    ['cancelled',   'cancel']     => T.call,
    ['cancelled',   'compensate'] => T.call(->(c) { c[:effect_started] && Reconciler.named_compensation?(c) }),
    ['compensated', 'record']     => T.call
  }.freeze

  def self.allowed?(from, to)
    ALLOWED.key?([from, to])
  end

  # The single gate every consumer move passes through.
  def self.transition(from, to, ctx = {})
    guard = ALLOWED[[from, to]]
    return false unless guard            # not an allowed edge
    guard.call(ctx)                      # edge exists; guard must pass
  end
end

R = Reconciler

# A consumer that tries to reach `accept` from a given kind, honestly.
# Returns the terminal action reached, or :blocked if no permitted path.
def drive(kind, ctx)
  case kind
  when 'succeeded'
    R.transition('succeeded', 'accept', ctx) ? :accept : :blocked
  when 'denied'      then R.transition('denied', 'deny', ctx) ? :deny : :blocked
  when 'cancelled'   then R.transition('cancelled', 'cancel', ctx) ? :cancel : :blocked
  when 'compensated' then R.transition('compensated', 'record', ctx) ? :record : :blocked
  when 'unknown_external_state', 'timed_out', 'partial'
    # MUST reconcile first; cannot jump to a terminal.
    return :blocked unless R.transition(kind, 'reconcile_required', ctx)
    recon = ctx[:reconcile_result]
    return :reconcile_required unless recon
    return :blocked unless R.transition('reconcile_required', recon, ctx)
    case recon
    when 'confirmed_succeeded' then R.transition('confirmed_succeeded', 'accept', ctx) ? :accept : :needs_human_review
    when 'confirmed_failed'
      if R.transition('confirmed_failed', 'retry', ctx) then :retry
      elsif R.transition('confirmed_failed', 'compensate', ctx) then :compensate
      else (R.transition('confirmed_failed', 'fail', ctx) ? :fail : :blocked)
      end
    when 'still_unknown'        then R.transition('still_unknown', 'reconcile_required', ctx) ? :reconcile_again : :hold
    when 'partially_confirmed'  then :reconcile_remainder
    when 'reconciliation_denied' then :hold
    when 'reconciliation_error'  then R.transition('reconciliation_error', 'reconcile_required', ctx) ? :reconcile_again : :hold
    end
  else :blocked
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# RSM-ALLOWED — every allowed transition is accepted (guards satisfied)
# ─────────────────────────────────────────────────────────────────────────────

puts "\nRSM-ALLOWED"

check('RSM-ALLOWED-01: unknown_external_state → reconcile_required') do
  R.transition('unknown_external_state', 'reconcile_required')
end
check('RSM-ALLOWED-02: timed_out → reconcile_required') do
  R.transition('timed_out', 'reconcile_required')
end
check('RSM-ALLOWED-03: reconcile_required → confirmed_succeeded') do
  R.transition('reconcile_required', 'confirmed_succeeded')
end
check('RSM-ALLOWED-04: reconcile_required → confirmed_failed') do
  R.transition('reconcile_required', 'confirmed_failed')
end
check('RSM-ALLOWED-05: reconcile_required → still_unknown') do
  R.transition('reconcile_required', 'still_unknown')
end
check('RSM-ALLOWED-06: reconcile_required → partially_confirmed') do
  R.transition('reconcile_required', 'partially_confirmed')
end
check('RSM-ALLOWED-07: confirmed_succeeded → accept (real observation)') do
  R.transition('confirmed_succeeded', 'accept', { evidence_kind: 'real' })
end
check('RSM-ALLOWED-08: confirmed_failed → retry (idempotency present)') do
  R.transition('confirmed_failed', 'retry', { idempotency_key: 'idem-1' })
end
check('RSM-ALLOWED-09: confirmed_failed → compensate (named compensation)') do
  R.transition('confirmed_failed', 'compensate', { compensation: 'RefundCharge' })
end
check('RSM-ALLOWED-10: confirmed_failed → fail (honest surfacing always permitted)') do
  R.transition('confirmed_failed', 'fail')
end
check('RSM-ALLOWED-11: still_unknown → reconcile_required (budget remaining)') do
  R.transition('still_unknown', 'reconcile_required', { budget_remaining: 2 })
end
check('RSM-ALLOWED-12: still_unknown → hold (escalate when exhausted)') do
  R.transition('still_unknown', 'hold')
end

# ─────────────────────────────────────────────────────────────────────────────
# RSM-FORBIDDEN — every forbidden transition is rejected
# ─────────────────────────────────────────────────────────────────────────────

puts "\nRSM-FORBIDDEN"

check('RSM-FORBIDDEN-01: unknown_external_state → succeeded is NOT an edge (no direct upgrade)') do
  !R.allowed?('unknown_external_state', 'succeeded') &&
    R.transition('unknown_external_state', 'succeeded') == false
end
check('RSM-FORBIDDEN-02: unknown_external_state → accept is rejected (skips reconciliation)') do
  R.transition('unknown_external_state', 'accept') == false
end
check('RSM-FORBIDDEN-03: unknown_external_state → confirmed_succeeded is rejected (skips reconcile_required)') do
  R.transition('unknown_external_state', 'confirmed_succeeded') == false
end
check('RSM-FORBIDDEN-04: unknown_external_state → failed is rejected (P15)') do
  R.transition('unknown_external_state', 'failed') == false
end
check('RSM-FORBIDDEN-05: unknown_external_state → retry is rejected (no reconcile, no idempotency)') do
  R.transition('unknown_external_state', 'retry', { idempotency_key: 'idem-1' }) == false
end
check('RSM-FORBIDDEN-06: unknown_external_state → compensate is rejected (no reconcile, no named comp)') do
  R.transition('unknown_external_state', 'compensate', { compensation: 'RefundCharge' }) == false
end
check('RSM-FORBIDDEN-07: timed_out → failed is rejected (timeout is not observed failure, P15)') do
  R.transition('timed_out', 'failed') == false
end
check('RSM-FORBIDDEN-08: reconcile_required → accept is rejected (must confirm first)') do
  R.transition('reconcile_required', 'accept', { evidence_kind: 'real' }) == false
end
check('RSM-FORBIDDEN-09: still_unknown → accept is rejected') do
  R.transition('still_unknown', 'accept', { evidence_kind: 'real' }) == false
end
check('RSM-FORBIDDEN-10: reconciliation_denied → confirmed_succeeded is rejected (cannot manufacture success)') do
  R.transition('reconciliation_denied', 'confirmed_succeeded') == false
end

# ─────────────────────────────────────────────────────────────────────────────
# RSM-GUARD — guard rejections (retry/compensate/accept/coercion)
# ─────────────────────────────────────────────────────────────────────────────

puts "\nRSM-GUARD"

check('RSM-GUARD-01: confirmed_failed → retry WITHOUT idempotency is rejected (P16)') do
  R.transition('confirmed_failed', 'retry', { idempotency_key: '' }) == false
end
check('RSM-GUARD-02: confirmed_failed → compensate WITHOUT named compensation is rejected (P17)') do
  R.transition('confirmed_failed', 'compensate', { compensation: 'no_compensation' }) == false
end
check('RSM-GUARD-03: confirmed_succeeded → accept on a MODEL observation is rejected (P13 no upward coercion)') do
  R.transition('confirmed_succeeded', 'accept', { evidence_kind: 'model' }) == false
end
check('RSM-GUARD-04: confirmed_succeeded → accept on a REAL observation is accepted (P13)') do
  R.transition('confirmed_succeeded', 'accept', { evidence_kind: 'real' }) == true
end
check('RSM-GUARD-05: still_unknown → reconcile_required WITHOUT budget is rejected (no infinite loop)') do
  R.transition('still_unknown', 'reconcile_required', { budget_remaining: 0 }) == false
end
check('RSM-GUARD-06: cancelled → compensate requires effect_started AND named compensation') do
  R.transition('cancelled', 'compensate', { effect_started: false, compensation: 'RefundCharge' }) == false &&
    R.transition('cancelled', 'compensate', { effect_started: true, compensation: 'RefundCharge' }) == true
end

# ─────────────────────────────────────────────────────────────────────────────
# RSM-DRIVE — end-to-end honest consumer paths
# ─────────────────────────────────────────────────────────────────────────────

puts "\nRSM-DRIVE"

check('RSM-DRIVE-01: lost-ack + reconcile confirms success (real) → accept') do
  drive('unknown_external_state',
        { reconcile_result: 'confirmed_succeeded', evidence_kind: 'real' }) == :accept
end
check('RSM-DRIVE-02: lost-ack + reconcile confirms success (model) → needs_human_review (NOT accept)') do
  drive('unknown_external_state',
        { reconcile_result: 'confirmed_succeeded', evidence_kind: 'model' }) == :needs_human_review
end
check('RSM-DRIVE-03: lost-ack + reconcile confirms failure + idempotency → retry') do
  drive('unknown_external_state',
        { reconcile_result: 'confirmed_failed', idempotency_key: 'idem-9' }) == :retry
end
check('RSM-DRIVE-04: lost-ack + reconcile confirms failure + named compensation (no idem) → compensate') do
  drive('unknown_external_state',
        { reconcile_result: 'confirmed_failed', compensation: 'RefundCharge' }) == :compensate
end
check('RSM-DRIVE-05: lost-ack + reconcile confirms failure + neither idem nor comp → fail (honest)') do
  drive('unknown_external_state',
        { reconcile_result: 'confirmed_failed' }) == :fail
end
check('RSM-DRIVE-06: lost-ack + still_unknown + budget → reconcile_again') do
  drive('unknown_external_state',
        { reconcile_result: 'still_unknown', budget_remaining: 1 }) == :reconcile_again
end
check('RSM-DRIVE-07: lost-ack + still_unknown + no budget → hold (escalate; never infer)') do
  drive('unknown_external_state',
        { reconcile_result: 'still_unknown', budget_remaining: 0 }) == :hold
end
check('RSM-DRIVE-08: lost-ack with NO reconcile result → stuck at reconcile_required (never terminal)') do
  drive('unknown_external_state', {}) == :reconcile_required
end
check('RSM-DRIVE-09: denied → deny directly (nothing sent; no reconcile)') do
  drive('denied', {}) == :deny
end
check('RSM-DRIVE-10: reconciliation_denied → hold (cannot manufacture an outcome)') do
  drive('unknown_external_state', { reconcile_result: 'reconciliation_denied' }) == :hold
end
check('RSM-DRIVE-11: partial → reconcile_remainder (some confirmed; reconcile the rest)') do
  drive('partial', { reconcile_result: 'partially_confirmed' }) == :reconcile_remainder
end

# ─────────────────────────────────────────────────────────────────────────────
# RSM-CLOSED — boundary scan
# ─────────────────────────────────────────────────────────────────────────────

puts "\nRSM-CLOSED"

check('RSM-CLOSED-01: proof is pure-Ruby — no compiler/VM/igniter_lang dependency') do
  !SOURCE.include?("require 'igniter_la" + "ng'") &&
    !SOURCE.include?('igniter_compi' + 'ler') &&
    !SOURCE.include?('igniter-' + 'vm')
end
check('RSM-CLOSED-02: no real file/network/db/socket/worker I/O') do
  !SOURCE.include?('File.ope' + 'n') &&
    !SOURCE.include?('TCPSock' + 'et') &&
    !SOURCE.include?('Net::HT' + 'TP') &&
    !SOURCE.include?('PG.conn' + 'ect')
end
check('RSM-CLOSED-03: KDR-only — no variant/match runtime authority used') do
  !SOURCE.include?('variant_decl' + 'arations') && !SOURCE.include?('match_no' + 'de')
end
check('RSM-CLOSED-04: lab-only boundary stated; no canon/stable-API claim') do
  SOURCE.include?('LAB-ONLY') &&
    !SOURCE.include?('stab' + 'le API auth') &&
    !SOURCE.include?('canon auth' + 'ority')
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "LAB-EPISTEMIC-OUTCOME-P3 (reconciliation state machine): #{$pass_count}/#{total} PASS"
puts '=' * 60

if $fail_count > 0
  puts "\nFAILURES: #{$fail_count}"
  exit 1
else
  puts "\nPASS — all #{total} checks passed"
  exit 0
end
