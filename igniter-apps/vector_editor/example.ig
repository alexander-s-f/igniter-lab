module VectorExample
import VectorTypes
import VectorTools

-- Program entry point - zero-input canvas click demo.
-- Builds an empty one-layer document and a draw-rect tool state, then feeds the
-- existing handler path without adding UI, storage, or event-loop authority.
entrypoint RunCanvasClickDemo

pure contract MakePoint {
  input x : Integer
  input y : Integer

  compute point = { x: x, y: y }
  output point : Point
}

pure contract MakeLayer {
  input id : String
  input name : String
  input objects : Collection[GraphicObject]

  compute layer = {
    id: id,
    name: name,
    visible: true,
    locked: false,
    objects: objects
  }
  output layer : Layer
}

pure contract MakeDocument {
  input layers : Collection[Layer]

  compute doc = {
    id: "doc-demo",
    width: 800,
    height: 600,
    layers: layers
  }
  output doc : Document
}

pure contract MakeToolState {
  input active_tool : String

  compute selected_ids : Collection[String] = []
  compute state = {
    active_tool: active_tool,
    selected_ids: selected_ids
  }
  output state : ToolState
}

contract RunCanvasClickDemo {
  compute empty_objects : Collection[GraphicObject] = []
  compute layer = call_contract("MakeLayer", "layer-1", "Main", empty_objects)
  compute doc = call_contract("MakeDocument", [layer])
  compute state = call_contract("MakeToolState", "draw_rect")
  compute click_pos = call_contract("MakePoint", 120, 80)

  compute next_doc = call_contract("HandleCanvasClick", doc, state, click_pos)
  output next_doc : Document
}
