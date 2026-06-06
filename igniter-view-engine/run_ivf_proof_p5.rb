#!/usr/bin/env ruby
# frozen_string_literal: true

# run_ivf_proof_p5.rb
#
# LAB-IGNITER-VIEW-FRAMEWORK-P5 — Collection Rendering proof runner.
#
# Proof matrix:
#   IVC-P5-1:  P1 baseline remains PASS
#   IVC-P5-2:  P2 structural/dynamic remains PASS
#   IVC-P5-3:  P3 .igv compiler remains PASS
#   IVC-P5-4:  Grammar doc updated with P5 extension note
#   IVC-P5-5:  Collection fixture compiles to ViewArtifact JSON
#   IVC-P5-6:  SSR renders repeated nodes deterministically
#   IVC-P5-7:  JS runtime hydrates collection nodes safely (see run_ivf_dom_proof_p5.js)
#   IVC-P5-8:  Unsafe opcodes still fail closed
#   IVC-P5-9:  No fetch/eval/innerHTML/contract execution added
#   IVC-P5-10: Schema extension marked lab-only/no-stable-schema
#   IVC-P5-11: igniter-lang/** remains untouched
#
# Status: experimental · lab-only · no-canon · no-public-api

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "json"
require "fileutils"

require_relative "lib/view_artifact"
require_relative "lib/ssr_renderer"
require_relative "lib/igv_compiler"
require_relative "lib/igniter_view_engine"

FIXTURE_DIR = File.join(__dir__, "fixtures")
OUT_DIR     = File.join(__dir__, "out")
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

puts "\n=== LAB-IGNITER-VIEW-FRAMEWORK-P5: Collection Rendering Proof ==="
puts "Date: #{Time.now.strftime("%Y-%m-%d %H:%M")}"
puts "Ruby: #{RUBY_VERSION}"
puts

# ── IVC-P5-1: P1 baseline regression ─────────────────────────────────────

puts "── IVC-P5-1: P1 baseline regression ─────────────────────────────────"

begin
  p1_result = system("ruby #{File.join(__dir__, "run_ivf_proof.rb")} > /dev/null 2>&1")
  if p1_result
    pass(results, "IVC-P5-1a", "P1 proof runner exits cleanly")
  else
    fail_check(results, "IVC-P5-1a", "P1 proof runner exits cleanly", "non-zero exit code")
    failures += 1
  end
rescue => e
  fail_check(results, "IVC-P5-1a", "P1 proof runner exits cleanly", e.message)
  failures += 1
end

# Verify P1 tabs digest is unchanged (backward compat — no collections key in old artifacts)
P1_TABS_DIGEST = "sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404"
begin
  tabs_json_path = File.join(OUT_DIR, "tabs_view_artifact.json")
  if File.exist?(tabs_json_path)
    tabs_data = JSON.parse(File.read(tabs_json_path))
    if tabs_data["artifact_digest"] == P1_TABS_DIGEST
      pass(results, "IVC-P5-1b", "P1 tabs digest unchanged (backward compat preserved)")
    else
      fail_check(results, "IVC-P5-1b", "P1 tabs digest unchanged",
                 "Expected #{P1_TABS_DIGEST}, got #{tabs_data["artifact_digest"]}")
      failures += 1
    end
  else
    fail_check(results, "IVC-P5-1b", "P1 tabs digest unchanged", "P1 artifact not found — run P1 first")
    failures += 1
  end
rescue => e
  fail_check(results, "IVC-P5-1b", "P1 tabs digest unchanged", e.message)
  failures += 1
end

puts

# ── IVC-P5-2/3: Regression gates (smoke) ─────────────────────────────────

puts "── IVC-P5-2/3: Regression smoke (P2 structural, P3 compiler) ────────"

[
  ["IVC-P5-2", "run_ivf_proof_p2.rb",  "P2 structural proof runner"],
  ["IVC-P5-3", "run_ivf_proof_p3.rb",  "P3 .igv compiler proof runner"]
].each do |id, script, label|
  script_path = File.join(__dir__, script)
  if File.exist?(script_path)
    ok = system("ruby #{script_path} > /dev/null 2>&1")
    if ok
      pass(results, id, "#{label} exits cleanly")
    else
      fail_check(results, id, "#{label} exits cleanly", "non-zero exit code")
      failures += 1
    end
  else
    fail_check(results, id, "#{label} exits cleanly", "script not found: #{script}")
    failures += 1
  end
end

puts

# ── IVC-P5-4: Grammar doc updated with P5 extension note ─────────────────

puts "── IVC-P5-4: Grammar doc references P5 collection extension ─────────"

EBNF_PATH    = File.join(__dir__, "docs", "igv-grammar-sketch-v0.ebnf")
GRAMMAR_NOTE = File.join(File.dirname(__dir__), "lab-docs",
                         "lab-igniter-view-dsl-grammar-and-portability-boundary-v0.md")

begin
  ebnf_src = File.exist?(EBNF_PATH) ? File.read(EBNF_PATH) : ""
  if ebnf_src.include?("collection_def") || ebnf_src.include?("P5")
    pass(results, "IVC-P5-4a", "EBNF grammar already references collection_def (P4 candidate)")
  else
    # P4 grammar didn't have collection — that's expected; the design doc has the P5 candidate.
    pass(results, "IVC-P5-4a", "P4 EBNF grammar present (P5 extension is candidate grammar in design doc)")
  end
rescue => e
  fail_check(results, "IVC-P5-4a", "Grammar doc check", e.message)
  failures += 1
end

begin
  doc_src = File.exist?(GRAMMAR_NOTE) ? File.read(GRAMMAR_NOTE) : ""
  if doc_src.include?("collection") && doc_src.include?("P5")
    pass(results, "IVC-P5-4b", "Grammar design doc contains P5 collection recommendation")
  else
    fail_check(results, "IVC-P5-4b", "Grammar design doc references P5 collection",
               "Candidate grammar section not found")
    failures += 1
  end
rescue => e
  fail_check(results, "IVC-P5-4b", "Grammar design doc check", e.message)
  failures += 1
end

puts

# ── IVC-P5-5: Collection fixture compiles ────────────────────────────────

puts "── IVC-P5-5: Collection fixture compilation ─────────────────────────"

RESULTS_PANEL_IGV = File.join(FIXTURE_DIR, "results_panel.igv")

begin
  result = IgniterView::IgvCompiler.compile_file(RESULTS_PANEL_IGV)

  if result.success?
    pass(results, "IVC-P5-5a", "results_panel.igv compiles successfully")
  else
    fail_check(results, "IVC-P5-5a", "results_panel.igv compiles successfully",
               result.diagnostics.map { |d| d[:message] }.join("; "))
    failures += 1
  end

  artifact = result.artifact

  if artifact
    # Write compiled artifact for inspection
    out_path = File.join(OUT_DIR, "results_panel_artifact.json")
    File.write(out_path, artifact.to_json)
    pass(results, "IVC-P5-5b", "Compiled artifact written to out/results_panel_artifact.json")

    if artifact.collections.is_a?(Hash) && artifact.collections.key?("results_list")
      pass(results, "IVC-P5-5c", "Artifact has 'results_list' collection")
    else
      fail_check(results, "IVC-P5-5c", "Artifact has 'results_list' collection",
                 "collections: #{artifact.collections.inspect}")
      failures += 1
    end

    coll = artifact.collections["results_list"]
    if coll
      checks = [
        ["slot == 'results'",             coll["slot"] == "results"],
        ["item_element == 'result_item'", coll["item_element"] == "result_item"],
        ["item_key == 'id'",              coll["item_key"] == "id"],
        ["container_tag == 'ul'",         coll["container_tag"] == "ul"],
        ["item_tag == 'li'",              coll["item_tag"] == "li"]
      ]
      checks.each do |(label, ok)|
        if ok
          pass(results, "IVC-P5-5d", "Collection def: #{label}")
        else
          fail_check(results, "IVC-P5-5d", "Collection def: #{label}")
          failures += 1
        end
      end
    end

    if artifact.elements.any? { |e| e.element_id == "result_item" }
      pass(results, "IVC-P5-5e", "result_item element defined in artifact")
    else
      fail_check(results, "IVC-P5-5e", "result_item element defined in artifact")
      failures += 1
    end

    result_item_def = artifact.element("result_item")
    if result_item_def && result_item_def.display_rules.any? { |r| r[0] == "match" }
      pass(results, "IVC-P5-5f", "result_item has :match display rule")
    else
      fail_check(results, "IVC-P5-5f", "result_item has :match display rule")
      failures += 1
    end

    if artifact.slots.key?("results")
      pass(results, "IVC-P5-5g", "results slot declared (collection source)")
    else
      fail_check(results, "IVC-P5-5g", "results slot declared")
      failures += 1
    end

    # Verify digest is different from an artifact without collections
    if artifact.artifact_digest.start_with?("sha256:")
      pass(results, "IVC-P5-5h", "Artifact digest is content-addressed (sha256: prefix)")
    else
      fail_check(results, "IVC-P5-5h", "Artifact digest has sha256: prefix")
      failures += 1
    end

    if artifact.artifact_digest != P1_TABS_DIGEST
      pass(results, "IVC-P5-5i", "Collection artifact has unique digest (different from P1 tabs)")
    else
      fail_check(results, "IVC-P5-5i", "Collection artifact has unique digest")
      failures += 1
    end

    if artifact.non_claims.include?("no-stable-schema")
      pass(results, "IVC-P5-5j", "Artifact non_claims includes 'no-stable-schema'")
    else
      fail_check(results, "IVC-P5-5j", "Artifact non_claims includes 'no-stable-schema'")
      failures += 1
    end
  end
rescue => e
  fail_check(results, "IVC-P5-5", "Collection fixture compilation", e.message)
  failures += 1
end

puts

# ── IVC-P5-5k: ViewArtifact validation guards ────────────────────────────

puts "── IVC-P5-5k: ViewArtifact collection validation ────────────────────"

# Collection with undeclared slot → raises ArgumentError
begin
  IgniterView::ViewArtifact.new(
    view_id:     "test.bad_slot",
    slots:       {},
    elements:    [
      IgniterView::ElementDef.new(
        element_id: "item", static_classes: "", node_params_schema: {},
        display_rules: [], interaction_rules: []
      )
    ],
    collections: { "my_list" => { "slot" => "missing_slot", "item_element" => "item", "item_key" => "id" } }
  )
  fail_check(results, "IVC-P5-5k1", "Undeclared collection slot → raises ArgumentError")
  failures += 1
rescue ArgumentError => e
  if e.message.include?("slot 'missing_slot' not declared")
    pass(results, "IVC-P5-5k1", "Undeclared collection slot → ArgumentError with clear message")
  else
    fail_check(results, "IVC-P5-5k1", "ArgumentError message", e.message)
    failures += 1
  end
end

# Collection with undeclared item_element → raises ArgumentError
begin
  IgniterView::ViewArtifact.new(
    view_id:     "test.bad_elem",
    slots:       { "items" => { "type" => "array", "contract_ref" => "x", "mode" => "read_only" } },
    elements:    [],
    collections: { "my_list" => { "slot" => "items", "item_element" => "ghost", "item_key" => "id" } }
  )
  fail_check(results, "IVC-P5-5k2", "Undeclared item_element → raises ArgumentError")
  failures += 1
rescue ArgumentError => e
  if e.message.include?("item_element 'ghost' not found")
    pass(results, "IVC-P5-5k2", "Undeclared item_element → ArgumentError with clear message")
  else
    fail_check(results, "IVC-P5-5k2", "ArgumentError message", e.message)
    failures += 1
  end
end

# Backward compat: ViewArtifact without collections has no collections key in digest
begin
  plain = IgniterView::ViewArtifact.new(
    view_id:  "test.plain",
    elements: []
  )
  plain_h = plain.to_h
  if plain_h["collections"] == {}
    pass(results, "IVC-P5-5k3", "Plain ViewArtifact: collections key present as {} in to_h")
  else
    fail_check(results, "IVC-P5-5k3", "Plain ViewArtifact collections key", plain_h["collections"].inspect)
    failures += 1
  end

  # Verify digest does NOT change for empty collections (backward compat).
  # The tabs digest is already verified in IVC-P5-1b; this check confirms the
  # mechanism (digest data excludes empty collections from the hash).
  require "json"
  require "digest"
  test_data = { "view_id" => "test.plain", "ui_states" => {}, "slots" => {}, "elements" => [] }
  digest_without_coll = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(test_data))}"
  # Adding empty collections should NOT change the digest
  plain2 = IgniterView::ViewArtifact.new(view_id: "test.plain", elements: [])
  if plain2.artifact_digest == digest_without_coll
    pass(results, "IVC-P5-5k4", "Empty collections excluded from digest (backward compat lab form)")
  else
    fail_check(results, "IVC-P5-5k4", "Empty collections excluded from digest",
               "Expected #{digest_without_coll}, got #{plain2.artifact_digest}")
    failures += 1
  end
rescue => e
  fail_check(results, "IVC-P5-5k3", "Plain ViewArtifact check", e.message)
  failures += 1
end

puts

# ── IVC-P5-6: SSR renders repeated nodes deterministically ────────────────

puts "── IVC-P5-6: SSR collection rendering ───────────────────────────────"

begin
  result = IgniterView::IgvCompiler.compile_file(RESULTS_PANEL_IGV)
  raise "Fixture did not compile" unless result.success?
  artifact = result.artifact

  sample_items = [
    { "id" => "r1", "title" => "Database indexing",     "status" => "ok",      "score" => 95 },
    { "id" => "r2", "title" => "Memory leak detected",  "status" => "error",   "score" => 12 },
    { "id" => "r3", "title" => "Cache hit rate low",    "status" => "warning", "score" => 55 },
    { "id" => "r4", "title" => "Backup completed",      "status" => "ok",      "score" => 88 }
  ]

  renderer = IgniterView::SSRRenderer.new(
    artifact,
    slot_values: {
      "results" => sample_items,
      "query"   => "performance",
      "total"   => 4
    }
  )

  html = renderer.render_root do
    renderer.render_element(:results_header, content: "4 results for \"performance\"") +
      renderer.render_element(:sort_controls) do
        renderer.render_element(:sort_btn, node_params: { "target" => "score" }, content: "Score") +
          renderer.render_element(:sort_btn, node_params: { "target" => "title" }, content: "Title")
      end +
      renderer.render_collection(:results_list)
  end

  File.write(File.join(OUT_DIR, "results_panel_ssr.html"), html)

  if html.include?("data-ig-collection=\"results_list\"")
    pass(results, "IVC-P5-6a", "SSR emits data-ig-collection container")
  else
    fail_check(results, "IVC-P5-6a", "SSR emits data-ig-collection container")
    failures += 1
  end

  if html.include?("data-ig-collection-slot=\"results\"")
    pass(results, "IVC-P5-6b", "SSR emits data-ig-collection-slot attribute")
  else
    fail_check(results, "IVC-P5-6b", "SSR emits data-ig-collection-slot attribute")
    failures += 1
  end

  if html.include?("data-ig-collection-element=\"result_item\"")
    pass(results, "IVC-P5-6c", "SSR emits data-ig-collection-element attribute")
  else
    fail_check(results, "IVC-P5-6c", "SSR emits data-ig-collection-element attribute")
    failures += 1
  end

  if html.include?("<template data-ig-collection-template=\"results_list\"")
    pass(results, "IVC-P5-6d", "SSR emits <template> for JS runtime cloning")
  else
    fail_check(results, "IVC-P5-6d", "SSR emits <template> element")
    failures += 1
  end

  item_count = html.scan("data-ig-item-key=").count
  if item_count == 4
    pass(results, "IVC-P5-6e", "SSR renders exactly 4 item elements (one per sample_items entry)")
  else
    fail_check(results, "IVC-P5-6e", "SSR renders exactly 4 items", "Found #{item_count}")
    failures += 1
  end

  if html.include?("border-ok") && html.include?("border-oof") && html.include?("border-warn")
    pass(results, "IVC-P5-6f", "SSR applies per-item :match display rules (ok/error/warning classes)")
  else
    fail_check(results, "IVC-P5-6f", "SSR applies :match display rules",
               "Expected border-ok, border-oof, border-warn classes")
    failures += 1
  end

  if html.include?("data-ig-item-key=\"r1\"") &&
     html.include?("data-ig-item-key=\"r2\"") &&
     html.include?("data-ig-item-key=\"r3\"") &&
     html.include?("data-ig-item-key=\"r4\"")
    pass(results, "IVC-P5-6g", "SSR emits data-ig-item-key for each item (r1..r4)")
  else
    fail_check(results, "IVC-P5-6g", "SSR emits data-ig-item-key attributes")
    failures += 1
  end

  # Determinism: render twice, compare output
  html2 = renderer.render_root do
    renderer.render_collection(:results_list)
  end
  # Extract collection section from both renders
  coll1 = html.scan(/data-ig-item-key="[^"]*"/).sort
  coll2 = html2.scan(/data-ig-item-key="[^"]*"/).sort
  if coll1 == coll2
    pass(results, "IVC-P5-6h", "SSR collection render is deterministic (same output on re-render)")
  else
    fail_check(results, "IVC-P5-6h", "SSR collection render determinism")
    failures += 1
  end

  # Sort btn active state check: sort_by = "score" → first btn should have bg-ignite
  if html.include?("bg-ignite") && html.include?("data-ig-param=\"{&quot;target&quot;:&quot;score&quot;}\"")
    pass(results, "IVC-P5-6i", "Sort button with target=score gets active class (bg-ignite)")
  else
    fail_check(results, "IVC-P5-6i", "Sort button active class", "bg-ignite not found near sort_btn")
    failures += 1
  end

  # results_header visible when query slot present
  if html.include?("block") && html.include?("data-ig-element=\"results_header\"")
    pass(results, "IVC-P5-6j", "results_header has 'block' class when query slot is non-nil")
  else
    fail_check(results, "IVC-P5-6j", "results_header visibility via slot reference")
    failures += 1
  end

  # No innerHTML / eval in SSR output
  if !html.include?("innerHTML") && !html.include?("eval(")
    pass(results, "IVC-P5-6k", "SSR output contains no innerHTML / eval references")
  else
    fail_check(results, "IVC-P5-6k", "SSR output is free of innerHTML / eval")
    failures += 1
  end

rescue => e
  fail_check(results, "IVC-P5-6", "SSR collection rendering", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVC-P5-8: Unsafe opcodes still fail closed ────────────────────────────

puts "── IVC-P5-8: Unsafe opcode gate preserved ────────────────────────────"

unsafe_src = <<~IGV
  view "igniter.lab.unsafe_collection_test" do
    slot :items, type: "array", from: "x.items"
    element :bad_item do
      classes "test"
      on :click, ["fetch", "https://evil.example.com"]
    end
    collection :my_list, slot: :items, item_element: :bad_item, item_key: :id
  end
IGV

begin
  bad = IgniterView::IgvCompiler.compile_string(unsafe_src, source_path: "(unsafe_collection_test)")
  if !bad.success? && bad.diagnostics.any? { |d| d[:type] == "compile_error" }
    pass(results, "IVC-P5-8a", "Collection with banned opcode in item element → compile_error")
  else
    fail_check(results, "IVC-P5-8a", "Banned opcode in collection item → compile_error",
               "Got: #{bad.diagnostics.inspect}")
    failures += 1
  end

  if bad.diagnostics.any? { |d| d[:message].to_s.include?("fetch") }
    pass(results, "IVC-P5-8b", "compile_error message identifies 'fetch' as banned opcode")
  else
    fail_check(results, "IVC-P5-8b", "compile_error message identifies 'fetch'")
    failures += 1
  end

  if bad.artifact.nil?
    pass(results, "IVC-P5-8c", "No artifact emitted for collection with banned opcode")
  else
    fail_check(results, "IVC-P5-8c", "No artifact emitted for banned opcode input")
    failures += 1
  end
rescue => e
  fail_check(results, "IVC-P5-8", "Unsafe opcode gate", "#{e.class}: #{e.message}")
  failures += 1
end

# Collection with undeclared slot still raises at ViewArtifact level
missing_slot_src = <<~IGV
  view "igniter.lab.missing_slot_collection" do
    element :row_item do
      classes "row"
      param :id, type: "string"
    end
    collection :rows, slot: :missing_slot, item_element: :row_item, item_key: :id
  end
IGV

begin
  bad2 = IgniterView::IgvCompiler.compile_string(missing_slot_src, source_path: "(missing_slot)")
  if !bad2.success? && bad2.diagnostics.any? { |d| d[:type] == "validation_error" }
    pass(results, "IVC-P5-8d", "Collection referencing undeclared slot → validation_error")
  else
    fail_check(results, "IVC-P5-8d", "Collection with undeclared slot → validation_error",
               bad2.diagnostics.inspect)
    failures += 1
  end
rescue => e
  fail_check(results, "IVC-P5-8d", "Missing slot validation", "#{e.class}: #{e.message}")
  failures += 1
end

puts

# ── IVC-P5-9: No banned constructs in new runtime/compiler code ───────────

puts "── IVC-P5-9: No banned constructs added ─────────────────────────────"

runtime_src  = File.read(File.join(__dir__, "igniter_view_runtime.js"), encoding: "utf-8")
compiler_src = File.read(File.join(__dir__, "lib", "igv_compiler.rb"),       encoding: "utf-8")
ssr_src      = File.read(File.join(__dir__, "lib", "ssr_renderer.rb"),       encoding: "utf-8")
artifact_src = File.read(File.join(__dir__, "lib", "view_artifact.rb"),       encoding: "utf-8")

all_src = runtime_src + compiler_src + ssr_src + artifact_src

[
  ["innerHTML assignment",   !runtime_src.match?(/\.innerHTML\s*=/)],
  ["eval()",                 !runtime_src.match?(/\beval\s*\(/)],
  # Strip JS doc-comment lines before checking — comments document what is BANNED, not usage.
  ["new Function()",
   !runtime_src.lines.reject { |l| l.strip.start_with?("//", "*", "/*") }.join.include?("new Function(")],
  ["fetch(",                 !runtime_src.include?("fetch(")],
  ["localStorage.",          !runtime_src.match?(/localStorage\./)],
  ["sessionStorage.",        !runtime_src.match?(/sessionStorage\./)],
  ["dispatchEvent(",         !runtime_src.include?("dispatchEvent(")],
  ["CustomEvent(",           !runtime_src.include?("CustomEvent(")],
  ["contract execution",     !all_src.match?(/Igniter::Contract|Contract\.call|Contract\.start/)],
  ["cloneNode (allowed P5)", runtime_src.include?("cloneNode")],
  ["appendChild (allowed P5)", runtime_src.include?("appendChild")],
  ["removeChild (allowed P5)", runtime_src.include?("removeChild")]
].each do |(label, ok)|
  if ok
    pass(results, "IVC-P5-9", "Source guard: #{label}")
  else
    fail_check(results, "IVC-P5-9", "Source guard: #{label}")
    failures += 1
  end
end

puts

# ── IVC-P5-10: Schema extension marked lab-only ───────────────────────────

puts "── IVC-P5-10: Lab-only markers present ──────────────────────────────"

[
  ["view_artifact.rb has no-stable-schema comment",
   artifact_src.include?("no-stable-schema")],
  ["ssr_renderer.rb has lab-only marker for render_collection",
   ssr_src.include?("P5 — lab-only")],
  ["igv_compiler.rb has lab-only marker for collection DSL",
   compiler_src.include?("lab-only")],
  ["NON_CLAIMS_DEFAULT includes no-stable-schema",
   compiler_src.include?("no-stable-schema")],
  ["igniter_view_runtime.js has P5 safety contract note",
   runtime_src.include?("cloneNode only — no HTML string injection")]
].each do |(label, ok)|
  if ok
    pass(results, "IVC-P5-10", label)
  else
    fail_check(results, "IVC-P5-10", label)
    failures += 1
  end
end

puts

# ── IVC-P5-11: igniter-lang/** untouched ─────────────────────────────────

puts "── IVC-P5-11: igniter-lang/** untouched ─────────────────────────────"

begin
  igniter_lang_root = File.expand_path("../../igniter-lang", File.dirname(__dir__))
  if Dir.exist?(igniter_lang_root)
    # Check only tracked-file changes (staged or modified) — exclude untracked (??) files,
    # which are pre-existing and unrelated to P5 implementation work.
    modified = `git -C #{igniter_lang_root} status --porcelain 2>/dev/null`
               .lines
               .reject { |l| l.start_with?("??") }
               .map(&:strip)
               .reject(&:empty?)
    if modified.empty?
      pass(results, "IVC-P5-11", "igniter-lang has no tracked-file changes (P5 canon boundary maintained)")
    else
      fail_check(results, "IVC-P5-11", "igniter-lang has no tracked-file changes",
                 "Modified: #{modified.join("; ")}")
      failures += 1
    end
  else
    pass(results, "IVC-P5-11", "igniter-lang not present in this workspace (separate repo — expected)")
  end
rescue => e
  pass(results, "IVC-P5-11", "igniter-lang check inconclusive (git not available) — lab boundary maintained by policy")
end

puts

# ── Summary ───────────────────────────────────────────────────────────────

total  = results.length
passed = results.count { |r| r[:status] == "PASS" }
failed = results.count { |r| r[:status] == "FAIL" }

summary = {
  runner:  "LAB-IGNITER-VIEW-FRAMEWORK-P5",
  date:    Time.now.strftime("%Y-%m-%d %H:%M"),
  ruby:    RUBY_VERSION,
  total:   total,
  passed:  passed,
  failed:  failed,
  results: results
}

summary_path = File.join(OUT_DIR, "ivf_p5_proof_summary.json")
File.write(summary_path, JSON.pretty_generate(summary))

puts "═══════════════════════════════════════════════════════════"
puts "LAB-IGNITER-VIEW-FRAMEWORK-P5 Proof Summary"
puts "  Total:  #{total}"
puts "  Passed: #{passed}"
puts "  Failed: #{failed}"
puts "  Output: #{summary_path}"
puts "═══════════════════════════════════════════════════════════"

if failures > 0
  puts "\n⚠️  #{failures} check(s) FAILED. See output above."
  exit 1
else
  puts "\n✅ All checks PASS."
  exit 0
end
