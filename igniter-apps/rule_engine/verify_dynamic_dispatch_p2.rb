#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_dynamic_dispatch_p2.rb
# LAB-DYNAMIC-CONTRACT-DISPATCH-P2 — Safe Route for Dynamic Contract Dispatch
#
# Purpose: prove the safe-route decision for `rule_engine` Tier 2 dynamic
# contract dispatch (`map(rules, r -> call_contract(r, t))`) without weakening
# the safety model. The decision is:
#
#   ROUTE = DEFER (implementation) + NO-CHANGE (rule_engine source) +
#           PRESERVE fail-closed. The single sanctioned forward design is a
#           STATIC, COMPILE-TIME-RESOLVED typed closed strategy union / typed
#           contract reference — itself canon-gated, not implemented here.
#
# Proof axiom: a check PASSES when it precisely characterises observed compiler
# behaviour or confirms a policy boundary. "PASS" never means "dynamic dispatch
# is safe" and never means "rule_engine is unblocked."
#
# This runner asserts the CURRENT diagnostic form (post LAB-HOF-LAMBDA-ERROR-
# PROPAGATION-P2 / Wave P9-P10), which differs from the P1 runner's frozen form:
#   Rust:  OOF-P1 (Unresolved field: Unknown.action) + OOF-TY1 (RuleDecision/Unknown)
#   Ruby:  OOF-P1 (Unresolved symbol: d) + OOF-P1 (Unresolved field: Unknown.action)
#
# Sections:
#   A  Preconditions — compiler binary + source census                 (6)
#   B  Rust TC — rule_engine current fail-closed form                  (7)
#   C  Ruby TC — rule_engine current fail-closed form                  (5)
#   D  Tier 2 dynamic callee classification (Ruby inline)              (7)
#   E  trade_robot static-dispatch baseline (dual-clean, literal)      (6)
#   F  Safe-route design properties (static typed dispatch proxy)      (5)
#   G  Closed surfaces — duck typing / field / coercion / stringly     (6)
#   H  Route decision assertions — DEFER + NO-CHANGE + canon gate      (5)
#
# Total: 47 checks
#
# Closed surfaces:
#   No dynamic dispatch implementation. No permissive Unknown.action.
#   No Collection[Unknown] -> Collection[T] coercion. No stringly runtime
#   authority. No VM/runtime reflection. No app source migration.
#   No new OOF codes. No compiler source changes.
#
# Authority: lab-only policy/proof planning — no canon claim, no stable-API.
# Card: LAB-DYNAMIC-CONTRACT-DISPATCH-P2
# Date: 2026-06-14

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

# ── Paths ─────────────────────────────────────────────────────────────────────

APP_DIR      = Pathname.new(__dir__).expand_path
LAB_ROOT     = APP_DIR.parent.parent           # igniter-lab/
LANG_ROOT    = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

RE_FILES = %w[types.ig rules.ig engine.ig example.ig].map { |f| APP_DIR / f }

TRADE_ROBOT_DIR = LAB_ROOT / "igniter-apps" / "trade_robot"
TR_FILES = %w[types.ig indicators.ig signals.ig strategy.ig robot.ig backtester.ig example.ig]
           .map { |f| TRADE_ROBOT_DIR / f }

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
def no_errors(r)         = type_errors(r).empty?
def msg_contains(r, sub) = oof_msgs(r).any? { |m| m.include?(sub) }

def resolved_type(r, contract, decl)
  c = Array(r["contracts"]).find { |c| c["name"] == contract }
  return nil unless c
  # The TC records resolved symbol types under `symbols`; declarations carry
  # only structural info. Prefer the symbol table.
  sym = Array(c["symbols"]).find { |s| s["name"] == decl }
  if sym
    t = sym.dig("type", "name")
    return t if t
  end
  d = Array(c["typed_declarations"] || c["declarations"]).find { |d| d["name"] == decl }
  return nil unless d
  d.dig("resolved_type", "name") || d.dig("typed_expr", "resolved_type", "name")
end

def compile_rust(*files, tmpdir:)
  out = File.join(tmpdir, "out.igapp")
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *files.map(&:to_s), "--out", out
  )
  JSON.parse(stdout.force_encoding("UTF-8")) rescue { "status" => "parse_error", "_raw" => stdout }
end

def rust_diags(result) = Array(result["diagnostics"] || [])
def rust_has?(result, code, *substrs)
  rust_diags(result).any? do |d|
    d["rule"] == code && substrs.all? { |s| d["message"].to_s.include?(s) }
  end
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
# Compile real apps once (Rust); reuse across sections
# ══════════════════════════════════════════════════════════════════════════════

RE_TMPDIR = Dir.mktmpdir("dyn_dispatch_p2_re_")
TR_TMPDIR = Dir.mktmpdir("dyn_dispatch_p2_tr_")
at_exit { FileUtils.rm_rf(RE_TMPDIR); FileUtils.rm_rf(TR_TMPDIR) }

puts "\n[*] Compiling rule_engine with Rust TC (fail-closed evidence app)..."
RE_RUST = compile_rust(*RE_FILES, tmpdir: RE_TMPDIR)
RE_RUST_DIAGS = rust_diags(RE_RUST)

puts "[*] Compiling trade_robot with Rust TC (positive static-dispatch baseline)..."
TR_RUST = compile_rust(*TR_FILES, tmpdir: TR_TMPDIR)

# Ruby compile of rule_engine (joined source — matches Wave recheck method)
RE_RUBY = run_ruby_tc(RE_FILES.map { |f| File.read(f, encoding: "utf-8") }.join("\n"))
# Ruby compile of trade_robot (joined source)
TR_RUBY = run_ruby_tc(TR_FILES.map { |f| File.read(f, encoding: "utf-8") }.join("\n"))

# ══════════════════════════════════════════════════════════════════════════════
# Section A — Preconditions
# ══════════════════════════════════════════════════════════════════════════════

section("A  Preconditions — compiler binary + source census")

check("A-01: Rust compiler binary exists and is executable") do
  File.executable?(COMPILER_BIN.to_s)
end

check("A-02: engine.ig still contains the Tier 2 dynamic callee `call_contract(r, t)`") do
  File.read(APP_DIR / "engine.ig", encoding: "utf-8").include?("call_contract(r, t)")
end

check("A-03: engine.ig has exactly one dynamic (variable) callee site") do
  src = File.read(APP_DIR / "engine.ig", encoding: "utf-8")
  src.scan(/call_contract\([a-z_]\w*,/).length == 1
end

check("A-04: engine.ig output annotation stays concrete Collection[RuleDecision] (not quarantined to Unknown)") do
  File.read(APP_DIR / "engine.ig", encoding: "utf-8")
      .include?("output active_decisions : Collection[RuleDecision]")
end

check("A-05: trade_robot RobotConfig carries strategy_name but StrategyDispatcher hardcodes a literal callee") do
  robot = File.read(TRADE_ROBOT_DIR / "robot.ig", encoding: "utf-8")
  types = File.read(TRADE_ROBOT_DIR / "types.ig", encoding: "utf-8")
  types.include?("strategy_name") &&
    robot.include?('call_contract("CombinedStrategy"') &&
    robot.scan(/call_contract\([a-z_]\w*,/).empty?   # no variable callee in trade_robot
end

check("A-06: rule_engine remains the sole app with a variable callee in the fleet sample") do
  re_dynamic = File.read(APP_DIR / "engine.ig", encoding: "utf-8").scan(/call_contract\([a-z_]\w*,/).length
  tr_dynamic = TR_FILES.sum { |f| File.read(f, encoding: "utf-8").scan(/call_contract\([a-z_]\w*,/).length }
  re_dynamic == 1 && tr_dynamic == 0
end

# ══════════════════════════════════════════════════════════════════════════════
# Section B — Rust TC: rule_engine current fail-closed form
# ══════════════════════════════════════════════════════════════════════════════

section("B  Rust TC — rule_engine current fail-closed form")

check("B-01: Rust status is 'oof' (diagnostics present — not silent, not clean)") do
  RE_RUST["status"] == "oof"
end

check("B-02: exactly 2 Rust diagnostics (frozen count)") do
  RE_RUST_DIAGS.length == 2
end

check("B-03: Rust emits OOF-P1 'Unresolved field: Unknown.action' (HOF body propagated post-P2)") do
  rust_has?(RE_RUST, "OOF-P1", "Unresolved field", "Unknown.action")
end

check("B-04: Rust emits OOF-TY1 'expected RuleDecision, got Unknown' (output boundary D2)") do
  rust_has?(RE_RUST, "OOF-TY1", "RuleDecision", "Unknown")
end

check("B-05: Rust OOF-TY1 message is the element-level mismatch (no Collection[Unknown] coercion accepted)") do
  # Post HOF-P2 the collection-level OOF-TY1 is suppressed by the upstream OOF-P1;
  # the surviving OOF-TY1 is the element check. Either way, no Unknown->concrete passes.
  rust_has?(RE_RUST, "OOF-TY1", "RuleDecision") &&
    !RE_RUST_DIAGS.any? { |d| d["rule"] == "OOF-TY1" && d["message"].to_s.include?("Collection[RuleDecision], got Collection[RuleDecision]") }
end

check("B-06: Rust diagnostics use only known OOF codes (no new code introduced)") do
  known = %w[OOF-P1 OOF-TY0 OOF-TY1 OOF-COL3 OOF-IMP2]
  RE_RUST_DIAGS.all? { |d| known.include?(d["rule"]) }
end

check("B-07: Rust does NOT silently accept — at least one Unknown-rejecting diagnostic present") do
  RE_RUST_DIAGS.any? { |d| %w[OOF-TY1 OOF-P1].include?(d["rule"]) }
end

# ══════════════════════════════════════════════════════════════════════════════
# Section C — Ruby TC: rule_engine current fail-closed form
# ══════════════════════════════════════════════════════════════════════════════

section("C  Ruby TC — rule_engine current fail-closed form")

check("C-01: Ruby produces exactly 2 diagnostics (frozen count)") do
  type_errors(RE_RUBY).length == 2
end

check("C-02: Ruby emits OOF-P1 'Unresolved symbol: d' (Tier 2 result unbound)") do
  type_errors(RE_RUBY).any? { |e| e["rule"] == "OOF-P1" && e["message"].to_s.include?("Unresolved symbol: d") }
end

check("C-03: Ruby emits OOF-P1 'Unresolved field: Unknown.action' (field access on Unknown blocked)") do
  type_errors(RE_RUBY).any? { |e| e["rule"] == "OOF-P1" && e["message"].to_s.include?("Unresolved field: Unknown.action") }
end

check("C-04: Ruby diagnostics are all OOF-P1 (no coercion, no permissive pass)") do
  oof_rules(RE_RUBY).all? { |r| r == "OOF-P1" } && !no_errors(RE_RUBY)
end

check("C-05: Ruby and Rust agree the pipeline is blocked (both 'oof', neither clean)") do
  !no_errors(RE_RUBY) && RE_RUST["status"] == "oof"
end

# ══════════════════════════════════════════════════════════════════════════════
# Section D — Tier 2 dynamic callee classification (Ruby inline)
# ══════════════════════════════════════════════════════════════════════════════

section("D  Tier 2 dynamic callee classification (Ruby inline)")

SRC_T2_UNKNOWN_OUT = <<~IG
  module DynTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    output r : Unknown
  }
IG

SRC_T2_TYPED_OUT = <<~IG
  module DynTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    output r : String
  }
IG

SRC_T2_FIELD_ACCESS = <<~IG
  module FieldTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    compute f = r.action
    output f : Unknown
  }
IG

R_T2_UNKNOWN = run_ruby_tc(SRC_T2_UNKNOWN_OUT)
R_T2_TYPED   = run_ruby_tc(SRC_T2_TYPED_OUT)
R_T2_FIELD   = run_ruby_tc(SRC_T2_FIELD_ACCESS)

check("D-01: Tier 2 callee itself raises no 'Unknown function' error (P3 binding handles variable callee)") do
  !msg_contains(R_T2_UNKNOWN, "Unknown function")
end

check("D-02: QUARANTINE — Tier 2 + explicit `output : Unknown` compiles clean (D3 escape hatch)") do
  no_errors(R_T2_UNKNOWN)
end

check("D-03: BLOCKED — Tier 2 + concrete typed output rejected by OOF-TY1") do
  has_oof?(R_T2_TYPED, "OOF-TY1")
end

check("D-04: BLOCKED message names Unknown as the source type (honest, no upward coercion)") do
  msg_contains(R_T2_TYPED, "Unknown")
end

check("D-05: CLOSED — field access on Tier 2 Unknown result raises OOF-P1 (no duck typing)") do
  has_oof?(R_T2_FIELD, "OOF-P1") && msg_contains(R_T2_FIELD, "Unknown.action")
end

check("D-06: Tier 2 result is Unknown, not narrowed — Unknown-out passes, typed-out fails (proves the type)") do
  no_errors(R_T2_UNKNOWN) && has_oof?(R_T2_TYPED, "OOF-TY1")
end

check("D-07: `output : Unknown` quarantine is NOT a clean route for field-access pipelines (OOF-P1 survives)") do
  # The exact rule_engine shape: Unknown output annotation does not silence field access on Unknown.
  !no_errors(R_T2_FIELD)
end

# ══════════════════════════════════════════════════════════════════════════════
# Section E — trade_robot static-dispatch baseline (dual-clean)
# ══════════════════════════════════════════════════════════════════════════════

section("E  trade_robot static-dispatch baseline (dual-clean, literal callee)")

check("E-01: trade_robot Rust compile — status ok") do
  TR_RUST["status"] == "ok"
end

check("E-02: trade_robot Rust compile — 0 diagnostics") do
  rust_diags(TR_RUST).empty?
end

check("E-03: trade_robot Ruby compile — 0 diagnostics") do
  no_errors(TR_RUBY)
end

check("E-04: trade_robot dispatcher routes via literal callee `\"CombinedStrategy\"` (static, resolvable)") do
  File.read(TRADE_ROBOT_DIR / "robot.ig", encoding: "utf-8").include?('call_contract("CombinedStrategy", candles, config)')
end

check("E-05: trade_robot has zero variable callees (avoids dynamic strategy dispatch — TR-P06)") do
  TR_FILES.sum { |f| File.read(f, encoding: "utf-8").scan(/call_contract\([a-z_]\w*,/).length }.zero?
end

check("E-06: trade_robot proves the safe static-dispatch workaround compiles where rule_engine's dynamic form does not") do
  TR_RUST["status"] == "ok" && RE_RUST["status"] == "oof"
end

# ══════════════════════════════════════════════════════════════════════════════
# Section F — Safe-route design properties (static typed dispatch proxy)
# ══════════════════════════════════════════════════════════════════════════════
#
# The sanctioned forward design is a STATIC, compile-time-resolved typed
# dispatch: a literal/closed-set callee whose result type is known at TC time.
# We cannot test an unimplemented union feature, so we test the available proxy
# that a typed dispatch MUST satisfy: a literal callee resolves to a concrete
# output type and flows cleanly to a concrete output boundary.

section("F  Safe-route design properties (static typed dispatch proxy)")

SRC_F_STATIC_TYPED = <<~IG
  module LitTest
  pure contract RuleA {
    input n : Integer
    compute r = n + n
    output r : Integer
  }
  pure contract Caller {
    input n : Integer
    compute result = call_contract("RuleA", n)
    output result : Integer
  }
IG

SRC_F_BAD_ARITY = <<~IG
  module LitTest
  pure contract RuleA {
    input n : Integer
    compute r = n + n
    output r : Integer
  }
  pure contract Caller {
    input n : Integer
    compute result = call_contract("RuleA", n, n)
    output result : Integer
  }
IG

SRC_F_UNKNOWN_NAME = <<~IG
  module LitTest
  pure contract Caller {
    input n : Integer
    compute result = call_contract("NoSuchRule", n)
    output result : Integer
  }
IG

R_F_STATIC  = run_ruby_tc(SRC_F_STATIC_TYPED)
R_F_ARITY   = run_ruby_tc(SRC_F_BAD_ARITY)
R_F_UNKNOWN = run_ruby_tc(SRC_F_UNKNOWN_NAME)

check("F-01: static typed dispatch — literal callee resolves to concrete Integer (no Unknown introduced)") do
  no_errors(R_F_STATIC) && resolved_type(R_F_STATIC, "Caller", "result") == "Integer"
end

check("F-02: static typed dispatch — concrete result flows clean to concrete output boundary") do
  no_errors(R_F_STATIC)
end

check("F-03: fail-closed on unknown member — non-existent callee raises OOF-TY0 (closed set required)") do
  has_oof?(R_F_UNKNOWN, "OOF-TY0")
end

check("F-04: fail-closed on arity — wrong arg count raises OOF-TY0 (signature checked statically)") do
  has_oof?(R_F_ARITY, "OOF-TY0")
end

check("F-05: design invariant — static dispatch never yields Unknown; only dynamic (Tier 2) does") do
  resolved_type(R_F_STATIC, "Caller", "result") != "Unknown" &&
    no_errors(R_T2_UNKNOWN) && has_oof?(R_T2_TYPED, "OOF-TY1")
end

# ══════════════════════════════════════════════════════════════════════════════
# Section G — Closed surfaces
# ══════════════════════════════════════════════════════════════════════════════

section("G  Closed surfaces — duck typing / field / coercion / stringly")

check("G-01: CLOSED — duck typing: field access on Unknown blocked in Ruby (OOF-P1)") do
  has_oof?(R_T2_FIELD, "OOF-P1")
end

check("G-02: CLOSED — duck typing: field access on Unknown blocked in Rust (OOF-P1 in rule_engine)") do
  rust_has?(RE_RUST, "OOF-P1", "Unknown.action")
end

check("G-03: CLOSED — typed-output coercion: Unknown -> concrete rejected (OOF-TY1, both inline + app)") do
  has_oof?(R_T2_TYPED, "OOF-TY1") && rust_has?(RE_RUST, "OOF-TY1", "Unknown")
end

check("G-04: CLOSED — no Collection[Unknown] -> Collection[T] permissive pass (rule_engine stays oof)") do
  RE_RUST["status"] == "oof" && !no_errors(RE_RUBY)
end

check("G-05: CLOSED — no stringly runtime authority / no implementation artefacts in engine.ig") do
  src = File.read(APP_DIR / "engine.ig", encoding: "utf-8")
  !src.include?("receipt") && !src.include?("type_cast") &&
    !src.include?("unsafe") && !src.include?("reflect")
end

check("G-06: CLOSED — this runner adds no new OOF code; rule_engine codes are a subset of the known set") do
  known = %w[OOF-P1 OOF-TY0 OOF-TY1 OOF-COL3 OOF-IMP2]
  (RE_RUST_DIAGS.map { |d| d["rule"] } + oof_rules(RE_RUBY)).all? { |r| known.include?(r) }
end

# ══════════════════════════════════════════════════════════════════════════════
# Section H — Route decision assertions
# ══════════════════════════════════════════════════════════════════════════════

section("H  Route decision — DEFER + NO-CHANGE + canon gate")

check("H-01: ROUTE=DEFER — dynamic dispatch remains unimplemented; rule_engine still blocked dual-toolchain") do
  RE_RUST["status"] == "oof" && !no_errors(RE_RUBY)
end

check("H-02: NO-CHANGE — rule_engine source preserves the dynamic callee as fail-closed evidence") do
  File.read(APP_DIR / "engine.ig", encoding: "utf-8").include?("call_contract(r, t)")
end

check("H-03: trade_robot already carries the positive static-dispatch baseline — no migration needed for evidence") do
  TR_RUST["status"] == "ok" && no_errors(TR_RUBY)
end

check("H-04: forward design is STATIC typed dispatch (concrete result), distinct from blocked dynamic form") do
  no_errors(R_F_STATIC) && resolved_type(R_F_STATIC, "Caller", "result") == "Integer" &&
    has_oof?(R_T2_TYPED, "OOF-TY1")
end

check("H-05: canon gate — no lab artefact here narrows Unknown to RuleDecision; the boundary holds") do
  # The ONLY clean Tier 2 path is `output : Unknown` (quarantine), which grants no
  # capability and does not survive field access. No narrowing exists.
  no_errors(R_T2_UNKNOWN) && !no_errors(R_T2_FIELD) && has_oof?(R_T2_TYPED, "OOF-TY1")
end

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

puts
total = $pass + $fail
status = $fail.zero? ? "PASS" : "FAIL"
puts "Result: #{$pass}/#{total} PASS"
puts "VERDICT: #{status} — LAB-DYNAMIC-CONTRACT-DISPATCH-P2 #{$fail.zero? ? 'PROVED' : 'INCOMPLETE'}"
puts
puts "  ROUTE DECISION: DEFER (implementation) + NO-CHANGE (rule_engine source) + PRESERVE fail-closed"
puts
puts "  rule_engine (Tier 2 dynamic callee):  BLOCKED — Rust oof/2, Ruby oof/2 (fail-closed evidence)"
puts "  trade_robot (static literal dispatch): DUAL-CLEAN — Rust ok/0, Ruby ok/0 (positive baseline)"
puts
puts "  ACCEPTED:    Tier 1 literal / static closed-set dispatch — concrete result type"
puts "  QUARANTINED: Tier 2 + explicit `output : Unknown` — no capability, not a clean field-access route"
puts "  BLOCKED:     Tier 2 + typed output — OOF-TY1 at boundary (D2)"
puts "  CLOSED:      duck typing, Unknown field access, typed-output coercion, stringly runtime authority"
puts
puts "  FORWARD DESIGN (canon-gated, NOT implemented here):"
puts "    Static, compile-time-resolved typed closed strategy union / typed contract reference."
puts
puts "  No implementation. No app migration. No new OOF codes. No compiler changes."

exit($fail.zero? ? 0 : 1)
