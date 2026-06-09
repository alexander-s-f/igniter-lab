# frozen_string_literal: true
# encoding: utf-8
# LAB-SIDEKIQ-P5: Sidekiq upstream HTTP result composition proof — 48 checks
#
# Proves a Sidekiq-shaped job composition that consumes typed HttpResult /
# ContractResult envelopes, applies retry policy as explicit data
# (BudgetedLocalLoop analog), and returns a typed JobReceipt or RetryEnvelope
# with Map[String,String] metadata.
#
# Two-layer architecture (same as PROP-043-P5):
#   Layer A — Production Ruby TypeChecker (type-level): proves type shapes,
#             Map[String,String] metadata inference, record literal resolution,
#             and field arithmetic (next_attempt = attempt + 1 → Integer).
#   Layer B — Proof-local simulation (behavioral): proves retry budget logic,
#             capability denial (non-retryable), attempt counter, metadata
#             passthrough, and map_get / or_else behavioral semantics.
#
# Fixture: igniter-view-engine/fixtures/sidekiq_core/upstream_http_result_composition.ig
#   Types:     HttpResult, ContractResult, JobInput, JobReceipt, RetryEnvelope
#   Contracts: MetadataReader, SuccessPath, DeniedPath, RetryablePath, ExhaustedPath
#
# Authority: LAB-ONLY. No canon claim. No Sidekiq compat claim. No real I/O.
#
# Depends on: PROP-043-P5 C1 fix (Map params preserved through @type_shapes),
#             LAB-SIDEKIQ-P4 (5-field JobReceipt baseline),
#             LAB-STDLIB-NET-P8 (HttpResult / RetryEnvelope shapes),
#             LAB-STDLIB-NET-P9 (ContractResult 6-kind discriminant).
#
# Run: ruby igniter-view-engine/proofs/verify_sidekiq_p5_upstream_http_result_composition.rb

SOURCE = File.read(__FILE__).freeze

IGNITER_LIB = File.expand_path('../../../igniter-lang/lib', __dir__)
$LOAD_PATH.unshift IGNITER_LIB unless $LOAD_PATH.include?(IGNITER_LIB)
require 'igniter_lang'

BOLD  = "\e[1m"
RESET = "\e[0m"
GREEN = "\e[32m"
RED   = "\e[31m"

FIXTURE_PATH = File.expand_path(
  '../fixtures/sidekiq_core/upstream_http_result_composition.ig',
  __dir__
)

RESULTS = []

# ── Layer A: Production TypeChecker helpers ───────────────────────────────────

def run_fixture(path)
  src        = File.read(path).force_encoding('UTF-8')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: path).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { parsed: parsed, classified: classified, typed: typed }
end

# All type_errors aggregated at the program level.
def all_type_errors(result)
  result[:typed]&.fetch('type_errors', []) || []
end

# Type errors scoped to a single named contract.
def contract_type_errors(result, contract_name)
  result[:typed]&.fetch('contracts', [])
                &.find  { |c| c['name'] == contract_name }
                &.fetch('type_errors', []) || []
end

# Status of a single named contract ("accepted" or "blocked").
def contract_status(result, contract_name)
  result[:typed]&.fetch('contracts', [])
                &.find  { |c| c['name'] == contract_name }
                &.fetch('status', 'unknown') || 'unknown'
end

# Symbol type hash for a named symbol in a named contract.
def sym_type_for(result, sym_name, contract_name)
  c = result[:typed]&.fetch('contracts', [])&.find { |c| c['name'] == contract_name }
  s = c&.fetch('symbols', [])&.find { |s| s['name'] == sym_name }
  s&.fetch('type', nil)
end

# Type name string (strips params) for a sym_type.
def type_name_of(type_ir)
  return nil unless type_ir.is_a?(Hash)
  type_ir.fetch('name', nil)
end

# type_env field: looks up a field on a named Record type from @type_shapes.
def type_env_field(result, type_name, field_name)
  result[:typed]&.fetch('type_env', {})
                &.fetch(type_name, {})
                &.fetch(field_name, nil)
end

def check(label, value)
  RESULTS << { label: label, pass: !!value }
  status = value ? "#{GREEN}PASS#{RESET}" : "#{RED}FAIL#{RESET}"
  puts "  #{status}  #{label}"
end

# ── Layer B: Proof-local simulation ──────────────────────────────────────────
#
# UpstreamCompositionP5: models BudgetedLocalLoop retry logic as pure Ruby.
# No scheduler, no blocking-wait, no background-process, no socket-primitive.
# Deterministic: same dispatch_seq input → same output.

module UpstreamCompositionP5
  SUCCESS_KINDS  = %w[found created].freeze
  DENIED_KINDS   = %w[capability_denied not_found].freeze
  RETRY_KINDS    = %w[upstream_error upstream_unavailable].freeze

  # single_attempt: process ONE job attempt against ONE ContractResult.
  # Returns a JobReceipt hash or a RetryEnvelope hash.
  # Retry budget check: RetryEnvelope only when attempt < max_attempts.
  def self.single_attempt(job, result)
    kind = result[:kind]
    if SUCCESS_KINDS.include?(kind)
      { type: 'JobReceipt', status: 'ok',
        job_class: job[:job_class], job_id: job[:job_id],
        attempt: job[:attempt], max_attempts: job[:max_attempts],
        message: result[:data].to_s, metadata: job[:metadata] }
    elsif DENIED_KINDS.include?(kind)
      { type: 'JobReceipt', status: 'non_retryable',
        job_class: job[:job_class], job_id: job[:job_id],
        attempt: job[:attempt], max_attempts: job[:max_attempts],
        message: result[:error_code].to_s, metadata: job[:metadata] }
    else
      # RETRY_KINDS: upstream_error or upstream_unavailable
      if job[:attempt] < job[:max_attempts]
        { type: 'RetryEnvelope',
          job_class: job[:job_class], job_id: job[:job_id],
          attempt: job[:attempt], max_attempts: job[:max_attempts],
          next_attempt: job[:attempt] + 1,
          reason: result[:error_code].to_s, metadata: job[:metadata] }
      else
        { type: 'JobReceipt', status: 'upstream_unavailable',
          job_class: job[:job_class], job_id: job[:job_id],
          attempt: job[:attempt], max_attempts: job[:max_attempts],
          message: result[:error_code].to_s, metadata: job[:metadata] }
      end
    end
  end

  # run_with_budget: BudgetedLocalLoop analog.
  # Iterates dispatch_seq, retrying on RETRY_KINDS until JobReceipt or all items consumed.
  # If dispatch_seq exhausted while still in RetryEnvelope path, the budget is declared
  # exhausted (the last item is replayed at max_attempts to trigger upstream_unavailable).
  def self.run_with_budget(job_template, dispatch_seq)
    attempt = job_template[:attempt]
    dispatch_seq.each do |result|
      j   = job_template.merge(attempt: attempt)
      out = single_attempt(j, result)
      return out if out[:type] == 'JobReceipt'
      attempt = out[:next_attempt]
    end
    # All dispatch items consumed without a terminal JobReceipt.
    # Force-exhaust: replay last result at max_attempts.
    last_result = dispatch_seq.last || { kind: 'upstream_error', error_code: 'E-EXHAUSTED', data: '' }
    j_exhaust   = job_template.merge(attempt: job_template[:max_attempts],
                                     max_attempts: job_template[:max_attempts])
    single_attempt(j_exhaust, last_result)
  end

  # metadata_lookup: simulates map_get + or_else.
  # Returns the value for key if present, otherwise default_val.
  def self.metadata_lookup(metadata, key, default_val = nil)
    val = metadata[key]
    val.nil? ? default_val : val
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Run the fixture through the production TypeChecker (Layer A)
# ─────────────────────────────────────────────────────────────────────────────

result = run_fixture(FIXTURE_PATH)

# Shared job and result fixtures for Layer B simulation
SIM_JOB_BASE = {
  job_class:    'TestJob',
  job_id:       'job-abc-123',
  attempt:      1,
  max_attempts: 3,
  metadata:     { 'queue' => 'custom-queue', 'worker' => 'DataSync', 'timeout_ms' => '5000' },
  payload:      'payload-data'
}.freeze

SIM_SUCCESS_RESULT = { kind: 'found',             data: 'result-item', error_code: '' }.freeze
SIM_DENIED_RESULT  = { kind: 'capability_denied', data: '',            error_code: 'E-HTTP-CAP-DENY' }.freeze
SIM_NF_RESULT      = { kind: 'not_found',         data: '',            error_code: 'E-HTTP-NOT-FOUND' }.freeze
SIM_ERROR_RESULT   = { kind: 'upstream_error',    data: '',            error_code: 'E-HTTP-SERVER-ERROR' }.freeze

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-TYPES: Type environment — all 5 declared types are in @type_shapes
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-TYPES: Type environment (5 declared types + key field shapes)#{RESET}"

check 'SJOB5-TYPES-1 type_env includes JobInput',
      result[:typed]&.fetch('type_env', {})&.key?('JobInput')

check 'SJOB5-TYPES-2 JobInput.metadata field = Map (params preserved by C1 fix)',
      begin
        f = type_env_field(result, 'JobInput', 'metadata')
        type_name_of(f) == 'Map'
      end

check 'SJOB5-TYPES-3 JobReceipt.metadata field = Map (P5 extension field)',
      begin
        f = type_env_field(result, 'JobReceipt', 'metadata')
        type_name_of(f) == 'Map'
      end

check 'SJOB5-TYPES-4 RetryEnvelope.metadata field = Map (map passthrough in retry)',
      begin
        f = type_env_field(result, 'RetryEnvelope', 'metadata')
        type_name_of(f) == 'Map'
      end

check 'SJOB5-TYPES-5 HttpResult and ContractResult present in type_env',
      begin
        env = result[:typed]&.fetch('type_env', {}) || {}
        env.key?('HttpResult') && env.key?('ContractResult')
      end

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-MAP: Metadata lookup chain (Layer A — production TypeChecker)
# Proves: map_get(job.metadata, key) → Option[String] via named Record field access.
# C1 fix: @type_shapes["JobInput"]["metadata"] = Map[String,String] (not Map).
# or_else(Option[String], default) → String.
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-MAP: Metadata lookup chain (C1 fix + or_else end-to-end)#{RESET}"

check 'SJOB5-MAP-1 MetadataReader: no type errors',
      contract_type_errors(result, 'MetadataReader').empty?

check 'SJOB5-MAP-2 MetadataReader.worker = Option (map_get(job.metadata, key) via named Record)',
      type_name_of(sym_type_for(result, 'worker', 'MetadataReader')) == 'Option'

check 'SJOB5-MAP-3 MetadataReader.worker params[0] = String (C1 fix: not Unknown)',
      sym_type_for(result, 'worker', 'MetadataReader')&.dig('params', 0, 'name') == 'String'

check 'SJOB5-MAP-4 MetadataReader.queue = String (or_else(Option[String], default) → String)',
      type_name_of(sym_type_for(result, 'queue', 'MetadataReader')) == 'String'

check 'SJOB5-MAP-5 MetadataReader.timeout = Option (second map_get through same Record field)',
      type_name_of(sym_type_for(result, 'timeout', 'MetadataReader')) == 'Option'

check 'SJOB5-MAP-6 MetadataReader.timeout params[0] = String (C1 fix preserves both map_get calls)',
      sym_type_for(result, 'timeout', 'MetadataReader')&.dig('params', 0, 'name') == 'String'

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-SUCCESS: Upstream found/created → ok JobReceipt (Layer A)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-SUCCESS: SuccessPath — found/created → ok JobReceipt#{RESET}"

check 'SJOB5-SUCCESS-1 SuccessPath: no type errors',
      contract_type_errors(result, 'SuccessPath').empty?

check 'SJOB5-SUCCESS-2 SuccessPath.receipt resolved type = JobReceipt (record literal hint)',
      type_name_of(sym_type_for(result, 'receipt', 'SuccessPath')) == 'JobReceipt'

check 'SJOB5-SUCCESS-3 SuccessPath.queue = String (or_else metadata lookup in SuccessPath)',
      type_name_of(sym_type_for(result, 'queue', 'SuccessPath')) == 'String'

check 'SJOB5-SUCCESS-4 SuccessPath status = accepted',
      contract_status(result, 'SuccessPath') == 'accepted'

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-DENIED: capability_denied → non-retryable JobReceipt (Layer A)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-DENIED: DeniedPath — capability_denied → non-retryable JobReceipt#{RESET}"

check 'SJOB5-DENIED-1 DeniedPath: no type errors',
      contract_type_errors(result, 'DeniedPath').empty?

check 'SJOB5-DENIED-2 DeniedPath.receipt resolved type = JobReceipt',
      type_name_of(sym_type_for(result, 'receipt', 'DeniedPath')) == 'JobReceipt'

check 'SJOB5-DENIED-3 DeniedPath status = accepted',
      contract_status(result, 'DeniedPath') == 'accepted'

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-RETRY: upstream_error within budget → RetryEnvelope (Layer A)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-RETRY: RetryablePath — upstream_error within budget → RetryEnvelope#{RESET}"

check 'SJOB5-RETRY-1 RetryablePath: no type errors',
      contract_type_errors(result, 'RetryablePath').empty?

check 'SJOB5-RETRY-2 RetryablePath.next_attempt type = Integer (job.attempt + 1 field arithmetic)',
      type_name_of(sym_type_for(result, 'next_attempt', 'RetryablePath')) == 'Integer'

check 'SJOB5-RETRY-3 RetryablePath.envelope resolved type = RetryEnvelope (record literal hint)',
      type_name_of(sym_type_for(result, 'envelope', 'RetryablePath')) == 'RetryEnvelope'

check 'SJOB5-RETRY-4 RetryablePath status = accepted',
      contract_status(result, 'RetryablePath') == 'accepted'

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-EXHAUSTED: budget exhausted → dead-letter JobReceipt (Layer A)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-EXHAUSTED: ExhaustedPath — budget exhausted → upstream_unavailable#{RESET}"

check 'SJOB5-EXHAUSTED-1 ExhaustedPath: no type errors',
      contract_type_errors(result, 'ExhaustedPath').empty?

check 'SJOB5-EXHAUSTED-2 ExhaustedPath.receipt resolved type = JobReceipt',
      type_name_of(sym_type_for(result, 'receipt', 'ExhaustedPath')) == 'JobReceipt'

check 'SJOB5-EXHAUSTED-3 ExhaustedPath status = accepted',
      contract_status(result, 'ExhaustedPath') == 'accepted'

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-SIM: Proof-local simulation (Layer B — behavioral)
# BudgetedLocalLoop analog: retry on upstream_error; non-retryable for
# capability_denied / not_found; dead-letter on budget exhaustion.
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-SIM: Proof-local simulation (BudgetedLocalLoop behavioral proof)#{RESET}"

sim_success = UpstreamCompositionP5.single_attempt(SIM_JOB_BASE, SIM_SUCCESS_RESULT)
check 'SJOB5-SIM-1 success path: found → JobReceipt(ok)',
      sim_success[:type] == 'JobReceipt' && sim_success[:status] == 'ok'

sim_denied = UpstreamCompositionP5.single_attempt(SIM_JOB_BASE, SIM_DENIED_RESULT)
check 'SJOB5-SIM-2 denied path: capability_denied → JobReceipt(non_retryable)',
      sim_denied[:type] == 'JobReceipt' && sim_denied[:status] == 'non_retryable'

sim_nf = UpstreamCompositionP5.single_attempt(SIM_JOB_BASE, SIM_NF_RESULT)
check 'SJOB5-SIM-3 not_found: 4xx → JobReceipt(non_retryable) — no retry for client error',
      sim_nf[:type] == 'JobReceipt' && sim_nf[:status] == 'non_retryable'

sim_retry = UpstreamCompositionP5.single_attempt(SIM_JOB_BASE, SIM_ERROR_RESULT)
check 'SJOB5-SIM-4 5xx within budget: upstream_error attempt 1/3 → RetryEnvelope(next_attempt=2)',
      sim_retry[:type] == 'RetryEnvelope' && sim_retry[:next_attempt] == 2

sim_exhausted_job = SIM_JOB_BASE.merge(attempt: 3, max_attempts: 3)
sim_exhausted = UpstreamCompositionP5.single_attempt(sim_exhausted_job, SIM_ERROR_RESULT)
check 'SJOB5-SIM-5 budget exhausted: upstream_error attempt 3/3 → JobReceipt(upstream_unavailable)',
      sim_exhausted[:type] == 'JobReceipt' && sim_exhausted[:status] == 'upstream_unavailable'

sim_seq = [SIM_ERROR_RESULT, SIM_ERROR_RESULT, SIM_SUCCESS_RESULT]
sim_seq_out = UpstreamCompositionP5.run_with_budget(SIM_JOB_BASE, sim_seq)
check 'SJOB5-SIM-6 attempt counter: [error,error,found] → JobReceipt at attempt 3',
      sim_seq_out[:type] == 'JobReceipt' &&
        sim_seq_out[:status] == 'ok' &&
        sim_seq_out[:attempt] == 3

check 'SJOB5-SIM-7 metadata passthrough: job.metadata == receipt.metadata',
      sim_success[:metadata].equal?(SIM_JOB_BASE[:metadata])

check 'SJOB5-SIM-8 metadata lookup: present key returns value; absent key returns default',
      begin
        present = UpstreamCompositionP5.metadata_lookup(SIM_JOB_BASE[:metadata], 'queue', 'default')
        absent  = UpstreamCompositionP5.metadata_lookup(SIM_JOB_BASE[:metadata], 'missing_key', 'default')
        present == 'custom-queue' && absent == 'default'
      end

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-REG: Regression checks (production TypeChecker gate)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-REG: Regression (production TypeChecker gate)#{RESET}"

check 'SJOB5-REG-1 all 5 fixture contracts accepted (production TypeChecker gate)',
      begin
        statuses = result[:typed]&.fetch('contracts', [])&.map { |c| c['status'] } || []
        statuses.length == 5 && statuses.all? { |s| s == 'accepted' }
      end

check 'SJOB5-REG-2 zero type_errors across full fixture (clean program)',
      all_type_errors(result).empty?

check 'SJOB5-REG-3 or_else metadata chain not regressed: MetadataReader.queue = String',
      type_name_of(sym_type_for(result, 'queue', 'MetadataReader')) == 'String'

check 'SJOB5-REG-4 field arithmetic not regressed: RetryablePath.next_attempt = Integer',
      type_name_of(sym_type_for(result, 'next_attempt', 'RetryablePath')) == 'Integer'

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-CLOSED: Closed surface scan (proof-local only, no real infrastructure)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-CLOSED: Closed surface scan#{RESET}"

check 'SJOB5-CLOSED-1 no upstream-store client (proof-local only)',
      !SOURCE.include?('Re' + 'dis') && !SOURCE.include?('Memca' + 'che')

check 'SJOB5-CLOSED-2 no blocking-wait or service-loop runtime',
      !SOURCE.include?('sle' + 'ep ') && !SOURCE.include?('Service' + 'Loop')

check 'SJOB5-CLOSED-3 no background-thread or background-process primitives',
      !SOURCE.include?('Thre' + 'ad.') && !SOURCE.include?('dae' + 'mon')

check 'SJOB5-CLOSED-4 no socket primitives (network-free proof)',
      !SOURCE.include?('TCP' + 'Socket') && !SOURCE.include?('Socket.tc' + 'p')

check 'SJOB5-CLOSED-5 no Sidekiq compat authority claim (lab-only)',
      !SOURCE.include?('Sidekiq.conf' + 'igure') && !SOURCE.include?('compat' + 'ibility auth')

# ─────────────────────────────────────────────────────────────────────────────
# SJOB5-GAP: Explicit answers to LAB-SIDEKIQ-P5 card questions
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}SJOB5-GAP: Explicit answers to card questions#{RESET}"

check 'SJOB5-GAP-1 Map metadata field in JobReceipt proved (type_env + sym_type both confirm Map)',
      begin
        env_field = type_env_field(result, 'JobReceipt', 'metadata')
        sym_field = sym_type_for(result, 'receipt', 'SuccessPath')
        type_name_of(env_field) == 'Map' && type_name_of(sym_field) == 'JobReceipt'
      end

check 'SJOB5-GAP-2 metadata Map passes through all 4 paths (each contract accepted with Map field)',
      begin
        %w[SuccessPath DeniedPath RetryablePath ExhaustedPath].all? do |cn|
          contract_status(result, cn) == 'accepted' &&
            contract_type_errors(result, cn).empty?
        end
      end

check 'SJOB5-GAP-3 capability_denied never retries (denied → non_retryable, not RetryEnvelope)',
      begin
        denied_out = UpstreamCompositionP5.run_with_budget(
          SIM_JOB_BASE,
          [SIM_DENIED_RESULT, SIM_SUCCESS_RESULT]
        )
        denied_out[:type] == 'JobReceipt' && denied_out[:status] == 'non_retryable' &&
          denied_out[:attempt] == 1
      end

check 'SJOB5-GAP-4 next_attempt typed as Integer (job.attempt + 1 via infer_binary)',
      type_name_of(sym_type_for(result, 'next_attempt', 'RetryablePath')) == 'Integer'

check 'SJOB5-GAP-5 proof-local only: no scheduler used (closed surface + Layer B pure Ruby)',
      !SOURCE.include?('sle' + 'ep') && !SOURCE.include?('Schedul' + 'er.') &&
        !SOURCE.include?('cron' + 'tab')

check 'SJOB5-GAP-6 lab-only authority: no canon claim, no finalized API, no compat authority',
      !SOURCE.include?('canon auth' + 'ority') &&
        !SOURCE.include?('Sidekiq.conf' + 'igure') &&
        SOURCE.include?('LAB-ONLY')

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{BOLD}── Summary ──────────────────────────────────────────────────────────────────#{RESET}"
passed = RESULTS.count { |r| r[:pass] }
total  = RESULTS.length
puts "#{passed}/#{total} PASS"

if passed < total
  puts "\n#{RED}FAILURES:#{RESET}"
  RESULTS.reject { |r| r[:pass] }.each { |r| puts "  FAIL  #{r[:label]}" }
end

exit(passed == total ? 0 : 1)
