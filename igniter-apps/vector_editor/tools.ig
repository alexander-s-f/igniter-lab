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
  
  -- Omit optional fields to test if TypeChecker allows partial initialization for Option[T]
  compute new_obj = {
    id: "rect-new",
    kind: "rect",
    style: default_style,
    pos: click_pos,
    rect_data: r_data
  }
  
  -- Hardcoded layer "layer-1" for prototype
  compute updated_doc = call_contract("AddObjectToDoc", doc, "layer-1", new_obj)
  
  output updated_doc : Document
}

contract HandleCanvasClick {
  input doc : Document
  input state : ToolState
  input click_pos : Point
  
  -- Dispatch tool action
  compute next_doc = if state.active_tool == "draw_rect" {
    call_contract("CreateAndAppendRect", doc, click_pos)
  } else {
    doc
  }
  
  output next_doc : Document
}
