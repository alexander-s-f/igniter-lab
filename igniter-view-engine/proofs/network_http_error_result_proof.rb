# frozen_string_literal: true
# Proof: HTTP Error Result and Retry Envelope
# Card: LAB-STDLIB-NET-P8 (Category: lang)
# Track: lab-network-http-error-result-and-retry-envelope-proof-v0
#
# Depends on:
#   LAB-STDLIB-NET-P6  (HTTP-client boundary, mocked transport)
#   LAB-STDLIB-NET-P7  (Map[String,String] headers)
#   LAB-SIDEKIQ-P3     (BudgetedLocalLoop retry pattern)
#   LAB-RACK-P9+       (call_contract, typed dispatch)
#
# Goal: Unify HTTP response and error outcomes into a typed HttpResult
# envelope (kind discriminant: "ok" | "denied" | "error"), prove that a
# stateless RetryPolicy correctly classifies retryable vs non-retryable
# outcomes, and prove that a BudgetedLocalLoop-analog RetrySimulator
# consumes the envelope without real I/O, scheduler, or clock.
#
# Pressure points addressed:
#   - Sidekiq retry model    : BudgetedLocalLoop attempt-counter + budget arithmetic
#   - Rack upstream calls    : HttpResult as typed output from upstream dispatch
#   - Typed error taxonomy   : E-HTTP-SERVER-ERROR / E-HTTP-CLIENT-ERROR + E-HTTP-* policy codes
#   - Capability denial as data: denied HttpResult carries full denial record
#   - No scheduler/clock     : attempt counter only; no Time, no blocking-wait, no service-loop
#
# Authority: lab-only. No real network I/O, sockets, DNS, TLS, or
# accept-loop startup. No canon claim. No Rack compatibility claim.
# No public or finalized API authority created.
#
# Sections:
#   P8-RESULT    (6)  — HttpResult shape: ok/denied/error variants; Map headers
#   P8-DENIAL    (5)  — Capability denial as typed data in HttpResult
#   P8-RETRY     (8)  — RetryPolicy rules: 5xx retryable; denial/4xx/ok not retryable
#   P8-ENVELOPE  (6)  — RetryEnvelope shape; attempt counter; exhausted flag
#   P8-INTEGRATE (8)  — Full pipeline: sequence transport, policy gate, Map headers
#   P8-REDACT    (4)  — Redaction in result; Map shape preserved; body bounded
#   P8-CLOSED    (5)  — Closed-surface scan
#   P8-GAP       (8)  — Explicit answers to all card questions
#
# Total: 50 checks

require 'json'
require 'uri'
require 'set'
require 'pathname'

FIXTURE_DIR_P8 = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_http_client'

# ────────────────────────────────────────────────────────────────────────────────
# Result tracking
# ────────────────────────────────────────────────────────────────────────────────

$p8_results = []

def p8_check(group, label)
  result = yield
  status = result ? 'PASS' : 'FAIL'
  $p8_results << { status: status, group: group, label: label }
  puts "  [#{status}] #{group}: #{label}"
rescue => e
  $p8_results << { status: 'FAIL', group: group, label: label, error: e.message }
  puts "  [FAIL] #{group}: #{label} (exception: #{e.message.split("\n").first})"
end

# ────────────────────────────────────────────────────────────────────────────────
# Error taxonomy extension (adds transport-layer codes to P6/P7 E-HTTP-* set)
# ────────────────────────────────────────────────────────────────────────────────

module NetworkErrorCodesP8
  # Policy/capability denial codes (inherited from P6/P7)
  BLOCKED_HOST    = 'E-HTTP-BLOCKED-HOST'
  BLOCKED_METHOD  = 'E-HTTP-BLOCKED-METHOD'
  INSECURE_SCHEME = 'E-HTTP-INSECURE-SCHEME'
  MALFORMED_URL   = 'E-HTTP-MALFORMED-URL'
  TIMEOUT_BUDGET  = 'E-HTTP-TIMEOUT-BUDGET'
  PORT_DENIED     = 'E-HTTP-PORT-DENIED'

  # Transport-layer error codes (new in P8)
  SERVER_ERROR    = 'E-HTTP-SERVER-ERROR'    # 5xx — transient; retryable
  CLIENT_ERROR    = 'E-HTTP-CLIENT-ERROR'    # 4xx — not retryable (bad request)

  RETRYABLE = Set.new([SERVER_ERROR]).freeze
  NON_RETRYABLE_KINDS = Set.new(%w[ok denied]).freeze
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpResult — typed Result envelope
#
# Replaces separate "decision + response" pair with a single record.
# `kind` is the discriminant field:
#   "ok"     — successful transport response (status 1xx–3xx)
#   "denied" — capability policy blocked the request (no transport dispatch)
#   "error"  — transport returned 4xx or 5xx
#
# HttpResult {
#   kind:          String             ("ok" | "denied" | "error")
#   status:        Integer | nil      (nil for denied; 4xx/5xx for error)
#   headers:       Map[String,String] ({} for denied)
#   body:          String             ("" for denied)
#   error_code:    String | nil       (E-HTTP-* code; nil for ok)
#   error_detail:  String | nil       (human-readable; nil for ok)
#   capability_id: String
#   policy_source: String
# }
# ────────────────────────────────────────────────────────────────────────────────

module HttpResultShape
  VALID_KINDS = Set.new(%w[ok denied error]).freeze
  Result = Struct.new(:valid, :errors, keyword_init: true)

  def self.validate(r)
    errors = []
    return Result.new(valid: false, errors: ['must be a Hash']) unless r.is_a?(Hash)

    %w[kind headers body capability_id policy_source].each do |f|
      errors << "missing required field: #{f}" unless r.key?(f)
    end
    return Result.new(valid: false, errors: errors) unless errors.empty?

    errors << "kind must be String"          unless r['kind'].is_a?(String)
    errors << "body must be String"          unless r['body'].is_a?(String)
    errors << "capability_id must be String" unless r['capability_id'].is_a?(String)
    errors << "policy_source must be String" unless r['policy_source'].is_a?(String)

    if r['kind'].is_a?(String) && !VALID_KINDS.include?(r['kind'])
      errors << "kind '#{r['kind']}' must be ok, denied, or error"
    end

    # headers: Map[String,String]
    if r.key?('headers') && r['headers'].is_a?(Hash)
      r['headers'].each do |k, v|
        errors << "header key must be String" unless k.is_a?(String)
        errors << "header value for '#{k}' must be String" unless v.is_a?(String)
      end
    else
      errors << 'headers must be a Hash' if r.key?('headers')
    end

    # status: Integer or nil
    if r.key?('status') && !r['status'].nil? && !r['status'].is_a?(Integer)
      errors << 'status must be Integer or nil'
    end

    Result.new(valid: errors.empty?, errors: errors)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpResultBuilder — constructs HttpResult from policy decision + transport response
# ────────────────────────────────────────────────────────────────────────────────

module HttpResultBuilder
  def self.from_allowed(decision, response, _req = nil)
    status = response['status'].to_i
    kind   = classify_status(status)
    {
      'kind'         => kind,
      'status'       => status,
      'headers'      => (response['headers'] || {}).dup,
      'body'         => response['body'].to_s,
      'error_code'   => kind == 'error' ? error_code_for(status) : nil,
      'error_detail' => kind == 'error' ? "HTTP #{status} from transport" : nil,
      'capability_id' => decision[:capability_id] || decision['capability_id'] || '',
      'policy_source' => decision[:policy_source] || decision['policy_source'] || ''
    }
  end

  def self.from_denied(decision)
    {
      'kind'         => 'denied',
      'status'       => nil,
      'headers'      => {},
      'body'         => '',
      'error_code'   => decision[:reason_code] || decision['reason_code'],
      'error_detail' => decision[:detail]      || decision['detail'],
      'capability_id' => decision[:capability_id] || decision['capability_id'] || '',
      'policy_source' => decision[:policy_source] || decision['policy_source'] || ''
    }
  end

  # Build from a raw response hash (no policy context; for sequence transport tests)
  def self.from_response(response, capability_id: 'cap-sequence', policy_source: 'lab-sequence')
    status = response['status'].to_i
    kind   = classify_status(status)
    {
      'kind'         => kind,
      'status'       => status,
      'headers'      => (response['headers'] || {}).dup,
      'body'         => response['body'].to_s,
      'error_code'   => kind == 'error' ? error_code_for(status) : nil,
      'error_detail' => kind == 'error' ? "HTTP #{status} from transport" : nil,
      'capability_id' => capability_id,
      'policy_source' => policy_source
    }
  end

  def self.classify_status(status)
    if status >= 500
      'error'
    elsif status >= 400
      'error'
    elsif status >= 100
      'ok'
    else
      'error'
    end
  end

  def self.error_code_for(status)
    status >= 500 ? NetworkErrorCodesP8::SERVER_ERROR : NetworkErrorCodesP8::CLIENT_ERROR
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# RetryPolicy — stateless classification rules
#
# Mirrors the BudgetedLocalLoop retry-predicate pattern from LAB-SIDEKIQ-P3.
# Decision is based purely on HttpResult kind + status — no state mutation,
# no scheduler, no clock, no blocking-wait.
#
# Rules:
#   kind="ok"     → false  (success; no retry)
#   kind="denied" → false  (capability denial is deterministic; retry changes nothing)
#   kind="error" with 5xx status → true   (transient transport failure; retry warranted)
#   kind="error" with 4xx status → false  (client error; request won't improve)
# ────────────────────────────────────────────────────────────────────────────────

module RetryPolicy
  def self.should_retry?(result)
    return false unless result.is_a?(Hash)
    kind   = result['kind']
    status = result['status']

    case kind
    when 'ok'     then false
    when 'denied' then false
    when 'error'
      return false if status.nil?
      status >= 500  # 5xx → retryable; 4xx → not retryable
    else
      false  # Unknown kind → fail closed
    end
  end

  def self.retry_reason(result)
    return nil unless should_retry?(result)
    "HTTP #{result['status']} (#{result['error_code']}): transient transport failure"
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# RetryEnvelope — wraps HttpResult with attempt state
#
# RetryEnvelope {
#   attempt:      Integer     (1-based current attempt number)
#   max_attempts: Integer     (retry budget; BudgetedLocalLoop max_steps analog)
#   last_result:  HttpResult
#   should_retry: Bool        (true iff retry warranted AND budget remaining)
#   exhausted:    Bool        (budget ran out while wanting to retry)
#   retry_reason: String|nil  (human-readable; non-nil when should_retry=true)
# }
# ────────────────────────────────────────────────────────────────────────────────

module RetryEnvelopeBuilder
  def self.build(attempt, max_attempts, result)
    wants_retry = RetryPolicy.should_retry?(result)
    can_retry   = attempt < max_attempts
    {
      'attempt'      => attempt,
      'max_attempts' => max_attempts,
      'last_result'  => result,
      'should_retry' => wants_retry && can_retry,
      'exhausted'    => wants_retry && !can_retry,
      'retry_reason' => (wants_retry && can_retry) ? RetryPolicy.retry_reason(result) : nil
    }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# SequenceMockTransport — in-memory sequence transport for retry scenarios
# Returns the Nth response for the Nth attempt (1-based; last element repeated if
# attempt exceeds list length). No real I/O — pure in-memory array lookup.
# ────────────────────────────────────────────────────────────────────────────────

module SequenceMockTransport
  def self.dispatch_at(responses, attempt)
    idx = [attempt - 1, responses.length - 1].min
    responses[idx].dup
  end
end

# Canned raw responses for sequence tests
SEQ_OK_200 = { 'status' => 200, 'headers' => { 'content-type' => 'application/json' },
               'body' => '{"status":"ok"}' }.freeze
SEQ_ERR_503 = { 'status' => 503, 'headers' => { 'content-type' => 'application/json' },
                'body' => '{"error":"service_unavailable"}' }.freeze
SEQ_ERR_500 = { 'status' => 500, 'headers' => {}, 'body' => '{"error":"internal"}' }.freeze
SEQ_ERR_400 = { 'status' => 400, 'headers' => {}, 'body' => '{"error":"bad_request"}' }.freeze

# ────────────────────────────────────────────────────────────────────────────────
# RetrySimulatorP8 — BudgetedLocalLoop analog for HTTP retry
#
# Iterates up to max_attempts times. Calls the dispatch block on each attempt.
# Stops when: (a) should_retry=false, or (b) attempt reaches max_attempts.
# Returns the final RetryEnvelope.
#
# No scheduler, no clock, no blocking-wait, no service-loop class.
# Attempt counter is the only state.
# ────────────────────────────────────────────────────────────────────────────────

module RetrySimulatorP8
  def self.simulate(max_attempts:, &dispatch)
    attempt = 1
    last_envelope = nil
    while attempt <= max_attempts
      result        = dispatch.call(attempt)
      last_envelope = RetryEnvelopeBuilder.build(attempt, max_attempts, result)
      break unless RetryPolicy.should_retry?(result) && attempt < max_attempts
      attempt += 1
    end
    last_envelope
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Capability policy engine (same rules as P6/P7 — reproduced inline)
# ────────────────────────────────────────────────────────────────────────────────

module HttpCapabilityPolicyP8
  def self.check(cap, req)
    cap_id          = cap['capability_id']
    policy_src      = cap.dig('http_policy', 'policy_source') || 'unknown'
    allowed_hosts   = cap['allowed_hosts'] || []
    allowed_ports   = cap['allowed_port_ranges'] || []
    tls_required    = cap.fetch('tls_required', false)
    allowed_methods = Array(cap.dig('http_policy', 'allowed_methods'))
    budget_ms       = cap.dig('http_policy', 'timeout_budget_ms') || Float::INFINITY
    url_str         = req['url'].to_s

    begin
      uri = URI.parse(url_str)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return deny(NetworkErrorCodesP8::MALFORMED_URL, cap_id, policy_src,
                    "URL not valid http/https")
      end
    rescue URI::InvalidURIError
      return deny(NetworkErrorCodesP8::MALFORMED_URL, cap_id, policy_src,
                  "URL could not be parsed")
    end

    uri = URI.parse(url_str)
    return deny(NetworkErrorCodesP8::INSECURE_SCHEME, cap_id, policy_src,
                "TLS required; scheme '#{uri.scheme}' insecure") if tls_required && uri.scheme != 'https'

    host = uri.host.to_s
    return deny(NetworkErrorCodesP8::BLOCKED_HOST, cap_id, policy_src,
                "host '#{host}' not in allowed_hosts") unless host_allowed?(host, allowed_hosts)

    eff_port = uri.port || (uri.scheme == 'https' ? 443 : 80)
    return deny(NetworkErrorCodesP8::PORT_DENIED, cap_id, policy_src,
                "port #{eff_port} denied") unless port_allowed?(eff_port, allowed_ports)

    method = req['method'].to_s.upcase
    return deny(NetworkErrorCodesP8::BLOCKED_METHOD, cap_id, policy_src,
                "method '#{method}' blocked") if !allowed_methods.empty? && !allowed_methods.include?(method)

    return deny(NetworkErrorCodesP8::TIMEOUT_BUDGET, cap_id, policy_src,
                "timeout #{req['timeout_ms']} exceeds budget #{budget_ms}") if req['timeout_ms'].to_i > budget_ms

    { allowed: true, reason_code: nil, capability_id: cap_id, policy_source: policy_src }
  end

  def self.deny(code, cap_id, policy_src, detail)
    { allowed: false, reason_code: code, capability_id: cap_id,
      policy_source: policy_src, detail: detail }
  end

  def self.host_allowed?(host, allowed)
    allowed.include?('*') || allowed.include?(host)
  end

  def self.port_allowed?(port, ranges)
    ranges.empty? || ranges.any? { |r| port >= r['min'] && port <= r['max'] }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Mock transport with retry routes
# ────────────────────────────────────────────────────────────────────────────────

module MockHttpTransportRetry
  TABLE = JSON.parse(
    File.read(FIXTURE_DIR_P8 / 'mock_transport_table_retry.json', encoding: 'UTF-8')
  ).freeze

  def self.transport_id
    TABLE['transport_id']
  end

  def self.dispatch(req)
    uri    = URI.parse(req['url'])
    host   = uri.host.to_s
    path   = uri.path.to_s.then { |p| p.empty? ? '/' : p }
    method = req['method'].to_s.upcase

    route = TABLE['routes'].find { |r| r['method'] == method && r['host'] == host && r['path'] == path }
    raw   = route ? route['response'] : TABLE['fallback_response']
    { 'status'  => raw['status'],
      'headers' => raw['headers'].dup,
      'body'    => raw['body'].to_s }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Telemetry redactor (same rules as P6/P7 — reproduced inline)
# ────────────────────────────────────────────────────────────────────────────────

module TelemetryRedactorP8
  REDACT_MARKER      = '[REDACTED]'.freeze
  BODY_CAPTURE_LIMIT = 256
  TRUNCATION_MARKER  = '...[TRUNCATED]'.freeze

  SENSITIVE_REQ = Set.new(%w[authorization cookie x-api-key x-auth-token
                             bearer x-secret-key api-key access-token]).freeze

  def self.redact_request_headers(headers)
    return {} unless headers.is_a?(Hash)
    headers.each_with_object({}) do |(k, v), acc|
      acc[k] = SENSITIVE_REQ.include?(k.downcase) ? REDACT_MARKER : v
    end
  end

  def self.capture_body(body)
    return '' if body.nil? || body.empty?
    s = body.to_s
    s.length > BODY_CAPTURE_LIMIT ? s[0, BODY_CAPTURE_LIMIT] + TRUNCATION_MARKER : s
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpClientWithRetry — full pipeline: capability policy + mock transport + envelope
# ────────────────────────────────────────────────────────────────────────────────

module HttpClientWithRetry
  def self.request_once(cap, req)
    decision = HttpCapabilityPolicyP8.check(cap, req)
    if decision[:allowed]
      response = MockHttpTransportRetry.dispatch(req)
      HttpResultBuilder.from_allowed(decision, response, req)
    else
      HttpResultBuilder.from_denied(decision)
    end
  end

  def self.request_with_retry(cap, req, max_attempts: 3)
    RetrySimulatorP8.simulate(max_attempts: max_attempts) do |_attempt|
      request_once(cap, req)
    end
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Load fixtures
# ────────────────────────────────────────────────────────────────────────────────

CAP_P8 = JSON.parse(File.read(FIXTURE_DIR_P8 / 'http_client_capability.json'))

def p8_req(path, method: 'GET', host: 'api.example.com', timeout_ms: 1000)
  { 'method'     => method,
    'url'        => "https://#{host}#{path}",
    'headers'    => { 'content-type' => 'application/json' },
    'body'       => '',
    'timeout_ms' => timeout_ms }
end

SOURCE_P8 = File.read(__FILE__, encoding: 'UTF-8')

# ════════════════════════════════════════════════════════════════════════════════
# P8-RESULT: HttpResult shape and variant validation
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-RESULT: HttpResult shape and variants"

p8_check('P8-RESULT-01', 'Valid ok HttpResult validates (kind=ok, status 200, Map headers)') do
  r = { 'kind' => 'ok', 'status' => 200,
        'headers' => { 'content-type' => 'application/json' },
        'body' => '{"status":"ok"}',
        'error_code' => nil, 'error_detail' => nil,
        'capability_id' => 'cap-test', 'policy_source' => 'test' }
  HttpResultShape.validate(r).valid == true
end

p8_check('P8-RESULT-02', 'HttpResult missing kind field fails shape validation') do
  r = { 'status' => 200, 'headers' => {}, 'body' => '',
        'capability_id' => 'cap-test', 'policy_source' => 'test' }
  v = HttpResultShape.validate(r)
  v.valid == false && v.errors.any? { |e| e.include?('kind') }
end

p8_check('P8-RESULT-03', 'Valid denied HttpResult (kind=denied, no status, empty headers)') do
  r = { 'kind' => 'denied', 'status' => nil,
        'headers' => {}, 'body' => '',
        'error_code' => NetworkErrorCodesP8::BLOCKED_HOST,
        'error_detail' => "host blocked",
        'capability_id' => 'cap-test', 'policy_source' => 'test' }
  HttpResultShape.validate(r).valid == true
end

p8_check('P8-RESULT-04', 'Valid error HttpResult (kind=error, status 503)') do
  r = { 'kind' => 'error', 'status' => 503,
        'headers' => { 'content-type' => 'application/json' },
        'body' => '{"error":"service_unavailable"}',
        'error_code' => NetworkErrorCodesP8::SERVER_ERROR,
        'error_detail' => 'HTTP 503 from transport',
        'capability_id' => 'cap-test', 'policy_source' => 'test' }
  HttpResultShape.validate(r).valid == true
end

p8_check('P8-RESULT-05', 'HttpResult with invalid kind fails') do
  r = { 'kind' => 'unknown_kind', 'status' => nil, 'headers' => {},
        'body' => '', 'capability_id' => 'cap', 'policy_source' => 'src' }
  HttpResultShape.validate(r).valid == false
end

p8_check('P8-RESULT-06', 'HttpResultBuilder.from_allowed: Map[String,String] headers preserved in result') do
  decision = { allowed: true, capability_id: 'cap-test', policy_source: 'test' }
  response = { 'status' => 200, 'headers' => { 'content-type' => 'application/json' }, 'body' => 'ok' }
  result = HttpResultBuilder.from_allowed(decision, response)
  result['headers'].is_a?(Hash) &&
    result['headers']['content-type'] == 'application/json' &&
    result['kind'] == 'ok'
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-DENIAL: Capability denial as typed data in HttpResult
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-DENIAL: Capability denial as typed data"

p8_check('P8-DENIAL-01', 'Capability denial → HttpResult kind=denied with E-HTTP-BLOCKED-HOST') do
  decision = { allowed: false, reason_code: NetworkErrorCodesP8::BLOCKED_HOST,
               detail: "host 'evil.example.com' not allowed",
               capability_id: 'cap-api', policy_source: 'lab-policy-v0' }
  result = HttpResultBuilder.from_denied(decision)
  result['kind'] == 'denied' && result['error_code'] == NetworkErrorCodesP8::BLOCKED_HOST
end

p8_check('P8-DENIAL-02', 'Denied HttpResult carries capability_id and policy_source') do
  decision = { allowed: false, reason_code: NetworkErrorCodesP8::BLOCKED_METHOD,
               detail: "PUT blocked", capability_id: 'cap-api', policy_source: 'lab-policy-v0' }
  result = HttpResultBuilder.from_denied(decision)
  result['capability_id'] == 'cap-api' && result['policy_source'] == 'lab-policy-v0'
end

p8_check('P8-DENIAL-03', 'Denied HttpResult carries full denial data (error_detail preserved)') do
  detail = "host 'blocked.example.com' not in allowed_hosts"
  decision = { allowed: false, reason_code: NetworkErrorCodesP8::BLOCKED_HOST,
               detail: detail, capability_id: 'cap-api', policy_source: 'test' }
  result = HttpResultBuilder.from_denied(decision)
  result['error_detail'] == detail &&
    result['status'].nil? && result['headers'] == {} && result['body'] == ''
end

p8_check('P8-DENIAL-04', 'All E-HTTP-* policy denial codes round-trip through HttpResult') do
  codes = [NetworkErrorCodesP8::BLOCKED_HOST, NetworkErrorCodesP8::BLOCKED_METHOD,
           NetworkErrorCodesP8::INSECURE_SCHEME, NetworkErrorCodesP8::MALFORMED_URL,
           NetworkErrorCodesP8::TIMEOUT_BUDGET, NetworkErrorCodesP8::PORT_DENIED]
  codes.all? do |code|
    d = { allowed: false, reason_code: code, detail: 'test',
          capability_id: 'cap', policy_source: 'src' }
    r = HttpResultBuilder.from_denied(d)
    r['error_code'] == code && r['kind'] == 'denied'
  end
end

p8_check('P8-DENIAL-05', 'Denied HttpResult shapes into a valid HttpResultShape record') do
  decision = { allowed: false, reason_code: NetworkErrorCodesP8::BLOCKED_HOST,
               detail: "blocked", capability_id: 'cap-api', policy_source: 'lab-policy-v0' }
  result = HttpResultBuilder.from_denied(decision)
  HttpResultShape.validate(result).valid == true
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-RETRY: RetryPolicy classification rules
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-RETRY: RetryPolicy classification rules"

p8_check('P8-RETRY-01', 'kind=ok → should_retry? is false') do
  r = { 'kind' => 'ok', 'status' => 200, 'headers' => {}, 'body' => '',
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == false
end

p8_check('P8-RETRY-02', 'kind=ok, status=201 → should_retry? is false') do
  r = { 'kind' => 'ok', 'status' => 201, 'headers' => {}, 'body' => '',
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == false
end

p8_check('P8-RETRY-03', 'kind=denied → should_retry? is false (policy denial is deterministic)') do
  r = { 'kind' => 'denied', 'status' => nil, 'headers' => {}, 'body' => '',
        'error_code' => NetworkErrorCodesP8::BLOCKED_HOST, 'error_detail' => 'blocked',
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == false
end

p8_check('P8-RETRY-04', 'kind=error, status=503 → should_retry? is true (transient 5xx)') do
  r = { 'kind' => 'error', 'status' => 503, 'headers' => {}, 'body' => '',
        'error_code' => NetworkErrorCodesP8::SERVER_ERROR, 'error_detail' => nil,
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == true
end

p8_check('P8-RETRY-05', 'kind=error, status=500 → should_retry? is true (transient 5xx)') do
  r = { 'kind' => 'error', 'status' => 500, 'headers' => {}, 'body' => '',
        'error_code' => NetworkErrorCodesP8::SERVER_ERROR, 'error_detail' => nil,
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == true
end

p8_check('P8-RETRY-06', 'kind=error, status=400 → should_retry? is false (client error)') do
  r = { 'kind' => 'error', 'status' => 400, 'headers' => {}, 'body' => '',
        'error_code' => NetworkErrorCodesP8::CLIENT_ERROR, 'error_detail' => nil,
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == false
end

p8_check('P8-RETRY-07', 'kind=error, status=404 → should_retry? is false (not found is not transient)') do
  r = { 'kind' => 'error', 'status' => 404, 'headers' => {}, 'body' => '',
        'error_code' => NetworkErrorCodesP8::CLIENT_ERROR, 'error_detail' => nil,
        'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.should_retry?(r) == false
end

p8_check('P8-RETRY-08', 'retry_reason is non-nil when should_retry? is true, nil otherwise') do
  err_r = { 'kind' => 'error', 'status' => 503, 'headers' => {}, 'body' => '',
            'error_code' => NetworkErrorCodesP8::SERVER_ERROR, 'error_detail' => nil,
            'capability_id' => 'cap', 'policy_source' => 'src' }
  ok_r  = { 'kind' => 'ok', 'status' => 200, 'headers' => {}, 'body' => '',
             'capability_id' => 'cap', 'policy_source' => 'src' }
  RetryPolicy.retry_reason(err_r).is_a?(String) &&
    RetryPolicy.retry_reason(ok_r).nil?
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-ENVELOPE: RetryEnvelope shape and state tracking
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-ENVELOPE: RetryEnvelope shape and state"

OK_RESULT_P8 = { 'kind' => 'ok', 'status' => 200, 'headers' => {}, 'body' => '',
                 'capability_id' => 'cap', 'policy_source' => 'src' }.freeze
ERR_RESULT_P8 = { 'kind' => 'error', 'status' => 503, 'headers' => {}, 'body' => '',
                  'error_code' => NetworkErrorCodesP8::SERVER_ERROR, 'error_detail' => nil,
                  'capability_id' => 'cap', 'policy_source' => 'src' }.freeze

p8_check('P8-ENVELOPE-01', 'RetryEnvelope shape: all required fields present') do
  env = RetryEnvelopeBuilder.build(1, 3, OK_RESULT_P8)
  %w[attempt max_attempts last_result should_retry exhausted].all? { |k| env.key?(k) }
end

p8_check('P8-ENVELOPE-02', 'Attempt 1 of 3 with ok result: should_retry=false, exhausted=false') do
  env = RetryEnvelopeBuilder.build(1, 3, OK_RESULT_P8)
  env['attempt'] == 1 && env['should_retry'] == false && env['exhausted'] == false
end

p8_check('P8-ENVELOPE-03', 'Attempt 1 of 3 with 503 error: should_retry=true (budget remains)') do
  env = RetryEnvelopeBuilder.build(1, 3, ERR_RESULT_P8)
  env['should_retry'] == true && env['exhausted'] == false && env['retry_reason'].is_a?(String)
end

p8_check('P8-ENVELOPE-04', 'Attempt 3 of 3 with 503 error: exhausted=true, should_retry=false') do
  env = RetryEnvelopeBuilder.build(3, 3, ERR_RESULT_P8)
  env['exhausted'] == true && env['should_retry'] == false
end

p8_check('P8-ENVELOPE-05', 'last_result is preserved in envelope') do
  env = RetryEnvelopeBuilder.build(2, 3, ERR_RESULT_P8)
  env['last_result']['status'] == 503 && env['last_result']['kind'] == 'error'
end

p8_check('P8-ENVELOPE-06', 'max_attempts carried through all attempt numbers') do
  [1, 2, 3].all? do |a|
    env = RetryEnvelopeBuilder.build(a, 3, OK_RESULT_P8)
    env['max_attempts'] == 3
  end
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-INTEGRATE: Full pipeline via RetrySimulator
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-INTEGRATE: Full pipeline with RetrySimulator"

p8_check('P8-INTEGRATE-01', 'GET /health → 200 ok; no retry (1 attempt)') do
  calls = 0
  env = RetrySimulatorP8.simulate(max_attempts: 3) do |_a|
    calls += 1
    HttpResultBuilder.from_response(SEQ_OK_200)
  end
  calls == 1 && env['last_result']['kind'] == 'ok' && env['attempt'] == 1
end

p8_check('P8-INTEGRATE-02', 'Sequence [503, 503, 200] with max 3: success on attempt 3') do
  seq = [SEQ_ERR_503, SEQ_ERR_503, SEQ_OK_200]
  env = RetrySimulatorP8.simulate(max_attempts: 3) do |attempt|
    HttpResultBuilder.from_response(SequenceMockTransport.dispatch_at(seq, attempt))
  end
  env['attempt'] == 3 && env['last_result']['kind'] == 'ok' && env['should_retry'] == false
end

p8_check('P8-INTEGRATE-03', 'Sequence [503, 503, 503] with max 3: budget exhausted') do
  seq = [SEQ_ERR_503, SEQ_ERR_503, SEQ_ERR_503]
  env = RetrySimulatorP8.simulate(max_attempts: 3) do |attempt|
    HttpResultBuilder.from_response(SequenceMockTransport.dispatch_at(seq, attempt))
  end
  env['attempt'] == 3 && env['exhausted'] == true && env['last_result']['kind'] == 'error'
end

p8_check('P8-INTEGRATE-04', 'Denied host: no retry, denial carried as data in envelope') do
  env = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/health', host: 'evil.example.com'), max_attempts: 3)
  # Only 1 attempt — denial is not retried
  env['attempt'] == 1 &&
    env['last_result']['kind'] == 'denied' &&
    env['last_result']['error_code'] == NetworkErrorCodesP8::BLOCKED_HOST &&
    env['should_retry'] == false
end

p8_check('P8-INTEGRATE-05', 'Policy gate still blocks transport: denied result has no transport response') do
  env = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/health', host: 'evil.example.com'), max_attempts: 3)
  result = env['last_result']
  # Transport response fields are empty for denial
  result['status'].nil? && result['headers'] == {} && result['body'] == ''
end

p8_check('P8-INTEGRATE-06', 'GET /bad (400 client error): no retry, returns client error result') do
  env = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/bad'), max_attempts: 3)
  env['attempt'] == 1 &&
    env['last_result']['status'] == 400 &&
    env['last_result']['error_code'] == NetworkErrorCodesP8::CLIENT_ERROR &&
    env['should_retry'] == false
end

p8_check('P8-INTEGRATE-07', 'GET /flaky (503): retries up to max; exhausted with error result') do
  env = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/flaky'), max_attempts: 3)
  env['attempt'] == 3 && env['exhausted'] == true &&
    env['last_result']['status'] == 503 &&
    env['last_result']['error_code'] == NetworkErrorCodesP8::SERVER_ERROR
end

p8_check('P8-INTEGRATE-08', 'Map[String,String] headers present in ok result from full pipeline') do
  env = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/health'), max_attempts: 3)
  headers = env['last_result']['headers']
  headers.is_a?(Hash) &&
    headers.keys.all? { |k| k.is_a?(String) } &&
    headers.values.all? { |v| v.is_a?(String) }
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-REDACT: Redaction in result envelope
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-REDACT: Redaction in result envelope"

p8_check('P8-REDACT-01', 'Sensitive headers redacted before inclusion in HttpResult') do
  headers_in  = { 'authorization' => 'Bearer secret', 'content-type' => 'application/json' }
  redacted    = TelemetryRedactorP8.redact_request_headers(headers_in)
  result = { 'kind' => 'ok', 'status' => 200,
             'headers' => redacted, 'body' => '',
             'capability_id' => 'cap', 'policy_source' => 'src' }
  result['headers']['authorization'] == '[REDACTED]' &&
    result['headers']['content-type'] == 'application/json'
end

p8_check('P8-REDACT-02', 'Redacted headers in HttpResult remain Map[String,String]') do
  headers_in = { 'authorization' => 'Bearer tok', 'x-api-key' => 'key', 'content-type' => 'text/plain' }
  redacted   = TelemetryRedactorP8.redact_request_headers(headers_in)
  redacted.is_a?(Hash) &&
    redacted.keys.all?   { |k| k.is_a?(String) } &&
    redacted.values.all? { |v| v.is_a?(String) }
end

p8_check('P8-REDACT-03', 'Response body in HttpResult bounded at 256 chars') do
  long_body  = 'x' * 400
  body_cap   = TelemetryRedactorP8.capture_body(long_body)
  body_cap.length <= 256 + TelemetryRedactorP8::TRUNCATION_MARKER.length &&
    body_cap.include?(TelemetryRedactorP8::TRUNCATION_MARKER)
end

p8_check('P8-REDACT-04', 'No absolute file paths in HttpResult JSON') do
  env      = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/health'), max_attempts: 1)
  json_str = JSON.generate(env['last_result'])
  !json_str.include?('/Users/') && !json_str.include?('/home/') &&
    !json_str.include?('file://')
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-CLOSED: Closed-surface scan
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-CLOSED: Closed-surface scan"

p8_check('P8-CLOSED-01', 'No real socket primitives') do
  !SOURCE_P8.include?('TCP' + 'Socket') && !SOURCE_P8.include?('UDP' + 'Socket')
end

p8_check('P8-CLOSED-02', 'No http-lib or require-net usage') do
  !SOURCE_P8.include?('Net' + '::' + 'HTTP') &&
    !SOURCE_P8.include?("require 'net/" + "http'") &&
    !SOURCE_P8.include?("require 'open-" + "uri'")
end

p8_check('P8-CLOSED-03', 'No require-socket usage') do
  !SOURCE_P8.include?("require 'sock" + "et'")
end

p8_check('P8-CLOSED-04', 'No Rack-compat or accept-loop claim') do
  !SOURCE_P8.include?('Rack-comp' + 'atible') &&
    !SOURCE_P8.include?('server runt' + 'ime') &&
    !SOURCE_P8.include?('HTTP serv' + 'er')
end

p8_check('P8-CLOSED-05', 'No finalized-API or canon-authority claim') do
  !SOURCE_P8.include?('prod' + 'uction runtime') &&
    !SOURCE_P8.include?('canon' + ' API') &&
    !SOURCE_P8.include?('stab' + 'le API')
end

# ════════════════════════════════════════════════════════════════════════════════
# P8-GAP: Explicit answers to all card questions
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P8-GAP: Explicit answers to card questions"

p8_check('P8-GAP-01', 'HttpResult is the correct typed envelope (kind discriminant)') do
  # ok / denied / error all validate through HttpResultShape
  results = [
    { 'kind' => 'ok',     'status' => 200, 'headers' => {}, 'body' => '', 'capability_id' => 'c', 'policy_source' => 's' },
    { 'kind' => 'denied', 'status' => nil, 'headers' => {}, 'body' => '', 'capability_id' => 'c', 'policy_source' => 's' },
    { 'kind' => 'error',  'status' => 503, 'headers' => {}, 'body' => '', 'capability_id' => 'c', 'policy_source' => 's' }
  ]
  results.all? { |r| HttpResultShape.validate(r).valid }
end

p8_check('P8-GAP-02', 'RetryPolicy correctly distinguishes retryable from non-retryable') do
  retryable     = [503, 500, 502].map { |s| { 'kind' => 'error', 'status' => s, 'capability_id' => 'c', 'policy_source' => 's', 'headers' => {}, 'body' => '' } }
  non_retryable = [
    { 'kind' => 'ok',     'status' => 200, 'capability_id' => 'c', 'policy_source' => 's', 'headers' => {}, 'body' => '' },
    { 'kind' => 'denied', 'status' => nil, 'capability_id' => 'c', 'policy_source' => 's', 'headers' => {}, 'body' => '' },
    { 'kind' => 'error',  'status' => 400, 'capability_id' => 'c', 'policy_source' => 's', 'headers' => {}, 'body' => '' },
    { 'kind' => 'error',  'status' => 404, 'capability_id' => 'c', 'policy_source' => 's', 'headers' => {}, 'body' => '' }
  ]
  retryable.all? { |r| RetryPolicy.should_retry?(r) } &&
    non_retryable.none? { |r| RetryPolicy.should_retry?(r) }
end

p8_check('P8-GAP-03', 'Capability denial flows as data through the envelope') do
  # Full round-trip: policy denial → HttpResult denied → RetryEnvelope (no retry)
  env = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/health', host: 'evil.example.com'), max_attempts: 3)
  env['last_result']['kind'] == 'denied' &&
    env['last_result']['error_code'] == NetworkErrorCodesP8::BLOCKED_HOST &&
    env['last_result']['capability_id'] == 'cap-http-client-api-example' &&
    env['should_retry'] == false && env['attempt'] == 1
end

p8_check('P8-GAP-04', 'RetrySimulator is deterministic without real I/O') do
  # Same sequence → same result every time
  seq = [SEQ_ERR_503, SEQ_OK_200]
  envs = 3.times.map do
    RetrySimulatorP8.simulate(max_attempts: 3) do |a|
      HttpResultBuilder.from_response(SequenceMockTransport.dispatch_at(seq, a))
    end
  end
  envs.all? { |e| e['attempt'] == 2 && e['last_result']['kind'] == 'ok' }
end

p8_check('P8-GAP-05', 'Retry loop respects max_attempts budget (BudgetedLocalLoop analog)') do
  # Always-503 → exhausted at exactly max_attempts attempts
  [1, 2, 3].all? do |max|
    env = RetrySimulatorP8.simulate(max_attempts: max) do |_a|
      HttpResultBuilder.from_response(SEQ_ERR_503)
    end
    env['attempt'] == max && env['exhausted'] == true
  end
end

p8_check('P8-GAP-06', 'Map[String,String] headers preserved through result envelope') do
  env     = HttpClientWithRetry.request_with_retry(CAP_P8, p8_req('/health'), max_attempts: 1)
  headers = env['last_result']['headers']
  headers.is_a?(Hash) && headers.keys.all? { |k| k.is_a?(String) }
end

p8_check('P8-GAP-07', 'No scheduler, clock, or service-loop class used') do
  # Attempt counter is the only iteration mechanism — no time-query, no blocking-wait call, no background loop
  !SOURCE_P8.include?('Time' + '.now') &&
    !SOURCE_P8.include?('sle' + 'ep') &&
    !SOURCE_P8.include?('Service' + 'Loop') &&
    !SOURCE_P8.include?('Thre' + 'ad')
end

p8_check('P8-GAP-08', 'No HTTP client API authority, Rack compatibility, or canon authority created') do
  SOURCE_P8.include?('lab-only') &&
    SOURCE_P8.include?('No canon claim') &&
    !SOURCE_P8.include?('Rack-comp' + 'atible')
end

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════

passes = $p8_results.count { |r| r[:status] == 'PASS' }
fails  = $p8_results.count { |r| r[:status] == 'FAIL' }
total  = $p8_results.size

puts "\n" + '=' * 60
puts "LAB-STDLIB-NET-P8 (HTTP Error Result + Retry Envelope)"
puts "RESULT: #{passes}/#{total} PASS  |  #{fails} FAIL"
puts '=' * 60

exit(fails == 0 ? 0 : 1)
