#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_job_runner_baseline_p1.rb
# LAB-JOB-RUNNER-BASELINE-P1 -- freeze job_runner as a positive
# dual-toolchain baseline and pressure source.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, IO,
# Redis, queue, scheduler, worker daemon, clock, retry dispatch,
# managed-loop, ServiceLoop, or app source implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"
require "timeout"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "job_runner"
RUST_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

SOURCE_NAMES = %w[types.ig jobs.ig engine.ig example.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_SOURCE_HASH = "sha256:546c30b56c9b79d4b8bf1fbc396bb2252aec0b6ae58ac85bd7e7708932c3b91c"
REGISTRY_PRIOR_HASH = "sha256:06f8e6d73f4476009011fd6980d0eca86ee3821adb058916ff2e393478d71225"
EXPECTED_MODULES = %w[JobRunnerEngine JobRunnerExample JobRunnerJobs JobRunnerTypes].sort.freeze
EXPECTED_TYPES = %w[JobRequest JobReceipt].sort.freeze
EXPECTED_VARIANTS = {
  "JobOutcome" => %w[Done Retry Exhausted DeadLetter]
}.freeze
EXPECTED_CONTRACTS = %w[
  AttemptOutcome BuildReceipt ComputeReportJob DispatchJob KnownJob MakeReq
  OutcomeAttempts OutcomeResult OutcomeStatus ProcessOrderJob RetryBudget
  RunDeadLetter RunExhausted RunReceipt RunSuccessFirst RunSuccessSecond
  RunWithRetry3 ShouldRetry ValidatePaymentJob
].sort.freeze
EXPECTED_PRESSURES = %w[JR-P01 JR-P02 JR-P03 JR-P04 JR-P05 JR-P06].freeze

$pass_count = 0
$fail_count = 0

def check(label)
  if yield
    $pass_count += 1
    puts "  PASS  #{label}"
  else
    $fail_count += 1
    puts "  FAIL  #{label}"
  end
rescue => e
  $fail_count += 1
  puts "  ERROR #{label} - #{e.class}: #{e.message.lines.first&.strip}"
end

def section(title)
  puts
  puts "-- #{title}"
end

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def source(name)
  read(APP_DIR / name)
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| source(name) }.join("\n")
end

def code_source
  @code_source ||= all_source.lines
    .reject { |line| line.strip.start_with?("--") }
    .map { |line| line.sub(/\s+--.*$/, "") }
    .join
end

def rust_bin
  return RUST_RELEASE if File.executable?(RUST_RELEASE.to_s)
  RUST_DEBUG
end

def capture_with_timeout(*cmd, timeout_seconds: 30)
  stdout = +""
  stderr = +""
  status = nil
  timed_out = false

  Open3.popen3(*cmd) do |stdin, out, err, wait_thr|
    stdin.close
    begin
      Timeout.timeout(timeout_seconds) do
        stdout = out.read
        stderr = err.read
        status = wait_thr.value
      end
    rescue Timeout::Error
      timed_out = true
      begin
        Process.kill("TERM", wait_thr.pid)
      rescue Errno::ESRCH
      end
      sleep 0.2
      begin
        Process.kill("KILL", wait_thr.pid) unless wait_thr.value
      rescue Errno::ESRCH
      end
      stdout = out.read rescue stdout
      stderr = err.read rescue stderr
      status = wait_thr.value rescue nil
    end
  end

  [stdout, stderr, status, timed_out]
end

def parse_json(stdout, stderr = "", status = nil, timed_out = false)
  JSON.parse(stdout.force_encoding("UTF-8"))
rescue
  { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status&.exitstatus, "_timed_out" => timed_out }
end

def result_body(result)
  result["result"] || result
end

TMP = Dir.mktmpdir("job_runner_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def run_rust_compile(label)
  out = File.join(TMP, "job_runner_rust_#{label}.igapp")
  stdout, stderr, status, timed_out = capture_with_timeout(
    rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out, timeout_seconds: 30
  )
  [parse_json(stdout, stderr, status, timed_out), out, timed_out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "job_runner_ruby_#{label}.igapp")
  script = <<~RUBY
    require "json"
    require "igniter_lang/compiler_orchestrator"
    paths = #{SOURCE_FILES.inspect}
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: #{out.inspect})
    puts JSON.generate(result)
  RUBY
  stdout, stderr, status, timed_out = capture_with_timeout(
    "ruby", "-I#{LANG_ROOT / 'lib'}", "-e", script, timeout_seconds: 30
  )
  [parse_json(stdout, stderr, status, timed_out), out, timed_out]
end

def load_json(path)
  return nil unless File.exist?(path)
  JSON.parse(File.read(path, encoding: "UTF-8"))
end

rust1, rust_out1, rust_timeout1 = run_rust_compile("one")
rust2, rust_out2, rust_timeout2 = run_rust_compile("two")
ruby1_raw, ruby_out1, ruby_timeout1 = run_ruby_compile("one")
ruby2_raw, ruby_out2, ruby_timeout2 = run_ruby_compile("two")
ruby1 = result_body(ruby1_raw)
ruby2 = result_body(ruby2_raw)

manifest = load_json(File.join(rust_out1, "manifest.json")) || {}
sir = load_json(File.join(rust_out1, "semantic_ir_program.json")) || {}
sourcemap = load_json(File.join(rust_out1, "sourcemap.json")) || {}
report = load_json(File.join(rust_out1, "compilation_report.json")) || {}
ruby_manifest = load_json(File.join(ruby_out1, "manifest.json")) || {}

registry = read(APP_DIR / "PRESSURE_REGISTRY.md")
card = read(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-JOB-RUNNER-BASELINE-P1.md")
lab_doc = read(LAB_ROOT / "lab-docs" / "governance" / "lab-job-runner-baseline-v0.md")
portfolio = read(LAB_ROOT / ".agents" / "portfolio-index.md")
dynamic_dispatch_card = read(LAB_ROOT / ".agents" / "work" / "cards" / "lab" / "LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md")
sumtype_p1 = read(LANG_ROOT / ".agents" / "work" / "proposals" / "LANG-SUMTYPE-CONSTRUCT-MATCH-P1-sumtype-v0.md")
sumtype_p2 = read(LANG_ROOT / ".agents" / "work" / "proposals" / "LANG-SUMTYPE-CONSTRUCT-MATCH-P2-sumtype-planning-v0.md")
prop039 = read(LANG_ROOT / ".agents" / "work" / "proposals" / "PROP-039-managed-local-recursion-and-loop-classes-v0.md")

metrics = {
  files: SOURCE_FILES.size,
  types: code_source.scan(/^type\s+/).size,
  variants: code_source.scan(/^variant\s+/).size,
  contracts: code_source.scan(/^(?:pure\s+)?contract\s+/).size,
  textual_call_contract: all_source.scan(/call_contract\(/).size,
  code_call_contract: code_source.scan(/call_contract\(/).size,
  textual_match: all_source.scan(/\bmatch\s+/).size,
  code_match: code_source.scan(/\bmatch\s+/).size,
  entrypoint: code_source.scan(/^entrypoint\s+/).size,
  loop_forms: code_source.scan(/^\s*loop\s+/).size
}

type_names = code_source.scan(/^type\s+([A-Za-z0-9_]+)/).flatten.sort
variant_names = code_source.scan(/^variant\s+([A-Za-z0-9_]+)/).flatten.sort
contract_names = code_source.scan(/^(?:pure\s+)?contract\s+([A-Za-z0-9_]+)/).flatten.sort
call_callees = code_source.scan(/call_contract\(\s*"([^"]+)"/m).flatten
nonliteral_calls = code_source.scan(/call_contract\((?!\s*")/m)
match_subjects = code_source.scan(/\bmatch\s+([A-Za-z0-9_.]+)\s*\{/).flatten
manifest_units = Array(manifest["source_units"])
sir_units = Array(sir["source_units"])
variant_decls = Array(sir["variant_declarations"])
sir_contracts = Array(sir["contracts"])
manifest_entrypoint = manifest["entrypoint"] || {}
sir_entrypoint = sir["entrypoint"] || {}
liveness = rust1["liveness_instrumentation"] || {}
counters = liveness["counters"] || {}

puts "LAB-JOB-RUNNER-BASELINE-P1"

section("A: Preconditions")
check("A-01 app directory exists") { APP_DIR.directory? }
check("A-02 igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
check("A-03 Rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-04 runner uses absolute app source paths") { SOURCE_FILES.all? { |path| path.start_with?(WS_ROOT.to_s) } }
SOURCE_NAMES.each_with_index do |name, index|
  check("A-#{format('%02d', index + 5)} source file exists: #{name}") { File.exist?(APP_DIR / name) }
end
check("A-09 pressure registry exists") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-10 governance card exists") { !card.empty? }
check("A-11 lab doc exists") { !lab_doc.empty? }
check("A-12 dynamic dispatch policy card exists") { !dynamic_dispatch_card.empty? }
check("A-13 PROP-039 proposal exists") { !prop039.empty? }
check("A-14 sumtype P1 proposal exists") { !sumtype_p1.empty? }
check("A-15 sumtype P2 proposal exists or route is documented elsewhere") { !sumtype_p2.empty? || registry.include?("LANG-SUMTYPE-CONSTRUCT-MATCH") }

section("B: Source Metrics")
check("B-01 exactly 4 source files") { metrics[:files] == 4 }
check("B-02 exactly 2 type declarations") { metrics[:types] == 2 }
check("B-03 exactly 1 variant declaration") { metrics[:variants] == 1 }
check("B-04 exactly 19 contracts") { metrics[:contracts] == 19 }
check("B-05 exactly 26 textual call_contract mentions") { metrics[:textual_call_contract] == 26 }
check("B-06 exactly 25 executable call_contract forms") { metrics[:code_call_contract] == 25 }
check("B-07 exactly 4 textual match mentions") { metrics[:textual_match] == 4 }
check("B-08 exactly 4 executable match expressions") { metrics[:code_match] == 4 }
check("B-09 exactly 1 bare entrypoint") { metrics[:entrypoint] == 1 }
check("B-10 no source loop form in app") { metrics[:loop_forms] == 0 }
check("B-11 types match expected") { type_names == EXPECTED_TYPES }
check("B-12 variants match expected") { variant_names == EXPECTED_VARIANTS.keys.sort }
check("B-13 contracts match expected") { contract_names == EXPECTED_CONTRACTS }

section("C: Ruby Compile")
check("C-01 Ruby runner did not time out") { !ruby_timeout1 && !ruby_timeout2 }
check("C-02 Ruby wrapper status ok") { ruby1_raw["status"] == "ok" || ruby1["status"] == "ok" }
check("C-03 Ruby inner status ok") { ruby1["status"] == "ok" }
check("C-04 Ruby diagnostics empty") { Array(ruby1["diagnostics"]).empty? }
check("C-05 Ruby warnings empty") { Array(ruby1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each do |stage|
  check("C-stage #{stage}") { ruby1.dig("stages", stage) == "ok" }
end
check("C-11 Ruby contracts match expected") { Array(ruby1["contracts"]).sort == EXPECTED_CONTRACTS }
check("C-12 Ruby source hash matches absolute baseline") { ruby1["source_hash"] == EXPECTED_SOURCE_HASH }
check("C-13 Ruby source hash stable across fresh runs") { ruby2["source_hash"] == ruby1["source_hash"] }
check("C-14 Ruby igapp directory exists") { File.directory?(ruby_out1) }
check("C-15 Ruby manifest exists") { File.exist?(File.join(ruby_out1, "manifest.json")) }
check("C-16 Ruby manifest entrypoint is RunSuccessSecond") { ruby_manifest.dig("entrypoint", "resolved_contract") == "RunSuccessSecond" }

section("D: Rust Compile")
check("D-01 Rust runner did not time out") { !rust_timeout1 && !rust_timeout2 }
check("D-02 Rust status ok") { rust1["status"] == "ok" }
check("D-03 Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("D-04 Rust warnings empty") { Array(rust1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each do |stage|
  check("D-stage #{stage}") { rust1.dig("stages", stage) == "ok" }
end
check("D-10 Rust contracts match expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
check("D-11 Rust source hash matches absolute baseline") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-12 Rust source hash stable across fresh runs") { rust2["source_hash"] == rust1["source_hash"] }
check("D-13 Rust igapp directory exists") { File.directory?(rust_out1) }
check("D-14 Rust second igapp directory exists") { File.directory?(rust_out2) }
check("D-15 Rust stdout parsed as JSON") { !rust1.key?("_parse_error") }

section("E: Hash and Artifact Stability")
check("E-01 Ruby and Rust source hashes agree") { ruby1["source_hash"] == rust1["source_hash"] }
check("E-02 source hash is sha256-prefixed") { rust1["source_hash"].to_s.start_with?("sha256:") }
check("E-03 prior registry hash differs from absolute-route baseline") { REGISTRY_PRIOR_HASH != EXPECTED_SOURCE_HASH }
check("E-04 registry records live absolute hash") { registry.include?(EXPECTED_SOURCE_HASH) }
check("E-05 card records live absolute hash") { card.include?(EXPECTED_SOURCE_HASH) }
check("E-06 lab doc records live absolute hash") { lab_doc.include?(EXPECTED_SOURCE_HASH) }
check("E-07 registry records prior hash as route-sensitive predecessor") { registry.include?(REGISTRY_PRIOR_HASH) && registry.include?("route-sensitive") }
check("E-08 runner source uses Open3") { read(__FILE__).include?("Open3.popen3") }
check("E-09 runner source uses mktmpdir") { read(__FILE__).include?("Dir.mktmpdir") }
check("E-10 runner source has timeout kill path") { read(__FILE__).include?("Process.kill") && read(__FILE__).include?("Timeout.timeout") }

section("F: Manifest and SIR")
check("F-01 manifest parsed") { !manifest.empty? }
check("F-02 semantic_ir_program parsed") { !sir.empty? }
check("F-03 sourcemap parsed") { !sourcemap.empty? }
check("F-04 compilation_report parsed") { !report.empty? }
check("F-05 diagnostics.json exists") { File.exist?(File.join(rust_out1, "diagnostics.json")) }
check("F-06 manifest source_hash matches result") { manifest["source_hash"] == rust1["source_hash"] }
check("F-07 SIR source_hash matches result") { sir["source_hash"] == rust1["source_hash"] }
check("F-08 report source_hash matches result") { report["source_hash"] == rust1["source_hash"] }
check("F-09 manifest has semantic_ir_ref") { !manifest["semantic_ir_ref"].to_s.empty? }
check("F-10 manifest has sourcemap_ref") { !manifest["sourcemap_ref"].to_s.empty? }
check("F-11 manifest contract_index has 19 entries") { Hash(manifest["contract_index"]).size == 19 }
check("F-12 SIR kind is semantic_ir_program") { sir["kind"] == "semantic_ir_program" }
check("F-13 manifest source_units count is 4") { manifest_units.size == 4 }
check("F-14 SIR source_units count is 4") { sir_units.size == 4 }
check("F-15 manifest module list matches expected") { manifest_units.map { |u| u["module"] }.sort == EXPECTED_MODULES }
check("F-16 SIR module list matches expected") { sir_units.map { |u| u["module"] }.sort == EXPECTED_MODULES }
check("F-17 manifest types are JobRequest/JobReceipt") { manifest_units.flat_map { |u| Array(u["types"]) }.sort == EXPECTED_TYPES }
check("F-18 SIR contracts match expected") { sir_contracts.map { |c| c["contract_name"] }.compact.sort == EXPECTED_CONTRACTS }

section("G: Entry Point")
check("G-01 source declares entrypoint RunSuccessSecond") { source("example.ig").include?("entrypoint RunSuccessSecond") }
check("G-02 manifest entrypoint resolves RunSuccessSecond") { manifest_entrypoint["resolved_contract"] == "RunSuccessSecond" }
check("G-03 manifest declared target is RunSuccessSecond") { manifest_entrypoint["declared_target"] == "RunSuccessSecond" }
check("G-04 SIR entrypoint resolves RunSuccessSecond") { sir_entrypoint["resolved_contract"] == "RunSuccessSecond" || sir_entrypoint["target"] == "RunSuccessSecond" }
check("G-05 RunSuccessFirst scenario present") { contract_names.include?("RunSuccessFirst") }
check("G-06 RunSuccessSecond scenario present") { contract_names.include?("RunSuccessSecond") }
check("G-07 RunExhausted scenario present") { contract_names.include?("RunExhausted") }
check("G-08 RunDeadLetter scenario present") { contract_names.include?("RunDeadLetter") }
check("G-09 RunReceipt scenario present") { contract_names.include?("RunReceipt") }

section("H: Static Dispatch Discipline")
check("H-01 all executable call_contract forms have literal callees") { call_callees.size == metrics[:code_call_contract] }
check("H-02 no executable non-literal call_contract forms") { nonliteral_calls.empty? }
check("H-03 every callee is a known contract") { call_callees.all? { |name| contract_names.include?(name) } }
check("H-04 dispatcher branches on process_order") { source("jobs.ig").include?('job_class == "process_order"') }
check("H-05 dispatcher branches on compute_report") { source("jobs.ig").include?('job_class == "compute_report"') }
check("H-06 dispatcher branches on validate_payment") { source("jobs.ig").include?('job_class == "validate_payment"') }
check("H-07 unknown dispatch path is fail-closed no-op") { source("jobs.ig").include?("0   -- unknown job class") }
check("H-08 KnownJob fail-closed gate exists") { source("jobs.ig").include?("contract KnownJob") && source("jobs.ig").include?("output known : Integer") }
check("H-09 RunWithRetry3 uses KnownJob gate") { source("engine.ig").include?('call_contract("KnownJob"') }
check("H-10 RunWithRetry3 emits DeadLetter for unknown class") { source("engine.ig").include?('DeadLetter { reason: "unknown job class" }') }
check("H-11 dynamic dispatch policy preserves fail-closed") { dynamic_dispatch_card.include?("PRESERVE fail-closed") }
check("H-12 registry routes JR-P02 to dynamic dispatch policy") { registry.include?("JR-P02") && registry.include?("LAB-DYNAMIC-CONTRACT-DISPATCH-P2") }

section("I: JobOutcome Variant Witness")
decl = variant_decls.find { |v| v["name"] == "JobOutcome" } || {}
arms = Array(decl["arms"])
check("I-01 SIR has one variant declaration") { variant_decls.size == 1 }
check("I-02 JobOutcome variant exists") { decl["name"] == "JobOutcome" }
check("I-03 JobOutcome arms match expected") { arms.map { |a| a["name"] } == EXPECTED_VARIANTS["JobOutcome"] }
check("I-04 Done carries result and attempts") { Array(arms.find { |a| a["name"] == "Done" }&.fetch("fields", [])).map { |f| f["name"] }.sort == %w[attempts result] }
check("I-05 Retry carries budget and result") { Array(arms.find { |a| a["name"] == "Retry" }&.fetch("fields", [])).map { |f| f["name"] }.sort == %w[budget result] }
check("I-06 Exhausted carries attempts") { Array(arms.find { |a| a["name"] == "Exhausted" }&.fetch("fields", [])).map { |f| f["name"] } == %w[attempts] }
check("I-07 DeadLetter carries reason") { Array(arms.find { |a| a["name"] == "DeadLetter" }&.fetch("fields", [])).map { |f| f["name"] } == %w[reason] }
check("I-08 AttemptOutcome constructs Done") { source("engine.ig").include?("Done { result: result, attempts: attempt }") }
check("I-09 AttemptOutcome constructs Retry") { source("engine.ig").include?("Retry { budget: budget, result: result }") }
check("I-10 AttemptOutcome constructs Exhausted") { source("engine.ig").include?("Exhausted { attempts: attempt }") }
check("I-11 RunWithRetry3 constructs DeadLetter") { source("engine.ig").include?("DeadLetter { reason:") }
check("I-12 registry marks JR-P01 positive capability") { registry.include?("JR-P01") && registry.include?("POSITIVE") && registry.include?("LANG-SUMTYPE-CONSTRUCT-MATCH") }
check("I-13 sumtype P1 says user variant match is dual-clean") { sumtype_p1.include?("User-`variant` match IS dual-clean") || sumtype_p1.include?("variant_construct") }

section("J: Retry Budget and Manual Unroll")
check("J-01 RetryBudget subtracts attempt from max_attempts") { source("engine.ig").include?("max_attempts - attempt") }
check("J-02 AttemptOutcome calls RetryBudget") { source("engine.ig").include?('call_contract("RetryBudget", attempt, max_attempts)') }
check("J-03 retry condition uses budget > 0") { source("engine.ig").include?("budget > 0") }
check("J-04 RunWithRetry3 has ok1 input") { source("engine.ig").include?("input ok1 : Integer") }
check("J-05 RunWithRetry3 has ok2 input") { source("engine.ig").include?("input ok2 : Integer") }
check("J-06 RunWithRetry3 has ok3 input") { source("engine.ig").include?("input ok3 : Integer") }
check("J-07 attempt 1 is explicit") { source("engine.ig").include?("ok1, 1, req.max_attempts") }
check("J-08 attempt 2 is explicit") { source("engine.ig").include?("ok2, 2, req.max_attempts") }
check("J-09 attempt 3 is explicit") { source("engine.ig").include?("ok3, 3, req.max_attempts") }
check("J-10 ShouldRetry matches JobOutcome") { source("engine.ig").include?("contract ShouldRetry") && source("engine.ig").include?("match o") }
check("J-11 registry routes JR-P03 to PROP-039") { registry.include?("JR-P03") && registry.include?("PROP-039") }
check("J-12 PROP-039 defines BudgetedLocalLoop") { prop039.include?("BudgetedLocalLoop") && prop039.include?("max_steps") }
check("J-13 lab doc records managed-loop as Rust-only/Ruby parity pressure") { lab_doc.include?("Rust-only") && lab_doc.include?("Ruby parity") }

section("K: Receipt Shape")
check("K-01 JobReceipt type exists") { source("types.ig").include?("type JobReceipt") }
check("K-02 JobReceipt has job_id") { source("types.ig").include?("job_id   : String") }
check("K-03 JobReceipt has status") { source("types.ig").include?("status   : String") }
check("K-04 JobReceipt has result") { source("types.ig").include?("result   : Integer") }
check("K-05 JobReceipt has attempts") { source("types.ig").include?("attempts : Integer") }
check("K-06 OutcomeStatus maps done") { source("engine.ig").include?('Done {}       => "done"') }
check("K-07 OutcomeStatus maps retrying") { source("engine.ig").include?('Retry {}      => "retrying"') }
check("K-08 OutcomeStatus maps exhausted") { source("engine.ig").include?('Exhausted {}  => "exhausted"') }
check("K-09 OutcomeStatus maps dead_letter") { source("engine.ig").include?('DeadLetter {} => "dead_letter"') }
check("K-10 BuildReceipt pins JobReceipt output") { source("engine.ig").include?("output receipt : JobReceipt") }
check("K-11 RunReceipt full path exists") { source("example.ig").include?("contract RunReceipt") && source("example.ig").include?('call_contract("BuildReceipt"') }

section("L: Pressure Registry")
EXPECTED_PRESSURES.each { |id| check("L-id #{id} present") { registry.include?(id) } }
check("L-07 JR-P01 routes sealed JobOutcome") { registry.include?("sealed JobOutcome") || registry.include?("sealed sum") }
check("L-08 JR-P02 preserves static dispatch route") { registry.include?("dynamic dispatch avoided") && registry.include?("typed contract registry") }
check("L-09 JR-P03 preserves managed loop parity gap") { registry.include?("managed loop is Rust-only") && registry.include?("OOF-L7") }
check("L-10 JR-P04 marks retry budget positive") { registry.include?("retry budget is explicit arithmetic") && registry.include?("POSITIVE") }
check("L-11 JR-P05 routes queue/worker/scheduler behind ServiceLoop") { registry.include?("No Redis") && registry.include?("ServiceLoop") && registry.include?("PROP-037") }
check("L-12 JR-P06 routes record-literal factories") { registry.include?("record-literal factories") && registry.include?("LANG-RUBY-RECORD-LITERAL-INFERENCE") }
check("L-13 registry has Baseline Closure") { registry.include?("Baseline Closure") && registry.include?("verify_lab_job_runner_baseline_p1.rb") }

section("M: Closed Surfaces")
check("M-01 no capability declarations") { !code_source.match?(/^\s*capability\s+/) }
check("M-02 no effect declarations") { !code_source.match?(/^\s*effect\s+/) }
check("M-03 no observed/effect modifiers") { !code_source.match?(/^\s*(observed|effect|privileged|irreversible)\s+contract\s+/) }
check("M-04 no Redis reference in executable code") { !code_source.match?(/\bRedis\b/) }
check("M-05 no queue implementation in executable code") { !code_source.match?(/\b(enqueue|dequeue|queue)\b/i) }
check("M-06 no worker daemon in executable code") { !code_source.match?(/\b(worker|daemon|perform_async)\b/i) }
check("M-07 no scheduler in executable code") { !code_source.match?(/\b(schedule|scheduler|cron)\b/i) }
check("M-08 no clock now call") { !code_source.match?(/\bnow\(|Time\.current|DateTime\b/) }
check("M-09 no ServiceLoop implementation") { !code_source.match?(/\bServiceLoop\b/) }
check("M-10 no DB/SQL/ORM code") { !code_source.match?(/\b(SQL|ActiveRecord|ORM|SELECT|INSERT|UPDATE)\b/) }
check("M-11 no HTTP/Rack/socket server") { !code_source.match?(/\b(HTTP|Rack|Socket|listen|accept_loop)\b/) }
check("M-12 manifest fragment class is core") { manifest["fragment_class"] == "core" }
check("M-13 manifest effects empty") { Array(manifest["effects"]).empty? }
check("M-14 manifest capabilities empty") { Array(manifest["capabilities"]).empty? }
check("M-15 SIR contracts have empty escape boundaries") { sir_contracts.all? { |c| Array(c["escape_boundaries"]).empty? } }
check("M-16 card preserves closed surfaces") { card.include?("No Redis") && card.include?("No real retry dispatch") && card.include?("No ServiceLoop implementation") }

section("N: Liveness and Harness Safety")
check("N-01 Rust liveness object present") { liveness["kind"] == "liveness_instrumentation" }
check("N-02 liveness breaches empty") { Array(liveness["breaches"]).empty? }
check("N-03 typechecker infer depth below fatal limit") { counters.fetch("typechecker.infer_expr.max_depth", 1001).to_i < 1000 }
check("N-04 form resolver walk depth below fatal limit") { counters.fetch("form_resolver.walk_expr.max_depth", 1001).to_i < 1000 }
check("N-05 parser import max steps below 100") { counters.fetch("parser.parse_import.max_steps", 101).to_i < 100 }
check("N-06 first and second Rust out paths differ") { rust_out1 != rust_out2 }
check("N-07 first and second Ruby out paths differ") { ruby_out1 != ruby_out2 }
check("N-08 runner source does not use shell pipe sentinels") do
  runner = read(__FILE__)
  pipe_to_head = ["|", "head"].join(" ")
  redirect_marker = ["2>", "&1"].join("")
  !runner.include?(pipe_to_head) && !runner.include?(redirect_marker)
end

section("O: Closure Artifacts")
check("O-01 card has closure summary") { card.include?("Closure Summary") && card.include?("CLOSED") }
check("O-02 lab doc records proof runner path") { lab_doc.include?("verify_lab_job_runner_baseline_p1.rb") }
check("O-03 lab doc marks evidence baseline only") { lab_doc.include?("evidence baseline only") }
check("O-04 lab doc records no app source edits") { lab_doc.include?("No app source edits") }
check("O-05 portfolio index has closure row") { portfolio.include?("LAB-JOB-RUNNER-BASELINE-P1 CLOSED") }
check("O-06 card records proof count") { card.include?("PASS") && card.include?("verify_lab_job_runner_baseline_p1.rb") }
check("O-07 registry records proof count") { registry.include?("PASS") && registry.include?("verify_lab_job_runner_baseline_p1.rb") }
check("O-08 card says no app source edits") { card.include?("No app source edits") }

total = $pass_count + $fail_count
puts
puts "=" * 72
puts "RESULT: #{$pass_count}/#{total} PASS / #{$fail_count} FAIL"
puts "=" * 72

if $fail_count.zero? && $pass_count >= 90
  puts "VERDICT: PASS - job_runner positive baseline frozen."
  exit 0
else
  puts "VERDICT: FAIL - job_runner baseline proof did not satisfy gate."
  exit 1
end
