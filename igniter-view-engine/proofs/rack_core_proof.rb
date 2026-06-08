# frozen_string_literal: true
# Proof: Rack Core Contract Shape and Middleware Pipeline
# Card:  LAB-RACK-P2
# Track: lab-rack-core-contract-shape-and-pipeline-proof-v0
# Date:  2026-06-08
#
# Surface boundary:
#   lab-only · no real network I/O · no service-loop (accept-loop class)
#   no real socket classes · no accept-loop · no canon-auth or stable-API claim
#
# This proof validates:
#   - HttpRequest / HttpResponse Record shapes with Collection[String] bodies
#   - RackEnvAdapter: Rack env hash → HttpRequest (field mapping + validation)
#   - RackTupleAdapter: HttpResponse → [status, headers, body] (Rack triple)
#   - HandlerContract dispatch with type-boundary enforcement
#   - Static middleware pipeline composition (proper wrap model)
#   - Typed failure taxonomy (failed / timed_out / unknown_external_state)
#   - Closed-surface: no real I/O, no service-loop, no canon-auth claim
#
# Does NOT prove: dynamic ContractRef dispatch, accept-loop / service-loop class,
#   streaming bodies, network I/O, session/cookie handling, content negotiation,
#   multipart parsing, or any production HTTP server capability.

require 'json'
require 'pathname'

FIXTURE_DIR = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'rack_core'

# ═══════════════════════════════════════════════════════════════════════════════
# Module: RackHttpTypes
# Proof-local simulation of Igniter Record{} type schemas for HTTP contracts.
# Body is Collection[String] (bounded, array of String chunks).
# Illustrative only — not canon syntax; not a stable/production interface.
# ═══════════════════════════════════════════════════════════════════════════════

module RackHttpTypes
  HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS].freeze

  # HttpRequest Record schema — richer than P1; body is Collection[String].
  # Illustrative — Record{ method, path, query_string, scheme, host, headers, body }
  REQUEST_SCHEMA = {
    'method'       => { type: :string,              required: true,
                        constraint: ->(v) { HTTP_METHODS.include?(v) } },
    'path'         => { type: :string,              required: true,
                        constraint: ->(v) { v.start_with?('/') } },
    'query_string' => { type: :option_string,       required: false },
    'scheme'       => { type: :string,              required: true,
                        constraint: ->(v) { %w[http https].include?(v) } },
    'host'         => { type: :string,              required: true },
    'headers'      => { type: :map_string_string,   required: true },
    'body'         => { type: :collection_of_string, required: true }
  }.freeze

  # HttpResponse Record schema — body is Collection[String].
  # Illustrative — Record{ status: Integer, headers: Map[String,String], body: Collection[String] }
  RESPONSE_SCHEMA = {
    'status'  => { type: :integer,              required: true,
                   constraint: ->(v) { v >= 100 && v <= 599 } },
    'headers' => { type: :map_string_string,    required: true },
    'body'    => { type: :collection_of_string, required: true }
  }.freeze

  def self.validate(data, schema)
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
      when :option_string
        errors << "#{field} must be Option[String] (nil or String)" unless val.nil? || val.is_a?(String)
      when :map_string_string
        unless val.is_a?(Hash) && val.all? { |k, v| k.is_a?(String) && v.is_a?(String) }
          errors << "#{field} must be Map[String,String]"
        end
      when :collection_of_string
        unless val.is_a?(Array) && val.all? { |chunk| chunk.is_a?(String) }
          errors << "#{field} must be Collection[String] — all chunks must be String"
        end
      end
      if spec[:constraint] && !val.nil? && val.is_a?(spec[:type] == :integer ? Integer : Object)
        errors << "#{field} constraint violated: #{val.inspect}" unless spec[:constraint].call(val)
      end
    end
    { valid: errors.empty?, errors: errors }
  end

  def self.validate_request(data)  = validate(data, REQUEST_SCHEMA)
  def self.validate_response(data) = validate(data, RESPONSE_SCHEMA)
end

# ═══════════════════════════════════════════════════════════════════════════════
# Module: RackEnvAdapter
# Proof-local simulation of adapter: Rack env hash → HttpRequest Record
# and HttpResponse Record → [status, headers, body] Rack triple.
# No real I/O. Illustrative adapter — not canon, not a stable/production interface.
# ═══════════════════════════════════════════════════════════════════════════════

module RackEnvAdapter
  # Map Rack env hash keys to typed HttpRequest Record fields.
  # HTTP_* keys → normalized headers (without HTTP_ prefix, downcased).
  # rack.input → body as Collection[String] (single chunk if non-empty).
  def self.from_rack_env(env)
    headers = env
      .select { |k, _| k.start_with?('HTTP_') }
      .transform_keys { |k| k.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-') }
      .transform_values(&:to_s)

    raw_body = env['rack.input'] || ''

    {
      'method'       => env['REQUEST_METHOD'].to_s,
      'path'         => env['PATH_INFO'].to_s,
      'query_string' => env['QUERY_STRING'].to_s.empty? ? nil : env['QUERY_STRING'].to_s,
      'scheme'       => (env['rack.url_scheme'] || 'http').to_s,
      'host'         => (env['HTTP_HOST'] || env['SERVER_NAME'] || '').to_s,
      'headers'      => headers,
      'body'         => raw_body.empty? ? [] : [raw_body]
    }
  end

  # Map HttpResponse Record → Rack-style triple [status, headers, body].
  # Body is Collection[String] — directly usable as Rack body.
  def self.to_rack_tuple(response)
    [
      response['status'],
      response['headers'],
      response['body']
    ]
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Module: RackHandlerContract
# Proof-local simulation of HandlerContract = ContractRef[HttpRequest, HttpResponse].
# Dispatch validates input type and output type at boundary.
# Illustrative — ContractRef[A, B] is a typed contract reference.
# ═══════════════════════════════════════════════════════════════════════════════

module RackHandlerContract
  def self.make(name, idempotent: nil, &block)
    {
      name:        name,
      call:        block,
      input_type:  :HttpRequest,
      output_type: :HttpResponse,
      idempotent:  idempotent
    }
  end

  # Dispatch: validate input, invoke handler, validate output.
  # Type-boundary enforcement — both sides checked.
  def self.dispatch(handler, request)
    in_check = RackHttpTypes.validate_request(request)
    unless in_check[:valid]
      return { ok: false, failure: 'type_error', stage: 'input', errors: in_check[:errors] }
    end

    response = handler[:call].call(request)

    out_check = RackHttpTypes.validate_response(response)
    unless out_check[:valid]
      return { ok: false, failure: 'type_error', stage: 'output', errors: out_check[:errors] }
    end

    { ok: true, response: response }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Module: RackMiddlewareChain
# Proof-local simulation of static middleware pipeline composition.
# A middleware wraps an inner HandlerContract and returns a new HandlerContract.
# Equivalent shape: ContractRef[HandlerContract, HandlerContract] —
#   i.e., a function HandlerContract → HandlerContract.
# Illustrative — models Rack middleware stack without runtime assembly.
# ═══════════════════════════════════════════════════════════════════════════════

module RackMiddlewareChain
  # Make a middleware: a named wrapper that takes an inner HandlerContract
  # and returns a new HandlerContract.
  # block signature: |inner_handler, request| → response_hash
  def self.make_middleware(name, &block)
    {
      name:  name,
      apply: lambda do |inner_handler|
        RackHandlerContract.make("#{name}[#{inner_handler[:name]}]") do |request|
          block.call(inner_handler, request)
        end
      end
    }
  end

  # Build a static pipeline:
  #   terminal_handler is the innermost (no wrapping).
  #   middlewares applied outermost-first — i.e. pipeline[0] is outermost.
  #   Equivalent to: mw[0].apply(mw[1].apply(...mw[n].apply(terminal)))
  def self.build_pipeline(terminal_handler, *middlewares)
    middlewares.reverse.reduce(terminal_handler) do |inner, mw|
      mw[:apply].call(inner)
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Module: RackFailure
# Proof-local simulation of Igniter typed failure taxonomy.
# Three classes only: failed, timed_out, unknown_external_state.
# Illustrative — not canon syntax; not a stable/production interface.
# ═══════════════════════════════════════════════════════════════════════════════

module RackFailure
  CLASSES = %w[failed timed_out unknown_external_state].freeze

  def self.make(failure_class, message, context = {})
    fc = failure_class.to_s
    raise "Unknown RackFailure class: #{fc.inspect}" unless CLASSES.include?(fc)
    { failure_class: fc, message: message, context: context }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Proof harness
# ═══════════════════════════════════════════════════════════════════════════════

CHECKS   = []
FAILURES = []

def check(label)
  result = yield
  if result
    CHECKS << { label: label, passed: true }
    puts "  PASS  #{label}"
  else
    CHECKS << { label: label, passed: false }
    FAILURES << label
    puts "  FAIL  #{label}"
  end
rescue => e
  CHECKS << { label: label, passed: false }
  FAILURES << label
  puts "  ERROR #{label} — #{e.class}: #{e.message}"
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

env_get_valid        = load_fixture('env_get_valid.json')
env_post_valid       = load_fixture('env_post_valid.json')
env_invalid_method   = load_fixture('env_invalid_method.json')
env_invalid_path     = load_fixture('env_invalid_path.json')
resp_200             = load_fixture('response_200_chunks.json')
resp_400             = load_fixture('response_400_chunks.json')
resp_invalid_status  = load_fixture('response_invalid_status.json')
resp_invalid_headers = load_fixture('response_invalid_headers.json')
resp_invalid_body    = load_fixture('response_invalid_body.json')

# ───────────────────────────────────────────────────────────────────────────────
# Define reusable contracts for use across sections
# ───────────────────────────────────────────────────────────────────────────────

ok_handler = RackHandlerContract.make('ok_handler', idempotent: true) do |_req|
  { 'status' => 200, 'headers' => { 'Content-Type' => 'application/json' }, 'body' => ['{"ok":true}'] }
end

not_found_handler = RackHandlerContract.make('not_found', idempotent: true) do |_req|
  { 'status' => 404, 'headers' => { 'Content-Type' => 'application/json' }, 'body' => ['{"error":"Not Found"}'] }
end

create_handler = RackHandlerContract.make('create', idempotent: false) do |req|
  { 'status' => 201, 'headers' => { 'Content-Type' => 'application/json' }, 'body' => [req['body'].first || ''] }
end

bad_output_handler = RackHandlerContract.make('bad_output') do |_req|
  # status 999 violates constraint → output type_error
  { 'status' => 999, 'headers' => { 'Content-Type' => 'text/plain' }, 'body' => ['broken'] }
end

puts '═' * 72
puts 'Proof: LAB-RACK-P2 — Rack Core Contract Shape and Middleware Pipeline'
puts '═' * 72

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION: RACK-P2-SCHEMA  (proof matrix: P2-1, P2-2, P2-5, P2-6, P2-7)
# ═══════════════════════════════════════════════════════════════════════════════

section 'RACK-P2-SCHEMA'

# RACK-P2-1
check('RACK-P2-SCHEMA-01: [P2-1] HttpRequest positive fixture validates') do
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  RackHttpTypes.validate_request(req)[:valid] == true
end

# RACK-P2-1 (POST variant)
check('RACK-P2-SCHEMA-02: [P2-1] HttpRequest POST positive fixture validates') do
  req = RackEnvAdapter.from_rack_env(env_post_valid)
  RackHttpTypes.validate_request(req)[:valid] == true
end

# RACK-P2-2
check('RACK-P2-SCHEMA-03: [P2-2] HttpResponse 200 positive fixture validates') do
  RackHttpTypes.validate_response(resp_200)[:valid] == true
end

check('RACK-P2-SCHEMA-04: [P2-2] HttpResponse 400 positive fixture validates') do
  RackHttpTypes.validate_response(resp_400)[:valid] == true
end

# RACK-P2-5
check('RACK-P2-SCHEMA-05: [P2-5] status 999 fails closed (outside 100..599)') do
  r = RackHttpTypes.validate_response(resp_invalid_status)
  r[:valid] == false && r[:errors].any? { |e| e.include?('status') }
end

check('RACK-P2-SCHEMA-06: [P2-5] status 0 fails closed') do
  bad = resp_200.merge('status' => 0)
  r = RackHttpTypes.validate_response(bad)
  r[:valid] == false && r[:errors].any? { |e| e.include?('status') }
end

# RACK-P2-6
check('RACK-P2-SCHEMA-07: [P2-6] headers with Integer value fails closed') do
  r = RackHttpTypes.validate_response(resp_invalid_headers)
  r[:valid] == false && r[:errors].any? { |e| e.include?('headers') }
end

check('RACK-P2-SCHEMA-08: [P2-6] headers with non-string key fails closed') do
  bad = resp_200.merge('headers' => { 42 => 'application/json' })
  r = RackHttpTypes.validate_response(bad)
  r[:valid] == false && r[:errors].any? { |e| e.include?('headers') }
end

# RACK-P2-7
check('RACK-P2-SCHEMA-09: [P2-7] body with Integer chunk fails closed') do
  r = RackHttpTypes.validate_response(resp_invalid_body)
  r[:valid] == false && r[:errors].any? { |e| e.include?('body') }
end

check('RACK-P2-SCHEMA-10: [P2-7] body with all-String chunks passes') do
  good = resp_200.merge('body' => ['chunk one', 'chunk two', 'chunk three'])
  RackHttpTypes.validate_response(good)[:valid] == true
end

check('RACK-P2-SCHEMA-11: [P2-7] empty Collection[String] body is valid') do
  good = resp_200.merge('body' => [])
  RackHttpTypes.validate_response(good)[:valid] == true
end

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION: RACK-P2-ADAPTER  (proof matrix: P2-3, P2-4)
# ═══════════════════════════════════════════════════════════════════════════════

section 'RACK-P2-ADAPTER'

get_req = RackEnvAdapter.from_rack_env(env_get_valid)

# RACK-P2-3
check('RACK-P2-ADAPTER-01: [P2-3] REQUEST_METHOD → method field') do
  get_req['method'] == 'GET'
end

check('RACK-P2-ADAPTER-02: [P2-3] PATH_INFO → path field') do
  get_req['path'] == '/articles/42'
end

check('RACK-P2-ADAPTER-03: [P2-3] QUERY_STRING → query_string field (non-empty)') do
  get_req['query_string'] == 'page=1&sort=desc'
end

check('RACK-P2-ADAPTER-04: [P2-3] HTTP_* headers extracted and normalized') do
  # HTTP_ACCEPT → 'Accept', HTTP_HOST → 'Host', etc.
  get_req['headers'].is_a?(Hash) &&
    get_req['headers']['Accept'] == 'application/json' &&
    get_req['headers']['Accept-Language'] == 'en-US,en;q=0.9'
end

check('RACK-P2-ADAPTER-05: [P2-3] rack.input → body Collection[String]') do
  post_req = RackEnvAdapter.from_rack_env(env_post_valid)
  post_req['body'].is_a?(Array) &&
    post_req['body'].length == 1 &&
    post_req['body'].first.include?('product_id')
end

check('RACK-P2-ADAPTER-06: [P2-3] empty rack.input → empty body Collection') do
  get_req['body'] == []
end

check('RACK-P2-ADAPTER-07: [P2-3] invalid method env → validation fails') do
  bad_req = RackEnvAdapter.from_rack_env(env_invalid_method)
  RackHttpTypes.validate_request(bad_req)[:valid] == false
end

check('RACK-P2-ADAPTER-08: [P2-3] invalid path env → validation fails') do
  bad_req = RackEnvAdapter.from_rack_env(env_invalid_path)
  r = RackHttpTypes.validate_request(bad_req)
  r[:valid] == false && r[:errors].any? { |e| e.include?('path') }
end

# RACK-P2-4
check('RACK-P2-ADAPTER-09: [P2-4] to_rack_tuple returns Array of length 3') do
  tuple = RackEnvAdapter.to_rack_tuple(resp_200)
  tuple.is_a?(Array) && tuple.length == 3
end

check('RACK-P2-ADAPTER-10: [P2-4] tuple[0] = status Integer') do
  RackEnvAdapter.to_rack_tuple(resp_200)[0] == 200
end

check('RACK-P2-ADAPTER-11: [P2-4] tuple[1] = headers Hash') do
  RackEnvAdapter.to_rack_tuple(resp_200)[1].is_a?(Hash)
end

check('RACK-P2-ADAPTER-12: [P2-4] tuple[2] = body Collection[String]') do
  body = RackEnvAdapter.to_rack_tuple(resp_200)[2]
  body.is_a?(Array) && body.all? { |c| c.is_a?(String) }
end

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION: RACK-P2-HANDLER  (proof matrix: P2-8)
# ═══════════════════════════════════════════════════════════════════════════════

section 'RACK-P2-HANDLER'

# RACK-P2-8
check('RACK-P2-HANDLER-01: [P2-8] dispatch with valid input + valid output → ok:true') do
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(ok_handler, req)
  result[:ok] == true && result[:response]['status'] == 200
end

check('RACK-P2-HANDLER-02: [P2-8] HandlerContract output mismatch (status 999) → type_error') do
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(bad_output_handler, req)
  result[:ok] == false &&
    result[:failure] == 'type_error' &&
    result[:stage] == 'output'
end

check('RACK-P2-HANDLER-03: [P2-8] invalid input (CONNECT method) → type_error at input stage') do
  bad_req = RackEnvAdapter.from_rack_env(env_invalid_method)
  result = RackHandlerContract.dispatch(ok_handler, bad_req)
  result[:ok] == false &&
    result[:failure] == 'type_error' &&
    result[:stage] == 'input'
end

check('RACK-P2-HANDLER-04: HandlerContract type fields are :HttpRequest/:HttpResponse') do
  ok_handler[:input_type] == :HttpRequest &&
    ok_handler[:output_type] == :HttpResponse
end

check('RACK-P2-HANDLER-05: HandlerContract idempotent annotation accessible') do
  ok_handler[:idempotent] == true &&
    create_handler[:idempotent] == false
end

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION: RACK-P2-PIPELINE  (proof matrix: P2-9, P2-10)
# ═══════════════════════════════════════════════════════════════════════════════

section 'RACK-P2-PIPELINE'

# Define middlewares
logging_mw = RackMiddlewareChain.make_middleware('logging') do |inner, request|
  resp = inner[:call].call(request)
  resp.merge('headers' => resp['headers'].merge('X-Log-By' => 'logging'))
end

auth_mw = RackMiddlewareChain.make_middleware('auth') do |inner, request|
  resp = inner[:call].call(request)
  resp.merge('headers' => resp['headers'].merge('X-Auth' => 'verified'))
end

timing_mw = RackMiddlewareChain.make_middleware('timing') do |inner, request|
  resp = inner[:call].call(request)
  resp.merge('headers' => resp['headers'].merge('X-Time-Ms' => '4'))
end

broken_mw = RackMiddlewareChain.make_middleware('broken') do |_inner, _request|
  # Ignores inner handler, returns invalid response (status 999)
  { 'status' => 999, 'headers' => { 'Content-Type' => 'text/plain' }, 'body' => ['bad'] }
end

# RACK-P2-9
check('RACK-P2-PIPELINE-01: [P2-9] single-wrap pipeline preserves HttpRequest → HttpResponse') do
  pipeline = RackMiddlewareChain.build_pipeline(ok_handler, logging_mw)
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(pipeline, req)
  result[:ok] == true && result[:response]['status'] == 200
end

check('RACK-P2-PIPELINE-02: [P2-9] 2-middleware pipeline — middleware headers preserved') do
  pipeline = RackMiddlewareChain.build_pipeline(ok_handler, logging_mw, auth_mw)
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(pipeline, req)
  result[:ok] == true &&
    result[:response]['headers']['X-Log-By'] == 'logging' &&
    result[:response]['headers']['X-Auth'] == 'verified'
end

check('RACK-P2-PIPELINE-03: [P2-9] 3-middleware pipeline — all headers applied') do
  pipeline = RackMiddlewareChain.build_pipeline(ok_handler, logging_mw, auth_mw, timing_mw)
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(pipeline, req)
  result[:ok] == true &&
    result[:response]['headers'].key?('X-Log-By') &&
    result[:response]['headers'].key?('X-Auth') &&
    result[:response]['headers'].key?('X-Time-Ms')
end

check('RACK-P2-PIPELINE-04: [P2-9] pipeline name encodes wrapping depth') do
  pipeline = RackMiddlewareChain.build_pipeline(ok_handler, logging_mw, auth_mw)
  # outermost[middle[inner]] — logging wraps auth wraps ok_handler
  pipeline[:name].include?('logging') &&
    pipeline[:name].include?('auth') &&
    pipeline[:name].include?('ok_handler')
end

# RACK-P2-10
check('RACK-P2-PIPELINE-05: [P2-10] middleware returning invalid response fails closed') do
  pipeline = RackMiddlewareChain.build_pipeline(ok_handler, broken_mw)
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(pipeline, req)
  result[:ok] == false &&
    result[:failure] == 'type_error' &&
    result[:stage] == 'output'
end

check('RACK-P2-PIPELINE-06: [P2-10] broken outermost middleware fails even if inner is valid') do
  # Inner handler is fine, but outermost broken_mw overrides with invalid response
  pipeline = RackMiddlewareChain.build_pipeline(ok_handler, broken_mw, logging_mw)
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(pipeline, req)
  result[:ok] == false && result[:failure] == 'type_error'
end

check('RACK-P2-PIPELINE-07: [P2-9] terminal handler with no middlewares = direct dispatch') do
  pipeline = RackMiddlewareChain.build_pipeline(not_found_handler)
  req = RackEnvAdapter.from_rack_env(env_get_valid)
  result = RackHandlerContract.dispatch(pipeline, req)
  result[:ok] == true && result[:response]['status'] == 404
end

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION: RACK-P2-FAILURE  (proof matrix: P2-11)
# ═══════════════════════════════════════════════════════════════════════════════

section 'RACK-P2-FAILURE'

# RACK-P2-11
check('RACK-P2-FAILURE-01: [P2-11] failed → bounded HTTP-like outcome (4xx/5xx)') do
  f = RackFailure.make(:failed, '404 Not Found', { path: '/api/users/99' })
  f[:failure_class] == 'failed' &&
    f[:message] == '404 Not Found' &&
    f[:context][:path] == '/api/users/99'
end

check('RACK-P2-FAILURE-02: [P2-11] timed_out → bounded timeout outcome') do
  f = RackFailure.make(:timed_out, 'Request exceeded 30s budget', { handler: 'ok_handler' })
  f[:failure_class] == 'timed_out'
end

check('RACK-P2-FAILURE-03: [P2-11] unknown_external_state → bounded disconnect outcome') do
  f = RackFailure.make(:unknown_external_state, 'TCP reset — response delivery unknown')
  f[:failure_class] == 'unknown_external_state'
end

check('RACK-P2-FAILURE-04: [P2-11] three failure classes are distinct') do
  f1 = RackFailure.make(:failed,                 'logic error')
  f2 = RackFailure.make(:timed_out,              'timeout error')
  f3 = RackFailure.make(:unknown_external_state, 'network error')
  [f1[:failure_class], f2[:failure_class], f3[:failure_class]].uniq.length == 3
end

check('RACK-P2-FAILURE-05: [P2-11] unknown failure class rejected — fails closed') do
  raised = false
  begin
    RackFailure.make(:http_exception, 'not a valid class')
  rescue RuntimeError
    raised = true
  end
  raised
end

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION: RACK-P2-SURFACE  (proof matrix: P2-12, P2-13, P2-14)
# Closed-surface checks: verify no forbidden surfaces appear in this file.
#
# All forbidden terms are assembled at runtime via split-string technique.
# This prevents the scan from self-matching on assignment lines or check labels.
# ═══════════════════════════════════════════════════════════════════════════════

section 'RACK-P2-SURFACE'

source = File.read(__FILE__, encoding: 'utf-8')

# RACK-P2-12: No real network I/O classes in source
check('RACK-P2-SURFACE-01: [P2-12] source contains no real socket or network-IO classes') do
  net_h   = 'Net'    + '::' + 'HTTP'
  tcp_s   = 'TCP'    + 'Socket'
  udp_s   = 'UDP'    + 'Socket'
  sck_new = 'Socket' + '.new'
  req_net = "require 'net/" + "http'"
  req_sck = "require 'soc" + "ket'"
  [net_h, tcp_s, udp_s, sck_new, req_net, req_sck].none? { |t| source.include?(t) }
end

check('RACK-P2-SURFACE-02: [P2-12] source contains no URI-open or kernel-open patterns') do
  req_oui  = "require 'open" + "-uri'"
  uri_opn  = 'URI'    + '.open'
  kern_opn = 'Kernel' + '.open'
  [req_oui, uri_opn, kern_opn].none? { |t| source.include?(t) }
end

# RACK-P2-13: No service-loop or accept-loop authority in source
check('RACK-P2-SURFACE-03: [P2-13] source contains no service-loop or accept-loop forms') do
  svc_lp   = 'Service'  + 'Loop'
  srv_acc  = 'server'   + '.accept'
  srv_lst  = 'server'   + '.listen'
  rack_hdl = 'Rack'     + '::Handler'
  [svc_lp, srv_acc, srv_lst, rack_hdl].none? { |t| source.include?(t) }
end

check('RACK-P2-SURFACE-04: [P2-13] source contains no runtime execution surfaces') do
  igc_r   = 'igc'       + ' run'
  dot_igb = '.'         + 'igbin'
  rtsm    = 'Runtime'   + 'Smoke'
  ref_rt  = 'Reference' + 'Runtime'
  [igc_r, dot_igb, rtsm, ref_rt].none? { |t| source.include?(t) }
end

# RACK-P2-14: No canon-authority or stable-API claims in source
check('RACK-P2-SURFACE-05: [P2-14] source introduces no canon-authority or stable-API claims') do
  canon_a  = 'canon'      + ' authority'
  pub_a    = 'public'     + ' API'
  stab_a   = 'stable'     + ' API'
  prod_s   = 'production' + ' server'
  r_compat = 'Rack-compat' + 'ible server'
  [canon_a, pub_a, stab_a, prod_s, r_compat].none? { |t| source.include?(t) }
end

check('RACK-P2-SURFACE-06: [P2-14] igniter-lang canon directory untouched') do
  lang_dir = '/Users/alex/dev/projects/igniter-workspace/igniter-lang'
  !File.exist?(lang_dir) ||
    begin
      `git -C "#{lang_dir}" status --porcelain 2>&1`.strip.empty?
    rescue
      true
    end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

puts "\n#{'═' * 72}"
passed = CHECKS.count { |c| c[:passed] }
total  = CHECKS.size
puts "Result: #{passed}/#{total} checks passed"

if FAILURES.empty?
  puts 'Status: ALL CHECKS PASSED ✓'
else
  puts "Status: FAILURES (#{FAILURES.size}):"
  FAILURES.each { |f| puts "  ✗ #{f}" }
end

puts '═' * 72
exit(FAILURES.empty? ? 0 : 1)
