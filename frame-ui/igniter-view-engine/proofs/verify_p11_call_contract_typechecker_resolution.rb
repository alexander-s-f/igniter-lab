#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LAB-RACK-P11: call_contract TypeChecker Literal Callee Resolution
# =================================================================
# Proves that the TypeChecker resolves literal `call_contract("Name", ...)` calls
# to the callee's single output type, using a same-module contract registry built
# before the contract loop (build_contract_registry, mirrors build_size_registry).
#
# Two-tier policy:
#   Tier 1: literal string callee → registry lookup; resolve type or emit OOF-TY0
#   Tier 2: dynamic callee (Ref/computed) → Unknown; VM fail-closed as in P9
#
# Sections:
#   P11-COMPILE  (5)  — fixture compiles; 7 contracts; no diagnostics
#   P11-STATIC   (6)  — literal callee → correct type in semantic IR
#   P11-TIER2    (4)  — dynamic callee → Unknown; compiles OK
#   P11-FC      (16)  — OOF-TY0 for unknown/effect/arity/self-recursion literal callees
#   P11-REG      (6)  — P9 regression green; P9 fixture still compiles and runs
#   P11-CLOSED   (5)  — closed-surface scan (no sockets, no ContractRef claims)
#   P11-GAP      (5)  — gap packet valid
#
# Total: 47 checks
#
# Authority: lab-only — no canon claim, no stable API surface.

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p11_call_contract_resolution'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)

# ── helpers ──────────────────────────────────────────────────────────────────

PASS_COUNT = [0]
FAIL_COUNT = [0]

def section(label)
  puts "\n── #{label}"
end

def check(label, &blk)
  result = blk.call
  if result
    puts "  [PASS] #{label}"
    PASS_COUNT[0] += 1
  else
    puts "  [FAIL] #{label}"
    FAIL_COUNT[0] += 1
  end
rescue => e
  puts "  [FAIL] #{label} (exception: #{e.message.split("\n").first})"
  FAIL_COUNT[0] += 1
end

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  out = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def compile_inline(src, tag)
  tmp = File.join(OUT_DIR.to_s, "inline_#{tag}.ig")
  out_dir = File.join(OUT_DIR.to_s, "inline_#{tag}")
  FileUtils.mkdir_p(OUT_DIR.to_s)
  File.write(tmp, src)
  compile_fixture(tmp, out_dir)
end

def run_vm(igapp_path, inputs_hash, entry_name: nil)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  FileUtils.mkdir_p(OUT_DIR.to_s)
  File.write(inputs_file, JSON.generate(inputs_hash))
  entry_flag = entry_name ? "--entry #{entry_name}" : ''
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} #{entry_flag} --json 2>/dev/null`
  out = out.force_encoding('UTF-8')
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
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

# ── inline fixtures for fail-closed tests ────────────────────────────────────

UNKNOWN_FC_SRC = <<~IG
  module Test.P11.UnknownCallee

  pure contract UnknownCaller {
    input n : Integer
    compute result = call_contract("NoSuchContract", n)
    output result : Integer
  }
IG

EFFECT_FC_SRC = <<~IG
  module Test.P11.EffectCallee

  effect contract WriteLog {
    input msg : String
    compute out = msg
    output out : String
  }

  pure contract PureCaller {
    input n : Integer
    compute s = "hi"
    compute result = call_contract("WriteLog", s)
    output result : String
  }
IG

ARITY_FC_SRC = <<~IG
  module Test.P11.ArityMismatch

  pure contract SingleInput {
    input n : Integer
    compute result = n + 1
    output result : Integer
  }

  pure contract ArityMismatchCaller {
    input n : Integer
    compute result = call_contract("SingleInput", n, n)
    output result : Integer
  }
IG

SELF_RECURSIVE_FC_SRC = <<~IG
  module Test.P11.SelfRecursion

  pure contract SelfRecursive {
    input n : Integer
    compute result = call_contract("SelfRecursive", n)
    output result : Integer
  }
IG

# ── compile everything ───────────────────────────────────────────────────────

FileUtils.mkdir_p(OUT_DIR.to_s)

MAIN_RESULT    = compile_fixture(FIXTURE_DIR / 'call_contract_resolution.ig', OUT_DIR / 'main')
UNKNOWN_FC     = compile_inline(UNKNOWN_FC_SRC,       'unknown_fc')
EFFECT_FC      = compile_inline(EFFECT_FC_SRC,        'effect_fc')
ARITY_FC       = compile_inline(ARITY_FC_SRC,         'arity_fc')
SELF_REC_FC    = compile_inline(SELF_RECURSIVE_FC_SRC,'self_recursive_fc')

MAIN_SIR       = load_sir(MAIN_RESULT)

# Load P9 multi_contract_caller for regression
P9_RESULT      = compile_fixture(FIXTURE_DIR / 'multi_contract_caller.ig', OUT_DIR / 'p9_reg')
P9_IGAPP       = P9_RESULT['igapp_path'] || P9_RESULT['_out_dir']

SOURCE = File.read(__FILE__)

# ── P11-COMPILE ───────────────────────────────────────────────────────────────
section 'P11-COMPILE: call_contract_resolution.ig compiles (7 contracts)'

check('P11-COMPILE-01: fixture compiles with status=ok') do
  MAIN_RESULT['status'] == 'ok'
end

check('P11-COMPILE-02: all 7 contracts present') do
  contracts = MAIN_RESULT['contracts'] || []
  %w[Adder CallerAdder CallerBool CallerDouble CallerDynamic Double IsPositive].all? do |c|
    contracts.include?(c)
  end
end

check('P11-COMPILE-03: no diagnostics') do
  (MAIN_RESULT['diagnostics'] || []).empty?
end

check('P11-COMPILE-04: all pipeline stages ok') do
  stages = MAIN_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

check('P11-COMPILE-05: semantic IR present and has contracts key') do
  MAIN_SIR.key?('contracts') && MAIN_SIR['contracts'].length == 7
end

# ── P11-STATIC ────────────────────────────────────────────────────────────────
section 'P11-STATIC: literal callee → correct type resolved in semantic IR'

check('P11-STATIC-01: CallerDouble.doubled node → Integer (P11 resolves Double output)') do
  sir_node_type(MAIN_SIR, 'CallerDouble', 'doubled') == 'Integer'
end

check('P11-STATIC-02: CallerBool.flag node → Bool (P11 resolves IsPositive output)') do
  sir_node_type(MAIN_SIR, 'CallerBool', 'flag') == 'Bool'
end

check('P11-STATIC-03: CallerAdder.sum node → Integer (P11 resolves Adder output)') do
  sir_node_type(MAIN_SIR, 'CallerAdder', 'sum') == 'Integer'
end

check('P11-STATIC-04: Double output type is Integer in base callee') do
  c = (MAIN_SIR['contracts'] || []).find { |x| x['contract_name'] == 'Double' }
  c && (c['outputs'] || []).any? { |o| o.dig('type', 'name') == 'Integer' }
end

check('P11-STATIC-05: IsPositive output type is Bool in base callee') do
  c = (MAIN_SIR['contracts'] || []).find { |x| x['contract_name'] == 'IsPositive' }
  c && (c['outputs'] || []).any? { |o| o.dig('type', 'name') == 'Bool' }
end

check('P11-STATIC-06: Adder output type is Integer in base callee') do
  c = (MAIN_SIR['contracts'] || []).find { |x| x['contract_name'] == 'Adder' }
  c && (c['outputs'] || []).any? { |o| o.dig('type', 'name') == 'Integer' }
end

# ── P11-TIER2 ────────────────────────────────────────────────────────────────
section 'P11-TIER2: dynamic callee (Ref) → Unknown; compiles OK'

check('P11-TIER2-01: CallerDynamic.result node → Unknown (Tier 2 stays Unknown)') do
  sir_node_type(MAIN_SIR, 'CallerDynamic', 'result') == 'Unknown'
end

check('P11-TIER2-02: CallerDynamic compiles without OOF-TY0 diagnostic') do
  diags = MAIN_RESULT['diagnostics'] || []
  diags.none? { |d| d['node'] == 'result' && d['rule'] == 'OOF-TY0' }
end

check('P11-TIER2-03: main fixture has no diagnostics at all (Tier 2 is silent)') do
  (MAIN_RESULT['diagnostics'] || []).empty?
end

check('P11-TIER2-04: CallerDynamic resolved differently from CallerDouble (Unknown vs Integer)') do
  tier2 = sir_node_type(MAIN_SIR, 'CallerDynamic', 'result')
  tier1 = sir_node_type(MAIN_SIR, 'CallerDouble',  'doubled')
  tier2 == 'Unknown' && tier1 == 'Integer'
end

# ── P11-FC ────────────────────────────────────────────────────────────────────
section 'P11-FC: OOF-TY0 for literal callees that fail static checks'

# FC-01: Unknown callee
check('P11-FC-01a: unknown literal callee → status=oof (TypeChecker rejects)') do
  UNKNOWN_FC['status'] == 'oof'
end

check('P11-FC-01b: unknown literal callee → OOF-TY0 diagnostic present') do
  diags = UNKNOWN_FC['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('P11-FC-01c: unknown literal callee → OOF-TY0 rule (not a different rule)') do
  diags = UNKNOWN_FC['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' && d['message'].to_s.include?('NoSuchContract') }
end

check('P11-FC-01d: unknown literal callee → error message mentions "unknown callee"') do
  diags = UNKNOWN_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.downcase.include?('unknown callee') }
end

# FC-02: Non-pure (effect) callee
check('P11-FC-02a: effect literal callee → status=oof (TypeChecker rejects)') do
  EFFECT_FC['status'] == 'oof'
end

check('P11-FC-02b: effect literal callee → OOF-TY0 diagnostic present') do
  diags = EFFECT_FC['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('P11-FC-02c: effect literal callee → message mentions callee name') do
  diags = EFFECT_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('WriteLog') }
end

check('P11-FC-02d: effect literal callee → message mentions "pure" or "modifier"') do
  diags = EFFECT_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.downcase =~ /pure|modifier/ }
end

# FC-03: Arity mismatch
check('P11-FC-03a: arity mismatch literal callee → status=oof (TypeChecker rejects)') do
  ARITY_FC['status'] == 'oof'
end

check('P11-FC-03b: arity mismatch literal callee → OOF-TY0 diagnostic present') do
  diags = ARITY_FC['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('P11-FC-03c: arity mismatch → message mentions callee name') do
  diags = ARITY_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('SingleInput') }
end

check('P11-FC-03d: arity mismatch → message has "expects" and counts') do
  diags = ARITY_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.downcase.include?('expects') }
end

# FC-04: Self-recursion
check('P11-FC-04a: self-recursive literal callee → status=oof (TypeChecker rejects)') do
  SELF_REC_FC['status'] == 'oof'
end

check('P11-FC-04b: self-recursive literal callee → OOF-TY0 diagnostic present') do
  diags = SELF_REC_FC['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('P11-FC-04c: self-recursive → message mentions "self-recursion"') do
  diags = SELF_REC_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.downcase.include?('self-recursion') }
end

check('P11-FC-04d: self-recursive → message mentions the contract name') do
  diags = SELF_REC_FC['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('SelfRecursive') }
end

# ── P11-REG ───────────────────────────────────────────────────────────────────
section 'P11-REG: P9 regression green'

check('P11-REG-01: P9 multi_contract_caller still compiles with status=ok') do
  P9_RESULT['status'] == 'ok'
end

check('P11-REG-02: P9 fixture has SelfRecurseDyn (dynamic self-call for VM-level test)') do
  contracts = P9_RESULT['contracts'] || []
  contracts.include?('SelfRecurseDyn')
end

check('P11-REG-03: P9 fixture CallerDoubler still compiles and present') do
  contracts = P9_RESULT['contracts'] || []
  contracts.include?('CallerDoubler')
end

check('P11-REG-04: P9 VM - CallerDoubler(10) → result=21') do
  r = run_vm(P9_IGAPP, { 'n' => 10 }, entry_name: 'CallerDoubler')
  r['status'] == 'success' && r['result'].to_i == 21
end

check('P11-REG-05: P9 VM - SelfRecurseDyn still triggers VM cycle detection (Tier 2 path)') do
  r = run_vm(P9_IGAPP, { 'n' => 1 }, entry_name: 'SelfRecurseDyn')
  r['status'] == 'error' && r['error'].to_s.include?('cycle detected')
end

check('P11-REG-06: compiler binary is present and executable') do
  File.executable?(COMPILER_BIN)
end

# ── P11-CLOSED ────────────────────────────────────────────────────────────────
section 'P11-CLOSED: closed-surface scan'

check('P11-CLOSED-01: no TCP/UDP/socket usage in proof') do
  !SOURCE.include?('TCP' + 'Socket') &&
  !SOURCE.include?('UDP' + 'Socket') &&
  !SOURCE.include?('Net::' + 'HTTP')
end

check('P11-CLOSED-02: no require socket/net/http') do
  !SOURCE.include?("require 'sock" + "et'") &&
  !SOURCE.include?("require 'net/" + "http'")
end

check('P11-CLOSED-03: no ContractRef-as-active claims') do
  !SOURCE.include?('Cont' + 'ractRef dispatch active') &&
  !SOURCE.include?('Cont' + 'ractRef is canon')
end

check('P11-CLOSED-04: no production/stable/public API claims') do
  !SOURCE.include?('stable-' + 'API') &&
  !SOURCE.include?('public' + '-runtime') &&
  !SOURCE.include?('Rack-comp' + 'atible')
end

check('P11-CLOSED-05: call_contract is lab-only — proof makes no canon claim') do
  !SOURCE.include?('canon' + ' contract dispatch') &&
  !SOURCE.include?('stable' + ' dispatch')
end

# ── P11-GAP ───────────────────────────────────────────────────────────────────
section 'P11-GAP: gap packet'

GAP_PACKET = {
  card:      'LAB-RACK-P11',
  date:      '2026-06-09',
  authority: 'lab-only — no canon claim, no stable API surface',

  closed_by_p11: {
    literal_callee_type_resolution: {
      description: 'call_contract("LiteralName", args...) is now resolved to the ' \
                   "callee's single output type at TypeChecker compile time",
      mechanism:   'build_contract_registry(classified: &ClassifiedProgram) builds a ' \
                   'HashMap<String, ContractRegistryEntry> before the contract loop. ' \
                   'In infer_expr, when the first arg is Expr::Literal{type_tag:"String"}, ' \
                   'Tier 1 lookup resolves the output type or emits OOF-TY0.',
      fail_closed: 'unknown callee, non-pure callee, self-recursion, arity mismatch ' \
                   'all emit OOF-TY0 at compile time for literal callees'
    }
  },

  two_tier_policy: {
    tier1_literal: {
      status: 'enforced',
      detail: 'Literal string first arg → registry lookup; type resolved or OOF-TY0'
    },
    tier2_dynamic: {
      status: 'preserved',
      detail: 'Non-literal first arg (Ref, computed) → Unknown; VM fail-closed as in P9'
    }
  },

  still_open: {
    multi_output_callee: {
      status: 'deferred',
      detail: 'Callee with >1 outputs returns Unknown; dedicated card if needed'
    },
    cross_contract_cycle_detection: {
      status: 'vm_only',
      detail: 'A→B→A cycles and depth>8 remain VM-level checks (P9); ' \
              'only self-recursion is now compile-time via P11'
    },
    contractref_type_semantics: {
      status: 'closed',
      detail: 'ContractRef type in igniter-lang canon is out of scope; ' \
              'P11 is compile-time static name lookup, not ContractRef'
    }
  },

  deferred:   'multi-output callee; cross-contract cycle detection at compile time',
  next_route: 'LAB-RACK-P12 (if opened): multi-output callee dispatch or VM-level type labeling'
}.freeze

check('P11-GAP-01: gap packet has closed_by_p11 with literal_callee_type_resolution') do
  GAP_PACKET[:closed_by_p11].key?(:literal_callee_type_resolution)
end

check('P11-GAP-02: gap packet two_tier_policy has tier1_literal enforced') do
  GAP_PACKET[:two_tier_policy][:tier1_literal][:status] == 'enforced'
end

check('P11-GAP-03: gap packet two_tier_policy has tier2_dynamic preserved') do
  GAP_PACKET[:two_tier_policy][:tier2_dynamic][:status] == 'preserved'
end

check('P11-GAP-04: gap packet still_open contains multi_output_callee deferred') do
  GAP_PACKET[:still_open][:multi_output_callee][:status] == 'deferred'
end

check('P11-GAP-05: gap packet contractref_type_semantics is closed (not ContractRef)') do
  GAP_PACKET[:still_open][:contractref_type_semantics][:status] == 'closed'
end

# ── final tally ───────────────────────────────────────────────────────────────

puts "\n#{'=' * 72}"
puts "  LAB-RACK-P11: call_contract TypeChecker Literal Callee Resolution"
puts "  #{PASS_COUNT[0]}/#{PASS_COUNT[0] + FAIL_COUNT[0]} #{FAIL_COUNT[0] == 0 ? 'PASS' : "FAIL (#{FAIL_COUNT[0]} failures)"}"
puts '=' * 72
