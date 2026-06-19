module VectorTransform
import VectorTypes

contract TranslateObject {
  input obj : GraphicObject
  input dx : Integer
  input dy : Integer
  
  -- We only translate the root pos. In a real engine we'd map over path_pts,
  -- but Option unwrapping is unsupported in surface syntax currently.
  compute new_pos = {
    x: obj.pos.x + dx,
    y: obj.pos.y + dy
  }
  
  compute translated = {
    id: obj.id,
    kind: obj.kind,
    style: obj.style,
    pos: new_pos,
    path_pts: obj.path_pts,
    rect_data: obj.rect_data,
    text_data: obj.text_data
  }
  
  output translated : GraphicObject
}
