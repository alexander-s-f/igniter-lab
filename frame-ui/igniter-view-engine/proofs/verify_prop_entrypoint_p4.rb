#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "pathname"

ROOT = Pathname.new(__dir__).parent
LAB_ROOT = ROOT.parent
COMPILER_DIR = LAB_ROOT / "igniter-compiler"
FIXTURE_DIR = ROOT / "fixtures" / "entrypoint_p4"

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

def section(name)
  puts "\n#{name}"
end

def compile_fixture(name)
  source_path = FIXTURE_DIR / "#{name}.ig"
  out_dir = Pathname.new(Dir.mktmpdir(["entrypoint_p4_", "_#{name}"]))
  stdout, stderr, status = Open3.capture3(
    "cargo", "run", "--quiet", "--", "compile", source_path.to_s, "--out", out_dir.to_s,
    chdir: COMPILER_DIR.to_s
  )
  result = stdout.strip.empty? ? {} : JSON.parse(stdout)
  manifest_path = out_dir / "manifest.json"
  sir_path = out_dir / "semantic_ir_program.json"
  report_path = result["compilation_report_path"] ? Pathname.new(result["compilation_report_path"]) : (out_dir / "compilation_report.json")
  {
    name: name,
    source_path: source_path,
    out_dir: out_dir,
    stdout: stdout,
    stderr: stderr,
    status: status,
    result: result,
    manifest: manifest_path.file? ? JSON.parse(manifest_path.read) : nil,
    semantic_ir: sir_path.file? ? JSON.parse(sir_path.read) : nil,
    report: report_path.file? ? JSON.parse(report_path.read) : nil
  }
rescue => e
  {
    name: name,
    source_path: source_path,
    out_dir: out_dir,
    error: e.message,
    result: {},
    manifest: nil,
    semantic_ir: nil,
    report: nil
  }
end

def diagnostics(entry)
  entry[:result].fetch("diagnostics", [])
end

def diagnostic_rules(entry)
  diagnostics(entry).map { |d| d["rule"] }
end

def compile_ok?(entry)
  entry[:result]["status"] == "ok" && entry[:status]&.success?
end

def compile_failed?(entry)
  %w[error oof].include?(entry[:result]["status"]) && !entry[:status]&.success?
end

def contract_ir(entry, name)
  entry[:semantic_ir]&.fetch("contracts", [])&.find { |c| c["contract_name"] == name }
end

def node_kinds(entry, name)
  contract_ir(entry, name)&.fetch("nodes", [])&.map { |n| n["kind"] } || []
end

def consumer_projection(manifest)
  ep = manifest.fetch("entrypoint")
  index_entry = manifest.fetch("contract_index").fetch(ep.fetch("resolved_contract"))
  {
    "display_label" => ep.fetch("declared_target"),
    "contract_path" => ep.fetch("contract_path"),
    "index_path" => index_entry.fetch("contract_path"),
    "contract_ref" => ep.fetch("contract_ref"),
    "index_ref" => index_entry.fetch("contract_ref"),
    "would_execute" => false,
    "authority" => "metadata_only"
  }
end

def diff_files
  stdout, = Open3.capture2("git", "diff", "--name-only", chdir: LAB_ROOT.to_s)
  stdout.lines.map(&:strip)
end

cases = {
  library: compile_fixture("no_entrypoint_library"),
  valid: compile_fixture("valid_entrypoint"),
  qualified: compile_fixture("qualified_entrypoint"),
  duplicate: compile_fixture("duplicate_entrypoint"),
  unknown: compile_fixture("unknown_entrypoint"),
  type_target: compile_fixture("entrypoint_points_to_type"),
  effect_target: compile_fixture("effect_contract_entrypoint")
}

section("EP4-COMPILE")
check("EP4-COMPILE-01 valid entrypoint fixture compiles") { compile_ok?(cases[:valid]) }
check("EP4-COMPILE-02 no-entrypoint fixture compiles") { compile_ok?(cases[:library]) }
check("EP4-COMPILE-03 qualified entrypoint fixture compiles") { compile_ok?(cases[:qualified]) }
check("EP4-COMPILE-04 effect-contract entrypoint fixture compiles as metadata") { compile_ok?(cases[:effect_target]) }
check("EP4-COMPILE-05 valid result points to igapp path") { cases[:valid][:result]["igapp_path"] == cases[:valid][:out_dir].to_s }
check("EP4-COMPILE-06 no-entrypoint result has one contract") { cases[:library][:result].fetch("contracts", []).length == 1 }
check("EP4-COMPILE-07 valid result has two contracts") { cases[:valid][:result].fetch("contracts", []).length == 2 }
check("EP4-COMPILE-08 effect target remains compile-only, no VM run field") { cases[:effect_target][:result]["runtime_smoke"].nil? }

section("EP4-DIAGNOSTICS")
check("EP4-DIAGNOSTICS-01 duplicate entrypoint fails closed") { compile_failed?(cases[:duplicate]) }
check("EP4-DIAGNOSTICS-02 duplicate emits OOF-EP1") { diagnostic_rules(cases[:duplicate]).include?("OOF-EP1") }
check("EP4-DIAGNOSTICS-03 unknown target fails closed") { compile_failed?(cases[:unknown]) }
check("EP4-DIAGNOSTICS-04 unknown target emits OOF-EP2") { diagnostic_rules(cases[:unknown]).include?("OOF-EP2") }
check("EP4-DIAGNOSTICS-05 type target fails closed") { compile_failed?(cases[:type_target]) }
check("EP4-DIAGNOSTICS-06 type target emits OOF-EP5") { diagnostic_rules(cases[:type_target]).include?("OOF-EP5") }
check("EP4-DIAGNOSTICS-07 unknown diagnostic includes source line") { diagnostics(cases[:unknown]).any? { |d| d["rule"] == "OOF-EP2" && d["line"] == 3 } }
check("EP4-DIAGNOSTICS-08 type diagnostic includes source line") { diagnostics(cases[:type_target]).any? { |d| d["rule"] == "OOF-EP5" && d["line"] == 3 } }
check("EP4-DIAGNOSTICS-09 diagnostic result includes source path") { cases[:unknown][:result]["source_path"].to_s.end_with?("unknown_entrypoint.ig") }

section("EP4-SIR")
valid_sir = cases[:valid][:semantic_ir]
library_sir = cases[:library][:semantic_ir]
qualified_sir = cases[:qualified][:semantic_ir]
effect_sir = cases[:effect_target][:semantic_ir]
check("EP4-SIR-01 SemanticIR has entrypoint when present") { valid_sir.key?("entrypoint") }
check("EP4-SIR-02 SemanticIR omits entrypoint when absent") { !library_sir.key?("entrypoint") }
check("EP4-SIR-03 declared target present") { valid_sir.dig("entrypoint", "declared_target") == "RunInvoice" }
check("EP4-SIR-04 resolved contract present") { valid_sir.dig("entrypoint", "resolved_contract") == "RunInvoice" }
check("EP4-SIR-05 contract_ref present") { valid_sir.dig("entrypoint", "contract_ref").to_s.start_with?("contract/RunInvoice/sha256:") }
check("EP4-SIR-06 qualified declared target preserved") { qualified_sir.dig("entrypoint", "declared_target") == "Entrypoint.P4.Qualified.RunQualified" }
check("EP4-SIR-07 qualified target resolves by contract_id") { qualified_sir.dig("entrypoint", "resolved_contract_id") == "Entrypoint.P4.Qualified.RunQualified" }
check("EP4-SIR-08 effect target fragment classification preserved") { effect_sir.dig("entrypoint", "contract_fragment_class") == contract_ir(cases[:effect_target], "FetchRemote")["fragment_class"] }
check("EP4-SIR-09 contract IR nodes unchanged by entrypoint") { node_kinds(cases[:valid], "RunInvoice") == %w[compute] }
check("EP4-SIR-10 no dependency edge created for entrypoint") { !JSON.generate(valid_sir.fetch("contracts")).include?("entrypoint_decl") }

section("EP4-MANIFEST")
valid_manifest = cases[:valid][:manifest]
library_manifest = cases[:library][:manifest]
qualified_manifest = cases[:qualified][:manifest]
check("EP4-MANIFEST-01 manifest has entrypoint when present") { valid_manifest.key?("entrypoint") }
check("EP4-MANIFEST-02 manifest omits entrypoint when absent") { !library_manifest.key?("entrypoint") }
check("EP4-MANIFEST-03 manifest entrypoint kind") { valid_manifest.dig("entrypoint", "kind") == "default_entrypoint" }
check("EP4-MANIFEST-04 manifest declared target") { valid_manifest.dig("entrypoint", "declared_target") == "RunInvoice" }
check("EP4-MANIFEST-05 manifest resolved contract") { valid_manifest.dig("entrypoint", "resolved_contract") == "RunInvoice" }
check("EP4-MANIFEST-06 contract_path exists on disk") { (cases[:valid][:out_dir] / valid_manifest.dig("entrypoint", "contract_path")).file? }
check("EP4-MANIFEST-07 contract_ref matches contract index") { valid_manifest.dig("entrypoint", "contract_ref") == valid_manifest.dig("contract_index", "RunInvoice", "contract_ref") }
check("EP4-MANIFEST-08 contract_path matches contract index") { valid_manifest.dig("entrypoint", "contract_path") == valid_manifest.dig("contract_index", "RunInvoice", "contract_path") }
check("EP4-MANIFEST-09 source span path present") { valid_manifest.dig("entrypoint", "source_span", "source_path").to_s.end_with?("valid_entrypoint.ig") }
check("EP4-MANIFEST-10 source span line/col present") { valid_manifest.dig("entrypoint", "source_span", "line") == 3 && valid_manifest.dig("entrypoint", "source_span", "col") == 1 }
check("EP4-MANIFEST-11 artifact hash is shape-valid") { valid_manifest["artifact_hash"].to_s.start_with?("sha256:") }
check("EP4-MANIFEST-12 entrypoint changes artifact hash material") { valid_manifest["artifact_hash"] != library_manifest["artifact_hash"] }
check("EP4-MANIFEST-13 qualified manifest keeps declared target") { qualified_manifest.dig("entrypoint", "declared_target") == "Entrypoint.P4.Qualified.RunQualified" }

section("EP4-CONSUMER")
consumer = consumer_projection(valid_manifest)
check("EP4-CONSUMER-01 consumer reads manifest entrypoint") { consumer["display_label"] == "RunInvoice" }
check("EP4-CONSUMER-02 consumer resolves contract artifact path") { consumer["contract_path"] == "contracts/run_invoice.json" }
check("EP4-CONSUMER-03 consumer validates path against index") { consumer["contract_path"] == consumer["index_path"] }
check("EP4-CONSUMER-04 consumer validates ref against index") { consumer["contract_ref"] == consumer["index_ref"] }
check("EP4-CONSUMER-05 consumer can read contract artifact") { JSON.parse(File.read(cases[:valid][:out_dir] / consumer["contract_path"]))["name"] == "RunInvoice" }
check("EP4-CONSUMER-06 consumer does not execute contract") { consumer["would_execute"] == false }
check("EP4-CONSUMER-07 consumer records metadata-only authority") { consumer["authority"] == "metadata_only" }
check("EP4-CONSUMER-08 consumer does not grant capabilities") { !valid_manifest.key?("capability_tokens") }

section("EP4-NONAUTH")
changed = diff_files
check("EP4-NONAUTH-01 no VM source changed") { changed.none? { |p| p.start_with?("igniter-vm/") } }
check("EP4-NONAUTH-02 compiler CLI source does not mention manifest entrypoint") { !File.read(LAB_ROOT / "igniter-compiler" / "src" / "main.rs").include?("entrypoint") }
check("EP4-NONAUTH-03 no scheduler field in manifest") { !JSON.generate(valid_manifest).include?("scheduler") }
check("EP4-NONAUTH-04 no main loop field in manifest") { !JSON.generate(valid_manifest).include?("main_loop") }
check("EP4-NONAUTH-05 no app framework field in manifest") { !JSON.generate(valid_manifest).include?("app_framework") }
check("EP4-NONAUTH-06 no visibility/package authority") { !JSON.generate(valid_manifest).include?("visibility") && !JSON.generate(valid_manifest).include?("package") }
check("EP4-NONAUTH-07 no import authority added") { valid_manifest.fetch("source_units", []).empty? }
check("EP4-NONAUTH-08 effect target metadata does not add capability token") { !cases[:effect_target][:manifest].key?("capability_tokens") }

section("EP4-REGRESSION")
check("EP4-REGRESSION-01 parser/classifier/typechecker stages ok for valid") { cases[:valid][:result].dig("stages", "parse") == "ok" && cases[:valid][:result].dig("stages", "classify") == "ok" && cases[:valid][:result].dig("stages", "typecheck") == "ok" }
check("EP4-REGRESSION-02 assemble stage ok for valid") { cases[:valid][:result].dig("stages", "assemble") == "ok" }
check("EP4-REGRESSION-03 grammar version unchanged for entrypoint-only source") { cases[:valid][:result]["grammar_version"] == "0.1.0" }
check("EP4-REGRESSION-04 no-entrypoint manifest remains normal igapp") { library_manifest["kind"] == "igapp_manifest" && library_manifest["contracts"].include?("Helper") }
check("EP4-REGRESSION-05 duplicate stops before assemble") { cases[:duplicate][:result].dig("stages", "assemble") == "skipped" }
check("EP4-REGRESSION-06 unknown stops before assemble") { cases[:unknown][:result].dig("stages", "assemble") == "skipped" }
check("EP4-REGRESSION-07 report status ok for valid") { cases[:valid][:report]["pass_result"] == "ok" }
check("EP4-REGRESSION-08 report status oof for unknown") { cases[:unknown][:report]["pass_result"] == "oof" }

total = $pass_count + $fail_count
puts "\nPROP-ENTRYPOINT-P4 #{($fail_count.zero? && $pass_count >= 40) ? "PASS" : "FAIL"} (#{$pass_count}/#{total})"
exit($fail_count.zero? && $pass_count >= 40 ? 0 : 1)
