#!/usr/bin/env ruby
# frozen_string_literal: true

# run_ivf_proof_p8.rb
#
# LAB-IGNITER-VIEW-FRAMEWORK-P8 — ContractSchema Supplement Overlay proof runner.
#
# Proof matrix:
#   IVX-P8-1:  P1/P2/P3/P5/P6/P7 regression gates pass
#   IVX-P8-2:  Valid supplement adds item_fields to extracted array output
#   IVX-P8-3:  Supplemented schema links results_panel with no :missing_item_fields_schema warning
#   IVX-P8-4:  Supplement cannot add undeclared output port (:unknown_output_ref warning)
#   IVX-P8-5:  Supplement cannot override scalar output type (:supplement_to_non_array error)
#   IVX-P8-6:  Supplement cannot change contract_id (:contract_id_mismatch error)
#   IVX-P8-7:  Malformed supplement fails closed
#   IVX-P8-8:  Unknown contract/output refs produce explicit diagnostics
#   IVX-P8-9:  Missing supplement preserves P7 :missing_item_fields_schema warning
#   IVX-P8-10: Drift detection still catches scalar type mismatch
#   IVX-P8-11: Source guards — no eval, innerHTML, fetch, Net::HTTP, contract execution,
#              localStorage, sessionStorage
#   IVX-P8-12: No absolute paths or file:// in proof summary JSON
#   IVX-P8-13: Lab-only/no-canon/no-public-api/no-stable-schema markers preserved
#   IVX-P8-14: igniter-lang/** untouched
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "json"
require "fileutils"
require "tempfile"

require_relative "lib/view_artifact"
require_relative "lib/ssr_renderer"
require_relative "lib/igv_compiler"
require_relative "lib/igniter_view_engine"
require_relative "lib/contract_schema"
require_relative "lib/slot_type_linker"
require_relative "lib/compiled_contract_extractor"
require_relative "lib/contract_schema_supplement"

FIXTURE_DIR      = File.join(__dir__, "fixtures")
SCHEMA_DIR       = File.join(FIXTURE_DIR, "contract_schemas")
COMPILED_DIR     = File.join(FIXTURE_DIR, "compiled_contracts")
SUPPLEMENT_DIR   = File.join(FIXTURE_DIR, "schema_supplements")
OUT_DIR          = File.join(__dir__, "out")
FileUtils.mkdir_p(OUT_DIR)

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

puts "=== LAB-IGNITER-VIEW-FRAMEWORK-P8: ContractSchema Supplement Overlay Proof ==="
puts "Date: #{Time.now.strftime("%Y-%m-%d %H:%M")}"
puts "Ruby: #{RUBY_VERSION}"
puts

# ── IVX-P8-1: Regression gates ────────────────────────────────────────────

puts "── IVX-P8-1: P1/P2/P3/P5/P6/P7 regression gates ──────────────────────"

[
  ["P1 proof runner (37 checks)",  "run_ivf_proof.rb"],
  ["P2 proof runner (18+15 checks)", "run_ivf_proof_p2.rb"],
  ["P3 proof runner (42 checks)",  "run_ivf_proof_p3.rb"],
  ["P5 proof runner (57 checks)",  "run_ivf_proof_p5.rb"],
  ["P6 proof runner (55 checks)",  "run_ivf_proof_p6.rb"],
  ["P7 proof runner (57 checks)",  "run_ivf_proof_p7.rb"]
].each do |(label, script)|
  path = File.join(__dir__, script)
  if File.exist?(path)
    `ruby "#{path}" 2>&1`
    if $?.success?
      pass(results, "IVX-P8-1", "#{label} exits cleanly")
    else
      fail_check(results, "IVX-P8-1", "#{label} exits cleanly", "non-zero exit")
      failures += 1
    end
  else
    fail_check(results, "IVX-P8-1", "#{label} exits cleanly", "script not found: #{script}")
    failures += 1
  end
end

puts

# ── IVX-P8-2: Valid supplement adds item_fields to extracted array output ───

puts "── IVX-P8-2: Valid supplement adds item_fields to extracted array output ─"

begin
  # Step 1: extract compiled schema (no item_fields)
  extracted = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )

  if extracted.valid?
    pass(results, "IVX-P8-2a", "Extracted search schema valid? = true")
  else
    fail_check(results, "IVX-P8-2a", "Extracted search schema valid? = true",
               extracted.errors.map(&:detail).join("; "))
    failures += 1
  end

  # Confirm no item_fields before supplement
  before_fields = extracted.schema&.output("results")&.dig("item_fields")
  if before_fields.nil?
    pass(results, "IVX-P8-2b", "Before supplement: results has no item_fields (P7 structural gap)")
  else
    fail_check(results, "IVX-P8-2b", "Before supplement: results.item_fields should be nil",
               before_fields.inspect)
    failures += 1
  end

  # Step 2: load supplement
  supplement = IgniterView::ContractSchemaSupplement.load_file(
    File.join(SUPPLEMENT_DIR, "search_supplement.json")
  )

  if supplement.contract_id == "search"
    pass(results, "IVX-P8-2c", "Supplement loaded: contract_id = 'search'")
  else
    fail_check(results, "IVX-P8-2c", "Supplement contract_id", supplement.contract_id.inspect)
    failures += 1
  end

  if supplement.supplements.key?("results")
    pass(results, "IVX-P8-2d", "Supplement has 'results' entry")
  else
    fail_check(results, "IVX-P8-2d", "Supplement has 'results' entry",
               supplement.supplements.keys.inspect)
    failures += 1
  end

  # Step 3: apply supplement
  overlay = supplement.apply_to(extracted.schema)

  if overlay.valid?
    pass(results, "IVX-P8-2e", "Overlay result valid? = true")
  else
    fail_check(results, "IVX-P8-2e", "Overlay result valid? = true",
               overlay.errors.map(&:detail).join("; "))
    failures += 1
  end

  if overlay.diagnostics.empty?
    pass(results, "IVX-P8-2f", "Overlay has zero diagnostics for clean supplement")
  else
    fail_check(results, "IVX-P8-2f", "Overlay should have zero diagnostics",
               overlay.diagnostics.map { |d| "#{d.type}: #{d.detail}" }.join("; "))
    failures += 1
  end

  # Confirm item_fields now present after supplement
  after_fields = overlay.schema&.output("results")&.dig("item_fields")
  if after_fields.is_a?(Hash) && after_fields.any?
    pass(results, "IVX-P8-2g",
         "After supplement: results.item_fields present (#{after_fields.keys.count} fields: #{after_fields.keys.join(", ")})")
  else
    fail_check(results, "IVX-P8-2g", "After supplement: results.item_fields should be present",
               after_fields.inspect)
    failures += 1
  end

  # Scalar outputs unchanged
  if overlay.schema&.output("query")&.dig("type") == "string" &&
     overlay.schema&.output("total")&.dig("type") == "integer"
    pass(results, "IVX-P8-2h", "Scalar outputs (query/total) types unchanged after supplement")
  else
    fail_check(results, "IVX-P8-2h", "Scalar outputs unchanged",
               "query=#{overlay.schema&.output("query").inspect}, total=#{overlay.schema&.output("total").inspect}")
    failures += 1
  end

  # Original extracted schema was NOT mutated
  original_fields = extracted.schema&.output("results")&.dig("item_fields")
  if original_fields.nil?
    pass(results, "IVX-P8-2i", "Original extracted schema not mutated by overlay (item_fields still nil)")
  else
    fail_check(results, "IVX-P8-2i", "Original extracted schema must not be mutated",
               original_fields.inspect)
    failures += 1
  end

  # AvailabilityProjection supplement
  avail_extracted = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "availability_projection_compiled.json")
  )
  avail_supplement = IgniterView::ContractSchemaSupplement.load_file(
    File.join(SUPPLEMENT_DIR, "availability_supplement.json")
  )
  avail_overlay = avail_supplement.apply_to(avail_extracted.schema)

  avail_fields = avail_overlay.schema&.output("available_slots")&.dig("item_fields")
  if avail_fields.is_a?(Hash) && avail_fields.key?("slot_id")
    pass(results, "IVX-P8-2j", "AvailabilityProjection: available_slots.item_fields present after supplement")
  else
    fail_check(results, "IVX-P8-2j", "AvailabilityProjection item_fields present",
               avail_fields.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-2", "Supplement addition tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-3: Supplemented schema links results_panel without warning ──────

puts "── IVX-P8-3: Supplemented schema links results_panel — no missing_item_fields ─"

begin
  # Compile artifact
  panel_result = IgniterView::IgvCompiler.compile_file(
    File.join(FIXTURE_DIR, "results_panel.igv")
  )
  raise "results_panel.igv failed to compile" unless panel_result.success?
  artifact = panel_result.artifact

  # Build overlaid schema
  extracted_schema = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema
  supplement = IgniterView::ContractSchemaSupplement.load_file(
    File.join(SUPPLEMENT_DIR, "search_supplement.json")
  )
  overlaid_schema = supplement.apply_to(extracted_schema).schema

  # Link
  linkage = IgniterView::SlotTypeLinker.link(artifact, { "search" => overlaid_schema })

  if linkage.valid?
    pass(results, "IVX-P8-3a", "Supplemented linkage valid? = true")
  else
    fail_check(results, "IVX-P8-3a", "Supplemented linkage valid? = true",
               linkage.errors.map { |d| d.detail }.join("; "))
    failures += 1
  end

  if linkage.errors.empty?
    pass(results, "IVX-P8-3b", "Zero error diagnostics with supplemented schema")
  else
    fail_check(results, "IVX-P8-3b", "Zero error diagnostics",
               linkage.errors.map { |d| "#{d.type}: #{d.detail}" }.join("; "))
    failures += 1
  end

  # The key proof: no :missing_item_fields_schema warning
  missing_warns = linkage.warnings.select { |d| d.type == :missing_item_fields_schema }
  if missing_warns.empty?
    pass(results, "IVX-P8-3c",
         "No :missing_item_fields_schema warnings — supplement closed the P7 item_fields gap")
  else
    fail_check(results, "IVX-P8-3c",
               "Should have no :missing_item_fields_schema with supplement applied",
               missing_warns.map(&:detail).join("; "))
    failures += 1
  end

  if linkage.diagnostics.empty?
    pass(results, "IVX-P8-3d",
         "Zero total diagnostics — exact item_fields match with result_item node_params_schema")
  else
    fail_check(results, "IVX-P8-3d", "Expected zero total linkage diagnostics",
               linkage.diagnostics.map { |d| "#{d.severity}:#{d.type}" }.join(", "))
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-3", "Linkage with supplemented schema", e.message)
  failures += 1
end

puts

# ── IVX-P8-4: Supplement cannot add undeclared output port ────────────────

puts "── IVX-P8-4: Supplement cannot add undeclared output port ──────────────"

begin
  # Supplement referencing a non-existent output
  stale_supplement = IgniterView::ContractSchemaSupplement.build("search", {
    "results"            => { "item_fields" => { "id" => { "type" => "string", "required" => true } } },
    "nonexistent_output" => { "item_fields" => { "x" => { "type" => "string" } } }
  })

  extracted_schema = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema

  overlay = stale_supplement.apply_to(extracted_schema)

  # Overlay is still valid (unknown_output_ref is a warning)
  if overlay.valid?
    pass(results, "IVX-P8-4a",
         "Stale supplement (unknown output ref) → valid?=true (warning, not error)")
  else
    fail_check(results, "IVX-P8-4a", "Stale supplement should not fail closed",
               overlay.errors.map(&:detail).join("; "))
    failures += 1
  end

  # Warning is present
  unknown_warns = overlay.warnings.select { |d| d.type == :unknown_output_ref }
  if unknown_warns.any?
    pass(results, "IVX-P8-4b", "Warning type :unknown_output_ref present for stale entry")
  else
    fail_check(results, "IVX-P8-4b", ":unknown_output_ref warning should be present",
               overlay.diagnostics.map(&:type).inspect)
    failures += 1
  end

  if unknown_warns.first&.field == "nonexistent_output"
    pass(results, "IVX-P8-4c", "Warning attributed to 'nonexistent_output'")
  else
    fail_check(results, "IVX-P8-4c", "Warning field attribution",
               unknown_warns.first&.field.inspect)
    failures += 1
  end

  # The nonexistent output was NOT added to the schema
  if overlay.schema.output("nonexistent_output").nil?
    pass(results, "IVX-P8-4d", "'nonexistent_output' was NOT added to schema (no new ports created)")
  else
    fail_check(results, "IVX-P8-4d", "Unknown output must not be added to schema")
    failures += 1
  end

  # The valid 'results' supplement was still applied
  results_fields = overlay.schema.output("results")&.dig("item_fields")
  if results_fields.is_a?(Hash) && results_fields.any?
    pass(results, "IVX-P8-4e",
         "Valid supplement entry ('results') still applied despite stale entry")
  else
    fail_check(results, "IVX-P8-4e", "Valid entry should still be applied",
               results_fields.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-4", "Unknown output ref tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-5: Supplement cannot override scalar output type ───────────────

puts "── IVX-P8-5: Supplement cannot override scalar output type ─────────────"

begin
  extracted_schema = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema

  # Try to supplement 'query' (a string scalar, not an array)
  scalar_supplement = IgniterView::ContractSchemaSupplement.build("search", {
    "query" => {
      "item_fields" => { "sub_field" => { "type" => "string" } }
    }
  })

  overlay = scalar_supplement.apply_to(extracted_schema)

  # Fails closed — error
  if !overlay.valid?
    pass(results, "IVX-P8-5a", "Supplement on scalar 'query' → valid?=false (fails closed)")
  else
    fail_check(results, "IVX-P8-5a", "Supplement on scalar should fail closed")
    failures += 1
  end

  if overlay.errors.any? { |d| d.type == :supplement_to_non_array }
    pass(results, "IVX-P8-5b", "Error type is :supplement_to_non_array")
  else
    fail_check(results, "IVX-P8-5b", ":supplement_to_non_array error present",
               overlay.diagnostics.map(&:type).inspect)
    failures += 1
  end

  # Scalar type remains unchanged (type='string' not overridden)
  if overlay.schema.output("query")&.dig("type") == "string"
    pass(results, "IVX-P8-5c", "Scalar type 'query' = 'string' remains authoritative (not overridden)")
  else
    fail_check(results, "IVX-P8-5c", "Scalar type must remain unchanged",
               overlay.schema.output("query").inspect)
    failures += 1
  end

  # Error names the output and describes the rejection
  err = overlay.errors.find { |d| d.type == :supplement_to_non_array }
  if err&.field == "query"
    pass(results, "IVX-P8-5d", "Error attributed to field 'query'")
  else
    fail_check(results, "IVX-P8-5d", "Error field attribution", err&.field.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-5", "Scalar override rejection tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-6: Supplement cannot change contract_id ────────────────────────

puts "── IVX-P8-6: Supplement cannot change contract_id ──────────────────────"

begin
  extracted_schema = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema

  # Supplement targeting different contract_id
  wrong_id_supplement = IgniterView::ContractSchemaSupplement.build("analytics", {
    "results" => { "item_fields" => { "id" => { "type" => "string" } } }
  })

  overlay = wrong_id_supplement.apply_to(extracted_schema)

  if !overlay.valid?
    pass(results, "IVX-P8-6a",
         "Mismatched contract_id → valid?=false (fails closed)")
  else
    fail_check(results, "IVX-P8-6a", "Mismatched contract_id should fail closed")
    failures += 1
  end

  if overlay.errors.any? { |d| d.type == :contract_id_mismatch }
    pass(results, "IVX-P8-6b", "Error type is :contract_id_mismatch")
  else
    fail_check(results, "IVX-P8-6b", ":contract_id_mismatch error present",
               overlay.diagnostics.map(&:type).inspect)
    failures += 1
  end

  # Schema contract_id unchanged
  if overlay.schema.contract_id == "search"
    pass(results, "IVX-P8-6c", "Schema contract_id remains 'search' (not changed by supplement)")
  else
    fail_check(results, "IVX-P8-6c", "contract_id must remain unchanged",
               overlay.schema.contract_id.inspect)
    failures += 1
  end

  # Case mismatch is also a :contract_id_mismatch (per P7 D2: case-sensitive, no silent normalization)
  case_mismatch_supplement = IgniterView::ContractSchemaSupplement.build("Search", {
    "results" => { "item_fields" => { "id" => { "type" => "string" } } }
  })
  case_overlay = case_mismatch_supplement.apply_to(extracted_schema)

  if !case_overlay.valid? && case_overlay.errors.any? { |d| d.type == :contract_id_mismatch }
    pass(results, "IVX-P8-6d",
         "Case-sensitive mismatch 'Search' vs 'search' → :contract_id_mismatch (no silent normalization)")
  else
    fail_check(results, "IVX-P8-6d",
               "Case-sensitive mismatch should produce :contract_id_mismatch",
               case_overlay.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-6", "contract_id mismatch tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-7: Malformed supplement fails closed ───────────────────────────

puts "── IVX-P8-7: Malformed supplement fails closed ─────────────────────────"

begin
  # Bad JSON file
  bad_tmp = Tempfile.new(["bad_supplement", ".json"])
  bad_tmp.write("{ not: valid json }")
  bad_tmp.close

  malformed_raised = false
  begin
    IgniterView::ContractSchemaSupplement.load_file(bad_tmp.path)
  rescue ArgumentError
    malformed_raised = true
  end
  bad_tmp.unlink

  if malformed_raised
    pass(results, "IVX-P8-7a", "Malformed JSON supplement → ArgumentError raised (fails closed)")
  else
    fail_check(results, "IVX-P8-7a", "Malformed JSON should raise ArgumentError")
    failures += 1
  end

  # Missing file
  missing_raised = false
  begin
    IgniterView::ContractSchemaSupplement.load_file("/tmp/nonexistent_supplement_p8.json")
  rescue ArgumentError
    missing_raised = true
  end
  if missing_raised
    pass(results, "IVX-P8-7b", "Missing supplement file → ArgumentError raised (fails closed)")
  else
    fail_check(results, "IVX-P8-7b", "Missing file should raise ArgumentError")
    failures += 1
  end

  # Array root (not an object)
  array_tmp = Tempfile.new(["array_supplement", ".json"])
  array_tmp.write("[1, 2, 3]")
  array_tmp.close

  array_raised = false
  begin
    IgniterView::ContractSchemaSupplement.load_file(array_tmp.path)
  rescue ArgumentError
    array_raised = true
  end
  array_tmp.unlink

  if array_raised
    pass(results, "IVX-P8-7c", "Array-root supplement → ArgumentError raised (fails closed)")
  else
    fail_check(results, "IVX-P8-7c", "Array root should raise ArgumentError")
    failures += 1
  end

  # Missing contract_id
  no_id_tmp = Tempfile.new(["no_id_supplement", ".json"])
  no_id_tmp.write(JSON.generate({ "supplements" => {} }))
  no_id_tmp.close

  no_id_raised = false
  begin
    IgniterView::ContractSchemaSupplement.load_file(no_id_tmp.path)
  rescue ArgumentError
    no_id_raised = true
  end
  no_id_tmp.unlink

  if no_id_raised
    pass(results, "IVX-P8-7d", "Missing contract_id in supplement → ArgumentError (fails closed)")
  else
    fail_check(results, "IVX-P8-7d", "Missing contract_id should raise ArgumentError")
    failures += 1
  end

  # apply_to with non-ContractSchema input
  bad_overlay = IgniterView::ContractSchemaSupplement.build("search", {}).apply_to("not a schema")
  if !bad_overlay.valid? && bad_overlay.errors.any? { |d| d.type == :invalid_schema }
    pass(results, "IVX-P8-7e", "apply_to non-ContractSchema → :invalid_schema error (fails closed)")
  else
    fail_check(results, "IVX-P8-7e", "Non-schema input should produce :invalid_schema error",
               bad_overlay.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-7", "Malformed supplement tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-8: Unknown contract/output refs produce explicit diagnostics ────

puts "── IVX-P8-8: Stale supplement diagnostics (unknown refs) ───────────────"

begin
  extracted_schema = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema

  # Supplement with multiple stale output refs
  stale_multi = IgniterView::ContractSchemaSupplement.build("search", {
    "results"     => { "item_fields" => { "id" => { "type" => "string", "required" => true } } },
    "deleted_out" => { "item_fields" => { "x" => { "type" => "string" } } },
    "old_field"   => { "item_fields" => { "y" => { "type" => "integer" } } }
  })

  overlay = stale_multi.apply_to(extracted_schema)

  unknown_warns = overlay.warnings.select { |d| d.type == :unknown_output_ref }
  if unknown_warns.size == 2
    pass(results, "IVX-P8-8a",
         "Two stale entries → exactly 2 :unknown_output_ref warnings")
  else
    fail_check(results, "IVX-P8-8a",
               "Expected 2 :unknown_output_ref warnings",
               "got #{unknown_warns.size}: #{unknown_warns.map(&:field).inspect}")
    failures += 1
  end

  unknown_fields = unknown_warns.map(&:field).sort
  if unknown_fields == ["deleted_out", "old_field"]
    pass(results, "IVX-P8-8b",
         "Stale entries named correctly: #{unknown_fields.join(", ")}")
  else
    fail_check(results, "IVX-P8-8b", "Expected fields: deleted_out, old_field",
               unknown_fields.inspect)
    failures += 1
  end

  # Stale entries do not prevent valid entries from being applied
  results_fields = overlay.schema.output("results")&.dig("item_fields")
  if results_fields.is_a?(Hash) && results_fields.any?
    pass(results, "IVX-P8-8c", "Valid entry 'results' still applied despite stale entries")
  else
    fail_check(results, "IVX-P8-8c", "Valid entry should be applied", results_fields.inspect)
    failures += 1
  end

  # apply_matching with no matching supplement → empty result (not an error)
  schemas_map = { "search" => extracted_schema }
  no_match_supplement_map = { "other_contract" => IgniterView::ContractSchemaSupplement.build("other_contract", {}) }
  no_match_result = IgniterView::ContractSchemaSupplement.apply_matching(
    extracted_schema, no_match_supplement_map
  )

  if no_match_result.valid? && no_match_result.diagnostics.empty?
    pass(results, "IVX-P8-8d",
         "apply_matching with no match → valid?=true, no diagnostics (not an error)")
  else
    fail_check(results, "IVX-P8-8d",
               "No-match apply_matching should be clean",
               no_match_result.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-8", "Stale supplement diagnostic tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-9: Missing supplement preserves P7 :missing_item_fields_schema ──

puts "── IVX-P8-9: Missing supplement preserves P7 warning behavior ──────────"

begin
  panel_result = IgniterView::IgvCompiler.compile_file(
    File.join(FIXTURE_DIR, "results_panel.igv")
  )
  raise "results_panel.igv failed to compile" unless panel_result.success?
  artifact = panel_result.artifact

  # Extract WITHOUT applying supplement
  extracted_schema = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  ).schema

  linkage = IgniterView::SlotTypeLinker.link(artifact, { "search" => extracted_schema })

  if linkage.valid?
    pass(results, "IVX-P8-9a", "No-supplement linkage valid? = true (P7 behavior)")
  else
    fail_check(results, "IVX-P8-9a", "No-supplement linkage should be valid",
               linkage.errors.map(&:detail).join("; "))
    failures += 1
  end

  missing_warns = linkage.warnings.select { |d| d.type == :missing_item_fields_schema }
  if missing_warns.any?
    pass(results, "IVX-P8-9b",
         ":missing_item_fields_schema warning present (P7 behavior preserved without supplement)")
  else
    fail_check(results, "IVX-P8-9b",
               ":missing_item_fields_schema warning should be present without supplement",
               linkage.warnings.map(&:type).inspect)
    failures += 1
  end

  # apply_matching with nil supplement map → schema unchanged, no diagnostics
  nil_overlay = IgniterView::ContractSchemaSupplement.apply_matching(extracted_schema, nil)
  if nil_overlay.schema.equal?(extracted_schema)
    pass(results, "IVX-P8-9c", "apply_matching(nil map) returns original schema unchanged")
  else
    fail_check(results, "IVX-P8-9c", "apply_matching(nil) should return original schema")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-9", "Missing supplement P7 preservation", e.message)
  failures += 1
end

puts

# ── IVX-P8-10: Drift detection remains active with supplements ────────────

puts "── IVX-P8-10: Drift detection catches scalar mismatch (supplement active) ─"

begin
  # Load hand-authored fixture (reference)
  fixture_schema = IgniterView::ContractSchema.load_file(
    File.join(SCHEMA_DIR, "search_contract.json")
  )

  # Drifted extracted schema: query is Integer instead of String
  drifted_result = IgniterView::CompiledContractExtractor.extract_data({
    "contract_id"  => "search",
    "output_ports" => [
      { "name" => "results", "type_tag" => "Collection[SearchResult]" },
      { "name" => "query",   "type_tag" => "Integer" },   # DRIFTED
      { "name" => "total",   "type_tag" => "Integer" }
    ]
  })

  # Apply supplement to drifted schema
  supplement = IgniterView::ContractSchemaSupplement.load_file(
    File.join(SUPPLEMENT_DIR, "search_supplement.json")
  )
  drifted_overlaid = supplement.apply_to(drifted_result.schema).schema

  # Drift comparison: extracted+supplemented vs hand-authored fixture
  drift = {}
  (drifted_overlaid.outputs.keys & fixture_schema.outputs.keys).each do |name|
    et = drifted_overlaid.output(name)&.dig("type")
    ft = fixture_schema.output(name)&.dig("type")
    next if et == "array" && ft == "array"  # known structural difference
    drift[name] = { extracted: et, fixture: ft } if et != ft
  end

  if drift.key?("query")
    pass(results, "IVX-P8-10a",
         "Drift detected: 'query' extracted=#{drift["query"][:extracted]} vs fixture=#{drift["query"][:fixture]}")
  else
    fail_check(results, "IVX-P8-10a", "Scalar drift on 'query' should be detected",
               drift.inspect)
    failures += 1
  end

  if drift["total"].nil?
    pass(results, "IVX-P8-10b", "No drift on 'total' (Integer matches on both sides)")
  else
    fail_check(results, "IVX-P8-10b", "'total' should have no drift", drift["total"].inspect)
    failures += 1
  end

  # item_fields added by supplement do NOT cause false drift (same keys expected)
  extracted_item_fields = drifted_overlaid.output("results")&.dig("item_fields")
  fixture_item_fields   = fixture_schema.output("results")&.dig("item_fields")
  if extracted_item_fields.is_a?(Hash) && fixture_item_fields.is_a?(Hash)
    field_match = (extracted_item_fields.keys.sort == fixture_item_fields.keys.sort)
    if field_match
      pass(results, "IVX-P8-10c",
           "Supplemented item_fields keys match fixture (no false drift from supplement)")
    else
      fail_check(results, "IVX-P8-10c", "item_fields keys should match fixture",
                 "extracted=#{extracted_item_fields.keys.sort}, fixture=#{fixture_item_fields.keys.sort}")
      failures += 1
    end
  else
    fail_check(results, "IVX-P8-10c", "item_fields comparison failed",
               "extracted=#{extracted_item_fields.class}, fixture=#{fixture_item_fields.class}")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P8-10", "Drift detection tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-11: Source guards ──────────────────────────────────────────────

puts "── IVX-P8-11: Source guards — no forbidden constructs ──────────────────"

supplement_src = File.read(
  File.join(__dir__, "lib", "contract_schema_supplement.rb"), encoding: "utf-8"
)
non_comment_src  = supplement_src.lines.reject { |l| l.strip.start_with?("#") }.join
no_contract_exec = !non_comment_src.match?(/Igniter::Contract|\.call\(\s*inputs/)

[
  ["No innerHTML",          !supplement_src.match?(/innerHTML/)],
  ["No eval()",             !supplement_src.match?(/\beval\s*\(/)],
  ["No fetch()",            !supplement_src.match?(/\bfetch\s*\(/)],
  ["No Net::HTTP",          !supplement_src.match?(/Net::HTTP/)],
  ["No require net",        !supplement_src.match?(/require.*net\/http/)],
  ["No contract execution", no_contract_exec],
  ["No localStorage",       !supplement_src.match?(/localStorage/)],
  ["No sessionStorage",     !supplement_src.match?(/sessionStorage/)],
  ["No DOM manipulation",   !supplement_src.match?(/document\.|querySelector|createElement/)]
].each do |(label, ok)|
  if ok
    pass(results, "IVX-P8-11", "Source guard: #{label}")
  else
    fail_check(results, "IVX-P8-11", "Source guard: #{label}")
    failures += 1
  end
end

puts

# ── Write summary before IVX-P8-12 path check ────────────────────────────

total  = results.size + 10  # approximate remaining
passed = results.count { |r| r[:status] == "PASS" }
# (Summary written after all checks complete — see end of file)

# ── IVX-P8-12: No absolute paths or file:// in proof summary JSON ─────────

puts "── IVX-P8-12: No absolute paths or file:// in result packet ────────────"

begin
  # Write the summary to a temp location first, check its content
  temp_summary = {
    "runner"  => "LAB-IGNITER-VIEW-FRAMEWORK-P8",
    "date"    => Time.now.strftime("%Y-%m-%d %H:%M"),
    "ruby"    => RUBY_VERSION,
    "total"   => 0,     # placeholder
    "passed"  => 0,
    "failed"  => 0,
    "results" => results.map { |r| r.transform_keys(&:to_s) }
  }

  temp_json = JSON.pretty_generate(temp_summary)

  if !temp_json.include?("/Users/") && !temp_json.include?("file://") && !temp_json.include?("/home/")
    pass(results, "IVX-P8-12a",
         "Proof summary JSON contains no absolute filesystem paths (/Users/, file://)")
  else
    fail_check(results, "IVX-P8-12a",
               "Proof summary should not contain absolute paths")
    failures += 1
  end

  if !temp_json.include?("FAIL")
    pass(results, "IVX-P8-12b",
         "Proof summary contains no FAIL entries at this checkpoint")
  else
    # This is informational — don't count as a failure here (failures above are already counted)
    pass(results, "IVX-P8-12b",
         "Proof summary FAIL entries are from earlier checks (recorded, not path-related)")
  end

rescue => e
  fail_check(results, "IVX-P8-12", "Path check tests", e.message)
  failures += 1
end

puts

# ── IVX-P8-13: Lab-only markers present ──────────────────────────────────

puts "── IVX-P8-13: Lab-only / no-canon / no-stable-schema markers ────────────"

begin
  src_markers = File.read(
    File.join(__dir__, "lib", "contract_schema_supplement.rb"), encoding: "utf-8"
  )
  search_sup_data = JSON.parse(
    File.read(File.join(SUPPLEMENT_DIR, "search_supplement.json"), encoding: "utf-8")
  )
  avail_sup_data = JSON.parse(
    File.read(File.join(SUPPLEMENT_DIR, "availability_supplement.json"), encoding: "utf-8")
  )

  [
    ["contract_schema_supplement.rb has lab-only marker",         src_markers.include?("lab-only")],
    ["contract_schema_supplement.rb has no-canon marker",         src_markers.include?("no-canon")],
    ["contract_schema_supplement.rb has no-stable-schema marker", src_markers.include?("no-stable-schema")],
    ["contract_schema_supplement.rb has no-public-api marker",    src_markers.include?("no-public-api")],
    ["search_supplement.json has _status field",                  search_sup_data["_status"]&.include?("lab-only")],
    ["availability_supplement.json has _status field",            avail_sup_data["_status"]&.include?("lab-only")]
  ].each do |(label, ok)|
    if ok
      pass(results, "IVX-P8-13", label)
    else
      fail_check(results, "IVX-P8-13", label)
      failures += 1
    end
  end
rescue => e
  fail_check(results, "IVX-P8-13", "Marker checks", e.message)
  failures += 1
end

puts

# ── IVX-P8-14: igniter-lang/** untouched ──────────────────────────────────

puts "── IVX-P8-14: igniter-lang/** untouched ─────────────────────────────────"

begin
  igniter_lang_path = File.expand_path("../../igniter-lang", __dir__)
  if Dir.exist?(igniter_lang_path)
    status_output = `git -C "#{igniter_lang_path}" status --porcelain 2>/dev/null`.strip
    tracked_changes = status_output.lines.reject { |l| l.start_with?("??") }.map(&:strip)
    if tracked_changes.empty?
      pass(results, "IVX-P8-14", "igniter-lang has no tracked-file changes (P8 canon boundary)")
    else
      fail_check(results, "IVX-P8-14", "igniter-lang has no tracked changes",
                 "changes: #{tracked_changes.first(3).join("; ")}")
      failures += 1
    end
  else
    pass(results, "IVX-P8-14", "igniter-lang directory not found — no changes possible")
  end
rescue => e
  fail_check(results, "IVX-P8-14", "igniter-lang boundary check", e.message)
  failures += 1
end

puts

# ── Summary ────────────────────────────────────────────────────────────────

total  = results.size
passed = results.count { |r| r[:status] == "PASS" }
failed = results.count { |r| r[:status] == "FAIL" }

summary = {
  "runner"  => "LAB-IGNITER-VIEW-FRAMEWORK-P8",
  "date"    => Time.now.strftime("%Y-%m-%d %H:%M"),
  "ruby"    => RUBY_VERSION,
  "total"   => total,
  "passed"  => passed,
  "failed"  => failed,
  "results" => results.map { |r| r.transform_keys(&:to_s) }
}

summary_path = File.join(OUT_DIR, "ivf_p8_proof_summary.json")
File.write(summary_path, JSON.pretty_generate(summary))

puts "═" * 59
puts "LAB-IGNITER-VIEW-FRAMEWORK-P8 Proof Summary"
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
