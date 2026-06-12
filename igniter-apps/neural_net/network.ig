module NeuralNetCore
import NeuralNetTypes
import NeuralNetActivations
import NeuralNetLayers

-- ============================================================
-- The Neural Network Model
-- ============================================================

contract FeedForwardNN {
  input x : InputVector
  
  -- Hardcoded Model Weights (Scale: 1000)
  -- This represents an XOR or similar logic gate model.
  -- Layer 1: 2 inputs -> 2 hidden
  compute w1 = {
    w11: 800,  -- 0.8
    w12: 0 - 500, -- -0.5
    w21: 0 - 400, -- -0.4
    w22: 900,  -- 0.9
    b1:  100,  -- 0.1
    b2:  0 - 200  -- -0.2
  }

  -- Layer 2: 2 hidden -> 1 output
  compute w2 = {
    w11: 1200, -- 1.2
    w21: 0 - 800, -- -0.8
    b1:  0 - 100  -- -0.1
  }

  -- Forward Pass
  compute h = call_contract("DenseLayer2x2", x, w1)
  compute y = call_contract("DenseLayer2x1", h, w2)

  output y : OutputVector
}
