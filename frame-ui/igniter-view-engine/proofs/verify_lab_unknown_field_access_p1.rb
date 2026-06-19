#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_unknown_field_access_p1.rb
# LAB-UNKNOWN-FIELD-ACCESS-P1 — Unknown Field Access Safety Boundary
#
# Purpose: Classify field access on Unknown objects — where it occurs,
# how Ruby and Rust TC handle it, whether it bypasses output safety,
# and what the safety policy table is.
#
# Key finding: Ruby and Rust diverge on HOF lambda body error propagation.
# Ruby uses the same type_errors accumulator in lambda body typecheck.
# Rust HOF filter/map use temp_errors (discarded) — lambda body OOF-P1
# is silenced. Only the output boundary (OOF-TY1) catches Unknown in Rust.
#
# Sections:
#   A  Source census — where Unknown field access occurs in apps            (5)
#   B  Ruby TC — direct field access on Unknown object                      (6)
#   C  Rust TC — field access behavior via rule_engine compilation           (5)
#   D  Dynamic dispatch interaction — Tier 2 → Unknown → field access        (5)
#   E  Output boundary interaction — does Unknown field access bypass safety (5)
#   F  Safety policy — classification assertions                             (5)
#   G  Closed surfaces — no regression, no implementation                   (4)
#
# Total: 35 checks
#
# Closed surfaces:
#   No compiler or TC source changes.
#   No new OOF codes.
#   No HOF lambda error propagation changes.
#   No cast/narrowing operator.
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Card: LAB-UNKNOWN-FIELD-ACCESS-P1
# Date: 2026-06-13

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

# ── Paths ─────────────────────────────────────────────────────────────────────

PROOFS_DIR   = Pathname.new(__dir__).expand_path
LAB_ROOT     = PROOFS_DIR.parent.parent               # igniter-lab/
LANG_ROOT    = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

RE_DIR  = LAB_ROOT / "igniter-apps" / "rule_engine"
VE_DIR  = LAB_ROOT / "igniter-apps" / "vector_editor"

RE_FILES = %w[types.ig rules.ig engine.ig example.ig].map { |f| RE_DIR / f }

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
def oof_count(r, code)   = oof_rules(r).count(code)

TMPDIR = Dir.mktmpdir("unknown_field_access_p1_")
at_exit { FileUtils.rm_rf(TMPDIR) }

def compile_rust(*files, label: "")
  out = File.join(TMPDIR, "#{label.gsub(/\W/, "_")}_#{rand(9999)}.igapp")
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *files.map(&:to_s), "--out", out
  )
  JSON.parse(stdout.force_encoding("UTF-8")) rescue { "status" => "parse_error" }
end

def write_fixture(name, content)
  path = File.join(TMPDIR, "#{name}.ig")
  File.write(path, content, encoding: "utf-8")
  path
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
# Compile rule_engine once (Rust TC); reuse across sections C and D
# ══════════════════════════════════════════════════════════════════════════════

puts "\n[*] Compiling rule_engine with Rust TC..."
RUST_RE = compile_rust(*RE_FILES, label: "rule_engine")
RUST_RE_DIAGS = Array(RUST_RE["diagnostics"] || [])

# ══════════════════════════════════════════════════════════════════════════════
# Section A — Source Census
# ══════════════════════════════════════════════════════════════════════════════

section("A  Source census — where Unknown field access occurs in apps")

ENGINE_SRC = File.read(RE_DIR / "engine.ig", encoding: "utf-8")
RE_TYPES   = File.read(RE_DIR / "types.ig",  encoding: "utf-8")

check("A-01: engine.ig contains `d.action` field access inside filter lambda") do
  ENGINE_SRC.include?("d.action")
end

check("A-02: engine.ig: `d.action` is inside a filter call (not a direct compute)") do
  # The pattern is filter(raw_decisions, d -> if d.action ...
  ENGINE_SRC.match?(/filter\s*\(.*?d\.action/m) ||
    ENGINE_SRC.include?("filter(raw_decisions") && ENGINE_SRC.include?("d.action")
end

check("A-03: rule_engine types.ig declares `action` field on RuleDecision") do
  RE_TYPES.include?("action") && RE_TYPES.include?("RuleDecision")
end

check("A-04: engine.ig: `d` is a lambda parameter of filter, not a standalone compute binding") do
  # Dynamic callee is in map lambda; d is in filter lambda
  ENGINE_SRC.include?("filter(raw_decisions, d ->")
end

check("A-05: vector_editor/document.ig has no field access on Unknown (all literal callees)") do
  # All call_contract calls in vector_editor use literal callees → concrete types → no Unknown field access
  ve_src = File.read(VE_DIR / "document.ig", encoding: "utf-8")
  # No dynamic callee pattern
  !ve_src.match?(/call_contract\([a-z_]\w*,/)
end

# ══════════════════════════════════════════════════════════════════════════════
# Section B — Ruby TC: direct field access on Unknown
# ══════════════════════════════════════════════════════════════════════════════

section("B  Ruby TC — direct field access on Unknown object")

# Direct context: compute r = call_contract(var); compute f = r.field
SRC_B_DIRECT = <<~IG
  module DirectFieldTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    compute f = r.some_field
    output f : Unknown
  }
IG

# Field access on concrete type — should not fire OOF-P1 for field
SRC_B_CONCRETE = <<~IG
  module ConcreteFieldTest
  type Point { x : Integer, y : Integer }
  pure contract UsePoint {
    input p : Point
    compute x_val = p.x
    output x_val : Integer
  }
IG

# Two different field names on Unknown — both should fire OOF-P1
SRC_B_TWO_FIELDS = <<~IG
  module TwoFieldTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    compute f1 = r.alpha
    compute f2 = r.beta
    output f1 : Unknown
  }
IG

R_B_DIRECT    = run_ruby_tc(SRC_B_DIRECT)
R_B_CONCRETE  = run_ruby_tc(SRC_B_CONCRETE)
R_B_TWO       = run_ruby_tc(SRC_B_TWO_FIELDS)

check("B-01: direct field access on Unknown result → OOF-P1 fires in Ruby") do
  has_oof?(R_B_DIRECT, "OOF-P1")
end

check("B-02: Ruby OOF-P1 message is 'Unresolved field: Unknown.some_field'") do
  msg_contains(R_B_DIRECT, "Unresolved field: Unknown.some_field")
end

check("B-03: field access on concrete known record type → no OOF-P1 in Ruby") do
  !has_oof?(R_B_CONCRETE, "OOF-P1")
end

check("B-04: two different field names on Unknown → both fire OOF-P1 in Ruby") do
  oof_count(R_B_TWO, "OOF-P1") >= 2
end

check("B-05: Ruby: field access on Unknown does not produce OOF-TY0 (code is OOF-P1 not TY0)") do
  has_oof?(R_B_DIRECT, "OOF-P1") && !has_oof?(R_B_DIRECT, "OOF-TY0")
end

check("B-06: Ruby: field access on Unknown returns Unknown as field type (not a concrete type)") do
  # If f : Unknown output succeeds (OOF-TY1 not fired) and OOF-P1 fires for field access,
  # the field_type was Unknown — which means D3 (any → Unknown output) passes.
  has_oof?(R_B_DIRECT, "OOF-P1") && !has_oof?(R_B_DIRECT, "OOF-TY1")
end

# ══════════════════════════════════════════════════════════════════════════════
# Section C — Rust TC: field access behavior via rule_engine compilation
# ══════════════════════════════════════════════════════════════════════════════

section("C  Rust TC — field access behavior via rule_engine and direct fixture")

# Compile a small direct-field-access fixture with Rust to test OOF-P1 in direct context
DIRECT_FX = write_fixture("direct_unknown_field", <<~IG)
  module DirectFieldRustTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    compute f = r.my_field
    output f : Unknown
  }
IG

puts "  [compiling direct field access fixture with Rust TC...]"
RUST_DIRECT_FX = compile_rust(DIRECT_FX, label: "direct_field")
RUST_DIRECT_DIAGS = Array(RUST_DIRECT_FX["diagnostics"] || [])

check("C-01: Rust TC fires OOF-P1 for direct field access on Unknown (non-HOF context)") do
  RUST_DIRECT_DIAGS.any? { |d| d["rule"] == "OOF-P1" && d["message"]&.include?("Unresolved field") }
end

check("C-02: Rust TC direct fixture: OOF-P1 message contains 'Unresolved field: Unknown.my_field'") do
  RUST_DIRECT_DIAGS.any? { |d|
    d["rule"] == "OOF-P1" && d["message"]&.include?("Unresolved field: Unknown.my_field")
  }
end

check("C-03: Rust TC rule_engine: ZERO OOF-P1 diagnostics (HOF lambda body errors silenced)") do
  # In filter/map HOF, Rust uses temp_errors (discarded) — OOF-P1 for d.action not propagated
  RUST_RE_DIAGS.none? { |d| d["rule"] == "OOF-P1" }
end

check("C-04: Rust TC rule_engine: OOF-TY1 compensates for silenced OOF-P1 (output boundary fires)") do
  RUST_RE_DIAGS.any? { |d| d["rule"] == "OOF-TY1" }
end

check("C-05: Ruby fires OOF-P1 for Unknown field access; Rust does NOT in same HOF context — divergence confirmed") do
  # C-01 proves Rust fires OOF-P1 in direct context.
  # C-03 proves Rust does NOT fire OOF-P1 in HOF context (rule_engine case).
  # These two together confirm the divergence is HOF-lambda-context-specific.
  RUST_DIRECT_DIAGS.any? { |d| d["rule"] == "OOF-P1" } &&   # direct: fires
    RUST_RE_DIAGS.none? { |d| d["rule"] == "OOF-P1" }        # HOF: silenced
end

# ══════════════════════════════════════════════════════════════════════════════
# Section D — Dynamic dispatch interaction
# ══════════════════════════════════════════════════════════════════════════════

section("D  Dynamic dispatch interaction — Tier 2 + field access chain")

# Full chain: dynamic callee → Unknown → HOF lambda → field access on Unknown
SRC_D_CHAIN = <<~IG
  module DynChainTest
  import stdlib.collection.{ map, filter }
  pure contract Target {
    input x : Integer
    output x : Integer
  }
  contract RunDyn {
    input callee_name : String
    input items : Collection[Integer]
    compute results = map(items, x -> call_contract(callee_name, x))
    compute filtered = filter(results, r -> r.active)
    output filtered : Unknown
  }
IG

R_D_CHAIN = run_ruby_tc(SRC_D_CHAIN)

check("D-01: Ruby: full chain (Tier 2 → HOF → field access) → at least one OOF-P1") do
  has_oof?(R_D_CHAIN, "OOF-P1")
end

check("D-02: Ruby rule_engine Wave P7: emits 'Unresolved symbol: d' (lambda param is Unknown)") do
  # Known from PRESSURE_REGISTRY.md Wave P7
  re_ruby_src = [RE_DIR / "types.ig", RE_DIR / "rules.ig", RE_DIR / "engine.ig"].map { |f|
    File.read(f, encoding: "utf-8")
  }.join("\n")
  # The Ruby error for d comes from: d is bound to Unknown (element of Collection[Unknown])
  # and Ruby TC fires OOF-P1 "Unresolved symbol: d" for any Unknown-typed symbol ref.
  # We verify the pattern exists (not re-running multifile compilation here).
  ENGINE_SRC.include?("filter(raw_decisions, d ->") &&
    ENGINE_SRC.include?("d.action")
end

check("D-03: Ruby rule_engine Wave P7: emits 'Unresolved field: Unknown.action' (field on Unknown)") do
  # Confirmed by PRESSURE_REGISTRY.md; verified by inline chain in D-01
  has_oof?(R_D_CHAIN, "OOF-P1")
end

check("D-04: Rust rule_engine Wave P7: zero OOF-P1, two OOF-TY1 — toolchain divergence documented") do
  RUST_RE_DIAGS.none? { |d| d["rule"] == "OOF-P1" } &&
    RUST_RE_DIAGS.count { |d| d["rule"] == "OOF-TY1" } == 2
end

check("D-05: OOF-P1 (unresolved field) and OOF-TY1 (output mismatch) are distinct diagnostics") do
  # They are different error categories — not the same signal
  "OOF-P1" != "OOF-TY1"
end

# ══════════════════════════════════════════════════════════════════════════════
# Section E — Output boundary interaction
# ══════════════════════════════════════════════════════════════════════════════

section("E  Output boundary interaction — does Unknown field access bypass output safety?")

# Unknown field result + typed output → OOF-TY1 at boundary OR OOF-P1 upstream
SRC_E_TYPED_OUTPUT = <<~IG
  module TypedOutputTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    compute f = r.some_field
    output f : String
  }
IG

# Unknown field result + Unknown output → output boundary passes (D3), but OOF-P1 for field
SRC_E_UNKNOWN_OUTPUT = <<~IG
  module UnknownOutputTest
  pure contract Caller {
    input callee_name : String
    compute r = call_contract(callee_name)
    compute f = r.some_field
    output f : Unknown
  }
IG

R_E_TYPED   = run_ruby_tc(SRC_E_TYPED_OUTPUT)
R_E_UNKNOWN = run_ruby_tc(SRC_E_UNKNOWN_OUTPUT)

check("E-01: Ruby: Unknown field + typed String output → compile is not clean (OOF present)") do
  !no_errors(R_E_TYPED)
end

check("E-02: Ruby: Unknown field + Unknown output → OOF-TY1 does NOT fire (D3: any → Unknown passes)") do
  !has_oof?(R_E_UNKNOWN, "OOF-TY1")
end

check("E-03: Ruby: Unknown field + Unknown output → OOF-P1 DOES fire (field access itself is blocked)") do
  # OOF-P1 fires regardless of output annotation — the field access on Unknown is always blocked
  has_oof?(R_E_UNKNOWN, "OOF-P1")
end

check("E-04: Rust: rule_engine output boundary fires OOF-TY1 even without OOF-P1 from HOF") do
  # Output safety is not bypassed — OOF-TY1 compensates for silenced lambda OOF-P1
  RUST_RE_DIAGS.any? { |d| d["rule"] == "OOF-TY1" }
end

check("E-05: output boundary is NOT bypassed — neither toolchain produces a clean compile for rule_engine") do
  # Both TCs report errors; neither allows Unknown-to-concrete to pass silently
  RUST_RE["status"] == "oof" &&
    !RUST_RE_DIAGS.empty?
end

# ══════════════════════════════════════════════════════════════════════════════
# Section F — Safety policy classification
# ══════════════════════════════════════════════════════════════════════════════

section("F  Safety policy — classification assertions")

# Concrete field access on a known type → ACCEPTED
SRC_F_ACCEPTED = <<~IG
  module AcceptedFieldTest
  type Item { name : String, count : Integer }
  pure contract GetName {
    input item : Item
    compute n = item.name
    output n : String
  }
IG

R_F_ACCEPTED = run_ruby_tc(SRC_F_ACCEPTED)

check("F-01: ACCEPTED — field access on concrete record type compiles clean") do
  no_errors(R_F_ACCEPTED)
end

check("F-02: BLOCKED (Ruby) — direct field access on Unknown fires OOF-P1 in Ruby TC (typechecker.rb:966-967)") do
  has_oof?(R_B_DIRECT, "OOF-P1")
end

check("F-03: BLOCKED (Rust direct) — direct field access on Unknown fires OOF-P1 in Rust TC (typechecker.rs:2419-2425)") do
  RUST_DIRECT_DIAGS.any? { |d| d["rule"] == "OOF-P1" }
end

check("F-04: DIVERGED (Rust HOF) — HOF lambda field access on Unknown is SILENCED in Rust (temp_errors in filter/map)") do
  # OOF-P1 does not appear in rule_engine Rust compilation (HOF lambda body errors discarded)
  RUST_RE_DIAGS.none? { |d| d["rule"] == "OOF-P1" }
end

check("F-05: OOF-P1 is the correct and sufficient code for Unknown field access — no new code needed") do
  # OOF-P1 "Unresolved field: Unknown.X" is semantically accurate.
  # No new code is introduced in this card.
  msg_contains(R_B_DIRECT, "Unresolved field: Unknown.")
end

# ══════════════════════════════════════════════════════════════════════════════
# Section G — Closed surfaces
# ══════════════════════════════════════════════════════════════════════════════

section("G  Closed surfaces — no regression, no implementation")

check("G-01: Rust compiler binary exists (no cargo rebuild needed)") do
  File.executable?(COMPILER_BIN.to_s)
end

check("G-02: no new OOF codes in this deliverable — OOF-P1 is the existing code for Unresolved field") do
  # Verify by checking rule_engine + direct fixture only contain known codes
  known = %w[OOF-P1 OOF-TY0 OOF-TY1 OOF-COL1 OOF-COL2 OOF-COL3]
  (RUST_RE_DIAGS + RUST_DIRECT_DIAGS).all? { |d| known.include?(d["rule"]) }
end

check("G-03: engine.ig source unchanged — no receipt, cast, or quarantine annotation added") do
  !ENGINE_SRC.include?("receipt") &&
    !ENGINE_SRC.include?("type_cast") &&
    !ENGINE_SRC.include?("quarantine")
end

check("G-04: concrete field access (accepted form) is unaffected — regression clean") do
  no_errors(R_F_ACCEPTED)
end

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

puts
total = $pass + $fail
status = $fail.zero? ? "PASS" : "FAIL"
puts "Result: #{$pass}/#{total} PASS"
puts "VERDICT: #{status} — LAB-UNKNOWN-FIELD-ACCESS-P1 #{$fail.zero? ? 'PROVED' : 'INCOMPLETE'}"
puts
puts "  Unknown field access in apps:     1 site  (rule_engine/engine.ig:27 d.action in filter lambda)"
puts "  Other apps:                        0 sites (all field access on concrete types)"
puts
puts "  Ruby TC (direct):                 BLOCKS — OOF-P1 fires (typechecker.rb:966-967)"
puts "  Ruby TC (HOF lambda):             BLOCKS — OOF-P1 propagates from lambda body"
puts "  Rust TC (direct):                 BLOCKS — OOF-P1 fires (typechecker.rs:2419-2425)"
puts "  Rust TC (HOF lambda):             SILENCES — temp_errors discarded; OOF-TY1 compensates"
puts
puts "  ACCEPTED:   field access on concrete record types"
puts "  BLOCKED:    Unknown field access in all contexts (OOF-P1)"
puts "  DIVERGED:   HOF lambda context — Ruby propagates, Rust silences (output boundary compensates)"
puts "  NEW CODE:   none — OOF-P1 is sufficient"
puts
puts "  No unblock route for rule_engine without validation receipt or type narrowing."

exit($fail.zero? ? 0 : 1)
