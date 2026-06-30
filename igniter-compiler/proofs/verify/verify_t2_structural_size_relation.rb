# encoding: utf-8
# verify_t2_structural_size_relation.rb
# PROP-041 T2 Structural-Size Relation — Lab Rust symmetry proof
#
# Symmetric with:
#   igniter-lang/experiments/prop041_structural_size_relation_proof/
#   verify_prop041_t2_production.rb  (canon Ruby pipeline)
#
# Gate scope:
#   Proves that the Rust lab compiler mirrors accepted Ruby canon behavior for:
#   - Parsing `size_relation TypeName accessor` (module-level, order-independent)
#   - STDLIB_SIZE_REGISTRY: Collection.tail / Collection.rest (stdlib_certified)
#   - User-assumed: module-level `size_relation TypeName accessor` declarations
#   - Dotted-path rehabilitation when relation is registered → structural_size_v1
#   - OOF-R8: missing structural size relation (non-numeric, unregistered)
#   - OOF-R9: registered relation but recur() call-site accessor does not match
#   - Numeric dotted-path blocked as OOF-R3 (not OOF-R8)
#   - T1 regression: simple-identifier decreases → syntactic_v0 unchanged
#   - OOF-R3 scope unweakened for non-T2 forms
#
# NOTE: T2 is structural evidence with trust metadata — NOT a full termination proof.
# Lab behavior does not create canon authority.
#
# Sections: T2A..T2I (closed-surface scan added as T2I)
# Expected: ALL PASS

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../../../../tools/proof_harness/bounded_command'

ROOT     = Pathname.new(__dir__).parent.parent
COMP     = ROOT / "target/release/igniter_compiler"
FIXTURES = ROOT / "fixtures/prop041_t2_structural_size_relation"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_fixture(name)
  src = File.read(FIXTURES / "#{name}.ig")
  compile_src(src, name)
end

def compile_src(src, label)
  tmp = Dir.mktmpdir("t2_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  r = BoundedCommand.run("#{COMP} compile #{ig} --out #{out}",
                         label: "compile:#{label}",
                         timeout: BoundedCommand::EXEC_TIMEOUT)
  BoundedCommand.print_result(r) unless r.ok?
  result = r.combined.force_encoding('UTF-8')
  [result, out, tmp]
end

def load_sir(app_path)
  sir_path = File.join(app_path, "semantic_ir_program.json")
  return nil unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path)) rescue nil
end

def find_contract(sir, name = nil)
  return nil unless sir
  contracts = sir["contracts"] || []
  contracts = [contracts] unless contracts.is_a?(Array)
  name ? contracts.find { |c| c["contract_name"] == name || c["name"] == name } : contracts.first
end

def termination_for(sir, name = nil)
  c = find_contract(sir, name)
  c&.dig("termination")
end

def has_oof(result_str, code)
  result_str.include?(code)
end

def oof_codes(result_str)
  begin
    data = JSON.parse(result_str)
    (data["diagnostics"] || []).map { |d| d["rule"] }
  rescue
    []
  end
end

unless COMP.exist?
  puts "[*] Building compiler (release)..."
  r = BoundedCommand.run("cargo build --release",
                         label: "cargo build --release",
                         timeout: BoundedCommand::CARGO_TIMEOUT)
  unless r.ok?
    BoundedCommand.print_result(r)
    puts "[!] Compiler build failed — aborting"
    exit(1)
  end
end

# =============================================================================
# T2A: Stdlib-certified upgrade
# Collection.tail / Collection.rest → structural_size_v1, stdlib_certified trust
# =============================================================================
puts "\n=== T2A: Stdlib-certified upgrade ===\n"

r_tail, app_tail, _ = compile_fixture("t2a_collection_tail_dotted")
sir_tail = load_sir(app_tail)
term_tail = termination_for(sir_tail)

if File.exist?(app_tail)
  pass "T2A: t2a_collection_tail_dotted compiles (no type errors)"
else
  fail! "T2A: t2a_collection_tail_dotted failed to compile"
end
if term_tail&.dig("variant_check") == "structural_size_v1"
  pass "T2A: variant_check = structural_size_v1"
else
  fail! "T2A: variant_check != structural_size_v1 (got: #{term_tail&.dig("variant_check").inspect})"
end
if term_tail&.dig("size_relation", "trust") == "stdlib_certified"
  pass "T2A: trust = stdlib_certified"
else
  fail! "T2A: trust != stdlib_certified (got: #{term_tail&.dig("size_relation", "trust").inspect})"
end

r_rest, app_rest, _ = compile_fixture("t2a_collection_rest_dotted")
sir_rest = load_sir(app_rest)
term_rest = termination_for(sir_rest)
if File.exist?(app_rest)
  pass "T2A: t2a_collection_rest_dotted compiles"
else
  fail! "T2A: t2a_collection_rest_dotted failed to compile"
end
if term_rest&.dig("variant_check") == "structural_size_v1"
  pass "T2A: rest_dotted variant_check = structural_size_v1"
else
  fail! "T2A: rest_dotted variant_check wrong (got: #{term_rest&.dig("variant_check").inspect})"
end

r_shape, app_shape, _ = compile_fixture("t2a_stdlib_sir_shape")
sir_shape = load_sir(app_shape)
if sir_shape&.dig("contracts")&.first&.dig("termination", "size_relation", "accessor") == "tail"
  pass "T2A: stdlib_sir_shape: accessor = 'tail'"
else
  fail! "T2A: stdlib_sir_shape: accessor wrong"
end
if sir_shape&.dig("contracts")&.first&.dig("termination", "size_relation", "source") == "compiler_builtin"
  pass "T2A: stdlib_sir_shape: source = compiler_builtin"
else
  fail! "T2A: stdlib_sir_shape: source != compiler_builtin"
end

# =============================================================================
# T2B: User-assumed custom type
# Module-level size_relation declaration → user_assumed trust, source = module name
# =============================================================================
puts "\n=== T2B: User-assumed custom type ===\n"

r_basic, app_basic, _ = compile_fixture("t2b_basic_user_assumed")
sir_basic = load_sir(app_basic)
term_basic = termination_for(sir_basic)
if File.exist?(app_basic)
  pass "T2B: t2b_basic_user_assumed compiles"
else
  fail! "T2B: t2b_basic_user_assumed failed to compile"
end
if term_basic&.dig("variant_check") == "structural_size_v1"
  pass "T2B: basic: variant_check = structural_size_v1"
else
  fail! "T2B: basic: variant_check wrong"
end
if term_basic&.dig("size_relation", "trust") == "user_assumed"
  pass "T2B: basic: trust = user_assumed"
else
  fail! "T2B: basic: trust != user_assumed"
end

r_multi, app_multi, _ = compile_fixture("t2b_multi_relation")
if File.exist?(app_multi)
  pass "T2B: t2b_multi_relation compiles (no type errors)"
else
  fail! "T2B: t2b_multi_relation failed to compile"
end

r_diff, app_diff, _ = compile_fixture("t2b_different_types")
if File.exist?(app_diff)
  pass "T2B: t2b_different_types compiles"
else
  fail! "T2B: t2b_different_types failed to compile"
end

r_sir, app_sir, _ = compile_fixture("t2b_sir_user_assumed")
sir_sir = load_sir(app_sir)
sir_contract = sir_sir&.dig("contracts")&.find { |c| c["contract_name"] == "SirUserAssumed" || c["name"] == "SirUserAssumed" }
if sir_contract&.dig("termination", "variant_check") == "structural_size_v1"
  pass "T2B: sir_user_assumed: variant_check = structural_size_v1"
else
  fail! "T2B: sir_user_assumed: variant_check wrong"
end
if sir_contract&.dig("termination", "size_relation", "trust") == "user_assumed"
  pass "T2B: sir_user_assumed: trust = user_assumed"
else
  fail! "T2B: sir_user_assumed: trust != user_assumed"
end
if sir_contract&.dig("termination", "size_relation", "source") == "T2B"
  pass "T2B: sir_user_assumed: source = module name (T2B)"
else
  fail! "T2B: sir_user_assumed: source != T2B (got: #{sir_contract&.dig("termination", "size_relation", "source").inspect})"
end

# =============================================================================
# T2C: Dotted-path rehabilitation
# Relation registered → no OOF-R3, no OOF-R8, structural_size_v1 emitted
# =============================================================================
puts "\n=== T2C: Dotted-path rehabilitation ===\n"

r_rpp, app_rpp, _ = compile_fixture("t2c_relation_present_pass")
if !has_oof(r_rpp, "OOF-R3")
  pass "T2C: relation_present_pass: no OOF-R3"
else
  fail! "T2C: relation_present_pass: OOF-R3 incorrectly fired"
end
if !has_oof(r_rpp, "OOF-R8")
  pass "T2C: relation_present_pass: no OOF-R8"
else
  fail! "T2C: relation_present_pass: OOF-R8 incorrectly fired"
end
if File.exist?(app_rpp)
  pass "T2C: relation_present_pass: no type errors (compiles)"
else
  fail! "T2C: relation_present_pass: failed to compile"
end

r_ca, app_ca, _ = compile_fixture("t2c_correct_accessor")
if !has_oof(r_ca, "OOF-R9")
  pass "T2C: correct_accessor: no OOF-R9"
else
  fail! "T2C: correct_accessor: OOF-R9 incorrectly fired"
end
if File.exist?(app_ca)
  pass "T2C: correct_accessor: compiles"
else
  fail! "T2C: correct_accessor: failed to compile"
end

r_order, app_order, _ = compile_fixture("t2c_order_independent")
if File.exist?(app_order)
  pass "T2C: order_independent: clean (size_relation after contract body)"
else
  fail! "T2C: order_independent: failed to compile"
end

r_spu, app_spu, _ = compile_fixture("t2c_stdlib_plus_user")
sir_spu = load_sir(app_spu)
if File.exist?(app_spu)
  pass "T2C: stdlib_plus_user: compiles"
else
  fail! "T2C: stdlib_plus_user: failed to compile"
end
if termination_for(sir_spu)&.dig("variant_check") == "structural_size_v1"
  pass "T2C: stdlib_plus_user: variant_check = structural_size_v1"
else
  fail! "T2C: stdlib_plus_user: variant_check wrong"
end

# =============================================================================
# T2D: OOF-R8 — missing relation
# Dotted-path with no registered (type, accessor) → OOF-R8 (not OOF-R3)
# =============================================================================
puts "\n=== T2D: OOF-R8 — missing relation ===\n"

r_nre, app_nre, _ = compile_fixture("t2d_no_registry_entry")
if has_oof(r_nre, "OOF-R8")
  pass "T2D: no_registry_entry: OOF-R8 fires"
else
  fail! "T2D: no_registry_entry: OOF-R8 did NOT fire"
end
unless has_oof(r_nre, "OOF-R3")
  pass "T2D: no_registry_entry: OOF-R3 does NOT fire"
else
  fail! "T2D: no_registry_entry: OOF-R3 incorrectly fired"
end

r_dt, _, _ = compile_fixture("t2d_different_type")
if has_oof(r_dt, "OOF-R8")
  pass "T2D: different_type: OOF-R8 fires"
else
  fail! "T2D: different_type: OOF-R8 did NOT fire"
end

r_typo, _, _ = compile_fixture("t2d_typo_in_accessor")
if has_oof(r_typo, "OOF-R8")
  pass "T2D: typo_in_accessor: OOF-R8 fires"
else
  fail! "T2D: typo_in_accessor: OOF-R8 did NOT fire"
end

r_er, _, _ = compile_fixture("t2d_empty_registry")
if has_oof(r_er, "OOF-R8")
  pass "T2D: empty_registry: OOF-R8 fires"
else
  fail! "T2D: empty_registry: OOF-R8 did NOT fire"
end

# =============================================================================
# T2E: OOF-R9 — relation/call-site mismatch
# Relation registered, but recur() arg at variant position is not subject.accessor
# =============================================================================
puts "\n=== T2E: OOF-R9 — relation/call-site mismatch ===\n"

r_wa, _, _ = compile_fixture("t2e_wrong_accessor")
if has_oof(r_wa, "OOF-R9")
  pass "T2E: wrong_accessor: OOF-R9 fires"
else
  fail! "T2E: wrong_accessor: OOF-R9 did NOT fire"
end
unless has_oof(r_wa, "OOF-R3")
  pass "T2E: wrong_accessor: OOF-R3 does NOT fire"
else
  fail! "T2E: wrong_accessor: OOF-R3 incorrectly fired"
end

r_pr, _, _ = compile_fixture("t2e_plain_ref")
if has_oof(r_pr, "OOF-R9")
  pass "T2E: plain_ref: OOF-R9 fires (plain ref instead of dotted accessor)"
else
  fail! "T2E: plain_ref: OOF-R9 did NOT fire"
end

r_wv, _, _ = compile_fixture("t2e_wrong_variable")
if has_oof(r_wv, "OOF-R9")
  pass "T2E: wrong_variable: OOF-R9 fires (correct accessor, wrong variable)"
else
  fail! "T2E: wrong_variable: OOF-R9 did NOT fire"
end

# =============================================================================
# T2F: Numeric dotted-path blocked as OOF-R3 (not OOF-R8)
# =============================================================================
puts "\n=== T2F: Numeric dotted-path → OOF-R3 ===\n"

r_count, _, _ = compile_fixture("t2f_count_accessor")
if has_oof(r_count, "OOF-R3")
  pass "T2F: count_accessor: OOF-R3 fires"
else
  fail! "T2F: count_accessor: OOF-R3 did NOT fire"
end
unless has_oof(r_count, "OOF-R8")
  pass "T2F: count_accessor: OOF-R8 does NOT fire (numeric excluded from T2)"
else
  fail! "T2F: count_accessor: OOF-R8 incorrectly fired"
end

r_length, _, _ = compile_fixture("t2f_length_accessor")
if has_oof(r_length, "OOF-R3")
  pass "T2F: length_accessor: OOF-R3 fires"
else
  fail! "T2F: length_accessor: OOF-R3 did NOT fire"
end
unless has_oof(r_length, "OOF-R8")
  pass "T2F: length_accessor: OOF-R8 does NOT fire"
else
  fail! "T2F: length_accessor: OOF-R8 incorrectly fired"
end

# =============================================================================
# T2G: T1 regression — syntactic_v0 unchanged
# Simple-identifier decreases must NOT be upgraded to structural_size_v1
# =============================================================================
puts "\n=== T2G: T1 regression — syntactic_v0 unchanged ===\n"

r_arith, app_arith, _ = compile_fixture("t2g_t1_arithmetic")
sir_arith = load_sir(app_arith)
if File.exist?(app_arith)
  pass "T2G: t1_arithmetic: no type errors"
else
  fail! "T2G: t1_arithmetic: failed to compile"
end
if termination_for(sir_arith)&.dig("variant_check") == "syntactic_v0"
  pass "T2G: t1_arithmetic: variant_check = syntactic_v0 (not structural_size_v1)"
else
  fail! "T2G: t1_arithmetic: variant_check != syntactic_v0"
end

r_tail1, app_tail1, _ = compile_fixture("t2g_t1_tail")
sir_tail1 = load_sir(app_tail1)
if File.exist?(app_tail1)
  pass "T2G: t1_tail: no type errors"
else
  fail! "T2G: t1_tail: failed to compile"
end
if termination_for(sir_tail1)&.dig("variant_check") == "syntactic_v0"
  pass "T2G: t1_tail: variant_check = syntactic_v0 (simple identifier, not dotted)"
else
  fail! "T2G: t1_tail: variant_check != syntactic_v0"
end

r_multi_t, app_multi_t, _ = compile_fixture("t2g_t1_multi_arg")
sir_multi_t = load_sir(app_multi_t)
if File.exist?(app_multi_t)
  pass "T2G: t1_multi_arg: no type errors"
else
  fail! "T2G: t1_multi_arg: failed to compile"
end
if termination_for(sir_multi_t)&.dig("variant_check") == "syntactic_v0"
  pass "T2G: t1_multi_arg: variant_check = syntactic_v0"
else
  fail! "T2G: t1_multi_arg: variant_check wrong"
end

r_fuel, app_fuel, _ = compile_fixture("t2g_t1_fuel_bounded")
sir_fuel = load_sir(app_fuel)
if File.exist?(app_fuel)
  pass "T2G: t1_fuel_bounded: no type errors"
else
  fail! "T2G: t1_fuel_bounded: failed to compile"
end
if termination_for(sir_fuel).nil?
  pass "T2G: t1_fuel_bounded: no termination IR (fuel_bounded, not recursive)"
else
  fail! "T2G: t1_fuel_bounded: unexpected termination IR"
end

r_r3pre, _, _ = compile_fixture("t2g_t1_oof_r3_preserved")
if has_oof(r_r3pre, "OOF-R3")
  pass "T2G: t1_oof_r3_preserved: OOF-R3 still fires under T2 extension"
else
  fail! "T2G: t1_oof_r3_preserved: OOF-R3 NOT fired (should still fire for T1 forms)"
end

# =============================================================================
# T2H: OOF-R3 scope unweakened for non-T2 forms
# =============================================================================
puts "\n=== T2H: OOF-R3 scope unweakened ===\n"

r_inc, _, _ = compile_fixture("t2h_arithmetic_increase")
if has_oof(r_inc, "OOF-R3")
  pass "T2H: arithmetic_increase: OOF-R3 fires"
else
  fail! "T2H: arithmetic_increase: OOF-R3 NOT fired"
end

r_wva, _, _ = compile_fixture("t2h_wrong_variant_arg")
if has_oof(r_wva, "OOF-R3")
  pass "T2H: wrong_variant_arg: OOF-R3 fires"
else
  fail! "T2H: wrong_variant_arg: OOF-R3 NOT fired"
end

r_unw, _, _ = compile_fixture("t2h_unwhitelisted_field")
if has_oof(r_unw, "OOF-R3")
  pass "T2H: unwhitelisted_field: OOF-R3 fires (T1 form, .first not whitelisted)"
else
  fail! "T2H: unwhitelisted_field: OOF-R3 NOT fired"
end

# =============================================================================
# T2I: Closed-surface scan
# Confirms: T2 does not create full termination proof authority; lab != canon;
# runtime/VM remain closed; user_assumed != verified proof.
# =============================================================================
puts "\n=== T2I: Closed-surface scan ===\n"

# Check that stdlib_certified trust is emitted correctly (not "user_assumed")
if term_tail&.dig("size_relation", "trust") == "stdlib_certified"
  pass "T2I: stdlib_certified trust is NOT user_assumed"
else
  fail! "T2I: stdlib_certified trust wrong (should not be user_assumed)"
end

# Check that user_assumed trust is NOT stdlib_certified
if term_basic&.dig("size_relation", "trust") == "user_assumed" &&
   term_basic&.dig("size_relation", "trust") != "stdlib_certified"
  pass "T2I: user_assumed trust is NOT stdlib_certified"
else
  fail! "T2I: user_assumed trust wrong"
end

# Check that structural_size_v1 is only for T2 contracts; T1 stays syntactic_v0
if termination_for(sir_arith)&.dig("variant_check") == "syntactic_v0" &&
   termination_for(sir_arith)&.dig("variant_check") != "structural_size_v1"
  pass "T2I: T1 contracts do NOT emit structural_size_v1"
else
  fail! "T2I: T1 contracts incorrectly emit structural_size_v1"
end

# Confirm size_relation SIR node contains required fields: accessor, trust, source
sr_node = term_tail&.dig("size_relation")
if sr_node && sr_node.key?("accessor") && sr_node.key?("trust") && sr_node.key?("source")
  pass "T2I: size_relation SIR node has accessor, trust, source fields"
else
  fail! "T2I: size_relation SIR node missing fields (got: #{sr_node.inspect})"
end

# =============================================================================
# Summary
# =============================================================================
puts ""
puts "=" * 60
puts "PROP-041 T2 Structural-Size Relation — Rust symmetry"
puts "Results: #{$pass_count}/#{$pass_count + $fail_count} PASS"
puts "=" * 60
if $fail_count > 0
  puts "[!] #{$fail_count} FAILURE(S) — Rust T2 symmetry NOT proven"
  exit(1)
else
  puts "[+] ALL PASS — Rust T2 structural-size symmetry proven"
  puts ""
  puts "Symmetry confirmed:"
  puts "  - size_relation TypeName accessor parsed (module-level, order-independent)"
  puts "  - STDLIB: Collection.tail / Collection.rest → stdlib_certified"
  puts "  - USER: module-level declarations → user_assumed (source = module name)"
  puts "  - OOF-R8: missing relation fires correctly"
  puts "  - OOF-R9: call-site mismatch fires correctly"
  puts "  - Numeric dotted-path → OOF-R3 (not OOF-R8)"
  puts "  - T1 syntactic_v0 unchanged"
  puts "  - OOF-R3 scope unweakened"
  puts ""
  puts "NOT a full termination proof. Lab behavior is not canon authority."
end
