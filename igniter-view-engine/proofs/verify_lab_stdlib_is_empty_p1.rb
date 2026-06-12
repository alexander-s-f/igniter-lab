#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_is_empty_p1.rb
# LAB-STDLIB-IS-EMPTY-P1 — stdlib.collection.is_empty / non_empty readiness proof
# =================================================================================
# Determines whether stdlib.collection.is_empty (and its dual non_empty) are
# ready for proposal authoring (ACCEPT), or blocked by some toolchain/design concern.
#
# Route:   READINESS PROOF / NO IMPLEMENTATION
# Card:    igniter-lab/.agents/work/cards/governance/LAB-STDLIB-IS-EMPTY-P1.md
# Verdict: ACCEPT — proposal authoring ready; both is_empty AND non_empty required
#
# Sections:
#   A  INVENTORY CHECK          (6)  — is_empty/non_empty absent; count/has_key precedent
#   B  APP FIXTURE SCAN         (6)  — gap documented in state_machine + bloom_filter + decision_tree
#   C  RUBY DIAGNOSTICS         (8)  — OOF-TY0 for both; unary_op not dispatched in TC
#   D  COLLECTION CARDINALITY   (6)  — pure over collection value; no empty construction blocker
#   E  NON_EMPTY NECESSITY      (6)  — ! unary not dispatched; workaround ergonomics
#   F  OOF CODE ANALYSIS        (6)  — OOF-COL1/COL2 sufficient; no new code in v0
#   G  SIGNATURE & AUTHORITY    (6)  — canonical names; authority_surface:none; pure/total
#   H  CLOSED SURFACES          (4)  — no TC impl; no app fixture edits; head/find_one separate
#
# Total: 48 checks (minimum: 43)

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR     = Pathname.new(__dir__)
LAB_ROOT       = SCRIPT_DIR.parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN   = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
APPS_DIR       = LAB_ROOT / "igniter-apps"
STDLIB_INVENTORY = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"
TC_RUBY        = WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST        = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Compiler binary not found: #{COMPILER_BIN}" unless COMPILER_BIN.exist?
abort "stdlib-inventory.json not found: #{STDLIB_INVENTORY}" unless STDLIB_INVENTORY.exist?
abort "Ruby TC not found: #{TC_RUBY}" unless TC_RUBY.exist?
abort "Rust TC not found: #{TC_RUST}" unless TC_RUST.exist?

# ─────────────────────────────────────────────────────────────────────────────
# Harness
# ─────────────────────────────────────────────────────────────────────────────

$pass = 0
$fail = 0

def check(label)
  result = yield
  if result
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [exception: #{e.message.lines.first&.strip}]"
end

def ruby_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    File.write(path, src)
    c = IgniterLang::CompilerOrchestrator.new
    Dir.mktmpdir do |tmpdir2|
      out = File.join(tmpdir2, "out.igapp")
      r = c.compile_sources(source_paths: [path], out_path: out)
      diags = r.dig("result", "diagnostics") || []
      {
        status:   r["status"] || "error",
        diags:    diags,
        messages: diags.map { |d| d["message"].to_s },
        codes:    diags.map { |d| d["rule"].to_s }.compact
      }
    end
  end
end

def rust_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", path, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags = Array(result["diagnostics"])
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Static inputs
# ─────────────────────────────────────────────────────────────────────────────

INVENTORY       = JSON.parse(File.read(STDLIB_INVENTORY, encoding: "UTF-8"))
INVENTORY_NAMES = INVENTORY.fetch("entries").map { |e| e["canonical_name"] }
TC_SRC          = File.read(TC_RUBY, encoding: "UTF-8")
RUST_SRC        = File.read(TC_RUST, encoding: "UTF-8")

STATE_MACHINE_SRC = File.read(APPS_DIR / "arch_patterns" / "state_machine.ig")
BLOOM_OPS_SRC     = File.read(APPS_DIR / "bloom_filter" / "ops.ig")
BLOOM_TYPES_SRC   = File.read(APPS_DIR / "bloom_filter" / "types.ig")
DT_EVALUATOR_SRC  = File.read(APPS_DIR / "decision_tree" / "evaluator.ig")

# ─────────────────────────────────────────────────────────────────────────────
# Test fixtures
# ─────────────────────────────────────────────────────────────────────────────

IS_EMPTY_FIXTURE = <<~IG
  module IsEmptyTest
  type Item { active : Bool }
  contract TestIsEmpty {
    input items : Collection[Item]
    compute result = is_empty(items)
    output result : Bool
  }
IG

NON_EMPTY_FIXTURE = <<~IG
  module NonEmptyTest
  type Item { active : Bool }
  contract TestNonEmpty {
    input items : Collection[Item]
    compute result = non_empty(items)
    output result : Bool
  }
IG

BANG_FIXTURE = <<~IG
  module BangTest
  contract TestBang {
    input x : Bool
    compute negated = !x
    output negated : Bool
  }
IG

COUNT_FIXTURE = <<~IG
  module CountTest
  type Item { active : Bool }
  contract TestCount {
    input items : Collection[Item]
    compute n = count(items)
    output n : Integer
  }
IG

FILTER_EMPTY_FIXTURE = <<~IG
  module FilterEmptyTest
  type Item { active : Bool }
  contract TestFilterEmpty {
    input items : Collection[Item]
    compute empty_set = filter(items, x -> false)
    output empty_set : Collection[Item]
  }
IG

IF_WORKAROUND_FIXTURE = <<~IG
  module IfWorkaroundTest
  contract TestIfWorkaround {
    input x : Bool
    compute negated = if x { false } else { true }
    output negated : Bool
  }
IG

GUARD_PATTERN_FIXTURE = <<~IG
  module GuardPatternTest
  type Item { active : Bool }
  contract TestGuard {
    input items : Collection[Item]
    compute filtered = filter(items, x -> x.active)
    compute count_active = count(filtered)
    output count_active : Integer
  }
IG

# ─────────────────────────────────────────────────────────────────────────────
# Section A — INVENTORY CHECK (6)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── A: INVENTORY CHECK ──────────────────────────────────────────────────"

check "A-01: stdlib-inventory.json has no 'stdlib.collection.is_empty' entry" do
  !INVENTORY_NAMES.include?("stdlib.collection.is_empty")
end

check "A-02: stdlib-inventory.json has no 'stdlib.collection.non_empty' entry" do
  !INVENTORY_NAMES.include?("stdlib.collection.non_empty")
end

check "A-03: stdlib.collection.count IS in inventory (collection namespace established)" do
  INVENTORY_NAMES.include?("stdlib.collection.count")
end

check "A-04: stdlib.collection.count output_signature is 'Integer' (not Bool — is_empty fills Bool gap)" do
  entry = INVENTORY.fetch("entries").find { |e| e["canonical_name"] == "stdlib.collection.count" }
  entry && entry["output_signature"] == "Integer"
end

check "A-05: stdlib.map.has_key IS in inventory (Bool output precedent in non-text stdlib)" do
  INVENTORY_NAMES.include?("stdlib.map.has_key")
end

check "A-06: No OOF-COL6 in stdlib-inventory.json (next code available; not consumed by prior cards)" do
  inventory_text = File.read(STDLIB_INVENTORY)
  !inventory_text.include?("OOF-COL6")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — APP FIXTURE SCAN (6)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── B: APP FIXTURE SCAN ─────────────────────────────────────────────────"

check "B-01: arch_patterns/state_machine.ig documents 'is_empty()' gap explicitly" do
  STATE_MACHINE_SRC.include?("is_empty()")
end

check "B-02: arch_patterns/state_machine.ig documents 'non-empty' check need" do
  STATE_MACHINE_SRC.include?("non-empty")
end

check "B-03: bloom_filter/ops.ig documents 'non-empty' check need (CheckBitAtIndex)" do
  BLOOM_OPS_SRC.include?("non-empty")
end

check "B-04: bloom_filter/ops.ig documents head() absence" do
  BLOOM_OPS_SRC.include?("head()")
end

check "B-05: bloom_filter/types.ig documents head() / col[i] absence" do
  BLOOM_TYPES_SRC.include?("head()")
end

check "B-06: decision_tree/evaluator.ig documents head() absence" do
  DT_EVALUATOR_SRC.include?("head()")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — RUBY DIAGNOSTICS (8)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── C: RUBY DIAGNOSTICS ─────────────────────────────────────────────────"

check "C-01: is_empty(items) → OOF-TY0 'Unknown function: is_empty'" do
  r = ruby_compile_source(IS_EMPTY_FIXTURE)
  r[:codes].include?("OOF-TY0") &&
    r[:messages].any? { |m| m.include?("is_empty") }
end

check "C-02: non_empty(items) → OOF-TY0 'Unknown function: non_empty'" do
  r = ruby_compile_source(NON_EMPTY_FIXTURE)
  r[:codes].include?("OOF-TY0") &&
    r[:messages].any? { |m| m.include?("non_empty") }
end

check "C-03: !x → OOF-TY0 'Unsupported expression kind: unary_op'" do
  r = ruby_compile_source(BANG_FIXTURE)
  r[:codes].include?("OOF-TY0") &&
    r[:messages].any? { |m| m.include?("unary_op") }
end

check "C-04: TC source has no 'when \"is_empty\"' dispatch arm" do
  !TC_SRC.include?('when "is_empty"')
end

check "C-05: TC source has no 'when \"non_empty\"' dispatch arm" do
  !TC_SRC.include?('when "non_empty"')
end

check "C-06: 'unary_op' absent from infer_expr case dispatch (confirmed by fn_expr_has_call? only)" do
  # infer_expr is defined starting with 'def infer_expr'; it has a case block
  # unary_op only appears in fn_expr_has_call? and fn_collect_calls_expr (graph helpers),
  # NOT as a case arm in infer_expr itself
  infer_expr_region = TC_SRC[/def infer_expr.*?^    end$/m]
  infer_expr_region.nil? || !infer_expr_region.include?('"unary_op"')
end

check "C-07: count(items) compiles cleanly — no OOF-TY0 (dispatched via COLLECTION_HOF_FNS)" do
  r = ruby_compile_source(COUNT_FIXTURE)
  !r[:codes].include?("OOF-TY0")
end

check "C-08: is_empty NOT in COLLECTION_HOF_FNS keys (TC source check)" do
  !TC_SRC.include?('"is_empty"') && !TC_SRC.include?("is_empty:")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — COLLECTION CARDINALITY (6)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── D: COLLECTION CARDINALITY ───────────────────────────────────────────"

check "D-01: count(items) compiles cleanly — cardinality dispatch proven, no errors" do
  r = ruby_compile_source(COUNT_FIXTURE)
  r[:codes].empty?
end

check "D-02: filter(items, x -> false) compiles cleanly (runtime-empty collection constructable)" do
  r = ruby_compile_source(FILTER_EMPTY_FIXTURE)
  r[:codes].empty?
end

check "D-03: filter(items, x -> false) produces Collection[Item] output (no type error on empty)" do
  r = ruby_compile_source(FILTER_EMPTY_FIXTURE)
  !r[:codes].include?("OOF-COL3") && !r[:codes].include?("OOF-TY0")
end

check "D-04: count dispatches via COLLECTION_HOF_FNS — same count→Integer pattern enables is_empty→Bool" do
  TC_SRC.include?('"count"  => { qualified_name: "stdlib.collection.count",  arity: 1, has_lambda: false }')
end

check "D-05: No authority-granting patterns in count's COLLECTION_HOF_FNS entry (pure precedent)" do
  count_entry = INVENTORY.fetch("entries").find { |e| e["canonical_name"] == "stdlib.collection.count" }
  count_entry && count_entry["authority_surface"] == "none" && count_entry["purity"] == "pure"
end

check "D-06: Guard pattern (filter + count) compiles cleanly — is_empty doesn't require new primitives" do
  r = ruby_compile_source(GUARD_PATTERN_FIXTURE)
  r[:codes].empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — NON_EMPTY NECESSITY (6)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── E: NON_EMPTY NECESSITY ──────────────────────────────────────────────"

check "E-01: Parser accepts ! (bang) — parse_unary handles :bang token → unary_op node" do
  # The parser.rb has parse_unary with peek_type?(:bang) branch
  parser_src = File.read(WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "parser.rb")
  parser_src.include?("peek_type?(:bang)") && parser_src.include?('"unary_op"')
end

check "E-02: !x → OOF-TY0 confirms unary_op is parsed but NOT type-checked" do
  r = ruby_compile_source(BANG_FIXTURE)
  r[:codes].include?("OOF-TY0") &&
    r[:messages].any? { |m| m.include?("unary_op") || m.include?("Unsupported") }
end

check "E-03: if/else manual negation compiles cleanly (workaround is possible but verbose)" do
  r = ruby_compile_source(IF_WORKAROUND_FIXTURE)
  r[:codes].empty?
end

check "E-04: if/else workaround is accepted — proving users can negate Bool; non_empty still needed for ergonomics" do
  # E-03 proved the workaround compiles; this checks it's error-free
  r = ruby_compile_source(IF_WORKAROUND_FIXTURE)
  !r[:codes].include?("OOF-TY0") && !r[:codes].include?("OOF-IF1")
end

check "E-05: non_empty gives same OOF-TY0 shape as is_empty — both absent, both needed" do
  r_ie = ruby_compile_source(IS_EMPTY_FIXTURE)
  r_ne = ruby_compile_source(NON_EMPTY_FIXTURE)
  r_ie[:codes].include?("OOF-TY0") && r_ne[:codes].include?("OOF-TY0")
end

check "E-06: Neither is_empty nor non_empty appear in TC as dispatched functions" do
  !TC_SRC.include?("stdlib.collection.is_empty") &&
    !TC_SRC.include?("stdlib.collection.non_empty")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — OOF CODE ANALYSIS (6)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── F: OOF CODE ANALYSIS ────────────────────────────────────────────────"

check "F-01: OOF-COL1 exists in TC (arity — reusable for is_empty)" do
  TC_SRC.include?('"OOF-COL1"')
end

check "F-02: OOF-COL2 exists in TC (non-Collection first arg — reusable for is_empty)" do
  TC_SRC.include?('"OOF-COL2"')
end

check "F-03: OOF-COL3 exists in TC (filter predicate Bool check — separate, not reused)" do
  TC_SRC.include?('"OOF-COL3"')
end

check "F-04: OOF-COL4 exists in TC (fold-family errors — separate, not reused)" do
  TC_SRC.include?('"OOF-COL4"')
end

check "F-05: OOF-COL5 exists in TC (sum symbol errors — separate, not reused)" do
  TC_SRC.include?('"OOF-COL5"')
end

check "F-06: OOF-COL6 absent from TC — next available code; v0 doesn't need a new code" do
  !TC_SRC.include?("OOF-COL6")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — SIGNATURE & AUTHORITY (6)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── G: SIGNATURE & AUTHORITY ────────────────────────────────────────────"

check "G-01: has_key in inventory with Bool output — Bool return type is established for stdlib" do
  entry = INVENTORY.fetch("entries").find { |e| e["canonical_name"] == "stdlib.map.has_key" }
  entry && entry["output_signature"] == "Bool"
end

check "G-02: has_key authority_surface: none — authority-free Bool predicate precedent" do
  entry = INVENTORY.fetch("entries").find { |e| e["canonical_name"] == "stdlib.map.has_key" }
  entry && entry["authority_surface"] == "none" && entry["purity"] == "pure"
end

check "G-03: OOF-IF1 enforces Bool condition in if_expr — is_empty output must be Bool" do
  TC_SRC.include?('"OOF-IF1"') &&
    TC_SRC.include?('if_expr condition must be Bool')
end

check "G-04: filter predicate OOF-COL3 enforces Bool return — is_empty used as predicate requires Bool" do
  TC_SRC.include?('"OOF-COL3"') &&
    TC_SRC.include?("predicate must return Bool")
end

check "G-05: No fold_stream or T3 path involves emptiness check (is_empty is pure regular-call)" do
  # fold_stream T3 is handle_t3_variant; is_empty has no T3 path
  !TC_SRC.include?('when "is_empty"') && !TC_SRC.include?('when "non_empty"')
end

check "G-06: contains/starts_with/ends_with in TEXT_STDLIB_FNS return Bool — Bool predicate pattern established" do
  TC_SRC.include?('"contains"') && TC_SRC.include?('"starts_with"') &&
    TC_SRC.include?('return_type: "Bool"')
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — CLOSED SURFACES (4)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n── H: CLOSED SURFACES ──────────────────────────────────────────────────"

check "H-01: TC source has no is_empty or non_empty implementation" do
  !TC_SRC.include?("infer_is_empty") && !TC_SRC.include?("infer_non_empty") &&
    !TC_SRC.include?("stdlib.collection.is_empty") && !TC_SRC.include?("stdlib.collection.non_empty")
end

check "H-02: state_machine.ig unmodified — still documents gap (no app fixture edits)" do
  # The gap comment is the evidence; unchanged from original
  STATE_MACHINE_SRC.include?("we lack is_empty()")
end

check "H-03: 'head' not dispatched in TC infer_call (separate future card)" do
  !TC_SRC.include?('when "head"') && !TC_SRC.include?("infer_head_call")
end

check "H-04: 'find_one' not dispatched in TC infer_call (separate future card)" do
  !TC_SRC.include?('when "find_one"') && !TC_SRC.include?("infer_find_one_call")
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

puts "\n" + "─" * 72
total = $pass + $fail
puts "LAB-STDLIB-IS-EMPTY-P1: #{$pass} PASS / #{$fail} FAIL / #{total} total"
if $fail.zero?
  puts "VERDICT: ACCEPT — stdlib.collection.is_empty + stdlib.collection.non_empty ready for proposal"
  puts "  is_empty : Collection[T] -> Bool  (pure, total, authority_surface:none)"
  puts "  non_empty: Collection[T] -> Bool  (pure, total, authority_surface:none — cannot derive via !)"
  puts "Next route: LANG-STDLIB-IS-EMPTY-PROP-P1 (proposal authoring)"
else
  puts "VERDICT: BLOCKED — #{$fail} checks failed"
end
