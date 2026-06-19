# frozen_string_literal: true
# Proof: HTTP Boundary — Record/Map Alignment
# Card: LAB-STDLIB-NET-P7 (Category: lang)
# Track: lab-network-http-boundary-record-map-alignment-v0
#
# Depends on:
#   LAB-STDLIB-NET-P6  (HTTP-client boundary proof)
#   LAB-RECORD-VM-P3   (nested record field values)
#   LAB-RECORD-MAP-P1  (Record/Map[String,String] bridge)
#   PROP-043-P5        (Map production implementation — not yet landed;
#                       this proof uses the same proof-local approach as
#                       PROP-043-P2 / LAB-RECORD-MAP-P1)
#
# Authority: lab-only. No real network I/O, sockets, DNS, TLS, or
# service-listener startup. No canon claim. No Rack compatibility claim.
# No public or finalized API authority created.
# Map[String,String] headers are proved via proof-local type inference
# modules (MapTypeInferenceV0), mirroring MapPipeline from PROP-043-P2.
#
# Sections:
#   P7-SHAPE     (6)  — HttpRequest/Response shape with Map[String,String] headers
#   P7-TYPEINFER (8)  — map_get/or_else/has_key type rules; OOF-MAP1/2/3
#   P7-REDACT    (8)  — redaction through Map-shaped headers
#   P7-POLICY    (8)  — capability policy unchanged by Map headers
#   P7-TRANSPORT (6)  — mocked transport with Map headers
#   P7-RECEIPT   (6)  — telemetry receipt format
#   P7-CLOSED    (5)  — closed-surface scan
#   P7-GAP       (8)  — explicit answers to all card questions
#
# Total: 55 checks

require 'json'
require 'uri'
require 'set'
require 'pathname'

FIXTURE_DIR_P7 = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_http_client'

# ────────────────────────────────────────────────────────────────────────────────
# Result tracking
# ────────────────────────────────────────────────────────────────────────────────

$p7_results = []

def p7_check(group, label)
  result = yield
  status = result ? 'PASS' : 'FAIL'
  $p7_results << { status: status, group: group, label: label }
  puts "  [#{status}] #{group}: #{label}"
rescue => e
  $p7_results << { status: 'FAIL', group: group, label: label, error: e.message }
  puts "  [FAIL] #{group}: #{label} (exception: #{e.message.split("\n").first})"
end

# ────────────────────────────────────────────────────────────────────────────────
# MapHeadersV0
# Proof-local runtime representation of Map[String,String] semantics.
# Wraps a Ruby Hash with strong key/value String constraints.
# Provides map_get (→ Option[String]) and or_else (→ String).
# ────────────────────────────────────────────────────────────────────────────────

module MapHeadersV0
  # Validation result for the shape check
  ValidateResult = Struct.new(:valid, :errors, keyword_init: true)

  # Validate that a Hash satisfies Map[String,String] — all keys and values are Strings.
  # Returns ValidateResult.
  def self.validate_type(hash)
    errors = []
    return ValidateResult.new(valid: false, errors: ['headers must be a Hash']) unless hash.is_a?(Hash)
    hash.each do |k, v|
      errors << "OOF-MAP1: header key #{k.inspect} must be String (got #{k.class})" unless k.is_a?(String)
      unless v.is_a?(String)
        errors << "header value for key #{k.inspect} must be String (got #{v.class})"
      end
    end
    ValidateResult.new(valid: errors.empty?, errors: errors)
  end

  # map_get(map, key) → Option[String]
  # Returns { some: value } if key is present, { none: true } otherwise.
  # Mirrors stdlib.map.get semantics: lookup never raises; missing key → None.
  def self.get(map, key)
    return { none: true } unless map.is_a?(Hash) && map.key?(key)
    { some: map[key] }
  end

  # or_else(option, default) → String
  # Unwraps an Option[String]; returns default if none.
  def self.or_else(option, default_val)
    return default_val unless option.is_a?(Hash)
    option.key?(:some) ? option[:some] : default_val
  end

  # has_key?(map, key) → Bool
  def self.has_key?(map, key)
    map.is_a?(Hash) && map.key?(key)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# MapTypeInferenceV0
# Proof-local type inference rules for Map[K,V] operations.
# Mirrors MapPipeline (PROP-043-P2) type inference rules.
# Does NOT modify production compiler files.
# ────────────────────────────────────────────────────────────────────────────────

module MapTypeInferenceV0
  # ── Type IR builders ──────────────────────────────────────────────────────────

  def self.map_type_ir(key_name, value_name)
    { 'name' => 'Map',
      'params' => [
        { 'name' => key_name.to_s, 'params' => [] },
        { 'name' => value_name.to_s, 'params' => [] }
      ] }
  end

  def self.option_type_ir(inner_ir)
    inner = inner_ir.is_a?(Hash) ? inner_ir : { 'name' => inner_ir.to_s, 'params' => [] }
    { 'name' => 'Option', 'params' => [inner] }
  end

  def self.type_name(type_ir)
    type_ir.is_a?(Hash) ? type_ir.fetch('name', 'Unknown') : type_ir.to_s
  end

  def self.type_param(type_ir, index)
    return { 'name' => 'Unknown', 'params' => [] } unless type_ir.is_a?(Hash)
    (type_ir['params'] || [])[index] || { 'name' => 'Unknown', 'params' => [] }
  end

  # ── Inference rules ───────────────────────────────────────────────────────────

  # Rule MAP-GET: map_get(Map[String,V], String) → Option[V]
  # If the map type is Unknown, returns Option[Unknown] (Unknown-compat propagation).
  def self.infer_map_get(map_type_ir)
    if type_name(map_type_ir) == 'Map'
      value_type = type_param(map_type_ir, 1)
      option_type_ir(value_type)
    else
      # Unknown map type → Option[Unknown]
      option_type_ir({ 'name' => 'Unknown', 'params' => [] })
    end
  end

  # Rule: or_else(Option[V], V) → V
  # If first arg is not Option, returns Unknown.
  def self.infer_or_else(option_type_ir)
    if type_name(option_type_ir) == 'Option'
      type_param(option_type_ir, 0)
    else
      { 'name' => 'Unknown', 'params' => [] }
    end
  end

  # Rule: map_has_key(Map[String,V], String) → Bool
  def self.infer_map_has_key(_map_type_ir)
    { 'name' => 'Bool', 'params' => [] }
  end

  # Rule: map_empty() → Map[String,Unknown]
  # Context-driven type inference deferred to v1.
  def self.infer_map_empty
    map_type_ir('String', 'Unknown')
  end

  # ── Annotation checks (OOF candidates) ───────────────────────────────────────

  # Check a user-declared Map type annotation for OOF-MAP1/2/3.
  # OOF-MAP1: key ≠ String in v0
  # OOF-MAP2: value = Any (permanently closed)
  # OOF-MAP3: value = Unknown in output annotation (must not appear in user annotations)
  def self.check_annotation(type_ir, context: :input)
    errors = []
    return errors unless type_name(type_ir) == 'Map'
    key_name = type_name(type_param(type_ir, 0))
    val_name = type_name(type_param(type_ir, 1))

    if key_name != 'String' && key_name != 'Unknown'
      errors << { code: 'OOF-MAP1',
                  message: "Map key type must be String in v0; got '#{key_name}'" }
    end
    if val_name == 'Any'
      errors << { code: 'OOF-MAP2',
                  message: "Map value type 'Any' is permanently closed" }
    end
    if context == :output && val_name == 'Unknown'
      errors << { code: 'OOF-MAP3',
                  message: "Map value type 'Unknown' must not appear in user output annotations" }
    end
    errors
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpRequestMapShape
# Validates HttpRequest with Map[String,String] headers constraint.
# Replaces the proof-local Hash check from P6 with MapHeadersV0 validation.
# ────────────────────────────────────────────────────────────────────────────────

module HttpRequestMapShape
  VALID_METHODS = Set.new(%w[GET POST PUT DELETE PATCH HEAD OPTIONS]).freeze
  URL_REGEX     = /\Ahttps?:\/\/[^\/\s]+/i.freeze

  Result = Struct.new(:valid, :errors, keyword_init: true)

  def self.validate(req)
    errors = []
    return Result.new(valid: false, errors: ['request must be a record (Hash)']) unless req.is_a?(Hash)

    %w[method url headers body timeout_ms].each do |f|
      errors << "missing required field: #{f}" unless req.key?(f)
    end
    return Result.new(valid: false, errors: errors) unless errors.empty?

    errors << 'method must be a String'    unless req['method'].is_a?(String)
    errors << 'url must be a String'       unless req['url'].is_a?(String)
    errors << 'body must be a String'      unless req['body'].is_a?(String)
    errors << 'timeout_ms must be Integer' unless req['timeout_ms'].is_a?(Integer)

    # Headers: Map[String,String] constraint via MapHeadersV0
    map_result = MapHeadersV0.validate_type(req['headers'])
    errors.concat(map_result.errors) unless map_result.valid

    if req['method'].is_a?(String) && !VALID_METHODS.include?(req['method'].upcase)
      errors << "method '#{req['method']}' is not a recognised HTTP method"
    end
    if req['url'].is_a?(String) && req['url'] !~ URL_REGEX
      errors << "url '#{req['url']}' does not match https?://host... pattern"
    end

    Result.new(valid: errors.empty?, errors: errors)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HttpResponseMapShape
# Validates HttpResponse with Map[String,String] headers constraint.
# ────────────────────────────────────────────────────────────────────────────────

module HttpResponseMapShape
  Result = Struct.new(:valid, :errors, keyword_init: true)

  def self.validate(resp)
    errors = []
    return Result.new(valid: false, errors: ['response must be a record (Hash)']) unless resp.is_a?(Hash)

    %w[status headers body].each do |f|
      errors << "missing required field: #{f}" unless resp.key?(f)
    end
    return Result.new(valid: false, errors: errors) unless errors.empty?

    errors << 'status must be Integer' unless resp['status'].is_a?(Integer)
    errors << 'body must be a String'  unless resp['body'].is_a?(String)

    map_result = MapHeadersV0.validate_type(resp['headers'])
    errors.concat(map_result.errors) unless map_result.valid

    if resp['status'].is_a?(Integer) && (resp['status'] < 100 || resp['status'] > 599)
      errors << "status #{resp['status']} is out of valid HTTP range 100-599"
    end

    Result.new(valid: errors.empty?, errors: errors)
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Network error codes (same as P6 — unchanged)
# ────────────────────────────────────────────────────────────────────────────────

module NetworkErrorCodesP7
  BLOCKED_HOST     = 'E-HTTP-BLOCKED-HOST'
  BLOCKED_METHOD   = 'E-HTTP-BLOCKED-METHOD'
  INSECURE_SCHEME  = 'E-HTTP-INSECURE-SCHEME'
  MALFORMED_URL    = 'E-HTTP-MALFORMED-URL'
  TIMEOUT_BUDGET   = 'E-HTTP-TIMEOUT-BUDGET'
  PORT_DENIED      = 'E-HTTP-PORT-DENIED'
end

# ────────────────────────────────────────────────────────────────────────────────
# Capability policy engine (same logic as P6 — Map headers do not affect policy)
# ────────────────────────────────────────────────────────────────────────────────

module HttpCapabilityPolicyP7
  def self.check(cap, req)
    cap_id          = cap['capability_id']
    policy_src      = cap.dig('http_policy', 'policy_source') || 'unknown'
    allowed_hosts   = cap['allowed_hosts'] || []
    allowed_ports   = cap['allowed_port_ranges'] || []
    tls_required    = cap.fetch('tls_required', false)
    allowed_methods = Array(cap.dig('http_policy', 'allowed_methods'))
    budget_ms       = cap.dig('http_policy', 'timeout_budget_ms') || Float::INFINITY

    url_str = req['url'].to_s

    begin
      uri = URI.parse(url_str)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return deny(NetworkErrorCodesP7::MALFORMED_URL, cap_id, policy_src,
                    "URL '#{url_str}' is not a valid http/https URI")
      end
    rescue URI::InvalidURIError
      return deny(NetworkErrorCodesP7::MALFORMED_URL, cap_id, policy_src,
                  "URL '#{url_str}' could not be parsed")
    end

    uri = URI.parse(url_str)

    if tls_required && uri.scheme != 'https'
      return deny(NetworkErrorCodesP7::INSECURE_SCHEME, cap_id, policy_src,
                  "capability requires TLS; scheme '#{uri.scheme}' is insecure")
    end

    host = uri.host.to_s
    unless host_allowed?(host, allowed_hosts)
      return deny(NetworkErrorCodesP7::BLOCKED_HOST, cap_id, policy_src,
                  "host '#{host}' not in allowed_hosts #{allowed_hosts.inspect}")
    end

    effective_port = uri.port || (uri.scheme == 'https' ? 443 : 80)
    unless port_allowed?(effective_port, allowed_ports)
      return deny(NetworkErrorCodesP7::PORT_DENIED, cap_id, policy_src,
                  "port #{effective_port} not in allowed_port_ranges")
    end

    method = req['method'].to_s.upcase
    if !allowed_methods.empty? && !allowed_methods.include?(method)
      return deny(NetworkErrorCodesP7::BLOCKED_METHOD, cap_id, policy_src,
                  "method '#{method}' not in allowed_methods #{allowed_methods.inspect}")
    end

    timeout_ms = req['timeout_ms'].to_i
    if timeout_ms > budget_ms
      return deny(NetworkErrorCodesP7::TIMEOUT_BUDGET, cap_id, policy_src,
                  "timeout_ms #{timeout_ms} exceeds budget #{budget_ms}")
    end

    { allowed: true, reason_code: nil, capability_id: cap_id, policy_source: policy_src }
  end

  def self.deny(code, cap_id, policy_src, detail = nil)
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
# Mock HTTP transport (same as P6 — no real I/O; deterministic table lookup)
# ────────────────────────────────────────────────────────────────────────────────

module MockHttpTransportP7
  TRANSPORT_TABLE = JSON.parse(
    File.read(FIXTURE_DIR_P7 / 'mock_transport_table.json')
  ).freeze

  def self.transport_id
    TRANSPORT_TABLE['transport_id']
  end

  def self.dispatch(req)
    uri    = URI.parse(req['url'])
    host   = uri.host.to_s
    path   = uri.path.to_s.then { |p| p.empty? ? '/' : p }
    method = req['method'].to_s.upcase

    route = TRANSPORT_TABLE['routes'].find do |r|
      r['method'] == method && r['host'] == host && r['path'] == path
    end

    raw = route ? route['response'] : TRANSPORT_TABLE['fallback_response']

    # Return Map[String,String]-shaped headers (all values are Strings in fixture)
    { 'status'  => raw['status'],
      'headers' => raw['headers'].dup,
      'body'    => raw['body'].to_s }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Telemetry redactor — Map-aware version
# Same sensitive header lists as P6. MapHeadersV0.validate_type confirms that
# redacted headers remain Map[String,String] (String value '[REDACTED]' is still String).
# ────────────────────────────────────────────────────────────────────────────────

module TelemetryRedactorP7
  REDACT_MARKER      = '[REDACTED]'.freeze
  BODY_CAPTURE_LIMIT = 256
  TRUNCATION_MARKER  = '...[TRUNCATED]'.freeze

  SENSITIVE_REQUEST_HEADERS = Set.new(%w[
    authorization cookie x-api-key x-auth-token bearer
    x-secret-key api-key access-token
  ]).freeze

  SENSITIVE_RESPONSE_HEADERS = Set.new(%w[
    set-cookie authorization x-auth-token
  ]).freeze

  def self.redact_request_headers(headers)
    return {} unless headers.is_a?(Hash)
    headers.each_with_object({}) do |(k, v), acc|
      acc[k] = SENSITIVE_REQUEST_HEADERS.include?(k.downcase) ? REDACT_MARKER : v
    end
  end

  def self.redact_response_headers(headers)
    return {} unless headers.is_a?(Hash)
    headers.each_with_object({}) do |(k, v), acc|
      acc[k] = SENSITIVE_RESPONSE_HEADERS.include?(k.downcase) ? REDACT_MARKER : v
    end
  end

  def self.capture_body(body)
    return '' if body.nil? || body.empty?
    s = body.to_s
    s.length > BODY_CAPTURE_LIMIT ? s[0, BODY_CAPTURE_LIMIT] + TRUNCATION_MARKER : s
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Telemetry receipt builder (same structure as P6)
# ────────────────────────────────────────────────────────────────────────────────

module TelemetryReceiptP7
  def self.build_denied(req, decision)
    uri = parse_uri(req['url'].to_s)
    { 'receipt_kind'        => 'http_request_attempt',
      'capability_id'       => decision[:capability_id],
      'capability_decision' => 'denied',
      'denial_reason'       => { 'code' => decision[:reason_code],
                                 'detail' => decision[:detail],
                                 'policy_source' => decision[:policy_source] },
      'request_method'      => req['method'],
      'request_host'        => uri&.host,
      'request_path'        => uri&.path,
      'request_headers_redacted' => TelemetryRedactorP7.redact_request_headers(req['headers'] || {}),
      'mocked_transport_id' => nil,
      'response_status'     => nil,
      'response_body_capture' => nil }
  end

  def self.build_allowed(req, decision, response)
    uri = parse_uri(req['url'].to_s)
    { 'receipt_kind'        => 'http_request_attempt',
      'capability_id'       => decision[:capability_id],
      'capability_decision' => 'allowed',
      'denial_reason'       => nil,
      'request_method'      => req['method'],
      'request_host'        => uri&.host,
      'request_path'        => uri&.path,
      'request_headers_redacted' => TelemetryRedactorP7.redact_request_headers(req['headers'] || {}),
      'mocked_transport_id' => MockHttpTransportP7.transport_id,
      'response_status'     => response['status'],
      'response_headers_redacted' => TelemetryRedactorP7.redact_response_headers(response['headers'] || {}),
      'response_body_capture' => TelemetryRedactorP7.capture_body(response['body']) }
  end

  def self.parse_uri(url)
    URI.parse(url)
  rescue URI::InvalidURIError
    nil
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# HTTP client (same flow as P6)
# ────────────────────────────────────────────────────────────────────────────────

module HttpClientP7
  def self.request(cap, req)
    decision = HttpCapabilityPolicyP7.check(cap, req)
    if decision[:allowed]
      response = MockHttpTransportP7.dispatch(req)
      receipt  = TelemetryReceiptP7.build_allowed(req, decision, response)
      { ok: true, response: response, receipt: receipt }
    else
      receipt = TelemetryReceiptP7.build_denied(req, decision)
      { ok: false, decision: decision, receipt: receipt }
    end
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Load fixtures
# ────────────────────────────────────────────────────────────────────────────────

CAP_P7      = JSON.parse(File.read(FIXTURE_DIR_P7 / 'http_client_capability.json'))
CAP_P7_WILD = JSON.parse(File.read(FIXTURE_DIR_P7 / 'http_wildcard_capability.json'))

# Reference request helpers — headers now Map[String,String] typed
def p7_get(path = '/health', host = 'api.example.com', timeout_ms = 1000, headers: nil)
  { 'method'     => 'GET',
    'url'        => "https://#{host}#{path}",
    'headers'    => headers || { 'content-type' => 'application/json', 'accept' => 'application/json' },
    'body'       => '',
    'timeout_ms' => timeout_ms }
end

def p7_post(path = '/data', host = 'api.example.com', timeout_ms = 2000, headers: nil)
  { 'method'     => 'POST',
    'url'        => "https://#{host}#{path}",
    'headers'    => headers || { 'content-type' => 'application/json' },
    'body'       => '{"key":"value"}',
    'timeout_ms' => timeout_ms }
end

SOURCE_P7 = File.read(__FILE__, encoding: 'UTF-8')

# ════════════════════════════════════════════════════════════════════════════════
# P7-SHAPE: HttpRequest/Response shape with Map[String,String] headers
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-SHAPE: Record shapes with Map[String,String] headers"

p7_check('P7-SHAPE-01', 'Valid HttpRequest with Map[String,String] headers validates') do
  req = JSON.parse(File.read(FIXTURE_DIR_P7 / 'http_request_map_headers.json', encoding: 'UTF-8'))
  r = HttpRequestMapShape.validate(req)
  r.valid == true && r.errors.empty?
end

p7_check('P7-SHAPE-02', 'HttpRequest with non-String header key fails (OOF-MAP1 path)') do
  req = p7_get.merge('headers' => { 123 => 'application/json' })
  r = HttpRequestMapShape.validate(req)
  r.valid == false && r.errors.any? { |e| e.include?('OOF-MAP1') }
end

p7_check('P7-SHAPE-03', 'HttpRequest with non-String header value fails') do
  req = p7_get.merge('headers' => { 'content-type' => 42 })
  r = HttpRequestMapShape.validate(req)
  r.valid == false && r.errors.any? { |e| e.include?('String') }
end

p7_check('P7-SHAPE-04', 'Valid HttpResponse with Map[String,String] headers validates') do
  resp = JSON.parse(File.read(FIXTURE_DIR_P7 / 'http_response_map_headers.json', encoding: 'UTF-8'))
  r = HttpResponseMapShape.validate(resp)
  r.valid == true && r.errors.empty?
end

p7_check('P7-SHAPE-05', 'HttpResponse missing headers field fails') do
  resp = { 'status' => 200, 'body' => 'OK' }
  r = HttpResponseMapShape.validate(resp)
  r.valid == false && r.errors.any? { |e| e.include?('headers') }
end

p7_check('P7-SHAPE-06', 'HttpResponse with Integer header value fails Map[String,String]') do
  resp = { 'status' => 200, 'headers' => { 'content-length' => 42 }, 'body' => 'OK' }
  r = HttpResponseMapShape.validate(resp)
  r.valid == false
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-TYPEINFER: Map type inference rules
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-TYPEINFER: Map[String,String] type inference"

p7_check('P7-TYPEINFER-01', 'map_get(Map[String,String], String) → Option[String]') do
  map_t  = MapTypeInferenceV0.map_type_ir('String', 'String')
  result = MapTypeInferenceV0.infer_map_get(map_t)
  MapTypeInferenceV0.type_name(result) == 'Option' &&
    MapTypeInferenceV0.type_name(MapTypeInferenceV0.type_param(result, 0)) == 'String'
end

p7_check('P7-TYPEINFER-02', 'or_else(Option[String], String) → String') do
  opt_t  = MapTypeInferenceV0.option_type_ir({ 'name' => 'String', 'params' => [] })
  result = MapTypeInferenceV0.infer_or_else(opt_t)
  MapTypeInferenceV0.type_name(result) == 'String'
end

p7_check('P7-TYPEINFER-03', 'map_has_key(Map[String,String], String) → Bool') do
  map_t  = MapTypeInferenceV0.map_type_ir('String', 'String')
  result = MapTypeInferenceV0.infer_map_has_key(map_t)
  MapTypeInferenceV0.type_name(result) == 'Bool'
end

p7_check('P7-TYPEINFER-04', 'map_get(Unknown map type) → Option[Unknown] (Unknown-compat)') do
  unknown_t = { 'name' => 'Unknown', 'params' => [] }
  result = MapTypeInferenceV0.infer_map_get(unknown_t)
  MapTypeInferenceV0.type_name(result) == 'Option' &&
    MapTypeInferenceV0.type_name(MapTypeInferenceV0.type_param(result, 0)) == 'Unknown'
end

p7_check('P7-TYPEINFER-05', 'Map[Integer,String] key annotation → OOF-MAP1 candidate') do
  bad_ann = MapTypeInferenceV0.map_type_ir('Integer', 'String')
  errors  = MapTypeInferenceV0.check_annotation(bad_ann, context: :input)
  errors.any? { |e| e[:code] == 'OOF-MAP1' }
end

p7_check('P7-TYPEINFER-06', 'Map[String,Any] value annotation → OOF-MAP2 (permanently closed)') do
  bad_ann = MapTypeInferenceV0.map_type_ir('String', 'Any')
  errors  = MapTypeInferenceV0.check_annotation(bad_ann, context: :input)
  errors.any? { |e| e[:code] == 'OOF-MAP2' }
end

p7_check('P7-TYPEINFER-07', 'Map[String,Unknown] in output annotation → OOF-MAP3 candidate') do
  ann    = MapTypeInferenceV0.map_type_ir('String', 'Unknown')
  errors = MapTypeInferenceV0.check_annotation(ann, context: :output)
  errors.any? { |e| e[:code] == 'OOF-MAP3' }
end

p7_check('P7-TYPEINFER-08', 'map_empty() returns Map[String,Unknown] (expression result; not an output annotation)') do
  result   = MapTypeInferenceV0.infer_map_empty
  # map_empty() return type IS Map[String,Unknown]
  is_map   = MapTypeInferenceV0.type_name(result) == 'Map'
  val_name = MapTypeInferenceV0.type_name(MapTypeInferenceV0.type_param(result, 1))
  is_unknown_val = val_name == 'Unknown'
  # OOF-MAP3 does NOT fire for expression results — only for user-declared output annotations
  oof3_on_expr = MapTypeInferenceV0.check_annotation(result, context: :input)
  is_map && is_unknown_val && oof3_on_expr.none? { |e| e[:code] == 'OOF-MAP3' }
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-REDACT: Redaction through Map-shaped headers
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-REDACT: Redaction through Map[String,String] headers"

p7_check('P7-REDACT-01', 'Authorization in Map headers → [REDACTED]; Map[String,String] shape preserved') do
  headers  = { 'authorization' => 'Bearer secret-xyz', 'content-type' => 'application/json' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  # Value replaced with String '[REDACTED]' — Map[String,String] still holds
  type_ok = MapHeadersV0.validate_type(redacted).valid
  redacted['authorization'] == '[REDACTED]' && type_ok
end

p7_check('P7-REDACT-02', 'Cookie in Map headers → [REDACTED]') do
  headers  = { 'cookie' => 'session=abc123' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  redacted['cookie'] == '[REDACTED]'
end

p7_check('P7-REDACT-03', 'X-Api-Key in Map headers → [REDACTED]') do
  headers  = { 'x-api-key' => 'secret-key-12345' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  redacted['x-api-key'] == '[REDACTED]'
end

p7_check('P7-REDACT-04', 'set-cookie in response Map headers → [REDACTED]') do
  headers  = { 'set-cookie' => 'sess=sec; HttpOnly', 'content-type' => 'application/json' }
  redacted = TelemetryRedactorP7.redact_response_headers(headers)
  redacted['set-cookie'] == '[REDACTED]' && redacted['content-type'] == 'application/json'
end

p7_check('P7-REDACT-05', 'Non-sensitive headers preserved unchanged in Map form') do
  headers  = { 'content-type' => 'application/json', 'x-request-id' => 'req-42' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  redacted['content-type'] == 'application/json' && redacted['x-request-id'] == 'req-42'
end

p7_check('P7-REDACT-06', 'map_get on redacted headers still works for non-sensitive key') do
  headers  = { 'authorization' => 'Bearer s', 'content-type' => 'application/json' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  # map_get on redacted Map: content-type still accessible
  opt = MapHeadersV0.get(redacted, 'content-type')
  opt[:some] == 'application/json'
end

p7_check('P7-REDACT-07', 'Body bounded at 256 chars; truncation marker appended') do
  long_body = 'x' * 512
  captured  = TelemetryRedactorP7.capture_body(long_body)
  captured.length <= 256 + TelemetryRedactorP7::TRUNCATION_MARKER.length &&
    captured.include?(TelemetryRedactorP7::TRUNCATION_MARKER)
end

p7_check('P7-REDACT-08', 'Redacted Map[String,String] headers remain valid Map type') do
  headers  = { 'authorization' => 'Bearer t', 'x-api-key' => 'k', 'content-type' => 'text/plain' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  # All values are String after redaction — Map[String,String] constraint holds
  MapHeadersV0.validate_type(redacted).valid == true
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-POLICY: Capability policy unchanged by Map headers
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-POLICY: Capability policy with Map-shaped headers"

p7_check('P7-POLICY-01', 'Allowed HTTPS GET with Map headers → decision allowed') do
  d = HttpCapabilityPolicyP7.check(CAP_P7, p7_get('/health'))
  d[:allowed] == true && d[:reason_code].nil?
end

p7_check('P7-POLICY-02', 'Disallowed host with Map headers → BLOCKED-HOST') do
  req = p7_get('/health', 'evil.example.com')
  d = HttpCapabilityPolicyP7.check(CAP_P7, req)
  !d[:allowed] && d[:reason_code] == NetworkErrorCodesP7::BLOCKED_HOST
end

p7_check('P7-POLICY-03', 'PUT method with Map headers → BLOCKED-METHOD') do
  req = p7_get.merge('method' => 'PUT')
  d = HttpCapabilityPolicyP7.check(CAP_P7, req)
  !d[:allowed] && d[:reason_code] == NetworkErrorCodesP7::BLOCKED_METHOD
end

p7_check('P7-POLICY-04', 'HTTP scheme with Map headers → INSECURE-SCHEME') do
  req = p7_get.merge('url' => 'http://api.example.com/health')
  d = HttpCapabilityPolicyP7.check(CAP_P7, req)
  !d[:allowed] && d[:reason_code] == NetworkErrorCodesP7::INSECURE_SCHEME
end

p7_check('P7-POLICY-05', 'Malformed URL with Map headers → MALFORMED-URL') do
  req = p7_get.merge('url' => 'not-a-valid-url')
  d = HttpCapabilityPolicyP7.check(CAP_P7, req)
  !d[:allowed] && d[:reason_code] == NetworkErrorCodesP7::MALFORMED_URL
end

p7_check('P7-POLICY-06', 'Timeout over budget with Map headers → TIMEOUT-BUDGET') do
  req = p7_get('/health', 'api.example.com', 5001)
  d = HttpCapabilityPolicyP7.check(CAP_P7, req)
  !d[:allowed] && d[:reason_code] == NetworkErrorCodesP7::TIMEOUT_BUDGET
end

p7_check('P7-POLICY-07', 'Port 80 with Map headers → PORT-DENIED') do
  req = p7_get.merge('url' => 'https://api.example.com:80/health')
  d = HttpCapabilityPolicyP7.check(CAP_P7, req)
  !d[:allowed] && d[:reason_code] == NetworkErrorCodesP7::PORT_DENIED
end

p7_check('P7-POLICY-08', 'Map headers do not affect policy (policy reads url/method/timeout only)') do
  # Same URL/method/timeout — different header content — same policy outcome
  req_a = p7_get(headers: { 'content-type' => 'application/json' })
  req_b = p7_get(headers: { 'accept' => 'text/html', 'x-custom' => 'value' })
  da = HttpCapabilityPolicyP7.check(CAP_P7, req_a)
  db = HttpCapabilityPolicyP7.check(CAP_P7, req_b)
  da[:allowed] == db[:allowed] && da[:reason_code] == db[:reason_code]
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-TRANSPORT: Mocked transport with Map-shaped headers
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-TRANSPORT: Mocked transport with Map headers"

p7_check('P7-TRANSPORT-01', 'Allowed GET /health with Map headers → 200; response headers Map-typed') do
  result = HttpClientP7.request(CAP_P7, p7_get('/health'))
  resp = result[:response]
  # Response headers from transport are String-keyed/valued
  type_ok = MapHeadersV0.validate_type(resp['headers']).valid
  result[:ok] == true && resp['status'] == 200 && type_ok
end

p7_check('P7-TRANSPORT-02', 'Allowed POST /data with Map headers → 201') do
  result = HttpClientP7.request(CAP_P7, p7_post('/data'))
  result[:ok] == true && result[:response]['status'] == 201
end

p7_check('P7-TRANSPORT-03', 'Unknown path → 404 fallback; Map headers do not affect routing') do
  req    = p7_get('/nonexistent/route')
  result = HttpClientP7.request(CAP_P7, req)
  result[:ok] == true && result[:response]['status'] == 404
end

p7_check('P7-TRANSPORT-04', 'Denied request never reaches transport (policy gate)') do
  req    = p7_get('/health', 'blocked.example.com')
  result = HttpClientP7.request(CAP_P7, req)
  result[:ok] == false && result[:response].nil?
end

p7_check('P7-TRANSPORT-05', 'Allowed request receipt carries mocked_transport_id') do
  result = HttpClientP7.request(CAP_P7, p7_get('/health'))
  result[:receipt]['mocked_transport_id'] == 'mock-http-transport-v0'
end

p7_check('P7-TRANSPORT-06', 'Mock transport is deterministic with Map headers') do
  req = p7_get('/health')
  r1  = MockHttpTransportP7.dispatch(req)
  r2  = MockHttpTransportP7.dispatch(req)
  r1['status'] == r2['status'] && r1['body'] == r2['body']
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-RECEIPT: Telemetry receipt format
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-RECEIPT: Telemetry receipt format"

p7_check('P7-RECEIPT-01', 'Allowed receipt: capability_decision = "allowed"') do
  result = HttpClientP7.request(CAP_P7, p7_get('/health'))
  result[:receipt]['capability_decision'] == 'allowed' &&
    result[:receipt]['capability_id'] == 'cap-http-client-api-example'
end

p7_check('P7-RECEIPT-02', 'Denied receipt: capability_decision = "denied"') do
  req    = p7_get('/health', 'blocked.example.com')
  result = HttpClientP7.request(CAP_P7, req)
  result[:receipt]['capability_decision'] == 'denied'
end

p7_check('P7-RECEIPT-03', 'Denied receipt carries denial_reason with code') do
  req    = p7_get('/health', 'blocked.example.com')
  result = HttpClientP7.request(CAP_P7, req)
  dr = result[:receipt]['denial_reason']
  dr.is_a?(Hash) && dr['code'] == NetworkErrorCodesP7::BLOCKED_HOST
end

p7_check('P7-RECEIPT-04', 'Receipt carries request_method and request_host') do
  result = HttpClientP7.request(CAP_P7, p7_get('/health'))
  result[:receipt]['request_method'] == 'GET' &&
    result[:receipt]['request_host'] == 'api.example.com'
end

p7_check('P7-RECEIPT-05', 'Receipt contains no absolute local file paths') do
  result   = HttpClientP7.request(CAP_P7, p7_get('/health'))
  json_str = JSON.generate(result[:receipt])
  !json_str.include?('/Users/') && !json_str.include?('/home/') &&
    !json_str.match?(%r{"/[A-Za-z]+/[A-Za-z]+/})
end

p7_check('P7-RECEIPT-06', 'Receipt contains no file:// links') do
  result   = HttpClientP7.request(CAP_P7, p7_get('/health'))
  json_str = JSON.generate(result[:receipt])
  !json_str.include?('file://')
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-CLOSED: Closed-surface scan
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-CLOSED: Closed-surface scan"

p7_check('P7-CLOSED-01', 'No real socket primitives in proof') do
  !SOURCE_P7.include?('TCP' + 'Socket') && !SOURCE_P7.include?('UDP' + 'Socket')
end

p7_check('P7-CLOSED-02', 'No http-lib or require-net usage') do
  !SOURCE_P7.include?('Net' + '::' + 'HTTP') &&
    !SOURCE_P7.include?("require 'net/" + "http'") &&
    !SOURCE_P7.include?("require 'open-" + "uri'")
end

p7_check('P7-CLOSED-03', 'No require-socket usage') do
  !SOURCE_P7.include?("require 'sock" + "et'")
end

p7_check('P7-CLOSED-04', 'No Rack-compat or service-listener claim') do
  !SOURCE_P7.include?('Rack-comp' + 'atible') &&
    !SOURCE_P7.include?('server runt' + 'ime') &&
    !SOURCE_P7.include?('HTTP serv' + 'er')
end

p7_check('P7-CLOSED-05', 'No finalized-API or canon-authority claim') do
  !SOURCE_P7.include?('prod' + 'uction runtime') &&
    !SOURCE_P7.include?('canon' + ' API') &&
    !SOURCE_P7.include?('stab' + 'le API')
end

# ════════════════════════════════════════════════════════════════════════════════
# P7-GAP: Explicit answers to all card questions
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P7-GAP: Explicit answers to card questions"

p7_check('P7-GAP-01', 'Map[String,String] is usable for HttpRequest headers') do
  # Proved: MapHeadersV0 validates all-String keys/values; map_get → Option[String]
  req = p7_get(headers: { 'content-type' => 'application/json', 'accept' => 'application/json' })
  HttpRequestMapShape.validate(req).valid == true
end

p7_check('P7-GAP-02', 'Map[String,String] is usable for HttpResponse headers') do
  resp = { 'status' => 200, 'headers' => { 'content-type' => 'application/json' }, 'body' => '' }
  HttpResponseMapShape.validate(resp).valid == true
end

p7_check('P7-GAP-03', 'Header lookup and fallback typecheck cleanly') do
  # map_get(Map[String,String], String) → Option[String] — proved P7-TYPEINFER-01
  # or_else(Option[String], String) → String — proved P7-TYPEINFER-02
  # Runtime: MapHeadersV0.get returns { some: value } or { none: true }
  headers = { 'content-type' => 'application/json' }
  ct_opt  = MapHeadersV0.get(headers, 'content-type')
  ct_val  = MapHeadersV0.or_else(ct_opt, 'text/plain')
  miss_opt = MapHeadersV0.get(headers, 'x-missing')
  miss_val = MapHeadersV0.or_else(miss_opt, 'text/plain')
  ct_val == 'application/json' && miss_val == 'text/plain'
end

p7_check('P7-GAP-04', 'Map header data does not change redaction behavior') do
  # Redaction replaces String value with '[REDACTED]' (still a String)
  # Map[String,String] shape is preserved after redaction
  headers  = { 'authorization' => 'Bearer tok', 'content-type' => 'text/plain' }
  redacted = TelemetryRedactorP7.redact_request_headers(headers)
  MapHeadersV0.validate_type(redacted).valid == true &&
    redacted['authorization'] == '[REDACTED]' &&
    redacted['content-type'] == 'text/plain'
end

p7_check('P7-GAP-05', 'Capability policy still gates before transport with Map headers') do
  # Denied request (bad host) never dispatches to MockHttpTransportP7
  result = HttpClientP7.request(CAP_P7, p7_get('/health', 'evil.example.com'))
  result[:ok] == false && result[:response].nil?
end

p7_check('P7-GAP-06', 'Mocked transport remains sufficient; real I/O, DNS, TLS remain closed') do
  # MockHttpTransportP7 is a pure table lookup (no socket, no DNS, no TLS)
  # transport_id labels it as mock
  MockHttpTransportP7.transport_id == 'mock-http-transport-v0'
end

p7_check('P7-GAP-07', 'Listener/accept-loop startup remains closed') do
  # listen_allowed=false; no bind_address; no accept loop
  CAP_P7['listen_allowed'] == false && CAP_P7['bind_address'].nil?
end

p7_check('P7-GAP-08', 'No HTTP client API authority, Rack compat, or canon authority created') do
  # This proof is lab-only. All modules are proof-local.
  # No API authority is declared public or finalized.
  SOURCE_P7.include?('lab-only') && SOURCE_P7.include?('No canon claim') &&
    !SOURCE_P7.include?('Rack-comp' + 'atible')
end

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════

passes = $p7_results.count { |r| r[:status] == 'PASS' }
fails  = $p7_results.count { |r| r[:status] == 'FAIL' }
total  = $p7_results.size

puts "\n" + '=' * 60
puts "LAB-STDLIB-NET-P7 (HTTP Boundary / Map Alignment)"
puts "RESULT: #{passes}/#{total} PASS  |  #{fails} FAIL"
puts '=' * 60

exit(fails == 0 ? 0 : 1)
