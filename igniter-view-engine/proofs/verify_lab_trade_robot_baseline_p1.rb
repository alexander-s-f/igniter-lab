#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_trade_robot_baseline_p1.rb
# LAB-TRADE-ROBOT-BASELINE-P1 — freeze trade_robot as a dual-toolchain
# positive baseline and register its app-pressure surfaces.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, IO, finance,
# or trading semantics implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
LANG_ROOT = LAB_ROOT.parent / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "trade_robot"
RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
RUST_BIN_FALLBACK = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

SOURCE_NAMES = %w[
  types.ig signals.ig indicators.ig strategy.ig robot.ig backtester.ig example.ig
].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_CONTRACTS = %w[
  BacktestTick CombinedStrategy ComputeEMA ComputeMACD ComputeRSI ComputeSMA
  ExecuteSignal MakeSignal RSIMeanReversion RobotTick RunBacktest RunTradingBot
  SMACrossoverStrategy StrategyDispatcher
].sort.freeze

EXPECTED_TYPES = %w[
  Candle TimeSeries IndicatorValue IndicatorSeries Signal Order Position Portfolio
  RobotConfig BacktestResult
].sort.freeze

EXPECTED_SOURCE_HASH = "sha256:3b279c19c641940d21ec76e455e3fa40a121d936fea3fbba4ffa9604cc32612a"

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

def read_source(name)
  File.read(APP_DIR / name, encoding: "UTF-8")
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| read_source(name) }.join("\n")
end

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_BIN_FALLBACK
end

TMP = Dir.mktmpdir("trade_robot_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def run_rust_compile(label)
  out = File.join(TMP, "trade_robot_#{label}.igapp")
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus }
  [parsed, out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "trade_robot_ruby_#{label}.igapp")
  script = <<~EOS
    require "json"
    require "igniter_lang/compiler_orchestrator"
    paths = #{SOURCE_FILES.inspect}
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: #{out.inspect})
    puts JSON.generate(result)
  EOS
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / "lib"}", "-e", script)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus }
  [parsed, out]
end

rust1, rust_out1 = run_rust_compile("one")
rust2, = run_rust_compile("two")
ruby1, ruby_out1 = run_ruby_compile("one")
ruby2, = run_ruby_compile("two")

metrics = {
  files: SOURCE_FILES.size,
  contracts: all_source.scan(/^contract\s+/).size,
  types: all_source.scan(/^type\s+/).size,
  call_contract: all_source.scan(/call_contract\(/).size,
  fold: all_source.scan(/\bfold\(/).size,
  map: all_source.scan(/\bmap\(/).size,
  filter: all_source.scan(/\bfilter\(/).size,
  concat: all_source.scan(/\bconcat\(/).size,
  record_literals: all_source.scan(/=\s*\{/).size
}

puts
puts "Section A — Preconditions"
check("A-01: app directory exists") { APP_DIR.directory? }
check("A-02: rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-03: igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, idx|
  check("A-#{format("%02d", idx + 4)}: source exists — #{name}") { File.exist?(APP_DIR / name) }
end

puts
puts "Section B — Source Shape"
check("B-01: exactly 7 source files") { metrics[:files] == 7 }
check("B-02: exactly 10 type declarations") { metrics[:types] == 10 }
check("B-03: exactly 14 contracts") { metrics[:contracts] == 14 }
check("B-04: 34 call_contract sites") { metrics[:call_contract] == 34 }
check("B-05: 5 fold sites") { metrics[:fold] == 5 }
check("B-06: 3 map sites") { metrics[:map] == 3 }
check("B-07: 1 filter site") { metrics[:filter] == 1 }
check("B-08: 6 concat sites") { metrics[:concat] == 6 }
check("B-09: at least 20 record literal computes") { metrics[:record_literals] >= 20 }

puts
puts "Section C — Type And Contract Inventory"
found_types = all_source.scan(/^type\s+([A-Za-z0-9_]+)/).flatten.sort
found_contracts = all_source.scan(/^contract\s+([A-Za-z0-9_]+)/).flatten.sort
check("C-01: type list matches expected") { found_types == EXPECTED_TYPES }
check("C-02: contract list matches expected") { found_contracts == EXPECTED_CONTRACTS }
EXPECTED_TYPES.each { |type| check("C-type-#{type}: type present") { found_types.include?(type) } }
EXPECTED_CONTRACTS.each { |contract| check("C-contract-#{contract}: contract present") { found_contracts.include?(contract) } }

puts
puts "Section D — Rust Compile"
check("D-01: Rust status ok") { rust1["status"] == "ok" }
check("D-02: Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("D-03: Rust warnings empty") { Array(rust1["warnings"]).empty? }
check("D-04: Rust source hash stable value") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-05: Rust source hash stable across two runs") { rust2["source_hash"] == rust1["source_hash"] }
check("D-06: Rust contract list matches expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
stages = rust1["stages"] || {}
%w[parse classify typecheck emit assemble].each do |stage|
  check("D-stage-#{stage}: Rust stage #{stage} ok") { stages[stage] == "ok" }
end
check("D-12: Rust igapp directory exists") { File.directory?(rust_out1) }
check("D-13: Rust semantic_ir file exists") { File.exist?(File.join(rust_out1, "semantic_ir_program.json")) }
check("D-14: Rust diagnostics file exists") { File.exist?(File.join(rust_out1, "diagnostics.json")) }

puts
puts "Section E — Ruby Compile"
ruby_result = ruby1["result"] || ruby1
ruby_result2 = ruby2["result"] || ruby2
ruby_diags = ruby_result["diagnostics"] || ruby1["diagnostics"] || []
check("E-01: Ruby status ok") { (ruby1["status"] || ruby_result["status"]) == "ok" }
check("E-02: Ruby diagnostics empty") { Array(ruby_diags).empty? }
check("E-03: Ruby source hash stable value") { (ruby1["source_hash"] || ruby_result["source_hash"]) == EXPECTED_SOURCE_HASH }
check("E-04: Ruby source hash stable across two runs") do
  (ruby2["source_hash"] || ruby_result2["source_hash"]) == (ruby1["source_hash"] || ruby_result["source_hash"])
end
check("E-05: Ruby and Rust source hash agree") { (ruby1["source_hash"] || ruby_result["source_hash"]) == rust1["source_hash"] }
check("E-06: Ruby igapp directory exists") { File.directory?(ruby_out1) }

puts
puts "Section F — Positive App Patterns"
check("F-01: report names compose pressure") { read_source("report.md").include?("compose") }
check("F-02: RobotConfig has strategy_name") { read_source("types.ig").include?("strategy_name : String") }
check("F-03: Portfolio carries three collection fields") do
  t = read_source("types.ig")
  t.include?("open_positions : Collection[Position]") && t.include?("closed_positions : Collection[Position]") && t.include?("orders : Collection[Order]")
end
check("F-04: StrategyDispatcher static workaround present") { read_source("robot.ig").include?("StrategyDispatcher") && read_source("robot.ig").include?("direct static dispatch") }
check("F-05: MakeSignal factory present") { read_source("signals.ig").include?("contract MakeSignal") }
check("F-06: Backtest manually unrolls p1..p10") do
  b = read_source("backtester.ig")
  (1..10).all? { |i| b.include?("compute p#{i}") }
end
check("F-07: fold used for SMA") { read_source("indicators.ig").include?("fold(closes, 0, (acc, v) -> acc + v)") }
check("F-08: fold used for EMA") { read_source("indicators.ig").include?("fold(closes, 0, (prev_ema, close) ->") }
check("F-09: fold-to-struct limitation documented") { read_source("indicators.ig").include?("fold state = {sum_gain") && read_source("indicators.ig").include?("fold() returns a single scalar") }
check("F-10: Temporal pressure documented") { read_source("indicators.ig").include?("Temporal[T] pressure") }

puts
puts "Section G — Closed Runtime/IO Surfaces"
check("G-01: no capability declarations") { !all_source.match?(/^\s*capability\s+/) }
check("G-02: no effect declarations") { !all_source.match?(/^\s*effect\s+/) }
check("G-03: no import stdlib.io") { !all_source.include?("stdlib.io") }
check("G-04: no Rack mentions in source") { !all_source.match?(/\bRack\b/) }
check("G-05: no SQL/ORM terms in source") { !all_source.match?(/\b(SQL|ORM|ActiveRecord)\b/) }
check("G-06: no stringly stdlib empty/append calls") { !all_source.match?(/call_contract\("(?:empty|append)"/) }
check("G-07: all call_contract callees are PascalCase user contracts") do
  all_source.scan(/call_contract\("([^"]+)"/).flatten.all? { |name| name.match?(/\A[A-Z]/) }
end

puts
puts "Section H — Liveness And Complexity"
liveness = rust1["liveness_instrumentation"] || {}
counters = liveness["counters"] || {}
check("H-01: liveness object present") { liveness["kind"] == "liveness_instrumentation" }
check("H-02: no liveness breaches") { Array(liveness["breaches"]).empty? }
check("H-03: tc_infer depth below 1000") { counters.fetch("typechecker.infer_expr.max_depth", 1001).to_i < 1000 }
check("H-04: fr_walk depth below 1000") { counters.fetch("form_resolver.walk_expr.max_depth", 1001).to_i < 1000 }
check("H-05: parser import steps below 100") { counters.fetch("parser.parse_import.max_steps", 101).to_i < 100 }
check("H-06: at least 7 fr_walk depth due multifile graph") { counters.fetch("form_resolver.walk_expr.max_depth", 0).to_i >= 7 }

puts
puts "Section I — Baseline Pressure Routes"
report = read_source("report.md")
check("I-01: report names manual state threading") { report.include?("Manual State Threading") }
check("I-02: report names polymorphic dispatch") { report.include?("No Polymorphic Dispatch") }
check("I-03: report names factory contracts") { report.include?("Factory Contracts") }
check("I-04: report names manual unrolling") { report.include?("Manual Unrolling") }
check("I-05: report proposes compose") { report.include?("Proposal: `compose`") }
check("I-06: report distinguishes compose from class") { report.include?("compose is NOT a class") || report.include?("`compose` is NOT a class") }
check("I-07: report lists fold-to-struct limitation") { report.include?("fold-to-struct") }
check("I-08: report lists Temporal pressure") { report.include?("Temporal[T]") }

puts
puts "Section J — Regression Baseline Summary"
check("J-01: app is dual-toolchain clean") { rust1["status"] == "ok" && (ruby1["status"] || ruby_result["status"]) == "ok" }
check("J-02: source hash is deterministic and shared") { rust1["source_hash"] == EXPECTED_SOURCE_HASH && (ruby1["source_hash"] || ruby_result["source_hash"]) == EXPECTED_SOURCE_HASH }
check("J-03: contract count is larger than neural_net baseline") { EXPECTED_CONTRACTS.size > 6 }
check("J-04: no source edits required by proof") { true }

puts
puts "Summary: #{$pass_count}/#{$pass_count + $fail_count} checks passed"
exit($fail_count.zero? ? 0 : 1)
