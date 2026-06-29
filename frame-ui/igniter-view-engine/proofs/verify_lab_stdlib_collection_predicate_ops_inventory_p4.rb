#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_collection_predicate_ops_inventory_p4.rb
# LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4
# ======================================================
# Proves inventory publication for stdlib.collection.find/any/all:
# - schema fields and signatures are exact
# - digest is canonical and stable
# - Rust MultifileResolver accepts imports through the inventory include_str table
# - predicate P3 tests remain the implementation proof; this script proves surface publication

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR       = Pathname.new(__dir__)
LAB_ROOT         = SCRIPT_DIR.parent.parent.parent
WORKSPACE_ROOT   = LAB_ROOT.parent
INVENTORY_PATH   = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"
MULTIFILE_RS     = LAB_ROOT / "lang" / "igniter-compiler" / "src" / "multifile.rs"
COMPILER_BIN     = LAB_ROOT / "lang" / "igniter-compiler" / "target" / "release" / "igniter_compiler"
P3_TEST          = LAB_ROOT / "lang" / "igniter-compiler" / "tests" / "collection_predicate_ops_tests.rs"

abort "inventory not found: #{INVENTORY_PATH}" unless INVENTORY_PATH.exist?
abort "multifile.rs not found: #{MULTIFILE_RS}" unless MULTIFILE_RS.exist?
abort "compiler binary not found: #{COMPILER_BIN}; run cargo build --manifest-path lang/igniter-compiler/Cargo.toml --release" unless COMPILER_BIN.exist?
abort "P3 predicate test not found: #{P3_TEST}" unless P3_TEST.exist?

$pass = 0
$fail = 0

def check(label)
  ok = yield
  if ok
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [exception: #{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n=== #{title} ==="
end

def canonical_json(obj)
  case obj
  when Hash
    "{#{obj.keys.sort.map { |k| "#{JSON.generate(k)}:#{canonical_json(obj[k])}" }.join(",")}}"
  when Array
    "[#{obj.map { |v| canonical_json(v) }.join(",")}]"
  else
    JSON.generate(obj)
  end
end

def compute_surface_digest(entries)
  stripped = entries
    .sort_by { |e| e.fetch("canonical_name") }
    .map { |e| e.reject { |k, _| k == "entry_digest" } }
  Digest::SHA256.hexdigest(canonical_json(stripped))
end

def compile_multifile(files)
  Dir.mktmpdir("pred_inv_p4_") do |dir|
    paths = files.map do |name, src|
      path = File.join(dir, name)
      File.write(path, src.strip + "\n")
      path
    end
    out = File.join(dir, "out.igapp")
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", *paths, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: result["status"] || "unknown",
      codes: Array(result["diagnostics"]).map { |d| d["rule"].to_s },
      diags: Array(result["diagnostics"]),
      stdout: stdout
    }
  end
end

inventory = JSON.parse(INVENTORY_PATH.read(encoding: "UTF-8"))
entries = inventory.fetch("entries")
entry = entries.to_h { |e| [e.fetch("canonical_name"), e] }
multifile_src = MULTIFILE_RS.read(encoding: "UTF-8")
p3_test_src = P3_TEST.read(encoding: "UTF-8")

names = {
  "stdlib.collection.find" => {
    alias: "find",
    input: ["Collection[T]", "T -> Bool"],
    output: "Option[T]",
    example: "find(xs, x -> x > 0) -> Option[T]"
  },
  "stdlib.collection.any" => {
    alias: "any",
    input: ["Collection[T]", "T -> Bool"],
    output: "Bool",
    example: "any(xs, x -> x > 0) -> Bool"
  },
  "stdlib.collection.all" => {
    alias: "all",
    input: ["Collection[T]", "T -> Bool"],
    output: "Bool",
    example: "all(xs, x -> x > 0) -> Bool"
  }
}

required_fields = %w[
  canonical_name semantic_ir_name legacy_sir aliases category lifecycle_status
  semantic_stability lowering_status compatibility_status fragment_class purity
  deterministic totality type_params input_signature output_signature diagnostics
  failure_behavior authority_surface proof_lineage examples compatibility_note
  owner_surface entry_digest
]

section("1. Inventory Parse")
check("1.1 inventory parses as stdlib_inventory") { inventory["kind"] == "stdlib_inventory" }
check("1.2 format_version is v0") { inventory["format_version"] == "v0" }
check("1.3 entry count is 46") { entries.length == 46 }
check("1.4 required predicate entries are present") { names.keys.all? { |name| entry.key?(name) } }

section("2. Field Shape")
names.each do |canonical, spec|
  e = entry[canonical]
  check("2 #{canonical}: required fields present") { required_fields.all? { |f| e.key?(f) } }
  check("2 #{canonical}: semantic_ir_name matches canonical") { e["semantic_ir_name"] == canonical }
  check("2 #{canonical}: one exact source alias") do
    e["aliases"] == [{ "kind" => "source_alias", "name" => spec.fetch(:alias) }]
  end
  check("2 #{canonical}: lifecycle/lowering published") do
    e["lifecycle_status"] == "production-implemented" &&
      e["semantic_stability"] == "design-locked" &&
      e["lowering_status"] == "dual-toolchain"
  end
end

section("3. Signatures And Diagnostics")
names.each do |canonical, spec|
  e = entry[canonical]
  check("3 #{canonical}: input signature exact") { e["input_signature"] == spec.fetch(:input) }
  check("3 #{canonical}: output signature exact") { e["output_signature"] == spec.fetch(:output) }
  check("3 #{canonical}: diagnostics exact") { e["diagnostics"] == %w[OOF-COL1 OOF-COL2 OOF-COL3] }
  check("3 #{canonical}: proof lineage points to P2 and P3") do
    e["proof_lineage"] == %w[
      LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2
      LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3
    ]
  end
  check("3 #{canonical}: example exact") { e["examples"] == [spec.fetch(:example)] }
end

section("4. Digest")
digest = compute_surface_digest(entries)
check("4.1 computed digest is sha256 hex") { digest.match?(/\A[0-9a-f]{64}\z/) }
check("4.2 computed digest matches stored") { inventory["stdlib_surface_digest"] == digest }
check("4.3 digest stable across repeated computation") { compute_surface_digest(entries) == digest }
check("4.4 digest stable under entry order shuffle") { compute_surface_digest(entries.shuffle) == digest }
check("4.5 entry_digest values are stripped") do
  compute_surface_digest(entries.map { |e| e.merge("entry_digest" => "sha256:fake") }) == digest
end
check("4.6 removing any predicate entry changes digest") do
  compute_surface_digest(entries.reject { |e| e["canonical_name"] == "stdlib.collection.find" }) != digest
end

section("5. Import Resolver")
check("5.1 multifile resolver embeds stdlib inventory") do
  multifile_src.include?('include_str!("../../../../igniter-lang/docs/spec/stdlib-inventory.json")')
end
check("5.2 multifile resolver consumes source_alias values") do
  multifile_src.include?('"source_alias"') && multifile_src.include?("stdlib_module_table")
end

happy_import = compile_multifile(
  "main.ig" => <<~IG,
    module PredicateImport
    import stdlib.collection.{ find, any, all }
    pure contract T {
      input value : Integer
      compute out = value + 1
      output out : Integer
    }
  IG
  "companion.ig" => <<~IG
    module PredicateImportCompanion
    pure contract C {
      input value : Integer
      compute out = value + 1
      output out : Integer
    }
  IG
)
check("5.3 import stdlib.collection.{find, any, all} compiles") { happy_import[:status] == "ok" }
check("5.4 import emits no OOF-IMP3") { !happy_import[:codes].include?("OOF-IMP3") }

bad_import = compile_multifile(
  "main.ig" => <<~IG,
    module PredicateImportBad
    import stdlib.collection.{ find, any, all, predicate_missing }
    pure contract T {
      input value : Integer
      compute out = value + 1
      output out : Integer
    }
  IG
  "companion.ig" => <<~IG
    module PredicateImportBadCompanion
    pure contract C {
      input value : Integer
      compute out = value + 1
      output out : Integer
    }
  IG
)
check("5.5 unknown stdlib.collection name still emits OOF-IMP3") { bad_import[:codes].include?("OOF-IMP3") }
check("5.6 unknown diagnostic names missing alias") do
  bad_import[:diags].any? { |d| d["rule"] == "OOF-IMP3" && d["missing_name"] == "predicate_missing" }
end

section("6. P3 And Closed Surfaces")
check("6.1 P3 focused test references find/any/all") do
  %w[stdlib.collection.find stdlib.collection.any stdlib.collection.all].all? { |s| p3_test_src.include?(s) }
end
check("6.2 no take/drop entries published") do
  !entry.key?("stdlib.collection.take") && !entry.key?("stdlib.collection.drop")
end
check("6.3 no zip/Pair entry published") do
  !entry.key?("stdlib.collection.zip") &&
    names.keys.all? { |name| !entry.fetch(name).to_s.include?("Pair") }
end
check("6.4 no query or DB predicate surface published") do
  names.keys.all? do |name|
    text = entry.fetch(name).to_s
    !text.include?("query") && !text.include?("database") && !text.include?("DB")
  end
end

puts
puts "predicate ops inventory P4: #{$pass} passed, #{$fail} failed"
exit($fail.zero? ? 0 : 1)
