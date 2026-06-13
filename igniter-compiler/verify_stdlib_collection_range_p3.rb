#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_stdlib_collection_range_p3.rb
# LANG-STDLIB-COLLECTION-RANGE-P3
# ================================
# Proves Rust TC parity for stdlib.collection.range:
#   - range arm emits OOF-COL1 on arity != 2
#   - Rust emitter qualifies fn -> stdlib.collection.range
#   - inventory dual-toolchain
#   - Ruby P2 behavior unchanged
#
# Card:   igniter-lang/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-RANGE-P3.md
# Packet: igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-RANGE-P3-rust-parity-proof-v0.md
#
# Sections:
#   A  INVENTORY            (6)  — dual-toolchain; digest stable; proof_lineage has P3
#   B  RUST TC HAPPY PATH  (8)  — range(0,5); range(a,b); range(3,6); Collection[Integer]; qualified SIR fn
#   C  RUST OOF-COL1       (6)  — 0-arg; 1-arg (message); 3-arg; code; no cascade
#   D  RUST TOTALITY       (4)  — range(5,5); range(5,3); both ok
#   E  MAP(RANGE) PIPELINE (6)  — map(range(0,n)) ok; SIR has range + map qualified
#   F  RUBY P2 UNCHANGED   (8)  — run P2 proof as regression suite
#   G  SOURCE STRUCTURE    (6)  — Rust TC arm has OOF-COL1; emitter COLLECTION_HOF_OPS has range
#   H  AUTHORITY CLOSED    (6)  — no parser changes; no Ruby changes; bloom untouched; fast-path unchanged
#
# Total: 50 checks

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR   = Pathname.new(__dir__)
COMPILER_DIR = SCRIPT_DIR
LANG_DIR     = Pathname.new("/Users/alex/dev/projects/igniter-workspace/igniter-lang")
LAB_DIR      = Pathname.new("/Users/alex/dev/projects/igniter-workspace/igniter-lab")
STDLIB_INV   = LANG_DIR / "docs/spec/stdlib-inventory.json"
RUST_TC      = COMPILER_DIR / "src/typechecker.rs"
RUST_EM      = COMPILER_DIR / "src/emitter.rs"
TC_RUBY      = LANG_DIR / "lib/igniter_lang/typechecker.rb"
BLOOM_SRC    = LAB_DIR / "igniter-apps/bloom_filter/example.ig"

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

def rust_compile(src, extra_args: [])
  Dir.mktmpdir do |dir|
    path = File.join(dir, "test.ig")
    File.write(path, src)
    out  = File.join(dir, "out.igapp")
    stdout, _stderr, _status = Open3.capture3(
      "cargo", "run", "--quiet", "--", "compile", path, "--out", out,
      chdir: COMPILER_DIR.to_s
    )
    # The compiler prints the result JSON to stdout on both success and error.
    # On typecheck error (OOF), igapp is not written — parse stdout directly.
    # Force UTF-8 to handle cargo warning output with Unicode chars.
    stdout_utf8 = stdout.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    report = {}
    json_start = stdout_utf8.index("{")
    if json_start
      begin
        report = JSON.parse(stdout_utf8[json_start..])
      rescue JSON::ParserError
        nil
      end
    end
    sir_path = File.join(out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    diags = report.fetch("diagnostics", [])
    {
      status:   report["status"] || "error",
      diags:    diags,
      codes:    diags.map { |d| d["rule"].to_s },
      messages: diags.map { |d| d["message"].to_s },
      sir:      sir
    }
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

INVENTORY = JSON.parse(STDLIB_INV.read(encoding: "UTF-8"))
ENTRIES   = INVENTORY["entries"]
RANGE_ENTRY = ENTRIES.find { |e| e["canonical_name"] == "stdlib.collection.range" }
RUST_TC_SRC = RUST_TC.read(encoding: "UTF-8")
RUST_EM_SRC = RUST_EM.read(encoding: "UTF-8")
TC_RUBY_SRC = TC_RUBY.read(encoding: "UTF-8")

# ─────────────────────────────────────────────────────────────────────────────
# Section A — Inventory (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== A: Inventory ==="

check "A-01: stdlib.collection.range entry exists" do
  !RANGE_ENTRY.nil?
end

check "A-02: lowering_status = 'dual-toolchain'" do
  RANGE_ENTRY&.fetch("lowering_status") == "dual-toolchain"
end

check "A-03: proof_lineage includes P3 annotation" do
  RANGE_ENTRY&.fetch("proof_lineage", [])&.any? { |l| l.include?("P3") }
end

check "A-04: output_signature = 'Collection[Integer]'" do
  RANGE_ENTRY&.fetch("output_signature") == "Collection[Integer]"
end

check "A-05: diagnostics = ['OOF-COL1']" do
  RANGE_ENTRY&.fetch("diagnostics", []) == ["OOF-COL1"]
end

check "A-06: stdlib_surface_digest matches Ruby-computed digest" do
  stored   = INVENTORY["stdlib_surface_digest"]
  stripped = ENTRIES.sort_by { |e| e["canonical_name"] }.map { |e| e.reject { |k, _| k == "entry_digest" } }
  computed = Digest::SHA256.hexdigest(canonical_json(stripped))
  stored == computed
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — Rust TC Happy Path (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== B: Rust TC Happy Path ==="

check "B-01: range(0, 5) → ok, no diagnostics" do
  r = rust_compile(<<~IG)
    module RangeBasic
    contract RangeBasic {
      compute result = range(0, 5)
      output result : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "B-02: range(0, 5) → SIR fn = 'stdlib.collection.range'" do
  r = rust_compile(<<~IG)
    module RangeBasic
    contract RangeBasic {
      compute result = range(0, 5)
      output result : Collection[Integer]
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.range")
end

check "B-03: bare 'range' does NOT appear as SIR fn in standalone case" do
  r = rust_compile(<<~IG)
    module RangeBasic
    contract RangeBasic {
      compute result = range(0, 5)
      output result : Collection[Integer]
    }
  IG
  !collect_sir_fns(r[:sir]).include?("range")
end

check "B-04: range(start, stop) with input variables → ok" do
  r = rust_compile(<<~IG)
    module RangeVar
    contract RangeVar {
      input start : Integer
      input stop  : Integer
      compute result = range(start, stop)
      output result : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "B-05: range(start, stop) with vars → SIR fn qualified" do
  r = rust_compile(<<~IG)
    module RangeVar
    contract RangeVar {
      input start : Integer
      input stop  : Integer
      compute result = range(start, stop)
      output result : Collection[Integer]
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.range")
end

check "B-06: range(3, 6) non-zero start → ok, no diagnostics" do
  r = rust_compile(<<~IG)
    module RangeOffset
    contract RangeOffset {
      compute result = range(3, 6)
      output result : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "B-07: range(0, 5) → no OOF-TY1 at Collection[Integer] output boundary" do
  r = rust_compile(<<~IG)
    module RangeBasic
    contract RangeBasic {
      compute result = range(0, 5)
      output result : Collection[Integer]
    }
  IG
  !r[:codes].include?("OOF-TY1")
end

check "B-08: fold(range(0, 5), 0, (acc, x) -> acc) → ok" do
  r = rust_compile(<<~IG)
    module FoldOverRange
    contract FoldOverRange {
      compute total = fold(range(0, 5), 0, (acc, x) -> acc)
      output total : Integer
    }
  IG
  r[:codes].empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — Rust OOF-COL1 (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== C: Rust OOF-COL1 Arity ==="

check "C-01: range() (0 args) → OOF-COL1" do
  r = rust_compile(<<~IG)
    module RangeZeroArgs
    contract RangeZeroArgs {
      compute result = range()
      output result : Collection[Integer]
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "C-02: range() → OOF-COL1 message references stdlib.collection.range" do
  r = rust_compile(<<~IG)
    module RangeZeroArgs
    contract RangeZeroArgs {
      compute result = range()
      output result : Collection[Integer]
    }
  IG
  r[:messages].any? { |m| m.include?("stdlib.collection.range") && m.include?("expected 2 arguments") }
end

check "C-03: range(5) (1 arg) → OOF-COL1" do
  r = rust_compile(<<~IG)
    module RangeOneArg
    contract RangeOneArg {
      compute result = range(5)
      output result : Collection[Integer]
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "C-04: range(5) → OOF-COL1 message includes 'got 1'" do
  r = rust_compile(<<~IG)
    module RangeOneArg
    contract RangeOneArg {
      compute result = range(5)
      output result : Collection[Integer]
    }
  IG
  r[:messages].any? { |m| m.include?("got 1") }
end

check "C-05: range(0, 5, n) (3 args) → OOF-COL1" do
  r = rust_compile(<<~IG)
    module RangeThreeArgs
    contract RangeThreeArgs {
      input n : Integer
      compute result = range(0, 5, n)
      output result : Collection[Integer]
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "C-06: arity error → no OOF-TY1 cascade (Collection[Integer] returned on error)" do
  r = rust_compile(<<~IG)
    module RangeOneArg
    contract RangeOneArg {
      compute result = range(5)
      output result : Collection[Integer]
    }
  IG
  r[:codes].include?("OOF-COL1") && !r[:codes].include?("OOF-TY1")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — Rust Totality (4 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== D: Rust Totality ==="

check "D-01: range(5, 5) equal bounds → ok, no diagnostics" do
  r = rust_compile(<<~IG)
    module RangeEqual
    contract RangeEqual {
      compute result = range(5, 5)
      output result : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "D-02: range(5, 5) → SIR fn qualified" do
  r = rust_compile(<<~IG)
    module RangeEqual
    contract RangeEqual {
      compute result = range(5, 5)
      output result : Collection[Integer]
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.range")
end

check "D-03: range(5, 3) descending → ok, no diagnostics (total)" do
  r = rust_compile(<<~IG)
    module RangeDesc
    contract RangeDesc {
      compute result = range(5, 3)
      output result : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "D-04: range(5, 3) → SIR fn qualified" do
  r = rust_compile(<<~IG)
    module RangeDesc
    contract RangeDesc {
      compute result = range(5, 3)
      output result : Collection[Integer]
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.range")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — map(range) Pipeline (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== E: map(range) Pipeline ==="

check "E-01: map(range(0, n), i -> i) → ok, no diagnostics" do
  r = rust_compile(<<~IG)
    module MapOverRange
    contract MapOverRange {
      input n : Integer
      compute slots = map(range(0, n), i -> i)
      output slots : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "E-02: map(range(0, n)) → SIR contains stdlib.collection.map" do
  r = rust_compile(<<~IG)
    module MapOverRange
    contract MapOverRange {
      input n : Integer
      compute slots = map(range(0, n), i -> i)
      output slots : Collection[Integer]
    }
  IG
  fns = collect_sir_fns(r[:sir])
  fns.include?("stdlib.collection.map")
end

check "E-03: map(range(0, n)) → SIR contains qualified range fn name" do
  r = rust_compile(<<~IG)
    module MapOverRange
    contract MapOverRange {
      input n : Integer
      compute slots = map(range(0, n), i -> i)
      output slots : Collection[Integer]
    }
  IG
  fns = collect_sir_fns(r[:sir])
  fns.include?("stdlib.collection.range")
end

check "E-04: map(range(0, n)) → bare 'range' NOT in SIR" do
  r = rust_compile(<<~IG)
    module MapOverRange
    contract MapOverRange {
      input n : Integer
      compute slots = map(range(0, n), i -> i)
      output slots : Collection[Integer]
    }
  IG
  !collect_sir_fns(r[:sir]).include?("range")
end

check "E-05: count(range(0, n)) — range as collection source feeds count → ok" do
  r = rust_compile(<<~IG)
    module CountRange
    contract CountRange {
      input n : Integer
      compute total = count(range(0, n))
      output total : Integer
    }
  IG
  r[:codes].empty?
end

check "E-06: fold(range(0, 5), 0, lam) → SIR fn for range is qualified" do
  r = rust_compile(<<~IG)
    module FoldRange
    contract FoldRange {
      compute total = fold(range(0, 5), 0, (acc, x) -> acc)
      output total : Integer
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.range")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — Ruby P2 Unchanged (8 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== F: Ruby P2 Unchanged ==="

$LOAD_PATH.unshift((LANG_DIR / "lib").to_s) unless $LOAD_PATH.include?((LANG_DIR / "lib").to_s)
require "igniter_lang"

def ruby_compile(src)
  c = IgniterLang::CompilerOrchestrator.new
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    File.write(path, src)
    out = File.join(tmpdir, "out.igapp")
    r   = c.compile_sources(source_paths: [path], out_path: out)
    diags = r.dig("result", "diagnostics") || []
    sir_path = File.join(r.dig("result", "igapp_path") || (out + ".igapp"), "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    {
      codes:    diags.map { |d| d["rule"].to_s },
      messages: diags.map { |d| d["message"].to_s },
      sir:      sir
    }
  end
end

check "F-01: Ruby range(0, 5) still ok (P2 regression)" do
  r = ruby_compile(<<~IG)
    module R
    contract R { compute result = range(0, 5); output result : Collection[Integer] }
  IG
  r[:codes].empty?
end

check "F-02: Ruby range(0, 5) → SIR fn qualified (P2 regression)" do
  r = ruby_compile(<<~IG)
    module R
    contract R { compute result = range(0, 5); output result : Collection[Integer] }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.range")
end

check "F-03: Ruby range() → OOF-COL1 (P2 regression)" do
  r = ruby_compile(<<~IG)
    module R
    contract R { compute result = range(); output result : Collection[Integer] }
  IG
  r[:codes].include?("OOF-COL1")
end

check "F-04: Ruby range(5) → OOF-COL1 'got 1' (P2 regression)" do
  r = ruby_compile(<<~IG)
    module R
    contract R { compute result = range(5); output result : Collection[Integer] }
  IG
  r[:codes].include?("OOF-COL1") && r[:messages].any? { |m| m.include?("got 1") }
end

check "F-05: Ruby range(5, 5) totality → ok (P2 regression)" do
  r = ruby_compile(<<~IG)
    module R
    contract R { compute result = range(5, 5); output result : Collection[Integer] }
  IG
  r[:codes].empty?
end

check "F-06: Ruby map(range(0, n), i -> i) → ok (P2 regression)" do
  r = ruby_compile(<<~IG)
    module R
    contract R {
      input n : Integer
      compute slots = map(range(0, n), i -> i)
      output slots : Collection[Integer]
    }
  IG
  r[:codes].empty?
end

check "F-07: Ruby char_at regression → ok" do
  r = ruby_compile(<<~IG)
    module R
    contract R { input s : String; compute c = char_at(s, 0); output c : String }
  IG
  r[:codes].empty?
end

check "F-08: Ruby fold regression → ok" do
  r = ruby_compile(<<~IG)
    module R
    contract R {
      input items : Collection[Integer]
      compute total = fold(items, 0, (acc, x) -> acc)
      output total : Integer
    }
  IG
  r[:codes].empty?
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — Source Structure (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== G: Source Structure ==="

check "G-01: Rust TC range arm exists in typechecker.rs" do
  RUST_TC_SRC.include?('"range" =>')
end

check "G-02: Rust TC range arm has OOF-COL1 guard" do
  RUST_TC_SRC.match?(/\"range\".*?OOF-COL1/m)
end

check "G-03: Rust TC range arm OOF-COL1 message references stdlib.collection.range" do
  RUST_TC_SRC.match?(/\"range\".*?stdlib\.collection\.range.*?expected 2 arguments/m)
end

check "G-04: Rust emitter COLLECTION_HOF_OPS includes range entry" do
  RUST_EM_SRC.include?('"range"') && RUST_EM_SRC.include?('"stdlib.collection.range"')
end

check "G-05: Rust emitter semantic_expr_for_compute delegate list includes range" do
  # The matches! macro should include "range" in the delegate list
  RUST_EM_SRC.match?(/matches!\(fn_val,.*?\"range\"/)
end

check "G-06: Ruby TC infer_range_call method unchanged — still uses OOF-COL1" do
  TC_RUBY_SRC.include?("def infer_range_call") && TC_RUBY_SRC.match?(/def infer_range_call.*?OOF-COL1/m)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — Authority Closed (6 checks)
# ─────────────────────────────────────────────────────────────────────────────

puts "\n=== H: Authority Closed ==="

check "H-01: bloom_filter example.ig unchanged — still has manual slot pattern" do
  BLOOM_SRC.exist? && BLOOM_SRC.read(encoding: "UTF-8").include?("compute s0 = { pos: 0, set: false }")
end

check "H-02: Rust TC fast-path 'range' in collection-producing fn list unchanged" do
  RUST_TC_SRC.include?('"split" | "range" | "filter"')
end

check "H-03: no new OOF codes introduced — only OOF-COL1 used in range arm" do
  # Extract just the range arm block (from "range" => to the next arm)
  range_start = RUST_TC_SRC.index('"range" =>')
  next_arm    = RUST_TC_SRC.index('"filter" | "take"', range_start)
  range_block = RUST_TC_SRC[range_start...next_arm]
  oofs = range_block.scan(/OOF-[A-Z0-9]+/).uniq
  oofs == ["OOF-COL1"]
end

check "H-04: no parser file changes (parser.rs still parses range as a normal call)" do
  # Parser has no special range keyword handling — standard call parsing
  parser_src = (COMPILER_DIR / "src/parser.rs").read(encoding: "UTF-8")
  !parser_src.include?("stdlib.collection.range") && !parser_src.include?("\"range\" =")
end

check "H-05: Rust emitter build_pipeline range arm unchanged (special IR for pipeline contexts)" do
  RUST_EM_SRC.include?('"kind": "range"')
end

check "H-06: Ruby TC typechecker.rb has no new Rust-related changes" do
  # Ruby TC should still have only the P2 infer_range_call method — no extra Rust-synced content
  TC_RUBY_SRC.include?("def infer_range_call") && !TC_RUBY_SRC.include?("LANG-STDLIB-COLLECTION-RANGE-P3")
end

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────

total = $pass + $fail
puts "\n#{"=" * 60}"
puts "LANG-STDLIB-COLLECTION-RANGE-P3: #{$pass} PASS / #{$fail} FAIL / #{total} total"
verdict = $fail.zero? ? "ACCEPT" : "REJECT (#{$fail} failing check#{"s" if $fail > 1})"
puts "VERDICT: #{verdict}"
puts "=" * 60
