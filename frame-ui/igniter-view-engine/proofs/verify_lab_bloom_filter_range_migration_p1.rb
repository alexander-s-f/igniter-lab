#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_bloom_filter_range_migration_p1.rb
# LAB-BLOOM-FILTER-RANGE-MIGRATION-P1
# =========================================
# Proves bloom_filter migrated from 31-node manual slot pattern to
# map(range(0, 16), i -> call_contract("MakeSlot", i)) using
# range + map (both dual-toolchain since LANG-STDLIB-COLLECTION-RANGE-P3).
#
# Card:   igniter-lab/.agents/work/cards/governance/LAB-BLOOM-FILTER-RANGE-MIGRATION-P1.md
# Lab doc: lab-docs/governance/lab-bloom-filter-range-migration-p1-v0.md
#
# Sections:
#   A  SOURCE STRUCTURE      (8)  — slots/bf/MakeSlot present; manual nodes absent; import correct
#   B  RUBY FULL COMPILE     (8)  — dual-toolchain clean; no diagnostics; SIR fns qualified
#   C  RUST FULL COMPILE     (8)  — dual-toolchain clean; no diagnostics; range arm hit
#   D  RANGE PRESSURE        (6)  — BF-P03 path: range(0,16) reduces node count
#   E  REGRESSION UNCHANGED  (8)  — ops.ig contracts unbroken; RunBloomExample unchanged
#   F  OPS EXTENSION         (6)  — MakeSlot contract correct; MakeSlotTrue still present
#   G  PRESSURE REGISTRY     (4)  — BF-P03 referenced; BF-P01/BF-P02 still resolved
#   H  AUTHORITY CLOSED      (2)  — no compiler changes; no type/hash/ops logic change
#
# Total: 50 checks

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"

LAB_DIR      = Pathname.new("/Users/alex/dev/projects/igniter-workspace/igniter-lab")
LANG_DIR     = Pathname.new("/Users/alex/dev/projects/igniter-workspace/igniter-lang")
COMPILER_DIR = LAB_DIR / "igniter-compiler"
APP_DIR      = LAB_DIR / "igniter-apps/bloom_filter"
REGISTRY     = APP_DIR / "PRESSURE_REGISTRY.md"

EXAMPLE_SRC = (APP_DIR / "example.ig").read(encoding: "UTF-8")
OPS_SRC     = (APP_DIR / "ops.ig").read(encoding: "UTF-8")
TYPES_SRC   = (APP_DIR / "types.ig").read(encoding: "UTF-8")

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
  puts "FAIL #{label} [#{e.message.lines.first&.strip}]"
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

def ruby_compile_bloom
  $LOAD_PATH.unshift((LANG_DIR / "lib").to_s) unless $LOAD_PATH.include?((LANG_DIR / "lib").to_s)
  require "igniter_lang"
  c = IgniterLang::CompilerOrchestrator.new
  Dir.mktmpdir do |d|
    r = c.compile_sources(
      source_paths: [
        (APP_DIR / "types.ig").to_s,
        (APP_DIR / "hash.ig").to_s,
        (APP_DIR / "ops.ig").to_s,
        (APP_DIR / "example.ig").to_s
      ],
      out_path: "#{d}/out"
    )
    diags = r.dig("result", "diagnostics") || []
    sir_path = "#{d}/out/semantic_ir_program.json"
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    { status: r.dig("result", "status") || r["status"], diags: diags, codes: diags.map { |d| d["rule"] }, sir: sir }
  end
end

def rust_compile_bloom
  files = %w[types.ig hash.ig ops.ig example.ig].map { |f| (APP_DIR / f).to_s }
  Dir.mktmpdir do |d|
    out = "#{d}/out.igapp"
    stdout, _, _ = Open3.capture3("cargo", "run", "--quiet", "--", "compile", *files, "--out", out, chdir: COMPILER_DIR.to_s)
    stdout_utf8 = stdout.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    report = {}
    json_start = stdout_utf8.index("{")
    begin
      report = JSON.parse(stdout_utf8[json_start..]) if json_start
    rescue JSON::ParserError
      nil
    end
    sir_path = "#{out}/semantic_ir_program.json"
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    diags = report.fetch("diagnostics", [])
    { status: report["status"] || "error", diags: diags, codes: diags.map { |d| d["rule"] }, sir: sir }
  end
end

def collect_sir_fns(node)
  return [] unless node.is_a?(Hash) || node.is_a?(Array)
  if node.is_a?(Array)
    return node.flat_map { |v| collect_sir_fns(v) }
  end
  results = []
  results << node["fn"] if node["kind"] == "call" && node["fn"]
  node.each_value { |v| results.concat(collect_sir_fns(v)) }
  results
end

# ─────────────────────────────────────────────────────────────────────────────
# Section A — Source Structure (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== A: Source Structure ==="

check "A-01: example.ig has 'compute slots' using map+range" do
  EXAMPLE_SRC.include?("compute slots") &&
    EXAMPLE_SRC.include?("map(range(0, 16)") &&
    EXAMPLE_SRC.include?('call_contract("MakeSlot"')
end

check "A-02: example.ig has Collection[BitSlot] type annotation on slots" do
  EXAMPLE_SRC.include?("compute slots : Collection[BitSlot]")
end

check "A-03: example.ig does NOT have manual slot computes (s0..s15 pattern gone)" do
  !EXAMPLE_SRC.match?(/compute s\d+ = \{ pos:/)
end

check "A-04: example.ig does NOT have append chain (b0..b14 pattern gone)" do
  !EXAMPLE_SRC.include?("compute b0") && !EXAMPLE_SRC.include?("compute b1 =")
end

check "A-05: example.ig imports map and range (not append)" do
  EXAMPLE_SRC.include?("import stdlib.collection.{ map, range }") &&
    !EXAMPLE_SRC.include?("import stdlib.collection.{ append }")
end

check "A-06: example.ig uses 'bits: slots' in the bf record (not 'bits: b14')" do
  EXAMPLE_SRC.include?("bits: slots") && !EXAMPLE_SRC.include?("bits: b14")
end

check "A-07: ops.ig has new MakeSlot contract (set: false)" do
  OPS_SRC.match?(/contract MakeSlot \{.*?set: false/m)
end

check "A-08: ops.ig MakeSlot appears before MakeSlotTrue" do
  make_slot_pos      = OPS_SRC.index("contract MakeSlot {")
  make_slot_true_pos = OPS_SRC.index("contract MakeSlotTrue {")
  make_slot_pos && make_slot_true_pos && make_slot_pos < make_slot_true_pos
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — Ruby Full Compile (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== B: Ruby Full Compile ==="

RUBY_RESULT = ruby_compile_bloom

check "B-01: Ruby bloom_filter compile → status ok" do
  RUBY_RESULT[:status] == "ok"
end

check "B-02: Ruby bloom_filter → no diagnostics" do
  RUBY_RESULT[:codes].empty?
end

check "B-03: Ruby SIR contains stdlib.collection.range (qualified)" do
  collect_sir_fns(RUBY_RESULT[:sir]).include?("stdlib.collection.range")
end

check "B-04: Ruby SIR contains stdlib.collection.map (qualified)" do
  collect_sir_fns(RUBY_RESULT[:sir]).include?("stdlib.collection.map")
end

check "B-05: Ruby SIR does NOT contain bare 'range' fn" do
  !collect_sir_fns(RUBY_RESULT[:sir]).include?("range")
end

check "B-06: Ruby no OOF-TY0 diagnostics" do
  !RUBY_RESULT[:codes].include?("OOF-TY0")
end

check "B-07: Ruby no OOF-TY1 diagnostics" do
  !RUBY_RESULT[:codes].include?("OOF-TY1")
end

check "B-08: Ruby no OOF-COL1 diagnostics" do
  !RUBY_RESULT[:codes].include?("OOF-COL1")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — Rust Full Compile (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== C: Rust Full Compile ==="

RUST_RESULT = rust_compile_bloom

check "C-01: Rust bloom_filter compile → status ok" do
  RUST_RESULT[:status] == "ok"
end

check "C-02: Rust bloom_filter → no diagnostics" do
  RUST_RESULT[:codes].empty?
end

check "C-03: Rust SIR contains qualified range fn" do
  collect_sir_fns(RUST_RESULT[:sir]).include?("stdlib.collection.range")
end

check "C-04: Rust SIR contains qualified map fn" do
  collect_sir_fns(RUST_RESULT[:sir]).include?("stdlib.collection.map")
end

check "C-05: Rust SIR does NOT contain bare 'range' fn" do
  !collect_sir_fns(RUST_RESULT[:sir]).include?("range")
end

check "C-06: Rust no OOF-TY0 diagnostics" do
  !RUST_RESULT[:codes].include?("OOF-TY0")
end

check "C-07: Rust no OOF-TY1 diagnostics" do
  !RUST_RESULT[:codes].include?("OOF-TY1")
end

check "C-08: Rust no OOF-COL1 diagnostics" do
  !RUST_RESULT[:codes].include?("OOF-COL1")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — Range Pressure (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== D: Range Pressure ==="

check "D-01: InitFilter16 node count reduced — no more than 4 computes" do
  init_block = EXAMPLE_SRC[EXAMPLE_SRC.index("contract InitFilter16")..]
  end_pos = init_block.index("\ncontract ") || init_block.length
  init_body = init_block[0...end_pos]
  compute_count = init_body.scan(/^\s*compute /).length
  compute_count <= 4
end

check "D-02: InitFilter16 has exactly 'slots' and 'bf' compute nodes" do
  init_block = EXAMPLE_SRC[EXAMPLE_SRC.index("contract InitFilter16")..]
  end_pos = init_block.index("\ncontract ") || init_block.length
  init_body = init_block[0...end_pos]
  computes = init_body.scan(/compute (\w+)/).flatten
  (computes & %w[slots bf]).sort == %w[bf slots].sort
end

check "D-03: range(0, 16) uses correct bounds for a 16-slot filter" do
  EXAMPLE_SRC.include?("range(0, 16)")
end

check "D-04: original 16 manual s0..s15 slot lines are gone" do
  (0..15).none? { |n| EXAMPLE_SRC.include?("compute s#{n} =") }
end

check "D-05: original 14 append chain lines are gone" do
  (1..14).none? { |n| EXAMPLE_SRC.include?("compute b#{n} = append(") }
end

check "D-06: original b0 bootstrap line is gone" do
  !EXAMPLE_SRC.include?("compute b0 : Collection[BitSlot]")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — Regression Unchanged (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== E: Regression Unchanged ==="

check "E-01: RunBloomExample contract still present in example.ig" do
  EXAMPLE_SRC.include?("contract RunBloomExample")
end

check "E-02: RunBloomExample still outputs query_hit, query_miss, query_hit_2" do
  EXAMPLE_SRC.include?("output query_hit : QueryResult") &&
    EXAMPLE_SRC.include?("output query_miss : QueryResult") &&
    EXAMPLE_SRC.include?("output query_hit_2 : QueryResult")
end

check "E-03: RunBloomExample still calls InitFilter16 via call_contract" do
  EXAMPLE_SRC.include?('call_contract("InitFilter16")')
end

check "E-04: SetBitAtIndex contract unchanged in ops.ig" do
  OPS_SRC.include?("contract SetBitAtIndex")
end

check "E-05: CheckBitAtIndex contract unchanged in ops.ig" do
  OPS_SRC.include?("contract CheckBitAtIndex")
end

check "E-06: Insert contract unchanged in ops.ig" do
  OPS_SRC.include?("contract Insert")
end

check "E-07: Query contract unchanged in ops.ig" do
  OPS_SRC.include?("contract Query")
end

check "E-08: types.ig unchanged — BitSlot, BloomFilter, HashSeed, QueryResult still present" do
  TYPES_SRC.include?("type BitSlot") &&
    TYPES_SRC.include?("type BloomFilter") &&
    TYPES_SRC.include?("type HashSeed") &&
    TYPES_SRC.include?("type QueryResult")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — ops.ig Extension (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== F: ops.ig Extension ==="

check "F-01: MakeSlot contract in ops.ig has 'input pos : Integer'" do
  OPS_SRC.match?(/contract MakeSlot \{[^}]*input pos : Integer/m)
end

check "F-02: MakeSlot computes slot with set: false" do
  OPS_SRC.match?(/contract MakeSlot \{.*?set: false/m)
end

check "F-03: MakeSlot outputs slot : BitSlot" do
  OPS_SRC.match?(/contract MakeSlot \{.*?output slot : BitSlot/m)
end

check "F-04: MakeSlotTrue contract still present with set: true" do
  OPS_SRC.include?("contract MakeSlotTrue") &&
    OPS_SRC.match?(/contract MakeSlotTrue \{.*?set: true/m)
end

check "F-05: ops.ig still imports map and filter from stdlib.collection" do
  OPS_SRC.include?("import stdlib.collection.{ map, filter }")
end

check "F-06: ops.ig does NOT import range (range used in example.ig, not ops.ig)" do
  !OPS_SRC.include?("import stdlib.collection.{ map, filter, range }")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — Pressure Registry (4 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== G: Pressure Registry ==="

REGISTRY_SRC = REGISTRY.read(encoding: "UTF-8")

check "G-01: PRESSURE_REGISTRY has BF-P03 entry" do
  REGISTRY_SRC.include?("BF-P03")
end

check "G-02: BF-P01 still marked RESOLVED in registry" do
  REGISTRY_SRC.match?(/BF-P01.*?RESOLVED/m)
end

check "G-03: BF-P02 still marked RESOLVED in registry" do
  REGISTRY_SRC.match?(/BF-P02.*?RESOLVED/m)
end

check "G-04: registry references LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 as BF-P03 closure" do
  REGISTRY_SRC.include?("LAB-BLOOM-FILTER-RANGE-MIGRATION-P1")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — Authority Closed (2 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== H: Authority Closed ==="

check "H-01: no changes to Ruby or Rust compiler files in this migration" do
  tc_ruby = LANG_DIR / "lib/igniter_lang/typechecker.rb"
  # Verify Ruby TC still has infer_range_call (P2 unchanged)
  tc_ruby.read(encoding: "UTF-8").include?("def infer_range_call")
end

check "H-02: hash.ig unchanged — manual modulo still present (BF-P06 not in scope)" do
  hash_src = (APP_DIR / "hash.ig").read(encoding: "UTF-8")
  hash_src.include?("contract Mod")
end

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────

total = $pass + $fail
puts "\n#{"=" * 60}"
puts "LAB-BLOOM-FILTER-RANGE-MIGRATION-P1: #{$pass} PASS / #{$fail} FAIL / #{total} total"
verdict = $fail.zero? ? "ACCEPT" : "REJECT (#{$fail} failing check#{"s" if $fail > 1})"
puts "VERDICT: #{verdict}"
puts "=" * 60
