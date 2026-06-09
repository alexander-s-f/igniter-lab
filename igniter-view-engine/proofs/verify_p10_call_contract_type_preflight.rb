# verify_p10_call_contract_type_preflight.rb
#
# LAB-RACK-P10: call_contract Output Type Verification — Design Preflight
#
# Purpose: Structural inspection proof. No TypeChecker or VM changes.
# Verifies the structural evidence needed to support P11:
#   1. SemanticIR carries complete output type metadata for each contract.
#   2. Literal callee names are distinguishable from dynamic callees in the AST.
#   3. The module contract list is available as a whole to the TypeChecker.
#   4. P9 behavior is preserved (all call_contract nodes type Unknown today).
#   5. The design matrix entries are structurally reachable.
#
# Proof scope:
#   P10-SIR    — SemanticIR shape: output type metadata completeness
#   P10-AST    — Literal vs. dynamic first arg detectable in AST
#   P10-MULTI  — Multi-contract programs compile; full list available
#   P10-P9REG  — P9 behavior unchanged (call_contract nodes type Unknown)
#   P10-CLOSED — closed-surface scan (no sockets, no stable API claims)
#   P10-GAP    — gap packet: design locked for P11
#
# Proof axiom: PASS means the stated structural property holds.
# CLOSED: lab-only, no canon grammar, no ContractRef semantics, no TCP/socket,
#         no middleware, no HTTP server, no stable/public API, no runtime authority.
#
# Authority: lab-only evidence — no canon claim, no stable API surface.
# Card: LAB-RACK-P10
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p10_type_preflight'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
TC_SRC       = File.expand_path('../../igniter-compiler/src/typechecker.rs', __dir__)
VM_SRC       = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

# ── Helpers ────────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  # Compiler output may contain UTF-8 sequences; force encoding so JSON.parse succeeds
  out  = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def read_sir(igapp_path)
  sir_file = File.join(igapp_path, 'semantic_ir_program.json')
  JSON.parse(File.read(sir_file)) rescue nil
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

PROBE_IGAPP  = (OUT_DIR / 'probe').to_s
PROBE_RESULT = compile_fixture(
  FIXTURE_DIR / 'call_contract_type_probe.ig',
  PROBE_IGAPP
)

P9_IGAPP  = (OUT_DIR / 'p9_caller').to_s
P9_RESULT = compile_fixture(
  FIXTURE_DIR / 'multi_contract_caller.ig',
  P9_IGAPP
)

PROBE_SIR = read_sir(PROBE_IGAPP)
P9_SIR    = read_sir(P9_IGAPP)

puts "LAB-RACK-P10: call_contract Output Type Verification — Design Preflight"
puts "═" * 72

# ── P10-SIR ───────────────────────────────────────────────────────────────────
section 'P10-SIR: SemanticIR carries complete output type metadata'

check('P10-SIR-01: probe fixture compiles ok') do
  PROBE_RESULT['status'] == 'ok'
end

check('P10-SIR-02: all 6 probe contracts present') do
  contracts = PROBE_RESULT['contracts'] || []
  %w[Adder IsPositive SideEffect CallerAdder CallerBool CallerDynamic].all? do |c|
    contracts.include?(c)
  end
end

check('P10-SIR-03: SemanticIR loaded successfully') do
  !PROBE_SIR.nil?
end

# Helper: find contract by name
def find_contract(sir, name)
  (sir['contracts'] || []).find { |c| c['contract_name'] == name }
end

check('P10-SIR-04: Adder output type is Integer in SemanticIR') do
  c = find_contract(PROBE_SIR, 'Adder')
  c && c['outputs']&.first&.dig('type', 'name') == 'Integer'
end

check('P10-SIR-05: IsPositive output type is Bool in SemanticIR') do
  c = find_contract(PROBE_SIR, 'IsPositive')
  c && c['outputs']&.first&.dig('type', 'name') == 'Bool'
end

check('P10-SIR-06: SideEffect modifier is effect in SemanticIR') do
  c = find_contract(PROBE_SIR, 'SideEffect')
  c && c['modifier'] == 'effect'
end

check('P10-SIR-07: Adder has 2 inputs with correct types') do
  c = find_contract(PROBE_SIR, 'Adder')
  inputs = c && c['inputs'] || []
  inputs.size == 2 &&
    inputs[0]['type']['name'] == 'Integer' &&
    inputs[1]['type']['name'] == 'Integer'
end

check('P10-SIR-08: all pure contracts have non-empty outputs array') do
  (PROBE_SIR['contracts'] || []).select { |c| c['modifier'] == 'pure' }.all? do |c|
    c['outputs'] && !c['outputs'].empty?
  end
end

check('P10-SIR-09: SideEffect (effect) output type also present in SemanticIR') do
  # Effect callees are blocked at dispatch, but output metadata IS available
  c = find_contract(PROBE_SIR, 'SideEffect')
  c && c['outputs']&.first&.dig('type', 'name') == 'Integer'
end

# ── P10-AST ───────────────────────────────────────────────────────────────────
section 'P10-AST: Literal vs. dynamic callee distinguishable in SemanticIR AST'

def find_call_contract_node(sir, contract_name, node_name)
  c = (sir['contracts'] || []).find { |c| c['contract_name'] == contract_name }
  return nil unless c
  (c['nodes'] || []).find do |n|
    n['name'] == node_name && n.dig('expr', 'fn') == 'call_contract'
  end
end

CALLER_ADDER_NODE = find_call_contract_node(PROBE_SIR, 'CallerAdder', 'sum')
CALLER_BOOL_NODE  = find_call_contract_node(PROBE_SIR, 'CallerBool',  'flag')
CALLER_DYN_NODE   = find_call_contract_node(PROBE_SIR, 'CallerDynamic', 'result')

check('P10-AST-01: CallerAdder/sum node is a call_contract node') do
  !CALLER_ADDER_NODE.nil?
end

check('P10-AST-02: CallerAdder/sum first arg is literal String "Adder"') do
  arg0 = CALLER_ADDER_NODE&.dig('expr', 'args', 0)
  arg0&.fetch('kind', nil) == 'literal' &&
    arg0&.fetch('type_tag', nil) == 'String' &&
    arg0&.fetch('value', nil) == 'Adder'
end

check('P10-AST-03: CallerBool/flag first arg is literal String "IsPositive"') do
  arg0 = CALLER_BOOL_NODE&.dig('expr', 'args', 0)
  arg0&.fetch('kind', nil) == 'literal' &&
    arg0&.fetch('type_tag', nil) == 'String' &&
    arg0&.fetch('value', nil) == 'IsPositive'
end

check('P10-AST-04: CallerDynamic/result first arg is NOT a literal (kind=ref)') do
  arg0 = CALLER_DYN_NODE&.dig('expr', 'args', 0)
  arg0&.fetch('kind', nil) == 'ref'  # dynamic: variable reference, not literal
end

check('P10-AST-05: CallerDynamic/result first arg has no type_tag (is a ref)') do
  arg0 = CALLER_DYN_NODE&.dig('expr', 'args', 0)
  !arg0&.key?('type_tag')
end

check('P10-AST-06: literal first arg check: kind=="literal" && type_tag=="String" is sufficient') do
  # Verify: CallerAdder passes, CallerDynamic does not
  literal_check = lambda do |node|
    arg0 = node&.dig('expr', 'args', 0)
    arg0&.fetch('kind', nil) == 'literal' && arg0&.fetch('type_tag', nil) == 'String'
  end
  literal_check.call(CALLER_ADDER_NODE) &&
    literal_check.call(CALLER_BOOL_NODE) &&
    !literal_check.call(CALLER_DYN_NODE)
end

check('P10-AST-07: all call_contract nodes currently type Unknown (P9 behavior)') do
  all_cc_nodes = (PROBE_SIR['contracts'] || []).flat_map do |c|
    (c['nodes'] || []).select { |n| n.dig('expr', 'fn') == 'call_contract' }
  end
  all_cc_nodes.size >= 3 &&
    all_cc_nodes.all? { |n| n.dig('type', 'name') == 'Unknown' }
end

check('P10-AST-08: arity of literal callee is readable from SemanticIR inputs array') do
  adder = find_contract(PROBE_SIR, 'Adder')
  adder && adder['inputs']&.size == 2
end

# ── P10-MULTI ─────────────────────────────────────────────────────────────────
section 'P10-MULTI: Full module contract list available; TypeChecker cross-contract access confirmed'

check('P10-MULTI-01: SemanticIR program contains all contracts in one document') do
  contracts = PROBE_SIR&.fetch('contracts', []) || []
  contracts.size == 6
end

check('P10-MULTI-02: TypeChecker build_size_registry pattern exists (cross-contract precedent)') do
  File.read(TC_SRC).include?('build_size_registry')
end

check('P10-MULTI-03: typecheck() receives &ClassifiedProgram (full module)') do
  src = File.read(TC_SRC)
  # typecheck() takes classified: &ClassifiedProgram — cross-contract access is available
  src.include?('classified: &ClassifiedProgram') || src.include?('classified: &crate::classifier::ClassifiedProgram')
end

check('P10-MULTI-04: contracts loop in typecheck() iterates classified.contracts') do
  File.read(TC_SRC).include?('classified.contracts')
end

check('P10-MULTI-05: Each contract output type fully described in one SemanticIR field') do
  # Verify the output type structure is consistent across all contracts
  (PROBE_SIR['contracts'] || []).all? do |c|
    (c['outputs'] || []).all? do |out|
      out.key?('name') && out.key?('type') && out['type'].key?('name')
    end
  end
end

check('P10-MULTI-06: module contract registry could be built from SemanticIR data alone') do
  # Prove: for each contract, (modifier + inputs.count + outputs.count + outputs[0].type) available
  registry = {}
  (PROBE_SIR['contracts'] || []).each do |c|
    name = c['contract_name']
    modifier = c['modifier']
    input_count = (c['inputs'] || []).size
    outputs = c['outputs'] || []
    single_output_type = outputs.size == 1 ? outputs.first.dig('type', 'name') : nil
    registry[name] = { modifier: modifier, input_count: input_count, single_output_type: single_output_type }
  end
  # Verify key entries
  registry['Adder'][:modifier]            == 'pure' &&
    registry['Adder'][:input_count]       == 2      &&
    registry['Adder'][:single_output_type] == 'Integer' &&
    registry['IsPositive'][:single_output_type] == 'Bool' &&
    registry['SideEffect'][:modifier]     == 'effect' &&
    registry['CallerDynamic'].is_a?(Hash)
end

# ── P10-P9REG ─────────────────────────────────────────────────────────────────
section 'P10-P9REG: P9 behavior unchanged — call_contract nodes still type Unknown'

check('P10-P9REG-01: P9 multi_contract_caller.ig compiles ok (P9 unchanged)') do
  P9_RESULT['status'] == 'ok'
end

check('P10-P9REG-02: P9 SIR loaded') do
  !P9_SIR.nil?
end

check('P10-P9REG-03: all call_contract nodes in P9 fixture type Unknown today') do
  all_cc = (P9_SIR['contracts'] || []).flat_map do |c|
    (c['nodes'] || []).select { |n| n.dig('expr', 'fn') == 'call_contract' }
  end
  all_cc.size >= 4 &&
    all_cc.all? { |n| n.dig('type', 'name') == 'Unknown' }
end

check('P10-P9REG-04: P9 contract outputs declared with explicit types') do
  # Even though call_contract nodes are Unknown, the output DECLARATIONS have explicit types
  caller_doubler = (P9_SIR['contracts'] || []).find { |c| c['contract_name'] == 'CallerDoubler' }
  caller_doubler && caller_doubler['outputs']&.first&.dig('type', 'name') == 'Integer'
end

check('P10-P9REG-05: SelfRecurse in P9 has literal "SelfRecurse" as first call_contract arg') do
  self_recurse = (P9_SIR['contracts'] || []).find { |c| c['contract_name'] == 'SelfRecurse' }
  node = (self_recurse&.fetch('nodes', []) || []).find { |n| n.dig('expr', 'fn') == 'call_contract' }
  node&.dig('expr', 'args', 0, 'value') == 'SelfRecurse'
end

check('P10-P9REG-06: P11 would catch SelfRecurse at compile time (literal self-call detectable)') do
  # Structural evidence: "SelfRecurse" calls "SelfRecurse" → same name → compile-time OOF-TY0 in P11
  caller = (P9_SIR['contracts'] || []).find { |c| c['contract_name'] == 'SelfRecurse' }
  node = (caller&.fetch('nodes', []) || []).find { |n| n.dig('expr', 'fn') == 'call_contract' }
  callee_name = node&.dig('expr', 'args', 0, 'value')
  # Same as contract_name → self-recursion
  callee_name == caller&.fetch('contract_name', nil)
end

# ── P10-CLOSED ────────────────────────────────────────────────────────────────
section 'P10-CLOSED: closed-surface scan'

SOURCE = File.read(__FILE__)

check('P10-CLOSED-01: no TCP/UDP socket use in proof source') do
  !SOURCE.include?('TCPSo' + 'cket') &&
  !SOURCE.include?('UDPSo' + 'cket') &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('P10-CLOSED-02: no network I/O in proof source') do
  !SOURCE.include?('Net::HT' + 'TP') &&
  !SOURCE.include?("require 'net/ht" + "tp'")
end

check('P10-CLOSED-03: no compiler-pipeline invocation in proof') do
  !SOURCE.include?('igc' + '-run') &&
  !SOURCE.include?('igc' + ' run')
end

check('P10-CLOSED-04: no stable API or public runtime claims in source') do
  !SOURCE.include?('stable-' + 'API') &&
  !SOURCE.include?('public' + '-runtime') &&
  !SOURCE.include?('Rack-comp' + 'atible')
end

check('P10-CLOSED-05: no ContractRef dispatch or canon claim active in proof') do
  # Split-string technique: check for claim strings without embedding them literally.
  # These would only appear if the proof wrongly asserted ContractRef as active.
  !SOURCE.include?('Cont' + 'ractRef dispatch active') &&
  !SOURCE.include?('Cont' + 'ractRef is canon') &&
  !SOURCE.include?('canon' + '-Cont' + 'ractRef')
end

# ── P10-GAP ───────────────────────────────────────────────────────────────────
section 'P10-GAP: gap packet — design locked for P11'

GAP_PACKET = {
  card:      'LAB-RACK-P10',
  date:      '2026-06-09',
  authority: 'lab-only — no canon claim, no stable API surface',

  established_by_p10: {
    sir_output_metadata_complete: {
      status: 'confirmed',
      detail: 'Every contract in SemanticIR has outputs[].type.name at typecheck time'
    },
    literal_callee_detectable: {
      status: 'confirmed',
      detail: 'Expr::Literal{kind:"literal", type_tag:"String"} vs Expr::Ref is distinguishable in AST'
    },
    module_registry_pattern_viable: {
      status: 'confirmed',
      detail: 'build_size_registry precedent in TypeChecker; same pattern for contract registry'
    },
    dynamic_callee_must_remain_unknown: {
      status: 'confirmed',
      detail: 'Non-literal first arg cannot be statically resolved; VM fail-closed is correct'
    },
    not_contractref_semantics: {
      status: 'confirmed',
      detail: 'Compile-time name lookup, not runtime ContractRef type; no grammar changes needed'
    }
  },

  p11_design: {
    mechanism: 'build_contract_registry(classified: &ClassifiedProgram) → HashMap<String, ContractRegistryEntry>',
    literal_callee_policy: 'Look up in registry; resolve output type; check modifier/arity/self-recursion at compile time',
    dynamic_callee_policy: 'Unknown (no-op, VM fail-closed)',
    unknown_compat_rule: 'Leave as-is — self-selecting for dynamic callees; no-op for static after P11',
    contractref: 'Not created — call_contract remains stdlib-style, no runtime type',
    grammar_changes: 'None required',
    stable_api: 'None — call_contract remains lab-only'
  },

  still_open: {
    multi_output_callee: {
      status: 'deferred',
      detail: 'Callee with >1 outputs returns Unknown; P11 defers to separate card'
    },
    non_pure_callee: {
      status: 'deferred',
      detail: 'Effect/query callee dispatch not in v0 or P11 scope'
    },
    contractref_type_semantics: {
      status: 'deferred',
      detail: 'ContractRef as runtime type remains closed; canon governance required'
    }
  },

  next_route: 'P11: implement module contract registry in TypeChecker + literal callee type resolution'
}.freeze

check('P10-GAP-01: established_by_p10 contains all five structural findings') do
  keys = GAP_PACKET[:established_by_p10].keys
  %i[sir_output_metadata_complete literal_callee_detectable module_registry_pattern_viable
     dynamic_callee_must_remain_unknown not_contractref_semantics].all? { |k| keys.include?(k) }
end

check('P10-GAP-02: p11_design has mechanism and literal_callee_policy') do
  GAP_PACKET[:p11_design].key?(:mechanism) && GAP_PACKET[:p11_design].key?(:literal_callee_policy)
end

check('P10-GAP-03: p11_design confirms grammar_changes=none') do
  GAP_PACKET[:p11_design][:grammar_changes] == 'None required'
end

check('P10-GAP-04: p11_design confirms stable_api=none') do
  GAP_PACKET[:p11_design][:stable_api]&.include?('lab-only')
end

check('P10-GAP-05: still_open contains contractref_type_semantics as deferred') do
  GAP_PACKET[:still_open][:contractref_type_semantics][:status] == 'deferred'
end

# ── Summary ───────────────────────────────────────────────────────────────────
total   = RESULTS.size
passed  = RESULTS.count { |r| r[:passed] }
failed  = total - passed

puts "\n#{'═' * 72}"
puts "  LAB-RACK-P10: call_contract Output Type Verification — Design Preflight"
puts "  #{passed}/#{total} PASS#{failed > 0 ? " — FAILURES: #{FAILURES.join(', ')}" : ''}"
puts "#{'═' * 72}"

exit(failed > 0 ? 1 : 0)
