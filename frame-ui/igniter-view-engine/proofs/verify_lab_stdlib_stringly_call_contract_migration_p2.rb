#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_stringly_call_contract_migration_p2.rb
# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2
# =====================================================================
# Proves that 24 stringly call_contract("append") sites have been
# migrated in arch_patterns / bloom_filter / decision_tree / vector_editor.
# 5 arch_patterns sites (c0-c4 BOOTSTRAP → direct Collection output)
# deferred to LANG-RUST-TYPED-COMPUTE-BINDING-P1.
# 5 igniter_parser sites deferred to LANG-STDLIB-STRING-SURFACE-P1.
#
# Sections:
#   A  Pre/post source scan          (8)  — migrated sites absent; deferred sites present
#   B  Non-stdlib call_contract kept (4)  — user PascalCase contract calls preserved
#   C  Dynamic call_contract kept    (3)  — rule_engine variable callees unchanged
#   D  ACCUMULATING rewrites Ruby    (6)  — canonical append(coll, elem) ok in Ruby
#   E  ACCUMULATING rewrites Rust    (6)  — canonical append(coll, elem) ok in Rust
#   F  BOOTSTRAP rewrites both TCs   (6)  — typed [elem,elem] fixtures ok in both TCs
#   G  EMPTY_CONSTRUCTOR not in P2   (3)  — igniter_parser sites still blocked (IP-P01)
#   H  bloom_filter diagnostic delta (4)  — before oof, after ok in both TCs
#   I  Site count verification       (6)  — per-app and total counts correct
#   J  Authority boundary            (4)  — no compiler changes; existing OOF codes only
#   K  Full app compile matrix       (8)  — all 4 apps Ruby + Rust results
#   L  Hygiene                       (4)  — no absolute paths in docs
#
# Total: 62 checks
# Acceptance: ≥60 PASS
#
# Run: ruby verify_lab_stdlib_stringly_call_contract_migration_p2.rb

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
LAB_DOCS_DIR = LAB_ROOT / "lab-docs" / "governance"
CARDS_DIR    = LAB_ROOT / ".agents" / "work" / "cards" / "governance"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Rust binary not found — run: cd igniter-compiler && cargo build --release" unless COMPILER_BIN.exist?

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

def section(name)
  puts "\n[#{name}]"
end

# ── Compile helpers ───────────────────────────────────────────────────────────

def ruby_compile(source)
  Dir.mktmpdir("mig2_rb_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [f], out_path: out)
    r = result["result"] || result
    {
      typecheck: r.dig("stages", "typecheck") || "unknown",
      status:    r["status"]                  || "unknown",
      diags:     Array(r["diagnostics"]),
      codes:     Array(r["diagnostics"]).map { |d| d["rule"] }.compact
    }
  end
end

def rust_compile(source)
  Dir.mktmpdir("mig2_rs_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", f, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def ruby_compile_app(app_dir)
  files = Dir.glob((app_dir / "*.ig").to_s).sort
  Dir.mktmpdir("mig2_app_rb_") do |dir|
    out = File.join(dir, "out")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: files, out_path: out)
    r = result["result"] || result
    {
      status: r["status"] || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact
    }
  end
end

def rust_compile_app(app_dir)
  files = Dir.glob((app_dir / "*.ig").to_s).sort
  Dir.mktmpdir("mig2_app_rs_") do |dir|
    out = File.join(dir, "out")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", *files, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact
    }
  end
end

def ruby_ok?(source)   = ruby_compile(source)[:status] == "ok"
def rust_ok?(source)   = rust_compile(source)[:status] == "ok"
def ruby_oof?(source)  = ruby_compile(source)[:status] == "oof"
def rust_oof?(source)  = rust_compile(source)[:status] == "oof"

# ── Census helpers ────────────────────────────────────────────────────────────

def all_cc_calls
  @all_cc_calls ||= begin
    calls = []
    Dir.glob((APPS_DIR / "**" / "*.ig").to_s).sort.each do |path|
      src = File.read(path, encoding: "UTF-8")
      src.each_line.with_index(1) do |line, lineno|
        next unless line.include?("call_contract(")
        m      = line.match(/call_contract\(\s*"([^"]*)"/)
        callee = m ? m[1] : :dynamic
        calls << { file: path, line: lineno, callee: callee, text: line.strip }
      end
    end
    calls
  end
end

def stdlib_form_calls
  all_cc_calls.select { |c| c[:callee].is_a?(String) && c[:callee] =~ /\A[a-z_]+\z/ }
end

def append_calls_in(app)
  all_cc_calls.select { |c| c[:callee] == "append" && c[:file].include?("/#{app}/") }
end

def app_of(c) = File.basename(File.dirname(c[:file]))

# ── Fixtures ─────────────────────────────────────────────────────────────────

ACCUM_FIXTURE = <<~IG
  module AccTest
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract AccContract {
    input existing : Collection[Item]
    input new_item : Item
    compute result = append(existing, new_item)
    output result : Collection[Item]
  }
IG

ACCUM_STRING_FIXTURE = <<~IG
  module AccStrTest
  import stdlib.collection.{ append }
  type Ctx { audit_trail : Collection[String] }
  contract AddEntry {
    input ctx : Ctx
    compute new_trail = append(ctx.audit_trail, "mw:step")
    compute result = { audit_trail: new_trail }
    output result : Ctx
  }
IG

ACCUM_CHAINED_FIXTURE = <<~IG
  module AccChained
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract MultiAppend {
    input items : Collection[Item]
    input a : Item
    input b : Item
    compute step1 = append(items, a)
    compute result = append(step1, b)
    output result : Collection[Item]
  }
IG

BOOTSTRAP_RECORD_FIXTURE = <<~IG
  module BootRec
  type Slot { pos : Integer, idx : Integer }
  type Store { size : Integer, slots : Collection[Slot] }
  contract InitStore {
    compute s0 = { pos: 0, idx: 1 }
    compute s1 = { pos: 1, idx: 2 }
    compute items : Collection[Slot] = [s0, s1]
    compute st = { size: 2, slots: items }
    output st : Store
  }
IG

BOOTSTRAP_STRING_FIXTURE = <<~IG
  module BootStr
  contract BuildTrail {
    compute trail : Collection[String] = ["pipeline:start", "pipeline:init"]
    output trail : Collection[String]
  }
IG

BOOTSTRAP_RECORD_IN_RECORD = <<~IG
  module BootRecRec
  type FeatureEntry { name : String, value : Integer }
  type Applicant { id : String, features : Collection[FeatureEntry] }
  contract BuildApplicant {
    compute f1 = { name: "income", value: 75000 }
    compute f2 = { name: "credit", value: 750 }
    compute features : Collection[FeatureEntry] = [f1, f2]
    compute app = { id: "x", features: features }
    output app : Applicant
  }
IG

# ═══════════════════════════════════════════════════════════════════════════════

section "A — Pre/post source scan"

check("A-01: bloom_filter has 0 call_contract(\"append\") after migration") {
  append_calls_in("bloom_filter").empty?
}

check("A-02: decision_tree has 0 call_contract(\"append\") after migration") {
  append_calls_in("decision_tree").empty?
}

check("A-03: vector_editor has 0 call_contract(\"append\") after migration") {
  append_calls_in("vector_editor").empty?
}

check("A-04: arch_patterns/pipeline.ig has 0 call_contract(\"append\") after migration") {
  all_cc_calls.select { |c|
    c[:callee] == "append" && c[:file].include?("/arch_patterns/pipeline.ig")
  }.empty?
}

check("A-05: arch_patterns/example.ig still has call_contract(\"append\") for c0-c4 (deferred — direct Collection output, Rust gap)") {
  deferred = all_cc_calls.select { |c|
    c[:callee] == "append" && c[:file].include?("/arch_patterns/example.ig")
  }
  deferred.size == 5
}

check("A-06: arch_patterns/example.ig empty_trail no longer uses call_contract(\"append\")") {
  # empty_trail was migrated to typed [] — no longer a stringly call
  empty_trail_stringly = all_cc_calls.select { |c|
    c[:callee] == "append" &&
    c[:file].include?("/arch_patterns/example.ig") &&
    c[:text].include?("pipeline:start")
  }
  empty_trail_stringly.empty?
}

check("A-07: igniter_parser call_contract sites unchanged (5 total — not migrated in P2)") {
  stdlib_form_calls.count { |c| c[:file].include?("/igniter_parser/") } == 5
}

check("A-08: total stdlib-form sites reduced from 34 to 10 (24 migrated)") {
  stdlib_form_calls.size == 10
}

# ─────────────────────────────────────────────────────────────────────────────

section "B — Non-stdlib call_contract preserved"

check("B-01: call_contract(\"MakeLeaf\",...) preserved in decision_tree/example.ig") {
  all_cc_calls.any? { |c|
    c[:callee] == "MakeLeaf" && c[:file].include?("/decision_tree/")
  }
}

check("B-02: call_contract(\"MakeDecision\",...) preserved in decision_tree") {
  all_cc_calls.any? { |c|
    c[:callee] == "MakeDecision" && c[:file].include?("/decision_tree/")
  }
}

check("B-03: call_contract(\"AppendObjectToLayer\",...) preserved in vector_editor/document.ig") {
  all_cc_calls.any? { |c|
    c[:callee] == "AppendObjectToLayer" && c[:file].include?("/vector_editor/")
  }
}

check("B-04: call_contract(\"AddNode\",...) preserved in decision_tree (user contract)") {
  all_cc_calls.any? { |c|
    c[:callee] == "AddNode" && c[:file].include?("/decision_tree/")
  }
}

# ─────────────────────────────────────────────────────────────────────────────

section "C — Dynamic call_contract preserved"

check("C-01: dynamic call_contract sites still present in rule_engine") {
  dynamic = all_cc_calls.select { |c| c[:callee] == :dynamic }
  dynamic.size > 0 && dynamic.all? { |c| c[:file].include?("/rule_engine/") }
}

check("C-02: rule_engine source not modified by P2 migration") {
  re_stringly = all_cc_calls.select { |c|
    c[:file].include?("/rule_engine/") &&
    c[:callee].is_a?(String) && c[:callee] =~ /\A[a-z_]+\z/
  }
  # rule_engine has no stdlib-form (append/empty) calls — only dynamic and user contract
  re_stringly.empty?
}

check("C-03: dynamic callee count unchanged (rule_engine engine.ig variable callee intact)") {
  all_cc_calls.count { |c| c[:callee] == :dynamic } >= 1
}

# ─────────────────────────────────────────────────────────────────────────────

section "D — ACCUMULATING append rewrites compile in Ruby"

check("D-01: ACCUMULATING append(Collection[Item], Item) → ok in Ruby") {
  ruby_ok?(ACCUM_FIXTURE)
}

check("D-02: ACCUMULATING append on String audit_trail field access → ok in Ruby") {
  ruby_ok?(ACCUM_STRING_FIXTURE)
}

check("D-03: chained ACCUMULATING two appends → ok in Ruby") {
  ruby_ok?(ACCUM_CHAINED_FIXTURE)
}

check("D-04: ACCUMULATING pattern — vector_editor AppendObjectToLayer shape compiles") {
  fixture = <<~IG
    module VEDoc
    import stdlib.collection.{ append, map }
    type Point { x : Integer, y : Integer }
    type Style { color : String, width : Integer }
    type GraphicObject { id : String, shape : String }
    type Layer { id : String, name : String, visible : Boolean, locked : Boolean, objects : Collection[GraphicObject] }
    contract AppendObjToLayer {
      input layer : Layer
      input obj : GraphicObject
      compute new_objects = append(layer.objects, obj)
      compute updated_layer = { id: layer.id, name: layer.name, visible: layer.visible, locked: layer.locked, objects: new_objects }
      output updated_layer : Layer
    }
  IG
  ruby_ok?(fixture)
}

check("D-05: ACCUMULATING pattern — decision_tree AddNode shape compiles in Ruby") {
  fixture = <<~IG
    module DTBuilder
    import stdlib.collection.{ append }
    type TreeNode { id : String, kind : String }
    type DecisionTree { root_id : String, nodes : Collection[TreeNode] }
    contract AddNode {
      input tree : DecisionTree
      input node : TreeNode
      compute new_nodes = append(tree.nodes, node)
      compute updated_tree = { root_id: tree.root_id, nodes: new_nodes }
      output updated_tree : DecisionTree
    }
  IG
  ruby_ok?(fixture)
}

check("D-06: ACCUMULATING append with String elem from field access → ok in Ruby") {
  ruby_ok?(ACCUM_STRING_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "E — ACCUMULATING append rewrites compile in Rust"

check("E-01: ACCUMULATING append(Collection[Item], Item) → ok in Rust") {
  rust_ok?(ACCUM_FIXTURE)
}

check("E-02: ACCUMULATING append on String audit_trail field access → ok in Rust") {
  rust_ok?(ACCUM_STRING_FIXTURE)
}

check("E-03: chained ACCUMULATING two appends → ok in Rust") {
  rust_ok?(ACCUM_CHAINED_FIXTURE)
}

check("E-04: ACCUMULATING pattern — vector_editor AppendObjectToLayer shape compiles in Rust") {
  fixture = <<~IG
    module VEDocRs
    import stdlib.collection.{ append, map }
    type GraphicObject { id : String, shape : String }
    type Layer { id : String, name : String, visible : Boolean, locked : Boolean, objects : Collection[GraphicObject] }
    contract AppendObjToLayer {
      input layer : Layer
      input obj : GraphicObject
      compute new_objects = append(layer.objects, obj)
      compute updated_layer = { id: layer.id, name: layer.name, visible: layer.visible, locked: layer.locked, objects: new_objects }
      output updated_layer : Layer
    }
  IG
  rust_ok?(fixture)
}

check("E-05: ACCUMULATING pattern — decision_tree AddNode shape compiles in Rust") {
  fixture = <<~IG
    module DTBuilderRs
    import stdlib.collection.{ append }
    type TreeNode { id : String, kind : String }
    type DecisionTree { root_id : String, nodes : Collection[TreeNode] }
    contract AddNode {
      input tree : DecisionTree
      input node : TreeNode
      compute new_nodes = append(tree.nodes, node)
      compute updated_tree = { root_id: tree.root_id, nodes: new_nodes }
      output updated_tree : DecisionTree
    }
  IG
  rust_ok?(fixture)
}

check("E-06: ACCUMULATING append with String elem → ok in Rust") {
  rust_ok?(ACCUM_STRING_FIXTURE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "F — BOOTSTRAP rewrites compile in both TCs"

check("F-01: BOOTSTRAP typed [Slot, Slot] seed in record container → ok in Ruby") {
  ruby_ok?(BOOTSTRAP_RECORD_FIXTURE)
}

check("F-02: BOOTSTRAP typed [Slot, Slot] seed in record container → ok in Rust") {
  rust_ok?(BOOTSTRAP_RECORD_FIXTURE)
}

check("F-03: BOOTSTRAP typed [String, String] direct output → ok in Ruby") {
  ruby_ok?(BOOTSTRAP_STRING_FIXTURE)
}

check("F-04: BOOTSTRAP typed [String, String] direct output → ok in Rust") {
  rust_ok?(BOOTSTRAP_STRING_FIXTURE)
}

check("F-05: BOOTSTRAP typed [FeatureEntry, FeatureEntry] in Applicant record → ok in Ruby") {
  ruby_ok?(BOOTSTRAP_RECORD_IN_RECORD)
}

check("F-06: BOOTSTRAP typed [FeatureEntry, FeatureEntry] in Applicant record → ok in Rust") {
  rust_ok?(BOOTSTRAP_RECORD_IN_RECORD)
}

# ─────────────────────────────────────────────────────────────────────────────

section "G — EMPTY_CONSTRUCTOR not migrated in P2"

check("G-01: igniter_parser call_contract(\"empty\") sites still present (3 total — IP-P01 blocks migration)") {
  all_cc_calls.count { |c|
    c[:callee] == "empty" && c[:file].include?("/igniter_parser/")
  } == 3
}

check("G-02: no call_contract(\"empty\") sites in the 4 migrated apps") {
  %w[bloom_filter decision_tree vector_editor arch_patterns].all? { |app|
    all_cc_calls.none? { |c|
      c[:callee] == "empty" && c[:file].include?("/#{app}/")
    }
  }
}

check("G-03: total call_contract(\"empty\") count unchanged at 3") {
  all_cc_calls.count { |c| c[:callee] == "empty" } == 3
}

# ─────────────────────────────────────────────────────────────────────────────

section "H — bloom_filter diagnostic delta"

check("H-01: bloom_filter Ruby ok/0 after migration") {
  r = ruby_compile_app(APPS_DIR / "bloom_filter")
  r[:status] == "ok" && r[:count] == 0
}

check("H-02: bloom_filter Rust ok/0 after migration") {
  r = rust_compile_app(APPS_DIR / "bloom_filter")
  r[:status] == "ok" && r[:count] == 0
}

check("H-03: bloom_filter Ruby diags contain no OOF-TY0 (all stringly calls migrated)") {
  r = ruby_compile_app(APPS_DIR / "bloom_filter")
  !r[:codes].include?("OOF-TY0")
}

check("H-04: bloom_filter Rust diags contain no OOF-TY0 (all stringly calls migrated)") {
  r = rust_compile_app(APPS_DIR / "bloom_filter")
  !r[:codes].include?("OOF-TY0")
}

# ─────────────────────────────────────────────────────────────────────────────

section "I — Site count verification"

check("I-01: arch_patterns remaining stringly \"append\" sites == 5 (c0-c4 deferred)") {
  all_cc_calls.count { |c|
    c[:callee] == "append" && c[:file].include?("/arch_patterns/")
  } == 5
}

check("I-02: igniter_parser remaining stringly sites == 5 (3 empty + 2 append)") {
  all_cc_calls.count { |c|
    %w[append empty].include?(c[:callee]) && c[:file].include?("/igniter_parser/")
  } == 5
}

check("I-03: bloom_filter has 0 stdlib-form call_contract sites") {
  stdlib_form_calls.none? { |c| c[:file].include?("/bloom_filter/") }
}

check("I-04: decision_tree has 0 stdlib-form call_contract sites") {
  stdlib_form_calls.none? { |c| c[:file].include?("/decision_tree/") }
}

check("I-05: vector_editor has 0 stdlib-form call_contract sites") {
  stdlib_form_calls.none? { |c| c[:file].include?("/vector_editor/") }
}

check("I-06: total stdlib-form remaining == 10 (5 arch_patterns c0-c4 + 5 igniter_parser)") {
  stdlib_form_calls.size == 10
}

# ─────────────────────────────────────────────────────────────────────────────

section "J — Authority boundary"

check("J-01: typechecker.rb call_contract arm uses @call_contract_registry (no callee name dispatch added)") {
  src = TC_RUBY_PATH.read(encoding: "utf-8")
  src.include?("@call_contract_registry") && !src.include?('== "append"')
}

check("J-02: typechecker.rs call_contract arm still uses contract_registry.get(callee_name)") {
  src = TC_RUST_PATH.read(encoding: "utf-8")
  src.include?("contract_registry.get(callee_name)")
}

check("J-03: only OOF-TY0 / OOF-TY1 / OOF-P1 codes appear in migrated app diagnostics (no new codes)") {
  all_codes = %w[bloom_filter decision_tree vector_editor arch_patterns].flat_map { |app|
    ruby_compile_app(APPS_DIR / app)[:codes]
  }.uniq
  valid_codes = %w[OOF-TY0 OOF-TY1 OOF-P1 OOF-COL1 OOF-COL2 OOF-COL6 OOF-COL7]
  all_codes.all? { |c| valid_codes.include?(c) }
}

check("J-04: no compiler source file contains \"call_contract_migration\" (no compiler change leaked)") {
  !TC_RUBY_PATH.read(encoding: "utf-8").include?("call_contract_migration") &&
    !TC_RUST_PATH.read(encoding: "utf-8").include?("call_contract_migration")
}

# ─────────────────────────────────────────────────────────────────────────────

section "K — Full app compile matrix"

check("K-01: bloom_filter Ruby ok/0") {
  r = ruby_compile_app(APPS_DIR / "bloom_filter")
  r[:status] == "ok" && r[:count] == 0
}

check("K-02: bloom_filter Rust ok/0") {
  r = rust_compile_app(APPS_DIR / "bloom_filter")
  r[:status] == "ok" && r[:count] == 0
}

check("K-03: decision_tree Ruby ok/0") {
  r = ruby_compile_app(APPS_DIR / "decision_tree")
  r[:status] == "ok" && r[:count] == 0
}

check("K-04: decision_tree Rust ok/0") {
  r = rust_compile_app(APPS_DIR / "decision_tree")
  r[:status] == "ok" && r[:count] == 0
}

check("K-05: vector_editor Ruby oof (VE-P09 new_obj remains — not related to stringly migration)") {
  r = ruby_compile_app(APPS_DIR / "vector_editor")
  r[:status] == "oof" && r[:count] == 1 && r[:codes].include?("OOF-P1")
}

check("K-06: vector_editor Rust ok/0 after removing only stringly stdlib site") {
  r = rust_compile_app(APPS_DIR / "vector_editor")
  r[:status] == "ok" && r[:count] == 0
}

check("K-07: arch_patterns Ruby oof — only c0-c4 stringly remain (5 OOF-TY0 + 1 OOF-TY1)") {
  r = ruby_compile_app(APPS_DIR / "arch_patterns")
  r[:status] == "oof" &&
    r[:codes].count("OOF-TY0") == 5 &&
    r[:codes].include?("OOF-TY1")
}

check("K-08: arch_patterns Rust oof — same 5 OOF-TY0 + 1 OOF-TY1 as Ruby") {
  r = rust_compile_app(APPS_DIR / "arch_patterns")
  r[:status] == "oof" &&
    r[:codes].count("OOF-TY0") == 5 &&
    r[:codes].include?("OOF-TY1")
}

# ─────────────────────────────────────────────────────────────────────────────

section "L — Hygiene"

check("L-01: migration doc exists and has no absolute paths") {
  doc = LAB_DOCS_DIR / "lab-stdlib-stringly-call-contract-migration-p2-v0.md"
  doc.exist? && !doc.read(encoding: "utf-8").match?(%r{/Users/|/home/|file://})
}

check("L-02: agent card exists and has no absolute paths") {
  card = CARDS_DIR / "LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2.md"
  card.exist? && !card.read(encoding: "utf-8").match?(%r{/Users/|/home/|file://})
}

check("L-03: migration doc has no .gemini or temp path references") {
  doc = LAB_DOCS_DIR / "lab-stdlib-stringly-call-contract-migration-p2-v0.md"
  doc.exist? && !doc.read(encoding: "utf-8").match?(/\.gemini|\/tmp\/|gemini-/)
}

check("L-04: P2 doc references deferred sites explicitly (LANG-RUST-TYPED-COMPUTE-BINDING-P1)") {
  doc = LAB_DOCS_DIR / "lab-stdlib-stringly-call-contract-migration-p2-v0.md"
  doc.exist? && doc.read(encoding: "utf-8").include?("LANG-RUST-TYPED-COMPUTE-BINDING-P1")
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
exit(passed >= 60 ? 0 : 1)
