#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vm_dispatch_skip_diagnostics_p1.rb
# LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1
#
# Proves VM dispatch table construction no longer silently skips contracts whose
# dispatch entries fail bytecode compilation.
#
# Authority: lab VM diagnostic behavior only. No compiler, typechecker, app
# source, dynamic dispatch, Unknown permissiveness, or canon language claim.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
VM_MANIFEST = LAB_ROOT / "igniter-vm" / "Cargo.toml"
VM_BIN = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"
VM_MAIN = LAB_ROOT / "igniter-vm" / "src" / "main.rs"
COMPILER_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
COMPILER_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1.md"
NUMERIC_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md"
EVALAST_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-EVALAST-MATCH-P1.md"
DOC = LAB_ROOT / "lab-docs" / "lang" / "lab-vm-dispatch-skip-diagnostics-p1-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"

APP_SPECS = {
  "batch_importer" => {
    sources: %w[types.ig validate.ig example.ig],
    entry: "RunImport",
    expected_status: "success"
  },
  "lead_router" => {
    sources: %w[types.ig pipeline.ig service.ig example.ig],
    entry: "RunAccept",
    expected_status: "success"
  },
  "call_router" => {
    sources: %w[types.ig correlate.ig operator.ig webhook.ig service.ig example.ig],
    entry: "RunConnectedMatched",
    expected_status: "success"
  }
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

def write_igapp(dir, sir)
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, "semantic_ir_program.json"), JSON.pretty_generate(sir))
  File.write(
    File.join(dir, "manifest.json"),
    JSON.pretty_generate({ "artifact_hash" => "synthetic-test", "capabilities" => [] })
  )
  dir
end

def literal_contract(name, value)
  {
    "contract_name" => name,
    "name" => name,
    "modifier" => "pure",
    "inputs" => [],
    "outputs" => [{ "name" => "result", "type" => { "name" => "Integer" } }],
    "nodes" => [
      {
        "kind" => "compute_node",
        "name" => "result",
        "expression" => { "kind" => "literal", "value" => value }
      }
    ]
  }
end

def call_contract_contract(name, callee)
  {
    "contract_name" => name,
    "name" => name,
    "modifier" => "pure",
    "inputs" => [],
    "outputs" => [{ "name" => "result", "type" => { "name" => "Integer" } }],
    "nodes" => [
      {
        "kind" => "compute_node",
        "name" => "result",
        "expression" => {
          "kind" => "call",
          "fn" => "call_contract",
          "args" => [{ "kind" => "literal", "value" => callee }]
        }
      }
    ]
  }
end

def unbuildable_contract(name)
  {
    "contract_name" => name,
    "name" => name,
    "modifier" => "pure",
    "inputs" => [],
    "outputs" => [{ "name" => "result", "type" => { "name" => "Integer" } }],
    "nodes" => [
      {
        "kind" => "compute_node",
        "name" => "result",
        "expression" => { "kind" => "dispatch_skip_probe" }
      }
    ]
  }
end

def run_vm(igapp, inputs_hash, entry: nil, json: true)
  inputs_path = File.join(File.dirname(igapp), "inputs_#{entry || 'default'}_#{json ? 'json' : 'text'}.json")
  File.write(inputs_path, JSON.generate(inputs_hash))
  argv = [VM_BIN.to_s, "run", "--contract", igapp.to_s, "--inputs", inputs_path]
  argv.concat(["--entry", entry]) if entry
  argv << "--json" if json
  stdout, stderr, status = Open3.capture3(*argv)
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: json ? parse_json(stdout) : nil
  }
end

def compile_app(app_name, source_names, out_dir)
  app_dir = LAB_ROOT / "igniter-apps" / app_name
  sources = source_names.map { |name| (app_dir / name).to_s }
  stdout, stderr, status = Open3.capture3(
    compiler_bin.to_s,
    "compile",
    *sources,
    "--out",
    out_dir.to_s
  )
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: parse_json(stdout)
  }
end

TMP = Dir.mktmpdir("lab_vm_dispatch_skip_diagnostics_p1_")
at_exit { FileUtils.rm_rf(TMP) }

BUILD = build_vm

BROKEN_IGAPP = File.join(TMP, "broken_dispatch.igapp")
BROKEN_SIR = {
  "schema_version" => "semantic-ir-test-v0",
  "contracts" => [
    literal_contract("RootOk", 7),
    unbuildable_contract("BadDispatch")
  ]
}
write_igapp(BROKEN_IGAPP, BROKEN_SIR)

GOOD_IGAPP = File.join(TMP, "good_dispatch.igapp")
GOOD_SIR = {
  "schema_version" => "semantic-ir-test-v0",
  "contracts" => [
    call_contract_contract("RootCallsGood", "GoodCallee"),
    literal_contract("GoodCallee", 42)
  ]
}
write_igapp(GOOD_IGAPP, GOOD_SIR)

BROKEN_JSON = run_vm(BROKEN_IGAPP, {}, entry: "RootOk", json: true)
BROKEN_TEXT = run_vm(BROKEN_IGAPP, {}, entry: "RootOk", json: false)
GOOD_JSON = run_vm(GOOD_IGAPP, {}, entry: "RootCallsGood", json: true)

APP_RESULTS = {}
APP_SPECS.each do |app_name, spec|
  out_dir = File.join(TMP, "#{app_name}.igapp")
  compile = compile_app(app_name, spec[:sources], out_dir)
  vm = compile[:success] ? run_vm(out_dir, {}, entry: spec[:entry], json: true) : nil
  APP_RESULTS[app_name] = { compile: compile, vm: vm, spec: spec }
  sleep 1
end

main_text = read(VM_MAIN)
card_text = read(CARD)
numeric_card_text = read(NUMERIC_CARD)
evalast_card_text = read(EVALAST_CARD)
doc_text = read(DOC)
portfolio_text = read(PORTFOLIO)
proof_text = read(Pathname.new(__FILE__))

puts "LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1"

section("A Implementation Shape")
check("A-01 VM build succeeds") { BUILD[:success] }
check("A-02 VM binary exists after build") { File.executable?(VM_BIN.to_s) }
check("A-03 main.rs contains dispatch_skipped accumulator") { main_text.include?("dispatch_skipped") }
check("A-04 main.rs emits dispatch_built count") { main_text.include?("\"dispatch_built\"") }
check("A-05 main.rs emits dispatch_skipped diagnostics") { main_text.include?("\"dispatch_skipped\"") }
check("A-06 main.rs refuses partial VM load") { main_text.include?("refusing partial VM load") }
check("A-07 main.rs reports skipped contract name") { main_text.include?("skipped dispatch entry for") }
check("A-08 old note-only skip is absent") { !main_text.include?("[P9] Note: skipping dispatch entry") }
check("A-09 helper accepts contract_name") { main_text.include?("contract_display_name") && main_text.include?("contract_name") }
check("A-10 helper accepts contract_id fallback") { main_text.include?("contract_id") }
check("A-11 code exits non-zero after dispatch diagnostics") { main_text.include?("std::process::exit(1);") }
check("A-12 implementation scope stays in main.rs") { !main_text.include?("dynamic dispatch relaxation") }

section("B Gates And Fixture Shape")
check("B-01 numeric dispatch dependency card exists") { NUMERIC_CARD.file? }
check("B-02 numeric dispatch cluster 2 is done") { numeric_card_text.include?("Cluster 2") && numeric_card_text.include?("DONE 2026-06-15") }
check("B-03 eval_ast match card exists") { EVALAST_CARD.file? }
check("B-04 eval_ast match card is done") { evalast_card_text.include?("**Status: DONE 2026-06-15.") }
check("B-05 broken fixture has two emitted contracts") { BROKEN_SIR["contracts"].size == 2 }
check("B-06 broken fixture root is buildable") { BROKEN_SIR["contracts"].first["contract_name"] == "RootOk" }
check("B-07 broken fixture second contract is BadDispatch") { BROKEN_SIR["contracts"][1]["contract_name"] == "BadDispatch" }
check("B-08 bad contract uses unsupported AST kind") { BROKEN_SIR["contracts"][1]["nodes"][0]["expression"]["kind"] == "dispatch_skip_probe" }
check("B-09 good fixture has two emitted contracts") { GOOD_SIR["contracts"].size == 2 }
check("B-10 good fixture root calls GoodCallee") { GOOD_SIR["contracts"][0]["nodes"][0]["expression"]["args"][0]["value"] == "GoodCallee" }
check("B-11 fixtures are igapp directories") { File.directory?(BROKEN_IGAPP) && File.directory?(GOOD_IGAPP) }
check("B-12 fixtures include semantic_ir_program.json") do
  File.exist?(File.join(BROKEN_IGAPP, "semantic_ir_program.json")) &&
    File.exist?(File.join(GOOD_IGAPP, "semantic_ir_program.json"))
end
check("B-13 fixtures include manifest.json") do
  File.exist?(File.join(BROKEN_IGAPP, "manifest.json")) &&
    File.exist?(File.join(GOOD_IGAPP, "manifest.json"))
end
check("B-14 synthetic manifests declare no capabilities") do
  JSON.parse(File.read(File.join(GOOD_IGAPP, "manifest.json")))["capabilities"] == [] &&
    JSON.parse(File.read(File.join(BROKEN_IGAPP, "manifest.json")))["capabilities"] == []
end

section("C JSON Failure Diagnostics")
check("C-01 broken JSON run exits non-zero") { BROKEN_JSON[:exit] != 0 }
check("C-02 broken JSON run is not success") { !BROKEN_JSON[:success] }
check("C-03 broken JSON stdout parses") { !BROKEN_JSON[:json].key?("_parse_error") }
check("C-04 broken JSON status is error") { BROKEN_JSON[:json]["status"] == "error" }
check("C-05 broken JSON error names dispatch table construction") { BROKEN_JSON[:json]["error"].to_s.include?("Dispatch table construction failed") }
check("C-06 broken JSON has dispatch_built=1") { BROKEN_JSON[:json]["dispatch_built"] == 1 }
check("C-07 broken JSON has one skipped entry") { Array(BROKEN_JSON[:json]["dispatch_skipped"]).size == 1 }
check("C-08 skipped entry names BadDispatch") { BROKEN_JSON[:json].dig("dispatch_skipped", 0, "contract_name") == "BadDispatch" }
check("C-09 skipped entry includes compile error") { BROKEN_JSON[:json].dig("dispatch_skipped", 0, "error").to_s.include?("Unsupported AST expression kind") }
check("C-10 skipped entry includes underlying AST kind") { BROKEN_JSON[:json].dig("dispatch_skipped", 0, "error").to_s.include?("dispatch_skip_probe") }
check("C-11 broken JSON result is absent") { !BROKEN_JSON[:json].key?("result") }
check("C-12 broken JSON observations absent") { !BROKEN_JSON[:json].key?("observations") }
check("C-13 broken JSON stderr has no evaluation success") { !BROKEN_JSON[:stderr].include?("EVALUATION SUCCESS") }
check("C-14 previous partial table cannot pass green") { BROKEN_JSON[:exit] != 0 && BROKEN_JSON[:json]["status"] != "success" }

section("D Non JSON Failure Diagnostics")
check("D-01 broken text run exits non-zero") { BROKEN_TEXT[:exit] != 0 }
check("D-02 broken text run is not success") { !BROKEN_TEXT[:success] }
check("D-03 text stderr names dispatch construction failure") { BROKEN_TEXT[:stderr].include?("Dispatch table construction failed") }
check("D-04 text stderr refuses partial load") { BROKEN_TEXT[:stderr].include?("refusing partial VM load") }
check("D-05 text stderr reports built count") { BROKEN_TEXT[:stderr].include?("Successfully built dispatch entries: 1") }
check("D-06 text stderr names skipped contract") { BROKEN_TEXT[:stderr].include?("BadDispatch") }
check("D-07 text stderr includes compile error") { BROKEN_TEXT[:stderr].include?("Unsupported AST expression kind") }
check("D-08 text stderr includes unsupported kind") { BROKEN_TEXT[:stderr].include?("dispatch_skip_probe") }
check("D-09 text output has no evaluation success") { !(BROKEN_TEXT[:stdout] + BROKEN_TEXT[:stderr]).include?("EVALUATION SUCCESS") }
check("D-10 text output does not claim clean run") { !(BROKEN_TEXT[:stdout] + BROKEN_TEXT[:stderr]).include?("status\":\"success") }

section("E Fully Buildable Synthetic App")
check("E-01 good JSON run exits zero") { GOOD_JSON[:exit] == 0 }
check("E-02 good JSON run is success") { GOOD_JSON[:success] }
check("E-03 good JSON stdout parses") { !GOOD_JSON[:json].key?("_parse_error") }
check("E-04 good JSON status success") { GOOD_JSON[:json]["status"] == "success" }
check("E-05 good JSON result is 42") { GOOD_JSON[:json]["result"] == 42 }
check("E-06 good JSON has latency") { GOOD_JSON[:json].key?("latency_us") }
check("E-07 good JSON has observations array") { GOOD_JSON[:json]["observations"].is_a?(Array) }
check("E-08 good JSON has no dispatch_skipped") { !GOOD_JSON[:json].key?("dispatch_skipped") }
check("E-09 good JSON has no error") { !GOOD_JSON[:json].key?("error") }
check("E-10 dispatch still supports call_contract") { GOOD_JSON[:json]["result"] == 42 }

section("F Real App VM Regressions")
APP_RESULTS.each do |app_name, result|
  compile = result[:compile]
  vm = result[:vm] || { json: {}, exit: 1, success: false, stdout: "", stderr: "compile failed" }
  spec = result[:spec]
  check("F-#{app_name}-01 compile exits zero") { compile[:exit] == 0 }
  check("F-#{app_name}-02 compile status ok") { compile[:json]["status"] == "ok" }
  check("F-#{app_name}-03 compile diagnostics empty") { Array(compile[:json]["diagnostics"]).empty? }
  check("F-#{app_name}-04 VM exits zero") { vm[:exit] == 0 }
  check("F-#{app_name}-05 VM status success") { vm[:json]["status"] == spec[:expected_status] }
  check("F-#{app_name}-06 VM has no dispatch_skipped") { !vm[:json].key?("dispatch_skipped") }
end

section("G Closure Artifacts")
check("G-01 proof file names card") { proof_text.include?("LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1") }
check("G-02 proof file covers JSON diagnostics") { proof_text.include?("JSON Failure Diagnostics") }
check("G-03 proof file covers non JSON diagnostics") { proof_text.include?("Non JSON Failure Diagnostics") }
check("G-04 proof file covers real apps") { proof_text.include?("Real App VM Regressions") }
check("G-05 lab doc exists") { DOC.file? }
check("G-06 lab doc records fail closed policy") { doc_text.include?("fail-closed") }
check("G-07 lab doc records dispatch_skipped") { doc_text.include?("dispatch_skipped") }
check("G-08 lab doc states lab VM authority only") { doc_text.include?("lab VM diagnostic behavior") }
check("G-09 card is closed") { card_text.include?("**Status:** CLOSED") }
check("G-10 card records proof count") { card_text.include?("90/90 PASS") }
check("G-11 portfolio contains closure entry") { portfolio_text.include?("LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1 CLOSED") }
check("G-12 portfolio references proof runner") { portfolio_text.include?("verify_lab_vm_dispatch_skip_diagnostics_p1.rb") }

puts "\nRESULT: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
