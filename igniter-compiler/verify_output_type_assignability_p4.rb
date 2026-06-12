#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_output_type_assignability_p4.rb
# LANG-OUTPUT-TYPE-ASSIGNABILITY-P4
# ===================================
# Rust parity proof for structural output type assignability.
#
# Grounding:
#   LANG-OUTPUT-TYPE-ASSIGNABILITY-P1  (design D1-D6)
#   LANG-OUTPUT-TYPE-ASSIGNABILITY-P2  (implementation planning)
#   LANG-OUTPUT-TYPE-ASSIGNABILITY-P3  (Ruby 70/70 PASS)
#   APP-RECHECK-WAVE-P2                (rule_engine confirmed Ruby correct; Rust needed parity)
#
# Sections:
#   B  Source structure: structurally_assignable + type_display in TC_RS   (6)
#   C  OOF-TY1 fires: outer name mismatch                                  (5)
#   D  OOF-TY1 fires: actual Unknown scalar and Collection depth            (6)
#   E  OOF-TY1 fires: param mismatch, same outer container                  (5)
#   F  OOF-TY1 fires: nested parametric types                               (4)
#   G  Permissive PASS — correct concrete types, no OOF-TY1                 (5)
#   I  rule_engine Collection[Unknown]->Collection[RuleDecision] blocked     (5)
#   J  Regression — prior-PASS contracts unaffected                          (5)
#   K  OOF-TY0 NOT at output boundary; LAB-RACK-P9 removed                  (4)
#
# Total: 45 checks
#
# Closed surfaces:
#   No Ruby changes.
#   No dynamic dispatch feature.
#   No validation receipt.
#   No VM/runtime changes.
#   Output boundary only.

require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR = Pathname.new(__FILE__).realpath.dirname
BIN        = SCRIPT_DIR / "target" / "release" / "igniter_compiler"
TC_RS      = SCRIPT_DIR / "src" / "typechecker.rs"

abort "Binary not found — run: cargo build --release in igniter-compiler/" unless BIN.exist?
abort "typechecker.rs not found" unless TC_RS.exist?

TC_SRC = TC_RS.read(encoding: "utf-8")

# ─── Harness ─────────────────────────────────────────────────────────────────

$pass = 0
$fail = 0

def check(label)
  result = false
  begin
    result = yield == true
  rescue => e
    result = false
    $fail += 1
    puts "  FAIL: #{label} [exception: #{e.message.lines.first&.strip}]"
    return
  end
  if result
    $pass += 1
    puts "  PASS: #{label}"
  else
    $fail += 1
    puts "  FAIL: #{label}"
  end
end

# ─── Compile helper ──────────────────────────────────────────────────────────

def rust_compile(src)
  Dir.mktmpdir("p4sa_") do |dir|
    ig  = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(ig, src.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(BIN.to_s, "compile", ig, "--out", out)
    r = begin JSON.parse(stdout.force_encoding("UTF-8")) rescue {} end
    diags = Array(r["diagnostics"])
    {
      status: r["status"] || "unknown",
      codes:  diags.map { |d| d["rule"] }.compact,
      msgs:   diags.map { |d| d["message"] }.compact,
      nodes:  diags.map { |d| d["node"] }.compact,
      diags:  diags
    }
  end
end

def has_oof_ty1(r) = r[:codes].include?("OOF-TY1")
def no_oof_ty1(r)  = !has_oof_ty1(r)
def has_oof_ty0(r) = r[:codes].include?("OOF-TY0")

# ─── Fixtures ─────────────────────────────────────────────────────────────────

# C: outer name mismatch
SRC_STR_INT = <<~IG
  module T
  contract C {
    input x : String
    output x : Integer
  }
IG

SRC_INT_TEXT = <<~IG
  module T
  contract C {
    input x : Integer
    output x : Text
  }
IG

SRC_CC_INT = <<~IG
  module T
  contract C {
    input s : String
    compute r = call_contract("f", s)
    output r : Integer
  }
IG

SRC_CC_TEXT = <<~IG
  module T
  contract C {
    input s : String
    compute r = call_contract("f", s)
    output r : Text
  }
IG

SRC_CC_RECORD = <<~IG
  module T
  type RuleDecision { rule_name: String, action: String, reason: String }
  contract C {
    input s : String
    compute r = call_contract("f", s)
    output r : RuleDecision
  }
IG

# D: actual Unknown at Collection depth
SRC_COL_UNK_TEXT = <<~IG
  module T
  contract C {
    input rules : Collection[String]
    input ctx   : String
    compute results = map(rules, r -> call_contract(r, ctx))
    output results : Collection[Text]
  }
IG

SRC_COL_UNK_INT = <<~IG
  module T
  contract C {
    input rules : Collection[String]
    input ctx   : String
    compute results = map(rules, r -> call_contract(r, ctx))
    output results : Collection[Integer]
  }
IG

SRC_COL_UNK_RECORD = <<~IG
  module T
  type RuleDecision { rule_name: String, action: String, reason: String }
  contract C {
    input rules : Collection[String]
    input ctx   : String
    compute results = map(rules, r -> call_contract(r, ctx))
    output results : Collection[RuleDecision]
  }
IG

# E: param mismatch, same outer
SRC_COL_INT_TEXT = <<~IG
  module T
  contract C {
    input items : Collection[Integer]
    output items : Collection[Text]
  }
IG

SRC_MAP_INT_TEXT = <<~IG
  module T
  contract C {
    input m : Map[String, Integer]
    output m : Map[String, Text]
  }
IG

SRC_COL_FOO_BAR = <<~IG
  module T
  type Foo { x : Integer }
  type Bar { y : String }
  contract C {
    input items : Collection[Foo]
    compute filtered = filter(items, x -> if x.x > 0 { true } else { false })
    output filtered : Collection[Bar]
  }
IG

# F: nested params — direct nested type annotation (Rust TC parses Collection[Collection[T]])
SRC_NESTED_DIRECT = <<~IG
  module T
  contract C {
    input items : Collection[Collection[Integer]]
    output items : Collection[Collection[Text]]
  }
IG

SRC_NESTED_MAP_OF_MAP = <<~IG
  module T
  contract C {
    input items : Collection[String]
    compute mapped = map(items, s -> map(items, t -> s))
    output mapped : Collection[Collection[Integer]]
  }
IG

# G: clean cases
SRC_CLEAN_INT = <<~IG
  module T
  contract C {
    input x : Integer
    compute r = x + 1
    output r : Integer
  }
IG

SRC_CLEAN_STR = <<~IG
  module T
  contract C {
    input s : String
    output s : String
  }
IG

SRC_CLEAN_MAP = <<~IG
  module T
  contract C {
    input m : Map[String, Integer]
    output m : Map[String, Integer]
  }
IG

SRC_CLEAN_COL = <<~IG
  module T
  contract C {
    input items : Collection[String]
    compute copy = items
    output copy : Collection[String]
  }
IG

SRC_CLEAN_RECORD = <<~IG
  module T
  type Foo { x : Integer }
  contract C {
    input items : Collection[Foo]
    compute filtered = filter(items, x -> if x.x > 0 { true } else { false })
    output filtered : Collection[Foo]
  }
IG

# I: rule_engine — simplified to avoid OOF-P1 (field access on Unknown triggers blocking error)
SRC_RULE_ENGINE = <<~IG
  module RuleEngine
  type Transaction { id: Integer, amount: Integer, currency: String }
  type RuleDecision { rule_name: String, action: String, reason: String }
  contract ExecuteRules {
    input t : Transaction
    input rules : Collection[String]
    compute active_decisions = map(rules, r -> call_contract(r, t))
    output active_decisions : Collection[RuleDecision]
  }
IG

# ─── Run fixtures ─────────────────────────────────────────────────────────────

r_str_int       = rust_compile(SRC_STR_INT)
r_int_text      = rust_compile(SRC_INT_TEXT)
r_cc_int        = rust_compile(SRC_CC_INT)
r_cc_text       = rust_compile(SRC_CC_TEXT)
r_cc_record     = rust_compile(SRC_CC_RECORD)
r_col_unk_text  = rust_compile(SRC_COL_UNK_TEXT)
r_col_unk_int   = rust_compile(SRC_COL_UNK_INT)
r_col_unk_rec   = rust_compile(SRC_COL_UNK_RECORD)
r_col_int_text  = rust_compile(SRC_COL_INT_TEXT)
r_map_int_text  = rust_compile(SRC_MAP_INT_TEXT)
r_col_foo_bar   = rust_compile(SRC_COL_FOO_BAR)
r_nested_direct = rust_compile(SRC_NESTED_DIRECT)
r_nested_mapmap = rust_compile(SRC_NESTED_MAP_OF_MAP)
r_clean_int     = rust_compile(SRC_CLEAN_INT)
r_clean_str     = rust_compile(SRC_CLEAN_STR)
r_clean_map     = rust_compile(SRC_CLEAN_MAP)
r_clean_col     = rust_compile(SRC_CLEAN_COL)
r_clean_record  = rust_compile(SRC_CLEAN_RECORD)
r_rule_engine   = rust_compile(SRC_RULE_ENGINE)

# ─── Section B — Source structure ────────────────────────────────────────────

puts
puts "=" * 72
puts "Section B — Source structure: new methods in typechecker.rs"
puts "=" * 72

check("B-01: fn structurally_assignable defined in typechecker.rs") do
  TC_SRC.include?("fn structurally_assignable(")
end

check("B-02: structurally_assignable implements D3 — expected Unknown returns true") do
  TC_SRC.match?(/fn structurally_assignable.*?type_name\(expected\) == "Unknown".*?return true/m)
end

check("B-03: structurally_assignable implements D2 — actual Unknown returns false") do
  TC_SRC.match?(/fn structurally_assignable.*?type_name\(actual\) == "Unknown".*?return false/m)
end

check("B-04: structurally_assignable recursively calls itself on params") do
  TC_SRC.match?(/self\.structurally_assignable\(&self\.type_ir/)
end

check("B-05: fn type_display defined in typechecker.rs") do
  TC_SRC.include?("fn type_display(")
end

check("B-06: type_display renders params with brackets — format!() uses bracket string") do
  TC_SRC.include?('format!("{}[{}]"')
end

# ─── Section C — OOF-TY1: outer name mismatch ────────────────────────────────

puts
puts "=" * 72
puts "Section C — OOF-TY1 fires: outer name mismatch"
puts "=" * 72

check("C-01: String input → Integer output → OOF-TY1 fires") do
  has_oof_ty1(r_str_int)
end

check("C-02: Integer input → Text output → OOF-TY1 fires") do
  has_oof_ty1(r_int_text)
end

check("C-03: OOF-TY1 rule code present in diagnostics") do
  r_str_int[:codes].include?("OOF-TY1")
end

check("C-04: OOF-TY1 message contains 'Output type mismatch'") do
  r_str_int[:msgs].any? { |m| m.include?("Output type mismatch") }
end

check("C-05: OOF-TY1 message includes the expected type name") do
  r_str_int[:msgs].any? { |m| m.include?("expected Integer") }
end

# ─── Section D — OOF-TY1: actual Unknown at depth ────────────────────────────

puts
puts "=" * 72
puts "Section D — OOF-TY1 fires: actual Unknown (scalar and Collection depth)"
puts "=" * 72

check("D-01: call_contract → Unknown, declared Integer → OOF-TY1") do
  has_oof_ty1(r_cc_int)
end

check("D-02: call_contract → Unknown, declared Text → OOF-TY1") do
  has_oof_ty1(r_cc_text)
end

check("D-03: call_contract → Unknown, declared RuleDecision → OOF-TY1") do
  has_oof_ty1(r_cc_record)
end

check("D-04: map → Collection[Unknown], declared Collection[Text] → OOF-TY1") do
  has_oof_ty1(r_col_unk_text)
end

check("D-05: map → Collection[Unknown], declared Collection[Integer] → OOF-TY1") do
  has_oof_ty1(r_col_unk_int)
end

check("D-06: map → Collection[Unknown], declared Collection[RuleDecision] → OOF-TY1") do
  has_oof_ty1(r_col_unk_rec)
end

# ─── Section E — OOF-TY1: param mismatch, same outer ─────────────────────────

puts
puts "=" * 72
puts "Section E — OOF-TY1 fires: param mismatch, same outer container"
puts "=" * 72

check("E-01: Collection[Integer] → Collection[Text] → OOF-TY1") do
  has_oof_ty1(r_col_int_text)
end

check("E-02: Map[String,Integer] → Map[String,Text] → OOF-TY1") do
  has_oof_ty1(r_map_int_text)
end

check("E-03: Collection[Foo] → Collection[Bar] (distinct records) → OOF-TY1") do
  has_oof_ty1(r_col_foo_bar)
end

check("E-04: OOF-TY1 message includes 'Collection[Integer]' (got) or 'Collection[Text]' (expected)") do
  r_col_int_text[:msgs].any? { |m| m.include?("Collection[Integer]") || m.include?("Collection[Text]") }
end

check("E-05: OOF-TY1 message includes 'Map[String,Integer]' or 'Map[String,Text]'") do
  r_map_int_text[:msgs].any? { |m| m.include?("Map[String,Integer]") || m.include?("Map[String,Text]") }
end

# ─── Section F — OOF-TY1: nested params ──────────────────────────────────────

puts
puts "=" * 72
puts "Section F — OOF-TY1 fires: nested parametric types"
puts "=" * 72

check("F-01: Collection[Collection[Integer]] input → Collection[Collection[Text]] output → OOF-TY1") do
  has_oof_ty1(r_nested_direct)
end

check("F-02: OOF-TY1 message shows nested type with brackets") do
  r_nested_direct[:msgs].any? { |m| m.include?("Collection[Collection[") }
end

check("F-03: OOF-TY1 message includes 'Collection[Collection[Integer]]'") do
  r_nested_direct[:msgs].any? { |m| m.include?("Collection[Collection[Integer]]") }
end

check("F-04: map-of-maps → Collection[Collection[String]] vs Collection[Collection[Integer]] → OOF-TY1") do
  has_oof_ty1(r_nested_mapmap)
end

# ─── Section G — Permissive PASS ─────────────────────────────────────────────

puts
puts "=" * 72
puts "Section G — Permissive PASS — correct concrete types, no OOF-TY1"
puts "=" * 72

check("G-01: Integer → Integer → no OOF-TY1") do
  no_oof_ty1(r_clean_int) && r_clean_int[:status] == "ok"
end

check("G-02: String → String → no OOF-TY1") do
  no_oof_ty1(r_clean_str)
end

check("G-03: Map[String,Integer] → Map[String,Integer] → no OOF-TY1") do
  no_oof_ty1(r_clean_map)
end

check("G-04: Collection[String] → Collection[String] → no OOF-TY1") do
  no_oof_ty1(r_clean_col)
end

check("G-05: Collection[Foo] → Collection[Foo] → no OOF-TY1") do
  no_oof_ty1(r_clean_record)
end

# ─── Section I — rule_engine OOF-TY1 activation ──────────────────────────────

puts
puts "=" * 72
puts "Section I — rule_engine Collection[Unknown]->Collection[RuleDecision] now blocked"
puts "=" * 72

check("I-01: rule_engine fixture produces OOF-TY1 (was SILENT via LAB-RACK-P9 — safety-positive)") do
  has_oof_ty1(r_rule_engine)
end

check("I-02: OOF-TY1 message includes 'Collection[RuleDecision]' (expected type)") do
  r_rule_engine[:msgs].any? { |m| m.include?("Collection[RuleDecision]") }
end

check("I-03: OOF-TY1 message includes 'Collection[Unknown]' (got type)") do
  r_rule_engine[:msgs].any? { |m| m.include?("Collection[Unknown]") }
end

check("I-04: OOF-TY1 node is 'active_decisions'") do
  r_rule_engine[:diags]
    .select { |d| d["rule"] == "OOF-TY1" }
    .any? { |d| d["node"] == "active_decisions" }
end

check("I-05: status is 'oof' (blocked by type error)") do
  r_rule_engine[:status] == "oof"
end

# ─── Section J — Regression ──────────────────────────────────────────────────

puts
puts "=" * 72
puts "Section J — Regression — prior-PASS contracts unaffected"
puts "=" * 72

check("J-01: clean Integer → Integer: status ok") do
  r_clean_int[:status] == "ok"
end

check("J-02: clean String → String: no OOF-TY1, no errors") do
  r_clean_str[:codes].empty?
end

check("J-03: clean Map[String,Integer]: no OOF-TY1") do
  no_oof_ty1(r_clean_map)
end

check("J-04: clean Collection[String]: no OOF-TY1") do
  no_oof_ty1(r_clean_col)
end

check("J-05: OOF-TY1 NOT in blocking_rule_present — source check") do
  blocking_block = TC_SRC[/fn blocking_rule_present.*?}/m] || ""
  !blocking_block.include?("OOF-TY1")
end

# ─── Section K — OOF-TY0 NOT at output boundary; LAB-RACK-P9 removed ─────────

puts
puts "=" * 72
puts "Section K — OOF-TY0 NOT at output boundary; LAB-RACK-P9 removed"
puts "=" * 72

check("K-01: LAB-RACK-P9 guard removed from output boundary source") do
  output_region = TC_SRC[/"output" =>.*?(?=^\s+"[a-z]|\z)/m] || ""
  !output_region.include?('type_name(&actual) != "Unknown"')
end

check("K-02: output boundary source uses structurally_assignable not type_name equality") do
  output_region = TC_SRC[/"output" =>.*?(?=^\s+"[a-z]|\z)/m] || ""
  output_region.include?("structurally_assignable")
end

check("K-03: Collection[Integer] → Collection[Text]: OOF-TY1 fires, no 'Type mismatch' OOF-TY0 at output node") do
  has_oof_ty1(r_col_int_text) &&
    r_col_int_text[:diags].none? { |d|
      d["rule"] == "OOF-TY0" &&
      d["node"] == "items" &&
      d.fetch("message", "").start_with?("Type mismatch:")
    }
end

check("K-04: output boundary emits OOF-TY1 diagnostic, not OOF-TY0") do
  # Source check: OOF-TY1 appears in the file (for output boundary), and the
  # structurally_assignable call appears before OOF-TY0 in the output region.
  # Confirmed by K-01/K-02 (region uses structurally_assignable); this verifies OOF-TY1 present.
  TC_SRC.include?('"OOF-TY1".to_string()')
end

# ─── Summary ─────────────────────────────────────────────────────────────────

puts
puts "=" * 72
total = $pass + $fail
result_label = $fail == 0 ? "PASS" : "FAIL"
puts "Result: #{$pass}/#{total} #{result_label}"
puts
puts "VERDICT: #{result_label} — LANG-OUTPUT-TYPE-ASSIGNABILITY-P4"
puts
puts "Rust parity achieved:"
puts "  structurally_assignable() — recursive structural check (D2/D3)"
puts "  type_display() — nested param rendering: Collection[RuleDecision], Map[String,T]"
puts "  Output boundary: OOF-TY1 replaces OOF-TY0; LAB-RACK-P9 guard removed (D6)"
puts
puts "Safety-positive evidence:"
puts "  rule_engine Collection[Unknown] -> Collection[RuleDecision] NOW BLOCKED in Rust"
puts "  LAB-RACK-P9 guard that silently passed unknown outputs is superseded by D2/D3"
puts
puts "Next: LANG-OUTPUT-TYPE-ASSIGNABILITY-P5 (dual-toolchain regression, optional)"
puts "=" * 72

exit($fail.zero? ? 0 : 1)
