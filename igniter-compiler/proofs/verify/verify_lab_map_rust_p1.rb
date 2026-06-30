# verify_lab_map_rust_p1.rb
# LAB-MAP-RUST-P1 — Rust lab Map[String,V] compiler symmetry
#
# Checks:
#   MAP-A  (4): Map[String,V] annotation accepted; no OOF for String key + non-Any value
#   MAP-B  (6): OOF-MAP1/2/3 fire on non-String key, Any value, Unknown output annotation
#   MAP-C  (7): map_get/has_key/from_pairs/map_empty/or_else type inference
#   MAP-D  (5): Record/Map bridge — FullRackResponse.headers → Map[String,String];
#               map_get → Option[String]; or_else → String; map_has_key → Bool
#   MAP-E  (4): SemanticIR resolved_type shapes for Map stdlib calls
#   MAP-F  (4): Regression — existing type inference unaffected

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../../../../tools/proof_harness/bounded_command'

ROOT = Pathname.new(__dir__).parent.parent
COMP = ROOT / "target/release/igniter_compiler"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("map_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
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

def find_compute_nodes(sir, contract_name = nil)
  return [] unless sir
  contracts = sir["contracts"] || []
  contracts = [contracts] unless contracts.is_a?(Array)
  if contract_name
    contracts = contracts.select { |c| c["contract_name"] == contract_name || c["name"] == contract_name }
  end
  contracts.flat_map { |c| c["nodes"] || [] }.select { |n| n["kind"] == "compute" }
end

# In Rust SIR, resolved_type is stored in node["type"] (not node["expr"]["resolved_type"])
def node_type(node)
  node["type"]
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

# ============================================================
puts "\n=== MAP-A: Map[String,V] annotation accepted (no OOF) ===\n"
# ============================================================

SRC_MAP_A1 = <<~IGNITER
  module MapAccept
  pure contract StringStringMap {
    input hdrs : Map[String, String]
    output out : Map[String, String]
    compute out = hdrs
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_A1, "map_a1")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP")
  fail! "MAP-A1: OOF-MAP fired for Map[String,String] — should be accepted (got: #{result[0..300]})"
else
  pass "MAP-A1: Map[String,String] accepted — no OOF-MAP"
end

SRC_MAP_A2 = <<~IGNITER
  module MapAccept
  pure contract StringIntMap {
    input counts : Map[String, Integer]
    output counts : Map[String, Integer]
    compute counts = counts
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_A2, "map_a2")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP")
  fail! "MAP-A2: OOF-MAP fired for Map[String,Integer] — should be accepted (got: #{result[0..300]})"
else
  pass "MAP-A2: Map[String,Integer] accepted — no OOF-MAP"
end

SRC_MAP_A3 = <<~IGNITER
  module MapAccept
  type Config {
    name: String
    value: String
  }
  pure contract StringRecordMap {
    input cfg : Map[String, Config]
    output cfg : Map[String, Config]
    compute cfg = cfg
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_A3, "map_a3")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP")
  fail! "MAP-A3: OOF-MAP fired for Map[String,Config] — should be accepted (got: #{result[0..300]})"
else
  pass "MAP-A3: Map[String,Config] accepted — no OOF-MAP"
end

SRC_MAP_A4 = <<~IGNITER
  module MapAccept
  pure contract StringBoolMap {
    input flags : Map[String, Bool]
    output flags : Map[String, Bool]
    compute flags = flags
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_A4, "map_a4")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP")
  fail! "MAP-A4: OOF-MAP fired for Map[String,Bool] — should be accepted (got: #{result[0..300]})"
else
  pass "MAP-A4: Map[String,Bool] accepted — no OOF-MAP"
end

# ============================================================
puts "\n=== MAP-B: OOF-MAP1/2/3 diagnostic codes ===\n"
# ============================================================

SRC_MAP_B1 = <<~IGNITER
  module MapDiag
  pure contract IntKey {
    input m : Map[Integer, String]
    output m : Map[Integer, String]
    compute m = m
  }
IGNITER

result, _out, tmp = compile_src(SRC_MAP_B1, "map_b1")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP1")
  pass "MAP-B1: OOF-MAP1 fires for Map[Integer,String] key"
else
  fail! "MAP-B1: OOF-MAP1 NOT fired for Map[Integer,String] (got: #{result[0..400]})"
end

SRC_MAP_B2 = <<~IGNITER
  module MapDiag
  pure contract BoolKey {
    input m : Map[Bool, String]
    output m : Map[Bool, String]
    compute m = m
  }
IGNITER

result, _out, tmp = compile_src(SRC_MAP_B2, "map_b2")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP1")
  pass "MAP-B2: OOF-MAP1 fires for Map[Bool,String] key"
else
  fail! "MAP-B2: OOF-MAP1 NOT fired for Map[Bool,String] (got: #{result[0..400]})"
end

# OOF-MAP1 message format check
if result.include?("Map key type in v0 must be String")
  pass "MAP-B2b: OOF-MAP1 message contains canon prefix 'Map key type in v0 must be String'"
else
  fail! "MAP-B2b: OOF-MAP1 message format mismatch (got: #{result[0..500]})"
end

SRC_MAP_B3 = <<~IGNITER
  module MapDiag
  pure contract AnyValue {
    input m : Map[String, Any]
    output m : Map[String, Any]
    compute m = m
  }
IGNITER

result, _out, tmp = compile_src(SRC_MAP_B3, "map_b3")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP2")
  pass "MAP-B3: OOF-MAP2 fires for Map[String,Any]"
else
  fail! "MAP-B3: OOF-MAP2 NOT fired for Map[String,Any] (got: #{result[0..400]})"
end

# OOF-MAP2 message format check
if result.include?("permanently closed")
  pass "MAP-B3b: OOF-MAP2 message contains 'permanently closed'"
else
  fail! "MAP-B3b: OOF-MAP2 message format mismatch (got: #{result[0..500]})"
end

SRC_MAP_B4_OUTPUT = <<~IGNITER
  module MapDiag
  pure contract UnknownValueOutput {
    input n : Integer
    output m : Map[String, Unknown]
    compute m = map_empty()
  }
IGNITER

result, _out, tmp = compile_src(SRC_MAP_B4_OUTPUT, "map_b4_output")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP3")
  pass "MAP-B4: OOF-MAP3 fires for Map[String,Unknown] in output annotation"
else
  fail! "MAP-B4: OOF-MAP3 NOT fired for Map[String,Unknown] output (got: #{result[0..400]})"
end

SRC_MAP_B5_INPUT = <<~IGNITER
  module MapDiag
  pure contract UnknownValueInput {
    input m : Map[String, Unknown]
    output n : Integer
    compute n = 42
  }
IGNITER

result, _out, tmp = compile_src(SRC_MAP_B5_INPUT, "map_b5_input")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP3")
  fail! "MAP-B5: OOF-MAP3 fired for Map[String,Unknown] in INPUT — should not fire on input"
else
  pass "MAP-B5: OOF-MAP3 NOT fired for Map[String,Unknown] in input — correct"
end

# ============================================================
puts "\n=== MAP-C: Map stdlib type inference ===\n"
# ============================================================

SRC_MAP_GET = <<~IGNITER
  module MapOps
  pure contract MapGetTest {
    input hdrs : Map[String, String]
    input key  : String
    compute val = map_get(hdrs, key)
    output val : Option[String]
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_GET, "map_get")
if result.include?("OOF-TY0") && result.include?("Unknown function")
  fail! "MAP-C1: map_get not recognized (got: #{result[0..400]})"
elsif result.include?("OOF-TY0")
  fail! "MAP-C1: unexpected OOF-TY0 for map_get (got: #{result[0..400]})"
else
  pass "MAP-C1: map_get recognized — no Unknown function error"
end
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "MapGetTest")
val_node = cn.find { |n| n["name"] == "val" }
if val_node
  rt = node_type(val_node)
  if rt && rt["name"] == "Option"
    inner = (rt["params"] || []).first
    inner_name = inner.is_a?(Hash) ? inner["name"] : inner.to_s
    if inner_name == "String"
      pass "MAP-C1b: map_get resolved_type = Option[String]"
    else
      fail! "MAP-C1b: map_get resolved_type inner = '#{inner_name}', expected String"
    end
  else
    fail! "MAP-C1b: map_get resolved_type = '#{rt&.dig("name")}', expected Option (node: #{val_node.inspect[0..200]})"
  end
else
  fail! "MAP-C1b: val compute node not found in SIR"
end
FileUtils.rm_rf(tmp)

SRC_MAP_HAS_KEY = <<~IGNITER
  module MapOps
  pure contract MapHasKeyTest {
    input hdrs : Map[String, String]
    input key  : String
    compute present = map_has_key(hdrs, key)
    output present : Bool
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_HAS_KEY, "map_has_key")
if result.include?("OOF-TY0") && result.include?("Unknown function")
  fail! "MAP-C2: map_has_key not recognized (got: #{result[0..400]})"
else
  pass "MAP-C2: map_has_key recognized — no Unknown function error"
end
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "MapHasKeyTest")
node = cn.find { |n| n["name"] == "present" }
if node
  rt = node_type(node)
  if rt && rt["name"] == "Bool"
    pass "MAP-C2b: map_has_key resolved_type = Bool"
  else
    fail! "MAP-C2b: map_has_key resolved_type = '#{rt&.dig("name")}', expected Bool"
  end
else
  fail! "MAP-C2b: present compute node not found in SIR"
end
FileUtils.rm_rf(tmp)

SRC_MAP_EMPTY = <<~IGNITER
  module MapOps
  pure contract MapEmptyTest {
    input n : Integer
    compute hdrs = map_empty()
    output n : Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_MAP_EMPTY, "map_empty")
if result.include?("OOF-TY0") && result.include?("Unknown function")
  fail! "MAP-C3: map_empty not recognized (got: #{result[0..400]})"
else
  pass "MAP-C3: map_empty recognized — no Unknown function error"
end
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "MapEmptyTest")
node = cn.find { |n| n["name"] == "hdrs" }
if node
  rt = node_type(node)
  if rt && rt["name"] == "Map"
    pass "MAP-C3b: map_empty resolved_type.name = Map"
  else
    fail! "MAP-C3b: map_empty resolved_type = '#{rt&.dig("name")}', expected Map"
  end
else
  fail! "MAP-C3b: hdrs compute node not found in SIR"
end
FileUtils.rm_rf(tmp)

SRC_OR_ELSE = <<~IGNITER
  module MapOps
  pure contract OrElseTest {
    input hdrs : Map[String, String]
    input key  : String
    compute raw    = map_get(hdrs, key)
    compute result = or_else(raw, "default")
    output result : String
  }
IGNITER

result, app_path, tmp = compile_src(SRC_OR_ELSE, "or_else")
if result.include?("OOF-TY0")
  fail! "MAP-C4: unexpected OOF-TY0 for or_else chain (got: #{result[0..400]})"
else
  pass "MAP-C4: or_else(map_get(...)) chain — no OOF-TY0"
end
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "OrElseTest")
node = cn.find { |n| n["name"] == "result" }
if node
  rt = node_type(node)
  if rt && rt["name"] == "String"
    pass "MAP-C4b: or_else resolved_type = String (V extracted from Option[String])"
  else
    fail! "MAP-C4b: or_else resolved_type = '#{rt&.dig("name")}', expected String"
  end
else
  fail! "MAP-C4b: result compute node not found in SIR"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== MAP-D: Record/Map bridge — FullRackResponse ===\n"
# ============================================================

SRC_BRIDGE = <<~IGNITER
  module MapBridge

  type FullRackResponse {
    status  : Integer
    body    : String
    headers : Map[String, String]
  }

  pure contract ContentTypeFromResponse {
    input response : FullRackResponse
    input key      : String
    compute raw_ct   = map_get(response.headers, key)
    compute ct       = or_else(raw_ct, "text/plain")
    compute has_ct   = map_has_key(response.headers, key)
    output ct        : String
    output has_ct    : Bool
  }
IGNITER

result, app_path, tmp = compile_src(SRC_BRIDGE, "bridge")
if result.include?("OOF-TY0")
  fail! "MAP-D1: unexpected OOF-TY0 in Record/Map bridge (got: #{result[0..400]})"
else
  pass "MAP-D1: Record/Map bridge compiles — no OOF-TY0"
end

sir = load_sir(app_path)
cn = find_compute_nodes(sir, "ContentTypeFromResponse")

raw_ct_node = cn.find { |n| n["name"] == "raw_ct" }
if raw_ct_node
  rt = node_type(raw_ct_node)
  if rt && rt["name"] == "Option"
    params = rt["params"] || []
    inner = params.first
    inner_name = inner.is_a?(Hash) ? inner["name"] : inner.to_s
    if inner_name == "String"
      pass "MAP-D2: map_get(response.headers, key) → Option[String]"
    else
      fail! "MAP-D2: map_get → Option[#{inner_name}], expected Option[String]"
    end
  else
    fail! "MAP-D2: raw_ct resolved_type = '#{rt&.dig("name")}', expected Option"
  end
else
  fail! "MAP-D2: raw_ct compute node not found in SIR"
end

ct_node = cn.find { |n| n["name"] == "ct" }
if ct_node
  rt = node_type(ct_node)
  if rt && rt["name"] == "String"
    pass "MAP-D3: or_else(raw_ct, 'text/plain') → String"
  else
    fail! "MAP-D3: ct resolved_type = '#{rt&.dig("name")}', expected String"
  end
else
  fail! "MAP-D3: ct compute node not found in SIR"
end

has_ct_node = cn.find { |n| n["name"] == "has_ct" }
if has_ct_node
  rt = node_type(has_ct_node)
  if rt && rt["name"] == "Bool"
    pass "MAP-D4: map_has_key(response.headers, key) → Bool"
  else
    fail! "MAP-D4: has_ct resolved_type = '#{rt&.dig("name")}', expected Bool"
  end
else
  fail! "MAP-D4: has_ct compute node not found in SIR"
end
FileUtils.rm_rf(tmp)

# MAP-D5: FullRackResponse headers field access resolves to Map[String,String] — params preserved
SRC_BRIDGE_FIELD_ACCESS = <<~IGNITER
  module MapBridge

  type FullRackResponse {
    status  : Integer
    body    : String
    headers : Map[String, String]
  }

  pure contract FieldTypeCheck {
    input response : FullRackResponse
    compute hdrs   = response.headers
    output status  : Integer
    compute status = response.status
  }
IGNITER

result, app_path, tmp = compile_src(SRC_BRIDGE_FIELD_ACCESS, "bridge_field")
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "FieldTypeCheck")
hdrs_node = cn.find { |n| n["name"] == "hdrs" }
if hdrs_node
  ht = node_type(hdrs_node)
  if ht && ht["name"] == "Map"
    params = ht["params"] || []
    # params may be ["String","String"] or [{name:"String"},{name:"String"}]
    key_name = params[0].is_a?(Hash) ? params[0]["name"] : params[0].to_s
    val_name = params[1].is_a?(Hash) ? params[1]["name"] : params[1].to_s
    if key_name == "String" && val_name == "String"
      pass "MAP-D5: response.headers field access → Map[String,String] — params preserved"
    else
      fail! "MAP-D5: headers Map params = [#{key_name}, #{val_name}], expected [String, String]"
    end
  else
    fail! "MAP-D5: hdrs node type = '#{ht&.dig("name")}', expected Map"
  end
else
  fail! "MAP-D5: hdrs compute node not found in SIR (nodes: #{cn.map{|n|n['name']}.inspect})"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== MAP-E: SemanticIR resolved_type shapes ===\n"
# ============================================================

SRC_SIR_SHAPES = <<~IGNITER
  module MapSIR
  pure contract SIRShapes {
    input hdrs : Map[String, String]
    input key  : String
    compute val     = map_get(hdrs, key)
    compute present = map_has_key(hdrs, key)
    compute empty   = map_empty()
    compute ct      = or_else(val, "text/plain")
    output ct       : String
    output present  : Bool
  }
IGNITER

result, app_path, tmp = compile_src(SRC_SIR_SHAPES, "sir_shapes")
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "SIRShapes")

# MAP-E1: map_get call node kind
val_node = cn.find { |n| n["name"] == "val" }
if val_node
  expr = val_node["expr"]
  if expr && expr["kind"] == "call"
    pass "MAP-E1: map_get SIR node kind = 'call'"
  else
    fail! "MAP-E1: map_get SIR node kind = '#{expr&.dig("kind")}', expected 'call'"
  end
else
  fail! "MAP-E1: val compute node not found"
end

# MAP-E2: map_get resolved_type params structure
if val_node
  rt = node_type(val_node)
  if rt && rt["name"] == "Option"
    inner = (rt["params"] || []).first
    inner_name = inner.is_a?(Hash) ? inner["name"] : inner.to_s
    if inner_name == "String"
      pass "MAP-E2: map_get resolved_type = {name:'Option', params:[{name:'String',...}]}"
    else
      fail! "MAP-E2: map_get resolved_type structure unexpected: #{rt.inspect[0..200]}"
    end
  else
    fail! "MAP-E2: map_get resolved_type structure unexpected: #{rt.inspect[0..200]}"
  end
else
  fail! "MAP-E2: val_node not found"
end

# MAP-E3: map_has_key resolved_type = Bool
pres_node = cn.find { |n| n["name"] == "present" }
if pres_node
  rt = node_type(pres_node)
  if rt && rt["name"] == "Bool"
    pass "MAP-E3: map_has_key SIR resolved_type = Bool"
  else
    fail! "MAP-E3: map_has_key resolved_type = '#{rt&.dig("name")}', expected Bool"
  end
else
  fail! "MAP-E3: present compute node not found"
end

# MAP-E4: or_else chain resolved_type = String
ct_node = cn.find { |n| n["name"] == "ct" }
if ct_node
  rt = node_type(ct_node)
  if rt && rt["name"] == "String"
    pass "MAP-E4: or_else resolved_type = String in SIR"
  else
    fail! "MAP-E4: or_else resolved_type = '#{rt&.dig("name")}', expected String"
  end
else
  fail! "MAP-E4: ct compute node not found"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== MAP-F: Regression — existing inference unaffected ===\n"
# ============================================================

SRC_REG_ARITH = <<~IGNITER
  module Reg
  pure contract IntArith {
    input n : Integer
    input m : Integer
    compute sum = n + m
    output sum : Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_REG_ARITH, "reg_arith")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP") || (result.include?("OOF-TY0") && result.include?("Unknown"))
  fail! "MAP-F1: regression — integer arithmetic affected (got: #{result[0..300]})"
else
  pass "MAP-F1: regression — integer arithmetic unaffected"
end

SRC_REG_OR_ELSE_PLAIN = <<~IGNITER
  module Reg
  pure contract OrElsePlain {
    input items : Collection[String]
    input fallback : String
    compute first  = find(items, |x| x)
    compute result = or_else(first, fallback)
    output result : String
  }
IGNITER

result, app_path, tmp = compile_src(SRC_REG_OR_ELSE_PLAIN, "reg_or_else_plain")
if result.include?("OOF-TY0")
  fail! "MAP-F2: regression — or_else on Collection find affected (got: #{result[0..400]})"
else
  pass "MAP-F2: regression — or_else(find(...), fallback) → String still works"
end
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "OrElsePlain")
res_node = cn.find { |n| n["name"] == "result" }
if res_node
  rt = node_type(res_node)
  if rt && rt["name"] == "String"
    pass "MAP-F2b: or_else on find chain → String (V from Option[String])"
  else
    fail! "MAP-F2b: or_else on find → '#{rt&.dig("name")}', expected String"
  end
end
FileUtils.rm_rf(tmp)

SRC_REG_FIND = <<~IGNITER
  module Reg
  pure contract FindTest {
    input items : Collection[Integer]
    compute found = find(items, |x| x)
    output found : Option[Integer]
  }
IGNITER

result, app_path, tmp = compile_src(SRC_REG_FIND, "reg_find")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  fail! "MAP-F3: regression — find type inference affected (got: #{result[0..300]})"
else
  pass "MAP-F3: regression — find(Collection[Integer]) → Option[Integer] unaffected"
end

SRC_REG_NO_MAP = <<~IGNITER
  module Reg
  pure contract NoMap {
    input name : String
    input age  : Integer
    compute greeting = concat(name, " is here")
    output greeting  : String
    output age       : Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_REG_NO_MAP, "reg_no_map")
FileUtils.rm_rf(tmp)
if result.include?("OOF-MAP")
  fail! "MAP-F4: regression — OOF-MAP fired on Map-free contract"
else
  pass "MAP-F4: regression — no OOF-MAP fires on Map-free contract"
end

# ============================================================
puts "\n=== Summary ===\n"
# ============================================================
total = $pass_count + $fail_count
puts "\nResults: #{$pass_count}/#{total} PASS"
if $fail_count > 0
  puts "[!] #{$fail_count} FAIL(s)"
  exit(1)
else
  puts "[+] ALL PASS"
end
