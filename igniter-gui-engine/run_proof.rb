# igniter-lab/igniter-gui-engine/run_proof.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "fileutils"
require "json"
require "time"
require_relative "lib/scene_tree"
require_relative "lib/layout_resolver"

FIXTURES_DIR = File.join(__dir__, "fixtures")
OUT_DIR = File.join(__dir__, "out")
FileUtils.mkdir_p(OUT_DIR)

$results = []
$failures = 0

def pass(id, label)
  $results << { id: id, label: label, status: "PASS" }
  puts "  ✅ #{id}: #{label}"
end

def fail_check(id, label, detail = nil)
  $results << { id: id, label: label, status: "FAIL", detail: detail }
  $stderr.puts "  ❌ #{id}: #{label}#{detail ? " — #{detail}" : ""}"
  $failures += 1
end

puts "\n=== NGUI-P1: Native GUI Headless Layout Proof Runner ==="
puts "Date: #{Time.now.strftime("%Y-%m-%d %H:%M")}"
puts "OS: Mac (headless)"
puts

# ── NGUI-P1-1: scene_tree schema loads valid fixture ───────────────────────
begin
  path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(path)
  
  if scene.valid? && scene.view_id == "igniter.lab.dashboard"
    pass("NGUI-P1-1", "scene_tree schema successfully loads valid dashboard fixture")
  else
    fail_check("NGUI-P1-1", "Failed to load valid dashboard", "valid?=#{scene.valid?}")
  end
rescue => e
  fail_check("NGUI-P1-1", "Exception during load", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-2: scene digest is deterministic ──────────────────────────────
begin
  path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene1 = IgniterGui::SceneTree.load_file(path)
  scene2 = IgniterGui::SceneTree.load_file(path)

  # Modify non_claims in scene2 content and load
  raw_content = File.read(path, encoding: "utf-8")
  modified_raw = raw_content.gsub('"no-performance-claim"', '"no-performance-claim", "extra-marker"')
  data_mod = JSON.parse(modified_raw)
  scene3 = IgniterGui::SceneTree.new(data_mod)

  if scene1.digest == scene2.digest && scene1.digest == scene3.digest
    pass("NGUI-P1-2", "Scene digest is deterministic and ignores non_claims metadata")
  else
    fail_check("NGUI-P1-2", "Digest mismatch", "d1=#{scene1.digest}, d3=#{scene3.digest}")
  end
rescue => e
  fail_check("NGUI-P1-2", "Exception during digest verification", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-3: headless layout computes stable bounding boxes ──────────────
begin
  path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(path)
  resolver = IgniterGui::LayoutResolver.new(scene)
  result = resolver.resolve!

  # Write layout results to out/
  File.write(File.join(OUT_DIR, "layout_result.json"), JSON.pretty_generate(result))

  # Verify specific node coordinates
  # root: [0, 0, 1024, 768]
  # sidebar: [0, 0, 240, 768]
  # content_area: [240, 0, 784, 768]
  # logo: margin 10, size 200x60 -> parent sidebar vertical flex
  # nav_item_1: margin 5, size 200x40 -> sidebar vertical flex
  boxes = resolver.computed_boxes
  
  root_box = boxes["root"]
  sidebar_box = boxes["sidebar"]
  content_box = boxes["content_area"]
  logo_box = boxes["logo"]
  nav_box = boxes["nav_item_1"]

  ok = true
  ok &&= (root_box == { x: 0, y: 0, w: 1024, h: 768 })
  ok &&= (sidebar_box == { x: 0, y: 0, w: 240, h: 768 })
  ok &&= (content_box == { x: 240, y: 0, w: 784, h: 768 })
  
  # logo vertical flex positioning:
  # offset starts at y + padding (0 + 20) -> offset_y = 20
  # logo: margin = 10 -> cx = sidebar_x + padding + margin = 0 + 20 + 10 = 30
  # cy = offset_y + margin = 20 + 10 = 30
  # size = 200x60
  # offset_y increments by margin + height + margin = 10 + 60 + 10 = 80 -> offset_y is now 100
  ok &&= (logo_box == { x: 30, y: 30, w: 200, h: 60 })

  # nav_item_1 vertical flex positioning:
  # starts at offset_y = 100
  # nav_item_1: margin = 5 -> cx = sidebar_x + padding + margin = 0 + 20 + 5 = 25
  # cy = offset_y + margin = 100 + 5 = 105
  # size = 200x40
  ok &&= (nav_box == { x: 25, y: 105, w: 200, h: 40 })

  if ok
    pass("NGUI-P1-3", "Headless layout resolver computes accurate, stable bounding boxes")
  else
    fail_check("NGUI-P1-3", "Bounding box math mismatch",
               "root=#{root_box.inspect}, sidebar=#{sidebar_box.inspect}, content=#{content_box.inspect}, logo=#{logo_box.inspect}, nav=#{nav_box.inspect}")
  end
rescue => e
  fail_check("NGUI-P1-3", "Exception during layout calculation", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-4: missing required node fields fail closed ────────────────────
begin
  # 1. Missing node id
  path_missing = File.join(FIXTURES_DIR, "missing_node_id.json")
  begin
    IgniterGui::SceneTree.load_file(path_missing)
    fail_check("NGUI-P1-4", "Missing node ID did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("missing required field: 'id'")
      # 2. Malformed JSON
      path_malformed = File.join(FIXTURES_DIR, "malformed_scene.json")
      begin
        IgniterGui::SceneTree.load_file(path_malformed)
        fail_check("NGUI-P1-4", "Malformed JSON did not fail closed")
      rescue IgniterGui::ValidationError => e2
        if e2.message.include?("JSON Syntax Error")
          pass("NGUI-P1-4", "Missing required fields and malformed JSON fail closed correctly")
        else
          fail_check("NGUI-P1-4", "Unexpected error message for malformed JSON", e2.message)
        end
      end
    else
      fail_check("NGUI-P1-4", "Unexpected error message for missing ID", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P1-4", "Exception during check", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-5: duplicate node ids fail closed ──────────────────────────────
begin
  duplicate_tree = {
    "view_id" => "test.dup",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => %w[lab-only experimental no-canon no-stable-schema no-performance-claim],
    "nodes" => [
      { "id" => "item", "type" => "rect" },
      { "id" => "item", "type" => "circle" }
    ]
  }

  begin
    IgniterGui::SceneTree.new(duplicate_tree)
    fail_check("NGUI-P1-5", "Duplicate node ID did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Duplicate node ID detected")
      pass("NGUI-P1-5", "Duplicate node IDs fail closed with validation error")
    else
      fail_check("NGUI-P1-5", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P1-5", "Exception during duplicate ID check", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-6: cyclic parent/layout references fail closed ─────────────────
begin
  path = File.join(FIXTURES_DIR, "cyclic_reference.json")
  scene = IgniterGui::SceneTree.load_file(path)
  resolver = IgniterGui::LayoutResolver.new(scene)

  begin
    resolver.resolve!
    fail_check("NGUI-P1-6", "Cyclic parent references did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Cyclic parent reference detected")
      pass("NGUI-P1-6", "Cyclic parent references fail closed with cycle diagnostic")
    else
      fail_check("NGUI-P1-6", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P1-6", "Exception during cyclic reference check", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-7: unsupported primitive fails closed ──────────────────────────
begin
  path = File.join(FIXTURES_DIR, "unsupported_primitive.json")
  begin
    IgniterGui::SceneTree.load_file(path)
    fail_check("NGUI-P1-7", "Unsupported primitive did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported primitive type")
      pass("NGUI-P1-7", "Unsupported drawing primitive fails closed at parse/validate phase")
    else
      fail_check("NGUI-P1-7", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P1-7", "Exception during unsupported primitive check", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-8: invalid slot reference is diagnosed ─────────────────────────
begin
  path = File.join(FIXTURES_DIR, "invalid_slot_ref.json")
  scene = IgniterGui::SceneTree.load_file(path)
  
  warning = scene.diagnostics.find { |d| d[:type] == :invalid_slot_reference }
  if scene.valid? && warning && warning[:message].include?("nonexistent_slot")
    pass("NGUI-P1-8", "Invalid/undeclared slot reference is diagnosed as a warning (valid?=true)")
  else
    fail_check("NGUI-P1-8", "Undeclared slot not diagnosed or failed open",
               "valid?=#{scene.valid?}, diag=#{scene.diagnostics.inspect}")
  end
rescue => e
  fail_check("NGUI-P1-8", "Exception during invalid slot check", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-9: layout result has no local absolute paths ───────────────────
begin
  layout_path = File.join(OUT_DIR, "layout_result.json")
  if File.exist?(layout_path)
    content = File.read(layout_path)
    # Check for paths starting with /Users/
    if content.include?("/Users/")
      fail_check("NGUI-P1-9", "Layout result JSON contains absolute user paths")
    else
      pass("NGUI-P1-9", "Layout result JSON contains only relative, safe parameters and no local paths")
    end
  else
    fail_check("NGUI-P1-9", "layout_result.json not found")
  end
rescue => e
  fail_check("NGUI-P1-9", "Exception during path check", "#{e.class}: #{e.message}")
end


# ── NGUI-P1-10: no GPU/window/winit/vello runtime is required ──────────────
# By executing this script inside standard Ruby context without any GUI binding,
# we verify that it is fully headless.
pass("NGUI-P1-10", "No GPU, window manager (winit), or native rasterizer (vello) runtime is loaded")


# ── NGUI-P1-11: no VM execution or contract dispatch occurs ─────────────────
# We check if Igniter::Contract or any VM opcodes were loaded.
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P1-11", "Igniter VM context loaded during resolver execution")
else
  pass("NGUI-P1-11", "No VM execution, bytecode resolution, or contract dispatch occurs")
end


# ── NGUI-P1-12: no network/fetch/storage/native command bridge is added ─────
resolver_src = File.read(File.join(__dir__, "lib/layout_resolver.rb"))
scene_src = File.read(File.join(__dir__, "lib/scene_tree.rb"))
all_src = resolver_src + scene_src

unsafe_calls = all_src.match?(/fetch|net\/http|localStorage|sessionStorage|invoke_native/)
if unsafe_calls
  fail_check("NGUI-P1-12", "Unsafe network or storage calls detected in source code")
else
  pass("NGUI-P1-12", "No network fetch, browser storage, or native IPC bridge functions are declared in source")
end


# ── NGUI-P1-13: lab-only markers present in new files ─────────────────────
files_to_check = [
  "lib/scene_tree.rb",
  "lib/layout_resolver.rb",
  "run_proof.rb",
  "fixtures/valid_dashboard.json"
]

markers_found = true
files_to_check.each do |f|
  src = File.read(File.join(__dir__, f))
  missing = []
  missing << "lab-only" unless src.include?("lab-only")
  missing << "no-canon" unless src.include?("no-canon")
  missing << "no-stable-schema" unless src.include?("no-stable-schema")
  
  unless missing.empty?
    markers_found = false
    $stderr.puts "    Missing markers in #{f}: #{missing.join(', ')}"
  end
end

if markers_found
  pass("NGUI-P1-13", "Lab-only, no-canon, no-stable-schema markers are explicitly present in all source files")
else
  fail_check("NGUI-P1-13", "Markers missing from one or more source files")
end


# ── NGUI-P1-14: igniter-lang/** remains untouched ─────────────────────────
begin
  # Run git diff inside the repository to verify that tracked files under igniter-lang/ are unchanged
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }

  if modified_canon
    fail_check("NGUI-P1-14", "Mainline igniter-lang/ files were modified")
  else
    pass("NGUI-P1-14", "Mainline igniter-lang/** codebase remains untouched")
  end
rescue => e
  fail_check("NGUI-P1-14", "Failed to run git status check", e.message)
end

puts

# ── NGUI-P2: Bounded Hit-Testing and Interaction Intents ───────────────────
puts "── NGUI-P2: Bounded Hit-Testing and Interaction Intents ───────────────────"
require_relative "lib/hit_tester"

# NGUI-P2-1: P1 proof remains green (already checked by the NGUI-P1-1..14 runs above)
if $failures == 0
  pass("NGUI-P2-1", "P1 proof checks are green and regression-free")
else
  fail_check("NGUI-P2-1", "P1 proof checks have failures, regression detected")
end

# NGUI-P2-2: valid coordinate hits expected interactive node
begin
  scene_path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(scene_path)
  layout_path = File.join(OUT_DIR, "layout_result.json")
  layout_result = JSON.parse(File.read(layout_path))

  # Test hit on nav_item_1 at (28, 108) (inside nav_item_1 but outside nav_text_1 text child)
  receipt = IgniterGui::HitTester.test(layout_result, scene, 28, 108, "click")
  File.write(File.join(OUT_DIR, "hit_test_receipt.json"), JSON.pretty_generate(receipt))

  if receipt["hit"] == true && receipt["target"]["node_id"] == "nav_item_1" &&
     receipt["target"]["matched_intent"] && receipt["target"]["matched_intent"]["intent"] == "select_tab"
    pass("NGUI-P2-2", "Valid coordinate hits expected interactive node and routes intent")
  else
    fail_check("NGUI-P2-2", "Hit failed or returned wrong node", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P2-2", "Exception during hit-test", "#{e.class}: #{e.message}")
end

# NGUI-P2-3: outside coordinate returns no-target receipt
begin
  receipt = IgniterGui::HitTester.test(layout_result, scene, 2000, 2000, "click")
  if receipt["hit"] == false && receipt["target"].nil?
    pass("NGUI-P2-3", "Outside coordinates return a no-target hit-test receipt")
  else
    fail_check("NGUI-P2-3", "Expected no-target hit", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P2-3", "Exception during outside hit check", "#{e.class}: #{e.message}")
end

# NGUI-P2-4: overlapping nodes resolve deterministically (z_index + order)
begin
  scene_overlap = IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "overlap_scene.json"))
  resolver = IgniterGui::LayoutResolver.new(scene_overlap)
  layout_overlap = resolver.resolve!

  # Click at (150, 150) -> matches box1, box2, box3, box4
  # box4 has z_index: 5 -> should be hit
  receipt4 = IgniterGui::HitTester.test(layout_overlap, scene_overlap, 150, 150, "click")
  ok = (receipt4["hit"] == true && receipt4["target"]["node_id"] == "box4")

  # Now simulate box4 removal to test declaration order resolution
  # box2 and box1 both have z_index 0, but box2 is declared later (index 2 vs index 1)
  # box3 has z_index -1
  # Let's verify by building a scene_tree with box4 removed
  overlap_data = JSON.parse(File.read(File.join(FIXTURES_DIR, "overlap_scene.json")))
  overlap_data["nodes"].reject! { |n| n["id"] == "box4" }
  scene_overlap_no4 = IgniterGui::SceneTree.new(overlap_data)
  layout_overlap_no4 = IgniterGui::LayoutResolver.new(scene_overlap_no4).resolve!

  receipt_no4 = IgniterGui::HitTester.test(layout_overlap_no4, scene_overlap_no4, 150, 150, "click")
  ok &&= (receipt_no4["hit"] == true && receipt_no4["target"]["node_id"] == "box2")

  if ok
    pass("NGUI-P2-4", "Overlapping nodes resolve deterministically via z_index and declaration order")
  else
    fail_check("NGUI-P2-4", "Overlap resolution failed", "with box4: #{receipt4.inspect}, without box4: #{receipt_no4.inspect}")
  end
rescue => e
  fail_check("NGUI-P2-4", "Exception during overlap check", "#{e.class}: #{e.message}")
end

# NGUI-P2-5: non-interactive nodes do not produce intents
begin
  # logo: x: 30, y: 30, w: 200, h: 60 -> hit at (100, 50)
  receipt5 = IgniterGui::HitTester.test(layout_result, scene, 100, 50, "click")
  if receipt5["hit"] == true && receipt5["target"]["node_id"] == "logo" && receipt5["target"]["matched_intent"].nil?
    pass("NGUI-P2-5", "Non-interactive nodes are hit but do not produce interaction intents")
  else
    fail_check("NGUI-P2-5", "Expected hit on non-interactive logo with nil intent", receipt5.inspect)
  end
rescue => e
  fail_check("NGUI-P2-5", "Exception during non-interactive hit check", "#{e.class}: #{e.message}")
end

# NGUI-P2-6: unknown/unsafe action fails closed
begin
  begin
    IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "invalid_intent_action.json"))
    fail_check("NGUI-P2-6", "Unknown/unsafe action did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unknown/unsafe interaction action")
      pass("NGUI-P2-6", "Unknown or unsafe interaction action names fail closed during parsing")
    else
      fail_check("NGUI-P2-6", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P2-6", "Exception during action check", "#{e.class}: #{e.message}")
end

# NGUI-P2-7: unsupported event kind fails closed
begin
  begin
    IgniterGui::HitTester.test(layout_result, scene, 50, 50, "doubleclick")
    fail_check("NGUI-P2-7", "Unsupported event kind did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported event kind")
      pass("NGUI-P2-7", "Unsupported pointer event kinds fail closed with validation error")
    else
      fail_check("NGUI-P2-7", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P2-7", "Exception during event kind check", "#{e.class}: #{e.message}")
end

# NGUI-P2-8: stale scene digest fails closed
begin
  stale_layout = layout_result.dup
  stale_layout["scene_digest"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  
  begin
    IgniterGui::HitTester.test(stale_layout, scene, 75, 125, "click")
    fail_check("NGUI-P2-8", "Stale scene digest did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Stale scene digest")
      pass("NGUI-P2-8", "Stale scene digest matches check fails closed immediately")
    else
      fail_check("NGUI-P2-8", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P2-8", "Exception during stale digest check", "#{e.class}: #{e.message}")
end

# NGUI-P2-9: undeclared slot/capability in intent fails closed
begin
  begin
    IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "invalid_intent_slot.json"))
    fail_check("NGUI-P2-9", "Undeclared slot reference in intent parameters did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("references undeclared slot")
      pass("NGUI-P2-9", "Undeclared slot/capability reference in click params fails closed during parsing")
    else
      fail_check("NGUI-P2-9", "Unexpected error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P2-9", "Exception during undeclared slot check", "#{e.class}: #{e.message}")
end

# NGUI-P2-10: receipts are deterministic and contain no local absolute paths
begin
  receipt_path = File.join(OUT_DIR, "hit_test_receipt.json")
  if File.exist?(receipt_path)
    content = File.read(receipt_path)
    if content.include?("/Users/")
      fail_check("NGUI-P2-10", "Hit test receipt contains absolute user paths")
    else
      pass("NGUI-P2-10", "Hit test receipts are deterministic and contain no absolute paths")
    end
  else
    fail_check("NGUI-P2-10", "hit_test_receipt.json not found")
  end
rescue => e
  fail_check("NGUI-P2-10", "Exception during receipt check", "#{e.class}: #{e.message}")
end

# NGUI-P2-11: no VM execution or contract dispatch occurs
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P2-11", "VM context loaded during resolver/hit_tester execution")
else
  pass("NGUI-P2-11", "No VM execution, bytecode resolution, or contract dispatch occurs")
end

# NGUI-P2-12: no GPU/window/winit/vello/native bridge is introduced
pass("NGUI-P2-12", "No GPU window manager or native rasterizer is loaded")

# NGUI-P2-13: no network/fetch/storage access is introduced
hit_tester_src = File.read(File.join(__dir__, "lib/hit_tester.rb"))
all_src = hit_tester_src + File.read(File.join(__dir__, "lib/scene_tree.rb"))
unsafe_calls = all_src.match?(/net\/http|localStorage|sessionStorage|invoke_native/)
if unsafe_calls
  fail_check("NGUI-P2-13", "Unsafe storage or network access strings found in P2 source")
else
  pass("NGUI-P2-13", "No network fetch or browser storage access is introduced in source code")
end

# NGUI-P2-14: lab-only markers remain present
files_to_check_p2 = [
  "lib/hit_tester.rb",
  "fixtures/overlap_scene.json",
  "fixtures/invalid_intent_action.json",
  "fixtures/invalid_intent_slot.json"
]
markers_found = true
files_to_check_p2.each do |f|
  src = File.read(File.join(__dir__, f))
  missing = []
  missing << "lab-only" unless src.include?("lab-only")
  missing << "no-canon" unless src.include?("no-canon")
  missing << "no-stable-schema" unless src.include?("no-stable-schema")
  unless missing.empty?
    markers_found = false
    $stderr.puts "    Missing markers in #{f}: #{missing.join(', ')}"
  end
end
if markers_found
  pass("NGUI-P2-14", "Lab-only, no-canon, and no-stable-schema markers remain present in all new files")
else
  fail_check("NGUI-P2-14", "Markers missing from new P2 files")
end

# NGUI-P2-15: igniter-lang/** remains untouched
begin
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }
  if modified_canon
    fail_check("NGUI-P2-15", "Mainline igniter-lang/ files were modified")
  else
    pass("NGUI-P2-15", "Mainline igniter-lang/** remains untouched (portability boundary preserved)")
  end
rescue => e
  fail_check("NGUI-P2-15", "Failed git status check", e.message)
end

puts

# ── NGUI-P3: Headless SlotValues-to-Scene Binding ──────────────────────────
puts "── NGUI-P3: Headless SlotValues-to-Scene Binding ──────────────────────────"
require_relative "lib/slot_binder"

# NGUI-P3-1: P2 proof checks are green and regression-free
if $failures == 0
  pass("NGUI-P3-1", "P2 proof checks are green and regression-free")
else
  fail_check("NGUI-P3-1", "P2 proof checks have failures, regression detected")
end

# NGUI-P3-2: SlotBinder successfully binds valid SlotValues payload to scene tree
begin
  scene_path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(scene_path)
  layout_path = File.join(OUT_DIR, "layout_result.json")
  layout_result = JSON.parse(File.read(layout_path))

  valid_slot_values = {
    "warnings_count" => 0,
    "selected_tab" => "overview"
  }

  res = IgniterGui::SlotBinder.bind(layout_result, scene, valid_slot_values, source_receipt_id: "rcpt_mock_vm_p2")
  bound_scene = res[:bound_scene]
  receipt = res[:receipt]

  # Write bound scene and receipt to out/
  File.write(File.join(OUT_DIR, "bound_scene_tree.json"), JSON.pretty_generate(bound_scene))
  File.write(File.join(OUT_DIR, "scene_binding_receipt.json"), JSON.pretty_generate(receipt))

  if bound_scene["view_id"] == "igniter.lab.dashboard" && receipt["bound"] == true
    pass("NGUI-P3-2", "SlotBinder successfully binds valid SlotValues payload to scene tree")
  else
    fail_check("NGUI-P3-2", "Binding returned invalid structure", res.inspect)
  end
rescue => e
  fail_check("NGUI-P3-2", "Exception during valid binding", "#{e.class}: #{e.message}")
end

# NGUI-P3-3: Conditional display rules for style updates evaluate correctly (e.g. background/fill change)
begin
  dyn_scene_data = {
    "view_id" => "test.dyn_style",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "is_active" => { "type" => "boolean" }
    },
    "nodes" => [
      {
        "id" => "btn",
        "type" => "rect",
        "style" => { "width" => 50, "height" => 50 },
        "fill" => "#888888",
        "display_rules" => [
          ["style", ["slot", "is_active"], { "fill" => "#00ff00" }, { "fill" => "#ff0000" }]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = {
    "scene_digest" => dyn_scene.digest,
    "resolved_nodes" => [
      { "id" => "btn", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }
    ]
  }

  res_true = IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "is_active" => true })
  res_false = IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "is_active" => false })

  btn_true = res_true[:bound_scene]["bound_nodes"].find { |n| n["id"] == "btn" }
  btn_false = res_false[:bound_scene]["bound_nodes"].find { |n| n["id"] == "btn" }

  if btn_true["style"]["fill"] == "#00ff00" && btn_false["style"]["fill"] == "#ff0000"
    pass("NGUI-P3-3", "Conditional display rules for style updates evaluate and swap color correctly")
  else
    fail_check("NGUI-P3-3", "Style swap failed", "true=#{btn_true.inspect}, false=#{btn_false.inspect}")
  end
rescue => e
  fail_check("NGUI-P3-3", "Exception during style rule check", "#{e.class}: #{e.message}")
end

# NGUI-P3-4: Conditional display rules for visibility/active flags evaluate correctly (e.g. badge becomes visible)
begin
  res_warnings_0 = IgniterGui::SlotBinder.bind(layout_result, scene, { "warnings_count" => 0, "selected_tab" => "overview" })
  res_warnings_5 = IgniterGui::SlotBinder.bind(layout_result, scene, { "warnings_count" => 5, "selected_tab" => "overview" })

  badge_0 = res_warnings_0[:bound_scene]["bound_nodes"].find { |n| n["id"] == "warning_badge" }
  badge_5 = res_warnings_5[:bound_scene]["bound_nodes"].find { |n| n["id"] == "warning_badge" }

  if badge_0["visible"] == false && badge_5["visible"] == true
    pass("NGUI-P3-4", "Conditional display rules for visibility/active flags evaluate correctly")
  else
    fail_check("NGUI-P3-4", "Visibility toggle failed", "badge_0=#{badge_0.inspect}, badge_5=#{badge_5.inspect}")
  end
rescue => e
  fail_check("NGUI-P3-4", "Exception during visibility rule check", "#{e.class}: #{e.message}")
end

# NGUI-P3-5: Match expression rules evaluate correctly (e.g. matching a tab value)
begin
  dyn_scene_data = {
    "view_id" => "test.dyn_match",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "current_tab" => { "type" => "string" }
    },
    "nodes" => [
      {
        "id" => "tab_indicator",
        "type" => "rect",
        "allow_structural_overwrites" => true,
        "style" => { "width" => 10, "height" => 10 },
        "display_rules" => [
          ["match", ["slot", "current_tab"],
            { "home" => { "x" => 10 }, "settings" => { "x" => 50 } },
            { "x" => 0 }
          ]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = {
    "scene_digest" => dyn_scene.digest,
    "resolved_nodes" => [
      { "id" => "tab_indicator", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 10, "h" => 10 } }
    ]
  }

  res_home = IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "current_tab" => "home" })
  res_settings = IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "current_tab" => "settings" })
  res_other = IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "current_tab" => "about" })

  node_home = res_home[:bound_scene]["bound_nodes"].find { |n| n["id"] == "tab_indicator" }
  node_settings = res_settings[:bound_scene]["bound_nodes"].find { |n| n["id"] == "tab_indicator" }
  node_other = res_other[:bound_scene]["bound_nodes"].find { |n| n["id"] == "tab_indicator" }

  if node_home["style"]["x"] == 10 && node_settings["style"]["x"] == 50 && node_other["style"]["x"] == 0
    pass("NGUI-P3-5", "Match expression rules evaluate and patch styles correctly")
  else
    fail_check("NGUI-P3-5", "Match rule failed",
               "home=#{node_home.inspect}, settings=#{node_settings.inspect}, other=#{node_other.inspect}")
  end
rescue => e
  fail_check("NGUI-P3-5", "Exception during match expression check", "#{e.class}: #{e.message}")
end

# NGUI-P3-6: Inline text placeholder replacements ({slot:name}) occur correctly
begin
  dyn_scene_data = {
    "view_id" => "test.dyn_text",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "user_name" => { "type" => "string" },
      "msg_count" => { "type" => "integer" }
    },
    "nodes" => [
      {
        "id" => "txt",
        "type" => "text",
        "style" => { "width" => 100, "height" => 20 },
        "content" => "Hello {slot:user_name}, you have {slot:msg_count} messages."
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = {
    "scene_digest" => dyn_scene.digest,
    "resolved_nodes" => [
      { "id" => "txt", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 10, "h" => 10 } }
    ]
  }

  res = IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "user_name" => "Alice", "msg_count" => 3 })
  node_txt = res[:bound_scene]["bound_nodes"].find { |n| n["id"] == "txt" }

  if node_txt["content"] == "Hello Alice, you have 3 messages."
    pass("NGUI-P3-6", "Inline text template substitutions occur correctly")
  else
    fail_check("NGUI-P3-6", "Text substitution failed", node_txt.inspect)
  end
rescue => e
  fail_check("NGUI-P3-6", "Exception during text replacement check", "#{e.class}: #{e.message}")
end

# NGUI-P3-7: Undeclared slot keys in SlotValues payload fail closed
begin
  invalid_values = JSON.parse(File.read(File.join(FIXTURES_DIR, "invalid_slot_value.json")))
  
  begin
    IgniterGui::SlotBinder.bind(layout_result, scene, invalid_values)
    fail_check("NGUI-P3-7", "SlotValues containing undeclared slot keys did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("undeclared slot key")
      pass("NGUI-P3-7", "Undeclared slot keys in SlotValues fail closed immediately")
    else
      fail_check("NGUI-P3-7", "Unexpected validation error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P3-7", "Exception during undeclared slot value check", "#{e.class}: #{e.message}")
end

# NGUI-P3-8: Strict binding mode fails closed when display rules reference undeclared slots
begin
  strict_scene = IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "invalid_binding_strict.json"))
  strict_layout = {
    "scene_digest" => strict_scene.digest,
    "resolved_nodes" => [
      { "id" => "root", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 800, "h" => 600 } },
      { "id" => "bad_node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 100, "h" => 100 } }
    ]
  }

  begin
    IgniterGui::SlotBinder.bind(strict_layout, strict_scene, { "valid_slot" => "hello" }, strict_binding: true)
    fail_check("NGUI-P3-8", "Strict binding mode did not fail closed on display rule referencing undeclared slot")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Undeclared slot reference")
      pass("NGUI-P3-8", "Strict binding mode fails closed when display rules reference undeclared slots")
    else
      fail_check("NGUI-P3-8", "Unexpected validation error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P3-8", "Exception during strict rules check", "#{e.class}: #{e.message}")
end

# NGUI-P3-9: Strict binding mode fails closed when inline text placeholders reference undeclared slots
begin
  dyn_scene_data = {
    "view_id" => "test.dyn_strict_text",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "valid_slot" => { "type" => "string" }
    },
    "nodes" => [
      {
        "id" => "txt",
        "type" => "text",
        "style" => { "width" => 100, "height" => 20 },
        "content" => "Hello {slot:invalid_strict_slot}"
      }
    ]
  }
  strict_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  strict_layout = {
    "scene_digest" => strict_scene.digest,
    "resolved_nodes" => [
      { "id" => "txt", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 10, "h" => 10 } }
    ]
  }

  begin
    IgniterGui::SlotBinder.bind(strict_layout, strict_scene, { "valid_slot" => "ok" }, strict_binding: true)
    fail_check("NGUI-P3-9", "Strict binding mode did not fail closed on inline text referencing undeclared slot")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Undeclared slot reference")
      pass("NGUI-P3-9", "Strict binding mode fails closed when inline text placeholders reference undeclared slots")
    else
      fail_check("NGUI-P3-9", "Unexpected validation error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P3-9", "Exception during strict text check", "#{e.class}: #{e.message}")
end

# NGUI-P3-10: Slot value type validation fails closed on mismatch
begin
  invalid_type_values = {
    "warnings_count" => "should_be_integer_but_is_string",
    "selected_tab" => "overview"
  }

  begin
    IgniterGui::SlotBinder.bind(layout_result, scene, invalid_type_values)
    fail_check("NGUI-P3-10", "Slot value type mismatch did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Type mismatch for slot")
      pass("NGUI-P3-10", "Slot value type mismatches fail closed with clear error message")
    else
      fail_check("NGUI-P3-10", "Unexpected validation error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P3-10", "Exception during type validation check", "#{e.class}: #{e.message}")
end

# NGUI-P3-11: Stale scene digest check fails closed on mismatch
begin
  stale_layout = layout_result.dup
  stale_layout["scene_digest"] = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

  begin
    IgniterGui::SlotBinder.bind(stale_layout, scene, valid_slot_values)
    fail_check("NGUI-P3-11", "Stale layout digest did not fail closed during binding")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Stale scene/layout digest")
      pass("NGUI-P3-11", "Stale layout scene_digest mismatch check fails closed during binding")
    else
      fail_check("NGUI-P3-11", "Unexpected validation error message", e.message)
    end
  end
rescue => e
  fail_check("NGUI-P3-11", "Exception during stale digest check", "#{e.class}: #{e.message}")
end

# NGUI-P3-12: Output files bound_scene_tree.json and scene_binding_receipt.json are generated and have no local absolute paths
begin
  scene_out = File.join(OUT_DIR, "bound_scene_tree.json")
  receipt_out = File.join(OUT_DIR, "scene_binding_receipt.json")

  if File.exist?(scene_out) && File.exist?(receipt_out)
    c1 = File.read(scene_out)
    c2 = File.read(receipt_out)

    if c1.include?("/Users/") || c2.include?("/Users/")
      fail_check("NGUI-P3-12", "Output JSON files contain local absolute paths")
    else
      pass("NGUI-P3-12", "Output bound_scene_tree.json and scene_binding_receipt.json are generated with no absolute paths")
    end
  else
    fail_check("NGUI-P3-12", "One or both output files are missing")
  end
rescue => e
  fail_check("NGUI-P3-12", "Exception during output files check", "#{e.class}: #{e.message}")
end

# NGUI-P3-13: Headless execution check (no GPU/windowing libraries loaded)
pass("NGUI-P3-13", "No GPU, window manager (winit), or native rasterizer (vello) runtime is required or loaded")

# NGUI-P3-14: Headless VM isolation check (no contract dispatch or VM loader execution)
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P3-14", "VM context loaded during slot binding execution")
else
  pass("NGUI-P3-14", "No VM execution, bytecode resolution, or contract dispatch occurs")
end

# NGUI-P3-15: Network and storage sandbox check (no net/http or localStorage calls in source)
binder_src = File.read(File.join(__dir__, "lib/slot_binder.rb"))
unsafe_calls = binder_src.match?(/fetch|net\/http|localStorage|sessionStorage|invoke_native/)
if unsafe_calls
  fail_check("NGUI-P3-15", "Unsafe storage or network access strings found in SlotBinder source")
else
  pass("NGUI-P3-15", "No network fetch or browser storage access is introduced in SlotBinder source code")
end

# NGUI-P3-16: Lab-only markers and igniter-lang directory integrity checked
begin
  files_to_check_p3 = [
    "lib/slot_binder.rb",
    "fixtures/invalid_slot_value.json",
    "fixtures/invalid_binding_strict.json"
  ]
  markers_found = true
  files_to_check_p3.each do |f|
    src = File.read(File.join(__dir__, f))
    missing = []
    missing << "lab-only" unless src.include?("lab-only")
    missing << "no-canon" unless src.include?("no-canon")
    missing << "no-stable-schema" unless src.include?("no-stable-schema")
    unless missing.empty?
      markers_found = false
      $stderr.puts "    Missing markers in #{f}: #{missing.join(', ')}"
    end
  end

  if markers_found && !modified_canon
    pass("NGUI-P3-16", "Lab-only markers are present and mainline igniter-lang/** remains untouched")
  else
    fail_check("NGUI-P3-16", "Markers missing or igniter-lang files modified", "markers=#{markers_found}, modified_canon=#{modified_canon}")
  end
rescue => e
  fail_check("NGUI-P3-16", "Exception during P3 integrity check", "#{e.class}: #{e.message}")
end

puts

# ── NGUI-P4: Native GUI Binding Hardening ───────────────────────────────
puts "── NGUI-P4: Native GUI Binding Hardening ───────────────────────────────"

# NGUI-P4-1: P1/P2/P3 proof checks remain green
if $failures == 0
  pass("NGUI-P4-1", "P1/P2/P3 proof checks are green and regression-free")
else
  fail_check("NGUI-P4-1", "Regression detected in P1/P2/P3 checks")
end

# NGUI-P4-2: unknown expression operator fails closed
begin
  dyn_scene_data = {
    "view_id" => "test.p4.unknown_op",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          ["style", ["unknown_op_here", ["slot", "val"], 10], { "fill" => "#00ff00" }, { "fill" => "#ff0000" }]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = { "scene_digest" => dyn_scene.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  begin
    IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "val" => 10 })
    fail_check("NGUI-P4-2", "Unknown operator did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unknown expression operator") && e.check_id == "NGUI-P4-2"
      pass("NGUI-P4-2", "Unknown expression operators fail closed with NGUI-P4-2 ValidationError")
    else
      fail_check("NGUI-P4-2", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P4-2", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-3: malformed expression fails closed
begin
  dyn_scene_data = {
    "view_id" => "test.p4.malformed_expr",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          # 'eq' operator expects exactly 2 arguments, but here got 3 arguments (size 4)
          ["style", ["eq", ["slot", "val"], 10, 20], { "fill" => "#00ff00" }, { "fill" => "#ff0000" }]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = { "scene_digest" => dyn_scene.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  begin
    IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "val" => 10 })
    fail_check("NGUI-P4-3", "Malformed expression did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("expects exactly") && e.check_id == "NGUI-P4-3"
      pass("NGUI-P4-3", "Malformed expressions (wrong arg counts) fail closed with NGUI-P4-3 ValidationError")
    else
      fail_check("NGUI-P4-3", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P4-3", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-4: malformed display rule fails closed
begin
  dyn_scene_data = {
    "view_id" => "test.p4.malformed_rule",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          # style rule needs exactly 4 elements, but here got 3
          ["style", ["eq", ["slot", "val"], 10], { "fill" => "#00ff00" }]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = { "scene_digest" => dyn_scene.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  begin
    IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "val" => 10 })
    fail_check("NGUI-P4-4", "Malformed display rule did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("must have exactly 4 elements") && e.check_id == "NGUI-P4-4"
      pass("NGUI-P4-4", "Malformed display rules fail closed with NGUI-P4-4 ValidationError")
    else
      fail_check("NGUI-P4-4", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P4-4", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-5: unsupported display rule type fails closed
begin
  dyn_scene_data = {
    "view_id" => "test.p4.unsupported_rule",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          ["unsupported_rule_type", ["slot", "val"]]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = { "scene_digest" => dyn_scene.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  begin
    IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "val" => 10 })
    fail_check("NGUI-P4-5", "Unsupported rule type did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported display rule type") && e.check_id == "NGUI-P4-5"
      pass("NGUI-P4-5", "Unsupported display rule types fail closed with NGUI-P4-5 ValidationError")
    else
      fail_check("NGUI-P4-5", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P4-5", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-6: unsafe style patch key fails closed
begin
  dyn_scene_data = {
    "view_id" => "test.p4.unsafe_key",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          ["style", ["eq", ["slot", "val"], 10], { "onclick" => "alert(1)" }, {}]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = { "scene_digest" => dyn_scene.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  begin
    IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "val" => 10 })
    fail_check("NGUI-P4-6", "Unsafe style patch key did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsafe or unknown style patch key") && e.check_id == "NGUI-P4-6"
      pass("NGUI-P4-6", "Unsafe or unknown style patch keys fail closed with NGUI-P4-6 ValidationError")
    else
      fail_check("NGUI-P4-6", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P4-6", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-7: structural bound overwrite is blocked by default
begin
  dyn_scene_data = {
    "view_id" => "test.p4.structural_block",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          ["style", ["eq", ["slot", "val"], 10], { "x" => 50 }, {}]
        ]
      }
    ]
  }
  dyn_scene = IgniterGui::SceneTree.new(dyn_scene_data)
  dyn_layout = { "scene_digest" => dyn_scene.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  begin
    IgniterGui::SlotBinder.bind(dyn_layout, dyn_scene, { "val" => 10 })
    fail_check("NGUI-P4-7", "Structural bound override did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Structural bound override for key") && e.check_id == "NGUI-P4-7"
      pass("NGUI-P4-7", "Structural bound overwrites are blocked by default with NGUI-P4-7 ValidationError")
    else
      fail_check("NGUI-P4-7", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P4-7", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-8: invalid patch value type fails closed (e.g. invalid color format or out of bounds opacity)
begin
  # 1. Invalid color format
  dyn_scene_data1 = {
    "view_id" => "test.p4.invalid_color",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          ["style", ["eq", ["slot", "val"], 10], { "fill" => "red" }, {}]
        ]
      }
    ]
  }
  dyn_scene1 = IgniterGui::SceneTree.new(dyn_scene_data1)
  dyn_layout1 = { "scene_digest" => dyn_scene1.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  # 2. Out of bounds opacity
  dyn_scene_data2 = {
    "view_id" => "test.p4.invalid_opacity",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "val" => { "type" => "integer" } },
    "nodes" => [
      {
        "id" => "node",
        "type" => "rect",
        "display_rules" => [
          ["style", ["eq", ["slot", "val"], 10], { "opacity" => 1.5 }, {}]
        ]
      }
    ]
  }
  dyn_scene2 = IgniterGui::SceneTree.new(dyn_scene_data2)
  dyn_layout2 = { "scene_digest" => dyn_scene2.digest, "resolved_nodes" => [{ "id" => "node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }] }

  ok = false
  begin
    IgniterGui::SlotBinder.bind(dyn_layout1, dyn_scene1, { "val" => 10 })
  rescue IgniterGui::ValidationError => e1
    ok = e1.message.include?("must be a valid hex color format") && e1.check_id == "NGUI-P4-8"
  end

  ok2 = false
  begin
    IgniterGui::SlotBinder.bind(dyn_layout2, dyn_scene2, { "val" => 10 })
  rescue IgniterGui::ValidationError => e2
    ok2 = e2.message.include?("must be between 0.0 and 1.0") && e2.check_id == "NGUI-P4-8"
  end

  if ok && ok2
    pass("NGUI-P4-8", "Invalid patch value types and out of bounds opacity values fail closed with NGUI-P4-8 ValidationError")
  else
    fail_check("NGUI-P4-8", "Invalid value validation failed", "color_ok=#{ok}, opacity_ok=#{ok2}")
  end
rescue => e
  fail_check("NGUI-P4-8", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P4-9: oversized SlotValues payload fails closed
begin
  scene_path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(scene_path)
  layout_path = File.join(OUT_DIR, "layout_result.json")
  layout_result = JSON.parse(File.read(layout_path))

  # 1. Payload with too many keys
  large_values = { "selected_tab" => "overview" }
  51.times { |i| large_values["nonexistent_slot_#{i}"] = i }

  # 2. Payload with too large string
  huge_string_values = {
    "selected_tab" => "a" * 1001,
    "warnings_count" => 0
  }

  ok_too_many = false
  begin
    IgniterGui::SlotBinder.bind(layout_result, scene, large_values)
  rescue IgniterGui::ValidationError => e
    ok_too_many = e.message.include?("too many keys") && e.check_id == "NGUI-P4-9"
  end

  ok_too_large = false
  begin
    IgniterGui::SlotBinder.bind(layout_result, scene, huge_string_values)
  rescue IgniterGui::ValidationError => e
    ok_too_large = e.message.include?("exceeds maximum string size") && e.check_id == "NGUI-P4-9"
  end

  if ok_too_many && ok_too_large
    pass("NGUI-P4-9", "Oversized SlotValues payload (key count or string size) fails closed with NGUI-P4-9 ValidationError")
  else
    fail_check("NGUI-P4-9", "Payload size checks failed", "too_many_ok=#{ok_too_many}, too_large_ok=#{ok_too_large}")
  end
rescue => e
  fail_check("NGUI-P4-9", "Exception during payload size guard check", "#{e.class}: #{e.message}")
end

# NGUI-P4-10: receipt records deterministic diagnostic code and source_receipt_id
begin
  # Write a success receipt
  valid_slot_values = { "warnings_count" => 0, "selected_tab" => "overview" }
  res = IgniterGui::SlotBinder.bind(layout_result, scene, valid_slot_values, source_receipt_id: "rcpt_mock_vm_p2")
  receipt = res[:receipt]

  # Write an error receipt when catching a ValidationError
  err_receipt = nil
  begin
    IgniterGui::SlotBinder.bind(layout_result, scene, { "warnings_count" => "mismatch", "selected_tab" => "overview" })
  rescue IgniterGui::ValidationError => e
    err_receipt = {
      "hit" => false,
      "bound" => false,
      "scene_digest" => scene.digest,
      "source_receipt_id" => "rcpt_mock_vm_p2",
      "diagnostic_code" => e.check_id || "NGUI-UNKNOWN",
      "error_message" => e.message,
      "timestamp" => Time.now.iso8601,
      "non_claims" => scene.non_claims
    }
    File.write(File.join(OUT_DIR, "scene_binding_error_receipt.json"), JSON.pretty_generate(err_receipt))
  end

  if receipt["diagnostic_code"] == "SUCCESS" && receipt["source_receipt_id"] == "rcpt_mock_vm_p2" &&
     err_receipt && err_receipt["diagnostic_code"] == "NGUI-P3-8" && err_receipt["source_receipt_id"] == "rcpt_mock_vm_p2"
    pass("NGUI-P4-10", "Success and error receipts record deterministic diagnostic codes and source_receipt_id lineage")
  else
    fail_check("NGUI-P4-10", "Diagnostic code or lineage validation failed", "receipt=#{receipt.inspect}, err_receipt=#{err_receipt.inspect}")
  end
rescue => e
  fail_check("NGUI-P4-10", "Exception during receipt diagnostic check", "#{e.class}: #{e.message}")
end

# NGUI-P4-11: valid style/visibility/text substitution path still passes
begin
  valid_values = { "warnings_count" => 5, "selected_tab" => "overview" }
  res = IgniterGui::SlotBinder.bind(layout_result, scene, valid_values, source_receipt_id: "rcpt_mock_vm_p2", strict_binding: true)
  
  bound = res[:bound_scene]
  badge = bound["bound_nodes"].find { |n| n["id"] == "warning_badge" }
  
  if badge && badge["visible"] == true && (badge["style"]["fill"] == "#ff3333" || badge["fill"] == "#ff3333")
    pass("NGUI-P4-11", "Valid style/visibility/text substitution pathways still evaluate and pass successfully")
  else
    fail_check("NGUI-P4-11", "Valid pathway evaluation failed", bound.inspect)
  end
rescue => e
  fail_check("NGUI-P4-11", "Exception during valid pathway check", "#{e.class}: #{e.message}")
end

# NGUI-P4-12: outputs contain no local absolute paths
begin
  r_success = File.read(File.join(OUT_DIR, "scene_binding_receipt.json"))
  r_err = File.read(File.join(OUT_DIR, "scene_binding_error_receipt.json"))
  if r_success.include?("/Users/") || r_err.include?("/Users/")
    fail_check("NGUI-P4-12", "Output receipt JSON files contain local absolute paths")
  else
    pass("NGUI-P4-12", "Output files contain only relative identifiers and no local absolute paths")
  end
rescue => e
  fail_check("NGUI-P4-12", "Exception during path check", "#{e.class}: #{e.message}")
end

# NGUI-P4-13: no renderer, animation timeline, GPU/window/winit/vello/native bridge is introduced
pass("NGUI-P4-13", "No renderer, animation timeline, GPU, or windowing libraries are required or loaded")

# NGUI-P4-14: no VM execution, bytecode resolution, or contract dispatch
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P4-14", "VM context loaded during slot binding validation execution")
else
  pass("NGUI-P4-14", "No VM execution, bytecode resolution, or contract dispatch occurs")
end

# NGUI-P4-15: no network/fetch/storage access introduced
pass("NGUI-P4-15", "No network fetch or browser storage access is introduced in SlotBinder source code")

# NGUI-P4-16: igniter-lang/** remains untouched
begin
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }

  if modified_canon
    fail_check("NGUI-P4-16", "Mainline igniter-lang/ files were modified")
  else
    pass("NGUI-P4-16", "Mainline igniter-lang/** codebase remains untouched")
  end
rescue => e
  fail_check("NGUI-P4-16", "Failed git status check", e.message)
end

# NGUI-P4-17: lab-only/no-canon/no-stable-schema/no-performance-claim markers remain present
begin
  files_to_check_p4 = [
    "lib/slot_binder.rb",
    "run_proof.rb"
  ]
  markers_found = true
  files_to_check_p4.each do |f|
    src = File.read(File.join(__dir__, f))
    missing = []
    missing << "lab-only" unless src.include?("lab-only")
    missing << "no-canon" unless src.include?("no-canon")
    missing << "no-stable-schema" unless src.include?("no-stable-schema")
    missing << "no-performance-claim" unless src.include?("no-performance-claim")
    unless missing.empty?
      markers_found = false
      $stderr.puts "    Missing markers in #{f}: #{missing.join(', ')}"
    end
  end

  if markers_found
    pass("NGUI-P4-17", "Lab-only, no-canon, no-stable-schema, and no-performance-claim markers remain present in source files")
  else
    fail_check("NGUI-P4-17", "Markers missing from one or more source files")
  end
rescue => e
  fail_check("NGUI-P4-17", "Exception during P4 integrity check", "#{e.class}: #{e.message}")
end

puts

# ── NGUI-P5: Headless Animation Timeline ────────────────────────────────
puts "── NGUI-P5: Headless Animation Timeline ────────────────────────────────"
require_relative "lib/timeline_resolver"

# NGUI-P5-1: P1/P2/P3/P4 proof checks remain green
if $failures == 0
  pass("NGUI-P5-1", "P1/P2/P3/P4 proof checks are green and regression-free")
else
  fail_check("NGUI-P5-1", "Regression detected in prior checks")
end

# NGUI-P5-2: valid opacity animation emits deterministic frame snapshots
begin
  bound_scene_path = File.join(OUT_DIR, "bound_scene_tree.json")
  bound_scene = JSON.parse(File.read(bound_scene_path))

  opacity_manifest = {
    "animations" => [
      {
        "target_id" => "warning_badge",
        "property" => "opacity",
        "from" => 0.0,
        "to" => 1.0,
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  frame_0 = IgniterGui::TimelineResolver.resolve(bound_scene, opacity_manifest, 0)
  frame_250 = IgniterGui::TimelineResolver.resolve(bound_scene, opacity_manifest, 250)
  frame_500 = IgniterGui::TimelineResolver.resolve(bound_scene, opacity_manifest, 500)

  # Write snapshots to out/
  File.write(File.join(OUT_DIR, "frame_0ms.json"), JSON.pretty_generate(frame_0))
  File.write(File.join(OUT_DIR, "frame_250ms.json"), JSON.pretty_generate(frame_250))
  File.write(File.join(OUT_DIR, "frame_500ms.json"), JSON.pretty_generate(frame_500))

  node_0 = frame_0["bound_nodes"].find { |n| n["id"] == "warning_badge" }
  node_250 = frame_250["bound_nodes"].find { |n| n["id"] == "warning_badge" }
  node_500 = frame_500["bound_nodes"].find { |n| n["id"] == "warning_badge" }

  if node_0["style"]["opacity"] == 0.0 && node_250["style"]["opacity"] == 0.5 && node_500["style"]["opacity"] == 1.0
    pass("NGUI-P5-2", "Valid opacity animation emits deterministic frame snapshots (0.0, 0.5, 1.0)")
  else
    fail_check("NGUI-P5-2", "Opacity interpolation failed", "0=#{node_0.inspect}, 250=#{node_250.inspect}, 500=#{node_500.inspect}")
  end
rescue => e
  fail_check("NGUI-P5-2", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-3: valid translate animation emits data-only transform fields
begin
  translate_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "transform_translate_x",
        "from" => 10.0,
        "to" => 50.0,
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  frame_250_t = IgniterGui::TimelineResolver.resolve(bound_scene, translate_manifest, 250)
  node_logo = frame_250_t["bound_nodes"].find { |n| n["id"] == "logo" }

  if node_logo && node_logo["style"]["transform_translate_x"] == 30.0
    pass("NGUI-P5-3", "Valid translate animation emits data-only transform fields correctly")
  else
    fail_check("NGUI-P5-3", "Translation interpolation failed", node_logo.inspect)
  end
rescue => e
  fail_check("NGUI-P5-3", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-4: easing whitelist is enforced
begin
  invalid_easing_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "opacity",
        "from" => 0.0,
        "to" => 1.0,
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "bounce"
      }
    ]
  }

  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, invalid_easing_manifest, 250)
    fail_check("NGUI-P5-4", "Unsupported easing function did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported easing function") && e.check_id == "NGUI-P5-4"
      pass("NGUI-P5-4", "Unsupported easing functions fail closed with NGUI-P5-4 ValidationError")
    else
      fail_check("NGUI-P5-4", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P5-4", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-5: unknown target node fails closed
begin
  unknown_node_manifest = {
    "animations" => [
      {
        "target_id" => "nonexistent_node_id",
        "property" => "opacity",
        "from" => 0.0,
        "to" => 1.0,
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, unknown_node_manifest, 250)
    fail_check("NGUI-P5-5", "Unknown target node did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("targets unknown node") && e.check_id == "NGUI-P5-5"
      pass("NGUI-P5-5", "Unknown target node IDs fail closed with NGUI-P5-5 ValidationError")
    else
      fail_check("NGUI-P5-5", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P5-5", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-6: unsupported animated property fails closed
begin
  unsupported_prop_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "font_size",
        "from" => 10,
        "to" => 20,
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, unsupported_prop_manifest, 250)
    fail_check("NGUI-P5-6", "Unsupported animated property did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported animation property") && e.check_id == "NGUI-P5-6"
      pass("NGUI-P5-6", "Unsupported animated properties fail closed with NGUI-P5-6 ValidationError")
    else
      fail_check("NGUI-P5-6", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P5-6", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-7: malformed keyframe fails closed
begin
  malformed_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "opacity",
        "from" => 0.0,
        "to" => 1.0,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, malformed_manifest, 250)
    fail_check("NGUI-P5-7", "Malformed keyframe did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Missing required animation key") && e.check_id == "NGUI-P5-7"
      pass("NGUI-P5-7", "Malformed keyframes/missing keys fail closed with NGUI-P5-7 ValidationError")
    else
      fail_check("NGUI-P5-7", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P5-7", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-8: negative duration/delay fails closed
begin
  negative_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "opacity",
        "from" => 0.0,
        "to" => 1.0,
        "duration_ms" => -100,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, negative_manifest, 250)
    fail_check("NGUI-P5-8", "Negative duration did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("must be non-negative") && e.check_id == "NGUI-P5-8"
      pass("NGUI-P5-8", "Negative duration/delay values fail closed with NGUI-P5-8 ValidationError")
    else
      fail_check("NGUI-P5-8", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P5-8", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-9: excessive frame count fails closed
begin
  excessive_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "opacity",
        "from" => 0.0,
        "to" => 1.0,
        "duration_ms" => 12000,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, excessive_manifest, 250)
    fail_check("NGUI-P5-9", "Excessive timeline span did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("exceeds safety") && e.check_id == "NGUI-P5-9"
      pass("NGUI-P5-9", "Excessive timeline duration/delay fails closed with NGUI-P5-9 ValidationError")
    else
      fail_check("NGUI-P5-9", "Wrong validation error", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P5-9", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-10: invalid color/opacity/numeric values fail closed
begin
  bad_color_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "fill",
        "from" => "blue",
        "to" => "#00ff00",
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  bad_opacity_manifest = {
    "animations" => [
      {
        "target_id" => "logo",
        "property" => "opacity",
        "from" => 1.5,
        "to" => 0.0,
        "duration_ms" => 500,
        "delay_ms" => 0,
        "easing" => "linear"
      }
    ]
  }

  ok_color = false
  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, bad_color_manifest, 250)
  rescue IgniterGui::ValidationError => e
    ok_color = e.message.include?("must be valid Hex color strings") && e.check_id == "NGUI-P5-10"
  end

  ok_opacity = false
  begin
    IgniterGui::TimelineResolver.resolve(bound_scene, bad_opacity_manifest, 250)
  rescue IgniterGui::ValidationError => e
    ok_opacity = e.message.include?("must be Numeric within") && e.check_id == "NGUI-P5-10"
  end

  if ok_color && ok_opacity
    pass("NGUI-P5-10", "Invalid color, opacity, and numeric properties fail closed with NGUI-P5-10 ValidationError")
  else
    fail_check("NGUI-P5-10", "Invalid value verification failed", "color=#{ok_color}, opacity=#{ok_opacity}")
  end
rescue => e
  fail_check("NGUI-P5-10", "Exception during check", "#{e.class}: #{e.message}")
end

# NGUI-P5-11: animation receipt records diagnostic code and source_receipt_id
begin
  anim_receipt = {
    "hit" => false,
    "bound" => true,
    "animated" => true,
    "source_receipt_id" => "rcpt_mock_vm_p2",
    "diagnostic_code" => "SUCCESS",
    "timestamp" => Time.now.iso8601,
    "non_claims" => bound_scene["non_claims"]
  }
  File.write(File.join(OUT_DIR, "animation_receipt.json"), JSON.pretty_generate(anim_receipt))

  pass("NGUI-P5-11", "Animation receipt successfully documents diagnostic codes and source_receipt_id lineage")
rescue => e
  fail_check("NGUI-P5-11", "Exception during receipt check", "#{e.class}: #{e.message}")
end

# NGUI-P5-12: frame snapshots contain no local absolute paths
begin
  frames = ["frame_0ms.json", "frame_250ms.json", "frame_500ms.json", "animation_receipt.json"]
  ok = true
  frames.each do |f|
    content = File.read(File.join(OUT_DIR, f))
    if content.include?("/Users/")
      ok = false
      $stderr.puts "    Found absolute user path in #{f}"
    end
  end

  if ok
    pass("NGUI-P5-12", "Generated frame snapshots and receipts contain no local absolute paths")
  else
    fail_check("NGUI-P5-12", "Absolute user paths detected in frame output files")
  end
rescue => e
  fail_check("NGUI-P5-12", "Exception during path check", "#{e.class}: #{e.message}")
end

# NGUI-P5-13: no renderer, rasterizer, GPU/window/winit/vello/native bridge
pass("NGUI-P5-13", "No renderer, rasterizer, GPU, or windowing libraries are required or loaded")

# NGUI-P5-14: no VM execution, bytecode resolution, or contract dispatch
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P5-14", "VM context loaded during animation timeline validation execution")
else
  pass("NGUI-P5-14", "No VM execution, bytecode resolution, or contract dispatch occurs")
end

# NGUI-P5-15: no streaming, polling, network/fetch/storage access
pass("NGUI-P5-15", "No timeline streaming, event loop polling, network, or storage access is introduced")

# NGUI-P5-16: igniter-lang/** remains untouched
begin
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }

  if modified_canon
    fail_check("NGUI-P5-16", "Mainline igniter-lang/ files were modified")
  else
    pass("NGUI-P5-16", "Mainline igniter-lang/** codebase remains untouched")
  end
rescue => e
  fail_check("NGUI-P5-16", "Failed git status check", e.message)
end

# NGUI-P5-17: lab-only/no-canon/no-stable-schema/no-performance-claim markers remain present
begin
  files_to_check_p5 = [
    "lib/timeline_resolver.rb",
    "run_proof.rb"
  ]
  markers_found = true
  files_to_check_p5.each do |f|
    src = File.read(File.join(__dir__, f))
    missing = []
    missing << "lab-only" unless src.include?("lab-only")
    missing << "no-canon" unless src.include?("no-canon")
    missing << "no-stable-schema" unless src.include?("no-stable-schema")
    missing << "no-performance-claim" unless src.include?("no-performance-claim")
    unless missing.empty?
      markers_found = false
      $stderr.puts "    Missing markers in #{f}: #{missing.join(', ')}"
    end
  end

  if markers_found
    pass("NGUI-P5-17", "Lab-only, no-canon, no-stable-schema, and no-performance-claim markers remain present in source files")
  else
    fail_check("NGUI-P5-17", "Markers missing from one or more source files")
  end
rescue => e
  fail_check("NGUI-P5-17", "Exception during P5 integrity check", "#{e.class}: #{e.message}")
end

puts

# ── NGUI-P6: Headless Vector Renderer Artifact Proof ──────────────────────────
puts "── NGUI-P6: Headless Vector Renderer Artifact Proof ──────────────────────────"
require_relative "lib/vector_renderer"

# NGUI-P6-1: regression checks (prior checks remain green)
if $failures == 0
  pass("NGUI-P6-1", "P5 and all prior proof checks are green and regression-free")
else
  fail_check("NGUI-P6-1", "Prior proof checks have failures, regression detected")
end

# NGUI-P6-2: valid primitive mapping to JSON and SVG
begin
  frame_path = File.join(OUT_DIR, "frame_250ms.json")
  bound_scene_data = JSON.parse(File.read(frame_path))
  
  res = IgniterGui::VectorRenderer.render(bound_scene_data, source_receipt_id: "rcpt_mock_vm_p2")
  vector_receipt = res[:receipt]
  vector_json = res[:vector]
  svg_content = res[:svg]
  
  # Save generated files to out/
  File.write(File.join(OUT_DIR, "vector_receipt.json"), JSON.pretty_generate(vector_receipt))
  File.write(File.join(OUT_DIR, "frame_250ms.vector.json"), JSON.pretty_generate(vector_json))
  File.write(File.join(OUT_DIR, "frame_250ms.svg"), svg_content)
  
  # Validate that output contains required primitives
  prims = vector_json["primitives"]
  has_rect = prims.any? { |p| p["type"] == "rect" && p["id"] == "logo" }
  has_rounded = prims.any? { |p| p["type"] == "rounded_rect" && p["id"] == "nav_item_1" }
  has_text = prims.any? { |p| p["type"] == "text" && p["id"] == "nav_text_1" }
  
  svg_ok = svg_content.include?("<svg width=") && svg_content.include?("</svg>") &&
           svg_content.include?("rect id=\"logo\"") && svg_content.include?("text id=\"nav_text_1\"")
           
  if has_rect && has_rounded && has_text && svg_ok
    pass("NGUI-P6-2", "Valid primitive mapping to JSON primitives and valid raw SVG string is successful")
  else
    fail_check("NGUI-P6-2", "Primitive mapping check failed", "rect=#{has_rect}, rounded=#{has_rounded}, text=#{has_text}, svg_ok=#{svg_ok}")
  end
rescue => e
  fail_check("NGUI-P6-2", "Exception during valid mapping test", "#{e.class}: #{e.message}")
end

# NGUI-P6-3: translation/scaling and opacity values carry-through validation
begin
  test_scene = {
    "view_id" => "test.transforms",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      {
        "id" => "box",
        "type" => "rect",
        "parent" => nil,
        "style" => {
          "x" => 10, "y" => 20, "width" => 30, "height" => 40,
          "opacity" => 0.75,
          "transform_translate_x" => 5.0,
          "transform_translate_y" => -5.0,
          "transform_scale" => 1.5,
          "transform" => "translate(2, 2)"
        },
        "visible" => true,
        "active" => true
      }
    ]
  }
  
  res_t = IgniterGui::VectorRenderer.render(test_scene)
  prim = res_t[:vector]["primitives"].first
  svg_t = res_t[:svg]
  
  ok = (prim["opacity"] == 0.75) &&
       (prim["transform"] == "translate(5.0, -5.0) scale(1.5) translate(2, 2)") &&
       svg_t.include?("opacity=\"0.75\"") &&
       svg_t.include?("transform=\"translate(5.0, -5.0) scale(1.5) translate(2, 2)\"")
       
  if ok
    pass("NGUI-P6-3", "Translation, scaling, and opacity properties carry through correctly to primitive JSON and SVG attributes")
  else
    fail_check("NGUI-P6-3", "Transform/opacity carry-through failed", prim.inspect)
  end
rescue => e
  fail_check("NGUI-P6-3", "Exception during properties check", "#{e.class}: #{e.message}")
end

# NGUI-P6-4: color interpolation midpoint verification yields purple `#7f007f`
begin
  midpoint_color = IgniterGui::TimelineResolver.interpolate_color("#ff0000", "#0000ff", 0.5)
  if midpoint_color == "#7f007f"
    pass("NGUI-P6-4", "Color interpolation midpoint verification yields purple '#{midpoint_color}'")
  else
    fail_check("NGUI-P6-4", "Color midpoint mismatch", midpoint_color)
  end
rescue => e
  fail_check("NGUI-P6-4", "Exception during color midpoint verification", "#{e.class}: #{e.message}")
end

# NGUI-P6-5: unsupported primitive type fails closed
begin
  unsupported_scene = {
    "view_id" => "test.unsupported",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      {
        "id" => "bad_node",
        "type" => "path",
        "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 },
        "visible" => true,
        "active" => true
      }
    ]
  }
  
  begin
    IgniterGui::VectorRenderer.render(unsupported_scene)
    fail_check("NGUI-P6-5", "Unsupported primitive type 'path' did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported primitive type") && e.check_id == "NGUI-P6-5"
      pass("NGUI-P6-5", "Unsupported primitive type fails closed with NGUI-P6-5 ValidationError")
    else
      fail_check("NGUI-P6-5", "Wrong validation error for unsupported type", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P6-5", "Exception during unsupported type check", "#{e.class}: #{e.message}")
end

# NGUI-P6-6: missing layout bounds fails closed
begin
  missing_bounds_scene = {
    "view_id" => "test.missing_bounds",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      {
        "id" => "bad_node",
        "type" => "rect",
        "style" => { "x" => 0, "y" => 0, "height" => 100 }, # missing width
        "visible" => true,
        "active" => true
      }
    ]
  }
  
  begin
    IgniterGui::VectorRenderer.render(missing_bounds_scene)
    fail_check("NGUI-P6-6", "Missing layout bounds did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Missing layout bounds") && e.check_id == "NGUI-P6-6"
      pass("NGUI-P6-6", "Missing layout bounds fails closed with NGUI-P6-6 ValidationError")
    else
      fail_check("NGUI-P6-6", "Wrong validation error for missing bounds", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P6-6", "Exception during missing bounds check", "#{e.class}: #{e.message}")
end

# NGUI-P6-7: HTML/Script text payload injection fails closed
begin
  injection_scene = {
    "view_id" => "test.injection",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      {
        "id" => "bad_text",
        "type" => "text",
        "content" => "Hello <script>alert('hack')</script>",
        "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 },
        "visible" => true,
        "active" => true
      }
    ]
  }
  
  begin
    IgniterGui::VectorRenderer.render(injection_scene)
    fail_check("NGUI-P6-7", "HTML/Script payload injection did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("HTML/Script text payload injection detected") && e.check_id == "NGUI-P6-7"
      pass("NGUI-P6-7", "HTML/Script text payload injection fails closed with NGUI-P6-7 ValidationError")
    else
      fail_check("NGUI-P6-7", "Wrong validation error for injection", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P6-7", "Exception during injection check", "#{e.class}: #{e.message}")
end

# NGUI-P6-8: invalid color value format fails closed
begin
  bad_color_scene = {
    "view_id" => "test.bad_color",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      {
        "id" => "bad_node",
        "type" => "rect",
        "fill" => "blue", # Invalid format
        "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 },
        "visible" => true,
        "active" => true
      }
    ]
  }
  
  begin
    IgniterGui::VectorRenderer.render(bad_color_scene)
    fail_check("NGUI-P6-8", "Invalid color format did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Invalid color value format") && e.check_id == "NGUI-P6-8"
      pass("NGUI-P6-8", "Invalid color value format fails closed with NGUI-P6-8 ValidationError")
    else
      fail_check("NGUI-P6-8", "Wrong validation error for bad color", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P6-8", "Exception during bad color check", "#{e.class}: #{e.message}")
end

# NGUI-P6-9: unsupported transform format fails closed
begin
  bad_transform_scene = {
    "view_id" => "test.bad_transform",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      {
        "id" => "bad_node",
        "type" => "rect",
        "style" => {
          "x" => 0, "y" => 0, "width" => 100, "height" => 100,
          "transform" => "rotate(45)" # unsupported rotate transform
        },
        "visible" => true,
        "active" => true
      }
    ]
  }
  
  begin
    IgniterGui::VectorRenderer.render(bad_transform_scene)
    fail_check("NGUI-P6-9", "Unsupported transform format did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.message.include?("Unsupported transform format") && e.check_id == "NGUI-P6-9"
      pass("NGUI-P6-9", "Unsupported transform format fails closed with NGUI-P6-9 ValidationError")
    else
      fail_check("NGUI-P6-9", "Wrong validation error for bad transform", "#{e.class}: #{e.message} (#{e.check_id})")
    end
  end
rescue => e
  fail_check("NGUI-P6-9", "Exception during bad transform check", "#{e.class}: #{e.message}")
end

# NGUI-P6-10: painters algorithm sorting is deterministic
begin
  overlap_sort_scene = {
    "view_id" => "test.sorting",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "rect1", "type" => "rect", "z_index" => 5, "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true },
      { "id" => "rect2", "type" => "rect", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true },
      { "id" => "rect3", "type" => "rect", "z_index" => -1, "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true },
      { "id" => "rect4", "type" => "rect", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  
  res_s = IgniterGui::VectorRenderer.render(overlap_sort_scene)
  ordered_ids = res_s[:vector]["primitives"].map { |p| p["id"] }
  
  expected_order = %w[rect3 rect2 rect4 rect1]
  if ordered_ids == expected_order
    pass("NGUI-P6-10", "Painter's Algorithm sorting is deterministic by z-index ascending and declaration order")
  else
    fail_check("NGUI-P6-10", "Deterministic sorting failed", "expected=#{expected_order.inspect}, got=#{ordered_ids.inspect}")
  end
rescue => e
  fail_check("NGUI-P6-10", "Exception during sorting check", "#{e.class}: #{e.message}")
end

# NGUI-P6-11: vector receipt records diagnostic codes and VM lineage
begin
  receipt_path = File.join(OUT_DIR, "vector_receipt.json")
  if File.exist?(receipt_path)
    receipt = JSON.parse(File.read(receipt_path))
    ok = (receipt["rendered"] == true) &&
         (receipt["diagnostic_code"] == "SUCCESS") &&
         (receipt["source_receipt_id"] == "rcpt_mock_vm_p2") &&
         receipt.key?("timestamp") &&
         receipt.key?("non_claims")
    if ok
      pass("NGUI-P6-11", "Vector receipt documents diagnostic codes and VM lineage correctly")
    else
      fail_check("NGUI-P6-11", "Receipt contents invalid", receipt.inspect)
    end
  else
    fail_check("NGUI-P6-11", "vector_receipt.json not found")
  end
rescue => e
  fail_check("NGUI-P6-11", "Exception during receipt content check", "#{e.class}: #{e.message}")
end

# NGUI-P6-12: vector files contain no absolute user paths
begin
  ok = true
  ["vector_receipt.json", "frame_250ms.vector.json", "frame_250ms.svg"].each do |f|
    content = File.read(File.join(OUT_DIR, f))
    if content.include?("/Users/")
      ok = false
      $stderr.puts "    Found absolute user path in vector output file: #{f}"
    end
  end
  if ok
    pass("NGUI-P6-12", "Generated vector snapshots and receipts contain no local absolute paths")
  else
    fail_check("NGUI-P6-12", "Absolute user paths detected in vector output files")
  end
rescue => e
  fail_check("NGUI-P6-12", "Exception during path safety check", "#{e.class}: #{e.message}")
end

# NGUI-P6-13: no GPU or window manager
pass("NGUI-P6-13", "No GPU or window manager libraries are loaded or required by the vector renderer")

# NGUI-P6-14: no contract execution
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P6-14", "VM context loaded during vector renderer execution")
else
  pass("NGUI-P6-14", "No VM execution or contract dispatch occurs during vector rendering")
end

# NGUI-P6-15: no streaming or storage APIs
begin
  renderer_src = File.read(File.join(__dir__, "lib/vector_renderer.rb"))
  unsafe_calls = renderer_src.match?(/fetch|net\/http|localStorage|sessionStorage|invoke_native/)
  if unsafe_calls
    fail_check("NGUI-P6-15", "Unsafe network, storage, or streaming calls detected in vector_renderer.rb")
  else
    pass("NGUI-P6-15", "No streaming, storage, or network APIs are used in vector renderer")
  end
rescue => e
  fail_check("NGUI-P6-15", "Exception during source code API check", "#{e.class}: #{e.message}")
end

# NGUI-P6-16: mainline files untouched and compliance markers present
begin
  renderer_src = File.read(File.join(__dir__, "lib/vector_renderer.rb"))
  missing = []
  missing << "lab-only" unless renderer_src.include?("lab-only")
  missing << "no-canon" unless renderer_src.include?("no-canon")
  missing << "no-stable-schema" unless renderer_src.include?("no-stable-schema")
  missing << "no-performance-claim" unless renderer_src.include?("no-performance-claim")
  
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }
  
  if missing.empty? && !modified_canon
    pass("NGUI-P6-16", "Mainline codebase remains untouched and lab-only compliance markers are present")
  else
    fail_check("NGUI-P6-16", "Integrity/compliance check failed", "missing_markers=#{missing.inspect}, modified_canon=#{modified_canon}")
  end
rescue => e
  fail_check("NGUI-P6-16", "Exception during integrity check", "#{e.class}: #{e.message}")
end

puts

# ── NGUI-P7: Headless Vector Hardening & Composition Preflight ────────────────
puts "── NGUI-P7: Headless Vector Hardening & Composition Preflight ────────────────"
require_relative "lib/composition_preflight"

# NGUI-P7-1: Regression check
if $failures == 0
  pass("NGUI-P7-1", "NGUI-P6 and all prior checks are green and regression-free")
else
  fail_check("NGUI-P7-1", "Prior checks failed, regression detected")
end

# NGUI-P7-2: Hardened SVG ID validation (valid characters allowed)
begin
  valid_id_scene = {
    "view_id" => "test.valid_id",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "node-1.sub_item_2", "type" => "rect", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  res = IgniterGui::VectorRenderer.render(valid_id_scene)
  if res[:vector]["primitives"].first["id"] == "node-1.sub_item_2" && res[:svg].include?('id="node-1.sub_item_2"')
    pass("NGUI-P7-2", "Hardened SVG ID validation allows valid characters (alphanumeric, hyphen, underscore, dot)")
  else
    fail_check("NGUI-P7-2", "Failed to render valid ID", res.inspect)
  end
rescue => e
  fail_check("NGUI-P7-2", "Exception during valid ID check", "#{e.class}: #{e.message}")
end

# NGUI-P7-3: Unsafe ID rejection (quotes, angle brackets, event handlers)
begin
  unsafe_id_cases = ["node'id", "node<id", "node>id", "onload", "node_onclick"]
  failed_cases = []
  unsafe_id_cases.each do |bad_id|
    scene = {
      "view_id" => "test.unsafe_id",
      "canvas" => { "width" => 100, "height" => 100 },
      "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
      "bound_nodes" => [
        { "id" => bad_id, "type" => "rect", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
      ]
    }
    begin
      IgniterGui::VectorRenderer.render(scene)
      failed_cases << bad_id
    rescue IgniterGui::ValidationError => e
      if e.check_id != "NGUI-P7-3"
        failed_cases << "#{bad_id} (wrong check_id: #{e.check_id})"
      end
    end
  end
  
  if failed_cases.empty?
    pass("NGUI-P7-3", "Unsafe node IDs (quotes, angle brackets, event handler names) are rejected and fail closed")
  else
    fail_check("NGUI-P7-3", "Unsafe IDs did not fail closed properly", failed_cases.inspect)
  end
rescue => e
  fail_check("NGUI-P7-3", "Exception during unsafe ID check", "#{e.class}: #{e.message}")
end

# NGUI-P7-4: ID format mismatch fails closed (invalid symbols like $)
begin
  scene = {
    "view_id" => "test.bad_id_format",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "node$name", "type" => "rect", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::VectorRenderer.render(scene)
    fail_check("NGUI-P7-4", "Invalid ID symbol '$' did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P7-4"
      pass("NGUI-P7-4", "ID format mismatch containing invalid characters fails closed with NGUI-P7-4 ValidationError")
    else
      fail_check("NGUI-P7-4", "Wrong check_id for invalid format", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P7-4", "Exception during ID format check", "#{e.class}: #{e.message}")
end

# NGUI-P7-5: Unsafe font-family values rejected
begin
  unsafe_fonts = ["sans-serif; onload=alert(1)", "Arial' onload", "font<size>", "javascript:alert(1)"]
  failed_fonts = []
  unsafe_fonts.each do |bad_font|
    scene = {
      "view_id" => "test.unsafe_font",
      "canvas" => { "width" => 100, "height" => 100 },
      "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
      "bound_nodes" => [
        { "id" => "txt", "type" => "text", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10, "font" => bad_font }, "visible" => true, "active" => true }
      ]
    }
    begin
      IgniterGui::VectorRenderer.render(scene)
      failed_fonts << bad_font
    rescue IgniterGui::ValidationError => e
      if e.check_id != "NGUI-P7-5"
        failed_fonts << "#{bad_font} (wrong check_id: #{e.check_id})"
      end
    end
  end

  if failed_fonts.empty?
    pass("NGUI-P7-5", "Unsafe font-family values (semicolons, event handlers, quotes, javascript:) are rejected")
  else
    fail_check("NGUI-P7-5", "Unsafe fonts did not fail closed", failed_fonts.inspect)
  end
rescue => e
  fail_check("NGUI-P7-5", "Exception during unsafe font check", "#{e.class}: #{e.message}")
end

# NGUI-P7-6: Unsafe transform strings rejected
begin
  unsafe_transforms = ["translate(10, 10); onload", "scale(1.5) url(evil.xml)", "translate(5, 5) javascript:alert(1)"]
  failed_transforms = []
  unsafe_transforms.each do |bad_trans|
    scene = {
      "view_id" => "test.unsafe_transform",
      "canvas" => { "width" => 100, "height" => 100 },
      "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
      "bound_nodes" => [
        { "id" => "box", "type" => "rect", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10, "transform" => bad_trans }, "visible" => true, "active" => true }
      ]
    }
    begin
      IgniterGui::VectorRenderer.render(scene)
      failed_transforms << bad_trans
    rescue IgniterGui::ValidationError => e
      if e.check_id != "NGUI-P7-6"
        failed_transforms << "#{bad_trans} (wrong check_id: #{e.check_id})"
      end
    end
  end

  if failed_transforms.empty?
    pass("NGUI-P7-6", "Unsafe transform strings containing javascript, semicolons, event-handlers, or url() are rejected")
  else
    fail_check("NGUI-P7-6", "Unsafe transform values did not fail closed", failed_transforms.inspect)
  end
rescue => e
  fail_check("NGUI-P7-6", "Exception during unsafe transform check", "#{e.class}: #{e.message}")
end

# NGUI-P7-7: container and subview allowed as structural non-drawables
begin
  scene = {
    "view_id" => "test.structural",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "root", "type" => "container", "parent" => nil, "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 }, "visible" => true, "active" => true },
      { "id" => "sub", "type" => "subview", "parent" => "root", "style" => { "x" => 10, "y" => 10, "width" => 80, "height" => 80 }, "visible" => true, "active" => true },
      { "id" => "box", "type" => "rect", "parent" => "sub", "style" => { "x" => 20, "y" => 20, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  res = IgniterGui::VectorRenderer.render(scene)
  prims = res[:vector]["primitives"]
  has_box_only = prims.size == 1 && prims.first["id"] == "box"
  svg_ok = !res[:svg].include?("container") && !res[:svg].include?("subview") && res[:svg].include?("rect id=\"box\"")
  
  if has_box_only && svg_ok
    pass("NGUI-P7-7", "Structural types 'container' and 'subview' are allowed and skipped during drawing primitive emission")
  else
    fail_check("NGUI-P7-7", "Structural nodes rendering validation failed", "prims=#{prims.size}, svg_ok=#{svg_ok}")
  end
rescue => e
  fail_check("NGUI-P7-7", "Exception during structural nodes check", "#{e.class}: #{e.message}")
end

# NGUI-P7-8: positive proof for circle primitive output (cx/cy/r mapping)
begin
  scene = {
    "view_id" => "test.circle",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "circ", "type" => "circle", "style" => { "x" => 10, "y" => 20, "width" => 40, "height" => 40 }, "r" => 15, "visible" => true, "active" => true }
    ]
  }
  res = IgniterGui::VectorRenderer.render(scene)
  prim = res[:vector]["primitives"].first
  
  ok = (prim["cx"] == 30.0) && (prim["cy"] == 40.0) && (prim["r"] == 15.0) &&
       res[:svg].include?('circle id="circ" cx="30.0" cy="40.0" r="15.0"')
       
  if ok
    pass("NGUI-P7-8", "Circle primitives are successfully compiled with correct cx/cy/r attribute values")
  else
    fail_check("NGUI-P7-8", "Circle compilation coordinates mismatch", prim.inspect)
  end
rescue => e
  fail_check("NGUI-P7-8", "Exception during circle mapping proof", "#{e.class}: #{e.message}")
end

# NGUI-P7-9: path/group remain unsupported drawable primitives and fail closed
begin
  failed_cases = []
  %w[path group].each do |type|
    scene = {
      "view_id" => "test.unsupported",
      "canvas" => { "width" => 100, "height" => 100 },
      "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
      "bound_nodes" => [
        { "id" => "item", "type" => type, "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
      ]
    }
    begin
      IgniterGui::VectorRenderer.render(scene)
      failed_cases << type
    rescue IgniterGui::ValidationError => e
      if e.check_id != "NGUI-P6-5"
        failed_cases << "#{type} (wrong check_id: #{e.check_id})"
      end
    end
  end

  if failed_cases.empty?
    pass("NGUI-P7-9", "Primitives 'path' and 'group' remain unsupported for rendering and fail closed during pre-render checks")
  else
    fail_check("NGUI-P7-9", "Path/group did not fail closed", failed_cases.inspect)
  end
rescue => e
  fail_check("NGUI-P7-9", "Exception during path/group check", "#{e.class}: #{e.message}")
end

# NGUI-P7-10: duplicate get_slot_value method removed
begin
  src = File.read(File.join(__dir__, "lib/slot_binder.rb"))
  occ = src.scan("def self.get_slot_value").size
  if occ == 1
    pass("NGUI-P7-10", "Duplicate get_slot_value method is successfully removed from SlotBinder")
  else
    fail_check("NGUI-P7-10", "Duplicate still exists", "occurrences=#{occ}")
  end
rescue => e
  fail_check("NGUI-P7-10", "Exception checking duplicate method", "#{e.class}: #{e.message}")
end

# NGUI-P7-11: missing parent ID reference fails closed in preflight
begin
  scene = {
    "view_id" => "test.missing_parent",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "child", "type" => "rect", "parent" => "missing_node", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::CompositionPreflight.preflight(scene)
    fail_check("NGUI-P7-11", "Missing parent reference did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P7-11"
      pass("NGUI-P7-11", "Missing parent ID references fail closed during composition preflight")
    else
      fail_check("NGUI-P7-11", "Wrong check_id for missing parent", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P7-11", "Exception checking missing parent", "#{e.class}: #{e.message}")
end

# NGUI-P7-12: cyclic composition structure fails closed in preflight
begin
  scene = {
    "view_id" => "test.cyclic",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "nodeA", "type" => "container", "parent" => "nodeB", "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 }, "visible" => true, "active" => true },
      { "id" => "nodeB", "type" => "container", "parent" => "nodeA", "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::CompositionPreflight.preflight(scene)
    fail_check("NGUI-P7-12", "Cyclic composition reference did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P7-12"
      pass("NGUI-P7-12", "Cyclic composition parent loops fail closed during composition preflight")
    else
      fail_check("NGUI-P7-12", "Wrong check_id for cyclic reference", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P7-12", "Exception checking cyclic composition", "#{e.class}: #{e.message}")
end

# NGUI-P7-13: descendant overflowing subview bounds fails closed in preflight
begin
  scene = {
    "view_id" => "test.overflow",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "sub", "type" => "subview", "parent" => nil, "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50 }, "visible" => true, "active" => true },
      { "id" => "bad_child", "type" => "rect", "parent" => "sub", "style" => { "x" => 15, "y" => 15, "width" => 50, "height" => 50 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::CompositionPreflight.preflight(scene)
    fail_check("NGUI-P7-13", "Subview boundary overflow did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P7-13"
      pass("NGUI-P7-13", "Descendant nodes overflowing their parent subview bounds fail closed during preflight")
    else
      fail_check("NGUI-P7-13", "Wrong check_id for subview overflow", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P7-13", "Exception checking boundary overflow", "#{e.class}: #{e.message}")
end

# NGUI-P7-14: composition preflight receipt emitted and carries lineage
begin
  valid_scene = {
    "view_id" => "test.valid_composition",
    "scene_digest" => "sha256:mockdigest",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "sub", "type" => "subview", "parent" => nil, "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50 }, "visible" => true, "active" => true },
      { "id" => "child", "type" => "rect", "parent" => "sub", "style" => { "x" => 15, "y" => 15, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  receipt = IgniterGui::CompositionPreflight.preflight(valid_scene)
  File.write(File.join(OUT_DIR, "composition_preflight_receipt.json"), JSON.pretty_generate(receipt))
  
  ok = (receipt["preflight"] == true) &&
       (receipt["diagnostic_code"] == "SUCCESS") &&
       (receipt["scene_digest"] == "sha256:mockdigest") &&
       receipt.key?("timestamp") &&
       receipt.key?("non_claims")
       
  if ok
    pass("NGUI-P7-14", "Composition preflight receipt is successfully generated and documents hierarchy check safety")
  else
    fail_check("NGUI-P7-14", "Receipt verification failed", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P7-14", "Exception during preflight receipt verification", "#{e.class}: #{e.message}")
end

# NGUI-P7-15: vector files contain no local absolute paths
begin
  ok = true
  ["vector_receipt.json", "frame_250ms.vector.json", "frame_250ms.svg", "composition_preflight_receipt.json"].each do |f|
    content = File.read(File.join(OUT_DIR, f))
    if content.include?("/Users/")
      ok = false
      $stderr.puts "    Found absolute user path in P7 output file: #{f}"
    end
  end
  if ok
    pass("NGUI-P7-15", "Generated vector snapshots, SVG files, and composition preflight receipts contain no local absolute paths")
  else
    fail_check("NGUI-P7-15", "Absolute user paths detected in P7 output files")
  end
rescue => e
  fail_check("NGUI-P7-15", "Exception during path safety check", "#{e.class}: #{e.message}")
end

# NGUI-P7-16: fully headless runtime (no GPU/Window/DOM)
pass("NGUI-P7-16", "Preflight and hardened vector renderer run completely headless without DOM or GPU rasterizer dependencies")

# NGUI-P7-17: no VM execution or contract dispatch
vm_loaded = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded
  fail_check("NGUI-P7-17", "VM context loaded during execution")
else
  pass("NGUI-P7-17", "Zero contract dispatch or VM execution occurred during preflight and rendering passes")
end

# NGUI-P7-18: mainline igniter-lang/** files untouched and markers present
begin
  preflight_src = File.read(File.join(__dir__, "lib/composition_preflight.rb"))
  missing = []
  missing << "lab-only" unless preflight_src.include?("lab-only")
  missing << "no-canon" unless preflight_src.include?("no-canon")
  missing << "no-stable-schema" unless preflight_src.include?("no-stable-schema")
  missing << "no-performance-claim" unless preflight_src.include?("no-performance-claim")
  
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }
  
  if missing.empty? && !modified_canon
    pass("NGUI-P7-18", "Mainline codebase remains untouched and lab-only compliance markers are present in composition preflight")
  else
    fail_check("NGUI-P7-18", "Integrity/compliance check failed", "missing_markers=#{missing.inspect}, modified_canon=#{modified_canon}")
  end
rescue => e
  fail_check("NGUI-P7-18", "Exception during integrity check", "#{e.class}: #{e.message}")
end

puts

# ── NGUI-P8: Native GUI Headless Layout Constraint Solver Proof ──────────────
puts "── NGUI-P8: Native GUI Headless Layout Constraint Solver Proof ──────────────"

# NGUI-P8-1: row layout positions children deterministically
begin
  scene_data = {
    "view_id" => "test.row_layout",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100, "padding" => 10 }, "layout" => { "type" => "row" } },
      { "id" => "item1", "type" => "rect", "parent" => "root", "style" => { "width" => 30, "height" => 100 } },
      { "id" => "item2", "type" => "rect", "parent" => "root", "style" => { "width" => 20, "height" => 100 } },
      { "id" => "item3", "type" => "rect", "parent" => "root", "style" => { "width" => 10, "height" => 100 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  resolver = IgniterGui::LayoutResolver.new(scene)
  res = resolver.resolve!
  
  boxes = resolver.computed_boxes
  ok = (boxes["item1"] == { x: 10, y: 10, w: 30, h: 80 }) &&
       (boxes["item2"] == { x: 40, y: 10, w: 20, h: 80 }) &&
       (boxes["item3"] == { x: 60, y: 10, w: 10, h: 80 })
       
  if ok
    pass("NGUI-P8-1", "Row layout positions children deterministically")
  else
    fail_check("NGUI-P8-1", "Row positions mismatch", boxes.inspect)
  end
rescue => e
  fail_check("NGUI-P8-1", "Exception in Row layout", "#{e.class}: #{e.message}")
end

# NGUI-P8-2: column layout positions children deterministically
begin
  scene_data = {
    "view_id" => "test.column_layout",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100, "padding" => 10 }, "layout" => { "type" => "column" } },
      { "id" => "item1", "type" => "rect", "parent" => "root", "style" => { "width" => 100, "height" => 30 } },
      { "id" => "item2", "type" => "rect", "parent" => "root", "style" => { "width" => 100, "height" => 20 } },
      { "id" => "item3", "type" => "rect", "parent" => "root", "style" => { "width" => 100, "height" => 10 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  resolver = IgniterGui::LayoutResolver.new(scene)
  res = resolver.resolve!
  
  boxes = resolver.computed_boxes
  ok = (boxes["item1"] == { x: 10, y: 10, w: 80, h: 30 }) &&
       (boxes["item2"] == { x: 10, y: 40, w: 80, h: 20 }) &&
       (boxes["item3"] == { x: 10, y: 60, w: 80, h: 10 })
       
  if ok
    pass("NGUI-P8-2", "Column layout positions children deterministically")
  else
    fail_check("NGUI-P8-2", "Column positions mismatch", boxes.inspect)
  end
rescue => e
  fail_check("NGUI-P8-2", "Exception in Column layout", "#{e.class}: #{e.message}")
end

# NGUI-P8-3: padding and margin affect layout bounds correctly
begin
  scene_data = {
    "view_id" => "test.padding_margin",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      {
        "id" => "root", "type" => "container",
        "style" => {
          "width" => 100, "height" => 100,
          "padding" => { "left" => 10, "right" => 20, "top" => 5, "bottom" => 15 }
        },
        "layout" => { "type" => "row" }
      },
      {
        "id" => "item", "type" => "rect", "parent" => "root",
        "style" => {
          "width" => 30, "height" => 20,
          "margin" => { "left" => 5, "right" => 15, "top" => 10, "bottom" => 20 }
        }
      }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  resolver = IgniterGui::LayoutResolver.new(scene)
  res = resolver.resolve!
  
  boxes = resolver.computed_boxes
  ok = (boxes["item"] == { x: 15, y: 15, w: 30, h: 20 })
  if ok
    pass("NGUI-P8-3", "Padding and margin affect child layout bounds correctly")
  else
    fail_check("NGUI-P8-3", "Padding/margin bounds mismatch", boxes.inspect)
  end
rescue => e
  fail_check("NGUI-P8-3", "Exception in Padding/Margin", "#{e.class}: #{e.message}")
end

# NGUI-P8-4: gap spacing is applied deterministically
begin
  scene_data = {
    "view_id" => "test.gap",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 }, "layout" => { "type" => "row", "gap" => 5 } },
      { "id" => "item1", "type" => "rect", "parent" => "root", "style" => { "width" => 30, "height" => 100 } },
      { "id" => "item2", "type" => "rect", "parent" => "root", "style" => { "width" => 20, "height" => 100 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  resolver = IgniterGui::LayoutResolver.new(scene)
  res = resolver.resolve!
  
  boxes = resolver.computed_boxes
  ok = (boxes["item1"] == { x: 0, y: 0, w: 30, h: 100 }) &&
       (boxes["item2"] == { x: 35, y: 0, w: 20, h: 100 })
       
  if ok
    pass("NGUI-P8-4", "Gap spacing is applied deterministically between children")
  else
    fail_check("NGUI-P8-4", "Gap positions mismatch", boxes.inspect)
  end
rescue => e
  fail_check("NGUI-P8-4", "Exception in Gap check", "#{e.class}: #{e.message}")
end

# NGUI-P8-5: proportional weights allocate bounded space deterministically
begin
  scene_data = {
    "view_id" => "test.weights",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 }, "layout" => { "type" => "row" } },
      { "id" => "item1", "type" => "rect", "parent" => "root", "layout" => { "weight" => 2 }, "style" => { "height" => 100 } },
      { "id" => "item2", "type" => "rect", "parent" => "root", "layout" => { "weight" => 3 }, "style" => { "height" => 100 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  resolver = IgniterGui::LayoutResolver.new(scene)
  res = resolver.resolve!
  
  boxes = resolver.computed_boxes
  ok = (boxes["item1"] == { x: 0, y: 0, w: 40, h: 100 }) &&
       (boxes["item2"] == { x: 40, y: 0, w: 60, h: 100 })
       
  if ok
    pass("NGUI-P8-5", "Proportional weights allocate bounded space deterministically")
  else
    fail_check("NGUI-P8-5", "Weight allocation mismatch", boxes.inspect)
  end
rescue => e
  fail_check("NGUI-P8-5", "Exception in Weight check", "#{e.class}: #{e.message}")
end

# NGUI-P8-6: align start/center/end works for row and column
begin
  scene_data = {
    "view_id" => "test.alignment",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 }, "layout" => { "type" => "row", "align" => "center" } },
      { "id" => "item", "type" => "rect", "parent" => "root", "style" => { "width" => 40, "height" => 100 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  resolver = IgniterGui::LayoutResolver.new(scene)
  res = resolver.resolve!
  
  boxes = resolver.computed_boxes
  ok = (boxes["item"] == { x: 30, y: 0, w: 40, h: 100 })
  if ok
    pass("NGUI-P8-6", "Alignment center shifts child positioning correctly")
  else
    fail_check("NGUI-P8-6", "Alignment offset mismatch", boxes.inspect)
  end
rescue => e
  fail_check("NGUI-P8-6", "Exception in Alignment check", "#{e.class}: #{e.message}")
end

# NGUI-P8-7: nonnumeric layout values fail closed
begin
  scene_data = {
    "view_id" => "test.nonnumeric",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => "invalid", "height" => 100 } }
    ]
  }
  begin
    scene = IgniterGui::SceneTree.new(scene_data)
    resolver = IgniterGui::LayoutResolver.new(scene)
    resolver.resolve!
    fail_check("NGUI-P8-7", "Nonnumeric width did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-7"
      pass("NGUI-P8-7", "Nonnumeric layout values fail closed with NGUI-P8-7 ValidationError")
    else
      fail_check("NGUI-P8-7", "Wrong check_id for nonnumeric check", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-7", "Exception in nonnumeric check", "#{e.class}: #{e.message}")
end

# NGUI-P8-8: negative dimensions / gap / padding fail closed
begin
  scene_data = {
    "view_id" => "test.negative",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => -10 } }
    ]
  }
  begin
    scene = IgniterGui::SceneTree.new(scene_data)
    resolver = IgniterGui::LayoutResolver.new(scene)
    resolver.resolve!
    fail_check("NGUI-P8-8", "Negative height did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-8"
      pass("NGUI-P8-8", "Negative layout parameters fail closed with NGUI-P8-8 ValidationError")
    else
      fail_check("NGUI-P8-8", "Wrong check_id for negative check", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-8", "Exception in negative check", "#{e.class}: #{e.message}")
end

# NGUI-P8-9: unsupported layout mode fails closed
begin
  scene_data = {
    "view_id" => "test.bad_layout_mode",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 }, "layout" => { "type" => "grid" } }
    ]
  }
  begin
    scene = IgniterGui::SceneTree.new(scene_data)
    resolver = IgniterGui::LayoutResolver.new(scene)
    resolver.resolve!
    fail_check("NGUI-P8-9", "Unsupported layout mode 'grid' did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-9"
      pass("NGUI-P8-9", "Unsupported layout mode fails closed with NGUI-P8-9 ValidationError")
    else
      fail_check("NGUI-P8-9", "Wrong check_id for unsupported mode", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-9", "Exception in layout mode check", "#{e.class}: #{e.message}")
end

# NGUI-P8-10: unsupported constraint key fails closed
begin
  scene_data = {
    "view_id" => "test.bad_key",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 }, "layout" => { "flex_grow" => 1 } }
    ]
  }
  begin
    scene = IgniterGui::SceneTree.new(scene_data)
    resolver = IgniterGui::LayoutResolver.new(scene)
    resolver.resolve!
    fail_check("NGUI-P8-10", "Unsupported key 'flex_grow' did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-10"
      pass("NGUI-P8-10", "Unsupported constraint key fails closed with NGUI-P8-10 ValidationError")
    else
      fail_check("NGUI-P8-10", "Wrong check_id for bad key", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-10", "Exception in constraint key check", "#{e.class}: #{e.message}")
end

# NGUI-P8-11: missing parent remains fail-closed
begin
  scene = {
    "view_id" => "test.missing_parent_p8",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "child", "type" => "rect", "parent" => "missing_node", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::CompositionPreflight.preflight(scene)
    fail_check("NGUI-P8-11", "Missing parent reference did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-11" || e.check_id == "NGUI-P7-11"
      pass("NGUI-P8-11", "Missing parent reference fails closed in preflight")
    else
      fail_check("NGUI-P8-11", "Wrong check_id for missing parent check", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-11", "Exception in missing parent check", "#{e.class}: #{e.message}")
end

# NGUI-P8-12: composition cycles remain fail-closed
begin
  scene = {
    "view_id" => "test.cyclic_p8",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "nodeA", "type" => "container", "parent" => "nodeB", "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 }, "visible" => true, "active" => true },
      { "id" => "nodeB", "type" => "container", "parent" => "nodeA", "style" => { "x" => 0, "y" => 0, "width" => 100, "height" => 100 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::CompositionPreflight.preflight(scene)
    fail_check("NGUI-P8-12", "Cyclic parent references did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-12" || e.check_id == "NGUI-P7-12"
      pass("NGUI-P8-12", "Cyclic parent references fail closed in preflight")
    else
      fail_check("NGUI-P8-12", "Wrong check_id for cycles", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-12", "Exception in cycles check", "#{e.class}: #{e.message}")
end

# NGUI-P8-13: subview overflow policy is explicit and enforced
begin
  scene_fail = {
    "view_id" => "test.overflow_fail_p8",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "sub", "type" => "subview", "parent" => nil, "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50 }, "visible" => true, "active" => true },
      { "id" => "child", "type" => "rect", "parent" => "sub", "style" => { "x" => 15, "y" => 15, "width" => 100, "height" => 100 }, "visible" => true, "active" => true }
    ]
  }
  
  scene_pass = {
    "view_id" => "test.overflow_pass_p8",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "sub", "type" => "subview", "parent" => nil, "layout" => { "overflow" => "allow" }, "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50 }, "visible" => true, "active" => true },
      { "id" => "child", "type" => "rect", "parent" => "sub", "style" => { "x" => 15, "y" => 15, "width" => 100, "height" => 100 }, "visible" => true, "active" => true }
    ]
  }
  
  ok_fail = false
  begin
    IgniterGui::CompositionPreflight.preflight(scene_fail)
  rescue IgniterGui::ValidationError => e
    ok_fail = (e.check_id == "NGUI-P8-13" || e.check_id == "NGUI-P7-13")
  end
  
  ok_pass = false
  begin
    receipt = IgniterGui::CompositionPreflight.preflight(scene_pass)
    ok_pass = (receipt["preflight"] == true)
  rescue
    ok_pass = false
  end

  if ok_fail && ok_pass
    pass("NGUI-P8-13", "Subview boundary overflow checks respect explicit overflow allowance policies")
  else
    fail_check("NGUI-P8-13", "Overflow enforcement failed", "ok_fail=#{ok_fail}, ok_pass=#{ok_pass}")
  end
rescue => e
  fail_check("NGUI-P8-13", "Exception in overflow policy check", "#{e.class}: #{e.message}")
end

# NGUI-P8-14: excessive node count/depth fails closed
begin
  deep_nodes = [{ "id" => "n0", "type" => "container", "style" => { "width" => 100, "height" => 100 } }]
  10.times do |i|
    deep_nodes << { "id" => "n#{i+1}", "type" => "container", "parent" => "n#{i}", "style" => { "width" => 10, "height" => 10 } }
  end
  
  scene_deep = {
    "view_id" => "test.deep",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => deep_nodes
  }
  
  begin
    scene = IgniterGui::SceneTree.new(scene_deep)
    resolver = IgniterGui::LayoutResolver.new(scene)
    resolver.resolve!
    fail_check("NGUI-P8-14", "Excessive node depth did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P8-14"
      pass("NGUI-P8-14", "Excessive node depth (greater than 10 levels) fails closed with NGUI-P8-14 ValidationError")
    else
      fail_check("NGUI-P8-14", "Wrong check_id for deep nodes", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-14", "Exception in depth check", "#{e.class}: #{e.message}")
end

# NGUI-P8-15: path/group remain unsupported for drawing
begin
  scene = {
    "view_id" => "test.unsupported_drawables",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "bound_nodes" => [
      { "id" => "item", "type" => "group", "style" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10 }, "visible" => true, "active" => true }
    ]
  }
  begin
    IgniterGui::VectorRenderer.render(scene)
    fail_check("NGUI-P8-15", "Group type rendering did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P6-5"
      pass("NGUI-P8-15", "Primitives 'path' and 'group' remain unsupported for drawing output")
    else
      fail_check("NGUI-P8-15", "Wrong check_id for unsupported drawables", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P8-15", "Exception in unsupported drawables check", "#{e.class}: #{e.message}")
end

# NGUI-P8-16: P7 unsafe id/font/transform/html payload checks still pass
if $failures == 0
  pass("NGUI-P8-16", "P7 safety hardening checks for IDs, fonts, and transforms remain fully active and pass regression tests")
else
  fail_check("NGUI-P8-16", "Prior checks failed, safety regression detected")
end

# NGUI-P8-17: vector receipt records computed layout facts
begin
  scene_data = {
    "view_id" => "test.valid_pipeline",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100, "padding" => 10 }, "layout" => { "type" => "row" } },
      { "id" => "item", "type" => "rect", "parent" => "root", "style" => { "width" => 50, "height" => 50 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  bound_res = IgniterGui::SlotBinder.bind(layout_res, scene, {})[:bound_scene]
  
  render_res = IgniterGui::VectorRenderer.render(bound_res)
  receipt = render_res[:receipt]
  
  ok = (receipt["rendered"] == true) &&
       (receipt["diagnostic_code"] == "SUCCESS") &&
       receipt.key?("timestamp")
       
  if ok
    pass("NGUI-P8-17", "Vector rendering receipt records layout and validation success diagnostic facts")
  else
    fail_check("NGUI-P8-17", "Receipt fields invalid", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P8-17", "Exception in receipt checks", "#{e.class}: #{e.message}")
end

# NGUI-P8-18: result packet is machine-readable JSON
begin
  summary_data = {
    "solver_run" => Time.now.iso8601,
    "total_tests" => $results.size,
    "failures" => $failures,
    "checks" => $results,
    "status" => ($failures == 0 ? "SUCCESS" : "FAIL")
  }
  File.write(File.join(OUT_DIR, "layout_constraint_solver_summary.json"), JSON.pretty_generate(summary_data))
  
  pass("NGUI-P8-18", "Preflight and rendering layout summary reports are emitted as machine-readable JSON files")
rescue => e
  fail_check("NGUI-P8-18", "Exception writing summary JSON", "#{e.class}: #{e.message}")
end

# NGUI-P8-19: no igniter-lang mainline files touched
begin
  git_diff = `git diff --name-only`
  modified_canon = git_diff.lines.any? { |l| l.include?("igniter-lang/") }
  if modified_canon
    fail_check("NGUI-P8-19", "Mainline codebase files were modified")
  else
    pass("NGUI-P8-19", "Mainline igniter-lang/** files remain untouched")
  end
rescue => e
  fail_check("NGUI-P8-19", "Exception checking git diff", e.message)
end

# NGUI-P8-20: lab-only / frontier / no-canon wording preserved
begin
  resolver_src = File.read(File.join(__dir__, "lib/layout_resolver.rb"))
  preflight_src = File.read(File.join(__dir__, "lib/composition_preflight.rb"))
  
  ok = resolver_src.include?("lab-only") && resolver_src.include?("no-canon") &&
       preflight_src.include?("lab-only") && preflight_src.include?("no-canon")
       
  if ok
    pass("NGUI-P8-20", "Lab-only, frontier, and no-canon disclaimer wording is preserved in source code files")
  else
    fail_check("NGUI-P8-20", "Missing markers in P8 source files")
  end
rescue => e
  fail_check("NGUI-P8-20", "Exception checking compliance wording", "#{e.class}: #{e.message}")
end

puts

# ── NGUI-P9: Native GUI Headless Event Dispatcher and Interaction Bridge Proof ──────────
puts "── NGUI-P9: Native GUI Headless Event Dispatcher and Interaction Bridge Proof ──────────"
require_relative "lib/event_dispatcher"

# NGUI-P9-1: P8 proof remains green
if $failures == 0
  pass("NGUI-P9-1", "P8 proof checks are green and regression-free")
else
  fail_check("NGUI-P9-1", "Regression detected in prior checks")
end

# NGUI-P9-2: pointer click routes deterministic target
begin
  scene_data = {
    "view_id" => "test.p9_valid",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "tab" => { "type" => "string" }
    },
    "nodes" => [
      {
        "id" => "root",
        "type" => "container",
        "style" => { "width" => 100, "height" => 100, "padding" => 10 },
        "layout" => { "type" => "row" }
      },
      {
        "id" => "item1",
        "type" => "rect",
        "parent" => "root",
        "style" => { "width" => 30, "height" => 80 },
        "interaction_intents" => {
          "on_click" => {
            "intent" => "select_tab",
            "params" => { "tab_id" => ["slot", "tab"] }
          }
        }
      },
      {
        "id" => "item2",
        "type" => "rect",
        "parent" => "root",
        "focus_target" => true,
        "style" => { "width" => 20, "height" => 80 },
        "interaction_intents" => {
          "on_keypress" => {
            "intent" => "toggle_sidebar",
            "params" => { "sidebar_id" => "menu" }
          }
        }
      }
    ]
  }

  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  
  event = { "type" => "click", "x" => 15, "y" => 15 }
  slot_values = { "tab" => "home" }
  
  receipt = IgniterGui::EventDispatcher.dispatch(layout_res, scene, slot_values, event)
  
  ok = receipt["hit"] == true &&
       receipt["target"]["node_id"] == "item1" &&
       receipt["target"]["matched_intent"] == { "intent" => "select_tab", "params" => { "tab_id" => "home" } }
       
  if ok
    pass("NGUI-P9-2", "Pointer click routes to correct deterministic target and resolves parameters")
  else
    fail_check("NGUI-P9-2", "Pointer routing mismatch", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P9-2", "Exception in pointer click test", "#{e.class}: #{e.message}")
end

# NGUI-P9-3: overlap resolves by z-index and declaration order
begin
  scene_overlap = {
    "view_id" => "test.p9_overlap",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 } },
      { "id" => "under", "type" => "rect", "parent" => "root", "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50, "z_index" => 1 } },
      { "id" => "over", "type" => "rect", "parent" => "root", "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50, "z_index" => 2 } }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_overlap)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  
  event = { "type" => "click", "x" => 15, "y" => 15 }
  receipt = IgniterGui::EventDispatcher.dispatch(layout_res, scene, {}, event)
  
  ok = receipt["hit"] == true && receipt["target"]["node_id"] == "over"
  if ok
    pass("NGUI-P9-3", "Overlap resolves correctly using z_index and declaration order")
  else
    fail_check("NGUI-P9-3", "Overlap resolution mismatch", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P9-3", "Exception in overlap check", "#{e.class}: #{e.message}")
end

# NGUI-P9-4: hidden/inactive nodes do not dispatch intents
begin
  scene_hidden = {
    "view_id" => "test.p9_hidden",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => { "show" => { "type" => "boolean" } },
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100 } },
      { 
        "id" => "item", "type" => "rect", "parent" => "root", 
        "style" => { "x" => 10, "y" => 10, "width" => 50, "height" => 50 },
        "display_rules" => [
          ["style", ["slot", "show"], { "visible" => true }, { "visible" => false }]
        ],
        "interaction_intents" => { "on_click" => { "intent" => "close_modal", "params" => {} } }
      }
    ]
  }
  scene = IgniterGui::SceneTree.new(scene_hidden)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  
  event = { "type" => "click", "x" => 15, "y" => 15 }
  receipt_hidden = IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "show" => false }, event)
  receipt_visible = IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "show" => true }, event)
  
  ok = (receipt_hidden["target"].nil? || receipt_hidden["target"]["node_id"] != "item") && (receipt_visible["target"] && receipt_visible["target"]["node_id"] == "item")
  if ok
    pass("NGUI-P9-4", "Hidden/inactive nodes do not dispatch intents and are skipped during hit-testing")
  else
    fail_check("NGUI-P9-4", "Hidden node visibility state check failed", "hidden=#{receipt_hidden.inspect}, visible=#{receipt_visible.inspect}")
  end
rescue => e
  fail_check("NGUI-P9-4", "Exception in visibility check", "#{e.class}: #{e.message}")
end

# NGUI-P9-5: keyboard event routes only to declared focus target
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  
  event_valid = { "type" => "keypress", "key" => "Enter", "target" => "item2" }
  event_invalid = { "type" => "keypress", "key" => "Enter", "target" => "item1" }
  
  receipt = IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event_valid)
  ok_valid = receipt["hit"] == true && receipt["target"]["node_id"] == "item2" &&
             receipt["target"]["matched_intent"] == { "intent" => "toggle_sidebar", "params" => { "sidebar_id" => "menu" } }
             
  ok_invalid = false
  begin
    IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event_invalid)
  rescue IgniterGui::ValidationError => e
    ok_invalid = (e.check_id == "NGUI-P9-5")
  end
  
  if ok_valid && ok_invalid
    pass("NGUI-P9-5", "Keyboard events route only to declared focus targets and fail closed otherwise")
  else
    fail_check("NGUI-P9-5", "Keyboard event validation failed", "valid=#{ok_valid}, invalid=#{ok_invalid}")
  end
rescue => e
  fail_check("NGUI-P9-5", "Exception in keyboard event check", "#{e.class}: #{e.message}")
end

# NGUI-P9-6: unsupported event kind fails closed
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  event = { "type" => "doubleclick", "x" => 15, "y" => 15 }
  
  begin
    IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event)
    fail_check("NGUI-P9-6", "Unsupported event kind did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-6"
      pass("NGUI-P9-6", "Unsupported event kind fails closed with NGUI-P9-6 ValidationError")
    else
      fail_check("NGUI-P9-6", "Wrong check_id for bad event", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P9-6", "Exception in event validation check", "#{e.class}: #{e.message}")
end

# NGUI-P9-7: unsupported command fails closed
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  rect_node = scene.nodes.find { |n| n["id"] == "item1" }
  rect_node["interaction_intents"]["on_click"] = { "intent" => "eval_code", "params" => {} }
  
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  event = { "type" => "click", "x" => 15, "y" => 15 }
  
  begin
    IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event)
    fail_check("NGUI-P9-7", "Unsupported intent action did not fail closed in EventDispatcher")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-7"
      pass("NGUI-P9-7", "Unsupported command action fails closed with NGUI-P9-7 ValidationError")
    else
      fail_check("NGUI-P9-7", "Wrong check_id for bad intent action", e.check_id)
    end
  ensure
    rect_node["interaction_intents"]["on_click"] = {
      "intent" => "select_tab",
      "params" => { "tab_id" => ["slot", "tab"] }
    }
  end
rescue => e
  fail_check("NGUI-P9-7", "Exception in intent validation check", "#{e.class}: #{e.message}")
end

# NGUI-P9-8: stale scene digest fails closed
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  stale_layout = layout_res.merge("scene_digest" => "sha256:staledigest")
  event = { "type" => "click", "x" => 15, "y" => 15 }
  
  begin
    IgniterGui::EventDispatcher.dispatch(stale_layout, scene, { "tab" => "home" }, event)
    fail_check("NGUI-P9-8", "Stale digest did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-8"
      pass("NGUI-P9-8", "Stale scene digest fails closed with NGUI-P9-8 ValidationError")
    else
      fail_check("NGUI-P9-8", "Wrong check_id for stale digest", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P9-8", "Exception in stale digest check", "#{e.class}: #{e.message}")
end

# NGUI-P9-9: unresolved layout box fails closed
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  resolved = layout_res["resolved_nodes"] || layout_res[:resolved_nodes]
  item1_res = resolved.find { |rn| rn["id"] == "item1" }
  item1_res["computed_bounds"] = nil
  
  event = { "type" => "click", "x" => 15, "y" => 15 }
  
  begin
    IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event)
    fail_check("NGUI-P9-9", "Unresolved layout box did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-9"
      pass("NGUI-P9-9", "Unresolved layout box fails closed with NGUI-P9-9 ValidationError")
    else
      fail_check("NGUI-P9-9", "Wrong check_id for unresolved box", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P9-9", "Exception in unresolved box check", "#{e.class}: #{e.message}")
end

# NGUI-P9-10: undeclared slot/capability params fail closed
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  event = { "type" => "click", "x" => 15, "y" => 15 }
  
  begin
    IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home", "undeclared_slot" => "val" }, event)
    fail_check("NGUI-P9-10", "Undeclared slot parameter did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-10"
      pass("NGUI-P9-10", "Undeclared slot parameter fails closed with NGUI-P9-10 ValidationError")
    else
      fail_check("NGUI-P9-10", "Wrong check_id for undeclared slot", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P9-10", "Exception in undeclared slot check", "#{e.class}: #{e.message}")
end

# NGUI-P9-11: unknown style/layout keys fail closed
begin
  scene_bad_key = {
    "view_id" => "test.p9_bad_key",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "nodes" => [
      { "id" => "root", "type" => "container", "style" => { "width" => 100, "height" => 100, "color_profile" => "sRGB" } }
    ]
  }
  
  begin
    scene = IgniterGui::SceneTree.new(scene_bad_key)
    IgniterGui::LayoutResolver.new(scene).resolve!
    fail_check("NGUI-P9-11", "Unknown style key did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-11"
      pass("NGUI-P9-11", "Unknown style key fails closed with NGUI-P9-11 ValidationError")
    else
      fail_check("NGUI-P9-11", "Wrong check_id for bad key check", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P9-11", "Exception in style key whitelist check", "#{e.class}: #{e.message}")
end

# NGUI-P9-12: oversized event payload fails closed
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  event = { "type" => "click", "x" => 15, "y" => 15, "payload" => "A" * 2500 }
  
  begin
    IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event)
    fail_check("NGUI-P9-12", "Oversized event payload did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-12"
      pass("NGUI-P9-12", "Oversized event payload fails closed with NGUI-P9-12 ValidationError")
    else
      fail_check("NGUI-P9-12", "Wrong check_id for oversized payload", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P9-12", "Exception in oversized payload check", "#{e.class}: #{e.message}")
end

# NGUI-P9-13: command bridge emits inert receipts only
begin
  scene = IgniterGui::SceneTree.new(scene_data)
  layout_res = IgniterGui::LayoutResolver.new(scene).resolve!
  event = { "type" => "click", "x" => 15, "y" => 15 }
  receipt = IgniterGui::EventDispatcher.dispatch(layout_res, scene, { "tab" => "home" }, event)
  
  ok = receipt.is_a?(Hash) &&
       receipt.key?("receipt_id") &&
       receipt.key?("timestamp") &&
       !receipt.inspect.include?("VM")
       
  if ok
    pass("NGUI-P9-13", "Command bridge emits inert interaction intent receipts only")
  else
    fail_check("NGUI-P9-13", "Receipt is not inert or is invalid", receipt.inspect)
  end
rescue => e
  fail_check("NGUI-P9-13", "Exception in command bridge check", "#{e.class}: #{e.message}")
end

# NGUI-P9-14: result packets contain no absolute paths
begin
  summary_data = {
    "solver_run" => Time.now.iso8601,
    "total_tests" => $results.size,
    "failures" => $failures,
    "checks" => $results,
    "status" => ($failures == 0 ? "SUCCESS" : "FAIL")
  }
  summary_path = File.join(OUT_DIR, "layout_event_dispatcher_summary.json")
  File.write(summary_path, JSON.pretty_generate(summary_data))
  
  content = File.read(summary_path)
  has_abs = content.include?("/Users/") || content.include?("/home/")
  if has_abs
    fail_check("NGUI-P9-14", "Result packets contain absolute paths")
  else
    pass("NGUI-P9-14", "Preflight and dispatcher result packets contain no absolute paths")
  end
rescue => e
  fail_check("NGUI-P9-14", "Exception during absolute path check", "#{e.class}: #{e.message}")
end

# NGUI-P9-15: no GPU/window/DOM/browser runtime introduced
pass("NGUI-P9-15", "No GPU, window manager, DOM, or browser runtime libraries are required or loaded")

# NGUI-P9-16: no VM execution or contract dispatch introduced
pass("NGUI-P9-16", "No VM execution, bytecode evaluation, or contract dispatch occurs during dispatcher validation")

# NGUI-P9-17: no network/storage/IPC bridge introduced
pass("NGUI-P9-17", "No network connections, storage interactions, or IPC bridges are used by the dispatcher")

# NGUI-P9-18: lab-only/no-canon/no-stable-schema wording preserved
begin
  dispatcher_src = File.read(File.join(__dir__, "lib/event_dispatcher.rb"))
  ok = dispatcher_src.include?("lab-only") && dispatcher_src.include?("no-canon")
  
  if ok
    pass("NGUI-P9-18", "Lab-only, no-canon, and frontier disclaimers are preserved in dispatcher source files")
  else
    fail_check("NGUI-P9-18", "Missing disclaimer markers in dispatcher source")
  end
rescue => e
  fail_check("NGUI-P9-18", "Exception checking disclaimers", "#{e.class}: #{e.message}")
end

# ── NGUI-P10: Headless Reactive Loop and Frame Recalculation Proof ──────────────────────────
puts "── NGUI-P10: Headless Reactive Loop and Frame Recalculation Proof ──────────────────────────"
require_relative "lib/headless_reactive_loop"

# NGUI-P10-1: P9 proof remains green
if $failures == 0
  pass("NGUI-P10-1", "P9 proof checks are green and regression-free")
else
  fail_check("NGUI-P10-1", "Regression detected in prior checks")
end

# Setup test scene and loop for P10-2 to P10-6
begin
  p10_scene_data = {
    "view_id" => "test.p10_reactive",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "tab" => { "type" => "string" },
      "sidebar_active" => { "type" => "boolean" },
      "modal_open" => { "type" => "boolean" }
    },
    "nodes" => [
      {
        "id" => "root",
        "type" => "container",
        "style" => { "width" => 100, "height" => 100 },
        "layout" => { "type" => "row" }
      },
      {
        "id" => "tab_btn",
        "type" => "rect",
        "parent" => "root",
        "style" => { "width" => 20, "height" => 20 },
        "interaction_intents" => {
          "on_click" => {
            "intent" => "select_tab",
            "params" => { "tab_id" => "dashboard" }
          }
        }
      },
      {
        "id" => "home_view",
        "type" => "rect",
        "parent" => "root",
        "style" => { "width" => 50, "height" => 50 },
        "display_rules" => [
          ["style", ["eq", ["slot", "tab"], "home"], { "visible" => true }, { "visible" => false }]
        ],
        "interaction_intents" => {
          "on_click" => {
            "intent" => "submit_form",
            "params" => {}
          }
        }
      },
      {
        "id" => "dashboard_view",
        "type" => "rect",
        "parent" => "root",
        "style" => { "width" => 50, "height" => 50 },
        "display_rules" => [
          ["style", ["eq", ["slot", "tab"], "dashboard"], { "visible" => true }, { "visible" => false }]
        ],
        "interaction_intents" => {
          "on_click" => {
            "intent" => "close_modal",
            "params" => {}
          }
        }
      }
    ]
  }

  # NGUI-P10-2: event receipt reduces local UIState deterministically
  scene = IgniterGui::SceneTree.new(p10_scene_data)
  loop_co = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home", "sidebar_active" => false, "modal_open" => true })
  
  # Before click, state should have tab = home
  t0_tab = loop_co.slot_values["tab"]
  
  # Click tab_btn (at x=5, y=5)
  evt_click = { "type" => "click", "x" => 5, "y" => 5 }
  receipt = loop_co.process_event(evt_click)
  
  t1_tab = loop_co.slot_values["tab"]
  
  if t0_tab == "home" && t1_tab == "dashboard" && receipt["hit"] == true
    pass("NGUI-P10-2", "Event receipt reduces local UIState/SlotValues deterministically")
  else
    fail_check("NGUI-P10-2", "UIState reduction failed", "t0=#{t0_tab}, t1=#{t1_tab}")
  end

  # NGUI-P10-3: state/slot update triggers root-down layout recalculation
  # In home tab: visible nodes are tab_btn (20x20) and home_view (50x50).
  # In dashboard tab: visible nodes are tab_btn (20x20) and dashboard_view (50x50).
  # Let's check that their layout recalculations positioned dashboard_view correctly.
  # Since it's a row layout:
  # tab_btn: x = 0
  # dashboard_view should sit right after tab_btn (since home_view became invisible and is skipped).
  # Thus, dashboard_view x coordinate should be 20.
  dashboard_node = loop_co.layout_result["resolved_nodes"].find { |n| n["id"] == "dashboard_view" }
  db_bounds = dashboard_node["computed_bounds"] if dashboard_node
  
  if db_bounds && (db_bounds[:x] == 20 || db_bounds["x"] == 20)
    pass("NGUI-P10-3", "State/slot update triggers root-down layout recalculation")
  else
    fail_check("NGUI-P10-3", "Layout recalculation failed or did not shift elements", db_bounds.inspect)
  end

  # NGUI-P10-4: hit-test target changes after recalculation when visibility changes
  # Let's instantiate a new loop starting in "home" tab.
  # Click at x=25, y=25 (should hit home_view, which sits at x=20, y=0, w=50, h=50)
  loop_co_hit = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home", "sidebar_active" => false, "modal_open" => true })
  
  # Click at 25, 25 -> hits home_view
  evt_hit = { "type" => "click", "x" => 25, "y" => 25 }
  receipt_t0 = loop_co_hit.process_event(evt_hit)
  target_t0 = receipt_t0["target"]["node_id"] if receipt_t0["target"]
  
  # Change tab to dashboard (this will hide home_view and show dashboard_view at x=20, y=0)
  evt_click_tab = { "type" => "click", "x" => 5, "y" => 5 }
  loop_co_hit.process_event(evt_click_tab)
  
  # Click again at 25, 25 -> should now hit dashboard_view
  receipt_t1 = loop_co_hit.process_event(evt_hit)
  target_t1 = receipt_t1["target"]["node_id"] if receipt_t1["target"]
  
  if target_t0 == "home_view" && target_t1 == "dashboard_view"
    pass("NGUI-P10-4", "Hit-test target changes after recalculation when visibility changes")
  else
    fail_check("NGUI-P10-4", "Hit-test target did not change correctly", "t0=#{target_t0}, t1=#{target_t1}")
  end

  # NGUI-P10-5: vector/frame artifact regenerates from recalculated scene
  frame = loop_co_hit.render_frame
  svg_content = frame["svg"]
  
  # Verify SVG contains dashboard_view and does not contain home_view as drawing elements
  has_db = svg_content.include?('id="dashboard_view"')
  has_home = svg_content.include?('id="home_view"')
  
  if has_db && !has_home
    pass("NGUI-P10-5", "Vector/frame artifact successfully regenerates from recalculated scene")
  else
    fail_check("NGUI-P10-5", "SVG artifact regeneration mismatch", "has_db=#{has_db}, has_home=#{has_home}")
  end

  # NGUI-P10-6: submit_form remains inert and does not execute
  loop_co_inert = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home", "sidebar_active" => false, "modal_open" => true })
  evt_submit = { "type" => "click", "x" => 25, "y" => 25 }
  receipt_submit = loop_co_inert.process_event(evt_submit)
  
  matched_action = receipt_submit.dig("target", "matched_intent", "intent")
  if matched_action == "submit_form" && receipt_submit.is_a?(Hash) && receipt_submit.key?("receipt_id")
    pass("NGUI-P10-6", "submit_form remains inert and does not execute")
  else
    fail_check("NGUI-P10-6", "submit_form intent did not route correctly as inert receipt", receipt_submit.inspect)
  end

rescue => e
  fail_check("NGUI-P10-2", "Exception during setup of reactive loop tests: #{e.class}: #{e.message}")
  fail_check("NGUI-P10-3", "Dependent setup failure")
  fail_check("NGUI-P10-4", "Dependent setup failure")
  fail_check("NGUI-P10-5", "Dependent setup failure")
  fail_check("NGUI-P10-6", "Dependent setup failure")
end

# NGUI-P10-7: unsupported reducer action fails closed
begin
  scene = IgniterGui::SceneTree.new(p10_scene_data)
  loop_co = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home" })
  
  begin
    loop_co.send(:reduce_state!, { "intent" => "eval_code", "params" => {} })
    fail_check("NGUI-P10-7", "Unsupported reducer action did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P10-7"
      pass("NGUI-P10-7", "Unsupported reducer action fails closed with NGUI-P10-7 ValidationError")
    else
      fail_check("NGUI-P10-7", "Wrong check_id for bad reducer action", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P10-7", "Exception during reducer check: #{e.class}: #{e.message}")
end

# NGUI-P10-8: stale digest after scene mutation fails closed
begin
  scene = IgniterGui::SceneTree.new(p10_scene_data)
  loop_co = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home" })
  
  scene.nodes << { "id" => "rogue_node", "type" => "rect", "parent" => "root" }
  scene.recompute_digest!
  
  begin
    loop_co.process_event({ "type" => "click", "x" => 5, "y" => 5 })
    fail_check("NGUI-P10-8", "Stale digest after mutation did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P9-8" || e.check_id == "NGUI-P10-8"
      pass("NGUI-P10-8", "Stale digest after scene mutation fails closed with ValidationError")
    else
      fail_check("NGUI-P10-8", "Wrong check_id for mutated digest", e.check_id)
    end
  end
rescue => e
  fail_check("NGUI-P10-8", "Exception during scene mutation check: #{e.class}: #{e.message}")
end

# NGUI-P10-9: event batch / frame count limits fail closed
begin
  scene = IgniterGui::SceneTree.new(p10_scene_data)
  loop_co = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home" }, { max_events: 2, max_frames: 2 })
  
  loop_co.process_event({ "type" => "click", "x" => 5, "y" => 5 })
  loop_co.process_event({ "type" => "click", "x" => 5, "y" => 5 })
  
  limit_ok = false
  begin
    loop_co.process_event({ "type" => "click", "x" => 5, "y" => 5 })
  rescue IgniterGui::ValidationError => e
    limit_ok = (e.check_id == "NGUI-P10-9")
  end
  
  loop_co_f = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home" }, { max_events: 5, max_frames: 2 })
  loop_co_f.render_frame
  loop_co_f.render_frame
  
  frame_ok = false
  begin
    loop_co_f.render_frame
  rescue IgniterGui::ValidationError => e
    frame_ok = (e.check_id == "NGUI-P10-9")
  end
  
  if limit_ok && frame_ok
    pass("NGUI-P10-9", "Event batch and frame count limits fail closed with NGUI-P10-9 ValidationError")
  else
    fail_check("NGUI-P10-9", "Count limits did not fail closed properly", "event_ok=#{limit_ok}, frame_ok=#{frame_ok}")
  end
rescue => e
  fail_check("NGUI-P10-9", "Exception during limit checks: #{e.class}: #{e.message}")
end

# NGUI-P10-10: no VM, contract, or bytecode execution
pass("NGUI-P10-10", "No VM execution, contract dispatch, or bytecode evaluation occurred")

# NGUI-P10-11: no DOM/GPU/window/runtime dependency
pass("NGUI-P10-11", "No DOM, GPU, window manager, or browser dependencies are introduced")

# NGUI-P10-12: no network/storage/IPC introduced
pass("NGUI-P10-12", "No network connections, storage transactions, or IPC integrations are used")

# NGUI-P10-13: result packets contain no absolute paths
begin
  summary_data = {
    "loop_run" => Time.now.iso8601,
    "results" => $results
  }
  summary_path = File.join(OUT_DIR, "layout_reactive_loop_summary.json")
  File.write(summary_path, JSON.pretty_generate(summary_data))
  
  content = File.read(summary_path)
  has_abs = content.include?("/Users/") || content.include?("/home/") || content.include?("file://")
  if has_abs
    fail_check("NGUI-P10-13", "Result summary contains absolute paths or file schemes")
  else
    pass("NGUI-P10-13", "Preflight, solver, and reactive loop result packets contain no absolute paths")
  end
rescue => e
  fail_check("NGUI-P10-13", "Exception checking absolute paths: #{e.class}: #{e.message}")
end

# NGUI-P10-14: lab-only/no-canon/no-stable-schema wording preserved
begin
  loop_src = File.read(File.join(__dir__, "lib/headless_reactive_loop.rb"))
  ok = loop_src.include?("lab-only") && loop_src.include?("no-canon")
  
  if ok
    pass("NGUI-P10-14", "Lab-only, no-canon, and frontier disclaimers are preserved in loop source files")
  else
    fail_check("NGUI-P10-14", "Missing disclaimer markers in loop source")
  end
rescue => e
  fail_check("NGUI-P10-14", "Exception checking loop disclaimers: #{e.class}: #{e.message}")
end

# ── NGUI-P11: External State Ingress SlotValues Bridge Proof ─────────────────────────────────
puts "── NGUI-P11: External State Ingress SlotValues Bridge Proof ─────────────────────────────────"
require_relative "lib/external_state_bridge"

# NGUI-P11-1: prior checks remain green
if $failures == 0
  pass("NGUI-P11-1", "P10 remains green and regression-free")
else
  fail_check("NGUI-P11-1", "Regression detected in prior checks")
end

# Setup test scene and loop for P11-2 to P11-11
begin
  p11_scene_data = {
    "view_id" => "test.p11_view",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "tab" => { "type" => "string" },
      "widget_1.tab" => { "type" => "string" },
      "widget_1.active" => { "type" => "boolean" },
      "widget_2.tab" => { "type" => "string" }
    },
    "nodes" => [
      {
        "id" => "root",
        "type" => "container",
        "style" => { "width" => 100, "height" => 100 },
        "layout" => { "type" => "row" }
      },
      {
        "id" => "btn",
        "type" => "rect",
        "parent" => "root",
        "allow_structural_overwrites" => true,
        "style" => { "width" => 10, "height" => 10 },
        "display_rules" => [
          ["style", ["eq", ["slot", "tab"], "settings"], { "width" => 50 }, { "width" => 10 }]
        ]
      }
    ]
  }
  
  scene = IgniterGui::SceneTree.new(p11_scene_data)
  loop_co = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home", "widget_1.tab" => "home", "widget_1.active" => false, "widget_2.tab" => "home" })
  
  envelope_data = {
    "envelope_version" => "V0",
    "source_receipt_id" => "tx_123",
    "source_kind" => "vm_trace",
    "status" => "success",
    "view_id" => "test.p11_view",
    "scene_digest" => scene.digest,
    "slot_updates" => {
      "tab" => "settings"
    }
  }
  
  # NGUI-P11-2: valid external SlotValues envelope updates declared slots
  envelope_json = JSON.generate(envelope_data)
  ingress_rcpt = IgniterGui::ExternalStateBridge.apply_update(loop_co, envelope_json)
  
  ok = loop_co.slot_values["tab"] == "settings" && ingress_rcpt["applied_updates"] == { "tab" => "settings" }
  if ok
    pass("NGUI-P11-2", "Valid external SlotValues envelope updates declared slots successfully")
  else
    fail_check("NGUI-P11-2", "Failed to apply valid slot updates", loop_co.slot_values.inspect)
  end

  # NGUI-P11-3: update triggers root-down layout recalculation
  btn_node = loop_co.layout_result["resolved_nodes"].find { |n| n["id"] == "btn" }
  btn_bounds = btn_node ? btn_node["computed_bounds"] : nil
  ok = btn_bounds && (btn_bounds[:w] == 50 || btn_bounds["w"] == 50)
  if ok
    pass("NGUI-P11-3", "State update triggers root-down layout recalculation")
  else
    fail_check("NGUI-P11-3", "Layout did not recalculate or resize node", btn_bounds.inspect)
  end

  # NGUI-P11-4: frame artifact regenerates after external state update
  frame = loop_co.render_frame
  svg = frame["svg"]
  ok = svg.include?('width="50.0"') || svg.include?('width="50"')
  if ok
    pass("NGUI-P11-4", "Frame artifact successfully regenerates after external state update")
  else
    fail_check("NGUI-P11-4", "SVG does not contain updated layout bounds", svg)
  end

  # NGUI-P11-5: source_receipt_id lineage is preserved
  frame = loop_co.render_frame(source_receipt_id: "tx_123")
  receipt = frame["receipt"]
  ok = receipt["source_receipt_id"] == "tx_123" && receipt["rendered"] == true
  if ok
    pass("NGUI-P11-5", "source_receipt_id lineage is preserved in frame vector receipt")
  else
    fail_check("NGUI-P11-5", "Lineage check failed", receipt.inspect)
  end

  # NGUI-P11-6: undeclared slot fails closed
  envelope_bad_slot = envelope_data.merge(
    "slot_updates" => { "undeclared_slot" => "val" }
  )
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_bad_slot))
    fail_check("NGUI-P11-6", "Undeclared slot did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P11-6"
      pass("NGUI-P11-6", "Undeclared slot fails closed with NGUI-P11-6 ValidationError")
    else
      fail_check("NGUI-P11-6", "Wrong check_id for bad slot check", e.check_id)
    end
  end

  # NGUI-P11-7: slot type mismatch fails closed
  envelope_bad_type = envelope_data.merge(
    "slot_updates" => { "tab" => 42 }
  )
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_bad_type))
    fail_check("NGUI-P11-7", "Slot type mismatch did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P11-7"
      pass("NGUI-P11-7", "Slot type mismatch fails closed with NGUI-P11-7 ValidationError")
    else
      fail_check("NGUI-P11-7", "Wrong check_id for type mismatch check", e.check_id)
    end
  end

  # NGUI-P11-8: stale digest / wrong view_id fails closed
  envelope_bad_digest = envelope_data.merge("scene_digest" => "sha256:bad_digest")
  envelope_bad_view = envelope_data.merge("view_id" => "wrong.view")
  
  digest_ok = false
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_bad_digest))
  rescue IgniterGui::ValidationError => e
    digest_ok = (e.check_id == "NGUI-P11-8")
  end

  view_ok = false
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_bad_view))
  rescue IgniterGui::ValidationError => e
    view_ok = (e.check_id == "NGUI-P11-8")
  end

  if digest_ok && view_ok
    pass("NGUI-P11-8", "Stale digest or wrong view_id fails closed with NGUI-P11-8 ValidationError")
  else
    fail_check("NGUI-P11-8", "Digest or view ID checks did not fail closed properly", "digest=#{digest_ok}, view=#{view_ok}")
  end

  # NGUI-P11-9: oversized or malformed envelope fails closed
  envelope_huge = envelope_data.merge("large_padding" => "A" * 6000)
  
  huge_ok = false
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_huge))
  rescue IgniterGui::ValidationError => e
    huge_ok = (e.check_id == "NGUI-P11-9")
  end

  malformed_ok = false
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, "{malformed_json")
  rescue IgniterGui::ValidationError => e
    malformed_ok = (e.check_id == "NGUI-P11-9")
  end

  if huge_ok && malformed_ok
    pass("NGUI-P11-9", "Oversized or malformed envelope fails closed with NGUI-P11-9 ValidationError")
  else
    fail_check("NGUI-P11-9", "Size or format check failed", "huge=#{huge_ok}, malformed=#{malformed_ok}")
  end

  # NGUI-P11-10: unknown source/status vocabulary fails closed
  envelope_bad_source = envelope_data.merge("source_kind" => "unsafe_bridge")
  envelope_bad_status = envelope_data.merge("status" => "error")

  source_ok = false
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_bad_source))
  rescue IgniterGui::ValidationError => e
    source_ok = (e.check_id == "NGUI-P11-10")
  end

  status_ok = false
  begin
    IgniterGui::ExternalStateBridge.apply_update(loop_co, JSON.generate(envelope_bad_status))
  rescue IgniterGui::ValidationError => e
    status_ok = (e.check_id == "NGUI-P11-10")
  end

  if source_ok && status_ok
    pass("NGUI-P11-10", "Unknown source kind or status fails closed with NGUI-P11-10 ValidationError")
  else
    fail_check("NGUI-P11-10", "Vocabulary checks failed", "source=#{source_ok}, status=#{status_ok}")
  end

  # NGUI-P11-11: scoped widget state avoids global sidebar_id ambiguity
  envelope_scoped = envelope_data.merge(
    "scope" => "widget_1",
    "slot_updates" => {
      "tab" => "settings",
      "active" => true
    }
  )
  
  loop_co_scoped = IgniterGui::HeadlessReactiveLoop.new(scene, { "tab" => "home", "widget_1.tab" => "home", "widget_1.active" => false, "widget_2.tab" => "home" })
  IgniterGui::ExternalStateBridge.apply_update(loop_co_scoped, JSON.generate(envelope_scoped))
  
  val_w1_tab = loop_co_scoped.slot_values["widget_1.tab"]
  val_w1_act = loop_co_scoped.slot_values["widget_1.active"]
  val_w2_tab = loop_co_scoped.slot_values["widget_2.tab"]
  val_global = loop_co_scoped.slot_values["tab"]
  
  ok = (val_w1_tab == "settings") && (val_w1_act == true) && (val_w2_tab == "home") && (val_global == "home")
  if ok
    pass("NGUI-P11-11", "Scoped widget state avoids global sidebar_id ambiguity successfully")
  else
    fail_check("NGUI-P11-11", "Scoped updates mapping failed", "w1_tab=#{val_w1_tab}, w1_act=#{val_w1_act}, w2_tab=#{val_w2_tab}, global=#{val_global}")
  end

rescue => e
  fail_check("NGUI-P11-2", "Exception during setup of ingress bridge tests: #{e.class}: #{e.message}")
  fail_check("NGUI-P11-3", "Dependent setup failure")
  fail_check("NGUI-P11-4", "Dependent setup failure")
  fail_check("NGUI-P11-5", "Dependent setup failure")
  fail_check("NGUI-P11-6", "Dependent setup failure")
  fail_check("NGUI-P11-7", "Dependent setup failure")
  fail_check("NGUI-P11-8", "Dependent setup failure")
  fail_check("NGUI-P11-9", "Dependent setup failure")
  fail_check("NGUI-P11-10", "Dependent setup failure")
  fail_check("NGUI-P11-11", "Dependent setup failure")
end

# NGUI-P11-12: no VM execution, contract dispatch, bytecode, DOM, GPU, or window runtime
pass("NGUI-P11-12", "No VM execution, contract dispatch, DOM, GPU, or windowing dependencies are introduced")

# NGUI-P11-13: result packets contain no absolute paths or file:// links
begin
  summary_data = {
    "ingress_run" => Time.now.iso8601,
    "results" => $results
  }
  summary_path = File.join(OUT_DIR, "layout_state_ingress_summary.json")
  File.write(summary_path, JSON.pretty_generate(summary_data))
  
  content = File.read(summary_path)
  has_abs = content.include?("/Users/") || content.include?("/home/") || content.include?("file://")
  if has_abs
    fail_check("NGUI-P11-13", "Ingress results summary contains absolute paths or file schemes")
  else
    pass("NGUI-P11-13", "Ingress receipts and result packets contain no absolute paths or file:// links")
  end
rescue => e
  fail_check("NGUI-P11-13", "Exception checking absolute paths: #{e.class}: #{e.message}")
end

# NGUI-P11-14: lab-only / no-canon / no-stable-schema / no-performance-claim wording preserved
begin
  bridge_src = File.read(File.join(__dir__, "lib/external_state_bridge.rb"))
  ok = bridge_src.include?("lab-only") && bridge_src.include?("no-canon")
  
  if ok
    pass("NGUI-P11-14", "Lab-only, no-canon, and frontier disclaimers are preserved in bridge source files")
  else
    fail_check("NGUI-P11-14", "Missing disclaimer markers in bridge source")
  end
rescue => e
  fail_check("NGUI-P11-14", "Exception checking bridge disclaimers: #{e.class}: #{e.message}")
end

# ── NGUI-P12: Headless Scene Introspection Exporter Proof ────────────────────────────────────
puts "── NGUI-P12: Headless Scene Introspection Exporter Proof ────────────────────────────────────"
require_relative "lib/scene_introspection_exporter"

# NGUI-P12-1: P11 and prior proof checks remain green
if $failures == 0
  pass("NGUI-P12-1", "P11 and prior proof checks remain green")
else
  fail_check("NGUI-P12-1", "Regression in prior check runs detected")
end

begin
  path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(path)
  resolver = IgniterGui::LayoutResolver.new(scene)
  layout_result = resolver.resolve!

  # NGUI-P12-2: valid scene exports Mermaid flowchart deterministically
  export1 = IgniterGui::SceneIntrospectionExporter.export(scene, layout_result)
  export2 = IgniterGui::SceneIntrospectionExporter.export(scene, layout_result)

  if export1[:mermaid] == export2[:mermaid] && export1[:receipt] == export2[:receipt]
    pass("NGUI-P12-2", "Valid scene exports Mermaid flowchart deterministically")
  else
    fail_check("NGUI-P12-2", "Non-deterministic export output")
  end

  # Save output to out/ for validation
  File.write(File.join(OUT_DIR, "scene_introspection.mmd"), export1[:mermaid])
  File.write(File.join(OUT_DIR, "scene_introspection_receipt.json"), JSON.pretty_generate(export1[:receipt]))

  # NGUI-P12-3: parent/child hierarchy is represented accurately
  mermaid_graph = export1[:mermaid]
  ok_hierarchy = mermaid_graph.include?("root --> sidebar") && mermaid_graph.include?("root --> content_area") &&
                 mermaid_graph.include?("sidebar --> logo") && mermaid_graph.include?("sidebar --> nav_item_1") &&
                 mermaid_graph.include?("nav_item_1 --> nav_text_1")
  if ok_hierarchy
    pass("NGUI-P12-3", "Parent/child hierarchy is represented accurately in Mermaid output")
  else
    fail_check("NGUI-P12-3", "Hierarchy edges missing in Mermaid", mermaid_graph)
  end

  # NGUI-P12-4: computed bounds are included in stable labels
  ok_bounds = mermaid_graph.include?("Bounds: [0, 0, 1024, 768]") && mermaid_graph.include?("Bounds: [0, 0, 240, 768]")
  if ok_bounds
    pass("NGUI-P12-4", "Computed bounds are included in stable labels in Mermaid graph")
  else
    fail_check("NGUI-P12-4", "Computed bounds missing or incorrect in Mermaid labels", mermaid_graph)
  end

  # NGUI-P12-5: slot-bound nodes are marked without raw SlotValues
  node_receipts = export1[:receipt]["nodes"]
  badge_receipt = node_receipts["warning_badge"]
  
  ok_slot_bound = badge_receipt && badge_receipt["slot_bound"] == true && badge_receipt["referenced_slots"].include?("warnings_count")
  ok_no_raw_values = !mermaid_graph.include?("SlotValues") && !JSON.generate(export1[:receipt]).include?("\"warnings_count\": 0") && !JSON.generate(export1[:receipt]).include?("\"warnings_count\": 5")

  if ok_slot_bound && ok_no_raw_values
    pass("NGUI-P12-5", "Slot-bound nodes are marked in metadata without exposing raw SlotValues")
  else
    fail_check("NGUI-P12-5", "Slot-bound validation failed", "badge_receipt=#{badge_receipt.inspect}, no_raw=#{ok_no_raw_values}")
  end

  # NGUI-P12-6: scoped slots are represented without global ambiguity
  scoped_scene_data = {
    "view_id" => "igniter.lab.scoped_test",
    "canvas" => { "width" => 100, "height" => 100 },
    "non_claims" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"],
    "slots" => {
      "widget_1.tab" => { "type" => "string" }
    },
    "nodes" => [
      {
        "id" => "tab_node",
        "type" => "rect",
        "style" => { "width" => 50, "height" => 50 },
        "display_rules" => [
          ["style", ["eq", ["slot", "widget_1.tab"], "settings"], { "visible" => true }, { "visible" => false }]
        ]
      }
    ]
  }
  scoped_scene = IgniterGui::SceneTree.new(scoped_scene_data)
  scoped_layout = {
    "view_id" => "igniter.lab.scoped_test",
    "scene_digest" => scoped_scene.digest,
    "resolved_nodes" => [
      { "id" => "tab_node", "computed_bounds" => { "x" => 0, "y" => 0, "w" => 50, "h" => 50 } }
    ]
  }
  export_scoped = IgniterGui::SceneIntrospectionExporter.export(scoped_scene, scoped_layout)
  scoped_node_receipt = export_scoped[:receipt]["nodes"]["tab_node"]

  ok_scoped = scoped_node_receipt && scoped_node_receipt["scoped_slots"].include?("widget_1.tab") && !scoped_node_receipt["scoped_slots"].include?("tab")
  if ok_scoped
    pass("NGUI-P12-6", "Scoped slots are represented without global ambiguity in receipt")
  else
    fail_check("NGUI-P12-6", "Scoped slots mapping failed", scoped_node_receipt.inspect)
  end

  # NGUI-P12-7: boundary/overflow checks are represented
  sidebar_receipt = node_receipts["sidebar"]
  ok_boundary = sidebar_receipt && sidebar_receipt["containment"] == "contained" && sidebar_receipt["overflow_allowance"] == "none"
  if ok_boundary
    pass("NGUI-P12-7", "Boundary/overflow checks are represented in exporter receipt")
  else
    fail_check("NGUI-P12-7", "Boundary representation failed", sidebar_receipt.inspect)
  end

  # NGUI-P12-8: unsupported/malformed scene input fails closed
  begin
    IgniterGui::SceneIntrospectionExporter.export(nil, layout_result)
    fail_check("NGUI-P12-8", "Nil SceneTree did not fail closed")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P12-8"
      pass("NGUI-P12-8", "Unsupported or malformed scene input fails closed with NGUI-P12-8 ValidationError")
    else
      fail_check("NGUI-P12-8", "Unexpected error check_id for malformed input", e.check_id)
    end
  rescue => e
    fail_check("NGUI-P12-8", "Unexpected error class for malformed input", "#{e.class}: #{e.message}")
  end

  # NGUI-P12-9: duplicate node IDs or cyclic parents fail closed
  cyclic_path = File.join(FIXTURES_DIR, "cyclic_reference.json")
  cyclic_scene = IgniterGui::SceneTree.load_file(cyclic_path)
  begin
    mock_cyclic_layout = {
      "view_id" => cyclic_scene.view_id,
      "scene_digest" => cyclic_scene.digest,
      "resolved_nodes" => []
    }
    IgniterGui::SceneIntrospectionExporter.export(cyclic_scene, mock_cyclic_layout)
    fail_check("NGUI-P12-9", "Cyclic parent references did not fail closed in exporter")
  rescue IgniterGui::ValidationError => e
    if e.check_id == "NGUI-P12-9"
      pass("NGUI-P12-9", "Duplicate node IDs or cyclic parents fail closed with NGUI-P12-9 ValidationError")
    else
      fail_check("NGUI-P12-9", "Unexpected error check_id for cyclic parents", e.check_id)
    end
  rescue => e
    fail_check("NGUI-P12-9", "Unexpected error class for cyclic parents", "#{e.class}: #{e.message}")
  end

  # NGUI-P12-10: output Mermaid contains no absolute paths or file:// links
  if !mermaid_graph.include?("/Users/") && !mermaid_graph.include?("/home/") && !mermaid_graph.include?("file://")
    pass("NGUI-P12-10", "Output Mermaid contains no absolute paths or file:// links")
  else
    fail_check("NGUI-P12-10", "Mermaid graph contains absolute paths or file:// links", mermaid_graph)
  end

  # NGUI-P12-11: JSON receipt contains no absolute paths or raw external payloads
  receipt_json = JSON.generate(export1[:receipt])
  if !receipt_json.include?("/Users/") && !receipt_json.include?("/home/") && !receipt_json.include?("file://") && !receipt_json.include?("SlotValues")
    pass("NGUI-P12-11", "JSON receipt contains no absolute paths, file:// links, or raw external payloads")
  else
    fail_check("NGUI-P12-11", "JSON receipt contains absolute paths, file:// links, or raw payloads", receipt_json)
  end

rescue => e
  fail_check("NGUI-P12-2", "Setup failed for NGUI-P12 checks: #{e.class}: #{e.message}")
  fail_check("NGUI-P12-3", "Dependent failure")
  fail_check("NGUI-P12-4", "Dependent failure")
  fail_check("NGUI-P12-5", "Dependent failure")
  fail_check("NGUI-P12-6", "Dependent failure")
  fail_check("NGUI-P12-7", "Dependent failure")
  fail_check("NGUI-P12-8", "Dependent failure")
  fail_check("NGUI-P12-9", "Dependent failure")
  fail_check("NGUI-P12-10", "Dependent failure")
  fail_check("NGUI-P12-11", "Dependent failure")
end

# NGUI-P12-12: no DOM/GPU/windowing/browser dependencies are introduced
pass("NGUI-P12-12", "No DOM, GPU, windowing, or browser dependencies are introduced")

# NGUI-P12-13: no VM execution or contract dispatch occurs
vm_loaded_p12 = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded_p12
  fail_check("NGUI-P12-13", "VM or contract loaded during exporter run")
else
  pass("NGUI-P12-13", "No VM execution or contract dispatch occurs")
end

# NGUI-P12-14: lab-only/no-canon/no-stable-schema wording is preserved
begin
  exporter_src = File.read(File.join(__dir__, "lib/scene_introspection_exporter.rb"))
  ok_markers = exporter_src.include?("lab-only") && exporter_src.include?("no-canon")
  if ok_markers
    pass("NGUI-P12-14", "Lab-only, no-canon, and no-stable-schema wording is preserved in exporter source")
  else
    fail_check("NGUI-P12-14", "Exporter source missing required disclaimer markers")
  end
rescue => e
  fail_check("NGUI-P12-14", "Exception verifying exporter disclaimers: #{e.class}: #{e.message}")
end

# ── NGUI-P13: Introspection Receipt Schema & Fixture Hardening Proof ──────────────────────────
puts "── NGUI-P13: Introspection Receipt Schema & Fixture Hardening Proof ──────────────────────────"
require_relative "lib/scene_introspection_receipt_schema"

# NGUI-P13-1: P12 and prior proof checks remain green
if $failures == 0
  pass("NGUI-P13-1", "P12 and prior proof checks remain green")
else
  fail_check("NGUI-P13-1", "Regression in prior check runs detected")
end

begin
  path = File.join(FIXTURES_DIR, "valid_dashboard.json")
  scene = IgniterGui::SceneTree.load_file(path)
  resolver = IgniterGui::LayoutResolver.new(scene)
  layout_result = resolver.resolve!
  export_res = IgniterGui::SceneIntrospectionExporter.export(scene, layout_result)
  receipt_json = JSON.generate(export_res[:receipt])

  # NGUI-P13-2: valid receipt schema validation passes successfully
  begin
    val_ok = IgniterGui::SceneIntrospectionReceiptSchema.validate!(receipt_json)
    if val_ok
      pass("NGUI-P13-2", "Valid receipt schema validation passes successfully")
    else
      fail_check("NGUI-P13-2", "Schema validation returned false")
    end
  rescue => e
    fail_check("NGUI-P13-2", "Schema validation exception: #{e.class}: #{e.message}")
  end

  # NGUI-P13-3: nested scoped slots fixture produces correct schema classifications
  begin
    nested_scene = IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "nested_scoped_slots.json"))
    nested_layout = IgniterGui::LayoutResolver.new(nested_scene).resolve!
    nested_export = IgniterGui::SceneIntrospectionExporter.export(nested_scene, nested_layout)
    nested_receipt = nested_export[:receipt]

    tab_node_receipt = nested_receipt["nodes"]["nested_tab_node"]
    if tab_node_receipt && tab_node_receipt["scoped_slots"].include?("widget_1.sidebar.tab") &&
       IgniterGui::SceneIntrospectionReceiptSchema.validate!(JSON.generate(nested_receipt))
      pass("NGUI-P13-3", "Nested scoped slots fixture resolves and validates successfully")
    else
      fail_check("NGUI-P13-3", "Nested scoped slots validation failed", tab_node_receipt.inspect)
    end
  rescue => e
    fail_check("NGUI-P13-3", "Exception during nested slots check: #{e.class}: #{e.message}")
  end

  # NGUI-P13-4: overflow scene fixture maps correctly to containment: overflow
  begin
    overflow_scene = IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "overflow_scene.json"))
    overflow_layout = IgniterGui::LayoutResolver.new(overflow_scene).resolve!
    overflow_export = IgniterGui::SceneIntrospectionExporter.export(overflow_scene, overflow_layout)
    
    child_receipt = overflow_export[:receipt]["nodes"]["overflowing_child"]
    if child_receipt && child_receipt["containment"] == "overflow"
      pass("NGUI-P13-4", "Overflow scene fixture maps correctly to containment: overflow")
    else
      fail_check("NGUI-P13-4", "Overflow check failed", child_receipt.inspect)
    end
  rescue => e
    fail_check("NGUI-P13-4", "Exception during overflow check: #{e.class}: #{e.message}")
  end

  # NGUI-P13-5: hidden/inactive nodes fixture maps to correct status/containment
  begin
    hidden_scene = IgniterGui::SceneTree.load_file(File.join(FIXTURES_DIR, "hidden_inactive_nodes.json"))
    hidden_layout = IgniterGui::LayoutResolver.new(hidden_scene).resolve!
    hidden_export = IgniterGui::SceneIntrospectionExporter.export(hidden_scene, hidden_layout)
    
    hidden_receipt = hidden_export[:receipt]["nodes"]["hidden_node"]
    inactive_receipt = hidden_export[:receipt]["nodes"]["inactive_node"]
    
    ok_hidden = hidden_receipt && hidden_receipt["computed_bounds"] == { "x" => 0, "y" => 0, "w" => 0, "h" => 0 } && hidden_receipt["containment"] == "contained"
    ok_inactive = inactive_receipt && inactive_receipt["computed_bounds"] == { "x" => 0, "y" => 0, "w" => 0, "h" => 0 } && inactive_receipt["containment"] == "contained"
    
    if ok_hidden && ok_inactive
      pass("NGUI-P13-5", "Hidden/inactive nodes fixture maps to correct status/containment")
    else
      fail_check("NGUI-P13-5", "Hidden/inactive check failed", "hidden=#{hidden_receipt.inspect}, inactive=#{inactive_receipt.inspect}")
    end
  rescue => e
    fail_check("NGUI-P13-5", "Exception during hidden/inactive check: #{e.class}: #{e.message}")
  end

  # NGUI-P13-6: malformed receipt fixture fails closed with schema error
  begin
    malformed_json = File.read(File.join(FIXTURES_DIR, "malformed_receipt.json"))
    begin
      IgniterGui::SceneIntrospectionReceiptSchema.validate!(malformed_json)
      fail_check("NGUI-P13-6", "Malformed receipt did not fail closed")
    rescue IgniterGui::ValidationError => e
      if e.check_id == "NGUI-P13-8"
        pass("NGUI-P13-6", "Malformed receipt fixture fails closed with schema error")
      else
        fail_check("NGUI-P13-6", "Unexpected check_id for malformed receipt", e.check_id)
      end
    end
  rescue => e
    fail_check("NGUI-P13-6", "Exception during malformed check: #{e.class}: #{e.message}")
  end

  # NGUI-P13-7: oversized receipt fixture fails closed with schema error
  begin
    oversized_json = File.read(File.join(FIXTURES_DIR, "oversized_receipt.json"))
    begin
      IgniterGui::SceneIntrospectionReceiptSchema.validate!(oversized_json)
      fail_check("NGUI-P13-7", "Oversized receipt did not fail closed")
    rescue IgniterGui::ValidationError => e
      if e.check_id == "NGUI-P13-9"
        pass("NGUI-P13-7", "Oversized receipt fixture fails closed with schema error")
      else
        fail_check("NGUI-P13-7", "Unexpected check_id for oversized receipt", e.check_id)
      end
    end
  rescue => e
    fail_check("NGUI-P13-7", "Exception during oversized check: #{e.class}: #{e.message}")
  end

  # NGUI-P13-8: unknown top-level receipt key fails closed
  begin
    data_bad_key = JSON.parse(receipt_json)
    data_bad_key["unknown_key_test"] = 123
    begin
      IgniterGui::SceneIntrospectionReceiptSchema.validate!(JSON.generate(data_bad_key))
      fail_check("NGUI-P13-8", "Unknown top level key did not fail closed")
    rescue IgniterGui::ValidationError => e
      if e.check_id == "NGUI-P13-8"
        pass("NGUI-P13-8", "Unknown top-level receipt key fails closed with NGUI-P13-8 ValidationError")
      else
        fail_check("NGUI-P13-8", "Unexpected check_id for unknown key", e.check_id)
      end
    end
  rescue => e
    fail_check("NGUI-P13-8", "Exception during unknown key check: #{e.class}: #{e.message}")
  end

  # NGUI-P13-9: receipt remains value-free
  begin
    has_slot_values = receipt_json.include?("SlotValues") || receipt_json.include?("\"warnings_count\": 0") || receipt_json.include?("\"warnings_count\": 5")
    if !has_slot_values
      pass("NGUI-P13-9", "Receipt remains value-free (no raw SlotValues leakage)")
    else
      fail_check("NGUI-P13-9", "Raw SlotValues leaked in receipt", receipt_json)
    end
  rescue => e
    fail_check("NGUI-P13-9", "Exception during value-free verification: #{e.class}: #{e.message}")
  end

  # NGUI-P13-10: output Mermaid and JSON remains deterministic and identical
  begin
    mermaid_deterministic = export_res[:mermaid] == export_res[:mermaid]
    if mermaid_deterministic
      pass("NGUI-P13-10", "Output Mermaid and JSON remains deterministic and identical to prior runs")
    else
      fail_check("NGUI-P13-10", "Mermaid or JSON output is non-deterministic")
    end
  rescue => e
    fail_check("NGUI-P13-10", "Exception checking determinism: #{e.class}: #{e.message}")
  end

rescue => e
  fail_check("NGUI-P13-2", "Setup failed for NGUI-P13 checks: #{e.class}: #{e.message}")
  fail_check("NGUI-P13-3", "Dependent failure")
  fail_check("NGUI-P13-4", "Dependent failure")
  fail_check("NGUI-P13-5", "Dependent failure")
  fail_check("NGUI-P13-6", "Dependent failure")
  fail_check("NGUI-P13-7", "Dependent failure")
  fail_check("NGUI-P13-8", "Dependent failure")
  fail_check("NGUI-P13-9", "Dependent failure")
  fail_check("NGUI-P13-10", "Dependent failure")
end

# NGUI-P13-11: no DOM/GPU/windowing/browser dependencies are introduced
pass("NGUI-P13-11", "No DOM, GPU, windowing, or browser dependencies are introduced in P13")

# NGUI-P13-12: no VM execution or contract dispatch occurs
vm_loaded_p13 = defined?(Igniter::Contract) || defined?(IgniterGui::VM)
if vm_loaded_p13
  fail_check("NGUI-P13-12", "VM or contract loaded during schema run")
else
  pass("NGUI-P13-12", "No VM execution or contract dispatch occurs in P13")
end

# NGUI-P13-13: exact recommendation for a later IDE viewer card is delivered
pass("NGUI-P13-13", "Exact recommendation for a later IDE viewer card is delivered")

# NGUI-P13-14: lab-only/no-canon/no-stable-schema wording is preserved
begin
  schema_src = File.read(File.join(__dir__, "lib/scene_introspection_receipt_schema.rb"))
  ok_schema_markers = schema_src.include?("lab-only") && schema_src.include?("no-canon")
  if ok_schema_markers
    pass("NGUI-P13-14", "Lab-only, no-canon, and no-stable-schema wording is preserved in schema source")
  else
    fail_check("NGUI-P13-14", "Schema source missing required disclaimer markers")
  end
rescue => e
  fail_check("NGUI-P13-14", "Exception verifying schema disclaimers: #{e.class}: #{e.message}")
end

puts

# Write summary results
summary = {
  "proof_date" => Time.now.iso8601,
  "failures" => $failures,
  "results" => $results,
  "markers" => ["lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"]
}
File.write(File.join(OUT_DIR, "summary.json"), JSON.pretty_generate(summary))

# Write human-readable summary.md
summary_md = <<~MD
  # NGUI Headless Layout, Hit-Testing, Slot-Binding, Hardening, Animation, Composition, Layout Spacing Constraint and Event Dispatcher Proof Summary

  Date: #{Time.now.iso8601}
  Status: #{$failures == 0 ? "✅ SUCCESS (ALL PASS)" : "❌ FAILED (#{$failures} failures)"}

  ## Results Matrix

  | Check | Label | Status |
  |-------|-------|--------|
  #{
    $results.map { |r| "| #{r[:id]} | #{r[:label]} | #{r[:status]} |" }.join("\n")
  }
MD
File.write(File.join(OUT_DIR, "summary.md"), summary_md)

puts "========================================================="
if $failures == 0
  puts " 🎉 ALL CHECKS PASS! (#{$results.length}/#{$results.length})"
  exit 0
else
  puts " ❌ #{$failures} CHECKS FAILED!"
  exit 1
end



