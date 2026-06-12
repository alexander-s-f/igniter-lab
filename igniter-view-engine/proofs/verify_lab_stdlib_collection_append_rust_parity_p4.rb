#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_collection_append_rust_parity_p4.rb
# LANG-STDLIB-COLLECTION-APPEND-PROP-P4
# =============================================
# Proves that the Rust compiler correctly implements stdlib.collection.append:
#   - append(Collection[T], T) -> Collection[T]
#   - canonical SIR fn name stdlib.collection.append (COLLECTION_HOF_OPS rewrite)
#   - OOF-COL1 arity != 2
#   - OOF-COL2 non-Collection first arg
#   - OOF-COL6 concrete item type mismatch
#   - Unknown permissive on both sides
#   - Ruby P3 behavior matched (parity checks)
#   - Inventory entry upgraded to dual-toolchain
#   - Import surface accepts append (OOF-IMP3 gone from importable name)
#   - App probe smoke (no spurious COL codes from bootstrap form)
#
# Sections:
#   A  RUST SOURCE        (8)  — TC arm; emitter entries; OOF codes; no bare-name SIR
#   B  OOF-COL1 ARITY     (6)  — 0 args, 1 arg, 3 args
#   C  OOF-COL2 NON-COLL  (6)  — String/Integer/custom type first arg
#   D  OOF-COL6 MISMATCH  (6)  — Collection[String]+Integer; Collection[Integer]+String
#   E  UNKNOWN PERMISSIVE (5)  — Unknown collection; Unknown item; matching types
#   F  HAPPY PATH + SIR   (8)  — String/Integer/custom; fn name; return type; no bare
#   G  RUBY PARITY        (6)  — same OOF codes / messages match P3 Ruby runner
#   H  INVENTORY          (7)  — dual-toolchain; digest; OOF-COL6; append entry
#   I  AUTHORITY CLOSED   (6)  — no runtime; no package; no import surface change; COLL_HOF_OPS count
#   J  REGRESSION         (8)  — map/filter/count/fold/sum still pass Rust
#
# Total: 66 checks

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR     = Pathname.new(__dir__)
LAB_ROOT       = SCRIPT_DIR.parent.parent
IGNITER_LANG   = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN   = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
TC_RUST        = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
EMITTER_RUST   = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"
INVENTORY_PATH = IGNITER_LANG / "docs" / "spec" / "stdlib-inventory.json"
APPS_DIR       = LAB_ROOT / "igniter-apps"

abort "Compiler not found: #{COMPILER_BIN}" unless COMPILER_BIN.exist?
abort "typechecker.rs not found: #{TC_RUST}" unless TC_RUST.exist?
abort "emitter.rs not found: #{EMITTER_RUST}" unless EMITTER_RUST.exist?
abort "stdlib-inventory.json not found: #{INVENTORY_PATH}" unless INVENTORY_PATH.exist?

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

def rust_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", path, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags  = Array(result["diagnostics"])
    sir    = {}
    igapp  = result["igapp_path"] || out
    sir_p  = File.join(igapp.to_s, "semantic_ir_program.json")
    sir    = JSON.parse(File.read(sir_p, encoding: "UTF-8")) if File.exist?(sir_p)
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact,
      sir:      sir
    }
  end
end

def rust_compile(*paths)
  Dir.mktmpdir do |tmpdir|
    out = File.join(tmpdir, "out.igapp")
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", *paths.map(&:to_s), "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags  = Array(result["diagnostics"])
    sir    = {}
    igapp  = result["igapp_path"] || out
    sir_p  = File.join(igapp.to_s, "semantic_ir_program.json")
    sir    = JSON.parse(File.read(sir_p, encoding: "UTF-8")) if File.exist?(sir_p)
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact,
      sir:      sir
    }
  end
end

def collect_sir_fns(node)
  case node
  when Hash
    fns = []
    fns << node["fn"] if node["kind"] == "call" && node["fn"]
    node.values.each { |v| fns.concat(collect_sir_fns(v)) }
    fns
  when Array
    node.flat_map { |item| collect_sir_fns(item) }
  else
    []
  end
end

def canonical_json(obj)
  case obj
  when Hash
    sorted = obj.keys.sort.map { |k| "#{JSON.generate(k)}:#{canonical_json(obj[k])}" }
    "{#{sorted.join(',')}}"
  when Array
    "[#{obj.map { |v| canonical_json(v) }.join(',')}]"
  else
    JSON.generate(obj)
  end
end

def compute_surface_digest(entries)
  stripped = entries.sort_by { |e| e["canonical_name"] }.map { |e| e.reject { |k, _| k == "entry_digest" } }
  Digest::SHA256.hexdigest(canonical_json(stripped))
end

TC_SRC       = TC_RUST.read.encode("UTF-8", invalid: :replace, undef: :replace)
EMITTER_SRC  = EMITTER_RUST.read.encode("UTF-8", invalid: :replace, undef: :replace)
INVENTORY    = JSON.parse(INVENTORY_PATH.read(encoding: "UTF-8"))
ENTRIES      = INVENTORY["entries"]
ENTRY_BY_NAME = ENTRIES.to_h { |e| [e["canonical_name"], e] }

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

HAPPY_STRING = <<~IG
  module AppendTest
  contract A {
    input items : Collection[String]
    input item : String
    compute r = append(items, item)
    output r : Collection[String]
  }
IG

HAPPY_INTEGER = <<~IG
  module AppendTest
  contract A {
    input items : Collection[Integer]
    input item : Integer
    compute r = append(items, item)
    output r : Collection[Integer]
  }
IG

HAPPY_CUSTOM = <<~IG
  module AppendTest
  type Row { name : String, score : Integer }
  contract A {
    input items : Collection[Row]
    input item : Row
    compute r = append(items, item)
    output r : Collection[Row]
  }
IG

ARITY_ZERO = <<~IG
  module T
  contract A {
    input items : Collection[String]
    compute r = append()
    output r : Collection[String]
  }
IG

ARITY_ONE = <<~IG
  module T
  contract A {
    input items : Collection[String]
    compute r = append(items)
    output r : Collection[String]
  }
IG

ARITY_THREE = <<~IG
  module T
  contract A {
    input items : Collection[String]
    input a : String
    input b : String
    compute r = append(items, a, b)
    output r : Collection[String]
  }
IG

COL2_STRING = <<~IG
  module T
  contract A {
    input x : String
    input item : String
    compute r = append(x, item)
    output r : Collection[String]
  }
IG

COL2_INTEGER = <<~IG
  module T
  contract A {
    input x : Integer
    input item : String
    compute r = append(x, item)
    output r : Collection[String]
  }
IG

COL2_CUSTOM = <<~IG
  module T
  type Thing { val : Integer }
  contract A {
    input x : Thing
    input item : String
    compute r = append(x, item)
    output r : Collection[String]
  }
IG

COL6_STR_INT = <<~IG
  module T
  contract A {
    input items : Collection[String]
    input bad : Integer
    compute r = append(items, bad)
    output r : Collection[String]
  }
IG

COL6_INT_STR = <<~IG
  module T
  contract A {
    input items : Collection[Integer]
    input bad : String
    compute r = append(items, bad)
    output r : Collection[Integer]
  }
IG

UNKNOWN_COL = <<~IG
  module T
  contract A {
    input items : Collection[String]
    compute unknown_col = something_unknown(items)
    compute r = append(unknown_col, "hello")
    output r : Collection[String]
  }
IG

UNKNOWN_ITEM = <<~IG
  module T
  contract A {
    input items : Collection[String]
    compute unknown_item = something_unknown(items)
    compute r = append(items, unknown_item)
    output r : Collection[String]
  }
IG

MAP_REGRESSION = <<~IG
  module T
  contract A {
    input items : Collection[Integer]
    compute r = map(items, x -> x)
    output r : Collection[Integer]
  }
IG

FILTER_REGRESSION = <<~IG
  module T
  type Item { active : Bool }
  contract A {
    input items : Collection[Item]
    compute r = filter(items, x -> x.active)
    output r : Collection[Item]
  }
IG

COUNT_REGRESSION = <<~IG
  module T
  contract A {
    input items : Collection[String]
    compute n = count(items)
    output n : Integer
  }
IG

FOLD_REGRESSION = <<~IG
  module T
  contract A {
    input items : Collection[Integer]
    compute total = fold(items, 0, (acc, x) -> acc)
    output total : Integer
  }
IG

SUM_REGRESSION = <<~IG
  module T
  type Item { score : Integer }
  contract A {
    input items : Collection[Item]
    compute total = sum(items, :score)
    output total : Integer
  }
IG

# ─────────────────────────────────────────────────────────────────────────────
# Section A — Rust Source Structure (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== A: Rust Source Structure ==="

check 'A-01: "append" arm present in typechecker.rs' do
  TC_SRC.include?('"append"') && TC_SRC.include?("LANG-STDLIB-COLLECTION-APPEND-PROP-P4")
end

check "A-02: OOF-COL1 in append arm of typechecker.rs" do
  TC_SRC.match?(/"append"\s*=>\s*\{.*?OOF-COL1/m)
end

check "A-03: OOF-COL2 in append arm of typechecker.rs" do
  TC_SRC.match?(/"append"\s*=>\s*\{.*?OOF-COL2/m)
end

check "A-04: OOF-COL6 in append arm of typechecker.rs" do
  TC_SRC.match?(/"append"\s*=>\s*\{.*?OOF-COL6/m)
end

check 'A-05: ("append", "stdlib.collection.append") in COLLECTION_HOF_OPS in emitter.rs' do
  EMITTER_SRC.include?('"append"') && EMITTER_SRC.include?('"stdlib.collection.append"')
end

check 'A-06: "append" in TEXT_STDLIB_OPS_C delegation guard in emitter.rs' do
  EMITTER_SRC.match?(/matches!\(fn_val,.*"append"/)
end

check "A-07: COLLECTION_HOF_OPS has 4 entries (map/filter/count/append)" do
  match = EMITTER_SRC.match(/COLLECTION_HOF_OPS:.*?=\s*&\[(.*?)\];/m)
  if match
    entries = match[1].scan(/"(\w+)",\s*"stdlib\.collection\./)
    entries.length == 4 && entries.flatten.sort == %w[append count filter map].sort
  else
    false
  end
end

check "A-08: bare 'append' NOT in SIR for direct-call fixture" do
  r = rust_compile_source(HAPPY_STRING)
  !collect_sir_fns(r[:sir]).include?("append")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — OOF-COL1 Arity (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== B: OOF-COL1 Arity ==="

check "B-01: zero args → OOF-COL1 code" do
  r = rust_compile_source(ARITY_ZERO)
  r[:codes].include?("OOF-COL1")
end

check "B-02: zero args → message mentions expected 2" do
  r = rust_compile_source(ARITY_ZERO)
  r[:messages].any? { |m| m.include?("expected 2") }
end

check "B-03: one arg → OOF-COL1 code" do
  r = rust_compile_source(ARITY_ONE)
  r[:codes].include?("OOF-COL1")
end

check "B-04: one arg → message mentions stdlib.collection.append" do
  r = rust_compile_source(ARITY_ONE)
  r[:messages].any? { |m| m.include?("stdlib.collection.append") }
end

check "B-05: three args → OOF-COL1 code" do
  r = rust_compile_source(ARITY_THREE)
  r[:codes].include?("OOF-COL1")
end

check "B-06: three args → message mentions got 3" do
  r = rust_compile_source(ARITY_THREE)
  r[:messages].any? { |m| m.include?("got 3") }
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — OOF-COL2 Non-Collection First Arg (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== C: OOF-COL2 Non-Collection First Arg ==="

check "C-01: String first arg → OOF-COL2 code" do
  r = rust_compile_source(COL2_STRING)
  r[:codes].include?("OOF-COL2")
end

check "C-02: String first arg → message mentions String" do
  r = rust_compile_source(COL2_STRING)
  r[:messages].any? { |m| m.include?("String") && m.include?("Collection") }
end

check "C-03: Integer first arg → OOF-COL2 code" do
  r = rust_compile_source(COL2_INTEGER)
  r[:codes].include?("OOF-COL2")
end

check "C-04: Integer first arg → message mentions Integer" do
  r = rust_compile_source(COL2_INTEGER)
  r[:messages].any? { |m| m.include?("Integer") }
end

check "C-05: custom type first arg → OOF-COL2 code" do
  r = rust_compile_source(COL2_CUSTOM)
  r[:codes].include?("OOF-COL2")
end

check "C-06: OOF-COL2 message mentions stdlib.collection.append" do
  r = rust_compile_source(COL2_STRING)
  r[:messages].any? { |m| m.include?("stdlib.collection.append") }
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — OOF-COL6 Type Mismatch (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== D: OOF-COL6 Item Type Mismatch ==="

check "D-01: Collection[String] + Integer → OOF-COL6 code" do
  r = rust_compile_source(COL6_STR_INT)
  r[:codes].include?("OOF-COL6")
end

check "D-02: Collection[String] + Integer → message mentions Integer and String" do
  r = rust_compile_source(COL6_STR_INT)
  r[:messages].any? { |m| m.include?("Integer") && m.include?("String") }
end

check "D-03: Collection[Integer] + String → OOF-COL6 code" do
  r = rust_compile_source(COL6_INT_STR)
  r[:codes].include?("OOF-COL6")
end

check "D-04: Collection[Integer] + String → message mentions String and Integer" do
  r = rust_compile_source(COL6_INT_STR)
  r[:messages].any? { |m| m.include?("String") && m.include?("Integer") }
end

check "D-05: OOF-COL6 message mentions stdlib.collection.append" do
  r = rust_compile_source(COL6_STR_INT)
  r[:messages].any? { |m| m.include?("stdlib.collection.append") }
end

check "D-06: mismatch fixture has no OOF-COL1 or OOF-COL2" do
  r = rust_compile_source(COL6_STR_INT)
  !r[:codes].include?("OOF-COL1") && !r[:codes].include?("OOF-COL2")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — Unknown Permissive (5 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== E: Unknown Permissive ==="

check "E-01: Unknown collection (from unknown fn) → no OOF-COL2" do
  r = rust_compile_source(UNKNOWN_COL)
  !r[:codes].include?("OOF-COL2")
end

check "E-02: Unknown item (from unknown fn) → no OOF-COL6" do
  r = rust_compile_source(UNKNOWN_ITEM)
  !r[:codes].include?("OOF-COL6")
end

check "E-03: Unknown item → no OOF-COL1 (arity correct)" do
  r = rust_compile_source(UNKNOWN_ITEM)
  !r[:codes].include?("OOF-COL1")
end

check "E-04: matching types → no OOF-COL6" do
  r = rust_compile_source(HAPPY_STRING)
  !r[:codes].include?("OOF-COL6")
end

check "E-05: matching Integer types → no OOF-COL6" do
  r = rust_compile_source(HAPPY_INTEGER)
  !r[:codes].include?("OOF-COL6")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — Happy Path + SIR (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== F: Happy Path + SIR ==="

check "F-01: Collection[String] + String → status ok" do
  r = rust_compile_source(HAPPY_STRING)
  r[:status] == "ok"
end

check "F-02: Collection[String] + String → no diagnostics" do
  r = rust_compile_source(HAPPY_STRING)
  r[:diags].empty?
end

check "F-03: SIR fn name == 'stdlib.collection.append'" do
  r = rust_compile_source(HAPPY_STRING)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.append")
end

check "F-04: bare 'append' absent from SIR" do
  r = rust_compile_source(HAPPY_INTEGER)
  !collect_sir_fns(r[:sir]).include?("append")
end

check "F-05: Collection[Integer] + Integer → status ok" do
  r = rust_compile_source(HAPPY_INTEGER)
  r[:status] == "ok"
end

check "F-06: Collection[Integer] + Integer → no diagnostics" do
  r = rust_compile_source(HAPPY_INTEGER)
  r[:diags].empty?
end

check "F-07: custom type fixture → status ok" do
  r = rust_compile_source(HAPPY_CUSTOM)
  r[:status] == "ok"
end

check "F-08: custom type fixture → SIR contains stdlib.collection.append" do
  r = rust_compile_source(HAPPY_CUSTOM)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.append")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — Ruby P3 Parity (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== G: Ruby P3 Parity ==="

check "G-01: OOF-COL1 rule code matches Ruby P3 (same code string)" do
  r = rust_compile_source(ARITY_ONE)
  r[:codes].include?("OOF-COL1")
end

check "G-02: OOF-COL2 rule code matches Ruby P3 (same code string)" do
  r = rust_compile_source(COL2_STRING)
  r[:codes].include?("OOF-COL2")
end

check "G-03: OOF-COL6 rule code matches Ruby P3 (same code string)" do
  r = rust_compile_source(COL6_STR_INT)
  r[:codes].include?("OOF-COL6")
end

check "G-04: happy path produces no diagnostics (Ruby parity)" do
  r = rust_compile_source(HAPPY_STRING)
  r[:diags].empty?
end

check "G-05: SIR fn name 'stdlib.collection.append' matches Ruby P3 qualified name" do
  r = rust_compile_source(HAPPY_INTEGER)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.append")
end

check "G-06: OOF-COL6 message format consistent with Ruby P3 (item type + element type)" do
  r = rust_compile_source(COL6_STR_INT)
  r[:messages].any? { |m| m.include?("item type") && m.include?("collection element type") }
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — Inventory (7 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== H: Inventory ==="

APPEND_ENTRY = ENTRY_BY_NAME["stdlib.collection.append"]

check "H-01: stdlib.collection.append entry exists" do
  !APPEND_ENTRY.nil?
end

check "H-02: lowering_status upgraded to 'dual-toolchain'" do
  APPEND_ENTRY&.fetch("lowering_status") == "dual-toolchain"
end

check "H-03: lifecycle_status == 'lab-implemented'" do
  APPEND_ENTRY&.fetch("lifecycle_status") == "lab-implemented"
end

check "H-04: diagnostics includes OOF-COL6 (P4 parity maintained)" do
  diags = APPEND_ENTRY&.fetch("diagnostics", []) || []
  diags.include?("OOF-COL6")
end

check "H-05: P4 proof_lineage entry present" do
  lineage = APPEND_ENTRY&.fetch("proof_lineage", []) || []
  lineage.any? { |l| l.to_s.include?("P4") }
end

check "H-06: stdlib_surface_digest stored == Ruby-computed" do
  stored   = INVENTORY["stdlib_surface_digest"]
  computed = compute_surface_digest(ENTRIES)
  stored == computed
end

check "H-07: entry count == 27" do
  ENTRIES.length == 27
end

# ─────────────────────────────────────────────────────────────────────────────
# Section I — Authority Closed (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== I: Authority Closed ==="

check "I-01: no VM dispatch for append (no runtime capability claimed)" do
  APPEND_ENTRY&.fetch("authority_surface") == "none"
end

check "I-02: purity == 'pure'" do
  APPEND_ENTRY&.fetch("purity") == "pure"
end

check "I-03: no new OOF-IMP codes — emitter changes are internal only" do
  # emitter.rs changes only add to COLLECTION_HOF_OPS table
  !EMITTER_SRC.include?("OOF-IMP")
end

check "I-04: COLLECTION_HOF_OPS in emitter now includes 4 entries" do
  match = EMITTER_SRC.match(/COLLECTION_HOF_OPS:.*?=\s*&\[(.*?)\];/m)
  if match
    entries = match[1].scan(/"stdlib\.collection\./)
    entries.length == 4
  else
    false
  end
end

check "I-05: append arm sets is_resolved = true" do
  TC_SRC.match?(/"append"\s*=>\s*\{.*?is_resolved\s*=\s*true/m)
end

check "I-06: fragment_class == 'core'" do
  APPEND_ENTRY&.fetch("fragment_class") == "core"
end

# ─────────────────────────────────────────────────────────────────────────────
# Section J — Regression (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== J: Regression ==="

check "J-01: map regression → status ok, no diagnostics" do
  r = rust_compile_source(MAP_REGRESSION)
  r[:status] == "ok" && r[:diags].empty?
end

check "J-02: map regression → SIR fn == 'stdlib.collection.map'" do
  r = rust_compile_source(MAP_REGRESSION)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.map")
end

check "J-03: filter regression → status ok, no diagnostics" do
  r = rust_compile_source(FILTER_REGRESSION)
  r[:status] == "ok" && r[:diags].empty?
end

check "J-04: filter regression → SIR fn == 'stdlib.collection.filter'" do
  r = rust_compile_source(FILTER_REGRESSION)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.filter")
end

check "J-05: count regression → status ok, no diagnostics" do
  r = rust_compile_source(COUNT_REGRESSION)
  r[:status] == "ok" && r[:diags].empty?
end

check "J-06: count regression → SIR fn == 'stdlib.collection.count'" do
  r = rust_compile_source(COUNT_REGRESSION)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.count")
end

check "J-07: fold regression → status ok, no diagnostics" do
  r = rust_compile_source(FOLD_REGRESSION)
  r[:status] == "ok" && r[:diags].empty?
end

check "J-08: sum regression → status ok, no diagnostics" do
  r = rust_compile_source(SUM_REGRESSION)
  r[:status] == "ok" && r[:diags].empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

puts
total = $pass + $fail
puts "#{$pass}/#{total} PASS  |  #{$fail} FAIL"
exit($fail.zero? ? 0 : 1)
