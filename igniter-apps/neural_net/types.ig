module NeuralNetTypes

-- ============================================================
-- Neural Net Core Types (Fixed Point Arithmetic)
-- ============================================================
-- Since Igniter has no Float support, all values (weights, biases,
-- inputs) are scaled by a factor of 1000.
-- E.g., 0.5 is represented as 500.

type InputVector {
  x1 : Integer
  x2 : Integer
}

type OutputVector {
  y1 : Integer
}

-- Since we lack `reduce()` and dynamic Matrix dimensions,
-- we MUST statically unroll Neural Network structures.
-- We represent a 2x2 Dense Layer's weights as a struct:
type Weights2x2 {
  w11 : Integer
  w12 : Integer
  w21 : Integer
  w22 : Integer
  b1  : Integer
  b2  : Integer
}

type Weights2x1 {
  w11 : Integer
  w21 : Integer
  b1  : Integer
}

type HiddenState {
  h1 : Integer
  h2 : Integer
}
