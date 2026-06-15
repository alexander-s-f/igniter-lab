#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vm_evalast_eval_expr_p1.rb
# LAB-VM-EVALAST-EVAL-EXPR-P1
#
# Spike proof for the spreadsheet eval_expr runtime tail. It proves that the
# live VM failure is not an eval_ast node-kind gap: eval_expr is an app-local
# `def` function call inside a map lambda, but the current .igapp does not
# materialize function bodies in SemanticIR. Under this card's VM-only authority,
# the correct result is a sharper routed blocker, not a hardcoded VM fix.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
VM_MANIFEST = LAB_ROOT / "igniter-vm" / "Cargo.toml"
VM_BIN = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"
VM_RS = LAB_ROOT / "igniter-vm" / "src" / "vm.rs"
VM_COMPILER_RS = LAB_ROOT / "igniter-vm" / "src" / "compiler.rs"
EMITTER_RS = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"
PARSER_RS = LAB_ROOT / "igniter-compiler" / "src" / "parser.rs"
TYPECHECKER_RS = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
COMPILER_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
COMPILER_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
APPS_ROOT = LAB_ROOT / "igniter-apps"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-EVALAST-EVAL-EXPR-P1.md"
APP_DEMO_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-APP-DEMO-ENTRY-WAVE-P1.md"
COVERAGE_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-EVALAST-COVERAGE-P1.md"
RECHECK_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-VM-RUN-OK-RECHECK-P1.md"
FOLLOWUP_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-FUNCTION-SIR-RUNTIME-P1.md"
DOC = LAB_ROOT / "lab-docs" / "lang" / "lab-vm-evalast-eval-expr-p1-v0.md"
SURFACE = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"
SPREADSHEET_REGISTRY = APPS_ROOT / "spreadsheet" / "PRESSURE_REGISTRY.md"

SPREADSHEET_FILES = %w[api.ig engine.ig example.ig types.ig].freeze
SMOKE_APPS = {
  "batch_importer" => "RunImport",
  "igniter_parser" => "RunParseDemo",
  "lead_router" => "RunAccept",
  "call_router" => "RunConnectedMatched",
  "vector_editor" => "RunCanvasClickDemo"
}.freeze

$pass = 0
$fail = 0

def check(label)
  ok = yield
  if ok
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n=== #{title} ==="
end

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def parse_json(text)
  JSON.parse(text.to_s.force_encoding("UTF-8"))
rescue JSON::ParserError
  { "_parse_error" => text.to_s.force_encoding("UTF-8") }
end

def compiler_bin
  return COMPILER_RELEASE if File.executable?(COMPILER_RELEASE.to_s)

  COMPILER_DEBUG
end

def build_vm
  stdout, stderr, status = Open3.capture3("cargo", "build", "--manifest-path", VM_MANIFEST.to_s)
  { stdout: stdout, stderr: stderr, exit: status.exitstatus, success: status.success? }
end

def app_dir(name)
  APPS_ROOT / name
end

def app_sources(name, files = nil)
  if files
    files.map { |file| app_dir(name) / file }
  else
    Dir.glob((app_dir(name) / "*.ig").to_s).sort.map { |path| Pathname.new(path) }
  end
end

def compile_sources(sources, out_dir)
  stdout, stderr, status = Open3.capture3(
    compiler_bin.to_s,
    "compile",
    *sources.map(&:to_s),
    "--out",
    out_dir.to_s
  )
  sir_path = File.join(out_dir, "semantic_ir_program.json")
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: parse_json(stdout),
    sir: File.exist?(sir_path) ? parse_json(File.read(sir_path, encoding: "UTF-8")) : {},
    out_dir: out_dir
  }
end

def run_vm(igapp, entry)
  inputs_path = File.join(File.dirname(igapp), "#{entry}_inputs.json")
  File.write(inputs_path, "{}")
  stdout, stderr, status = Open3.capture3(
    VM_BIN.to_s,
    "run",
    "--contract",
    igapp.to_s,
    "--inputs",
    inputs_path,
    "--entry",
    entry,
    "--json"
  )
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: parse_json(stdout)
  }
end

def find_nodes(node, acc = [], &block)
  case node
  when Hash
    acc << node if yield(node)
    node.each_value { |value| find_nodes(value, acc, &block) }
  when Array
    node.each { |value| find_nodes(value, acc, &block) }
  end
  acc
end

def contract(sir, name)
  Array(sir["contracts"]).find { |c| c["contract_name"] == name || c["name"] == name }
end

def protected_diffs
  stdout, _stderr, _status = Open3.capture3("git", "diff", "--name-only")
  stdout.lines.map(&:strip).select do |path|
    (path.start_with?("igniter-apps/") && path.end_with?(".ig")) ||
      path.start_with?("igniter-compiler/src/") ||
      path.start_with?("igniter-vm/src/")
  end
end

TMP = Dir.mktmpdir("lab_vm_evalast_eval_expr_p1_")
at_exit { FileUtils.rm_rf(TMP) }

BUILD = build_vm

spreadsheet_compile = compile_sources(app_sources("spreadsheet", SPREADSHEET_FILES), File.join(TMP, "spreadsheet.igapp"))
spreadsheet_sir = spreadsheet_compile[:sir]
spreadsheet_run = spreadsheet_compile[:success] ? run_vm(spreadsheet_compile[:out_dir], "RunWorkbookDemo") : nil
spreadsheet_sidecar = parse_json(File.read(File.join(spreadsheet_compile[:out_dir], "contracts", "calculate_grid.json"), encoding: "UTF-8"))
spreadsheet_form_trace = parse_json(File.read(File.join(spreadsheet_compile[:out_dir], "form_resolution_trace.json"), encoding: "UTF-8"))

calc_contract = contract(spreadsheet_sir, "CalculateGrid") || {}
eval_expr_calls = find_nodes(calc_contract) do |node|
  (node["kind"] == "call" && node["fn"] == "eval_expr") ||
    (node["kind"] == "apply" && node["operator"] == "eval_expr")
end
map_calls = find_nodes(calc_contract) do |node|
  (node["kind"] == "call" && node["fn"] == "stdlib.collection.map") ||
    (node["kind"] == "apply" && node["operator"] == "stdlib.collection.map")
end
sidecar_eval_expr_calls = find_nodes(spreadsheet_sidecar) { |node| node["kind"] == "call" && node["fn"] == "eval_expr" }
trace_eval_expr = Array(spreadsheet_form_trace["trace"]).select { |row| row["trigger"] == "eval_expr" }

smokes = SMOKE_APPS.to_h do |app, entry|
  out_dir = File.join(TMP, "#{app}.igapp")
  compile = compile_sources(app_sources(app), out_dir)
  run = compile[:success] ? run_vm(out_dir, entry) : nil
  [app, { entry: entry, compile: compile, run: run }]
end

card = read(CARD)
app_demo_card = read(APP_DEMO_CARD)
coverage_card = read(COVERAGE_CARD)
recheck_card = read(RECHECK_CARD)
followup_card = read(FOLLOWUP_CARD)
doc = read(DOC)
surface = read(SURFACE)
portfolio = read(PORTFOLIO)
registry = read(SPREADSHEET_REGISTRY)
vm_rs = read(VM_RS)
vm_compiler_rs = read(VM_COMPILER_RS)
emitter_rs = read(EMITTER_RS)
parser_rs = read(PARSER_RS)
typechecker_rs = read(TYPECHECKER_RS)
spreadsheet_engine = read(app_dir("spreadsheet") / "engine.ig")

puts "LAB-VM-EVALAST-EVAL-EXPR-P1"
puts "spreadsheet_compile=#{spreadsheet_compile[:json]["status"] || spreadsheet_compile[:success]}"
puts "spreadsheet_run_status=#{spreadsheet_run&.dig(:json, "status")}"
puts "spreadsheet_error=#{spreadsheet_run&.dig(:json, "error")}"
puts "functions_count=#{Array(spreadsheet_sir["functions"]).size}"
puts "eval_expr_calls=#{eval_expr_calls.size}"

section("A Gates")
check("A-01 VM build succeeds") { BUILD[:success] }
check("A-02 VM binary exists after build") { File.executable?(VM_BIN.to_s) }
check("A-03 app demo entry wave is closed") { app_demo_card.include?("**Status:** CLOSED") }
check("A-04 eval_ast coverage guard is closed") { coverage_card.include?("**Status:** CLOSED") }
check("A-05 RUN-OK recheck P1 is closed") { recheck_card.include?("**Status:** CLOSED") }
check("A-06 RUN-OK recheck names spreadsheet as runtime-not-ok") { recheck_card.include?("spreadsheet") && recheck_card.include?("RUN-NOT-OK") }
check("A-07 card exists") { CARD.file? }
check("A-08 spreadsheet app directory exists") { app_dir("spreadsheet").directory? }
check("A-09 compiler binary exists") { File.executable?(compiler_bin.to_s) }
check("A-10 VM-only authority is declared") { card.include?("VM runtime support only") || card.include?("VM-only") }

section("B Live Spreadsheet Failure")
check("B-01 spreadsheet source declares eval_expr def") { spreadsheet_engine.include?("def eval_expr") }
check("B-02 spreadsheet source declares eval_ref def") { spreadsheet_engine.include?("def eval_ref") }
check("B-03 eval_expr carries decreases fuel") { spreadsheet_engine.include?("def eval_expr") && spreadsheet_engine.include?("decreases fuel") }
check("B-04 CalculateGrid maps over grid.cells") { spreadsheet_engine.include?("map(grid.cells") }
check("B-05 CalculateGrid calls eval_expr inside map lambda") { spreadsheet_engine.include?("cell -> eval_expr(cell.ast, grid)") }
check("B-06 spreadsheet compile succeeds") { spreadsheet_compile[:success] && spreadsheet_compile[:json]["status"] == "ok" }
check("B-07 spreadsheet SIR includes RunWorkbookDemo contract") { contract(spreadsheet_sir, "RunWorkbookDemo") }
check("B-08 spreadsheet SIR includes CalculateGrid contract") { calc_contract.any? }
check("B-09 CalculateGrid SIR contains map call") { map_calls.size == 1 }
check("B-10 CalculateGrid SIR contains exactly one eval_expr call") { eval_expr_calls.size == 1 }
check("B-11 eval_expr call is emitted as call node") { eval_expr_calls.first&.dig("kind") == "call" && eval_expr_calls.first&.dig("fn") == "eval_expr" }
check("B-12 eval_expr call has two args") { Array(eval_expr_calls.first&.dig("args")).size == 2 }
check("B-13 sidecar contract also preserves eval_expr call") { sidecar_eval_expr_calls.size >= 1 }
check("B-14 form trace records eval_expr trigger") { trace_eval_expr.any? }
check("B-15 form trace does not resolve eval_expr to a form") { trace_eval_expr.all? { |row| row["resolved_to"].nil? } }
check("B-16 VM run fails") { spreadsheet_run && !spreadsheet_run[:success] }
check("B-17 VM failure is eval_expr operator") { spreadsheet_run[:json]["error"].to_s.include?("Unsupported operator: eval_expr") }
check("B-18 failure is after compile, not compile-only") { spreadsheet_compile[:success] && spreadsheet_run[:exit] != 0 }

section("C Missing Function Substrate")
check("C-01 semantic_ir_program has no functions key") { !spreadsheet_sir.key?("functions") }
check("C-02 semantic_ir_program functions fallback is empty") { Array(spreadsheet_sir["functions"]).empty? }
check("C-03 source_units only list contracts/types") { Array(spreadsheet_sir["source_units"]).all? { |unit| !unit.key?("functions") } }
check("C-04 source_units include SpreadsheetEngine") { Array(spreadsheet_sir["source_units"]).any? { |unit| unit["module"] == "SpreadsheetEngine" } }
check("C-05 SpreadsheetEngine source unit omits def names") do
  unit = Array(spreadsheet_sir["source_units"]).find { |row| row["module"] == "SpreadsheetEngine" }
  unit && Array(unit["contracts"]) == ["CalculateGrid"] && !unit.to_s.include?("eval_expr")
end
check("C-06 eval_expr is not a contract") { contract(spreadsheet_sir, "eval_expr").nil? && contract(spreadsheet_sir, "EvalExpr").nil? }
check("C-07 eval_ref is not a contract") { contract(spreadsheet_sir, "eval_ref").nil? && contract(spreadsheet_sir, "EvalRef").nil? }
check("C-08 .igapp has no functions sidecar") { Dir.glob(File.join(spreadsheet_compile[:out_dir], "**", "*function*")).empty? }
check("C-09 emitter creates contracts array") { emitter_rs.include?('result.insert("contracts"') }
check("C-10 emitter does not insert functions into SIR") { !emitter_rs.include?('result.insert("functions"') }
check("C-11 parser has FunctionDecl") { parser_rs.include?("pub struct FunctionDecl") && parser_rs.include?("parse_function_decl") }
check("C-12 typechecker receives functions") { typechecker_rs.include?("functions: &[crate::parser::FunctionDecl]") }

section("D VM Boundary")
check("D-01 eval_ast has generic apply/call arm") { vm_rs.include?('"apply" | "call" | "map" | "filter" | "fold" | "reduce"') }
check("D-02 eval_ast recognizes call_contract separately") { vm_rs.include?('"call_contract"') && vm_rs.include?("call_contract_value") }
check("D-03 eval_ast unknown op error is the observed shape") { vm_rs.include?("Unsupported operator: {}") }
check("D-04 VM has no app-local function registry") { !vm_rs.include?("function_registry") }
check("D-05 VM has no eval_expr hardcode") { !vm_rs.include?('"eval_expr"') }
check("D-06 VM does not read .ig source paths for runtime semantics") { !vm_rs.include?("source_units") && !vm_rs.include?("source_path") }
check("D-07 VM compiler fallback OP_CALL is not enough without function body") { vm_compiler_rs.include?("OP_CALL") && vm_compiler_rs.include?("Unsupported binary operator") }
check("D-08 current card did not edit protected source files") { protected_diffs.empty? }
check("D-09 route is not dynamic dispatch") { !spreadsheet_engine.include?("call_contract(expr") && !spreadsheet_engine.include?("call_contract(eval_expr") }
check("D-10 route is not stdlib VM gap") { eval_expr_calls.first&.dig("fn") == "eval_expr" && eval_expr_calls.first&.dig("fn") !~ /^stdlib\./ }
check("D-11 route requires function materialization before runtime") { !spreadsheet_sir.key?("functions") && eval_expr_calls.any? }
check("D-12 VM-only implementation is correctly held") { card.include?("ROUTED") || card.include?("larger semantic surface") }

section("E Regression Runtime Smokes")
SMOKE_APPS.each do |app, entry|
  result = smokes.fetch(app)
  check("E #{app} compile succeeds") { result[:compile][:success] && result[:compile][:json]["status"] == "ok" }
  check("E #{app} run exits success") { result[:run]&.dig(:success) }
  check("E #{app} VM status success") { result[:run]&.dig(:json, "status") == "success" }
  check("E #{app} entrypoint used") { result[:entry] == entry }
end

section("F Artifacts")
check("F-01 proof runner exists") { Pathname.new(__FILE__).file? }
check("F-02 lab doc exists") { DOC.file? }
check("F-03 lab doc records missing function substrate") { doc.include?("does not materialize function bodies") }
check("F-04 lab doc records spreadsheet failure") { doc.include?("Unsupported operator: eval_expr") }
check("F-05 lab doc records no VM source fix") { doc.include?("No VM source change") || doc.include?("no VM source change") }
check("F-06 card is closed routed") { card.include?("**Status:** CLOSED") && card.include?("ROUTED") }
check("F-07 card records RUN-OK unchanged") { card.include?("23/25") }
check("F-08 IMPLEMENTED_SURFACE records reclassification") { surface.include?("function SIR") && surface.include?("LAB-FUNCTION-SIR-RUNTIME-P1") }
check("F-09 spreadsheet registry records routed SS-P08") { registry.include?("SS-P08") && registry.include?("LAB-FUNCTION-SIR-RUNTIME-P1") }
check("F-10 portfolio records this card") { portfolio.include?("LAB-VM-EVALAST-EVAL-EXPR-P1 CLOSED") }
check("F-11 no app source edits") { protected_diffs.none? { |path| path.start_with?("igniter-apps/") } }
check("F-12 no compiler or VM source edits") { protected_diffs.none? { |path| path.start_with?("igniter-compiler/src/") || path.start_with?("igniter-vm/src/") } }

section("G Follow-Up")
check("G-01 follow-up card exists") { FOLLOWUP_CARD.file? }
check("G-02 follow-up authorizes compiler/emitter function SIR") { followup_card.include?("compiler") && followup_card.include?("function") && followup_card.include?("SIR") }
check("G-03 follow-up authorizes VM function runtime") { followup_card.include?("VM") && followup_card.include?("runtime") }
check("G-04 follow-up keeps app source closed") { followup_card.include?("No app source edits") }
check("G-05 follow-up keeps dynamic dispatch closed") { followup_card.include?("No dynamic dispatch") }
check("G-06 follow-up target includes spreadsheet") { followup_card.include?("spreadsheet") && followup_card.include?("RunWorkbookDemo") }
check("G-07 follow-up names eval_expr/eval_ref") { followup_card.include?("eval_expr") && followup_card.include?("eval_ref") }
check("G-08 follow-up does not claim canon authority") { followup_card.include?("lab") && followup_card.include?("no canon") }

puts "\nRESULT: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
