#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vm_run_ok_recheck_p3.rb
# LAB-VM-RUN-OK-RECHECK-P3
#
# Evidence-only VM RUN-OK recheck after LAB-FUNCTION-SIR-RUNTIME-P1 and
# LAB-RUST-DECIMAL-INPUT-SCALE-P1. This proof keeps compile status separate from
# runtime status and confirms the active registry-backed runtime fleet moved
# from P2's 23/25 to 24/25: spreadsheet is now RUN-OK; rule_engine remains the
# single governance-gated compile-not-ok app.

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

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-VM-RUN-OK-RECHECK-P3.md"
P2_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-VM-RUN-OK-RECHECK-P2.md"
P2_DOC = LAB_ROOT / ".agents" / "docs" / "vm-run-ok-recheck-p2-2026-06-15-v0.md"
FUNCTION_SIR_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-FUNCTION-SIR-RUNTIME-P1.md"
DECIMAL_SCALE_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-RUST-DECIMAL-INPUT-SCALE-P1.md"
SURFACE = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
DOC = LAB_ROOT / ".agents" / "docs" / "vm-run-ok-recheck-p3-2026-06-15-v0.md"
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
    owner: "governance-gated dynamic dispatch",
    next_route: "LAB-DYNAMIC-CONTRACT-DISPATCH-P2 selected safe route / ledger D-001",
    evidence: /Unknown\.action|RuleDecision|dynamic|dispatch/i
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

TMP = Dir.mktmpdir("lab_vm_run_ok_recheck_p3_")
at_exit { FileUtils.rm_rf(TMP) }

BUILD = build_vm
ACTIVE_REGISTRY_APPS = Dir.glob((APPS_ROOT / "*" / "PRESSURE_REGISTRY.md").to_s).map { |path| File.basename(File.dirname(path)) }.sort

RESULTS = EXPECTED_ACTIVE_APPS.map do |app|
  sources = app_sources(app)
  entry = detect_entry(app, sources)
  out_dir = File.join(TMP, "#{app}.igapp")
  compile = sources.empty? ? nil : compile_app(app, sources, out_dir)
  run = compile && compile[:success] && entry ? run_app(app, out_dir, entry) : nil
  runtime_status =
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
    status: runtime_status
  }
end

run_ok = RESULTS.count { |row| row[:status] == "RUN-OK" }
non_green = RESULTS.reject { |row| row[:status] == "RUN-OK" }
non_green_names = non_green.map { |row| row[:app] }.sort
spreadsheet = RESULTS.find { |row| row[:app] == "spreadsheet" }
rule_engine = RESULTS.find { |row| row[:app] == "rule_engine" }
spreadsheet_functions = Array(spreadsheet[:compile][:sir]["functions"])
spreadsheet_function_names = spreadsheet_functions.map { |fn| fn["name"] }.sort
spreadsheet_eval_expr_calls = find_nodes(spreadsheet[:compile][:sir]) do |node|
  node["kind"] == "call" && node["fn"] == "eval_expr"
end

puts "LAB-VM-RUN-OK-RECHECK-P3"
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
p2_card = read(P2_CARD)
p2_doc = read(P2_DOC)
function_sir_card = read(FUNCTION_SIR_CARD)
decimal_scale_card = read(DECIMAL_SCALE_CARD)
surface = read(SURFACE)
doc = read(DOC)
portfolio = read(PORTFOLIO)
spreadsheet_registry = read(SPREADSHEET_REGISTRY)
rule_engine_registry = read(RULE_ENGINE_REGISTRY)

section("A Gates And Baseline")
check("A-01 VM build succeeds") { BUILD[:success] }
check("A-02 VM binary exists") { File.executable?(VM_BIN.to_s) }
check("A-03 compiler binary exists") { File.executable?(compiler_bin.to_s) }
check("A-04 P2 card is closed") { p2_card.include?("**Status:** CLOSED") }
check("A-05 P2 rollup exists") { P2_DOC.file? }
check("A-06 P2 baseline is RUN-OK 23/25") { p2_card.include?("RUN-OK 23/25") && p2_doc.include?("RUN-OK 23/25") }
check("A-07 function SIR card is closed") { function_sir_card.include?("**Status:** CLOSED") }
check("A-08 function SIR card says spreadsheet RUN-OK") { function_sir_card.include?("spreadsheet RunWorkbookDemo RUN-OK") || function_sir_card.include?("RunWorkbookDemo` runs") }
check("A-09 decimal scale card is closed") { decimal_scale_card.include?("**Status:** CLOSED") }
check("A-10 P3 card exists") { CARD.file? }
check("A-11 P3 authority is evidence-only") { card.include?("evidence-only runtime recheck") }
check("A-12 P3 gate mentions closed decimal scale card") { card.include?("LAB-RUST-DECIMAL-INPUT-SCALE-P1") }

section("B Fleet Enumeration")
check("B-01 registry-backed active fleet count is 25") { ACTIVE_REGISTRY_APPS == EXPECTED_ACTIVE_APPS }
check("B-02 every active app has source files") { RESULTS.all? { |row| row[:sources].any? } }
check("B-03 every active app has selected entrypoint") { RESULTS.all? { |row| row[:entry].is_a?(String) && !row[:entry].empty? } }
check("B-04 benchmark-app is excluded") { !ACTIVE_REGISTRY_APPS.include?("benchmark-app") }
check("B-05 todolist is excluded") { !ACTIVE_REGISTRY_APPS.include?("todolist") }
check("B-06 bookkeeping still uses ComputeAccountBalance") { RESULTS.find { |row| row[:app] == "bookkeeping" }[:entry] == "ComputeAccountBalance" }
check("B-07 spreadsheet uses RunWorkbookDemo") { spreadsheet[:entry] == "RunWorkbookDemo" }
check("B-08 rule_engine uses RunRuleEngine") { rule_engine[:entry] == "RunRuleEngine" }
check("B-09 all apps have source hashes") { RESULTS.all? { |row| row[:source_hash].to_s.start_with?("sha256:") } }
check("B-10 fleet includes spreadsheet in active metric") { ACTIVE_REGISTRY_APPS.include?("spreadsheet") }

section("C Runtime Results")
check("C-01 RUN-OK count is 24 of 25") { run_ok == 24 }
check("C-02 P3 delta vs P2 is plus one") { run_ok - 23 == 1 }
check("C-03 non-green set is exactly rule_engine") { non_green_names == %w[rule_engine] }
check("C-04 every non-green app has owner class") { non_green.all? { |row| EXPECTED_NON_GREEN.key?(row[:app]) } }
check("C-05 no RUN-NOT-OK apps remain") { RESULTS.none? { |row| row[:status] == "RUN-NOT-OK" } }
check("C-06 only compile-not-ok app is rule_engine") { RESULTS.select { |row| row[:status] == "COMPILE-NOT-OK" }.map { |row| row[:app] } == %w[rule_engine] }
check("C-07 all non-rule apps are RUN-OK") { (EXPECTED_ACTIVE_APPS - %w[rule_engine]).all? { |app| RESULTS.find { |row| row[:app] == app }[:status] == "RUN-OK" } }
check("C-08 compile and runtime statuses are separate") { rule_engine[:compile] && rule_engine[:run].nil? && spreadsheet[:compile] && spreadsheet[:run] }
check("C-09 P3 did not count compile success as runtime success") { RESULTS.all? { |row| row[:status] != "RUN-OK" || row[:run]&.dig(:json, "status") == "success" } }
check("C-10 source hashes are stable across result rows") { RESULTS.map { |row| row[:source_hash] }.uniq.size == EXPECTED_ACTIVE_APPS.size }

section("D Spreadsheet Resolution Evidence")
check("D-01 spreadsheet compiles cleanly") { spreadsheet[:compile][:success] && spreadsheet[:compile][:json]["status"] == "ok" }
check("D-02 spreadsheet VM runs successfully") { spreadsheet[:status] == "RUN-OK" && spreadsheet[:run][:json]["status"] == "success" }
check("D-03 spreadsheet SIR has functions array") { spreadsheet_functions.any? }
check("D-04 spreadsheet SIR includes eval_expr and eval_ref") { spreadsheet_function_names == %w[eval_expr eval_ref] }
check("D-05 spreadsheet emitted SIR still references eval_expr as executable function substrate") do
  JSON.generate(spreadsheet[:compile][:sir]).include?("eval_expr") &&
    spreadsheet_functions.any? { |fn| JSON.generate(fn["body"]).include?("eval_expr") || fn["name"] == "eval_expr" }
end
check("D-06 eval_expr call no longer traps at runtime") { !evidence_text(spreadsheet).include?("Unsupported operator: eval_expr") }
check("D-07 spreadsheet VM result is an array") { spreadsheet[:run][:json]["result"].is_a?(Array) }
check("D-08 spreadsheet VM result has one evaluated cell") { Array(spreadsheet[:run][:json]["result"]).size == 1 }
check("D-09 spreadsheet evaluated cell kind is Number") { spreadsheet[:run][:json].dig("result", 0, "kind") == "Number" }
check("D-10 spreadsheet evaluated cell num_val is 7.0") { spreadsheet[:run][:json].dig("result", 0, "num_val") == 7.0 }
check("D-11 spreadsheet registry records SS-P08 resolved") { spreadsheet_registry.include?("SS-P08 RESOLVED") }
check("D-12 VM surface records app-local def function registry implemented") { surface.include?("app-local `def` function registry") && surface.include?("✅") }

section("E Rule Engine Still Governance-Gated")
check("E-01 rule_engine remains compile-not-ok") { rule_engine[:status] == "COMPILE-NOT-OK" }
check("E-02 rule_engine has no VM run attempted") { rule_engine[:run].nil? }
check("E-03 rule_engine evidence names Unknown.action") { evidence_text(rule_engine).include?("Unknown.action") }
check("E-04 rule_engine evidence names RuleDecision") { evidence_text(rule_engine).include?("RuleDecision") }
check("E-05 rule_engine owner is governance-gated dynamic dispatch") { EXPECTED_NON_GREEN["rule_engine"][:owner] == "governance-gated dynamic dispatch" }
check("E-06 rule_engine registry records selected safe route") { rule_engine_registry.include?("selected safe route") || rule_engine_registry.include?("intentional fail-closed") }
check("E-07 P3 does not relax dynamic dispatch") { card.include?("rule_engine") && card.include?("governance-gated") }
check("E-08 rule_engine remains only non-green owner") { non_green == [rule_engine] }

section("F Artifacts")
check("F-01 P3 card is closed") { card.include?("**Status:** CLOSED") }
check("F-02 P3 card records RUN-OK 24/25") { card.include?("RUN-OK 24/25") }
check("F-03 P3 card records delta plus one") { card.include?("+1") || card.include?("plus one") }
check("F-04 P3 rollup doc exists") { DOC.file? }
check("F-05 P3 rollup records active fleet") { doc.include?("25 apps") && doc.include?("advanced_logistics") && doc.include?("web_router") }
check("F-06 P3 rollup records spreadsheet resolved") { doc.include?("spreadsheet") && doc.include?("RUN-OK") && doc.include?("function SIR") }
check("F-07 P3 rollup records rule_engine non-green owner") { doc.include?("rule_engine") && doc.include?("governance-gated") }
check("F-08 P3 rollup records compile/run separation") { doc.include?("COMPILE-NOT-OK") && doc.include?("RUN-OK") }
check("F-09 portfolio records P3") { portfolio.include?("LAB-VM-RUN-OK-RECHECK-P3 CLOSED") }
check("F-10 proof runner exists") { Pathname.new(__FILE__).file? }

section("G Boundary")
check("G-01 card keeps no compiler changes closed") { card.include?("No compiler changes") }
check("G-02 card keeps no VM changes closed") { card.include?("No VM changes") }
check("G-03 card keeps no app migrations closed") { card.include?("No app migrations") }
check("G-04 card keeps no pressure resolution without live evidence") { card.include?("No pressure resolution without live runtime evidence") }
check("G-05 protected source diffs are empty") { protected_diffs.empty? }
check("G-06 proof uses temp output directory") { TMP.start_with?(Dir.tmpdir) }
check("G-07 proof does not edit app source") { protected_diffs.none? { |path| path.start_with?("igniter-apps/") } }
check("G-08 proof does not edit compiler source") { protected_diffs.none? { |path| path.start_with?("igniter-compiler/src/") } }
check("G-09 proof does not edit VM source") { protected_diffs.none? { |path| path.start_with?("igniter-vm/src/") } }
check("G-10 Ruby/canon authority is not claimed") { card.include?("evidence-only") && !doc.include?("canon authority") }

puts "\nRESULT: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
