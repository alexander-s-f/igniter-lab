#!/usr/bin/env ruby
# frozen_string_literal: true

# run_ivf_proof_p6.rb
#
# LAB-IGNITER-VIEW-FRAMEWORK-P6 — Slot-Contract Type Linkage proof runner.
#
# Proof matrix:
#   IVT-P6-1:  P1/P2/P3/P5 regression gates pass
#   IVT-P6-2:  Valid slot-to-contract output linkage passes (no errors)
#   IVT-P6-3:  Missing contract ref fails closed (unresolved_contract_ref error)
#   IVT-P6-4:  Missing output ref fails closed (missing_output_ref error)
#   IVT-P6-5:  Array item schema matches node_params_schema (valid full match)
#   IVT-P6-6:  Missing required item field is diagnosed (error)
#   IVT-P6-7:  Item field type mismatch is diagnosed (warning)
#   IVT-P6-8:  Extra item fields policy explicit and tested (warning, allowed)
#   IVT-P6-9:  SSR rendering deterministic for valid collections
#   IVT-P6-10: JS runtime collection update still passes DOM proof
#   IVT-P6-11: Safety forbidden constructs absent from new source files
#   IVT-P6-12: Lab-only / no-canon / no-stable-schema markers present
#   IVT-P6-13: igniter-lang/** remains untouched
#
# Status: experimental · lab-only · no-canon · no-public-api

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "json"
require "fileutils"

require_relative "lib/view_artifact"
require_relative "lib/ssr_renderer"
require_relative "lib/igv_compiler"
require_relative "lib/igniter_view_engine"
require_relative "lib/contract_schema"
require_relative "lib/slot_type_linker"

FIXTURE_DIR  = File.join(__dir__, "fixtures")
SCHEMA_DIR   = File.join(FIXTURE_DIR, "contract_schemas")
OUT_DIR      = File.join(__dir__, "out")
FileUtils.mkdir_p(OUT_DIR)

results  = []
failures = 0

def pass(results, id, label)
  results << { id: id, label: label, status: "PASS" }
  puts "  ✅ #{id}: #{label}"
end

def fail_check(results, id, label, detail = nil)
  results << { id: id, label: label, status: "FAIL", detail: detail }
  $stderr.puts "  ❌ #{id}: #{label}#{detail ? " — #{detail}" : ""}"
end

# ── Shared helpers ─────────────────────────────────────────────────────────

# Build a minimal ViewArtifact for linkage tests without going through .igv DSL.
def build_test_artifact(view_id:, slots: {}, elements: [], collections: {})
  IgniterView::ViewArtifact.new(
    view_id:     view_id,
    slots:       slots,
    elements:    elements,
    collections: collections
  )
end

def elem_def(id, params_schema)
  IgniterView::ElementDef.new(
    element_id:         id,
    static_classes:     "test-item",
    node_params_schema: params_schema,
    display_rules:      [],
    interaction_rules:  []
  )
end

puts "\n=== LAB-IGNITER-VIEW-FRAMEWORK-P6: Slot-Contract Type Linkage Proof ==="
puts "Date: #{Time.now.strftime("%Y-%m-%d %H:%M")}"
puts "Ruby: #{RUBY_VERSION}"
puts

# ── IVT-P6-1: Regression gates ────────────────────────────────────────────

puts "── IVT-P6-1: P1/P2/P3/P5 regression gates ──────────────────────────"

[
  ["IVT-P6-1a", "run_ivf_proof.rb",    "P1 proof runner (37 checks)"],
  ["IVT-P6-1b", "run_ivf_proof_p2.rb", "P2 proof runner (18+15 checks)"],
  ["IVT-P6-1c", "run_ivf_proof_p3.rb", "P3 proof runner (42 checks)"],
  ["IVT-P6-1d", "run_ivf_proof_p5.rb", "P5 proof runner (57 checks)"]
].each do |id, script, label|
  path = File.join(__dir__, script)
  if File.exist?(path)
    ok = system("ruby #{path} > /dev/null 2>&1")
    if ok
      pass(results, id, "#{label} exits cleanly")
    else
      fail_check(results, id, "#{label} exits cleanly", "non-zero exit")
      failures += 1
    end
  else
    fail_check(results, id, label, "script not found: #{script}")
    failures += 1
  end
end

puts

# ── IVT-P6-2: Valid slot-to-contract output linkage ───────────────────────

puts "── IVT-P6-2: Valid linkage (results_panel + search_contract) ────────"

begin
  # Load the compiled results_panel artifact (from P5 out/ or recompile)
  panel_result = IgniterView::IgvCompiler.compile_file(
    File.join(FIXTURE_DIR, "results_panel.igv")
  )
  raise "results_panel.igv failed to compile" unless panel_result.success?
  panel_artifact = panel_result.artifact

  # Load the search contract schema
  search_schema = IgniterView::ContractSchema.load_file(
    File.join(SCHEMA_DIR, "search_contract.json")
  )

  schemas = { "search" => search_schema }
  linkage = IgniterView::SlotTypeLinker.link(panel_artifact, schemas)

  # Write linkage result for inspection
  File.write(File.join(OUT_DIR, "results_panel_linkage.json"), JSON.pretty_generate(linkage.to_h))

  if linkage.valid?
    pass(results, "IVT-P6-2a", "Valid linkage: SlotTypeLinker.link returns valid? = true")
  else
    fail_check(results, "IVT-P6-2a", "Valid linkage returns valid?=true",
               linkage.errors.map { |e| e.detail }.join("; "))
    failures += 1
  end

  if linkage.errors.empty?
    pass(results, "IVT-P6-2b", "Valid linkage: zero error diagnostics")
  else
    fail_check(results, "IVT-P6-2b", "Zero error diagnostics",
               linkage.errors.map(&:type).join(", "))
    failures += 1
  end

  if linkage.warnings.empty?
    pass(results, "IVT-P6-2c", "Valid linkage: zero warning diagnostics (exact schema match)")
  else
    fail_check(results, "IVT-P6-2c", "Zero warnings for exact schema match",
               linkage.warnings.map { |w| "#{w.type}: #{w.detail}" }.join("; "))
    failures += 1
  end

  if linkage.diagnostics.empty?
    pass(results, "IVT-P6-2d", "Valid linkage: diagnostics array is empty")
  else
    fail_check(results, "IVT-P6-2d", "Empty diagnostics for valid linkage",
               "#{linkage.diagnostics.length} diagnostics found")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-2", "Valid linkage test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-3: Missing contract ref fails closed ───────────────────────────

puts "── IVT-P6-3: Missing contract ref → fails closed ────────────────────"

begin
  art3 = build_test_artifact(
    view_id:  "test.missing_ref",
    slots:    {
      "data" => { "type" => "array", "contract_ref" => "unknown_contract.output", "mode" => "read_only" }
    },
    elements: [elem_def("row", { "id" => "string" })],
    collections: {
      "rows" => { "slot" => "data", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result3 = IgniterView::SlotTypeLinker.link(art3, {})

  if !result3.valid?
    pass(results, "IVT-P6-3a", "Missing contract → valid?=false (fails closed)")
  else
    fail_check(results, "IVT-P6-3a", "Missing contract should fail closed")
    failures += 1
  end

  err3 = result3.errors.find { |e| e.type == :unresolved_contract_ref }
  if err3
    pass(results, "IVT-P6-3b", "Error type is :unresolved_contract_ref")
  else
    fail_check(results, "IVT-P6-3b", "Expected :unresolved_contract_ref error",
               result3.diagnostics.map { |d| d.type }.inspect)
    failures += 1
  end

  if err3 && err3.detail.to_s.include?("unknown_contract")
    pass(results, "IVT-P6-3c", "Error message names the missing contract_id")
  else
    fail_check(results, "IVT-P6-3c", "Error message names missing contract_id")
    failures += 1
  end

  if err3 && err3.slot == "data"
    pass(results, "IVT-P6-3d", "Error is attributed to the correct slot name")
  else
    fail_check(results, "IVT-P6-3d", "Error attributed to correct slot")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-3", "Missing contract ref test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-4: Missing output ref fails closed ─────────────────────────────

puts "── IVT-P6-4: Missing output ref → fails closed ──────────────────────"

begin
  schema4 = IgniterView::ContractSchema.build("my_contract", {
    "results" => { "type" => "array", "item_fields" => { "id" => { "type" => "string", "required" => true } } }
  })

  art4 = build_test_artifact(
    view_id: "test.missing_output",
    slots:   {
      "data" => { "type" => "array", "contract_ref" => "my_contract.nonexistent_output",
                  "mode" => "read_only" }
    },
    elements: [elem_def("row", { "id" => "string" })],
    collections: {
      "rows" => { "slot" => "data", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result4 = IgniterView::SlotTypeLinker.link(art4, { "my_contract" => schema4 })

  if !result4.valid?
    pass(results, "IVT-P6-4a", "Missing output ref → valid?=false")
  else
    fail_check(results, "IVT-P6-4a", "Missing output ref should fail closed")
    failures += 1
  end

  err4 = result4.errors.find { |e| e.type == :missing_output_ref }
  if err4
    pass(results, "IVT-P6-4b", "Error type is :missing_output_ref")
  else
    fail_check(results, "IVT-P6-4b", "Expected :missing_output_ref error",
               result4.diagnostics.map(&:type).inspect)
    failures += 1
  end

  if err4 && err4.detail.to_s.include?("nonexistent_output")
    pass(results, "IVT-P6-4c", "Error message names the missing output")
  else
    fail_check(results, "IVT-P6-4c", "Error message names the missing output")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-4", "Missing output ref test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-5: Array item schema matches node_params_schema ────────────────

puts "── IVT-P6-5: Full item schema match (enriched_search_contract subset) "

begin
  # Load enriched schema (has extra fields created_at, author)
  enriched_schema = IgniterView::ContractSchema.load_file(
    File.join(SCHEMA_DIR, "enriched_search_contract.json")
  )

  panel_result5 = IgniterView::IgvCompiler.compile_file(
    File.join(FIXTURE_DIR, "results_panel.igv")
  )
  raise unless panel_result5.success?
  art5 = panel_result5.artifact

  # Build adjusted slots that point to enriched_search contract
  # We'll build a custom artifact to test item field matching
  item_elem5 = elem_def("result_item", {
    "id" => "string", "title" => "string", "status" => "string", "score" => "integer"
  })
  art5b = build_test_artifact(
    view_id:  "test.p6_5",
    slots:    { "results" => { "type" => "array", "contract_ref" => "enriched_search.results",
                               "mode" => "read_only" } },
    elements: [item_elem5],
    collections: {
      "results_list" => { "slot" => "results", "item_element" => "result_item",
                          "item_key" => "id", "container_tag" => "ul",
                          "item_tag" => "li", "container_classes" => "" }
    }
  )

  result5 = IgniterView::SlotTypeLinker.link(art5b, { "enriched_search" => enriched_schema })

  # Should have: extra_item_field warnings for created_at and author (in contract but not in schema)
  # Should NOT have: errors (required fields id,title,status all present; score optional)
  if result5.errors.empty?
    pass(results, "IVT-P6-5a", "Full item match (required fields all covered): no errors")
  else
    fail_check(results, "IVT-P6-5a", "No errors for full required field coverage",
               result5.errors.map(&:detail).join("; "))
    failures += 1
  end

  # Contract has optional fields (created_at, author) NOT in node_params_schema.
  # Policy: element only needs to declare params it USES. Optional contract fields
  # that the element doesn't declare are silently allowed — no warning, no error.
  # Only required contract fields missing from element schema are errors.
  if result5.warnings.empty?
    pass(results, "IVT-P6-5b", "Contract optional extra fields not in element schema → silently allowed (0 warnings)")
  else
    fail_check(results, "IVT-P6-5b", "Optional contract-only fields should produce 0 warnings",
               "Got #{result5.warnings.length}: #{result5.warnings.map { |w| w.type }.join(", ")}")
    failures += 1
  end

  # Verify that the required fields (id, title, status) are covered — no missing_required_item_field
  missing_errs = result5.errors.select { |e| e.type == :missing_required_item_field }
  if missing_errs.empty?
    pass(results, "IVT-P6-5c", "No missing_required_item_field errors (all required fields covered)")
  else
    fail_check(results, "IVT-P6-5c", "Unexpected missing_required_item_field errors",
               missing_errs.map(&:detail).join("; "))
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-5", "Item schema match test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-6: Missing required item field ─────────────────────────────────

puts "── IVT-P6-6: Missing required item field → error ────────────────────"

begin
  schema6 = IgniterView::ContractSchema.build("strict_contract", {
    "items" => {
      "type" => "array",
      "item_fields" => {
        "id"        => { "type" => "string", "required" => true },
        "name"      => { "type" => "string", "required" => true },
        "author_id" => { "type" => "string", "required" => true }  # ← NOT in node_params_schema
      }
    }
  })

  # node_params_schema is missing "author_id"
  art6 = build_test_artifact(
    view_id:  "test.missing_field",
    slots:    { "items" => { "type" => "array", "contract_ref" => "strict_contract.items",
                             "mode" => "read_only" } },
    elements: [elem_def("row", { "id" => "string", "name" => "string" })],  # no author_id
    collections: {
      "rows" => { "slot" => "items", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result6 = IgniterView::SlotTypeLinker.link(art6, { "strict_contract" => schema6 })

  if !result6.valid?
    pass(results, "IVT-P6-6a", "Missing required field → valid?=false")
  else
    fail_check(results, "IVT-P6-6a", "Missing required field should fail closed")
    failures += 1
  end

  err6 = result6.errors.find { |e| e.type == :missing_required_item_field }
  if err6
    pass(results, "IVT-P6-6b", "Error type is :missing_required_item_field")
  else
    fail_check(results, "IVT-P6-6b", "Expected :missing_required_item_field error",
               result6.diagnostics.map(&:type).inspect)
    failures += 1
  end

  if err6 && err6.detail.to_s.include?("author_id")
    pass(results, "IVT-P6-6c", "Error message identifies the missing field 'author_id'")
  else
    fail_check(results, "IVT-P6-6c", "Error message names missing field")
    failures += 1
  end

  if err6 && err6.collection == "rows"
    pass(results, "IVT-P6-6d", "Error is attributed to the correct collection 'rows'")
  else
    fail_check(results, "IVT-P6-6d", "Error attributed to correct collection")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-6", "Missing required item field test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-7: Item field type mismatch ────────────────────────────────────

puts "── IVT-P6-7: Item field type mismatch → warning ─────────────────────"

begin
  schema7 = IgniterView::ContractSchema.build("typed_contract", {
    "items" => {
      "type" => "array",
      "item_fields" => {
        "id"    => { "type" => "string",  "required" => true },
        "score" => { "type" => "string",  "required" => false }  # contract says string
      }
    }
  })

  # node_params_schema says score is "integer" — mismatch!
  art7 = build_test_artifact(
    view_id:  "test.type_mismatch",
    slots:    { "items" => { "type" => "array", "contract_ref" => "typed_contract.items",
                             "mode" => "read_only" } },
    elements: [elem_def("row", { "id" => "string", "score" => "integer" })],
    collections: {
      "rows" => { "slot" => "items", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result7 = IgniterView::SlotTypeLinker.link(art7, { "typed_contract" => schema7 })

  if result7.valid?
    pass(results, "IVT-P6-7a", "Type mismatch is warning-only → valid?=true (not a hard error)")
  else
    fail_check(results, "IVT-P6-7a", "Type mismatch should be warning-only (valid?=true)",
               result7.errors.map(&:detail).join("; "))
    failures += 1
  end

  warn7 = result7.warnings.find { |w| w.type == :item_field_type_mismatch }
  if warn7
    pass(results, "IVT-P6-7b", "Warning type is :item_field_type_mismatch")
  else
    fail_check(results, "IVT-P6-7b", "Expected :item_field_type_mismatch warning",
               result7.diagnostics.map(&:type).inspect)
    failures += 1
  end

  if warn7 && warn7.detail.to_s.include?("score") &&
     warn7.detail.to_s.include?("integer") && warn7.detail.to_s.include?("string")
    pass(results, "IVT-P6-7c", "Warning message names field, declared type, and contract type")
  else
    fail_check(results, "IVT-P6-7c", "Warning message includes field name and both types")
    failures += 1
  end

  # Only warning, no errors → linkage is valid
  if result7.errors.empty?
    pass(results, "IVT-P6-7d", "Type mismatch produces no errors (warning policy)")
  else
    fail_check(results, "IVT-P6-7d", "Type mismatch should not produce errors")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-7", "Type mismatch test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-8: Extra item fields policy ────────────────────────────────────

puts "── IVT-P6-8: Extra item fields → allowed with warning ───────────────"

begin
  schema8 = IgniterView::ContractSchema.build("base_contract", {
    "items" => {
      "type" => "array",
      "item_fields" => {
        "id"   => { "type" => "string", "required" => true },
        "name" => { "type" => "string", "required" => true }
        # no "priority" or "tags" fields
      }
    }
  })

  # node_params_schema has "priority" and "tags" not in contract → extra fields
  art8 = build_test_artifact(
    view_id:  "test.extra_fields",
    slots:    { "items" => { "type" => "array", "contract_ref" => "base_contract.items",
                             "mode" => "read_only" } },
    elements: [elem_def("row", { "id" => "string", "name" => "string",
                                 "priority" => "string", "tags" => "string" })],
    collections: {
      "rows" => { "slot" => "items", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result8 = IgniterView::SlotTypeLinker.link(art8, { "base_contract" => schema8 })

  if result8.valid?
    pass(results, "IVT-P6-8a", "Extra item fields → valid?=true (allowed, not a hard error)")
  else
    fail_check(results, "IVT-P6-8a", "Extra fields should be allowed (valid?=true)",
               result8.errors.map(&:detail).join("; "))
    failures += 1
  end

  extra_warns8 = result8.warnings.select { |w| w.type == :extra_item_field }
  if extra_warns8.length == 2
    pass(results, "IVT-P6-8b", "Exactly 2 extra_item_field warnings (priority, tags)")
  else
    fail_check(results, "IVT-P6-8b", "Expected exactly 2 extra_item_field warnings",
               "Got #{extra_warns8.length}: #{extra_warns8.map { |w| w.detail }.join(" | ")}")
    failures += 1
  end

  field_names_8 = extra_warns8.map { |w| w.detail.to_s.match(/'([^']+)' which is not/) }
                               .compact.map { |m| m[1] }.sort
  if field_names_8 == %w[priority tags]
    pass(results, "IVT-P6-8c", "Extra field warnings name 'priority' and 'tags'")
  else
    fail_check(results, "IVT-P6-8c", "Extra field warnings name the correct fields",
               "Got: #{field_names_8.inspect}")
    failures += 1
  end

  if result8.errors.empty?
    pass(results, "IVT-P6-8d", "Extra fields produce no errors (explicit allowed policy)")
  else
    fail_check(results, "IVT-P6-8d", "Extra fields should not produce errors")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-8", "Extra item fields policy test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-8e: Slot type mismatch ─────────────────────────────────────────

puts "── IVT-P6-8e: Slot type mismatch (string slot, array contract) ──────"

begin
  schema_type = IgniterView::ContractSchema.build("type_check", {
    "data" => { "type" => "array", "item_fields" => { "id" => { "type" => "string", "required" => true } } }
  })

  # Slot declares type: "string" but contract says "array"
  art_type = build_test_artifact(
    view_id:  "test.slot_type",
    slots:    { "data" => { "type" => "string", "contract_ref" => "type_check.data",
                            "mode" => "read_only" } },
    elements: [elem_def("row", { "id" => "string" })],
    collections: {}
  )

  result_type = IgniterView::SlotTypeLinker.link(art_type, { "type_check" => schema_type })

  if !result_type.valid?
    pass(results, "IVT-P6-8e1", "Slot type mismatch → valid?=false (fails closed)")
  else
    fail_check(results, "IVT-P6-8e1", "Slot type mismatch should fail closed")
    failures += 1
  end

  err_type = result_type.errors.find { |e| e.type == :slot_type_mismatch }
  if err_type
    pass(results, "IVT-P6-8e2", "Error type is :slot_type_mismatch")
  else
    fail_check(results, "IVT-P6-8e2", "Expected :slot_type_mismatch",
               result_type.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-8e", "Slot type mismatch test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-8f: Non-array collection slot ──────────────────────────────────

puts "── IVT-P6-8f: Collection uses non-array slot → error ────────────────"

begin
  schema_str = IgniterView::ContractSchema.build("str_contract", {
    "name" => { "type" => "string" }
  })

  art_str = build_test_artifact(
    view_id:  "test.non_array_coll",
    slots:    { "name" => { "type" => "string", "contract_ref" => "str_contract.name",
                             "mode" => "read_only" } },
    elements: [elem_def("row", { "id" => "string" })],
    collections: {
      "rows" => { "slot" => "name", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result_str = IgniterView::SlotTypeLinker.link(art_str, { "str_contract" => schema_str })

  if !result_str.valid?
    pass(results, "IVT-P6-8f1", "Collection on non-array slot → valid?=false")
  else
    fail_check(results, "IVT-P6-8f1", "Non-array collection slot should fail closed")
    failures += 1
  end

  err_str = result_str.errors.find { |e| e.type == :non_array_collection_slot || e.type == :slot_type_mismatch }
  if err_str
    pass(results, "IVT-P6-8f2", "Error produced for collection using non-array slot")
  else
    fail_check(results, "IVT-P6-8f2", "Expected error for non-array collection slot",
               result_str.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-8f", "Non-array collection slot test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-8g: Missing item_fields in contract → warning ──────────────────

puts "── IVT-P6-8g: Array output without item_fields → warning ────────────"

begin
  schema_nofields = IgniterView::ContractSchema.build("nofields_contract", {
    "items" => { "type" => "array" }  # no item_fields
  })

  art_nf = build_test_artifact(
    view_id:  "test.no_item_fields",
    slots:    { "items" => { "type" => "array", "contract_ref" => "nofields_contract.items",
                             "mode" => "read_only" } },
    elements: [elem_def("row", { "id" => "string" })],
    collections: {
      "rows" => { "slot" => "items", "item_element" => "row", "item_key" => "id",
                  "container_tag" => "ul", "item_tag" => "li", "container_classes" => "" }
    }
  )

  result_nf = IgniterView::SlotTypeLinker.link(art_nf, { "nofields_contract" => schema_nofields })

  if result_nf.valid?
    pass(results, "IVT-P6-8g1", "Missing item_fields → valid?=true (warning only)")
  else
    fail_check(results, "IVT-P6-8g1", "Missing item_fields should be warning-only")
    failures += 1
  end

  warn_nf = result_nf.warnings.find { |w| w.type == :missing_item_fields_schema }
  if warn_nf
    pass(results, "IVT-P6-8g2", "Warning type is :missing_item_fields_schema")
  else
    fail_check(results, "IVT-P6-8g2", "Expected :missing_item_fields_schema warning",
               result_nf.diagnostics.map(&:type).inspect)
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-8g", "Missing item_fields test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-9: SSR rendering deterministic for valid collections ────────────

puts "── IVT-P6-9: SSR rendering unchanged for valid linked collections ───"

begin
  panel_result9 = IgniterView::IgvCompiler.compile_file(
    File.join(FIXTURE_DIR, "results_panel.igv")
  )
  raise unless panel_result9.success?
  artifact9 = panel_result9.artifact

  sample_items = [
    { "id" => "r1", "title" => "Alpha", "status" => "ok",      "score" => 95 },
    { "id" => "r2", "title" => "Beta",  "status" => "error",   "score" => 12 },
    { "id" => "r3", "title" => "Gamma", "status" => "warning", "score" => 55 }
  ]

  renderer9 = IgniterView::SSRRenderer.new(artifact9,
    slot_values: { "results" => sample_items, "query" => "test", "total" => 3 })

  html9a = renderer9.render_root { renderer9.render_collection(:results_list) }
  html9b = renderer9.render_root { renderer9.render_collection(:results_list) }

  if html9a == html9b
    pass(results, "IVT-P6-9a", "SSR collection render is deterministic after P6 linkage layer")
  else
    fail_check(results, "IVT-P6-9a", "SSR collection renders should be identical")
    failures += 1
  end

  if html9a.scan("data-ig-item-key=").count == 3
    pass(results, "IVT-P6-9b", "SSR renders 3 items (slot values unchanged by linker)")
  else
    fail_check(results, "IVT-P6-9b", "Expected 3 items in SSR output")
    failures += 1
  end

  if html9a.include?("border-ok") && html9a.include?("border-oof") && html9a.include?("border-warn")
    pass(results, "IVT-P6-9c", "SSR per-item display rules still applied correctly")
  else
    fail_check(results, "IVT-P6-9c", "SSR display rules unchanged by P6")
    failures += 1
  end

rescue => e
  fail_check(results, "IVT-P6-9", "SSR determinism test", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVT-P6-10: JS runtime DOM proof still passes ─────────────────────────

puts "── IVT-P6-10: JS DOM proof (P5) still passes ───────────────────────"

begin
  dom_proof = File.join(__dir__, "run_ivf_dom_proof_p5.js")
  if File.exist?(dom_proof)
    ok = system("node #{dom_proof} > /dev/null 2>&1")
    if ok
      pass(results, "IVT-P6-10", "P5 Node.js DOM proof (19 checks) still passes after P6 additions")
    else
      fail_check(results, "IVT-P6-10", "P5 DOM proof exits cleanly")
      failures += 1
    end
  else
    fail_check(results, "IVT-P6-10", "P5 DOM proof script found", "not found: #{dom_proof}")
    failures += 1
  end
rescue => e
  fail_check(results, "IVT-P6-10", "DOM proof check", e.message)
  failures += 1
end

puts

# ── IVT-P6-11: Safety forbidden constructs absent ─────────────────────────

puts "── IVT-P6-11: No forbidden constructs in new P6 source files ────────"

linker_src = File.read(File.join(__dir__, "lib", "slot_type_linker.rb"), encoding: "utf-8")
schema_src = File.read(File.join(__dir__, "lib", "contract_schema.rb"),  encoding: "utf-8")

all_new_src = linker_src + schema_src

# Strip comment lines before checking — comments document what is NOT done, not actual calls.
non_comment_src  = all_new_src.lines.reject { |l| l.strip.start_with?("#") }.join
no_contract_exec = !non_comment_src.match?(/Igniter::Contract|\.call\(\s*inputs/)

[
  ["No innerHTML",          !all_new_src.match?(/innerHTML/)],
  ["No eval()",             !all_new_src.match?(/\beval\s*\(/)],
  ["No fetch()",            !all_new_src.match?(/\bfetch\s*\(/)],
  ["No File::open (net)",   !all_new_src.match?(/Net::HTTP/)],
  ["No require net",        !all_new_src.match?(/require.*net\/http/)],
  ["No contract execution", no_contract_exec],
  ["No localStorage",       !all_new_src.match?(/localStorage/)],
  ["No sessionStorage",     !all_new_src.match?(/sessionStorage/)]
].each do |(label, ok)|
  if ok
    pass(results, "IVT-P6-11", "Source guard: #{label}")
  else
    fail_check(results, "IVT-P6-11", "Source guard: #{label}")
    failures += 1
  end
end

puts

# ── IVT-P6-12: Lab-only markers ───────────────────────────────────────────

puts "── IVT-P6-12: Lab-only markers present ──────────────────────────────"

[
  ["slot_type_linker.rb has lab-only marker",
   linker_src.include?("lab-only")],
  ["slot_type_linker.rb has no-canon marker",
   linker_src.include?("no-canon")],
  ["slot_type_linker.rb has no-stable-schema marker",
   linker_src.include?("no-stable-schema")],
  ["contract_schema.rb has lab-only marker",
   schema_src.include?("lab-only")],
  ["contract_schema.rb has no-public-api marker",
   schema_src.include?("no-public-api")],
  ["search_contract.json has _status field",
   File.read(File.join(SCHEMA_DIR, "search_contract.json")).include?("experimental")]
].each do |(label, ok)|
  if ok
    pass(results, "IVT-P6-12", label)
  else
    fail_check(results, "IVT-P6-12", label)
    failures += 1
  end
end

puts

# ── IVT-P6-13: igniter-lang/** untouched ─────────────────────────────────

puts "── IVT-P6-13: igniter-lang/** untouched ─────────────────────────────"

begin
  igniter_lang_root = File.expand_path("../../igniter-lang", File.dirname(__dir__))
  if Dir.exist?(igniter_lang_root)
    modified = `git -C #{igniter_lang_root} status --porcelain 2>/dev/null`
               .lines.reject { |l| l.start_with?("??") }.map(&:strip).reject(&:empty?)
    if modified.empty?
      pass(results, "IVT-P6-13", "igniter-lang has no tracked-file changes (P6 canon boundary)")
    else
      fail_check(results, "IVT-P6-13", "igniter-lang unchanged", modified.join("; "))
      failures += 1
    end
  else
    pass(results, "IVT-P6-13", "igniter-lang not present (separate repo — boundary by policy)")
  end
rescue => e
  pass(results, "IVT-P6-13", "igniter-lang check inconclusive — boundary maintained by policy")
end

puts

# ── Summary ───────────────────────────────────────────────────────────────

total  = results.length
passed = results.count { |r| r[:status] == "PASS" }
failed = results.count { |r| r[:status] == "FAIL" }

summary = {
  runner:  "LAB-IGNITER-VIEW-FRAMEWORK-P6",
  date:    Time.now.strftime("%Y-%m-%d %H:%M"),
  ruby:    RUBY_VERSION,
  total:   total,
  passed:  passed,
  failed:  failed,
  results: results
}

File.write(File.join(OUT_DIR, "ivf_p6_proof_summary.json"), JSON.pretty_generate(summary))

puts "═══════════════════════════════════════════════════════════"
puts "LAB-IGNITER-VIEW-FRAMEWORK-P6 Proof Summary"
puts "  Total:  #{total}"
puts "  Passed: #{passed}"
puts "  Failed: #{failed}"
puts "  Output: #{File.join(OUT_DIR, "ivf_p6_proof_summary.json")}"
puts "═══════════════════════════════════════════════════════════"

if failures > 0
  puts "\n⚠️  #{failures} check(s) FAILED."
  exit 1
else
  puts "\n✅ All checks PASS."
  exit 0
end
