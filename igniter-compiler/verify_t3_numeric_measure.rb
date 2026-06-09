# encoding: utf-8
# verify_t3_numeric_measure.rb
# PROP-042 T3 Numeric Measure Expressions — Lab Rust symmetry proof
#
# Symmetric with:
#   igniter-lang/experiments/prop042_numeric_measure_proof/
#   verify_prop042_t3_production.rb  (canon Ruby pipeline, 45/45 PASS)
#
# Gate scope:
#   Proves that the Rust lab compiler mirrors accepted Ruby production behavior for:
#   - Parsing `decreases count(items)` function-call form structurally (no regex)
#   - T3 dispatch: count(items) → numeric_measure_v0 SemanticIR
#   - Exact §5.1 SIR shape: variant_check / numeric_measure {fn/arg/trust/source}
#   - OOF-R10: unrecognized/deferred measure functions (size/depth/byte_length)
#   - OOF-R11: recognized measure, recur() call-site not structurally covered
#   - T2 bridge: user_assumed size_relation satisfies T3 call-site obligation
#   - T1 regression: simple-identifier decreases → syntactic_v0 (unchanged)
#   - T2 regression: dotted-path decreases → structural_size_v1 (unchanged)
#   - Dotted numeric accessor (items.count) → OOF-R3, not OOF-R10
#   - Multi-recur all-pass and one-fail cases
#   - OOF-R9 still fires for T2 call-site mismatch (unchanged by T3 additions)
#
# NOTE: T3 is compiler-controlled evidence — NOT a full termination proof.
# Lab behavior does not create canon authority.
# Only count(Collection[T]) is accepted in NUMERIC_MEASURE_BUILTINS v0.
# Runtime/VM behavior remains closed.
#
# Expected: ALL PASS

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../tools/proof_harness/bounded_command'

ROOT     = Pathname.new(__dir__)
COMP     = ROOT / "target/release/igniter_compiler"
FIXTURES = ROOT / "fixtures/prop042_t3_numeric_measure"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_fixture(name)
  src = File.read(FIXTURES / "#{name}.ig")
  compile_src(src, name)
end

def compile_src(src, label)
  tmp = Dir.mktmpdir("t3_#{label}")
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

def oof_codes(result_str)
  JSON.parse(result_str).then { |d| (d["diagnostics"] || []).map { |e| e["rule"] } }
rescue
  []
end

def has_oof(result_str, code)
  oof_codes(result_str).include?(code)
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
# T3A: Clean T3 passes
# count(items) + stdlib Collection registration → numeric_measure_v0
# =============================================================================
puts "\n=== T3A: Clean T3 passes — numeric_measure_v0 ===\n"

r_tail, app_tail, _ = compile_fixture("t3a_count_tail")
sir_tail  = load_sir(app_tail)
term_tail = termination_for(sir_tail)

if File.exist?(app_tail)
  pass "T3A: count_tail: compiles (no type errors)"
else
  fail! "T3A: count_tail: failed to compile (got errors)"
end
if term_tail&.dig("variant_check") == "numeric_measure_v0"
  pass "T3A: count_tail: variant_check = numeric_measure_v0"
else
  fail! "T3A: count_tail: variant_check wrong (got: #{term_tail&.dig("variant_check").inspect})"
end
if term_tail&.dig("numeric_measure", "trust") == "stdlib_numeric_certified"
  pass "T3A: count_tail: trust = stdlib_numeric_certified"
else
  fail! "T3A: count_tail: trust wrong (got: #{term_tail&.dig("numeric_measure", "trust").inspect})"
end

r_rest, app_rest, _ = compile_fixture("t3a_count_rest")
sir_rest  = load_sir(app_rest)
term_rest = termination_for(sir_rest)

if File.exist?(app_rest)
  pass "T3A: count_rest: compiles"
else
  fail! "T3A: count_rest: failed to compile"
end
if term_rest&.dig("variant_check") == "numeric_measure_v0"
  pass "T3A: count_rest: variant_check = numeric_measure_v0"
else
  fail! "T3A: count_rest: variant_check wrong (got: #{term_rest&.dig("variant_check").inspect})"
end
if term_rest&.dig("numeric_measure", "trust") == "stdlib_numeric_certified"
  pass "T3A: count_rest: trust = stdlib_numeric_certified"
else
  fail! "T3A: count_rest: trust wrong"
end

r_multi, app_multi, _ = compile_fixture("t3a_multi_input")
sir_multi  = load_sir(app_multi)
term_multi = termination_for(sir_multi)

if File.exist?(app_multi)
  pass "T3A: multi_input: compiles"
else
  fail! "T3A: multi_input: failed to compile"
end
if term_multi&.dig("variant_check") == "numeric_measure_v0"
  pass "T3A: multi_input: variant_check = numeric_measure_v0"
else
  fail! "T3A: multi_input: variant_check wrong (got: #{term_multi&.dig("variant_check").inspect})"
end
if term_multi&.dig("numeric_measure", "trust") == "stdlib_numeric_certified"
  pass "T3A: multi_input: trust = stdlib_numeric_certified"
else
  fail! "T3A: multi_input: trust wrong"
end

# =============================================================================
# T3B: SemanticIR exact §5.1 shape
# variant_check / decreases / numeric_measure {fn/arg/trust/source}
# =============================================================================
puts "\n=== T3B: SemanticIR shape — exact §5.1 ===\n"

# Reuse count_tail (contract CountTail, input items)
if term_tail&.dig("variant_check") == "numeric_measure_v0"
  pass "T3B: sir: variant_check = numeric_measure_v0"
else
  fail! "T3B: sir: variant_check wrong"
end
if term_tail&.dig("decreases") == "count(items)"
  pass "T3B: sir: decreases = 'count(items)'"
else
  fail! "T3B: sir: decreases wrong (got: #{term_tail&.dig("decreases").inspect})"
end
if term_tail&.dig("numeric_measure", "fn") == "stdlib.collection.count"
  pass "T3B: sir: numeric_measure.fn = 'stdlib.collection.count'"
else
  fail! "T3B: sir: numeric_measure.fn wrong (got: #{term_tail&.dig("numeric_measure", "fn").inspect})"
end
if term_tail&.dig("numeric_measure", "arg") == "items"
  pass "T3B: sir: numeric_measure.arg = 'items'"
else
  fail! "T3B: sir: numeric_measure.arg wrong (got: #{term_tail&.dig("numeric_measure", "arg").inspect})"
end
if term_tail&.dig("numeric_measure", "trust") == "stdlib_numeric_certified"
  pass "T3B: sir: numeric_measure.trust = 'stdlib_numeric_certified'"
else
  fail! "T3B: sir: numeric_measure.trust wrong"
end
if term_tail&.dig("numeric_measure", "source") == "compiler_builtin"
  pass "T3B: sir: numeric_measure.source = 'compiler_builtin'"
else
  fail! "T3B: sir: numeric_measure.source wrong (got: #{term_tail&.dig("numeric_measure", "source").inspect})"
end

# =============================================================================
# T3C: OOF-R11 — call-site structural coverage failure
# count(items) recognized but recur() arg not T2-registered structural subvalue
# =============================================================================
puts "\n=== T3C: OOF-R11 — call-site structural coverage failure ===\n"

r_plain, _, _ = compile_fixture("t3c_plain_ref")
r_unrg, _, _  = compile_fixture("t3c_unregistered_accessor")
r_wvar, _, _  = compile_fixture("t3c_wrong_variable")

if has_oof(r_plain, "OOF-R11")
  pass "T3C: plain_ref: OOF-R11 fires (recur(items) — plain ref)"
else
  fail! "T3C: plain_ref: OOF-R11 did NOT fire"
end
unless has_oof(r_plain, "OOF-R10")
  pass "T3C: plain_ref: OOF-R10 does NOT fire (count IS recognized)"
else
  fail! "T3C: plain_ref: OOF-R10 unexpectedly fired"
end

if has_oof(r_unrg, "OOF-R11")
  pass "T3C: unregistered_accessor: OOF-R11 fires (items.head not in registry)"
else
  fail! "T3C: unregistered_accessor: OOF-R11 did NOT fire"
end
unless has_oof(r_unrg, "OOF-R10")
  pass "T3C: unregistered_accessor: OOF-R10 does NOT fire"
else
  fail! "T3C: unregistered_accessor: OOF-R10 unexpectedly fired"
end

if has_oof(r_wvar, "OOF-R11")
  pass "T3C: wrong_variable: OOF-R11 fires (other.tail at items position)"
else
  fail! "T3C: wrong_variable: OOF-R11 did NOT fire"
end
unless has_oof(r_wvar, "OOF-R10")
  pass "T3C: wrong_variable: OOF-R10 does NOT fire"
else
  fail! "T3C: wrong_variable: OOF-R10 unexpectedly fired"
end

# =============================================================================
# T3D: OOF-R10 — unrecognized / deferred measure function
# size / byte_length / depth not in NUMERIC_MEASURE_BUILTINS v0
# =============================================================================
puts "\n=== T3D: OOF-R10 — unrecognized / deferred measure function ===\n"

r_size, _, _ = compile_fixture("t3d_size_fn")
r_byte, _, _ = compile_fixture("t3d_byte_length")
r_unkn, _, _ = compile_fixture("t3d_unknown_fn")

if has_oof(r_size, "OOF-R10")
  pass "T3D: size_fn: OOF-R10 fires (size deferred from v0)"
else
  fail! "T3D: size_fn: OOF-R10 did NOT fire"
end
unless has_oof(r_size, "OOF-R11")
  pass "T3D: size_fn: OOF-R11 does NOT fire (function not recognized)"
else
  fail! "T3D: size_fn: OOF-R11 unexpectedly fired"
end

if has_oof(r_byte, "OOF-R10")
  pass "T3D: byte_length: OOF-R10 fires (Text measures deferred)"
else
  fail! "T3D: byte_length: OOF-R10 did NOT fire"
end
unless has_oof(r_byte, "OOF-R11")
  pass "T3D: byte_length: OOF-R11 does NOT fire"
else
  fail! "T3D: byte_length: OOF-R11 unexpectedly fired"
end

if has_oof(r_unkn, "OOF-R10")
  pass "T3D: unknown_fn: OOF-R10 fires (depth not in NUMERIC_MEASURE_BUILTINS)"
else
  fail! "T3D: unknown_fn: OOF-R10 did NOT fire"
end
unless has_oof(r_unkn, "OOF-R11")
  pass "T3D: unknown_fn: OOF-R11 does NOT fire"
else
  fail! "T3D: unknown_fn: OOF-R11 unexpectedly fired"
end

# =============================================================================
# T3E: T2 bridge — user_assumed relation satisfies T3 call-site obligation
# count(items) + size_relation Collection sub → passes OOF-R11 check
# =============================================================================
puts "\n=== T3E: T2 bridge — user_assumed relation satisfies T3 call-site ===\n"

r_user, app_user, _ = compile_fixture("t3e_user_relation")
sir_user  = load_sir(app_user)
term_user = termination_for(sir_user)

if File.exist?(app_user)
  pass "T3E: user_relation: compiles (no type errors)"
else
  fail! "T3E: user_relation: failed to compile"
end
if term_user&.dig("variant_check") == "numeric_measure_v0"
  pass "T3E: user_relation: variant_check = numeric_measure_v0"
else
  fail! "T3E: user_relation: variant_check wrong (got: #{term_user&.dig("variant_check").inspect})"
end
if term_user&.dig("numeric_measure", "trust") == "stdlib_numeric_certified"
  pass "T3E: user_relation: trust = stdlib_numeric_certified (measure is stdlib, coverage via user relation)"
else
  fail! "T3E: user_relation: trust wrong (got: #{term_user&.dig("numeric_measure", "trust").inspect})"
end

# =============================================================================
# T3F: T1 regression — simple-identifier decreases unaffected
# T3 dispatch does not intercept simple-identifier variants
# =============================================================================
puts "\n=== T3F: T1 regression — syntactic_v0 unaffected ===\n"

r_t1s, app_t1s, _ = compile_fixture("t3f_t1_simple")
r_t1i, app_t1i, _ = compile_fixture("t3f_t1_items")
sir_t1s  = load_sir(app_t1s)
sir_t1i  = load_sir(app_t1i)
term_t1s = termination_for(sir_t1s)
term_t1i = termination_for(sir_t1i)

if File.exist?(app_t1s)
  pass "T3F: t1_simple: compiles"
else
  fail! "T3F: t1_simple: failed to compile"
end
if term_t1s&.dig("variant_check") == "syntactic_v0"
  pass "T3F: t1_simple: variant_check = syntactic_v0 (NOT numeric_measure_v0)"
else
  fail! "T3F: t1_simple: variant_check wrong (got: #{term_t1s&.dig("variant_check").inspect})"
end

if File.exist?(app_t1i)
  pass "T3F: t1_items: compiles"
else
  fail! "T3F: t1_items: failed to compile"
end
if term_t1i&.dig("variant_check") == "syntactic_v0"
  pass "T3F: t1_items: variant_check = syntactic_v0 (simple identifier, not function-call form)"
else
  fail! "T3F: t1_items: variant_check wrong (got: #{term_t1i&.dig("variant_check").inspect})"
end

# =============================================================================
# T3G: T2 regression — dotted-path decreases unaffected
# T3 dispatch does not intercept dotted-path variants
# =============================================================================
puts "\n=== T3G: T2 regression — structural_size_v1 unaffected ===\n"

r_t2r, app_t2r, _ = compile_fixture("t3g_t2_regression")
sir_t2r  = load_sir(app_t2r)
term_t2r = termination_for(sir_t2r)

if File.exist?(app_t2r)
  pass "T3G: t2_regression: compiles"
else
  fail! "T3G: t2_regression: failed to compile"
end
if term_t2r&.dig("variant_check") == "structural_size_v1"
  pass "T3G: t2_regression: variant_check = structural_size_v1 (NOT numeric_measure_v0)"
else
  fail! "T3G: t2_regression: variant_check wrong (got: #{term_t2r&.dig("variant_check").inspect})"
end

# =============================================================================
# T3H: Dotted numeric accessor → OOF-R3, not OOF-R10
# items.count is dotted-path form — T2 NUMERIC_ACCESSORS boundary unchanged
# =============================================================================
puts "\n=== T3H: Dotted numeric → OOF-R3, not OOF-R10 ===\n"

r_dotted, _, _ = compile_fixture("t3h_dotted_count")

if has_oof(r_dotted, "OOF-R3")
  pass "T3H: dotted_count: OOF-R3 fires (items.count → T2 numeric dotted-path boundary)"
else
  fail! "T3H: dotted_count: OOF-R3 did NOT fire"
end
unless has_oof(r_dotted, "OOF-R10")
  pass "T3H: dotted_count: OOF-R10 does NOT fire (not function-call form)"
else
  fail! "T3H: dotted_count: OOF-R10 unexpectedly fired"
end
unless has_oof(r_dotted, "OOF-R8")
  pass "T3H: dotted_count: OOF-R8 does NOT fire (numeric is not T2 missing-relation)"
else
  fail! "T3H: dotted_count: OOF-R8 unexpectedly fired"
end

# =============================================================================
# T3I: Multi-recur call sites
# Fail: at least one site fails structural coverage → OOF-R11
# Pass: all sites covered → numeric_measure_v0
# =============================================================================
puts "\n=== T3I: Multi-recur call sites ===\n"

r_mf, _, _        = compile_fixture("t3i_multi_recur_fail")
r_mp, app_mp, _   = compile_fixture("t3i_multi_recur_pass")
sir_mp  = load_sir(app_mp)
term_mp = termination_for(sir_mp)

if has_oof(r_mf, "OOF-R11")
  pass "T3I: multi_recur_fail: OOF-R11 fires (plain recur(items) site fails)"
else
  fail! "T3I: multi_recur_fail: OOF-R11 did NOT fire"
end
unless has_oof(r_mf, "OOF-R10")
  pass "T3I: multi_recur_fail: OOF-R10 does NOT fire (count IS recognized)"
else
  fail! "T3I: multi_recur_fail: OOF-R10 unexpectedly fired"
end

if File.exist?(app_mp)
  pass "T3I: multi_recur_pass: compiles (both recur sites covered)"
else
  fail! "T3I: multi_recur_pass: failed to compile"
end
if term_mp&.dig("variant_check") == "numeric_measure_v0"
  pass "T3I: multi_recur_pass: variant_check = numeric_measure_v0"
else
  fail! "T3I: multi_recur_pass: variant_check wrong (got: #{term_mp&.dig("variant_check").inspect})"
end

# =============================================================================
# OOF-R9 regression: T2 call-site mismatch unaffected by T3 additions
# A T2 contract with registered relation but wrong recur accessor still fires OOF-R9.
# =============================================================================
puts "\n=== OOF-R9 regression: T2 call-site mismatch ===\n"

OOF_R9_SOURCE = <<~IG
  module OOFR9Regression
  size_relation Collection tail
  recursive contract R9Mismatch {
    input items: Collection[Integer]
    compute result = recur(items.rest)
    output result: Integer
    decreases items.tail
    max_steps 100
  }
IG

r_r9, _, _ = compile_src(OOF_R9_SOURCE, "oof_r9_regression")

if has_oof(r_r9, "OOF-R9")
  pass "OOF-R9 regression: OOF-R9 fires (relation=tail, recur passes items.rest — mismatch)"
else
  fail! "OOF-R9 regression: OOF-R9 did NOT fire"
end
unless has_oof(r_r9, "OOF-R11")
  pass "OOF-R9 regression: OOF-R11 does NOT fire (T2 dotted-path, not T3 function-call)"
else
  fail! "OOF-R9 regression: OOF-R11 unexpectedly fired"
end

# =============================================================================
# Summary
# =============================================================================
puts ""
puts "─" * 64
puts "Results: #{$pass_count}/#{$pass_count + $fail_count} PASS"
if $fail_count == 0
  puts "[+] ALL PASS — Rust T3 numeric measure symmetry proven"
else
  puts "[!] #{$fail_count} FAILURE(S) — see above"
end
puts ""
puts "NOT a full termination proof. Lab behavior is not canon authority."
puts "NUMERIC_MEASURE_BUILTINS v0: count(Collection[T]) only."
puts "size/length/byte_length/user-defined measures: OOF-R10 (deferred)."

exit($fail_count > 0 ? 1 : 0)
