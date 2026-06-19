#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_rust_decimal_input_scale_p1.rb
# LAB-RUST-DECIMAL-INPUT-SCALE-P1
#
# Rust lab proof for Decimal[N] input-annotation scale extraction in numeric
# operator typing. This verifies the bug routed by LANG-RUBY-NUMERIC-OPS-PARITY-P1:
# input Decimal[2] values must not be read as scale 0 in Rust operator_type.

require "json"
require "open3"
require "tmpdir"
require "pathname"

SCRIPT_DIR = Pathname.new(__FILE__).realpath.dirname
LAB_ROOT = SCRIPT_DIR.parent
COMPILER_DIR = SCRIPT_DIR
COMPILER_BIN = COMPILER_DIR / "target" / "release" / "igniter_compiler"
TYPECHECKER_RS = COMPILER_DIR / "src" / "typechecker.rs"
STDLIB_CALLS_RS = COMPILER_DIR / "src" / "typechecker" / "stdlib_calls.rs"
CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-RUST-DECIMAL-INPUT-SCALE-P1.md"
DOC = LAB_ROOT / "lab-docs" / "lang" / "lab-rust-decimal-input-scale-p1-v0.md"
RUBY_NUMERIC_CARD = LAB_ROOT.parent / "igniter-lang" / ".agents" / "work" / "cards" / "lang" / "LANG-RUBY-NUMERIC-OPS-PARITY-P1.md"
RUBY_NUMERIC_PROOF = LAB_ROOT.parent / "igniter-lang" / ".agents" / "work" / "proposals" / "LANG-RUBY-NUMERIC-OPS-PARITY-P1-proof-v0.md"

CHECKS = []

def check(label)
  pass = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  CHECKS << { label: label, pass: pass, detail: detail }
  puts "#{pass ? 'PASS' : 'FAIL'} #{label}"
  puts "     #{detail}" if detail && !pass
end

def section(name)
  puts "\n[#{name}]"
end

def read(path)
  path.read(encoding: "utf-8")
end

def ensure_compiler!
  return if COMPILER_BIN.exist?

  stdout, stderr, status = Open3.capture3("cargo", "build", "--release", chdir: COMPILER_DIR.to_s)
  return if status.success?

  warn stdout
  warn stderr
  abort "cargo build --release failed"
end

def compile_source(label, source)
  Dir.mktmpdir("dec_scale_#{label}_") do |dir|
    src_path = File.join(dir, "#{label}.ig")
    out_path = File.join(dir, "out")
    File.write(src_path, source.strip + "\n")

    stdout, stderr, status = Open3.capture3(COMPILER_BIN.to_s, "compile", src_path, "--out", out_path)
    json = JSON.parse(stdout) rescue {}
    sir_path = File.join(out_path, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "utf-8")) : nil

    {
      label: label,
      stdout: stdout,
      stderr: stderr,
      process_success: status.success?,
      json: json,
      sir: sir,
      out_path: out_path
    }
  end
end

def diagnostics(result)
  Array(result.dig(:json, "diagnostics"))
end

def codes(result)
  diagnostics(result).map { |d| d["rule"] }.compact
end

def status(result)
  result.dig(:json, "status")
end

def stages(result)
  result.dig(:json, "stages") || {}
end

def compute_nodes(result, contract_name = nil)
  contracts = Array(result.dig(:sir, "contracts"))
  contracts = contracts.select { |c| [c["contract_name"], c["name"]].include?(contract_name) } if contract_name
  contracts.flat_map { |c| Array(c["nodes"]) }.select { |n| n["kind"] == "compute" }
end

def compute_type(result, name)
  node = compute_nodes(result).find { |n| n["name"] == name }
  node && node["type"]
end

def type_name(type_info)
  type_info && type_info["name"]
end

def decimal_scale(type_info)
  params = Array(type_info && type_info["params"])
  first = params.first
  first.is_a?(Hash) ? first["name"] : first
end

def decimal_type?(type_info, scale)
  type_name(type_info) == "Decimal" && decimal_scale(type_info).to_s == scale.to_s
end

def sir_text(result)
  JSON.generate(result[:sir] || {})
end

ensure_compiler!

TYPECHECKER_SRC = read(TYPECHECKER_RS)
STDLIB_CALLS_SRC = read(STDLIB_CALLS_RS)
CARD_SRC = read(CARD)
DOC_SRC = DOC.exist? ? read(DOC) : ""
RUBY_CARD_SRC = read(RUBY_NUMERIC_CARD)
RUBY_PROOF_SRC = read(RUBY_NUMERIC_PROOF)

INPUT_MUL_2_2 = <<~IG
  module DecimalScaleInputMul
  pure contract MulInputs {
    input a : Decimal[2]
    input b : Decimal[2]
    compute c = a * b
    output c : Decimal[4]
  }
IG

INPUT_MUL_2_4 = <<~IG
  module DecimalScaleInputMul
  pure contract MulInputsWide {
    input a : Decimal[2]
    input b : Decimal[4]
    compute c = a * b
    output c : Decimal[6]
  }
IG

INPUT_ADD_2_2 = <<~IG
  module DecimalScaleInputAdd
  pure contract AddInputs {
    input a : Decimal[2]
    input b : Decimal[2]
    compute c = a + b
    output c : Decimal[2]
  }
IG

INPUT_SUB_4_4 = <<~IG
  module DecimalScaleInputSub
  pure contract SubInputs {
    input a : Decimal[4]
    input b : Decimal[4]
    compute c = a - b
    output c : Decimal[4]
  }
IG

INPUT_DIV_2_2 = <<~IG
  module DecimalScaleInputDiv
  pure contract DivInputs {
    input a : Decimal[2]
    input b : Decimal[2]
    compute c = a / b
    output c : Decimal[2]
  }
IG

INPUT_ADD_MISMATCH = <<~IG
  module DecimalScaleInputMismatch
  pure contract AddMismatch {
    input a : Decimal[2]
    input b : Decimal[4]
    compute c = a + b
    output c : Decimal[2]
  }
IG

INPUT_SUB_MISMATCH = <<~IG
  module DecimalScaleInputMismatch
  pure contract SubMismatch {
    input a : Decimal[4]
    input b : Decimal[2]
    compute c = a - b
    output c : Decimal[4]
  }
IG

CONSTRUCT_MUL_2_2 = <<~IG
  module DecimalScaleConstructMul
  pure contract MulConstruct {
    compute a = decimal(150, 2)
    compute b = decimal(200, 2)
    compute c = a * b
    output c : Decimal[4]
  }
IG

CONSTRUCT_ADD_2_2 = <<~IG
  module DecimalScaleConstructAdd
  pure contract AddConstruct {
    compute a = decimal(150, 2)
    compute b = decimal(200, 2)
    compute c = a + b
    output c : Decimal[2]
  }
IG

CONSTRUCT_ADD_MISMATCH = <<~IG
  module DecimalScaleConstructMismatch
  pure contract AddConstructMismatch {
    compute a = decimal(150, 2)
    compute b = decimal(200, 4)
    compute c = a + b
    output c : Decimal[2]
  }
IG

CONSTRUCT_NON_LITERAL_SCALE = <<~IG
  module DecimalScaleConstructBad
  pure contract BadScale {
    input s : Integer
    compute a = decimal(150, s)
    output a : Decimal[2]
  }
IG

MIXED_INPUT_CONSTRUCT_MUL = <<~IG
  module DecimalScaleMixed
  pure contract MixedMul {
    input a : Decimal[2]
    compute b = decimal(200, 2)
    compute c = a * b
    output c : Decimal[4]
  }
IG

STDLIB_MUL_INPUTS = <<~IG
  module DecimalScaleStdlibMul
  pure contract StdlibMulInputs {
    input a : Decimal[2]
    input b : Decimal[2]
    compute c = mul(a, b)
    output c : Decimal[4]
  }
IG

STDLIB_MUL_CONSTRUCTS = <<~IG
  module DecimalScaleStdlibMul
  pure contract StdlibMulConstructs {
    compute a = decimal(1, 2)
    compute b = decimal(1, 4)
    compute c = mul(a, b)
    output c : Decimal[6]
  }
IG

IMPLICIT_FLOAT_TO_DECIMAL = <<~IG
  module DecimalScaleBoundary
  pure contract FloatBoundary {
    compute a = 0.00
    output a : Decimal[2]
  }
IG

MISSING_DECIMAL_SCALE = <<~IG
  module DecimalScaleSyntax
  pure contract MissingScale {
    input a : Decimal
    output a : Decimal[2]
  }
IG

results = {
  input_mul_2_2: compile_source("input_mul_2_2", INPUT_MUL_2_2),
  input_mul_2_4: compile_source("input_mul_2_4", INPUT_MUL_2_4),
  input_add_2_2: compile_source("input_add_2_2", INPUT_ADD_2_2),
  input_sub_4_4: compile_source("input_sub_4_4", INPUT_SUB_4_4),
  input_div_2_2: compile_source("input_div_2_2", INPUT_DIV_2_2),
  input_add_mismatch: compile_source("input_add_mismatch", INPUT_ADD_MISMATCH),
  input_sub_mismatch: compile_source("input_sub_mismatch", INPUT_SUB_MISMATCH),
  construct_mul_2_2: compile_source("construct_mul_2_2", CONSTRUCT_MUL_2_2),
  construct_add_2_2: compile_source("construct_add_2_2", CONSTRUCT_ADD_2_2),
  construct_add_mismatch: compile_source("construct_add_mismatch", CONSTRUCT_ADD_MISMATCH),
  construct_non_literal_scale: compile_source("construct_non_literal_scale", CONSTRUCT_NON_LITERAL_SCALE),
  mixed_input_construct_mul: compile_source("mixed_input_construct_mul", MIXED_INPUT_CONSTRUCT_MUL),
  stdlib_mul_inputs: compile_source("stdlib_mul_inputs", STDLIB_MUL_INPUTS),
  stdlib_mul_constructs: compile_source("stdlib_mul_constructs", STDLIB_MUL_CONSTRUCTS),
  implicit_float_to_decimal: compile_source("implicit_float_to_decimal", IMPLICIT_FLOAT_TO_DECIMAL),
  missing_decimal_scale: compile_source("missing_decimal_scale", MISSING_DECIMAL_SCALE)
}

section("A-source-and-implementation-guards")
check("A-01 card exists") { CARD.file? }
check("A-02 card route is Rust Decimal input scale") { CARD_SRC.include?("Rust typechecker") && CARD_SRC.include?("Decimal input scale") }
check("A-03 Ruby numeric card documents the routed Rust bug") { RUBY_CARD_SRC.include?("Rust mis-extracts the scale") }
check("A-04 Ruby proof packet documents input annotation divergence") { RUBY_PROOF_SRC.include?("input annotation") && RUBY_PROOF_SRC.include?("Decimal[0]") }
check("A-05 typechecker has decimal_scale helper") { TYPECHECKER_SRC.include?("fn decimal_scale(&self, type_info: &serde_json::Value) -> String") }
check("A-06 decimal_scale normalizes through get_param") { TYPECHECKER_SRC.include?("self.get_param(type_info, 0)") }
check("A-07 decimal_scale reads normalized type_name") { TYPECHECKER_SRC.include?("self.type_name(&param)") }
check("A-08 decimal_scale preserves fail-soft bare Decimal fallback") { TYPECHECKER_SRC.include?("unwrap_or_else(|| \"0\".to_string())") }
check("A-09 operator_type reads left Decimal scale through helper") { TYPECHECKER_SRC.include?("let left_scale = self.decimal_scale(left);") }
check("A-10 operator_type reads right Decimal scale through helper") { TYPECHECKER_SRC.include?("let right_scale = self.decimal_scale(right);") }
check("A-11 stdlib mul arm reads left Decimal scale through helper") { STDLIB_CALLS_SRC.include?("let left_scale_val = self.decimal_scale(left);") }
check("A-12 stdlib mul arm reads right Decimal scale through helper") { STDLIB_CALLS_SRC.include?("let right_scale_val = self.decimal_scale(right);") }

section("B-input-annotation-reproduction-closure")
r = results[:input_mul_2_2]
check("B-01 input Decimal[2] * Decimal[2] compiles ok") { status(r) == "ok" }
check("B-02 input mul process exits successfully") { r[:process_success] }
check("B-03 input mul emits no diagnostics") { diagnostics(r).empty? }
check("B-04 input mul parse stage ok") { stages(r)["parse"] == "ok" }
check("B-05 input mul typecheck stage ok") { stages(r)["typecheck"] == "ok" }
check("B-06 input mul emit stage ok") { stages(r)["emit"] == "ok" }
check("B-07 input mul assemble stage ok") { stages(r)["assemble"] == "ok" }
check("B-08 input mul includes MulInputs contract") { Array(r.dig(:json, "contracts")).include?("MulInputs") }
check("B-09 input mul SIR exists") { r[:sir].is_a?(Hash) }
check("B-10 input mul compute c is Decimal[4]") { decimal_type?(compute_type(r, "c"), 4) }
check("B-11 input mul SIR no longer contains Decimal[0]") { !sir_text(r).include?('"name":"0"') }
check("B-12 input mul grammar remains decimal-v0") { r.dig(:json, "grammar_version") == "decimal-v0" }
check("B-13 input mul has no liveness breaches") { Array(r.dig(:json, "liveness_instrumentation", "breaches")).empty? }
check("B-14 input mul source hash is present") { r.dig(:json, "source_hash").to_s.start_with?("sha256:") }

section("C-input-annotation-decimal-arithmetic-matrix")
check("C-01 Decimal[2] * Decimal[4] compiles ok") { status(results[:input_mul_2_4]) == "ok" }
check("C-02 Decimal[2] * Decimal[4] resolves to Decimal[6]") { decimal_type?(compute_type(results[:input_mul_2_4], "c"), 6) }
check("C-03 Decimal[2] * Decimal[4] has no diagnostics") { diagnostics(results[:input_mul_2_4]).empty? }
check("C-04 Decimal[2] + Decimal[2] compiles ok") { status(results[:input_add_2_2]) == "ok" }
check("C-05 Decimal[2] + Decimal[2] resolves to Decimal[2]") { decimal_type?(compute_type(results[:input_add_2_2], "c"), 2) }
check("C-06 Decimal[2] + Decimal[2] has no diagnostics") { diagnostics(results[:input_add_2_2]).empty? }
check("C-07 Decimal[4] - Decimal[4] compiles ok") { status(results[:input_sub_4_4]) == "ok" }
check("C-08 Decimal[4] - Decimal[4] resolves to Decimal[4]") { decimal_type?(compute_type(results[:input_sub_4_4], "c"), 4) }
check("C-09 Decimal[4] - Decimal[4] has no diagnostics") { diagnostics(results[:input_sub_4_4]).empty? }
check("C-10 Decimal[2] / Decimal[2] compiles ok") { status(results[:input_div_2_2]) == "ok" }
check("C-11 Decimal[2] / Decimal[2] keeps left scale Decimal[2]") { decimal_type?(compute_type(results[:input_div_2_2], "c"), 2) }
check("C-12 Decimal[2] / Decimal[2] has no diagnostics") { diagnostics(results[:input_div_2_2]).empty? }

section("D-scale-mismatch-remains-rejected")
r = results[:input_add_mismatch]
check("D-01 Decimal[2] + Decimal[4] is rejected") { status(r) == "oof" }
check("D-02 add mismatch emits OOF-TC5") { codes(r).include?("OOF-TC5") }
check("D-03 add mismatch reports left_scale=2") { diagnostics(r).any? { |d| d["message"].to_s.include?("left_scale=2") } }
check("D-04 add mismatch reports right_scale=4") { diagnostics(r).any? { |d| d["message"].to_s.include?("right_scale=4") } }
check("D-05 add mismatch does not emit an igapp") { r.dig(:json, "igapp_path").nil? }
check("D-06 add mismatch no longer misses the scale mismatch") { !diagnostics(r).empty? && !sir_text(r).include?('"contracts"') }
r = results[:input_sub_mismatch]
check("D-07 Decimal[4] - Decimal[2] is rejected") { status(r) == "oof" }
check("D-08 sub mismatch emits OOF-TC5") { codes(r).include?("OOF-TC5") }
check("D-09 sub mismatch reports left_scale=4") { diagnostics(r).any? { |d| d["message"].to_s.include?("left_scale=4") } }
check("D-10 sub mismatch reports right_scale=2") { diagnostics(r).any? { |d| d["message"].to_s.include?("right_scale=2") } }
check("D-11 sub mismatch has no emitted SIR") { r[:sir].nil? }
check("D-12 mismatch diagnostics are still node-local to c") { diagnostics(results[:input_add_mismatch]).all? { |d| d["node"] == "c" } && diagnostics(results[:input_sub_mismatch]).all? { |d| d["node"] == "c" } }

section("E-constructor-created-decimal-regressions")
check("E-01 decimal(150,2) * decimal(200,2) compiles ok") { status(results[:construct_mul_2_2]) == "ok" }
check("E-02 constructor multiplication resolves to Decimal[4]") { decimal_type?(compute_type(results[:construct_mul_2_2], "c"), 4) }
check("E-03 constructor multiplication has no diagnostics") { diagnostics(results[:construct_mul_2_2]).empty? }
check("E-04 decimal(150,2) + decimal(200,2) compiles ok") { status(results[:construct_add_2_2]) == "ok" }
check("E-05 constructor addition resolves to Decimal[2]") { decimal_type?(compute_type(results[:construct_add_2_2], "c"), 2) }
check("E-06 constructor addition has no diagnostics") { diagnostics(results[:construct_add_2_2]).empty? }
check("E-07 constructor scale mismatch is rejected") { status(results[:construct_add_mismatch]) == "oof" }
check("E-08 constructor scale mismatch emits OOF-TC5") { codes(results[:construct_add_mismatch]).include?("OOF-TC5") }
check("E-09 constructor non-literal scale still emits OOF-DM4") { codes(results[:construct_non_literal_scale]).include?("OOF-DM4") }
check("E-10 constructor invalid scale does not become implicit coercion") { status(results[:construct_non_literal_scale]) == "oof" }

section("F-mixed-and-stdlib-mul-paths")
check("F-01 input Decimal[2] * constructor Decimal[2] compiles ok") { status(results[:mixed_input_construct_mul]) == "ok" }
check("F-02 mixed input/constructor multiplication resolves to Decimal[4]") { decimal_type?(compute_type(results[:mixed_input_construct_mul], "c"), 4) }
check("F-03 mixed input/constructor multiplication has no diagnostics") { diagnostics(results[:mixed_input_construct_mul]).empty? }
check("F-04 mul(input Decimal[2], input Decimal[2]) compiles ok") { status(results[:stdlib_mul_inputs]) == "ok" }
check("F-05 stdlib mul input annotations resolve to Decimal[4]") { decimal_type?(compute_type(results[:stdlib_mul_inputs], "c"), 4) }
check("F-06 stdlib mul input annotations have no Decimal[0]") { !sir_text(results[:stdlib_mul_inputs]).include?('"name":"0"') }
check("F-07 mul(constructor Decimal[2], constructor Decimal[4]) compiles ok") { status(results[:stdlib_mul_constructs]) == "ok" }
check("F-08 stdlib mul constructor path resolves to Decimal[6]") { decimal_type?(compute_type(results[:stdlib_mul_constructs], "c"), 6) }

section("G-closed-surfaces-and-boundaries")
check("G-01 implicit Float -> Decimal remains rejected") { status(results[:implicit_float_to_decimal]) == "oof" }
check("G-02 implicit Float -> Decimal still emits OOF-TY1") { codes(results[:implicit_float_to_decimal]).include?("OOF-TY1") }
check("G-03 Decimal without scale remains rejected") { status(results[:missing_decimal_scale]) != "ok" }
check("G-04 Decimal without scale still emits OOF-DM3") { codes(results[:missing_decimal_scale]).include?("OOF-DM3") }
check("G-05 card keeps Ruby closed") { CARD_SRC.include?("No Ruby changes") }
check("G-06 card keeps VM closed") { CARD_SRC.include?("No VM changes") }
check("G-07 card keeps app migrations closed") { CARD_SRC.include?("No app migrations") }
check("G-08 lab doc exists") { DOC.file? }
check("G-09 lab doc records no Ruby/VM/app authority") { DOC_SRC.include?("No Ruby") && DOC_SRC.include?("No VM") && DOC_SRC.include?("No app") }
check("G-10 lab doc records 60+ proof target closure") { DOC_SRC.include?("RESULT: 78/78 PASS") || DOC_SRC.include?("78/78") }

passes = CHECKS.count { |c| c[:pass] }
fails = CHECKS.length - passes
puts "\nRESULT: #{passes}/#{CHECKS.length} PASS"

if fails.positive?
  puts "\nFailures:"
  CHECKS.reject { |c| c[:pass] }.each do |c|
    puts "- #{c[:label]}#{c[:detail] ? " (#{c[:detail]})" : ""}"
  end
  exit 1
end
