module NeuralNetExample
import NeuralNetTypes
import NeuralNetCore

contract RunInference {
  -- We pass inputs scaled by 1000
  compute x1 = { x1: 1000, x2: 0 }    -- [1.0, 0.0]
  compute x2 = { x1: 1000, x2: 1000 } -- [1.0, 1.0]

  compute pred1 = call_contract("FeedForwardNN", x1)
  compute pred2 = call_contract("FeedForwardNN", x2)

  output pred1 : OutputVector
  output pred2 : OutputVector
}
