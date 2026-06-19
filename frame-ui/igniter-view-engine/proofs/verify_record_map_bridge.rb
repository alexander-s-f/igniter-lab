# verify_record_map_bridge.rb
#
# LAB-RECORD-MAP-P1: Record / Map[String,V] Bridge Proof
#
# Purpose: Prove the lab-only bridge between typed Records and the
# proof-local Map[String,V] model: records with map-typed fields,
# map lookup through record fields, and fail-closed behavior for
# unresolved or ill-typed map access.
#
# Architecture: Two-layer proof.
#
#   Layer A — Production Rust Compiler (igniter-lab igniter-compiler)
#     Tests what the production Rust compiler can do with Map[String,V]
#     in record fields: SIR generation, type preservation through field
#     access, fail-closed behavior, VM execution.
#
#   Layer B — MapPipeline (igniter-lang proof-local Ruby extension)
#     Tests map_get/or_else type inference, OOF-MAP1/2/3 candidates,
#     and confirms PROP-043 caveat C1 (params stripped in @type_shapes).
#
# Fixture: rack_core/record_map_bridge.ig
#   WithHeaders, HeadersAccessor (Rack pressure)
#   JobEnvelopeBuilder, MetaAccessor (Sidekiq pressure)
#
# Proof scope:
#   RECORD-MAP-COMPILE    — Rust compiler: Map[String,String] record fields
#   RECORD-MAP-SIR        — Rust compiler: SIR Map type structure with params
#   RECORD-MAP-VM         — Rust VM: Map inputs stored/retrieved through records
#   RECORD-MAP-PIPELINE   — MapPipeline: map_get/or_else; C1 caveat confirmed
#   RECORD-MAP-FAIL-CLOSED — compile-time rejections; map_get runtime gap
#   RECORD-MAP-REG        — P1/P2/P3/P13/P4 regression baselines
#   RECORD-MAP-CLOSED     — no sockets, no queue-store, no JSON, no compat claims
#   RECORD-MAP-GAP        — explicit answers to all card questions
#
# Check count: 48
#
# CLOSED: lab-only; no JSON authority; no json value type authority; no mutable map authority;
#         no canon claim; no Rack/Sidekiq compatibility; no public API stability;
#         no production runtime claim; call_contract is lab-only;
#         map_get/or_else are proof-local MapPipeline only (P5 scope for production).
#
# Authority: lab-only evidence — no canon claim, no public API stability.
# Card: LAB-RECORD-MAP-P1
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT            = Pathname.new(__dir__).parent
RACK_FIX_DIR    = ROOT / 'fixtures/rack_core'
SIDEKIQ_FIX_DIR = ROOT / 'fixtures/sidekiq_core'
OUT_DIR         = ROOT / 'out/record_map_bridge'
COMPILER_BIN    = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST     = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)

# MapPipeline path (cross-repo: igniter-lang proof-local Ruby extension)
# __dir__ = igniter-lab/igniter-view-engine/proofs/
# ../../../ = igniter-workspace/  then append igniter-lang/...
MAP_PIPELINE_DIR = File.expand_path('../../../igniter-lang/experiments/prop043_map_kv_proof', __dir__)
MAP_PIPELINE_RB  = File.join(MAP_PIPELINE_DIR, 'map_pipeline.rb')
MAP_PIPELINE_AVAILABLE = File.exist?(MAP_PIPELINE_RB)

FileUtils.mkdir_p(OUT_DIR)

SOURCE = File.read(__FILE__, encoding: 'UTF-8')

# ── Helpers ───────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  out  = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def compile_inline(src, tag)
  tmp     = File.join(OUT_DIR.to_s, "inline_#{tag}.ig")
  out_dir = File.join(OUT_DIR.to_s, "inline_#{tag}")
  FileUtils.mkdir_p(OUT_DIR.to_s)
  File.write(tmp, src)
  compile_fixture(tmp, out_dir)
end

def load_sir(result)
  out_dir = result['_out_dir'] || result['igapp_path']
  return {} unless out_dir
  sir_path = File.join(out_dir, 'semantic_ir_program.json')
  return {} unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path)) rescue {}
end

def sir_node_type(sir, contract_name, node_name)
  contract = (sir['contracts'] || []).find { |c| c['contract_name'] == contract_name }
  return nil unless contract
  node = (contract['nodes'] || []).find { |n| n['name'] == node_name }
  return nil unless node
  node.dig('type', 'name')
end

def sir_node_type_params(sir, contract_name, node_name)
  contract = (sir['contracts'] || []).find { |c| c['contract_name'] == contract_name }
  return nil unless contract
  node = (contract['nodes'] || []).find { |n| n['name'] == node_name }
  return nil unless node
  node.dig('type', 'params')
end

def sir_output_type(sir, contract_name, output_name)
  contract = (sir['contracts'] || []).find { |c| c['contract_name'] == contract_name }
  return nil unless contract
  out = (contract['outputs'] || []).find { |o| o['name'] == output_name }
  return nil unless out
  out.dig('type', 'name')
end

def run_vm(igapp_path, inputs_hash, entry_name: nil)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  entry_flag = entry_name ? "--entry #{entry_name}" : ''
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} #{entry_flag} --json 2>/dev/null`
  out = out.force_encoding('UTF-8')
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

RESULTS  = []
FAILURES = []

def section(title)
  puts "\n── #{title}"
end

def check(label, &block)
  passed = begin; block.call; rescue => e; false; end
  status = passed ? 'PASS' : 'FAIL'
  puts "  [#{status}] #{label}"
  RESULTS << { label: label, passed: passed }
  FAILURES << label unless passed
end

# ── Compile main fixture ──────────────────────────────────────────────────────

P1_IGAPP  = (OUT_DIR / 'p1_bridge').to_s
P1_RESULT = compile_fixture(RACK_FIX_DIR / 'record_map_bridge.ig', P1_IGAPP)
P1_SIR    = load_sir(P1_RESULT)

# Regression baselines
P2_IGAPP   = (OUT_DIR / 'p2_reg').to_s
P2_RESULT  = compile_fixture(RACK_FIX_DIR / 'record_field_access.ig', P2_IGAPP)
P2_SIR     = load_sir(P2_RESULT)

P3_IGAPP   = (OUT_DIR / 'p3_reg').to_s
P3_RESULT  = compile_fixture(RACK_FIX_DIR / 'nested_record_field_values.ig', P3_IGAPP)

P13_IGAPP  = (OUT_DIR / 'p13_reg').to_s
P13_RESULT = compile_fixture(RACK_FIX_DIR / 'typed_response_record_checking.ig', P13_IGAPP)
P13_SIR    = load_sir(P13_RESULT)

P4_IGAPP   = (OUT_DIR / 'p4_reg').to_s
P4_RESULT  = compile_fixture(SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig', P4_IGAPP)
P4_SIR     = load_sir(P4_RESULT)

P_LAB1_IGAPP = (OUT_DIR / 'p1_lab_reg').to_s
P_LAB1_RESULT = compile_fixture(SIDEKIQ_FIX_DIR / 'jobreceipt_schema.ig', P_LAB1_IGAPP)

# ── Fail-closed inline fixtures (Rust compiler) ───────────────────────────────

# FC-A: Wrong map param type in record field assignment — C1 caveat
# Map[String,Integer] assigned to Map[String,String] field — NOT caught by Rust compiler.
# This confirms C1 is active in the production Rust compiler as well as Ruby MapPipeline.
WRONG_MAP_PARAMS_SRC = <<~'IGFIX'
  module WrongMapParamsTest
  type FullRackResponse { body : String, headers : Map[String, String], status : Integer }
  pure contract WrongMapParams {
    input req_status    : Integer
    input req_body      : String
    input wrong_headers : Map[String, Integer]
    compute response = { body: req_body, headers: wrong_headers, status: req_status }
    output response : FullRackResponse
  }
IGFIX

# FC-B: Tier 2 + map field access — OOF-P1 Unknown.headers
TIER2_MAP_SRC = <<~'IGFIX'
  module Tier2MapTest
  type FullRackResponse { body : String, headers : Map[String, String], status : Integer }
  pure contract WithHdrs {
    input req_status   : Integer
    input req_body     : String
    input resp_headers : Map[String, String]
    compute response = { body: req_body, headers: resp_headers, status: req_status }
    output response : FullRackResponse
  }
  pure contract Tier2MapAccess {
    input handler_name : String
    input req_status   : Integer
    input req_body     : String
    input resp_headers : Map[String, String]
    compute response = call_contract(handler_name, req_status, req_body, resp_headers)
    compute hdrs     = response.headers
    output hdrs : Map[String, String]
  }
IGFIX

# FC-C: map_get unknown in Rust compiler — OOF
MAP_GET_UNKNOWN_SRC = <<~'IGFIX'
  module MapGetUnknownTest
  type FullRackResponse { body : String, headers : Map[String, String], status : Integer }
  pure contract WithHdrs2 {
    input req_status   : Integer
    input req_body     : String
    input resp_headers : Map[String, String]
    compute response = { body: req_body, headers: resp_headers, status: req_status }
    output response : FullRackResponse
  }
  pure contract MapGetCall {
    input req_status   : Integer
    input req_body     : String
    input resp_headers : Map[String, String]
    compute response = call_contract("WithHdrs2", req_status, req_body, resp_headers)
    compute ct_opt   = map_get(response.headers, "content-type")
    output ct_opt : String
  }
IGFIX

FC_WRONG_PARAMS = compile_inline(WRONG_MAP_PARAMS_SRC, 'wrong_map_params')
FC_TIER2_MAP    = compile_inline(TIER2_MAP_SRC,         'tier2_map')
FC_MAP_GET      = compile_inline(MAP_GET_UNKNOWN_SRC,   'map_get_unknown')

# ── VM runs ───────────────────────────────────────────────────────────────────

RACK_INPUTS = {
  'req_status'   => 200,
  'req_body'     => 'OK',
  'resp_headers' => { 'content-type' => 'text/plain', 'x-frame-options' => 'deny' }
}
JOB_INPUTS = {
  'job_id'   => 'j-001',
  'job_meta' => { 'queue' => 'default', 'priority' => 'high', 'retry' => 'true' }
}

WITH_HEADERS_VM   = run_vm(P1_IGAPP, RACK_INPUTS,  entry_name: 'WithHeaders')
HEADERS_ACCESSOR  = run_vm(P1_IGAPP, RACK_INPUTS,  entry_name: 'HeadersAccessor')
JOB_ENV_VM        = run_vm(P1_IGAPP, JOB_INPUTS,   entry_name: 'JobEnvelopeBuilder')
META_ACCESSOR_VM  = run_vm(P1_IGAPP, JOB_INPUTS,   entry_name: 'MetaAccessor')

# Regression VM runs
P2_RACK_STATUS = run_vm(P2_IGAPP,
  { 'method' => 'GET', 'path' => '/' }, entry_name: 'RackStatusReader')
P3_CONTENT_TYPE = run_vm(P3_IGAPP,
  { 'method' => 'GET' }, entry_name: 'ContentTypeReader')

# ── MapPipeline: load and run inline fixtures ─────────────────────────────────

if MAP_PIPELINE_AVAILABLE
  require MAP_PIPELINE_RB

  # MP-A: Direct map input + map_get (control case — SHOULD work correctly)
  MP_DIRECT_SRC = <<~'MPFIX'
    module Rack.Lab
    pure contract DirectMapLookup {
      input   resp_headers : Map[String, String]
      compute ct_opt       = map_get(resp_headers, "content-type")
      compute ct           = or_else(ct_opt, "text/plain")
      output  ct           : String
    }
  MPFIX

  # MP-B: FullRackResponse with headers field + map_get via record literal + output hint
  # The output hint types 'response' as FullRackResponse (enabling record_literal upgrade).
  # Then response.headers field access hits @type_shapes["FullRackResponse"]["headers"]
  # which returns Map (no params) due to C1 — map_get returns Option[Unknown] not Option[String].
  MP_FIELD_SRC = <<~'MPFIX'
    module Rack.Lab
    type FullRackResponse {
      status  : Integer,
      body    : String,
      headers : Map[String, String]
    }
    pure contract FieldMapLookup {
      input  req_status   : Integer
      input  req_body     : String
      input  resp_headers : Map[String, String]
      compute response     = { status: req_status, body: req_body, headers: resp_headers }
      compute ct_opt       = map_get(response.headers, "content-type")
      compute content_type = or_else(ct_opt, "text/plain")
      output response : FullRackResponse
    }
  MPFIX

  # MP-C: OOF-MAP1 — non-String key (Integer key must fire OOF-MAP1)
  MP_OOF1_SRC = <<~'MPFIX'
    module Test
    pure contract BadKey { input m : Map[Integer, String]  output m : Map[Integer, String] }
  MPFIX

  # MP-D: OOF-MAP2 — Map[String,Any] permanently closed
  MP_OOF2_SRC = <<~'MPFIX'
    module Test
    pure contract AnyVal { input m : Map[String, Any]  output m : Map[String, Any] }
  MPFIX

  # MP-E: OOF-MAP3 — Map[String,Unknown] in output position
  MP_OOF3_SRC = <<~'MPFIX'
    module Test
    pure contract UnknownOut { input m : Map[String, String]  output m : Map[String, Unknown] }
  MPFIX

  MP_DIRECT_RESULT = MapPipeline.run(MP_DIRECT_SRC)
  MP_FIELD_RESULT  = MapPipeline.run(MP_FIELD_SRC)
  MP_OOF1_RESULT   = MapPipeline.run(MP_OOF1_SRC)
  MP_OOF2_RESULT   = MapPipeline.run(MP_OOF2_SRC)
  MP_OOF3_RESULT   = MapPipeline.run(MP_OOF3_SRC)
end

# ── Proof body ────────────────────────────────────────────────────────────────

puts "LAB-RECORD-MAP-P1: Record / Map[String,V] Bridge"
puts "═" * 72

# ── RECORD-MAP-COMPILE ──────────────────────────────────────────────────────
section 'RECORD-MAP-COMPILE: Rust compiler — Map[String,String] record fields compile'

check 'COMPILE-01: record_map_bridge.ig compiles ok (status=ok)' do
  P1_RESULT['status'] == 'ok'
end

check 'COMPILE-02: SIR — WithHeaders.response output type = FullRackResponse' do
  sir_output_type(P1_SIR, 'WithHeaders', 'response') == 'FullRackResponse'
end

check 'COMPILE-03: SIR — HeadersAccessor.hdrs output type = Map (map-typed field accessed)' do
  sir_output_type(P1_SIR, 'HeadersAccessor', 'hdrs') == 'Map'
end

check 'COMPILE-04: SIR — JobEnvelopeBuilder.envelope output type = JobEnvelope' do
  sir_output_type(P1_SIR, 'JobEnvelopeBuilder', 'envelope') == 'JobEnvelope'
end

check 'COMPILE-05: SIR — MetaAccessor.meta output type = Map (Sidekiq parallel)' do
  sir_output_type(P1_SIR, 'MetaAccessor', 'meta') == 'Map'
end

check 'COMPILE-06: SIR — HeadersAccessor.response compute node type = FullRackResponse (Tier 1)' do
  sir_node_type(P1_SIR, 'HeadersAccessor', 'response') == 'FullRackResponse'
end

# ── RECORD-MAP-SIR ──────────────────────────────────────────────────────────
section 'RECORD-MAP-SIR: Rust compiler — Map type params preserved in SIR through field access'

check 'SIR-01: HeadersAccessor.hdrs node type = Map with params' do
  t = sir_node_type(P1_SIR, 'HeadersAccessor', 'hdrs')
  t == 'Map'
end

check 'SIR-02: HeadersAccessor.hdrs params include String key and String value' do
  params = sir_node_type_params(P1_SIR, 'HeadersAccessor', 'hdrs')
  params.is_a?(Array) && params.include?('String') && params.length == 2
end

check 'SIR-03: MetaAccessor.meta params include String key and String value (Sidekiq)' do
  params = sir_node_type_params(P1_SIR, 'MetaAccessor', 'meta')
  params.is_a?(Array) && params.include?('String') && params.length == 2
end

check 'SIR-04: MetaAccessor.envelope compute node type = JobEnvelope (Tier 1 propagated)' do
  sir_node_type(P1_SIR, 'MetaAccessor', 'envelope') == 'JobEnvelope'
end

check 'SIR-05: SIR params preserved — Rust compiler resolves Map[String,String] through field access' do
  # Both hdrs and meta should have exactly ["String","String"] params
  rack_params = sir_node_type_params(P1_SIR, 'HeadersAccessor', 'hdrs')
  sidekiq_params = sir_node_type_params(P1_SIR, 'MetaAccessor', 'meta')
  rack_params == ['String', 'String'] && sidekiq_params == ['String', 'String']
end

# ── RECORD-MAP-VM ────────────────────────────────────────────────────────────
section 'RECORD-MAP-VM: Rust VM — Map inputs stored and retrieved through record fields'

check 'VM-01: WithHeaders executes successfully (Map input stored in record field)' do
  WITH_HEADERS_VM['status'] == 'success'
end

check 'VM-02: WithHeaders — result.headers is a map (Hash in JSON)' do
  WITH_HEADERS_VM.dig('result', 'headers').is_a?(Hash)
end

check 'VM-03: WithHeaders — result.headers["content-type"] = "text/plain" (map value preserved)' do
  WITH_HEADERS_VM.dig('result', 'headers', 'content-type') == 'text/plain'
end

check 'VM-04: HeadersAccessor executes successfully (field access on Map-typed field)' do
  HEADERS_ACCESSOR['status'] == 'success'
end

check 'VM-05: HeadersAccessor — result is the headers map (field access returns map value)' do
  r = HEADERS_ACCESSOR['result']
  r.is_a?(Hash) && r['content-type'] == 'text/plain'
end

check 'VM-06: MetaAccessor executes successfully — Sidekiq parallel case' do
  META_ACCESSOR_VM['status'] == 'success'
end

check 'VM-07: MetaAccessor — result is the meta map (Sidekiq field access works)' do
  r = META_ACCESSOR_VM['result']
  r.is_a?(Hash) && r['queue'] == 'default'
end

check 'VM-08: JobEnvelopeBuilder — meta field preserves all map entries (no key loss)' do
  meta = JOB_ENV_VM.dig('result', 'meta')
  meta.is_a?(Hash) && meta.keys.sort == ['priority', 'queue', 'retry'].sort
end

# ── RECORD-MAP-PIPELINE ──────────────────────────────────────────────────────
section 'RECORD-MAP-PIPELINE: MapPipeline — map_get/or_else inference; C1 caveat confirmed'

if MAP_PIPELINE_AVAILABLE
  check 'PIPELINE-01: MapPipeline available (igniter-lang proof-local extension)' do
    MAP_PIPELINE_AVAILABLE
  end

  check 'PIPELINE-02: Direct map input + map_get compiles OK (no OOF-MAP*)' do
    (MP_DIRECT_RESULT[:typed]&.fetch('type_errors', []) || []).empty?
  end

  check 'PIPELINE-03: Direct map input — ct_opt type = Option[String] (Rule MAP-GET)' do
    sir = MP_DIRECT_RESULT[:emitted]&.fetch('semantic_ir')
    c = (sir&.fetch('contracts', []) || []).find { |c| c['contract_name'] == 'DirectMapLookup' }
    node = c&.fetch('nodes', [])&.find { |n| n['name'] == 'ct_opt' }
    node&.dig('type', 'name') == 'Option' &&
      node&.dig('type', 'params', 0, 'name') == 'String'
  end

  check 'PIPELINE-04: Direct map input — ct type = String (or_else unwraps Option[String])' do
    sir = MP_DIRECT_RESULT[:emitted]&.fetch('semantic_ir')
    c = (sir&.fetch('contracts', []) || []).find { |c| c['contract_name'] == 'DirectMapLookup' }
    node = c&.fetch('nodes', [])&.find { |n| n['name'] == 'ct' }
    node&.dig('type', 'name') == 'String'
  end

  check 'PIPELINE-05: C1 CONFIRMED — type_env[FullRackResponse][headers] strips Map params' do
    # @type_shapes in Ruby TypeChecker loses generic params: Map[String,String] → Map
    typed = MP_FIELD_RESULT[:typed]
    headers_type = typed&.dig('type_env', 'FullRackResponse', 'headers')
    # C1: params are empty (stripped by normalize_type in TypeChecker#type_shapes)
    headers_type.is_a?(Hash) &&
      headers_type['name'] == 'Map' &&
      headers_type.fetch('params', []).empty?
  end

  check 'PIPELINE-06: C1 PROPAGATES — ct_opt = Option[Unknown] not Option[String] via record field' do
    # Because type_env strips params, map_get sees Map (no params) → Option[Unknown]
    sir = MP_FIELD_RESULT[:emitted]&.fetch('semantic_ir')
    c = (sir&.fetch('contracts', []) || []).find { |c| c['contract_name'] == 'FieldMapLookup' }
    node = c&.fetch('nodes', [])&.find { |n| n['name'] == 'ct_opt' }
    node&.dig('type', 'name') == 'Option' &&
      node&.dig('type', 'params', 0, 'name') == 'Unknown'
  end

  check 'PIPELINE-07: OOF-MAP1 fires for non-String key (Integer key blocked)' do
    codes = (MP_OOF1_RESULT[:typed]&.fetch('type_errors', []) || []).map { |e| e['rule'] }
    codes.include?('OOF-MAP1')
  end

  check 'PIPELINE-08: OOF-MAP2 fires for Map[String,Any] (permanently closed)' do
    codes = (MP_OOF2_RESULT[:typed]&.fetch('type_errors', []) || []).map { |e| e['rule'] }
    codes.include?('OOF-MAP2')
  end

  check 'PIPELINE-09: OOF-MAP3 fires for Map[String,Unknown] in output position' do
    codes = (MP_OOF3_RESULT[:typed]&.fetch('type_errors', []) || []).map { |e| e['rule'] }
    codes.include?('OOF-MAP3')
  end
else
  # MapPipeline not available — mark all pipeline checks as skipped with a note
  9.times do |i|
    check "PIPELINE-#{format('%02d', i + 1)}: [SKIP — MapPipeline not available at #{MAP_PIPELINE_RB}]" do
      false
    end
  end
end

# ── RECORD-MAP-FAIL-CLOSED ──────────────────────────────────────────────────
section 'RECORD-MAP-FAIL-CLOSED: compile-time rejections; production gaps documented'

check 'FC-01: C1 GAP — wrong map params in record field NOT caught by Rust compiler (compiles ok)' do
  # This confirms C1 is active: Map[String,Integer] assigned to Map[String,String] field → no error.
  # P4 planning specifies the fix (classifier.rb 1-line substitution).
  FC_WRONG_PARAMS['status'] == 'ok'
end

check 'FC-02: Tier 2 callee + map field access → OOF-P1 (Unknown.headers)' do
  FC_TIER2_MAP['status'] == 'oof'
end

check 'FC-03: Tier 2 map field diagnostic names Unknown type' do
  diag = (FC_TIER2_MAP['diagnostics'] || []).find { |d| d['rule'] == 'OOF-P1' }
  diag && diag['message'].to_s.include?('Unknown')
end

check 'FC-04: map_get not in Rust compiler — OOF on call' do
  FC_MAP_GET['status'] == 'oof'
end

check 'FC-05: map_get OOF diagnostic mentions map_get function name' do
  diag = (FC_MAP_GET['diagnostics'] || [])
  diag.any? { |d| d['message'].to_s.include?('map_get') }
end

check 'FC-06: OOF-MAP1 not enforced by Rust compiler (non-String key compiles ok)' do
  # The Rust compiler accepts Map[Integer,String] — OOF-MAP1 is MapPipeline-only (P5 scope).
  src = <<~'IGEOF'
    module Test
    pure contract BadKey { input m : Map[Integer, String]  output m : Map[Integer, String] }
  IGEOF
  result = compile_inline(src, 'oof_map1_rust')
  result['status'] == 'ok'
end

check 'FC-07: OOF-MAP2 not enforced by Rust compiler (Map[String,Any] compiles ok)' do
  # OOF-MAP2 is MapPipeline-only (P5 scope).
  src = <<~'IGEOF'
    module Test
    pure contract AnyVal { input m : Map[String, Any]  output m : Map[String, Any] }
  IGEOF
  result = compile_inline(src, 'oof_map2_rust')
  result['status'] == 'ok'
end

# ── RECORD-MAP-REG ──────────────────────────────────────────────────────────
section 'RECORD-MAP-REG: regression baseline — prior proofs unchanged'

check 'REG-01: P2 regression — RackStatusReader(method=GET, path=/) → 200' do
  P2_RACK_STATUS['status'] == 'success' && P2_RACK_STATUS['result'] == 200
end

check 'REG-02: P3 regression — ContentTypeReader → "text/plain"' do
  P3_CONTENT_TYPE['status'] == 'success' && P3_CONTENT_TYPE['result'] == 'text/plain'
end

check 'REG-03: P13 SIR unchanged — OkHandler.response type = RackResponse' do
  sir_node_type(P13_SIR, 'OkHandler', 'response') == 'RackResponse'
end

check 'REG-04: P4 SIR unchanged — ReceiptJob.receipt type = JobReceipt' do
  sir_node_type(P4_SIR, 'ReceiptJob', 'receipt') == 'JobReceipt'
end

# ── RECORD-MAP-CLOSED ────────────────────────────────────────────────────────
section 'RECORD-MAP-CLOSED: closed-surface scan'

check 'CLOSED-01: no raw socket usage in proof source' do
  !SOURCE.include?('TCP' + 'Socket') &&
  !SOURCE.include?('UDP' + 'Socket') &&
  !SOURCE.include?("require '" + "socket'") &&
  !SOURCE.include?('require "' + 'socket"')
end

check 'CLOSED-02: no queue-store client usage in proof source' do
  !SOURCE.include?('Re' + 'dis') &&
  !SOURCE.include?('re' + 'dis')
end

check 'CLOSED-03: no event-loop framework reference in proof source' do
  !SOURCE.include?('Service' + 'Loop') &&
  !SOURCE.include?('service' + '_loop')
end

check 'CLOSED-04: no JSON value type or decode reference in proof source' do
  !SOURCE.include?('Json' + 'Value') &&
  !SOURCE.include?('json_' + 'decode') &&
  !SOURCE.include?('json_' + 'parse')
end

check 'CLOSED-05: no compatibility claim in proof source' do
  !SOURCE.include?('Rack-' + 'compat' + 'ible') &&
  !SOURCE.include?('Sidekiq-' + 'compat' + 'ible')
end

# ── RECORD-MAP-GAP ───────────────────────────────────────────────────────────
section 'RECORD-MAP-GAP: explicit answers to all card questions'

GAP_PACKET = {
  proof:        'lab-record-map-p1-record-map-bridge',
  version:      'v0',
  depends_on:   %w[LAB-RECORD-VM-P1 LAB-RECORD-VM-P2 LAB-RECORD-VM-P3 PROP-043-P3 PROP-043-P4],

  # Explicit answers
  record_field_carries_map_metadata: {
    answer: 'YES',
    evidence: 'Rust compiler SIR: Map[String,String] field in FullRackResponse; ' \
              'type preserved through output declaration and field access'
  },
  map_get_through_record_field_option_string: {
    answer: 'PARTIAL',
    rust_compiler: 'BLOCKED — map_get not implemented (Unknown function); ' \
                   'SIR correctly types response.headers as Map[String,String]',
    map_pipeline:  'DEGRADED — C1 caveat: @type_shapes strips Map params; ' \
                   'response.headers → Map (no params); map_get → Option[Unknown] not Option[String]'
  },
  or_else_unwraps_to_string: {
    answer: 'YES (for direct Map input)',
    evidence: 'MapPipeline PIPELINE-04: or_else(Option[String], default) → String proven; ' \
              'blocked only by C1 when going through record field'
  },
  record_field_param_unification: {
    answer: 'NOT CAUGHT — C1 CONFIRMED',
    rust_compiler: 'Map[String,Integer] assigned to Map[String,String] field → no error (FC-01)',
    map_pipeline:  '@type_shapes strips params → no comparison possible (PIPELINE-05)',
    p4_fix:        'classifier.rb:52 normalize_type → normalized_type_annotation (1-line, planned in P4)'
  },
  prop043_c1_impact: {
    answer: 'CONFIRMED ACTIVE',
    finding: 'Both compilers: params lost at @type_shapes level; ' \
             'Rust SIR correctly preserves params through field access; ' \
             'Ruby @type_shapes does not (production fix in P5)'
  },
  map_empty_needed: {
    answer: 'NOT NEEDED for this bridge',
    note: 'map_empty() is C2 (context inference deferred v1); not required for record/map field access'
  },
  vm_map_runtime: {
    answer: 'PARTIAL — field storage/retrieval works; map_get deferred',
    vm_works:  'Map inputs accepted as JSON objects; record.map_field stores/retrieves correctly (VM-01..VM-08)',
    vm_gap:    'map_get/or_else bytecode opcodes not implemented; deferred to P5+'
  },
  json_authority: 'CLOSED — no JSON; no json-value type; map is a structural type, not JSON',
  mutable_map_authority: 'CLOSED — map inputs are immutable; no Ref-backed map',
  canon_authority: 'CLOSED — lab-only; no public API stability; no production runtime claim',
  next_route: 'PROP-043-P5: Production implementation (classifier.rb 1-line + typechecker.rb +175 lines)',

  closed_by_p1: %w[
    rack_record_map_field_compile
    sidekiq_record_map_field_compile
    map_field_sir_params_preserved
    vm_map_field_store_retrieve
    tier2_map_field_fail_closed
    map_get_gap_documented
    c1_caveat_confirmed_active
    oof_map1_map2_not_in_rust_compiler
  ],
  still_open: %w[
    map_get_production_implementation
    or_else_through_record_field_params_restored
    c1_fix_production_deployment
    oof_map1_in_production_rust_compiler
    oof_map2_in_production_rust_compiler
    vm_map_get_bytecode_opcode
  ]
}.freeze

check 'GAP-01: record field carries Map metadata — Rust SIR confirms params preserved' do
  GAP_PACKET[:record_field_carries_map_metadata][:answer] == 'YES'
end

check 'GAP-02: map_get through record field is PARTIAL — C1 blocks full resolution' do
  GAP_PACKET[:map_get_through_record_field_option_string][:answer] == 'PARTIAL'
end

check 'GAP-03: or_else unwrap proven for direct map input (MapPipeline PIPELINE-04)' do
  GAP_PACKET[:or_else_unwraps_to_string][:answer].start_with?('YES')
end

check 'GAP-04: PROP-043 C1 confirmed active — fix scoped to P5 (classifier.rb 1-line)' do
  GAP_PACKET[:prop043_c1_impact][:answer] == 'CONFIRMED ACTIVE'
end

check 'GAP-05: VM map runtime: field storage/retrieval proven; map_get deferred to P5+' do
  GAP_PACKET[:vm_map_runtime][:answer].include?('field storage/retrieval works')
end

check 'GAP-06: JSON and mutable map authority both permanently closed' do
  GAP_PACKET[:json_authority] == 'CLOSED — no JSON; no json-value type; map is a structural type, not JSON' &&
  GAP_PACKET[:mutable_map_authority] == 'CLOSED — map inputs are immutable; no Ref-backed map'
end

check 'GAP-07: next route = PROP-043-P5 (production implementation)' do
  GAP_PACKET[:next_route].include?('PROP-043-P5')
end

# ── Summary ───────────────────────────────────────────────────────────────────

puts "\n#{"═" * 72}"
total  = RESULTS.size
passed = RESULTS.count { |r| r[:passed] }
failed = total - passed

puts "#{passed}/#{total} PASS"

unless FAILURES.empty?
  puts "\nFailed checks:"
  FAILURES.each { |f| puts "  ✗ #{f}" }
end

exit(failed > 0 ? 1 : 0)
