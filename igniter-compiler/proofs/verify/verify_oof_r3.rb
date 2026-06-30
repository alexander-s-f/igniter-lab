# encoding: utf-8
# verify_oof_r3.rb
# PROP-039 OOF-R3 Lab Rust symmetry — syntactic variant decrease proof
#
# Symmetric with igniter-lang/experiments/oof_r3_syntactic_variant_decrease_proof/verify_oof_r3.rb
#
# Gate scope:
#   - OOF-R3 fires when recur() variant-position arg does NOT syntactically decrease declared variant.
#   - [PROP-041 T2 update] Non-numeric dotted-path variants now fire OOF-R8 (missing
#     structural size relation) instead of OOF-R3. Numeric dotted-paths still fire OOF-R3.
#   - Whitelisted decrease patterns: variant-N (N>0 integer), variant.tail, variant.rest.
#   - Exempt: fuel_bounded contracts, recursive + decreases fuel.
#   - SemanticIR: termination.variant_check = "syntactic_v0" on clean recursive contracts.
#
# Sections: R3a–R3n (33 checks total)

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../../../../tools/proof_harness/bounded_command'

ROOT      = Pathname.new(__dir__).parent.parent
COMP      = ROOT / "target/release/igniter_compiler"
FIXTURES  = ROOT.parent.parent.parent /
            "igniter-lang/experiments/oof_r3_syntactic_variant_decrease_proof/fixtures"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("r3_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  # LAB-PROOF-HYGIENE-P1: bounded execution — hard timeout, kills process group
  r = BoundedCommand.run("#{COMP} compile #{ig} --out #{out}",
                         label: "compile:#{label}",
                         timeout: BoundedCommand::EXEC_TIMEOUT)
  BoundedCommand.print_result(r) unless r.ok?
  result = r.combined.force_encoding('UTF-8')
  [result, out, tmp]
end

def compile_fixture(name)
  src = File.read(FIXTURES / "#{name}.ig")
  compile_src(src, name)
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

def oof_codes(result_str)
  begin
    data = JSON.parse(result_str)
    (data["diagnostics"] || []).map { |d| d["rule"] }
  rescue
    []
  end
end

def has_oof(result_str, code)
  result_str.include?(code)
end

def diag_message(result_str, code)
  begin
    data = JSON.parse(result_str)
    diag = (data["diagnostics"] || []).find { |d| d["rule"] == code }
    diag&.fetch("message", "") || ""
  rescue
    ""
  end
end

def count_oof(result_str, code)
  begin
    data = JSON.parse(result_str)
    (data["diagnostics"] || []).count { |d| d["rule"] == code }
  rescue
    0
  end
end

unless COMP.exist?
  puts "[*] Building compiler (release)..."
  # LAB-PROOF-HYGIENE-P1: bounded cargo build
  r = BoundedCommand.run("cargo build --release",
                         label: "cargo build --release",
                         timeout: BoundedCommand::CARGO_TIMEOUT)
  unless r.ok?
    BoundedCommand.print_result(r)
    puts "[!] Compiler build failed — aborting"
    exit(1)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# R3a: Happy path — arithmetic decrease
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3a: Happy path — arithmetic decrease ===\n"

result_sub, app_sub, tmp_sub = compile_fixture("happy_subtract")
if File.exist?(app_sub)
  pass "R3a: happy_subtract compiles (n-1 is whitelisted decrease)"
else
  fail! "R3a: happy_subtract failed to compile (got: #{result_sub[0..300]})"
end
unless has_oof(result_sub, "OOF-R3")
  pass "R3a: no OOF-R3 for happy_subtract"
else
  fail! "R3a: OOF-R3 incorrectly fired for happy_subtract"
end

result_marg, app_marg, tmp_marg = compile_fixture("happy_multi_arg")
if File.exist?(app_marg)
  pass "R3a: happy_multi_arg compiles (a-1 at variant position, b+1 irrelevant)"
else
  fail! "R3a: happy_multi_arg failed to compile (got: #{result_marg[0..300]})"
end
unless has_oof(result_marg, "OOF-R3")
  pass "R3a: no OOF-R3 for happy_multi_arg"
else
  fail! "R3a: OOF-R3 incorrectly fired for happy_multi_arg"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3b: Happy path — structural decrease (whitelisted accessors)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3b: Happy path — structural decrease (tail / rest) ===\n"

result_tail, app_tail, tmp_tail = compile_fixture("happy_structural_tail")
if File.exist?(app_tail)
  pass "R3b: happy_structural_tail compiles (n.tail is whitelisted)"
else
  fail! "R3b: happy_structural_tail failed (got: #{result_tail[0..300]})"
end
unless has_oof(result_tail, "OOF-R3")
  pass "R3b: no OOF-R3 for n.tail"
else
  fail! "R3b: OOF-R3 incorrectly fired for n.tail"
end

result_rest, app_rest, tmp_rest = compile_fixture("happy_structural_rest")
if File.exist?(app_rest)
  pass "R3b: happy_structural_rest compiles (n.rest is whitelisted)"
else
  fail! "R3b: happy_structural_rest failed (got: #{result_rest[0..300]})"
end
unless has_oof(result_rest, "OOF-R3")
  pass "R3b: no OOF-R3 for n.rest"
else
  fail! "R3b: OOF-R3 incorrectly fired for n.rest"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3c: Happy path — multi-recur, both decreasing
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3c: Happy path — multi-recur both decreasing ===\n"

result_mr, app_mr, tmp_mr = compile_fixture("happy_multi_recur")
if File.exist?(app_mr)
  pass "R3c: happy_multi_recur compiles (recur(n-1)+recur(n-2) — both decrease)"
else
  fail! "R3c: happy_multi_recur failed (got: #{result_mr[0..300]})"
end
unless has_oof(result_mr, "OOF-R3")
  pass "R3c: no OOF-R3 for multi-recur"
else
  fail! "R3c: OOF-R3 incorrectly fired for multi-recur"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3d: OOF-R3 fires — same value (recur(n))
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3d: OOF-R3 — same value (recur(n)) ===\n"

result_same, app_same, tmp_same = compile_fixture("oof_r3_same")
if has_oof(result_same, "OOF-R3")
  pass "R3d: OOF-R3 fires for recur(n) — no syntactic decrease"
else
  fail! "R3d: OOF-R3 NOT fired for recur(n) (got: #{result_same[0..300]})"
end
msg_same = diag_message(result_same, "OOF-R3")
if msg_same.include?("n")
  pass "R3d: OOF-R3 message mentions variant 'n'"
else
  fail! "R3d: OOF-R3 message does not mention 'n' (msg: #{msg_same})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3e: OOF-R3 fires — wrong direction (recur(n+1))
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3e: OOF-R3 — increase (recur(n+1)) ===\n"

result_inc, app_inc, tmp_inc = compile_fixture("oof_r3_increase")
if has_oof(result_inc, "OOF-R3")
  pass "R3e: OOF-R3 fires for recur(n+1)"
else
  fail! "R3e: OOF-R3 NOT fired for recur(n+1) (got: #{result_inc[0..300]})"
end
msg_inc = diag_message(result_inc, "OOF-R3")
if msg_inc.include?("n") && (msg_inc.include?("+") || msg_inc.include?("n + 1"))
  pass "R3e: OOF-R3 message describes increase expression"
else
  fail! "R3e: OOF-R3 message does not describe n+1 (msg: #{msg_inc})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3f: OOF-R3 fires — constant literal
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3f: OOF-R3 — constant literal (recur(42)) ===\n"

result_const, app_const, tmp_const = compile_fixture("oof_r3_constant")
if has_oof(result_const, "OOF-R3")
  pass "R3f: OOF-R3 fires for recur(42)"
else
  fail! "R3f: OOF-R3 NOT fired for recur(42) (got: #{result_const[0..300]})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3g: OOF-R3 fires — unrelated variable at variant position
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3g: OOF-R3 — unrelated variable at variant position ===\n"

result_unrel, app_unrel, tmp_unrel = compile_fixture("oof_r3_unrelated_var")
if has_oof(result_unrel, "OOF-R3")
  pass "R3g: OOF-R3 fires when variant position arg is unrelated variable"
else
  fail! "R3g: OOF-R3 NOT fired for unrelated var at variant position (got: #{result_unrel[0..300]})"
end
msg_unrel = diag_message(result_unrel, "OOF-R3")
if msg_unrel.include?("n")
  pass "R3g: OOF-R3 message mentions declared variant 'n'"
else
  fail! "R3g: OOF-R3 message does not mention variant 'n' (msg: #{msg_unrel})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3h: OOF-R3 fires — non-whitelisted accessor (n.something)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3h: OOF-R3 — non-whitelisted accessor (n.something) ===\n"

result_nwl, app_nwl, tmp_nwl = compile_fixture("oof_r3_nonwhitelisted")
if has_oof(result_nwl, "OOF-R3")
  pass "R3h: OOF-R3 fires for n.something (not in whitelist)"
else
  fail! "R3h: OOF-R3 NOT fired for non-whitelisted accessor (got: #{result_nwl[0..300]})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3i: OOF-R3 fires — partial: one recur() good, one bad
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3i: OOF-R3 — partial: recur(n-1) + recur(n) ===\n"

result_part, app_part, tmp_part = compile_fixture("oof_r3_partial")
r3_count = count_oof(result_part, "OOF-R3")
if r3_count == 1
  pass "R3i: exactly one OOF-R3 fired (recur(n) bad, recur(n-1) clean)"
else
  fail! "R3i: expected 1 OOF-R3, got #{r3_count} (result: #{result_part[0..300]})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3j: Dotted-path variant — blocked via OOF-R8 (PROP-041 T2)
# PROP-041 T2 update: non-numeric dotted-path variants with no size_relation
# declaration now fire OOF-R8 (missing structural size relation), not OOF-R3.
# Compilation is still blocked; OOF-R3 scope is unweakened for non-T2 forms.
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3j: Dotted-path variant — blocked via OOF-R8 (PROP-041 T2) ===\n"

result_dot, app_dot, tmp_dot = compile_fixture("oof_r3_dotted_path")
if has_oof(result_dot, "OOF-R8")
  pass "R3j: OOF-R8 fires for 'decreases items.remaining' (T2 missing-relation)"
else
  fail! "R3j: OOF-R8 NOT fired for dotted-path variant (got: #{result_dot[0..300]})"
end
unless has_oof(result_dot, "OOF-R3")
  pass "R3j: OOF-R3 does NOT fire (T2 handles non-numeric dotted-path)"
else
  fail! "R3j: OOF-R3 incorrectly fired for non-numeric dotted-path (should be OOF-R8)"
end
unless File.exist?(app_dot)
  pass "R3j: semantic_ir not produced (blocked by OOF-R8)"
else
  fail! "R3j: semantic_ir produced despite OOF-R8 (should be blocked)"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3k: Exempt — fuel_bounded and decreases fuel
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3k: Exempt — fuel_bounded and decreases fuel ===\n"

result_fe, app_fe, tmp_fe = compile_fixture("fuel_exempt")
unless has_oof(result_fe, "OOF-R3")
  pass "R3k: fuel_bounded contract — no OOF-R3 (exempt)"
else
  fail! "R3k: OOF-R3 incorrectly fired for fuel_bounded contract"
end

result_dfe, app_dfe, tmp_dfe = compile_fixture("decreases_fuel_exempt")
unless has_oof(result_dfe, "OOF-R3")
  pass "R3k: recursive + decreases fuel — no OOF-R3 (fuel exempt)"
else
  fail! "R3k: OOF-R3 incorrectly fired for recursive+decreases fuel contract"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3l: SemanticIR — termination.variant_check present on clean contracts
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3l: SemanticIR — termination.variant_check on clean recursive contracts ===\n"

sir_sub  = load_sir(app_sub)
cir_sub  = find_contract(sir_sub)
sir_marg = load_sir(app_marg)
cir_marg = find_contract(sir_marg)

if cir_sub && cir_sub.key?("termination")
  pass "R3l: happy_subtract contract_ir has termination field"
else
  fail! "R3l: happy_subtract contract_ir missing termination field (cir: #{cir_sub&.keys})"
end
if cir_sub && cir_sub.dig("termination", "decreases") == "n"
  pass "R3l: happy_subtract termination.decreases == 'n'"
else
  fail! "R3l: happy_subtract termination.decreases wrong (got: #{cir_sub&.dig("termination", "decreases")})"
end
if cir_sub && cir_sub.dig("termination", "variant_check") == "syntactic_v0"
  pass "R3l: happy_subtract termination.variant_check == 'syntactic_v0'"
else
  fail! "R3l: happy_subtract termination.variant_check wrong (got: #{cir_sub&.dig("termination", "variant_check")})"
end
if cir_marg && cir_marg.dig("termination", "decreases") == "a"
  pass "R3l: happy_multi_arg termination.decreases == 'a' (variant name preserved)"
else
  fail! "R3l: happy_multi_arg termination.decreases wrong (got: #{cir_marg&.dig("termination", "decreases")})"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3m: OOF-R3 blocks semantic_ir emission
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3m: OOF-R3 blocks semantic_ir emission ===\n"

unless File.exist?(app_same)
  pass "R3m: oof_r3_same — no semantic_ir produced when OOF-R3 fires"
else
  fail! "R3m: oof_r3_same — semantic_ir produced despite OOF-R3"
end
unless File.exist?(app_inc)
  pass "R3m: oof_r3_increase — no semantic_ir produced when OOF-R3 fires"
else
  fail! "R3m: oof_r3_increase — semantic_ir produced despite OOF-R3"
end
unless File.exist?(app_part)
  pass "R3m: oof_r3_partial — no semantic_ir produced when OOF-R3 fires"
else
  fail! "R3m: oof_r3_partial — semantic_ir produced despite OOF-R3"
end

# ─────────────────────────────────────────────────────────────────────────────
# R3n: Regression — OOF-R1/R5/R6/R7 unaffected
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== R3n: Regression — G5 OOF checks unaffected ===\n"

SRC_PURE_RECUR = <<~IGNITER
  module R3Reg
  pure contract PureRecur {
    input n: Integer
    compute result = recur(n - 1)
    output result: Integer
  }
IGNITER

result_pr, _out_pr, tmp_pr = compile_src(SRC_PURE_RECUR, "pure_recur")
FileUtils.rm_rf(tmp_pr)
if has_oof(result_pr, "OOF-R1") && !has_oof(result_pr, "OOF-R3")
  pass "R3n: pure contract with recur() → OOF-R1, not OOF-R3"
else
  fail! "R3n: expected OOF-R1 only, got codes: #{oof_codes(result_pr)} (result: #{result_pr[0..300]})"
end

SRC_R5_BLOCKS_R3 = <<~IGNITER
  module R3Reg
  recursive contract R5BlocksR3 {
    input n: Integer
    input m: Integer
    compute result = recur(n)
    output result: Integer
    decreases n
    max_steps 100
  }
IGNITER

result_r5, _out_r5, tmp_r5 = compile_src(SRC_R5_BLOCKS_R3, "r5_blocks_r3")
FileUtils.rm_rf(tmp_r5)
if has_oof(result_r5, "OOF-R5")
  pass "R3n: OOF-R5 fires when arity is wrong"
else
  fail! "R3n: OOF-R5 did not fire for arity mismatch (got: #{result_r5[0..300]})"
end
unless has_oof(result_r5, "OOF-R3")
  pass "R3n: OOF-R3 not fired when OOF-R5 already blocked (arity wrong → skip decrease check)"
else
  fail! "R3n: OOF-R3 fired despite OOF-R5 (decrease check should be skipped on arity mismatch)"
end

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────
[tmp_sub, tmp_marg, tmp_tail, tmp_rest, tmp_mr,
 tmp_same, tmp_inc, tmp_const, tmp_unrel,
 tmp_nwl, tmp_part, tmp_dot, tmp_fe, tmp_dfe].each { |t| FileUtils.rm_rf(t) }

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
total  = $pass_count + $fail_count
passed = $pass_count
failed = $fail_count

puts "\n" + "─" * 60
puts "OOF-R3 Lab Rust symmetry: #{passed}/#{total} PASS"
if failed > 0
  puts "FAIL count: #{failed}"
  exit 1
else
  puts "ALL PASS"
end
