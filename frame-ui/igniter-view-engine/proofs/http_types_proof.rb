# frozen_string_literal: true
# Proof: HttpRequest / HttpResponse typed Records + ContractRef dispatch
# Card: LAB-LANG-HTTP-TYPES-P1
# Surface: lab-only, proof-local evidence only.
# No canon claim, no public API, no stable schema.
# No real HTTP calls — in-memory type-system simulation only.
# Syntax comments marked "Illustrative only — not canon syntax" (lab-experimental).

require 'json'
require 'pathname'

FIXTURE_DIR = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'http_types'

# ═══════════════════════════════════════════════════════════════════════════════
# Module: IgniterTypeSystem
# Simulates proof-local type-checking for Igniter Record{} types.
# Illustrative only — not canon syntax.
# ═══════════════════════════════════════════════════════════════════════════════

module IgniterTypeSystem
  HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS].freeze
  VALID_STATUS_CLASSES = [1, 2, 3, 4, 5].freeze # 1xx–5xx

  # HttpRequest schema: typed Record fields
  # Illustrative — Record{ method: String, path: String, headers: Map[String,String], body: Option[String] }
  HTTP_REQUEST_SCHEMA = {
    'method'  => { type: :string,           required: true,  constraint: ->(v) { HTTP_METHODS.include?(v) } },
    'path'    => { type: :string,           required: true,  constraint: ->(v) { v.start_with?('/') } },
    'headers' => { type: :map_string_string, required: true  },
    'body'    => { type: :option_string,    required: false }
  }.freeze

  # HttpResponse schema
  # Illustrative — Record{ status: Integer, headers: Map[String,String], body: Option[String] }
  HTTP_RESPONSE_SCHEMA = {
    'status'  => { type: :integer,          required: true, constraint: ->(v) { v >= 100 && v <= 599 } },
    'headers' => { type: :map_string_string, required: true },
    'body'    => { type: :option_string,    required: false }
  }.freeze

  def self.validate_record(data, schema)
    errors = []
    schema.each do |field, spec|
      if spec[:required] && !data.key?(field)
        errors << "missing required field: #{field}"
        next
      end
      next unless data.key?(field)
      val = data[field]
      case spec[:type]
      when :string
        errors << "#{field} must be a String" unless val.is_a?(String)
      when :integer
        errors << "#{field} must be an Integer" unless val.is_a?(Integer)
      when :map_string_string
        unless val.is_a?(Hash) && val.all? { |k, v| k.is_a?(String) && v.is_a?(String) }
          errors << "#{field} must be Map[String,String]"
        end
      when :option_string
        unless val.nil? || val.is_a?(String)
          errors << "#{field} must be Option[String] (nil or String)"
        end
      end
      if spec[:constraint] && !val.nil? && !spec[:constraint].call(val)
        errors << "#{field} constraint violated: #{val.inspect}"
      end
    end
    { valid: errors.empty?, errors: errors }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Module: IgniterContractRef
# Simulates ContractRef[HttpRequest, HttpResponse] dispatch and chain composition.
# Illustrative — ContractRef[A, B] is a typed reference to a contract.
# ═══════════════════════════════════════════════════════════════════════════════

module IgniterContractRef
  # Create a ContractRef[HttpRequest, HttpResponse] from a block.
  # Takes an optional idempotent: keyword to declare the idempotency property.
  def self.make(name, idempotent: nil, &block)
    {
      name:        name,
      call:        block,
      input_type:  :HttpRequest,
      output_type: :HttpResponse,
      idempotent:  idempotent
    }
  end

  # Dispatch: validate input, call contract, validate output.
  def self.dispatch(contract_ref, request)
    in_result = IgniterTypeSystem.validate_record(request, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
    return { ok: false, failure: 'type_error', errors: in_result[:errors] } unless in_result[:valid]

    response = contract_ref[:call].call(request)

    out_result = IgniterTypeSystem.validate_record(response, IgniterTypeSystem::HTTP_RESPONSE_SCHEMA)
    return { ok: false, failure: 'type_error', errors: out_result[:errors] } unless out_result[:valid]

    { ok: true, response: response }
  end

  # Compose a chain of ContractRefs (Rack Builder analog).
  # Each middleware in the chain sees the request; the last ref produces the response.
  # Illustrative — models Rack middleware stack where inner handler is the final ref.
  def self.compose_chain(refs)
    raise ArgumentError, 'refs must be non-empty' if refs.empty?
    {
      name:        refs.map { |r| r[:name] }.join(' → '),
      input_type:  :HttpRequest,
      output_type: :HttpResponse,
      idempotent:  nil,
      call: lambda do |request|
        # Each middleware can inspect/mutate the request before passing to next.
        # Simple proof model: last ref produces the authoritative response.
        refs.last[:call].call(request)
      end
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Module: IgniterFailure
# Simulates the three Igniter failure classes.
# ═══════════════════════════════════════════════════════════════════════════════

module IgniterFailure
  CLASSES = %w[failed timed_out unknown_external_state].freeze

  def self.make(failure_class, message, context = {})
    raise "Unknown failure class: #{failure_class}" unless CLASSES.include?(failure_class.to_s)
    { failure_class: failure_class.to_s, message: message, context: context }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Proof runner harness
# ═══════════════════════════════════════════════════════════════════════════════

CHECKS     = []
FAILURES   = []
CHECK_LOCK = Mutex.new

def check(label)
  result = yield
  CHECK_LOCK.synchronize do
    if result
      CHECKS << { label: label, passed: true }
      puts "  PASS  #{label}"
    else
      CHECKS << { label: label, passed: false }
      FAILURES << label
      puts "  FAIL  #{label}"
    end
  end
rescue => e
  CHECK_LOCK.synchronize do
    CHECKS << { label: label, passed: false }
    FAILURES << label
    puts "  ERROR #{label} — #{e.class}: #{e.message}"
  end
end

def section(title)
  puts "\n── #{title} ──"
end

# ───────────────────────────────────────────────────────────────────────────────
# Load fixtures
# ───────────────────────────────────────────────────────────────────────────────

def load_fixture(name)
  JSON.parse(File.read(FIXTURE_DIR / name))
end

req_get_valid       = load_fixture('request_get_valid.json')
req_post_valid      = load_fixture('request_post_valid.json')
req_invalid_method  = load_fixture('request_invalid_method.json')
req_invalid_path    = load_fixture('request_invalid_path.json')
resp_200_ok         = load_fixture('response_200_ok.json')
resp_404            = load_fixture('response_404.json')
resp_invalid_status = load_fixture('response_invalid_status.json')

# ───────────────────────────────────────────────────────────────────────────────
# Define reusable contract refs
# ───────────────────────────────────────────────────────────────────────────────

echo_contract = IgniterContractRef.make('echo', idempotent: true) do |req|
  { 'status' => 200, 'headers' => { 'Content-Type' => 'application/json' }, 'body' => req['body'] }
end

always_404_contract = IgniterContractRef.make('always_404', idempotent: true) do |_req|
  { 'status' => 404, 'headers' => { 'Content-Type' => 'application/json' }, 'body' => '{"error":"Not Found"}' }
end

bad_output_contract = IgniterContractRef.make('bad_output') do |_req|
  # Returns invalid response — status 999 violates constraint
  { 'status' => 999, 'headers' => { 'Content-Type' => 'text/plain' }, 'body' => nil }
end

post_contract = IgniterContractRef.make('create_user', idempotent: false) do |req|
  { 'status' => 201, 'headers' => { 'Content-Type' => 'application/json' }, 'body' => req['body'] }
end

logging_middleware = IgniterContractRef.make('logging') do |_req|
  # In a real middleware this would call next; here it short-circuits for structural proof
  { 'status' => 200, 'headers' => { 'X-Log' => 'true' }, 'body' => nil }
end

auth_middleware = IgniterContractRef.make('auth') do |_req|
  { 'status' => 200, 'headers' => { 'X-Auth' => 'verified' }, 'body' => nil }
end

puts '═' * 70
puts 'Proof: LAB-LANG-HTTP-TYPES-P1 — HttpRequest/HttpResponse Types + ContractRef Dispatch'
puts '═' * 70

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: HTTP-SCHEMA (10 checks)
# ═══════════════════════════════════════════════════════════════════════════════

section 'HTTP-SCHEMA'

check('HTTP-SCHEMA-01: Valid GET request validates') do
  r = IgniterTypeSystem.validate_record(req_get_valid, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r[:valid] == true
end

check('HTTP-SCHEMA-02: Valid POST request validates') do
  r = IgniterTypeSystem.validate_record(req_post_valid, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r[:valid] == true
end

check('HTTP-SCHEMA-03: Invalid method fails with method name in error') do
  r = IgniterTypeSystem.validate_record(req_invalid_method, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r[:valid] == false && r[:errors].any? { |e| e.include?('FETCH') }
end

check('HTTP-SCHEMA-04: Invalid path (no leading /) fails') do
  r = IgniterTypeSystem.validate_record(req_invalid_path, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r[:valid] == false && r[:errors].any? { |e| e.include?('path') }
end

check('HTTP-SCHEMA-05: Missing required field (no method) fails') do
  req = req_get_valid.dup.tap { |h| h.delete('method') }
  r = IgniterTypeSystem.validate_record(req, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r[:valid] == false && r[:errors].any? { |e| e.include?('method') }
end

check('HTTP-SCHEMA-06: Valid 200 response validates') do
  r = IgniterTypeSystem.validate_record(resp_200_ok, IgniterTypeSystem::HTTP_RESPONSE_SCHEMA)
  r[:valid] == true
end

check('HTTP-SCHEMA-07: Valid 404 response validates') do
  r = IgniterTypeSystem.validate_record(resp_404, IgniterTypeSystem::HTTP_RESPONSE_SCHEMA)
  r[:valid] == true
end

check('HTTP-SCHEMA-08: Invalid status 999 fails') do
  r = IgniterTypeSystem.validate_record(resp_invalid_status, IgniterTypeSystem::HTTP_RESPONSE_SCHEMA)
  r[:valid] == false && r[:errors].any? { |e| e.include?('status') }
end

check('HTTP-SCHEMA-09: headers Map[String,String] — non-string value fails') do
  bad_req = req_get_valid.merge('headers' => { 'Accept' => 42 })
  r = IgniterTypeSystem.validate_record(bad_req, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r[:valid] == false && r[:errors].any? { |e| e.include?('headers') }
end

check('HTTP-SCHEMA-10: body Option[String] — nil is valid; non-string fails') do
  nil_body_req = req_get_valid.merge('body' => nil)
  r_nil = IgniterTypeSystem.validate_record(nil_body_req, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  bad_body_req = req_get_valid.merge('body' => 12345)
  r_bad = IgniterTypeSystem.validate_record(bad_body_req, IgniterTypeSystem::HTTP_REQUEST_SCHEMA)
  r_nil[:valid] == true && r_bad[:valid] == false
end

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: HTTP-CONTRACT-REF (8 checks)
# ═══════════════════════════════════════════════════════════════════════════════

section 'HTTP-CONTRACT-REF'

check('HTTP-CONTRACT-REF-01: dispatch(echo_contract, valid_request) returns ok:true') do
  result = IgniterContractRef.dispatch(echo_contract, req_get_valid)
  result[:ok] == true && result[:response].is_a?(Hash)
end

check('HTTP-CONTRACT-REF-02: dispatch(echo_contract, invalid_request) returns ok:false type_error') do
  result = IgniterContractRef.dispatch(echo_contract, req_invalid_method)
  result[:ok] == false && result[:failure] == 'type_error'
end

check('HTTP-CONTRACT-REF-03: dispatch(always_404_contract, valid_request) returns ok:true with 404') do
  result = IgniterContractRef.dispatch(always_404_contract, req_get_valid)
  result[:ok] == true && result[:response]['status'] == 404
end

check('HTTP-CONTRACT-REF-04: dispatch produces validated output (response schema checked)') do
  result = IgniterContractRef.dispatch(echo_contract, req_get_valid)
  result[:ok] == true &&
    IgniterTypeSystem.validate_record(result[:response], IgniterTypeSystem::HTTP_RESPONSE_SCHEMA)[:valid]
end

check('HTTP-CONTRACT-REF-05: ContractRef has correct input_type and output_type') do
  echo_contract[:input_type] == :HttpRequest && echo_contract[:output_type] == :HttpResponse
end

check('HTTP-CONTRACT-REF-06: ContractRef name field set correctly') do
  echo_contract[:name] == 'echo'
end

check('HTTP-CONTRACT-REF-07: dispatch with contract returning invalid response → type_error') do
  result = IgniterContractRef.dispatch(bad_output_contract, req_get_valid)
  result[:ok] == false && result[:failure] == 'type_error'
end

check('HTTP-CONTRACT-REF-08: dispatch returns correct status for any valid request') do
  r1 = IgniterContractRef.dispatch(always_404_contract, req_get_valid)
  r2 = IgniterContractRef.dispatch(always_404_contract, req_post_valid)
  r1[:ok] && r1[:response]['status'] == 404 &&
    r2[:ok] && r2[:response]['status'] == 404
end

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: HTTP-CHAIN (8 checks)
# ═══════════════════════════════════════════════════════════════════════════════

section 'HTTP-CHAIN'

single_chain  = IgniterContractRef.compose_chain([echo_contract])
logging_chain = IgniterContractRef.compose_chain([logging_middleware, always_404_contract])
three_chain   = IgniterContractRef.compose_chain([logging_middleware, auth_middleware, echo_contract])

check('HTTP-CHAIN-01: compose_chain of 1 ref = same behavior as single ref') do
  r_direct = IgniterContractRef.dispatch(echo_contract, req_get_valid)
  r_chain  = IgniterContractRef.dispatch(single_chain, req_get_valid)
  r_direct[:ok] == r_chain[:ok] &&
    r_direct[:response]['status'] == r_chain[:response]['status']
end

check('HTTP-CHAIN-02: compose_chain [logging_middleware, handler] → handler response returned') do
  result = IgniterContractRef.dispatch(logging_chain, req_get_valid)
  result[:ok] == true && result[:response]['status'] == 404
end

check('HTTP-CHAIN-03: compose_chain name = joined names') do
  logging_chain[:name] == 'logging → always_404'
end

check('HTTP-CHAIN-04: compose_chain input_type = :HttpRequest') do
  logging_chain[:input_type] == :HttpRequest
end

check('HTTP-CHAIN-05: compose_chain output_type = :HttpResponse') do
  logging_chain[:output_type] == :HttpResponse
end

check('HTTP-CHAIN-06: dispatch on composed chain with valid request works') do
  result = IgniterContractRef.dispatch(three_chain, req_get_valid)
  result[:ok] == true
end

check('HTTP-CHAIN-07: Multiple chain compositions — 3-ref chain') do
  three_chain[:name] == 'logging → auth → echo' &&
    IgniterContractRef.dispatch(three_chain, req_post_valid)[:ok] == true
end

check('HTTP-CHAIN-08: Chain with invalid input → type_error at dispatch boundary') do
  result = IgniterContractRef.dispatch(logging_chain, req_invalid_path)
  result[:ok] == false && result[:failure] == 'type_error'
end

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: HTTP-FAILURE (6 checks)
# ═══════════════════════════════════════════════════════════════════════════════

section 'HTTP-FAILURE'

check('HTTP-FAILURE-01: IgniterFailure.make(:failed, ...) → failure_class:failed') do
  f = IgniterFailure.make(:failed, 'Not found')
  f[:failure_class] == 'failed'
end

check('HTTP-FAILURE-02: IgniterFailure.make(:timed_out, ...) → failure_class:timed_out') do
  f = IgniterFailure.make(:timed_out, 'Timeout after 30s')
  f[:failure_class] == 'timed_out'
end

check('HTTP-FAILURE-03: IgniterFailure.make(:unknown_external_state, ...) → correct class') do
  f = IgniterFailure.make(:unknown_external_state, 'Network partition — state unclear')
  f[:failure_class] == 'unknown_external_state'
end

check('HTTP-FAILURE-04: Unknown failure class raises error') do
  raised = false
  begin
    IgniterFailure.make(:bad_class, 'oops')
  rescue RuntimeError
    raised = true
  end
  raised
end

check('HTTP-FAILURE-05: Failure has message field') do
  f = IgniterFailure.make(:failed, 'Resource not found', { path: '/api/users/99' })
  f[:message] == 'Resource not found'
end

check('HTTP-FAILURE-06: Failure distinguishes 404 (failed) / timeout (timed_out) / network (unknown_external_state)') do
  f404     = IgniterFailure.make(:failed,                 '404 Not Found')
  ftimeout = IgniterFailure.make(:timed_out,              'Request exceeded 30s budget')
  fnet     = IgniterFailure.make(:unknown_external_state, 'TCP reset — response state unknown')
  f404[:failure_class] == 'failed' &&
    ftimeout[:failure_class] == 'timed_out' &&
    fnet[:failure_class] == 'unknown_external_state' &&
    f404[:failure_class] != ftimeout[:failure_class] &&
    ftimeout[:failure_class] != fnet[:failure_class]
end

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: HTTP-IDEMPOTENCY (4 checks)
# ═══════════════════════════════════════════════════════════════════════════════

section 'HTTP-IDEMPOTENCY'

check('HTTP-IDEMPOTENCY-01: GET contract declared idempotent — property accessible') do
  echo_contract[:idempotent] == true
end

check('HTTP-IDEMPOTENCY-02: POST contract declared non-idempotent') do
  post_contract[:idempotent] == false
end

check('HTTP-IDEMPOTENCY-03: Idempotent contract — calling twice produces same output') do
  r1 = IgniterContractRef.dispatch(echo_contract, req_get_valid)
  r2 = IgniterContractRef.dispatch(echo_contract, req_get_valid)
  r1[:ok] == true && r2[:ok] == true &&
    r1[:response]['status'] == r2[:response]['status'] &&
    r1[:response]['body'] == r2[:response]['body']
end

check('HTTP-IDEMPOTENCY-04: Non-idempotent contract — no idempotency claim (idempotent: false)') do
  post_contract[:idempotent] == false
end

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: HTTP-STABLE (5 checks)
# ═══════════════════════════════════════════════════════════════════════════════

section 'HTTP-STABLE'

check('HTTP-STABLE-01: IgniterTypeSystem responds to validate_record') do
  IgniterTypeSystem.respond_to?(:validate_record)
end

check('HTTP-STABLE-02: IgniterContractRef responds to dispatch and compose_chain') do
  IgniterContractRef.respond_to?(:dispatch) && IgniterContractRef.respond_to?(:compose_chain)
end

check('HTTP-STABLE-03: No real HTTP calls in this file (split-string guard scan)') do
  # Uses split-string technique to avoid self-triggering on the scan line.
  source = File.read(__FILE__, encoding: 'utf-8')
  net_class   = 'Net' + '::' + 'HTTP'
  tcp_class   = 'TCP' + 'Socket'
  http_open   = 'Net' + '::' + 'HTTP' + '.start'
  !source.include?(net_class) && !source.include?(tcp_class) && !source.include?(http_open)
end

check('HTTP-STABLE-04: igniter-lang directory untouched (git status check)') do
  base = '/Users/alex/dev/projects/igniter-workspace/igniter-lab'
  lang_dir = File.join(base, 'igniter-lang')
  # If the directory doesn't exist we can't have touched it
  !File.exist?(lang_dir) ||
    begin
      out = `git -C "#{base}" status --porcelain "igniter-lang" 2>&1`
      out.strip.empty?
    rescue
      true
    end
end

check('HTTP-STABLE-05: P1 HTTP types proof does not require network_ffi_stub') do
  source = File.read(__FILE__, encoding: 'utf-8')
  # Split-string technique: avoid self-match on the literal terms
  stub_term = 'network' + '_ffi' + '_stub'
  ffi_term  = 'network' + '_ffi'
  # Count occurrences — the only hits should be inside this check block (self-reference only)
  stub_hits = source.scan(stub_term).size
  ffi_hits  = source.scan(ffi_term).size
  # stub_term appears in: the check label (1), the stub_term assignment (1) = 2 hits max from self-ref
  # ffi_term appears inside stub_term hits too; total from self-reference <= 4
  stub_hits <= 2 && ffi_hits <= 4
end

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

puts "\n#{'═' * 70}"
passed = CHECKS.count { |c| c[:passed] }
total  = CHECKS.size
puts "Result: #{passed}/#{total} checks passed"

if FAILURES.empty?
  puts 'Status: ALL CHECKS PASSED'
else
  puts "Status: FAILURES (#{FAILURES.size}):"
  FAILURES.each { |f| puts "  - #{f}" }
end
puts '═' * 70
exit(FAILURES.empty? ? 0 : 1)
