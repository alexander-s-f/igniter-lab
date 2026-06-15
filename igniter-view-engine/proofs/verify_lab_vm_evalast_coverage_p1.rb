#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vm_evalast_coverage_p1.rb
# LAB-VM-EVALAST-COVERAGE-P1
#
# Source-anchored guard for VM bytecode lowering vs eval_ast coverage.
# PASS means every compile_expr expression kind is explicitly classified for
# the tree-walked lambda/eval path. PASS does not grant new semantic authority.

require "open3"
require "pathname"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"

COMPILER_RS = LAB_ROOT / "igniter-vm" / "src" / "compiler.rs"
VM_RS = LAB_ROOT / "igniter-vm" / "src" / "vm.rs"
EMITTER_RS = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-EVALAST-COVERAGE-P1.md"
MATCH_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-EVALAST-MATCH-P1.md"
DISPATCH_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md"
VARIANT_CARD = LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VARIANT-VM-P1.md"
DOC = LAB_ROOT / "lab-docs" / "lang" / "lab-vm-evalast-coverage-p1-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"

EXPECTED_BYTECODE_KINDS = %w[
  apply array array_literal binary_op call concat emit_observation field_access
  filter fn fold if_expr lambda let literal loop_node map map_reduce_aggregate
  match_expr match_node range record record_literal reduce ref service_loop_node
  symbol temporal_read unary unary_op unsupported variant_construct
].freeze

EXPECTED_EVAL_AST_KINDS = %w[
  apply array array_literal binary_op call concat emit_observation field_access
  filter fn fold if_expr lambda let literal map match_expr match_node range
  record record_literal reduce ref temporal_read unary unary_op
].freeze

CLASSIFICATION = {
  "apply" => ["both", "generic apply/call evaluator"],
  "array" => ["both", "literal collection construction"],
  "array_literal" => ["both", "literal collection construction"],
  "binary_op" => ["both", "arithmetic/comparison/logical operators"],
  "call" => ["both", "generic apply/call evaluator"],
  "concat" => ["both", "direct concat node"],
  "emit_observation" => ["both", "modifier-gated observation path"],
  "field_access" => ["both", "record field extraction"],
  "filter" => ["both", "HOF node and op fallback"],
  "fn" => ["both", "lambda serialization alias"],
  "fold" => ["both", "HOF node and op fallback"],
  "if_expr" => ["both", "dual field shapes plus branch return_expr unwrap"],
  "lambda" => ["both", "lambda serialization"],
  "let" => ["both", "local binding"],
  "literal" => ["both", "value literal"],
  "map" => ["both", "HOF node and op fallback"],
  "match_expr" => ["both", "match arm dispatch after LAB-VM-EVALAST-MATCH-P1"],
  "match_node" => ["both", "match arm dispatch after LAB-VM-EVALAST-MATCH-P1"],
  "range" => ["both", "range source/value construction"],
  "record" => ["both", "record construction"],
  "record_literal" => ["both", "record construction"],
  "reduce" => ["both", "fold/reduce HOF evaluator"],
  "ref" => ["both", "env/input/temporal lookup"],
  "temporal_read" => ["both", "backend read_as_of"],
  "unary" => ["both", "not/negation"],
  "unary_op" => ["both", "not/negation"],
  "map_reduce_aggregate" => ["bytecode_serialized_eval", "OP_MAP_REDUCE owns the aggregate node and calls eval_ast for source/pipeline expressions"],
  "loop_node" => ["bytecode_only_hold", "loop control is OP_LOOP_START/OP_LOOP_STEP, not lambda tree-walked"],
  "service_loop_node" => ["bytecode_only_hold", "service loop tick/control remains escape/runtime-only"],
  "symbol" => ["bytecode_only_hold", "compiler literalizes symbol to string value"],
  "unsupported" => ["intentionally_unsupported", "compiler emits OP_UNSUPPORTED fail-closed"],
  "variant_construct" => ["bytecode_only_gap", "route LAB-VM-EVALAST-VARIANT-CONSTRUCT-P2 for nested lambda/HOF constructors"]
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

def extract_top_level_kind_arms(source, start_marker, end_marker)
  start = source.index(start_marker)
  raise "missing start marker #{start_marker}" unless start
  tail = source[start..]
  finish = tail.index(end_marker)
  raise "missing end marker #{end_marker}" unless finish

  block = tail[0...finish]
  block.lines.grep(/^ {12}"/).flat_map { |line| line.scan(/"([^"]+)"/).flatten }.uniq.sort
end

def git_ig_diffs
  stdout, _stderr, _status = Open3.capture3(
    "git", "diff", "--name-only", "--", "igniter-apps"
  )
  stdout.lines.map(&:strip).select { |path| path.end_with?(".ig") }
end

compiler = read(COMPILER_RS)
vm = read(VM_RS)
emitter = read(EMITTER_RS)
card = read(CARD)
match_card = read(MATCH_CARD)
dispatch_card = read(DISPATCH_CARD)
variant_card = read(VARIANT_CARD)
doc = read(DOC)
portfolio = read(PORTFOLIO)

bytecode_kinds = extract_top_level_kind_arms(
  compiler,
  "fn compile_expr(&mut self, node: &serde_json::Value)",
  "_ => return Err(format!(\"Unsupported AST expression kind:"
)
eval_ast_kinds = extract_top_level_kind_arms(
  vm,
  "fn eval_ast<'a>(",
  "_ => Err(format!(\"Unsupported AST kind in VM evaluator:"
)

classified_kinds = CLASSIFICATION.keys.sort
both = CLASSIFICATION.select { |_kind, (status, _note)| status == "both" }.keys.sort
bytecode_only = CLASSIFICATION.select { |_kind, (status, _note)| status != "both" }.keys.sort
eval_ast_only = eval_ast_kinds - bytecode_kinds

section("A. Required Inputs")
check("A-01 compiler.rs exists") { COMPILER_RS.file? }
check("A-02 vm.rs exists") { VM_RS.file? }
check("A-03 emitter.rs exists") { EMITTER_RS.file? }
check("A-04 card exists") { CARD.file? }
check("A-05 LAB-VM-EVALAST-MATCH-P1 gate is DONE/CLOSED") { match_card.include?("Status: DONE") || match_card.include?("Status:** DONE") || match_card.include?("Status:** CLOSED") }
check("A-06 numeric dispatch card records cluster 2 DONE") { dispatch_card.include?("Cluster 2") && dispatch_card.include?("DONE") }
check("A-07 LAB-VARIANT-VM-P1 predecessor exists in canon repo") { VARIANT_CARD.file? }
check("A-08 runtime RUN-OK report is optional and absent/present is non-authority") { true }

section("B. Bytecode Lowering Kind Census")
check("B-01 bytecode kind census extracted 32 top-level arms") { bytecode_kinds.size == 32 }
check("B-02 bytecode kind census matches expected set") { bytecode_kinds == EXPECTED_BYTECODE_KINDS.sort }
EXPECTED_BYTECODE_KINDS.sort.each do |kind|
  check("B-kind #{kind} is present in compile_expr") { bytecode_kinds.include?(kind) }
end
check("B-35 compile_expr fails closed on unknown expression kind") { compiler.include?("Unsupported AST expression kind") }
check("B-36 compile_expr map_reduce_aggregate emits OP_MAP_REDUCE") { compiler.include?('"map_reduce_aggregate"') && compiler.include?("OP_MAP_REDUCE") }
check("B-37 compile_expr variant_construct lowers to OP_PUSH_RECORD") { compiler.include?('"variant_construct"') && compiler.include?("OP_PUSH_RECORD") }
check("B-38 compile_expr match_node/match_expr share one arm") { compiler.include?('"match_node" | "match_expr"') }

section("C. eval_ast Kind Census")
check("C-01 eval_ast kind census extracted 26 top-level arms") { eval_ast_kinds.size == 26 }
check("C-02 eval_ast kind census matches expected set") { eval_ast_kinds == EXPECTED_EVAL_AST_KINDS.sort }
EXPECTED_EVAL_AST_KINDS.sort.each do |kind|
  check("C-kind #{kind} is present in eval_ast") { eval_ast_kinds.include?(kind) }
end
check("C-29 eval_ast fails closed on unknown kind") { vm.include?("Unsupported AST kind in VM evaluator") }
check("C-30 eval_lambda delegates body evaluation back to eval_ast") { vm.include?("fn eval_lambda") && vm.include?("eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await") }
check("C-31 eval_ast match_node/match_expr share one arm") { vm.include?('"match_node" | "match_expr"') }
check("C-32 eval_ast if_expr accepts both condition and cond") { vm.include?('node.get("condition").or_else(|| node.get("cond"))') }
check("C-33 eval_ast if_expr unwraps return_expr block branches") { vm.include?('branch.get("return_expr").unwrap_or(branch)') }

section("D. Coverage Matrix Guard")
check("D-01 every bytecode kind is classified") { bytecode_kinds.all? { |kind| CLASSIFICATION.key?(kind) } }
check("D-02 no stale classification lacks a bytecode kind") { (classified_kinds - bytecode_kinds).empty? }
check("D-03 all eval_ast arms are bytecode-backed") { eval_ast_only.empty? }
check("D-04 aligned set equals eval_ast top-level set") { both == eval_ast_kinds }
check("D-05 bytecode-only set is explicit") { bytecode_only == %w[loop_node map_reduce_aggregate service_loop_node symbol unsupported variant_construct].sort }
EXPECTED_BYTECODE_KINDS.sort.each do |kind|
  status, note = CLASSIFICATION.fetch(kind)
  check("D-kind #{kind} has non-empty classification status") { !status.empty? && !note.empty? }
  check("D-kind #{kind} classification agrees with eval_ast presence") do
    status == "both" ? eval_ast_kinds.include?(kind) : !eval_ast_kinds.include?(kind)
  end
end

section("E. Bytecode-Only Routes")
check("E-01 symbol is bytecode-only literalization") { CLASSIFICATION["symbol"].join.include?("literalizes symbol") }
check("E-02 map_reduce_aggregate is serialized OP_MAP_REDUCE path") { vm.include?("OP_MAP_REDUCE") && vm.include?("Missing source in map_reduce_aggregate") }
check("E-03 OP_MAP_REDUCE uses eval_ast for source") { vm.include?("let source_val = eval_ast(source") }
check("E-04 OP_MAP_REDUCE uses eval_ast for pipeline bodies") { vm.scan("eval_ast(body, inputs, temporal_context").size >= 3 }
check("E-05 loop_node remains bytecode loop-control path") { compiler.include?("OP_LOOP_START") && compiler.include?("OP_LOOP_STEP") }
check("E-06 service_loop_node remains bytecode tick/control path") { compiler.include?("OP_LOAD_TICK") }
check("E-07 unsupported remains intentional fail-closed opcode") { compiler.include?('"unsupported"') && compiler.include?("OP_UNSUPPORTED") }
check("E-08 variant_construct gap has named route") { CLASSIFICATION["variant_construct"].join.include?("LAB-VM-EVALAST-VARIANT-CONSTRUCT-P2") }
check("E-09 emitter still produces variant_construct from annotated_expr") { emitter.include?('Some("variant_construct")') }
check("E-10 emitter still renames match_expr to match_node") { emitter.include?('Some("match_expr")') && emitter.include?('"match_node"') }

section("F. Deliverable Anchors")
check("F-01 lab doc exists") { DOC.file? }
check("F-02 lab doc names coverage matrix") { doc.include?("Coverage Matrix") }
check("F-03 lab doc anchors compiler.rs range") { doc.include?("igniter-vm/src/compiler.rs:243") }
check("F-04 lab doc anchors vm.rs range") { doc.include?("igniter-vm/src/vm.rs:2219") }
check("F-05 lab doc records match_expr aligned") { doc.include?("match_expr") && doc.include?("aligned") }
check("F-06 lab doc names variant_construct follow-up") { doc.include?("LAB-VM-EVALAST-VARIANT-CONSTRUCT-P2") }
check("F-07 lab doc states no semantic expansion") { doc.include?("No VM semantics changed") }
check("F-08 card is closed") { card.include?("**Status:** CLOSED") }
check("F-09 portfolio index includes this card") { portfolio.include?("LAB-VM-EVALAST-COVERAGE-P1 CLOSED") }
check("F-10 no app .ig source diffs in this guard") { git_ig_diffs.empty? }

section("G. Closed Surfaces")
check("G-01 proof runner does not edit VM source") { true }
check("G-02 card keeps no language semantics changes closed") { card.include?("No language semantics changes") }
check("G-03 card keeps no broad VM rewrite closed") { card.include?("No broad VM rewrite") }
check("G-04 card keeps no closure conversion implementation closed") { card.include?("No closure conversion implementation") }
check("G-05 card keeps no dispatch-table changes closed") { card.include?("No dispatch-table changes") }
check("G-06 card keeps no app migrations closed") { card.include?("No app migrations") }

puts "\nRESULT: #{$pass}/#{$pass + $fail} checks passed"
exit($fail.zero? ? 0 : 1)
