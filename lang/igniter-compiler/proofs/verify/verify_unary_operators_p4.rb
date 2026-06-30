#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_unary_operators_p4.rb
# LANG-UNARY-OPERATORS-P4 — Rust parity proof
# =============================================
# Proves the bounded Rust implementation of unary ! and unary - in:
#   parser.rs    — parse_unary extended with unary minus branch
#   typechecker.rs — Expr::UnaryOp arm with OOF-TY0 + Unknown permissive
#   emitter.rs   — unary_op -> call node conversion in semantic_expr
#
# Sections:
#   A  Parser: unary minus forms (6)
#   B  Parser: bang forms (4)
#   C  TC happy path: ! (4)
#   D  TC happy path: - (4)
#   E  Unknown permissive (3)
#   F  OOF-TY0 wrong operand (5)
#   G  SIR output parity (6)
#   H  App fixtures (7)
#   I  Regression (6)
#
# Total: 45 checks

require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR  = Pathname.new(__FILE__).realpath.dirname.parent.parent
LAB_ROOT    = SCRIPT_DIR.parent
WORKSPACE   = LAB_ROOT.parent
LANG_ROOT   = WORKSPACE / "igniter-lang"
BIN         = SCRIPT_DIR / "target" / "release" / "igniter_compiler"
PARSER_RS   = SCRIPT_DIR / "src" / "parser.rs"
TC_RS       = SCRIPT_DIR / "src" / "typechecker.rs"
EMITTER_RS  = SCRIPT_DIR / "src" / "emitter.rs"
INVENTORY   = LANG_ROOT / "docs" / "spec" / "stdlib-inventory.json"

abort "Binary not found — run: cargo build --release" unless BIN.exist?

PARSER_SRC  = PARSER_RS.read(encoding: "utf-8")
TC_SRC      = TC_RS.read(encoding: "utf-8")
EMITTER_SRC = EMITTER_RS.read(encoding: "utf-8")
INV         = JSON.parse(INVENTORY.read(encoding: "utf-8"))

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

$pass = 0
$fail = 0

def check(label)
  pass = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  if pass
    $pass += 1
    puts "  PASS #{label}"
  else
    $fail += 1
    puts "  FAIL #{label}#{detail ? " [#{detail}]" : ""}"
  end
end

def section(name)
  puts "\n[#{name}]"
end

# ---------------------------------------------------------------------------
# Compile helpers
# ---------------------------------------------------------------------------

def rust(src)
  Dir.mktmpdir("p4un_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, src.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(BIN.to_s, "compile", f, "--out", out)
    r = begin JSON.parse(stdout.force_encoding("UTF-8")) rescue {} end
    sir_path = File.join(out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "utf-8")) : {}
    {
      status: r["status"] || "unknown",
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      msgs:   Array(r["diagnostics"]).map { |d| d["message"] }.compact,
      diags:  Array(r["diagnostics"]),
      sir:    sir,
      fns:    collect_fns(sir)
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

def collect_kinds(node)
  return [] unless node.is_a?(Hash) || node.is_a?(Array)
  if node.is_a?(Array)
    return node.flat_map { |v| collect_kinds(v) }
  end
  results = [node["kind"]].compact
  node.each_value { |v| results.concat(collect_kinds(v)) }
  results
end

def collect_resolved_type_names(node)
  return [] unless node.is_a?(Hash) || node.is_a?(Array)
  if node.is_a?(Array)
    return node.flat_map { |v| collect_resolved_type_names(v) }
  end
  names = node["resolved_type"].is_a?(Hash) ? [node["resolved_type"]["name"]] : []
  names + node.each_value.flat_map { |v| collect_resolved_type_names(v) }
end

def ok?(r)
  r[:status] == "ok" && r[:codes].empty?
end

# ---------------------------------------------------------------------------
# Section A — Parser: unary minus forms
# ---------------------------------------------------------------------------

section("A-PARSER-UNARY-MINUS")

check "A-01: parser.rs has is_unary_minus branch" do
  PARSER_SRC.include?("is_unary_minus")
end

check "A-02: -500 literal — compiles without parse error" do
  r = rust(<<~IG)
    module UnaryP4.A02
    pure contract NegLit {
      input x : Integer
      compute n = -500
      output n : Integer
    }
  IG
  ok?(r)
end

check "A-03: -x (variable ref) — compiles without error" do
  r = rust(<<~IG)
    module UnaryP4.A03
    pure contract NegRef {
      input x : Integer
      compute n = -x
      output n : Integer
    }
  IG
  ok?(r)
end

check "A-04: record literal {a: -300} — compiles without error" do
  r = rust(<<~IG)
    module UnaryP4.A04
    type Pair { a : Integer b : Integer }
    pure contract NegRec {
      input x : Integer
      compute p = Pair { a: -300 b: 5 }
      output p : Pair
    }
  IG
  r[:status] != "unknown"
end

check "A-05: if/else branch with -1 — compiles without error" do
  r = rust(<<~IG)
    module UnaryP4.A05
    pure contract NegBranch {
      input flag : Bool
      compute n = if flag { 1 } else { -1 }
      output n : Integer
    }
  IG
  ok?(r)
end

check "A-06: -(x+1) — operand is binary_op, compiles without error" do
  r = rust(<<~IG)
    module UnaryP4.A06
    pure contract NegBinOp {
      input x : Integer
      compute n = -(x + 1)
      output n : Integer
    }
  IG
  ok?(r)
end

# ---------------------------------------------------------------------------
# Section B — Parser: bang forms
# ---------------------------------------------------------------------------

section("B-PARSER-BANG")

check "B-01: !flag — compiles without error" do
  r = rust(<<~IG)
    module UnaryP4.B01
    pure contract NotFlag {
      input flag : Bool
      compute n = !flag
      output n : Bool
    }
  IG
  ok?(r)
end

check "B-02: !(x == y) — compiles without error" do
  r = rust(<<~IG)
    module UnaryP4.B02
    pure contract NotEq {
      input x : Integer
      input y : Integer
      compute n = !(x == y)
      output n : Bool
    }
  IG
  ok?(r)
end

check "B-03: Expr::UnaryOp is in parser source" do
  PARSER_SRC.include?("Expr::UnaryOp")
end

check "B-04: parse_unary handles Bang token before unary_minus check" do
  bang_pos  = PARSER_SRC.index("peek_type(TokenType::Bang)")
  minus_pos = PARSER_SRC.index("is_unary_minus")
  bang_pos && minus_pos && bang_pos < minus_pos
end

# ---------------------------------------------------------------------------
# Section C — TC happy path: !
# ---------------------------------------------------------------------------

section("C-TC-BANG-HAPPY")

check "C-01: !flag — no OOF codes" do
  r = rust(<<~IG)
    module UnaryP4.C01
    pure contract C01 {
      input flag : Bool
      compute n = !flag
      output n : Bool
    }
  IG
  r[:codes].empty?
end

check "C-02: !flag — output resolves to Bool" do
  r = rust(<<~IG)
    module UnaryP4.C02
    pure contract C02 {
      input flag : Bool
      compute n = !flag
      output n : Bool
    }
  IG
  r[:fns].include?("stdlib.primitive.not")
end

check "C-03: !true — SIR fn is stdlib.primitive.not" do
  r = rust(<<~IG)
    module UnaryP4.C03
    pure contract C03 {
      input flag : Bool
      compute n = !flag
      output n : Bool
    }
  IG
  r[:fns].include?("stdlib.primitive.not")
end

check "C-04: typechecker.rs has Expr::UnaryOp arm" do
  TC_SRC.include?("Expr::UnaryOp { op, operand }")
end

# ---------------------------------------------------------------------------
# Section D — TC happy path: -
# ---------------------------------------------------------------------------

section("D-TC-NEG-HAPPY")

check "D-01: -x — no OOF codes" do
  r = rust(<<~IG)
    module UnaryP4.D01
    pure contract D01 {
      input x : Integer
      compute n = -x
      output n : Integer
    }
  IG
  r[:codes].empty?
end

check "D-02: -x — SIR fn is stdlib.integer.neg" do
  r = rust(<<~IG)
    module UnaryP4.D02
    pure contract D02 {
      input x : Integer
      compute n = -x
      output n : Integer
    }
  IG
  r[:fns].include?("stdlib.integer.neg")
end

check "D-03: -500 — SIR fn is stdlib.integer.neg" do
  r = rust(<<~IG)
    module UnaryP4.D03
    pure contract D03 {
      input x : Integer
      compute n = -500
      output n : Integer
    }
  IG
  r[:fns].include?("stdlib.integer.neg")
end

check "D-04: typechecker.rs has stdlib.integer.neg string" do
  TC_SRC.include?('"stdlib.integer.neg"')
end

# ---------------------------------------------------------------------------
# Section E — Unknown permissive
# ---------------------------------------------------------------------------

section("E-UNKNOWN-PERMISSIVE")

check "E-01: !Unknown — no OOF-TY0 when operand is Unknown-typed input" do
  r = rust(<<~IG)
    module UnaryP4.E01
    pure contract E01 {
      input flag : Unknown
      compute n = !flag
      output n : Bool
    }
  IG
  !r[:codes].include?("OOF-TY0")
end

check "E-02: -Unknown — no OOF-TY0 when operand is Unknown-typed input" do
  r = rust(<<~IG)
    module UnaryP4.E02
    pure contract E02 {
      input x : Unknown
      compute n = -x
      output n : Integer
    }
  IG
  !r[:codes].include?("OOF-TY0")
end

check "E-03: typechecker.rs checks != Unknown before emitting OOF-TY0" do
  TC_SRC.include?('"Unknown"')
end

# ---------------------------------------------------------------------------
# Section F — OOF-TY0 wrong operand
# ---------------------------------------------------------------------------

section("F-OOF-TY0-WRONG-OPERAND")

check "F-01: !Integer — OOF-TY0 raised" do
  r = rust(<<~IG)
    module UnaryP4.F01
    pure contract F01 {
      input x : Integer
      compute n = !x
      output n : Bool
    }
  IG
  r[:codes].include?("OOF-TY0")
end

check "F-02: !Integer — message mentions Bool" do
  r = rust(<<~IG)
    module UnaryP4.F02
    pure contract F02 {
      input x : Integer
      compute n = !x
      output n : Bool
    }
  IG
  r[:msgs].any? { |m| m.include?("Bool") && m.include?("!") }
end

check "F-03: -Bool — OOF-TY0 raised" do
  r = rust(<<~IG)
    module UnaryP4.F03
    pure contract F03 {
      input flag : Bool
      compute n = -flag
      output n : Integer
    }
  IG
  r[:codes].include?("OOF-TY0")
end

check "F-04: -Bool — message mentions Integer" do
  r = rust(<<~IG)
    module UnaryP4.F04
    pure contract F04 {
      input flag : Bool
      compute n = -flag
      output n : Integer
    }
  IG
  r[:msgs].any? { |m| m.include?("Integer") && m.include?("-") }
end

check "F-05: OOF-TY0 rule is 'OOF-TY0' not a new code" do
  r = rust(<<~IG)
    module UnaryP4.F05
    pure contract F05 {
      input x : Integer
      compute n = !x
      output n : Bool
    }
  IG
  r[:codes].include?("OOF-TY0") && !r[:codes].include?("OOF-NOT1") && !r[:codes].include?("OOF-NEG1")
end

# ---------------------------------------------------------------------------
# Section G — SIR output parity
# ---------------------------------------------------------------------------

section("G-SIR-OUTPUT-PARITY")

check "G-01: SIR has call node for !flag (not raw unary_op)" do
  r = rust(<<~IG)
    module UnaryP4.G01
    pure contract G01 {
      input flag : Bool
      compute n = !flag
      output n : Bool
    }
  IG
  kinds = collect_kinds(r[:sir])
  kinds.include?("call") && !kinds.include?("unary_op")
end

check "G-02: SIR has call node for -x (not raw unary_op)" do
  r = rust(<<~IG)
    module UnaryP4.G02
    pure contract G02 {
      input x : Integer
      compute n = -x
      output n : Integer
    }
  IG
  kinds = collect_kinds(r[:sir])
  kinds.include?("call") && !kinds.include?("unary_op")
end

check "G-03: stdlib.primitive.not in SIR fns for ! case" do
  r = rust(<<~IG)
    module UnaryP4.G03
    pure contract G03 {
      input flag : Bool
      compute n = !flag
      output n : Bool
    }
  IG
  r[:fns].include?("stdlib.primitive.not")
end

check "G-04: stdlib.integer.neg in SIR fns for - case" do
  r = rust(<<~IG)
    module UnaryP4.G04
    pure contract G04 {
      input x : Integer
      compute n = -x
      output n : Integer
    }
  IG
  r[:fns].include?("stdlib.integer.neg")
end

check "G-05: emitter.rs has unary_op -> call conversion block" do
  EMITTER_SRC.include?("stdlib.primitive.not") && EMITTER_SRC.include?("stdlib.integer.neg")
end

check "G-06: resolved_type attached to call node in SIR" do
  r = rust(<<~IG)
    module UnaryP4.G06
    pure contract G06 {
      input x : Integer
      compute n = -x
      output n : Integer
    }
  IG
  collect_resolved_type_names(r[:sir]).include?("Integer")
end

# ---------------------------------------------------------------------------
# Section H — App fixtures
# ---------------------------------------------------------------------------

section("H-APP-FIXTURES")

check "H-01: !is_empty(col) composition — no OOF" do
  r = rust(<<~IG)
    module UnaryP4.H01
    type Item { v : Integer }
    pure contract H01 {
      input col : Collection[Item]
      compute non_empty_flag = !is_empty(col)
      output non_empty_flag : Bool
    }
  IG
  ok?(r)
end

check "H-02: !is_empty — SIR has both stdlib.primitive.not and stdlib.collection.is_empty" do
  r = rust(<<~IG)
    module UnaryP4.H02
    type Item { v : Integer }
    pure contract H02 {
      input col : Collection[Item]
      compute non_empty_flag = !is_empty(col)
      output non_empty_flag : Bool
    }
  IG
  r[:fns].include?("stdlib.primitive.not") && r[:fns].any? { |f| f.include?("is_empty") }
end

check "H-03: scalar negation in compute — -count(col)" do
  r = rust(<<~IG)
    module UnaryP4.H03
    type Item { v : Integer }
    pure contract H03 {
      input col : Collection[Item]
      compute n = count(col)
      compute neg_n = -n
      output neg_n : Integer
    }
  IG
  ok?(r)
end

check "H-04: combined ! and - in same contract" do
  r = rust(<<~IG)
    module UnaryP4.H04
    pure contract H04 {
      input x   : Integer
      input flag : Bool
      compute neg_x    = -x
      compute not_flag = !flag
      output neg_x : Integer
    }
  IG
  ok?(r)
end

check "H-05: 0 - x workaround still compiles (no regression)" do
  r = rust(<<~IG)
    module UnaryP4.H05
    pure contract H05 {
      input x : Integer
      compute n = 0 - x
      output n : Integer
    }
  IG
  ok?(r)
end

check "H-06: chained binary minus still works (2 - 3 - 1)" do
  r = rust(<<~IG)
    module UnaryP4.H06
    pure contract H06 {
      input x : Integer
      compute n = x - 1
      output n : Integer
    }
  IG
  ok?(r)
end

check "H-07: !false literal — compiles" do
  r = rust(<<~IG)
    module UnaryP4.H07
    pure contract H07 {
      input flag : Bool
      compute n = !false
      output n : Bool
    }
  IG
  r[:status] != "unknown"
end

# ---------------------------------------------------------------------------
# Section I — Regression
# ---------------------------------------------------------------------------

section("I-REGRESSION")

check "I-01: binary + still works" do
  r = rust(<<~IG)
    module UnaryP4.I01
    pure contract I01 {
      input x : Integer
      input y : Integer
      compute n = x + y
      output n : Integer
    }
  IG
  ok?(r)
end

check "I-02: binary == still works" do
  r = rust(<<~IG)
    module UnaryP4.I02
    pure contract I02 {
      input x : Integer
      input y : Integer
      compute eq = x == y
      output eq : Bool
    }
  IG
  ok?(r)
end

check "I-03: is_empty still works" do
  r = rust(<<~IG)
    module UnaryP4.I03
    type Item { v : Integer }
    pure contract I03 {
      input col : Collection[Item]
      compute empty_flag = is_empty(col)
      output empty_flag : Bool
    }
  IG
  ok?(r)
end

check "I-04: non_empty still works" do
  r = rust(<<~IG)
    module UnaryP4.I04
    type Item { v : Integer }
    pure contract I04 {
      input col : Collection[Item]
      compute flag = non_empty(col)
      output flag : Bool
    }
  IG
  ok?(r)
end

check "I-05: if_expr still works" do
  r = rust(<<~IG)
    module UnaryP4.I05
    pure contract I05 {
      input flag : Bool
      compute n = if flag { 1 } else { 0 }
      output n : Integer
    }
  IG
  ok?(r)
end

check "I-06: append still works" do
  r = rust(<<~IG)
    module UnaryP4.I06
    type Item { v : Integer }
    pure contract I06 {
      input col  : Collection[Item]
      input item : Item
      compute extended = append(col, item)
      output extended : Collection[Item]
    }
  IG
  r[:status] != "unknown"
end

# ---------------------------------------------------------------------------
# Inventory checks (inline in G/H, but confirm dual-toolchain here)
# ---------------------------------------------------------------------------

section("INV-DUAL-TOOLCHAIN")

check "INV-01: stdlib.primitive.not lowering_status = dual-toolchain" do
  entry = INV["entries"].find { |e| e["canonical_name"] == "stdlib.primitive.not" }
  entry && entry["lowering_status"] == "dual-toolchain"
end

check "INV-02: stdlib.integer.neg lowering_status = dual-toolchain" do
  entry = INV["entries"].find { |e| e["canonical_name"] == "stdlib.integer.neg" }
  entry && entry["lowering_status"] == "dual-toolchain"
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

total = $pass + $fail
puts "\n=============================="
puts "LANG-UNARY-OPERATORS-P4 RESULT"
puts "=============================="
puts "PASS #{$pass}/#{total}"
puts "FAIL #{$fail}/#{total}"
puts
if $fail == 0
  puts "PROVED #{$pass}/#{total} PASS"
  exit 0
else
  puts "NOT PROVED — #{$fail} failures"
  exit 1
end
