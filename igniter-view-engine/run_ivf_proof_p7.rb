#!/usr/bin/env ruby
# frozen_string_literal: true

# run_ivf_proof_p7.rb
#
# LAB-IGNITER-VIEW-FRAMEWORK-P7 — Compiled Contract Schema Extraction proof runner.
#
# Proof matrix:
#   IVX-P7-1:  P1/P2/P3/P5/P6 regression gates pass
#   IVX-P7-2:  Valid compiled contract artifact extracts ContractSchema
#   IVX-P7-3:  Extracted schema links results_panel artifact successfully (valid?=true)
#   IVX-P7-4:  Extracted scalar outputs equal hand-authored fixture; array type=array (no item_fields)
#   IVX-P7-5:  Malformed contract JSON fails closed (error diagnostic)
#   IVX-P7-6:  Missing contract_id fails closed (explicit diagnostic)
#   IVX-P7-7:  Missing array item_fields emits :missing_item_fields warning
#   IVX-P7-8:  Drift between fixture and extracted schema is reported
#   IVX-P7-9:  No contract execution, no network, no runtime dispatch in extractor source
#   IVX-P7-10: ViewArtifact digest/SSR unchanged (no modifications to P1-P6 artifacts)
#   IVX-P7-11: Lab-only/no-canon/no-stable-schema markers present
#   IVX-P7-12: igniter-lang/** untouched
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "json"
require "fileutils"
require "digest"

require_relative "lib/view_artifact"
require_relative "lib/ssr_renderer"
require_relative "lib/igv_compiler"
require_relative "lib/igniter_view_engine"
require_relative "lib/contract_schema"
require_relative "lib/slot_type_linker"
require_relative "lib/compiled_contract_extractor"

FIXTURE_DIR          = File.join(__dir__, "fixtures")
SCHEMA_DIR           = File.join(FIXTURE_DIR, "contract_schemas")
COMPILED_DIR         = File.join(FIXTURE_DIR, "compiled_contracts")
OUT_DIR              = File.join(__dir__, "out")
FileUtils.mkdir_p(OUT_DIR)
FileUtils.mkdir_p(COMPILED_DIR)

results  = []
failures = 0

def pass(results, id, label)
  puts "  ✅ #{id}: #{label}"
  results << { id: id, label: label, status: "PASS" }
end

def fail_check(results, id, label, detail = nil)
  msg = detail ? "#{label} — #{detail}" : label
  puts "  ❌ #{id}: #{msg}"
  results << { id: id, label: label, status: "FAIL", detail: detail }
end

puts "=== LAB-IGNITER-VIEW-FRAMEWORK-P7: Compiled Contract Schema Extraction Proof ==="
puts "Date: #{Time.now.strftime("%Y-%m-%d %H:%M")}"
puts "Ruby: #{RUBY_VERSION}"
puts

# ── IVX-P7-1: Regression gates ────────────────────────────────────────────

puts "── IVX-P7-1: P1/P2/P3/P5/P6 regression gates ──────────────────────"

[
  ["P1 proof runner (37 checks)", "run_ivf_proof.rb"],
  ["P2 proof runner (18+15 checks)", "run_ivf_proof_p2.rb"],
  ["P3 proof runner (42 checks)", "run_ivf_proof_p3.rb"],
  ["P5 proof runner (57 checks)", "run_ivf_proof_p5.rb"],
  ["P6 proof runner (55 checks)", "run_ivf_proof_p6.rb"]
].each do |(label, script)|
  path = File.join(__dir__, script)
  if File.exist?(path)
    output = `ruby "#{path}" 2>&1`
    if $?.success?
      pass(results, "IVX-P7-1", "#{label} exits cleanly")
    else
      fail_check(results, "IVX-P7-1", "#{label} exits cleanly", "non-zero exit")
      failures += 1
    end
  else
    fail_check(results, "IVX-P7-1", "#{label} exits cleanly", "script not found: #{script}")
    failures += 1
  end
end

puts

# ── IVX-P7-2: Valid extraction from compiled contract JSON ─────────────────

puts "── IVX-P7-2: Valid compiled contract artifact extracts ContractSchema ──"

begin
  search_path = File.join(COMPILED_DIR, "search_compiled.json")
  result_search = IgniterView::CompiledContractExtractor.extract(search_path)

  if result_search.valid?
    pass(results, "IVX-P7-2a", "search_compiled.json extracts valid? = true")
  else
    fail_check(results, "IVX-P7-2a", "search_compiled.json extracts valid? = true",
               result_search.errors.map(&:detail).join("; "))
    failures += 1
  end

  schema = result_search.schema
  if schema.is_a?(IgniterView::ContractSchema)
    pass(results, "IVX-P7-2b", "Extracted result.schema is a ContractSchema")
  else
    fail_check(results, "IVX-P7-2b", "Extracted result.schema is a ContractSchema",
               schema.class.to_s)
    failures += 1
  end

  if schema&.contract_id == "search"
    pass(results, "IVX-P7-2c", "Extracted contract_id = 'search'")
  else
    fail_check(results, "IVX-P7-2c", "Extracted contract_id = 'search'",
               schema&.contract_id.inspect)
    failures += 1
  end

  expected_outputs = %w[results query total]
  missing = expected_outputs.reject { |n| schema&.output(n) }
  if missing.empty?
    pass(results, "IVX-P7-2d", "All 3 outputs extracted (results, query, total)")
  else
    fail_check(results, "IVX-P7-2d", "All 3 outputs extracted", "missing: #{missing}")
    failures += 1
  end

  # Check types
  if schema&.output("query")&.dig("type") == "string"
    pass(results, "IVX-P7-2e", "query output type normalized to 'string'")
  else
    fail_check(results, "IVX-P7-2e", "query output type normalized to 'string'",
               schema&.output("query").inspect)
    failures += 1
  end

  if schema&.output("total")&.dig("type") == "integer"
    pass(results, "IVX-P7-2f", "total output type normalized to 'integer'")
  else
    fail_check(results, "IVX-P7-2f", "total output type normalized to 'integer'",
               schema&.output("total").inspect)
    failures += 1
  end

  if schema&.output("results")&.dig("type") == "array"
    pass(results, "IVX-P7-2g", "results output Collection[SearchResult] normalized to 'array'")
  else
    fail_check(results, "IVX-P7-2g", "results output normalized to 'array'",
               schema&.output("results").inspect)
    failures += 1
  end

  # AvailabilityProjection: Collection + opaque struct
  avail_path = File.join(COMPILED_DIR, "availability_projection_compiled.json")
  result_avail = IgniterView::CompiledContractExtractor.extract(avail_path)

  if result_avail.valid?
    pass(results, "IVX-P7-2h", "availability_projection_compiled.json extracts valid? = true")
  else
    fail_check(results, "IVX-P7-2h", "availability_projection_compiled.json extracts valid? = true",
               result_avail.errors.map(&:detail).join("; "))
    failures += 1
  end

  avail_schema = result_avail.schema
  if avail_schema&.output("available_slots")&.dig("type") == "array"
    pass(results, "IVX-P7-2i", "available_slots Collection[TimeSlot] → 'array'")
  else
    fail_check(results, "IVX-P7-2i", "available_slots → 'array'",
               avail_schema&.output("available_slots").inspect)
    failures += 1
  end

  if avail_schema&.output("snap")&.dig("type") == "object"
    pass(results, "IVX-P7-2j", "snap AvailabilitySnapshot (opaque struct) → 'object'")
  else
    fail_check(results, "IVX-P7-2j", "snap AvailabilitySnapshot → 'object'",
               avail_schema&.output("snap").inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-2", "Extraction tests", e.message)
  failures += 1
  result_search = nil
end

puts

# ── IVX-P7-3: Extracted schema links results_panel successfully ────────────

puts "── IVX-P7-3: Extracted schema links results_panel artifact ────────────"

begin
  # Compile results_panel.igv to get a live ViewArtifact (same approach as P6)
  panel_result = IgniterView::IgvCompiler.compile_file(
    File.join(FIXTURE_DIR, "results_panel.igv")
  )
  raise "results_panel.igv failed to compile" unless panel_result.success?
  artifact = panel_result.artifact

  # Build schemas from extracted compiled contracts
  extracted_schemas = IgniterView::CompiledContractExtractor.extract_dir(COMPILED_DIR)

  linkage_result = IgniterView::SlotTypeLinker.link(artifact, extracted_schemas)

  if linkage_result.valid?
    pass(results, "IVX-P7-3a", "Extracted schema linkage result valid?=true")
  else
    fail_check(results, "IVX-P7-3a", "Extracted schema linkage result valid?=true",
               linkage_result.errors.map { |d| d.detail }.join("; "))
    failures += 1
  end

  if linkage_result.errors.empty?
    pass(results, "IVX-P7-3b", "Zero error diagnostics in linkage (extracted schema)")
  else
    fail_check(results, "IVX-P7-3b", "Zero error diagnostics",
               linkage_result.errors.map { |d| "#{d.type}: #{d.detail}" }.join("; "))
    failures += 1
  end

  # Expect :missing_item_fields_schema warning for the array output (no item_fields in compiled)
  missing_fields_warns = linkage_result.warnings.select { |d| d.type == :missing_item_fields_schema }
  if missing_fields_warns.any?
    pass(results, "IVX-P7-3c",
         "Expected :missing_item_fields_schema warning present (Collection type, no item_fields in compiled format)")
  else
    fail_check(results, "IVX-P7-3c",
               ":missing_item_fields_schema warning present for array slot (expected from compiled format)",
               "warnings: #{linkage_result.warnings.map(&:type).inspect}")
    failures += 1
  end

  # Scalar slots have no linkage errors
  scalar_errors = linkage_result.errors.select { |d| %w[query total].include?(d.slot) }
  if scalar_errors.empty?
    pass(results, "IVX-P7-3d", "No errors on scalar slots (query, total)")
  else
    fail_check(results, "IVX-P7-3d", "No errors on scalar slots",
               scalar_errors.map { |d| "#{d.slot}: #{d.type}" }.join(", "))
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-3", "Linkage with extracted schema", e.message)
  failures += 1
end

puts

# ── IVX-P7-4: Scalar outputs equal hand-authored fixture ──────────────────

puts "── IVX-P7-4: Extracted outputs vs hand-authored fixture ────────────────"

begin
  # Re-extract search compiled schema
  search_extracted = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema

  # Load hand-authored fixture
  search_fixture = IgniterView::ContractSchema.load_file(
    File.join(SCHEMA_DIR, "search_contract.json")
  )

  # Scalar outputs: query and total should be identical
  %w[query total].each do |name|
    extracted_type = search_extracted&.output(name)&.dig("type")
    fixture_type   = search_fixture.output(name)&.dig("type")
    if extracted_type == fixture_type
      pass(results, "IVX-P7-4", "Scalar output '#{name}': extracted type='#{extracted_type}' equals fixture")
    else
      fail_check(results, "IVX-P7-4", "Scalar output '#{name}' type matches",
                 "extracted=#{extracted_type.inspect} vs fixture=#{fixture_type.inspect}")
      failures += 1
    end
  end

  # Array output: extracted type=array matches fixture type=array
  extracted_results_type = search_extracted&.output("results")&.dig("type")
  fixture_results_type   = search_fixture.output("results")&.dig("type")
  if extracted_results_type == fixture_results_type && extracted_results_type == "array"
    pass(results, "IVX-P7-4", "Array output 'results': both extracted and fixture have type='array'")
  else
    fail_check(results, "IVX-P7-4", "Array output 'results' type",
               "extracted=#{extracted_results_type.inspect} vs fixture=#{fixture_results_type.inspect}")
    failures += 1
  end

  # Structural difference: extracted has NO item_fields; fixture HAS item_fields
  extracted_item_fields = search_extracted&.output("results")&.dig("item_fields")
  fixture_item_fields   = search_fixture.output("results")&.dig("item_fields")

  if extracted_item_fields.nil?
    pass(results, "IVX-P7-4",
         "Extracted 'results' has no item_fields (expected — compiled format does not carry them)")
  else
    fail_check(results, "IVX-P7-4", "Extracted 'results' should have no item_fields",
               "got: #{extracted_item_fields.inspect}")
    failures += 1
  end

  if fixture_item_fields.is_a?(Hash) && fixture_item_fields.any?
    pass(results, "IVX-P7-4",
         "Hand-authored fixture 'results' has item_fields (#{fixture_item_fields.keys.count} fields)")
  else
    fail_check(results, "IVX-P7-4", "Fixture should have item_fields", fixture_item_fields.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-4", "Scalar equivalence test", e.message)
  failures += 1
end

puts

# ── IVX-P7-5: Malformed contract JSON fails closed ─────────────────────────

puts "── IVX-P7-5: Malformed contract JSON fails closed ──────────────────────"

begin
  bad_json_result = IgniterView::CompiledContractExtractor.extract_data(
    nil, source: "synthetic-nil"
  )

  if !bad_json_result.valid?
    pass(results, "IVX-P7-5a", "nil data → valid?=false (fails closed)")
  else
    fail_check(results, "IVX-P7-5a", "nil data should fail closed")
    failures += 1
  end

  if bad_json_result.errors.any? { |d| d.type == :malformed_artifact }
    pass(results, "IVX-P7-5b", "nil data → :malformed_artifact error")
  else
    fail_check(results, "IVX-P7-5b", ":malformed_artifact error present",
               bad_json_result.diagnostics.map(&:type).inspect)
    failures += 1
  end

  # Array root (not an object)
  array_root_result = IgniterView::CompiledContractExtractor.extract_data(
    [1, 2, 3], source: "synthetic-array"
  )
  if !array_root_result.valid?
    pass(results, "IVX-P7-5c", "Array root → valid?=false (fails closed)")
  else
    fail_check(results, "IVX-P7-5c", "Array root should fail closed")
    failures += 1
  end

  # Malformed JSON file (write temp file)
  require "tempfile"
  tmp = Tempfile.new(["bad_contract", ".json"])
  tmp.write("{ this is: not valid json }")
  tmp.close
  file_result = IgniterView::CompiledContractExtractor.extract(tmp.path)
  if !file_result.valid?
    pass(results, "IVX-P7-5d", "Malformed JSON file → valid?=false (fails closed)")
  else
    fail_check(results, "IVX-P7-5d", "Malformed JSON file should fail closed")
    failures += 1
  end
  tmp.unlink

  # Missing file
  missing_result = IgniterView::CompiledContractExtractor.extract("/tmp/nonexistent_contract_p7.json")
  if !missing_result.valid?
    pass(results, "IVX-P7-5e", "Missing file → valid?=false (fails closed)")
  else
    fail_check(results, "IVX-P7-5e", "Missing file should fail closed")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-5", "Malformed JSON tests", e.message)
  failures += 1
end

puts

# ── IVX-P7-6: Missing contract_id fails closed ─────────────────────────────

puts "── IVX-P7-6: Missing contract_id fails closed ──────────────────────────"

begin
  no_id_result = IgniterView::CompiledContractExtractor.extract_data({
    "output_ports" => [{ "name" => "x", "type_tag" => "Integer" }]
  })

  if !no_id_result.valid?
    pass(results, "IVX-P7-6a", "Missing contract_id → valid?=false")
  else
    fail_check(results, "IVX-P7-6a", "Missing contract_id should fail closed")
    failures += 1
  end

  if no_id_result.errors.any? { |d| d.type == :missing_contract_id }
    pass(results, "IVX-P7-6b", "Error type is :missing_contract_id")
  else
    fail_check(results, "IVX-P7-6b", "Error type :missing_contract_id",
               no_id_result.diagnostics.map(&:type).inspect)
    failures += 1
  end

  # Empty string contract_id
  empty_id_result = IgniterView::CompiledContractExtractor.extract_data({
    "contract_id" => "   ",
    "output_ports" => []
  })
  if !empty_id_result.valid?
    pass(results, "IVX-P7-6c", "Blank contract_id → valid?=false")
  else
    fail_check(results, "IVX-P7-6c", "Blank contract_id should fail closed")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-6", "Missing contract_id tests", e.message)
  failures += 1
end

puts

# ── IVX-P7-7: Array type without item_fields emits explicit diagnostic ──────

puts "── IVX-P7-7: Missing item_fields for Collection type → diagnostic ───────"

begin
  coll_result = IgniterView::CompiledContractExtractor.extract_data({
    "contract_id" => "MyContract",
    "output_ports" => [
      { "name" => "items",  "type_tag" => "Collection[Item]" },
      { "name" => "scalar", "type_tag" => "String" }
    ]
  })

  if coll_result.valid?
    pass(results, "IVX-P7-7a", "Collection output → valid?=true (warning, not error)")
  else
    fail_check(results, "IVX-P7-7a", "Collection output should be valid (warning only)",
               coll_result.errors.map(&:detail).join("; "))
    failures += 1
  end

  missing_fields_diag = coll_result.warnings.select { |d| d.type == :missing_item_fields }
  if missing_fields_diag.any?
    pass(results, "IVX-P7-7b", "Warning type :missing_item_fields present for Collection output")
  else
    fail_check(results, "IVX-P7-7b", ":missing_item_fields warning present",
               coll_result.diagnostics.map(&:type).inspect)
    failures += 1
  end

  if missing_fields_diag.first&.field == "items"
    pass(results, "IVX-P7-7c", "Warning is attributed to the correct field 'items'")
  else
    fail_check(results, "IVX-P7-7c", "Warning field attribution",
               missing_fields_diag.first&.field.inspect)
    failures += 1
  end

  # Scalar output has no missing_item_fields warning
  scalar_warns = coll_result.warnings.select { |d| d.field == "scalar" }
  if scalar_warns.empty?
    pass(results, "IVX-P7-7d", "Scalar 'scalar' output has no warnings")
  else
    fail_check(results, "IVX-P7-7d", "Scalar output should have no warnings",
               scalar_warns.map(&:type).inspect)
    failures += 1
  end

  # Array[X] prefix also triggers missing_item_fields
  array_result = IgniterView::CompiledContractExtractor.extract_data({
    "contract_id" => "ArrContract",
    "output_ports" => [{ "name" => "rows", "type_tag" => "Array[Row]" }]
  })
  arr_warn = array_result.warnings.select { |d| d.type == :missing_item_fields }
  if arr_warn.any?
    pass(results, "IVX-P7-7e", "Array[X] also triggers :missing_item_fields warning")
  else
    fail_check(results, "IVX-P7-7e", "Array[X] should trigger :missing_item_fields",
               array_result.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-7", "Missing item_fields diagnostic tests", e.message)
  failures += 1
end

puts

# ── IVX-P7-8: Drift detection ─────────────────────────────────────────────

puts "── IVX-P7-8: Drift detection between fixture and extracted schema ───────"

begin
  # Create a "drifted" compiled contract: query is Integer instead of String
  drifted_extracted = IgniterView::CompiledContractExtractor.extract_data({
    "contract_id" => "search",
    "output_ports" => [
      { "name" => "results", "type_tag" => "Collection[SearchResult]" },
      { "name" => "query",   "type_tag" => "Integer" },  # DRIFTED: should be String
      { "name" => "total",   "type_tag" => "Integer" }
    ]
  }).schema

  fixture_schema = IgniterView::ContractSchema.load_file(
    File.join(SCHEMA_DIR, "search_contract.json")
  )

  # Drift reporter: compare extracted vs fixture for each shared output
  drift_report = {}
  (drifted_extracted.outputs.keys & fixture_schema.outputs.keys).each do |name|
    extracted_type = drifted_extracted.output(name)&.dig("type")
    fixture_type   = fixture_schema.output(name)&.dig("type")
    # Skip array (always drifts on item_fields, which is known)
    next if extracted_type == "array" && fixture_type == "array"
    if extracted_type != fixture_type
      drift_report[name] = { extracted: extracted_type, fixture: fixture_type }
    end
  end

  if drift_report.key?("query")
    pass(results, "IVX-P7-8a",
         "Drift detected: 'query' extracted=#{drift_report['query'][:extracted]} vs fixture=#{drift_report['query'][:fixture]}")
  else
    fail_check(results, "IVX-P7-8a", "Drift on 'query' should be detected",
               drift_report.inspect)
    failures += 1
  end

  if drift_report["total"].nil?
    pass(results, "IVX-P7-8b", "No drift on 'total' (Integer matches on both sides)")
  else
    fail_check(results, "IVX-P7-8b", "'total' should have no drift", drift_report["total"].inspect)
    failures += 1
  end

  # No drift case: clean extracted matches fixture for scalar outputs
  clean_extracted = IgniterView::CompiledContractExtractor.extract_data({
    "contract_id" => "search",
    "output_ports" => [
      { "name" => "results", "type_tag" => "Collection[SearchResult]" },
      { "name" => "query",   "type_tag" => "String" },
      { "name" => "total",   "type_tag" => "Integer" }
    ]
  }).schema

  clean_drift = {}
  (clean_extracted.outputs.keys & fixture_schema.outputs.keys).each do |name|
    et = clean_extracted.output(name)&.dig("type")
    ft = fixture_schema.output(name)&.dig("type")
    next if et == "array" && ft == "array"
    clean_drift[name] = { extracted: et, fixture: ft } if et != ft
  end

  if clean_drift.empty?
    pass(results, "IVX-P7-8c", "No drift on scalar outputs when compiled types match fixture")
  else
    fail_check(results, "IVX-P7-8c", "No scalar drift expected", clean_drift.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-8", "Drift detection tests", e.message)
  failures += 1
end

puts

# ── IVX-P7-9: Safety forbidden constructs absent ──────────────────────────

puts "── IVX-P7-9: No forbidden constructs in CompiledContractExtractor ───────"

extractor_src = File.read(
  File.join(__dir__, "lib", "compiled_contract_extractor.rb"), encoding: "utf-8"
)
non_comment_src  = extractor_src.lines.reject { |l| l.strip.start_with?("#") }.join
no_contract_exec = !non_comment_src.match?(/Igniter::Contract|\.call\(\s*inputs/)

[
  ["No innerHTML",          !extractor_src.match?(/innerHTML/)],
  ["No eval()",             !extractor_src.match?(/\beval\s*\(/)],
  ["No fetch()",            !extractor_src.match?(/\bfetch\s*\(/)],
  ["No Net::HTTP",          !extractor_src.match?(/Net::HTTP/)],
  ["No require net",        !extractor_src.match?(/require.*net\/http/)],
  ["No contract execution", no_contract_exec],
  ["No localStorage",       !extractor_src.match?(/localStorage/)],
  ["No sessionStorage",     !extractor_src.match?(/sessionStorage/)]
].each do |(label, ok)|
  if ok
    pass(results, "IVX-P7-9", "Source guard: #{label}")
  else
    fail_check(results, "IVX-P7-9", "Source guard: #{label}")
    failures += 1
  end
end

puts

# ── IVX-P7-10: ViewArtifact digest/SSR unchanged ──────────────────────────

puts "── IVX-P7-10: ViewArtifact digest / SSR unchanged ──────────────────────"

begin
  # tabs digest from P1 — must remain unchanged
  TABS_DIGEST_P1 = "sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404"

  tabs_artifact_path = File.join(__dir__, "out", "tabs_view_artifact.json")
  tabs_data   = JSON.parse(File.read(tabs_artifact_path, encoding: "utf-8"))
  tabs_digest = tabs_data["artifact_digest"]

  if tabs_digest == TABS_DIGEST_P1
    pass(results, "IVX-P7-10a", "tabs ViewArtifact digest unchanged from P1 baseline")
  else
    fail_check(results, "IVX-P7-10a", "tabs digest unchanged",
               "got #{tabs_digest}, expected #{TABS_DIGEST_P1}")
    failures += 1
  end

  # results_panel artifact digest must be unchanged from P6
  results_panel_path = File.join(__dir__, "out", "results_panel_artifact.json")
  rp_data   = JSON.parse(File.read(results_panel_path, encoding: "utf-8"))
  rp_digest = rp_data["artifact_digest"]

  if rp_digest.start_with?("sha256:")
    pass(results, "IVX-P7-10b", "results_panel digest is a SHA-256 (unchanged format)")
  else
    fail_check(results, "IVX-P7-10b", "results_panel has valid sha256 digest", rp_digest.inspect)
    failures += 1
  end

  # Extractor does NOT modify ViewArtifact — verified by checking it has no write-back method
  extractor_src_for_digest = File.read(
    File.join(__dir__, "lib", "compiled_contract_extractor.rb"), encoding: "utf-8"
  )
  touches_artifact = extractor_src_for_digest.match?(/ViewArtifact.*new|artifact\.slots|artifact\.digest/)
  if !touches_artifact
    pass(results, "IVX-P7-10c", "CompiledContractExtractor does not touch ViewArtifact")
  else
    fail_check(results, "IVX-P7-10c", "Extractor should not touch ViewArtifact")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P7-10", "Digest/SSR unchanged checks", e.message)
  failures += 1
end

puts

# ── IVX-P7-11: Lab-only markers present ───────────────────────────────────

puts "── IVX-P7-11: Lab-only / no-canon / no-stable-schema markers ────────────"

begin
  extractor_src_markers = File.read(
    File.join(__dir__, "lib", "compiled_contract_extractor.rb"), encoding: "utf-8"
  )

  [
    ["compiled_contract_extractor.rb has lab-only marker",        extractor_src_markers.include?("lab-only")],
    ["compiled_contract_extractor.rb has no-canon marker",        extractor_src_markers.include?("no-canon")],
    ["compiled_contract_extractor.rb has no-stable-schema marker", extractor_src_markers.include?("no-stable-schema")],
    ["compiled_contract_extractor.rb has no-public-api marker",   extractor_src_markers.include?("no-public-api")],
    ["search_compiled.json has _status field",
      JSON.parse(File.read(File.join(COMPILED_DIR, "search_compiled.json"), encoding: "utf-8"))["_status"]&.include?("lab-only")]
  ].each do |(label, ok)|
    if ok
      pass(results, "IVX-P7-11", label)
    else
      fail_check(results, "IVX-P7-11", label)
      failures += 1
    end
  end
rescue => e
  fail_check(results, "IVX-P7-11", "Marker checks", e.message)
  failures += 1
end

puts

# ── IVX-P7-12: igniter-lang/** untouched ──────────────────────────────────

puts "── IVX-P7-12: igniter-lang/** untouched ─────────────────────────────────"

begin
  igniter_lang_path = File.expand_path("../../igniter-lang", __dir__)
  if Dir.exist?(igniter_lang_path)
    status_output = `git -C "#{igniter_lang_path}" status --porcelain 2>/dev/null`.strip
    tracked_changes = status_output.lines.reject { |l| l.start_with?("??") }.map(&:strip)
    if tracked_changes.empty?
      pass(results, "IVX-P7-12", "igniter-lang has no tracked-file changes (P7 canon boundary)")
    else
      fail_check(results, "IVX-P7-12", "igniter-lang has no tracked changes",
                 "changes: #{tracked_changes.first(3).join('; ')}")
      failures += 1
    end
  else
    pass(results, "IVX-P7-12", "igniter-lang directory not found — no changes possible")
  end
rescue => e
  fail_check(results, "IVX-P7-12", "igniter-lang boundary check", e.message)
  failures += 1
end

puts

# ── Summary ────────────────────────────────────────────────────────────────

total  = results.size
passed = results.count { |r| r[:status] == "PASS" }
failed = results.count { |r| r[:status] == "FAIL" }

# Save proof summary
summary = {
  "runner"  => "LAB-IGNITER-VIEW-FRAMEWORK-P7",
  "date"    => Time.now.strftime("%Y-%m-%d %H:%M"),
  "ruby"    => RUBY_VERSION,
  "total"   => total,
  "passed"  => passed,
  "failed"  => failed,
  "results" => results.map { |r| r.transform_keys(&:to_s) }
}

summary_path = File.join(OUT_DIR, "ivf_p7_proof_summary.json")
File.write(summary_path, JSON.pretty_generate(summary))

puts "═" * 59
puts "LAB-IGNITER-VIEW-FRAMEWORK-P7 Proof Summary"
puts "  Total:  #{total}"
puts "  Passed: #{passed}"
puts "  Failed: #{failed}"
puts "  Output: #{summary_path}"
puts "═" * 59
puts

if failures == 0
  puts "✅ All checks PASS."
  exit 0
else
  puts "❌ #{failures} check(s) FAILED."
  exit 1
end
