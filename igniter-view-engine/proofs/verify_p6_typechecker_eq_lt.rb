# verify_p6_typechecker_eq_lt.rb
#
# LAB-RACK-P6: TypeChecker == and < Alignment
#
# Purpose: Prove that the TypeChecker now accepts == for compatible primitive
# types (String/Text, Integer, Bool) and < for Integer only; and that these
# operators compile + execute end-to-end on the lab VM.
#
# TypeChecker change (LAB-RACK-P6):
#   + "==" arm: accepts (String,String),(Text,Text),(String,Text),(Text,String),
#               (Integer,Integer),(Bool,Bool). Rejects incompatible pairs
#               with OOF-TY0. Returns Bool.
#   + "<"  arm: accepts (Integer,Integer) only. Rejects String/Text/Bool
#               with OOF-TY0. Returns Bool.
#   No VM change needed: binary_op handler already dispatches "==" and "<".
#   No emitter change needed: binary_op passes through op field as-is.
#
# Proof scope:
#   P6-TC     — TypeChecker accepts/rejects == and < correctly
#   P6-IR     — SemanticIR shape contains binary_op with op=="==" nodes
#   P6-VM     — 5 exact-route cases execute on VM with correct results
#   P6-LT     — Integer < Integer executes on VM; correct true/false values
#   P6-REG    — P5 route_dispatch.ig and path_param_extract.ig still green
#   P6-CLOSED — closed-surface scan
#   P6-GAP    — gap packet: eq/lt closed; vm_entrypoint + ContractRef open
#
# Proof axiom: PASS means the stated property holds.
# CLOSED: lab-only, no canon grammar edits, no real TCP/socket, no accept-loop,
#         no ContractRef runtime dispatch, no VM entrypoint selector,
#         no stable/public-API, no rack-compat claims.
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Card: LAB-RACK-P6
# Date: 2026-06-08

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p6_tc_eq_lt'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
TC_SRC       = File.expand_path('../../igniter-compiler/src/typechecker.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

# ── Helpers ────────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def run_vm(igapp_path, inputs_hash)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} --json 2>/dev/null`
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

def read_sir(igapp_path)
  files = Dir.glob("#{igapp_path}/*.json") + Dir.glob("#{igapp_path}/**/*.json")
  files.each do |f|
    data = JSON.parse(File.read(f)) rescue nil
    return data if data&.dig('kind') == 'semantic_ir_program'
  end
  nil
end

RESULTS  = []
FAILURES = []

def check(label, &block)
  result = block.call
  status = result ? 'PASS' : 'FAIL'
  RESULTS  << { label: label, passed: result }
  FAILURES << label unless result
  puts "  #{status}  #{label}"
rescue => e
  RESULTS  << { label: label, passed: false }
  FAILURES << label
  puts "  ERROR #{label} — #{e.class}: #{e.message.lines.first.chomp}"
end

def section(title)
  puts "\n── #{title} #{('─' * [0, 72 - title.length].max)}"
end

# ── Compile all fixtures ───────────────────────────────────────────────────────
puts "\n[*] Compiling P6 fixtures..."
EXACT_RESULT    = compile_fixture(FIXTURE_DIR / 'route_dispatch_exact.ig',  OUT_DIR / 'exact.igapp')
LT_RESULT       = compile_fixture(FIXTURE_DIR / 'lt_integer_valid.ig',      OUT_DIR / 'lt.igapp')
EQ_MM_RESULT    = compile_fixture(FIXTURE_DIR / 'eq_type_mismatch.ig',      OUT_DIR / 'eq_mismatch.igapp')
LT_REJ_RESULT   = compile_fixture(FIXTURE_DIR / 'lt_string_reject.ig',      OUT_DIR / 'lt_reject.igapp')
# Regression fixtures from P5
ROUTE_RESULT    = compile_fixture(FIXTURE_DIR / 'route_dispatch.ig',         OUT_DIR / 'route.igapp')
PARAM_RESULT    = compile_fixture(FIXTURE_DIR / 'path_param_extract.ig',     OUT_DIR / 'param.igapp')

# ── Run VM execution cases ─────────────────────────────────────────────────────
puts "[*] Running VM cases..."

def exact_vm(method, path)
  run_vm(
    File.join(OUT_DIR.to_s, 'exact.igapp'),
    { 'method' => method, 'path' => path }
  )
end

def lt_vm(n)
  run_vm(File.join(OUT_DIR.to_s, 'lt.igapp'), { 'n' => n })
end

def route_vm(method, path)
  run_vm(File.join(OUT_DIR.to_s, 'route.igapp'), { 'method' => method, 'path' => path })
end

def param_vm(path)
  run_vm(File.join(OUT_DIR.to_s, 'param.igapp'), { 'path' => path })
end

EXACT_GET_ROOT    = exact_vm('GET',  '/')
EXACT_GET_ITEM    = exact_vm('GET',  '/articles/42')
EXACT_POST_COL    = exact_vm('POST', '/articles')
EXACT_GET_MISSING = exact_vm('GET',  '/missing')
EXACT_POST_ITEM   = exact_vm('POST', '/articles/42')

LT_SMALL  = lt_vm(50)
LT_EXACT  = lt_vm(100)
LT_LARGE  = lt_vm(200)

ROUTE_REG_ROOT   = route_vm('GET',  '/')
ROUTE_REG_ITEM   = route_vm('GET',  '/articles/42')
PARAM_REG_42     = param_vm('/articles/42')

TC_SRC_TEXT = File.read(TC_SRC) rescue ''

puts "[*] Done. Running checks...\n"

# ══════════════════════════════════════════════════════════════════════════════
# P6-TC  — TypeChecker accepts/rejects == and < correctly
# ══════════════════════════════════════════════════════════════════════════════
section('P6-TC — TypeChecker == and < alignment')

check('P6-TC-01: [P6-1] RouteDispatchExact (String==String) compiles with status=ok') do
  EXACT_RESULT['status'] == 'ok'
end

check('P6-TC-02: [P6-1] RouteDispatchExact has no OOF-TY0 diagnostics') do
  (EXACT_RESULT['diagnostics'] || []).none? { |d| d['rule'] == 'OOF-TY0' }
end

check('P6-TC-03: [P6-2] LtIntegerValid (Integer<Integer) compiles with status=ok') do
  LT_RESULT['status'] == 'ok'
end

check('P6-TC-04: [P6-3] EqTypeMismatch (String==Integer) fails with status=oof') do
  EQ_MM_RESULT['status'] == 'oof'
end

check('P6-TC-05: [P6-3] EqTypeMismatch diagnostic is OOF-TY0 with cannot-compare message') do
  (EQ_MM_RESULT['diagnostics'] || []).any? do |d|
    d['rule'] == 'OOF-TY0' &&
      d['message'].to_s.include?('cannot compare') &&
      d['message'].to_s.include?('String') &&
      d['message'].to_s.include?('Integer')
  end
end

check('P6-TC-06: [P6-4] LtStringReject (String<String) fails with status=oof') do
  LT_REJ_RESULT['status'] == 'oof'
end

check('P6-TC-07: [P6-4] LtStringReject diagnostic is OOF-TY0 with expected-Integer message') do
  (LT_REJ_RESULT['diagnostics'] || []).any? do |d|
    d['rule'] == 'OOF-TY0' &&
      d['message'].to_s.include?('Integer')
  end
end

check('P6-TC-08: [P6-5] typechecker.rs source contains "==" arm (stdlib.primitive.eq)') do
  TC_SRC_TEXT.include?('stdlib.primitive.eq')
end

check('P6-TC-09: [P6-6] typechecker.rs source contains "<" arm (stdlib.integer.lt)') do
  TC_SRC_TEXT.include?('stdlib.integer.lt')
end

check('P6-TC-10: [P6-7] typechecker.rs LAB-RACK-P6 comment present') do
  TC_SRC_TEXT.include?('LAB-RACK-P6')
end

# ══════════════════════════════════════════════════════════════════════════════
# P6-IR  — SemanticIR shape
# ══════════════════════════════════════════════════════════════════════════════
section('P6-IR — SemanticIR binary_op shape for ==')

EXACT_SIR = read_sir(OUT_DIR / 'exact.igapp')

check('P6-IR-01: [P6-8] RouteDispatchExact SemanticIR is non-nil') do
  !EXACT_SIR.nil?
end

check('P6-IR-02: [P6-8] RouteDispatchExact SemanticIR contains binary_op node with op==\"==\"') do
  return false unless EXACT_SIR
  sir_json = JSON.generate(EXACT_SIR)
  sir_json.include?('"op"') && sir_json.include?('"=="')
end

check('P6-IR-03: [P6-8] RouteDispatchExact SemanticIR: status_code node exists in nodes array') do
  return false unless EXACT_SIR
  contracts = EXACT_SIR['contracts'] || []
  nodes     = contracts.first&.fetch('nodes', []) || []
  nodes.any? { |n| n['name'] == 'status_code' }
end

# ══════════════════════════════════════════════════════════════════════════════
# P6-VM  — 5 exact-route VM execution cases
# ══════════════════════════════════════════════════════════════════════════════
section('P6-VM — exact route dispatch end-to-end VM execution')

check('P6-VM-01: [P6-9]  GET /           → VM result 200') do
  EXACT_GET_ROOT['status'] == 'success' && EXACT_GET_ROOT['result'] == 200
end

check('P6-VM-02: [P6-10] GET /articles/42 → VM result 200') do
  EXACT_GET_ITEM['status'] == 'success' && EXACT_GET_ITEM['result'] == 200
end

check('P6-VM-03: [P6-11] POST /articles  → VM result 201') do
  EXACT_POST_COL['status'] == 'success' && EXACT_POST_COL['result'] == 201
end

check('P6-VM-04: [P6-12] GET /missing    → VM result 404') do
  EXACT_GET_MISSING['status'] == 'success' && EXACT_GET_MISSING['result'] == 404
end

check('P6-VM-05: [P6-13] POST /articles/42 → VM result 405') do
  EXACT_POST_ITEM['status'] == 'success' && EXACT_POST_ITEM['result'] == 405
end

# ══════════════════════════════════════════════════════════════════════════════
# P6-LT  — Integer < Integer VM execution
# ══════════════════════════════════════════════════════════════════════════════
section('P6-LT — Integer < Integer end-to-end VM execution')

check('P6-LT-01: [P6-14] n=50  < 100 → VM result true') do
  LT_SMALL['status'] == 'success' && LT_SMALL['result'] == true
end

check('P6-LT-02: [P6-15] n=100 < 100 → VM result false (boundary)') do
  LT_EXACT['status'] == 'success' && LT_EXACT['result'] == false
end

check('P6-LT-03: [P6-16] n=200 < 100 → VM result false') do
  LT_LARGE['status'] == 'success' && LT_LARGE['result'] == false
end

# ══════════════════════════════════════════════════════════════════════════════
# P6-REG  — P5 fixtures still green
# ══════════════════════════════════════════════════════════════════════════════
section('P6-REG — P5 regression: route_dispatch and path_param_extract')

check('P6-REG-01: [P6-17] route_dispatch.ig (P5) still compiles with status=ok') do
  ROUTE_RESULT['status'] == 'ok'
end

check('P6-REG-02: [P6-17] P5 GET / route still returns 200 on VM') do
  ROUTE_REG_ROOT['status'] == 'success' && ROUTE_REG_ROOT['result'] == 200
end

check('P6-REG-03: [P6-17] P5 GET /articles/42 still returns 200 on VM') do
  ROUTE_REG_ITEM['status'] == 'success' && ROUTE_REG_ITEM['result'] == 200
end

check('P6-REG-04: [P6-18] path_param_extract.ig (P5) still compiles with status=ok') do
  PARAM_RESULT['status'] == 'ok'
end

check('P6-REG-05: [P6-18] path param extraction /articles/42 → "42" still correct') do
  PARAM_REG_42['status'] == 'success' && PARAM_REG_42['result'].to_s == '42'
end

# ══════════════════════════════════════════════════════════════════════════════
# P6-CLOSED  — closed-surface scan
# ══════════════════════════════════════════════════════════════════════════════
section('P6-CLOSED — closed-surface scan')

source = File.read(__FILE__)

check('P6-CLOSED-01: [P6-19] source contains no real socket or network-IO classes') do
  net_h   = 'Net'    + '::' + 'HTTP'
  tcp_s   = 'TCP'    + 'Socket'
  udp_s   = 'UDP'    + 'Socket'
  sck_new = 'Socket' + '.new'
  req_net = "require 'net/" + "http'"
  req_sck = "require 'soc" + "ket'"
  [net_h, tcp_s, udp_s, sck_new, req_net, req_sck].none? { |t| source.include?(t) }
end

check('P6-CLOSED-02: [P6-19] source contains no service-loop or accept-loop forms') do
  svc_lp  = 'Service'  + 'Loop'
  srv_acc = 'server'   + '.accept'
  rack_hd = 'Rack'     + '::Handler'
  [svc_lp, srv_acc, rack_hd].none? { |t| source.include?(t) }
end

check('P6-CLOSED-03: [P6-20] source contains no igc-run or runtime-smoke surfaces') do
  igc_r  = 'igc'     + ' run'
  rt_smk = 'Runtime' + 'Smoke'
  ref_rt = 'Reference' + 'Runtime'
  ig_bin = '.ig'     + 'bin'
  [igc_r, rt_smk, ref_rt, ig_bin].none? { |t| source.include?(t) }
end

check('P6-CLOSED-04: [P6-21] source contains no stable-api or rack-compat claims') do
  stbl = 'stable' + ' API'
  rack = 'Rack-comp' + 'atible'
  prod = 'production' + ' server'
  [stbl, rack, prod].none? { |t| source.include?(t) }
end

# ══════════════════════════════════════════════════════════════════════════════
# P6-GAP  — gap packet
# ══════════════════════════════════════════════════════════════════════════════
section('P6-GAP — gap packet')

GAP_PACKET = {
  card:       'LAB-RACK-P6',
  date:       '2026-06-08',
  authority:  'lab-only — no canon claim, no stable-API surface',
  closed_by_p6: {
    typechecker_eq:  '== now accepted for String/Text/Integer/Bool; rejects incompatible types with OOF-TY0',
    typechecker_lt:  '< now accepted for Integer only; rejects String/Text/Bool with OOF-TY0',
    route_dispatch:  'Exact route dispatch (path=="/", method=="GET") compiles + executes end-to-end on VM'
  },
  still_open: {
    vm_entrypoint: {
      status:   'gap',
      detail:   'VM always executes contracts[0]; no entrypoint selector',
      evidence: 'igniter-vm/src/compiler.rs: contracts_arr.get(0)'
    },
    contractref_dispatch: {
      status:   'gap',
      detail:   'ContractRef runtime dispatch not implemented; OP_CALL user-contract fallthrough',
      evidence: 'igniter-vm/src/vm.rs: OP_CALL Unknown/unimplemented function'
    },
    middleware_execution: {
      status:   'deferred',
      detail:   'No middleware layer; no before/after hook execution model'
    },
    query_glob_routing: {
      status:   'deferred',
      detail:   'Query params, glob routes, prefix router semantics not implemented'
    }
  },
  deferred:   'query params; glob routing; middleware; ContractRef runtime; VM entrypoint selector',
  next_route: 'LAB-RACK-P7: VM entrypoint selector (unblock multi-contract dispatch) OR ContractRef alignment'
}.freeze

check('P6-GAP-01: [P6-22] gap packet has closed_by_p6 + still_open + next_route') do
  %i[closed_by_p6 still_open deferred next_route].all? { |k| GAP_PACKET.key?(k) }
end

check('P6-GAP-02: [P6-22] typechecker_eq and typechecker_lt listed as closed') do
  GAP_PACKET[:closed_by_p6].key?(:typechecker_eq) &&
    GAP_PACKET[:closed_by_p6].key?(:typechecker_lt)
end

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
puts "\n" + ('═' * 72)
total  = RESULTS.length
passed = RESULTS.count { |r| r[:passed] }
failed = RESULTS.count { |r| !r[:passed] }
puts "  LAB-RACK-P6  #{passed}/#{total} PASS#{failed > 0 ? "  (#{failed} FAIL)" : ''}"
puts '═' * 72

if FAILURES.any?
  puts "\nFailed checks:"
  FAILURES.each { |f| puts "  [!] #{f}" }
end

puts "\nClosed by P6:"
GAP_PACKET[:closed_by_p6].each { |k, v| puts "  #{k.to_s.ljust(20)} #{v[0..60]}" }
puts "\nStill open:"
GAP_PACKET[:still_open].each { |k, info| puts "  #{k.to_s.ljust(24)} #{info[:detail][0..55]}" }
puts "\nNext route: #{GAP_PACKET[:next_route]}"

exit(failed > 0 ? 1 : 0)
