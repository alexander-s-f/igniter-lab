# frozen_string_literal: true
# Proof: HTTP Upstream Call Contract Composition
# Card: LAB-STDLIB-NET-P9 (Category: lang)
# Track: lab-network-http-upstream-call-contract-composition-proof-v0
#
# Goal: Prove how an Igniter contract composes an upstream HTTP call result
# with domain logic:
#   request builder -> mocked HTTP boundary -> HttpResult envelope
#   -> typed domain response / retry envelope
#
# Composition chain:
#   Domain Input
#     -> ItemRequestBuilderP9.build_*()           HttpRequest shape (Map[String,String] headers)
#     -> HttpCapabilityPolicyP9.check()           allowed / denied
#        |-- denied: HttpResultBuilderP9.from_denied()         -> HttpResult{kind:denied}
#        `-- allowed: MockHttpTransportDomain.dispatch()       -> HttpResult{kind:ok/error}
#     -> [RetrySimulatorP9   --  Sidekiq path only]
#     -> DomainResponseMapperP9.map()             -> ContractResult
#
# ContractResult kinds:
#   found | created | not_found | upstream_error | capability_denied | upstream_unavailable
#
# Pressure:
#   - Rack handler calling upstream service (single call, no retry)
#   - Sidekiq job calling upstream service (BudgetedLocalLoop analog retry)
#   - capability denial as typed branch (no transport dispatch)
#   - no real sockets, name-resolution, accept-loop startup, or blocking-wait calls
#
# UpstreamCallContractP9 is the proof-local analog of call_contract from LAB-RACK.
# call_contract is explicitly lab-only; no canon claim, no finalized API surface.
#
# Authority: lab-only. No public API, no Rack compatibility claim, no canon claim.

require 'json'
require 'uri'
require 'set'
require 'pathname'

FIXTURE_DIR_P9 = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_http_client'

# ────────────────────────────────────────────────────────────────────────────────
# Result tracking
# ────────────────────────────────────────────────────────────────────────────────

$p9_results = []

def p9_check(group, label)
  result = yield
  status = result ? 'PASS' : 'FAIL'
  $p9_results << { status: status, group: group, label: label }
  puts "  [#{status}] #{group}: #{label}"
rescue => e
  $p9_results << { status: 'FAIL', group: group, label: label, error: e.message }
  puts "  [FAIL] #{group}: #{label} (exception: #{e.message.split("\n").first})"
end

# ────────────────────────────────────────────────────────────────────────────────
# Error taxonomy (same set as P6/P7/P8; reproduced for standalone proof)
# ────────────────────────────────────────────────────────────────────────────────

module NetworkErrorCodesP9
  BLOCKED_HOST    = 'E-HTTP-BLOCKED-HOST'
  BLOCKED_METHOD  = 'E-HTTP-BLOCKED-METHOD'
  INSECURE_SCHEME = 'E-HTTP-INSECURE-SCHEME'
  MALFORMED_URL   = 'E-HTTP-MALFORMED-URL'
  TIMEOUT_BUDGET  = 'E-HTTP-TIMEOUT-BUDGET'
  PORT_DENIED     = 'E-HTTP-PORT-DENIED'
  SERVER_ERROR    = 'E-HTTP-SERVER-ERROR'
  CLIENT_ERROR    = 'E-HTTP-CLIENT-ERROR'
end

# ────────────────────────────────────────────────────────────────────────────────
# ContractResult — typed domain output envelope
#
# ContractResult {
#   kind:           String    ("found" | "created" | "not_found" | "upstream_error"
#                              | "capability_denied" | "upstream_unavailable")
#   data:           Hash|nil  (domain payload for found/created; nil otherwise)
#   error_code:     String|nil
#   error_detail:   String|nil
#   retry_envelope: Hash|nil  (RetryEnvelope from simulator; non-nil when applicable)
# }
#
# "upstream_unavailable" fires when the retry budget is exhausted.
# "upstream_error" fires for non-retried errors (4xx, or immediate Rack 5xx).
# ────────────────────────────────────────────────────────────────────────────────

module ContractResultShape
  VALID_KINDS = Set.new(%w[found created not_found upstream_error
                           capability_denied upstream_unavailable]).freeze
  Result = Struct.new(:valid, :errors, keyword_init: true)

  def self.validate(r)
    errors = []
    return Result.new(valid: false, errors: ['must be Hash']) unless r.is_a?(Hash)
    errors << 'missing required field: kind' unless r.key?('kind')
    return Result.new(valid: false, errors: errors) unless errors.empty?
    errors << 'kind must be String' unless r['kind'].is_a?(String)
    if r['kind'].is_a?(String) && !VALID_KINDS.include?(r['kind'])
      errors << "unknown kind: '#{r['kind']}'"
    end
    Result.new(valid: errors.empty?, errors: errors)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# ItemRequestBuilderP9 — maps domain inputs to HttpRequest shapes
# ────────────────────────────────────────────────────────────────────────────────

module ItemRequestBuilderP9
  BASE_URL = 'https://api.example.com'

  def self.build_get(id, timeout_ms: 1000)
    { 'method'     => 'GET',
      'url'        => "#{BASE_URL}/items/#{id}",
      'headers'    => { 'accept' => 'application/json' },
      'body'       => '',
      'timeout_ms' => timeout_ms }
  end

  def self.build_create(attrs, timeout_ms: 1000)
    { 'method'     => 'POST',
      'url'        => "#{BASE_URL}/items",
      'headers'    => { 'content-type' => 'application/json',
                        'accept'       => 'application/json' },
      'body'       => JSON.generate(attrs),
      'timeout_ms' => timeout_ms }
  end

  def self.build_path(path, method: 'GET', timeout_ms: 1000)
    { 'method'     => method,
      'url'        => "#{BASE_URL}#{path}",
      'headers'    => { 'accept' => 'application/json' },
      'body'       => '',
      'timeout_ms' => timeout_ms }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpResultBuilderP9 — constructs HttpResult from policy decision + response
# ────────────────────────────────────────────────────────────────────────────────

module HttpResultBuilderP9
  def self.from_allowed(decision, response, _req = nil)
    status = response['status'].to_i
    kind   = status >= 400 ? 'error' : 'ok'
    { 'kind'         => kind,
      'status'       => status,
      'headers'      => (response['headers'] || {}).dup,
      'body'         => response['body'].to_s,
      'error_code'   => kind == 'error' ? error_code_for(status) : nil,
      'error_detail' => kind == 'error' ? "HTTP #{status} from transport" : nil,
      'capability_id' => decision[:capability_id] || decision['capability_id'] || '',
      'policy_source' => decision[:policy_source] || decision['policy_source'] || '' }
  end

  def self.from_denied(decision)
    { 'kind'         => 'denied',
      'status'       => nil,
      'headers'      => {},
      'body'         => '',
      'error_code'   => decision[:reason_code] || decision['reason_code'],
      'error_detail' => decision[:detail]      || decision['detail'],
      'capability_id' => decision[:capability_id] || decision['capability_id'] || '',
      'policy_source' => decision[:policy_source] || decision['policy_source'] || '' }
  end

  def self.error_code_for(status)
    status >= 500 ? NetworkErrorCodesP9::SERVER_ERROR : NetworkErrorCodesP9::CLIENT_ERROR
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpCapabilityPolicyP9 — capability policy engine (same rules as P6/P7/P8)
# ────────────────────────────────────────────────────────────────────────────────

module HttpCapabilityPolicyP9
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
        return deny(NetworkErrorCodesP9::MALFORMED_URL, cap_id, policy_src, 'not http/https')
      end
    rescue URI::InvalidURIError
      return deny(NetworkErrorCodesP9::MALFORMED_URL, cap_id, policy_src, 'parse error')
    end

    uri = URI.parse(url_str)
    return deny(NetworkErrorCodesP9::INSECURE_SCHEME, cap_id, policy_src,
                'TLS required') if tls_required && uri.scheme != 'https'

    host = uri.host.to_s
    return deny(NetworkErrorCodesP9::BLOCKED_HOST, cap_id, policy_src,
                "host '#{host}' not allowed") unless host_allowed?(host, allowed_hosts)

    eff_port = uri.port || (uri.scheme == 'https' ? 443 : 80)
    return deny(NetworkErrorCodesP9::PORT_DENIED, cap_id, policy_src,
                "port #{eff_port} denied") unless port_allowed?(eff_port, allowed_ports)

    method = req['method'].to_s.upcase
    return deny(NetworkErrorCodesP9::BLOCKED_METHOD, cap_id, policy_src,
                "method '#{method}' blocked") if !allowed_methods.empty? && !allowed_methods.include?(method)

    return deny(NetworkErrorCodesP9::TIMEOUT_BUDGET, cap_id, policy_src,
                'timeout exceeds budget') if req['timeout_ms'].to_i > budget_ms

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
# RetryPolicyP9 / RetryEnvelopeBuilderP9 / RetrySimulatorP9
# BudgetedLocalLoop analog: same rules as P8; reproduced with P9 suffix.
# No blocking-wait calls, no service-loop class, no time-query.
# ────────────────────────────────────────────────────────────────────────────────

module RetryPolicyP9
  def self.should_retry?(result)
    return false unless result.is_a?(Hash)
    kind   = result['kind']
    status = result['status']
    case kind
    when 'ok'     then false
    when 'denied' then false
    when 'error'  then !status.nil? && status >= 500
    else false
    end
  end
end

module RetryEnvelopeBuilderP9
  def self.build(attempt, max_attempts, result)
    wants = RetryPolicyP9.should_retry?(result)
    can   = attempt < max_attempts
    { 'attempt'      => attempt,
      'max_attempts' => max_attempts,
      'last_result'  => result,
      'should_retry' => wants && can,
      'exhausted'    => wants && !can,
      'retry_reason' => (wants && can) ? "HTTP #{result['status']} transient" : nil }
  end
end

module RetrySimulatorP9
  def self.simulate(max_attempts:, &dispatch)
    attempt      = 1
    last_envelope = nil
    while attempt <= max_attempts
      result        = dispatch.call(attempt)
      last_envelope = RetryEnvelopeBuilderP9.build(attempt, max_attempts, result)
      break unless RetryPolicyP9.should_retry?(result) && attempt < max_attempts
      attempt += 1
    end
    last_envelope
  end
end

module SequenceMockTransportP9
  def self.dispatch_at(responses, attempt)
    idx = [attempt - 1, responses.length - 1].min
    responses[idx].dup
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# TelemetryRedactorP9 (same rules as P6/P7/P8)
# ────────────────────────────────────────────────────────────────────────────────

module TelemetryRedactorP9
  REDACT_MARKER      = '[REDACTED]'.freeze
  BODY_CAPTURE_LIMIT = 256
  TRUNCATION_MARKER  = '...[TRUNCATED]'.freeze

  SENSITIVE_KEYS = Set.new(%w[authorization cookie x-api-key x-auth-token
                               bearer x-secret-key api-key access-token]).freeze

  def self.redact_request_headers(headers)
    return {} unless headers.is_a?(Hash)
    headers.each_with_object({}) do |(k, v), acc|
      acc[k] = SENSITIVE_KEYS.include?(k.downcase) ? REDACT_MARKER : v
    end
  end

  def self.capture_body(body)
    return '' if body.nil? || body.empty?
    s = body.to_s
    s.length > BODY_CAPTURE_LIMIT ? s[0, BODY_CAPTURE_LIMIT] + TRUNCATION_MARKER : s
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# MockHttpTransportDomain — reads domain fixture; deterministic table lookup
# ────────────────────────────────────────────────────────────────────────────────

module MockHttpTransportDomain
  TABLE = JSON.parse(
    File.read(FIXTURE_DIR_P9 / 'mock_transport_table_domain.json', encoding: 'UTF-8')
  ).freeze

  def self.transport_id
    TABLE['transport_id']
  end

  def self.dispatch(req)
    uri    = URI.parse(req['url'])
    host   = uri.host.to_s
    path   = uri.path.to_s.then { |p| p.empty? ? '/' : p }
    method = req['method'].to_s.upcase

    route = TABLE['routes'].find do |r|
      r['method'] == method && r['host'] == host && r['path'] == path
    end
    raw = route ? route['response'] : TABLE['fallback_response']
    { 'status'  => raw['status'],
      'headers' => (raw['headers'] || {}).dup,
      'body'    => raw['body'].to_s }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# DomainResponseMapperP9 — maps HttpResult -> ContractResult
#
# Rack path: called directly after a single request_once call.
# Sidekiq path: called by UpstreamCallContractP9.call_with_retry (non-exhausted).
# retry_envelope is nil for Rack calls; non-nil for Sidekiq calls.
# ────────────────────────────────────────────────────────────────────────────────

module DomainResponseMapperP9
  def self.map(http_result, retry_envelope: nil)
    kind   = http_result['kind']
    status = http_result['status']

    case kind
    when 'ok'
      data    = parse_body(http_result['body'])
      cr_kind = status == 201 ? 'created' : 'found'
      contract_result(cr_kind, data: data, retry_envelope: retry_envelope)
    when 'denied'
      contract_result('capability_denied',
        error_code:   http_result['error_code'],
        error_detail: http_result['error_detail'])
    when 'error'
      if status == 404
        contract_result('not_found', retry_envelope: retry_envelope)
      else
        contract_result('upstream_error',
          error_code:     http_result['error_code'],
          error_detail:   http_result['error_detail'],
          retry_envelope: retry_envelope)
      end
    else
      contract_result('upstream_error',
        error_detail: "unknown HttpResult kind: #{kind}")
    end
  end

  def self.parse_body(body)
    return nil if body.nil? || body.empty?
    JSON.parse(body) rescue nil
  end

  def self.contract_result(kind, data: nil, error_code: nil, error_detail: nil, retry_envelope: nil)
    { 'kind'         => kind,
      'data'         => data,
      'error_code'   => error_code,
      'error_detail' => error_detail,
      'retry_envelope' => retry_envelope }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# UpstreamCallContractP9
#
# Proof-local analog of call_contract from LAB-RACK.
# call_contract is explicitly lab-only; no canon claim; no finalized API surface.
#
# call()              -> Rack scenario: single dispatch, no retry
# call_with_retry()   -> Sidekiq scenario: BudgetedLocalLoop analog with budget
# call_with_sequence()-> test helper: sequence transport for retry scenario proofs
# ────────────────────────────────────────────────────────────────────────────────

module UpstreamCallContractP9
  # Core single dispatch (shared by both scenarios)
  def self.request_once(cap, req)
    decision = HttpCapabilityPolicyP9.check(cap, req)
    if decision[:allowed]
      response = MockHttpTransportDomain.dispatch(req)
      HttpResultBuilderP9.from_allowed(decision, response, req)
    else
      HttpResultBuilderP9.from_denied(decision)
    end
  end

  # Rack scenario: one call; returns ContractResult immediately (no retry)
  def self.call(cap, req)
    DomainResponseMapperP9.map(request_once(cap, req))
  end

  # Sidekiq scenario: retry with budget; returns ContractResult
  # exhausted -> upstream_unavailable; otherwise -> DomainResponseMapperP9.map
  def self.call_with_retry(cap, req, max_attempts: 3)
    env = RetrySimulatorP9.simulate(max_attempts: max_attempts) do |_attempt|
      request_once(cap, req)
    end
    result = env['last_result']
    if env['exhausted']
      { 'kind'         => 'upstream_unavailable',
        'data'         => nil,
        'error_code'   => result['error_code'],
        'error_detail' => "Retry budget exhausted after #{env['attempt']} attempts",
        'retry_envelope' => env }
    else
      DomainResponseMapperP9.map(result, retry_envelope: env)
    end
  end

  # Test helper: sequence-driven retry (SequenceMockTransportP9 instead of domain table)
  def self.call_with_sequence(cap, req, seq_responses, max_attempts: 3)
    env = RetrySimulatorP9.simulate(max_attempts: max_attempts) do |attempt|
      decision = HttpCapabilityPolicyP9.check(cap, req)
      if decision[:allowed]
        raw = SequenceMockTransportP9.dispatch_at(seq_responses, attempt)
        HttpResultBuilderP9.from_allowed(decision, raw, req)
      else
        HttpResultBuilderP9.from_denied(decision)
      end
    end
    result = env['last_result']
    if env['exhausted']
      { 'kind'         => 'upstream_unavailable',
        'data'         => nil,
        'error_code'   => result['error_code'],
        'error_detail' => "Retry budget exhausted after #{env['attempt']} attempts",
        'retry_envelope' => env }
    else
      DomainResponseMapperP9.map(result, retry_envelope: env)
    end
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Load fixtures and shared constants
# ────────────────────────────────────────────────────────────────────────────────

CAP_P9    = JSON.parse(File.read(FIXTURE_DIR_P9 / 'http_client_capability.json'))
SOURCE_P9 = File.read(__FILE__, encoding: 'UTF-8')

REQ_GET_1    = ItemRequestBuilderP9.build_get(1).freeze
REQ_GET_99   = ItemRequestBuilderP9.build_get(99).freeze
REQ_GET_FL   = ItemRequestBuilderP9.build_path('/items/flaky').freeze
REQ_POST     = ItemRequestBuilderP9.build_create({ 'name' => 'Gadget' }).freeze
REQ_DENIED   = { 'method' => 'GET', 'url' => 'https://evil.example.com/items/1',
                 'headers' => { 'accept' => 'application/json' },
                 'body' => '', 'timeout_ms' => 1000 }.freeze

SEQ_OK_P9    = { 'status' => 200, 'headers' => { 'content-type' => 'application/json' },
                 'body' => '{"id":1,"status":"ok"}' }.freeze
SEQ_503_P9   = { 'status' => 503, 'headers' => { 'content-type' => 'application/json' },
                 'body' => '{"error":"service_unavailable"}' }.freeze
SEQ_400_P9   = { 'status' => 400, 'headers' => {},
                 'body' => '{"error":"bad_request"}' }.freeze

# ════════════════════════════════════════════════════════════════════════════════
# P9-CONTRACT: ContractResult shape and kind variants
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-CONTRACT: ContractResult shape and kind variants"

p9_check('P9-CONTRACT-01', 'All 6 valid ContractResult kinds validate through ContractResultShape') do
  %w[found created not_found upstream_error capability_denied upstream_unavailable].all? do |kind|
    ContractResultShape.validate({ 'kind' => kind }).valid
  end
end

p9_check('P9-CONTRACT-02', 'Invalid kind fails ContractResultShape validation') do
  r = ContractResultShape.validate({ 'kind' => 'unknown_outcome' })
  r.valid == false && r.errors.any? { |e| e.include?('unknown kind') }
end

p9_check('P9-CONTRACT-03', 'Missing kind field fails ContractResultShape validation') do
  r = ContractResultShape.validate({ 'data' => nil })
  r.valid == false && r.errors.any? { |e| e.include?('kind') }
end

p9_check('P9-CONTRACT-04', 'found ContractResult: data field is non-nil for a successful response') do
  result = UpstreamCallContractP9.call(CAP_P9, REQ_GET_1)
  result['kind'] == 'found' && !result['data'].nil? && result['data'].is_a?(Hash)
end

p9_check('P9-CONTRACT-05', 'upstream_unavailable ContractResult: retry_envelope is non-nil') do
  cr = UpstreamCallContractP9.call_with_sequence(CAP_P9, REQ_GET_1, [SEQ_503_P9], max_attempts: 2)
  cr['kind'] == 'upstream_unavailable' && !cr['retry_envelope'].nil?
end

p9_check('P9-CONTRACT-06', 'capability_denied ContractResult: error_code is an E-HTTP-* denial code') do
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_DENIED)
  cr['kind'] == 'capability_denied' &&
    cr['error_code'] == NetworkErrorCodesP9::BLOCKED_HOST
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-BUILDER: ItemRequestBuilderP9 maps domain inputs to request shapes
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-BUILDER: Request builder maps domain input to HttpRequest shape"

p9_check('P9-BUILDER-01', 'build_get(1) produces GET request; URL ends with /items/1') do
  req = ItemRequestBuilderP9.build_get(1)
  req['method'] == 'GET' && req['url'].end_with?('/items/1')
end

p9_check('P9-BUILDER-02', 'build_get headers are Map[String,String]') do
  req = ItemRequestBuilderP9.build_get(1)
  req['headers'].is_a?(Hash) &&
    req['headers'].keys.all?   { |k| k.is_a?(String) } &&
    req['headers'].values.all? { |v| v.is_a?(String) }
end

p9_check('P9-BUILDER-03', 'build_create produces POST request; URL ends with /items') do
  req = ItemRequestBuilderP9.build_create({ 'name' => 'Widget' })
  req['method'] == 'POST' && req['url'].end_with?('/items')
end

p9_check('P9-BUILDER-04', 'build_create body is JSON-encoded attrs; content-type header set') do
  req  = ItemRequestBuilderP9.build_create({ 'name' => 'Widget' })
  body = JSON.parse(req['body']) rescue nil
  !body.nil? && body['name'] == 'Widget' &&
    req['headers']['content-type'] == 'application/json'
end

p9_check('P9-BUILDER-05', 'build_get with different ids produces distinct URLs') do
  r1 = ItemRequestBuilderP9.build_get(1)
  r2 = ItemRequestBuilderP9.build_get(42)
  r1['url'] != r2['url'] &&
    r1['url'].end_with?('/items/1') &&
    r2['url'].end_with?('/items/42')
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-MAPPER: DomainResponseMapperP9 maps HttpResult -> ContractResult
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-MAPPER: DomainResponseMapper maps HttpResult to ContractResult"

p9_check('P9-MAPPER-01', 'HttpResult ok/200 -> ContractResult kind=found') do
  hr = { 'kind' => 'ok', 'status' => 200, 'headers' => {}, 'body' => '{"id":1}',
         'capability_id' => 'c', 'policy_source' => 's' }
  DomainResponseMapperP9.map(hr)['kind'] == 'found'
end

p9_check('P9-MAPPER-02', 'HttpResult ok/201 -> ContractResult kind=created') do
  hr = { 'kind' => 'ok', 'status' => 201, 'headers' => {}, 'body' => '{"id":2,"created":true}',
         'capability_id' => 'c', 'policy_source' => 's' }
  DomainResponseMapperP9.map(hr)['kind'] == 'created'
end

p9_check('P9-MAPPER-03', 'HttpResult error/404 -> ContractResult kind=not_found') do
  hr = { 'kind' => 'error', 'status' => 404,
         'error_code' => NetworkErrorCodesP9::CLIENT_ERROR,
         'headers' => {}, 'body' => '{"error":"not_found"}',
         'capability_id' => 'c', 'policy_source' => 's' }
  DomainResponseMapperP9.map(hr)['kind'] == 'not_found'
end

p9_check('P9-MAPPER-04', 'HttpResult error/503 -> ContractResult kind=upstream_error') do
  hr = { 'kind' => 'error', 'status' => 503,
         'error_code' => NetworkErrorCodesP9::SERVER_ERROR,
         'error_detail' => 'HTTP 503',
         'headers' => {}, 'body' => '{}',
         'capability_id' => 'c', 'policy_source' => 's' }
  DomainResponseMapperP9.map(hr)['kind'] == 'upstream_error'
end

p9_check('P9-MAPPER-05', 'HttpResult denied -> ContractResult kind=capability_denied') do
  hr = { 'kind' => 'denied', 'status' => nil,
         'error_code' => NetworkErrorCodesP9::BLOCKED_HOST,
         'error_detail' => 'host blocked',
         'headers' => {}, 'body' => '',
         'capability_id' => 'c', 'policy_source' => 's' }
  DomainResponseMapperP9.map(hr)['kind'] == 'capability_denied'
end

p9_check('P9-MAPPER-06', 'found ContractResult: body JSON parsed and available in data field') do
  hr = { 'kind' => 'ok', 'status' => 200, 'headers' => {},
         'body' => '{"id":1,"name":"Widget","price":9.99}',
         'capability_id' => 'c', 'policy_source' => 's' }
  cr = DomainResponseMapperP9.map(hr)
  cr['kind'] == 'found' &&
    cr['data'].is_a?(Hash) &&
    cr['data']['name'] == 'Widget' &&
    cr['data']['id'] == 1
end

p9_check('P9-MAPPER-07', 'capability_denied ContractResult: error_code and error_detail preserved') do
  detail = "host 'evil.example.com' not in allowed_hosts"
  hr = { 'kind' => 'denied', 'status' => nil,
         'error_code' => NetworkErrorCodesP9::BLOCKED_HOST,
         'error_detail' => detail,
         'headers' => {}, 'body' => '',
         'capability_id' => 'cap-api', 'policy_source' => 'lab-policy-v0' }
  cr = DomainResponseMapperP9.map(hr)
  cr['error_code'] == NetworkErrorCodesP9::BLOCKED_HOST &&
    cr['error_detail'] == detail
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-RACK: Rack handler scenario — single call, no retry
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-RACK: Rack handler scenario (single call, no retry)"

p9_check('P9-RACK-01', 'GET /items/1 (Rack single call) -> ContractResult kind=found with item data') do
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_GET_1)
  cr['kind'] == 'found' &&
    cr['data'].is_a?(Hash) &&
    cr['data']['id'] == 1 &&
    cr['data']['name'] == 'Widget'
end

p9_check('P9-RACK-02', 'POST /items (Rack single call) -> ContractResult kind=created') do
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_POST)
  cr['kind'] == 'created' && cr['data'].is_a?(Hash) && cr['data']['created'] == true
end

p9_check('P9-RACK-03', 'GET /items/99 (Rack single call) -> ContractResult kind=not_found') do
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_GET_99)
  cr['kind'] == 'not_found'
end

p9_check('P9-RACK-04', 'GET /items/flaky (Rack, no retry) -> ContractResult kind=upstream_error (no retry in Rack scenario)') do
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_GET_FL)
  cr['kind'] == 'upstream_error' &&
    cr['error_code'] == NetworkErrorCodesP9::SERVER_ERROR
end

p9_check('P9-RACK-05', 'Denied host (Rack) -> ContractResult kind=capability_denied (no transport dispatch)') do
  transport_calls = 0
  decision = HttpCapabilityPolicyP9.check(CAP_P9, REQ_DENIED)
  if decision[:allowed]
    transport_calls += 1
    response = MockHttpTransportDomain.dispatch(REQ_DENIED)
    HttpResultBuilderP9.from_allowed(decision, response)
  else
    HttpResultBuilderP9.from_denied(decision)
  end
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_DENIED)
  transport_calls == 0 &&
    cr['kind'] == 'capability_denied' &&
    cr['error_code'] == NetworkErrorCodesP9::BLOCKED_HOST
end

p9_check('P9-RACK-06', 'Intermediate HttpResult from request_once carries Map[String,String] headers') do
  result = UpstreamCallContractP9.request_once(CAP_P9, REQ_GET_1)
  hdrs = result['headers']
  hdrs.is_a?(Hash) &&
    hdrs.keys.all?   { |k| k.is_a?(String) } &&
    hdrs.values.all? { |v| v.is_a?(String) }
end

p9_check('P9-RACK-07', 'GET /items/1 Rack call is deterministic: 3 identical calls produce identical result') do
  results = 3.times.map { UpstreamCallContractP9.call(CAP_P9, REQ_GET_1) }
  results.all? { |cr| cr['kind'] == 'found' && cr['data']['id'] == 1 } &&
    results.map { |cr| cr['data'] }.uniq.length == 1
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-SIDEKIQ: Sidekiq job scenario — retry with BudgetedLocalLoop analog
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-SIDEKIQ: Sidekiq job scenario (retry with budget)"

p9_check('P9-SIDEKIQ-01', 'GET /items/1 with retry max 3: found on attempt 1') do
  cr = UpstreamCallContractP9.call_with_retry(CAP_P9, REQ_GET_1, max_attempts: 3)
  cr['kind'] == 'found' &&
    cr['retry_envelope']['attempt'] == 1 &&
    !cr['retry_envelope']['exhausted']
end

p9_check('P9-SIDEKIQ-02', 'Sequence [503, 503, 200] max 3: found on attempt 3 (retry succeeds)') do
  seq = [SEQ_503_P9, SEQ_503_P9, SEQ_OK_P9]
  cr  = UpstreamCallContractP9.call_with_sequence(CAP_P9, REQ_GET_1, seq, max_attempts: 3)
  cr['kind'] == 'found' &&
    cr['retry_envelope']['attempt'] == 3 &&
    !cr['retry_envelope']['exhausted']
end

p9_check('P9-SIDEKIQ-03', 'Sequence [503, 503, 503] max 3: upstream_unavailable; budget exhausted') do
  seq = [SEQ_503_P9, SEQ_503_P9, SEQ_503_P9]
  cr  = UpstreamCallContractP9.call_with_sequence(CAP_P9, REQ_GET_1, seq, max_attempts: 3)
  cr['kind'] == 'upstream_unavailable' &&
    cr['retry_envelope']['attempt'] == 3 &&
    cr['retry_envelope']['exhausted'] == true
end

p9_check('P9-SIDEKIQ-04', 'Denied host with retry max 3: capability_denied; only 1 dispatch attempted') do
  dispatch_count = 0
  env = RetrySimulatorP9.simulate(max_attempts: 3) do |_a|
    dispatch_count += 1
    UpstreamCallContractP9.request_once(CAP_P9, REQ_DENIED)
  end
  cr = if env['exhausted']
    { 'kind' => 'upstream_unavailable', 'data' => nil,
      'error_code' => env['last_result']['error_code'],
      'error_detail' => "exhausted after #{env['attempt']}",
      'retry_envelope' => env }
  else
    DomainResponseMapperP9.map(env['last_result'], retry_envelope: env)
  end
  dispatch_count == 1 &&
    cr['kind'] == 'capability_denied'
end

p9_check('P9-SIDEKIQ-05', 'Sequence [400] (non-retryable 4xx): upstream_error; 1 attempt only') do
  seq = [SEQ_400_P9]
  cr  = UpstreamCallContractP9.call_with_sequence(CAP_P9, REQ_GET_1, seq, max_attempts: 3)
  cr['kind'] == 'upstream_error' &&
    cr['retry_envelope']['attempt'] == 1 &&
    !cr['retry_envelope']['exhausted']
end

p9_check('P9-SIDEKIQ-06', 'Sequence [503] with max_attempts=1: upstream_unavailable after exactly 1 attempt') do
  seq = [SEQ_503_P9]
  cr  = UpstreamCallContractP9.call_with_sequence(CAP_P9, REQ_GET_1, seq, max_attempts: 1)
  cr['kind'] == 'upstream_unavailable' &&
    cr['retry_envelope']['attempt'] == 1 &&
    cr['retry_envelope']['exhausted'] == true
end

p9_check('P9-SIDEKIQ-07', 'upstream_unavailable ContractResult: retry_envelope contains last_result with error_code') do
  seq = [SEQ_503_P9]
  cr  = UpstreamCallContractP9.call_with_sequence(CAP_P9, REQ_GET_1, seq, max_attempts: 2)
  cr['kind'] == 'upstream_unavailable' &&
    !cr['retry_envelope'].nil? &&
    cr['retry_envelope']['last_result']['error_code'] == NetworkErrorCodesP9::SERVER_ERROR &&
    cr['retry_envelope']['exhausted'] == true
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-COMPOSE: Composition chain integrity
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-COMPOSE: Composition chain integrity"

p9_check('P9-COMPOSE-01', 'Builder -> call() produces ContractResult (not raw HttpResult)') do
  req = ItemRequestBuilderP9.build_get(1)
  cr  = UpstreamCallContractP9.call(CAP_P9, req)
  ContractResultShape.validate(cr).valid &&
    !cr.key?('capability_id')  # ContractResult does not expose HttpResult internal fields
end

p9_check('P9-COMPOSE-02', 'HttpResult kind maps deterministically to ContractResult kind') do
  mapping = {
    ['ok',     200] => 'found',
    ['ok',     201] => 'created',
    ['error',  404] => 'not_found',
    ['error',  503] => 'upstream_error',
    ['denied', nil] => 'capability_denied'
  }
  mapping.all? do |(kind, status), expected_cr_kind|
    hr = { 'kind' => kind, 'status' => status,
           'error_code' => nil, 'error_detail' => nil,
           'headers' => {}, 'body' => '{}',
           'capability_id' => 'c', 'policy_source' => 's' }
    DomainResponseMapperP9.map(hr)['kind'] == expected_cr_kind
  end
end

p9_check('P9-COMPOSE-03', 'Built request headers are Map[String,String] at every builder method') do
  reqs = [
    ItemRequestBuilderP9.build_get(1),
    ItemRequestBuilderP9.build_create({ 'name' => 'Test' }),
    ItemRequestBuilderP9.build_path('/items/flaky')
  ]
  reqs.all? do |req|
    req['headers'].is_a?(Hash) &&
      req['headers'].keys.all?   { |k| k.is_a?(String) } &&
      req['headers'].values.all? { |v| v.is_a?(String) }
  end
end

p9_check('P9-COMPOSE-04', 'Denied branch: transport is not reached; ContractResult is capability_denied') do
  transport_calls = 0
  decision = HttpCapabilityPolicyP9.check(CAP_P9, REQ_DENIED)
  if decision[:allowed]
    transport_calls += 1
    response = MockHttpTransportDomain.dispatch(REQ_DENIED)
    HttpResultBuilderP9.from_allowed(decision, response)
  else
    HttpResultBuilderP9.from_denied(decision)
  end
  # The real call:
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_DENIED)
  transport_calls == 0 && cr['kind'] == 'capability_denied' && cr['data'].nil?
end

p9_check('P9-COMPOSE-05', 'Full pipeline produces identical results for identical inputs (deterministic)') do
  3.times.map { UpstreamCallContractP9.call(CAP_P9, REQ_GET_1) }.then do |results|
    results.all? { |cr| cr['kind'] == 'found' } &&
      results.map { |cr| cr['data'] }.uniq.length == 1
  end
end

p9_check('P9-COMPOSE-06', 'UpstreamCallContractP9 is proof-local; no canon or finalized API claim') do
  SOURCE_P9.include?('lab-only') &&
    SOURCE_P9.include?('no canon claim') &&
    SOURCE_P9.include?('no finalized API surface')
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-REDACT: Redaction in composition pipeline
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-REDACT: Redaction in composition pipeline"

p9_check('P9-REDACT-01', 'Authorization header redacted before dispatch; ContractResult data unaffected') do
  headers_with_auth = { 'authorization' => 'Bearer secret', 'content-type' => 'application/json' }
  redacted = TelemetryRedactorP9.redact_request_headers(headers_with_auth)
  req_redacted = REQ_GET_1.merge('headers' => redacted)
  cr = UpstreamCallContractP9.call(CAP_P9, req_redacted)
  redacted['authorization'] == '[REDACTED]' &&
    cr['kind'] == 'found' &&
    cr['data']['name'] == 'Widget'
end

p9_check('P9-REDACT-02', 'Redacted request headers remain Map[String,String]') do
  headers_in = { 'authorization' => 'Bearer tok', 'x-api-key' => 'key',
                 'accept' => 'application/json' }
  redacted = TelemetryRedactorP9.redact_request_headers(headers_in)
  redacted.is_a?(Hash) &&
    redacted.keys.all?   { |k| k.is_a?(String) } &&
    redacted.values.all? { |v| v.is_a?(String) }
end

p9_check('P9-REDACT-03', 'Response body captured and bounded at 256 chars') do
  long_body   = 'x' * 400
  captured    = TelemetryRedactorP9.capture_body(long_body)
  captured.length <= 256 + TelemetryRedactorP9::TRUNCATION_MARKER.length &&
    captured.include?(TelemetryRedactorP9::TRUNCATION_MARKER)
end

p9_check('P9-REDACT-04', 'No absolute file paths in ContractResult JSON') do
  cr       = UpstreamCallContractP9.call(CAP_P9, REQ_GET_1)
  json_str = JSON.generate(cr)
  !json_str.include?('/Users/') && !json_str.include?('/home/') &&
    !json_str.include?('file://')
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-CLOSED: Closed-surface scan
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-CLOSED: Closed-surface scan"

p9_check('P9-CLOSED-01', 'No real socket primitives') do
  !SOURCE_P9.include?('TCP' + 'Socket') && !SOURCE_P9.include?('UDP' + 'Socket')
end

p9_check('P9-CLOSED-02', 'No http-lib or require-net usage') do
  !SOURCE_P9.include?('Net' + '::' + 'HTTP') &&
    !SOURCE_P9.include?("require 'net/" + "http'") &&
    !SOURCE_P9.include?("require 'open-" + "uri'")
end

p9_check('P9-CLOSED-03', 'No require-socket usage') do
  !SOURCE_P9.include?("require 'sock" + "et'")
end

p9_check('P9-CLOSED-04', 'No Rack-compat or accept-loop claim') do
  !SOURCE_P9.include?('Rack-comp' + 'atible') &&
    !SOURCE_P9.include?('server runt' + 'ime') &&
    !SOURCE_P9.include?('HTTP serv' + 'er')
end

p9_check('P9-CLOSED-05', 'No finalized-API or canon claim') do
  !SOURCE_P9.include?('prod' + 'uction runtime') &&
    !SOURCE_P9.include?('canon' + ' API') &&
    !SOURCE_P9.include?('stab' + 'le API')
end

# ════════════════════════════════════════════════════════════════════════════════
# P9-GAP: Explicit answers to all card questions
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P9-GAP: Explicit answers to card questions"

p9_check('P9-GAP-01', 'Composition model: builder -> boundary -> HttpResult -> mapper -> ContractResult') do
  # Prove each stage exists and outputs the right type
  req     = ItemRequestBuilderP9.build_get(1)          # stage 1: domain input -> HttpRequest shape
  http_r  = UpstreamCallContractP9.request_once(CAP_P9, req)  # stage 2: boundary -> HttpResult
  cr      = DomainResponseMapperP9.map(http_r)                # stage 3: mapper -> ContractResult
  req.is_a?(Hash) && req.key?('method') &&                     # stage 1 output
    http_r.is_a?(Hash) && http_r.key?('kind') &&               # stage 2 output (HttpResult shape)
    ContractResultShape.validate(cr).valid                      # stage 3 output (ContractResult shape)
end

p9_check('P9-GAP-02', 'Rack vs Sidekiq: Rack returns upstream_error immediately; Sidekiq can reach upstream_unavailable') do
  # Rack: single call on /items/flaky -> upstream_error (no retry)
  rack_cr  = UpstreamCallContractP9.call(CAP_P9, REQ_GET_FL)
  # Sidekiq: sequence exhausted -> upstream_unavailable
  sidekiq_cr = UpstreamCallContractP9.call_with_sequence(
    CAP_P9, REQ_GET_1, [SEQ_503_P9], max_attempts: 1)
  rack_cr['kind'] == 'upstream_error' && sidekiq_cr['kind'] == 'upstream_unavailable'
end

p9_check('P9-GAP-03', 'Capability denial flows as typed branch: no transport; capability_denied ContractResult') do
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_DENIED)
  cr['kind'] == 'capability_denied' &&
    cr['error_code'] == NetworkErrorCodesP9::BLOCKED_HOST &&
    cr['data'].nil?
end

p9_check('P9-GAP-04', 'Rack scenario correctly omits retry: upstream_error for 503; not upstream_unavailable') do
  # Rack handler can return upstream_error but not upstream_unavailable —
  # upstream_unavailable requires retry budget exhaustion which Rack does not attempt.
  cr = UpstreamCallContractP9.call(CAP_P9, REQ_GET_FL)
  cr['kind'] == 'upstream_error' && cr['kind'] != 'upstream_unavailable'
end

p9_check('P9-GAP-05', 'upstream_unavailable is correct kind for exhausted retry budget') do
  # All 5xx patterns that exhaust budget produce upstream_unavailable, not upstream_error
  [1, 2, 3].all? do |max|
    cr = UpstreamCallContractP9.call_with_sequence(
      CAP_P9, REQ_GET_1, [SEQ_503_P9], max_attempts: max)
    cr['kind'] == 'upstream_unavailable' && cr['retry_envelope']['exhausted'] == true
  end
end

p9_check('P9-GAP-06', 'call_contract analog is proof-local; no canon or finalized API claim') do
  SOURCE_P9.include?('lab-only') &&
    SOURCE_P9.include?('no finalized API surface') &&
    !SOURCE_P9.include?('canon' + ' API')
end

p9_check('P9-GAP-07', 'No real I/O, name-resolution, accept-loop startup, or blocking-wait at any stage') do
  !SOURCE_P9.include?('Time' + '.now') &&
    !SOURCE_P9.include?('sle' + 'ep') &&
    !SOURCE_P9.include?('Service' + 'Loop') &&
    !SOURCE_P9.include?('Thre' + 'ad') &&
    !SOURCE_P9.include?('DN' + 'S') &&
    !SOURCE_P9.include?('TCP' + 'Socket')
end

p9_check('P9-GAP-08', 'Map[String,String] headers preserved at every stage of composition') do
  # Stage 1: built request headers
  built_hdrs = ItemRequestBuilderP9.build_get(1)['headers']
  # Stage 2: intermediate HttpResult headers
  http_result = UpstreamCallContractP9.request_once(CAP_P9, REQ_GET_1)
  result_hdrs = http_result['headers']
  # Both must be Map[String,String]
  [built_hdrs, result_hdrs].all? do |h|
    h.is_a?(Hash) && h.keys.all? { |k| k.is_a?(String) } && h.values.all? { |v| v.is_a?(String) }
  end
end

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════

passes = $p9_results.count { |r| r[:status] == 'PASS' }
fails  = $p9_results.count { |r| r[:status] == 'FAIL' }
total  = $p9_results.size

puts "\n" + '=' * 60
puts "LAB-STDLIB-NET-P9 (HTTP Upstream Call Contract Composition)"
puts "RESULT: #{passes}/#{total} PASS  |  #{fails} FAIL"
puts '=' * 60

exit(fails == 0 ? 0 : 1)
