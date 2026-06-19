# verify_p3_contractref_dispatch.rb
#
# LAB-RACK-P3: ContractRef VM Dispatch Preflight
#
# Purpose: Prove or precisely falsify whether the lab compiler/VM can dispatch
# a Rack-shaped handler through ContractRef[HttpRequest, HttpResponse].
#
# Proof axiom: a check PASSES when it precisely characterises a gap or confirms
# a working baseline. "PASS" does not mean "the feature works."
# "PASS" on a dispatch check means the gap is confirmed at a specific layer.
#
# Gap layers under test:
#   TypeChecker   – direct cross-contract call syntax
#   SemanticIR    – IR node shape for call/apply nodes
#   VM compiler   – contracts[0]-only entrypoint selection
#   VM executor   – OP_CALL handler dispatches stdlib only; unknown → error
#   Type system   – ContractRef[A,B] parameterised type annotation
#
# CLOSED: lab-only, no canon grammar edits, no real TCP/socket, no accept-loop forms,
#         no production/stable-API/public-API claims.
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Card: LAB-RACK-P3
# Date: 2026-06-08

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent           # igniter-view-engine/
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p3_contractref_dispatch'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_IGAPP_REF = File.expand_path(
  '../../igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/positive.igapp',
  __dir__
)

FileUtils.mkdir_p(OUT_DIR)

# ── Compile helper ─────────────────────────────────────────────────────────────
#
# Returns a hash:
#   status:      "ok" | "error" | "parse_error"
#   stages:      hash of stage => "ok"/"error"
#   diagnostics: array of diagnostic hashes
#   _out_dir:    path to compiled igapp directory (may not exist on error)
#   _raw:        raw compiler stdout+stderr
def compile_fixture(src_path, out_dir)
  out   = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  json  = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir']  = out_dir.to_s
  json['_raw']      = out
  json['_ok_exit']  = $?.success?
  json
end

# ── VM run helper ──────────────────────────────────────────────────────────────
#
# Returns a hash:
#   status: "success" | "error" | "parse_error"
#   result: value (on success)
#   error:  message (on error)
def run_vm(igapp_path, inputs_hash)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs_tmp.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} --json 2>/dev/null`
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

# ── Read SemanticIR helper ─────────────────────────────────────────────────────
def read_sir(igapp_dir)
  path = File.join(igapp_dir.to_s, 'semantic_ir_program.json')
  return nil unless File.exist?(path)
  JSON.parse(File.read(path)) rescue nil
end

# ── Check harness ──────────────────────────────────────────────────────────────
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

# ══════════════════════════════════════════════════════════════════════════════
# Compile all fixtures once up-front (avoids redundant rebuilds in checks)
# ══════════════════════════════════════════════════════════════════════════════
puts "\n[*] Compiling LAB-RACK-P3 fixtures..."

HELLO_RESULT = compile_fixture(
  FIXTURE_DIR / 'hello_handler_standalone.ig',
  OUT_DIR / 'hello_handler.igapp'
)

DIRECT_RESULT = compile_fixture(
  FIXTURE_DIR / 'direct_call_attempt.ig',
  OUT_DIR / 'direct_call.igapp'
)

CREF_RESULT = compile_fixture(
  FIXTURE_DIR / 'contractref_annotation.ig',
  OUT_DIR / 'contractref_annotation.igapp'
)

# Read SemanticIR for hello (used in IR section)
HELLO_SIR = read_sir(OUT_DIR / 'hello_handler.igapp')

# Run VM for hello (used in VM section)
HELLO_VM  = if HELLO_RESULT['status'] == 'ok'
  run_vm(OUT_DIR / 'hello_handler.igapp', { 'method' => 'GET', 'path' => '/hello' })
else
  { 'status' => 'skipped', 'error' => 'compilation failed' }
end

# Read existing form-dispatch reference igapp (UseIntegerAdd / AddInteger)
FORM_SIR = read_sir(VM_IGAPP_REF)

puts "[*] Compilation complete. Running checks...\n"

# ══════════════════════════════════════════════════════════════════════════════
# P3-BASELINE
# ══════════════════════════════════════════════════════════════════════════════
section('P3-BASELINE')

check('P3-BASELINE-01: [P3-1] P2 rack_core_proof.rb exists with section marker') do
  p2 = File.expand_path('rack_core_proof.rb', __dir__)
  File.exist?(p2) && File.read(p2).include?('RACK-P2-SURFACE')
end

check('P3-BASELINE-02: [P3-2] HelloHandler standalone compiles with status=ok') do
  HELLO_RESULT['status'] == 'ok'
end

check('P3-BASELINE-03: [P3-2] HelloHandler standalone: all pipeline stages pass') do
  stages = HELLO_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

# ══════════════════════════════════════════════════════════════════════════════
# P3-DISPATCH  — gap characterisation at call-boundary layer
# ══════════════════════════════════════════════════════════════════════════════
section('P3-DISPATCH — TypeChecker/type-annotation gap characterisation')

check('P3-DISPATCH-01: [P3-3] direct cross-contract call is rejected by compiler') do
  # PASS = gap confirmed at TypeChecker (compilation NOT clean)
  DIRECT_RESULT['status'] != 'ok' ||
    (DIRECT_RESULT['diagnostics'] || []).any?
end

check('P3-DISPATCH-02: [P3-3] direct call diagnostic array is non-empty') do
  (DIRECT_RESULT['diagnostics'] || []).length > 0
end

check('P3-DISPATCH-03: [P3-3] direct call diagnostic rule code is present') do
  diags = DIRECT_RESULT['diagnostics'] || []
  diags.any? { |d| d['rule'].to_s.length > 0 }
end

check('P3-DISPATCH-04: [P3-5] ContractRef[A,B] type annotation: compilation recorded') do
  # Check is structural: we need a recorded result (any status)
  %w[ok error parse_error].include?(CREF_RESULT['status'])
end

check('P3-DISPATCH-05: [P3-5] ContractRef[A,B] compiles without error (accepted as opaque type_ref)') do
  # Finding: ContractRef[A,B] is NOT rejected by the parser or typechecker.
  # The compiler accepts it as a structural type_ref in SemanticIR.
  # Parser/typechecker layer has NO gap for ContractRef[A,B].
  # The dispatch gap is entirely at the VM runtime layer (confirmed in P3-VM-04).
  CREF_RESULT['status'] == 'ok' &&
    (CREF_RESULT['diagnostics'] || []).empty?
end

check('P3-DISPATCH-06: [P3-6] direct call SemanticIR: Dispatcher node absent (not emitted)') do
  # If compilation failed, no igapp is emitted — Dispatcher never reaches SemanticIR
  direct_sir = read_sir(OUT_DIR / 'direct_call.igapp')
  if direct_sir.nil?
    true   # compilation gap confirmed: no igapp produced
  else
    # If an igapp was produced, confirm Dispatcher is absent OR has the call gap
    contracts = direct_sir['contracts'] || []
    dispatcher = contracts.find { |c| c['contract_name'] == 'Dispatcher' }
    dispatcher.nil?  # Dispatcher absent from SemanticIR is also a gap confirmation
  end
end

# ══════════════════════════════════════════════════════════════════════════════
# P3-IR  — SemanticIR shape verification
# ══════════════════════════════════════════════════════════════════════════════
section('P3-IR — SemanticIR node shape')

check('P3-IR-01: [P3-7] HelloHandler SemanticIR: contracts array has exactly 1 entry') do
  contracts = (HELLO_SIR || {})['contracts'] || []
  contracts.length == 1
end

check('P3-IR-02: [P3-7] HelloHandler SemanticIR: contract_name is HelloHandler') do
  contracts = (HELLO_SIR || {})['contracts'] || []
  contracts.first&.fetch('contract_name', nil) == 'HelloHandler'
end

check('P3-IR-03: [P3-8] HelloHandler SemanticIR: compute node is a literal expr (no call nodes)') do
  contracts = (HELLO_SIR || {})['contracts'] || []
  nodes     = contracts.first&.fetch('nodes', []) || []
  status_node = nodes.find { |n| n['name'] == 'status_code' }
  status_node && status_node.dig('expr', 'kind') == 'literal'
end

check('P3-IR-06: [P3-5] ContractRef SemanticIR: input type has kind=type_ref and params=[String,Integer]') do
  # Finding: ContractRef[A,B] emits { kind: "type_ref", name: "ContractRef", params: ["String","Integer"] }
  # This confirms the compiler stores structural type info but attaches no dispatch semantics.
  cref_sir = read_sir(OUT_DIR / 'contractref_annotation.igapp')
  return false unless cref_sir
  contracts = cref_sir['contracts'] || []
  handler_input = contracts.first&.dig('inputs')&.find { |i| i['name'] == 'handler' }
  return false unless handler_input
  t = handler_input['type']
  t['kind'] == 'type_ref' &&
    t['name'] == 'ContractRef' &&
    t['params'] == %w[String Integer]
end

check('P3-IR-04: [P3-9] form-dispatch igapp: UseIntegerAdd node has kind=call, fn=AddInteger') do
  # Confirms the IR identity for form-based cross-contract shape (reference artifact)
  contracts   = (FORM_SIR || {})['contracts'] || []
  use_integer = contracts.find { |c| c['contract_name'] == 'UseIntegerAdd' }
  return false unless use_integer
  nodes    = use_integer['nodes'] || []
  tot_node = nodes.find { |n| n['name'] == 'total' }
  tot_node && tot_node.dig('expr', 'kind') == 'call' &&
    tot_node.dig('expr', 'fn') == 'AddInteger'
end

check('P3-IR-05: [P3-9] form-dispatch igapp: contracts array has AddInteger at index 0') do
  contracts = (FORM_SIR || {})['contracts'] || []
  contracts.first&.fetch('contract_name', nil) == 'AddInteger'
end

# ══════════════════════════════════════════════════════════════════════════════
# P3-VM  — VM execution gap characterisation
# ══════════════════════════════════════════════════════════════════════════════
section('P3-VM — VM execution and dispatch gap')

check('P3-VM-01: [P3-10] HelloHandler VM execution succeeds') do
  HELLO_VM['status'] == 'success'
end

check('P3-VM-02: [P3-10] HelloHandler VM result is 200') do
  HELLO_VM['result'] == 200
end

check('P3-VM-03: [P3-11] VM compiler always selects contracts[0] (structural gap confirmed)') do
  # Gap confirmed by reading compiler.rs:31-32:
  #   contracts_arr.get(0).ok_or("No contracts found in semantic_ir_program")
  # This means a multi-contract igapp (e.g. Dispatcher + HelloHandler) always
  # executes the FIRST contract, with no entrypoint selection mechanism.
  compiler_src = File.expand_path('../../igniter-vm/src/compiler.rs', __dir__)
  return false unless File.exist?(compiler_src)
  src = File.read(compiler_src)
  src.include?('contracts_arr.get(0)') &&
    src.include?('No contracts found in semantic_ir_program')
end

check('P3-VM-04: [P3-11] VM OP_CALL fallthrough: user contracts produce Unknown-function error') do
  # Gap confirmed by reading vm.rs:1291:
  #   return Err(format!("OP_CALL: Unknown/unimplemented function '{}' ...", fn_name, ...))
  # The OP_CALL match block (lines 387-1291) covers only stdlib/builtin functions.
  # Any user-defined contract name falls through to this error branch.
  vm_src = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
  return false unless File.exist?(vm_src)
  src = File.read(vm_src)
  src.include?("OP_CALL: Unknown/unimplemented function")
end

# ══════════════════════════════════════════════════════════════════════════════
# P3-SURFACE  — closed-surface scan
# ══════════════════════════════════════════════════════════════════════════════
section('P3-SURFACE — closed-surface scan')

source = File.read(__FILE__)

check('P3-SURFACE-01: [P3-12] source contains no real socket or network-IO classes') do
  net_h   = 'Net'    + '::' + 'HTTP'
  tcp_s   = 'TCP'    + 'Socket'
  udp_s   = 'UDP'    + 'Socket'
  sck_new = 'Socket' + '.new'
  req_net = "require 'net/" + "http'"
  req_sck = "require 'soc" + "ket'"
  [net_h, tcp_s, udp_s, sck_new, req_net, req_sck].none? { |t| source.include?(t) }
end

check('P3-SURFACE-02: [P3-12] source contains no service-loop or accept-loop forms') do
  svc_lp   = 'Service'  + 'Loop'
  srv_acc  = 'server'   + '.accept'
  srv_lst  = 'server'   + '.listen'
  rack_hdl = 'Rack'     + '::Handler'
  [svc_lp, srv_acc, srv_lst, rack_hdl].none? { |t| source.include?(t) }
end

check('P3-SURFACE-03: [P3-13] source contains no igc-run or runtime-smoke surfaces') do
  igc_r   = 'igc'   + ' run'
  rt_smk  = 'Runtime' + 'Smoke'
  ref_rt  = 'Reference' + 'Runtime'
  ig_bin  = '.ig'   + 'bin'
  [igc_r, rt_smk, ref_rt, ig_bin].none? { |t| source.include?(t) }
end

check('P3-SURFACE-04: [P3-14] source contains no stable-api, production, or canon-grammar claims') do
  stbl_api = 'stable' + ' API'
  prod_srv = 'production' + ' server'
  rack_cmp = 'Rack-comp' + 'atible'
  pub_api  = 'public'  + ' API'
  [stbl_api, prod_srv, rack_cmp, pub_api].none? { |t| source.include?(t) }
end

# ══════════════════════════════════════════════════════════════════════════════
# P3-GAP-PACKET  — structured gap summary
# ══════════════════════════════════════════════════════════════════════════════
section('P3-GAP-PACKET — structured dispatch gap packet')

GAP_PACKET = {
  card:        'LAB-RACK-P3',
  date:        '2026-06-08',
  authority:   'lab-only — no canon claim, no stable-API surface',
  gaps: {
    parser: {
      status:   'none',
      detail:   'ContractRef[A,B] IS accepted by compiler as structural type_ref — no parser gap; ' \
                'direct-call syntax rejected at TypeChecker (unknown function), not at parser',
      evidence: 'contractref_annotation.igapp type_ref SemanticIR; direct_call diagnostics'
    },
    typechecker: {
      status:   'gap',
      detail:   'Direct HelloHandler(args) call: TypeChecker rejects (OOF-TY0 or unknown-function)',
      evidence: 'direct_call_attempt.ig diagnostics'
    },
    semanticir: {
      status:   'partial',
      detail:   'Form-resolved calls preserved as kind:call, fn:ContractName in IR; ' \
                'but ContractRef first-class type not present; Dispatcher node not emitted',
      evidence: 'positive.igapp UseIntegerAdd node; direct_call.igapp absent'
    },
    vm_entrypoint: {
      status:   'gap',
      detail:   'VM always executes contracts[0] from semantic_ir_program; no entrypoint selector',
      evidence: 'igniter-vm/src/compiler.rs line 32: contracts_arr.get(0)'
    },
    vm_dispatch: {
      status:   'gap',
      detail:   'OP_CALL match covers stdlib/builtins only; user-defined contract names → ' \
                '"OP_CALL: Unknown/unimplemented function"',
      evidence: 'igniter-vm/src/vm.rs line 1291'
    }
  },
  next_route:  'LAB-RACK-P4: route dispatch with static handler table (no ContractRef runtime, form-only dispatch)',
  closed:      'ContractRef runtime dispatch; dynamic entrypoint selection; canon grammar edit'
}.freeze

check('P3-GAP-PACKET-01: [P3-15] gap packet has all required layer keys') do
  required = %i[parser typechecker semanticir vm_entrypoint vm_dispatch]
  required.all? { |k| GAP_PACKET[:gaps].key?(k) }
end

check('P3-GAP-PACKET-02: [P3-15] gap packet specifies next route and closed surface') do
  GAP_PACKET[:next_route].to_s.start_with?('LAB-RACK-P4') &&
    GAP_PACKET[:closed].to_s.include?('ContractRef runtime dispatch')
end

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
puts "\n" + ('═' * 72)
total  = RESULTS.length
passed = RESULTS.count { |r| r[:passed] }
failed = RESULTS.count { |r| !r[:passed] }
puts "  LAB-RACK-P3  #{passed}/#{total} PASS#{failed > 0 ? "  (#{failed} FAIL)" : ''}"
puts '═' * 72

if FAILURES.any?
  puts "\nFailed checks:"
  FAILURES.each { |f| puts "  [!] #{f}" }
end

puts "\nGap packet summary:"
GAP_PACKET[:gaps].each do |layer, info|
  puts "  #{layer.to_s.ljust(16)} #{info[:status].upcase.ljust(8)} #{info[:detail][0..72]}"
end
puts "\nNext route: #{GAP_PACKET[:next_route]}"
puts "Closed:     #{GAP_PACKET[:closed]}"

exit(failed > 0 ? 1 : 0)
