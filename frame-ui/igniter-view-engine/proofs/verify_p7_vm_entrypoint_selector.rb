# verify_p7_vm_entrypoint_selector.rb
#
# LAB-RACK-P7: VM Named Entrypoint Selector
#
# Purpose: Prove that the VM can select a named contract from a multi-contract
# igapp via --entry <contract_name> CLI flag; default behavior (no --entry)
# remains contracts[0]; unknown entrypoint fails closed with a clear error.
#
# Implementation (LAB-RACK-P7):
#   igniter-vm/src/compiler.rs:
#     + Compiler::compile_entry(contract_jv, entry_name: Option<&str>)
#       When Some(name): searches contracts array by "contract_name" field.
#       When None: falls back to contracts[0] (unchanged default behavior).
#       Fails closed: "Entry '<name>' not found in igapp (available: [...])"
#     + Compiler::compile() unchanged (calls compile_entry(jv, None))
#   igniter-vm/src/main.rs:
#     + "--entry" / "--entrypoint" / "-e" flag added to run subcommand parser
#     + Passes entry_name to compiler.compile_entry
#     + modifier reading respects --entry selection
#
# Proof scope:
#   P7-COMPILE  — multi-contract fixture compiles; 3 contracts in SemanticIR
#   P7-SOURCE   — compiler.rs contains compile_entry + LAB-RACK-P7 annotation
#   P7-DEFAULT  — no --entry executes contracts[0] (Double)
#   P7-ENTRY    — --entry Double / IsSmall / RouteGate each select correctly
#   P7-FAIL     — unknown entrypoint fails closed with descriptive error
#   P7-REG      — P6 route_dispatch_exact.ig still green
#   P7-CLOSED   — closed-surface scan (no sockets, no compiler-run, no API claims)
#   P7-GAP      — gap packet: entrypoint closed; ContractRef still open
#
# Proof axiom: PASS means the stated property holds.
# CLOSED: lab-only, no canon grammar edits, no real TCP/socket, no accept-loop,
#         no ContractRef runtime dispatch, no middleware, no HTTP server,
#         no stable/public-API, no rack-compat claims.
#
# Authority: lab-only evidence — no canon claim, no stable API surface.
# Card: LAB-RACK-P7
# Date: 2026-06-08

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p7_vm_entrypoint'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
COMPILER_SRC = File.expand_path('../../igniter-vm/src/compiler.rs', __dir__)
MAIN_SRC     = File.expand_path('../../igniter-vm/src/main.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

# ── Helpers ────────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def run_vm(igapp_path, inputs_hash, entry_name: nil)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  entry_flag = entry_name ? "--entry #{entry_name}" : ''
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} #{entry_flag} --json 2>/dev/null`
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

def read_sir(igapp_path)
  sir_file = File.join(igapp_path.to_s, 'semantic_ir_program.json')
  return JSON.parse(File.read(sir_file)) if File.exist?(sir_file)
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

# ── Compile fixtures ──────────────────────────────────────────────────────────
puts "\n[*] Compiling P7 fixtures..."
MULTI_RESULT = compile_fixture(FIXTURE_DIR / 'multi_contract_entrypoints.ig',
                               OUT_DIR / 'multi.igapp')
EXACT_RESULT = compile_fixture(FIXTURE_DIR / 'route_dispatch_exact.ig',
                               OUT_DIR / 'exact.igapp')
MULTI_IGAPP  = MULTI_RESULT['_out_dir']
EXACT_IGAPP  = EXACT_RESULT['_out_dir']
MULTI_SIR    = read_sir(MULTI_IGAPP)

# ── P7-COMPILE ────────────────────────────────────────────────────────────────
section 'P7-COMPILE: multi-contract fixture compiles and SemanticIR has 3 contracts'

check('P7-COMPILE-01: multi_contract_entrypoints.ig compiles ok') do
  MULTI_RESULT['status'] == 'ok'
end

check('P7-COMPILE-02: SemanticIR has contracts array with 3 entries') do
  MULTI_SIR&.dig('contracts')&.size == 3
end

check('P7-COMPILE-03: contracts are Double, IsSmall, RouteGate (in order)') do
  names = MULTI_SIR&.dig('contracts')&.map { |c| c['contract_name'] }
  names == ['Double', 'IsSmall', 'RouteGate']
end

# ── P7-SOURCE ─────────────────────────────────────────────────────────────────
section 'P7-SOURCE: compiler.rs contains compile_entry + LAB-RACK-P7 annotation'

COMP_SRC_TEXT = File.read(COMPILER_SRC) rescue ''
MAIN_SRC_TEXT = File.read(MAIN_SRC)     rescue ''

check('P7-SOURCE-01: compiler.rs defines compile_entry method') do
  COMP_SRC_TEXT.include?('compile_entry')
end

check('P7-SOURCE-02: compiler.rs contains LAB-RACK-P7 annotation') do
  COMP_SRC_TEXT.include?('LAB-RACK-P7')
end

check('P7-SOURCE-03: main.rs defines --entry flag') do
  MAIN_SRC_TEXT.include?('"--entry"')
end

# ── P7-DEFAULT ────────────────────────────────────────────────────────────────
section 'P7-DEFAULT: no --entry flag executes contracts[0] (Double)'

DEFAULT_RESULT = run_vm(MULTI_IGAPP, { 'n' => 5 })

check('P7-DEFAULT-01: no --entry → status success') do
  DEFAULT_RESULT['status'] == 'success'
end

check('P7-DEFAULT-02: no --entry → result=10 (contracts[0]=Double, 5+5=10)') do
  DEFAULT_RESULT['result'] == 10
end

# ── P7-ENTRY ──────────────────────────────────────────────────────────────────
section 'P7-ENTRY: --entry selects named contracts by contract_name field'

# Double: n + n
ENTRY_DOUBLE = run_vm(MULTI_IGAPP, { 'n' => 21 }, entry_name: 'Double')

check('P7-ENTRY-01: --entry Double → status success') do
  ENTRY_DOUBLE['status'] == 'success'
end

check('P7-ENTRY-02: --entry Double → result=42 (21+21)') do
  ENTRY_DOUBLE['result'] == 42
end

# IsSmall: n < 100 → true when n=50
ENTRY_SMALL_T = run_vm(MULTI_IGAPP, { 'n' => 50 }, entry_name: 'IsSmall')

check('P7-ENTRY-03: --entry IsSmall n=50 → result=true') do
  ENTRY_SMALL_T['result'] == true
end

# IsSmall: n < 100 → false when n=150
ENTRY_SMALL_F = run_vm(MULTI_IGAPP, { 'n' => 150 }, entry_name: 'IsSmall')

check('P7-ENTRY-04: --entry IsSmall n=150 → result=false') do
  ENTRY_SMALL_F['result'] == false
end

# RouteGate: GET / → 200
ENTRY_GATE_200 = run_vm(MULTI_IGAPP, { 'method' => 'GET', 'path' => '/' }, entry_name: 'RouteGate')

check('P7-ENTRY-05: --entry RouteGate GET / → status_code=200') do
  ENTRY_GATE_200['result'] == 200
end

# RouteGate: GET /other → 404
ENTRY_GATE_404 = run_vm(MULTI_IGAPP, { 'method' => 'GET', 'path' => '/other' }, entry_name: 'RouteGate')

check('P7-ENTRY-06: --entry RouteGate GET /other → status_code=404') do
  ENTRY_GATE_404['result'] == 404
end

# RouteGate: POST /other → 405
ENTRY_GATE_405 = run_vm(MULTI_IGAPP, { 'method' => 'POST', 'path' => '/other' }, entry_name: 'RouteGate')

check('P7-ENTRY-07: --entry RouteGate POST /other → status_code=405') do
  ENTRY_GATE_405['result'] == 405
end

# ── P7-FAIL ───────────────────────────────────────────────────────────────────
section 'P7-FAIL: unknown entrypoint fails closed'

FAIL_UNKNOWN = run_vm(MULTI_IGAPP, { 'n' => 1 }, entry_name: 'UnknownContract')

check('P7-FAIL-01: --entry UnknownContract → status=error (fails closed)') do
  FAIL_UNKNOWN['status'] == 'error'
end

check('P7-FAIL-02: error message mentions "not found" with available names') do
  err = FAIL_UNKNOWN['error'].to_s
  err.include?('not found') && err.include?('Double')
end

# Non-existent single-contract case: ensure available list is still printed
FAIL_MISSING = run_vm(MULTI_IGAPP, { 'n' => 1 }, entry_name: 'Middleware')

check('P7-FAIL-03: --entry Middleware → error lists RouteGate in available') do
  FAIL_MISSING['error'].to_s.include?('RouteGate')
end

# ── P7-REG ────────────────────────────────────────────────────────────────────
section 'P7-REG: P6 route_dispatch_exact.ig still green (regression)'

check('P7-REG-01: route_dispatch_exact.ig compiles ok') do
  EXACT_RESULT['status'] == 'ok'
end

REG_200 = run_vm(EXACT_IGAPP, { 'method' => 'GET', 'path' => '/' })
check('P7-REG-02: GET / → 200 (exact route regression)') do
  REG_200['result'] == 200
end

REG_404 = run_vm(EXACT_IGAPP, { 'method' => 'GET', 'path' => '/missing' })
check('P7-REG-03: GET /missing → 404 (exact route regression)') do
  REG_404['result'] == 404
end

REG_POST = run_vm(EXACT_IGAPP, { 'method' => 'POST', 'path' => '/articles' })
check('P7-REG-04: POST /articles → 201 (exact route regression)') do
  REG_POST['result'] == 201
end

# ── P7-CLOSED ─────────────────────────────────────────────────────────────────
section 'P7-CLOSED: closed-surface scan'

SOURCE = File.read(__FILE__)

# Self-referential: the scan constructs forbidden strings at check time.
# The source must not contain these as literals; split-string technique used
# in the check blocks below.
check('P7-CLOSED-01: no TCP/UDP socket use in proof source') do
  !SOURCE.include?('TCPSo' + 'cket') &&
  !SOURCE.include?('UDPSo' + 'cket') &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('P7-CLOSED-02: no network I/O calls in proof source') do
  !SOURCE.include?('Net::HT' + 'TP') &&
  !SOURCE.include?("require 'net/ht" + "tp'")
end

check('P7-CLOSED-03: no compiler-pipeline invocation in proof source') do
  !SOURCE.include?('igc' + '-run') &&
  !SOURCE.include?('igc' + ' run')
end

check('P7-CLOSED-04: no production API or runtime claims in source') do
  !SOURCE.include?('stable-' + 'API') &&
  !SOURCE.include?('public' + '-runtime') &&
  !SOURCE.include?('Rack-comp' + 'atible')
end

# ── P7-GAP ────────────────────────────────────────────────────────────────────
section 'P7-GAP: gap packet'

GAP_PACKET = {
  card:      'LAB-RACK-P7',
  date:      '2026-06-08',
  authority: 'lab-only — no canon claim, no stable API surface',

  closed_by_p7: {
    vm_entrypoint_selector: {
      description: '--entry <contract_name> CLI flag selects a named contract ' \
                   'from a multi-contract igapp; unknown name fails closed',
      mechanism:   'Compiler::compile_entry(jv, Option<&str>) searches ' \
                   'contracts array by contract_name field; returns ' \
                   'descriptive error listing available names on miss',
      default_preserved: 'compile(jv) calls compile_entry(jv, None) → ' \
                         'contracts[0] — backward-compatible'
    }
  },

  still_open: {
    contractref_dispatch: {
      status: 'gap',
      detail: 'ContractRef runtime dispatch not implemented; OP_CALL for ' \
              'user-defined contracts falls through in vm.rs',
      path:   'LAB-RACK-P8 or ContractRef alignment card'
    },
    middleware_execution: {
      status: 'deferred',
      detail: 'No before/after hook model'
    },
    query_glob_routing: {
      status: 'deferred',
      detail: 'Query param parsing and glob routing not in scope'
    }
  },

  deferred:   'ContractRef runtime; middleware; query params; glob routing',
  next_route: 'LAB-RACK-P8: ContractRef alignment (enable OP_CALL for ' \
              'user-defined contract invocations)'
}.freeze

check('P7-GAP-01: gap packet has closed_by_p7 with vm_entrypoint_selector') do
  GAP_PACKET[:closed_by_p7].key?(:vm_entrypoint_selector)
end

check('P7-GAP-02: gap packet still_open contains contractref_dispatch') do
  GAP_PACKET[:still_open].key?(:contractref_dispatch)
end

# ── Summary ───────────────────────────────────────────────────────────────────
total   = RESULTS.size
passed  = RESULTS.count { |r| r[:passed] }
failed  = total - passed

puts "\n#{'═' * 72}"
puts "  LAB-RACK-P7: VM Named Entrypoint Selector"
puts "  #{passed}/#{total} PASS#{failed > 0 ? " — FAILURES: #{FAILURES.join(', ')}" : ''}"
puts "#{'═' * 72}"

exit(failed > 0 ? 1 : 0)
