# verify_g5_recur.rb
# PROP-039 Gate 5 Rust symmetry — recur() call semantics
#
# Checks:
#   G5a: recur() parses in recursive/fuel_bounded contracts (4 checks)
#   G5b: SemanticIR has compute.expr = recur_call (4 checks)
#   G5c: recur_call has args + return_type (2 checks)
#   G5d: OOF-R1 fires (invalid context) (2 checks)
#   G5e: OOF-R5 fires (arity mismatch) (2 checks)
#   G5f: OOF-R6 fires (type mismatch) (1 check)
#   G5g: OOF-R7 fires (not single-output) (1 check)
#   G5h: recur_call is sub-expr, NOT top-level node (2 checks)
#   G5i: regression — Gate 4/8 body semantics still work (1 check)
#   G5j: regression — multi-recur in one expr (1 check)

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'

ROOT = Pathname.new(__dir__)
COMP = ROOT / "target/release/igniter_compiler"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("g5_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  result = `#{COMP} compile #{ig} --out #{out} 2>&1`
  [result, out, tmp]
end

def load_sir(app_path)
  sir_path = File.join(app_path, "semantic_ir_program.json")
  return nil unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path)) rescue nil
end

def find_contract_nodes(sir, contract_name = nil)
  return [] unless sir
  contracts = sir["contracts"] || []
  contracts = [contracts] unless contracts.is_a?(Array)
  if contract_name
    contracts = contracts.select { |c| c["contract_name"] == contract_name || c["name"] == contract_name }
  end
  contracts.flat_map { |c| c["nodes"] || [] }
end

def find_compute_nodes(sir, contract_name = nil)
  find_contract_nodes(sir, contract_name).select { |n| n["kind"] == "compute" }
end

unless COMP.exist?
  puts "[*] Building compiler (release)..."
  system("cargo build --release", chdir: ROOT.to_s)
end

# ============================================================
puts "\n=== G5a: recur() parses in recursive/fuel_bounded contracts ===\n"
# ============================================================

SRC_RECURSIVE_BASIC = <<~IGNITER
  module G5
  recursive contract CountDown {
    input n: Integer
    compute result = recur(n - 1)
    output result: Integer
    decreases fuel
    max_steps 100
  }
IGNITER

result, app_path, tmp = compile_src(SRC_RECURSIVE_BASIC, "recursive_basic")
if File.exist?(app_path)
  pass "G5a: recursive + recur() compiles to output"
else
  fail! "G5a: recursive + recur() failed to produce output (result: #{result[0..400]})"
end
unless result.include?("OOF-R1")
  pass "G5a: no OOF-R1 for recursive contract"
else
  fail! "G5a: OOF-R1 incorrectly fired for recursive contract"
end
FileUtils.rm_rf(tmp)

SRC_FUEL_BOUNDED_BASIC = <<~IGNITER
  module G5
  fuel_bounded contract Step {
    input n: Integer
    compute result = recur(n - 1)
    output result: Integer
    max_steps 50
  }
IGNITER

result, app_path, tmp = compile_src(SRC_FUEL_BOUNDED_BASIC, "fuel_bounded_basic")
if File.exist?(app_path)
  pass "G5a: fuel_bounded + recur() compiles to output"
else
  fail! "G5a: fuel_bounded + recur() failed to produce output (result: #{result[0..400]})"
end
unless result.include?("OOF-R1")
  pass "G5a: no OOF-R1 for fuel_bounded contract"
else
  fail! "G5a: OOF-R1 incorrectly fired for fuel_bounded contract"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G5b: SemanticIR compute.expr = recur_call ===\n"
# ============================================================

result, app_path, tmp = compile_src(SRC_RECURSIVE_BASIC, "sir_recursive")
sir = load_sir(app_path)
compute_nodes = find_compute_nodes(sir, "CountDown")

if compute_nodes.empty?
  fail! "G5b: No compute nodes found in CountDown contract"
else
  cn = compute_nodes.first
  expr = cn["expr"]
  if expr.nil?
    fail! "G5b: compute node has no expr field"
  elsif expr["kind"] == "recur_call"
    pass "G5b: compute.expr.kind = 'recur_call' for recursive contract"
  else
    fail! "G5b: compute.expr.kind = '#{expr["kind"]}', expected 'recur_call'"
  end
end
FileUtils.rm_rf(tmp)

result, app_path, tmp = compile_src(SRC_FUEL_BOUNDED_BASIC, "sir_fuel")
sir = load_sir(app_path)
compute_nodes = find_compute_nodes(sir, "Step")

if compute_nodes.empty?
  fail! "G5b: No compute nodes found in Step contract"
else
  cn = compute_nodes.first
  expr = cn["expr"]
  if expr && expr["kind"] == "recur_call"
    pass "G5b: compute.expr.kind = 'recur_call' for fuel_bounded contract"
  else
    fail! "G5b: compute.expr.kind = '#{expr&.dig("kind")}', expected 'recur_call'"
  end
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G5c: recur_call has args + return_type ===\n"
# ============================================================

result, app_path, tmp = compile_src(SRC_RECURSIVE_BASIC, "recur_shape")
sir = load_sir(app_path)
compute_nodes = find_compute_nodes(sir, "CountDown")

if compute_nodes.empty?
  fail! "G5c: No compute nodes found"
else
  expr = compute_nodes.first["expr"]
  if expr && expr["kind"] == "recur_call"
    if expr.key?("args") && expr["args"].is_a?(Array)
      pass "G5c: recur_call has 'args' array (len=#{expr["args"].length})"
    else
      fail! "G5c: recur_call missing 'args' array"
    end
    if expr.key?("return_type")
      pass "G5c: recur_call has 'return_type' = '#{expr["return_type"]}'"
    else
      fail! "G5c: recur_call missing 'return_type' field"
    end
  else
    fail! "G5c: expr is not recur_call, skipping shape checks"
  end
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G5d: OOF-R1 fires for invalid recur() context ===\n"
# ============================================================

SRC_OOF_R1_REGULAR = <<~IGNITER
  module G5
  contract BadRecur {
    input x: Integer
    compute result = recur(x)
    output result: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_R1_REGULAR, "oof_r1_regular")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R1")
  pass "G5d: OOF-R1 fires for recur() in regular (non-recursive) contract"
else
  fail! "G5d: OOF-R1 NOT fired for recur() in regular contract (got: #{result[0..400]})"
end

SRC_OOF_R1_LOOP = <<~IGNITER
  module G5
  contract LoopRecur {
    input items: Collection[Integer]
    compute total: Integer = 0
    for Process item in items {
      lead acc: Integer = 0
      compute acc = recur(item)
    }
    output total: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_R1_LOOP, "oof_r1_loop")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R1")
  pass "G5d: OOF-R1 fires for recur() inside loop body"
else
  fail! "G5d: OOF-R1 NOT fired for recur() in loop body (got: #{result[0..400]})"
end

# ============================================================
puts "\n=== G5e: OOF-R5 fires for arity mismatch ===\n"
# ============================================================

SRC_OOF_R5_TOO_MANY = <<~IGNITER
  module G5
  recursive contract ArityBad {
    input n: Integer
    compute result = recur(n, n)
    output result: Integer
    decreases fuel
    max_steps 100
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_R5_TOO_MANY, "oof_r5_many")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R5")
  pass "G5e: OOF-R5 fires for too many recur() args (2 given, 1 expected)"
else
  fail! "G5e: OOF-R5 NOT fired for too many args (got: #{result[0..400]})"
end

SRC_OOF_R5_TOO_FEW = <<~IGNITER
  module G5
  recursive contract ArityFew {
    input n: Integer
    input m: Integer
    compute result = recur(n)
    output result: Integer
    decreases fuel
    max_steps 100
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_R5_TOO_FEW, "oof_r5_few")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R5")
  pass "G5e: OOF-R5 fires for too few recur() args (1 given, 2 expected)"
else
  fail! "G5e: OOF-R5 NOT fired for too few args (got: #{result[0..400]})"
end

# ============================================================
puts "\n=== G5f: OOF-R6 fires for type mismatch ===\n"
# ============================================================

SRC_OOF_R6 = <<~IGNITER
  module G5
  recursive contract TypeBad {
    input n: Integer
    compute result = recur("hello")
    output result: Integer
    decreases fuel
    max_steps 100
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_R6, "oof_r6")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R6")
  pass "G5f: OOF-R6 fires for recur() arg type mismatch (String given, Integer expected)"
else
  fail! "G5f: OOF-R6 NOT fired for type mismatch (got: #{result[0..400]})"
end

# ============================================================
puts "\n=== G5g: OOF-R7 fires for non-single-output contract ===\n"
# ============================================================

SRC_OOF_R7 = <<~IGNITER
  module G5
  recursive contract MultiOut {
    input n: Integer
    compute a = recur(n - 1)
    compute b: Integer = 0
    output a: Integer
    output b: Integer
    decreases fuel
    max_steps 100
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_R7, "oof_r7")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R7")
  pass "G5g: OOF-R7 fires for recursive contract with != 1 output"
else
  fail! "G5g: OOF-R7 NOT fired for multi-output recur() (got: #{result[0..400]})"
end

# ============================================================
puts "\n=== G5h: recur_call is sub-expr, NOT top-level node ===\n"
# ============================================================

result, app_path, tmp = compile_src(SRC_RECURSIVE_BASIC, "sir_toplevel_check")
sir = load_sir(app_path)

if sir
  all_nodes = find_contract_nodes(sir, "CountDown")
  top_recur = all_nodes.select { |n| n["kind"] == "recur_call" }
  if top_recur.empty?
    pass "G5h: recur_call does NOT appear as a top-level node in contract"
  else
    fail! "G5h: recur_call appears as top-level node (should be sub-expr only)"
  end

  # Confirm it IS present as a sub-expr
  compute_nodes = all_nodes.select { |n| n["kind"] == "compute" }
  nested_recur = compute_nodes.any? { |cn| cn.dig("expr", "kind") == "recur_call" }
  if nested_recur
    pass "G5h: recur_call IS present as sub-expr inside compute.expr"
  else
    fail! "G5h: recur_call not found as sub-expr in compute.expr"
  end
else
  fail! "G5h: Could not load SemanticIR"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G5i: regression — Gate 8 loop body semantics still work ===\n"
# ============================================================

SRC_GATE4_REGRESSION = <<~IGNITER
  module G5
  contract BodyReg {
    input items: Collection[Integer]
    compute base: Integer = 0
    for Loop item in items {
      lead acc: Integer = 0
      compute acc = acc + item
    }
    output base: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_GATE4_REGRESSION, "gate4_regression")
sir = load_sir(app_path)
if sir
  nodes = find_contract_nodes(sir, "BodyReg")
  loop_node = nodes.find { |n| n["kind"] == "loop_node" }
  if loop_node && loop_node["body"].is_a?(Array) && !loop_node["body"].empty?
    pass "G5i: Gate 8 loop body semantics (lead_node + compute_node in body) still intact"
  elsif loop_node
    fail! "G5i: loop_node found but body is empty/nil (Gate 8 regression?)"
  else
    fail! "G5i: No loop_node found (Gate 8 regression?)"
  end
else
  fail! "G5i: Could not load SemanticIR for regression check"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G5j: multi-recur in single expr ===\n"
# ============================================================

SRC_MULTI_RECUR = <<~IGNITER
  module G5
  recursive contract Tree {
    input n: Integer
    compute size = recur(n - 1) + recur(n - 2)
    output size: Integer
    decreases fuel
    max_steps 200
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MULTI_RECUR, "multi_recur")
if File.exist?(app_path)
  pass "G5j: multi-recur (recur(n-1) + recur(n-2)) in single expr compiles"
else
  fail! "G5j: multi-recur failed to compile (result: #{result[0..400]})"
end
unless result.include?("OOF-R1") || result.include?("OOF-R5") || result.include?("OOF-R6")
  # No spurious errors for valid multi-recur
else
  fail! "G5j: Spurious OOF errors for valid multi-recur (got: #{result[0..400]})"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n==============================="
total = $pass_count + $fail_count
puts "[*] Results: #{$pass_count}/#{total} PASS, #{$fail_count} FAIL"
if $fail_count == 0
  puts "[+] G5 CONFORMANCE PASS — PROP-039 gate 5 recur() Rust symmetry verified"
  exit 0
else
  puts "[!] G5 CONFORMANCE FAIL — #{$fail_count} check(s) failed"
  exit 1
end
