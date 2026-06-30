#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_stdlib_collection_concat_p4.rb
# LANG-STDLIB-COLLECTION-CONCAT-PROP-P4 — Rust parity proof for stdlib.collection.concat
# ========================================================================================
# Proves Rust TC parity with Ruby P3 for stdlib.collection.concat.
# Covers OOF-COL1/COL2/COL7, Unknown permissive, DSA-P03 fix, element type
# preservation in SIR, text concat unaffected, and inventory promotion.
#
# Sections:
#   A  Happy path             (5)  — concat(Col[T], Col[T]) → Col[T], SIR correct
#   B  OOF-COL1               (3)  — arity != 2
#   C  OOF-COL2               (3)  — second arg not Collection
#   D  OOF-COL7               (3)  — element type mismatch
#   E  Unknown permissive     (4)  — Unknown first arg routes to collection, not text
#   F  DSA-P03 fix            (4)  — field-access first arg routes to collection
#   G  Element type in SIR    (4)  — Collection[T] params preserved in output SIR
#   H  Text concat unaffected (4)  — text path still works, no regression
#   I  Inventory              (2)  — lowering_status = dual-toolchain
#
# Total: 32 checks

require "open3"
require "json"
require "tmpdir"
require "pathname"

SCRIPT_DIR     = Pathname.new(__FILE__).realpath.dirname.parent.parent
LAB_ROOT       = SCRIPT_DIR.parent
LANG_ROOT      = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN   = SCRIPT_DIR / "target" / "release" / "igniter_compiler"
INVENTORY      = LANG_ROOT / "docs" / "spec" / "stdlib-inventory.json"

$LOAD_PATH.unshift((LANG_ROOT / "lib").to_s)
require "igniter_lang"

abort "Rust binary not found — run cargo build --release" unless COMPILER_BIN.exist?

INV = JSON.parse(INVENTORY.read(encoding: "utf-8"))

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

CHECKS = []

def check(label)
  pass = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  CHECKS << { label: label, pass: pass, detail: detail }
  puts "#{pass ? "PASS" : "FAIL"} #{label}"
  puts "     #{detail}" if detail && !pass
end

def section(name)
  puts "\n[#{name}]"
end

# ---------------------------------------------------------------------------
# Compile helpers
# ---------------------------------------------------------------------------

def rust_compile(source)
  Dir.mktmpdir("col_concat_rs_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", f, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    sir_path = File.join(out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "utf-8")) : {}
    {
      status: r["status"] || "unknown",
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"]),
      sir:    sir
    }
  end
end

def ruby_compile(source)
  Dir.mktmpdir("col_concat_rb_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [f], out_path: out)
    r = result["result"] || result
    {
      typecheck: r.dig("stages", "typecheck") || "unknown",
      codes:     Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:     Array(r["diagnostics"])
    }
  end
end

# Walk the SIR tree and return all "fn" values for call nodes
def collect_fn_names(node)
  return [] unless node.is_a?(Hash) || node.is_a?(Array)
  if node.is_a?(Array)
    return node.flat_map { |v| collect_fn_names(v) }
  end
  results = []
  results << node["fn"] if node["kind"] == "call" && node["fn"]
  node.each_value { |v| results.concat(collect_fn_names(v)) }
  results
end

# Return resolved_type of the first call node matching fn_name
def resolved_type_for(sir, fn_name)
  find_node = lambda do |node|
    return nil unless node.is_a?(Hash) || node.is_a?(Array)
    if node.is_a?(Array)
      node.each { |v| r = find_node.call(v); return r if r }
      return nil
    end
    return node["resolved_type"] if node["kind"] == "call" && node["fn"] == fn_name
    node.each_value { |v| r = find_node.call(v); return r if r }
    nil
  end
  find_node.call(sir)
end

# ---------------------------------------------------------------------------
# Section A — Happy path
# ---------------------------------------------------------------------------

section("A-HAPPY-PATH")

a1 = rust_compile(<<~IG)
  module ColConcat.A1
  pure contract TestA1 {
    input xs : Collection[Integer]
    input ys : Collection[Integer]
    compute out = concat(xs, ys)
    output out : Collection[Integer]
  }
IG

a2 = rust_compile(<<~IG)
  module ColConcat.A2
  pure contract TestA2 {
    input xs : Collection[Text]
    input ys : Collection[Text]
    compute out = concat(xs, ys)
    output out : Collection[Text]
  }
IG

a3 = rust_compile(<<~IG)
  module ColConcat.A3
  pure contract TestA3 {
    input xs : Collection[Integer]
    input ys : Collection[Integer]
    compute out = concat(xs, ys)
    output out : Collection[Integer]
  }
IG

check("A-01 Rust: concat(Col[Int], Col[Int]) → status=ok") { a1[:status] == "ok" }
check("A-02 Rust: concat(Col[Text], Col[Text]) → status=ok") { a2[:status] == "ok" }
check("A-03 Rust: SIR fn name = stdlib.collection.concat") {
  collect_fn_names(a1[:sir]).include?("stdlib.collection.concat")
}
check("A-04 Rust: no OOF codes on happy path") { a1[:codes].empty? }
check("A-05 Ruby: concat(Col[Int], Col[Int]) → typecheck=ok") {
  ruby_compile(<<~IG)[:typecheck] == "ok"
    module ColConcat.A5
    pure contract TestA5 {
      input xs : Collection[Integer]
      input ys : Collection[Integer]
      compute out = concat(xs, ys)
      output out : Collection[Integer]
    }
  IG
}

# ---------------------------------------------------------------------------
# Section B — OOF-COL1 (arity)
# ---------------------------------------------------------------------------

section("B-OOF-COL1-ARITY")

b1 = rust_compile(<<~IG)
  module ColConcat.B1
  pure contract TestB1 {
    input xs : Collection[Integer]
    compute out = concat(xs)
    output out : Collection[Integer]
  }
IG

b2 = rust_compile(<<~IG)
  module ColConcat.B2
  pure contract TestB2 {
    input xs : Collection[Integer]
    input ys : Collection[Integer]
    input zs : Collection[Integer]
    compute out = concat(xs, ys, zs)
    output out : Collection[Integer]
  }
IG

b3 = rust_compile(<<~IG)
  module ColConcat.B3
  pure contract TestB3 {
    compute out = concat()
    output out : Collection[Integer]
  }
IG

check("B-01 Rust: concat(xs) (1 arg) → OOF-COL1") { b1[:codes].include?("OOF-COL1") }
check("B-02 Rust: concat(xs,ys,zs) (3 args) → OOF-COL1") { b2[:codes].include?("OOF-COL1") }
check("B-03 Rust: concat() (0 args) → OOF-COL1") { b3[:codes].include?("OOF-COL1") }

# ---------------------------------------------------------------------------
# Section C — OOF-COL2 (second arg not Collection)
# ---------------------------------------------------------------------------

section("C-OOF-COL2-SECOND-ARG")

c1 = rust_compile(<<~IG)
  module ColConcat.C1
  pure contract TestC1 {
    input xs : Collection[Integer]
    input t  : Text
    compute out = concat(xs, t)
    output out : Collection[Integer]
  }
IG

c2 = rust_compile(<<~IG)
  module ColConcat.C2
  pure contract TestC2 {
    input xs : Collection[Integer]
    input n  : Integer
    compute out = concat(xs, n)
    output out : Collection[Integer]
  }
IG

c3_rb = ruby_compile(<<~IG)
  module ColConcat.C3
  pure contract TestC3 {
    input xs : Collection[Integer]
    input t  : Text
    compute out = concat(xs, t)
    output out : Collection[Integer]
  }
IG

check("C-01 Rust: concat(Col[Int], Text) → OOF-COL2") { c1[:codes].include?("OOF-COL2") }
check("C-02 Rust: concat(Col[Int], Integer) → OOF-COL2") { c2[:codes].include?("OOF-COL2") }
check("C-03 Ruby: concat(Col[Int], Text) → OOF-COL2 (parity check)") { c3_rb[:codes].include?("OOF-COL2") }

# ---------------------------------------------------------------------------
# Section D — OOF-COL7 (element type mismatch)
# ---------------------------------------------------------------------------

section("D-OOF-COL7-ELEM-MISMATCH")

d1 = rust_compile(<<~IG)
  module ColConcat.D1
  pure contract TestD1 {
    input xs : Collection[Integer]
    input ys : Collection[Text]
    compute out = concat(xs, ys)
    output out : Collection[Integer]
  }
IG

d2_rb = ruby_compile(<<~IG)
  module ColConcat.D2
  pure contract TestD2 {
    input xs : Collection[Integer]
    input ys : Collection[Text]
    compute out = concat(xs, ys)
    output out : Collection[Integer]
  }
IG

d3 = rust_compile(<<~IG)
  module ColConcat.D3
  pure contract TestD3 {
    input xs : Collection[Integer]
    input ys : Collection[Text]
    compute out = concat(xs, ys)
    output out : Collection[Integer]
  }
IG

check("D-01 Rust: concat(Col[Int], Col[Text]) → OOF-COL7") { d1[:codes].include?("OOF-COL7") }
check("D-02 Ruby: concat(Col[Int], Col[Text]) → OOF-COL7 (parity)") { d2_rb[:codes].include?("OOF-COL7") }
check("D-03 Rust: OOF-COL7 message mentions element types") {
  Array(d3[:diags]).any? { |d| d["rule"] == "OOF-COL7" && d["message"].to_s.match?(/Integer|Text/) }
}

# ---------------------------------------------------------------------------
# Section E — Unknown permissive
# ---------------------------------------------------------------------------

section("E-UNKNOWN-PERMISSIVE")

# Untyped variable — typechecker will produce Unknown type, should route to collection path
e1 = rust_compile(<<~IG)
  module ColConcat.E1
  pure contract TestE1 {
    input xs : Collection[Integer]
    input ys : Collection[Integer]
    compute mid = concat(xs, ys)
    compute out = concat(mid, ys)
    output out : Collection[Integer]
  }
IG

# Two-arg concat where both are concrete Collections (known path)
e2 = rust_compile(<<~IG)
  module ColConcat.E2
  pure contract TestE2 {
    input xs : Collection[Text]
    input ys : Collection[Text]
    compute out = concat(xs, ys)
    output out : Collection[Text]
  }
IG

check("E-01 Rust: chained concat (mid is Col) → status=ok") { e1[:status] == "ok" }
check("E-02 Rust: chained concat SIR has stdlib.collection.concat (not stdlib.text.concat)") {
  fns = collect_fn_names(e1[:sir])
  fns.include?("stdlib.collection.concat") && !fns.include?("stdlib.text.concat")
}
check("E-03 Rust: concat(Col[Text], Col[Text]) → status=ok") { e2[:status] == "ok" }
check("E-04 Rust: no OOF-TY0 on collection concat (not routing to unsupported)") {
  !e1[:codes].include?("OOF-TY0") && !e2[:codes].include?("OOF-TY0")
}

# ---------------------------------------------------------------------------
# Section F — DSA-P03 fix: field-access first arg routes to collection
# ---------------------------------------------------------------------------

section("F-DSA-P03-FIELD-ACCESS")

# s.elements is a Collection[T] accessed via field — quick_arg_type returned Unknown before fix
f1 = rust_compile(<<~IG)
  module ColConcat.F1
  type Batch { elements : Collection[Integer] }
  pure contract TestF1 {
    input s : Batch
    input ys : Collection[Integer]
    compute out = concat(s.elements, ys)
    output out : Collection[Integer]
  }
IG

f2 = rust_compile(<<~IG)
  module ColConcat.F2
  type Pair { left : Collection[Text], right : Collection[Text] }
  pure contract TestF2 {
    input p : Pair
    compute out = concat(p.left, p.right)
    output out : Collection[Text]
  }
IG

check("F-01 Rust: concat(s.elements, ys) → status=ok (DSA-P03 fixed)") { f1[:status] == "ok" }
check("F-02 Rust: concat(s.elements, ys) SIR fn = stdlib.collection.concat") {
  collect_fn_names(f1[:sir]).include?("stdlib.collection.concat")
}
check("F-03 Rust: concat(p.left, p.right) → status=ok") { f2[:status] == "ok" }
check("F-04 Rust: concat(p.left, p.right) SIR fn = stdlib.collection.concat (not text)") {
  fns = collect_fn_names(f2[:sir])
  fns.include?("stdlib.collection.concat") && !fns.include?("stdlib.text.concat")
}

# ---------------------------------------------------------------------------
# Section G — Element type preserved in SIR
# ---------------------------------------------------------------------------

section("G-ELEMENT-TYPE-IN-SIR")

g1 = rust_compile(<<~IG)
  module ColConcat.G1
  pure contract TestG1 {
    input xs : Collection[Integer]
    input ys : Collection[Integer]
    compute out = concat(xs, ys)
    output out : Collection[Integer]
  }
IG

g2 = rust_compile(<<~IG)
  module ColConcat.G2
  pure contract TestG2 {
    input xs : Collection[Text]
    input ys : Collection[Text]
    compute out = concat(xs, ys)
    output out : Collection[Text]
  }
IG

g1_rt = resolved_type_for(g1[:sir], "stdlib.collection.concat")
g2_rt = resolved_type_for(g2[:sir], "stdlib.collection.concat")

check("G-01 Rust: resolved_type present on stdlib.collection.concat call in SIR") {
  !g1_rt.nil?
}
check("G-02 Rust: resolved_type.name = Collection for Int concat") {
  g1_rt.is_a?(Hash) && g1_rt["name"] == "Collection"
}
check("G-03 Rust: resolved_type has non-empty params (element type not erased)") {
  g1_rt.is_a?(Hash) && Array(g1_rt["params"]).length > 0
}
check("G-04 Rust: element param name = Integer for Col[Integer] concat") {
  g1_rt.is_a?(Hash) &&
    Array(g1_rt["params"]).first.is_a?(Hash) &&
    Array(g1_rt["params"]).first["name"] == "Integer"
}

# ---------------------------------------------------------------------------
# Section H — Text concat unaffected
# ---------------------------------------------------------------------------

section("H-TEXT-CONCAT-UNAFFECTED")

h1 = rust_compile(<<~IG)
  module ColConcat.H1
  pure contract TestH1 {
    input a : Text
    input b : Text
    compute out = concat(a, b)
    output out : Text
  }
IG

h2 = rust_compile(<<~IG)
  module ColConcat.H2
  pure contract TestH2 {
    input a : Text
    input b : Text
    input c : Text
    compute out = concat(a, b)
    output out : Text
  }
IG

h3_rb = ruby_compile(<<~IG)
  module ColConcat.H3
  pure contract TestH3 {
    input a : Text
    input b : Text
    compute out = concat(a, b)
    output out : Text
  }
IG

check("H-01 Rust: concat(Text, Text) → status=ok") { h1[:status] == "ok" }
check("H-02 Rust: concat(Text, Text) SIR fn = stdlib.text.concat") {
  collect_fn_names(h1[:sir]).include?("stdlib.text.concat")
}
check("H-03 Rust: concat(Text, Text) no collection codes") {
  (h1[:codes] & %w[OOF-COL1 OOF-COL2 OOF-COL7]).empty?
}
check("H-04 Ruby: concat(Text, Text) → typecheck=ok (text path regression)") { h3_rb[:typecheck] == "ok" }

# ---------------------------------------------------------------------------
# Section I — Inventory
# ---------------------------------------------------------------------------

section("I-INVENTORY")

concat_entry = INV["entries"].find { |e| e["canonical_name"] == "stdlib.collection.concat" }

check("I-01 inventory: stdlib.collection.concat lowering_status = dual-toolchain") {
  concat_entry&.fetch("lowering_status", nil) == "dual-toolchain"
}
check("I-02 inventory: stdlib.collection.concat proof_lineage mentions PROP-P4") {
  Array(concat_entry&.fetch("proof_lineage", [])).any? { |l| l.include?("P4") }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

puts "\n" + "=" * 60
total  = CHECKS.size
passed = CHECKS.count { |c| c[:pass] }
failed = total - passed

puts "LANG-STDLIB-COLLECTION-CONCAT-PROP-P4 #{passed == total ? "PASS" : "FAIL"} (#{passed}/#{total})"

if failed > 0
  puts "\nFailed checks:"
  CHECKS.each { |c| puts "  FAIL #{c[:label]}#{c[:detail] ? " — #{c[:detail]}" : ""}" unless c[:pass] }
end
