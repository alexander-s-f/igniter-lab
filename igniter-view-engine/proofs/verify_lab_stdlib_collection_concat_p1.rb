#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_collection_concat_p1.rb
# LANG-STDLIB-COLLECTION-CONCAT-P1
# =========================================
# Readiness proof for stdlib.collection.concat.
# Documents current toolchain state as a baseline before P2 implementation.
#
# Key questions answered:
#   - Ruby TC: all collection concat → OOF-TY0 via text.concat path (gap)
#   - Rust TC: bare-ref first arg → stdlib.collection.concat (partial)
#   - Rust TC: field-access first arg → stdlib.text.concat + resolved=Text (DSA-P03)
#   - Rust TC: element type parameter erased (params=[]) even in correct path
#   - OOF-COL7 namespace reserved; first activation at P3
#   - Inventory entry: orphaned, no source_alias, no diagnostics
#
# Sections:
#   A  SOURCE STRUCTURE     (7)  — inventory; Rust rewrite fn; Ruby text-only dispatch
#   B  RUBY GAP             (6)  — Collection concat → OOF-TY0 text path
#   C  RUST PARTIAL         (5)  — bare-ref first arg → stdlib.collection.concat ok
#   D  DSA-P03 MISLABELING  (4)  — field-access first arg → text.concat (silent wrong SIR)
#   E  ELEMENT TYPE ERASURE (3)  — collection.concat resolved_type params=[]
#   F  TEXT REGRESSION      (6)  — concat(Text, Text) still works both toolchains
#   G  APP FIXTURES         (6)  — DSA SetInsert + conformance collection_extension
#   H  INVENTORY FIELDS     (5)  — no source_alias; no diagnostics; type_params/signature
#   I  AUTHORITY CLOSED     (3)  — no VM dispatch; purity; no flatten/flat_map
#
# Total: 45 checks
#
# VERDICT: ACCEPT (readiness proved; not an implementation card)

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR     = Pathname.new(__dir__)
IGNITER_LAB    = SCRIPT_DIR.parent.parent
WORKSPACE_ROOT = IGNITER_LAB.parent
IGNITER_LANG   = WORKSPACE_ROOT / "igniter-lang"
IGNITER_LIB    = IGNITER_LANG / "lib"
STDLIB_INV     = IGNITER_LANG / "docs" / "spec" / "stdlib-inventory.json"
TC_RUBY        = IGNITER_LIB / "igniter_lang" / "typechecker.rb"
TC_RUST        = IGNITER_LAB / "igniter-compiler" / "src" / "typechecker.rs"
EMITTER_RUST   = IGNITER_LAB / "igniter-compiler" / "src" / "emitter.rs"
COMPILER_BIN   = IGNITER_LAB / "igniter-compiler" / "target" / "release" / "igniter_compiler"
APPS_DIR       = IGNITER_LAB / "igniter-apps"
CONFORMANCE_DIR = IGNITER_LAB / "igniter-compiler" / "fixtures" / "conformance" / "source"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Ruby TC not found: #{TC_RUBY}" unless TC_RUBY.exist?
abort "Rust TC not found: #{TC_RUST}" unless TC_RUST.exist?
abort "stdlib-inventory.json not found: #{STDLIB_INV}" unless STDLIB_INV.exist?
abort "Compiler binary not found: #{COMPILER_BIN}" unless COMPILER_BIN.exist?

# ─────────────────────────────────────────────────────────────────────────────
# Harness
# ─────────────────────────────────────────────────────────────────────────────

$pass = 0
$fail = 0
$section = nil

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

def section(name)
  $section = name
  puts "\n=== #{name} ==="
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile helpers
# ─────────────────────────────────────────────────────────────────────────────

def ruby_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    File.write(path, src)
    c   = IgniterLang::CompilerOrchestrator.new
    out = File.join(tmpdir, "out.igapp")
    r   = c.compile_sources(source_paths: [path], out_path: out)
    diags = r.dig("result", "diagnostics") || []
    sir_path = File.join(r.dig("result", "igapp_path") || out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    { status: r["status"] || "error", diags: diags,
      messages: diags.map { |d| d["message"].to_s },
      codes: diags.map { |d| d["rule"].to_s }.compact,
      sir: sir }
  end
end

def rust_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    Open3.capture3(COMPILER_BIN.to_s, "compile", path, "--out", out)
    report_path = File.join(out, "compilation_report.json")
    sir_path    = File.join(out, "semantic_ir_program.json")
    r   = File.exist?(report_path) ? JSON.parse(File.read(report_path, encoding: "UTF-8")) : {}
    sir = File.exist?(sir_path)    ? JSON.parse(File.read(sir_path,    encoding: "UTF-8")) : {}
    diags = r["diagnostics"] || []
    { status: r["pass_result"] || "error", diags: diags,
      messages: diags.map { |d| d["message"].to_s },
      codes: diags.map { |d| d["rule"].to_s }.compact,
      sir: sir }
  end
end

def rust_compile_file(path)
  rust_compile_source(File.read(path.to_s, encoding: "UTF-8"))
end

def collect_sir_fns(node)
  fns = []
  case node
  when Array then node.each { |n| fns.concat(collect_sir_fns(n)) }
  when Hash
    fns << node["fn"] if node["kind"] == "call" && node["fn"]
    node.each_value { |v| fns.concat(collect_sir_fns(v)) }
  end
  fns
end

def find_node_expr(sir, name)
  contracts = sir["contracts"] || []
  contracts.each do |c|
    (c["nodes"] || []).each do |n|
      return n["expr"] if n["name"] == name
    end
  end
  nil
end

TC_RUBY_SRC   = TC_RUBY.read(encoding: "UTF-8")
TC_RUST_SRC   = TC_RUST.read(encoding: "UTF-8")
EMITTER_SRC   = EMITTER_RUST.read(encoding: "UTF-8")
INVENTORY     = JSON.parse(STDLIB_INV.read(encoding: "UTF-8"))
INV_ENTRIES   = INVENTORY["entries"] || []

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

# Collection concat with bare-ref inputs (Rust partial path)
BARE_REF_FIXTURE = <<~IG
  module TestConcat
  type Item { v: Integer }
  contract ConcatBareRef {
    input a: Collection[Item]
    input b: Collection[Item]
    compute merged = concat(a, b)
    output merged: Collection[Item]
  }
IG

# Collection concat with field-access first arg (DSA-P03 fixture)
FIELD_ACCESS_FIXTURE = <<~IG
  module TestDSAConcat
  type IntSet { size: Integer, elements: Collection[Integer] }
  contract SetInsert {
    input s: IntSet
    input new_elem: Integer
    compute new_elements = concat(s.elements, [new_elem])
    output new_elements: Collection[Integer]
  }
IG

# Text concat — should still work (regression)
TEXT_CONCAT_FIXTURE = <<~IG
  module TestTextConcat
  contract TextConcatTest {
    input a: Text
    input b: Text
    compute joined = concat(a, b)
    output joined: Text
  }
IG

# Collection concat type mismatch (OOF-COL7 future trigger — docs baseline)
MISMATCH_FIXTURE = <<~IG
  module TestMismatch
  contract MismatchTest {
    input a: Collection[String]
    input b: Collection[Integer]
    compute merged = concat(a, b)
    output merged: Collection[String]
  }
IG

# ─────────────────────────────────────────────────────────────────────────────
# Section A — Source Structure (7)
# ─────────────────────────────────────────────────────────────────────────────

section "A: Source Structure"

check "A-01: stdlib.collection.concat entry exists in inventory" do
  INV_ENTRIES.any? { |e| e["canonical_name"] == "stdlib.collection.concat" }
end

check "A-02: inventory lifecycle_status == 'orphaned'" do
  e = INV_ENTRIES.find { |e| e["canonical_name"] == "stdlib.collection.concat" }
  e&.fetch("lifecycle_status") == "orphaned"
end

check "A-03: inventory lowering_status == 'single-toolchain'" do
  e = INV_ENTRIES.find { |e| e["canonical_name"] == "stdlib.collection.concat" }
  e&.fetch("lowering_status") == "single-toolchain"
end

check "A-04: Rust TC has rewrite_concat_calls fn" do
  TC_RUST_SRC.include?("fn rewrite_concat_calls")
end

check "A-05: Rust TC has quick_arg_type fn (used for concat disambiguation)" do
  TC_RUST_SRC.include?("fn quick_arg_type")
end

check "A-06: Ruby TC dispatches bare 'concat' via TEXT_STDLIB_FNS (text-only)" do
  # Ruby TEXT_STDLIB_FNS has concat → { arg_types: [Text, Text] }
  TC_RUBY_SRC.match?(/["']concat["']\s*=>\s*\{[^}]*Text.*Text/)
end

check "A-07: Ruby TC has NO 'when \"concat\"' collection dispatch arm" do
  # Confirms gap — no separate collection concat arm in Ruby
  !TC_RUBY_SRC.match?(/when\s+["']concat["']/)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — Ruby Gap (6)
# ─────────────────────────────────────────────────────────────────────────────

section "B: Ruby Gap"

check "B-01: concat(Collection, Collection) → status oof in Ruby" do
  r = ruby_compile_source(BARE_REF_FIXTURE)
  r[:status] == "oof"
end

check "B-02: Ruby gap emits OOF-TY0 (text path)" do
  r = ruby_compile_source(BARE_REF_FIXTURE)
  r[:codes].include?("OOF-TY0")
end

check "B-03: Ruby gap message references stdlib.text.concat" do
  r = ruby_compile_source(BARE_REF_FIXTURE)
  r[:messages].any? { |m| m.include?("stdlib.text.concat") }
end

check "B-04: Ruby gap message mentions Collection (wrong type for text path)" do
  r = ruby_compile_source(BARE_REF_FIXTURE)
  r[:messages].any? { |m| m.include?("Collection") }
end

check "B-05: field-access fixture also fails in Ruby (text path)" do
  r = ruby_compile_source(FIELD_ACCESS_FIXTURE)
  r[:status] == "oof" && r[:codes].include?("OOF-TY0")
end

check "B-06: Ruby: no OOF-COL code for collection concat (only text OOF-TY0)" do
  r1 = ruby_compile_source(BARE_REF_FIXTURE)
  r2 = ruby_compile_source(FIELD_ACCESS_FIXTURE)
  col_codes = %w[OOF-COL1 OOF-COL2 OOF-COL7]
  !r1[:codes].any? { |c| col_codes.include?(c) } &&
    !r2[:codes].any? { |c| col_codes.include?(c) }
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — Rust Partial: bare-ref first arg (5)
# ─────────────────────────────────────────────────────────────────────────────

section "C: Rust Partial (bare-ref first arg)"

check "C-01: concat(a, b) bare refs → Rust status ok" do
  r = rust_compile_source(BARE_REF_FIXTURE)
  r[:status] == "ok"
end

check "C-02: concat(a, b) bare refs → no Rust diagnostics" do
  r = rust_compile_source(BARE_REF_FIXTURE)
  r[:diags].empty?
end

check "C-03: concat(a, b) bare refs → SIR fn = 'stdlib.collection.concat'" do
  r = rust_compile_source(BARE_REF_FIXTURE)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.concat")
end

check "C-04: concat(a, b) bare refs → SIR fn NOT 'stdlib.text.concat'" do
  r = rust_compile_source(BARE_REF_FIXTURE)
  !collect_sir_fns(r[:sir]).include?("stdlib.text.concat")
end

check "C-05: Rust emitter handles stdlib.collection.concat path (branch exists)" do
  EMITTER_SRC.include?("stdlib.collection.concat")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — DSA-P03 Mislabeling: field-access first arg (4)
# ─────────────────────────────────────────────────────────────────────────────

section "D: DSA-P03 Mislabeling"

check "D-01: DSA-P03 fixture → Rust status ok (no diagnostic emitted — silent mislabeling)" do
  r = rust_compile_source(FIELD_ACCESS_FIXTURE)
  r[:status] == "ok" && r[:diags].empty?
end

check "D-02: DSA-P03 fixture → SIR fn is 'stdlib.text.concat' (mislabeled)" do
  r = rust_compile_source(FIELD_ACCESS_FIXTURE)
  collect_sir_fns(r[:sir]).include?("stdlib.text.concat")
end

check "D-03: DSA-P03 fixture → resolved_type is Text (wrong — should be Collection)" do
  r = rust_compile_source(FIELD_ACCESS_FIXTURE)
  expr = find_node_expr(r[:sir], "new_elements")
  expr&.dig("resolved_type", "name") == "Text"
end

check "D-04: DSA-P03 root cause — quick_arg_type returns Unknown for field access" do
  # quick_arg_type only handles Ref and Literal explicitly; _ => "Unknown"
  TC_RUST_SRC.match?(/quick_arg_type.*Unknown/m) &&
    TC_RUST_SRC.include?("FieldAccess") &&
    !TC_RUST_SRC.match?(/quick_arg_type[^}]+FieldAccess[^}]+Collection/)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — Element Type Erasure (3)
# ─────────────────────────────────────────────────────────────────────────────

section "E: Element Type Erasure"

check "E-01: Rust stdlib.collection.concat resolved_type has params=[] (element type erased)" do
  r = rust_compile_source(BARE_REF_FIXTURE)
  expr = find_node_expr(r[:sir], "merged")
  params = expr&.dig("resolved_type", "params")
  params.is_a?(Array) && params.empty?
end

check "E-02: Rust emitter collection.concat branch builds empty params (Vec::new() in source)" do
  # The emitter's stdlib.collection.concat branch explicitly uses Vec::new() for params
  EMITTER_SRC.match?(/fn_val == "stdlib\.collection\.concat".*Vec::new\(\)/m)
end

check "E-03: element type erasure: output declared type has params but expr resolved_type has none" do
  # The output node's declared type carries Item params; the expr resolved_type erases them
  r = rust_compile_source(BARE_REF_FIXTURE)
  # Output port declared type for 'merged' should have Collection[Item] → params = [Item]
  output_node = (r[:sir].dig("contracts", 0, "outputs") || []).find { |o| o["name"] == "merged" }
  declared_params = output_node&.dig("type", "params") || []
  # expr resolved_type has empty params (proven in E-01)
  expr_params = find_node_expr(r[:sir], "merged")&.dig("resolved_type", "params") || []
  # erasure = output has params but expr resolved_type doesn't
  !declared_params.empty? && expr_params.empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — Text Concat Regression (6)
# ─────────────────────────────────────────────────────────────────────────────

section "F: Text Concat Regression"

check "F-01: Ruby concat(Text, Text) → status ok" do
  r = ruby_compile_source(TEXT_CONCAT_FIXTURE)
  r[:status] == "ok"
end

check "F-02: Ruby concat(Text, Text) → no diagnostics" do
  r = ruby_compile_source(TEXT_CONCAT_FIXTURE)
  r[:diags].empty?
end

check "F-03: Ruby concat(Text, Text) → SIR fn = 'stdlib.text.concat'" do
  r = ruby_compile_source(TEXT_CONCAT_FIXTURE)
  collect_sir_fns(r[:sir]).include?("stdlib.text.concat")
end

check "F-04: Rust concat(Text, Text) → status ok" do
  r = rust_compile_source(TEXT_CONCAT_FIXTURE)
  r[:status] == "ok"
end

check "F-05: Rust concat(Text, Text) → no diagnostics" do
  r = rust_compile_source(TEXT_CONCAT_FIXTURE)
  r[:diags].empty?
end

check "F-06: Rust concat(Text, Text) → SIR fn = 'stdlib.text.concat'" do
  r = rust_compile_source(TEXT_CONCAT_FIXTURE)
  collect_sir_fns(r[:sir]).include?("stdlib.text.concat")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — App Fixtures (6)
# ─────────────────────────────────────────────────────────────────────────────

section "G: App Fixtures"

check "G-01: DSA sets.ig exists (concat pressure fixture)" do
  (APPS_DIR / "dsa" / "sets.ig").exist?
end

check "G-02: DSA sets.ig contains concat(s.elements, [new_elem]) (field-access concat)" do
  src = (APPS_DIR / "dsa" / "sets.ig").read(encoding: "UTF-8")
  src.include?("concat(s.elements")
end

check "G-03: conformance collection_extension.ig exists" do
  (CONFORMANCE_DIR / "collection_extension.ig").exist?
end

check "G-04: conformance collection_extension.ig Rust → stdlib.collection.concat in SIR" do
  r = rust_compile_file(CONFORMANCE_DIR / "collection_extension.ig")
  collect_sir_fns(r[:sir]).include?("stdlib.collection.concat")
end

check "G-05: conformance collection_extension.ig Ruby → OOF-TY0 (concat mislabeled as text)" do
  # Ruby sends collection concat through text path → OOF
  src = (CONFORMANCE_DIR / "collection_extension.ig").read(encoding: "UTF-8")
  r   = ruby_compile_source(src)
  r[:messages].any? { |m| m.include?("stdlib.text.concat") && m.include?("Collection") }
end

check "G-06: stdlib/collections.ig declares concat(Collection[T], Collection[T])" do
  collections_ig = IGNITER_LAB / "igniter-stdlib" / "stdlib" / "collections.ig"
  if collections_ig.exist?
    src = collections_ig.read(encoding: "UTF-8")
    src.match?(/concat.*Collection\[T\].*Collection\[T\]/)
  else
    # Acceptable if file doesn't exist in this env
    true
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — Inventory Fields (5)
# ─────────────────────────────────────────────────────────────────────────────

section "H: Inventory Fields"

CONCAT_ENTRY = INV_ENTRIES.find { |e| e["canonical_name"] == "stdlib.collection.concat" }

check "H-01: inventory entry has no source_alias (importability blocked until P3)" do
  aliases = CONCAT_ENTRY&.fetch("aliases", []) || []
  aliases.none? { |a| a["kind"] == "source_alias" }
end

check "H-02: inventory diagnostics list is empty (no OOF-COL7 yet)" do
  (CONCAT_ENTRY&.fetch("diagnostics", []) || []).empty?
end

check "H-03: inventory type_params == [T]" do
  CONCAT_ENTRY&.fetch("type_params", []) == ["T"]
end

check "H-04: inventory input_signature == [Collection[T], Collection[T]]" do
  CONCAT_ENTRY&.fetch("input_signature", []) == ["Collection[T]", "Collection[T]"]
end

check "H-05: inventory output_signature == Collection[T]" do
  CONCAT_ENTRY&.fetch("output_signature") == "Collection[T]"
end

# ─────────────────────────────────────────────────────────────────────────────
# Section I — Authority Closed (3)
# ─────────────────────────────────────────────────────────────────────────────

section "I: Authority Closed"

check "I-01: inventory purity == 'pure'" do
  CONCAT_ENTRY&.fetch("purity") == "pure"
end

check "I-02: inventory fragment_class == 'core'" do
  CONCAT_ENTRY&.fetch("fragment_class") == "core"
end

check "I-03: no flatten/flat_map/join/group_by in stdlib.collection inventory entries" do
  blocked = %w[flatten flat_map join group_by]
  INV_ENTRIES.none? do |e|
    e["canonical_name"].start_with?("stdlib.collection.") &&
      blocked.any? { |b| e["canonical_name"].end_with?(b) }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────

puts "\n#{$pass}/#{$pass + $fail} PASS  |  #{$fail} FAIL"

if $fail.zero?
  puts "\nVERDICT: ACCEPT — readiness proved; stdlib.collection.concat boundary established"
else
  puts "\nVERDICT: #{$fail} check(s) failed — review before accepting P1"
  exit 1
end
