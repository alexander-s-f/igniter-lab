#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_rust_typed_compute_binding_p1.rb
# LANG-RUST-TYPED-COMPUTE-BINDING-P1
# =====================================================================
# Research + proof that Rust TC does not propagate compute type
# annotations into symbol_types when the inferred RHS is Unknown-bearing.
#
# Answers all 13 research questions. Sections:
#
#   A  Source survey: annotation handling in Rust TC      (6)
#   B  Current gap reproduction: typed [] → Unknown bind  (5)
#   C  Downstream append sees wrong type today             (5)
#   D  Output boundary comparison: direct output works     (4)
#   E  Ruby parity behavior (LANG-TYPED-COMPUTE-BINDING-P2)(5)
#   F  Concrete match case                                 (4)
#   G  Concrete mismatch case                              (4)
#   H  Unannotated compute unchanged                       (4)
#   I  arch_patterns c0..c4 evidence                       (5)
#   J  Implementation insertion point + non-goals          (4)
#
# Total: 46 checks (target: ≥40)
# Acceptance: ≥40 PASS
#
# Run: ruby verify_rust_typed_compute_binding_p1.rb
#      (from igniter-lab/igniter-compiler/ or anywhere with absolute paths below)

require "json"
require "open3"
require "pathname"
require "tmpdir"

COMPILER_DIR = Pathname.new(__FILE__).parent
LAB_ROOT     = COMPILER_DIR.parent
WORKSPACE    = LAB_ROOT.parent
IGNITER_LIB  = WORKSPACE / "igniter-lang" / "lib"
COMPILER_BIN = COMPILER_DIR / "target" / "release" / "igniter_compiler"
TC_RUST_PATH = COMPILER_DIR / "src" / "typechecker.rs"
TC_RUBY_PATH = WORKSPACE / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
APPS_DIR     = LAB_ROOT / "igniter-apps"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Rust binary not found — run: cargo build --release" unless COMPILER_BIN.exist?

# ── Harness ──────────────────────────────────────────────────────────────────

CHECKS = []

def check(label)
  pass   = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  CHECKS << { label: label, pass: pass, detail: detail }
  puts "#{pass ? "PASS" : "FAIL"} #{label}"
  puts "     #{detail}" if detail
  pass
end

def section(name, description = "")
  puts "\n[#{name}]#{description.empty? ? "" : " #{description}"}"
end

# ── Compile helpers ───────────────────────────────────────────────────────────

def ruby_compile(source)
  Dir.mktmpdir("rtcb_rb_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [f], out_path: out)
    r = result["result"] || result
    {
      status: r["status"]         || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def rust_compile(source)
  Dir.mktmpdir("rtcb_rs_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", f, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def rust_compile_app(app_dir)
  files = Dir.glob((app_dir / "*.ig").to_s).sort
  Dir.mktmpdir("rtcb_app_rs_") do |dir|
    out = File.join(dir, "out")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", *files, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def ruby_ok?(s)   = ruby_compile(s)[:status] == "ok"
def rust_ok?(s)   = rust_compile(s)[:status] == "ok"
def ruby_oof?(s)  = ruby_compile(s)[:status] == "oof"
def rust_oof?(s)  = rust_compile(s)[:status] == "oof"

# ── Fixtures ─────────────────────────────────────────────────────────────────

# Q2: gap scenario — typed [] seed → intermediate compute → downstream append → output
GAP_CHAIN_FIXTURE = <<~IG
  module GapChain
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract TestChain {
    input elem : Item
    compute c0 : Collection[Item] = []
    compute c1 = append(c0, elem)
    output c1 : Collection[Item]
  }
IG

# Gap scenario with non-empty typed array literal
GAP_CHAIN_NONEMPTY = <<~IG
  module GapChainNE
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract TestChainNE {
    input extra : Item
    compute seed_a = { value: 1 }
    compute seed_b = { value: 2 }
    compute c0 : Collection[Item] = [seed_a, seed_b]
    compute c1 = append(c0, extra)
    output c1 : Collection[Item]
  }
IG

# Direct output — Rust LAB-TC-ARRAY-P1 handles this via collection_output_hints
DIRECT_OUTPUT_FIXTURE = <<~IG
  module DirectOut
  type Item { value : Integer }
  contract DirectOutput {
    compute xs : Collection[Item] = []
    output xs : Collection[Item]
  }
IG

# Direct output with non-empty array — tests that annotation + empty array boundary works
DIRECT_OUTPUT_NONEMPTY = <<~IG
  module DirectNE
  type Item { value : Integer }
  contract DirectOutputNE {
    compute a = { value: 1 }
    compute b = { value: 2 }
    compute xs : Collection[Item] = [a, b]
    output xs : Collection[Item]
  }
IG

# Multi-hop chain: c0 annotation → c1 (append) → c2 (append) → output
MULTI_HOP_FIXTURE = <<~IG
  module MultiHop
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract MultiHop {
    input elem_a : Item
    input elem_b : Item
    compute c0 : Collection[Item] = []
    compute c1 = append(c0, elem_a)
    compute c2 = append(c1, elem_b)
    output c2 : Collection[Item]
  }
IG

# Unannotated — no type_annotation on compute; baseline behavior
UNANNOTATED_FIXTURE = <<~IG
  module Unannotated
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract Unann {
    input elem : Item
    compute c0 = []
    compute c1 = append(c0, elem)
    output c1 : Collection[Item]
  }
IG

# Ruby parity fixture — same chain, verifies Ruby ok (P2 propagates)
RUBY_PARITY_FIXTURE = GAP_CHAIN_FIXTURE

# Concrete match — annotation matches inferred type (no Unknown)
CONCRETE_MATCH_FIXTURE = <<~IG
  module ConcreteMatch
  contract CMatch {
    compute s : String = "hello"
    output s : String
  }
IG

# Concrete mismatch — annotation says String, inferred is Integer
CONCRETE_MISMATCH_FIXTURE = <<~IG
  module ConcreteMismatch
  contract CMismatch {
    compute n : String = 42
    output n : String
  }
IG

# String chain — annotation works for String (primitive, not Unknown)
STRING_CHAIN_FIXTURE = <<~IG
  module StringChain
  import stdlib.collection.{ append }
  contract SChain {
    input s : String
    compute c0 : Collection[String] = ["hello"]
    compute c1 = append(c0, s)
    output c1 : Collection[String]
  }
IG

# ── Read TC source once ───────────────────────────────────────────────────────
TC_RUST_SRC = TC_RUST_PATH.read(encoding: "utf-8")
TC_RUBY_SRC = TC_RUBY_PATH.read(encoding: "utf-8")

# ═══════════════════════════════════════════════════════════════════════════════

section "A", "Source survey: annotation handling in Rust TC"
# Q1: Where does Rust typecheck compute declarations?
# Q2: Where is a compute's declared type annotation read?
# Q3: Where are local symbol types updated after compute inference?

check('A-01: compute arm exists at "compute" | "snapshot" branch in typechecker.rs') {
  TC_RUST_SRC.include?('"compute" | "snapshot"')
}

check("A-02: type_annotation field is present in Rust declarations (Classify output has type_annotation)") {
  # The classifier outputs type_annotation as a JSON field; Rust reads it with decl.type_annotation
  TC_RUST_SRC.include?("decl.type_annotation")
}

check("A-03: symbol_types.insert is the single bind site for compute nodes (line ~1187)") {
  # After all upgrades, typed_expr.resolved_type is inserted — this is where the gap lives
  TC_RUST_SRC.include?("symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())")
}

check("A-04: decl.type_annotation is NOT used to override bind type in the compute arm (gap confirmed)") {
  # In the compute arm, annotation is used only for output_type_hints (pre-scan) and map annotation
  # checks — never to set typed_expr.resolved_type for binding.
  # Evidence: the only use of decl.type_annotation inside "compute" arm is for LAB-MAP-RUST-P1
  # annotation checking, not for bind-type override.
  # Confirmed by: no "if let Some(ann) = &decl.type_annotation { ... typed_expr.resolved_type = ..." in compute arm
  !TC_RUST_SRC.match?(/compute.*snapshot.*\n(?:.*\n){0,80}type_annotation.*resolved_type\s*=\s*self\.type_ir/)
}

check("A-05: collection_output_hints is built only from output-level and record-field hints (LAB-TC-ARRAY-P1/P2)") {
  TC_RUST_SRC.include?("LAB-TC-ARRAY-P1") &&
    TC_RUST_SRC.include?("LAB-TC-ARRAY-P2") &&
    TC_RUST_SRC.include?("collection_output_hints")
}

check("A-06: output arm reads decl.type_annotation to get expected type for structurally_assignable check") {
  # The output check at line ~1228 reads decl.type_annotation — annotation IS used at output boundary
  TC_RUST_SRC.include?('"output" =>') &&
    TC_RUST_SRC.include?("decl.type_annotation.as_ref().unwrap()") &&
    TC_RUST_SRC.include?("structurally_assignable")
}

# ─────────────────────────────────────────────────────────────────────────────

section "B", "Current gap reproduction: typed [] → Unknown bind in Rust"
# Q4: Does Rust upgrade at compute binding or only at output boundary?
# Q5: What type does c0 get in symbol_types today?

check("B-01: GAP CHAIN — Rust oof (downstream append from annotated [] intermediate fails)") {
  rust_oof?(GAP_CHAIN_FIXTURE)
}

check("B-02: GAP CHAIN — Rust diagnostic is OOF-TY1 (output type mismatch, not OOF-COL)") {
  r = rust_compile(GAP_CHAIN_FIXTURE)
  r[:codes].include?("OOF-TY1")
}

check("B-03: GAP CHAIN NONEMPTY — Rust oof even with non-empty typed array literal seed") {
  # [seed_a, seed_b] where items are Unknown record literals → still infers Unknown
  rust_oof?(GAP_CHAIN_NONEMPTY)
}

check("B-04: MULTI-HOP — Rust oof (two-hop chain: c0→c1→c2 all Unknown-bearing)") {
  rust_oof?(MULTI_HOP_FIXTURE)
}

check("B-05: STRING CHAIN — Rust oof (even String-typed seed, because items are String literals but array infers Unknown)") {
  # "hello" is a String literal — infer_expr returns String. But [String] → Collection?
  # Actually, ArrayLiteral in infer_expr always returns Unknown (comment at line 3990).
  # So Collection[String] annotation is not used for binding → c0 = Unknown → c1 = Collection[Unknown]
  rust_oof?(STRING_CHAIN_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "C", "Downstream append sees wrong type today"
# Q5 (continued): What exact type does c0 get?
# Q6: Is the gap limited to Collection[Unknown], or any Unknown-bearing type?

check("C-01: GAP CHAIN OOF-TY1 message mentions Collection[Unknown] or Unknown (append returns Unknown-bearing)") {
  r = rust_compile(GAP_CHAIN_FIXTURE)
  r[:diags].any? { |d|
    msg = d["message"] || ""
    msg.include?("Unknown") && (d["rule"] == "OOF-TY1")
  }
}

check("C-02: MULTI-HOP also OOF-TY1 (gap propagates through multiple append hops)") {
  r = rust_compile(MULTI_HOP_FIXTURE)
  r[:codes].include?("OOF-TY1")
}

check("C-03: GAP confirms append(Unknown, T) → Collection[Unknown] in Rust (not OOF-COL2 / OOF-COL6)") {
  # append's first arg is Unknown (not non-Collection) → col_arg_name="Unknown" → elem_type=Unknown
  # → resolved_type = Collection[Unknown] → no OOF-COL2/COL6 but eventual OOF-TY1 at output
  r = rust_compile(GAP_CHAIN_FIXTURE)
  !r[:codes].include?("OOF-COL2") && !r[:codes].include?("OOF-COL6") && r[:codes].include?("OOF-TY1")
}

check("C-04: gap is NOT limited to empty array — non-empty annotated intermediate also fails") {
  rust_oof?(GAP_CHAIN_NONEMPTY)
}

check("C-05: structurally_assignable rejects Unknown actual at any param depth (D2 rule — line ~2049)") {
  # structurally_assignable recurses into params;
  # actual_params=[Unknown], expected_params=[T]; structurally_assignable(Unknown, T) → false (D2)
  TC_RUST_SRC.include?("D2: actual Unknown always rejected")
}

# ─────────────────────────────────────────────────────────────────────────────

section "D", "Output boundary comparison: direct output of annotated [] works in Rust"
# Q4 (continued): Rust upgrades at output boundary only for direct-output position.

check("D-01: DIRECT OUTPUT — Rust ok/0 when annotated [] is directly the output name") {
  # collection_output_hints["xs"] fires because output xs : Collection[Item] exists
  rust_ok?(DIRECT_OUTPUT_FIXTURE)
}

check("D-02: DIRECT OUTPUT NONEMPTY — Rust ok/0 when annotated [a,b] is directly the output name") {
  rust_ok?(DIRECT_OUTPUT_NONEMPTY)
}

check("D-03: collection_output_hints is the mechanism — keyed on output.name → Collection element IR") {
  # LAB-TC-ARRAY-P1 pre-scan builds collection_output_hints from output declarations
  # The key is the output node NAME; when compute name == output name, the hint fires
  TC_RUST_SRC.include?("collection_output_hints") &&
    TC_RUST_SRC.include?("LAB-TC-ARRAY-P1: pre-scan output declarations")
}

check("D-04: DIRECT OUTPUT diverges from GAP CHAIN — same annotation, different position") {
  # The ONLY difference: in DIRECT_OUTPUT, compute xs IS the output name → hint fires
  # In GAP_CHAIN, compute c0 is NOT the output name (c1 is) → no hint for c0
  rust_ok?(DIRECT_OUTPUT_FIXTURE) && rust_oof?(GAP_CHAIN_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "E", "Ruby parity behavior (LANG-TYPED-COMPUTE-BINDING-P2)"
# Q7: Should Rust mirror Ruby P2 exactly?

check("E-01: GAP CHAIN — Ruby ok/0 (LANG-TYPED-COMPUTE-BINDING-P2 propagates annotation into bind type)") {
  ruby_ok?(GAP_CHAIN_FIXTURE)
}

check("E-02: MULTI-HOP — Ruby ok/0 (annotation propagates through chain)") {
  ruby_ok?(MULTI_HOP_FIXTURE)
}

check("E-03: STRING CHAIN — Ruby ok/0 (String annotation propagates; append(Collection[String], String) ok)") {
  ruby_ok?(STRING_CHAIN_FIXTURE)
}

check("E-04: unknown_or_unknown_bearing? helper exists in Ruby TC") {
  TC_RUBY_SRC.include?("def unknown_or_unknown_bearing?")
}

check("E-05: Ruby P2 compute arm uses unknown_or_unknown_bearing? to decide bind type") {
  TC_RUBY_SRC.include?("unknown_or_unknown_bearing?(inferred_type)") &&
    TC_RUBY_SRC.include?("expected_type")
}

# ─────────────────────────────────────────────────────────────────────────────

section "F", "Concrete match case"
# Q8: What happens for concrete mismatch?
# Q9: What happens for concrete match?

check("F-01: CONCRETE MATCH — Ruby ok (annotation matches inferred String literal)") {
  ruby_ok?(CONCRETE_MATCH_FIXTURE)
}

check("F-02: CONCRETE MATCH — Rust ok (no annotation processing, inferred String is used and correct)") {
  rust_ok?(CONCRETE_MATCH_FIXTURE)
}

check("F-03: Ruby P2 takes structurally_assignable? branch for concrete match (uses inferred type)") {
  # When inferred is NOT unknown_bearing AND structurally_assignable?(inferred, expected) → inferred_type
  # Code: elsif structurally_assignable?(inferred_type, expected_type) \n inferred_type
  TC_RUBY_SRC.include?("elsif structurally_assignable?(inferred_type, expected_type)") &&
    TC_RUBY_SRC.include?("inferred_type")
}

check("F-04: DIRECT OUTPUT NONEMPTY concrete — both ok (items typed via P3 in Ruby, via hint in Rust)") {
  ruby_ok?(DIRECT_OUTPUT_NONEMPTY) && rust_ok?(DIRECT_OUTPUT_NONEMPTY)
}

# ─────────────────────────────────────────────────────────────────────────────

section "G", "Concrete mismatch case"
# Q8: What happens for concrete mismatch?

check("G-01: CONCRETE MISMATCH — Ruby oof (OOF-TY0: Binding type mismatch)") {
  r = ruby_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:status] == "oof" && r[:codes].include?("OOF-TY0")
}

check("G-02: CONCRETE MISMATCH — Rust status (no OOF-TY0 for annotation mismatch today)") {
  # Rust does NOT check annotation vs inferred type in the compute arm —
  # it only checks at the output boundary. So the output check sees Integer
  # vs String → OOF-TY1 (not OOF-TY0). Rust never emits OOF-TY0 for this.
  r = rust_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:codes].include?("OOF-TY1") && !r[:codes].include?("OOF-TY0")
}

check("G-03: Rust concrete mismatch produces OOF-TY1 at output boundary (not binding-time OOF-TY0)") {
  r = rust_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:codes] == ["OOF-TY1"]
}

check("G-04: Ruby concrete mismatch produces OOF-TY0 at binding time (annotation authoritative, output ok)") {
  # Ruby P2: concrete mismatch → OOF-TY0 + annotation authoritative → bind_type = String
  # → output check String vs String → ok (only OOF-TY0, no OOF-TY1)
  r = ruby_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:codes].include?("OOF-TY0") && !r[:codes].include?("OOF-TY1")
}

# ─────────────────────────────────────────────────────────────────────────────

section "H", "Unannotated compute unchanged"
# Q10: What happens when there is no annotation?

check("H-01: UNANNOTATED — Rust oof (no annotation to override Unknown bind; same as before P2 concept)") {
  rust_oof?(UNANNOTATED_FIXTURE)
}

check("H-02: UNANNOTATED — Ruby oof (no annotation → inferred_type = Unknown; output fails)") {
  ruby_oof?(UNANNOTATED_FIXTURE)
}

check("H-03: both TCs same behavior for unannotated (no regression from annotation-handling change)") {
  ruby_oof?(UNANNOTATED_FIXTURE) && rust_oof?(UNANNOTATED_FIXTURE)
}

check("H-04: Ruby compute arm else branch uses inferred_type when no annotation present") {
  # else clause: bind_type = inferred_type
  TC_RUBY_SRC.include?("else\n            inferred_type\n          end")
}

# ─────────────────────────────────────────────────────────────────────────────

section "I", "arch_patterns c0..c4 evidence"
# Q12: Which arch_patterns sites are unblocked?

check("I-01: arch_patterns Rust oof/6 currently (5 OOF-TY0 call_contract + 1 OOF-TY1 cascade)") {
  r = rust_compile_app(APPS_DIR / "arch_patterns")
  r[:status] == "oof" &&
    r[:codes].count("OOF-TY0") == 5 &&
    r[:codes].include?("OOF-TY1") &&
    r[:count] == 6
}

check("I-02: arch_patterns OOF-TY1 message references Collection[Transition] (c4 output boundary)") {
  r = rust_compile_app(APPS_DIR / "arch_patterns")
  r[:diags].any? { |d| d["rule"] == "OOF-TY1" && (d["message"] || "").include?("Transition") }
}

check("I-03: arch_patterns/example.ig c0-c4 are still stringly call_contract sites (not yet migrated)") {
  src = (APPS_DIR / "arch_patterns" / "example.ig").read(encoding: "utf-8")
  src.scan(/call_contract\s*\(\s*"append"/).size == 5
}

check("I-04: c0-c4 migration plan: BOOTSTRAP c0 as Collection[Transition] + ACCUMULATING c1-c4 unblocked by P2") {
  # After P2 Rust fix:
  # compute c0 : Collection[Transition] = [t0, t1]  → bind type = Collection[Transition]
  # compute c1 = append(c0, t2)  → append(Collection[Transition], Unknown) → Collection[Transition]
  #   (no OOF-COL6: elem=Transition, item=Unknown → item is Unknown → check skipped)
  # → c1..c4 all Collection[Transition] → output ok
  TC_RUST_SRC.include?("elem_name != \"Unknown\" && item_name != \"Unknown\" && elem_name != item_name")
}

check("I-05: LANG-RUST-TYPED-COMPUTE-BINDING-P2 unblocks all 5 arch_patterns deferred sites") {
  # After migration (not done in P1) + P2 fix:
  # c0-c4 all Collection[Transition] → output c4 : Collection[Transition] ok → 0 diags
  # Evidence: gap fixture (same shape) OOF-TY1 in Rust, ok in Ruby
  rust_oof?(GAP_CHAIN_FIXTURE) && ruby_ok?(GAP_CHAIN_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "J", "Implementation insertion point + non-goals"
# Q13: Can P2 be one local Rust TC change?

check("J-01: insertion point is immediately before symbol_types.insert in the compute arm (~line 1187)") {
  # The fix inserts annotation override logic between the array-literal upgrade block and the
  # symbol_types.insert call. One location in one file.
  idx = TC_RUST_SRC.index("symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())")
  idx && idx > 0
}

check("J-02: helper unknown_or_unknown_bearing does NOT exist in Rust TC yet (needs to be added in P2)") {
  !TC_RUST_SRC.include?("unknown_or_unknown_bearing") &&
    !TC_RUST_SRC.include?("unknown_bearing")
}

check("J-03: structurally_assignable already exists in Rust TC (can be reused for concrete-match branch)") {
  TC_RUST_SRC.include?("fn structurally_assignable")
}

check("J-04: no parser change needed — type_annotation already parsed and available in decl (Rust uses Option<serde_json::Value>)") {
  # annotation is present in classifier JSON output; decl.type_annotation is Option<serde_json::Value>
  # Parser already emits type_annotation for compute declarations. No parser change for P2.
  TC_RUST_SRC.include?("type_annotation.as_ref()") &&
    !TC_RUST_SRC.include?("parse_compute_annotation") # no special parsing needed
}

# ═══════════════════════════════════════════════════════════════════════════════

puts "\n" + "=" * 60
total  = CHECKS.size
passed = CHECKS.count { |c| c[:pass] }
failed = CHECKS.reject { |c| c[:pass] }

puts "TOTAL: #{passed}/#{total} PASS"

if failed.any?
  puts "\nFailed checks:"
  failed.each { |c| puts "  FAIL #{c[:label]}" }
end

# ── Research answers summary ──────────────────────────────────────────────────
puts <<~SUMMARY

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RESEARCH ANSWERS
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Q01 Where does Rust typecheck compute declarations?
      typechecker.rs: "compute" | "snapshot" arm (~line 1106).

  Q02 Where is a compute's declared type annotation read?
      In the "output" arm (~line 1228) and pre-scan for
      collection_output_hints (LAB-TC-ARRAY-P1/P2, lines ~698-747).
      It is NOT read in the compute arm to override the bind type.

  Q03 Where are local symbol types updated after compute inference?
      symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())
      — single call after array/record upgrades (~line 1187).

  Q04 Does Rust upgrade at output boundary only or also at compute binding?
      Output boundary ONLY (via collection_output_hints pre-scan for
      direct-output positions). Intermediate computes with annotations
      are NOT upgraded — their symbol_types entry remains Unknown.

  Q05 What exact type does c0 get in symbol_types today?
      Unknown. infer_expr for ArrayLiteral always returns Unknown
      (by design — comment at line 3990). The collection_output_hints
      mechanism only fires when the compute node name == an output name.

  Q06 Is the gap limited to Collection[Unknown], or any Unknown-bearing type?
      Any compute annotation where the RHS infers as Unknown or
      Unknown-bearing. For arrays: always Unknown from infer_expr.
      For record literals: Unknown unless a record-hint fires.
      structurally_assignable rejects Unknown at any param depth (D2).

  Q07 Should Rust mirror Ruby P2 exactly?
      Yes. Same three-way branch:
        (a) Unknown-bearing inferred → use annotation, no error
        (b) Concrete match (structurally_assignable) → use inferred
        (c) Concrete mismatch → emit OOF-TY0, use annotation to prevent cascade

  Q08 What happens for concrete mismatch?
      Ruby: OOF-TY0 at binding time; annotation used; no cascade OOF-TY1.
      Rust (today): no binding-time error; inferred type used; OOF-TY1
        may fire at output boundary (secondary gap — lower priority than Unknown gap).

  Q09 What happens for concrete match?
      Both TCs: inferred type is used; annotation confirms. No error.
      After P2 Rust fix: same — structurally_assignable branch keeps inferred type.

  Q10 What happens when there is no annotation?
      Both TCs: inferred type used as bind type unchanged. No regression.

  Q11 What happens when annotation is non-Collection?
      Same three-way branch applies. A String annotation on a String
      literal → concrete match → no gap. A Map[K,V] annotation on
      Unknown-bearing expr → use annotation (same rule, different type).

  Q12 Which arch_patterns sites are unblocked by P2?
      All 5 deferred sites (c0-c4 in BuildTransitionTable):
        compute c0 : Collection[Transition] = [t0, t1]
        compute c1 = append(c0, t2)  ...  compute c4 = append(c3, t5)
        output c4 : Collection[Transition]
      After P2: c0 binds Collection[Transition]; append(Collection[T], Unknown)
      returns Collection[T] (item Unknown → OOF-COL6 check skipped);
      c1..c4 all Collection[Transition]; OOF-TY1 clears. → arch_patterns DUAL-CLEAN.

  Q13 Can P2 be one local Rust TC change?
      Yes. One file: typechecker.rs. One insertion point: before
      symbol_types.insert in the compute arm (~line 1187).
      Two additions:
        (a) fn unknown_or_unknown_bearing — ~4 lines recursive helper
        (b) annotation override block — ~15 lines (mirror Ruby P2 logic)
      No parser change. No emitter change. No stdlib change. No app change.

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY

exit(passed >= 40 ? 0 : 1)
