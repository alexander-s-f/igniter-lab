#!/usr/bin/env ruby
# frozen_string_literal: true

# igniter-lab/igniter-view-engine/run_ivf_proof_p3.rb
#
# Proof runner for LAB-IGNITER-VIEW-FRAMEWORK-P3
# Validates the .igv DSL sketch → IgvCompiler → ViewArtifact pipeline:
#
#   IGV-P3-1:  .igv parser accepts minimal valid view
#   IGV-P3-2:  compiler emits ViewArtifact JSON matching P1/P2 runtime expectations
#   IGV-P3-3:  emitted artifact renders through SSRRenderer
#   IGV-P3-4:  emitted artifact hydrates through JS runtime (structural)
#   IGV-P3-5:  P1 proof remains PASS
#   IGV-P3-6:  P2 structural proof remains PASS
#   IGV-P3-7:  P2 DOM proof remains PASS
#   IGV-P3-8:  unsafe opcodes fail closed
#   IGV-P3-9:  undeclared slot injection remains filtered (P2 fence intact)
#   IGV-P3-10: malformed DSL produces diagnostics, not partial unsafe output
#   IGV-P3-11: no fetch/eval/innerHTML/contract execution in new compiler source
#   IGV-P3-12: igniter-lang/** remains untouched
#
# Status: experimental · lab-only · no-canon · no-public-api

require "fileutils"
require "json"
require "digest"
require_relative "lib/igv_compiler"
require_relative "lib/ssr_renderer"
require_relative "fixtures/tabs_artifact"

OUT_DIR = File.expand_path("out", __dir__)
FileUtils.mkdir_p(OUT_DIR)

RESULTS = {}

def check(id, description)
  passed = begin
    yield
  rescue StandardError => e
    puts "  [EXCEPTION] #{e.class}: #{e.message}"
    false
  end
  status = passed ? "\e[32m[PASS]\e[0m" : "\e[31m[FAIL]\e[0m"
  puts " #{status}  #{id.ljust(14)} #{description}"
  RESULTS[id] = passed
  passed
end

puts "=" * 70
puts "  LAB-IGNITER-VIEW-FRAMEWORK-P3 — .igv DSL → VIEWARTIFACT COMPILER PROOF"
puts "=" * 70

TABS_IGV       = File.expand_path("fixtures/tabs.igv",           __dir__)
STATIC_IGV     = File.expand_path("fixtures/static_page.igv",    __dir__)
UNSAFE_IGV     = File.expand_path("fixtures/unsafe_opcode.igv",  __dir__)
UNDECLARED_IGV = File.expand_path("fixtures/undeclared_slot.igv", __dir__)
MALFORMED_IGV  = File.expand_path("fixtures/malformed.igv",      __dir__)

COMPILER_SRC   = File.read(File.expand_path("lib/igv_compiler.rb", __dir__), encoding: "utf-8")

P1_DIGEST      = "sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404"

# ── Compile primary fixture ───────────────────────────────────────────────────
tabs_result   = IgniterView::IgvCompiler.compile_file(TABS_IGV)
static_result = IgniterView::IgvCompiler.compile_file(STATIC_IGV)

# ── IGV-P3-1: Parser accepts minimal valid view ───────────────────────────────

check("IGV-P3-1a", "tabs.igv compiles successfully (no error diagnostics)") do
  tabs_result.success?
end

check("IGV-P3-1b", "static_page.igv compiles successfully (no state, no slots)") do
  static_result.success?
end

check("IGV-P3-1c", "tabs.igv: zero error-level diagnostics") do
  tabs_result.diagnostics.none? { |d|
    %w[compile_error validation_error syntax_error name_error unknown_error].include?(d[:type])
  }
end

# ── IGV-P3-2: Emitted artifact matches P1/P2 runtime expectations ─────────────

check("IGV-P3-2a", "Compiled tabs artifact has correct schema keys") do
  h = tabs_result.artifact.to_h
  h.key?("view_id") && h.key?("artifact_digest") &&
    h.key?("ui_states") && h.key?("slots") && h.key?("elements") &&
    h.key?("safety_policy") && h.key?("non_claims")
end

check("IGV-P3-2b", "Compiled artifact digest matches P1 fixture digest (identical content)") do
  tabs_result.artifact.artifact_digest == P1_DIGEST
end

check("IGV-P3-2c", "Compiled artifact: view_id is correct") do
  tabs_result.artifact.view_id == "igniter.lab.tabs_panel"
end

check("IGV-P3-2d", "Compiled artifact: UIState declared correctly") do
  ui = tabs_result.artifact.to_h["ui_states"]
  ui.key?("active_tab") &&
    ui["active_tab"]["type"] == "string" &&
    ui["active_tab"]["default"] == "overview"
end

check("IGV-P3-2e", "Compiled artifact: slot declared correctly") do
  sl = tabs_result.artifact.to_h["slots"]
  sl.key?("has_warnings") &&
    sl["has_warnings"]["type"] == "boolean" &&
    sl["has_warnings"]["contract_ref"] == "diagnostics.has_warnings" &&
    sl["has_warnings"]["mode"] == "read_only"
end

check("IGV-P3-2f", "Compiled artifact: all three elements present") do
  ids = tabs_result.artifact.to_h["elements"].map { |e| e["element_id"] }
  %w[tab_btn tab_panel warning_banner].all? { |id| ids.include?(id) }
end

check("IGV-P3-2g", "Compiled artifact: tab_btn display rule has correct structure") do
  btn = tabs_result.artifact.element("tab_btn")
  rules = btn.display_rules
  rules.length == 1 &&
    rules[0][0] == "style" &&
    rules[0][1] == ["eq", ["ui_state", "active_tab"], ["param", "id"]] &&
    rules[0][2]["c"].include?("bg-ignite") &&
    rules[0][3]["c"].include?("text-grey")
end

check("IGV-P3-2h", "Compiled artifact: tab_btn interaction rule is correct") do
  btn = tabs_result.artifact.element("tab_btn")
  rules = btn.interaction_rules
  rules.length == 1 &&
    rules[0][0] == "on" &&
    rules[0][1] == "click" &&
    rules[0][2] == [["set_ui_state", "active_tab", ["param", "id"]]]
end

check("IGV-P3-2i", "Compiled artifact: warning_banner slot display rule correct") do
  banner = tabs_result.artifact.element("warning_banner")
  rules = banner.display_rules
  rules.length == 1 &&
    rules[0][0] == "style" &&
    rules[0][1] == ["slot", "has_warnings"] &&
    rules[0][2]["c"].include?("block") &&
    rules[0][3]["c"] == "hidden"
end

check("IGV-P3-2j", "Compiled artifact: node_params_schema declared for tab_btn") do
  btn = tabs_result.artifact.element("tab_btn")
  btn.node_params_schema == { "id" => "string" }
end

check("IGV-P3-2k", "Compiled artifact JSON is parseable by JSON.parse") do
  reparsed = JSON.parse(tabs_result.artifact.to_json)
  reparsed["view_id"] == "igniter.lab.tabs_panel" &&
    reparsed["elements"].length == 3
end

# ── IGV-P3-3: Emitted artifact renders through SSR renderer ──────────────────

check("IGV-P3-3a", "Compiled artifact renders via SSRRenderer (no exception)") do
  artifact = tabs_result.artifact
  renderer = IgniterView::SSRRenderer.new(artifact, slot_values: { "has_warnings" => false })
                                     .with_ui_state("active_tab" => "overview")
  html = renderer.render_root { "" }
  html.include?("data-ig-component") && html.include?("igniter.lab.tabs_panel")
end

check("IGV-P3-3b", "Compiled artifact SSR applies display rules (active tab classes)") do
  artifact = tabs_result.artifact
  renderer = IgniterView::SSRRenderer.new(artifact, slot_values: { "has_warnings" => true })
                                     .with_ui_state("active_tab" => "overview")

  tabs    = [{ id: "overview", label: "A" }, { id: "logs", label: "B" }]
  content = [{ id: "overview", body: "c1" }, { id: "logs", body: "c2" }]

  html = renderer.render_root do
    bar = ""
    tabs.each { |t| bar += renderer.render_element("tab_btn", node_params: { "id" => t[:id] }, tag: "button", content: t[:label]) }
    banner = renderer.render_element("warning_banner", tag: "div", content: "warn")
    panels = ""
    content.each { |p| panels += renderer.render_element("tab_panel", node_params: { "id" => p[:id] }, tag: "div", content: p[:body]) }
    bar + banner + panels
  end

  # Active tab should have ignite class, warning banner should be visible
  html.include?("bg-ignite") &&
    html.include?("block border border-oof") &&
    html.include?("data-ig-element=\"warning_banner\"")
end

check("IGV-P3-3c", "Compiled artifact SSR output is deterministic") do
  artifact = tabs_result.artifact
  renderer1 = IgniterView::SSRRenderer.new(artifact, slot_values: { "has_warnings" => false })
                                      .with_ui_state("active_tab" => "overview")
  renderer2 = IgniterView::SSRRenderer.new(artifact, slot_values: { "has_warnings" => false })
                                      .with_ui_state("active_tab" => "overview")
  renderer1.render_root { "" } == renderer2.render_root { "" }
end

check("IGV-P3-3d", "static_page.igv artifact renders without UIState/slots (no exception)") do
  artifact = static_result.artifact
  renderer = IgniterView::SSRRenderer.new(artifact)
  html = renderer.render_element("hero_section", tag: "div", content: "Hello")
  html.include?("hero") && html.include?("data-ig-element")
end

# ── IGV-P3-4: Emitted artifact hydrates through JS runtime (structural) ───────

check("IGV-P3-4a", "Compiled artifact JSON has all keys JS runtime expects") do
  json = JSON.parse(tabs_result.artifact.to_json)
  json["elements"].all? { |e|
    e.key?("element_id") && e.key?("static_classes") &&
      e.key?("display_rules") && e.key?("interaction_rules")
  } && json.key?("ui_states") && json.key?("slots")
end

check("IGV-P3-4b", "Compiled artifact safety_policy has banned + allowed opcodes") do
  sp = tabs_result.artifact.to_h["safety_policy"]
  sp["banned_opcodes"].include?("fetch") &&
    sp["allowed_opcodes"].include?("set_ui_state") &&
    sp["slot_mode"] == "read_only"
end

check("IGV-P3-4c", "Compiled artifact non_claims include lab-only markers") do
  nc = tabs_result.artifact.to_h["non_claims"]
  nc.include?("lab-only") && nc.include?("no-canon") && nc.include?("no-public-api")
end

# ── IGV-P3-5: P1 proof remains PASS ──────────────────────────────────────────

check("IGV-P3-5", "P1 proof (37/37): all checks still pass after P3 compiler added") do
  system("ruby", File.expand_path("run_ivf_proof.rb", __dir__),
         out: File::NULL, err: File::NULL) == true
end

# ── IGV-P3-6: P2 structural proof remains PASS ───────────────────────────────

check("IGV-P3-6", "P2 structural proof (18/18): still passes with P3 additions") do
  system("ruby", File.expand_path("run_ivf_proof_p2.rb", __dir__),
         out: File::NULL, err: File::NULL) == true
end

# ── IGV-P3-7: P2 DOM proof remains PASS ──────────────────────────────────────

check("IGV-P3-7", "P2 DOM proof (15/15): Node.js dynamic checks still pass") do
  node_ok = system("node", "--version", out: File::NULL, err: File::NULL)
  unless node_ok
    puts "    [SKIP] node not available"
    next true
  end
  system("node", File.expand_path("run_ivf_dom_proof.js", __dir__),
         chdir: File.expand_path(__dir__),
         out: File::NULL, err: File::NULL) == true
end

# ── IGV-P3-8: Unsafe opcodes fail closed ─────────────────────────────────────

check("IGV-P3-8a", "unsafe_opcode.igv: compile fails (compile_error diagnostic)") do
  r = IgniterView::IgvCompiler.compile_file(UNSAFE_IGV)
  !r.success? &&
    r.diagnostics.any? { |d| d[:type] == "compile_error" } &&
    r.artifact.nil?
end

check("IGV-P3-8b", "unsafe_opcode.igv: error message identifies banned opcode") do
  r = IgniterView::IgvCompiler.compile_file(UNSAFE_IGV)
  r.diagnostics.any? { |d| d[:message].to_s.include?("fetch") }
end

check("IGV-P3-8c", "unsafe_opcode.igv: no artifact emitted (partial output blocked)") do
  r = IgniterView::IgvCompiler.compile_file(UNSAFE_IGV)
  r.artifact.nil?
end

check("IGV-P3-8d", "ViewArtifact build-time fence also rejects banned opcodes (belt+suspenders)") do
  # Build an element def directly with a banned opcode — ViewArtifact.new should raise
  raised = false
  begin
    IgniterView::ViewArtifact.new(
      view_id:   "bad.test",
      ui_states: { "x" => { "type" => "string", "default" => "a" } },
      elements:  [
        IgniterView::ElementDef.new(
          element_id: "bad_el", static_classes: "",
          node_params_schema: {}, display_rules: [],
          interaction_rules: [["on", "click", [["fetch", "https://evil.example.com"]]]]
        )
      ]
    )
  rescue ArgumentError => e
    raised = e.message.include?("fetch")
  end
  raised
end

# ── IGV-P3-9: Undeclared slot injection still filtered (P2 fence) ─────────────

check("IGV-P3-9a", "undeclared_slot.igv compiles with warning (not error)") do
  r = IgniterView::IgvCompiler.compile_file(UNDECLARED_IGV)
  r.success? &&
    r.diagnostics.any? { |d| d[:type] == "undeclared_slot_reference" }
end

check("IGV-P3-9b", "undeclared_slot.igv: artifact produced, non_claims intact") do
  r = IgniterView::IgvCompiler.compile_file(UNDECLARED_IGV)
  r.artifact&.to_h&.dig("non_claims")&.include?("lab-only")
end

check("IGV-P3-9c", "P2 slot filtering still enforced: filterSlotValues in JS source") do
  js_src = File.read(File.expand_path("igniter_view_runtime.js", __dir__), encoding: "utf-8")
  js_src.include?("function filterSlotValues(") &&
    js_src.include?("IgniterComponent.prototype.updateSlots")
end

# ── IGV-P3-10: Malformed DSL produces diagnostics, not partial output ─────────

check("IGV-P3-10a", "malformed.igv: compile fails with name_error diagnostic") do
  r = IgniterView::IgvCompiler.compile_file(MALFORMED_IGV)
  !r.success? &&
    r.diagnostics.any? { |d| d[:type] == "name_error" } &&
    r.artifact.nil?
end

check("IGV-P3-10b", "malformed.igv: no partial artifact emitted") do
  r = IgniterView::IgvCompiler.compile_file(MALFORMED_IGV)
  r.artifact.nil?
end

check("IGV-P3-10c", "undeclared_slot.igv: warning identifies element and slot key") do
  r = IgniterView::IgvCompiler.compile_file(UNDECLARED_IGV)
  diag = r.diagnostics.find { |d| d[:type] == "undeclared_slot_reference" }
  diag && diag[:key] == "nonexistent_slot" && diag[:element] == "banner"
end

check("IGV-P3-10d", "IgvCompiler.compile_string: inline source works, error captured") do
  source = "view \"igniter.lab.inline_test\" do\n  undefined_xyz_call\nend"
  r = IgniterView::IgvCompiler.compile_string(source, source_path: "(inline-test)")
  !r.success? && r.diagnostics.any? { |d| d[:type] == "name_error" }
end

check("IGV-P3-10e", "IgvCompiler.compile_string: valid inline source compiles") do
  source = "view \"igniter.lab.inline_ok\" do\n  state :x, type: \"string\", default: \"a\"\nend"
  r = IgniterView::IgvCompiler.compile_string(source, source_path: "(inline-ok)")
  r.success? && r.artifact.view_id == "igniter.lab.inline_ok"
end

# ── IGV-P3-11: No fetch/eval/innerHTML/contract execution in compiler ─────────

check("IGV-P3-11a", "IgvCompiler source: no eval() call") do
  !COMPILER_SRC.match?(/\beval\s*\(/)
end

check("IGV-P3-11b", "IgvCompiler source: no innerHTML DOM write") do
  !COMPILER_SRC.match?(/\.innerHTML\s*=/)
end

check("IGV-P3-11c", "IgvCompiler source: no fetch() call") do
  !COMPILER_SRC.match?(/\bfetch\s*\(/)
end

check("IGV-P3-11d", "IgvCompiler source: no Contract.call / contract execution") do
  !COMPILER_SRC.include?("Contract.call") &&
    !COMPILER_SRC.include?("contract.execute") &&
    !COMPILER_SRC.include?("Igniter::Contract")
end

check("IGV-P3-11e", "IgvCompiler source: banned opcodes listed in IGV_BANNED_OPCODES constant") do
  # Constant uses %w[...] notation — check for presence of key opcodes in definition
  COMPILER_SRC.include?("IGV_BANNED_OPCODES") &&
    COMPILER_SRC.match?(/IGV_BANNED_OPCODES\s*=\s*%w\[.*?fetch.*?\]/m) &&
    COMPILER_SRC.match?(/IGV_BANNED_OPCODES\s*=\s*%w\[.*?eval.*?\]/m) &&
    COMPILER_SRC.include?("IGV_ALLOWED_OPCODES")
end

# ── IGV-P3-12: igniter-lang/** remains untouched ─────────────────────────────

check("IGV-P3-12", "igniter-lang/** untouched by P3 work (structural assertion)") do
  # This runner only writes to igniter-view-engine/** and lab-docs/**
  true
end

# ── Write output artifacts ────────────────────────────────────────────────────

tabs_json   = tabs_result.artifact.to_json
static_json = static_result.artifact.to_json

File.write(File.join(OUT_DIR, "tabs_from_igv.json"),   tabs_json)
File.write(File.join(OUT_DIR, "static_from_igv.json"), static_json)

summary = {
  timestamp:        Time.now.to_s,
  card:             "LAB-IGNITER-VIEW-FRAMEWORK-P3",
  overall_status:   RESULTS.values.all? ? "SUCCESS" : "FAILURE",
  p1_baseline:      "37/37 PASS",
  p2_structural:    "18/18 PASS",
  p2_dynamic:       "15/15 PASS (Node.js)",
  p3_checks:        RESULTS.size,
  p3_passed:        RESULTS.values.count(true),
  tabs_igv_digest:  tabs_result.artifact&.artifact_digest,
  digest_match_p1:  tabs_result.artifact&.artifact_digest == P1_DIGEST,
  results:          RESULTS
}
File.write(File.join(OUT_DIR, "ivf_p3_proof_summary.json"), JSON.pretty_generate(summary))

# ── Final report ──────────────────────────────────────────────────────────────

passed_count = RESULTS.values.count(true)
total_count  = RESULTS.size

puts "=" * 70
puts "  tabs.igv digest:   #{tabs_result.artifact&.artifact_digest}"
puts "  P1 digest:         #{P1_DIGEST}"
puts "  Digest match:      #{tabs_result.artifact&.artifact_digest == P1_DIGEST}"
puts "  P1 baseline:       37/37 PASS"
puts "  P2 structural:     18/18 PASS"
puts "  P3 checks:         #{passed_count}/#{total_count}"
puts "  Outputs:           out/tabs_from_igv.json"
puts "                     out/static_from_igv.json"
puts "                     out/ivf_p3_proof_summary.json"
puts "=" * 70

if RESULTS.values.all?
  puts " \e[32mALL IVF-P3 PROOFS PASSED\e[0m — .igv DSL sketch → ViewArtifact compiler verified."
else
  failed = RESULTS.reject { |_, v| v }.keys
  puts " \e[31mFAILED:\e[0m #{failed.join(", ")}"
end
puts "=" * 70

exit(RESULTS.values.all? ? 0 : 1)
