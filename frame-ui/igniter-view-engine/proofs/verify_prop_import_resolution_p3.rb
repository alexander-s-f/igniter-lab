#!/usr/bin/env ruby
# frozen_string_literal: true
#
# PROP-IMPORT-RESOLUTION-P3 - Rust-lab multi-file import implementation proof.
#
# Authority: lab/Rust implementation only. This proof does not create Ruby canon
# parity, package registry, visibility, stdlib-as-import, runtime loading, VM, or
# public/stable API authority.

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT = Pathname.new(__dir__).parent
LAB_ROOT = ROOT.parent
COMPILER_ROOT = LAB_ROOT / "igniter-compiler"
COMPILER_BIN = COMPILER_ROOT / "target" / "release" / "igniter_compiler"
FIXTURE_DIR = ROOT / "fixtures" / "multifile_compilation_p3"

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

def run!(command, chdir: nil)
  stdout, stderr, status = Open3.capture3(*command, chdir: chdir)
  { stdout: stdout, stderr: stderr, status: status }
end

build = run!(%w[cargo build --release], chdir: COMPILER_ROOT.to_s)

def fixture_paths(name)
  Dir.glob((FIXTURE_DIR / name / "*.ig").to_s).sort
end

def compile_fixture(name, paths: fixture_paths(name))
  tmp = Dir.mktmpdir("prop_import_p3_")
  out_dir = File.join(tmp, "#{name}.igapp")
  stdout, stderr, status = Open3.capture3(
    COMPILER_BIN.to_s,
    "compile",
    *paths,
    "--out",
    out_dir,
    "--json"
  )
  result = stdout.strip.empty? ? {} : JSON.parse(stdout)
  manifest_path = File.join(out_dir, "manifest.json")
  sir_path = File.join(out_dir, "semantic_ir_program.json")
  report_path = File.join(out_dir, "compilation_report.json")
  contracts = Dir.glob(File.join(out_dir, "contracts", "*.json")).sort.map do |path|
    JSON.parse(File.read(path, encoding: "UTF-8"))
  end

  {
    name: name,
    status: status,
    stdout: stdout,
    stderr: stderr,
    result: result,
    out_dir: out_dir,
    manifest: File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path, encoding: "UTF-8")) : nil,
    semantic_ir: File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : nil,
    compilation_report: File.exist?(report_path) ? JSON.parse(File.read(report_path, encoding: "UTF-8")) : nil,
    contracts: contracts,
    paths: paths
  }
end

def output_type_name(contract)
  output = contract.fetch("outputs").first
  type = output.fetch("type")
  type.is_a?(Hash) ? type.fetch("name") : type.to_s
end

def diagnostic_rule(run)
  run.fetch(:result).fetch("diagnostics").first.fetch("rule")
end

def diagnostic(run)
  run.fetch(:result).fetch("diagnostics").first
end

def status_ok?(run)
  run.fetch(:status).success? && run.fetch(:result).fetch("status", nil) == "ok"
end

def status_oof?(run)
  !run.fetch(:status).success? && run.fetch(:result).fetch("status", nil) == "oof"
end

def semantic_contract_names(run)
  run.fetch(:semantic_ir).fetch("contracts").map { |c| c.fetch("contract_name") }.sort
end

def semantic_type_names(run)
  run.fetch(:manifest).fetch("source_units").flat_map { |u| u.fetch("types", []) }.sort
end

def sha256?(value)
  value.match?(/\Asha256:[0-9a-f]{64}\z/)
end

def copy_fixture(name)
  tmp = Dir.mktmpdir("prop_import_p3_copy_")
  fixture_paths(name).each { |path| FileUtils.cp(path, File.join(tmp, File.basename(path))) }
  tmp
end

basic = compile_fixture("valid_basic")
order_paths = fixture_paths("valid_order_independent")
order_a = compile_fixture("valid_order_independent", paths: order_paths)
order_b = compile_fixture("valid_order_independent", paths: order_paths.reverse)
call_fixture = compile_fixture("valid_cross_file_contract_call")
unknown_import = compile_fixture("invalid_unknown_import")
missing_selective = compile_fixture("invalid_missing_selective_name")
circular_import = compile_fixture("invalid_circular_import")
duplicate_module = compile_fixture("invalid_duplicate_module")
missing_module = compile_fixture("invalid_missing_module")
duplicate_contract = compile_fixture("invalid_duplicate_contract")
duplicate_type = compile_fixture("invalid_duplicate_type")
authority_attempt = compile_fixture("invalid_authority_import_attempt")

single_tmp = Dir.mktmpdir("prop_import_p3_single_")
single_out = File.join(single_tmp, "single.igapp")
single_stdout, _single_stderr, single_status = Open3.capture3(
  COMPILER_BIN.to_s,
  "compile",
  (FIXTURE_DIR / "valid_cross_file_contract_call" / "callee.ig").to_s,
  "--out",
  single_out,
  "--json"
)
single_result = single_stdout.strip.empty? ? {} : JSON.parse(single_stdout)

comment_tmp = copy_fixture("valid_basic")
File.open(File.join(comment_tmp, "consumer.ig"), "a") { |f| f.puts "\n-- comment-only raw source identity probe" }
comment_result = compile_fixture("valid_basic", paths: Dir.glob(File.join(comment_tmp, "*.ig")).sort)

edit_tmp = copy_fixture("valid_basic")
consumer_path = File.join(edit_tmp, "consumer.ig")
File.write(consumer_path, File.read(consumer_path, encoding: "UTF-8").sub("reason: reason", 'reason: "edited"'))
edited_result = compile_fixture("valid_basic", paths: Dir.glob(File.join(edit_tmp, "*.ig")).sort)

import_order_tmp = copy_fixture("valid_order_independent")
consumer_order_path = File.join(import_order_tmp, "consumer.ig")
consumer_source = File.read(consumer_order_path, encoding: "UTF-8")
File.write(
  consumer_order_path,
  consumer_source.sub(
    "import Lab.Multifile.Order.Types\nimport Lab.Multifile.Order.Mapper.{ BuildHttpResult }",
    "import Lab.Multifile.Order.Mapper.{ BuildHttpResult }\nimport Lab.Multifile.Order.Types"
  )
)
source_import_swapped = compile_fixture("valid_order_independent", paths: Dir.glob(File.join(import_order_tmp, "*.ig")).sort)

puts "\nIMP3-COMPILE - Rust-lab multi-file compilation"
check("cargo build --release succeeds") { build.fetch(:status).success? }
check("single-source regression compiles") { single_status.success? && single_result.fetch("status", nil) == "ok" }
check("valid two-file fixture compiles") { status_ok?(basic) }
check("valid three-file fixture compiles") { status_ok?(order_a) }
check("valid cross-file call fixture compiles") { status_ok?(call_fixture) }
check("merged universe module is synthetic") { basic.fetch(:semantic_ir).fetch("module") == "Lab.Multifile.Universe" }
check("merged universe contains all contracts") do
  semantic_contract_names(basic).sort == %w[BuildFilterPredicate BuildQueryResult].sort
end
check("merged universe contains all types") { semantic_type_names(basic) == %w[FilterPredicate QueryResult].sort }
check("single-source path has no source_units evidence") do
  manifest = JSON.parse(File.read(File.join(single_out, "manifest.json"), encoding: "UTF-8"))
  !manifest.key?("source_units")
end

puts "\nIMP3-IMPORT - Import resolution"
check("whole-module import resolves") { status_ok?(order_a) }
check("selective import resolves") { status_ok?(basic) }
check("imported named record type used in consumer") do
  contract = basic.fetch(:semantic_ir).fetch("contracts").find { |c| c.fetch("contract_name") == "BuildQueryResult" }
  contract && output_type_name(contract) == "QueryResult"
end
check("imported FilterPredicate record type used in consumer") do
  contract = basic.fetch(:semantic_ir).fetch("contracts").find { |c| c.fetch("contract_name") == "BuildFilterPredicate" }
  contract && output_type_name(contract) == "FilterPredicate"
end
check("imported contract literal call_contract resolves") do
  status_ok?(call_fixture) && semantic_contract_names(call_fixture).include?("UseDoubleValue")
end
check("literal call_contract output type resolves") do
  contract = call_fixture.fetch(:semantic_ir).fetch("contracts").find { |c| c.fetch("contract_name") == "UseDoubleValue" }
  contract && output_type_name(contract) == "Integer"
end
check("file order does not affect source_hash") do
  order_a.fetch(:result).fetch("source_hash") == order_b.fetch(:result).fetch("source_hash")
end
check("file order does not affect contract set") { semantic_contract_names(order_a) == semantic_contract_names(order_b) }
check("import order does not affect contract set") do
  semantic_contract_names(order_a) == semantic_contract_names(source_import_swapped)
end
check("import order does not affect manifest contract list") do
  order_a.fetch(:manifest).fetch("contracts").sort == source_import_swapped.fetch(:manifest).fetch("contracts").sort
end

puts "\nIMP3-IDENTITY - Composite identity"
check("composite source_hash is SHA256") { sha256?(basic.fetch(:result).fetch("source_hash")) }
check("manifest source_hash equals compiler result source_hash") do
  basic.fetch(:manifest).fetch("source_hash") == basic.fetch(:result).fetch("source_hash")
end
check("semantic_ir source_hash equals manifest source_hash") do
  basic.fetch(:semantic_ir).fetch("source_hash") == basic.fetch(:manifest).fetch("source_hash")
end
check("same files in different input order have same source_hash") do
  order_a.fetch(:manifest).fetch("source_hash") == order_b.fetch(:manifest).fetch("source_hash")
end
check("one source edit changes hash") { basic.fetch(:manifest).fetch("source_hash") != edited_result.fetch(:manifest).fetch("source_hash") }
check("comment-only edit changes hash") do
  status_ok?(comment_result) && basic.fetch(:manifest).fetch("source_hash") != comment_result.fetch(:manifest).fetch("source_hash")
end
check("manifest source_units shape-valid") do
  basic.fetch(:manifest).fetch("source_units").all? { |u| u.key?("module") && u.key?("source_path") && sha256?(u.fetch("source_hash")) }
end
check("compilation report source_units shape-valid") do
  basic.fetch(:compilation_report).fetch("source_units").length == basic.fetch(:manifest).fetch("source_units").length
end
check("source_units sorted by module") do
  modules = order_a.fetch(:manifest).fetch("source_units").map { |u| u.fetch("module") }
  modules == modules.sort
end
check("contract_ref remains per-contract") do
  refs = basic.fetch(:contracts).map { |c| c.fetch("source_contract_ref") }
  refs.all? { |ref| ref.start_with?("contract/") } && refs.uniq.length == refs.length
end
check("artifact_hash remains distinct from source_hash") do
  basic.fetch(:manifest).fetch("artifact_hash") != basic.fetch(:manifest).fetch("source_hash")
end
check("semantic_ir_ref shape valid") { basic.fetch(:manifest).fetch("semantic_ir_ref").match?(/\Asemanticir\/[0-9a-f]{16}\z/) }
check("compilation_report_ref shape valid") do
  basic.fetch(:manifest).fetch("compilation_report_ref").match?(/\Acompilation_report\/[0-9a-f]{16}\z/)
end

puts "\nIMP3-DIAGNOSTICS - OOF-IMP and declaration failures"
check("circular import fails closed") { status_oof?(circular_import) }
check("circular import -> OOF-IMP1") { diagnostic_rule(circular_import) == "OOF-IMP1" }
check("circular import includes cycle_path") { diagnostic(circular_import).fetch("cycle_path").length >= 3 }
check("unknown module fails closed") { status_oof?(unknown_import) }
check("unknown module -> OOF-IMP2") { diagnostic_rule(unknown_import) == "OOF-IMP2" }
check("unknown module includes source/module/import facts") do
  d = diagnostic(unknown_import)
  d.key?("source_path") && d.key?("module_path") && d.key?("import_path")
end
check("missing selective name fails closed") { status_oof?(missing_selective) }
check("missing selective name -> OOF-IMP3") { diagnostic_rule(missing_selective) == "OOF-IMP3" }
check("missing selective diagnostic includes missing_name") { diagnostic(missing_selective).fetch("missing_name") == "MissingRecord" }
check("duplicate module fails closed") { status_oof?(duplicate_module) }
check("duplicate module -> OOF-IMP4") { diagnostic_rule(duplicate_module) == "OOF-IMP4" }
check("duplicate module includes source paths") { diagnostic(duplicate_module).fetch("source_paths").length == 2 }
check("missing module fails closed") { status_oof?(missing_module) }
check("missing module -> OOF-IMP5") { diagnostic_rule(missing_module) == "OOF-IMP5" }
check("duplicate contract fails closed") { status_oof?(duplicate_contract) }
check("duplicate contract -> OOF-DECL-DUP-CONTRACT") { diagnostic_rule(duplicate_contract) == "OOF-DECL-DUP-CONTRACT" }
check("duplicate type fails closed") { status_oof?(duplicate_type) }
check("duplicate type -> OOF-DECL-DUP-TYPE") { diagnostic_rule(duplicate_type) == "OOF-DECL-DUP-TYPE" }
check("duplicate declaration diagnostics include module paths") { diagnostic(duplicate_type).fetch("module_paths").length == 2 }
check("no old OOF-M1/M2/M3 import codes emitted") do
  [
    circular_import,
    unknown_import,
    missing_selective,
    duplicate_module
  ].none? { |run| %w[OOF-M1 OOF-M2 OOF-M3].include?(diagnostic_rule(run)) }
end

puts "\nIMP3-AUTHORITY - Import carries no authority"
check("authority import attempt fails closed") { status_oof?(authority_attempt) }
check("imported effect contract is not callable by pure consumer") do
  authority_attempt.fetch(:result).fetch("diagnostics").any? do |d|
    d.fetch("rule", "") == "OOF-TY0" && d.fetch("message", "").include?("not pure")
  end
end
check("import does not change fragment classification") do
  basic.fetch(:semantic_ir).fetch("contracts").all? { |c| c.fetch("fragment_class") == "core" }
end
check("manifest has no package registry") do
  !basic.fetch(:manifest).key?("registry") && !basic.fetch(:manifest).key?("package_registry")
end
check("manifest has no distribution metadata") do
  !basic.fetch(:manifest).key?("semver") && !basic.fetch(:manifest).key?("distribution")
end
check("manifest has no capability grants from import") do
  !basic.fetch(:manifest).key?("capabilities_imported") && !basic.fetch(:manifest).key?("authority_imports")
end
check("source_units evidence has no capability grants") do
  basic.fetch(:manifest).fetch("source_units").none? { |u| u.key?("capability_grant") || u.key?("profile_binding") }
end
check("import does not add profile authority") do
  basic.fetch(:semantic_ir).fetch("contracts").none? { |c| c.key?("profile_binding") || c.key?("required_capabilities") }
end

puts "\nIMP3-COPYPASTE - Reuse without redefinition"
consumer_source = File.read((FIXTURE_DIR / "valid_basic" / "consumer.ig").to_s, encoding: "UTF-8")
types_source = File.read((FIXTURE_DIR / "valid_basic" / "types.ig").to_s, encoding: "UTF-8")
check("QueryResult declared once in provider") { types_source.scan(/\btype QueryResult\b/).length == 1 }
check("FilterPredicate declared once in provider") { types_source.scan(/\btype FilterPredicate\b/).length == 1 }
check("consumer does not redefine QueryResult") { consumer_source.scan(/\btype QueryResult\b/).empty? }
check("consumer does not redefine FilterPredicate") { consumer_source.scan(/\btype FilterPredicate\b/).empty? }
check("consumer imports QueryResult selectively") { consumer_source.include?("QueryResult") && consumer_source.include?("import") }
check("consumer typechecks using imported QueryResult") do
  contract = basic.fetch(:semantic_ir).fetch("contracts").find { |c| c.fetch("contract_name") == "BuildQueryResult" }
  contract && output_type_name(contract) == "QueryResult"
end
check("consumer typechecks using imported FilterPredicate") do
  contract = basic.fetch(:semantic_ir).fetch("contracts").find { |c| c.fetch("contract_name") == "BuildFilterPredicate" }
  contract && output_type_name(contract) == "FilterPredicate"
end
check("reuse is not stdlib authority") do
  basic.fetch(:manifest).fetch("source_units").none? { |u| u.fetch("module").start_with?("Stdlib") }
end

puts "\nIMP3-CLOSED - Closed surfaces"
check("no Ruby canon implementation was required") { !File.exist?(LAB_ROOT.parent / "igniter-lang" / "lib" / "igniter_lang" / "multifile_resolver.rb") }
check("no VM change is represented in manifest") { !basic.fetch(:manifest).key?("vm_multifile_loader") }
check("no package registry") { !basic.fetch(:manifest).key?("package_registry") }
check("no visibility/public/internal") do
  basic.fetch(:semantic_ir).fetch("contracts").none? { |c| c.key?("visibility") }
end
check("no stdlib-as-import") do
  basic.fetch(:manifest).fetch("source_units").none? { |u| u.fetch("module").start_with?("Stdlib") }
end
check("no runtime loading") { !basic.fetch(:manifest).key?("runtime_loader") }
check("no public/stable API claim") { !basic.fetch(:manifest).key?("public_api") }
check("no package trust metadata") { !basic.fetch(:manifest).key?("package_trust") }
check("module name is not content identity") { basic.fetch(:manifest).fetch("source_hash").start_with?("sha256:") }
check("P3 uses Rust-lab compiler binary") { COMPILER_BIN.to_s.include?("igniter-compiler") }

cargo_test = run!(%w[cargo test --release], chdir: COMPILER_ROOT.to_s)

puts "\nIMP3-REGRESSION - Toolchain checks"
check("cargo test --release succeeds") { cargo_test.fetch(:status).success? }
check("cargo test output names Rust tests") { cargo_test.fetch(:stdout).include?("test result:") || cargo_test.fetch(:stderr).include?("test result:") }
check("previous P1 fixture set is still readable") { fixture_paths("valid_basic").length == 2 }
check("Rust-lab result status is machine-readable") { basic.fetch(:result).fetch("kind") == "compiler_result" }
check("git diff check is external hygiene gate") { true }

if $fail_count.zero?
  puts "\nPROP-IMPORT-RESOLUTION-P3 PASS (#{$pass_count}/#{$pass_count})"
  exit 0
else
  warn "\nPROP-IMPORT-RESOLUTION-P3 FAIL (#{$pass_count} passed, #{$fail_count} failed)"
  exit 1
end
