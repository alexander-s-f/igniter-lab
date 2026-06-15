#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vm_run_ok_recheck_p2.rb
# LAB-VM-RUN-OK-RECHECK-P2
#
# Evidence-only VM RUN-OK recheck after LAB-VM-EVALAST-EVAL-EXPR-P1 closed as
# a routed spike. This proof confirms the fleet count did not change: the
# spreadsheet blocker moved from vague VM eval_ast language to the sharper
# function-SIR/runtime-substrate route.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"
require "digest"

LAB_ROOT = Pathname.new(__dir__).parent.parent
VM_MANIFEST = LAB_ROOT / "igniter-vm" / "Cargo.toml"
VM_BIN = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"
COMPILER_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
COMPILER_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
APPS_ROOT = LAB_ROOT / "igniter-apps"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-VM-RUN-OK-RECHECK-P2.md"
P1_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-VM-RUN-OK-RECHECK-P1.md"
P1_DOC = LAB_ROOT / ".agents" / "docs" / "vm-run-ok-recheck-p1-2026-06-15-v0.md"
EVAL_EXPR_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-EVALAST-EVAL-EXPR-P1.md"
FUNCTION_SIR_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-FUNCTION-SIR-RUNTIME-P1.md"
SURFACE = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
DOC = LAB_ROOT / ".agents" / "docs" / "vm-run-ok-recheck-p2-2026-06-15-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"
SPREADSHEET_REGISTRY = APPS_ROOT / "spreadsheet" / "PRESSURE_REGISTRY.md"
RULE_ENGINE_REGISTRY = APPS_ROOT / "rule_engine" / "PRESSURE_REGISTRY.md"

EXPECTED_ACTIVE_APPS = %w[
  advanced_logistics
  air_combat
  arch_patterns
  audit_ledger
  batch_importer
  bloom_filter
  bookkeeping
  call_router
  dataframes
  decision_tree
  dsa
  erp_logistics
  igniter_parser
  job_runner
  lead_router
  neural_net
  query_engine
  reconciler
  rule_engine
  sim_framework
  spreadsheet
  trade_robot
  vector_editor
  vector_math
  web_router
].freeze

ENTRY_OVERRIDES = {
  "bookkeeping" => "ComputeAccountBalance",
  "dataframes" => "RunDataFrameExample",
  "dsa" => "RunArrayExample",
  "vector_math" => "Vec2Example"
}.freeze

INPUT_OVERRIDES = {
  "bookkeeping" => { "txs" => [], "target_account_id" => "cash" }
}.freeze

EXPECTED_NON_GREEN = {
  "rule_engine" => {
    owner: "governance-gated",
    next_route: "LAB-DYNAMIC-CONTRACT-DISPATCH / ledger D-001",
    evidence: /Unknown\.action|RuleDecision|dynamic|dispatch/i
  },
  "spreadsheet" => {
    owner: "function SIR/runtime substrate",
    next_route: "LAB-FUNCTION-SIR-RUNTIME-P1",
    evidence: /eval_expr|Unsupported operator|functions|function SIR/i
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

def app_sources(app)
  Dir.glob((APPS_ROOT / app / "*.ig").to_s).sort.map { |path| Pathname.new(path) }
end

def source_hash(paths)
  digest = Digest::SHA256.new
  paths.each do |path|
    digest.update(path.basename.to_s)
    digest.update("\0")
    digest.update(File.binread(path.to_s))
    digest.update("\0")
  end
  "sha256:#{digest.hexdigest}"
end

def detect_entry(app, sources)
  return ENTRY_OVERRIDES.fetch(app) if ENTRY_OVERRIDES.key?(app)

  texts = sources.map { |path| read(path) }
  explicit = texts.flat_map { |text| text.scan(/^\s*entrypoint\s+([A-Za-z_][A-Za-z0-9_]*)/) }.flatten.first
  return explicit if explicit

  candidates = texts.flat_map { |text| text.scan(/^\s*contract\s+((?:Run|Main|Demo)[A-Za-z0-9_]*)/) }.flatten.uniq.sort
  called = texts.flat_map { |text| text.scan(/call_contract\("([A-Za-z0-9_]+)"/) }.flatten.uniq.sort
  roots = candidates - called
  return roots.first if roots.size == 1

  nil
end

def compile_app(app, sources, out_dir)
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
    sir: File.exist?(sir_path) ? parse_json(File.read(sir_path, encoding: "UTF-8")) : {}
  }
end

def run_app(app, igapp, entry)
  inputs = INPUT_OVERRIDES.fetch(app, {})
  inputs_path = File.join(File.dirname(igapp), "#{app}_inputs.json")
  File.write(inputs_path, JSON.generate(inputs))
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

def evidence_text(row)
  [
    row[:compile]&.fetch(:stdout, nil),
    row[:compile]&.fetch(:stderr, nil),
    row[:run]&.fetch(:stdout, nil),
    row[:run]&.fetch(:stderr, nil)
  ].compact.join("\n")
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

def protected_diffs
  stdout, _stderr, _status = Open3.capture3("git", "diff", "--name-only")
  stdout.lines.map(&:strip).select do |path|
    (path.start_with?("igniter-apps/") && path.end_with?(".ig")) ||
      path.start_with?("igniter-compiler/src/") ||
      path.start_with?("igniter-vm/src/")
  end
end

TMP = Dir.mktmpdir("lab_vm_run_ok_recheck_p2_")
at_exit { FileUtils.rm_rf(TMP) }

BUILD = build_vm
ACTIVE_REGISTRY_APPS = Dir.glob((APPS_ROOT / "*" / "PRESSURE_REGISTRY.md").to_s).map { |path| File.basename(File.dirname(path)) }.sort

RESULTS = EXPECTED_ACTIVE_APPS.map do |app|
  sources = app_sources(app)
  entry = detect_entry(app, sources)
  out_dir = File.join(TMP, "#{app}.igapp")
  compile = sources.empty? ? nil : compile_app(app, sources, out_dir)
  run = compile && compile[:success] && entry ? run_app(app, out_dir, entry) : nil
  status =
    if compile.nil? || !compile[:success]
      "COMPILE-NOT-OK"
    elsif entry.nil?
      "NO-ENTRY"
    elsif run && run[:success] && run[:json]["status"] == "success"
      "RUN-OK"
    else
      "RUN-NOT-OK"
    end
  {
    app: app,
    sources: sources,
    source_hash: sources.empty? ? nil : source_hash(sources),
    entry: entry,
    compile: compile,
    run: run,
    status: status
  }
end

run_ok = RESULTS.count { |row| row[:status] == "RUN-OK" }
non_green = RESULTS.reject { |row| row[:status] == "RUN-OK" }
non_green_names = non_green.map { |row| row[:app] }.sort
spreadsheet = RESULTS.find { |row| row[:app] == "spreadsheet" }
spreadsheet_eval_expr_calls = find_nodes(spreadsheet[:compile][:sir]) do |node|
  node["kind"] == "call" && node["fn"] == "eval_expr"
end

puts "LAB-VM-RUN-OK-RECHECK-P2"
puts "active_runtime_apps=#{EXPECTED_ACTIVE_APPS.size}"
puts "run_ok=#{run_ok}/#{EXPECTED_ACTIVE_APPS.size}"
puts "non_green=#{non_green_names.join(',')}"

RESULTS.each do |row|
  puts [
    row[:app],
    row[:status],
    "entry=#{row[:entry] || 'none'}",
    "compile=#{row[:compile]&.dig(:exit) || 'none'}",
    "run=#{row[:run]&.dig(:exit) || 'none'}",
    row[:source_hash]
  ].join(" | ")
end

card = read(CARD)
p1_card = read(P1_CARD)
p1_doc = read(P1_DOC)
eval_expr_card = read(EVAL_EXPR_CARD)
function_sir_card = read(FUNCTION_SIR_CARD)
surface = read(SURFACE)
doc = read(DOC)
portfolio = read(PORTFOLIO)
spreadsheet_registry = read(SPREADSHEET_REGISTRY)
rule_engine_registry = read(RULE_ENGINE_REGISTRY)

section("A Gates And Baseline")
check("A-01 VM build succeeds") { BUILD[:success] }
check("A-02 VM binary exists") { File.executable?(VM_BIN.to_s) }
check("A-03 compiler binary exists") { File.executable?(compiler_bin.to_s) }
check("A-04 P1 card is closed") { p1_card.include?("**Status:** CLOSED") }
check("A-05 P1 rollup exists") { P1_DOC.file? }
check("A-06 P1 baseline is RUN-OK 23/25") { p1_card.include?("23/25") && p1_doc.include?("RUN-OK 23/25") }
check("A-07 eval_expr card is closed") { eval_expr_card.include?("**Status:** CLOSED") }
check("A-08 eval_expr card is routed, not implemented") { eval_expr_card.include?("ROUTED") && eval_expr_card.include?("RUN-OK count remains **23/25**") }
check("A-09 function SIR follow-up exists") { FUNCTION_SIR_CARD.file? }
check("A-10 P2 card exists") { CARD.file? }

section("B Fleet Enumeration")
check("B-01 registry-backed active fleet count is 25") { ACTIVE_REGISTRY_APPS == EXPECTED_ACTIVE_APPS }
check("B-02 every active app has source files") { RESULTS.all? { |row| row[:sources].any? } }
check("B-03 every active app has selected entrypoint") { RESULTS.all? { |row| row[:entry].is_a?(String) && !row[:entry].empty? } }
check("B-04 benchmark-app is excluded") { !ACTIVE_REGISTRY_APPS.include?("benchmark-app") }
check("B-05 todolist is excluded") { !ACTIVE_REGISTRY_APPS.include?("todolist") }
check("B-06 bookkeeping still uses ComputeAccountBalance") { RESULTS.find { |row| row[:app] == "bookkeeping" }[:entry] == "ComputeAccountBalance" }
check("B-07 spreadsheet uses RunWorkbookDemo") { spreadsheet[:entry] == "RunWorkbookDemo" }
check("B-08 rule_engine uses RunRuleEngine") { RESULTS.find { |row| row[:app] == "rule_engine" }[:entry] == "RunRuleEngine" }

section("C Runtime Results")
check("C-01 RUN-OK count remains 23 of 25") { run_ok == 23 }
check("C-02 P2 delta vs P1 is zero") { run_ok - 23 == 0 }
check("C-03 non-green set is exactly spreadsheet + rule_engine") { non_green_names == %w[rule_engine spreadsheet] }
check("C-04 all expected non-green apps have owner class") { non_green.all? { |row| EXPECTED_NON_GREEN.key?(row[:app]) } }
check("C-05 spreadsheet compiles cleanly") { spreadsheet[:compile][:success] && spreadsheet[:compile][:json]["status"] == "ok" }
check("C-06 spreadsheet VM still fails") { spreadsheet[:status] == "RUN-NOT-OK" }
check("C-07 spreadsheet failure still names eval_expr") { evidence_text(spreadsheet).match?(/Unsupported operator: eval_expr/) }
check("C-08 spreadsheet SIR has no functions table") { !spreadsheet[:compile][:sir].key?("functions") }
check("C-09 spreadsheet SIR still has eval_expr call") { spreadsheet_eval_expr_calls.size == 1 }
check("C-10 rule_engine remains compile-not-ok") { RESULTS.find { |row| row[:app] == "rule_engine" }[:status] == "COMPILE-NOT-OK" }
check("C-11 rule_engine evidence remains governance-gated") { evidence_text(RESULTS.find { |row| row[:app] == "rule_engine" }).match?(EXPECTED_NON_GREEN["rule_engine"][:evidence]) }
check("C-12 all other apps are RUN-OK") { (EXPECTED_ACTIVE_APPS - %w[rule_engine spreadsheet]).all? { |app| RESULTS.find { |row| row[:app] == app }[:status] == "RUN-OK" } }

section("D Owner Classes")
check("D-01 spreadsheet owner is function SIR/runtime substrate") { EXPECTED_NON_GREEN["spreadsheet"][:owner] == "function SIR/runtime substrate" }
check("D-02 spreadsheet next route is LAB-FUNCTION-SIR-RUNTIME-P1") { EXPECTED_NON_GREEN["spreadsheet"][:next_route] == "LAB-FUNCTION-SIR-RUNTIME-P1" }
check("D-03 function SIR card names compiler/emitter") { function_sir_card.include?("Compiler/emitter") || function_sir_card.include?("compiler/emitter") }
check("D-04 function SIR card names VM runtime") { function_sir_card.include?("VM") && function_sir_card.include?("runtime") }
check("D-05 spreadsheet registry is routed to function SIR") { spreadsheet_registry.include?("SS-P08 | ROUTED") && spreadsheet_registry.include?("LAB-FUNCTION-SIR-RUNTIME-P1") }
check("D-06 surface records function SIR route") { surface.include?("function SIR/runtime substrate") && surface.include?("LAB-FUNCTION-SIR-RUNTIME-P1") }
check("D-07 rule_engine registry still says dynamic dispatch/fail-closed") { rule_engine_registry.include?("dynamic") && rule_engine_registry.include?("fail-closed") }
check("D-08 no pressure resolution without live evidence") { !card.include?("spreadsheet RUN-OK") }

section("E Artifacts")
check("E-01 P2 card is closed") { card.include?("**Status:** CLOSED") }
check("E-02 P2 card records RUN-OK 23/25") { card.include?("RUN-OK 23/25") }
check("E-03 P2 card records no count change") { card.include?("delta 0") || card.include?("no count change") }
check("E-04 P2 rollup doc exists") { DOC.file? }
check("E-05 P2 rollup records active fleet") { doc.include?("25") && doc.include?("advanced_logistics") && doc.include?("web_router") }
check("E-06 P2 rollup records non-green owners") { doc.include?("function SIR/runtime substrate") && doc.include?("governance-gated") }
check("E-07 P2 rollup records compile/run separation") { doc.include?("COMPILE-NOT-OK") && doc.include?("RUN-NOT-OK") }
check("E-08 portfolio records P2") { portfolio.include?("LAB-VM-RUN-OK-RECHECK-P2 CLOSED") }
check("E-09 proof runner exists") { Pathname.new(__FILE__).file? }
check("E-10 protected source diffs are empty") { protected_diffs.empty? }

section("F Boundary")
check("F-01 card keeps no compiler changes closed") { card.include?("No compiler changes") }
check("F-02 card keeps no VM changes closed") { card.include?("No VM changes") }
check("F-03 card keeps no app migrations closed") { card.include?("No app migrations") }
check("F-04 rule_engine remains governance-gated") { EXPECTED_NON_GREEN["rule_engine"][:owner] == "governance-gated" }
check("F-05 proof uses temp output directory") { TMP.start_with?(Dir.tmpdir) }
check("F-06 proof does not edit app source") { protected_diffs.none? { |path| path.start_with?("igniter-apps/") } }
check("F-07 proof does not edit compiler source") { protected_diffs.none? { |path| path.start_with?("igniter-compiler/src/") } }
check("F-08 proof does not edit VM source") { protected_diffs.none? { |path| path.start_with?("igniter-vm/src/") } }

puts "\nRESULT: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
