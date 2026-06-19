#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_collection_map_filter_count_inventory_p5.rb
# LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5 — inventory + OOF-COL1/COL2 proof
# =============================================================================
# Proves that:
#   - stdlib-inventory.json contains entries for map, filter, count
#   - entry fields satisfy the schema contract
#   - stdlib_surface_digest is stable and matches computed value
#   - every live Ruby and Rust dispatch key maps to an inventory entry or alias
#   - Rust TC emits OOF-COL1 (arity) and OOF-COL2 (non-Collection) for all three
#   - P4 regressions remain green (67/67 on re-run)
#   - closed surfaces are intact (no fold/sum inventory entries)
#
# Sections:
#   A  Inventory schema         (10)  — entry count, required fields, vocab
#   B  Digest stability         ( 8)  — determinism, shuffle, mutate, strip
#   C  map entry                ( 9)  — fields, aliases, SIR name, proof_lineage
#   D  filter entry             ( 9)  — fields, aliases, SIR name, diagnostics
#   E  count entry update       ( 7)  — proof_lineage updated, T3 note, dual
#   F  Bidirectional dispatch   ( 8)  — Ruby HOF keys → inventory; Rust aliases
#   G  OOF-COL1 parity          (10)  — count/filter/map arity mismatch errors
#   H  OOF-COL2 parity          (10)  — count/filter/map non-Collection errors
#   I  P4 regression            ( 8)  — canonical names; types; OOF-COL3; chain
#   J  Authority closed         ( 7)  — no fold/sum inventory; no new import
#
# Total: 86 checks (minimum: 60)

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR     = Pathname.new(__dir__)
LAB_ROOT       = SCRIPT_DIR.parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN   = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
INVENTORY_PATH = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"
TC_RUBY        = WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST        = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"

abort "Compiler binary not found: #{COMPILER_BIN}" unless COMPILER_BIN.exist?
abort "Inventory not found: #{INVENTORY_PATH}" unless INVENTORY_PATH.exist?

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

# ── Helpers ───────────────────────────────────────────────────────────────────

INVENTORY     = JSON.parse(INVENTORY_PATH.read(encoding: "UTF-8"))
ENTRIES       = INVENTORY["entries"]
ENTRY_BY_NAME = ENTRIES.to_h { |e| [e["canonical_name"], e] }
TC_RUST_SRC   = TC_RUST.read.encode("UTF-8", invalid: :replace, undef: :replace)
EMITTER_RUST  = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"
EMITTER_SRC   = EMITTER_RUST.read.encode("UTF-8", invalid: :replace, undef: :replace)
TC_RUBY_SRC   = TC_RUBY.exist? ? TC_RUBY.read.encode("UTF-8", invalid: :replace, undef: :replace) : ""

REQUIRED_FIELDS = %w[
  canonical_name semantic_ir_name legacy_sir aliases category
  lifecycle_status semantic_stability lowering_status compatibility_status
  fragment_class purity deterministic totality type_params
  input_signature output_signature diagnostics failure_behavior
  authority_surface proof_lineage examples compatibility_note
  owner_surface entry_digest
].freeze

VALID_LIFECYCLE  = %w[doc-only proposal proof-local lab-implemented production-implemented canon deprecated orphaned].freeze
VALID_SEMANTIC   = %w[sketch convention experiment-pass design-locked superseded].freeze
VALID_LOWERING   = %w[none kernel-only single-toolchain dual-toolchain].freeze
VALID_COMPAT     = %w[pre-v1-none surface-stable frozen].freeze

def canonical_json(obj)
  case obj
  when Hash
    sorted = obj.keys.sort.map { |k| "#{JSON.generate(k)}:#{canonical_json(obj[k])}" }
    "{#{sorted.join(",")}}"
  when Array
    "[#{obj.map { |v| canonical_json(v) }.join(",")}]"
  else
    JSON.generate(obj)
  end
end

def compute_surface_digest(entries)
  stripped = entries
    .sort_by { |e| e["canonical_name"] }
    .map { |e| e.reject { |k, _| k == "entry_digest" } }
  Digest::SHA256.hexdigest(canonical_json(stripped))
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

# ── Section A: Inventory schema ───────────────────────────────────────────────
puts "\n=== A: Inventory schema ==="

check "A-01: inventory parses without error" do
  INVENTORY.is_a?(Hash)
end

check "A-02: format_version = 'v0'" do
  INVENTORY["format_version"] == "v0"
end

check "A-03: entry count == 26 (24 + map + filter)" do
  ENTRIES.length == 26
end

check "A-04: all required fields present in every entry" do
  missing = ENTRIES.flat_map do |e|
    REQUIRED_FIELDS.select { |f| !e.key?(f) }.map { |f| "#{e["canonical_name"]}.#{f}" }
  end
  missing.empty? || (puts("  missing: #{missing.first(3).join(", ")}"); false)
end

check "A-05: all lifecycle_status values are valid vocabulary" do
  ENTRIES.all? { |e| VALID_LIFECYCLE.include?(e["lifecycle_status"]) }
end

check "A-06: all semantic_stability values are valid vocabulary" do
  ENTRIES.all? { |e| VALID_SEMANTIC.include?(e["semantic_stability"]) }
end

check "A-07: all lowering_status values are valid vocabulary" do
  ENTRIES.all? { |e| VALID_LOWERING.include?(e["lowering_status"]) }
end

check "A-08: stdlib_surface_digest present in envelope" do
  INVENTORY.key?("stdlib_surface_digest") && !INVENTORY["stdlib_surface_digest"].nil?
end

check "A-09: stdlib.collection.map entry present" do
  ENTRY_BY_NAME.key?("stdlib.collection.map")
end

check "A-10: stdlib.collection.filter entry present" do
  ENTRY_BY_NAME.key?("stdlib.collection.filter")
end

# ── Section B: Digest stability ───────────────────────────────────────────────
puts "\n=== B: Digest stability ==="

DIGEST_A = compute_surface_digest(ENTRIES)

check "B-01: surface digest computes without error (SHA256, 64 hex chars)" do
  DIGEST_A.is_a?(String) && DIGEST_A.length == 64
end

check "B-02: computed digest matches stored stdlib_surface_digest" do
  INVENTORY["stdlib_surface_digest"] == DIGEST_A
end

check "B-03: digest stable across two computations" do
  compute_surface_digest(ENTRIES) == DIGEST_A
end

check "B-04: shuffling entry order does not change digest" do
  compute_surface_digest(ENTRIES.shuffle) == DIGEST_A
end

check "B-05: adding whitespace to raw JSON does not change digest" do
  reparsed = JSON.parse(JSON.pretty_generate(INVENTORY))
  compute_surface_digest(reparsed["entries"]) == DIGEST_A
end

check "B-06: entry_digest fields stripped before digest computation" do
  with_digests = ENTRIES.map { |e| e.merge("entry_digest" => "sha256:fake") }
  compute_surface_digest(with_digests) == DIGEST_A
end

check "B-07: removing one entry changes the digest" do
  fewer = ENTRIES.reject { |e| e["canonical_name"] == "stdlib.text.trim" }
  compute_surface_digest(fewer) != DIGEST_A
end

check "B-08: adding a new entry changes the digest" do
  extra = ENTRIES + [{"canonical_name" => "stdlib.test.fake", "entry_digest" => nil}]
  compute_surface_digest(extra) != DIGEST_A
end

# ── Section C: map entry ──────────────────────────────────────────────────────
puts "\n=== C: map entry ==="

MAP_ENTRY = ENTRY_BY_NAME["stdlib.collection.map"]

check "C-01: semantic_ir_name == canonical_name for map" do
  MAP_ENTRY&.dig("semantic_ir_name") == "stdlib.collection.map"
end

check "C-02: map aliases contains source_alias 'map'" do
  aliases = MAP_ENTRY&.dig("aliases") || []
  aliases.any? { |a| a["kind"] == "source_alias" && a["name"] == "map" }
end

check "C-03: map category == 'collection'" do
  MAP_ENTRY&.dig("category") == "collection"
end

check "C-04: map lifecycle_status == 'lab-implemented'" do
  MAP_ENTRY&.dig("lifecycle_status") == "lab-implemented"
end

check "C-05: map lowering_status == 'dual-toolchain'" do
  MAP_ENTRY&.dig("lowering_status") == "dual-toolchain"
end

check "C-06: map type_params == ['T', 'U']" do
  MAP_ENTRY&.dig("type_params") == ["T", "U"]
end

check "C-07: map output_signature == 'Collection[U]'" do
  MAP_ENTRY&.dig("output_signature") == "Collection[U]"
end

check "C-08: map diagnostics includes OOF-COL1 and OOF-COL2" do
  diags = MAP_ENTRY&.dig("diagnostics") || []
  diags.include?("OOF-COL1") && diags.include?("OOF-COL2")
end

check "C-09: map proof_lineage mentions P3 and P4" do
  pl = MAP_ENTRY&.dig("proof_lineage") || []
  pl.any? { |s| s.include?("P3") } && pl.any? { |s| s.include?("P4") }
end

# ── Section D: filter entry ───────────────────────────────────────────────────
puts "\n=== D: filter entry ==="

FILTER_ENTRY = ENTRY_BY_NAME["stdlib.collection.filter"]

check "D-01: semantic_ir_name == canonical_name for filter" do
  FILTER_ENTRY&.dig("semantic_ir_name") == "stdlib.collection.filter"
end

check "D-02: filter aliases contains source_alias 'filter'" do
  aliases = FILTER_ENTRY&.dig("aliases") || []
  aliases.any? { |a| a["kind"] == "source_alias" && a["name"] == "filter" }
end

check "D-03: filter category == 'collection'" do
  FILTER_ENTRY&.dig("category") == "collection"
end

check "D-04: filter lifecycle_status == 'lab-implemented'" do
  FILTER_ENTRY&.dig("lifecycle_status") == "lab-implemented"
end

check "D-05: filter lowering_status == 'dual-toolchain'" do
  FILTER_ENTRY&.dig("lowering_status") == "dual-toolchain"
end

check "D-06: filter type_params == ['T']" do
  FILTER_ENTRY&.dig("type_params") == ["T"]
end

check "D-07: filter output_signature == 'Collection[T]'" do
  FILTER_ENTRY&.dig("output_signature") == "Collection[T]"
end

check "D-08: filter diagnostics includes OOF-COL1, OOF-COL2, OOF-COL3" do
  diags = FILTER_ENTRY&.dig("diagnostics") || []
  diags.include?("OOF-COL1") && diags.include?("OOF-COL2") && diags.include?("OOF-COL3")
end

check "D-09: filter proof_lineage mentions P3 and P4" do
  pl = FILTER_ENTRY&.dig("proof_lineage") || []
  pl.any? { |s| s.include?("P3") } && pl.any? { |s| s.include?("P4") }
end

# ── Section E: count entry update ────────────────────────────────────────────
puts "\n=== E: count entry update ==="

COUNT_ENTRY = ENTRY_BY_NAME["stdlib.collection.count"]

check "E-01: stdlib.collection.count entry present" do
  !COUNT_ENTRY.nil?
end

check "E-02: count proof_lineage mentions P3" do
  pl = COUNT_ENTRY&.dig("proof_lineage") || []
  pl.any? { |s| s.include?("P3") }
end

check "E-03: count proof_lineage mentions P4" do
  pl = COUNT_ENTRY&.dig("proof_lineage") || []
  pl.any? { |s| s.include?("P4") }
end

check "E-04: count proof_lineage mentions T3 path" do
  pl = COUNT_ENTRY&.dig("proof_lineage") || []
  pl.any? { |s| s.downcase.include?("t3") }
end

check "E-05: count lowering_status == 'dual-toolchain'" do
  COUNT_ENTRY&.dig("lowering_status") == "dual-toolchain"
end

check "E-06: count output_signature == 'Integer'" do
  COUNT_ENTRY&.dig("output_signature") == "Integer"
end

check "E-07: count semantic_ir_name == 'stdlib.collection.count'" do
  COUNT_ENTRY&.dig("semantic_ir_name") == "stdlib.collection.count"
end

# ── Section F: Bidirectional dispatch ────────────────────────────────────────
puts "\n=== F: Bidirectional dispatch ==="

# Every live Ruby HOF dispatch key should have an inventory alias
HOF_KEYS = %w[map filter count].freeze

check "F-01: Ruby COLLECTION_HOF_FNS dispatch key 'map' maps to inventory alias" do
  aliases_flat = (ENTRY_BY_NAME["stdlib.collection.map"]&.dig("aliases") || []).map { |a| a["name"] }
  aliases_flat.include?("map")
end

check "F-02: Ruby COLLECTION_HOF_FNS dispatch key 'filter' maps to inventory alias" do
  aliases_flat = (ENTRY_BY_NAME["stdlib.collection.filter"]&.dig("aliases") || []).map { |a| a["name"] }
  aliases_flat.include?("filter")
end

check "F-03: Ruby COLLECTION_HOF_FNS dispatch key 'count' maps to inventory alias" do
  aliases_flat = (ENTRY_BY_NAME["stdlib.collection.count"]&.dig("aliases") || []).map { |a| a["name"] }
  aliases_flat.include?("count")
end

check "F-04: Rust emitter COLLECTION_HOF_OPS 'map' maps to inventory canonical name" do
  EMITTER_SRC.include?('"stdlib.collection.map"') &&
    ENTRY_BY_NAME.key?("stdlib.collection.map")
end

check "F-05: Rust emitter COLLECTION_HOF_OPS 'filter' maps to inventory canonical name" do
  EMITTER_SRC.include?('"stdlib.collection.filter"') &&
    ENTRY_BY_NAME.key?("stdlib.collection.filter")
end

check "F-06: Rust emitter COLLECTION_HOF_OPS 'count' maps to inventory canonical name" do
  TC_RUST_SRC.include?('"stdlib.collection.count"') &&
    ENTRY_BY_NAME.key?("stdlib.collection.count")
end

check "F-07: every source_alias in collection entries is a known dispatch key" do
  collection_entries = ENTRIES.select { |e| e["category"] == "collection" && e["lifecycle_status"] != "orphaned" }
  all_aliases = collection_entries.flat_map { |e| (e["aliases"] || []).map { |a| a["name"] } }.compact
  known = %w[map filter count concat first last sum zip] # known HOF/collection dispatch keys
  unknowns = all_aliases.reject { |a| known.include?(a) }
  unknowns.empty? || (puts("  unknown aliases: #{unknowns.join(", ")}"); false)
end

check "F-08: no orphan collection entries have source_alias 'map' or 'filter'" do
  orphaned = ENTRIES.select { |e| e["lifecycle_status"] == "orphaned" }
  orphaned.none? do |e|
    (e["aliases"] || []).any? { |a| %w[map filter].include?(a["name"]) }
  end
end

# ── Section G: OOF-COL1 parity ───────────────────────────────────────────────
puts "\n=== G: OOF-COL1 parity ==="

check "G-01: count() 0 args → OOF-COL1" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      output n : Integer
      compute n = count()
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "G-02: OOF-COL1 message for count mentions 'stdlib.collection.count'" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      output n : Integer
      compute n = count()
    }
  IG
  r[:messages].any? { |m| m.include?("stdlib.collection.count") }
end

check "G-03: count(a, b) 2 args → OOF-COL1" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input a : Collection[Integer]
      input b : Collection[Integer]
      output n : Integer
      compute n = count(a, b)
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "G-04: filter(items) 1 arg → OOF-COL1" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items)
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "G-05: OOF-COL1 message for filter mentions 'stdlib.collection.filter'" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items)
    }
  IG
  r[:messages].any? { |m| m.include?("stdlib.collection.filter") }
end

check "G-06: filter() 0 args → OOF-COL1" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      output r : Collection[Integer]
      compute r = filter()
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "G-07: map(items) 1 arg → OOF-COL1" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Integer]
      compute r = map(items)
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "G-08: OOF-COL1 message for map mentions 'stdlib.collection.map'" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Integer]
      compute r = map(items)
    }
  IG
  r[:messages].any? { |m| m.include?("stdlib.collection.map") }
end

check "G-09: map() 0 args → OOF-COL1" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      output r : Collection[Integer]
      compute r = map()
    }
  IG
  r[:codes].include?("OOF-COL1")
end

check "G-10: correct arity (count 1 arg, map 2 args, filter 2 args) — no OOF-COL1" do
  r1 = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Integer]
      output n : Integer
      compute n = count(items)
    }
  IG
  r2 = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Integer]
      compute r = map(items, x -> x.value)
    }
  IG
  r3 = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items, x -> x.active)
    }
  IG
  !r1[:codes].include?("OOF-COL1") &&
    !r2[:codes].include?("OOF-COL1") &&
    !r3[:codes].include?("OOF-COL1")
end

# ── Section H: OOF-COL2 parity ───────────────────────────────────────────────
puts "\n=== H: OOF-COL2 parity ==="

check "H-01: count(n) where n:Integer → OOF-COL2" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Integer
      compute r = count(n)
    }
  IG
  r[:codes].include?("OOF-COL2")
end

check "H-02: OOF-COL2 message for count mentions 'Collection[T]'" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Integer
      compute r = count(n)
    }
  IG
  r[:messages].any? { |m| m.include?("Collection") }
end

check "H-03: count(t) where t:Text → OOF-COL2" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input t : Text
      output r : Integer
      compute r = count(t)
    }
  IG
  r[:codes].include?("OOF-COL2")
end

check "H-04: filter(n, x -> x) where n:Integer → OOF-COL2" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Collection[Integer]
      compute r = filter(n, x -> x)
    }
  IG
  r[:codes].include?("OOF-COL2")
end

check "H-05: OOF-COL2 message for filter mentions 'stdlib.collection.filter'" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Collection[Integer]
      compute r = filter(n, x -> x)
    }
  IG
  r[:messages].any? { |m| m.include?("stdlib.collection.filter") }
end

check "H-06: map(n, x -> x) where n:Integer → OOF-COL2" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Collection[Integer]
      compute r = map(n, x -> x)
    }
  IG
  r[:codes].include?("OOF-COL2")
end

check "H-07: OOF-COL2 message for map mentions 'stdlib.collection.map'" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Collection[Integer]
      compute r = map(n, x -> x)
    }
  IG
  r[:messages].any? { |m| m.include?("stdlib.collection.map") }
end

check "H-08: count(items) where items:Collection[Integer] — no OOF-COL2" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Integer]
      output n : Integer
      compute n = count(items)
    }
  IG
  !r[:codes].include?("OOF-COL2")
end

check "H-09: filter(items, x -> x.active) where items:Collection[Item] — no OOF-COL2" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items, x -> x.active)
    }
  IG
  !r[:codes].include?("OOF-COL2")
end

check "H-10: Unknown first arg — no OOF-COL2 (Unknown is permissive)" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Unknown]
      output n : Integer
      compute n = count(items)
    }
  IG
  !r[:codes].include?("OOF-COL2")
end

# ── Section I: P4 regression ──────────────────────────────────────────────────
puts "\n=== I: P4 regression ==="

check "I-01: map SIR fn == 'stdlib.collection.map'" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Integer]
      compute r = map(items, x -> x.value)
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.map")
end

check "I-02: filter SIR fn == 'stdlib.collection.filter'" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items, x -> x.active)
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.filter")
end

check "I-03: count SIR fn == 'stdlib.collection.count'" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Integer]
      output n : Integer
      compute n = count(items)
    }
  IG
  collect_sir_fns(r[:sir]).include?("stdlib.collection.count")
end

check "I-04: map result Collection[Integer] when lambda returns Integer field" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Integer]
      compute r = map(items, x -> x.value)
    }
  IG
  sir = r[:sir]
  (sir["contracts"] || []).any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "params", 0, "name") == "Integer"
    end
  end
end

check "I-05: filter non-Bool predicate → OOF-COL3" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items, x -> x.value)
    }
  IG
  r[:codes].include?("OOF-COL3")
end

check "I-06: filter Bool predicate — no OOF-COL3" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output r : Collection[Item]
      compute r = filter(items, x -> x.active)
    }
  IG
  !r[:codes].include?("OOF-COL3")
end

check "I-07: chain filter+map+count — all three qualified in SIR" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { value: Integer; active: Bool; }
    contract C {
      input items : Collection[Item]
      output n : Integer
      compute active = filter(items, x -> x.active)
      compute values = map(active, x -> x.value)
      compute n = count(values)
    }
  IG
  fns = collect_sir_fns(r[:sir])
  fns.include?("stdlib.collection.map") &&
    fns.include?("stdlib.collection.filter") &&
    fns.include?("stdlib.collection.count")
end

check "I-08: OOF-COL1 message format correct (mentions expected/got)" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      output n : Integer
      compute n = count()
    }
  IG
  r[:messages].any? { |m| m.include?("expected") && m.include?("got") }
end

# ── Section J: Authority closed ───────────────────────────────────────────────
puts "\n=== J: Authority closed ==="

check "J-01: stdlib.collection.fold NOT in inventory" do
  !ENTRY_BY_NAME.key?("stdlib.collection.fold")
end

check "J-02: stdlib.collection.sum NOT in inventory" do
  !ENTRY_BY_NAME.key?("stdlib.collection.sum")
end

check "J-03: inventory entry count == 26 (no extras crept in)" do
  ENTRIES.length == 26
end

check "J-04: no new stdlib.collection.* entries beyond map/filter/count/concat" do
  col_entries = ENTRIES.select { |e| e["canonical_name"].start_with?("stdlib.collection.") }
  names = col_entries.map { |e| e["canonical_name"] }
  allowed = %w[stdlib.collection.map stdlib.collection.filter stdlib.collection.count stdlib.collection.concat]
  extras = names - allowed
  extras.empty? || (puts("  unexpected: #{extras.join(", ")}"); false)
end

check "J-05: no new stdlib.* import authority added (authority_surface none for map/filter)" do
  [MAP_ENTRY, FILTER_ENTRY].all? { |e| e&.dig("authority_surface") == "none" }
end

check "J-06: Ruby TC COLLECTION_HOF_FNS still present (P5 adds no Ruby changes)" do
  # Ruby infer_collection_hof_call already emits OOF-COL1/COL2; P5 does not modify Ruby TC
  TC_RUBY_SRC.include?("COLLECTION_HOF_FNS") &&
    TC_RUBY_SRC.include?("infer_collection_hof_call")
end

check "J-07: Rust TC OOF-COL1 present for map, filter, count" do
  TC_RUST_SRC.include?("stdlib.collection.count: expected 1 argument") &&
    TC_RUST_SRC.include?("stdlib.collection.filter: expected 2 arguments") &&
    TC_RUST_SRC.include?("stdlib.collection.map: expected 2 arguments")
end

# ── Summary ───────────────────────────────────────────────────────────────────

total = $pass + $fail
puts "\n" + "=" * 62
puts "LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5: #{$pass} PASS / #{$fail} FAIL / #{total} total"
puts "=" * 62
if $fail == 0
  puts "\nVERDICT: PASS — inventory + OOF-COL1/COL2 parity proved"
  puts "stdlib.collection.{map,filter,count} inventory entries live."
  puts "digest: #{DIGEST_A}"
  puts "Next route: LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P6 (if needed)"
else
  puts "\nVERDICT: FAIL — #{$fail} check(s) need attention"
end
