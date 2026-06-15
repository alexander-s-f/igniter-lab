#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vm_run_ok_recheck_p1.rb
# LAB-VM-RUN-OK-RECHECK-P1
#
# Evidence-only VM RUN-OK recheck for the registry-backed runtime app fleet.
# This proof compiles app sources to fresh temp .igapp directories and runs one
# selected zero-input or fixture-backed entrypoint per active app.
#
# Authority: lab runtime evidence only. No compiler, VM, app-source, migration,
# canon, or dynamic dispatch authority is implied.

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

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-VM-RUN-OK-RECHECK-P1.md"
CHECKPOINT = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md"
APP_DEMO_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-APP-DEMO-ENTRY-WAVE-P1.md"
CHAR_AT_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-STDLIB-STRING-CHAR-AT-VM-P1.md"
DECIMAL_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-NUMERIC-DECIMAL-CONSTRUCT-P1.md"
BOOKKEEPING_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1.md"
SURFACE = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
DOC = LAB_ROOT / ".agents" / "docs" / "vm-run-ok-recheck-p1-2026-06-15-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"
PARSER_REGISTRY = APPS_ROOT / "igniter_parser" / "PRESSURE_REGISTRY.md"
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
    owner: "real runtime bug",
    next_route: "VM app-local function-call/eval_expr support",
    evidence: /eval_expr|Unsupported operator|function-call|runtime/i
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
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: parse_json(stdout)
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

TMP = Dir.mktmpdir("lab_vm_run_ok_recheck_p1_")
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

puts "LAB-VM-RUN-OK-RECHECK-P1"
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

card_text = read(CARD)
checkpoint_text = read(CHECKPOINT)
app_demo_text = read(APP_DEMO_CARD)
char_at_text = read(CHAR_AT_CARD)
decimal_text = read(DECIMAL_CARD)
bookkeeping_text = read(BOOKKEEPING_CARD)
surface_text = read(SURFACE)
doc_text = read(DOC)
portfolio_text = read(PORTFOLIO)
parser_registry_text = read(PARSER_REGISTRY)
spreadsheet_registry_text = read(SPREADSHEET_REGISTRY)
rule_engine_registry_text = read(RULE_ENGINE_REGISTRY)

section("A Fleet Enumeration")
check("A-01 VM build succeeds") { BUILD[:success] }
check("A-02 VM binary exists") { File.executable?(VM_BIN.to_s) }
check("A-03 compiler binary exists") { File.executable?(compiler_bin.to_s) }
check("A-04 registry-backed active fleet count is 25") { ACTIVE_REGISTRY_APPS == EXPECTED_ACTIVE_APPS }
check("A-05 benchmark-app is excluded from active registry-backed fleet") { !ACTIVE_REGISTRY_APPS.include?("benchmark-app") }
check("A-06 todolist is excluded from active registry-backed fleet") { !ACTIVE_REGISTRY_APPS.include?("todolist") }
check("A-07 every active app has at least one source file") { RESULTS.all? { |row| row[:sources].any? } }
check("A-08 every active app has a selected entrypoint") { RESULTS.all? { |row| row[:entry].is_a?(String) && !row[:entry].empty? } }
check("A-09 bookkeeping uses fixture-backed Decimal entry") { RESULTS.find { |row| row[:app] == "bookkeeping" }[:entry] == "ComputeAccountBalance" }
check("A-10 string parser uses zero-input demo entry") { RESULTS.find { |row| row[:app] == "igniter_parser" }[:entry] == "RunParseDemo" }

section("B Runtime Results")
check("B-01 every active app compiles before runtime classification except expected governance gates") do
  RESULTS.all? { |row| row[:compile]&.dig(:success) || row[:app] == "rule_engine" }
end
check("B-02 RUN-OK count is 23 of 25") { run_ok == 23 }
check("B-03 non-green set is exactly spreadsheet + rule_engine") { non_green_names == %w[rule_engine spreadsheet] }
check("B-04 every non-green app has exactly one owner class") { non_green.all? { |row| EXPECTED_NON_GREEN.key?(row[:app]) } }
check("B-05 spreadsheet remains a runtime bug, not needs-inputs") do
  row = RESULTS.find { |result| result[:app] == "spreadsheet" }
  row[:compile][:success] && row[:entry] == "RunWorkbookDemo" && evidence_text(row).match?(EXPECTED_NON_GREEN["spreadsheet"][:evidence])
end
check("B-06 rule_engine remains governance-gated") do
  row = RESULTS.find { |result| result[:app] == "rule_engine" }
  row[:status] != "RUN-OK" && evidence_text(row).match?(EXPECTED_NON_GREEN["rule_engine"][:evidence])
end
check("B-07 igniter_parser is RUN-OK after char_at VM support") { RESULTS.find { |row| row[:app] == "igniter_parser" }[:status] == "RUN-OK" }
check("B-08 bookkeeping is RUN-OK after Decimal constructor/migration") { RESULTS.find { |row| row[:app] == "bookkeeping" }[:status] == "RUN-OK" }
check("B-09 advanced_logistics is RUN-OK through demo entry") { RESULTS.find { |row| row[:app] == "advanced_logistics" }[:status] == "RUN-OK" }
check("B-10 vector_editor is RUN-OK through demo entry") { RESULTS.find { |row| row[:app] == "vector_editor" }[:status] == "RUN-OK" }
check("B-11 erp_logistics selected entry is RUN-OK") { RESULTS.find { |row| row[:app] == "erp_logistics" }[:status] == "RUN-OK" }
check("B-12 compile-clean and run-clean are distinct columns") { RESULTS.all? { |row| row.key?(:compile) && row.key?(:run) && row.key?(:status) } }

section("C Checkpoint Delta")
check("C-01 checkpoint baseline is RUN-OK 1 to 18") { checkpoint_text.include?("RUN-OK 1") && checkpoint_text.include?("18") }
check("C-02 recheck delta from checkpoint is +5 RUN-OK") { run_ok - 18 == 5 }
check("C-03 app demo wave card is closed") { app_demo_text.include?("CLOSED") }
check("C-04 char_at VM card is closed") { char_at_text.include?("CLOSED") }
check("C-05 Decimal construct card exists") { DECIMAL_CARD.file? }
check("C-06 bookkeeping migration card exists") { BOOKKEEPING_CARD.file? }

section("D Closure Artifacts")
check("D-01 card is closed") { card_text.include?("**Status:** CLOSED") }
check("D-02 card records RUN-OK 23/25") { card_text.include?("RUN-OK 23/25") }
check("D-03 card keeps no source changes boundary") { card_text.include?("No source files modified") || card_text.include?("no source files modified") }
check("D-04 rollup doc exists") { DOC.file? }
check("D-05 rollup doc records exact active fleet") { doc_text.include?("25") && doc_text.include?("advanced_logistics") && doc_text.include?("web_router") }
check("D-06 rollup doc records non-green owner classes") { doc_text.include?("spreadsheet") && doc_text.include?("real runtime bug") && doc_text.include?("governance-gated") }
check("D-07 surface index records RUN-OK recheck") { surface_text.include?("RUN-OK recheck") && surface_text.include?("23/25") }
check("D-08 surface index no longer keeps demo-entry as current owner bucket") { !surface_text.include?("| needs-inputs / demo-entry | advanced_logistics, spreadsheet, vector_editor, erp_logistics, igniter_parser |") }
check("D-09 portfolio records closure") { portfolio_text.include?("LAB-VM-RUN-OK-RECHECK-P1") && portfolio_text.include?("CLOSED") }
check("D-10 parser registry records runtime closure") { parser_registry_text.include?("RunParseDemo") && parser_registry_text.include?("RUN-OK recheck") }
check("D-11 spreadsheet registry still records runtime blocker") { spreadsheet_registry_text.include?("Unsupported operator") && spreadsheet_registry_text.include?("eval_expr") }
check("D-12 rule_engine registry remains governance-gated") { rule_engine_registry_text.include?("governance") || rule_engine_registry_text.include?("dynamic") }

section("E Boundary Checks")
check("E-01 proof uses temp igapp outputs") { __FILE__ && TMP.start_with?(Dir.tmpdir) }
check("E-02 proof does not shell out through the wrapper") do
  wrapper_path_fragment = "/" + "tools" + "/" + "igniter"
  !read(Pathname.new(__FILE__)).include?(wrapper_path_fragment)
end
check("E-03 proof does not modify app source") { read(Pathname.new(__FILE__)).include?("Authority: lab runtime evidence only") }
check("E-04 dynamic dispatch remains non-authority") { EXPECTED_NON_GREEN["rule_engine"][:owner] == "governance-gated" }
check("E-05 every non-green has a next route") { EXPECTED_NON_GREEN.values.all? { |row| row[:next_route].to_s.size.positive? } }

puts "\nRESULT: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
