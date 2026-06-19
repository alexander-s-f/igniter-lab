#!/usr/bin/env ruby
# LAB-FUNCTION-RECURSION-P4
# Empirical proof: SCC-based OOF-L4 gate is live in Rust lab compiler.
# Target: ≥60 checks.

require "open3"
require "json"
require "set"
require "tmpdir"

SCRIPT_DIR  = File.expand_path(File.dirname(__FILE__))
COMPILER    = File.expand_path("../../igniter-compiler/target/release/igniter_compiler", SCRIPT_DIR)
FIXTURE_DIR = File.expand_path("../fixtures/function_recursion", SCRIPT_DIR)

abort "Compiler binary not found: #{COMPILER}" unless File.exist?(COMPILER)

# ─────────────────────────────────────────────────────────────────────────────
# Harness
# ─────────────────────────────────────────────────────────────────────────────

def parse_result(stdout)
  JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
end

def compile_fixture(name)
  path = File.join(FIXTURE_DIR, name)
  abort "Fixture not found: #{path}" unless File.exist?(path)
  Dir.mktmpdir do |tmpdir|
    out = File.join(tmpdir, "out.igapp")
    stdout, _stderr, _status = Open3.capture3(COMPILER, "compile", path, "--out", out)
    result = parse_result(stdout)
    {
      status:      result["status"] || "parse-error",
      diagnostics: Array(result["diagnostics"]),
      oof_codes:   Array(result["diagnostics"]).map { |d| d["rule"] }.compact,
      nodes:       Array(result["diagnostics"]).map { |d| d["node"] }.compact.sort
    }
  end
end

def compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    stdout, _stderr, _status = Open3.capture3(COMPILER, "compile", path, "--out", out)
    result = parse_result(stdout)
    {
      status:      result["status"] || "parse-error",
      diagnostics: Array(result["diagnostics"]),
      oof_codes:   Array(result["diagnostics"]).map { |d| d["rule"] }.compact,
      nodes:       Array(result["diagnostics"]).map { |d| d["node"] }.compact.sort
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Check infrastructure
# ─────────────────────────────────────────────────────────────────────────────

$pass = 0
$fail = 0
$checks = []

def check(label, got, expected)
  ok = got == expected
  $pass += 1 if ok
  $fail += 1 unless ok
  $checks << { label: label, ok: ok, got: got, expected: expected }
  puts "#{ok ? "PASS" : "FAIL"} #{label}" + (ok ? "" : " | got=#{got.inspect} expected=#{expected.inspect}")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section A — Non-recursive functions (no OOF-L4 expected) [8 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== A: Non-recursive functions ===\n"

non_rec = compile_fixture("non_recursive.ig")
check "A-01: non_recursive.ig status ok",       non_rec[:status],    "ok"
check "A-02: non_recursive.ig zero OOF-L4",     non_rec[:oof_codes], []

dag = compile_fixture("p4_dag_with_helpers.ig")
check "A-03: dag_with_helpers status ok (fuel on compute)", dag[:status],    "ok"
check "A-04: dag_with_helpers zero diagnostics",            dag[:oof_codes], []

unknown = compile_fixture("p4_unknown_calls.ig")
check "A-05: unknown_calls status ok",      unknown[:status],    "ok"
check "A-06: unknown_calls zero OOF-L4",    unknown[:oof_codes], []

helper_fix = compile_fixture("p3_helper_call.ig")
check "A-07: p3_helper_call.ig status ok",     helper_fix[:status],    "ok"
check "A-08: p3_helper_call.ig zero OOF-L4",   helper_fix[:oof_codes], []

# ─────────────────────────────────────────────────────────────────────────────
# Section B — Self-recursive functions [8 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== B: Self-recursive functions ===\n"

self_no = compile_fixture("p2_case1_self_no_decreases.ig")
check "B-01: self_no_decreases status oof",        self_no[:status],    "oof"
check "B-02: self_no_decreases OOF-L4 present",    self_no[:oof_codes], ["OOF-L4"]
check "B-03: self_no_decreases node is countdown", self_no[:nodes],     ["countdown"]

self_ok = compile_fixture("p2_case2_self_with_decreases.ig")
check "B-04: self_with_decreases status ok",       self_ok[:status],    "ok"
check "B-05: self_with_decreases zero OOF-L4",     self_ok[:oof_codes], []

self_rec_fuel = compile_fixture("self_recursive_fuel.ig")
check "B-06: self_recursive_fuel.ig status ok",    self_rec_fuel[:status],    "ok"
check "B-07: self_recursive_fuel.ig zero OOF-L4",  self_rec_fuel[:oof_codes], []

no_dec_inline = compile_source(<<~IG)
  module Test.SelfNoDec
  def loop_forever(n: Float) -> Float {
    loop_forever(n)
  }
IG
check "B-08: inline self-recursive no decreases → OOF-L4", no_dec_inline[:oof_codes], ["OOF-L4"]

# ─────────────────────────────────────────────────────────────────────────────
# Section C — Pure mutual recursion (the P2 correctness bug is now fixed) [10 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== C: Pure mutual recursion ===\n"

mutual_none = compile_fixture("p2_case3_pure_mutual_no_decreases.ig")
check "C-01: pure_mutual_no_decreases status oof",   mutual_none[:status],    "oof"
check "C-02: pure_mutual_no_decreases has 2 OOF-L4", mutual_none[:oof_codes], ["OOF-L4", "OOF-L4"]
check "C-03: pure_mutual_no_decreases nodes sorted",  mutual_none[:nodes],     ["ping", "pong"]

mutual_partial = compile_fixture("p2_case4_pure_mutual_partial_decreases.ig")
check "C-04: pure_mutual_partial status oof",     mutual_partial[:status],    "oof"
check "C-05: pure_mutual_partial has 1 OOF-L4",  mutual_partial[:oof_codes], ["OOF-L4"]

mutual_all = compile_fixture("p2_case5_pure_mutual_all_decreases.ig")
check "C-06: pure_mutual_all_decreases status ok", mutual_all[:status],    "ok"
check "C-07: pure_mutual_all_decreases zero OOF",  mutual_all[:oof_codes], []

mutual_fuel_fix = compile_fixture("mutual_recursive_fuel.ig")
check "C-08: mutual_recursive_fuel.ig status ok", mutual_fuel_fix[:status],    "ok"
check "C-09: mutual_recursive_fuel.ig zero OOF",  mutual_fuel_fix[:oof_codes], []

# Two-node: both no fuel but neither self-calls — the fixed bug
two_no_fuel = compile_source(<<~IG)
  module Test.TwoMutual
  def alpha(n: Float) -> Float { beta(n) }
  def beta(n: Float) -> Float  { alpha(n) }
IG
check "C-10: two-node mutual no fuel → OOF-L4 on both nodes", two_no_fuel[:nodes], ["alpha", "beta"]

# ─────────────────────────────────────────────────────────────────────────────
# Section D — Three-way and complex SCCs [10 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== D: Three-way and complex SCCs ===\n"

three_way = compile_fixture("p3_three_way_mutual.ig")
check "D-01: three_way_mutual status oof",    three_way[:status],    "oof"
check "D-02: three_way_mutual has 3 OOF-L4", three_way[:oof_codes], ["OOF-L4", "OOF-L4", "OOF-L4"]

four_no = compile_fixture("p4_four_way_cycle.ig")
check "D-03: four_way_cycle status oof",    four_no[:status],    "oof"
check "D-04: four_way_cycle has 4 OOF-L4", four_no[:oof_codes], ["OOF-L4", "OOF-L4", "OOF-L4", "OOF-L4"]
check "D-05: four_way_cycle nodes sorted",  four_no[:nodes],     ["a", "b", "c", "d"]

four_ok = compile_fixture("p4_four_way_all_annotated.ig")
check "D-06: four_way_all_annotated status ok", four_ok[:status],    "ok"
check "D-07: four_way_all_annotated zero OOF",  four_ok[:oof_codes], []

# Three-way with one missing annotation
three_partial = compile_source(<<~IG)
  module Test.ThreePartial
  def aa(n: Float) -> Float decreases fuel { bb(n) }
  def bb(n: Float) -> Float decreases fuel { cc(n) }
  def cc(n: Float) -> Float                { aa(n) }
IG
check "D-08: three-way one missing → OOF-L4 on cc", three_partial[:oof_codes], ["OOF-L4"]
check "D-09: three-way one missing → node is cc",    three_partial[:nodes],     ["cc"]

# Mixed: self-recursive + calls mutual partner
mixed_no = compile_source(<<~IG)
  module Test.MixedNoFuel
  def ax(n: Float) -> Float { ax(n) }
  def bx(n: Float) -> Float { ax(n) }
IG
# ax self-calls → OOF-L4 for ax; bx does NOT form a cycle (no path bx→bx)
check "D-10: mixed ax self-recur bx-calls-ax → OOF-L4 on ax only", mixed_no[:nodes], ["ax"]

# ─────────────────────────────────────────────────────────────────────────────
# Section E — Disconnected SCCs [8 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== E: Disconnected SCCs ===\n"

disco = compile_fixture("p3_disconnected_sccs.ig")
check "E-01: disconnected_sccs status oof",       disco[:status], "oof"
check "E-02: disconnected_sccs has 4 OOF-L4",    disco[:oof_codes], ["OOF-L4", "OOF-L4", "OOF-L4", "OOF-L4"]

# Two independent cycles, one annotated one not
two_cycles = compile_source(<<~IG)
  module Test.TwoCycles
  def p1(n: Float) -> Float decreases fuel { p2(n) }
  def p2(n: Float) -> Float decreases fuel { p1(n) }
  def q1(n: Float) -> Float { q2(n) }
  def q2(n: Float) -> Float { q1(n) }
IG
check "E-03: two cycles one annotated → oof",         two_cycles[:status],    "oof"
check "E-04: two cycles → OOF-L4 only on q1/q2",     two_cycles[:nodes],     ["q1", "q2"]
check "E-05: two cycles → exactly 2 OOF-L4",         two_cycles[:oof_codes], ["OOF-L4", "OOF-L4"]

# Non-recursive between two SCCs: helper not in any cycle
with_bridge = compile_source(<<~IG)
  module Test.WithBridge
  def go(n: Float) -> Float { go(n) }
  def bridge(n: Float) -> Float { n }
IG
check "E-06: bridge non-recursive no OOF-L4 on bridge",
  with_bridge[:diagnostics].any? { |d| d["node"] == "bridge" }, false
check "E-07: bridge recursive go → OOF-L4 on go",
  with_bridge[:nodes].include?("go"), true
check "E-08: bridge total OOF-L4 count is 1", with_bridge[:oof_codes], ["OOF-L4"]

# ─────────────────────────────────────────────────────────────────────────────
# Section F — Mixed self + mutual SCC via p3_mixed_with_helper.ig [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== F: Mixed self+mutual SCC (spreadsheet pattern) ===\n"

mixed = compile_fixture("p3_mixed_with_helper.ig")
# eval_expr (self+cross) and eval_ref (cross) form one mutual SCC.
# Both carry decreases fuel → ok. format_result is a helper → no OOF-L4.
check "F-01: p3_mixed_with_helper status ok",      mixed[:status],    "ok"
check "F-02: p3_mixed_with_helper zero OOF-L4",   mixed[:oof_codes], []

# SS-P02: only eval_expr annotated — eval_ref still missing → OOF-L4 on eval_ref
ss_p02 = compile_source(<<~IG)
  module Test.SSP02
  type Expr  { kind: Text, num_val: Float? }
  type Value { kind: Text, num_val: Float? }
  def eval_expr(e: Expr) -> Value decreases fuel {
    if e.kind == "Number" {
      { kind: "Number", num_val: e.num_val }
    } else {
      eval_ref(e.kind)
    }
  }
  def eval_ref(id: Text) -> Value {
    let dummy = { kind: "Number", num_val: 0.0 }
    eval_expr(dummy)
  }
  def format_result(v: Value) -> Text { v.kind }
IG
check "F-03: SS-P02 eval_expr annotated only → oof", ss_p02[:status], "oof"
check "F-04: SS-P02 OOF-L4 on eval_ref only",        ss_p02[:nodes],  ["eval_ref"]

# SS-P03: both annotated → ok
ss_p03 = compile_source(<<~IG)
  module Test.SSP03
  type Expr  { kind: Text, num_val: Float? }
  type Value { kind: Text, num_val: Float? }
  def eval_expr(e: Expr) -> Value decreases fuel {
    if e.kind == "Number" {
      { kind: "Number", num_val: e.num_val }
    } else {
      eval_ref(e.kind)
    }
  }
  def eval_ref(id: Text) -> Value decreases fuel {
    let dummy = { kind: "Number", num_val: 0.0 }
    eval_expr(dummy)
  }
  def format_result(v: Value) -> Text { v.kind }
IG
check "F-05: SS-P03 both annotated → ok",     ss_p03[:status],    "ok"
check "F-06: SS-P03 zero OOF-L4",             ss_p03[:oof_codes], []

# ─────────────────────────────────────────────────────────────────────────────
# Section G — Diagnostic determinism [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== G: Diagnostic determinism ===\n"

# Run the same source twice and compare outputs
src = <<~IG
  module Test.Determinism
  def c1(n: Float) -> Float { c2(n) }
  def c2(n: Float) -> Float { c3(n) }
  def c3(n: Float) -> Float { c1(n) }
IG
r1 = compile_source(src)
r2 = compile_source(src)
check "G-01: deterministic nodes run1 vs run2",       r1[:nodes],     r2[:nodes]
check "G-02: deterministic oof_codes run1 vs run2",   r1[:oof_codes], r2[:oof_codes]
check "G-03: three-way cycle nodes alphabetical",      r1[:nodes],     r1[:nodes].sort

# Alphabetical ordering within SCC: c1, c2, c3
check "G-04: three-way nodes are c1 c2 c3", r1[:nodes], ["c1", "c2", "c3"]

# Reversed definition order produces same result
src_rev = <<~IG
  module Test.DeterminismRev
  def z3(n: Float) -> Float { z1(n) }
  def z2(n: Float) -> Float { z3(n) }
  def z1(n: Float) -> Float { z2(n) }
IG
r_rev = compile_source(src_rev)
check "G-05: reversed definition order → same count",     r_rev[:oof_codes].length, 3
check "G-06: reversed definition order → nodes alphabetical", r_rev[:nodes], r_rev[:nodes].sort

# ─────────────────────────────────────────────────────────────────────────────
# Section H — P2 regression: all five P2 cases with UPDATED expectations [10 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== H: P2 regression (updated expectations) ===\n"

# Case 1: self-recursive, no decreases → OOF-L4
h1 = compile_fixture("p2_case1_self_no_decreases.ig")
check "H-01: P2-Case1 status oof",     h1[:status],    "oof"
check "H-02: P2-Case1 OOF-L4 fires",  h1[:oof_codes], ["OOF-L4"]

# Case 2: self-recursive with decreases → ok
h2 = compile_fixture("p2_case2_self_with_decreases.ig")
check "H-03: P2-Case2 status ok",       h2[:status],    "ok"
check "H-04: P2-Case2 zero OOF-L4",    h2[:oof_codes], []

# Case 3: pure mutual, no decreases → NOW FIXED (was ok, now oof)
h3 = compile_fixture("p2_case3_pure_mutual_no_decreases.ig")
check "H-05: P2-Case3 status oof (BUG FIXED)", h3[:status],    "oof"
check "H-06: P2-Case3 two OOF-L4",            h3[:oof_codes], ["OOF-L4", "OOF-L4"]

# Case 4: pure mutual, partial (ping has fuel, pong does not) → OOF-L4 on pong
h4 = compile_fixture("p2_case4_pure_mutual_partial_decreases.ig")
check "H-07: P2-Case4 status oof",     h4[:status], "oof"
check "H-08: P2-Case4 one OOF-L4",    h4[:oof_codes], ["OOF-L4"]

# Case 5: pure mutual, both annotated → ok
h5 = compile_fixture("p2_case5_pure_mutual_all_decreases.ig")
check "H-09: P2-Case5 status ok",      h5[:status],    "ok"
check "H-10: P2-Case5 zero OOF-L4",   h5[:oof_codes], []

# ─────────────────────────────────────────────────────────────────────────────
# Section I — P3 regression: reference fixtures [8 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== I: P3 regression (reference fixtures) ===\n"

# p3_helper_call: recursive + non-recursive helper → OOF-L4 only on recursive
i_helper = compile_fixture("p3_helper_call.ig")
check "I-01: p3_helper_call ok (recurse_with_helper has fuel)", i_helper[:status], "ok"
check "I-02: p3_helper_call zero OOF-L4",                       i_helper[:oof_codes], []

# p3_three_way_mutual: A→B→C→A, no annotations → OOF-L4 on all three
i_three = compile_fixture("p3_three_way_mutual.ig")
check "I-03: p3_three_way_mutual status oof",    i_three[:status], "oof"
check "I-04: p3_three_way_mutual has 3 OOF-L4", i_three[:oof_codes], ["OOF-L4", "OOF-L4", "OOF-L4"]

# p3_disconnected_sccs: two independent mutual SCCs + non-recursive epsilon
i_disco = compile_fixture("p3_disconnected_sccs.ig")
check "I-05: p3_disconnected_sccs status oof",    i_disco[:status], "oof"
check "I-06: p3_disconnected_sccs has 4 OOF-L4", i_disco[:oof_codes], ["OOF-L4", "OOF-L4", "OOF-L4", "OOF-L4"]

# p3_mixed_with_helper: eval_expr+eval_ref both annotated, format_result helper
i_mixed = compile_fixture("p3_mixed_with_helper.ig")
check "I-07: p3_mixed_with_helper ok (SS-P03 complete)", i_mixed[:status], "ok"
check "I-08: p3_mixed_with_helper zero OOF-L4",          i_mixed[:oof_codes], []

# ─────────────────────────────────────────────────────────────────────────────
# Section J — Unknown calls do not create false SCCs [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== J: Unknown calls — no false SCCs ===\n"

# Calls to names not defined as def functions in this module
check "J-01: unknown_calls.ig status ok",       unknown[:status],    "ok"
check "J-02: unknown_calls.ig zero OOF-L4",     unknown[:oof_codes], []

# Call to a field-access pattern (not a simple fn call)
field_call = compile_source(<<~IG)
  module Test.FieldCall
  type Obj { n: Float }
  def process(o: Obj) -> Float {
    o.n
  }
IG
check "J-03: field access not a call → no OOF-L4", field_call[:oof_codes], []
check "J-04: field access → status ok",             field_call[:status],    "ok"

# Mixed: one def calls an unknown external name, one calls itself
mixed_unknown = compile_source(<<~IG)
  module Test.MixedUnknown
  def uses_external(n: Float) -> Float {
    n
  }
  def self_recursive(n: Float) -> Float {
    self_recursive(n)
  }
IG
check "J-05: mixed_unknown OOF-L4 only on self_recursive",
  mixed_unknown[:nodes], ["self_recursive"]
check "J-06: mixed_unknown total OOF-L4 count is 1",
  mixed_unknown[:oof_codes], ["OOF-L4"]

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
total = $pass + $fail
puts "\n#{'='*60}"
puts "LAB-FUNCTION-RECURSION-P4  #{$pass}/#{total} PASS"
puts "#{'='*60}"

if $fail > 0
  puts "\nFailed checks:"
  $checks.select { |c| !c[:ok] }.each do |c|
    puts "  FAIL #{c[:label]}"
    puts "       got:      #{c[:got].inspect}"
    puts "       expected: #{c[:expected].inspect}"
  end
end

exit($fail == 0 ? 0 : 1)
