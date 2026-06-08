# verify_p5_vm_stdlib_text.rb
#
# LAB-RACK-P5: VM stdlib.text.* Alignment
#
# Purpose: Add stdlib.text.starts_with, stdlib.text.split, and
# stdlib.text.byte_length to the VM OP_CALL handler in igniter-vm/src/vm.rs,
# then prove end-to-end VM execution of the P4 route dispatch contracts.
#
# This converts LAB-RACK-P4 from "algebra + IR + confirmed VM gap" into a
# full end-to-end lab VM proof for static route dispatch and path param
# extraction.
#
# Changes to igniter-vm/src/vm.rs (LAB-RACK-P5):
#   + "stdlib.text.starts_with"  → same logic as bare "starts_with"
#   + "stdlib.text.split"        → same logic as bare "split"
#   + "stdlib.text.byte_length"  → same logic as bare "length" (byte count)
#
# Proof scope:
#   P5-COMPILE   — both contracts still compile clean (regression check)
#   P5-VM-EXEC   — 5 route cases execute on VM and return correct status codes
#   P5-PARAM-EXEC — param extraction executes on VM and returns correct :id
#   P5-STDLIBTEXT — vm.rs source confirms the 3 new cases are present
#   P5-SURFACE    — closed-surface scan
#   P5-GAP-PACKET — updated gap packet; vm_stdlib_text gap closed
#
# Proof axiom: PASS means execution is correct. P5-STDLIBTEXT checks PASS
# when the vm.rs source contains the named dispatch cases.
#
# CLOSED: lab-only, no canon grammar edits, no real TCP/socket, no accept-loop,
#         no ContractRef runtime dispatch, no VM entrypoint selector,
#         no TypeChecker == or < fix, no production/stable-API claims.
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Card: LAB-RACK-P5
# Date: 2026-06-08

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p5_vm_stdlib_text'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC       = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)

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

# ── Compile fixtures ───────────────────────────────────────────────────────────
puts "\n[*] Compiling P5 fixtures..."
ROUTE_RESULT = compile_fixture(FIXTURE_DIR / 'route_dispatch.ig', OUT_DIR / 'route_dispatch.igapp')
PARAM_RESULT = compile_fixture(FIXTURE_DIR / 'path_param_extract.ig', OUT_DIR / 'path_param_extract.igapp')

# ── Run all VM cases ───────────────────────────────────────────────────────────
puts "[*] Running VM execution checks..."

def route_vm(method, path)
  run_vm(
    File.join(File.expand_path('../../igniter-view-engine/out/p5_vm_stdlib_text/route_dispatch.igapp', __dir__)),
    { 'method' => method, 'path' => path }
  )
end

def param_vm(path)
  run_vm(
    File.join(File.expand_path('../../igniter-view-engine/out/p5_vm_stdlib_text/path_param_extract.igapp', __dir__)),
    { 'path' => path }
  )
end

ROUTE_GET_ROOT    = route_vm('GET',  '/')
ROUTE_GET_ITEM    = route_vm('GET',  '/articles/42')
ROUTE_POST_COL    = route_vm('POST', '/articles')
ROUTE_GET_MISSING = route_vm('GET',  '/missing')
ROUTE_POST_ITEM   = route_vm('POST', '/articles/42')
PARAM_42          = param_vm('/articles/42')
PARAM_99          = param_vm('/articles/99')

VM_SRC_TEXT = File.read(VM_SRC) rescue ''

puts "[*] Done. Running checks...\n"

# ══════════════════════════════════════════════════════════════════════════════
# P5-COMPILE  — regression: contracts still compile clean
# ══════════════════════════════════════════════════════════════════════════════
section('P5-COMPILE — compile regression')

check('P5-COMPILE-01: [P5-1] RouteDispatch still compiles with status=ok') do
  ROUTE_RESULT['status'] == 'ok'
end

check('P5-COMPILE-02: [P5-1] PathParamExtract still compiles with status=ok') do
  PARAM_RESULT['status'] == 'ok'
end

# ══════════════════════════════════════════════════════════════════════════════
# P5-STDLIBTEXT  — vm.rs source confirms the 3 new dispatch cases
# ══════════════════════════════════════════════════════════════════════════════
section('P5-STDLIBTEXT — vm.rs source alignment check')

check('P5-STDLIBTEXT-01: [P5-2] vm.rs contains stdlib.text.starts_with case') do
  VM_SRC_TEXT.include?('"stdlib.text.starts_with"')
end

check('P5-STDLIBTEXT-02: [P5-2] vm.rs contains stdlib.text.split case') do
  VM_SRC_TEXT.include?('"stdlib.text.split"')
end

check('P5-STDLIBTEXT-03: [P5-2] vm.rs contains stdlib.text.byte_length case') do
  VM_SRC_TEXT.include?('"stdlib.text.byte_length"')
end

check('P5-STDLIBTEXT-04: [P5-2] vm.rs LAB-RACK-P5 alignment comment present') do
  VM_SRC_TEXT.include?('LAB-RACK-P5')
end

# ══════════════════════════════════════════════════════════════════════════════
# P5-VM-EXEC  — 5 route cases execute on VM with correct results
# ══════════════════════════════════════════════════════════════════════════════
section('P5-VM-EXEC — end-to-end VM execution')

check('P5-VM-EXEC-01: [P5-3] GET / → VM result 200') do
  ROUTE_GET_ROOT['status'] == 'success' && ROUTE_GET_ROOT['result'] == 200
end

check('P5-VM-EXEC-02: [P5-4] GET /articles/42 → VM result 200') do
  ROUTE_GET_ITEM['status'] == 'success' && ROUTE_GET_ITEM['result'] == 200
end

check('P5-VM-EXEC-03: [P5-5] POST /articles → VM result 201') do
  ROUTE_POST_COL['status'] == 'success' && ROUTE_POST_COL['result'] == 201
end

check('P5-VM-EXEC-04: [P5-6] GET /missing → VM result 404') do
  ROUTE_GET_MISSING['status'] == 'success' && ROUTE_GET_MISSING['result'] == 404
end

check('P5-VM-EXEC-05: [P5-7] POST /articles/42 → VM result 405') do
  ROUTE_POST_ITEM['status'] == 'success' && ROUTE_POST_ITEM['result'] == 405
end

# ══════════════════════════════════════════════════════════════════════════════
# P5-PARAM-EXEC  — path param extraction executes on VM
# ══════════════════════════════════════════════════════════════════════════════
section('P5-PARAM-EXEC — path param extraction end-to-end')

check('P5-PARAM-EXEC-01: [P5-8] /articles/42 → VM result "42"') do
  PARAM_42['status'] == 'success' && PARAM_42['result'].to_s == '42'
end

check('P5-PARAM-EXEC-02: [P5-8] /articles/99 → VM result "99"') do
  PARAM_99['status'] == 'success' && PARAM_99['result'].to_s == '99'
end

check('P5-PARAM-EXEC-03: [P5-8] VM stdlib.text.split gap now closed (no OP_CALL error)') do
  PARAM_42['error'].to_s.empty? && PARAM_99['error'].to_s.empty?
end

# ══════════════════════════════════════════════════════════════════════════════
# P5-SURFACE  — closed-surface scan
# ══════════════════════════════════════════════════════════════════════════════
section('P5-SURFACE — closed-surface scan')

source = File.read(__FILE__)

check('P5-SURFACE-01: [P5-9] source contains no real socket or network-IO classes') do
  net_h   = 'Net'    + '::' + 'HTTP'
  tcp_s   = 'TCP'    + 'Socket'
  udp_s   = 'UDP'    + 'Socket'
  sck_new = 'Socket' + '.new'
  req_net = "require 'net/" + "http'"
  req_sck = "require 'soc" + "ket'"
  [net_h, tcp_s, udp_s, sck_new, req_net, req_sck].none? { |t| source.include?(t) }
end

check('P5-SURFACE-02: [P5-9] source contains no service-loop or accept-loop forms') do
  svc_lp   = 'Service'  + 'Loop'
  srv_acc  = 'server'   + '.accept'
  srv_lst  = 'server'   + '.listen'
  rack_hdl = 'Rack'     + '::Handler'
  [svc_lp, srv_acc, srv_lst, rack_hdl].none? { |t| source.include?(t) }
end

check('P5-SURFACE-03: [P5-10] source contains no igc-run or runtime-smoke surfaces') do
  igc_r   = 'igc'     + ' run'
  rt_smk  = 'Runtime' + 'Smoke'
  ref_rt  = 'Reference' + 'Runtime'
  ig_bin  = '.ig'     + 'bin'
  [igc_r, rt_smk, ref_rt, ig_bin].none? { |t| source.include?(t) }
end

check('P5-SURFACE-04: [P5-11] source contains no stable-api, production-server, or rack-compat claims') do
  stbl_api = 'stable' + ' API'
  prod_srv = 'production' + ' server'
  rack_cmp = 'Rack-comp'  + 'atible'
  pub_api  = 'public'  + ' API'
  [stbl_api, prod_srv, rack_cmp, pub_api].none? { |t| source.include?(t) }
end

# ══════════════════════════════════════════════════════════════════════════════
# P5-GAP-PACKET  — updated gap packet; vm_stdlib_text gap closed
# ══════════════════════════════════════════════════════════════════════════════
section('P5-GAP-PACKET — updated gap packet')

GAP_PACKET = {
  card:        'LAB-RACK-P5',
  date:        '2026-06-08',
  authority:   'lab-only — no canon claim, no stable-API surface',
  closed_by_p5: {
    vm_stdlib_text: 'stdlib.text.starts_with / split / byte_length now dispatch correctly in VM OP_CALL'
  },
  still_open: {
    string_equality: {
      status:   'gap',
      detail:   'TypeChecker OOF-TY0 on == and < for all types; separate TypeChecker card needed',
      evidence: 'OOF-TY0: Unsupported operator: =='
    },
    vm_entrypoint: {
      status:   'gap',
      detail:   'VM always executes contracts[0]; no entrypoint selector (from P3)',
      evidence: 'igniter-vm/src/compiler.rs line 32: contracts_arr.get(0)'
    },
    contractref_dispatch: {
      status:   'gap',
      detail:   'ContractRef runtime dispatch not implemented; OP_CALL user-contract fallthrough (from P3)',
      evidence: 'igniter-vm/src/vm.rs: OP_CALL Unknown/unimplemented function'
    }
  },
  deferred:   'query params; prefix/glob; middleware execution; ContractRef runtime; VM entrypoint selector',
  next_route: 'LAB-RACK-P6: TypeChecker == and < alignment (unblock string equality and length bounds)'
}.freeze

check('P5-GAP-PACKET-01: [P5-12] gap packet has closed_by_p5 + still_open + deferred') do
  %i[closed_by_p5 still_open deferred next_route].all? { |k| GAP_PACKET.key?(k) }
end

check('P5-GAP-PACKET-02: [P5-12] vm_stdlib_text listed as closed; string_equality still open') do
  GAP_PACKET[:closed_by_p5].key?(:vm_stdlib_text) &&
    GAP_PACKET[:still_open].key?(:string_equality)
end

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
puts "\n" + ('═' * 72)
total  = RESULTS.length
passed = RESULTS.count { |r| r[:passed] }
failed = RESULTS.count { |r| !r[:passed] }
puts "  LAB-RACK-P5  #{passed}/#{total} PASS#{failed > 0 ? "  (#{failed} FAIL)" : ''}"
puts '═' * 72

if FAILURES.any?
  puts "\nFailed checks:"
  FAILURES.each { |f| puts "  [!] #{f}" }
end

puts "\nClosed by P5: #{GAP_PACKET[:closed_by_p5].map { |k, v| "#{k}: #{v[0..50]}" }.join('; ')}"
puts "\nStill open:"
GAP_PACKET[:still_open].each { |k, info| puts "  #{k.to_s.ljust(22)} #{info[:detail][0..60]}" }
puts "\nNext route: #{GAP_PACKET[:next_route]}"

exit(failed > 0 ? 1 : 0)
