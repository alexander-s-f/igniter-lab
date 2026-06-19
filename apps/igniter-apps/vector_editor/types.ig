module VectorTypes

type Point {
  x : Integer
  y : Integer
}

type Style {
  fill_hex : String
  stroke_hex : String
  stroke_width : Integer
}

type RectData {
  width : Integer
  height : Integer
}

type TextData {
  content : String
  font_size : Integer
}

-- Igniter doesn't have ADTs, so we use a union-like struct with a kind tag
type GraphicObject {
  id : String
  kind : String
  style : Style
  pos : Point
  path_pts : Collection[Point]?
  rect_data : RectData?
  text_data : TextData?
}

type Layer {
  id : String
  name : String
  visible : Bool
  locked : Bool
  objects : Collection[GraphicObject]
}

type Document {
  id : String
  width : Integer
  height : Integer
  layers : Collection[Layer]
}

type ToolState {
  active_tool : String
  selected_ids : Collection[String]
}
