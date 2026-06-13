#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_rule_engine_baseline_p1.rb
# LAB-RULE-ENGINE-BASELINE-P1 — Freeze rule_engine blocked baseline
#
# Purpose: Pin the current blocked state of rule_engine after dynamic-dispatch,
# output-assignability, and Unknown-field-access safety work. Goal is NOT to
# unblock rule_engine — it is to ensure future work cannot accidentally weaken
# the safety boundary.
#
# Frozen diagnostics (Wave P7):
#   Rust TC: oof / 2× OOF-TY1
#     "Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]"
#     "Output type mismatch: expected RuleDecision, got Unknown"
#   Ruby TC: oof / 2× OOF-P1
#     "Unresolved symbol: d"
#     "Unresolved field: Unknown.action"
#
# Sections:
#   A  Preconditions — compiler binary + source files exist          (5)
#   B  Rust TC status and diagnostic count frozen                    (6)
#   C  Rust OOF-TY1 messages frozen                                  (5)
#   D  Ruby TC diagnostic count and messages frozen                  (6)
#   E  Dynamic callee site classified and quarantined                (5)
#   F  Unknown field access site classified and policy confirmed     (5)
#   G  Source integrity — no app source changes                      (5)
#   H  Safety policy assertions                                      (5)
#   I  Liveness counters within bounds                               (5)
#   J  Closed surfaces — no implementation, no regression            (5)
#
# Total: 52 checks
#
# Closed surfaces:
#   No compiler or TC source changes.
#   No app source changes.
#   No dynamic dispatch implementation.
#   No validation receipt semantics.
#   No new OOF codes.
#
# Authority: lab-only evidence — no canon claim.
# Card: LAB-RULE-ENGINE-BASELINE-P1
# Date: 2026-06-13

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

# ── Paths ─────────────────────────────────────────────────────────────────────

PROOFS_DIR   = Pathname.new(__dir__).expand_path
LAB_ROOT     = PROOFS_DIR.parent.parent
LANG_ROOT    = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

RE_DIR   = LAB_ROOT / "igniter-apps" / "rule_engine"
CARD_DIR = LAB_ROOT / ".agents" / "work" / "cards" / "lab"

RE_SOURCE_FILES = %w[types.ig rules.ig engine.ig example.ig].map { |f| RE_DIR / f }

EXPECTED_RUST_DIAG_COUNT = 2
EXPECTED_RUBY_DIAG_COUNT = 2
FROZEN_SOURCE_HASH       = "sha256:0cf7f61465246aedb46242c9c6c36add39f9d71956950461a7831e9bdc22486b"
LIVENESS_FATAL_LIMIT     = 1000
FROZEN_TC_INFER_DEPTH    = 6
FROZEN_FR_WALK_DEPTH     = 6

# ── Load Ruby TC ──────────────────────────────────────────────────────────────

$LOAD_PATH.unshift (LANG_ROOT / "lib").to_s
require "igniter_lang"

# ── Helpers ───────────────────────────────────────────────────────────────────

def run_ruby_tc(src)
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: "inline").to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  IgniterLang::TypeChecker.new.typecheck(classified)
rescue => e
  { "type_errors" => [{ "rule" => "ERROR", "message" => e.message }] }
end

def type_errors(r)       = Array(r["type_errors"] || [])
def oof_rules(r)         = type_errors(r).map { |e| e["rule"] || "" }
def oof_msgs(r)          = type_errors(r).map { |e| e["message"] || "" }
def has_oof?(r, code)    = oof_rules(r).include?(code)
def oof_count(r, code)   = oof_rules(r).count(code)
def msg_contains(r, sub) = oof_msgs(r).any? { |m| m.include?(sub) }

TMPDIR = Dir.mktmpdir("rule_engine_baseline_p1_")
at_exit { FileUtils.rm_rf(TMPDIR) }

def compile_rust(*files, label: "")
  out = File.join(TMPDIR, "#{label.gsub(/\W/, "_")}.igapp")
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *files.map(&:to_s), "--out", out
  )
  JSON.parse(stdout.force_encoding("UTF-8")) rescue { "status" => "parse_error" }
end

# ── Check harness ─────────────────────────────────────────────────────────────

$pass = 0
$fail = 0

def check(label)
  result = yield
  if result
    $pass += 1
    puts "  PASS  #{label}"
  else
    $fail += 1
    puts "  FAIL  #{label}"
  end
rescue => e
  $fail += 1
  puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n─── #{title} #{'─' * [0, 68 - title.length].max}"
end

# ══════════════════════════════════════════════════════════════════════════════
# Compile once; reuse across sections
# ══════════════════════════════════════════════════════════════════════════════

puts "\n[*] Compiling rule_engine with Rust TC..."
RUST_RESULT = compile_rust(*RE_SOURCE_FILES, label: "rule_engine_p1")
RUST_DIAGS  = Array(RUST_RESULT["diagnostics"] || [])
RUST_LIVE   = RUST_RESULT["liveness_instrumentation"] || {}

puts "[*] Running Ruby TC inline on rule_engine source..."
RE_SRC_ALL = RE_SOURCE_FILES.map { |f| File.read(f.to_s, encoding: "utf-8") }.join("\n\n")
RUBY_RESULT = run_ruby_tc(RE_SRC_ALL)
RUBY_ERRS   = type_errors(RUBY_RESULT)

ENGINE_SRC  = File.read((RE_DIR / "engine.ig").to_s,  encoding: "utf-8")
TYPES_SRC   = File.read((RE_DIR / "types.ig").to_s,   encoding: "utf-8")
RULES_SRC   = File.read((RE_DIR / "rules.ig").to_s,   encoding: "utf-8")
EXAMPLE_SRC = File.read((RE_DIR / "example.ig").to_s, encoding: "utf-8")

# ══════════════════════════════════════════════════════════════════════════════
# Section A — Preconditions
# ══════════════════════════════════════════════════════════════════════════════

section("A  Preconditions — compiler binary + source files exist")

check("A-01: Rust compiler binary exists and is executable") do
  File.executable?(COMPILER_BIN.to_s)
end
%w[types.ig rules.ig engine.ig example.ig].each_with_index do |f, i|
  check("A-#{format('%02d', i + 2)}: source file exists — #{f}") do
    File.exist?((RE_DIR / f).to_s)
  end
end

# ══════════════════════════════════════════════════════════════════════════════
# Section B — Rust TC status and diagnostic count frozen
# ══════════════════════════════════════════════════════════════════════════════

section("B  Rust TC status and diagnostic count frozen")

check("B-01: Rust TC status is 'oof' (blocked, not ok — safety-positive)") do
  RUST_RESULT["status"] == "oof"
end

check("B-02: Rust TC has exactly #{EXPECTED_RUST_DIAG_COUNT} diagnostics") do
  RUST_DIAGS.size == EXPECTED_RUST_DIAG_COUNT
end

check("B-03: all Rust diagnostics are OOF-TY1") do
  RUST_DIAGS.all? { |d| d["rule"] == "OOF-TY1" }
end

check("B-04: no OOF-P1 in Rust diagnostics (HOF lambda silencing documented in LAB-UNKNOWN-FIELD-ACCESS-P1)") do
  RUST_DIAGS.none? { |d| d["rule"] == "OOF-P1" }
end

check("B-05: no OOF-TY0 in Rust diagnostics") do
  RUST_DIAGS.none? { |d| d["rule"] == "OOF-TY0" }
end

check("B-06: Rust source hash matches frozen baseline") do
  RUST_RESULT["source_hash"] == FROZEN_SOURCE_HASH
end

# ══════════════════════════════════════════════════════════════════════════════
# Section C — Rust OOF-TY1 messages frozen
# ══════════════════════════════════════════════════════════════════════════════

section("C  Rust OOF-TY1 messages frozen (exact text + node names)")

oof_ty1_diags = RUST_DIAGS.select { |d| d["rule"] == "OOF-TY1" }

check("C-01: Rust diag-1 message contains 'expected Collection[RuleDecision], got Collection[Unknown]'") do
  oof_ty1_diags.any? { |d| d["message"].to_s.include?("expected Collection[RuleDecision], got Collection[Unknown]") }
end

check("C-02: Rust diag-1 node is 'active_decisions'") do
  oof_ty1_diags.any? { |d|
    d["message"].to_s.include?("Collection[RuleDecision]") && d["node"].to_s == "active_decisions"
  }
end

check("C-03: Rust diag-2 message contains 'expected RuleDecision, got Unknown'") do
  oof_ty1_diags.any? { |d| d["message"].to_s.include?("expected RuleDecision, got Unknown") }
end

check("C-04: Rust diag-2 node is 'decision'") do
  oof_ty1_diags.any? { |d|
    d["message"].to_s.include?("expected RuleDecision, got Unknown") && d["node"].to_s == "decision"
  }
end

check("C-05: no additional OOF-TY1 nodes beyond active_decisions and decision") do
  valid_nodes = %w[active_decisions decision]
  oof_ty1_diags.all? { |d| valid_nodes.include?(d["node"].to_s) }
end

# ══════════════════════════════════════════════════════════════════════════════
# Section D — Ruby TC diagnostic count and messages frozen
# ══════════════════════════════════════════════════════════════════════════════

section("D  Ruby TC diagnostic count and messages frozen")

check("D-01: Ruby TC returns exactly #{EXPECTED_RUBY_DIAG_COUNT} errors") do
  RUBY_ERRS.size == EXPECTED_RUBY_DIAG_COUNT
end

check("D-02: both Ruby errors are OOF-P1") do
  RUBY_ERRS.all? { |e| e["rule"] == "OOF-P1" }
end

check("D-03: Ruby OOF-P1 message-1 is 'Unresolved symbol: d'") do
  RUBY_ERRS.any? { |e| e["message"].to_s == "Unresolved symbol: d" }
end

check("D-04: Ruby OOF-P1 message-2 is 'Unresolved field: Unknown.action'") do
  RUBY_ERRS.any? { |e| e["message"].to_s == "Unresolved field: Unknown.action" }
end

check("D-05: no OOF-TY1 in Ruby (OOF-P1 upstream blocks OOF-TY1 cascade)") do
  RUBY_ERRS.none? { |e| e["rule"] == "OOF-TY1" }
end

check("D-06: no OOF-TY0 in Ruby") do
  RUBY_ERRS.none? { |e| e["rule"] == "OOF-TY0" }
end

# ══════════════════════════════════════════════════════════════════════════════
# Section E — Dynamic callee site classified and quarantined
# ══════════════════════════════════════════════════════════════════════════════

section("E  Dynamic callee site — classified Tier 2 / quarantined")

check("E-01: engine.ig contains dynamic callee `call_contract(r, t)` (variable r, not a literal)") do
  ENGINE_SRC.include?("call_contract(r, t)")
end

check("E-02: engine.ig dynamic callee is inside a map HOF lambda (`map(rules, r -> call_contract(r, t)`)") do
  ENGINE_SRC.include?("map(rules, r ->") && ENGINE_SRC.include?("call_contract(r, t)")
end

check("E-03: dynamic callee output propagates as Collection[Unknown] — Rust OOF-TY1 message confirms") do
  RUST_DIAGS.any? { |d| d["message"].to_s.include?("Collection[Unknown]") }
end

check("E-04: exactly 1 dynamic callee pattern in engine.ig (no literal string callee in ExecuteRules)") do
  # call_contract(r, t) is the only call_contract in engine.ig — r is a variable
  count = ENGINE_SRC.scan(/call_contract\s*\(/).size
  count == 1 && ENGINE_SRC.include?("call_contract(r, t)")
end

check("E-05: example.ig uses only literal string callees (no variable callee — Tier 1 pattern)") do
  # example.ig uses call_contract("ExecuteRules", ...) — literal string
  EXAMPLE_SRC.include?('call_contract("ExecuteRules"') &&
    !EXAMPLE_SRC.match?(/call_contract\([a-z_][a-zA-Z_0-9]*\s*,/)
end

# ══════════════════════════════════════════════════════════════════════════════
# Section F — Unknown field access site classified and policy confirmed
# ══════════════════════════════════════════════════════════════════════════════

section("F  Unknown field access — blocked in Ruby, silenced+compensated in Rust")

check("F-01: engine.ig contains `d.action` field access inside filter lambda") do
  ENGINE_SRC.include?("d.action")
end

check("F-02: `d.action` is inside a filter HOF lambda (`filter(raw_decisions, d ->`)") do
  ENGINE_SRC.include?("filter(raw_decisions, d ->") && ENGINE_SRC.include?("d.action")
end

check("F-03: Ruby fires OOF-P1 for lambda param d bound to Unknown element of Collection[Unknown]") do
  RUBY_ERRS.any? { |e| e["rule"] == "OOF-P1" && e["message"].to_s.include?("Unresolved symbol: d") }
end

check("F-04: Ruby fires OOF-P1 cascade for field access on Unknown ('Unresolved field: Unknown.action')") do
  RUBY_ERRS.any? { |e| e["rule"] == "OOF-P1" && e["message"].to_s.include?("Unresolved field: Unknown.action") }
end

check("F-05: Rust silences OOF-P1 in HOF lambda (temp_errors) — Rust diags have no OOF-P1") do
  RUST_DIAGS.none? { |d| d["rule"] == "OOF-P1" }
end

# ══════════════════════════════════════════════════════════════════════════════
# Section G — Source integrity — no app source changes
# ══════════════════════════════════════════════════════════════════════════════

section("G  Source integrity — app source unchanged")

check("G-01: types.ig declares Transaction and RuleDecision types") do
  TYPES_SRC.include?("type Transaction") && TYPES_SRC.include?("type RuleDecision")
end

check("G-02: rules.ig has all 3 rule contracts") do
  %w[HighValueRule ForeignCurrencyRule FraudScoreRule].all? { |c| RULES_SRC.include?("contract #{c}") }
end

check("G-03: engine.ig has exactly 1 contract (ExecuteRules)") do
  ENGINE_SRC.include?("contract ExecuteRules") &&
    ENGINE_SRC.scan(/^contract\s+/).size == 1
end

check("G-04: example.ig has RunRuleEngine contract with 3 literal rule names") do
  EXAMPLE_SRC.include?("contract RunRuleEngine") &&
    EXAMPLE_SRC.include?('"HighValueRule"') &&
    EXAMPLE_SRC.include?('"ForeignCurrencyRule"') &&
    EXAMPLE_SRC.include?('"FraudScoreRule"')
end

check("G-05: source hash is stable across two Rust compile runs") do
  result2 = compile_rust(*RE_SOURCE_FILES, label: "rule_engine_p1_second")
  result2["source_hash"] == FROZEN_SOURCE_HASH
end

# ══════════════════════════════════════════════════════════════════════════════
# Section H — Safety policy assertions
# ══════════════════════════════════════════════════════════════════════════════

section("H  Safety policy assertions")

check("H-01: dynamic callee + typed output = BLOCKED (Rust OOF-TY1 D2 rule confirmed active)") do
  RUST_DIAGS.any? { |d| d["rule"] == "OOF-TY1" }
end

check("H-02: both Ruby and Rust block the unsafe path — neither compiles cleanly") do
  RUBY_ERRS.size >= 1 && RUST_RESULT["status"] == "oof"
end

check("H-03: engine.ig has no `output : Unknown` — typed output annotation = BLOCKED (not quarantined)") do
  !ENGINE_SRC.include?("output active_decisions : Unknown") &&
    ENGINE_SRC.include?("output active_decisions : Collection[RuleDecision]")
end

check("H-04: no validation receipt, no type cast, no type narrowing in engine.ig source") do
  !ENGINE_SRC.include?("receipt") &&
    !ENGINE_SRC.include?("cast(") &&
    !ENGINE_SRC.include?("narrow(")
end

check("H-05: RuleDecision.action field is declared as String (concrete type — not Unknown)") do
  TYPES_SRC.include?("action : String") && TYPES_SRC.include?("RuleDecision")
end

# ══════════════════════════════════════════════════════════════════════════════
# Section I — Liveness counters within bounds
# ══════════════════════════════════════════════════════════════════════════════

section("I  Liveness counters within bounds")

live_counters = (RUST_LIVE["counters"] || {})
live_breaches = Array(RUST_LIVE["breaches"] || [])

check("I-01: liveness_instrumentation present in Rust compile result") do
  !RUST_LIVE.empty?
end

check("I-02: no liveness breaches") do
  live_breaches.empty?
end

check("I-03: tc_infer max_depth matches frozen value (#{FROZEN_TC_INFER_DEPTH})") do
  live_counters["typechecker.infer_expr.max_depth"].to_i == FROZEN_TC_INFER_DEPTH
end

check("I-04: fr_walk max_depth matches frozen value (#{FROZEN_FR_WALK_DEPTH})") do
  live_counters["form_resolver.walk_expr.max_depth"].to_i == FROZEN_FR_WALK_DEPTH
end

check("I-05: both tc_infer and fr_walk are below fatal limit (#{LIVENESS_FATAL_LIMIT})") do
  live_counters["typechecker.infer_expr.max_depth"].to_i < LIVENESS_FATAL_LIMIT &&
    live_counters["form_resolver.walk_expr.max_depth"].to_i < LIVENESS_FATAL_LIMIT
end

# ══════════════════════════════════════════════════════════════════════════════
# Section J — Closed surfaces — no implementation, no regression
# ══════════════════════════════════════════════════════════════════════════════

section("J  Closed surfaces — no implementation, no regression")

LAB_DISPATCH_CARD = (CARD_DIR / "LAB-DYNAMIC-CONTRACT-DISPATCH-P1.md").to_s
LAB_FIELD_CARD    = (CARD_DIR / "LAB-UNKNOWN-FIELD-ACCESS-P1.md").to_s
P4_CARD           = (CARD_DIR / "LANG-OUTPUT-TYPE-ASSIGNABILITY-P4.md").to_s

check("J-01: LAB-DYNAMIC-CONTRACT-DISPATCH-P1 card is CLOSED") do
  File.exist?(LAB_DISPATCH_CARD) &&
    File.read(LAB_DISPATCH_CARD, encoding: "utf-8").include?("CLOSED")
end

check("J-02: LAB-UNKNOWN-FIELD-ACCESS-P1 card is CLOSED") do
  File.exist?(LAB_FIELD_CARD) &&
    File.read(LAB_FIELD_CARD, encoding: "utf-8").include?("CLOSED")
end

check("J-03: LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 card is CLOSED") do
  File.exist?(P4_CARD) &&
    File.read(P4_CARD, encoding: "utf-8").include?("CLOSED")
end

check("J-04: engine.ig comment documents Tier 2 VM delegation (dynamic call intent preserved)") do
  ENGINE_SRC.include?("Tier 2") || ENGINE_SRC.include?("dynamic") || ENGINE_SRC.include?("VM")
end

check("J-05: no dynamic dispatch implementation — engine.ig has no dispatch_table, receipt, or narrowing") do
  !ENGINE_SRC.include?("dispatch_table") &&
    !ENGINE_SRC.include?("receipt") &&
    !ENGINE_SRC.include?("type_narrow")
end

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

puts
total = $pass + $fail
puts "=" * 68
puts "Result: #{$pass}/#{total} PASS  |  #{$fail} FAIL"
puts "=" * 68
if $fail.zero?
  puts "VERDICT: PASS — LAB-RULE-ENGINE-BASELINE-P1 PROVED"
  puts
  puts "  Rust TC blocked:   #{EXPECTED_RUST_DIAG_COUNT}× OOF-TY1 (Collection[Unknown] + Unknown output)"
  puts "  Ruby TC blocked:   #{EXPECTED_RUBY_DIAG_COUNT}× OOF-P1  (Unresolved symbol:d + field:Unknown.action)"
  puts "  Dynamic callee:    QUARANTINED (Tier 2 — engine.ig:17-18)"
  puts "  Unknown field:     BLOCKED-Ruby / SILENCED+OOF-TY1-Rust (engine.ig:27)"
  puts "  Source hash:       #{FROZEN_SOURCE_HASH}"
  puts "  Unblock route:     NONE in current stage"
else
  puts "VERDICT: FAIL"
end
puts
exit($fail.zero? ? 0 : 1)
