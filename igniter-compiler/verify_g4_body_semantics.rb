# verify_g4_body_semantics.rb
# PROP-039 Gate 8 Rust symmetry verification — loop body semantics
#
# Checks:
#   G8a: `lead` parses correctly inside FiniteLoop / budgeted loop
#   G8b: SemanticIR has `body` with lead_node + compute_node
#   G8c: `item_type` present in loop_node
#   G8d: OOF-L7 fires (compute targets item / outer symbol)
#   G8e: OOF-L8 fires (lead shadows outer symbol or item variable)
#   G8f: OOF-L5 fires (lead at contract level, nested loop, non-literal initial)
#   G8g: `body_nodes` still contains compute nodes (VM compat)
#   G8h: `body` and `body_nodes` both present (two-track architecture)

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../tools/proof_harness/bounded_command'

ROOT = Pathname.new(__dir__)
COMP = ROOT / "target/release/igniter_compiler"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("g8_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  # LAB-PROOF-HYGIENE-P1: bounded execution — hard timeout, kills process group
  r = BoundedCommand.run("#{COMP} compile #{ig} --out #{out}",
                         label: "compile:#{label}",
                         timeout: BoundedCommand::EXEC_TIMEOUT)
  BoundedCommand.print_result(r) unless r.ok?
  [r.combined, out, tmp]
end

def load_sir(app_path)
  sir_path = File.join(app_path, "semantic_ir_program.json")
  return nil unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path)) rescue nil
end

def find_loop_nodes(sir)
  return [] unless sir
  loop_nodes = []
  contracts = sir["contracts"] || []
  (contracts.is_a?(Array) ? contracts : [contracts]).each do |contract|
    nodes = contract["nodes"] || []
    nodes.each { |n| loop_nodes << n if n["kind"] == "loop_node" }
  end
  loop_nodes
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

# ============================================================
puts "\n=== G8a: lead parses correctly inside loop body ===\n"
# ============================================================

SRC_LEAD_BASIC = <<~IGNITER
  module G8
  contract SumWithLead {
    input items: Collection[Integer]
    compute total: Integer = 0
    for Accumulate item in items {
      lead acc: Integer = 0
      compute acc = acc + item
    }
    output total: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_LEAD_BASIC, "lead_basic")
if File.exist?(app_path)
  pass "G8a: lead inside FiniteLoop parses and compiles"
else
  fail! "G8a: lead inside FiniteLoop failed to compile (output: #{result[0..400]})"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G8b: SemanticIR body = [lead_node, compute_node] ===\n"
# ============================================================

SRC_CANON_BODY = <<~IGNITER
  module G8
  contract CanonBody {
    input nums: Collection[Integer]
    compute total: Integer = 0
    for Accumulate item in nums {
      lead acc: Integer = 0
      compute acc = acc + item
    }
    output total: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_CANON_BODY, "canon_body")
sir = load_sir(app_path)
loop_nodes = find_loop_nodes(sir)

if loop_nodes.empty?
  fail! "G8b: No loop_node found in SemanticIR"
else
  ln = loop_nodes.first
  body = ln["body"]
  if body.nil?
    fail! "G8b: loop_node has no 'body' field"
  elsif !body.is_a?(Array)
    fail! "G8b: 'body' is not an array (got: #{body.class})"
  else
    lead_nodes    = body.select { |n| n["kind"] == "lead_node" }
    compute_nodes = body.select { |n| n["kind"] == "compute_node" }

    if lead_nodes.any?
      ln_node = lead_nodes.first
      pass "G8b: body contains lead_node (name=#{ln_node['name']}, type=#{ln_node['type']})"
      if ln_node["initial"]
        pass "G8b: lead_node has initial field"
      else
        fail! "G8b: lead_node missing initial field"
      end
    else
      fail! "G8b: body has no lead_node (body: #{body.map{|n| n['kind']}})"
    end

    if compute_nodes.any?
      pass "G8b: body contains compute_node (name=#{compute_nodes.first['name']})"
    else
      fail! "G8b: body has no compute_node"
    end

    # Verify ordering: lead_node before compute_node
    first_lead_idx    = body.index { |n| n["kind"] == "lead_node" }
    first_compute_idx = body.index { |n| n["kind"] == "compute_node" }
    if first_lead_idx && first_compute_idx && first_lead_idx < first_compute_idx
      pass "G8b: lead_node appears before compute_node in body"
    elsif first_lead_idx && first_compute_idx
      fail! "G8b: lead_node (#{first_lead_idx}) appears AFTER compute_node (#{first_compute_idx})"
    end
  end
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G8c: item_type stored in loop_node ===\n"
# ============================================================

SRC_ITEM_TYPE = <<~IGNITER
  module G8
  contract ItemTypeCheck {
    input values: Collection[Integer]
    compute result: Integer = 0
    for Process v in values {
      lead acc: Integer = 0
      compute acc = acc + v
    }
    output result: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_ITEM_TYPE, "item_type")
sir = load_sir(app_path)
loop_nodes = find_loop_nodes(sir)

if loop_nodes.empty?
  fail! "G8c: No loop_node found"
else
  ln = loop_nodes.first
  if ln["item_type"]
    pass "G8c: item_type='#{ln['item_type']}' present in loop_node"
    if ln["item_type"] == "Integer"
      pass "G8c: item_type correctly resolved to 'Integer' from Collection[Integer]"
    else
      fail! "G8c: item_type='#{ln['item_type']}', expected 'Integer'"
    end
  else
    fail! "G8c: item_type missing from loop_node (keys: #{ln.keys})"
  end
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G8d: OOF-L7 fires (read-only targets) ===\n"
# ============================================================

# OOF-L7: compute targets loop item (read-only) — gate-8 mode (has lead)
SRC_L7_ITEM = <<~IGNITER
  module G8
  contract L7Item {
    input items: Collection[Integer]
    compute total: Integer = 0
    for Process item in items {
      lead acc: Integer = 0
      compute item = item + 1
    }
    output total: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L7_ITEM, "l7_item")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L7")
  pass "G8d: OOF-L7 fires when compute targets loop item (read-only)"
else
  fail! "G8d: OOF-L7 NOT fired for compute targeting loop item (got: #{result[0..300]})"
end

# OOF-L7: compute targets outer contract symbol (read-only outer state) — gate-8 mode (has lead)
SRC_L7_OUTER = <<~IGNITER
  module G8
  contract L7Outer {
    input items: Collection[Integer]
    input factor: Integer
    compute total: Integer = 0
    for Process item in items {
      lead acc: Integer = 0
      compute factor = factor + item
    }
    output total: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L7_OUTER, "l7_outer")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L7")
  pass "G8d: OOF-L7 fires when compute targets outer contract symbol (read-only)"
else
  fail! "G8d: OOF-L7 NOT fired for compute targeting outer symbol (got: #{result[0..300]})"
end

# ============================================================
puts "\n=== G8e: OOF-L8 fires (lead shadows outer / item) ===\n"
# ============================================================

# OOF-L8: lead shadows outer contract symbol
# Fixture: clean Collection[Integer] source — no OOF-L1 contamination;
# lead 'total' shadows outer compute 'total' → pure OOF-L8 signal.
SRC_L8_OUTER = <<~IGNITER
  module G8
  contract L8Outer {
    input items: Collection[Integer]
    compute total: Integer = 0
    for Process item in items {
      lead total: Integer = 0
      compute total = total + item
    }
    output total: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L8_OUTER, "l8_outer")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L8")
  pass "G8e: OOF-L8 fires when lead shadows outer contract symbol"
else
  fail! "G8e: OOF-L8 NOT fired for lead shadowing outer symbol (got: #{result[0..300]})"
end

# OOF-L8: lead shadows loop item variable
SRC_L8_ITEM = <<~IGNITER
  module G8
  contract L8Item {
    input nums: Collection[Integer]
    compute result: Integer = 0
    for Process item in nums {
      lead item: Integer = 0
      compute item = item + 1
    }
    output result: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L8_ITEM, "l8_item")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L8")
  pass "G8e: OOF-L8 fires when lead shadows loop item variable"
else
  fail! "G8e: OOF-L8 NOT fired for lead shadowing item variable (got: #{result[0..300]})"
end

# ============================================================
puts "\n=== G8f: OOF-L5 fires (lead at contract level) ===\n"
# ============================================================

SRC_L5_CONTRACT_LEVEL = <<~IGNITER
  module G8
  contract L5ContractLevel {
    input items: Collection[Integer]
    lead acc: Integer = 0
    compute total: Integer = 0
    output total: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L5_CONTRACT_LEVEL, "l5_contract")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L5")
  pass "G8f: OOF-L5 fires when lead appears at contract level"
else
  fail! "G8f: OOF-L5 NOT fired for lead at contract level (got: #{result[0..300]})"
end

# OOF-L5: nested loop inside loop body
SRC_L5_NESTED = <<~IGNITER
  module G8
  contract L5Nested {
    input items: Collection[Integer]
    compute total: Integer = 0
    for Outer item in items {
      for Inner inner_item in items {
        compute inner_item = inner_item + 1
      }
    }
    output total: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L5_NESTED, "l5_nested")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L5")
  pass "G8f: OOF-L5 fires for nested loop inside loop body"
else
  fail! "G8f: OOF-L5 NOT fired for nested loop (got: #{result[0..300]})"
end

# OOF-L5: lead initial is a non-literal expression (ref to loop item)
# Gate 8 v0 rule: initial MUST be a static literal — `lead acc: Integer = item` is an OOF-L5.
SRC_L5_NONLITERAL = <<~IGNITER
  module G8
  contract L5NonLiteral {
    input items: Collection[Integer]
    compute base: Integer = 0
    for Process item in items {
      lead acc: Integer = item
      compute acc = acc + item
    }
    output base: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L5_NONLITERAL, "l5_nonliteral")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L5")
  pass "G8f: OOF-L5 fires when lead initial is non-literal (ref to loop item)"
else
  fail! "G8f: OOF-L5 NOT fired for non-literal lead initial — lead acc: Integer = item (got: #{result[0..300]})"
end

# OOF-L5: lead initial is a non-literal expression (ref to outer compute)
SRC_L5_NONLITERAL_OUTER = <<~IGNITER
  module G8
  contract L5NonLiteralOuter {
    input items: Collection[Integer]
    compute base: Integer = 42
    for Process item in items {
      lead acc: Integer = base
      compute acc = acc + item
    }
    output base: Integer
  }
IGNITER

result, _out, tmp = compile_src(SRC_L5_NONLITERAL_OUTER, "l5_nonliteral_outer")
FileUtils.rm_rf(tmp)
if result.include?("OOF-L5")
  pass "G8f: OOF-L5 fires when lead initial is non-literal (ref to outer compute)"
else
  fail! "G8f: OOF-L5 NOT fired for non-literal lead initial — lead acc: Integer = base (got: #{result[0..300]})"
end

# ============================================================
puts "\n=== G8g: body_nodes still contains compute nodes (VM compat) ===\n"
# ============================================================

SRC_BODY_NODES = <<~IGNITER
  module G8
  contract BodyNodesCompat {
    input nums: Collection[Integer]
    compute total: Integer = 0
    for Accumulate item in nums {
      lead acc: Integer = 0
      compute acc = acc + item
    }
    output total: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_BODY_NODES, "body_nodes_compat")
sir = load_sir(app_path)
loop_nodes = find_loop_nodes(sir)

if loop_nodes.empty?
  fail! "G8g: No loop_node found"
else
  ln = loop_nodes.first
  body_nodes = ln["body_nodes"]
  if body_nodes.nil?
    fail! "G8g: body_nodes field missing from loop_node"
  elsif !body_nodes.is_a?(Array)
    fail! "G8g: body_nodes is not an array"
  else
    compute_nodes = body_nodes.select { |n| n["kind"] == "compute" }
    lead_nodes    = body_nodes.select { |n| n["kind"] == "lead" || n["kind"] == "lead_node" }

    if compute_nodes.any?
      pass "G8g: body_nodes contains compute node(s) for VM (backward compat preserved)"
    else
      fail! "G8g: body_nodes has no compute nodes (VM compat broken) — got: #{body_nodes.map{|n| n['kind']}}"
    end

    if lead_nodes.empty?
      pass "G8g: body_nodes does NOT contain lead nodes (VM-only field, compute-only)"
    else
      fail! "G8g: body_nodes contains lead nodes — should be compute-only for VM compat"
    end
  end
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== G8h: body field separate from body_nodes (two-track) ===\n"
# ============================================================

SRC_DUAL_TRACK = <<~IGNITER
  module G8
  contract DualTrack {
    input items: Collection[Integer]
    compute total: Integer = 0
    for Process item in items {
      lead acc: Integer = 0
      compute acc = acc + item
    }
    output total: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_DUAL_TRACK, "dual_track")
sir = load_sir(app_path)
loop_nodes = find_loop_nodes(sir)

if loop_nodes.any?
  ln = loop_nodes.first
  has_body       = ln.key?("body")
  has_body_nodes = ln.key?("body_nodes")
  if has_body && has_body_nodes
    pass "G8h: loop_node has both 'body' (canon) and 'body_nodes' (VM) fields — two-track architecture"
  elsif has_body
    fail! "G8h: loop_node has 'body' but missing 'body_nodes' (VM compat broken)"
  elsif has_body_nodes
    fail! "G8h: loop_node has 'body_nodes' but missing 'body' (canon gate 8 field absent)"
  else
    fail! "G8h: loop_node missing both 'body' and 'body_nodes'"
  end
else
  fail! "G8h: No loop_node found"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n==============================="
total = $pass_count + $fail_count
puts "[*] Results: #{$pass_count}/#{total} PASS, #{$fail_count} FAIL"
if $fail_count == 0
  puts "[+] G8 CONFORMANCE PASS — PROP-039 gate 8 Rust symmetry verified"
  exit 0
else
  puts "[!] G8 CONFORMANCE FAIL — #{$fail_count} check(s) failed"
  exit 1
end
