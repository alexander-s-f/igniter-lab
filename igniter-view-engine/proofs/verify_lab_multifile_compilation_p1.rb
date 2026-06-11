#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_multifile_compilation_p1.rb
# LAB-MULTIFILE-COMPILATION-P1 - proof-local multi-file compilation universe.
#
# Authority: lab proof only. The multi-file driver below is proof-local; it
# does not add a production compiler CLI, package manager, visibility system,
# stdlib import, real IO authority, or canon claim.

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN   = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
FIXTURE_DIR    = ROOT / "fixtures" / "multifile_compilation"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} - #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

def canonicalize(value)
  case value
  when Hash
    value.keys.sort.each_with_object({}) { |key, out| out[key.to_s] = canonicalize(value[key]) }
  when Array
    value.map { |item| canonicalize(item) }
  else
    value
  end
end

def canonical_json(value)
  JSON.generate(canonicalize(value))
end

def sha256(value)
  "sha256:#{Digest::SHA256.hexdigest(value)}"
end

def fixture_paths(name)
  Dir.glob((FIXTURE_DIR / name / "*.ig").to_s).sort
end

def output_type_name(contract)
  output = contract.fetch("outputs").first
  type = output.fetch("type")
  type.is_a?(Hash) ? type.fetch("name") : type.to_s
end

def parse_file(path)
  source = File.read(path, encoding: "UTF-8")
  parsed = IgniterLang::ParsedProgram.parse(source, source_path: path).to_h
  {
    path: path,
    source: source,
    parsed: parsed,
    module: parsed.fetch("module"),
    imports: parsed.fetch("imports", []),
    type_names: parsed.fetch("types", []).map { |t| t.fetch("name") },
    contract_names: parsed.fetch("contracts", []).map { |c| c.fetch("name") }
  }
end

def source_without_module_imports(source)
  source.lines.reject do |line|
    stripped = line.strip
    stripped.start_with?("module ") || stripped.start_with?("import ")
  end.join
end

class ProofLocalMultifileDriver
  attr_reader :diagnostics

  def initialize(paths)
    @paths = paths
    @diagnostics = []
  end

  def compile
    files = @paths.map { |path| parse_file(path) }
    return fail_result("LAB-MF-PARSE", "parse failed") if files.any? { |f| f[:module].nil? || f[:module].empty? }

    duplicate_module = duplicate(files.map { |f| f[:module] })
    if duplicate_module
      return diagnostic_result(
        "OOF-M3",
        "duplicate module declaration '#{duplicate_module}'",
        files.select { |f| f[:module] == duplicate_module }.map { |f| f[:path] }
      )
    end

    by_module = files.to_h { |f| [f[:module], f] }
    import_diags = validate_imports(files, by_module)
    return diagnostic_result(import_diags.first[:rule], import_diags.first[:message], import_diags.first[:paths]) unless import_diags.empty?

    cycle = find_cycle(files)
    if cycle
      return diagnostic_result("OOF-M1", "circular import detected: #{cycle.join(" -> ")}", cycle)
    end

    duplicate_contract = duplicate(files.flat_map { |f| f[:contract_names] })
    if duplicate_contract
      owners = files.select { |f| f[:contract_names].include?(duplicate_contract) }.map { |f| f[:path] }
      return diagnostic_result("LAB-MF-DUP-CONTRACT", "duplicate contract '#{duplicate_contract}'", owners)
    end

    duplicate_type = duplicate(files.flat_map { |f| f[:type_names] })
    if duplicate_type
      owners = files.select { |f| f[:type_names].include?(duplicate_type) }.map { |f| f[:path] }
      return diagnostic_result("LAB-MF-DUP-TYPE", "duplicate type '#{duplicate_type}'", owners)
    end

    compile_merged(files)
  end

  private

  def validate_imports(files, by_module)
    files.flat_map do |file|
      file[:imports].filter_map do |import|
        target = by_module[import.fetch("module_path")]
        unless target
          next {
            rule: "OOF-M2",
            message: "unknown import path '#{import.fetch("module_path")}' from #{file[:module]}",
            paths: [file[:path], import.fetch("module_path")]
          }
        end

        names = import.fetch("names", nil)
        next nil if names.nil?

        exported = target[:type_names] + target[:contract_names]
        missing = names.reject { |name| exported.include?(name) }
        next nil if missing.empty?

        {
          rule: "OOF-M2",
          message: "unknown import name(s) #{missing.join(", ")} from #{import.fetch("module_path")}",
          paths: [file[:path], target[:path]]
        }
      end
    end
  end

  def find_cycle(files)
    graph = files.to_h { |f| [f[:module], f[:imports].map { |i| i.fetch("module_path") }] }
    visiting = {}
    visited = {}
    stack = []

    visit = lambda do |mod|
      return nil if visited[mod]
      if visiting[mod]
        idx = stack.index(mod) || 0
        return stack[idx..] + [mod]
      end

      visiting[mod] = true
      stack << mod
      graph.fetch(mod, []).each do |dep|
        next unless graph.key?(dep)
        found = visit.call(dep)
        return found if found
      end
      stack.pop
      visiting.delete(mod)
      visited[mod] = true
      nil
    end

    graph.keys.each do |mod|
      found = visit.call(mod)
      return found if found
    end
    nil
  end

  def compile_merged(files)
    sorted = files.sort_by { |f| f[:module] }
    source_hash = multifile_source_hash(sorted)
    merged_source = +"module Lab.Multifile.Universe\n\n"
    sorted.each do |file|
      merged_source << "-- source_module: #{file[:module]}\n"
      merged_source << source_without_module_imports(file[:source])
      merged_source << "\n"
    end

    tmp = Dir.mktmpdir("lab_multifile_p1")
    merged_path = File.join(tmp, "multifile_universe.ig")
    out_dir = File.join(tmp, "universe.igapp")
    File.write(merged_path, merged_source)

    stdout, stderr, status = Open3.capture3(
      COMPILER_BIN.to_s, "compile", merged_path, "--out", out_dir, "--json"
    )
    report = stdout.strip.empty? ? {} : JSON.parse(stdout)

    unless status.success? && report.fetch("status", nil) == "ok"
      diagnostics = []
      diagnostics += report.fetch("diagnostics", []) if report.is_a?(Hash)
      return {
        status: "oof",
        diagnostics: diagnostics,
        error: stderr,
        source_hash: source_hash,
        files: sorted,
        merged_source: merged_source
      }
    end

    manifest = JSON.parse(File.read(File.join(out_dir, "manifest.json"), encoding: "UTF-8"))
    semantic_ir = JSON.parse(File.read(File.join(out_dir, "semantic_ir_program.json"), encoding: "UTF-8"))
    compilation_report = JSON.parse(File.read(File.join(out_dir, "compilation_report.json"), encoding: "UTF-8"))
    contracts = Dir.glob(File.join(out_dir, "contracts", "*.json")).map do |path|
      JSON.parse(File.read(path, encoding: "UTF-8"))
    end

    ref_prefix = source_hash.delete_prefix("sha256:")[0, 16]
    manifest_like = manifest.merge(
      "program_id" => "semanticir/#{ref_prefix}",
      "source_hash" => source_hash,
      "semantic_ir_ref" => "semanticir/#{ref_prefix}",
      "compilation_report_ref" => "compilation_report/#{ref_prefix}",
      "source_units" => sorted.map do |file|
        {
          "module" => file[:module],
          "source_hash" => sha256(file[:source]),
          "types" => file[:type_names],
          "contracts" => file[:contract_names]
        }
      end
    )

    {
      status: "ok",
      source_hash: source_hash,
      files: sorted,
      merged_source: merged_source,
      out_dir: out_dir,
      compiler_report: report,
      manifest: manifest_like,
      rust_manifest: manifest,
      semantic_ir: semantic_ir,
      compilation_report: compilation_report,
      contracts: contracts,
      contract_names: contracts.map { |c| c.fetch("contract_id") }.sort,
      type_names: sorted.flat_map { |f| f[:type_names] }.sort
    }
  end

  def multifile_source_hash(sorted_files)
    material = sorted_files.map do |file|
      {
        "module" => file[:module],
        "source_hash" => sha256(file[:source]),
        "source" => file[:source]
      }
    end
    sha256(canonical_json(material))
  end

  def diagnostic_result(rule, message, paths)
    { status: "oof", diagnostics: [{ "rule" => rule, "message" => message, "paths" => paths }] }
  end

  def fail_result(rule, message)
    { status: "oof", diagnostics: [{ "rule" => rule, "message" => message }] }
  end

  def duplicate(values)
    seen = {}
    values.find { |value| seen[value] ? true : (seen[value] = true; false) }
  end
end

def compile_fixture(name, paths = fixture_paths(name))
  ProofLocalMultifileDriver.new(paths).compile
end

basic = compile_fixture("valid_basic")
order_paths = fixture_paths("valid_order_independent")
order_a = compile_fixture("valid_order_independent", order_paths)
order_b = compile_fixture("valid_order_independent", order_paths.reverse)
call_fixture = compile_fixture("valid_cross_file_contract_call")
unknown_import = compile_fixture("invalid_unknown_import")
circular_import = compile_fixture("invalid_circular_import")
duplicate_module = compile_fixture("invalid_duplicate_module")
duplicate_contract = compile_fixture("invalid_duplicate_contract")
authority_attempt = compile_fixture("invalid_authority_import_attempt")

single_file_tmp = Dir.mktmpdir("lab_multifile_single")
single_out = File.join(single_file_tmp, "single.igapp")
single_stdout, _single_stderr, single_status = Open3.capture3(
  COMPILER_BIN.to_s,
  "compile",
  (FIXTURE_DIR / "valid_cross_file_contract_call" / "callee.ig").to_s,
  "--out",
  single_out,
  "--json"
)
single_report = single_stdout.strip.empty? ? {} : JSON.parse(single_stdout)

comment_paths = fixture_paths("valid_basic")
comment_tmp = Dir.mktmpdir("lab_multifile_comment")
comment_paths.each { |path| FileUtils.cp(path, File.join(comment_tmp, File.basename(path))) }
File.open(File.join(comment_tmp, "consumer.ig"), "a") { |f| f.puts "\n-- comment-only raw source identity probe" }
comment_result = compile_fixture("valid_basic", Dir.glob(File.join(comment_tmp, "*.ig")).sort)

source_import_tmp = Dir.mktmpdir("lab_multifile_import_order")
fixture_paths("valid_order_independent").each { |path| FileUtils.cp(path, File.join(source_import_tmp, File.basename(path))) }
consumer_path = File.join(source_import_tmp, "consumer.ig")
consumer_source = File.read(consumer_path, encoding: "UTF-8")
swapped_source = consumer_source.sub(
  "import Lab.Multifile.Order.Types\nimport Lab.Multifile.Order.Mapper.{ BuildHttpResult }",
  "import Lab.Multifile.Order.Mapper.{ BuildHttpResult }\nimport Lab.Multifile.Order.Types"
)
File.write(consumer_path, swapped_source)
source_import_swapped = compile_fixture("valid_order_independent", Dir.glob(File.join(source_import_tmp, "*.ig")).sort)

puts "\nMF-COMPILE - Multi-file universe compilation"
check("valid two-file fixture compiles") { basic[:status] == "ok" }
check("valid three-file fixture compiles") { order_a[:status] == "ok" }
check("valid cross-file call fixture compiles") { call_fixture[:status] == "ok" }
check("one logical compilation universe is produced") do
  basic[:manifest].fetch("source_units").length == 2 && basic[:semantic_ir].fetch("module") == "Lab.Multifile.Universe"
end
check("contracts from all files are visible") do
  basic[:contract_names].include?("BuildQueryResult") && basic[:contract_names].include?("BuildFilterPredicate")
end
check("types from all files are visible") do
  basic[:type_names].include?("QueryResult") && basic[:type_names].include?("FilterPredicate")
end
check("three-file universe includes all contracts") do
  order_a[:contract_names].sort == %w[BuildHttpResult StatusReader].sort
end
check("single-file behavior still compiles") do
  single_status.success? && single_report.fetch("status", nil) == "ok"
end

puts "\nMF-IMPORT - Import resolution and cross-file use"
check("module import resolves") { order_a[:status] == "ok" }
check("selective import resolves") { basic[:status] == "ok" }
check("imported named record type used by consumer") do
  contract = basic[:semantic_ir].fetch("contracts").find { |c| c.fetch("contract_name") == "BuildQueryResult" }
  contract && output_type_name(contract) == "QueryResult"
end
check("imported FilterPredicate record type is reused") do
  contract = basic[:semantic_ir].fetch("contracts").find { |c| c.fetch("contract_name") == "BuildFilterPredicate" }
  contract && output_type_name(contract) == "FilterPredicate"
end
check("imported contract called by literal call_contract") do
  call_fixture[:status] == "ok" && call_fixture[:contract_names].include?("UseDoubleValue")
end
check("literal call_contract output type resolves across files") do
  contract = call_fixture[:semantic_ir].fetch("contracts").find { |c| c.fetch("contract_name") == "UseDoubleValue" }
  contract && output_type_name(contract) == "Integer"
end
check("import order in source does not affect resolved contract set") do
  order_a[:contract_names] == source_import_swapped[:contract_names]
end
check("file order passed to driver does not affect result") do
  order_a[:source_hash] == order_b[:source_hash] && order_a[:contract_names] == order_b[:contract_names]
end

puts "\nMF-IDENTITY - Deterministic multi-file identity"
check("multi-file source_hash is SHA256") { basic[:source_hash].match?(/\Asha256:[0-9a-f]{64}\z/) }
check("same files in different input order have same source_hash") { order_a[:source_hash] == order_b[:source_hash] }
check("changing one source file changes source_hash") { basic[:source_hash] != comment_result[:source_hash] }
check("comment-only change is classified as raw-source identity change") do
  comment_result[:status] == "ok" && basic[:source_hash] != comment_result[:source_hash]
end
check("manifest semantic_ir_ref shape valid") { basic[:manifest].fetch("semantic_ir_ref").match?(/\Asemanticir\/[0-9a-f]{16}\z/) }
check("manifest compilation_report_ref shape valid") do
  basic[:manifest].fetch("compilation_report_ref").match?(/\Acompilation_report\/[0-9a-f]{16}\z/)
end
check("manifest source_units sorted by module") do
  modules = order_a[:manifest].fetch("source_units").map { |u| u.fetch("module") }
  modules == modules.sort
end
check("contract_ref remains per-contract") do
  refs = basic[:contracts].map { |c| c.fetch("source_contract_ref") }
  refs.all? { |ref| ref.start_with?("contract/") } && refs.uniq.length == refs.length
end
check("multi-file source_hash is not artifact_hash") do
  basic[:manifest].fetch("source_hash") != basic[:manifest].fetch("artifact_hash")
end

puts "\nMF-DIAGNOSTICS - Fail-closed import/module errors"
check("unknown import path fails closed") { unknown_import[:status] == "oof" }
check("unknown import path uses OOF-M2") { unknown_import[:diagnostics].first.fetch("rule") == "OOF-M2" }
check("unknown import diagnostic includes path") { unknown_import[:diagnostics].first.fetch("message").include?("Missing") }
check("circular import fails closed") { circular_import[:status] == "oof" }
check("circular import uses OOF-M1") { circular_import[:diagnostics].first.fetch("rule") == "OOF-M1" }
check("circular import diagnostic includes modules") { circular_import[:diagnostics].first.fetch("message").include?("Cycle.A") }
check("duplicate module declaration fails closed") { duplicate_module[:status] == "oof" }
check("duplicate module uses OOF-M3 candidate") { duplicate_module[:diagnostics].first.fetch("rule") == "OOF-M3" }
check("duplicate contract name fails closed") { duplicate_contract[:status] == "oof" }
check("duplicate contract diagnostic is lab candidate") do
  duplicate_contract[:diagnostics].first.fetch("rule") == "LAB-MF-DUP-CONTRACT"
end
check("duplicate diagnostics include enough path facts") do
  duplicate_contract[:diagnostics].first.fetch("paths").length == 2
end

puts "\nMF-AUTHORITY - Import carries no capability authority"
check("authority import attempt fails closed") { authority_attempt[:status] == "oof" }
check("imported effect contract is not callable by pure consumer") do
  authority_attempt[:diagnostics].any? do |d|
    d.fetch("rule", "") == "OOF-TY0" || d.fetch("message", "").include?("not pure")
  end
end
check("import does not change fragment classification by itself") do
  basic[:semantic_ir].fetch("contracts").all? { |c| c.fetch("fragment_class") == "core" }
end
check("imported module cannot smuggle runtime authority") do
  basic[:manifest].fetch("source_units").none? { |u| u.key?("capability_grant") }
end
check("manifest has no package registry") { !basic[:manifest].key?("registry") && !basic[:manifest].key?("package_registry") }
check("manifest has no distribution metadata") { !basic[:manifest].key?("semver") && !basic[:manifest].key?("distribution") }
check("manifest has no imported capability grants") do
  !basic[:manifest].key?("capabilities_imported") && !basic[:manifest].key?("authority_imports")
end
check("consumer-side capability/profile binding remains absent in pure fixture") do
  basic[:semantic_ir].fetch("contracts").none? { |c| c.key?("profile_binding") || c.key?("required_capabilities") }
end

puts "\nMF-COPYPASTE - Reuse without redefinition"
consumer_source = File.read((FIXTURE_DIR / "valid_basic" / "consumer.ig").to_s, encoding: "UTF-8")
types_source = File.read((FIXTURE_DIR / "valid_basic" / "types.ig").to_s, encoding: "UTF-8")
check("QueryResult declared exactly once in provider") { types_source.scan(/\btype QueryResult\b/).length == 1 }
check("consumer does not redefine QueryResult") { consumer_source.scan(/\btype QueryResult\b/).empty? }
check("consumer imports QueryResult selectively") { consumer_source.include?("QueryResult") && consumer_source.include?("import") }
check("consumer output typechecks using imported QueryResult") do
  contract = basic[:semantic_ir].fetch("contracts").find { |c| c.fetch("contract_name") == "BuildQueryResult" }
  contract && output_type_name(contract) == "QueryResult"
end
check("FilterPredicate also reused without redefining in consumer") do
  consumer_source.scan(/\btype FilterPredicate\b/).empty? && basic[:type_names].include?("FilterPredicate")
end
check("reuse is proof-local, not stdlib authority") do
  basic[:manifest].fetch("source_units").none? { |u| u.fetch("module").start_with?("Stdlib") }
end

puts "\nMF-CLOSED - Closed authority surfaces"
check("no package registry") { !basic[:manifest].key?("package_registry") }
check("no semver") { !basic[:manifest].key?("semver") }
check("no public/internal visibility") { !basic[:merged_source].include?("public ") && !basic[:merged_source].include?("internal ") }
check("no stdlib-as-import claim") { basic[:files].all? { |f| f[:imports].none? { |i| i.fetch("module_path").start_with?("Stdlib") } } }
check("no real file/network/storage IO") do
  basic[:semantic_ir].fetch("contracts").none? { |c| c.fetch("fragment_class") != "core" }
end
check("no VM bytecode identity redesign") { !basic[:manifest].key?("bytecode_identity") }
check("no public/stable API claim") { !basic[:manifest].key?("public_api") }
check("no canon PROP authority") { !basic[:manifest].key?("canon_authority") }
check("no module name as content identity") { basic[:manifest].fetch("source_hash").start_with?("sha256:") }
check("driver is proof-local") { ProofLocalMultifileDriver.name == "ProofLocalMultifileDriver" }

if $fail_count.zero?
  puts "\nLAB-MULTIFILE-COMPILATION-P1 PASS (#{$pass_count}/#{$pass_count})"
  exit 0
else
  warn "\nLAB-MULTIFILE-COMPILATION-P1 FAIL (#{$pass_count} passed, #{$fail_count} failed)"
  exit 1
end
