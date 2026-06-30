#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LAB-RUST-TYPECHECKER-DECOMP-P2 proof.
#
# Authority: behavior-preserving Rust lab refactor only. This runner proves the
# stdlib call dispatch extraction by compiling the Wave P11 16-app fleet and by
# checking source-shape invariants for the new typechecker submodule.

require "json"
require "open3"
require "pathname"
require "tmpdir"

COMPILER_DIR = Pathname.new(__dir__).parent.parent.expand_path
LAB_ROOT = COMPILER_DIR.parent
SRC = COMPILER_DIR / "src"
APPS = LAB_ROOT / "igniter-apps"
BIN = COMPILER_DIR / "target" / "release" / "igniter_compiler"

TC_RS = SRC / "typechecker.rs"
STDLIB_RS = SRC / "typechecker" / "stdlib_calls.rs"
LIB_RS = SRC / "lib.rs"
EMITTER_RS = SRC / "emitter.rs"
CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-RUST-TYPECHECKER-DECOMP-P2.md"
P1_RUNNER = COMPILER_DIR / "proofs" / "verify" / "verify_rust_typechecker_decomp_p1.rb"

def read(path)
  File.read(path.to_s, encoding: "utf-8")
rescue Errno::ENOENT
  ""
end

TC_SRC = read(TC_RS)
STDLIB_SRC = read(STDLIB_RS)
LIB_SRC = read(LIB_RS)
EMITTER_SRC = read(EMITTER_RS)

def fn_line(lines, name)
  lines.index { |l| l =~ /^\s+(pub )?fn #{Regexp.escape(name)}\b/ }&.+(1)
end

def fn_span(src, name)
  lines = src.lines
  start = fn_line(lines, name)
  return 0 unless start
  starts = lines.each_index.select { |i| lines[i] =~ /^\s+(pub )?fn \w/ }.map { |i| i + 1 }
  nxt = starts.find { |line| line > start }
  (nxt || lines.length + 1) - start
end

def run_cmd(*args, chdir: COMPILER_DIR)
  Open3.capture3(*args, chdir: chdir.to_s)
end

def compile_app(app, rel_files)
  Dir.mktmpdir("decomp_p2_") do |dir|
    out = File.join(dir, "#{app}.igapp")
    files = rel_files.map { |f| (APPS / app / f).to_s }
    stdout, stderr, status = Open3.capture3(BIN.to_s, "compile", *files, "--out", out)
    result = JSON.parse(stdout)
    manifest = File.file?(File.join(out, "manifest.json")) ? JSON.parse(File.read(File.join(out, "manifest.json"))) : nil
    semantic_ir = File.file?(File.join(out, "semantic_ir_program.json")) ? JSON.parse(File.read(File.join(out, "semantic_ir_program.json"))) : nil
    {
      app: app,
      ok: status.success?,
      stdout: stdout,
      stderr: stderr,
      result: result,
      manifest: manifest,
      semantic_ir: semantic_ir,
    }
  rescue JSON::ParserError => e
    {
      app: app,
      ok: false,
      stdout: stdout.to_s,
      stderr: stderr.to_s,
      result: { "status" => "json_parse_error", "diagnostics" => [{ "rule" => "JSON", "message" => e.message, "node" => app }] },
      manifest: nil,
      semantic_ir: nil,
    }
  end
end

def diagnostics(result)
  Array(result.dig(:result, "diagnostics"))
end

def diag_triples(result)
  diagnostics(result).map { |d| [d["rule"], d["message"], d["node"]] }.sort
end

def json_strings(value, acc = [])
  case value
  when Hash
    value.each_value { |v| json_strings(v, acc) }
  when Array
    value.each { |v| json_strings(v, acc) }
  when String
    acc << value
  end
  acc
end

def contains_pair?(value, key, expected)
  case value
  when Hash
    return true if value[key] == expected
    value.each_value.any? { |v| contains_pair?(v, key, expected) }
  when Array
    value.any? { |v| contains_pair?(v, key, expected) }
  else
    false
  end
end

$pass = 0
$fail = 0

def check(label)
  if yield
    $pass += 1
    puts "  PASS  #{label}"
  else
    $fail += 1
    puts "  FAIL  #{label}"
  end
rescue => e
  $fail += 1
  puts "  FAIL  #{label} [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n--- #{title}"
end

FLEET = {
  "advanced_logistics" => %w[types.ig spatial.ig router.ig api.ig],
  "arch_patterns" => %w[types.ig event_sourcing.ig state_machine.ig pipeline.ig example.ig],
  "bloom_filter" => %w[types.ig hash.ig ops.ig example.ig],
  "dataframes" => %w[types.ig matrix.ig dataframe.ig example.ig],
  "decision_tree" => %w[types.ig builder.ig evaluator.ig example.ig],
  "dsa" => %w[types.ig arrays.ig sets.ig graphs.ig strings.ig example.ig],
  "igniter_parser" => %w[types.ig lexer.ig parser.ig api.ig],
  "neural_net" => %w[types.ig activations.ig layers.ig network.ig example.ig],
  "sim_framework" => %w[types.ig temporal.ig relation.ig constraints.ig rules.ig engine.ig example.ig],
  "vector_editor" => %w[types.ig transform.ig document.ig tools.ig],
  "vector_math" => %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig],
  "rule_engine" => %w[types.ig rules.ig engine.ig example.ig],
  "trade_robot" => %w[types.ig indicators.ig signals.ig strategy.ig robot.ig backtester.ig example.ig],
  "air_combat" => %w[types.ig vec.ig kalman.ig guidance.ig strategy.ig swarm.ig engine.ig example.ig],
  "lead_router" => %w[types.ig pipeline.ig service.ig example.ig],
  "call_router" => %w[types.ig correlate.ig operator.ig webhook.ig service.ig example.ig],
}

EXPECTED_STATUS = FLEET.keys.to_h { |app| [app, app == "rule_engine" ? "oof" : "ok"] }
RULE_ENGINE_GOLDEN = [
  ["OOF-P1", "Unresolved field: Unknown.action", "active_decisions"],
  ["OOF-TY1", "Output type mismatch: expected RuleDecision, got Unknown", "decision"],
].sort

section("A source shape")
infer_span = fn_span(TC_SRC, "infer_expr")
check("A-01 typechecker.rs exists") { File.file?(TC_RS.to_s) }
check("A-02 stdlib_calls.rs exists") { File.file?(STDLIB_RS.to_s) }
check("A-03 nested module declared with path attr") { TC_SRC.include?("#[path = \"typechecker/stdlib_calls.rs\"]") }
check("A-04 lib.rs still exposes pub mod typechecker only") { LIB_SRC.scan(/^pub mod typechecker;/).length == 1 }
check("A-05 no typechecker/mod.rs conversion") { !File.exist?((SRC / "typechecker" / "mod.rs").to_s) }
check("A-06 infer_expr now delegates to infer_stdlib_call") { TC_SRC.include?("infer_stdlib_call(") }
check("A-07 inline substring arm removed from typechecker.rs") { !TC_SRC.include?("\"substring\" =>") }
check("A-08 inline map arm removed from typechecker.rs") { !TC_SRC.include?("\"map\" =>") }
check("A-09 inline fold arm removed from typechecker.rs") { !TC_SRC.include?("\"fold\" =>") }
check("A-10 stdlib module contains substring arm") { STDLIB_SRC.include?("\"substring\" =>") }
check("A-11 stdlib module contains map arm") { STDLIB_SRC.include?("\"map\" =>") }
check("A-12 stdlib module contains fold arm") { STDLIB_SRC.include?("\"fold\" =>") }
check("A-13 infer_expr is under 800 lines after extraction") { infer_span > 0 && infer_span < 800 }
check("A-14 stdlib module carries substantial extracted body") { STDLIB_SRC.lines.length > 1_000 }
check("A-15 emitter source was not part of the extraction") { EMITTER_SRC.include?("pub struct Emitter") && !EMITTER_SRC.include?("infer_stdlib_call") }

section("B build and P1 fixed-state")
stdout, stderr, status = run_cmd("cargo", "build", "--release")
check("B-01 cargo build --release succeeds") { status.success? }
check("B-02 release compiler binary exists") { File.executable?(BIN.to_s) }
p1_out, p1_err, p1_status = run_cmd("ruby", P1_RUNNER.to_s)
check("B-03 P1 verifier passes in fixed-state mode") { p1_status.success? }
check("B-04 P1 verifier still reports 60 checks") { p1_out.include?("/60 PASS") }
check("B-05 card is the P2 implementation card") { read(CARD).include?("LAB-RUST-TYPECHECKER-DECOMP-P2") }

section("C Wave P11 16-app matrix")
results = {}
FLEET.each do |app, files|
  results[app] = compile_app(app, files)
  res = results[app][:result]
  check("C #{app}: compiler emitted parseable result JSON") { results[app][:result].is_a?(Hash) && results[app][:result]["status"] }
  check("C #{app}: status matches Wave P11 #{EXPECTED_STATUS[app]}") { res["status"] == EXPECTED_STATUS[app] }
  if app == "rule_engine"
    check("C #{app}: diagnostic count remains 2") { diagnostics(results[app]).length == 2 }
    check("C #{app}: exact diagnostic triples unchanged") { diag_triples(results[app]) == RULE_ENGINE_GOLDEN }
  else
    check("C #{app}: diagnostics remain empty") { diagnostics(results[app]).empty? }
    check("C #{app}: ok app assembled manifest") { results[app][:manifest].is_a?(Hash) }
  end
end

section("D rule_engine fail-closed golden")
rule = results.fetch("rule_engine")
check("D-01 rule_engine is the only non-ok app") { results.count { |_app, r| r[:result]["status"] != "ok" } == 1 }
check("D-02 rule_engine has OOF-P1 Unknown.action") { diag_triples(rule).include?(["OOF-P1", "Unresolved field: Unknown.action", "active_decisions"]) }
check("D-03 rule_engine has OOF-TY1 RuleDecision/Unknown") { diag_triples(rule).include?(["OOF-TY1", "Output type mismatch: expected RuleDecision, got Unknown", "decision"]) }
check("D-04 rule_engine has no extra OOF code") { diag_triples(rule).map(&:first).sort == %w[OOF-P1 OOF-TY1] }
check("D-05 rule_engine output did not assemble manifest") { rule[:manifest].nil? }
check("D-06 rule_engine stdout remained valid JSON") { rule[:result].is_a?(Hash) }
check("D-07 non-rule_engine apps are 15 clean apps") { results.count { |app, r| app != "rule_engine" && r[:result]["status"] == "ok" } == 15 }
check("D-08 diagnostic parity is exact golden, not just same count") { diag_triples(rule) == RULE_ENGINE_GOLDEN }

section("E manifest entrypoints")
ENTRYPOINTS = {
  "air_combat" => "RunDuel",
  "lead_router" => "RunAccept",
  "call_router" => "RunConnectedMatched",
}
ENTRYPOINTS.each do |app, target|
  manifest = results.fetch(app)[:manifest] || {}
  entrypoint = manifest["entrypoint"] || {}
  check("E #{app}: manifest entrypoint exists") { entrypoint.is_a?(Hash) && !entrypoint.empty? }
  check("E #{app}: declared target remains #{target}") { entrypoint["declared_target"] == target || entrypoint["target"] == target }
  check("E #{app}: resolved contract remains #{target}") { entrypoint["resolved_contract"] == target }
end

section("F representative SemanticIR stdlib names")
strings_by_app = results.transform_values { |r| json_strings(r[:semantic_ir]) }
check("F-01 igniter_parser keeps stdlib.string.char_at") { strings_by_app["igniter_parser"].include?("stdlib.string.char_at") }
check("F-02 igniter_parser keeps stdlib.string.substring") { strings_by_app["igniter_parser"].include?("stdlib.string.substring") }
check("F-03 igniter_parser keeps stdlib.collection.append") { strings_by_app["igniter_parser"].include?("stdlib.collection.append") }
check("F-04 trade_robot keeps stdlib.collection.map") { strings_by_app["trade_robot"].include?("stdlib.collection.map") }
check("F-05 trade_robot keeps stdlib.collection.filter") { strings_by_app["trade_robot"].include?("stdlib.collection.filter") }
check("F-06 trade_robot keeps stdlib.collection.count") { strings_by_app["trade_robot"].include?("stdlib.collection.count") }
check("F-07 trade_robot keeps stdlib.collection.concat") { strings_by_app["trade_robot"].include?("stdlib.collection.concat") }
check("F-08 dsa keeps stdlib.collection.map") { strings_by_app["dsa"].include?("stdlib.collection.map") }
check("F-09 dsa keeps stdlib.collection.filter") { strings_by_app["dsa"].include?("stdlib.collection.filter") }
check("F-10 lead_router keeps fold lowering path") { contains_pair?(results["lead_router"][:semantic_ir], "kind", "fold") }

section("G closed surfaces")
status_out, _status_err, _status = run_cmd("git", "-C", LAB_ROOT.to_s, "status", "--short", "--", "igniter-apps", "igniter-compiler/src/parser.rs", "igniter-compiler/src/emitter.rs", "igniter-compiler/src/assembler.rs", "igniter-compiler/src/classifier.rs", "igniter-compiler/src/multifile.rs")
check("G-01 no app source/status changes in this refactor") { !status_out.lines.any? { |l| l.include?("igniter-apps/") && l.end_with?(".ig\n") } }
check("G-02 parser remains untouched by this refactor") { !status_out.include?("igniter-compiler/src/parser.rs") }
check("G-03 emitter remains untouched by this refactor") { !status_out.include?("igniter-compiler/src/emitter.rs") }
check("G-04 assembler remains untouched by this refactor") { !status_out.include?("igniter-compiler/src/assembler.rs") }
check("G-05 classifier remains untouched by this refactor") { !status_out.include?("igniter-compiler/src/classifier.rs") }
check("G-06 multifile remains untouched by this refactor") { !status_out.include?("igniter-compiler/src/multifile.rs") }
check("G-07 Ruby canon was not edited") { !run_cmd("git", "-C", (LAB_ROOT.parent / "igniter-lang").to_s, "status", "--short", "--", "lib/igniter_lang/typechecker.rb").first.include?("typechecker.rb") }
check("G-08 no later typechecker modules opened") { %w[records operators match_expr infer_expr].none? { |m| File.exist?((SRC / "typechecker" / "#{m}.rs").to_s) } }

puts
total = $pass + $fail
puts "Result: #{$pass}/#{total} PASS"
puts "VERDICT: #{$fail.zero? ? 'PASS' : 'FAIL'} -- LAB-RUST-TYPECHECKER-DECOMP-P2 behavior-preserving extraction"
puts "Matrix: #{results.count { |_app, r| r[:result]['status'] == 'ok' }}/16 ok; rule_engine=#{results.dig('rule_engine', :result, 'status')}/#{diagnostics(results['rule_engine']).length}"
puts "Shape: typechecker.rs=#{TC_SRC.lines.length} lines; stdlib_calls.rs=#{STDLIB_SRC.lines.length} lines; infer_expr=#{infer_span} lines"
exit($fail.zero? ? 0 : 1)
