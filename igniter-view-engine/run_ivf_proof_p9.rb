#!/usr/bin/env ruby
# frozen_string_literal: true

# run_ivf_proof_p9.rb
#
# LAB-IGNITER-VIEW-FRAMEWORK-P9 — LinkageReport unified diagnostic report proof runner.
#
# Proof matrix:
#   IVX-P9-1:  P8 and prior regression gates remain green
#   IVX-P9-2:  Extraction diagnostics appear with source_layer = extractor
#   IVX-P9-3:  Supplement overlay warnings/errors appear with source_layer = overlay
#   IVX-P9-4:  Slot linkage diagnostics appear with source_layer = linker
#   IVX-P9-5:  Severity counts are correct across all layers
#   IVX-P9-6:  Stale supplement report preserves valid entries and warns on unknown refs
#   IVX-P9-7:  Scalar override attempt reports hard error at overlay layer
#   IVX-P9-8:  Missing supplement preserves P7 :missing_item_fields_schema warning at linker layer
#   IVX-P9-9:  Text renderer is stable (deterministic) and readable
#   IVX-P9-10: JSON report contains no absolute paths or file:// links
#   IVX-P9-11: No contract execution, network, DOM, storage, or public API in source
#   IVX-P9-12: Lab-only / no-canon / no-stable-schema markers preserved
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "json"
require "fileutils"

require_relative "lib/view_artifact"
require_relative "lib/ssr_renderer"
require_relative "lib/igv_compiler"
require_relative "lib/igniter_view_engine"
require_relative "lib/contract_schema"
require_relative "lib/slot_type_linker"
require_relative "lib/compiled_contract_extractor"
require_relative "lib/contract_schema_supplement"
require_relative "lib/linkage_report"

FIXTURE_DIR    = File.join(__dir__, "fixtures")
SCHEMA_DIR     = File.join(FIXTURE_DIR, "contract_schemas")
COMPILED_DIR   = File.join(FIXTURE_DIR, "compiled_contracts")
SUPPLEMENT_DIR = File.join(FIXTURE_DIR, "schema_supplements")
OUT_DIR        = File.join(__dir__, "out")
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

puts "=== LAB-IGNITER-VIEW-FRAMEWORK-P9: LinkageReport Diagnostic Report Proof ==="
puts "Date: #{Time.now.strftime("%Y-%m-%d %H:%M")}"
puts "Ruby: #{RUBY_VERSION}"
puts

# ── IVX-P9-1: Regression gates ────────────────────────────────────────────

puts "── IVX-P9-1: P8 and prior regression gates ─────────────────────────────"

[
  ["P1 proof runner (37 checks)",   "run_ivf_proof.rb"],
  ["P2 proof runner (18+15 checks)", "run_ivf_proof_p2.rb"],
  ["P3 proof runner (42 checks)",   "run_ivf_proof_p3.rb"],
  ["P5 proof runner (57 checks)",   "run_ivf_proof_p5.rb"],
  ["P6 proof runner (55 checks)",   "run_ivf_proof_p6.rb"],
  ["P7 proof runner (57 checks)",   "run_ivf_proof_p7.rb"],
  ["P8 proof runner (66 checks)",   "run_ivf_proof_p8.rb"]
].each do |(label, script)|
  path = File.join(__dir__, script)
  if File.exist?(path)
    `ruby "#{path}" 2>&1`
    if $?.success?
      pass(results, "IVX-P9-1", "#{label} exits cleanly")
    else
      fail_check(results, "IVX-P9-1", "#{label} exits cleanly", "non-zero exit")
      failures += 1
    end
  else
    fail_check(results, "IVX-P9-1", "#{label} exits cleanly", "not found: #{script}")
    failures += 1
  end
end

puts

# ── Build shared inputs for IVX-P9-2 through P9-8 ──────────────────────────

# Shared: compile results_panel.igv
panel_artifact = begin
  pr = IgniterView::IgvCompiler.compile_file(File.join(FIXTURE_DIR, "results_panel.igv"))
  raise "compile failed" unless pr.success?
  pr.artifact
end

# ── IVX-P9-2: Extraction diagnostics attributed to :extractor layer ────────

puts "── IVX-P9-2: Extraction diagnostics → source_layer = extractor ──────────"

begin
  # Extract WITHOUT supplement → Collection type emits :missing_item_fields warning
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )

  # No supplement → pass nil overlay_result
  linkage = IgniterView::SlotTypeLinker.link(panel_artifact, { "search" => extraction.schema })

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    nil,
    linkage_result:    linkage
  )

  extractor_entries = report.entries_for(layer: :extractor)

  if extractor_entries.any?
    pass(results, "IVX-P9-2a", "Extraction diagnostics present in report")
  else
    fail_check(results, "IVX-P9-2a", "Extraction diagnostics should be present (no supplement)")
    failures += 1
  end

  if extractor_entries.all? { |e| e.source_layer == :extractor }
    pass(results, "IVX-P9-2b", "All extraction entries have source_layer = :extractor")
  else
    fail_check(results, "IVX-P9-2b", "source_layer must be :extractor for extraction entries")
    failures += 1
  end

  missing_fields = extractor_entries.select { |e| e.type == :missing_item_fields }
  if missing_fields.any?
    pass(results, "IVX-P9-2c",
         ":missing_item_fields warning present at :extractor layer (Collection type gap)")
  else
    fail_check(results, "IVX-P9-2c", ":missing_item_fields expected at :extractor layer",
               extractor_entries.map(&:type).inspect)
    failures += 1
  end

  if missing_fields.first&.field == "results"
    pass(results, "IVX-P9-2d", "Extraction warning attributed to field 'results'")
  else
    fail_check(results, "IVX-P9-2d", "Field attribution", missing_fields.first&.field.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-2", "Extraction layer attribution", e.message)
  failures += 1
end

puts

# ── IVX-P9-3: Overlay diagnostics attributed to :overlay layer ───────────

puts "── IVX-P9-3: Overlay diagnostics → source_layer = overlay ─────────────"

begin
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )

  # Stale supplement: valid 'results' entry + unknown 'nonexistent' entry
  stale_sup = IgniterView::ContractSchemaSupplement.build("search", {
    "results"        => { "item_fields" => { "id" => { "type" => "string", "required" => true } } },
    "nonexistent_x"  => { "item_fields" => { "z" => { "type" => "string" } } }
  })
  overlay = stale_sup.apply_to(extraction.schema)

  linkage = IgniterView::SlotTypeLinker.link(
    panel_artifact,
    { "search" => (overlay.valid? ? overlay.schema : extraction.schema) }
  )

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    overlay,
    linkage_result:    linkage
  )

  overlay_entries = report.entries_for(layer: :overlay)

  if overlay_entries.any?
    pass(results, "IVX-P9-3a", "Overlay diagnostics present in report")
  else
    fail_check(results, "IVX-P9-3a", "Overlay diagnostics should be present (stale entry)")
    failures += 1
  end

  if overlay_entries.all? { |e| e.source_layer == :overlay }
    pass(results, "IVX-P9-3b", "All overlay entries have source_layer = :overlay")
  else
    fail_check(results, "IVX-P9-3b", "source_layer must be :overlay for overlay entries")
    failures += 1
  end

  unknown_ref = overlay_entries.select { |e| e.type == :unknown_output_ref }
  if unknown_ref.any?
    pass(results, "IVX-P9-3c", ":unknown_output_ref warning at :overlay layer (stale entry)")
  else
    fail_check(results, "IVX-P9-3c", ":unknown_output_ref expected at :overlay layer",
               overlay_entries.map(&:type).inspect)
    failures += 1
  end

  # Overlay warnings are only warnings (valid?=true for stale supplement)
  if report.valid?
    pass(results, "IVX-P9-3d", "Report valid?=true for stale supplement (warning only)")
  else
    fail_check(results, "IVX-P9-3d", "Stale supplement should not fail report")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-3", "Overlay layer attribution", e.message)
  failures += 1
end

puts

# ── IVX-P9-4: Linker diagnostics attributed to :linker layer ─────────────

puts "── IVX-P9-4: Linker diagnostics → source_layer = linker ────────────────"

begin
  # Build a schema that will trigger a linker error: wrong type for 'results'
  # (slot declares type="array" but contract output declares type="string")
  mistyped_schema = IgniterView::ContractSchema.build("search", {
    "results" => { "type" => "string" },  # WRONG — should be array
    "query"   => { "type" => "string" },
    "total"   => { "type" => "integer" }
  })

  linkage = IgniterView::SlotTypeLinker.link(panel_artifact, { "search" => mistyped_schema })

  report = IgniterView::LinkageReport.build(
    contract_id:    "search",
    view_id:        panel_artifact.view_id,
    linkage_result: linkage
  )

  linker_entries = report.entries_for(layer: :linker)

  if linker_entries.any?
    pass(results, "IVX-P9-4a", "Linker diagnostics present in report (type mismatch)")
  else
    fail_check(results, "IVX-P9-4a", "Linker diagnostics should be present")
    failures += 1
  end

  if linker_entries.all? { |e| e.source_layer == :linker }
    pass(results, "IVX-P9-4b", "All linker entries have source_layer = :linker")
  else
    fail_check(results, "IVX-P9-4b", "source_layer must be :linker for linker entries")
    failures += 1
  end

  mismatch = linker_entries.select { |e| e.type == :slot_type_mismatch }
  if mismatch.any?
    pass(results, "IVX-P9-4c", ":slot_type_mismatch error at :linker layer")
  else
    fail_check(results, "IVX-P9-4c", ":slot_type_mismatch expected at :linker layer",
               linker_entries.map(&:type).inspect)
    failures += 1
  end

  if !report.valid?
    pass(results, "IVX-P9-4d", "Report valid?=false on linker error (fails closed)")
  else
    fail_check(results, "IVX-P9-4d", "Linker error should make report invalid")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-4", "Linker layer attribution", e.message)
  failures += 1
end

puts

# ── IVX-P9-5: Severity counts correct across all layers ──────────────────

puts "── IVX-P9-5: Severity counts correct across all layers ─────────────────"

begin
  # Scenario: extraction warning + overlay warning (stale) + linker warning (missing item_fields)
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )

  stale_overlay = IgniterView::ContractSchemaSupplement.build("search", {
    "results"   => { "item_fields" => { "id" => { "type" => "string", "required" => true } } },
    "stale_one" => { "item_fields" => {} }
  }).apply_to(extraction.schema)

  linkage = IgniterView::SlotTypeLinker.link(
    panel_artifact,
    { "search" => stale_overlay.schema }
  )

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    stale_overlay,
    linkage_result:    linkage
  )

  ext_warns = report.entries_for(layer: :extractor).count(&:warning?)
  ovl_warns = report.entries_for(layer: :overlay).count(&:warning?)
  lnk_warns = report.entries_for(layer: :linker).count(&:warning?)
  total_expected_warns = ext_warns + ovl_warns + lnk_warns

  if report.warning_count == total_expected_warns
    pass(results, "IVX-P9-5a",
         "Total warning_count (#{report.warning_count}) equals sum by layer " \
         "(ext=#{ext_warns} + ovl=#{ovl_warns} + lnk=#{lnk_warns})")
  else
    fail_check(results, "IVX-P9-5a", "warning_count mismatch",
               "report=#{report.warning_count} vs sum=#{total_expected_warns}")
    failures += 1
  end

  if report.error_count == 0
    pass(results, "IVX-P9-5b", "Zero errors in multi-warning scenario")
  else
    fail_check(results, "IVX-P9-5b", "Expected zero errors", "got #{report.error_count}")
    failures += 1
  end

  if report.valid?
    pass(results, "IVX-P9-5c", "Report valid?=true when all diagnostics are warnings")
  else
    fail_check(results, "IVX-P9-5c", "All-warnings report should be valid")
    failures += 1
  end

  if report.entry_count == report.error_count + report.warning_count
    pass(results, "IVX-P9-5d",
         "entry_count (#{report.entry_count}) == error_count + warning_count")
  else
    fail_check(results, "IVX-P9-5d", "entry_count should equal errors + warnings",
               "entry=#{report.entry_count}, errors=#{report.error_count}, warns=#{report.warning_count}")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-5", "Severity count tests", e.message)
  failures += 1
end

puts

# ── IVX-P9-6: Stale supplement preserves valid entries + warns ───────────

puts "── IVX-P9-6: Stale supplement report — valid entries applied, warnings surfaced ─"

begin
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )
  stale_sup = IgniterView::ContractSchemaSupplement.build("search", {
    "results"    => { "item_fields" => { "id" => { "type" => "string", "required" => true },
                                         "score" => { "type" => "integer" } } },
    "gone_field" => { "item_fields" => { "x" => { "type" => "string" } } }
  })
  stale_overlay = stale_sup.apply_to(extraction.schema)

  linkage = IgniterView::SlotTypeLinker.link(
    panel_artifact,
    { "search" => stale_overlay.schema }
  )

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    stale_overlay,
    linkage_result:    linkage
  )

  overlay_warns = report.entries_for(layer: :overlay).select { |e| e.type == :unknown_output_ref }
  if overlay_warns.any?
    pass(results, "IVX-P9-6a", ":unknown_output_ref warning surfaced at :overlay layer")
  else
    fail_check(results, "IVX-P9-6a", ":unknown_output_ref warning expected")
    failures += 1
  end

  # Valid 'results' entry still applied → no :missing_item_fields_schema at linker
  linker_missing = report.entries_for(layer: :linker).select { |e| e.type == :missing_item_fields_schema }
  if linker_missing.empty?
    pass(results, "IVX-P9-6b",
         "No :missing_item_fields_schema at linker — valid supplement entry was applied")
  else
    fail_check(results, "IVX-P9-6b",
               "Valid entry should suppress :missing_item_fields_schema",
               linker_missing.map(&:detail).join("; "))
    failures += 1
  end

  if report.valid?
    pass(results, "IVX-P9-6c", "Report valid?=true (stale entry is warning only)")
  else
    fail_check(results, "IVX-P9-6c", "Stale supplement report should be valid")
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-6", "Stale supplement report test", e.message)
  failures += 1
end

puts

# ── IVX-P9-7: Scalar override attempt → overlay layer error ──────────────

puts "── IVX-P9-7: Scalar override attempt → hard error at :overlay layer ─────"

begin
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )

  # Supplement targeting scalar 'query' with item_fields
  bad_sup = IgniterView::ContractSchemaSupplement.build("search", {
    "query" => { "item_fields" => { "sub" => { "type" => "string" } } }
  })
  bad_overlay = bad_sup.apply_to(extraction.schema)

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    bad_overlay,
    linkage_result:    nil
  )

  overlay_errors = report.entries_for(layer: :overlay).select { |e| e.type == :supplement_to_non_array }

  if overlay_errors.any?
    pass(results, "IVX-P9-7a",
         ":supplement_to_non_array error present at :overlay layer")
  else
    fail_check(results, "IVX-P9-7a", ":supplement_to_non_array expected at :overlay layer",
               report.entries_for(layer: :overlay).map(&:type).inspect)
    failures += 1
  end

  if !report.valid?
    pass(results, "IVX-P9-7b", "Report valid?=false on overlay error (fails closed)")
  else
    fail_check(results, "IVX-P9-7b", "Overlay error should make report invalid")
    failures += 1
  end

  if overlay_errors.first&.field == "query"
    pass(results, "IVX-P9-7c", "Overlay error attributed to field 'query'")
  else
    fail_check(results, "IVX-P9-7c", "Error field attribution",
               overlay_errors.first&.field.inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-7", "Scalar override report test", e.message)
  failures += 1
end

puts

# ── IVX-P9-8: Missing supplement → P7 :missing_item_fields_schema at linker ─

puts "── IVX-P9-8: Missing supplement → P7 :missing_item_fields_schema at :linker ─"

begin
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )

  # No supplement applied
  linkage = IgniterView::SlotTypeLinker.link(panel_artifact, { "search" => extraction.schema })

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    nil,
    linkage_result:    linkage
  )

  linker_missing = report.entries_for(layer: :linker).select { |e| e.type == :missing_item_fields_schema }

  if linker_missing.any?
    pass(results, "IVX-P9-8a",
         ":missing_item_fields_schema preserved at :linker layer (P7 behavior, no supplement)")
  else
    fail_check(results, "IVX-P9-8a",
               ":missing_item_fields_schema expected at :linker without supplement",
               report.entries_for(layer: :linker).map(&:type).inspect)
    failures += 1
  end

  if report.valid?
    pass(results, "IVX-P9-8b", "Report valid?=true (warning only, P7 behavior)")
  else
    fail_check(results, "IVX-P9-8b", "No-supplement report should be valid",
               report.errors.map { |e| "#{e.source_layer}:#{e.type}" }.join(", "))
    failures += 1
  end

  # Overlay layer absent (nil overlay_result) → zero overlay entries
  overlay_entries = report.entries_for(layer: :overlay)
  if overlay_entries.empty?
    pass(results, "IVX-P9-8c", "No overlay layer entries when overlay_result is nil")
  else
    fail_check(results, "IVX-P9-8c", "Overlay entries should be empty without overlay",
               overlay_entries.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVX-P9-8", "Missing supplement report test", e.message)
  failures += 1
end

puts

# ── IVX-P9-9: Text renderer stable and readable ────────────────────────────

puts "── IVX-P9-9: Text renderer stable (deterministic) and readable ──────────"

begin
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )
  supplement = IgniterView::ContractSchemaSupplement.load_file(
    File.join(SUPPLEMENT_DIR, "search_supplement.json")
  )
  overlay = supplement.apply_to(extraction.schema)
  linkage = IgniterView::SlotTypeLinker.link(panel_artifact, { "search" => overlay.schema })

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    overlay,
    linkage_result:    linkage
  )

  text1 = report.to_text
  text2 = report.to_text

  if text1 == text2
    pass(results, "IVX-P9-9a", "Text renderer is deterministic (two calls produce identical output)")
  else
    fail_check(results, "IVX-P9-9a", "Text renderer must be deterministic")
    failures += 1
  end

  if text1.include?("LINKAGE REPORT") && text1.include?("contract: search")
    pass(results, "IVX-P9-9b", "Text contains 'LINKAGE REPORT' header and contract name")
  else
    fail_check(results, "IVX-P9-9b", "Text header missing")
    failures += 1
  end

  # Happy path (full supplement applied) should show no diagnostics on linker/overlay
  if text1.include?("[overlay]") && text1.include?("[linker]")
    pass(results, "IVX-P9-9c", "Text includes section markers for all three layers")
  else
    fail_check(results, "IVX-P9-9c", "Text should mention all three layer labels",
               "text=#{text1[0..200]}")
    failures += 1
  end

  if text1.include?("VALID") || text1.include?("INVALID")
    pass(results, "IVX-P9-9d", "Text includes status line (VALID/INVALID)")
  else
    fail_check(results, "IVX-P9-9d", "Text should include status", text1[0..200])
    failures += 1
  end

  # Check text for fully-supplemented happy path: should say VALID
  if report.valid? && text1.include?("VALID")
    pass(results, "IVX-P9-9e", "Text shows VALID for fully-supplemented happy-path report")
  else
    fail_check(results, "IVX-P9-9e", "Happy-path text should show VALID",
               "valid=#{report.valid?}, text fragment=#{text1[0..300]}")
    failures += 1
  end

  # Save the lab report text for inspection
  report_text_path = File.join(OUT_DIR, "ivf_p9_linkage_report_sample.txt")
  File.write(report_text_path, text1)
  pass(results, "IVX-P9-9f", "Sample text report written to #{File.basename(report_text_path)}")

rescue => e
  fail_check(results, "IVX-P9-9", "Text renderer tests", e.message)
  failures += 1
end

puts

# ── IVX-P9-10: JSON report contains no absolute paths ─────────────────────

puts "── IVX-P9-10: JSON report contains no absolute paths or file:// ─────────"

begin
  # Build the lab report (with supplement)
  extraction = IgniterView::CompiledContractExtractor.extract(
    File.join(COMPILED_DIR, "search_compiled.json")
  )
  supplement = IgniterView::ContractSchemaSupplement.load_file(
    File.join(SUPPLEMENT_DIR, "search_supplement.json")
  )
  overlay = supplement.apply_to(extraction.schema)
  linkage = IgniterView::SlotTypeLinker.link(panel_artifact, { "search" => overlay.schema })

  report = IgniterView::LinkageReport.build(
    contract_id:       "search",
    view_id:           panel_artifact.view_id,
    extraction_result: extraction,
    overlay_result:    overlay,
    linkage_result:    linkage
  )

  report_h    = report.to_h
  report_json = JSON.pretty_generate(report_h)

  if !report_json.include?("/Users/") && !report_json.include?("/home/") && !report_json.include?("file://")
    pass(results, "IVX-P9-10a",
         "JSON report contains no absolute filesystem paths (/Users/, /home/, file://)")
  else
    fail_check(results, "IVX-P9-10a", "JSON report should not contain absolute paths")
    failures += 1
  end

  # JSON is parseable
  parsed = JSON.parse(report_json)
  if parsed.is_a?(Hash) && parsed.key?("valid") && parsed.key?("summary") && parsed.key?("entries")
    pass(results, "IVX-P9-10b", "JSON report is valid JSON with required keys (valid, summary, entries)")
  else
    fail_check(results, "IVX-P9-10b", "JSON report malformed", parsed.keys.inspect)
    failures += 1
  end

  # Summary has by_layer breakdown
  by_layer = parsed.dig("summary", "by_layer")
  if by_layer.is_a?(Hash) && %w[extractor overlay linker].all? { |l| by_layer.key?(l) }
    pass(results, "IVX-P9-10c", "JSON summary has by_layer breakdown for all 3 layers")
  else
    fail_check(results, "IVX-P9-10c", "by_layer breakdown missing", by_layer.inspect)
    failures += 1
  end

  # _status marker present
  if parsed["_status"]&.include?("lab-only")
    pass(results, "IVX-P9-10d", "JSON report has _status lab-only marker")
  else
    fail_check(results, "IVX-P9-10d", "_status lab-only marker missing", parsed["_status"].inspect)
    failures += 1
  end

  # Save lab JSON report
  report_json_path = File.join(OUT_DIR, "ivf_p9_linkage_report_summary.json")
  File.write(report_json_path, report_json)
  pass(results, "IVX-P9-10e", "JSON report written to #{File.basename(report_json_path)}")

rescue => e
  fail_check(results, "IVX-P9-10", "JSON report path/format checks", e.message)
  failures += 1
end

puts

# ── IVX-P9-11: Source guards ──────────────────────────────────────────────

puts "── IVX-P9-11: Source guards — no forbidden constructs in linkage_report.rb ─"

report_src = File.read(
  File.join(__dir__, "lib", "linkage_report.rb"), encoding: "utf-8"
)
non_comment = report_src.lines.reject { |l| l.strip.start_with?("#") }.join
no_contract  = !non_comment.match?(/Igniter::Contract|\.call\(\s*inputs/)

[
  ["No innerHTML",          !report_src.match?(/innerHTML/)],
  ["No eval()",             !report_src.match?(/\beval\s*\(/)],
  ["No fetch()",            !report_src.match?(/\bfetch\s*\(/)],
  ["No Net::HTTP",          !report_src.match?(/Net::HTTP/)],
  ["No require net",        !report_src.match?(/require.*net\/http/)],
  ["No contract execution", no_contract],
  ["No localStorage",       !report_src.match?(/localStorage/)],
  ["No sessionStorage",     !report_src.match?(/sessionStorage/)],
  ["No DOM manipulation",   !report_src.match?(/document\.|querySelector|createElement/)],
  ["No system calls",       !non_comment.match?(/`.*`|\bsystem\b|\bspawn\b|\bexec\b/)]
].each do |(label, ok)|
  if ok
    pass(results, "IVX-P9-11", "Source guard: #{label}")
  else
    fail_check(results, "IVX-P9-11", "Source guard: #{label}")
    failures += 1
  end
end

puts

# ── IVX-P9-12: Lab-only markers present ──────────────────────────────────

puts "── IVX-P9-12: Lab-only / no-canon / no-stable-schema markers ────────────"

begin
  src = File.read(File.join(__dir__, "lib", "linkage_report.rb"), encoding: "utf-8")

  [
    ["linkage_report.rb has lab-only marker",         src.include?("lab-only")],
    ["linkage_report.rb has no-canon marker",         src.include?("no-canon")],
    ["linkage_report.rb has no-stable-schema marker", src.include?("no-stable-schema")],
    ["linkage_report.rb has no-public-api marker",    src.include?("no-public-api")],
    ["NON_CLAIMS constant present in source",         src.include?("NON_CLAIMS")]
  ].each do |(label, ok)|
    if ok
      pass(results, "IVX-P9-12", label)
    else
      fail_check(results, "IVX-P9-12", label)
      failures += 1
    end
  end
rescue => e
  fail_check(results, "IVX-P9-12", "Marker checks", e.message)
  failures += 1
end

puts

# ── Summary ────────────────────────────────────────────────────────────────

total  = results.size
passed = results.count { |r| r[:status] == "PASS" }
failed = results.count { |r| r[:status] == "FAIL" }

summary = {
  "runner"  => "LAB-IGNITER-VIEW-FRAMEWORK-P9",
  "date"    => Time.now.strftime("%Y-%m-%d %H:%M"),
  "ruby"    => RUBY_VERSION,
  "total"   => total,
  "passed"  => passed,
  "failed"  => failed,
  "results" => results.map { |r| r.transform_keys(&:to_s) }
}

summary_path = File.join(OUT_DIR, "ivf_p9_proof_summary.json")
File.write(summary_path, JSON.pretty_generate(summary))

puts "═" * 59
puts "LAB-IGNITER-VIEW-FRAMEWORK-P9 Proof Summary"
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
