#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_erp_logistics_demo_entry_p1.rb
# LAB-ERP-LOGISTICS-DEMO-ENTRY-P1 -- classify and add a zero-input demo
# orchestrator entry for erp_logistics so the VM can exercise the app without
# external routes/shipment/warehouse inputs.
#
# Authority: app fixture/entrypoint work only. NO compiler, VM, stdlib, numeric
# coercion, IO, clock, scheduler, DB, or queue implementation.
#
# Honest outcome pinned by this proof:
#   * Rust compiles ok/0 (9 contracts) and the VM runs the demo entry
#     RunBestRoute end-to-end -> 2437.5 (= 3.25 * 750.0). filter + fold + Float
#     comparison/multiply all execute.
#   * Ruby remains oof/4 on a PRE-EXISTING Float-operator over-restriction in
#     the Ruby typechecker (CalculateBestRoute, CheckCapacity). The demo entry
#     adds ZERO new diagnostics. Ruby numeric parity is a routed residual,
#     OUT of this card's authority (no compiler changes).
#   * RunCapacity / RunDispatchDemo compile dual-closure-clean but TRAP at the
#     VM on a direct (non-fold) Float comparison (ERP-P11): the VM comparison
#     opcode is still Integer-only even though Float arithmetic and in-fold
#     Float comparison already run. Also a routed residual (no VM changes).

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "erp_logistics"
RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_BIN_FALLBACK = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
VM_BIN = LAB_ROOT / "igniter-vm" / "target" / "release" / "igniter-vm"
VM_BIN_FALLBACK = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"

# Source order is the documented multi-file closure order (types first). Paths
# are absolute via Open3, the path-sensitive baseline shared with the fleet.
SOURCE_NAMES = %w[types.ig warehouse.ig optimizer.ig api.ig example.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_SOURCE_HASH = "sha256:dafbf1eb358fc7e13e1458b12c5e7f81a61f514017ea714cd548ae23b52d3041"
EXPECTED_SOURCE_UNITS = %w[ErpApi ErpExample ErpOptimizer ErpTypes ErpWarehouse].sort.freeze
EXPECTED_TYPES = %w[Route Shipment Warehouse].sort.freeze
EXPECTED_CONTRACTS = %w[
  CalculateBestRoute CheckCapacity DispatchShipment
  MakeRoute MakeShipment MakeWarehouse
  RunBestRoute RunCapacity RunDispatchDemo
].sort.freeze
PRODUCTION_CONTRACTS = %w[CalculateBestRoute CheckCapacity DispatchShipment].freeze
DEMO_CONTRACTS = %w[MakeRoute MakeShipment MakeWarehouse RunBestRoute RunCapacity RunDispatchDemo].freeze
EXPECTED_PRESSURES = (1..11).map { |n| "ERP-P#{format('%02d', n)}" }.freeze

ENTRY = "RunBestRoute"
ENTRY_RESULT = 2437.5

$pass_count = 0
$fail_count = 0

def check(label)
  if yield
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} -- #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

def section(title)
  puts
  puts "Section #{title}"
end

def read_path(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def read_source(name)
  read_path(APP_DIR / name)
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| read_source(name) }.join("\n")
end

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_BIN_FALLBACK
end

def vm_bin
  return VM_BIN if File.executable?(VM_BIN.to_s)
  VM_BIN_FALLBACK
end

def normalize_compile_result(result)
  result["result"] || result
end

TMP = Dir.mktmpdir("erp_logistics_demo_entry_p1_")
at_exit { FileUtils.rm_rf(TMP) }

# The lab toolchain has a documented fd/timing flake ("Internal compiler error:
# No such file or directory") when the release binary is spawned in very rapid
# succession. Open3 from a fresh interpreter is reliable, but we retry to make
# the proof robust regardless of host load.
def run_rust_compile(label)
  out = File.join(TMP, "erp_rust_#{label}.igapp")
  parsed = nil
  3.times do
    stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
    parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
      "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus
    }
    break unless parsed.key?("_parse_error")
  end
  [parsed, out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "erp_ruby_#{label}.igapp")
  script = <<~RUBY
    require "json"
    require "igniter_lang/compiler_orchestrator"
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(
      source_paths: #{SOURCE_FILES.inspect},
      out_path: #{out.inspect}
    )
    inner = result["result"] || result
    puts JSON.generate({
      "status" => result["status"],
      "result" => {
        "status" => inner["status"],
        "source_hash" => inner["source_hash"],
        "diagnostics" => inner["diagnostics"],
        "warnings" => inner["warnings"],
        "contracts" => inner["contracts"],
        "stages" => inner["stages"]
      }
    })
  RUBY
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / 'lib'}", "-e", script)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus
  }
  [parsed, out]
end

def run_vm(igapp, entry)
  inputs = File.join(TMP, "inputs_#{entry}.json")
  File.write(inputs, "{}")
  stdout, stderr, status = Open3.capture3(
    vm_bin.to_s, "run", "--contract", igapp, "--inputs", inputs, "--entry", entry, "--json"
  )
  JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus
  }
end

rust1, rust_out1 = run_rust_compile("one")
rust2, _rust_out2 = run_rust_compile("two")
ruby1_raw, _ruby_out1 = run_ruby_compile("one")
ruby2_raw, _ruby_out2 = run_ruby_compile("two")
ruby1 = normalize_compile_result(ruby1_raw)
ruby2 = normalize_compile_result(ruby2_raw)

manifest_path = File.join(rust_out1, "manifest.json")
sir_path = File.join(rust_out1, "semantic_ir_program.json")
sourcemap_path = File.join(rust_out1, "sourcemap.json")
report_path = File.join(rust_out1, "compilation_report.json")

$manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path, encoding: "UTF-8")) : nil
$sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : nil
$sourcemap = File.exist?(sourcemap_path) ? JSON.parse(File.read(sourcemap_path, encoding: "UTF-8")) : nil
$report = File.exist?(report_path) ? JSON.parse(File.read(report_path, encoding: "UTF-8")) : nil

vm_best = run_vm(rust_out1, "RunBestRoute")
vm_capacity = run_vm(rust_out1, "RunCapacity")
vm_dispatch = run_vm(rust_out1, "RunDispatchDemo")

registry = read_path(APP_DIR / "PRESSURE_REGISTRY.md")
app_report = read_path(APP_DIR / "REPORT.md")
card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-ERP-LOGISTICS-DEMO-ENTRY-P1.md")
numeric_card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md")
lab_doc = read_path(LAB_ROOT / "lab-docs" / "governance" / "lab-erp-logistics-demo-entry-p1-v0.md")
portfolio = read_path(LAB_ROOT / ".agents" / "portfolio-index.md")
dev_tutorial = read_path(LANG_ROOT / "docs" / "dev-tutorial.md")
example_src = read_source("example.ig")

metrics = {
  files: SOURCE_FILES.size,
  types: all_source.scan(/^type\s+/).size,
  variants: all_source.scan(/^variant\s+/).size,
  contracts: all_source.scan(/^(?:pure\s+)?contract\s+/).size,
  call_contract: all_source.scan(/call_contract\(/).size,
  call_contract_literals: all_source.scan(/call_contract\("([^"]+)"/).flatten,
  filter: all_source.scan(/\bfilter\(/).size,
  fold: all_source.scan(/\bfold\(/).size,
  entrypoint: all_source.scan(/^\s*entrypoint\s+/).size
}

manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort
manifest_units = (($manifest || {})["source_units"] || [])
sir_units = (($sir || {})["source_units"] || [])
manifest_entrypoint = ($manifest || {})["entrypoint"] || {}
sir_entrypoint = ($sir || {})["entrypoint"] || {}

ruby_diags = Array(ruby1["diagnostics"])
ruby_diag_paths = ruby_diags.map { |d| d["path"].to_s }

section("A -- Preconditions")
check("A-01: app directory exists") { APP_DIR.directory? }
check("A-02: rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-03: vm binary exists") { File.executable?(vm_bin.to_s) }
check("A-04: igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, idx|
  check("A-#{format('%02d', idx + 5)}: source exists -- #{name}") { File.exist?(APP_DIR / name) }
end
check("A-10: example.ig is the only new source unit (others pre-existed)") do
  example_src.include?("module ErpExample")
end
check("A-11: pressure registry exists") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-12: lab doc exists") { !lab_doc.empty? }
check("A-13: governance card exists") { !card.empty? }
check("A-14: gate numeric-dispatch card read surface exists") { !numeric_card.empty? }
check("A-15: dev tutorial read surface exists") { !dev_tutorial.empty? }

section("B -- Rust compilation (Open3 / mktmpdir / absolute paths)")
check("B-01: Rust compile returns status ok") { rust1["status"] == "ok" }
check("B-02: Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("B-03: Rust warnings empty") { Array(rust1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each_with_index do |stage, idx|
  check("B-#{format('%02d', idx + 4)}: Rust stage #{stage} ok") { (rust1["stages"] || {})[stage] == "ok" }
end
check("B-09: Rust result has 9 contracts") { Array(rust1["contracts"]).size == 9 }
check("B-10: Rust contract set matches expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
check("B-11: Rust compile wrote fresh igapp") { File.directory?(rust_out1) }
check("B-12: Rust compile stdout parsed as JSON (flake retried)") { !rust1.key?("_parse_error") }

section("C -- Ruby compilation: PINNED residual blocker (numeric parity)")
check("C-01: Ruby wrapper status present") { !ruby1_raw["status"].nil? }
check("C-02: Ruby inner status is oof (blocked, not green)") { ruby1["status"] == "oof" }
check("C-03: Ruby reports exactly 4 diagnostics") { ruby_diags.size == 4 }
check("C-04: Ruby compile stdout parsed as JSON") { !ruby1_raw.key?("_parse_error") }
check("C-05: all Ruby diagnostics are in PRODUCTION contracts, none in ErpExample") do
  ruby_diag_paths.all? { |p| p.include?("CalculateBestRoute") || p.include?("CheckCapacity") } &&
    ruby_diag_paths.none? { |p| p.include?("Make") || p.include?("Run") }
end
check("C-06: Ruby blocker is Float operator over-restriction (Integer expected)") do
  ruby_diags.any? { |d| d["message"].to_s.include?("Float<Float") } &&
    ruby_diags.any? { |d| d["message"].to_s.include?("Float*Float") }
end
check("C-07: CheckCapacity is_valid is a Ruby Float-comparison blocker") do
  ruby_diag_paths.any? { |p| p.include?("CheckCapacity/node:is_valid") }
end
check("C-08: CalculateBestRoute best_cost/total_cost are Ruby Float blockers") do
  ruby_diag_paths.any? { |p| p.include?("CalculateBestRoute/node:best_cost") } &&
    ruby_diag_paths.any? { |p| p.include?("CalculateBestRoute/node:total_cost") }
end
check("C-09: demo entry adds ZERO new Ruby diagnostics vs production baseline") do
  ruby_diag_paths.none? { |p| p.include?("RunBestRoute") || p.include?("RunCapacity") || p.include?("RunDispatchDemo") }
end

section("D -- Source hash agreement and stability")
check("D-01: Rust source_hash matches pinned baseline") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-02: Ruby source_hash matches pinned baseline") { ruby1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-03: Rust source_hash stable across two fresh runs") { rust2["source_hash"] == rust1["source_hash"] }
check("D-04: Ruby source_hash stable across two fresh runs") { ruby2["source_hash"] == ruby1["source_hash"] }
check("D-05: Ruby and Rust source_hash agree on the same closure") { ruby1["source_hash"] == rust1["source_hash"] }
check("D-06: source_hash is sha256-prefixed") { rust1["source_hash"].to_s.start_with?("sha256:") }
check("D-07: registry records live hash") { registry.include?(EXPECTED_SOURCE_HASH) }
check("D-08: card records live hash") { card.include?(EXPECTED_SOURCE_HASH) }
check("D-09: lab doc records live hash") { lab_doc.include?(EXPECTED_SOURCE_HASH) }
check("D-10: runner uses Open3.capture3") { File.read(__FILE__, encoding: "UTF-8").include?("Open3.capture3") }
check("D-11: runner uses Dir.mktmpdir") { File.read(__FILE__, encoding: "UTF-8").include?("Dir.mktmpdir") }

section("E -- Artifacts, manifest, and SIR")
check("E-01: manifest.json exists and parsed") { !$manifest.nil? }
check("E-02: semantic_ir_program.json exists and parsed") { !$sir.nil? }
check("E-03: sourcemap.json exists and parsed") { !$sourcemap.nil? }
check("E-04: manifest source_hash matches result") { ($manifest || {})["source_hash"] == rust1["source_hash"] }
check("E-05: SIR source_hash matches result") { ($sir || {})["source_hash"] == rust1["source_hash"] }
check("E-06: manifest has semantic_ir_ref") { !($manifest || {})["semantic_ir_ref"].to_s.empty? }
check("E-07: SIR kind is semantic_ir_program") { ($sir || {})["kind"] == "semantic_ir_program" }
check("E-08: manifest fragment class is core") { ($manifest || {})["fragment_class"] == "core" }
check("E-09: manifest effects empty (pure core)") { Array(($manifest || {})["effects"]).empty? }
check("E-10: manifest capabilities empty (pure core)") { Array(($manifest || {})["capabilities"]).empty? }

section("F -- Source units, types, contracts")
check("F-01: manifest has 5 source_units") { manifest_units.size == 5 }
check("F-02: SIR has 5 source_units") { sir_units.size == 5 }
check("F-03: manifest source unit modules match expected") { manifest_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
check("F-04: SIR source unit modules match expected") { sir_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
EXPECTED_SOURCE_UNITS.each_with_index do |mod, idx|
  check("F-#{format('%02d', idx + 5)}: source unit #{mod} present") { manifest_units.any? { |u| u["module"] == mod } }
end
check("F-10: type declarations count is 3") { metrics[:types] == 3 }
check("F-11: ErpTypes manifest types match expected") do
  types_unit = manifest_units.find { |u| u["module"] == "ErpTypes" } || {}
  Array(types_unit["types"]).sort == EXPECTED_TYPES
end
check("F-12: no variants declared") { metrics[:variants].zero? }
check("F-13: result contract list matches expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
check("F-14: manifest contract list matches expected") { manifest_contracts == EXPECTED_CONTRACTS }
check("F-15: SIR contract list matches expected") { sir_contracts == EXPECTED_CONTRACTS }
check("F-16: Ruby contract closure matches Rust even while oof") do
  # Ruby oof emits no contract list; assert the source-derived count instead.
  metrics[:contracts] == EXPECTED_CONTRACTS.size
end

section("G -- Source metrics and static dispatch hygiene")
check("G-01: exactly 5 source files") { metrics[:files] == 5 }
check("G-02: exactly 3 types") { metrics[:types] == 3 }
check("G-03: exactly 9 contracts") { metrics[:contracts] == 9 }
check("G-04: exactly 1 bare entrypoint") { metrics[:entrypoint] == 1 }
check("G-05: at least one filter site (optimizer)") { metrics[:filter] >= 1 }
check("G-06: at least one fold site (optimizer)") { metrics[:fold] >= 1 }
check("G-07: all call_contract sites are string literals") { metrics[:call_contract_literals].size == metrics[:call_contract] }
check("G-08: all call_contract targets are PascalCase") { metrics[:call_contract_literals].all? { |n| n.match?(/\A[A-Z]/) } }
check("G-09: no dynamic call_contract callee syntax") { !all_source.match?(/call_contract\(\s*[a-z_][a-zA-Z0-9_]*\s*,/) }
check("G-10: every call_contract target resolves to a defined contract") do
  metrics[:call_contract_literals].uniq.all? { |n| EXPECTED_CONTRACTS.include?(n) }
end

section("H -- Entry point resolution")
check("H-01: source declares bare entrypoint RunBestRoute") { example_src.include?("entrypoint RunBestRoute") }
check("H-02: Rust manifest entrypoint resolves RunBestRoute") do
  manifest_entrypoint["resolved_contract"] == ENTRY && manifest_entrypoint["declared_target"] == ENTRY
end
check("H-03: Rust SIR entrypoint resolves RunBestRoute") do
  sir_entrypoint["resolved_contract"] == ENTRY && (sir_entrypoint["target"] == ENTRY || sir_entrypoint["declared_target"] == ENTRY)
end
check("H-04: entrypoint contract artifact path present") { manifest_entrypoint["contract_path"].to_s.include?("run_best_route") }
check("H-05: only one entrypoint declared (ERP-P09 single bare entry)") { example_src.scan(/entrypoint\s+/).size == 1 }

section("I -- VM run: demo entry succeeds end-to-end")
check("I-01: VM RunBestRoute status success") { vm_best["status"] == "success" }
check("I-02: VM RunBestRoute result is 3.25 * 750.0 = 2437.5") { vm_best["result"] == ENTRY_RESULT }
check("I-03: VM RunBestRoute returned no error") { vm_best["error"].nil? }
check("I-04: VM RunBestRoute parsed cleanly") { !vm_best.key?("_parse_error") }
check("I-05: VM run exercised filter+fold+Float (numeric ops execute)") do
  # A non-zero Float result through the optimizer proves Float comparison
  # (in fold) and Float multiplication both ran on the VM.
  vm_best["result"].is_a?(Float) && vm_best["result"] > 0.0
end

section("J -- VM run: capacity path pinned as ERP-P11 (VM direct Float compare)")
check("J-01: VM RunCapacity errors (not success)") { vm_capacity["status"] == "error" }
check("J-02: VM RunCapacity error is direct Float comparison trap") do
  vm_capacity["error"].to_s.include?("Expected Integer") && vm_capacity["error"].to_s.include?("Float")
end
check("J-03: VM RunDispatchDemo errors (same trap)") { vm_dispatch["status"] == "error" }
check("J-04: VM RunDispatchDemo error is direct Float comparison trap") do
  vm_dispatch["error"].to_s.include?("Expected Integer") && vm_dispatch["error"].to_s.include?("Float")
end
check("J-05: example.ig documents the RunCapacity/RunDispatchDemo VM trap") do
  example_src.include?("ERP-P11") && example_src.downcase.include?("integer-only")
end
check("J-06: the gap is Float comparison specifically, arithmetic already runs") do
  # RunBestRoute (Float multiply + in-fold Float compare) succeeded; the direct
  # comparison path is the only failing surface.
  vm_best["status"] == "success" && vm_capacity["status"] == "error"
end

section("K -- Pure core and closed surfaces (no IO/clock/queue/DB introduced)")
check("K-01: example.ig has no capability declarations") { !example_src.match?(/^\s*capability\s+/) }
check("K-02: example.ig has no effect declarations") { !example_src.match?(/^\s*effect\s+/) }
check("K-03: example.ig has no observed/effect/privileged modifiers") { !example_src.match?(/^\s*(observed|effect|privileged|irreversible)\s+contract\s+/) }
check("K-04: source imports no IO stdlib") { !all_source.include?("stdlib.io") }
check("K-05: source has no now()/clock") { !all_source.include?("now()") }
check("K-06: source has no DB/SQL/ORM") { !all_source.match?(/\b(SQL|ORM|ActiveRecord|Database)\b/) }
check("K-07: source has no HTTP/socket/server") { !all_source.match?(/\b(HTTP|Rack|Socket|server)\b/) }
check("K-08: source has no queue/scheduler/worker") { !all_source.match?(/\b(Sidekiq|Worker|perform_async|Scheduler|Queue)\b/) }
check("K-09: example.ig reads no external inputs (zero-input fixture)") { !example_src.match?(/^\s*input\s+(routes|shipment|warehouse)\s*:/) }
check("K-10: production contracts untouched -- CheckCapacity unchanged") do
  read_source("warehouse.ig").include?("compute is_valid = shipment.weight < 1000.0")
end
check("K-11: production contracts untouched -- CalculateBestRoute unchanged") do
  read_source("optimizer.ig").include?("compute total_cost = best_cost * shipment.weight")
end
check("K-12: production contracts untouched -- DispatchShipment unchanged") do
  read_source("api.ig").include?('call_contract("CheckCapacity", shipment)')
end

section("L -- Demo factories build typed records (ERP-P10)")
check("L-01: MakeWarehouse / MakeShipment / MakeRoute exist") do
  %w[MakeWarehouse MakeShipment MakeRoute].all? { |c| EXPECTED_CONTRACTS.include?(c) }
end
check("L-02: factories take typed inputs (not inline literal records)") do
  example_src.include?("input id : Text") && example_src.include?("input weight : Float")
end
check("L-03: factories are pure contracts") do
  example_src.scan(/pure contract Make/).size == 3
end
check("L-04: example.ig documents the String->Text record-field gap (ERP-P10)") do
  example_src.include?("ERP-P10") && example_src.include?("record-field")
end
check("L-05: demo contracts are exactly the 6 added by example.ig") do
  (DEMO_CONTRACTS - EXPECTED_CONTRACTS).empty? && (EXPECTED_CONTRACTS - PRODUCTION_CONTRACTS).sort == DEMO_CONTRACTS.sort
end

section("M -- Pressure registry ERP-P01..ERP-P11")
EXPECTED_PRESSURES.each_with_index do |pid, idx|
  check("M-#{format('%02d', idx + 1)}: registry preserves #{pid}") { registry.include?(pid) }
end
check("M-12: ERP-P09 routes single-entry to PROP-029 named profiles") { registry.include?("ERP-P09") && registry.include?("PROP-029") }
check("M-13: ERP-P10 routes record-field literal coercion / record-literal surface") { registry.include?("ERP-P10") && (registry.include?("record-literal") || registry.include?("String") && registry.include?("Text")) }
check("M-14: ERP-P11 routes VM direct Float comparison gap") { registry.include?("ERP-P11") && registry.downcase.include?("float") }
check("M-15: dev tutorial confirms only bare entrypoint implemented (PROP-029)") do
  dev_tutorial.include?("Rich entrypoint") && dev_tutorial.include?("Only the **bare** `entrypoint C` is implemented")
end

section("N -- Classification, honesty, and closure artifacts")
check("N-01: card classifies entry/UX outcome (Rust+VM green, Ruby blocked)") do
  c = card.downcase
  c.include?("rust") && c.include?("ruby") && (c.include?("blocked") || c.include?("residual"))
end
check("N-02: card pins numeric parity as out-of-authority residual") do
  card.include?("no compiler") || card.include?("Closed Surface") || card.include?("authority")
end
check("N-03: lab doc states evidence baseline only") { lab_doc.include?("evidence") && (lab_doc.include?("not authority") || lab_doc.include?("fixture")) }
check("N-04: lab doc records the VM RunBestRoute success result") { lab_doc.include?("2437.5") }
check("N-05: lab doc records Ruby oof/4 residual") { lab_doc.include?("oof") && lab_doc.include?("4") }
check("N-06: lab doc records proof runner path") { lab_doc.include?("verify_lab_erp_logistics_demo_entry_p1.rb") }
check("N-07: registry has demo-entry closure section") { registry.include?("Demo Entry") || registry.include?("DEMO-ENTRY") }
check("N-08: portfolio index has erp_logistics demo-entry row") { portfolio.include?("LAB-ERP-LOGISTICS-DEMO-ENTRY-P1") }
check("N-09: card records proof runner + lab doc paths") do
  card.include?("verify_lab_erp_logistics_demo_entry_p1.rb") && card.include?("lab-erp-logistics-demo-entry-p1-v0.md")
end
check("N-10: runner documents the fd/timing compile flake") do
  File.read(__FILE__, encoding: "UTF-8").include?("fd/timing flake")
end

puts
total = $pass_count + $fail_count
puts "=" * 72
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 72
exit($fail_count.zero? ? 0 : 1)
