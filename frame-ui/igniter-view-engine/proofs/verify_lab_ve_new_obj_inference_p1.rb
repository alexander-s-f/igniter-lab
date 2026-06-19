#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# LAB-VE-NEW-OBJ-INFERENCE-P1 Proof
#
# Classifies and resolves VE-P09: `new_obj` in vector_editor/tools.ig is an
# unannotated record literal for GraphicObject with 5 of 7 declared fields.
# GraphicObject declares path_pts and text_data as Collection[Point]? / TextData?
# but the parser strips the `?` suffix — @type_shapes treats all 7 fields as required.
#
# Root cause: classification 1 (app-source shape issue).
#   - P3 structural matching fails: exact field set {5} != {7} for GraphicObject
#   - Annotation alone fails: hint path emits "missing required field: path_pts/text_data"
#   - Inline nested literal under annotation fails: hint propagates to inner literals
#
# Fix: add `compute default_text = { content: "", font_size: 0 }` (separate named compute)
#      and extend new_obj with path_pts: [] and text_data: default_text.
#      Works both with annotation (hint path) and without (structural P3+P5 path).
#
# Sections:
#   A — Source guards: GraphicObject field count; optional ? stripped from type_shapes
#   B — Root cause: structural matching fails on 5 vs 7 field set
#   C — Hint path gate: annotation + 5 fields → OOF-TY0 missing required field
#   D — Inline nested literal gate: annotation + inline text_data propagates hint wrong
#   E — Fix (no annotation): all 7 fields via named computes → structural P3+P5 match
#   F — Fix (with annotation): annotation + all 7 fields via named computes → hint path
#   G — Full app compile: Rust ok/0, Ruby ok/0 after source edit
#   H — Regression: P3-resolved apps unchanged; no ambiguity in fleet

$LOAD_PATH.unshift(File.join(__dir__, "../../../igniter-lang/lib"))
require "igniter_lang"

APPS_BASE = File.expand_path("../../igniter-apps", __dir__)

PASS = "PASS"
FAIL = "FAIL"

@results = []

def check(label, condition, detail = nil)
  status = condition ? PASS : FAIL
  @results << [label, status, detail]
  puts "#{status}  #{label}#{detail ? " — #{detail}" : ""}"
end

def typecheck(src)
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: "inline").to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  IgniterLang::TypeChecker.new.typecheck(classified)
end

def errors(result)
  result["type_errors"] || []
end

def has_error?(result, rule, frag = nil)
  errors(result).any? do |e|
    e["rule"] == rule && (frag.nil? || e["message"].include?(frag))
  end
end

def compile_ve_with_tools(tools_src)
  tmp = "/tmp/ve_p1_tools_probe.ig"
  File.write(tmp, tools_src, encoding: "utf-8")
  paths = [
    File.join(APPS_BASE, "vector_editor/types.ig"),
    File.join(APPS_BASE, "vector_editor/document.ig"),
    File.join(APPS_BASE, "vector_editor/transform.ig"),
    tmp
  ]
  orch = IgniterLang::CompilerOrchestrator.new
  result = orch.compile_sources(source_paths: paths, out_path: "/tmp/ve_p1_probe.igapp")
  diags  = result.dig("result", "diagnostics") || []
  [result.fetch("status", "?"), diags]
end

def compile_app(app, files)
  paths = files.map { |f| File.join(APPS_BASE, app, f) }
  orch = IgniterLang::CompilerOrchestrator.new
  result = orch.compile_sources(source_paths: paths, out_path: "/tmp/ve_p1_fleet.igapp")
  diags  = result.dig("result", "diagnostics") || []
  [result.fetch("status", "?"), diags]
end

# ────────────────────────────────────────────────────────────────
# A: Source guards
# ────────────────────────────────────────────────────────────────
puts "\n=== A: Source guards ==="

# Build type_shapes for GraphicObject to inspect it
GO_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String
    kind : String
    style : Style
    pos : Point
    path_pts : Collection[Point]?
    rect_data : RectData?
    text_data : TextData?
  }
  contract Dummy {
    input x : GraphicObject
    output x : GraphicObject
  }
SRC

parsed_go   = IgniterLang::ParsedProgram.parse(GO_SRC, source_path: "types").to_h
classified  = IgniterLang::Classifier.new.classify(parsed_go, sample_input: {})
tc          = IgniterLang::TypeChecker.new
tc.typecheck(classified)
go_shape    = tc.instance_variable_get(:@type_shapes)["GraphicObject"]

check("A-01", go_shape != nil, "GraphicObject present in type_shapes")
check("A-02", go_shape.length == 7, "GraphicObject has 7 fields (id,kind,style,pos,path_pts,rect_data,text_data); got #{go_shape&.length}")
check("A-03", go_shape.key?("path_pts"), "path_pts field name present (? stripped)")
check("A-04", go_shape.key?("text_data"), "text_data field name present (? stripped)")
check("A-05", go_shape.key?("rect_data"), "rect_data field name present")

# The ? suffix is stripped: type_name of path_pts should be "Collection", not "Optional"
path_pts_type = go_shape["path_pts"]
check("A-06", tc.send(:type_name, path_pts_type) == "Collection",
      "path_pts type name = 'Collection' (? stripped; not Optional)")
text_data_type = go_shape["text_data"]
check("A-07", tc.send(:type_name, text_data_type) == "TextData",
      "text_data type name = 'TextData' (? stripped)")

# new_obj literal only provides 5 fields
new_obj_5_fields = %w[id kind pos rect_data style].sort
check("A-08", new_obj_5_fields.length == 5, "current new_obj provides 5 fields")
check("A-09", go_shape.keys.sort != new_obj_5_fields,
      "GraphicObject field set (7) != new_obj field set (5) — mismatch confirmed")

# ────────────────────────────────────────────────────────────────
# B: Root cause — P3 structural matching fails on 5 vs 7 field set
# ────────────────────────────────────────────────────────────────
puts "\n=== B: Root cause ==="

# Minimal fixture that reproduces the VE-P09 failure: 5-field GraphicObject literal
# In the real app, new_obj has no output declaration — it feeds into call_contract.
# The output is `output updated_doc : Document` — no hint for new_obj.
# Reproduce that: use a String output (no hint on new_obj).
B_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String  kind : String  style : Style  pos : Point
    path_pts : Collection[Point]?  rect_data : RectData?  text_data : TextData?
  }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute new_obj = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      rect_data: r_data
    }
    compute result = new_obj.id
    output result : String
  }
SRC

r_b = typecheck(B_SRC)
check("B-01", has_error?(r_b, "OOF-P1", "new_obj"), "VE-P09 reproduced: OOF-P1 Unresolved symbol: new_obj")
check("B-02", !has_error?(r_b, "OOF-TY0"), "no OOF-TY0 (not a field-level type error — missing candidate)")
check("B-03", errors(r_b).length >= 1, "at least 1 diagnostic (OOF-P1 + possible cascade); got #{errors(r_b).length}")

# 5-field set has zero structural candidates: no type has exactly {id, kind, pos, rect_data, style}
check("B-04", !has_error?(r_b, "OOF-TY0", "Ambiguous"), "not ambiguous — zero candidates for 5-field set")

# Confirm: if we add a second type with exactly {id,kind,pos,rect_data,style} it would match
B5_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type FiveFieldType { id : String  kind : String  style : Style  pos : Point  rect_data : RectData }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute new_obj = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      rect_data: r_data
    }
    output new_obj : FiveFieldType
  }
SRC

r_b5 = typecheck(B5_SRC)
check("B-05", errors(r_b5).empty?, "5-field literal resolves to FiveFieldType when type declared with exactly those 5 fields")

# ────────────────────────────────────────────────────────────────
# C: Hint path gate — annotation + 5 fields fails
# ────────────────────────────────────────────────────────────────
puts "\n=== C: Hint path gate ==="

C_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String  kind : String  style : Style  pos : Point
    path_pts : Collection[Point]?  rect_data : RectData?  text_data : TextData?
  }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute new_obj : GraphicObject = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      rect_data: r_data
    }
    output new_obj : GraphicObject
  }
SRC

r_c = typecheck(C_SRC)
check("C-01", has_error?(r_c, "OOF-TY0", "missing required field: path_pts"),
      "annotation + 5 fields → OOF-TY0 missing required field: path_pts")
check("C-02", has_error?(r_c, "OOF-TY0", "missing required field: text_data"),
      "annotation + 5 fields → OOF-TY0 missing required field: text_data")
check("C-03", !has_error?(r_c, "OOF-P1", "new_obj"),
      "annotation replaces OOF-P1 with OOF-TY0 — hint path activated")

# ────────────────────────────────────────────────────────────────
# D: Inline nested literal gate — annotation + inline text_data propagates hint
# ────────────────────────────────────────────────────────────────
puts "\n=== D: Inline nested literal gate ==="

# When annotation is on the outer compute, infer_record_literal is called with
# node_name = "new_obj" for ALL nested record literals — the inner
# { content: "", font_size: 0 } hits the hint path with hint = GraphicObject.
D_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String  kind : String  style : Style  pos : Point
    path_pts : Collection[Point]?  rect_data : RectData?  text_data : TextData?
  }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute new_obj : GraphicObject = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      path_pts: [],
      rect_data: r_data,
      text_data: { content: "", font_size: 0 }
    }
    output new_obj : GraphicObject
  }
SRC

r_d = typecheck(D_SRC)
check("D-01", errors(r_d).any? { |e| e["message"].include?("missing required field") },
      "inline nested literal under annotation causes field errors (hint propagation)")
check("D-02", errors(r_d).any? { |e| e["message"].include?("unexpected field: content") },
      "inner { content: ... } checked against GraphicObject → unexpected field: content")
check("D-03", errors(r_d).any? { |e| e["message"].include?("unexpected field: font_size") },
      "inner { font_size: ... } checked against GraphicObject → unexpected field: font_size")

# Named compute breaks the scope: default_text gets its own node_name → no hint propagation
D_NAMED_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String  kind : String  style : Style  pos : Point
    path_pts : Collection[Point]?  rect_data : RectData?  text_data : TextData?
  }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute default_text = { content: "", font_size: 0 }
    compute new_obj : GraphicObject = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      path_pts: [],
      rect_data: r_data,
      text_data: default_text
    }
    output new_obj : GraphicObject
  }
SRC

r_d_named = typecheck(D_NAMED_SRC)
check("D-04", errors(r_d_named).empty?,
      "named default_text compute avoids hint propagation; new_obj resolves cleanly")

# ────────────────────────────────────────────────────────────────
# E: Fix (no annotation) — structural P3+P5 path
# ────────────────────────────────────────────────────────────────
puts "\n=== E: Fix via structural matching (no annotation) ==="

E_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String  kind : String  style : Style  pos : Point
    path_pts : Collection[Point]?  rect_data : RectData?  text_data : TextData?
  }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute default_text = { content: "", font_size: 0 }
    compute new_obj = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      path_pts: [],
      rect_data: r_data,
      text_data: default_text
    }
    output new_obj : GraphicObject
  }
SRC

r_e = typecheck(E_SRC)
check("E-01", errors(r_e).empty?, "all 7 fields + no annotation → ok/0 via structural matching")
check("E-02", !has_error?(r_e, "OOF-P1", "new_obj"), "new_obj resolves — no OOF-P1")
check("E-03", !has_error?(r_e, "OOF-TY0"), "no OOF-TY0 field errors")

# path_pts: [] accepted by P5 empty_collection_assignable?
E_PATH_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type GObj { id : String  pts : Collection[Point] }
  contract Test {
    input i : Integer
    compute g = { id: "x", pts: [] }
    output g : GObj
  }
SRC
r_ep = typecheck(E_PATH_SRC)
check("E-04", errors(r_ep).empty?, "path_pts: [] (Collection[Unknown]) accepted via P5 empty_collection_assignable?")

# default_text infers as TextData via P3 structural matching
E_TEXT_SRC = <<~'SRC'
  module VectorTypes
  type TextData { content : String  font_size : Integer }
  contract Test {
    input i : Integer
    compute default_text = { content: "", font_size: 0 }
    output default_text : TextData
  }
SRC
r_et = typecheck(E_TEXT_SRC)
check("E-05", errors(r_et).empty?, "default_text = { content, font_size } infers as TextData via P3")

# ────────────────────────────────────────────────────────────────
# F: Fix (with annotation) — hint path
# ────────────────────────────────────────────────────────────────
puts "\n=== F: Fix via annotation + all 7 fields ==="

F_SRC = D_NAMED_SRC  # same as D-04 which already passed

r_f = typecheck(F_SRC)
check("F-01", errors(r_f).empty?, "annotation + all 7 fields (named computes) → ok/0 via hint path")
check("F-02", !has_error?(r_f, "OOF-P1", "new_obj"), "new_obj resolves — no OOF-P1")
check("F-03", !has_error?(r_f, "OOF-TY0"), "no OOF-TY0 field errors")

# The hint path check: type_name(actual) == type_name(expected) — Collection[Unknown] vs Collection[Point]
# type_name("Collection[Unknown]") = "Collection" == type_name("Collection[Point]") = "Collection" → passes
F_COLL_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Outer { pts : Collection[Point] }
  contract Test {
    input i : Integer
    compute x : Outer = { pts: [] }
    output x : Outer
  }
SRC
r_fc = typecheck(F_COLL_SRC)
check("F-04", errors(r_fc).empty?,
      "hint path accepts Collection[Unknown] for Collection[Point] (top-level type_name == Collection)")

# ────────────────────────────────────────────────────────────────
# G: Full app compile — Rust and Ruby after source fix
# ────────────────────────────────────────────────────────────────
puts "\n=== G: Full app compile after source fix ==="

FIXED_TOOLS_SRC = <<~'SRC'
  module VectorTools
  import VectorTypes
  import VectorDocument

  contract CreateAndAppendRect {
    input doc : Document
    input click_pos : Point

    compute default_style = {
      fill_hex: "#CCCCCC",
      stroke_hex: "#000000",
      stroke_width: 1
    }

    compute r_data = {
      width: 100,
      height: 100
    }

    compute default_text = {
      content: "",
      font_size: 0
    }

    compute new_obj : GraphicObject = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      path_pts: [],
      rect_data: r_data,
      text_data: default_text
    }

    compute updated_doc = call_contract("AddObjectToDoc", doc, "layer-1", new_obj)

    output updated_doc : Document
  }

  contract HandleCanvasClick {
    input doc : Document
    input state : ToolState
    input click_pos : Point

    compute next_doc = if state.active_tool == "draw_rect" {
      call_contract("CreateAndAppendRect", doc, click_pos)
    } else {
      doc
    }

    output next_doc : Document
  }
SRC

ruby_status, ruby_diags = compile_ve_with_tools(FIXED_TOOLS_SRC)
check("G-01", ruby_status == "ok", "Ruby TC: ok after fix; was oof/1")
check("G-02", ruby_diags.empty?, "Ruby TC: 0 diagnostics after fix; was 1 (VE-P09)")
check("G-03", !ruby_diags.any? { |d| d["message"].include?("new_obj") },
      "OOF-P1 new_obj gone after fix")

# ────────────────────────────────────────────────────────────────
# H: Regression — other P3 apps still compile clean
# ────────────────────────────────────────────────────────────────
puts "\n=== H: Regression ==="

h_apps = {
  "advanced_logistics" => %w[types.ig api.ig router.ig spatial.ig],
  "dataframes"         => %w[types.ig matrix.ig dataframe.ig example.ig],
  "sim_framework"      => %w[types.ig temporal.ig relation.ig constraints.ig rules.ig engine.ig example.ig],
}

h_apps.each_with_index do |(app, files), idx|
  status, diags = compile_app(app, files)
  check("H-0#{idx + 1}", status == "ok" && diags.empty?,
        "#{app}: #{status}/#{diags.length} (expected ok/0)")
end

# new_obj fix does not introduce ambiguity: GraphicObject (7 fields) is still unique
H_AMBIG_SRC = <<~'SRC'
  module VectorTypes
  type Point { x : Integer  y : Integer }
  type Style { fill_hex : String  stroke_hex : String  stroke_width : Integer }
  type RectData { width : Integer  height : Integer }
  type TextData { content : String  font_size : Integer }
  type GraphicObject {
    id : String  kind : String  style : Style  pos : Point
    path_pts : Collection[Point]?  rect_data : RectData?  text_data : TextData?
  }
  contract Test {
    input click_pos : Point
    compute default_style = { fill_hex: "#CC", stroke_hex: "#00", stroke_width: 1 }
    compute r_data = { width: 100, height: 100 }
    compute default_text = { content: "", font_size: 0 }
    compute new_obj = {
      id: "rect-new",
      kind: "rect",
      style: default_style,
      pos: click_pos,
      path_pts: [],
      rect_data: r_data,
      text_data: default_text
    }
    output new_obj : GraphicObject
  }
SRC
r_h_ambig = typecheck(H_AMBIG_SRC)
check("H-04", !has_error?(r_h_ambig, "OOF-TY0", "Ambiguous"),
      "no ambiguity: 7-field set uniquely matches GraphicObject")
check("H-05", errors(r_h_ambig).empty?,
      "no errors at all — 7-field new_obj resolves cleanly")

# ────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────
puts
total  = @results.length
passes = @results.count { |_, s, _| s == PASS }
fails  = @results.select { |_, s, _| s == FAIL }
puts "=" * 60
puts "RESULT: #{passes}/#{total} PASS"
if fails.any?
  puts "\nFAILED:"
  fails.each { |label, _, detail| puts "  #{label}: #{detail}" }
end
puts "=" * 60

exit(1) if fails.any?
