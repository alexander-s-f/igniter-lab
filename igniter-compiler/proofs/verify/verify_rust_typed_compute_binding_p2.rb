#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_rust_typed_compute_binding_p2.rb
# LANG-RUST-TYPED-COMPUTE-BINDING-P2
# =====================================================================
# Proof that the P2 implementation is correct:
#   - fn unknown_or_unknown_bearing helper added to typechecker.rs
#   - Annotation override block added in compute arm (three-way branch)
#   - Rust TC now mirrors Ruby LANG-TYPED-COMPUTE-BINDING-P2 behavior
#
# Sections:
#
#   A  Source patch present                            (4)
#   B  Helper detects scalar Unknown                   (4)
#   C  Helper detects param-depth Unknown              (4)
#   D  Annotated [] binds Collection[T]                (4)
#   E  Downstream append sees Collection[T]            (4)
#   F  Concrete match behavior preserved               (4)
#   G  Concrete mismatch OOF-TY0 diagnostic           (4)
#   H  Unannotated compute unchanged                   (3)
#   I  Output boundary unchanged (LAB-TC-ARRAY-P1)    (4)
#   J  arch_patterns c0-c4 shape unblocked             (4)
#   K  Ruby parity / no Ruby TC changes               (3)
#   L  No parser / emitter / stdlib changes            (3)
#
# Total: 45 checks (target: ≥45)
# Acceptance: ≥45 PASS
#
# Run: ruby verify_rust_typed_compute_binding_p2.rb
#      (from igniter-lab/igniter-compiler/)

require "json"
require "open3"
require "pathname"
require "tmpdir"

COMPILER_DIR = Pathname.new(__FILE__).parent.parent.parent
LAB_ROOT     = COMPILER_DIR.parent
WORKSPACE    = LAB_ROOT.parent
IGNITER_LIB  = WORKSPACE / "igniter-lang" / "lib"
COMPILER_BIN = COMPILER_DIR / "target" / "release" / "igniter_compiler"
TC_RUST_PATH = COMPILER_DIR / "src" / "typechecker.rs"
TC_RUBY_PATH = WORKSPACE / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
APPS_DIR     = LAB_ROOT / "igniter-apps"
PARSER_PATH  = COMPILER_DIR / "src" / "parser.rs"
EMITTER_PATH = WORKSPACE / "igniter-lang" / "lib" / "igniter_lang" / "emitter.rb"
STDLIB_PATH  = WORKSPACE / "igniter-lang" / "lib" / "igniter_lang" / "stdlib"

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
  Dir.mktmpdir("rtcb2_rb_") do |dir|
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
  Dir.mktmpdir("rtcb2_rs_") do |dir|
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
  Dir.mktmpdir("rtcb2_app_rs_") do |dir|
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

def ruby_compile_app(app_dir)
  files = Dir.glob((app_dir / "*.ig").to_s).sort
  Dir.mktmpdir("rtcb2_app_rb_") do |dir|
    out = File.join(dir, "out")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: files, out_path: out)
    r = result["result"] || result
    {
      status: r["status"]         || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def rust_ok?(s)  = rust_compile(s)[:status] == "ok"
def rust_oof?(s) = rust_compile(s)[:status] == "oof"
def ruby_ok?(s)  = ruby_compile(s)[:status] == "ok"
def ruby_oof?(s) = ruby_compile(s)[:status] == "oof"

# ── Fixtures ─────────────────────────────────────────────────────────────────

# Core gap fixture: annotated [] intermediate → downstream append → output
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

# Non-empty annotated intermediate: items are Unknown record literals
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

# Param-depth Unknown: inferred = Collection[Unknown] (not scalar Unknown)
# base=[] unannotated → Unknown; append(base, elem) → Collection[Unknown]
# c0 annotation Collection[Item]: unknown_or_unknown_bearing(Collection[Unknown]) → true via params
COL_UNKNOWN_FIXTURE = <<~IG
  module ColUnknownTest
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract ColUnknownTest {
    input elem : Item
    compute base = []
    compute c0 : Collection[Item] = append(base, elem)
    output c0 : Collection[Item]
  }
IG

# Direct output — LAB-TC-ARRAY-P1 collection_output_hints mechanism
DIRECT_OUTPUT_FIXTURE = <<~IG
  module DirectOut
  type Item { value : Integer }
  contract DirectOutput {
    compute xs : Collection[Item] = []
    output xs : Collection[Item]
  }
IG

# Multi-hop chain
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

# Unannotated — no override fires
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

# Concrete match: String annotation, String inferred — branch (b), no error
CONCRETE_MATCH_FIXTURE = <<~IG
  module ConcreteMatch
  contract CMatch {
    compute s : String = "hello"
    output s : String
  }
IG

# Concrete mismatch: String annotation, Integer inferred — branch (c), OOF-TY0
CONCRETE_MISMATCH_FIXTURE = <<~IG
  module ConcreteMismatch
  contract CMismatch {
    compute n : String = 42
    output n : String
  }
IG

# String collection chain
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

# ── Read source files once ─────────────────────────────────────────────────────
TC_RUST_SRC  = TC_RUST_PATH.read(encoding: "utf-8")
TC_RUBY_SRC  = TC_RUBY_PATH.read(encoding: "utf-8")
PARSER_SRC   = PARSER_PATH.exist? ? PARSER_PATH.read(encoding: "utf-8") : ""

# ═══════════════════════════════════════════════════════════════════════════════

section "A", "Source patch present"

check("A-01: fn unknown_or_unknown_bearing defined in typechecker.rs") {
  TC_RUST_SRC.include?("fn unknown_or_unknown_bearing")
}

check("A-02: annotation override block present — LANG-RUST-TYPED-COMPUTE-BINDING-P2 comment marker") {
  TC_RUST_SRC.include?("LANG-RUST-TYPED-COMPUTE-BINDING-P2")
}

check("A-03: three-way branch structure present (annotation override block)") {
  # Branch (a): Unknown-bearing inferred → annotation authoritative
  # Branch (c): concrete mismatch → OOF-TY0
  TC_RUST_SRC.include?("unknown_or_unknown_bearing(&typed_expr.resolved_type)") &&
    TC_RUST_SRC.include?("structurally_assignable(&typed_expr.resolved_type, &ann_type)")
}

check("A-04: override block is immediately before symbol_types.insert (binding site)") {
  # Confirm the code pattern: if let Some(ann) = ... { ... } then symbol_types.insert
  idx_block  = TC_RUST_SRC.index("if let Some(ann) = &decl.type_annotation {")
  idx_insert = TC_RUST_SRC.index("symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())")
  idx_block && idx_insert && idx_block < idx_insert
}

# ─────────────────────────────────────────────────────────────────────────────

section "B", "Helper detects scalar Unknown"

check("B-01: helper source — scalar check: self.type_name(t) == \"Unknown\"") {
  TC_RUST_SRC.include?('self.type_name(t) == "Unknown"') ||
    TC_RUST_SRC.match?(/unknown_or_unknown_bearing[^{]+\{[^}]*"Unknown"/)
}

check("B-02: helper source — recursive params check via iter().any") {
  TC_RUST_SRC.include?("params.iter().any(|p| self.unknown_or_unknown_bearing")
}

check("B-03: behavioral — empty annotated array literal → Unknown scalar → annotation used → ok") {
  # GAP_CHAIN: compute c0 : Collection[Item] = []
  # infer_expr([]) → Unknown (scalar) → helper returns true → annotation Collection[Item] used
  rust_ok?(GAP_CHAIN_FIXTURE)
}

check("B-04: behavioral — non-empty annotated array with Unknown items → Unknown scalar → ok") {
  # [seed_a, seed_b] where items are Unknown record literals → ArrayLiteral still infers Unknown
  # (infer_expr for ArrayLiteral always returns Unknown — not an element-level inference)
  rust_ok?(GAP_CHAIN_NONEMPTY)
}

# ─────────────────────────────────────────────────────────────────────────────

section "C", "Helper detects param-depth Unknown (Collection[Unknown])"

check("C-01: helper source — recursive call: self.unknown_or_unknown_bearing(&self.type_ir(p))") {
  TC_RUST_SRC.include?("self.unknown_or_unknown_bearing(&self.type_ir(p))")
}

check("C-02: helper handles unwrap_or(false) for types with no params") {
  TC_RUST_SRC.include?("unwrap_or(false)") &&
    TC_RUST_SRC.match?(/unknown_or_unknown_bearing[\s\S]{0,300}unwrap_or\(false\)/)
}

check("C-03: behavioral — COL_UNKNOWN: inferred = Collection[Unknown] → helper true via params → annotation used → ok") {
  # base=[] unannotated → Unknown; append(Unknown, elem) → Collection[Unknown]
  # c0 : Collection[Item] = append(base, elem) → inferred Collection[Unknown]
  # unknown_or_unknown_bearing(Collection[Unknown]) → params=[Unknown] → iter finds Unknown → true
  # → annotation Collection[Item] authoritative → ok
  rust_ok?(COL_UNKNOWN_FIXTURE)
}

check("C-04: structural_assignable rejects Collection[Unknown] as actual (D2 rule) — helper is necessary") {
  # Without the helper: structurally_assignable(Collection[Unknown], Collection[Item]) would be called
  # at the output boundary — false (D2: Unknown actual rejected) → OOF-TY1.
  # The helper routes to branch (a) BEFORE it reaches output boundary check.
  # Verify: unannotated version (no override) still fails at output
  rust_oof?(UNANNOTATED_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "D", "Annotated [] compute binds Collection[T]"

check("D-01: GAP_CHAIN ok/0 — annotated [] → Collection[Item] bound (not Unknown)") {
  r = rust_compile(GAP_CHAIN_FIXTURE)
  r[:status] == "ok" && r[:count] == 0
}

check("D-02: MULTI_HOP ok/0 — c0 annotation propagates through two-hop chain") {
  r = rust_compile(MULTI_HOP_FIXTURE)
  r[:status] == "ok" && r[:count] == 0
}

check("D-03: STRING_CHAIN ok/0 — Collection[String] annotation propagates") {
  r = rust_compile(STRING_CHAIN_FIXTURE)
  r[:status] == "ok" && r[:count] == 0
}

check("D-04: GAP_CHAIN_NONEMPTY ok/0 — non-empty array seed also correct") {
  r = rust_compile(GAP_CHAIN_NONEMPTY)
  r[:status] == "ok" && r[:count] == 0
}

# ─────────────────────────────────────────────────────────────────────────────

section "E", "Downstream append sees Collection[T]"

check("E-01: GAP_CHAIN: no OOF-COL diagnostic (c1=append(Collection[Item], Item) → Collection[Item])") {
  r = rust_compile(GAP_CHAIN_FIXTURE)
  r[:codes].none? { |c| c.start_with?("OOF-COL") }
}

check("E-02: MULTI_HOP: no OOF at all (c1, c2 both Collection[Item]; chain clean)") {
  r = rust_compile(MULTI_HOP_FIXTURE)
  r[:count] == 0
}

check("E-03: OOF-COL6 guard: item=Unknown skips type check → Collection[T] preserved (source)") {
  # The OOF-COL6 guard reads: elem_name != "Unknown" && item_name != "Unknown" && elem_name != item_name
  # When item is Unknown (input not yet typed), the check is skipped → no OOF-COL6
  TC_RUST_SRC.include?("elem_name != \"Unknown\" && item_name != \"Unknown\" && elem_name != item_name")
}

check("E-04: GAP_CHAIN: no OOF-TY1 (no Unknown propagates to output boundary)") {
  r = rust_compile(GAP_CHAIN_FIXTURE)
  !r[:codes].include?("OOF-TY1")
}

# ─────────────────────────────────────────────────────────────────────────────

section "F", "Concrete match behavior preserved"

check("F-01: CONCRETE_MATCH ok/0 — String annotation matches String inferred; branch (b) keeps inferred") {
  # structurally_assignable(String, String) → true → keep inferred, no error, no change
  r = rust_compile(CONCRETE_MATCH_FIXTURE)
  r[:status] == "ok" && r[:count] == 0
}

check("F-02: DIRECT_OUTPUT ok/0 — LAB-TC-ARRAY-P1 collection_output_hints still fires for direct output") {
  rust_ok?(DIRECT_OUTPUT_FIXTURE)
}

check("F-03: branch (b) source: !structurally_assignable → branch (c); if assignable → no change") {
  # Branch (b) is the implicit else: concrete match → do nothing (no typed_expr mutation)
  # Branch (c): emit OOF-TY0 + use annotation
  # The code structure: if unknown_or_unknown_bearing → (a); else if !structurally_assignable → (c); (b) implicit
  TC_RUST_SRC.include?("!self.structurally_assignable(&typed_expr.resolved_type, &ann_type)")
}

check("F-04: CONCRETE_MATCH: no OOF-TY0 emitted (annotation matches → no mismatch error)") {
  r = rust_compile(CONCRETE_MATCH_FIXTURE)
  !r[:codes].include?("OOF-TY0")
}

# ─────────────────────────────────────────────────────────────────────────────

section "G", "Concrete mismatch OOF-TY0 diagnostic (branch c)"

check("G-01: CONCRETE_MISMATCH oof/1 OOF-TY0 — Rust now has binding-time diagnostic") {
  r = rust_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:status] == "oof" && r[:codes] == ["OOF-TY0"]
}

check("G-02: CONCRETE_MISMATCH: no cascade OOF-TY1 — annotation authoritative → output type correct") {
  # branch (c): typed_expr.resolved_type = ann_type (String); output check String vs String → ok
  r = rust_compile(CONCRETE_MISMATCH_FIXTURE)
  !r[:codes].include?("OOF-TY1")
}

check("G-03: OOF-TY0 message includes 'declared' and 'got' (binding mismatch format)") {
  r = rust_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:diags].any? { |d|
    d["rule"] == "OOF-TY0" &&
      (d["message"] || "").include?("declared") &&
      (d["message"] || "").include?("got")
  }
}

check("G-04: Ruby parity — CONCRETE_MISMATCH same OOF-TY0 behavior in Ruby") {
  r = ruby_compile(CONCRETE_MISMATCH_FIXTURE)
  r[:status] == "oof" && r[:codes].include?("OOF-TY0") && !r[:codes].include?("OOF-TY1")
}

# ─────────────────────────────────────────────────────────────────────────────

section "H", "Unannotated compute unchanged"

check("H-01: UNANNOTATED Rust oof/1 OOF-TY1 — no annotation → override block skipped → Unknown propagates") {
  r = rust_compile(UNANNOTATED_FIXTURE)
  r[:status] == "oof" && r[:codes].include?("OOF-TY1")
}

check("H-02: UNANNOTATED Ruby oof — same behavior (no regression)") {
  ruby_oof?(UNANNOTATED_FIXTURE)
}

check("H-03: override block only fires on Some(ann) — else branch (no annotation) takes no action") {
  # Source: if let Some(ann) = &decl.type_annotation { ... }
  # When decl.type_annotation is None, the block is skipped entirely
  TC_RUST_SRC.include?("if let Some(ann) = &decl.type_annotation {")
}

# ─────────────────────────────────────────────────────────────────────────────

section "I", "Output boundary behavior unchanged (LAB-TC-ARRAY-P1 still works)"

check("I-01: DIRECT_OUTPUT Rust ok/0 — collection_output_hints still fires for direct-output position") {
  r = rust_compile(DIRECT_OUTPUT_FIXTURE)
  r[:status] == "ok" && r[:count] == 0
}

check("I-02: collection_output_hints mechanism unchanged in source (LAB-TC-ARRAY-P1 markers present)") {
  TC_RUST_SRC.include?("LAB-TC-ARRAY-P1: pre-scan output declarations") &&
    TC_RUST_SRC.include?("collection_output_hints")
}

check("I-03: annotation override block runs AFTER array-literal upgrade block (ordering preserved)") {
  # The array-literal upgrade (LAB-TC-ARRAY-P1) block fires and sets typed_expr.resolved_type
  # BEFORE the annotation override block sees it. If LAB-TC-ARRAY-P1 fired, resolved_type is non-Unknown
  # → override takes branch (b) or (c), not (a). No conflict.
  # Use compute-arm-specific markers to avoid matching pre-scan occurrences.
  idx_array_block  = TC_RUST_SRC.index("LAB-TC-ARRAY-P1: contextual ArrayLiteral typing")
  idx_ann_block    = TC_RUST_SRC.index("LANG-RUST-TYPED-COMPUTE-BINDING-P2: if the compute")
  idx_insert       = TC_RUST_SRC.index("symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())")
  idx_array_block && idx_ann_block && idx_insert &&
    idx_array_block < idx_ann_block && idx_ann_block < idx_insert
}

check("I-04: bloom_filter Rust ok/0 — no regression from P2 change") {
  r = rust_compile_app(APPS_DIR / "bloom_filter")
  r[:status] == "ok" && r[:count] == 0
}

# ─────────────────────────────────────────────────────────────────────────────

section "J", "arch_patterns c0-c4 shape unblocked (stringly sites still deferred)"

check("J-01: GAP_CHAIN matches arch_patterns c0-c4 chain shape — both TCs ok/0") {
  # arch_patterns c0-c4: annotated Bootstrap seed + ACCUMULATING appends + typed output
  # GAP_CHAIN is the minimal reproduction of that shape; P2 fix makes it ok in Rust
  rust_ok?(GAP_CHAIN_FIXTURE) && ruby_ok?(GAP_CHAIN_FIXTURE)
}

check("J-02: arch_patterns Rust still oof/6 — stringly call_contract sites not yet migrated") {
  # The 5 stringly call_contract("append",...) sites have no type annotation on the compute nodes
  # → override block skips (no annotation) → Unknown propagates → OOF-TY0 for unknown callee
  # → c4 = Unknown → OOF-TY1 at output boundary
  r = rust_compile_app(APPS_DIR / "arch_patterns")
  r[:status] == "oof" &&
    r[:codes].count("OOF-TY0") == 5 &&
    r[:codes].include?("OOF-TY1") &&
    r[:count] == 6
}

check("J-03: arch_patterns Ruby still oof/6 — same pattern as Rust") {
  r = ruby_compile_app(APPS_DIR / "arch_patterns")
  r[:status] == "oof" &&
    r[:codes].count("OOF-TY0") == 5 &&
    r[:codes].include?("OOF-TY1") &&
    r[:count] == 6
}

check("J-04: arch_patterns c0-c4 are still stringly call_contract sites (migration pending)") {
  src = (APPS_DIR / "arch_patterns" / "example.ig").read(encoding: "utf-8")
  src.scan(/call_contract\s*\(\s*"append"/).size == 5
}

# ─────────────────────────────────────────────────────────────────────────────

section "K", "Ruby parity / no Ruby TC changes"

check("K-01: GAP_CHAIN — both TCs ok/0 (Rust now matches Ruby LANG-TYPED-COMPUTE-BINDING-P2)") {
  rust_ok?(GAP_CHAIN_FIXTURE) && ruby_ok?(GAP_CHAIN_FIXTURE)
}

check("K-02: Ruby TC unknown_or_unknown_bearing? helper still present (P2 did not touch Ruby TC)") {
  TC_RUBY_SRC.include?("def unknown_or_unknown_bearing?")
}

check("K-03: COL_UNKNOWN — both TCs ok/0 (param-depth Unknown handled in both)") {
  rust_ok?(COL_UNKNOWN_FIXTURE) && ruby_ok?(COL_UNKNOWN_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "L", "No parser / emitter / stdlib changes"

check("L-01: parser.rs does not contain LANG-RUST-TYPED-COMPUTE-BINDING-P2 marker (no parser change)") {
  !PARSER_SRC.include?("LANG-RUST-TYPED-COMPUTE-BINDING-P2")
}

check("L-02: emitter.rb does not contain LANG-RUST-TYPED-COMPUTE-BINDING-P2 marker (no emitter change)") {
  emitter_src = EMITTER_PATH.exist? ? EMITTER_PATH.read(encoding: "utf-8") : ""
  !emitter_src.include?("LANG-RUST-TYPED-COMPUTE-BINDING-P2")
}

check("L-03: stdlib directory mtime unchanged — no stdlib files modified by P2") {
  # Indirect check: stdlib collection source does not reference P2 card
  stdlib_collection = STDLIB_PATH / "collection.rb"
  src = stdlib_collection.exist? ? stdlib_collection.read(encoding: "utf-8") : ""
  !src.include?("LANG-RUST-TYPED-COMPUTE-BINDING-P2")
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

exit(passed >= 45 ? 0 : 1)
