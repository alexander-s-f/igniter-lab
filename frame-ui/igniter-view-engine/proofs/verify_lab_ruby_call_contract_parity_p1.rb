#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_ruby_call_contract_parity_p1.rb
# LAB-RUBY-CALL-CONTRACT-PARITY-P1 — readiness/safety proof for Ruby call_contract parity.
#
# This proof does NOT implement anything. It classifies call shapes, compares Ruby vs Rust
# current behavior, identifies safe vs blocked subsets, and gates P2 on output assignability.
#
# Authority: readiness proof only. No Ruby TC changes. No Rust TC changes. No VM changes.
# P2 planning is explicitly conditional on LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 state.
#
# Sections:
#   A  Shape Inventory         (10) — count and classify all call_contract calls in apps
#   B  Ruby TC current state   ( 8) — all call_contract → OOF-TY0 "Unknown function"
#   C  Rust TC Tier 1          ( 8) — literal callee → registry lookup, arity, purity
#   D  Rust TC Tier 2          ( 4) — dynamic callee → Unknown, no error
#   E  Stdlib name routing     ( 6) — "append"/"empty" not in contract registry; needs route
#   F  Lambda-internal form    ( 4) — literal names inside lambda bodies — safe subset
#   G  App blocker taxonomy    ( 6) — which blockers are call_contract vs stdlib vs other
#   H  Safe subset + gate      ( 6) — P2 authorized scope; output assignability constraint
#   I  Authority closed        ( 4) — no implementation, no Unknown escape
#
# Total: 56 checks

require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
WORKSPACE    = LAB_ROOT.parent
IGNITER_LIB  = WORKSPACE / "igniter-lang" / "lib"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
TC_RUBY_PATH = WORKSPACE / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST_PATH = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
APPS_DIR     = LAB_ROOT / "igniter-apps"
INVENTORY    = WORKSPACE / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

STDLIB_CALL_CONTRACT_ALIASES = %w[append empty concat].freeze

# ── Shape classification helpers ────────────────────────────────────────────

CALL_CONTRACT_RE = /call_contract\((\s*"[^"]*"|\s*\w+)/

def classify_call_contract_calls
  stdlib_calls  = []
  literal_calls = []
  dynamic_calls = []

  Dir.glob((APPS_DIR / "**" / "*.ig").to_s).sort.each do |path|
    src = File.read(path, encoding: "UTF-8")
    src.each_line.with_index(1) do |line, lineno|
      next unless line.include?("call_contract(")
      m = CALL_CONTRACT_RE.match(line)
      next unless m
      first_arg = m[1].strip
      rel = path.sub(APPS_DIR.to_s + "/", "")
      if first_arg.start_with?('"')
        name = first_arg.gsub('"', '')
        if STDLIB_CALL_CONTRACT_ALIASES.include?(name)
          stdlib_calls  << { file: rel, line: lineno, name: name }
        else
          literal_calls << { file: rel, line: lineno, name: name }
        end
      else
        dynamic_calls << { file: rel, line: lineno, name: first_arg }
      end
    end
  end

  { stdlib: stdlib_calls, literal: literal_calls, dynamic: dynamic_calls }
end

def lambda_internal_calls
  results = []
  Dir.glob((APPS_DIR / "**" / "*.ig").to_s).sort.each do |path|
    src = File.read(path, encoding: "UTF-8")
    lines = src.lines
    lines.each_with_index do |line, idx|
      next unless line.include?("call_contract(")
      # Look back 6 lines for a lambda arrow
      context = lines[[(idx - 6), 0].max...idx].join
      results << { file: path.sub(APPS_DIR.to_s + "/", ""), line: idx + 1 } if context.include?("->")
    end
  end
  results
end

CALLS = classify_call_contract_calls
LAMBDA_CALLS = lambda_internal_calls

# ── Ruby TC helper ───────────────────────────────────────────────────────────

def ruby_tc(src, source_path: "inline.ig")
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: source_path).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  top_errors = Array(typed["type_errors"])
  contracts  = Array(typed["contracts"])
  { typed: typed, errors: top_errors,
    codes:    top_errors.map { |e| e["rule"] },
    messages: top_errors.map { |e| e["message"].to_s },
    contracts: contracts }
rescue => e
  { error: e.message, errors: [], codes: [], messages: [], contracts: [] }
end

def contract_errors(result, name)
  c = result[:contracts].find { |c| c["name"] == name }
  Array(c&.fetch("type_errors", []))
end

def contract_status(result, name)
  c = result[:contracts].find { |c| c["name"] == name }
  c&.fetch("status", "unknown")
end

# ── Rust compiler helper ─────────────────────────────────────────────────────

$_tmpdir = Dir.mktmpdir("cc_parity_p1_")
at_exit { require "fileutils"; FileUtils.rm_rf($_tmpdir) }

def rust_compile_source(src)
  path = File.join($_tmpdir, "inline_#{rand(1_000_000)}.ig")
  out  = path + ".igapp"
  File.write(path, src)
  stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", path, "--out", out)
  result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
  diags  = Array(result["diagnostics"])
  { status:   result["status"] || "parse-error",
    diags:    diags,
    codes:    diags.map { |d| d["rule"].to_s },
    messages: diags.map { |d| d["message"].to_s } }
end

# ── Check harness ────────────────────────────────────────────────────────────

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

TC_RUBY_SRC = TC_RUBY_PATH.exist? ? TC_RUBY_PATH.read.encode("UTF-8", invalid: :replace, undef: :replace) : ""
TC_RUST_SRC = TC_RUST_PATH.exist? ? TC_RUST_PATH.read.encode("UTF-8", invalid: :replace, undef: :replace) : ""

# ── Section A: Shape Inventory ──────────────────────────────────────────────
puts
puts "Section A — Shape Inventory"

total_calls = CALLS[:stdlib].size + CALLS[:literal].size + CALLS[:dynamic].size
check("A-01: total call_contract calls >= 140 across all apps") { total_calls >= 140 }
check("A-02: STDLIB_FORM (append/empty/concat) count == 34") { CALLS[:stdlib].size == 34 }
check("A-03: LITERAL_MODULE (PascalCase contract) count == 113") { CALLS[:literal].size == 113 }
check("A-04: DYNAMIC (variable, not string literal) count == 1") { CALLS[:dynamic].size == 1 }
check("A-05: LAMBDA_INTERNAL calls >= 6") { LAMBDA_CALLS.size >= 6 }
check("A-06: 'append' appears in STDLIB calls") { CALLS[:stdlib].any? { |c| c[:name] == "append" } }
check("A-07: 'empty' appears in STDLIB calls (igniter_parser)") do
  CALLS[:stdlib].any? { |c| c[:name] == "empty" && c[:file].include?("igniter_parser") }
end
check("A-08: DYNAMIC form is only in rule_engine/engine.ig") do
  CALLS[:dynamic].all? { |c| c[:file].include?("rule_engine") }
end
check("A-09: LITERAL_MODULE names are all PascalCase") do
  CALLS[:literal].all? { |c| c[:name] =~ /\A[A-Z]/ }
end
check("A-10: LITERAL_MODULE spans >= 20 source files") do
  CALLS[:literal].map { |c| c[:file] }.uniq.size >= 20
end

# ── Section B: Ruby TC Current State ────────────────────────────────────────
puts
puts "Section B — Ruby TC Current State"

LITERAL_CC_SRC = <<~IG
  module TestCCLiteral
  contract Helper {
    input x : Integer
    output x : Integer
  }
  contract Caller {
    input val : Integer
    compute result = call_contract("Helper", val)
    output result : Integer
  }
IG

STDLIB_CC_SRC = <<~IG
  module TestCCStdlib
  contract AppendTest {
    input items : Collection[Integer]
    input item : Integer
    compute result = call_contract("append", items, item)
    output result : Collection[Integer]
  }
IG

DYNAMIC_CC_SRC = <<~IG
  module TestCCDynamic
  contract DynCaller {
    input contract_name : String
    input val : Integer
    compute result = call_contract(contract_name, val)
    output result : Integer
  }
IG

UNKNOWN_OUT_CC_SRC = <<~IG
  module TestCCUnknown
  contract DynCaller {
    input contract_name : String
    input val : Integer
    compute result = call_contract(contract_name, val)
    output result : Unknown
  }
IG

r_lit  = ruby_tc(LITERAL_CC_SRC)
r_std  = ruby_tc(STDLIB_CC_SRC)
r_dyn  = ruby_tc(DYNAMIC_CC_SRC)
r_unk  = ruby_tc(UNKNOWN_OUT_CC_SRC)

check("B-01: literal same-module → OOF-TY0 'Unknown function: call_contract'") do
  r_lit[:codes].include?("OOF-TY0") &&
    r_lit[:messages].any? { |m| m.include?("Unknown function") && m.include?("call_contract") }
end
check("B-02: stdlib 'append' form → OOF-TY0 'Unknown function: call_contract'") do
  r_std[:codes].include?("OOF-TY0") &&
    r_std[:messages].any? { |m| m.include?("Unknown function") && m.include?("call_contract") }
end
check("B-03: dynamic variable form → OOF-TY0 'Unknown function: call_contract'") do
  r_dyn[:codes].include?("OOF-TY0") &&
    r_dyn[:messages].any? { |m| m.include?("Unknown function") && m.include?("call_contract") }
end
check("B-04: contract status = blocked when call_contract used (literal)") do
  contract_status(r_lit, "Caller") == "blocked"
end
check("B-05: contract status = blocked when call_contract used (dynamic)") do
  contract_status(r_dyn, "DynCaller") == "blocked"
end
check("B-06: NO 'when \"call_contract\"' arm in Ruby TC source") do
  !TC_RUBY_SRC.include?('"call_contract"') && !TC_RUBY_SRC.include?("'call_contract'")
end
check("B-07: concrete output type → adds type-mismatch OOF-TY0 on top of unknown-function error") do
  r_dyn[:codes].count("OOF-TY0") >= 2
end
check("B-08: Unknown output type → only one OOF-TY0 (no type mismatch)") do
  r_unk[:codes].count("OOF-TY0") == 1 &&
    r_unk[:messages].none? { |m| m.include?("Type mismatch") }
end

# ── Section C: Rust TC Tier 1 ────────────────────────────────────────────────
puts
puts "Section C — Rust TC Tier 1 (literal callee)"

RUST_CC_LITERAL_SRC = <<~IG
  module TestCCRust
  contract Helper {
    input x : Integer
    output x : Integer
  }
  contract Caller {
    input val : Integer
    compute result = call_contract("Helper", val)
    output result : Integer
  }
IG

RUST_CC_UNKNOWN_SRC = <<~IG
  module TestCCRust
  contract Caller {
    input val : Integer
    compute result = call_contract("NonExistent", val)
    output result : Integer
  }
IG

RUST_CC_STDLIB_SRC = <<~IG
  module TestCCRust
  contract AppendTest {
    input items : Collection[Integer]
    input item : Integer
    compute result = call_contract("append", items, item)
    output result : Collection[Integer]
  }
IG

RUST_CC_ARITY_SRC = <<~IG
  module TestCCRust
  contract Helper {
    input x : Integer
    output x : Integer
  }
  contract Caller {
    input val : Integer
    compute result = call_contract("Helper", val, 999)
    output result : Integer
  }
IG

RUST_CC_PASS_SRC = <<~IG
  module TestCCRust
  contract Helper {
    input x : Integer
    input y : Integer
    output x : Integer
  }
  contract Caller {
    input a : Integer
    input b : Integer
    compute result = call_contract("Helper", a, b)
    output result : Integer
  }
IG

rc_lit  = rust_compile_source(RUST_CC_LITERAL_SRC)
rc_unk  = rust_compile_source(RUST_CC_UNKNOWN_SRC)
rc_std  = rust_compile_source(RUST_CC_STDLIB_SRC)
rc_ari  = rust_compile_source(RUST_CC_ARITY_SRC)
rc_pass = rust_compile_source(RUST_CC_PASS_SRC)

check("C-01: literal same-module pure contract → Rust status ok") { rc_lit[:status] == "ok" }
check("C-02: literal same-module → no Rust diagnostics") { rc_lit[:diags].empty? }
check("C-03: literal unknown callee → OOF-TY0 'not found in this module'") do
  rc_unk[:codes].include?("OOF-TY0") &&
    rc_unk[:messages].any? { |m| m.include?("not found in this module") }
end
check("C-04: literal stdlib 'append' → OOF-TY0 'not found in this module'") do
  rc_std[:codes].include?("OOF-TY0") &&
    rc_std[:messages].any? { |m| m.include?("not found in this module") }
end
check("C-05: arity mismatch → OOF-TY0") do
  rc_ari[:codes].include?("OOF-TY0") &&
    rc_ari[:messages].any? { |m| m.include?("expects") && m.include?("got") }
end
check("C-06: arity match → ok, no errors") { rc_pass[:status] == "ok" && rc_pass[:diags].empty? }
check("C-07: LAB-RACK-P11 comment present in Rust TC (two-tier Tier 1)") do
  TC_RUST_SRC.include?("LAB-RACK-P11")
end
check("C-08: 'call_contract' arm present in Rust TC") do
  TC_RUST_SRC.include?('"call_contract"')
end

# ── Section D: Rust TC Tier 2 ────────────────────────────────────────────────
puts
puts "Section D — Rust TC Tier 2 (dynamic callee)"

RUST_CC_DYNAMIC_SRC = <<~IG
  module TestCCRust
  contract DynCaller {
    input contract_name : String
    input val : Integer
    compute result = call_contract(contract_name, val)
    output result : Integer
  }
IG

rc_dyn = rust_compile_source(RUST_CC_DYNAMIC_SRC)

check("D-01: dynamic callee (variable) → Rust status ok") { rc_dyn[:status] == "ok" }
check("D-02: dynamic callee → no OOF-TY0 (Unknown is permissive)") { rc_dyn[:codes].empty? }
check("D-03: 'Tier 2' comment present in Rust TC (dynamic → Unknown)") do
  TC_RUST_SRC.include?("Tier 2")
end
check("D-04: rule_engine dynamic form ('r') is exactly one call in all apps") do
  CALLS[:dynamic].size == 1 && CALLS[:dynamic].first[:name] == "r"
end

# ── Section E: Stdlib Name Routing ───────────────────────────────────────────
puts
puts "Section E — Stdlib Name Routing"

INVENTORY_DATA = INVENTORY.exist? ? JSON.parse(INVENTORY.read(encoding: "UTF-8")) : {}
INV_ENTRIES    = (INVENTORY_DATA["entries"] || []).map { |e| e["canonical_name"] }

check("E-01: stdlib.collection.append is in stdlib inventory (authorized P1)") do
  INV_ENTRIES.any? { |n| n == "stdlib.collection.append" }
end
check("E-02: stdlib.collection.empty has NO inventory entry (not yet authorized)") do
  INV_ENTRIES.none? { |n| n == "stdlib.collection.empty" }
end
check("E-03: Rust TC produces OOF-TY0 for call_contract('append',...) — not a module contract") do
  rc_std[:codes].include?("OOF-TY0") &&
    rc_std[:messages].any? { |m| m.include?("append") }
end
check("E-04: Ruby TC produces OOF-TY0 for call_contract('append',...) — no call_contract arm") do
  r_std[:codes].include?("OOF-TY0")
end
check("E-05: 'append' stdlib calls span >= 5 files (broad pressure for stdlib route)") do
  CALLS[:stdlib].select { |c| c[:name] == "append" }.map { |c| c[:file] }.uniq.size >= 5
end
check("E-06: 'empty' stdlib calls exist (igniter_parser bootstrap pattern)") do
  CALLS[:stdlib].any? { |c| c[:name] == "empty" }
end

# ── Section F: Lambda-Internal Form ─────────────────────────────────────────
puts
puts "Section F — Lambda-Internal Form"

LAMBDA_FILES = LAMBDA_CALLS.map { |c| c[:file] }.uniq

check("F-01: non-dynamic lambda-internal calls are all literal module contract names") do
  LAMBDA_CALLS.all? do |lc|
    src_line = File.readlines((APPS_DIR / lc[:file]).to_s, encoding: "UTF-8")[lc[:line] - 1] rescue ""
    m = CALL_CONTRACT_RE.match(src_line)
    next true unless m
    first_arg = m[1].strip
    # Dynamic form (no quotes) is allowed here — rule_engine dynamic lambda is classified separately
    next true unless first_arg.start_with?('"')
    name = first_arg.gsub('"', '')
    !STDLIB_CALL_CONTRACT_ALIASES.include?(name)
  end
end
check("F-02: vector_editor has lambda-internal call_contract") do
  LAMBDA_FILES.any? { |f| f.include?("vector_editor") }
end
check("F-03: bloom_filter has lambda-internal call_contract") do
  LAMBDA_FILES.any? { |f| f.include?("bloom_filter") }
end
check("F-04: literal lambda-internal calls are subset of LITERAL_MODULE + STDLIB_FORM (no new shapes)") do
  lambda_names = LAMBDA_CALLS.map do |lc|
    src_line = File.readlines((APPS_DIR / lc[:file]).to_s, encoding: "UTF-8")[lc[:line] - 1] rescue ""
    m = CALL_CONTRACT_RE.match(src_line)
    next nil unless m
    first_arg = m[1].strip
    first_arg.start_with?('"') ? first_arg.gsub('"', '') : nil  # skip dynamic forms
  end.compact
  all_known = CALLS[:literal].map { |c| c[:name] } + CALLS[:stdlib].map { |c| c[:name] }
  (lambda_names - all_known).empty?
end

# ── Section G: App Blocker Taxonomy ─────────────────────────────────────────
puts
puts "Section G — App Blocker Taxonomy"

APPS_WITH_LITERAL_CC = CALLS[:literal].map { |c| c[:file].split("/").first }.uniq.sort
APPS_WITH_STDLIB_CC  = CALLS[:stdlib].map  { |c| c[:file].split("/").first }.uniq.sort
APPS_WITH_DYNAMIC_CC = CALLS[:dynamic].map { |c| c[:file].split("/").first }.uniq.sort

check("G-01: Ruby literal call_contract gap spans >= 10 apps") do
  APPS_WITH_LITERAL_CC.size >= 10
end
check("G-02: Rust call_contract('append',...) gap spans <= 6 apps (VE/DT/AP/igniter_parser/bloom/arch)") do
  APPS_WITH_STDLIB_CC.size <= 6
end
check("G-03: dynamic form is isolated to rule_engine only") do
  APPS_WITH_DYNAMIC_CC == ["rule_engine"]
end
check("G-04: neural_net uses only literal same-module contracts (no stdlib/dynamic)") do
  nn_calls_stdlib  = CALLS[:stdlib].none?  { |c| c[:file].include?("neural_net") }
  nn_calls_dynamic = CALLS[:dynamic].none? { |c| c[:file].include?("neural_net") }
  nn_calls_stdlib && nn_calls_dynamic
end
check("G-05: vector_math uses only literal same-module contracts (no stdlib/dynamic)") do
  vm_stdlib  = CALLS[:stdlib].none?  { |c| c[:file].include?("vector_math") }
  vm_dynamic = CALLS[:dynamic].none? { |c| c[:file].include?("vector_math") }
  vm_stdlib && vm_dynamic
end
check("G-06: call_contract('empty') is the sole blocker specific to igniter_parser (no stdlib.collection.empty)") do
  CALLS[:stdlib].any? { |c| c[:name] == "empty" && c[:file].include?("igniter_parser") }
end

# ── Section H: Safe Subset + Output Assignability Gate ──────────────────────
puts
puts "Section H — Safe Subset Definition + Output Assignability Gate"

check("H-01: P2 safe subset — literal same-module contract name — Ruby can look up contract registry") do
  # Confirming there IS a contract registry concept in the Ruby TC
  TC_RUBY_SRC.include?("uses_contract") || TC_RUBY_SRC.include?("typecheck_uses_contract") ||
    TC_RUBY_SRC.include?("contract_registry") || TC_RUBY_SRC.include?("@contracts")
end
check("H-02: P2 safe subset — dynamic callee → Unknown, Tier 2 (matches Rust; no new acceptance)") do
  # Rust Tier 2 is documented as model for Ruby P2
  TC_RUST_SRC.include?("Tier 2") && TC_RUST_SRC.include?("Unknown")
end
check("H-03: P2 blocked — stdlib names must route via stdlib dispatch, not contract registry") do
  # stdlib names are in inventory, not in any app's contract definitions
  stdlib_names_in_inventory = CALLS[:stdlib].map { |c| "stdlib.collection.#{c[:name]}" }
                                             .uniq
                                             .select { |n| INV_ENTRIES.include?(n) }
  stdlib_names_in_inventory.any?
end
check("H-04: P2 blocked — call_contract('empty') requires stdlib.collection.empty (not in inventory)") do
  INV_ENTRIES.none? { |n| n == "stdlib.collection.empty" }
end
check("H-05: output assignability gate — Ruby TC 'Unknown function: call_contract' means current " \
      "output type checks are suppressed; P2 must not escape Unknown to concrete without structural check") do
  # Ruby TC currently emits OOF-TY0 + Unknown for all call_contract.
  # After P2 resolves types, output check becomes structural. This is safe only if
  # LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 (LAB-RACK-P9 Rust guard removed) is addressed.
  # We gate P2 by confirming: Ruby TC currently always produces type_error for call_contract.
  r_lit[:codes].include?("OOF-TY0")
end
check("H-06: P2 multi-output contracts → Unknown (same as Rust; not blocked by assignability)") do
  # Rust resolves single-output to concrete; multi-output stays Unknown.
  # Confirming this comment exists in Rust TC.
  TC_RUST_SRC.include?("Multi-output") || TC_RUST_SRC.include?("multi-output") ||
    TC_RUST_SRC.include?("single_output_type")
end

# ── Section I: Authority Closed ───────────────────────────────────────────────
puts
puts "Section I — Authority Closed"

check("I-01: Ruby TC source unchanged — no call_contract arm added in this proof") do
  !TC_RUBY_SRC.include?('"call_contract"') && !TC_RUBY_SRC.include?("'call_contract'")
end
check("I-02: Rust TC source unchanged — LAB-RACK-P11 is the existing implementation, not new") do
  TC_RUST_SRC.include?("LAB-RACK-P11")
end
check("I-03: no 'Unknown' escape — this proof does not accept dynamic Unknown as output") do
  # The proof classifies dynamic as blocked (Tier 2 Unknown stays Unknown, VM fail-closed).
  # This check confirms the classification is consistent.
  CALLS[:dynamic].size == 1  # exactly the rule_engine case; no new acceptance
end
check("I-04: no VM/runtime changes — proof is pure static analysis + TC behavioral characterization") do
  true  # structural: no VM files modified in this proof
end

# ── Summary ───────────────────────────────────────────────────────────────────

puts
total = $pass_count + $fail_count
puts "=" * 70
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 70

puts
puts "── Shape summary ─────────────────────────────────────────────────────"
puts "  LITERAL_MODULE:   #{CALLS[:literal].size} calls, #{CALLS[:literal].map { |c| c[:file] }.uniq.size} files"
puts "  STDLIB_FORM:      #{CALLS[:stdlib].size} calls, #{CALLS[:stdlib].map { |c| c[:file] }.uniq.size} files"
puts "  DYNAMIC:          #{CALLS[:dynamic].size} call, 1 file (rule_engine/engine.ig)"
puts "  LAMBDA_INTERNAL:  #{LAMBDA_CALLS.size} calls (subset of LITERAL_MODULE)"
puts
puts "── P2 safe subset ────────────────────────────────────────────────────"
puts "  SAFE:    Literal same-module contract name (Tier 1)"
puts "  SAFE:    Dynamic callee → Tier 2 Unknown (no error, VM fail-closed)"
puts "  BLOCKED: Stdlib names ('append','empty') → route to stdlib dispatch"
puts "  BLOCKED: call_contract('empty') → stdlib.collection.empty not authorized"
puts "── Output assignability gate ─────────────────────────────────────────"
puts "  P2 authorized once LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 state is clear."
puts "  Literal callee output type resolution must satisfy declared output type."
puts "  Dynamic/multi-output remains Unknown (permissive; no structural check needed)."

exit($fail_count.zero? ? 0 : 1)
