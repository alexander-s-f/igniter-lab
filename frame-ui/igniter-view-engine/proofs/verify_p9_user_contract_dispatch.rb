# verify_p9_user_contract_dispatch.rb
#
# LAB-RACK-P9: Explicit Named User-Contract Dispatch via call_contract
#
# Purpose: Prove that call_contract("ContractName", args...) correctly
# dispatches to a named contract inside the same igapp at VM runtime, and
# that every fail-closed constraint fires correctly.
#
# Implementation (LAB-RACK-P9):
#   igniter-vm/src/vm.rs:
#     + DispatchEntry struct: bytecode, input_names, modifier, contract_name
#     + MAX_CALL_DEPTH = 8 constant
#     + VM.dispatch_table: HashMap<String, DispatchEntry>
#     + "call_contract" arm in execute_with_grants:
#       - depth check (MAX_CALL_DEPTH)
#       - cycle detection via __call_chain__ in temporal_context
#       - dispatch table lookup (unknown callee → error)
#       - modifier == "pure" guard (effect/privileged callee → error)
#       - arity check (positional args vs input_names)
#       - isolated callee execution (fresh frame, new depth+chain)
#   igniter-vm/src/compiler.rs:
#     + build_dispatch_entry(contract_jv, contract_name):
#       extracts input_names from inputs array, modifier, compiles bytecode
#   igniter-vm/src/main.rs:
#     + builds dispatch table from all contracts in igapp
#     + seeds __call_chain__ with root contract name
#     + sets dispatch_table on VM before execution
#   igniter-compiler/src/typechecker.rs:
#     + registers "call_contract" as known function (OOF-TY0 for non-string
#       first arg; resolved_type stays Unknown — callee output not verifiable v0)
#     + Expr::Ref OOF-P1 only fires when symbol is truly absent (not when
#       declared with Unknown type — e.g. from call_contract result)
#     + output type check: Unknown actual passes declared output type
#       (VM enforces correctness at runtime)
#
# Proof scope:
#   P9-COMPILE    — fixture compiles; 7 contracts accepted
#   P9-SOURCE     — vm.rs/typechecker.rs contain P9 annotations + DispatchEntry
#   P9-HAPPY      — CallerDoubler(10)→21, CallerSmall(50)→true, CallerGate(GET,/)→200
#   P9-FAIL-CLOSED — all fail-closed constraints enforced:
#     FC-01 unknown callee → error (lists available)
#     FC-02 arity mismatch → error (shows expected vs got)
#     FC-03 non-string first arg → OOF-TY0 at compile time
#     FC-04 effect callee blocked → error (modifier guard)
#     FC-05 self-recursion blocked → cycle error
#     FC-06 A→B→A cycle blocked → cycle error
#     FC-07 depth > 8 blocked → max depth error
#   P9-REG        — P7 regression: multi_contract_entrypoints.ig still green
#   P9-CLOSED     — closed-surface scan (no sockets, no stable API claims)
#   P9-GAP        — gap packet: v0 policy; multi-output callee; non-pure callee
#
# Proof axiom: PASS means the stated property holds.
# CLOSED: lab-only, no canon grammar edits, no real TCP/socket, no accept-loop,
#         no ContractRef type semantics, no middleware, no HTTP server,
#         no stable/public API, no rack-compat claims.
#         call_contract is explicitly lab-only; no canon claim, no stable API.
#
# Authority: lab-only evidence — no canon claim, no stable API surface.
# Card: LAB-RACK-P9
# Date: 2026-06-08

require 'json'
require 'fileutils'
require 'tmpdir'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p9_user_contract_dispatch'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC       = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
COMPILER_SRC = File.expand_path('../../igniter-vm/src/compiler.rs', __dir__)
TC_SRC       = File.expand_path('../../igniter-compiler/src/typechecker.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

# ── Helpers ────────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  # Force UTF-8: compiler output may contain Unicode (e.g. × in liveness calibration strings)
  out  = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def compile_inline(source_str, label)
  dir = File.join(OUT_DIR.to_s, "inline_#{label}")
  FileUtils.mkdir_p(dir)
  src = File.join(dir, "#{label}.ig")
  File.write(src, source_str)
  compile_fixture(src, File.join(dir, 'igapp'))
end

def run_vm(igapp_path, inputs_hash, entry_name: nil)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  entry_flag = entry_name ? "--entry #{entry_name}" : ''
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} #{entry_flag} --json 2>/dev/null`
  # Force UTF-8 so JSON.parse handles any Unicode in VM error messages
  out = out.force_encoding('UTF-8')
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

# ── Results tracking ───────────────────────────────────────────────────────────

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

# ── Compile fixtures ───────────────────────────────────────────────────────────

CALLER_IGAPP    = (OUT_DIR / 'multi_caller').to_s
CALLER_RESULT   = compile_fixture(
  FIXTURE_DIR / 'multi_contract_caller.ig',
  CALLER_IGAPP
)

P7_IGAPP        = (OUT_DIR / 'multi_entrypoints').to_s
P7_RESULT       = compile_fixture(
  FIXTURE_DIR / 'multi_contract_entrypoints.ig',
  P7_IGAPP
)

# Inline fixtures for fail-closed tests
# LAB-RACK-P11 NOTE: inline fixtures below use DYNAMIC callees (first arg is a variable,
# not a string literal) so they compile through P11's Tier 2 path (Unknown) and still test
# the VM-level fail-closed behavior.  Literal-callee versions are tested in P11's own proof.
UNKNOWN_CALLEE_SRC = <<~IG
  module Test.UnknownCallee

  pure contract UnknownCallee {
    input n : Integer
    compute callee = "NoSuchContract"
    compute result = call_contract(callee, n)
    output result : Integer
  }
IG

ARITY_MISMATCH_SRC = <<~IG
  module Test.ArityMismatch

  pure contract ArityMismatch {
    input n : Integer
    compute callee = "Double"
    compute result = call_contract(callee, n, n)
    output result : Integer
  }

  pure contract Double {
    input n : Integer
    compute result = n + n
    output result : Integer
  }
IG

NON_STRING_ARG_SRC = <<~IG
  module Test.NonStringArg

  pure contract NonStringArg {
    input n : Integer
    compute result = call_contract(n, 42)
    output result : Integer
  }
IG

EFFECT_CALLEE_SRC = <<~IG
  module Test.EffectCallee

  effect contract EffectCallee {
    input n : Integer
    compute result = n + 1
    output result : Integer
  }

  pure contract EffectCaller {
    input n : Integer
    compute callee = "EffectCallee"
    compute result = call_contract(callee, n)
    output result : Integer
  }
IG

CYCLE_AB_SRC = <<~IG
  module Test.CycleAB

  pure contract CycleA {
    input n : Integer
    compute result = call_contract("CycleB", n)
    output result : Integer
  }

  pure contract CycleB {
    input n : Integer
    compute result = call_contract("CycleA", n)
    output result : Integer
  }
IG

# Depth-9 chain: D1→D2→...→D9→DBase (9 hops exceed MAX_CALL_DEPTH=8)
DEPTH_CHAIN_SRC = begin
  parts = (1..9).map do |i|
    callee = i < 9 ? "D#{i+1}" : "DBase"
    "pure contract D#{i} {\n  input n : Integer\n  compute result = call_contract(\"#{callee}\", n)\n  output result : Integer\n}"
  end
  parts << "pure contract DBase {\n  input n : Integer\n  compute result = n + 1\n  output result : Integer\n}"
  "module Test.DepthChain\n\n" + parts.join("\n\n")
end

UNKNOWN_RESULT  = compile_inline(UNKNOWN_CALLEE_SRC, 'unknown_callee')
ARITY_RESULT    = compile_inline(ARITY_MISMATCH_SRC, 'arity_mismatch')
NONSTR_RESULT   = compile_inline(NON_STRING_ARG_SRC, 'non_string_arg')
EFFECT_RESULT   = compile_inline(EFFECT_CALLEE_SRC,  'effect_callee')
CYCLE_RESULT    = compile_inline(CYCLE_AB_SRC,       'cycle_ab')
DEPTH_RESULT    = compile_inline(DEPTH_CHAIN_SRC,    'depth_chain')

puts "LAB-RACK-P9: Explicit Named User-Contract Dispatch via call_contract"
puts "═" * 72

# ── P9-COMPILE ────────────────────────────────────────────────────────────────
section 'P9-COMPILE: multi_contract_caller.ig compiles (7 contracts accepted)'

check('P9-COMPILE-01: fixture compiles with status=ok') do
  CALLER_RESULT['status'] == 'ok'
end

check('P9-COMPILE-02: all 7 contracts present in igapp') do
  contracts = CALLER_RESULT['contracts'] || []
  %w[CallerDoubler CallerGate CallerSmall Double GateCheck IsSmall SelfRecurseDyn].all? do |c|
    contracts.include?(c)
  end
end

check('P9-COMPILE-03: no diagnostics in caller fixture') do
  (CALLER_RESULT['diagnostics'] || []).empty?
end

check('P9-COMPILE-04: all stages ok (parse, classify, typecheck, emit, assemble)') do
  stages = CALLER_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

check('P9-COMPILE-05: effect_callee fixture compiles ok (effect callee is accepted by compiler)') do
  EFFECT_RESULT['status'] == 'ok'
end

check('P9-COMPILE-06: cycle_ab fixture compiles ok (cycles caught at VM not compile time)') do
  CYCLE_RESULT['status'] == 'ok'
end

check('P9-COMPILE-07: depth_chain fixture compiles ok (depth caught at VM not compile time)') do
  DEPTH_RESULT['status'] == 'ok'
end

# ── P9-SOURCE ─────────────────────────────────────────────────────────────────
section 'P9-SOURCE: implementation annotations present in source files'

VM_SOURCE = File.read(VM_SRC)
TC_SOURCE = File.read(TC_SRC)
CC_SOURCE = File.read(COMPILER_SRC)

check('P9-SOURCE-01: vm.rs contains DispatchEntry struct') do
  VM_SOURCE.include?('struct DispatchEntry')
end

check('P9-SOURCE-02: vm.rs contains MAX_CALL_DEPTH constant') do
  VM_SOURCE.include?('MAX_CALL_DEPTH')
end

check('P9-SOURCE-03: vm.rs contains call_contract dispatch arm') do
  VM_SOURCE.include?('"call_contract"')
end

check('P9-SOURCE-04: vm.rs contains __call_chain__ cycle detection') do
  VM_SOURCE.include?('__call_chain__')
end

check('P9-SOURCE-05: vm.rs contains __call_depth__ depth tracking') do
  VM_SOURCE.include?('__call_depth__')
end

check('P9-SOURCE-06: vm.rs contains LAB-RACK-P9 annotation') do
  VM_SOURCE.include?('LAB-RACK-P9')
end

check('P9-SOURCE-07: compiler.rs contains build_dispatch_entry') do
  CC_SOURCE.include?('build_dispatch_entry')
end

check('P9-SOURCE-08: compiler.rs contains LAB-RACK-P9 annotation') do
  CC_SOURCE.include?('LAB-RACK-P9')
end

check('P9-SOURCE-09: typechecker.rs contains call_contract registration') do
  TC_SOURCE.include?('"call_contract"')
end

check('P9-SOURCE-10: typechecker.rs contains LAB-RACK-P9 annotation') do
  TC_SOURCE.include?('LAB-RACK-P9')
end

# ── P9-HAPPY ──────────────────────────────────────────────────────────────────
section 'P9-HAPPY: happy-path dispatch'

HAPPY_DOUBLER  = run_vm(CALLER_IGAPP, { 'n' => 10 }, entry_name: 'CallerDoubler')
HAPPY_SMALL_T  = run_vm(CALLER_IGAPP, { 'n' => 50 }, entry_name: 'CallerSmall')
HAPPY_SMALL_F  = run_vm(CALLER_IGAPP, { 'n' => 150 }, entry_name: 'CallerSmall')
HAPPY_GATE_200 = run_vm(CALLER_IGAPP, { 'method' => 'GET', 'path' => '/' }, entry_name: 'CallerGate')
HAPPY_GATE_404 = run_vm(CALLER_IGAPP, { 'method' => 'GET', 'path' => '/other' }, entry_name: 'CallerGate')
HAPPY_GATE_405 = run_vm(CALLER_IGAPP, { 'method' => 'POST', 'path' => '/' }, entry_name: 'CallerGate')

check('P9-HAPPY-01: CallerDoubler(n=10) → 21 (double then +1)') do
  HAPPY_DOUBLER['status'] == 'success' && HAPPY_DOUBLER['result'] == 21
end

check('P9-HAPPY-02: CallerDoubler returns status=success') do
  HAPPY_DOUBLER['status'] == 'success'
end

check('P9-HAPPY-03: CallerSmall(n=50) → true (50 < 100)') do
  HAPPY_SMALL_T['status'] == 'success' && HAPPY_SMALL_T['result'] == true
end

check('P9-HAPPY-04: CallerSmall(n=150) → false (150 >= 100)') do
  HAPPY_SMALL_F['status'] == 'success' && HAPPY_SMALL_F['result'] == false
end

check('P9-HAPPY-05: CallerGate(GET, /) → 200') do
  HAPPY_GATE_200['status'] == 'success' && HAPPY_GATE_200['result'] == 200
end

check('P9-HAPPY-06: CallerGate(GET, /other) → 404') do
  HAPPY_GATE_404['status'] == 'success' && HAPPY_GATE_404['result'] == 404
end

check('P9-HAPPY-07: CallerGate(POST, /) → 405') do
  HAPPY_GATE_405['status'] == 'success' && HAPPY_GATE_405['result'] == 405
end

# ── P9-FAIL-CLOSED ────────────────────────────────────────────────────────────
section 'P9-FAIL-CLOSED: all fail-closed constraints enforced'

# FC-01: unknown callee
FC01 = run_vm(UNKNOWN_RESULT['igapp_path'] || UNKNOWN_RESULT['_out_dir'], { 'n' => 5 }, entry_name: 'UnknownCallee')

check('P9-FC-01a: unknown callee → status=error') do
  FC01['status'] == 'error'
end

check('P9-FC-01b: unknown callee error mentions "no contract named"') do
  FC01['error'].to_s.include?('no contract named')
end

check('P9-FC-01c: unknown callee error lists available contracts') do
  FC01['error'].to_s.include?('available')
end

# FC-02: arity mismatch
FC02 = run_vm(ARITY_RESULT['igapp_path'] || ARITY_RESULT['_out_dir'], { 'n' => 5 }, entry_name: 'ArityMismatch')

check('P9-FC-02a: arity mismatch → status=error') do
  FC02['status'] == 'error'
end

check('P9-FC-02b: arity mismatch error mentions "expects" and "got"') do
  err = FC02['error'].to_s
  err.include?('expects') && err.include?('got')
end

check('P9-FC-02c: arity mismatch error names the callee contract') do
  FC02['error'].to_s.include?('Double')
end

# FC-03: non-string first arg → caught at compile time by TypeChecker
check('P9-FC-03a: non-string first arg → compiler status=oof (TypeChecker rejects)') do
  NONSTR_RESULT['status'] == 'oof'
end

check('P9-FC-03b: non-string first arg → OOF-TY0 diagnostic present') do
  diags = NONSTR_RESULT['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('P9-FC-03c: non-string first arg → diagnostic mentions "String"') do
  diags = NONSTR_RESULT['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('String') }
end

# FC-04: effect callee blocked
FC04 = run_vm(EFFECT_RESULT['igapp_path'] || EFFECT_RESULT['_out_dir'], { 'n' => 5 }, entry_name: 'EffectCaller')

check('P9-FC-04a: effect callee → status=error') do
  FC04['status'] == 'error'
end

check('P9-FC-04b: effect callee error mentions "not pure"') do
  FC04['error'].to_s.include?('not pure')
end

check('P9-FC-04c: effect callee error names the callee and its modifier') do
  err = FC04['error'].to_s
  err.include?('EffectCallee') && err.include?('effect')
end

# FC-05: self-recursion blocked (via dynamic Tier 2 callee; literal form caught in P11)
# SelfRecurseDyn uses a variable callee name so it passes P11 compile-time checks,
# but the VM __call_chain__ guard still detects the cycle at runtime.
FC05 = run_vm(CALLER_IGAPP, { 'n' => 1 }, entry_name: 'SelfRecurseDyn')

check('P9-FC-05a: self-recursion → status=error') do
  FC05['status'] == 'error'
end

check('P9-FC-05b: self-recursion error mentions "cycle detected"') do
  FC05['error'].to_s.include?('cycle detected')
end

check('P9-FC-05c: self-recursion error mentions SelfRecurseDyn twice (self -> self)') do
  err = FC05['error'].to_s
  err.scan('SelfRecurseDyn').size >= 2
end

# FC-06: A→B→A cycle blocked
FC06 = run_vm(CYCLE_RESULT['igapp_path'] || CYCLE_RESULT['_out_dir'], { 'n' => 1 }, entry_name: 'CycleA')

check('P9-FC-06a: A→B→A cycle → status=error') do
  FC06['status'] == 'error'
end

check('P9-FC-06b: A→B→A cycle error mentions "cycle detected"') do
  FC06['error'].to_s.include?('cycle detected')
end

check('P9-FC-06c: A→B→A cycle error names both contracts in chain') do
  err = FC06['error'].to_s
  err.include?('CycleA') && err.include?('CycleB')
end

# FC-07: depth > 8 blocked
FC07 = run_vm(DEPTH_RESULT['igapp_path'] || DEPTH_RESULT['_out_dir'], { 'n' => 1 }, entry_name: 'D1')

check('P9-FC-07a: depth > 8 → status=error') do
  FC07['status'] == 'error'
end

check('P9-FC-07b: depth > 8 error mentions "max call depth"') do
  FC07['error'].to_s.include?('max call depth')
end

check('P9-FC-07c: depth > 8 error states the limit (8)') do
  FC07['error'].to_s.include?('8')
end

# ── P9-REG ────────────────────────────────────────────────────────────────────
section 'P9-REG: P7 regression — multi_contract_entrypoints.ig still green'

check('P9-REG-01: multi_contract_entrypoints.ig compiles ok') do
  P7_RESULT['status'] == 'ok'
end

check('P9-REG-02: Double, IsSmall, RouteGate all present') do
  contracts = P7_RESULT['contracts'] || []
  %w[Double IsSmall RouteGate].all? { |c| contracts.include?(c) }
end

REG_DBL = run_vm(P7_IGAPP, { 'n' => 7 }, entry_name: 'Double')
check('P9-REG-03: --entry Double n=7 → 14') do
  REG_DBL['status'] == 'success' && REG_DBL['result'] == 14
end

REG_SMALL = run_vm(P7_IGAPP, { 'n' => 7 }, entry_name: 'IsSmall')
check('P9-REG-04: --entry IsSmall n=7 → true') do
  REG_SMALL['status'] == 'success' && REG_SMALL['result'] == true
end

REG_GATE = run_vm(P7_IGAPP, { 'method' => 'GET', 'path' => '/' }, entry_name: 'RouteGate')
check('P9-REG-05: --entry RouteGate GET / → 200') do
  REG_GATE['status'] == 'success' && REG_GATE['result'] == 200
end

REG_DFLT = run_vm(P7_IGAPP, { 'n' => 3 })
check('P9-REG-06: no --entry → contracts[0] (default behavior preserved)') do
  REG_DFLT['status'] == 'success'
end

# ── P9-CLOSED ─────────────────────────────────────────────────────────────────
section 'P9-CLOSED: closed-surface scan'

SOURCE = File.read(__FILE__)

check('P9-CLOSED-01: no TCP/UDP socket use in proof source') do
  !SOURCE.include?('TCPSo' + 'cket') &&
  !SOURCE.include?('UDPSo' + 'cket') &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('P9-CLOSED-02: no network I/O calls in proof source') do
  !SOURCE.include?('Net::HT' + 'TP') &&
  !SOURCE.include?("require 'net/ht" + "tp'")
end

check('P9-CLOSED-03: no compiler-pipeline invocation in proof source') do
  !SOURCE.include?('igc' + '-run') &&
  !SOURCE.include?('igc' + ' run')
end

check('P9-CLOSED-04: no production API or runtime claims in source') do
  !SOURCE.include?('stable-' + 'API') &&
  !SOURCE.include?('public' + '-runtime') &&
  !SOURCE.include?('Rack-comp' + 'atible')
end

check('P9-CLOSED-05: call_contract is lab-only — proof makes no canon claim') do
  !SOURCE.include?('canon' + ' contract dispatch') &&
  !SOURCE.include?('stable' + ' dispatch')
end

# ── P9-GAP ────────────────────────────────────────────────────────────────────
section 'P9-GAP: gap packet'

GAP_PACKET = {
  card:      'LAB-RACK-P9',
  date:      '2026-06-08',
  authority: 'lab-only — no canon claim, no stable API surface',

  closed_by_p9: {
    call_contract_dispatch: {
      description: 'call_contract("ContractName", args...) dispatches to a ' \
                   'named contract in the same igapp at VM runtime',
      mechanism:   'Pre-built dispatch table (HashMap<String, DispatchEntry>) ' \
                   'compiled at igapp load time; callee executed in isolated ' \
                   'frame with fresh inputs and updated call chain/depth',
      fail_closed: 'unknown callee, arity mismatch, non-pure callee, ' \
                   'self-recursion, A→B→A cycles, depth > 8 all error clearly'
    }
  },

  v0_policy: {
    pure_callee_only: {
      status: 'enforced',
      detail: 'Only pure contracts may be called; effect/privileged callee → error'
    },
    no_cycles_or_recursion: {
      status: 'enforced',
      detail: 'Call chain tracked in temporal_context; any repeat name → error'
    },
    max_depth_8: {
      status: 'enforced',
      detail: 'MAX_CALL_DEPTH=8; exceeding → clear error message'
    }
  },

  still_open: {
    non_pure_callee: {
      status: 'deferred',
      detail: 'Effect/query/trusted callee dispatch not in v0 scope'
    },
    multi_output_callee: {
      status: 'deferred',
      detail: 'Callee returning multiple named outputs not handled; ' \
              'VM returns single result value'
    },
    output_type_verification: {
      status: 'deferred',
      detail: 'call_contract returns Unknown type at compile time; ' \
              'actual output type correctness is VM-runtime-only in v0'
    },
    contractref_type_semantics: {
      status: 'deferred',
      detail: 'ContractRef type in igniter-lang canon is out of scope for lab'
    }
  },

  deferred:   'non-pure callee; multi-output callee; output-type verification; ContractRef canon',
  next_route: 'LAB-RACK-P10 (if opened): non-pure callee dispatch; or P9-hardening'
}.freeze

check('P9-GAP-01: gap packet has closed_by_p9 with call_contract_dispatch') do
  GAP_PACKET[:closed_by_p9].key?(:call_contract_dispatch)
end

check('P9-GAP-02: gap packet v0_policy has pure_callee_only enforced') do
  GAP_PACKET[:v0_policy][:pure_callee_only][:status] == 'enforced'
end

check('P9-GAP-03: gap packet still_open contains output_type_verification') do
  GAP_PACKET[:still_open].key?(:output_type_verification)
end

check('P9-GAP-04: gap packet still_open contains contractref_type_semantics') do
  GAP_PACKET[:still_open].key?(:contractref_type_semantics)
end

# ── Summary ───────────────────────────────────────────────────────────────────
total   = RESULTS.size
passed  = RESULTS.count { |r| r[:passed] }
failed  = total - passed

puts "\n#{'═' * 72}"
puts "  LAB-RACK-P9: Explicit Named User-Contract Dispatch via call_contract"
puts "  #{passed}/#{total} PASS#{failed > 0 ? " — FAILURES: #{FAILURES.join(', ')}" : ''}"
puts "#{'═' * 72}"

exit(failed > 0 ? 1 : 0)
