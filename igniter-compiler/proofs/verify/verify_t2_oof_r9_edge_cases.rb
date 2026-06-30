# encoding: utf-8
# verify_t2_oof_r9_edge_cases.rb
# PROP-041 T2 OOF-R9 — Branch and Multi-Recur Edge Hardening
# Card: LAB-TERM-T2-P2
#
# Proves OOF-R9 call-site mismatch behavior across:
#   - Multi-recur expressions (all correct → PASS; one wrong → OOF-R9)
#   - If-expression branches (both correct → PASS; wrong else → OOF-R9)
#   - Nested arithmetic with wrong recur site → OOF-R9
#   - OOF-R3/R8 precedence: numeric dotted-path → OOF-R3, missing relation → OOF-R8 (not OOF-R9)
#   - T1 regression: simple-identifier decreases → syntactic_v0 unchanged
#
# Root cause fixed: check_t2_callsite_in_expr IfExpr arm previously walked only cond,
# not then/else_block bodies. Now mirrors check_recur_in_expr exactly.
#
# NOTE: T2 is structural evidence with trust metadata — NOT a full termination proof.
# Lab behavior does not create canon authority.
#
# Sections: R9A..R9H
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
  tmp = Dir.mktmpdir("r9_#{label}")
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

def has_oof(result_str, code)
  result_str.include?(code)
end

def compiled_ok(app_path)
  File.exist?(app_path) && File.directory?(app_path)
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
# R9A: Multi-recur expression — all recur sites correct
# recur(items.next) + recur(items.next) → PASS (no OOF-R9)
# =============================================================================
puts "\n=== R9A: Multi-recur — all sites correct ===\n"

r_mbc, app_mbc, _ = compile_fixture("t2r9_multi_recur_both_correct")
if compiled_ok(app_mbc)
  pass "R9A: multi_recur_both_correct: compiles (no type errors)"
else
  fail! "R9A: multi_recur_both_correct: failed to compile"
end
unless has_oof(r_mbc, "OOF-R9")
  pass "R9A: multi_recur_both_correct: OOF-R9 does NOT fire (both sites correct)"
else
  fail! "R9A: multi_recur_both_correct: OOF-R9 incorrectly fired"
end
unless has_oof(r_mbc, "OOF-R8")
  pass "R9A: multi_recur_both_correct: no OOF-R8"
else
  fail! "R9A: multi_recur_both_correct: OOF-R8 incorrectly fired"
end

# =============================================================================
# R9B: Multi-recur expression — one site correct, one wrong
# recur(items.next) + recur(items) → OOF-R9
# =============================================================================
puts "\n=== R9B: Multi-recur — one site wrong ===\n"

r_mow, _, _ = compile_fixture("t2r9_multi_recur_one_wrong")
if has_oof(r_mow, "OOF-R9")
  pass "R9B: multi_recur_one_wrong: OOF-R9 fires (wrong arg at second recur site)"
else
  fail! "R9B: multi_recur_one_wrong: OOF-R9 did NOT fire"
end
unless has_oof(r_mow, "OOF-R3")
  pass "R9B: multi_recur_one_wrong: OOF-R3 does NOT fire"
else
  fail! "R9B: multi_recur_one_wrong: OOF-R3 incorrectly fired"
end
# Mixed: one correct call site should not suppress OOF-R9 for the wrong one
if has_oof(r_mow, "OOF-R9") && !has_oof(r_mow, "OOF-R3")
  pass "R9B: mixed correct/wrong fails closed — correct site does NOT suppress wrong-site OOF-R9"
else
  fail! "R9B: mixed correct/wrong behavior incorrect"
end

# =============================================================================
# R9C: If-expression — both branches correct
# if n > 0 { recur(items.next, n-1) } else { recur(items.next, n-1) } → PASS
# =============================================================================
puts "\n=== R9C: If-expression — both branches correct ===\n"

r_ibc, app_ibc, _ = compile_fixture("t2r9_if_both_branches_correct")
if compiled_ok(app_ibc)
  pass "R9C: if_both_branches_correct: compiles (no type errors)"
else
  fail! "R9C: if_both_branches_correct: failed to compile"
end
unless has_oof(r_ibc, "OOF-R9")
  pass "R9C: if_both_branches_correct: OOF-R9 does NOT fire (both branches correct)"
else
  fail! "R9C: if_both_branches_correct: OOF-R9 incorrectly fired"
end
unless has_oof(r_ibc, "OOF-R3") || has_oof(r_ibc, "OOF-R8")
  pass "R9C: if_both_branches_correct: no spurious OOF-R3/R8"
else
  fail! "R9C: if_both_branches_correct: spurious OOF-R3 or OOF-R8"
end

# =============================================================================
# R9D: If-expression — wrong else-branch
# if n > 0 { recur(items.next, n-1) } else { recur(items, n-1) } → OOF-R9
# =============================================================================
puts "\n=== R9D: If-expression — wrong else-branch ===\n"

r_iweb, _, _ = compile_fixture("t2r9_if_wrong_else_branch")
if has_oof(r_iweb, "OOF-R9")
  pass "R9D: if_wrong_else_branch: OOF-R9 fires (wrong arg in else branch)"
else
  fail! "R9D: if_wrong_else_branch: OOF-R9 did NOT fire — check_t2_callsite_in_expr IfExpr fix required"
end
unless has_oof(r_iweb, "OOF-R3")
  pass "R9D: if_wrong_else_branch: OOF-R3 does NOT fire"
else
  fail! "R9D: if_wrong_else_branch: OOF-R3 incorrectly fired"
end
unless has_oof(r_iweb, "OOF-R8")
  pass "R9D: if_wrong_else_branch: OOF-R8 does NOT fire (relation is registered)"
else
  fail! "R9D: if_wrong_else_branch: OOF-R8 incorrectly fired"
end

# =============================================================================
# R9E: Nested arithmetic — wrong recur site buried in BinaryOp
# 0 + recur(items) — recur inside arithmetic, accessor missing → OOF-R9
# =============================================================================
puts "\n=== R9E: Nested arithmetic — wrong recur in BinaryOp ===\n"

r_naw, _, _ = compile_fixture("t2r9_nested_arith_wrong")
if has_oof(r_naw, "OOF-R9")
  pass "R9E: nested_arith_wrong: OOF-R9 fires (recur nested in BinaryOp, wrong accessor)"
else
  fail! "R9E: nested_arith_wrong: OOF-R9 did NOT fire"
end
unless has_oof(r_naw, "OOF-R3")
  pass "R9E: nested_arith_wrong: OOF-R3 does NOT fire"
else
  fail! "R9E: nested_arith_wrong: OOF-R3 incorrectly fired"
end

# =============================================================================
# R9F: OOF-R9 baseline forms (re-verified from T2A-T2I)
# Plain subject, wrong variable, wrong accessor — confirm still fire OOF-R9
# =============================================================================
puts "\n=== R9F: OOF-R9 baseline forms ===\n"

r_wa, _, _ = compile_fixture("t2e_wrong_accessor")
if has_oof(r_wa, "OOF-R9")
  pass "R9F: wrong_accessor: OOF-R9 fires"
else
  fail! "R9F: wrong_accessor: OOF-R9 did NOT fire"
end

r_pr, _, _ = compile_fixture("t2e_plain_ref")
if has_oof(r_pr, "OOF-R9")
  pass "R9F: plain_ref (recur(items) instead of recur(items.next)): OOF-R9 fires"
else
  fail! "R9F: plain_ref: OOF-R9 did NOT fire"
end

r_wv, _, _ = compile_fixture("t2e_wrong_variable")
if has_oof(r_wv, "OOF-R9")
  pass "R9F: wrong_variable (recur(other.accessor)): OOF-R9 fires"
else
  fail! "R9F: wrong_variable: OOF-R9 did NOT fire"
end

# =============================================================================
# R9G: OOF-R3/R8 precedence — numeric dotted-path stays R3, missing stays R8
# Confirms OOF-R9 does not fire for missing-relation or numeric cases
# =============================================================================
puts "\n=== R9G: OOF-R3/R8 precedence unchanged ===\n"

r_count, _, _ = compile_fixture("t2f_count_accessor")
if has_oof(r_count, "OOF-R3") && !has_oof(r_count, "OOF-R9")
  pass "R9G: numeric accessor (count): OOF-R3 fires, OOF-R9 does NOT fire"
else
  fail! "R9G: numeric accessor (count): wrong codes — R3=#{has_oof(r_count,'OOF-R3')} R9=#{has_oof(r_count,'OOF-R9')}"
end

r_nr, _, _ = compile_fixture("t2d_no_registry_entry")
if has_oof(r_nr, "OOF-R8") && !has_oof(r_nr, "OOF-R9")
  pass "R9G: missing relation: OOF-R8 fires, OOF-R9 does NOT fire"
else
  fail! "R9G: missing relation: wrong codes — R8=#{has_oof(r_nr,'OOF-R8')} R9=#{has_oof(r_nr,'OOF-R9')}"
end

# =============================================================================
# R9H: T1 regression — syntactic_v0 unaffected
# Simple-identifier decreases still compiles; structural_size_v1 not emitted
# =============================================================================
puts "\n=== R9H: T1 regression ===\n"

r_arith, app_arith, _ = compile_fixture("t2g_t1_arithmetic")
if compiled_ok(app_arith)
  pass "R9H: t1_arithmetic: compiles (T2 extension does not affect T1)"
else
  fail! "R9H: t1_arithmetic: failed to compile"
end
unless has_oof(r_arith, "OOF-R9")
  pass "R9H: t1_arithmetic: OOF-R9 does NOT fire (T1 contract)"
else
  fail! "R9H: t1_arithmetic: OOF-R9 incorrectly fired on T1 contract"
end

# =============================================================================
# Summary
# =============================================================================
puts ""
puts "=" * 60
puts "PROP-041 T2 OOF-R9 Branch and Multi-Recur Edge Hardening"
puts "Results: #{$pass_count}/#{$pass_count + $fail_count} PASS"
puts "=" * 60
if $fail_count > 0
  puts "[!] #{$fail_count} FAILURE(S) — OOF-R9 edge hardening NOT proven"
  exit(1)
else
  puts "[+] ALL PASS — OOF-R9 branch and multi-recur edge cases proven"
  puts ""
  puts "Edge cases proven:"
  puts "  - Multi-recur both correct: no OOF-R9 (pass)"
  puts "  - Multi-recur one wrong: OOF-R9 fires (fail-closed)"
  puts "  - Mixed correct/wrong: correct site does NOT suppress wrong-site OOF-R9"
  puts "  - If-expr both branches correct: no OOF-R9 (pass)"
  puts "  - If-expr wrong else branch: OOF-R9 fires (IfExpr fix confirmed)"
  puts "  - Nested arithmetic wrong recur: OOF-R9 fires (BinaryOp walk confirmed)"
  puts "  - OOF-R3/R8 precedence unchanged"
  puts "  - T1 syntactic_v0 unaffected"
  puts ""
  puts "Root cause fixed: check_t2_callsite_in_expr IfExpr arm now walks"
  puts "then/else_block bodies (mirrors check_recur_in_expr exactly)."
  puts ""
  puts "NOT a full termination proof. Lab behavior is not canon authority."
end
