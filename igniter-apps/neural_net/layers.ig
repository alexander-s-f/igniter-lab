module NeuralNetLayers
import NeuralNetTypes
import NeuralNetActivations

-- ============================================================
-- Unrolled Neural Network Layers
-- ============================================================
-- Matrix Multiplication is unrolled:
-- h1 = Act((x1 * w11) + (x2 * w12) + b1)
-- Because our scale is 1000, multiplying two fixed-point numbers
-- yields a scale of 1,000,000. So we divide by 1000 to normalize.

contract DenseLayer2x2 {
  input x : InputVector
  input w : Weights2x2

  -- Neuron 1 Pre-activation
  compute z1_raw = (x.x1 * w.w11) + (x.x2 * w.w12)
  compute z1 = (z1_raw / 1000) + w.b1

  -- Neuron 2 Pre-activation
  compute z2_raw = (x.x1 * w.w21) + (x.x2 * w.w22)
  compute z2 = (z2_raw / 1000) + w.b2

  -- Activation
  compute h1 = call_contract("ReLU", z1)
  compute h2 = call_contract("ReLU", z2)

  compute out = { h1: h1, h2: h2 }
  output out : HiddenState
}

contract DenseLayer2x1 {
  input h : HiddenState
  input w : Weights2x1

  -- Output Neuron Pre-activation
  compute z1_raw = (h.h1 * w.w11) + (h.h2 * w.w21)
  compute z1 = (z1_raw / 1000) + w.b1

  -- Output Activation
  compute y1 = call_contract("SigmoidApprox", z1)

  compute out = { y1: y1 }
  output out : OutputVector
}
