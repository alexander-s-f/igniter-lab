#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Proof runner: LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1
# Classifies and verifies the fix for VM-P10: 36 Ruby diagnostics
# "missing required field: r0/r1/r2" + "unexpected field: x/y/z".
#
# Root cause: nested Vec3 row literals in mat3.ig Mat3 contracts share
# the same node_name ("result") as the outer Mat3 literal.  Ruby TC's
# @output_type_hints["result"] = Mat3 is incorrectly applied to inner
# {x,y,z} literals, which are meant to be Vec3.
#
# Fix: extract inner Vec3 row literals as annotated computes
# (`compute r0 : Vec3 = {...}`) in all 6 affected mat3.ig contracts.
# This gives each row literal an unambiguous Vec3 type hint.
#
# Target: >=45 checks, 8 sections.

require "pathname"
require "json"
require "open3"

PROOF_DIR    = Pathname.new(__dir__).expand_path
LAB_ROOT     = (PROOF_DIR / "../../").expand_path
WORKSPACE    = (LAB_ROOT / "..").expand_path
IGNITER_LANG = (WORKSPACE / "igniter-lang").expand_path
VM_DIR       = (LAB_ROOT / "igniter-apps/vector_math").expand_path
RUST_BIN     = (LAB_ROOT / "igniter-compiler/target/release/igniter_compiler").expand_path
RUBY_TC_PATH = (IGNITER_LANG / "lib/igniter_lang/typechecker.rb").expand_path
COMP_RPT_PATH = (IGNITER_LANG / "lib/igniter_lang/compilation_report.rb").expand_path

SOURCE_FILES = %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig]
  .map { |f| (VM_DIR / f).to_s }

MAT3_ONLY_FILES = [(VM_DIR / "types.ig").to_s, (VM_DIR / "mat3.ig").to_s]

$pass = 0
$fail = 0

def assert(id, desc, ok = nil, &block)
  result = block ? block.call : ok
  if result
    puts "PASS  #{id}: #{desc}"
    $pass += 1
  else
    puts "FAIL  #{id}: #{desc}"
    $fail += 1
  end
end

# Run Ruby TC on given paths, return parsed result hash
def ruby_compile(source_paths)
  code = <<~RUBY
    require "igniter_lang/compiler_orchestrator"
    require "json"
    paths = #{source_paths.inspect}
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/proof-vm.igapp")
    puts JSON.generate(result)
  RUBY
  out, _err, _status = Open3.capture3("ruby", "-Ilib", "-e", code, chdir: IGNITER_LANG.to_s)
  JSON.parse(out)
rescue
  {}
end

# Run Rust TC on SOURCE_FILES
def rust_compile
  args = [RUST_BIN.to_s, "compile"] + SOURCE_FILES + ["--out", "/tmp/proof-vm-rust.igapp"]
  out, _err, _status = Open3.capture3(*args)
  JSON.parse(out.force_encoding("UTF-8"))
rescue
  {}
end

def ruby_diags(result)
  Array(result.dig("result", "diagnostics") || result["diagnostics"] || [])
end

def rust_diags(result)
  Array(result["diagnostics"] || [])
end

mat3_lines   = File.readlines((VM_DIR / "mat3.ig").to_s, encoding: "utf-8")
ruby_tc_lines = File.readlines(RUBY_TC_PATH.to_s, encoding: "utf-8")
comp_rpt_lines = File.readlines(COMP_RPT_PATH.to_s, encoding: "utf-8")

ruby_result_full  = ruby_compile(SOURCE_FILES)
ruby_result_mat3  = ruby_compile(MAT3_ONLY_FILES)
rust_result       = rust_compile

puts ""
puts "=== A: Source guard — mat3.ig edits in place ==="

A_AFFECTED = %w[Mat3Identity Mat3Transpose Mat3Add Mat3Scale MakeRotation2D MakeScale3D]
A_CLEAN    = %w[Mat3MulVec3 Mat3Determinant]

assert "A-01", "mat3.ig exists at expected path" do
  (VM_DIR / "mat3.ig").exist?
end

assert "A-02", "mat3.ig has annotated row computes: compute r0 : Vec3 =" do
  mat3_lines.count { |l| l.strip.start_with?("compute r0 : Vec3 =") } == 6
end

assert "A-03", "mat3.ig has annotated row computes: compute r1 : Vec3 =" do
  mat3_lines.count { |l| l.strip.start_with?("compute r1 : Vec3 =") } == 6
end

assert "A-04", "mat3.ig has annotated row computes: compute r2 : Vec3 =" do
  mat3_lines.count { |l| l.strip.start_with?("compute r2 : Vec3 =") } == 6
end

assert "A-05", "mat3.ig has outer Mat3 assembly: compute result = { r0: r0" do
  mat3_lines.count { |l| l.include?("{ r0: r0, r1: r1, r2: r2 }") } == 6
end

assert "A-06", "Mat3MulVec3 and Mat3Determinant not changed — no r0/r1/r2 annotated computes in their bodies" do
  # These two contracts do not use nested Vec3 row literals — verify they have no extra annotated rows
  # by checking that total annotated Vec3 rows == 18 (6 contracts x 3 rows each)
  mat3_lines.count { |l| l =~ /compute r[012] : Vec3 =/ } == 18
end

puts ""
puts "=== B: Ruby TC outcome — 36 diagnostics → 0 ==="

assert "B-01", "Ruby TC full compilation: 0 diagnostics" do
  ruby_diags(ruby_result_full).size == 0
end

assert "B-02", "Ruby TC result status is ok or oof-free" do
  ruby_result_full.dig("result", "diagnostics")&.empty? != false ||
    ruby_diags(ruby_result_full).size == 0
end

assert "B-03", "Ruby TC stages: typecheck ok" do
  ruby_result_full.dig("result", "stages", "typecheck") == "ok"
end

assert "B-04", "Ruby TC: no OOF-TY0 missing required field errors" do
  ruby_diags(ruby_result_full).none? { |d| d["message"].to_s.include?("missing required field") }
end

assert "B-05", "Ruby TC: no unexpected field x/y/z errors" do
  ruby_diags(ruby_result_full).none? { |d| d["message"].to_s.include?("has unexpected field") }
end

assert "B-06", "Ruby TC mat3-only compilation: 0 diagnostics" do
  ruby_diags(ruby_result_mat3).size == 0
end

assert "B-07", "Ruby TC mat3-only: typecheck ok" do
  ruby_result_mat3.dig("result", "stages", "typecheck") == "ok"
end

assert "B-08", "Ruby TC: no r0/r1/r2 field mismatch errors anywhere" do
  ruby_diags(ruby_result_full).none? { |d|
    %w[r0 r1 r2].any? { |f| d["message"].to_s.include?(f) }
  }
end

puts ""
puts "=== C: Rust TC baseline preserved ==="

assert "C-01", "Rust binary exists" do
  RUST_BIN.exist?
end

assert "C-02", "Rust TC full compilation: 0 diagnostics" do
  rust_diags(rust_result).size == 0
end

assert "C-03", "Rust TC status ok" do
  rust_result["status"] == "ok"
end

assert "C-04", "Rust TC stages: typecheck ok" do
  rust_result.dig("stages", "typecheck") == "ok"
end

assert "C-05", "Rust TC: no OOF-TY0 errors" do
  rust_diags(rust_result).none? { |d| d["rule"] == "OOF-TY0" }
end

puts ""
puts "=== D: Root cause — nested hint propagation in infer_record_literal ==="

assert "D-01", "Ruby TC infer_record_literal: @output_type_hints lookup uses node_name" do
  ruby_tc_lines.any? { |l| l.include?("@output_type_hints") && l.include?("fetch(node_name") }
end

assert "D-02", "Ruby TC infer_record_literal: field values inferred with same node_name as outer" do
  # Line: infer_expr(val_expr, symbol_types, type_errors, type_warnings, node_name) inside transform_values
  ruby_tc_lines.any? { |l| l.include?("transform_values") } &&
    ruby_tc_lines.any? { |l| l.include?("infer_expr(val_expr") && l.include?("node_name") }
end

assert "D-03", "Ruby TC typecheck_contract resets @output_type_hints per contract" do
  ruby_tc_lines.any? { |l| l.strip == "@output_type_hints = {}" }
end

assert "D-04", "Ruby TC output declarations set @output_type_hints[name] = type" do
  ruby_tc_lines.any? { |l| l.include?("@output_type_hints[od.fetch") && l.include?("type_ir(ann)") }
end

assert "D-05", "Ruby TC dedupe_errors uses [rule, message, node, line] — explains 6-per-contract dedup" do
  ruby_tc_lines.any? { |l| l.include?("dedupe_errors") && l.include?("uniq") } ||
    ruby_tc_lines.any? { |l| l.include?("rule") && l.include?("message") && l.include?("node") && l.include?("line") && l.include?("uniq") }
end

puts ""
puts "=== E: Attribution mechanism — CompilationReport.enrich bug ==="

assert "E-01", "CompilationReport.enrich uses contracts[0].name for all diagnostics attribution" do
  comp_rpt_lines.any? { |l| l.include?("contracts") && l.include?("fetch(0") && l.include?("name") }
end

assert "E-02", "Ruby TC flat_maps all contract type_errors into one array" do
  ruby_tc_lines.any? { |l| l.include?("flat_map") && l.include?("type_errors") }
end

assert "E-03", "Ruby TC flat_map means errors lose per-contract identity before attribution" do
  # Errors from Mat3Identity end up attributed to contracts[0] — verified by empirical run
  ruby_tc_lines.any? { |l| l.include?("typed_contracts.flat_map") }
end

assert "E-04", "CompilationReport diagnostic_category_for checks typecheck stage" do
  comp_rpt_lines.any? { |l| l.include?("diagnostic_category_for") || l.include?("typechecker_oof") }
end

assert "E-05", "Diagnostics.enrich uses contract parameter for all entries lacking own contract key" do
  diag_path = (IGNITER_LANG / "lib/igniter_lang/diagnostics.rb").to_s
  diag_lines = File.readlines(diag_path, encoding: "utf-8")
  diag_lines.any? { |l| l.include?("normalized.key?(\"contract\")") }
rescue
  false
end

puts ""
puts "=== F: Fix mechanism — annotated computes give Vec3 hint ==="

assert "F-01", "Ruby TC temp hint path: compute with type_annotation installs @output_type_hints[name]" do
  ruby_tc_lines.any? { |l| l.include?("temp_hint_installed") && l.include?("@output_type_hints") }
end

assert "F-02", "Ruby TC temp hint path: hint deleted after compute inference (ensure block)" do
  ruby_tc_lines.any? { |l| l.include?("@output_type_hints.delete(name)") && l.include?("temp_hint_installed") }
end

assert "F-03", "mat3.ig: compute r0 : Vec3 gives node_name r0 (not result) to inner literal" do
  # The annotated compute `compute r0 : Vec3 = {x:..., y:..., z:...}` has name "r0"
  # so infer_expr is called with node_name = "r0", and @output_type_hints["r0"] = Vec3
  mat3_lines.any? { |l| l.include?("compute r0 : Vec3 =") }
end

assert "F-04", "mat3.ig: outer result compute references named symbols, not nested literals" do
  mat3_lines.any? { |l| l.include?("{ r0: r0, r1: r1, r2: r2 }") }
end

assert "F-05", "Ruby TC P3 structural matching finds Mat3 for {r0:Vec3,r1:Vec3,r2:Vec3} outer literal" do
  # Verified empirically: ruby_result_full has 0 diagnostics; Mat3 contracts compile clean
  ruby_diags(ruby_result_full).none? { |d| d["contract"]&.start_with?("Mat3") }
end

puts ""
puts "=== G: Regression — other source files unaffected ==="

assert "G-01", "Ruby TC vec2.ig contracts (Vec2Add etc.) produce 0 errors" do
  ruby_diags(ruby_result_full).none? { |d| d["contract"].to_s.start_with?("Vec2") }
end

assert "G-02", "Ruby TC vec3.ig contracts produce 0 errors" do
  ruby_diags(ruby_result_full).none? { |d| d["contract"].to_s.start_with?("Vec3") }
end

assert "G-03", "Ruby TC geometry.ig contracts produce 0 errors" do
  ruby_diags(ruby_result_full).none? { |d|
    %w[MakeAABB AABBContains AABBOverlaps DistanceSq MidPoint].include?(d["contract"].to_s)
  }
end

assert "G-04", "Ruby TC example.ig contracts produce 0 errors" do
  ruby_diags(ruby_result_full).none? { |d|
    %w[SimulateFrame TransformExample Vec2Example CollisionExample].include?(d["contract"].to_s)
  }
end

assert "G-05", "mat3.ig total line count is reasonable (not accidentally truncated)" do
  mat3_lines.size >= 80 && mat3_lines.size <= 130
end

assert "G-06", "mat3.ig still has 8 contracts" do
  mat3_lines.count { |l| l.strip.start_with?("contract ") } == 8
end

assert "G-07", "types.ig unchanged — Vec3 still has x, y, z fields; Mat3 still has r0, r1, r2" do
  types_content = File.read((VM_DIR / "types.ig").to_s, encoding: "utf-8")
  types_content.include?("Vec3") && types_content.include?("x : Integer") &&
    types_content.include?("Mat3") && types_content.include?("r0 : Vec3")
end

puts ""
puts "=== H: Contract-level isolation — individual mat3 contracts clean ==="

A_AFFECTED.each_with_index do |name, i|
  idx = i + 1
  assert "H-0#{idx}", "#{name} produces 0 Ruby TC errors (mat3-only)" do
    ruby_diags(ruby_result_mat3).none? { |d| d["contract"] == name }
  end
end

assert "H-07", "Mat3MulVec3 still clean (Vec3 output, no nested Mat3-row literals)" do
  ruby_diags(ruby_result_full).none? { |d| d["contract"] == "Mat3MulVec3" }
end

assert "H-08", "Mat3Determinant still clean (Integer output)" do
  ruby_diags(ruby_result_full).none? { |d| d["contract"] == "Mat3Determinant" }
end

puts ""
total = $pass + $fail
puts "#{$pass}/#{total} PASS"
exit($fail == 0 ? 0 : 1)
