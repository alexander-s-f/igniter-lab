module VectorDocument
import VectorTypes
import stdlib.collection.{ append, map }

contract AppendObjectToLayer {
  input layer : Layer
  input obj : GraphicObject
  
  compute new_objects = append(layer.objects, obj)
  
  compute updated_layer = {
    id: layer.id,
    name: layer.name,
    visible: layer.visible,
    locked: layer.locked,
    objects: new_objects
  }
  
  output updated_layer : Layer
}

contract AddObjectToDoc {
  input doc : Document
  input target_layer_id : String
  input new_obj : GraphicObject
  
  -- We map over layers. If the ID matches, we call the helper contract 
  -- to avoid the inline RecordLit parser bug inside lambdas/blocks.
  compute updated_layers = map(doc.layers, layer ->
    if layer.id == target_layer_id {
      call_contract("AppendObjectToLayer", layer, new_obj)
    } else {
      layer
    }
  )
  
  compute updated_doc = {
    id: doc.id,
    width: doc.width,
    height: doc.height,
    layers: updated_layers
  }
  
  output updated_doc : Document
}
