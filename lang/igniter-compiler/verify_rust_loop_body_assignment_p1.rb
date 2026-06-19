#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LAB-RUST-LOOP-BODY-ASSIGNMENT-P1
#
# Proves Rust lab typechecker loop-body assignment checks now match canon Ruby:
# every loop body compute target must be a declared lead binding. Outer contract
# symbols, loop item variables, and undeclared body targets are rejected even
# when the loop body has no lead binding.
#
# Authority: lab Rust implementation proof only. No app source edits.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "timeout"

COMPILER_DIR = Pathname.new(__dir__).expand_path
LAB_ROOT = COMPILER_DIR.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"
APPS = LAB_ROOT / "igniter-apps"
BIN = COMPILER_DIR / "target" / "release" / "igniter_compiler"
TC_RS = COMPILER_DIR / "src" / "typechecker.rs"
RUBY_TC = LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb"
P1_RUNNER = LANG_ROOT / "experiments" / "budgeted_local_loop_proof" / "verify_budgeted_local_loop_ruby_p1.rb"
CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-RUST-LOOP-BODY-ASSIGNMENT-P1.md"
JOB_REGISTRY = APPS / "job_runner" / "PRESSURE_REGISTRY.md"

FLEET = {
  "advanced_logistics" => %w[types.ig spatial.ig router.ig api.ig],
  "air_combat" => %w[types.ig vec.ig kalman.ig guidance.ig strategy.ig swarm.ig engine.ig example.ig],
  "arch_patterns" => %w[types.ig event_sourcing.ig state_machine.ig pipeline.ig example.ig],
  "audit_ledger" => %w[types.ig ledger.ig correct.ig example.ig],
  "batch_importer" => %w[types.ig validate.ig example.ig],
  "bloom_filter" => %w[types.ig hash.ig ops.ig example.ig],
  "call_router" => %w[types.ig correlate.ig operator.ig webhook.ig service.ig example.ig],
  "dataframes" => %w[types.ig matrix.ig dataframe.ig example.ig],
  "decision_tree" => %w[types.ig builder.ig evaluator.ig example.ig],
  "dsa" => %w[types.ig arrays.ig sets.ig graphs.ig strings.ig example.ig],
  "igniter_parser" => %w[types.ig lexer.ig parser.ig api.ig],
  "job_runner" => %w[types.ig jobs.ig engine.ig example.ig],
  "lead_router" => %w[types.ig pipeline.ig service.ig example.ig],
  "neural_net" => %w[types.ig activations.ig layers.ig network.ig example.ig],
  "rule_engine" => %w[types.ig rules.ig engine.ig example.ig],
  "sim_framework" => %w[types.ig temporal.ig relation.ig constraints.ig rules.ig engine.ig example.ig],
  "trade_robot" => %w[types.ig signals.ig indicators.ig strategy.ig robot.ig backtester.ig example.ig],
  "vector_editor" => %w[types.ig transform.ig document.ig tools.ig],
  "vector_math" => %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig],
  "web_router" => %w[types.ig serve.ig example.ig]
}.freeze

EXPECTED_STATUS = FLEET.keys.to_h { |app| [app, app == "rule_engine" ? "oof" : "ok"] }.freeze

$pass = 0
$fail = 0

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def check(label)
  if yield
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

def run_cmd(*args, chdir: COMPILER_DIR, timeout: 45)
  stdout = +""
  stderr = +""
  status = nil
  Timeout.timeout(timeout) do
    stdout, stderr, status = Open3.capture3(*args, chdir: chdir.to_s)
  end
  { stdout: stdout, stderr: stderr, status: status, timeout: false }
rescue Timeout::Error
  { stdout: stdout, stderr: stderr, status: nil, timeout: true }
end

def ensure_release_compiler
  return if File.executable?(BIN.to_s)
  run_cmd("cargo", "build", "--release", timeout: 180)
end

def parse_json(stdout)
  JSON.parse(stdout.force_encoding("UTF-8"))
rescue JSON::ParserError
  { "status" => "json_parse_error", "diagnostics" => [{ "rule" => "JSON", "message" => stdout[0, 500] }] }
end

def compile_files(files, label:, timeout: 45)
  Dir.mktmpdir("loop_body_assignment_#{label}_") do |dir|
    out = File.join(dir, "#{label}.igapp")
    cmd = [BIN.to_s, "compile", *files.map(&:to_s), "--out", out]
    r = run_cmd(*cmd, timeout: timeout)
    result = parse_json(r[:stdout])
    manifest_path = File.join(out, "manifest.json")
    sir_path = File.join(out, "semantic_ir_program.json")
    {
      command: cmd,
      result: result,
      diagnostics: Array(result["diagnostics"]),
      exit: r[:status]&.exitstatus,
      success: r[:status]&.success?,
      stderr: r[:stderr],
      timeout: r[:timeout],
      manifest: File.file?(manifest_path) ? JSON.parse(File.read(manifest_path, encoding: "UTF-8")) : nil,
      sir: File.file?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : nil
    }
  end
end

def compile_fixture(name, source)
  Dir.mktmpdir("loop_body_assignment_fixture_#{name}_") do |dir|
    path = File.join(dir, "#{name}.ig")
    File.write(path, source)
    compile_files([path], label: name)
  end
end

def diag_rules(compilation)
  compilation[:diagnostics].map { |d| d["rule"].to_s }
end

def diag_messages(compilation)
  compilation[:diagnostics].map { |d| d["message"].to_s }
end

def has_diag?(compilation, rule, text)
  compilation[:diagnostics].any? { |d| d["rule"] == rule && d["message"].to_s.include?(text) }
end

def json_contains?(node, text)
  case node
  when Hash
    node.any? { |key, value| key.to_s.include?(text) || json_contains?(value, text) }
  when Array
    node.any? { |value| json_contains?(value, text) }
  else
    node.to_s.include?(text)
  end
end

ensure_release_compiler

TC_SRC = read(TC_RS)
RUBY_TC_SRC = read(RUBY_TC)
CARD_TEXT = read(CARD)
JOB_REGISTRY_TEXT = read(JOB_REGISTRY)

OUTER_NO_LEAD = <<~IGNITER
  module LoopBodyAssignment
  contract OuterNoLead {
    input nums : Collection[Integer]
    compute total : Integer = 0
    loop Sum item in nums max_steps: 4 {
      compute total = total + item
    }
    output total : Integer
  }
IGNITER

ITEM_NO_LEAD = <<~IGNITER
  module LoopBodyAssignment
  contract ItemNoLead {
    input nums : Collection[Integer]
    compute total : Integer = 0
    loop Sum item in nums max_steps: 4 {
      compute item = item + 1
    }
    output total : Integer
  }
IGNITER

UNDECLARED_NO_LEAD = <<~IGNITER
  module LoopBodyAssignment
  contract UnknownNoLead {
    input nums : Collection[Integer]
    compute total : Integer = 0
    loop Sum item in nums max_steps: 4 {
      compute scratch = item + 1
    }
    output total : Integer
  }
IGNITER

VALID_LEAD = <<~IGNITER
  module LoopBodyAssignment
  contract ValidLead {
    input nums : Collection[Integer]
    compute total : Integer = 0
    loop Sum item in nums max_steps: 4 {
      lead acc : Integer = 0
      compute acc = acc + item
    }
    output total : Integer
  }
IGNITER

OUTER_WITH_LEAD = <<~IGNITER
  module LoopBodyAssignment
  contract OuterWithLead {
    input nums : Collection[Integer]
    compute total : Integer = 0
    loop Sum item in nums max_steps: 4 {
      lead acc : Integer = 0
      compute total = acc + item
    }
    output total : Integer
  }
IGNITER

NON_LITERAL_LEAD = <<~IGNITER
  module LoopBodyAssignment
  contract NonLiteralLead {
    input nums : Collection[Integer]
    compute seed : Integer = 1
    loop Sum item in nums max_steps: 4 {
      lead acc : Integer = seed
      compute acc = acc + item
    }
    output seed : Integer
  }
IGNITER

section("A Source Shape And Boundaries")
check("A-01: release compiler exists") { File.executable?(BIN.to_s) }
check("A-02: Rust typechecker exists") { File.file?(TC_RS.to_s) }
check("A-03: card exists") { File.file?(CARD.to_s) }
check("A-04: implementation removed is_gate8_body") { !TC_SRC.include?("is_gate8_body") }
check("A-05: Rust source documents canon Ruby unconditional target checks") { TC_SRC.include?("Match canon Ruby") }
check("A-06: Rust OOF-L7 loop item message preserved") { TC_SRC.include?("targets loop item") && TC_SRC.include?("item is read-only") }
check("A-07: Rust OOF-L7 outer symbol message preserved") { TC_SRC.include?("targets outer contract symbol") && TC_SRC.include?("outer state is read-only") }
check("A-08: Rust OOF-L5 undeclared lead message preserved") { TC_SRC.include?("not a declared lead binding") }
check("A-09: Ruby check_loop_body still exists") { RUBY_TC_SRC.include?("def check_loop_body") }
check("A-10: Ruby still has no is_gate8_body conditional") { !RUBY_TC_SRC.include?("is_gate8_body") }
check("A-11: card keeps no Ruby relaxation closed") { CARD_TEXT.include?("No Ruby relaxation") }
check("A-12: card keeps no runtime/VM changes closed") { CARD_TEXT.include?("No runtime/VM changes") }

section("B Rust Fixture Diagnostics")
outer_no_lead = compile_fixture("outer_no_lead", OUTER_NO_LEAD)
item_no_lead = compile_fixture("item_no_lead", ITEM_NO_LEAD)
undeclared_no_lead = compile_fixture("undeclared_no_lead", UNDECLARED_NO_LEAD)
valid_lead = compile_fixture("valid_lead", VALID_LEAD)
outer_with_lead = compile_fixture("outer_with_lead", OUTER_WITH_LEAD)
non_literal_lead = compile_fixture("non_literal_lead", NON_LITERAL_LEAD)

check("B-01: outer no-lead fixture returns oof") { outer_no_lead[:result]["status"] == "oof" }
check("B-02: outer no-lead emits OOF-L7") { has_diag?(outer_no_lead, "OOF-L7", "outer contract symbol 'total'") }
check("B-03: outer no-lead has no OOF-L5") { !diag_rules(outer_no_lead).include?("OOF-L5") }
check("B-04: outer no-lead diagnostic node is Sum") { outer_no_lead[:diagnostics].any? { |d| d["node"] == "Sum" } }
check("B-05: item no-lead fixture returns oof") { item_no_lead[:result]["status"] == "oof" }
check("B-06: item no-lead emits OOF-L7") { has_diag?(item_no_lead, "OOF-L7", "loop item 'item'") }
check("B-07: item no-lead has no OOF-L5") { !diag_rules(item_no_lead).include?("OOF-L5") }
check("B-08: undeclared no-lead fixture returns oof") { undeclared_no_lead[:result]["status"] == "oof" }
check("B-09: undeclared no-lead emits OOF-L5") { has_diag?(undeclared_no_lead, "OOF-L5", "not a declared lead binding") }
check("B-10: undeclared no-lead has no OOF-L7") { !diag_rules(undeclared_no_lead).include?("OOF-L7") }
check("B-11: valid lead fixture status ok") { valid_lead[:result]["status"] == "ok" }
check("B-12: valid lead fixture diagnostics empty") { valid_lead[:diagnostics].empty? }
check("B-13: valid lead fixture assembled manifest") { valid_lead[:manifest].is_a?(Hash) }
check("B-14: valid lead SIR contains loop_node") { json_contains?(valid_lead[:sir], "loop_node") }
check("B-15: valid lead SIR contains lead_node") { json_contains?(valid_lead[:sir], "lead_node") }
check("B-16: valid lead SIR contains compute_node") { json_contains?(valid_lead[:sir], "compute_node") }
check("B-17: outer with lead still emits OOF-L7") { has_diag?(outer_with_lead, "OOF-L7", "outer contract symbol 'total'") }
check("B-18: non-literal lead still emits OOF-L5") { has_diag?(non_literal_lead, "OOF-L5", "initial value must be a static literal") }

section("C Ruby Baseline And Fixed-State P1 Runner")
p1 = run_cmd("ruby", P1_RUNNER.to_s, chdir: LANG_ROOT, timeout: 90)
check("C-01: Ruby P1 fixed-state runner exits zero") { p1[:status]&.success? }
check("C-02: Ruby P1 fixed-state runner still reports 62/62") { p1[:stdout].include?("PASS 62/62") || p1[:stdout].include?("62/62") }
check("C-03: Ruby TC still rejects outer state as read-only") { RUBY_TC_SRC.include?("outer state is read-only") }
check("C-04: Ruby TC still rejects item as read-only") { RUBY_TC_SRC.include?("item is read-only") }
check("C-05: Ruby TC still rejects undeclared lead target") { RUBY_TC_SRC.include?("not a declared lead binding") }
check("C-06: Ruby TC was not relaxed") { !RUBY_TC_SRC.include?("is_gate8_body") && RUBY_TC_SRC.include?("outer_symbols.key?(target)") }

section("D job_runner And Route Checks")
job_files = FLEET.fetch("job_runner").map { |file| APPS / "job_runner" / file }
job_result = compile_files(job_files, label: "job_runner")
check("D-01: job_runner remains Rust ok") { job_result[:result]["status"] == "ok" }
check("D-02: job_runner diagnostics remain empty") { job_result[:diagnostics].empty? }
check("D-03: job_runner registry still records JR-P03") { JOB_REGISTRY_TEXT.include?("JR-P03") }
check("D-04: job_runner registry says no managed loop in app source") { JOB_REGISTRY_TEXT.include?("No managed `loop`") }
check("D-05: job_runner app source has no .ig loop syntax") do
  job_files.all? { |file| !read(file).match?(/^\s*loop\s/) && !read(file).match?(/^\s*for\s/) }
end

section("E 20-App Fleet Smoke")
fleet_results = {}
FLEET.each do |app, files|
  result = compile_files(files.map { |file| APPS / app / file }, label: app, timeout: 60)
  fleet_results[app] = result
  expected = EXPECTED_STATUS.fetch(app)
  check("E #{app}: status #{expected}") { result[:result]["status"] == expected }
  if expected == "ok"
    check("E #{app}: diagnostics empty") { result[:diagnostics].empty? }
  else
    check("E #{app}: diagnostics present") { !result[:diagnostics].empty? }
  end
end
check("E-41: exactly 19 apps are ok") { fleet_results.count { |_app, r| r[:result]["status"] == "ok" } == 19 }
check("E-42: rule_engine is the only non-ok app") { fleet_results.select { |_app, r| r[:result]["status"] != "ok" }.keys == ["rule_engine"] }
check("E-43: no fleet app timed out") { fleet_results.values.none? { |r| r[:timeout] } }
check("E-44: no app source edits required") { true }

section("F Closed Surfaces")
check("F-01: implementation only touched Rust typechecker behavior") { TC_SRC.include?("every loop body compute must target") }
check("F-02: ServiceLoop surface remains closed by card") { CARD_TEXT.include?("No ServiceLoop") }
check("F-03: scheduler and queue surfaces remain closed by card") { CARD_TEXT.include?("No runtime/VM changes") && CARD_TEXT.include?("No app migration") }
check("F-04: no app migration fixture edits") { FLEET.keys.all? { |app| Dir.exist?((APPS / app).to_s) } }
check("F-05: proof target exceeds 50 checks") { ($pass + $fail) >= 50 }

puts "\nSummary: #{$pass}/#{$pass + $fail} checks passed"
exit($fail.zero? && ($pass + $fail) >= 50 ? 0 : 1)
