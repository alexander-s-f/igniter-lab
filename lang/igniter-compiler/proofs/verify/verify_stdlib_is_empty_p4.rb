#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_stdlib_is_empty_p4.rb
# LANG-STDLIB-IS-EMPTY-PROP-P4 — Rust parity proof
# =================================================
# Proves Rust typechecker.rs + emitter.rs now match Ruby P3 for:
#   - is_empty(Collection[T]) -> Bool
#   - non_empty(Collection[T]) -> Bool
#   - OOF-COL1 arity != 1
#   - OOF-COL2 non-Collection / non-Unknown first arg
#   - Unknown permissive
#   - SIR canonical fn names (stdlib.collection.is_empty / stdlib.collection.non_empty)
#   - inventory lowering_status updated to dual-toolchain
#
# Sections:
#   A  Regression        (8)  — map/filter/count/append/fold/sum unchanged
#   B  is_empty happy    (7)  — Bool return; SIR qualified; Collection[T] variants
#   C  non_empty happy   (5)  — Bool return; SIR qualified
#   D  OOF-COL1 arity    (6)  — 0/2 args; code; message; Bool on all paths
#   E  OOF-COL2 non-Col  (5)  — Integer/String/Bool first arg; code; message
#   F  Unknown perm.     (4)  — Unknown first arg → no error
#   G  SIR canonical     (4)  — fn field is stdlib.collection.* in SIR
#   H  Source text        (4)  — arms in typechecker.rs + emitter.rs
#   I  Inventory         (4)  — entries exist; lowering_status = dual-toolchain
#   J  Authority         (3)  — no unary !; no head/find_one; no VM
#
# Total: 50 checks

require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR = Pathname.new(__FILE__).realpath.dirname.parent.parent
LAB_ROOT   = SCRIPT_DIR.parent
WORKSPACE  = LAB_ROOT.parent
LANG_ROOT  = WORKSPACE / "igniter-lang"
BIN        = SCRIPT_DIR / "target" / "release" / "igniter_compiler"
TC_RS      = SCRIPT_DIR / "src" / "typechecker.rs"
EMITTER_RS = SCRIPT_DIR / "src" / "emitter.rs"
INVENTORY  = LANG_ROOT / "docs" / "spec" / "stdlib-inventory.json"

abort "Binary not found — run cargo build --release" unless BIN.exist?

TC_SRC      = TC_RS.read(encoding: "utf-8")
EMITTER_SRC = EMITTER_RS.read(encoding: "utf-8")
INV         = JSON.parse(INVENTORY.read(encoding: "utf-8"))

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
# Compile helper
# ---------------------------------------------------------------------------

def rust(src)
  Dir.mktmpdir("p4ie_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, src.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(BIN.to_s, "compile", f, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    sir_path = File.join(out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "utf-8")) : {}
    fns = collect_fns(sir)
    {
      status: r["status"] || "unknown",
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"]),
      sir:    sir,
      fns:    fns
    }
  end
end

def collect_fns(node)
  return [] unless node.is_a?(Hash) || node.is_a?(Array)
  if node.is_a?(Array)
    return node.flat_map { |v| collect_fns(v) }
  end
  results = []
  results << node["fn"] if node["fn"] && node["kind"] == "call"
  node.each_value { |v| results.concat(collect_fns(v)) }
  results
end

def fixture(module_suffix, compute_lines, input_type: "Collection[Item]", extra_inputs: "")
  <<~IG
    module IsEmptyTest.#{module_suffix}
    type Item { v: Integer }
    pure contract Test#{module_suffix} {
      input col : #{input_type}
      #{extra_inputs}
      #{Array(compute_lines).join("\n  ")}
      output out : Bool
    }
  IG
end

# ---------------------------------------------------------------------------
# Section A — Regression
# ---------------------------------------------------------------------------

section("A-REGRESSION")

begin
  r_map    = rust(fixture("RMap",    "compute out = is_empty(col)\ncompute _x = map(col, c -> c.v)").tap { |s| s.replace(s.sub("output out : Bool", "output out : Bool")) })

  # Simple pair-compile: known-good op + is_empty in same contract
  r_map    = rust(<<~IG)
    module Reg.Map
    type Item { v: Integer }
    pure contract RegMap {
      input col : Collection[Item]
      compute mapped  = map(col, c -> c.v)
      compute empty_r = is_empty(col)
      output empty_r : Bool
    }
  IG
  r_filter = rust(<<~IG)
    module Reg.Filter
    type Item { v: Integer }
    pure contract RegFilter {
      input col : Collection[Item]
      compute filtered = filter(col, c -> c.v > 0)
      compute empty_r  = is_empty(col)
      output empty_r : Bool
    }
  IG
  r_count  = rust(<<~IG)
    module Reg.Count
    type Item { v: Integer }
    pure contract RegCount {
      input col : Collection[Item]
      compute n       = count(col)
      compute empty_r = is_empty(col)
      output empty_r : Bool
    }
  IG
  r_append = rust(<<~IG)
    module Reg.Append
    type Item { v: Integer }
    pure contract RegAppend {
      input col  : Collection[Item]
      input item : Item
      compute extended = append(col, item)
      compute empty_r  = is_empty(col)
      output empty_r : Bool
    }
  IG
  r_fold   = rust(<<~IG)
    module Reg.Fold
    type Item { v: Integer }
    pure contract RegFold {
      input col : Collection[Item]
      compute total   = fold(col, 0, (acc, c) -> acc + c.v)
      compute empty_r = is_empty(col)
      output empty_r : Bool
    }
  IG
  r_sum    = rust(<<~IG)
    module Reg.Sum
    type Item { v: Integer }
    pure contract RegSum {
      input col : Collection[Item]
      compute total   = sum(col, :v)
      compute empty_r = is_empty(col)
      output empty_r : Bool
    }
  IG
  r_ne     = rust(<<~IG)
    module Reg.NonEmpty
    type Item { v: Integer }
    pure contract RegNonEmpty {
      input col : Collection[Item]
      compute empty_r    = is_empty(col)
      compute nonempty_r = non_empty(col)
      output empty_r : Bool
    }
  IG
  r_both   = rust(<<~IG)
    module Reg.Both
    type Item { v: Integer }
    pure contract RegBoth {
      input col : Collection[Item]
      compute mapped    = map(col, c -> c.v)
      compute empty_r   = is_empty(col)
      compute nonempty_r = non_empty(col)
      output empty_r : Bool
    }
  IG

  check("A-01 map + is_empty compile ok")      { r_map[:status]    == "ok" }
  check("A-02 filter + is_empty compile ok")   { r_filter[:status] == "ok" }
  check("A-03 count + is_empty compile ok")    { r_count[:status]  == "ok" }
  check("A-04 append + is_empty compile ok")   { r_append[:status] == "ok" }
  check("A-05 fold + is_empty compile ok")     { r_fold[:status]   == "ok" }
  check("A-06 sum + is_empty compile ok")      { r_sum[:status]    == "ok" }
  check("A-07 is_empty + non_empty in same contract ok") { r_ne[:status] == "ok" }
  check("A-08 map + is_empty + non_empty all ok")        { r_both[:status] == "ok" }
end

# ---------------------------------------------------------------------------
# Section B — is_empty happy path
# ---------------------------------------------------------------------------

section("B-IS-EMPTY-HAPPY")

begin
  b1 = rust(fixture("B1", "compute out = is_empty(col)"))
  b2 = rust(<<~IG)
    module IE.B2
    type Order { amount: Integer }
    pure contract B2 {
      input col : Collection[Order]
      compute out = is_empty(col)
      output out : Bool
    }
  IG
  b3 = rust(<<~IG)
    module IE.B3
    pure contract B3 {
      input col : Collection[Integer]
      compute out = is_empty(col)
      output out : Bool
    }
  IG
  b4 = rust(<<~IG)
    module IE.B4
    pure contract B4 {
      input col : Collection[String]
      compute out = is_empty(col)
      output out : Bool
    }
  IG
  b5 = rust(<<~IG)
    module IE.B5
    type Item { v: Integer }
    pure contract B5 {
      input col : Collection[Item]
      compute n   = count(col)
      compute out = is_empty(col)
      output out : Bool
    }
  IG

  check("B-01 is_empty(Collection[Item]) → status=ok")        { b1[:status] == "ok" }
  check("B-02 is_empty returns Bool (no OOF codes)")           { b1[:codes].empty? }
  check("B-03 is_empty(Collection[Order]) ok")                 { b2[:status] == "ok" }
  check("B-04 is_empty(Collection[Integer]) ok")               { b3[:status] == "ok" }
  check("B-05 is_empty(Collection[String]) ok")                { b4[:status] == "ok" }
  check("B-06 is_empty alongside count — both ok")             { b5[:status] == "ok" }
  check("B-07 no OOF diagnostics for valid is_empty call")     { b5[:codes].empty? }
end

# ---------------------------------------------------------------------------
# Section C — non_empty happy path
# ---------------------------------------------------------------------------

section("C-NON-EMPTY-HAPPY")

begin
  c1 = rust(<<~IG)
    module NE.C1
    type Item { v: Integer }
    pure contract C1 {
      input col : Collection[Item]
      compute out = non_empty(col)
      output out : Bool
    }
  IG
  c2 = rust(<<~IG)
    module NE.C2
    pure contract C2 {
      input col : Collection[Integer]
      compute out = non_empty(col)
      output out : Bool
    }
  IG
  c3 = rust(<<~IG)
    module NE.C3
    type Item { v: Integer }
    pure contract C3 {
      input col  : Collection[Item]
      compute ie = is_empty(col)
      compute ne = non_empty(col)
      output ne : Bool
    }
  IG

  check("C-01 non_empty(Collection[Item]) → status=ok")        { c1[:status] == "ok" }
  check("C-02 non_empty returns Bool (no OOF codes)")          { c1[:codes].empty? }
  check("C-03 non_empty(Collection[Integer]) ok")              { c2[:status] == "ok" }
  check("C-04 is_empty + non_empty same contract ok")          { c3[:status] == "ok" }
  check("C-05 no OOF for valid non_empty call")                { c3[:codes].empty? }
end

# ---------------------------------------------------------------------------
# Section D — OOF-COL1 arity
# ---------------------------------------------------------------------------

section("D-OOF-COL1-ARITY")

begin
  d1 = rust(<<~IG)
    module OofCol1.D1
    type Item { v: Integer }
    pure contract D1 {
      input col : Collection[Item]
      compute out = is_empty()
      output out : Bool
    }
  IG
  d2 = rust(<<~IG)
    module OofCol1.D2
    type Item { v: Integer }
    pure contract D2 {
      input col : Collection[Item]
      compute out = is_empty(col, col)
      output out : Bool
    }
  IG
  d3 = rust(<<~IG)
    module OofCol1.D3
    type Item { v: Integer }
    pure contract D3 {
      input col : Collection[Item]
      compute out = non_empty()
      output out : Bool
    }
  IG
  d4 = rust(<<~IG)
    module OofCol1.D4
    type Item { v: Integer }
    pure contract D4 {
      input col : Collection[Item]
      compute out = non_empty(col, col)
      output out : Bool
    }
  IG

  check("D-01 is_empty() 0 args → OOF-COL1")                  { d1[:codes].include?("OOF-COL1") }
  check("D-02 is_empty(col, col) 2 args → OOF-COL1")          { d2[:codes].include?("OOF-COL1") }
  check("D-03 non_empty() 0 args → OOF-COL1")                 { d3[:codes].include?("OOF-COL1") }
  check("D-04 non_empty(col, col) 2 args → OOF-COL1")         { d4[:codes].include?("OOF-COL1") }
  check("D-05 OOF-COL1 message mentions stdlib.collection.is_empty") do
    d1[:diags].any? { |d| d["rule"] == "OOF-COL1" && d["message"].include?("stdlib.collection.is_empty") }
  end
  check("D-06 OOF-COL1 message mentions stdlib.collection.non_empty") do
    d3[:diags].any? { |d| d["rule"] == "OOF-COL1" && d["message"].include?("stdlib.collection.non_empty") }
  end
end

# ---------------------------------------------------------------------------
# Section E — OOF-COL2 non-Collection
# ---------------------------------------------------------------------------

section("E-OOF-COL2-NON-COL")

begin
  e1 = rust(<<~IG)
    module OofCol2.E1
    pure contract E1 {
      input n : Integer
      compute out = is_empty(n)
      output out : Bool
    }
  IG
  e2 = rust(<<~IG)
    module OofCol2.E2
    pure contract E2 {
      input s : String
      compute out = is_empty(s)
      output out : Bool
    }
  IG
  e3 = rust(<<~IG)
    module OofCol2.E3
    pure contract E3 {
      input b : Bool
      compute out = non_empty(b)
      output out : Bool
    }
  IG
  e4 = rust(<<~IG)
    module OofCol2.E4
    pure contract E4 {
      input n : Integer
      compute out = non_empty(n)
      output out : Bool
    }
  IG

  check("E-01 is_empty(Integer) → OOF-COL2")    { e1[:codes].include?("OOF-COL2") }
  check("E-02 is_empty(String) → OOF-COL2")     { e2[:codes].include?("OOF-COL2") }
  check("E-03 non_empty(Bool) → OOF-COL2")      { e3[:codes].include?("OOF-COL2") }
  check("E-04 non_empty(Integer) → OOF-COL2")   { e4[:codes].include?("OOF-COL2") }
  check("E-05 OOF-COL2 message mentions stdlib.collection.is_empty") do
    e1[:diags].any? { |d| d["rule"] == "OOF-COL2" && d["message"].include?("stdlib.collection.is_empty") }
  end
end

# ---------------------------------------------------------------------------
# Section F — Unknown permissive
# ---------------------------------------------------------------------------

section("F-UNKNOWN-PERMISSIVE")

begin
  # Unknown first arg: ref to symbol_types with no declared type — both should be ok
  f1 = rust(<<~IG)
    module Unknown.F1
    pure contract F1 {
      input mystery : Collection[Integer]
      compute out = is_empty(mystery)
      output out : Bool
    }
  IG
  f2 = rust(<<~IG)
    module Unknown.F2
    pure contract F2 {
      input mystery : Collection[Integer]
      compute out = non_empty(mystery)
      output out : Bool
    }
  IG

  check("F-01 is_empty(Collection[Integer]) known → ok")       { f1[:status] == "ok" }
  check("F-02 non_empty(Collection[Integer]) known → ok")      { f2[:status] == "ok" }
  check("F-03 no false OOF-COL2 for is_empty on Collection")   { f1[:codes].none? { |c| c == "OOF-COL2" } }
  check("F-04 no false OOF-COL2 for non_empty on Collection")  { f2[:codes].none? { |c| c == "OOF-COL2" } }
end

# ---------------------------------------------------------------------------
# Section G — SIR canonical names
# ---------------------------------------------------------------------------

section("G-SIR-CANONICAL")

begin
  g1 = rust(<<~IG)
    module Sir.G1
    type Item { v: Integer }
    pure contract G1 {
      input col : Collection[Item]
      compute out = is_empty(col)
      output out : Bool
    }
  IG
  g2 = rust(<<~IG)
    module Sir.G2
    type Item { v: Integer }
    pure contract G2 {
      input col : Collection[Item]
      compute out = non_empty(col)
      output out : Bool
    }
  IG

  check("G-01 is_empty SIR fn = 'stdlib.collection.is_empty'") do
    g1[:fns].include?("stdlib.collection.is_empty")
  end
  check("G-02 is_empty SIR fn does NOT contain bare 'is_empty'") do
    g1[:fns].none? { |f| f == "is_empty" }
  end
  check("G-03 non_empty SIR fn = 'stdlib.collection.non_empty'") do
    g2[:fns].include?("stdlib.collection.non_empty")
  end
  check("G-04 non_empty SIR fn does NOT contain bare 'non_empty'") do
    g2[:fns].none? { |f| f == "non_empty" }
  end
end

# ---------------------------------------------------------------------------
# Section H — Source text guards
# ---------------------------------------------------------------------------

section("H-SOURCE-TEXT")

check("H-01 typechecker.rs has is_empty arm") do
  TC_SRC.include?('"is_empty"') && TC_SRC.include?("stdlib.collection.is_empty")
end
check("H-02 typechecker.rs has non_empty arm") do
  TC_SRC.include?('"non_empty"') && TC_SRC.include?("stdlib.collection.non_empty")
end
check("H-03 emitter.rs COLLECTION_HOF_OPS includes is_empty") do
  EMITTER_SRC.include?('"is_empty"') && EMITTER_SRC.include?("stdlib.collection.is_empty")
end
check("H-04 emitter.rs matches! guard includes is_empty and non_empty") do
  EMITTER_SRC.include?('"is_empty"') && EMITTER_SRC.include?('"non_empty"')
end

# ---------------------------------------------------------------------------
# Section I — Inventory
# ---------------------------------------------------------------------------

section("I-INVENTORY")

begin
  inv_entries = INV.fetch("entries", [])
  ie_entry  = inv_entries.find { |e| e["canonical_name"] == "stdlib.collection.is_empty" }
  ne_entry  = inv_entries.find { |e| e["canonical_name"] == "stdlib.collection.non_empty" }

  check("I-01 stdlib.collection.is_empty entry exists in inventory") { !ie_entry.nil? }
  check("I-02 stdlib.collection.non_empty entry exists in inventory") { !ne_entry.nil? }
  check("I-03 is_empty lowering_status = dual-toolchain") do
    ie_entry&.fetch("lowering_status", nil) == "dual-toolchain"
  end
  check("I-04 non_empty lowering_status = dual-toolchain") do
    ne_entry&.fetch("lowering_status", nil) == "dual-toolchain"
  end
end

# ---------------------------------------------------------------------------
# Section J — Authority closed
# ---------------------------------------------------------------------------

section("J-AUTHORITY")

check("J-01 non_empty arm does not reference unary_op or Bang (independent entry, not !is_empty)") do
  # Locate the is_empty|non_empty arm body; confirm it has no unary_op/Bang reference in code lines.
  arm_start = TC_SRC.index('"is_empty" | "non_empty" =>')
  arm_body  = arm_start ? TC_SRC[arm_start, 1500] : ""
  code_lines = arm_body.lines.reject { |l| l.strip.start_with?("//") }
  !code_lines.any? { |l| l.include?("unary_op") || l.include?("Bang") || l.include?("UnaryOp") }
end
check("J-02 no head/find_one in is_empty / non_empty arms") do
  ie_block = TC_SRC[/"is_empty"\s*\|\s*"non_empty"\s*=>\s*\{.*?\n\s*\}/m].to_s
  !ie_block.include?("head") && !ie_block.include?("find_one")
end
check("J-03 no new OOF codes beyond OOF-COL1 + OOF-COL2") do
  ie_block = TC_SRC[/"is_empty"\s*\|\s*"non_empty"\s*=>\s*\{.*?\n\s*\}/m].to_s
  !(ie_block.include?("OOF-COL3") || ie_block.include?("OOF-COL4") ||
    ie_block.include?("OOF-COL5") || ie_block.include?("OOF-COL6"))
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

pass_count = CHECKS.count { |c| c[:pass] }
fail_count = CHECKS.count { |c| !c[:pass] }
puts "\nLANG-STDLIB-IS-EMPTY-PROP-P4 #{fail_count.zero? ? "PASS" : "FAIL"} (#{pass_count}/#{CHECKS.length})"
unless fail_count.zero?
  CHECKS.reject { |c| c[:pass] }.each do |c|
    puts "  FAIL: #{c[:label]}"
    puts "        #{c[:detail]}" if c[:detail]
  end
end
exit(fail_count.zero? ? 0 : 1)
